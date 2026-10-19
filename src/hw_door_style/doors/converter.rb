module HarryWardrobes
  module DoorStyle
    # Rebuilds door / drawer-front wrappers to the model contract:
    #
    #   Wrapper (WRD_DOOR, LIN_DOOR, ...)   DC, scale 1, NO LenX/LenY/LenZ formulas.
    #     Hidden DOOR_W / DOOR_T / DOOR_H carry what the Len formulas used to set.
    #   Slab  "DOOR" (drawer fronts: "FRONT")
    #     DC child at 0,0,0, LenX/Y/Z = parent!DOOR_W / DOOR_T / DOOR_H.
    #     DOOR_STYLE = FLAT | SHAKER. Geometry built at true size (scale 1).
    #   Hinges / TIP-ON   true size, at Y = DOOR_T, DC position formulas.
    module Converter
      ROLES = %w[style hinge tip_on].freeze
      SLAB_NAMES = { door: 'DOOR', ext_drawer: 'FRONT', int_drawer: 'FRONT' }.freeze
      WRAP_ATTRS = { 'DOOR_W' => 'x', 'DOOR_T' => 'y', 'DOOR_H' => 'z' }.freeze

      def self.slab_name(kind)
        SLAB_NAMES[kind] || 'DOOR'
      end

      # pairs:      [[instance, kind], ...]
      # style:      style id, or nil to keep each item's current style (Rebuild)
      # hinge_type: optional new job hinge type (set inside the same undo step)
      # Returns { items: n, definitions: n, notes: [..] }
      def self.apply(pairs, style, op_name, hinge_type: nil)
        model = Sketchup.active_model
        return { items: 0, definitions: 0, notes: [] } if pairs.empty?

        Ops.run(model, op_name) { rebuild(model, pairs, style, hinge_type: hinge_type) }
      end

      # Current style of an item (for Rebuild / Repair).
      def self.current_style(inst)
        s = inst.definition.get_attribute(DICT, 'requested_style')
        return s if s
        slab = slab_of(inst)
        return 'shaker' if slab && (DC.read(slab, 'door_style').to_s.upcase == 'SHAKER' || slab.definition.name =~ /\ASTYLE_SHAKER/i)
        'flat'
      end

      def self.slab_of(inst)
        inst.definition.entities.find do |e|
          e.is_a?(Sketchup::ComponentInstance) &&
            (e.get_attribute(DICT, 'role') == 'style' || e.definition.name =~ /\ASTYLE_/i)
        end
      end

      # Does all the work; call inside an operation.
      def self.rebuild(model, pairs, style, hinge_type: nil)
        Settings.set_job_hinge_type(hinge_type, model) if hinge_type
        job_hinge = Settings.job_hinge_type(model)

        # Measure everything BEFORE changing any definition.
        jobs = pairs.map do |inst, kind|
          s = style || current_style(inst)
          s = 'flat' if kind == :int_drawer
          { inst: inst, kind: kind, style: s, defn: inst.definition, size: Finder.real_size(inst),
            formulas: wrapper_formulas(inst) }
        end

        groups = jobs.group_by do |j|
          [j[:defn].entityID, j[:style], j[:kind], j[:size].map { |v| (v * 25.4 * 2).round }]
        end

        style_cache = {}
        notes = []
        groups.each_value do |js|
          first = js.first
          ids = js.map { |j| j[:inst].entityID }
          defn = first[:defn]
          unless (defn.instances.map(&:entityID) - ids).empty?
            first[:inst].make_unique
            defn = first[:inst].definition
          end
          js.each { |j| j[:inst].definition = defn unless j[:inst].definition == defn }

          # Wrapper contract on the definition and every instance.
          js.each { |j| migrate_wrapper(j[:inst], j[:size], j[:formulas]) }
          js.each { |j| reset_scale(j[:inst]) }

          info = rebuild_definition(model, defn, first, js.map { |j| j[:inst] }, job_hinge, style_cache)
          notes << "#{Finder.label(first[:inst])} #{Finder.mm_s(first[:size][0])}x#{Finder.mm_s(first[:size][2])}: #{info[:note]}" unless info[:note].to_s.empty?
        end

        Tagger.tag_all(model)
        Colours.reapply(model)
        { items: jobs.size, definitions: groups.size, notes: notes.uniq }
      end

      # Old Len formulas (instance first, then definition, then _inst__ template),
      # or an existing DOOR_W/T/H formula if the wrapper was already migrated.
      def self.wrapper_formulas(inst)
        WRAP_ATTRS.to_h do |name, axis|
          f = DC.read(inst, "_#{name.downcase}_formula")
          f = DC.read(inst, "_len#{axis}_formula") if f.to_s.strip.empty?
          f = DC.get(inst.definition, "_inst__len#{axis}_formula") if f.to_s.strip.empty?
          [name, f.to_s.strip.empty? ? nil : f.to_s.strip]
        end
      end

      def self.migrate_wrapper(inst, size, formulas)
        objs = [inst, inst.definition]
        DC.child(objs, Finder.label(inst)) if DC.read(inst, '_name').to_s.empty?
        WRAP_ATTRS.keys.each_with_index do |name, i|
          DC.length_attr(objs, name, formulas[name], size[i])
        end
        objs.each { |o| DC.remove_len!(o) }
      end

      def self.reset_scale(inst)
        _scale, axes, origin = Finder.decompose(inst.transformation)
        x, y, z = axes.map(&:normalize)
        inst.transformation = Geom::Transformation.axes(origin, x, y, z)
      end

      def self.rebuild_definition(model, defn, job, instances, hinge_type, cache)
        ents = defn.entities
        w, t, h = job[:size]
        tag = Tagger.tag_for(model, job[:kind])

        doomed = ents.select do |e|
          e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) ||
            (e.is_a?(Sketchup::ComponentInstance) &&
              (ROLES.include?(e.get_attribute(DICT, 'role')) || e.definition.name =~ /\ASTYLE_/i))
        end
        ents.erase_entities(doomed) unless doomed.empty?

        sdef, info = slab_definition(model, job[:style], job[:kind], w, t, h, cache)
        si = ents.add_instance(sdef, Geom::Transformation.new)
        si.layer = tag
        si.set_attribute(DICT, 'role', 'style')
        slab_attrs([si], job[:kind], info[:style], w, t, h)

        hw = Hardware.add(defn, [defn] + instances, w, t, h, job[:kind], hinge_type)

        {
          'requested_style' => job[:style], 'style' => info[:style], 'kind' => job[:kind].to_s,
          'midrail' => info[:midrail], 'note' => info[:note],
          'width_mm' => (w * 25.4).round(1), 'height_mm' => (h * 25.4).round(1),
          'hinge_type' => (job[:kind] == :door ? hinge_type : ''),
          'hinges' => hw[:hinges], 'tip_on' => hw[:tip_on], 'plugin_version' => VERSION
        }.each { |k, v| defn.set_attribute(DICT, k, v) }

        info
      end

      # DC attributes on a slab instance or definition.
      def self.slab_attrs(objs, kind, style, w, t, h)
        DC.child(objs, slab_name(kind))
        DC.formula(objs, 'x', '0', 0.0)
        DC.formula(objs, 'y', '0', 0.0)
        DC.formula(objs, 'z', '0', 0.0)
        DC.formula(objs, 'lenx', 'parent!DOOR_W', w)
        DC.formula(objs, 'leny', 'parent!DOOR_T', t)
        DC.formula(objs, 'lenz', 'parent!DOOR_H', h)
        DC.string_attr(objs, 'DOOR_STYLE', style.to_s.upcase)
      end

      # One slab definition per (style, kind, size), shared between wrappers.
      def self.slab_definition(model, style, kind, w, t, h, cache)
        key = [style, kind, [w, t, h].map { |v| (v * 25.4 * 10).round }, Settings.geometry_signature].flatten.join('|')
        return cache[key] if cache[key]

        existing = model.definitions.find do |d|
          d.get_attribute(DICT, 'style_key') == key && d.name !~ /\ASTYLE_/i
        end
        if existing
          info = { style: existing.get_attribute(DICT, 'style'),
                   midrail: existing.get_attribute(DICT, 'midrail'),
                   note: existing.get_attribute(DICT, 'note').to_s }
          return cache[key] = [existing, info]
        end

        d = model.definitions.add(slab_name(kind))
        info = Styles.build(style, d.entities, w, t, h, kind)
        d.set_attribute(DICT, 'role', 'style')
        d.set_attribute(DICT, 'style_key', key)
        d.set_attribute(DICT, 'style', info[:style])
        d.set_attribute(DICT, 'midrail', info[:midrail])
        d.set_attribute(DICT, 'note', info[:note])
        d.description = "#{Styles.label(info[:style])} #{Finder.mm_s(w)} x #{Finder.mm_s(h)} mm"
        slab_attrs([d], kind, info[:style], w, t, h)
        Tagger.tag_geometry(d.entities, Tagger.tag_for(model, kind))
        OpenCutList.mark_new_part(d) # bought-in: off the cutting diagrams
        cache[key] = [d, info]
      end
    end
  end
end
