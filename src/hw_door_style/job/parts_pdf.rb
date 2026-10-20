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

      def self.sheets?(g) = g['section'].to_s.empty? || g['section'] == 'sheets'

      def self.layout(d)
        doc = Doc.new(d)
        unless d['scribes_on']
          doc.page.text(M, doc.y, 'Scribes are OFF (every runout 0) - panel sizes may be wrong.', font: 'F2', size: 9)
          doc.instance_variable_set(:@y, doc.y - ROW - 4)
        end
        # Boards: the sheet goods (18mm in strips, full sheets for the rest). Worktops, 22mm
        # panels, bullnose and MDF / timber lengths are ordered elsewhere.
        boards = d['groups'].select { |g| sheets?(g) }
        unless boards.empty?
          doc.heading('Boards', "18mm in cut and edged strips (next width up); full sheets for the rest. Other thicknesses: area + #{f(d['waste_pct'])}% waste")
          doc.table([['Material', nil, :left], ['Thickness', 60, :right], ['Full sheets for', 130, :left], ['Sheet', 90, :right], ['Full sheets', 60, :right]],
                    boards.map do |g|
                      why = g['strip_group'] ? Array(g['manual']).join(', ') : "#{format('%.2f', g['area_m2'])} m2"
                      [g['material'], "#{f(g['thickness'])} mm", why.empty? ? '-' : why,
                       g['sheet'] ? "#{f(g['sheet'][0])} x #{f(g['sheet'][1])}" : '-', g['sheets'].nil? ? 'ENTER' : g['sheets']]
                    end)
        end
        strips = d['groups'].flat_map { |g| Array(g['strips']).map { |st| [g, st] } }
        unless strips.empty?
          doc.heading('Cut + Edged', 'each part uses the next width up, packed end to end along the strip')
          doc.table([['Material', nil, :left], ['Thickness', 60, :right], ['Strip', 110, :right], ['Qty', 45, :right]],
                    strips.map { |g, st| [g['material'], "#{f(g['thickness'])} mm", "#{st['width']} x #{f(st['length'])}", st['count']] })
        end
        wt = d['groups'].select { |g| g['section'] == 'worktops' }
        unless wt.empty?
          doc.heading('Worktops', '22 / 25 mm worktops - ordered on their own, not in the MFC sheet count')
          doc.table([['Material', nil, :left], ['Thickness', 60, :right], ['Parts', 45, :right], ['Sheet', 90, :right], ['Sheets', 60, :right]],
                    wt.map { |g| [g['material'], "#{f(g['thickness'])} mm", g['count'], g['sheet'] ? "#{f(g['sheet'][0])} x #{f(g['sheet'][1])}" : '-', g['sheets'].nil? ? 'ENTER' : g['sheets']] })
        end
        d['groups'].each do |g|
          next if %w[vinyl white_back].include?(g['section']) # on the Door / Vinyl order
          doc.heading("#{g['material']} - #{f(g['thickness'])} mm#{g['section'] == 'worktops' ? ' (worktop)' : ''}", "#{g['count']} parts#{g['grained'] ? ', grained' : ''}#{g['std_ok'] ? '' : ', thickness not in the standard list'}")
          doc.table([['#', 26, :left], ['Name', nil, :left], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right],
                     ['Edge L1', 92, :left], ['Edge L2', 92, :left], ['Edge W1', 92, :left], ['Edge W2', 92, :left]],
                    g['parts'].map { |p| [p['number'], p['name'], f(p['length']), f(p['width']), p['qty'], p['edges']['ymin'], p['edges']['ymax'], p['edges']['xmin'], p['edges']['xmax']] })
        end
        unless d['edging'].empty?
          doc.heading('Edging', 'metres of tape (part lengths, no allowance)')
          doc.table([['Edge', nil, :left], ['Board thickness', 90, :right], ['Edges', 50, :right], ['Metres', 60, :right]],
                    d['edging'].map { |e| [e['material'], "#{f(e['height'])} mm", e['parts'], format('%.1f', e['metres'])] })
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
          doc.table([['#', 26, :left], ['Parent', 120, :left], ['Material', nil, :left], ['Int. cab width', 75, :right], ['Height', 50, :right], ['Runners', 170, :left], ['Qty', 30, :right]],
                    boxes.map { |b| [b['number'], b['parent'], b['material'], b['width'] ? "#{b['width']} mm" : '-', b['height'] ? "#{b['height']} mm#{b['warn'] ? ' (!)' : ''}" : '-', b['runner'], b['qty']] })
        end
        hws = Array(d['hardware_lines'])
        unless hws.empty?
          doc.heading('Hardware', 'counted from the model, one line per item')
          doc.table([['#', 60, :left], ['Name', nil, :left], ['Qty', 40, :right]],
                    hws.map { |h| [h['numbers'].join(', '), h['name'], h['qty']] })
        end
        unless d['handles'].empty?
          doc.heading('Handles', 'from the Door style window')
          doc.table([['Kind', 100, :left], ['Handle', nil, :left], ['SKU', 110, :left], ['Supplier', 90, :left], ['Qty', 40, :right]],
                    d['handles'].map { |h| [h['kind'], h['name'], h['sku'], h['supplier'], h['qty']] })
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
