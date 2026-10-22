module HarryWardrobes
  module DoorStyle
    # Parts list PDF (A4 portrait) on the same small PDF writer as the door order.
    module PartsPdf
      W = Pdf::PAGE_W
      H = Pdf::PAGE_H
      M = Pdf::MARGIN
      ROW = Pdf::ROW_H

      class Doc
        attr_reader :pages

        def initialize(data)
          @data = data
          @pages = []
          new_page
        end

        def page = @pages.last

        def y = @y

        def new_page
          @pages << Pdf::Page.new
          @y = H - M - 10
          if @pages.size == 1
            page.text(M, @y - 2, 'Harry Wardrobes - Parts list', font: 'F2', size: 15)
            page.text(W - M, @y - 2, "Version v#{@data['list_version']}", font: 'F2', size: 12, align: :right)
            @y -= 18
            page.text(M, @y, Pdf.head_line(@data['head']), size: 9, max: W - 2 * M)
            @y -= 12
            page.text(M, @y, 'Doors and drawer fronts are on the door order', size: 9)
            @y -= 8
            page.line(M, @y, W - M, @y, 0.2, 1.2)
            @y -= 16
          end
        end

        def need(h)
          new_page if @y - h < M + 10
        end

        def heading(t, sub = nil)
          need(ROW * 3)
          page.text(M, @y, t, font: 'F2', size: 11)
          page.text(M + Pdf.width(Pdf.clean(t), 'F2', 11) + 8, @y, sub, size: 8.5) if sub
          @y -= ROW + 2
        end

        # cols: [[label, width or nil, :left/:right]]
        def table(cols, rows)
          ws = Pdf.fit_widths(cols.map { |c| c[1] }, W - 2 * M)
          cols = cols.each_with_index.map { |(l, _w, a), i| [l, ws[i], a] }
          head = lambda do
            page.rect_fill(M, @y - 4, W - 2 * M, ROW, 0.92)
            x = M
            cols.each { |l, w, a| page.text(a == :right ? x + w - 3 : x + 3, @y, l, font: 'F2', align: a, max: w - 6); x += w }
            @y -= ROW
          end
          need(ROW * 2)
          head.call
          rows.each do |r|
            if @y < M + 20
              new_page
              head.call
            end
            x = M
            cols.each_with_index do |(_, w, a), i|
              page.text(a == :right ? x + w - 3 : x + 3, @y, r[i].to_s, align: a, max: w - 6)
              x += w
            end
            page.line(M, @y - 4, W - M, @y - 4)
            @y -= ROW
          end
          @y -= 8
        end
      end

      def self.f(v) = PartsList.fmt(v)

      # The parts list: Timber (every board and length that isn't hardware - 18 mm by the
      # strip width it's cut from, other boards, Timber / MDF lengths, drawer boxes), then
      # Hardware (counted items and the handles). Worktops and the 22 mm panels are on the
      # Door / Vinyl order, not here.
      def self.layout(d)
        doc = Doc.new(d)
        unless d['scribes_on']
          doc.page.text(M, doc.y, 'Scribes are OFF (every runout 0) - panel sizes may be wrong.', font: 'F2', size: 9)
          doc.instance_variable_set(:@y, doc.y - ROW - 4)
        end
        part_cols = [['#', 26, :left], ['Name', nil, :left], ['Length', 48, :right], ['Width', 48, :right], ['Qty', 30, :right],
                     ['Edge L1', 84, :left], ['Edge L2', 84, :left], ['Edge W1', 84, :left], ['Edge W2', 84, :left]]
        row = ->(p) { [p['number'], p['name'], f(p['length']), f(p['width']), p['qty'], p['edges']['ymin'], p['edges']['ymax'], p['edges']['xmin'], p['edges']['xmax']] }

        doc.page.text(M, doc.y, 'TIMBER', font: 'F2', size: 13)
        doc.instance_variable_set(:@y, doc.y - ROW - 4)
        boards = d['groups'].reject { |g| %w[vinyl white_back worktops].include?(g['section']) }
        boards.each do |g|
          if g['strip_group']
            # 18 mm: by strip width - "90 mm strips: 3 x 2800" over the parts cut from them
            by_w = g['parts'].group_by { |p| p['strip_width'] }
            widths = by_w.keys.compact.sort
            doc.heading("#{g['material']} - #{f(g['thickness'])} mm", "#{g['count']} parts#{g['grained'] ? ', grained' : ''}, cut and edged strips #{f(g['strips'].sum { |st| st['count'] })} in all")
            widths.each do |w|
              st = Array(g['strips']).find { |x| x['width'] == w } || {}
              doc.heading("#{w} mm strips", "#{st['count']} x #{f(st['length'])} mm - #{by_w[w].sum { |p| p['qty'] }} pieces, packed end to end")
              doc.table(part_cols, by_w[w].map(&row))
            end
            unless (full = by_w[nil] || []).empty?
              doc.heading('Full sheet', "#{full.sum { |p| p['qty'] }} pieces wider than the widest strip#{g['sheets'] ? " - #{g['sheets']} sheet(s) #{g['sheet'] ? "#{f(g['sheet'][0])} x #{f(g['sheet'][1])}" : ''}" : ''}")
              doc.table(part_cols, full.map(&row))
            end
          else
            doc.heading("#{g['material']} - #{f(g['thickness'])} mm", "#{g['count']} parts#{g['grained'] ? ', grained' : ''}#{g['sheets'] ? ", #{g['sheets']} sheet(s)" : ''}")
            doc.table(part_cols, g['parts'].map(&row))
          end
        end
        tb = Array(d['timber_lines'])
        unless tb.empty?
          doc.heading('Timber / MDF', 'ordered as lengths (cut lengths from the model)')
          doc.table([['#', 40, :left], ['Name', nil, :left], ['Material', 120, :left], ['Section', 80, :right], ['Length', 60, :right], ['Qty', 40, :right]],
                    tb.map { |t| [t['numbers'].join(', '), t['name'], t['material'], t['section'], f(t['length']), t['qty']] })
        end
        boxes = Array(d['drawer_boxes'])
        unless boxes.empty?
          doc.heading('Drawer boxes', 'internal cabinet width; runners in pairs, one pair per box')
          doc.table([['#', 26, :left], ['Parent', 120, :left], ['Material', nil, :left], ['Int. cab width', 75, :right], ['Height', 50, :right], ['Runners', 130, :left], ['Qty', 30, :right]],
                    boxes.map { |b| [b['number'], b['parent'], b['material'], b['width'] ? "#{b['width']} mm" : '-', b['height'] ? "#{b['height']} mm#{b['warn'] ? ' (!)' : ''}" : '-', b['runner'], b['qty']] })
        end

        doc.need(ROW * 6)
        doc.instance_variable_set(:@y, doc.y - 6)
        doc.page.text(M, doc.y, 'HARDWARE', font: 'F2', size: 13)
        doc.instance_variable_set(:@y, doc.y - ROW - 4)
        hws = Array(d['hardware_lines'])
        unless hws.empty?
          doc.table([['#', 60, :left], ['Name', nil, :left], ['Qty', 40, :right]],
                    hws.map { |h| [h['numbers'].join(', '), h['name'], h['qty']] })
        end
        hl = Array(d['handles'])
        doc.heading('Handles', hl.empty? ? 'none on this job (n/a)' : 'from the Door style window')
        unless hl.empty?
          doc.table([['Kind', 100, :left], ['Handle', nil, :left], ['SKU', 110, :left], ['Supplier', 90, :left], ['Qty', 40, :right]],
                    hl.map { |h| [h['kind'], h['name'], h['sku'], h['supplier'], h['qty']] })
        end
        doc.pages.each_with_index do |p, i|
          p.text(M, M - 14, "HW Door Style v#{d['version']} - parts list rules from OpenCutList (L'Air du Bois, GPL-3.0)", size: 7)
          p.text(W - M, M - 14, "Page #{i + 1} of #{doc.pages.size}", size: 7, align: :right)
        end
        doc.pages.map(&:to_s)
      end

      def self.write(path, d)
        pages = layout(d)
        File.binwrite(path, Pdf.document(pages))
      end
    end
  end
end
