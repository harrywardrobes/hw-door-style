module HarryWardrobes
  module DoorStyle
    # Hinge / TIP-ON components for the cutlist.
    #
    # They are NOT hidden (cutlist software skips hidden components). Instead each
    # one sits fully inside the door's thickness, in the solid frame area, so the
    # door's own faces cover it on every side: invisible in the model and in
    # renders, but a normal component the cutlist can find. Faces and instance get
    # the material "HARDWARE" so the cutlist can split them out.
    #
    # If a definition with the same name already exists and was not made by this
    # plugin (e.g. a real Blum model named "soft_close_110"), it is reused as-is.
    module Hardware
      HINGE_BOX  = [35, 10, 35].freeze # mm: x (across door), y (thickness), z (height)
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

      def self.ours?(d)
        d.get_attribute(DICT, 'role') == 'hardware'
      end

      def self.paint(defn, model)
        mat = material(model)
        tag = Tagger.layer(model, Settings.get['hardware_tag'])
        defn.entities.each do |e|
          next unless e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
          e.layer = tag unless e.layer == tag
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
        d.description = 'HW Door Style hardware (cutlist part - sits inside the door, not visible)'
        paint(d, model)
        d
      end

      def self.place(ents, defn, point, model, role, type)
        inst = ents.add_instance(defn, Geom::Transformation.new(point))
        inst.layer = Tagger.layer(model, Settings.get['hardware_tag'])
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

      # Y position that centres a part of thickness `pt` inside a door of thickness `t`.
      def self.inside_y(t, pt)
        [(t - pt) / 2.0, 0.5.mm].max
      end

      # Adds hardware to a door definition. min = local corner of the door.
      # Returns { hinges: n, tip_on: n }.
      def self.add(door_def, min, w, t, h, kind, hinge_type)
        return { hinges: 0, tip_on: 0 } unless kind == :door
        model = door_def.model
        ents = door_def.entities
        gap = EDGE_GAP.mm

        hd = definition(model, hinge_type, HINGE_BOX)
        hb = hd.bounds
        heights = hinge_heights(h, Settings.hinge_count(h))
        heights.each do |zc|
          p = Geom::Point3d.new(min.x + gap - hb.min.x,
                                min.y + inside_y(t, hb.height) - hb.min.y,
                                min.z + zc - hb.depth / 2.0 - hb.min.z)
          place(ents, hd, p, model, 'hinge', hinge_type)
        end

        tips = 0
        if Settings.pto?(hinge_type)
          td = definition(model, 'tip_on', TIP_ON_BOX)
          tb = td.bounds
          p = Geom::Point3d.new(min.x + w - tb.width - gap - tb.min.x,
                                min.y + inside_y(t, tb.height) - tb.min.y,
                                min.z + h - tb.depth - 20.mm - tb.min.z)
          place(ents, td, p, model, 'tip_on', 'tip_on')
          tips = 1
        end

        { hinges: heights.size, tip_on: tips }
      end
    end
  end
end
