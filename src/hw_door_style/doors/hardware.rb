module HarryWardrobes
  module DoorStyle
    # Hinge / TIP-ON components for the cutlist.
    #
    # Placed just BEHIND the door slab (Y = DOOR_T, where the real hinge sits),
    # always true size (scale 1), with DC position formulas. Hinges are a round
    # 35mm euro-hinge cup, 12mm deep. Tag = Settings "hinge_tag" (default
    # "hinges"). They are
    # never hidden themselves (cutlist software skips hidden components). Faces and
    # instance carry the material "HARDWARE" so the cutlist can split them out, and
    # the colour tool never repaints them.
    #
    # If a definition with the same name already exists and was not made by this
    # plugin (e.g. a real Blum model named "soft_close_110"), it is reused as-is.
    module Hardware
      HINGE_CUP  = [35, 12].freeze     # mm: cup diameter, depth behind the door
      CUP_SEGMENTS = 24
      SHAPE      = 'cup35_v1'.freeze   # bump to rebuild existing plugin hinges
      TIP_ON_BOX = [20, 10, 40].freeze
      EDGE_GAP   = 5 # mm from the door edge

      def self.material(model)
        name = Settings.get['hardware_material']
        m = model.materials[name]
        unless m
          m = model.materials.add(name)
          m.color = Sketchup::Color.new(140, 140, 145)
        end
        m
      end

      def self.tag(model)
        Tagger.layer(model, Settings.get['hinge_tag'])
      end

      def self.ours?(d)
        d.get_attribute(DICT, 'role') == 'hardware'
      end

      def self.paint(defn, model)
        mat = material(model)
        tg = tag(model)
        defn.entities.each do |e|
          next unless e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
          e.layer = tg unless e.layer == tg
          if e.is_a?(Sketchup::Face)
            e.material = mat unless e.material == mat
            e.back_material = mat unless e.back_material == mat
          end
        end
      end

      # Round euro-hinge cup: circle in the XZ plane, pushed back DEPTH in +Y.
      # Bounds start at the origin (0..D, 0..depth, 0..D).
      def self.cup(ents, dia, depth)
        r = dia / 2.0
        edges = ents.add_circle(Geom::Point3d.new(r, 0, r), Y_AXIS, r, CUP_SEGMENTS)
        f = ents.add_face(edges)
        f.reverse! if f.normal.y > 0
        f.pushpull(-depth)
      end

      def self.shape_ok?(d)
        d.get_attribute(DICT, 'shape') == SHAPE
      end

      # size_mm: [w, t, h] box, or :cup for the round hinge cup.
      def self.definition(model, name, size_mm)
        d = model.definitions[name]
        return d if d && !ours?(d)
        if d && (size_mm != :cup || shape_ok?(d))
          paint(d, model)
          return d
        end
        if d
          d.entities.clear!
        else
          d = model.definitions.add(name)
        end
        if size_mm == :cup
          cup(d.entities, HINGE_CUP[0].mm, HINGE_CUP[1].mm)
          d.set_attribute(DICT, 'shape', SHAPE)
        else
          w, t, h = size_mm.map { |v| v.mm }
          Styles.box(d.entities, w, t, h)
        end
        d.set_attribute(DICT, 'role', 'hardware')
        d.description = 'HW Door Style hardware (cutlist part, behind the door)'
        paint(d, model)
        d
      end

      def self.place(ents, defn, point, model, role, type)
        inst = ents.add_instance(defn, Geom::Transformation.new(point))
        inst.layer = tag(model)
        inst.material = material(model)
        inst.hidden = false
        inst.set_attribute(DICT, 'role', role)
        inst.set_attribute(DICT, 'type', type)
        inst
      end

      # Top/bottom inset: the setting, but never more than a quarter of the door
      # height (same rule as the hinge Z formula below).
      def self.inset(h)
        [Settings.mm('hinge_end_inset_mm'), h / 4.0].min
      end

      def self.hinge_heights(h, n)
        return [h / 2.0] if n <= 1
        i = inset(h)
        step = (h - 2 * i) / (n - 1).to_f
        Array.new(n) { |k| i + k * step }
      end

      # Len formulas pin hardware to its true size, so a DC redraw can never stretch it.
      def self.lock_size(inst, prefix, bounds)
        DC.formula(inst, 'lenx', "parent!#{prefix}_W", bounds.width)
        DC.formula(inst, 'leny', "parent!#{prefix}_D", bounds.height)
        DC.formula(inst, 'lenz', "parent!#{prefix}_HT", bounds.depth)
      end

      # --- hinge side -------------------------------------------------------------------
      # Double doors: the first copy (left door) is hinged on its left edge, the second
      # copy on its right. Single door: the unit's "Hinge side (single door)" option, added
      # to the unit next to Double / Single the first time its doors are drawn.
      # ZZ_HINGE_RIGHT on the door is a formula, so changing either option in Component
      # Options moves the hinges (and TIP-ON, on the other edge) when the unit redraws.

      def self.unit_def(inst)
        inst.parent.is_a?(Sketchup::ComponentDefinition) ? inst.parent : nil
      end

      def self.double_key(unit)
        dd = unit && DC.dict(unit) or return nil
        DC.key_in(dd, 'door_double') || DC.key_in(dd, 'double')
      end

      def self.side_key(unit)
        dd = unit && DC.dict(unit) or return nil
        DC.key_in(dd, 'hinge_side')
      end

      # Adds the unit option if it's missing; returns its key.
      def self.ensure_side_option(unit)
        return nil unless unit
        k = side_key(unit)
        return k if k
        dbl = double_key(unit)
        letter = dbl.to_s[/\A([a-z])\d{1,2}_/, 1]
        if letter
          used = DC.dict(unit).keys.filter_map { |x| x[/\A_?#{letter}(\d{1,2})_/, 1]&.to_i }.max.to_i
          k = format('%s%02d_hinge_side', letter, used + 1)
        else
          k = 'hinge_side'
        end
        ([unit] + unit.instances).each do |o|
          o.set_attribute(DC::DICT_NAME, k, 0.0) if o == unit || DC.get(o, k).nil?
          o.set_attribute(DC::DICT_NAME, "_#{k}_label", k.upcase)
          o.set_attribute(DC::DICT_NAME, "_#{k}_formlabel", 'Hinge side (single door)')
          o.set_attribute(DC::DICT_NAME, "_#{k}_access", 'LIST')
          o.set_attribute(DC::DICT_NAME, "_#{k}_options", '&Left=0&Right=1&')
          o.set_attribute(DC::DICT_NAME, "_#{k}_units", 'FLOAT')
          o.set_attribute(DC::DICT_NAME, "_#{k}_formulaunits", 'FLOAT')
        end
        k
      end

      def self.truthy?(v)
        return false if v.nil?
        return v != 0 if v.is_a?(Numeric)
        s = v.to_s.strip.upcase
        !(s.empty? || s == '0' || s == '0.0' || s == 'FALSE')
      end

      # The value of a unit option: the unit instance's own value, else the definition's.
      def self.unit_value(unit, key)
        return nil unless unit && key
        i = unit.instances.first
        i ? DC.read(i, key) : DC.get(unit, key)
      end

      # Hinges on the door's right edge? (now, for drawing; the formula keeps it right later)
      # Stable wardrobe: the stable panel's side (Left 0 / Right 1). The door above the panel
      # ("..._UPPER") is on that side, the full-height door on the other; each hinges on its
      # outer edge.
      def self.stable_key(unit)
        dd = unit && DC.dict(unit) or return nil
        DC.key_in(dd, 'stable_side')
      end

      def self.upper?(inst) = Finder.names_for(inst).any? { |n| n.end_with?('_UPPER') }

      def self.right?(inst)
        unit = unit_def(inst)
        if (sk = stable_key(unit))
          on_stable = truthy?(unit_value(unit, sk))
          return upper?(inst) ? on_stable : !on_stable
        end
        dbl = double_key(unit)
        return DC.read(inst, 'copy').to_f >= 1 if dbl && truthy?(unit_value(unit, dbl))
        truthy?(unit_value(unit, side_key(unit)))
      end

      def self.side_formula(unit, door = nil)
        if (sk = stable_key(unit))
          up = door && upper?(door)
          return "IF(parent!#{sk.upcase}=1, #{up ? '1, 0' : '0, 1'})"
        end
        dbl = double_key(unit)
        side = side_key(unit)
        single = side ? "IF(parent!#{side.upcase}=1, 1, 0)" : '0'
        dbl ? "IF(parent!#{dbl.upcase}, IF(COPY>=1, 1, 0), #{single})" : single
      end

      # Adds hardware to a door wrapper definition, positioned from the wrapper
      # origin with DC formulas so it follows DOOR_W / DOOR_T / DOOR_H when the
      # door is resized (hinge COUNT still needs a re-run).
      # wrappers = [definition, instances...] that carry the helper attributes.
      # Returns { hinges: n, tip_on: n }.
      def self.add(door_def, wrappers, w, t, h, kind, hinge_type)
        return { hinges: 0, tip_on: 0 } unless kind == :door
        # Fixed panels (the stable panel) have no hinges or TIP-ON.
        return { hinges: 0, tip_on: 0 } if Finder.fixed_def?(door_def)
        model = door_def.model
        ents = door_def.entities
        gap = EDGE_GAP.mm

        hd = definition(model, hinge_type, :cup)
        hb = hd.bounds
        n = Settings.hinge_count(h)
        heights = hinge_heights(h, n)

        DC.length_attr(wrappers, 'ZZ_HINGE_X', nil, gap - hb.min.x)
        DC.length_attr(wrappers, 'ZZ_HINGE_XR', nil, gap + hb.width + hb.min.x)
        insts = wrappers.grep(Sketchup::ComponentInstance)
        unit = insts.map { |i| unit_def(i) }.compact.first
        ensure_side_option(unit)
        right = insts.first ? right?(insts.first) : false
        side_f = side_formula(unit, insts.first)
        wrappers.each do |o|
          DC.number_attr(o, 'ZZ_HINGE_RIGHT', side_f, o.is_a?(Sketchup::ComponentInstance) ? (right?(o) ? 1 : 0) : (right ? 1 : 0))
        end
        DC.length_attr(wrappers, 'ZZ_HINGE_INSET', nil, Settings.mm('hinge_end_inset_mm'))
        DC.length_attr(wrappers, 'ZZ_HINGE_HALF', nil, hb.depth / 2.0 + hb.min.z)
        DC.number_attr(wrappers, 'ZZ_HINGE_GAPS', nil, [n - 1, 1].max)
        DC.length_attr(wrappers, 'ZZ_HINGE_W', nil, hb.width)
        DC.length_attr(wrappers, 'ZZ_HINGE_D', nil, hb.height)
        DC.length_attr(wrappers, 'ZZ_HINGE_HT', nil, hb.depth)
        DC.child(hd, hinge_type)

        inset_f = 'SMALLEST(parent!ZZ_HINGE_INSET, parent!DOOR_H/4)'
        heights.each_with_index do |zc, i|
          x = right ? w - (gap + hb.width + hb.min.x) : gap - hb.min.x
          p = Geom::Point3d.new(x, t - hb.min.y, zc - hb.depth / 2.0 - hb.min.z)
          inst = place(ents, hd, p, model, 'hinge', hinge_type)
          DC.child(inst, hinge_type)
          DC.number_attr(inst, 'ZZ_HINGE_I', nil, i)
          z_f = if n <= 1
                  'parent!DOOR_H/2 - parent!ZZ_HINGE_HALF'
                else
                  "#{inset_f} + ZZ_HINGE_I*(parent!DOOR_H - 2*#{inset_f})/parent!ZZ_HINGE_GAPS - parent!ZZ_HINGE_HALF"
                end
          DC.formula(inst, 'x', 'IF(parent!ZZ_HINGE_RIGHT, parent!DOOR_W - parent!ZZ_HINGE_XR, parent!ZZ_HINGE_X)', p.x)
          DC.formula(inst, 'y', 'parent!DOOR_T', p.y)
          DC.formula(inst, 'z', z_f, p.z)
          lock_size(inst, 'ZZ_HINGE', hb)
        end

        tips = 0
        if Settings.pto?(hinge_type)
          td = definition(model, 'tip_on', TIP_ON_BOX)
          tb = td.bounds
          tip_x = tb.width + gap + tb.min.x
          tip_z = tb.depth + 20.mm + tb.min.z
          DC.length_attr(wrappers, 'ZZ_TIP_X', nil, tip_x)
          DC.length_attr(wrappers, 'ZZ_TIP_XL', nil, gap - tb.min.x)
          DC.length_attr(wrappers, 'ZZ_TIP_Z', nil, tip_z)
          DC.length_attr(wrappers, 'ZZ_TIP_W', nil, tb.width)
          DC.length_attr(wrappers, 'ZZ_TIP_D', nil, tb.height)
          DC.length_attr(wrappers, 'ZZ_TIP_HT', nil, tb.depth)
          DC.child(td, 'tip_on')
          p = Geom::Point3d.new(right ? gap - tb.min.x : w - tip_x, t - tb.min.y, h - tip_z)
          inst = place(ents, td, p, model, 'tip_on', 'tip_on')
          DC.child(inst, 'tip_on')
          DC.formula(inst, 'x', 'IF(parent!ZZ_HINGE_RIGHT, parent!ZZ_TIP_XL, parent!DOOR_W - parent!ZZ_TIP_X)', p.x)
          DC.formula(inst, 'y', 'parent!DOOR_T', p.y)
          DC.formula(inst, 'z', 'parent!DOOR_H - parent!ZZ_TIP_Z', p.z)
          lock_size(inst, 'ZZ_TIP', tb)
          tips = 1
        end

        { hinges: heights.size, tip_on: tips }
      end
    end
  end
end
