require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Room Plan: one PDF for the fitters and the workshop - ROOM_PLAN_v<N>_<file>.pdf.
    #
    #   1 Cover / Specification  customer, room, colours, door style, hinges, handles, fit week
    #   2 Product List           every pod (T / W / B / M) - loose items first - with doors and interior
    #   3 Door elevation         the doors and drawer fronts on each wall, with sizes (DoorView)
    #   4 Renders                the job's render scenes (Settings > HubSpot > Pictures, "Renders")
    #   5 Installation Plan      last, landscape: the plan scene, notes, Pod numbers; ceiling, top
    #                            fascia, cornice, runouts along the bottom
    # The parts list is its own PDF.
    #
    # Every page has the header: customer, drawing X<room id>, account HW<contact id>,
    # fit week (the Room's "Fit week" in HubSpot), room, date, page n of N.
    module RoomPlan
      W = Pdf::PAGE_W
      H = Pdf::PAGE_H
      M = Pdf::MARGIN
      ROW = Pdf::ROW_H
      LOOSE_FIRST = %w[M T W B L F].freeze

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
          right = [["Customer", hd['customer']], ['Room', hd['room']], ['Drawing', hd['drawing']]]
          right.each_slice(3).with_index do |col, ci|
            x = W - M - 135 + ci * 135
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
          'first' => j['customer_first'].to_s.strip, 'last' => j['customer_last'].to_s.strip,
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

      # The cover's rows: [[label, value], ...] (nil = a gap). The Workshop shows the same.
      def self.spec_rows(model, hd, doors)
        rows = [['Customer', hd['customer']], ['Room', hd['room']], ['Drawing / Account', "#{hd['drawing']}   #{hd['account']}"], ['Fit week', hd['fit_week']], nil]
        Colours::GROUPS.each { |id, label| rows << [label, colour_text(model, id)] }
        rows << ['Door style', door_style_text(model, doors)]
        rows << ['Hinges', Settings::HINGE_TYPES[Settings.job_hinge_type(model)]]
        hl = PartsList.handles(model)
        ['Robe handle', 'Drawer handle', 'Interior handle'].each do |kind|
          h = hl.find { |x| x['kind'] == kind }
          rows << [kind, h ? h['name'] : 'n/a']
        end
        rows.map { |r| r && [r[0], r[1].to_s.empty? ? '-' : r[1].to_s] }
      end

      # "Rebecca Williams" - the customer's full name as written.
      def self.full_name(hd)
        [hd['first'], hd['last']].map { |n| n.to_s.strip }.reject(&:empty?).join(' ')
      end

      def self.spec_page(doc, model, hd, rows, doors, parts)
        doc.section('Cover / Specification')
        pg = doc.page
        y = doc.y
        spec_rows(model, hd, doors).each do |r|
          next y -= 8 unless r
          pg.text(M, y, r[0], font: 'F2', size: 9)
          pg.text(M + 150, y, r[1], size: 9, max: W - 2 * M - 150)
          pg.line(M, y - 4, W - M, y - 4)
          y -= ROW + 2
        end
        # at the foot of the cover: the room and the customer's full name, large
        room = hd['room'].to_s.strip.upcase
        name = full_name(hd)
        pg.line(M, M + 64, W - M, M + 64, 0.2, 1)
        pg.text(M, M + 44, room.empty? ? '-' : room, font: 'F2', size: 20, max: W - 2 * M)
        pg.text(M, M + 26, name.empty? ? hd['customer'].to_s : name, font: 'F2', size: 14, max: W - 2 * M)
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
      # and Interior on their own lines. The blocks: [{ 't', 'title', 'lines' => [[k, v]] }].
      def self.product_blocks(rows, info)
        rows.sort_by { |r| [LOOSE_FIRST.index(r['ref']) || 9, r['num']] }.map do |r|
          i = info[r['t']]
          { 't' => r['t'], 'pid' => r['pid'], 'title' => describe(r),
            'lines' => ([['Doors', door_text(i['doors'])], ['Interior', interior_text(i)]] + Array(r['flags'])).reject { |_k, v| v.to_s.empty? } }
        end
      end

      def self.product_page(doc, rows, info)
        doc.section('Product List')
        product_blocks(rows, info).each do |b|
          r = b
          lines = b['lines']
          doc.need(ROW * (lines.size + 2))
          pg = doc.page
          y = doc.y
          pg.text(M, y, r['t'], font: 'F2', size: 11)
          pg.text(M + 40, y, r['title'], font: 'F2', size: 10)
          y -= ROW + 1
          lines.each do |k, v|
            pg.text(M + 40, y, "#{k}:", font: 'F2', size: 8.5)
            pg.text(M + 92, y, v, size: 8.5, max: W - 2 * M - 92)
            y -= ROW - 1
          end
          # the rule just under the block (y is the next line's baseline - the rule sat on the
          # next title before)
          pg.line(M, y + 5, W - M, y + 5)
          doc.instance_variable_set(:@y, y - 8)
        end
      end

      LW = Pdf::PAGE_H # the installation plan is landscape
      LH = Pdf::PAGE_W

      # The installation plan: landscape, the last page. The plan picture fills the page;
      # along the bottom, large: main ceiling, top fascia, cornice, then the runouts.
      def self.plan_page(doc, model, hd, images, sizes)
        pg = Pdf::Page.new
        doc.pages << pg
        sizes[doc.pages.size - 1] = [LW, LH]
        top = LH - M - 6
        pg.text(M, top, 'INSTALLATION PLAN', font: 'F2', size: 16, max: LW - 2 * M - 150)
        pg.text(M, top - 15, plan_subtitle(hd), font: 'F2', size: 11, max: LW - 2 * M - 150)
        right = [['Drawing', hd['drawing']]]
        right.each_slice(3).with_index do |col, ci|
          x = LW - M - 135 + ci * 135
          col.each_with_index do |(k, v), i|
            pg.text(x, top - i * 10, "#{k}:", font: 'F2', size: 7.5)
            pg.text(x + 42, top - i * 10, v.to_s.empty? ? '-' : v.to_s, size: 7.5, max: 90)
          end
        end
        pg.line(M, top - 32, LW - M, top - 32, 0.2, 1.2)
        foot = M + 58
        if Plan.plan_page(model)
          jpg = File.join(Dir.tmpdir, "hw_room_plan_#{Process.pid}.jpg")
          Plan.picture(model, jpg)
          im = Pdf.jpeg(jpg)
          File.delete(jpg) rescue nil
          images['Im1'] = im
          box_w = LW - 2 * M
          box_h = top - 40 - foot
          s = [box_w / im['w'], box_h / im['h']].min
          pg.image('Im1', M + (box_w - im['w'] * s) / 2, foot + (box_h - im['h'] * s) / 2, im['w'] * s, im['h'] * s)
          Plan.overlay(pg, Plan.labels, M + (box_w - im['w'] * s) / 2, foot + (box_h - im['h'] * s) / 2, im['w'] * s, im['h'] * s)
        else
          pg.text(M, top - 60, 'No plan scene in this model - add a scene named "top" or "plan" to show the installation plan here.', font: 'F2', size: 10)
        end
        items = plan_items(model, @cornice)
        pg.line(M, foot - 6, LW - M, foot - 6, 0.2, 1)
        cw = (LW - 2 * M) / items.size.to_f
        items.each_with_index do |(k, val), i|
          x = M + i * cw
          pg.text(x, foot - 20, k, font: 'F2', size: 8.5, max: cw - 6)
          pg.text(x, foot - 36, val.to_s.empty? ? '-' : val.to_s, font: 'F2', size: 13, max: cw - 6)
        end
      end

      # "BEATRICE - Rebecca Williams" under the installation plan's title.
      def self.plan_subtitle(hd)
        [hd['room'].to_s.strip.upcase, full_name(hd).then { |n| n.empty? ? hd['customer'].to_s.strip : n }].reject(&:empty?).join(' - ')
      end

      # Along the foot of the installation plan: [[label, value], ...].
      def self.plan_items(model, cornice = nil)
        c = Ceiling.mm(model)
        fa = Plan.top_fascia(model)
        items = [['Main ceiling', c.positive? ? "#{c.round} mm" : '-'], ['Top fascia', fa ? "#{fa} mm" : '-'], ['Cornice', cornice.to_s.empty? ? '-' : cornice]]
        v = Pencil.on?(model) ? Runouts.job_values(model) : nil
        Runouts::SIDES.each { |sd, _k, l| items << ["#{l.sub(/\ARunout - /, '').sub(' (mm)', '').capitalize} runout", v ? "#{v[sd].round} mm" : 'OFF'] }
        items
      end

      # What the Workshop's Room Plan tab shows: the cover's rows, the product blocks and the
      # installation plan's title and foot - the PDF's own words (fit week not fetched here).
      def self.window_data(model, parts, rows, tops)
        doors = Report.rows(model)
        hd = head(model, nil)
        { 'spec' => spec_rows(model, hd, doors), 'products' => product_blocks(rows, by_ref(parts, doors, tops)),
          'room' => hd['room'].to_s.strip.upcase, 'full_name' => full_name(hd).then { |n| n.empty? ? hd['customer'].to_s : n },
          'plan_title' => 'INSTALLATION PLAN', 'plan_subtitle' => plan_subtitle(hd), 'plan_items' => plan_items(model, cornice(parts)),
          'head' => hd }
      rescue StandardError => e
        Log.error('room plan window data', e)
        {}
      end

      # The job's renders (the "Renders" scenes in Settings > HubSpot > Pictures), two to a page.
      def self.render_pages(doc, model, images)
        row = Array(Settings.get['hubspot_pictures']).find { |r| r['field'].to_s == 'render_1' || r['label'].to_s =~ /render/i } or return
        names = Array(row['scenes']).select { |n| model.pages[n] }
        return if names.empty?
        view = model.active_view
        was = model.pages.selected_page
        cam = view.camera.then { |c| Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov) }
        po = model.options['PageOptions']
        trans = po['ShowTransition']
        po['ShowTransition'] = false
        shots = names.filter_map do |n|
          model.pages.selected_page = model.pages[n]
          view.refresh
          jpg = File.join(Dir.tmpdir, "hw_render_#{Process.pid}_#{images.size}.jpg")
          ok = view.write_image(filename: jpg, width: 1600, height: (1600 * view.vpheight / view.vpwidth.to_f).round, antialias: true, compression: 0.85)
          next unless ok && File.exist?(jpg)
          im = Pdf.jpeg(jpg)
          File.delete(jpg) rescue nil
          key = "Im#{images.size + 2}"
          images[key] = im
          [n, key, im]
        end
        shots.each_slice(2) do |pair|
          doc.section('Renders')
          pg = doc.page
          box_h = (doc.y - M - 6) / pair.size
          pair.each_with_index do |(_n, key, im), i|
            top = doc.y - i * box_h
            bw = W - 2 * M
            bh = box_h - 8
            s = [bw / im['w'], bh / im['h']].min
            pg.image(key, M + (bw - im['w'] * s) / 2, top - bh + (bh - im['h'] * s) / 2, im['w'] * s, im['h'] * s)
          end
        end
      ensure
        model.pages.selected_page = was if was
        view.camera = cam if cam
        po['ShowTransition'] = trans unless trans.nil?
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

      def self.layout(model, parts, fit: :fetch)
        rows, tops = Products.list(model)
        doors = Report.rows(model)
        info = by_ref(parts, doors, tops)
        hd = head(model, fit)
        @cornice = cornice(parts)
        images = {}
        sizes = []
        doc = Doc.new(hd)
        doc.start
        spec_page(doc, model, hd, rows, doors, parts)
        product_page(doc, rows, info)
        door_pages(doc, model)
        begin
          render_pages(doc, model, images)
        rescue StandardError => e
          Log.error('room plan renders', e)
        end
        plan_page(doc, model, hd, images, sizes)
        key = Products.key_text(rows.map { |r| r['ref'] })
        doc.pages.each_with_index do |p, i|
          pw = (sizes[i] || [W, H])[0]
          p.text(M, M - 14, "HW #{VERSION}", size: 7)
          unless key.empty?
            k = Pdf.fit(key, 'F1', 7, pw - 2 * M - 160)
            p.text((pw - Pdf.width(k, 'F1', 7)) / 2, M - 14, k, size: 7)
          end
          p.text(pw - M, M - 14, "Page #{i + 1} of #{doc.pages.size}", size: 7.5, font: 'F2', align: :right)
        end
        [doc.pages.map(&:to_s), images, sizes]
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
        pages, images, sizes = layout(model, parts)
        path = File.join(dir, "ROOM_PLAN_v#{v}_#{Report.safe_name(base)}.pdf")
        File.binwrite(path, Pdf.document(pages, images: images, sizes: sizes))
        Ops.run(model, 'Record room plan export', transparent: true) { model.set_attribute(DICT, 'room_plan_version', v) }
        [path, v]
      end
    end
  end
end
