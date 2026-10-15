module HarryWardrobes
  module DoorStyle
    # Hinge / TIP-ON components for the cutlist.
    #
    # Placed just BEHIND the door (against its back face, where the real hinge
    # sits), on the DOOR tag - so hiding DOOR hides them with the doors. They are
    # never hidden themselves (cutlist software skips hidden components). Faces and
    # instance carry the material "HARDWARE" so the cutlist can split them out, and
    # the colour tool never repaints them.
    #
    # If a definition with the same name already exists and was not made by this
    # plugin (e.g. a real Blum model named "soft_close_110"), it is reused as-is.
    module Hardware
      HINGE_BOX  = [35, 10, 35].freeze # mm: x (across door), y (depth behind door), z (height)
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

      def self.definition(model, name, size_mm)
        d = model.definitions[name]
        if d
          paint(d, model) if ours?(d)
          return d
        end
        d = model.definitions.add(name)
        w, t, h = size_mm.map { |v| v.mm }
        Styles.box(d.entities, w, t, h)
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

      def self.hinge_heights(h, n)
        box = HINGE_BOX[2].mm
        inset = Settings.mm('hinge_end_inset_mm')
        inset = h / 4.0 if h < (2 * inset + box)
        return [h / 2.0] if n <= 1
        step = (h - 2 * inset) / (n - 1).to_f
        Array.new(n) { |i| inset + i * step }
      end

      # Adds hardware to a door definition. min = local corner of the door body
      # (front face at min.y, back face at min.y + t). Returns { hinges: n, tip_on: n }.
      def self.add(door_def, min, w, t, h, kind, hinge_type)
        return { hinges: 0, tip_on: 0 } unless kind == :door
        model = door_def.model
        ents = door_def.entities
        gap = EDGE_GAP.mm
        back = min.y + t

        hd = definition(model, hinge_type, HINGE_BOX)
        hb = hd.bounds
        heights = hinge_heights(h, Settings.hinge_count(h))
        heights.each do |zc|
          p = Geom::Point3d.new(min.x + gap - hb.min.x, back - hb.min.y,
                                min.z + zc - hb.depth / 2.0 - hb.min.z)
          place(ents, hd, p, model, 'hinge', hinge_type)
        end

        tips = 0
        if Settings.pto?(hinge_type)
          td = definition(model, 'tip_on', TIP_ON_BOX)
          tb = td.bounds
          p = Geom::Point3d.new(min.x + w - tb.width - gap - tb.min.x, back - tb.min.y,
                                min.z + h - tb.depth - 20.mm - tb.min.z)
          place(ents, td, p, model, 'tip_on', 'tip_on')
          tips = 1
        end

        { hinges: heights.size, tip_on: tips }
      end
    end
  end
end
