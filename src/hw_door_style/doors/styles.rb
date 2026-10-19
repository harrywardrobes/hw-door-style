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

      # Drawings. Each is (entities, w, t, h, kind, profile) -> { midrail:, note:, flat: }
      # and lists the profile sizes it needs (SIZES). A style can be chosen once there is
      # a drawing with its id here AND every size it needs is filled in (Settings > Door
      # styles). New drawings: add a lambda and an entry in DRAWINGS.
      FLAT = lambda do |ents, w, t, h, _kind, _p|
        box(ents, w, t, h)
        { midrail: false, note: '' }
      end

      SHAKER_SIZES = %w[door_frame_mm drawer_stile_mm drawer_frame_mm recess_mm min_panel_mm
                        midrail_min_door_height_mm midrail_centre_mm midrail_width_mm].freeze

      SHAKER = lambda do |ents, w, t, h, kind, pr|
        mm = ->(k) { pr[k].to_f / 25.4 }
        # Doors: same frame all round. Drawer fronts: stiles (vertical sides) match the
        # doors so panels line up vertically; rails (top / bottom) are slimmer.
        stile  = kind == :door ? mm.call('door_frame_mm') : mm.call('drawer_stile_mm')
        rail   = kind == :door ? mm.call('door_frame_mm') : mm.call('drawer_frame_mm')
        depth  = mm.call('recess_mm')
        min_p  = mm.call('min_panel_mm')

        panels = []
        midrail = kind == :door && h > mm.call('midrail_min_door_height_mm')
        if midrail
          c  = mm.call('midrail_centre_mm')
          mw = mm.call('midrail_width_mm')
          panels << [stile, rail, w - stile, c - mw / 2.0]
          panels << [stile, c + mw / 2.0, w - stile, h - rail]
        else
          panels << [stile, rail, w - stile, h - rail]
        end

        too_small = panels.any? { |x0, z0, x1, z1| (x1 - x0) < min_p || (z1 - z0) < min_p }
        if too_small || depth >= t
          box(ents, w, t, h)
          next { midrail: false, flat: true, note: "Too small for #{pr['name'] || 'shaker'} - left flat" }
        end

        box(ents, w, t, h)
        panels.each { |x0, z0, x1, z1| recess(ents, x0, z0, x1, z1, depth) }
        { midrail: midrail, note: '' }
      end

      DRAWINGS = {
        'flat'   => { builder: FLAT,   sizes: [] },
        'shaker' => { builder: SHAKER, sizes: SHAKER_SIZES }
      }.freeze

      # Every size a style can have (shown for every style in Settings, so they can be
      # filled in before its drawing exists).
      ALL_SIZES = SHAKER_SIZES

      SIZE_LABELS = {
        'door_frame_mm' => 'Door frame width', 'drawer_stile_mm' => 'Drawer front stiles (vertical)',
        'drawer_frame_mm' => 'Drawer front rails (top / bottom)', 'recess_mm' => 'Recess depth',
        'min_panel_mm' => 'Smallest panel', 'midrail_min_door_height_mm' => 'Mid-rail when door taller than',
        'midrail_centre_mm' => 'Mid-rail centre above door bottom', 'midrail_width_mm' => 'Mid-rail width'
      }.freeze

      # --- the style list (Settings > Door styles) ---------------------------------------

      def self.profiles
        list = Array(Settings.get['door_styles']).select { |p| p.is_a?(Hash) && !p['id'].to_s.empty? }
        list = [{ 'id' => 'flat', 'name' => 'Flat' }] + list unless list.any? { |p| p['id'] == 'flat' }
        list
      end

      def self.profile(id)
        profiles.find { |p| p['id'] == id.to_s } || (id.to_s == 'flat' ? { 'id' => 'flat', 'name' => 'Flat' } : nil)
      end

      # Why a style can't be chosen yet ([] = it can).
      def self.missing(p)
        return ['not in the style list'] unless p
        d = DRAWINGS[p['id']]
        return ['no drawing yet'] unless d
        d[:sizes].reject { |k| p[k].to_f > 0 }.map { |k| SIZE_LABELS[k] || k }
      end

      def self.ready?(id)
        missing(profile(id)).empty?
      end

      # Styles that can be chosen, in list order.
      def self.ids
        profiles.map { |p| p['id'] }.select { |i| ready?(i) }
      end

      def self.label(id)
        (profile(id) || {})['name'] || id.to_s.capitalize
      end

      def self.handleless?(id)
        (profile(id) || {})['handleless'] ? true : false
      end

      # Changes whenever a style's sizes change (so slabs are redrawn).
      def self.signature(id)
        p = profile(id) || {}
        ALL_SIZES.map { |k| p[k].to_f }.join(',')
      end

      # Builds the style's drawing. A style that can't be drawn (or is too small) is drawn
      # flat; info[:style] says what was drawn.
      def self.build(id, ents, w, t, h, kind)
        id = 'flat' unless ready?(id)
        info = DRAWINGS[id][:builder].call(ents, w, t, h, kind, profile(id))
        info.merge(style: info.delete(:flat) ? 'flat' : id)
      end
    end
  end
end
