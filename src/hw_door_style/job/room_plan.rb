require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Room Plan: one PDF for the fitters and the workshop - ROOM_PLAN_v<N>_<file>.pdf.
    #
    #   1 Cover / Specification  customer, colours, doors, hinges, handles, ceiling, depths, scribes
    #   2 Product List           every ref (T / W / B / M) - loose items first - with doors and interior
    #   3 Installation Plan      the plan scene, notes, T numbers, and the fitting footer
    #   3b Door elevation        the doors and drawer fronts on each wall, with sizes (DoorView)
    #   4 Pod Sheet              the parts in each ref
    #   5 Panel list             MDF / Timber / Cut / Worktop / Facing
    #
    # Every page has the header: customer, drawing X<room id>, account HW<contact id>,
    # fit week (the Room's "Fit week" in HubSpot), room, date, page n of N.
    module RoomPlan
      W = Pdf::PAGE_W
      H = Pdf::PAGE_H
      M = Pdf::MARGIN
      ROW = Pdf::ROW_H
      LOOSE_FIRST = %w[M T W B L F].freeze
      PANEL_TYPES = %w[MDF Timber Cut Worktop Facing].freeze

      # Pages with the Room Plan header.
      class Doc < PartsPdf::Doc
        def initialize(head)
          @head = head
          @title = ''
          super({})
        end

        def section(title)
          @title = title
          @pages.size == 1 && @fresh ? redo_header : new_page
          @fresh = false
        end

        def new_page
          @pages << Pdf::Page.new
          header
        end

        def start
          @fresh = true
        end

        private

        def redo_header
          @pages[-1] = Pdf::Page.new
          header
        end

        def header
          hd = @head
          top = H - M - 6
          page.text(M, top, 'Harry Wardrobes - Room Plan', font: 'F2', size: 14)
          page.text(M, top - 15, @title, font: 'F2', size: 11)
          right = [["Customer", hd['customer']], ['Room', hd['room']], ['Drawing', hd['drawing']],
                   ['Account', hd['account']], ['Fit week', hd['fit_week']], ['Date', hd['date']]]
          right.each_slice(3).with_index do |col, ci|
            x = W - M - 300 + ci * 150
            col.each_with_index do |(k, v), i|
              page.text(x, top - i * 10, "#{k}:", font: 'F2', size: 7.5)
              page.text(x + 42, top - i * 10, v.to_s.empty? ? '-' : v.to_s, size: 7.5, max: 104)
            end
          end
          @y = top - 32
          page.line(M, @y, W - M, @y, 0.2, 1.2)
          @y -= 16
        end
      end

      def self.f(v) = PartsList.fmt(v)

      # --- the facts on every page --------------------------------------------------------

      def self.fit_week(room_id)
        return nil if room_id.to_s.empty? || !HubSpot.key?
        v = (HubSpot.read_one('listings', room_id, ['fit_week'])['properties'] || {})['fit_week']
        v.to_s.empty? ? nil : "Week #{v.to_f.round}"
      rescue StandardError => e
        Log.error('room plan fit week', e)
        nil
      end

      def self.head(model, fit = :fetch)
        l = HubSpotRoom.link(model) || {}
        customer = l['customer'].to_s
        customer = [l['first_name'], l['last_name']].compact.join(' ') if customer.strip.empty?
        { 'customer' => customer.strip.empty? ? File.basename(model.path.to_s, '.skp') : customer,
          'address' => l['address'].to_s,
          'room' => l['room_name'].to_s,
          'drawing' => l['room_id'].to_s.empty? ? '' : "X#{l['room_id']}",
          'account' => l['contact_id'].to_s.empty? ? '' : "HW#{l['contact_id']}",
          'fit_week' => fit == :fetch ? fit_week(l['room_id']) : fit,
          'date' => Time.now.strftime('%d/%m/%Y') }
      end

      # --- what is in each ref -------------------------------------------------------------

      # Every part / hardware piece, and door row, counted per ref (T1...).
      def self.by_ref(parts, doors, tops)
        out = Hash.new { |h, k| h[k] = { 'parts' => Hash.new(0), 'hardware' => Hash.new(0), 'doors' => [] } }
        parts['groups'].each do |g|
          g['parts'].each do |p|
            Array(p['instances']).each do |i|
              t = tops[i['top']] or next
              out[t]['parts'][[p['number'], p['name'], g['material'], p['length'], p['width'], p['thickness']]] += 1
            end
          end
        end
        parts['hardware'].each do |h|
          Array(h['instances']).each do |i|
            t = tops[i['top']] or next
            out[t]['hardware'][[h['number'], h['name'], h['material']]] += 1
          end
        end
        doors.each { |d| (t = tops[d['top_id']]) && out[t]['doors'] << d }
        out
      end

      def self.door_text(list)
        doors = list.select { |d| d['kind_id'] == 'door' }
        return '' if doors.empty?
        fixed, doors = doors.partition { |d| d['kind'] == 'Stable Panel' }
        out = doors.group_by { |d| [d['style'], d['height'], d['hinge_type']] }.map do |(style, h, hinge), ds|
          hands = ds.map { |d| d['hand'].to_s }.reject(&:empty?).tally.map { |k, n| n > 1 ? "#{n} #{k}" : k }.join(' + ')
          t = "#{ds.size} x #{style} #{h} high#{hands.empty? ? '' : " (#{hands})"}"
          t += ' - 155 HINGES' if hinge.to_s.include?('155')
          t
        end
        out += fixed.map { |d| "stable panel #{d['width']} x #{d['height']} (fixed)" }
        out.join('; ')
      end

      def self.interior_text(info)
        c = Hash.new(0)
        info['parts'].each { |(_, name, *), q| c['shelf'] += q if name =~ /SHELF/i && name !~ /BOX/i }
        info['hardware'].each { |(_, name, _), q| c['rail'] += q if name =~ /RAIL|HANG/i }
        info['doors'].each { |d| c['ext'] += 1 if d['kind_id'] == 'ext_drawer'; c['int'] += 1 if d['kind_id'] == 'int_drawer' }
        [[c['shelf'], 'shelf', 'shelves'], [c['rail'], 'hanging rail', 'hanging rails'],
         [c['ext'], 'drawer', 'drawers'], [c['int'], 'internal drawer', 'internal drawers']]
          .select { |n, *| n.positive? }.map { |n, one, many| "#{n} #{n == 1 ? one : many}" }.join(', ')
      end

      def self.describe(r)
        d = r['depth'] ? " (#{r['depth']} deep#{r['finished'] ? " / #{r['finished']} overall" : ''})" : ''
        "#{r['size'][0]} #{r['type']}#{d}"
      end

      # MDF / Timber / Cut / Worktop / Facing.
      def self.panel_type(g, p)
        return 'Worktop' if g['section'] == 'worktops'
        return 'Facing' if p['name'] =~ /FACING/i
        return 'Timber' if g['material'] =~ /TIMBER|2X1|PINE/i
        return 'MDF' if g['material'] =~ /MDF/i
        'Cut'
      end

      # --- pages ---------------------------------------------------------------------------

      def self.spec_page(doc, model, hd, rows, doors, parts)
        doc.section('Cover / Specification')
        pg = doc.page
        y = doc.y
        kv = lambda do |k, v|
          pg.text(M, y, k, font: 'F2', size: 9)
          pg.text(M + 150, y, v.to_s.empty? ? '-' : v.to_s, size: 9, max: W - 2 * M - 150)
          pg.line(M, y - 4, W - M, y - 4)
          y -= ROW + 2
        end
        kv.call('Customer', hd['customer'])
        kv.call('Address', hd['address'])
        kv.call('Room', hd['room'])
        kv.call('Drawing / Account', "#{hd['drawing']}   #{hd['account']}")
        kv.call('Fit week', hd['fit_week'])
        y -= 8
        Colours::GROUPS.each { |id, label| (v = Colours.job_choices(model)[id]) && kv.call(label, v) }
        st = DoorStyleWindow.job_styles(model)
        kv.call('Door style', "Doors #{Styles.label(st['door'])}, drawer fronts #{Styles.label(st['ext_drawer'])}")
        kv.call('Hinges', Settings::HINGE_TYPES[Settings.job_hinge_type(model)])
        PartsList.handles(model).each { |h| kv.call(h['kind'], "#{h['name']}#{h['sku'].empty? ? '' : " (#{h['sku']})"} x #{h['qty']}") }
        y -= 8
        c = Ceiling.mm(model)
        kv.call('Ceiling height', c.positive? ? "#{c.round} mm" : 'not set')
        (fa = Plan.top_fascia(model)) && kv.call('Top fascia', "#{fa} mm")
        dj = Depth.job_values(model)
        kv.call('Depth', "Standard #{dj['standard'].round} mm, bridge / worktop #{dj['short'].round} mm (back wall to back of facing)")
        kv.call('Scribes', scribes(model))
        kv.call('Products', rows.group_by { |r| r['ref'] }.map { |k, v| "#{v.size} #{k}" }.join(', '))
        kv.call('Doors / drawer fronts', "#{doors.count { |d| d['kind_id'] == 'door' }} doors, #{doors.count { |d| d['kind_id'] == 'ext_drawer' }} drawer fronts, #{doors.count { |d| d['kind_id'] == 'int_drawer' }} internal drawers")
        kv.call('Cornice', cornice(parts))
        doc.instance_variable_set(:@y, y)
      end

      def self.scribes(model)
        return 'OFF (all 0)' unless Pencil.on?(model)
        v = Runouts.job_values(model)
        "L #{v['left'].round}  R #{v['right'].round}  F #{v['floor'].round}  C #{v['ceiling'].round}  Back #{v['back'].round}"
      end

      def self.cornice(parts)
        cs = parts['groups'].select { |g| g['section'] == 'vinyl' }.flat_map { |g| g['parts'].select { |p| p['name'] =~ /CORNICE/i } }
        cs.empty? ? 'None' : "#{cs.sum { |p| p['qty'] }} length(s), #{cs.map { |p| f(p['length']) }.uniq.join(' / ')} mm"
      end

      def self.product_page(doc, rows, info)
        doc.section('Product List')
        list = rows.sort_by { |r| [LOOSE_FIRST.index(r['ref']) || 9, r['num']] }
        doc.table([['Ref', 34, :left], ['Unit', 210, :left], ['Doors', nil, :left], ['Interior', 190, :left]],
                  list.map { |r| [r['t'], describe(r), door_text(info[r['t']]['doors']), interior_text(info[r['t']])] })
      end

      def self.plan_page(doc, model, hd, images)
        doc.section('Installation Plan')
        pg = doc.page
        foot = M + 30
        if Plan.plan_page(model)
          jpg = File.join(Dir.tmpdir, "hw_room_plan_#{Process.pid}.jpg")
          Plan.picture(model, jpg)
          im = Pdf.jpeg(jpg)
          File.delete(jpg) rescue nil
          images['Im1'] = im
          box_w = W - 2 * M
          box_h = doc.y - foot - 6
          s = [box_w / im['w'], box_h / im['h']].min
          pg.image('Im1', M + (box_w - im['w'] * s) / 2, foot + 4 + (box_h - im['h'] * s) / 2, im['w'] * s, im['h'] * s)
        else
          pg.text(M, doc.y, 'No plan scene in this model - add a scene named "top" or "plan" to show the installation plan here.', font: 'F2', size: 10)
        end
        c = Ceiling.mm(model)
        items = [['Client', hd['customer']], ['Account', hd['account']], ['Drawing', hd['drawing']],
                 ['Main ceiling', c.positive? ? "#{c.round} mm" : '-'], ['Scribe set', scribes(model)], ['Cornice', @cornice]]
        pg.line(M, foot + 2, W - M, foot + 2, 0.2, 1)
        x = M
        widths = [130, 80, 80, 80, 230, nil]
        items.each_with_index do |(k, v), i|
          w = widths[i] || (W - M - x)
          pg.text(x, foot - 10, k, font: 'F2', size: 7.5)
          pg.text(x, foot - 21, v.to_s.empty? ? '-' : v.to_s, size: 8, max: w - 6)
          x += w
        end
      end

      # Door elevation, a page per wall.
      def self.door_pages(doc, model)
        walls = DoorView.walls(model)
        walls.each do |w|
          doc.section(DoorView.title(w, walls.size > 1))
          DoorView.draw_pdf(doc.page, w, M, M + 6, W - 2 * M, doc.y - M - 6)
        end
      rescue StandardError => e
        Log.error('room plan door elevation', e)
      end

      def self.pod_page(doc, rows, info)
        doc.section('Pod Sheet')
        rows.sort_by { |r| [LOOSE_FIRST.index(r['ref']) || 9, r['num']] }.each do |r|
          i = info[r['t']]
          doc.heading("#{r['t']}  #{describe(r)}")
          lines = i['parts'].map { |(n, name, mat, l, w, th), q| [n, name, mat, "#{f(l)} x #{f(w)} x #{f(th)}", q] }
          lines += i['hardware'].map { |(n, name, mat), q| [n, name, mat, 'hardware', q] }
          lines += i['doors'].map { |d| ['', "#{d['kind']} #{d['item']}", d['style'], "#{d['width']} x #{d['height']}", 1] }
          if lines.empty?
            doc.need(ROW)
            doc.page.text(M, doc.y, 'No parts found for this ref.', size: 8)
            doc.instance_variable_set(:@y, doc.y - ROW - 4)
          else
            doc.table([['#', 30, :left], ['Part', nil, :left], ['Material', 170, :left], ['Size (mm)', 130, :right], ['Qty', 34, :right]], lines.sort_by { |a| [a[0].to_s.empty? ? 1 : 0, a[0].to_i, a[0].to_s] })
          end
        end
      end

      def self.panel_page(doc, parts, tops)
        doc.section('Panel list')
        by = Hash.new { |h, k| h[k] = [] }
        parts['groups'].each do |g|
          g['parts'].each do |p|
            refs = Array(p['instances']).filter_map { |i| tops[i['top']] }.tally.map { |t, n| n > 1 ? "#{t} x#{n}" : t }.join(', ')
            by[panel_type(g, p)] << [p['number'], p['name'], g['material'], f(p['thickness']), f(p['length']), f(p['width']), p['qty'], refs]
          end
        end
        PANEL_TYPES.each do |t|
          next if by[t].empty?
          doc.heading(t, "#{by[t].sum { |r| r[6] }} piece(s)")
          doc.table([['#', 30, :left], ['Part', nil, :left], ['Material', 150, :left], ['Thk', 34, :right], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right], ['Refs', 150, :left]], by[t])
        end
      end

      def self.layout(model, parts, fit: :fetch)
        rows, tops = Products.list(model)
        doors = Report.rows(model)
        info = by_ref(parts, doors, tops)
        hd = head(model, fit)
        @cornice = cornice(parts)
        images = {}
        doc = Doc.new(hd)
        doc.start
        spec_page(doc, model, hd, rows, doors, parts)
        product_page(doc, rows, info)
        plan_page(doc, model, hd, images)
        door_pages(doc, model)
        pod_page(doc, rows, info)
        panel_page(doc, parts, tops)
        key = Products.key_text(rows.map { |r| r['ref'] })
        doc.pages.each_with_index do |p, i|
          p.text(M, M - 14, "HW Door Style v#{VERSION}", size: 7)
          p.text(M + 80, M - 14, key, size: 7, max: W - 2 * M - 160) unless key.empty?
          p.text(W - M, M - 14, "Page #{i + 1} of #{doc.pages.size}", size: 7.5, font: 'F2', align: :right)
        end
        [doc.pages.map(&:to_s), images]
      end

      def self.version(dir, base, recorded)
        re = /\AROOM_PLAN_v(\d+)_#{Regexp.escape(Report.safe_name(base))}\.pdf\z/i
        on_disk = Dir.exist?(dir) ? Dir.children(dir).filter_map { |x| x[re, 1]&.to_i }.max.to_i : 0
        [on_disk, recorded.to_i].max + 1
      end

      # Writes ROOM_PLAN_v<N>_<file>.pdf next to the .skp. Returns [path, version].
      def self.write(model, parts)
        raise 'Save the SketchUp file first - the room plan is saved next to it.' if model.path.to_s.empty?
        dir = File.dirname(model.path)
        base = File.basename(model.path, '.skp')
        v = version(dir, base, model.get_attribute(DICT, 'room_plan_version', 0))
        pages, images = layout(model, parts)
        path = File.join(dir, "ROOM_PLAN_v#{v}_#{Report.safe_name(base)}.pdf")
        File.binwrite(path, Pdf.document(pages, images: images))
        Ops.run(model, 'Record room plan export', transparent: true) { model.set_attribute(DICT, 'room_plan_version', v) }
        [path, v]
      end
    end
  end
end
