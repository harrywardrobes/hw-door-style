module HarryWardrobes
  module DoorStyle
    # Style registry. Each style builds its geometry into an empty Entities
    # collection with the front face on the y = 0 plane facing -Y, the solid
    # extending to +Y by the thickness, width along X and height along Z.
    #
    # To add a style: write a builder lambda (entities, w, t, h, kind) -> info hash
    # and register it in STYLES. Menus and context menus pick it up automatically.
    module Styles
      TOL = 0.001

      def self.pt(x, y, z)
        Geom::Point3d.new(x, y, z)
      end

      # Plain slab. Returns nothing useful.
      def self.box(ents, w, t, h)
        f = ents.add_face(pt(0, 0, 0), pt(w, 0, 0), pt(w, 0, h), pt(0, 0, h))
        f.reverse! if f.normal.y > 0
        f.pushpull(-t)
        # Make sure the solid is outward-facing: front face must point to -Y.
        front = ents.grep(Sketchup::Face)
                    .select { |fc| fc.normal.parallel?(Y_AXIS) && fc.vertices.all? { |v| v.position.y.abs < TOL } }
                    .max_by(&:area)
        ents.grep(Sketchup::Face).each(&:reverse!) if front && front.normal.y > 0
      end

      # Pushes a rectangle on the front face back by depth.
      def self.recess(ents, x0, z0, x1, z1, depth)
        f = ents.add_face(pt(x0, 0, z0), pt(x1, 0, z0), pt(x1, 0, z1), pt(x0, 0, z1))
        return false unless f
        f.reverse! if f.normal.y > 0
        f.pushpull(-depth)
        true
      end

      FLAT = lambda do |ents, w, t, h, _kind|
        box(ents, w, t, h)
        { style: 'flat', midrail: false, note: '' }
      end

      SHAKER = lambda do |ents, w, t, h, kind|
        # Doors: same frame all round. Drawer fronts: stiles (vertical sides) match the
        # doors so panels line up vertically; rails (top / bottom) are slimmer.
        stile  = kind == :door ? Settings.mm('door_frame_mm') : Settings.mm('drawer_stile_mm')
        rail   = kind == :door ? Settings.mm('door_frame_mm') : Settings.mm('drawer_frame_mm')
        depth  = Settings.mm('recess_mm')
        min_p  = Settings.mm('min_panel_mm')

        panels = []
        midrail = kind == :door && h > Settings.mm('midrail_min_door_height_mm')
        if midrail
          c  = Settings.mm('midrail_centre_mm')
          mw = Settings.mm('midrail_width_mm')
          panels << [stile, rail, w - stile, c - mw / 2.0]
          panels << [stile, c + mw / 2.0, w - stile, h - rail]
        else
          panels << [stile, rail, w - stile, h - rail]
        end

        too_small = panels.any? { |x0, z0, x1, z1| (x1 - x0) < min_p || (z1 - z0) < min_p }
        if too_small || depth >= t
          box(ents, w, t, h)
          next { style: 'flat', midrail: false, note: 'Too small for shaker - left flat' }
        end

        box(ents, w, t, h)
        panels.each { |x0, z0, x1, z1| recess(ents, x0, z0, x1, z1, depth) }
        { style: 'shaker', midrail: midrail, note: '' }
      end

      STYLES = {
        'flat'   => { label: 'Flat',   builder: FLAT },
        'shaker' => { label: 'Shaker', builder: SHAKER }
      }.freeze

      def self.ids
        STYLES.keys
      end

      def self.label(id)
        STYLES.dig(id, :label) || id.to_s.capitalize
      end

      def self.build(id, ents, w, t, h, kind)
        style = STYLES[id] || STYLES['flat']
        style[:builder].call(ents, w, t, h, kind)
      end
    end
  end
end
