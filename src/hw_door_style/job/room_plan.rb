require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Room Plan: one PDF for the fitters and the workshop - ROOM_PLAN_v<N>_<file>.pdf.
    #
    #   1 Cover / Specification  customer, room, colours, door style, hinges, handles, fit week
    #   2 Product List           every pod (T / W / B / M) - loose items first - with doors and interior
    #   3 Installation Plan      the plan scene, notes, Pod numbers; ceiling, top fascia, runouts, cornice
    #   3b Door elevation        the doors and drawer fronts on each wall, with sizes (DoorView)
    #   4 Panel list             Timber / MDF, Cut, Worktop, Facing - each part with the pods it's in
    #
    # Every page has the header: customer, drawing X<room id>, account HW<contact id>,
    # fit week (the Room's "Fit week" in HubSpot), room, date, page n of N.
    module RoomPlan
      W = Pdf::PAGE_W
      H = Pdf::PAGE_H
      M = Pdf::MARGIN
      ROW = Pdf::ROW_H
      LOOSE_FIRST = %w[M T W B L F].freeze
      PANEL_TYPES = ['Timber / MDF', 'Cut', 'Worktop', 'Facing'].freeze

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
                   ['Account', hd['account']], ['Fit week', hd['fit_week']]]
          right.each_slice(3).with_index do |col, ci|
            x = W - M - 270 + ci * 135
            col.each_with_index do |(k, v), i|
              page.text(x, top - i * 10, "#{k}:", font: 'F2', size: 7.5)
              page.text(x + 42, top - i * 10, v.to_s.empty? ? '-' : v.to_s, size: 7.5, max: 90)
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

      # Customer "WILLIAMS, Rebecca" (the HubSpot contact), room (the Workshop's room name),
      # drawing X<Room ID>, account HW<HubSpot contact ID> - the same on every PDF.
      def self.head(model, fit = :fetch)
        l = HubSpotRoom.customer_link(model) || {}
        j = (JobInfo.get(model) rescue {}) || {}
        { 'customer' => customer_name(j['customer_first'], j['customer_last']),
          'address' => l['address'].to_s,
          'room' => j['room_name'].to_s.empty? ? l['room_name'].to_s : j['room_name'].to_s,
          'drawing' => j['room_id'].to_s.empty? ? '' : "X#{j['room_id']}",
          'account' => l['contact_id'].to_s.empty? ? '' : "HW#{l['contact_id']}",
          'fit_week' => fit == :fetch ? fit_week(l['room_id']) : fit }
      end

      # "WILLIAMS, Rebecca Jane": surname in capitals, comma, first names as written.
      def self.customer_name(first, last)
        [last.to_s.strip.upcase, first.to_s.strip].reject(&:empty?).join(', ')
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

      # Timber / MDF (lengths), Cut, Worktop, Facing.
      def self.panel_type(g, p)
        return 'Worktop' if g['section'] == 'worktops'
        return 'Facing' if p['name'] =~ /FACING/i
        return 'Timber / MDF' if g['material'] =~ /TIMBER|2X1|PINE|MDF/i
        'Cut'
      end

      # --- pages ---------------------------------------------------------------------------

      # Door style for the cover: the doors' style ("Shaker"), with a note when anything else
      # in the model has another style (flat internal drawer fronts are the norm, not noted).
      def self.door_style_text(model, doors)
        st = DoorStyleWindow.job_styles(model)
        main = Styles.label(st['door'])
        others = doors.reject { |d| d['kind_id'] == 'int_drawer' && d['style'].to_s.casecmp?('flat') }
                      .map { |d| d['style'].to_s }.reject { |x| x.empty? || x.casecmp?(main) }.uniq
        others.empty? ? main : "#{main} (also #{others.join(', ')} in this room)"
      end

      # The job colours as the colour they resolve to - never "Default".
      def self.colour_text(model, gid)
        name = Colours.resolved(model, Colours.job_choices(model).transform_values { |v| v || Colours::DEFAULT })[gid].to_s
        name == Colours::DEFAULT ? '-' : name
      end

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
        kv.call('Room', hd['room'])
        kv.call('Drawing / Account', "#{hd['drawing']}   #{hd['account']}")
        kv.call('Fit week', hd['fit_week'])
        y -= 8
        Colours::GROUPS.each { |id, label| kv.call(label, colour_text(model, id)) }
        kv.call('Door style', door_style_text(model, doors))
        kv.call('Hinges', Settings::HINGE_TYPES[Settings.job_hinge_type(model)])
        PartsList.handles(model).each { |h| kv.call(h['kind'], "#{h['name']}#{h['sku'].empty? ? '' : " (#{h['sku']})"} x #{h['qty']}") }
        doc.instance_variable_set(:@y, y)
      end

      # "Floor Runout 25 mm   Ceiling Runout 25 mm ..." for the installation plan.
      def self.runouts_text(model)
        return 'Scribes OFF (every runout 0)' unless Pencil.on?(model)
        v = Runouts.job_values(model)
        Runouts::SIDES.map { |s, _k, l| "#{l.sub(/\ARunout - /, '').sub(' (mm)', '').split.map(&:capitalize).join(' ')} Runout #{v[s].round} mm" }.join('   ')
      end

      def self.cornice(parts)
        cs = parts['groups'].select { |g| g['section'] == 'vinyl' }.flat_map { |g| g['parts'].select { |p| p['name'] =~ /CORNICE/i } }
        cs.empty? ? 'None' : "#{cs.sum { |p| p['qty'] }} length(s), #{cs.map { |p| f(p['length']) }.uniq.join(' / ')} mm"
      end

      # One block per pod: "T1  1000 Wardrobe (580 deep / 598 overall)" in bold, then Doors
      # and Interior on their own lines.
      def self.product_page(doc, rows, info)
        doc.section('Product List')
        list = rows.sort_by { |r| [LOOSE_FIRST.index(r['ref']) || 9, r['num']] }
        list.each do |r|
          i = info[r['t']]
          lines = [['Doors', door_text(i['doors'])], ['Interior', interior_text(i)]].reject { |_k, v| v.to_s.empty? }
          doc.need(ROW * (lines.size + 2))
          pg = doc.page
          y = doc.y
          pg.text(M, y, r['t'], font: 'F2', size: 11)
          pg.text(M + 40, y, describe(r), font: 'F2', size: 10)
          y -= ROW + 1
          lines.each do |k, v|
            pg.text(M + 40, y, "#{k}:", font: 'F2', size: 8.5)
            pg.text(M + 92, y, v, size: 8.5, max: W - 2 * M - 92)
            y -= ROW - 1
          end
          pg.line(M, y - 2, W - M, y - 2)
          doc.instance_variable_set(:@y, y - 8)
        end
      end

      def self.plan_page(doc, model, hd, images)
        doc.section('Installation Plan')
        pg = doc.page
        foot = M + 42
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
        fa = Plan.top_fascia(model)
        items = [['Drawing', hd['drawing']], ['Main ceiling', c.positive? ? "#{c.round} mm" : '-'], ['Top fascia', fa ? "#{fa} mm" : '-'], ['Cornice', @cornice]]
        pg.line(M, foot + 14, W - M, foot + 14, 0.2, 1)
        x = M
        widths = Pdf.fit_widths([90, 90, 90, nil], W - 2 * M, 60)
        items.each_with_index do |(k, v), i|
          w = widths[i]
          pg.text(x, foot + 2, k, font: 'F2', size: 7.5)
          pg.text(x, foot - 9, v.to_s.empty? ? '-' : v.to_s, size: 8, max: w - 6)
          x += w
        end
        pg.text(M, foot - 22, 'Scribes:', font: 'F2', size: 7.5)
        pg.text(M + 36, foot - 22, runouts_text(model), size: 8, max: W - 2 * M - 36)
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

      # One list: every part by type (Timber / MDF, Cut, Worktop, Facing) with the pods it's
      # in ("T1 x3, T2"); then the hardware and the doors / drawer fronts the same way.
      def self.panel_page(doc, parts, tops, doors = [])
        doc.section('Panel list')
        by = Hash.new { |h, k| h[k] = [] }
        pods = ->(insts) { insts.filter_map { |i| tops[i['top']] }.tally.map { |t, n| n > 1 ? "#{t} x#{n}" : t }.join(', ') }
        parts['groups'].each do |g|
          next if %w[vinyl white_back].include?(g['section'])
          g['parts'].each do |p|
            by[panel_type(g, p)] << [p['number'], p['name'], g['material'], f(p['thickness']), f(p['length']), f(p['width']), p['qty'], pods.call(Array(p['instances']))]
          end
        end
        Array(parts['timber']).each do |t|
          by['Timber / MDF'] << [t['number'], t['name'], t['material'], t['section'], f(t['length']), '-', t['qty'], pods.call(Array(t['instances']))]
        end
        PANEL_TYPES.each do |t|
          next if by[t].empty?
          doc.heading(t, "#{by[t].sum { |r| r[6].to_i }} piece(s)")
          doc.table([['#', 30, :left], ['Part', nil, :left], ['Material', 120, :left], [t == 'Timber / MDF' ? 'Section' : 'Thk', 44, :right], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right], ['Pods', 120, :left]], by[t])
        end
        hws = Array(parts['hardware']).reject { |h| h['drawer_box'] }
        unless hws.empty?
          lines = PartsList.hardware_lines(hws)
          by_pod = hws.to_h { |h| [h['name'], pods.call(Array(h['instances']))] }
          doc.heading('Hardware', "#{lines.sum { |l| l['qty'] }} piece(s)")
          doc.table([['#', 40, :left], ['Item', nil, :left], ['Qty', 30, :right], ['Pods', 160, :left]],
                    lines.map { |l| [l['numbers'].join(', '), l['name'], l['qty'], l['parts'].map { |n| by_pod[n] }.reject(&:empty?).uniq.join(', ')] })
        end
        unless doors.empty?
          doc.heading('Doors / drawer fronts', "#{doors.size} - on the Door / Vinyl order")
          doc.table([['Pod', 34, :left], ['Item', nil, :left], ['Kind', 90, :left], ['Style', 60, :left], ['W', 40, :right], ['H', 40, :right], ['Hand', 36, :left]],
                    doors.map { |d| [tops[d['top_id']].to_s, d['item'], d['kind'], d['style'], d['width'], d['height'], d['hand']] })
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
        panel_page(doc, parts, tops, doors)
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
