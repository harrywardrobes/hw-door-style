module HarryWardrobes
  module DoorStyle
    # Finds doors and drawer fronts in the model and measures them.
    module Finder
      KINDS = {
        door:       'Door',
        ext_drawer: 'External drawer',
        int_drawer: 'Internal drawer'
      }.freeze

      def self.instance?(e)
        e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      end

      def self.dc_name(inst)
        n = DC.read(inst, '_name')
        n.to_s.strip.upcase
      end

      def self.names_for(inst)
        base = DC.base_name(inst.definition).upcase
        [dc_name(inst), base].reject(&:empty?).uniq
      end

      # Front type kept on the component itself ("front_role" on the definition), so it goes
      # with every copy and export whatever the component is called: door, ext_drawer,
      # int_drawer, fixed (a fixed panel - styled like a door, no hinges or handles) or none.
      # Components without one are found by name (Settings > Doors > Component names).
      ROLE = 'front_role'.freeze
      ROLES = { 'door' => :door, 'ext_drawer' => :ext_drawer, 'int_drawer' => :int_drawer, 'fixed' => :door }.freeze
      ROLE_LABELS = [['door', 'Door'], ['ext_drawer', 'Drawer front'], ['int_drawer', 'Internal drawer front'],
                     ['fixed', 'Fixed panel (no hinges / handles)'], ['none', 'Not a front']].freeze

      def self.role(inst)
        d = inst.respond_to?(:definition) ? inst.definition : inst
        r = d.get_attribute(DICT, ROLE).to_s
        r.empty? ? nil : r
      end

      # Sets (or with nil clears) the front type on the components' definitions (in an operation).
      def self.set_role(insts, role)
        insts.map { |i| i.respond_to?(:definition) ? i.definition : i }.uniq.each do |d|
          role ? d.set_attribute(DICT, ROLE, role.to_s) : d.delete_attribute(DICT, ROLE)
        end
      end

      # :door, :ext_drawer, :int_drawer or nil
      def self.kind_of(inst)
        return nil unless inst.is_a?(Sketchup::ComponentInstance)
        if (r = role(inst))
          return ROLES[r]
        end
        names = names_for(inst)
        return :int_drawer if (names & Settings.names('int_drawer_names')).any?
        return :ext_drawer if (names & Settings.names('ext_drawer_names')).any?
        return :door       if (names & Settings.names('door_names')).any?
        nil
      end

      # Fixed panels (Settings "fixed_panel_names", e.g. the stable panel): styled and ordered
      # like a door, but no hinges or handles.
      def self.fixed_name?(name)
        base = name.to_s.sub(/#\d+\z/, '').strip.upcase
        Settings.names('fixed_panel_names').include?(base)
      end

      # A fixed panel definition: its front type, else its name.
      def self.fixed_def?(defn)
        r = role(defn)
        r ? r == 'fixed' : fixed_name?(defn.name)
      end

      def self.fixed?(inst)
        return false unless inst.respond_to?(:definition)
        r = role(inst)
        return r == 'fixed' if r
        (names_for(inst) & Settings.names('fixed_panel_names')).any?
      end

      # Drawer fronts framed like a door (Settings "framed_drawer_units", e.g. the linen press):
      # the same frame all round as the doors above them.
      def self.framed?(inst)
        names = Settings.names('framed_drawer_units')
        return false if names.empty?
        e = inst
        8.times do
          d = e.parent
          break unless d.is_a?(Sketchup::ComponentDefinition)
          base = DC.base_name(d).upcase
          return true if names.any? { |n| base == n || base.start_with?("#{n}_") }
          e = d.instances.first or break
        end
        false
      end

      # Doors that never get a mid-rail (Settings "no_midrail_names").
      def self.no_midrail?(inst)
        inst.respond_to?(:definition) && (names_for(inst) & Settings.names('no_midrail_names')).any?
      end

      def self.label(inst)
        n = dc_name(inst)
        n = inst.definition.name if n.empty?
        n
      end

      # Walk every placed occurrence. Yields (instance, kind, path_of_parent_instances).
      # Does not descend into targets (their children are our own style/hardware parts).
      def self.each_occurrence(entities, path = [], depth = 0, &blk)
        return if depth > 12
        entities.each do |e|
          next unless instance?(e)
          k = kind_of(e)
          if k
            yield(e, k, path)
          else
            each_occurrence(e.definition.entities, path + [e], depth + 1, &blk)
          end
        end
      end

      # Unique target instances (each entity once), optionally filtered by kind.
      def self.targets(roots, kinds)
        found = {}
        roots.each do |r|
          if instance?(r) && (k = kind_of(r))
            found[r.entityID] = [r, k] if kinds.include?(k)
          elsif instance?(r)
            each_occurrence(r.definition.entities) { |i, kk, _| found[i.entityID] = [i, kk] if kinds.include?(kk) }
          end
        end
        found.values
      end

      def self.all_targets(model, kinds)
        found = {}
        each_occurrence(model.entities) { |i, k, _| found[i.entityID] = [i, k] if kinds.include?(k) }
        found.values
      end

      # --- measuring -------------------------------------------------------

      # Returns [sx, sy, sz] scale factors and normalised axes from a transformation.
      def self.decompose(t)
        a = t.to_a
        w = a[15].to_f.zero? ? 1.0 : a[15].to_f
        vx = Geom::Vector3d.new(a[0] / w, a[1] / w, a[2] / w)
        vy = Geom::Vector3d.new(a[4] / w, a[5] / w, a[6] / w)
        vz = Geom::Vector3d.new(a[8] / w, a[9] / w, a[10] / w)
        origin = Geom::Point3d.new(a[12] / w, a[13] / w, a[14] / w)
        [[vx.length.to_f, vy.length.to_f, vz.length.to_f], [vx, vy, vz], origin]
      end

      HARDWARE_ROLES = %w[hinge tip_on].freeze

      def self.hardware?(e)
        e.is_a?(Sketchup::ComponentInstance) && HARDWARE_ROLES.include?(e.get_attribute(DICT, 'role'))
      end

      # Bounds of the door body only - ignores hinges/TIP-ONs, which sit behind the door.
      def self.body_bounds(defn)
        bb = Geom::BoundingBox.new
        defn.entities.each do |e|
          next if hardware?(e)
          next unless e.respond_to?(:bounds)
          bb.add(e.bounds)
        end
        bb.empty? ? defn.bounds : bb
      end

      # Real size (Length, inches) along local X, Y, Z = width, thickness, height.
      # Width/height from the body geometry x scale. Thickness prefers the DC LenY
      # (so a DC that squashed the door to fit hinges is corrected on rebuild).
      def self.real_size(inst)
        # Migrated wrappers carry their size in DOOR_W / DOOR_T / DOOR_H.
        wth = %w[door_w door_t door_h].map { |k| DC.read(inst, k) }
        return wth.map(&:to_f) if wth.all? { |v| v.is_a?(Numeric) && v > 0 }

        scale, = decompose(inst.transformation)
        b = body_bounds(inst.definition)
        geo = [b.width * scale[0], b.height * scale[1], b.depth * scale[2]].map(&:to_f)
        dc = %w[lenx leny lenz].map { |k| DC.get(inst, k) } # instance only: the drawn size
        geo.each_index.map do |i|
          v = dc[i]
          ok = v.is_a?(Numeric) && v > 0 && (i == 1 || (v - geo[i]).abs < 1.mm)
          ok ? v.to_f : geo[i]
        end
      end

      # Local min corner of the door body, scaled - where the rebuilt geometry starts.
      def self.scaled_min(inst)
        scale, = decompose(inst.transformation)
        m = body_bounds(inst.definition).min
        Geom::Point3d.new(m.x * scale[0], m.y * scale[1], m.z * scale[2])
      end

      def self.scaled?(inst)
        scale, = decompose(inst.transformation)
        scale.any? { |s| (s - 1.0).abs > 0.0005 }
      end

      # Every component instance / group in the model, once each.
      def self.each_instance(entities, seen = {}, depth = 0, &blk)
        return if depth > 15
        entities.each do |e|
          next unless instance?(e)
          next if seen[e.entityID]
          seen[e.entityID] = true
          yield e
          each_instance(e.definition.entities, seen, depth + 1, &blk)
        end
      end

      def self.mm_s(len)
        format('%.0f', len.to_f * 25.4)
      end
    end
  end
end
