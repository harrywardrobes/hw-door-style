module HarryWardrobes
  module DoorStyle
    # Minimal PDF writer for the door order (A4 landscape, Helvetica, multi-page table).
    # No external libraries, so it runs inside SketchUp's Ruby.
    module Pdf
      WIDTHS = {
        'F1' => [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584],
        'F2' => [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584]
      }.freeze

      PAGE_W = 842.0
      PAGE_H = 595.0
      MARGIN = 32.0
      SIZE   = 8.0
      ROW_H  = 13.0

      # key, label, width (pt), align
      COLUMNS = [
        ['n', '#', 22, :right], ['unit', 'Unit', 128, :left], ['item', 'Item', 105, :left],
        ['kind', 'Kind', 78, :left], ['width', 'W', 34, :right], ['height', 'H', 34, :right],
        ['style', 'Style', 46, :left], ['midrail', 'Mid-rail', 40, :left],
        ['hinge_type', 'Hinge type', 74, :left], ['hinges', 'Hinges', 34, :right],
        ['tip_on', 'TIP-ON', 34, :right], ['handles', 'Handles', 38, :right], ['notes', 'Notes', nil, :left]
      ].freeze

      def self.clean(s)
        s.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
         .gsub(/[–—]/, '-').gsub(/[‘’]/, "'").gsub(/[“”]/, '"').gsub("×", 'x')
         .gsub(/[^\x20-\x7E]/, '?')
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

      def self.columns
        used = COLUMNS.sum { |c| c[2].to_f }
        COLUMNS.map { |k, l, w, a| [k, l, w || (PAGE_W - 2 * MARGIN - used), a] }
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
        page.text(MARGIN, y, 'Harry Wardrobes - Door order', font: 'F2', size: 15)
        page.text(PAGE_W - MARGIN, y, "Version v#{data['export_version']}", font: 'F2', size: 12, align: :right)
        y -= 16
        meta = "Job: #{data['job']}   |   Hinge type: #{data['hinge_type']}   |   #{data['date']}"
        page.text(MARGIN, y, meta, size: 9)
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

      def self.layout(data)
        pages = []
        page = Page.new
        pages << page
        y = title_block(page, data)
        y = table_header(page, y)

        if data['rows'].empty?
          page.text(MARGIN, y, 'No doors or drawer fronts found.')
        end

        data['rows'].each do |r|
          if y < MARGIN + 20
            page = Page.new
            pages << page
            y = table_header(page, PAGE_H - MARGIN - 10)
          end
          x = MARGIN
          columns.each do |key, _l, w, align|
            v = r[key]
            v = '' if v.nil? || (v.is_a?(Integer) && v.zero? && %w[hinges tip_on handles].include?(key))
            tx = align == :right ? x + w - 3 : x + 3
            page.text(tx, y, v.to_s, align: align, max: w - 6)
            x += w
          end
          page.line(MARGIN, y - 4, PAGE_W - MARGIN, y - 4)
          y -= ROW_H
        end

        # Door elevation, a page per wall (DoorView).
        walls = Array(data['elevation'])
        walls.each do |w|
          pg = Page.new
          pg.text(MARGIN, PAGE_H - MARGIN - 12, "Harry Wardrobes - #{DoorView.title(w, walls.size > 1)}", font: 'F2', size: 15)
          pg.text(PAGE_W - MARGIN, PAGE_H - MARGIN - 12, "Job: #{data['job']}   |   v#{data['export_version']}", size: 9, align: :right)
          DoorView.draw_pdf(pg, w, MARGIN, MARGIN + 6, PAGE_W - 2 * MARGIN, PAGE_H - 2 * MARGIN - 34)
          pages << pg
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
      def self.document(pages, images: {})
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
          objs << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_W.to_i} #{PAGE_H.to_i}] " \
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
