module HarryWardrobes
  module DoorStyle
    # Worktop view for the Door / Vinyl order: each worktop drawn from above (its front edge
    # at the bottom) with its length and depth, and the edges to be profiled drawn bold:
    #
    #   front         always profiled (bold)
    #   left / right  profiled unless that side is against a wall (the WORKTOP unit's
    #                 Wall left / Wall right; a drawer unit: Fitted = between units, so not)
    #   back          against the wall (dotted) unless the unit's Wall back is off
    #
    # Only real worktops (the parts list's Worktops section: 22 / 25 mm) - the linen press
    # top is an 18 mm floor.
    module WorktopView
      def self.mm(v) = v.to_f * 25.4

      def self.truthy?(v) = !v.nil? && !%w[FALSE 0 0.0 NO].include?(v.to_s.strip.upcase) && !v.to_s.strip.empty?

      # The unit option (instance value, else the definition's), by its key or nil.
      def self.option(unit, base)
        k = DC.key(unit, base) or return nil
        DC.read(unit, k)
      end

      # Which edges are profiled for a worktop part inside unit.
      def self.edges(unit)
        wl = option(unit, 'wall_left')
        wr = option(unit, 'wall_right')
        wb = option(unit, 'wall_back')
        fitted = option(unit, 'fitted')
        { 'front' => true,
          'left' => !(wl.nil? ? truthy?(fitted) : truthy?(wl)),
          'right' => !(wr.nil? ? truthy?(fitted) : truthy?(wr)),
          'back' => wb.nil? ? false : !truthy?(wb) }
      end

      # [{ 'name', 'pod', 'length', 'depth', 'thickness', 'material', 'edges' }] - every worktop
      # part, from the parts list's worktop groups (so the sizes match the order).
      def self.worktops(model, parts, tops)
        out = []
        parts['groups'].select { |g| g['section'] == 'worktops' }.each do |g|
          g['parts'].each do |p|
            Array(p['instances']).each do |i|
              unit = i['top'] && (model.find_entity_by_id(i['top']) rescue nil)
              out << { 'name' => p['name'], 'pod' => tops[i['top']].to_s, 'length' => p['length'].to_f.round, 'depth' => p['width'].to_f.round,
                       'thickness' => g['thickness'].to_f.round, 'material' => g['material'], 'edges' => unit ? edges(unit) : edges(nil) }
            end
          end
        end
        out.sort_by { |w| [Labels.t_key(w['pod']), w['name']] }
      end

      def self.title(w, idx, many)
        "Worktop#{many ? " #{idx + 1}" : ''} - #{w['pod'].to_s.empty? ? w['name'] : "#{w['pod']} #{w['name']}"}"
      end

      # One worktop in the box (bx, by, bw, bh) on a PDF page, with dimensions and the key.
      def self.draw_pdf(page, w, bx, by, bw, bh, key: true)
        l = w['length'].to_f
        d = w['depth'].to_f
        return if l <= 0 || d <= 0
        s = [(bw - 120) / l, (bh - 80) / d].min
        rw = l * s
        rh = d * s
        x0 = bx + 60 + ((bw - 120) - rw) / 2
        y0 = by + 40 + ((bh - 80) - rh) / 2
        e = w['edges']
        edge = lambda do |x1, y1, x2, y2, on|
          on ? page.line(x1, y1, x2, y2, 0, 2.2) : page.dashed(x1, y1, x2, y2, 0.2, 0.6, 3)
        end
        edge.call(x0, y0, x0 + rw, y0, e['front'])            # front (bottom)
        edge.call(x0, y0 + rh, x0 + rw, y0 + rh, e['back'])   # back (top)
        edge.call(x0, y0, x0, y0 + rh, e['left'])
        edge.call(x0 + rw, y0, x0 + rw, y0 + rh, e['right'])
        # dimensions: length under the front, depth to the right
        dy = y0 - 18
        page.line(x0, y0 - 4, x0, dy - 3, 0.55, 0.4)
        page.line(x0 + rw, y0 - 4, x0 + rw, dy - 3, 0.55, 0.4)
        page.line(x0, dy, x0 + rw, dy, 0, 0.5)
        [x0, x0 + rw].each { |x| page.line(x, dy - 2.5, x, dy + 2.5, 0, 0.5) }
        page.text(x0 + rw / 2 - Pdf.width("#{l.round}", 'F2', 9) / 2, dy - 10, "#{l.round}", font: 'F2', size: 9)
        dx = x0 + rw + 18
        page.line(x0 + rw + 4, y0, dx + 3, y0, 0.55, 0.4)
        page.line(x0 + rw + 4, y0 + rh, dx + 3, y0 + rh, 0.55, 0.4)
        page.line(dx, y0, dx, y0 + rh, 0, 0.5)
        [y0, y0 + rh].each { |y| page.line(dx - 2.5, y, dx + 2.5, y, 0, 0.5) }
        page.text(dx + 5, y0 + rh / 2 - 3, "#{d.round}", font: 'F2', size: 9)
        page.text(x0, y0 + rh + 8, "#{w['material']}  #{w['thickness']} mm", size: 8) if key
        page.text(x0 + rw / 2 - 10, y0 + 4, 'FRONT', size: 6.5) if rh > 24
        return unless key
        # key
        ky = by + 4
        page.line(bx, ky + 3, bx + 22, ky + 3, 0, 2.2)
        page.text(bx + 26, ky, 'profiled edge', size: 7)
        page.dashed(bx + 90, ky + 3, bx + 112, ky + 3, 0.2, 0.6, 3)
        page.text(bx + 116, ky, 'against a wall / not profiled', size: 7)
        pro = e.select { |_k, v| v }.keys.join(', ')
        page.text(bx + bw, ky, "Profile: #{pro}", size: 7, align: :right)
      end
    end
  end
end
