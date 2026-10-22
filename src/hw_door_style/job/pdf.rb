module HarryWardrobes
  module DoorStyle
    # Minimal PDF writer for the door order (A4 portrait, Helvetica, multi-page table).
    # No external libraries, so it runs inside SketchUp's Ruby.
    module Pdf
      WIDTHS = {
        'F1' => [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584],
        'F2' => [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584]
      }.freeze

      # A4 portrait - every HW PDF (door order, parts list, Room Plan) is upright.
      PAGE_W = 595.0
      PAGE_H = 842.0
      MARGIN = 28.0
      SIZE   = 8.0
      ROW_H  = 13.0

      # The order lines: key, label, width (pt), align (Details is the flexible one).
      COLUMNS = [
        ['type', 'Type', 112, :left], ['size', 'Size', 68, :left],
        ['thumb', '', 44, :left], ['details', 'Details', nil, :left], ['drilling', 'Drilling', 52, :left], ['pods', 'Pods', 74, :left]
      ].freeze
      LINE_H = 9.5

      def self.clean(s)
        s.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
         .gsub(/[–—]/, '-').gsub(/[‘’]/, "'").gsub(/[“”]/, '"').gsub("×", 'x')
         .gsub('°', '').gsub(/[^\x20-\x7E]/, '?')
      end

      def self.width(s, font, size)
        s.each_char.sum { |c| WIDTHS[font][c.ord - 32] || 556 } * size / 1000.0
      end

      def self.fit(s, font, size, max)
        s = clean(s)
        return s if width(s, font, size) <= max
        s = s[0..-2] while !s.empty? && width(s + '...', font, size) > max
        s + '...'
      end

      def self.esc(s)
        s.gsub(/[\\()]/) { |c| "\\#{c}" }
      end

      class Page
        attr_reader :ops

        def initialize
          @ops = []
        end

        def text(x, y, str, font: 'F1', size: SIZE, align: :left, max: nil)
          s = max ? Pdf.fit(str, font, size, max) : Pdf.clean(str)
          x -= Pdf.width(s, font, size) if align == :right
          @ops << format('BT /%s %.1f Tf %.2f %.2f Td (%s) Tj ET', font, size, x, y, Pdf.esc(s))
        end

        def rect_fill(x, y, w, h, gray)
          @ops << format('%.2f g %.2f %.2f %.2f %.2f re f 0 g', gray, x, y, w, h)
        end

        def line(x1, y1, x2, y2, gray = 0.8, w = 0.5)
          @ops << format('%.2f G %.2f w %.2f %.2f m %.2f %.2f l S 0 G', gray, w, x1, y1, x2, y2)
        end

        def rect(x, y, w, h, gray = 0, lw = 0.6)
          @ops << format('%.2f G %.2f w %.2f %.2f %.2f %.2f re S 0 G', gray, lw, x, y, w, h)
        end

        # A dashed line (dash / gap in points).
        def dashed(x1, y1, x2, y2, gray = 0, w = 0.5, dash = 3)
          @ops << format('%.2f G %.2f w [%.1f %.1f] 0 d %.2f %.2f m %.2f %.2f l S [] 0 d 0 G', gray, w, dash, dash, x1, y1, x2, y2)
        end

        # A JPEG (Pdf.jpeg) drawn at x, y (bottom-left), w x h points.
        def image(name, x, y, w, h)
          @ops << format('q %.2f 0 0 %.2f %.2f %.2f cm /%s Do Q', w, h, x, y, name)
        end

        def to_s
          @ops.join("\n")
        end
      end

      # { 'bytes', 'w', 'h' } for a baseline / progressive JPEG file (size read from its SOF).
      def self.jpeg(path)
        b = File.binread(path)
        i = 2
        while i < b.bytesize
          i += 1 while b.getbyte(i) == 0xFF && b.getbyte(i + 1) == 0xFF
          marker = b.getbyte(i + 1)
          len = (b.getbyte(i + 2) << 8) | b.getbyte(i + 3)
          if [0xC0, 0xC1, 0xC2].include?(marker)
            h = (b.getbyte(i + 5) << 8) | b.getbyte(i + 6)
            w = (b.getbyte(i + 7) << 8) | b.getbyte(i + 8)
            return { 'bytes' => b, 'w' => w, 'h' => h }
          end
          i += 2 + len
        end
        raise "#{File.basename(path)}: not a JPEG"
      end

      # Column widths fitted to the page: fixed widths shrink together when they don't leave
      # the flexible (nil) columns at least min_flex each.
      def self.fit_widths(widths, total, min_flex = 90)
        fixed = widths.compact.sum.to_f
        flex = widths.count(nil)
        room = total - min_flex * flex
        k = fixed > room && fixed.positive? ? room / fixed : 1.0
        ws = widths.map { |w| w && w * k }
        free = (total - ws.compact.sum) / [flex, 1].max
        ws.map { |w| w || free }
      end

      # "Customer: WILLIAMS, Rebecca   |   Room: ...   |   Drawing: X...   |   Account: HW..." (RoomPlan.head).
      def self.head_line(hd)
        hd ||= {}
        [['Customer', hd['customer']], ['Room', hd['room']], ['Drawing', hd['drawing']], ['Account', hd['account']]]
          .map { |k, v| "#{k}: #{v.to_s.empty? ? '-' : v}" }.join('   |   ')
      end

      def self.columns
        ws = fit_widths(COLUMNS.map { |c| c[2] }, PAGE_W - 2 * MARGIN, 70)
        COLUMNS.each_with_index.map { |(k, l, _w, a), i| [k, l, ws[i], a] }
      end

      def self.table_header(page, y)
        x = MARGIN
        page.rect_fill(MARGIN, y - 4, PAGE_W - 2 * MARGIN, ROW_H, 0.92)
        columns.each do |_k, label, w, align|
          tx = align == :right ? x + w - 3 : x + 3
          page.text(tx, y, label, font: 'F2', align: align, max: w - 6)
          x += w
        end
        y - ROW_H
      end

      def self.title_block(page, data)
        y = PAGE_H - MARGIN - 12
        page.text(MARGIN, y, 'Harry Wardrobes - Door / Vinyl Order', font: 'F2', size: 15)
        page.text(PAGE_W - MARGIN, y, "Version v#{data['export_version']}", font: 'F2', size: 12, align: :right)
        y -= 16
        page.text(MARGIN, y, head_line(data['head']), size: 9, max: PAGE_W - 2 * MARGIN)
        y -= 12
        meta = "Colour: #{data['colour']}   |   Hinges: #{data['hinge_type']}   |   Heights are the door height; hole positions are hinge centres"
        page.text(MARGIN, y, meta, size: 9)
        key = Array(data['hinge_key'])
        unless key.empty?
          y -= 12
          page.text(MARGIN, y, 'Different hinges (shaded):', font: 'F2', size: 9)
          x = MARGIN + Pdf.width('Different hinges (shaded):', 'F2', 9) + 8
          key.each do |mark, type, shade|
            label = "#{mark} #{type}"
            wdt = Pdf.width(label, 'F2', 9) + 8
            page.rect_fill(x - 3, y - 3, wdt, 12, shade)
            page.text(x + 1, y, label, font: 'F2', size: 9)
            x += wdt + 6
          end
        end
        y -= 8
        page.line(MARGIN, y, PAGE_W - MARGIN, y, 0.2, 1.2)
        y -= 16

        t = data['totals']
        blocks = [
          ['Items by style', t['by_style'].map { |k, v| [k, v] }],
          ['Hinges', t['hinges'].map { |k, v| [k, v] }],
          ['Totals', [['Items', t['items']], ['TIP-ON', t['tip_on']], ['Handles / knobs', t['handles']]]]
        ]
        bw = (PAGE_W - 2 * MARGIN) / 3.0
        tallest = 0
        blocks.each_with_index do |(title, pairs), i|
          bx = MARGIN + i * bw
          by = y
          page.text(bx, by, title.upcase, font: 'F2', size: 7.5)
          by -= 11
          pairs.each do |k, v|
            page.text(bx, by, k.to_s, size: 8.5, max: bw - 60)
            page.text(bx + bw - 24, by, v.to_s, font: 'F2', size: 8.5, align: :right)
            by -= 11
          end
          tallest = [tallest, y - by].max
        end
        y - tallest - 10
      end

      # The lines of the Details column - everything the supplier asks for.
      def self.details(l, data)
        out = ["Style: #{l['style']}. Colour: #{data['colour']}"]
        out << "Component: #{l['kind']}#{l['midrail_mm'].to_i.positive? ? ' with centre rail' : ''}"
        out << "Height: #{l['height']}mm. Width: #{l['width']}mm"
        out << "Stile: #{l['stile_mm']}mm. Rail: #{l['rail_mm']}mm" if l['stile_mm'].to_i.positive?
        out << "Centre rail from door bottom: #{l['midrail_mm']}mm (#{l['midrail_w']}mm wide)" if l['midrail_mm'].to_i.positive?
        if l['hinges'].to_i.positive?
          out << "Drilled: #{l['hand'] == 'RH' ? 'Right' : 'Left'}. #{l['hinges']} hinge holes - #{l['hinge_type'].to_s.sub('Soft Close', 'SC')}#{l['tip_on'].to_i.positive? ? ", #{l['tip_on']} TIP-ON" : ''}"
          Report.hole_lines(l['holes'], l['height']).each { |h| out << h }
        elsif l['tip_on'].to_i.positive?
          out << "#{l['tip_on']} TIP-ON"
        end
        out << "Handles: #{l['handles']}" if l['handles'].to_i.positive?
        out << "Note: #{l['notes']}" unless l['notes'].to_s.empty?
        out
      end

      # A small front-on picture of the front: its frame (stile / rail), centre rail and
      # the hinge holes on the hinged side.
      def self.thumbnail(page, l, bx, by, bw, bh)
        w = l['width'].to_f
        h = l['height'].to_f
        return if w <= 0 || h <= 0
        s = [bw / w, bh / h].min
        rw = w * s
        rh = h * s
        x = bx + (bw - rw) / 2
        y = by + (bh - rh) / 2
        page.rect(x, y, rw, rh, 0, 0.7)
        st = l['stile_mm'].to_f * s
        ra = l['rail_mm'].to_f * s
        page.rect(x + st, y + ra, rw - 2 * st, rh - 2 * ra, 0.45, 0.4) if st.positive? && rw > 2 * st + 2 && rh > 2 * ra + 2
        if l['midrail_mm'].to_f.positive?
          mz = y + l['midrail_mm'].to_f * s
          mw = l['midrail_w'].to_f * s / 2
          page.rect_fill(x + st, mz - mw, rw - 2 * st, 2 * mw, 0.75) if mw.positive?
        end
        Array(l['holes']).each do |z|
          hx = l['hand'] == 'RH' ? x + rw - 2.2 : x + 2.2
          page.rect_fill(hx - 1.1, y + z * s - 1.1, 2.2, 2.2, 0)
        end
      end

      def self.layout(data)
        pages = []
        page = Page.new
        pages << page
        y = title_block(page, data)
        y = table_header(page, y)

        lines = Array(data['lines'])
        page.text(MARGIN, y, 'No doors or drawer fronts found.') if lines.empty?

        lines.each do |l|
          det = details(l, data)
          rh = [det.size * LINE_H + 14, 34].max
          if y - rh < MARGIN + 10
            page = Page.new
            pages << page
            y = table_header(page, PAGE_H - MARGIN - 10)
          end
          x = MARGIN
          columns.each do |key, _lab, w, align|
            tx = align == :right ? x + w - 3 : x + 3
            case key
            when 'type' then page.text(tx, y, "#{l['qty']} x #{l['kind']}", font: 'F2', size: 9, max: w - 6)
            when 'size' then page.text(tx, y, "#{l['height']} x #{l['width']}mm", max: w - 6)
            when 'thumb' then thumbnail(page, l, x + 4, y - rh + 10, w - 8, rh - 10)
            when 'details'
              det.each_with_index do |t, i|
                if l['hinge_mark'] && t.start_with?('Drilled')
                  t = "#{l['hinge_mark']} #{t}"
                  page.rect_fill(tx - 2, y - i * LINE_H - 3, [Pdf.width(Pdf.clean(t), 'F2', SIZE) + 4, w - 2].min, LINE_H, l['hinge_shade'])
                  page.text(tx, y - i * LINE_H, t, font: 'F2', max: w - 6)
                else
                  page.text(tx, y - i * LINE_H, t, max: w - 6)
                end
              end
            when 'drilling' then page.text(tx, y, l['hinges'].to_i.positive? ? "#{l['hand'] == 'RH' ? 'Right' : 'Left'} (#{l['hinges']})" : '-', max: w - 6)
            when 'pods'
              Array(l['pods']).each_slice(2).with_index { |ps, i| page.text(tx, y - i * LINE_H, ps.join(', '), size: 7.5, max: w - 6) }
            end
            x += w
          end
          page.line(MARGIN, y - rh + 8, PAGE_W - MARGIN, y - rh + 8)
          y -= rh
        end

        # 22mm (white back) panels and bullnose / cornice: ordered with the doors.
        Array(data['vinyl']).each do |sec|
          next if sec['rows'].empty?
          if y < MARGIN + 60
            page = Page.new
            pages << page
            y = PAGE_H - MARGIN - 10
          end
          y -= 10
          page.text(MARGIN, y, sec['title'], font: 'F2', size: 11)
          page.text(MARGIN + Pdf.width(sec['title'], 'F2', 11) + 8, y, sec['note'].to_s, size: 8.5)
          y -= ROW_H + 2
          cols = sec['cols']
          ws = fit_widths(cols.map { |c| c[1] }, PAGE_W - 2 * MARGIN)
          head = lambda do
            page.rect_fill(MARGIN, y - 4, PAGE_W - 2 * MARGIN, ROW_H, 0.92)
            x = MARGIN
            cols.each_with_index { |(l, _w, a), i| page.text(a == :right ? x + ws[i] - 3 : x + 3, y, l, font: 'F2', align: a, max: ws[i] - 6); x += ws[i] }
            y -= ROW_H
          end
          head.call
          sec['rows'].each do |r|
            if y < MARGIN + 20
              page = Page.new
              pages << page
              y = PAGE_H - MARGIN - 10
              head.call
            end
            x = MARGIN
            cols.each_with_index { |(_l, _w, a), i| page.text(a == :right ? x + ws[i] - 3 : x + 3, y, r[i].to_s, align: a, max: ws[i] - 6); x += ws[i] }
            page.line(MARGIN, y - 4, PAGE_W - MARGIN, y - 4)
            y -= ROW_H
          end
        end

        # Drawings: door elevations (one per wall), two to a page, stacked.
        walls = Array(data['elevation'])
        walls.each_slice(2) do |pair|
          pg = Page.new
          pg.text(PAGE_W - MARGIN, PAGE_H - MARGIN - 12, "v#{data['export_version']}", size: 9, align: :right)
          pg.text(MARGIN, PAGE_H - MARGIN - 26, head_line(data['head']), size: 8, max: PAGE_W - 2 * MARGIN)
          box_h = (PAGE_H - 2 * MARGIN - 34) / pair.size
          pair.each_with_index do |w, i|
            top = PAGE_H - MARGIN - 34 - i * box_h
            pg.text(MARGIN, top - (i.zero? ? -22 : 14), "Harry Wardrobes - #{DoorView.title(w, walls.size > 1)}", font: 'F2', size: i.zero? ? 15 : 12)
            pg.line(MARGIN, top, PAGE_W - MARGIN, top, 0.7, 0.5) if i.positive?
            DoorView.draw_pdf(pg, w, MARGIN, top - box_h + 6, PAGE_W - 2 * MARGIN, box_h - (i.zero? ? 6 : 26))
          end
          pages << pg
        end

        # Worktop order: its own page(s) - a small drawing at the left, the details beside it.
        tops = Array(data['worktops'])
        unless tops.empty?
          pg = nil
          y = 0
          row_h = 118
          new_top_page = lambda do
            pg = Page.new
            pages << pg
            pg.text(MARGIN, PAGE_H - MARGIN - 12, 'Harry Wardrobes - Worktop Order', font: 'F2', size: 15)
            pg.text(PAGE_W - MARGIN, PAGE_H - MARGIN - 12, "v#{data['export_version']}", size: 9, align: :right)
            pg.text(MARGIN, PAGE_H - MARGIN - 28, head_line(data['head']), size: 9, max: PAGE_W - 2 * MARGIN)
            pg.text(MARGIN, PAGE_H - MARGIN - 40, "#{tops.size} worktop(s). Solid line = profiled edge, dashed = against a wall / not profiled. Sizes in mm.", size: 8.5)
            pg.line(MARGIN, PAGE_H - MARGIN - 46, PAGE_W - MARGIN, PAGE_H - MARGIN - 46, 0.2, 1.2)
            y = PAGE_H - MARGIN - 52
          end
          new_top_page.call
          tops.each_with_index do |w, i|
            new_top_page.call if y - row_h < MARGIN + 10
            tw = 230
            WorktopView.draw_pdf(pg, w, MARGIN, y - row_h + 6, tw, row_h - 12, key: false)
            tx = MARGIN + tw + 16
            ty = y - 14
            pg.text(tx, ty, "#{i + 1}. #{w['pod'].to_s.empty? ? '' : "#{w['pod']} - "}#{w['name']}", font: 'F2', size: 11)
            e = w['edges'] || {}
            pro = e.select { |_k, v| v }.keys.join(', ')
            [["Size", "#{w['length']} x #{w['depth']} x #{w['thickness']}mm (length x depth x thickness)"],
             ["Colour", w['material'].to_s], ["Profiled edges", pro.empty? ? 'none' : pro],
             ["Plain edges", e.reject { |_k, v| v }.keys.join(', ').then { |t| t.empty? ? 'none' : t }],
             ["Qty", '1']].each_with_index do |(k, v), j|
              pg.text(tx, ty - 16 - j * 12, "#{k}:", font: 'F2', size: 8.5)
              pg.text(tx + 70, ty - 16 - j * 12, v, size: 8.5, max: PAGE_W - MARGIN - tx - 70)
            end
            pg.line(MARGIN, y - row_h + 2, PAGE_W - MARGIN, y - row_h + 2)
            y -= row_h
          end
        end

        pages.each_with_index do |p, i|
          p.text(MARGIN, MARGIN - 14, "HW Door Style v#{data['version']}", size: 7)
          p.text(MARGIN + 80, MARGIN - 14, data['key'].to_s, size: 7, max: PAGE_W - 2 * MARGIN - 160) unless data['key'].to_s.empty?
          p.text(PAGE_W - MARGIN, MARGIN - 14, "Page #{i + 1} of #{pages.size}", size: 7, align: :right)
        end
        pages.map(&:to_s)
      end

      def self.render(data)
        document(layout(data))
      end

      # Page content streams -> PDF bytes.
      # images: { 'Im1' => Pdf.jpeg(path) } - drawn with Page#image.
      # sizes: [[w, h] or nil per page] - nil is A4 portrait (a landscape page is [PAGE_H, PAGE_W]).
      def self.document(pages, images: {}, sizes: [])
        objs = []
        objs << '<< /Type /Catalog /Pages 2 0 R >>'
        first_img = 5 + pages.size * 2
        kids = pages.each_index.map { |i| "#{5 + i * 2} 0 R" }
        objs << "<< /Type /Pages /Kids [#{kids.join(' ')}] /Count #{pages.size} >>"
        objs << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
        objs << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'
        xo = images.keys.each_with_index.map { |n, k| "/#{n} #{first_img + k} 0 R" }.join(' ')
        res = "/Font << /F1 3 0 R /F2 4 0 R >>#{xo.empty? ? '' : " /XObject << #{xo} >>"}"
        pages.each_with_index do |c, i|
          pw, ph = sizes[i] || [PAGE_W, PAGE_H]
          objs << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{pw.to_i} #{ph.to_i}] " \
                  "/Resources << #{res} >> /Contents #{6 + i * 2} 0 R >>"
          objs << "<< /Length #{c.bytesize} >>\nstream\n#{c}\nendstream"
        end
        images.each_value do |im|
          objs << ("<< /Type /XObject /Subtype /Image /Width #{im['w']} /Height #{im['h']} /ColorSpace /DeviceRGB " \
                   "/BitsPerComponent 8 /Filter /DCTDecode /Length #{im['bytes'].bytesize} >>\nstream\n".b + im['bytes'].b + "\nendstream".b)
        end

        out = String.new("%PDF-1.4\n", encoding: Encoding::BINARY)
        offsets = []
        objs.each_with_index do |o, i|
          offsets << out.bytesize
          out << "#{i + 1} 0 obj\n".b << o.b << "\nendobj\n".b
        end
        xref = out.bytesize
        out << "xref\n0 #{objs.size + 1}\n0000000000 65535 f \n".b
        offsets.each { |off| out << format("%010d 00000 n \n", off).b }
        out << "trailer\n<< /Size #{objs.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
        out
      end

      def self.write(path, data)
        File.binwrite(path, render(data))
      end
    end
  end
end
