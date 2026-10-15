module HarryWardrobes
  module DoorStyle
    # Hidden hinge / TIP-ON components, placed inside the door envelope, used
    # only for the parts list. If a definition with the same name already exists
    # (e.g. a real Blum model named "soft_close_110"), it is reused.
    module Hardware
      HINGE_BOX  = [35, 12, 35].freeze # mm: x, y (into back of door), z
      TIP_ON_BOX = [20, 10, 40].freeze

      def self.definition(model, name, size_mm)
        d = model.definitions[name]
        return d if d
        d = model.definitions.add(name)
        w, t, h = size_mm.map { |v| v.mm }
        Styles.box(d.entities, w, t, h)
        d.set_attribute(DICT, 'role', 'hardware')
        d.description = 'HW Door Style hardware placeholder (parts list only)'
        d
      end

      def self.place(ents, defn, point, tag, role, type)
        inst = ents.add_instance(defn, Geom::Transformation.new(point))
        inst.layer = tag
        inst.hidden = true
        inst.set_attribute(DICT, 'role', role)
        inst.set_attribute(DICT, 'type', type)
        inst
      end

      def self.hinge_heights(h, n)
        box = HINGE_BOX[2].mm
        inset = Settings.mm('hinge_end_inset_mm')
        inset = h / 4.0 if h < (2 * inset + box)
        return [h / 2.0] if n <= 1
        step = (h - 2 * inset) / (n - 1).to_f
        Array.new(n) { |i| inset + i * step }
      end

      # Adds hardware to a door definition. min = local corner of the door.
      # Returns { hinges: n, tip_on: n }.
      def self.add(door_def, min, w, t, h, kind, hinge_type)
        return { hinges: 0, tip_on: 0 } unless kind == :door
        model = door_def.model
        tag = model.layers.add(Settings.get['hardware_tag'])
        ents = door_def.entities

        hd = definition(model, hinge_type, HINGE_BOX)
        hx = 5.mm
        hy = t - HINGE_BOX[1].mm
        heights = hinge_heights(h, Settings.hinge_count(h))
        heights.each do |zc|
          p = Geom::Point3d.new(min.x + hx, min.y + hy, min.z + zc - HINGE_BOX[2].mm / 2.0)
          place(ents, hd, p, tag, 'hinge', hinge_type)
        end

        tips = 0
        if Settings.pto?(hinge_type)
          td = definition(model, 'tip_on', TIP_ON_BOX)
          p = Geom::Point3d.new(min.x + w - TIP_ON_BOX[0].mm - 5.mm,
                                min.y + t - TIP_ON_BOX[1].mm,
                                min.z + h - TIP_ON_BOX[2].mm - 20.mm)
          place(ents, td, p, tag, 'tip_on', 'tip_on')
          tips = 1
        end

        { hinges: heights.size, tip_on: tips }
      end
    end
  end
end
