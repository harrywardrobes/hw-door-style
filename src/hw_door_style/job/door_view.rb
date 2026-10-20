module HarryWardrobes
  module DoorStyle
    # Door elevation: the doors and drawer fronts on each wall drawn flat, front on, with
    # their sizes - widths along the bottom (and along the top for doors above drawers), the
    # overall height at each end, the height of any door that isn't full height, each drawer
    # front's height, the mid-rail width on each door and the mid-rail centre on the first.
    #
    #   Model   Workshop > Floor Plan > "Doors view": a drawing per wall on the "Door elevation"
    #           tag (below the floor, out of the way) and a scene for each - "Doors", or
    #           "Doors - back wall" / "- left wall"... when there is more than one wall. The tag
    #           shows only in those scenes. Made again each time, like the T numbers.
    #   PDFs    a Door elevation page per wall in the Room Plan and on the door order.
    module DoorView
      ATTR = 'door_view'.freeze
      KINDS = %i[door ext_drawer].freeze
      WALLS = { [0, -1] => 'back wall', [1, 0] => 'left wall', [-1, 0] => 'right wall', [0, 1] => 'front wall' }.freeze
      ORDER = ['back wall', 'left wall', 'right wall', 'front wall'].freeze

      def self.mm(v) = v.to_f * 25.4

      def self.tag(model)
        n = Settings.get['door_view_tag'].to_s.strip
        n = 'Door elevation' if n.empty?
        model.layers[n] || model.layers.add(n)
      end

      def self.scene_re = /\ADoors\b/i

      # --- reading the fronts ----------------------------------------------------------

      # Every visible door / external drawer front with its world transformation.
      def self.occurrences(model)
        out = []
        walk = lambda do |ents, tr, depth|
          ents.each do |e|
            next unless Finder.instance?(e)
            next if e.hidden?
            t = tr * e.transformation
            k = Finder.kind_of(e)
            if k
              out << [e, k, t] if KINDS.include?(k)
            elsif depth < 12
              walk.call(e.definition.entities, t, depth + 1)
            end
          end
        end
        walk.call(model.entities, Geom::Transformation.new, 0)
        out
      end

      # The wall a front faces from (its front normal, snapped).
      def self.wall_of(t)
        n = t.yaxis.reverse
        n.z = 0
        return nil if n.length < 1e-6
        n.normalize!
        key = n.x.abs > n.y.abs ? [n.x.positive? ? 1 : -1, 0] : [0, n.y.positive? ? 1 : -1]
        [key, Geom::Vector3d.new(key[0], key[1], 0)]
      end

      # [{ 'wall', 'width', 'height', 'fronts' => [...], 'dims' => [...], 'texts' => [...] }]
      # in mm, from the left / bottom of the run as seen from the front.
      def self.walls(model)
        raw = Hash.new { |h, k| h[k] = [] }
        occurrences(model).each do |e, k, t|
          key, n = wall_of(t)
          next unless key
          r = Z_AXIS * n # viewer's right
          db = e.definition.bounds
          pts = (0..7).map { |i| t * db.corner(i) }
          us = pts.map { |p| mm(Geom::Vector3d.new(p.x, p.y, p.z).dot(r)) }
          zs = pts.map { |p| mm(p.z) }
          w, _th, h = Finder.real_size(e)
          d = e.definition
          style = d.get_attribute(DICT, 'style') || 'flat'
          pn = Styles.panels(style, w, h, k, no_midrail: Finder.no_midrail?(e))
          raw[key] << { 'kind' => k.to_s, 'u0' => us.min, 'u1' => us.max, 'z0' => zs.min, 'z1' => zs.max,
                        'w' => mm(w).round, 'h' => mm(h).round, 'style' => style, 'fixed' => Finder.fixed?(e),
                        'panels' => pn[:panels].map { |a| a.map { |v| mm(v) } },
                        'midrail' => pn[:midrail] && mm(pn[:midrail]).round, 'midrail_width' => pn[:midrail_width] && mm(pn[:midrail_width]).round }
        end
        list = raw.map do |key, fronts|
          u = fronts.map { |f| f['u0'] }.min
          z = fronts.map { |f| f['z0'] }.min
          fronts.each { |f| f['u0'] -= u; f['u1'] -= u; f['z0'] -= z; f['z1'] -= z }
          fronts.sort_by! { |f| [f['u0'].round, f['z0'].round] }
          wall = { 'wall' => WALLS[key], 'fronts' => fronts, 'width' => fronts.map { |f| f['u1'] }.max, 'height' => fronts.map { |f| f['z1'] }.max }
          wall.merge(measure(wall))
        end
        list.sort_by { |w| ORDER.index(w['wall']) || 9 }
      end

      # Dimensions and texts for a wall (mm). A dimension: { 'a' => [u, z], 'b' => [u, z],
      # 'side' => :left / :right / :top / :bottom / :inside / :mid, 'text' }.
      def self.measure(wall)
        fs = wall['fronts']
        hh = wall['height']
        ww = wall['width']
        tol = 5
        dims = []
        texts = []
        dims << { 'a' => [0, 0], 'b' => [0, hh], 'side' => 'left', 'text' => hh.round.to_s }
        dims << { 'a' => [ww, 0], 'b' => [ww, hh], 'side' => 'right', 'text' => hh.round.to_s }
        fs.each do |f|
          uc = (f['u0'] + f['u1']) / 2.0
          if f['z0'] < tol
            dims << { 'a' => [f['u0'], 0], 'b' => [f['u1'], 0], 'side' => 'bottom', 'text' => f['w'].to_s }
          elsif f['z1'] > hh - tol
            dims << { 'a' => [f['u0'], hh], 'b' => [f['u1'], hh], 'side' => 'top', 'text' => f['w'].to_s }
          end
          if f['kind'] == 'ext_drawer'
            texts << { 'at' => [uc, (f['z0'] + f['z1']) / 2.0], 'text' => f['h'].to_s }
          elsif (f['z1'] - f['z0'] - hh).abs > 3
            dims << { 'a' => [uc, f['z0']], 'b' => [uc, f['z1']], 'side' => 'inside', 'text' => f['h'].to_s }
          end
          texts << { 'at' => [uc, f['z0'] + f['midrail']], 'text' => f['midrail_width'].to_s } if f['midrail']
        end
        first = fs.select { |f| f['midrail'] }.min_by { |f| f['u0'] }
        dims << { 'a' => [first['u0'], first['z0']], 'b' => [first['u0'], first['z0'] + first['midrail']], 'side' => 'mid', 'text' => first['midrail'].to_s } if first
        { 'dims' => dims, 'texts' => texts }
      end

      # --- in the model ----------------------------------------------------------------

      GAP = 2500 # mm between the drawings, below the floor

      def self.build(model)
        walls = walls(model)
        tag = tag(model)
        view = model.active_view
        was_page = model.pages.selected_page
        c = view.camera
        cam = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov)
        cam.height = c.height unless c.perspective?
        opts = model.options['PageOptions']
        trans = opts['ShowTransition']
        made = []
        Ops.run(model, 'Doors view') do
          old = model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT, ATTR) }
          model.entities.erase_entities(old) unless old.empty?
          model.pages.to_a.select { |pg| pg.name =~ scene_re }.each { |pg| model.pages.erase(pg) }
          b = model.bounds
          z = b.min.z - GAP.mm
          walls.each do |w|
            z -= w['height'].mm
            g = draw(model, w, Geom::Point3d.new(b.min.x, b.min.y - 3000.mm, z))
            g.layer = tag
            g.set_attribute(DICT, ATTR, w['wall'])
            made << [w, g]
            z -= GAP.mm
          end
          opts['ShowTransition'] = false
          tag.visible = true
          made.each do |w, g|
            name = walls.size == 1 ? 'Doors' : "Doors - #{w['wall']}"
            ctr = g.bounds.center
            view.camera = Sketchup::Camera.new(ctr.offset([0, -20_000.mm, 0]), ctr, Z_AXIS, false)
            view.zoom(g)
            pg = model.pages.add(name)
            pg.use_camera = true
          end
          model.pages.each { |pg| pg.set_visibility(tag, pg.name =~ scene_re ? true : false) }
        ensure
          opts['ShowTransition'] = trans
          model.pages.selected_page = was_page if was_page
          view.camera = cam
          sel = model.pages.selected_page
          tag.visible = sel && sel.name =~ scene_re ? true : false
        end
        made.map { |w, _| w['wall'] }
      end

      def self.draw(model, wall, origin)
        g = model.entities.add_group
        ents = g.entities
        pt = ->(u, z) { origin.offset([u.mm, 0, z.mm]) }
        wall['fronts'].each do |f|
          ents.add_face(pt.(f['u0'], f['z0']), pt.(f['u1'], f['z0']), pt.(f['u1'], f['z1']), pt.(f['u0'], f['z1']))
          f['panels'].each do |x0, z0, x1, z1|
            ents.add_face(pt.(f['u0'] + x0, f['z0'] + z0), pt.(f['u0'] + x1, f['z0'] + z0), pt.(f['u0'] + x1, f['z0'] + z1), pt.(f['u0'] + x0, f['z0'] + z1))
          end
        end
        off = { 'left' => [-160, 0], 'right' => [160, 0], 'top' => [0, 90], 'bottom' => [0, -90], 'inside' => [0, 0], 'mid' => [-70, 0] }
        wall['dims'].each do |d|
          o = off[d['side']] || [0, 0]
          v = Geom::Vector3d.new(o[0].mm, 0, o[1].mm)
          v = Geom::Vector3d.new(0.01.mm, 0, 0) if v.length.zero?
          ents.add_dimension_linear(pt.(*d['a']), pt.(*d['b']), v)
        end
        wall['texts'].each do |t|
          x = ents.add_text(t['text'], pt.(*t['at']))
          x.display_leader = false
        end
        g
      end

      # --- on a PDF page -----------------------------------------------------------------

      # Draws a wall into the box (points): fronts, panels, dimensions.
      def self.draw_pdf(page, wall, bx, by, bw, bh)
        ww = wall['width'].to_f
        hh = wall['height'].to_f
        return if ww <= 0 || hh <= 0
        s = [(bw - 110) / ww, (bh - 50) / hh].min
        ox = bx + 60 + ((bw - 110) - ww * s) / 2
        oy = by + 25 + ((bh - 50) - hh * s) / 2
        p = ->(u, z) { [ox + u * s, oy + z * s] }
        wall['fronts'].each do |f|
          x, y = p.(f['u0'], f['z0'])
          page.rect(x, y, (f['u1'] - f['u0']) * s, (f['z1'] - f['z0']) * s, 0, 0.8)
          f['panels'].each do |x0, z0, x1, z1|
            page.rect(x + x0 * s, y + z0 * s, (x1 - x0) * s, (z1 - z0) * s, 0.35, 0.5)
          end
        end
        off = { 'left' => [-34, 0], 'right' => [34, 0], 'top' => [0, 12], 'bottom' => [0, -12], 'inside' => [0, 0], 'mid' => [-16, 0] }
        wall['dims'].each do |d|
          dx, dy = off[d['side']] || [0, 0]
          ax, ay = p.(*d['a'])
          bx2, by2 = p.(*d['b'])
          page.line(ax, ay, ax + dx, ay + dy, 0.55, 0.4) unless dx.zero? && dy.zero?
          page.line(bx2, by2, bx2 + dx, by2 + dy, 0.55, 0.4) unless dx.zero? && dy.zero?
          x1 = ax + dx
          y1 = ay + dy
          x2 = bx2 + dx
          y2 = by2 + dy
          page.line(x1, y1, x2, y2, 0, 0.5)
          if (x2 - x1).abs > (y2 - y1).abs
            [x1, x2].each { |x| page.line(x, y1 - 2.5, x, y1 + 2.5, 0, 0.5) }
            mx = (x1 + x2) / 2
            ty = d['side'] == 'top' ? y1 + 2.5 : y1 - 9
            page.text(mx - Pdf.width(d['text'], 'F1', 8) / 2, ty, d['text'], size: 8)
          else
            [y1, y2].each { |y| page.line(x1 - 2.5, y, x1 + 2.5, y, 0, 0.5) }
            my = (y1 + y2) / 2 - 3
            tw = Pdf.width(d['text'], 'F1', 8)
            tx = case d['side']
                 when 'left', 'mid' then x1 - tw - 3
                 when 'right' then x1 + 3
                 else x1 - tw / 2
                 end
            page.rect_fill(tx - 1, my - 2, tw + 2, 10, 1) if d['side'] == 'inside'
            page.text(tx, my, d['text'], size: 8)
          end
        end
        wall['texts'].each do |t|
          x, y = p.(*t['at'])
          tw = Pdf.width(t['text'], 'F1', 8)
          page.rect_fill(x - tw / 2 - 1, y - 4, tw + 2, 9, 1)
          page.text(x - tw / 2, y - 2.5, t['text'], size: 8)
        end
      end

      def self.title(wall, many)
        many ? "Door elevation - #{wall['wall']}" : 'Door elevation'
      end
    end
  end
end
