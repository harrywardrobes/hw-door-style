require 'json'

module HarryWardrobes
  module DoorStyle
    # On-screen summary of every door / drawer front, with CSV export and print-to-PDF.
    module Report
      HEADERS = ['#', 'Unit', 'Item', 'Kind', 'Width mm', 'Height mm', 'Style', 'Mid-rail',
                 'Hinge type', 'Hinges', 'TIP-ON', 'Handles', 'Notes'].freeze

      def self.path_label(path)
        return '(model)' if path.empty?
        path.map do |p|
          n = p.respond_to?(:definition) ? Finder.label(p) : p.name
          p.name.to_s.empty? ? n : "#{n} (#{p.name})"
        end.join(' > ')
      end

      # A door with a mid-rail is a wardrobe door.
      def self.kind_label(kind, defn)
        return 'Stable Panel' if kind == :door && Finder.fixed_def?(defn)
        kind == :door && defn.get_attribute(DICT, 'midrail') ? 'Wardrobe Door' : Finder::KINDS[kind]
      end

      # "Yes - 815mm": the mid-rail's centre above the bottom of the door, from the style.
      def self.midrail_text(defn, style)
        return '' unless defn.get_attribute(DICT, 'midrail')
        c = (Styles.profile(style || 'shaker') || {})['midrail_centre_mm']
        c ? "Yes - #{c.to_f.round}mm" : 'Yes'
      end

      def self.rows(model = Sketchup.active_model)
        rows = []
        pto = Settings.pto?(Settings.job_hinge_type(model))
        rules = Settings.job_handles(model)
        # internal drawer fronts are in the interior colour (Colours.apply)
        int_colour = (RoomPlan.colour_text(model, 'interior') rescue nil)
        # Handles set to N/A in the Door style window count none.
        none = { door: DoorStyleWindow.na?('main_robe_handle', model), ext_drawer: DoorStyleWindow.na?('drawer_handle', model),
                 int_drawer: DoorStyleWindow.na?('interior_handle', model) }
        Finder.each_occurrence(model.entities) do |inst, kind, path|
          d = inst.definition
          w, _t, h = Finder.real_size(inst)
          kids = d.entities.grep(Sketchup::ComponentInstance)
          hinges = kids.select { |e| e.get_attribute(DICT, 'role') == 'hinge' }
          tips   = kids.count  { |e| e.get_attribute(DICT, 'role') == 'tip_on' }
          style  = d.get_attribute(DICT, 'style')
          notes  = []
          notes << d.get_attribute(DICT, 'note').to_s
          notes << 'Not processed yet' if style.nil? && kind != :int_drawer
          if style
            pr = Repair.problems(inst, kind)
            notes << "Needs Repair / re-run: #{pr.join(', ')}" unless pr.empty?
          end
          pr = Styles.profile(style || 'flat') || {}
          # hinge centres from the door bottom, mm (hinge_heights works in inches, as the model)
          hole_mm = hinges.empty? ? [] : Hardware.hinge_heights(h.to_f, hinges.size).map { |z| (z * 25.4).round }
          rows << {
            'unit' => path_label(path), 'item' => Finder.label(inst), 'top_id' => (path.first || inst).entityID,
            'stile_mm' => (kind == :door ? pr['door_frame_mm'] : pr['drawer_stile_mm']).to_f.round,
            'rail_mm' => (kind == :door ? pr['door_frame_mm'] : pr['drawer_frame_mm']).to_f.round,
            'midrail_mm' => d.get_attribute(DICT, 'midrail') ? pr['midrail_centre_mm'].to_f.round : 0,
            'midrail_w' => d.get_attribute(DICT, 'midrail') ? pr['midrail_width_mm'].to_f.round : 0,
            'holes' => hole_mm,
            'kind' => kind_label(kind, d), 'kind_id' => kind.to_s, 'width' => Finder.mm_s(w), 'height' => Finder.mm_s(h),
            'style' => Styles.label(style || 'flat'),
            'midrail' => midrail_text(d, style),
            'hand' => kind == :door && hinges.any? ? (Hardware.right?(inst) ? 'RH' : 'LH') : '',
            'hinge_type' => hinges.empty? ? '' : Settings::HINGE_TYPES.fetch(hinges.first.get_attribute(DICT, 'type').to_s, hinges.first.get_attribute(DICT, 'type').to_s),
            'hinges' => hinges.size, 'tip_on' => tips,
            'handles' => none[kind] || Finder.fixed?(inst) ? 0 : Settings.handle_count(kind, w, hinges.empty? ? pto : Settings.pto?(hinges.first.get_attribute(DICT, 'type').to_s), rules: rules,
                                                handleless: Styles.handleless?(d.get_attribute(DICT, 'requested_style') || style || 'flat')),
            'notes' => notes.reject(&:empty?).join('; '),
            'colour' => kind == :int_drawer ? int_colour : nil
          }
        end
        rows.each_with_index { |r, i| r['n'] = i + 1 }
        rows
      end

      # The order as a supplier reads it: identical fronts on one line with a quantity.
      # [{ 'qty', 'kind', 'style', 'width', 'height', 'hand', 'hinge_type', 'hinges', 'holes',
      #    'stile_mm', 'rail_mm', 'midrail_mm', 'midrail_w', 'handles', 'pods' => ['T1', ...], 'hinge_mark', 'hinge_shade' }]
      def self.order_lines(rows)
        rows.group_by { |r| [r['kind'], r['style'], r['width'], r['height'], r['hand'], r['hinge_type'], r['hinges'], r['tip_on'], r['midrail_mm'], r['handles']] }
            .map do |_k, list|
          f = list.first
          f.merge('qty' => list.size, 'pods' => list.map { |r| r['t'].to_s.empty? ? r['unit'] : r['t'] }.tally.map { |t, n| n > 1 ? "#{t} x#{n}" : t },
                  'notes' => list.map { |r| r['notes'].to_s }.reject(&:empty?).uniq.join('; '))
        end.sort_by { |l| [l['kind_id'] == 'door' ? 0 : (l['kind_id'] == 'ext_drawer' ? 1 : 2), -l['height'].to_f, -l['width'].to_f, l['hand'].to_s] }
      end

      # "H1: 100 (from top of door)" ... as HPP / Integral read the drilling: the upper
      # holes from the top of the door, the lower ones from the bottom (the middle of three
      # from the bottom).
      def self.hole_lines(holes, height)
        n = holes.size
        return [] if n.zero?
        holes.sort.reverse.each_with_index.map do |z, i|
          from_top = i < n / 2
          "H#{i + 1}: #{(from_top ? height.to_f - z : z).round} (from #{from_top ? 'top' : 'bottom'} of door)"
        end
      end

      def self.totals(rows)
        t = { 'by_style' => Hash.new(0), 'hinges' => Hash.new(0), 'tip_on' => 0, 'handles' => 0, 'items' => rows.size }
        rows.each do |r|
          t['by_style']["#{r['kind']} - #{r['style']}"] += 1
          t['hinges'][r['hinge_type']] += r['hinges'] if r['hinges'] > 0
          t['tip_on'] += r['tip_on']
          t['handles'] += r['handles'].to_i
        end
        t
      end

      def self.csv(rows)
        q = ->(v) { s = v.to_s; s =~ /[",\n]/ ? "\"#{s.gsub('"', '""')}\"" : s }
        lines = [HEADERS.map(&q).join(',')]
        rows.each do |r|
          lines << [r['n'], r['unit'], r['item'], r['kind'], r['width'], r['height'], r['style'],
                    r['midrail'], r['hinge_type'], r['hinges'], r['tip_on'], r['handles'], r['notes']].map(&q).join(',')
        end
        lines.join("\r\n")
      end

      # --- export: DOOR_ORDER_v<N>_<file name>.csv + .pdf next to the .skp ---

      def self.safe_name(s)
        s.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '_').strip
      end

      def self.order_stem(version, base)
        "DOOR_ORDER_v#{version}_#{safe_name(base)}"
      end

      # Next version = highest found in the folder or recorded in the model, + 1.
      def self.next_version(dir, base, recorded = 0)
        pattern = /\ADOOR_ORDER_v(\d+)_#{Regexp.escape(safe_name(base))}\.(csv|pdf)\z/i
        found = Dir.exist?(dir) ? Dir.children(dir).map { |f| f[pattern, 1].to_i }.max.to_i : 0
        [found, recorded.to_i].max + 1
      end

      # Writes DOOR_ORDER_v<N> .pdf (and .csv if set) next to the .skp, no questions. Returns [csv or nil, pdf, version].
      # PDF only, unless Settings > General "Also save CSV files" is on.
      def self.csv?
        Settings.get['export_csv'] ? true : false
      end

      # 22mm (white back) panels and bullnose / cornice from the parts list: ordered with the
      # doors, so they're on this order (not the parts list). [{ title, note, cols, rows }]
      def self.vinyl_sections(parts)
        f = ->(v) { PartsList.fmt(v) }
        wb = parts['groups'].select { |g| g['section'] == 'white_back' }
        vin = parts['groups'].select { |g| g['section'] == 'vinyl' }
        nosing = ->(p) { p['name'].to_s =~ PartsList::VINYL_RE }
        vrow = ->(g, p) { [p['number'], p['name'], g['material'], "#{f.call(g['thickness'])} mm", f.call(p['length']), f.call(p['width']), p['qty']] }
        [
          { 'title' => '22mm panels (white back)', 'note' => 'vinyl-wrapped 22mm panels, white backed',
            'cols' => [['#', 26, :left], ['Name', nil, :left], ['Colour', 110, :left], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right]],
            'rows' => wb.flat_map { |g| g['parts'].map { |p| [p['number'], p['name'], g['material'], f.call(p['length']), f.call(p['width']), p['qty']] } } },
          { 'title' => 'Bullnose / cornice', 'note' => 'vinyl',
            'cols' => [['#', 26, :left], ['Name', nil, :left], ['Colour', 110, :left], ['Thickness', 60, :right], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right]],
            'rows' => vin.flat_map { |g| g['parts'].select(&nosing).map { |p| vrow.call(g, p) } } },
          { 'title' => 'Vinyl end panels', 'note' => 'end panels (Vinyl - TRUE) and the drawer units\' end panels - height x width as they stand',
            'cols' => [['#', 26, :left], ['Name', nil, :left], ['Colour', 110, :left], ['Thickness', 60, :right], ['Height', 50, :right], ['Width', 50, :right], ['Qty', 30, :right]],
            'rows' => vin.flat_map { |g| g['parts'].reject(&nosing).map { |p| [p['number'], p['name'], g['material'], "#{f.call(g['thickness'])} mm", f.call(p['height'] || p['length']), f.call(p['across'] || p['width']), p['qty']] } } }
        ]
      end

      # parts: the parts list (PartsList.generate) for the 22mm / bullnose sections and the
      # worktop views; made here when not given.
      def self.write_order(model = Sketchup.active_model, parts: nil)
        raise 'Save the SketchUp file first - the door order is saved next to it.' if model.path.to_s.empty?
        dir  = File.dirname(model.path)
        base = File.basename(model.path, '.skp')
        v    = next_version(dir, base, model.get_attribute(DICT, 'export_version', 0))
        stem = File.join(dir, order_stem(v, base))
        data = payload(model).merge('export_version' => v)
        parts ||= PartsList.generate(model)
        tops = (Products.list(model)[1] rescue {})
        data['vinyl'] = vinyl_sections(parts)
        data['worktops'] = begin
          WorktopView.worktops(model, parts, tops)
        rescue StandardError => e
          Log.error('worktop view', e)
          []
        end
        data['elevation'] = begin
          DoorView.walls(model)
        rescue StandardError => e
          Log.error('door order elevation', e)
          []
        end
        File.write("#{stem}.csv", "\uFEFF" + csv(data['rows']), mode: 'w:UTF-8') if csv?
        Pdf.write("#{stem}.pdf", data)
        Ops.run(model, 'Record door order export', transparent: true) { model.set_attribute(DICT, 'export_version', v) }
        [csv? ? "#{stem}.csv" : nil, "#{stem}.pdf", v]
      end

      # Menu: the Door / Vinyl order on its own (the Workshop pack is the usual way).
      def self.export_order(model = Sketchup.active_model)
        unless Pencil.on?(model) || Runouts.units(model.entities).empty?
          return nil unless UI.messagebox("Scribes are OFF - every runout is 0, so sizes may be wrong.\n\nExport the door order anyway?", MB_YESNO) == IDYES
        end
        if model.path.to_s.empty?
          UI.messagebox('Save the SketchUp file first - the door order is saved next to it and named after it.')
          return nil
        end
        csv_path, pdf, v = write_order(model)
        UI.messagebox("Door / Vinyl order v#{v} saved in:\n#{File.dirname(pdf)}\n\n#{csv_path ? "#{File.basename(csv_path)}\n" : ''}#{File.basename(pdf)}")
        v
      rescue StandardError => e
        UI.messagebox("Export failed: #{e.message}")
        Log.error('export order', e)
        nil
      end

      SHADES = [0.88, 0.76, 0.64].freeze # grey levels (1 = white) - print in black and white

      # More than one hinge type: the usual one (most doors; a tie goes to the job's) stays
      # plain, each other type gets a grey shade and a mark (*, **, ***...) so it reads in
      # black and white too. Sets 'hinge_mark' / 'hinge_shade' on the rows; returns the key
      # [[mark, type, shade]] (empty when every door has the same hinges).
      def self.mark_hinges(rows, job_label = nil)
        counts = rows.reject { |r| r['hinge_type'].to_s.empty? }.group_by { |r| r['hinge_type'] }.transform_values(&:size)
        return [] if counts.size < 2
        usual = counts.max_by { |t, n| [n, t == job_label ? 1 : 0] }.first
        odd = (counts.keys - [usual]).sort_by { |t| [-counts[t], t] }
        key = odd.each_with_index.map { |t, i| ['*' * (i + 1), t, SHADES[i % SHADES.size]] }
        rows.each do |r|
          k = key.find { |_m, t, _s| t == r['hinge_type'] }
          r['hinge_mark'], r['hinge_shade'] = k ? [k[0], k[2]] : [nil, nil]
        end
        key
      end

      def self.payload(model = Sketchup.active_model)
        r = rows(model)
        # Unit = the product's Pod number (Product List); the component path stays as 'unit_path'.
        tops = (Products.list(model)[1] rescue {})
        r.each do |x|
          x['unit_path'] = x['unit']
          x['t'] = tops[x['top_id']].to_s
          x['unit'] = x['t'].empty? ? x['unit'] : x['t']
        end
        hinge_key = mark_hinges(r, Settings::HINGE_TYPES[Settings.job_hinge_type(model)])
        out = {
          'job' => File.basename(model.path.to_s, '.skp'),
          'head' => (RoomPlan.head(model, nil) rescue {}),
          'hinge_type' => Settings::HINGE_TYPES[Settings.job_hinge_type(model)],
          'date' => Time.now.strftime('%d/%m/%Y %H:%M'),
          'version' => VERSION,
          'last_export' => model.get_attribute(DICT, 'export_version', 0).to_i,
          'rows' => r, 'totals' => totals(r),
          'colour' => (RoomPlan.colour_text(model, 'door') rescue '-'),
          'lines' => order_lines(r),
          'hinge_key' => hinge_key,
          'key' => (Products.key_text(r.map { |x| x['t'].to_s[/\A[A-Z]+/] }.compact) rescue ''),
          'runouts' => { 'on' => Pencil.on?(model), 'changed' => Runouts.report(model) }
        }
        # the order as the PDF prints it (title, header line, each line's Details and Drilling),
        # so the Workshop shows the same words
        out['title'] = Pdf.doors_title(out['head'])
        out['head_line'] = Pdf.head_line(out['head'])
        out['lines'].each do |l|
          l['details'] = Pdf.details(l, out)
          l['drilling'] = l['hinges'].to_i.positive? ? (l['hand'] == 'RH' ? 'DRILLED RIGHT' : 'DRILLED LEFT') : ''
        end
        out
      end

      def self.show
        dlg = Dialog.open('summary', title: 'HW Door Style - Summary', key: 'hw_door_style_summary',
                                     width: 1000, height: 650, data: payload)
        dlg.add_action_callback('exportOrder') do |_ctx|
          export_order
          dlg.execute_script("render(#{JSON.generate(payload)})")
        end
        dlg.add_action_callback('refresh') { |_ctx| dlg.execute_script("render(#{JSON.generate(payload)})") }
        dlg.show
      end
    end
  end
end
