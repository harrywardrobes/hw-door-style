module HarryWardrobes
  module DoorStyle
    # Rebuilds door / drawer-front definitions at real size with the chosen style.
    module Converter
      ROLES = %w[style hinge tip_on].freeze

      # pairs:      [[instance, kind], ...]
      # style:      style id, or nil to keep each item's current style (Rebuild)
      # hinge_type: optional new job hinge type (set inside the same undo step)
      # Returns { items: n, definitions: n, notes: [..] }
      def self.apply(pairs, style, op_name, hinge_type: nil)
        model = Sketchup.active_model
        return { items: 0, definitions: 0, notes: [] } if pairs.empty?

        model.start_operation(op_name, true)
        begin
          Settings.set_job_hinge_type(hinge_type, model) if hinge_type
          job_hinge = Settings.job_hinge_type(model)

          # Measure everything BEFORE changing any definition.
          jobs = pairs.map do |inst, kind|
            s = style || inst.definition.get_attribute(DICT, 'requested_style', 'flat')
            s = 'flat' if kind == :int_drawer
            { inst: inst, kind: kind, style: s, defn: inst.definition,
              size: Finder.real_size(inst), min: Finder.scaled_min(inst) }
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

            info = rebuild_definition(model, defn, first, job_hinge, style_cache)
            notes << "#{Finder.label(first[:inst])} #{Finder.mm_s(first[:size][0])}x#{Finder.mm_s(first[:size][2])}: #{info[:note]}" unless info[:note].to_s.empty?

            js.each do |j|
              j[:inst].definition = defn unless j[:inst].definition == defn
              reset_scale(j[:inst])
            end
          end

          model.commit_operation
          { items: jobs.size, definitions: groups.size, notes: notes.uniq }
        rescue StandardError => e
          model.abort_operation
          raise e
        end
      end

      def self.reset_scale(inst)
        _scale, axes, origin = Finder.decompose(inst.transformation)
        x, y, z = axes.map(&:normalize)
        inst.transformation = Geom::Transformation.axes(origin, x, y, z)
      end

      def self.style_tag(model, ents)
        old = ents.find { |e| e.is_a?(Sketchup::ComponentInstance) && e.get_attribute(DICT, 'role') == 'style' }
        return old.layer if old
        face = ents.grep(Sketchup::Face).first
        face ? face.layer : model.layers[0]
      end

      def self.rebuild_definition(model, defn, job, hinge_type, cache)
        ents = defn.entities
        w, t, h = job[:size]
        tag = style_tag(model, ents)

        doomed = ents.select do |e|
          e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) ||
            (e.is_a?(Sketchup::ComponentInstance) && ROLES.include?(e.get_attribute(DICT, 'role')))
        end
        ents.erase_entities(doomed) unless doomed.empty?

        sdef, info = style_definition(model, job[:style], job[:kind], w, t, h, cache)
        si = ents.add_instance(sdef, Geom::Transformation.new(job[:min]))
        si.layer = tag
        si.set_attribute(DICT, 'role', 'style')

        hw = Hardware.add(defn, job[:min], w, t, h, job[:kind], hinge_type)

        {
          'requested_style' => job[:style], 'style' => info[:style], 'kind' => job[:kind].to_s,
          'midrail' => info[:midrail], 'note' => info[:note],
          'width_mm' => (w * 25.4).round(1), 'height_mm' => (h * 25.4).round(1),
          'hinge_type' => (job[:kind] == :door ? hinge_type : ''),
          'hinges' => hw[:hinges], 'tip_on' => hw[:tip_on], 'plugin_version' => VERSION
        }.each { |k, v| defn.set_attribute(DICT, k, v) }

        info
      end

      # One style definition per (style, kind, size), shared between doors.
      def self.style_definition(model, style, kind, w, t, h, cache)
        key = [style, kind, [w, t, h].map { |v| (v * 25.4 * 10).round }, Settings.geometry_signature].flatten.join('|')
        return cache[key] if cache[key]

        existing = model.definitions.find { |d| d.get_attribute(DICT, 'style_key') == key }
        if existing
          info = { style: existing.get_attribute(DICT, 'style'),
                   midrail: existing.get_attribute(DICT, 'midrail'),
                   note: existing.get_attribute(DICT, 'note').to_s }
          return cache[key] = [existing, info]
        end

        d = model.definitions.add("STYLE_#{style.upcase}")
        info = Styles.build(style, d.entities, w, t, h, kind)
        d.set_attribute(DICT, 'role', 'style')
        d.set_attribute(DICT, 'style_key', key)
        d.set_attribute(DICT, 'style', info[:style])
        d.set_attribute(DICT, 'midrail', info[:midrail])
        d.set_attribute(DICT, 'note', info[:note])
        d.description = "#{Styles.label(info[:style])} #{Finder.mm_s(w)} x #{Finder.mm_s(h)} mm"
        cache[key] = [d, info]
      end
    end
  end
end
