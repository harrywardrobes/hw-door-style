module HarryWardrobes
  module DoorStyle
    # Workshop: the one window for everything that goes to the workshop and HubSpot -
    # door order, parts list (sheet goods, edging, hardware), labels - saved as one pack and
    # synced to the HubSpot Room: files, quantities, sheets per colour, cut and edged strips,
    # order statuses, and (only when asked) the stage.
    module Workshop
      STATUS_DONE = ['Ordered', 'Received', 'Partially Received'].freeze
      NEEDS = 'Needs Ordering'.freeze
      NA = 'Not Applicable'.freeze

      # Status field -> what in the model needs ordering.
      def self.needs(model, parts)
        c = HubSpotRoom.counts(model)
        doors = Report.rows(model).size + parts['groups'].select { |g| %w[vinyl white_back].include?(g['section']) }.sum { |g| g['count'].to_i }
        worktop = parts['groups'].any? { |g| g['section'] == 'worktops' }
        sheets = parts['groups'].any? { |g| g['section'] == 'sheets' }
        {
          'door_vinyl_order_status' => [doors.positive?, "#{doors} door(s) / drawer front(s)"],
          'drawer_order_status' => [(c['ext_drawers'] + c['int_drawers']).positive?, "#{c['ext_drawers'] + c['int_drawers']} drawer(s)"],
          'sheets_order_status' => [sheets, sheets ? 'board in the parts list' : 'no boards'],
          'hardware_order_status' => [!parts['hardware'].empty? || parts['handles'].any? { |h| h['qty'].to_i.positive? }, "#{parts['hardware'].sum { |h| h['qty'] }} hardware piece(s)"],
          'worktop_order_status' => [worktop, worktop ? 'worktop in the parts list' : 'no worktop (22 / 25 mm)']
        }
      end

      QTY_FIELDS = (HubSpotRoom::HINGE_FIELDS.values + %w[blum_push_tipon_set drawer_total_quantity drawer_type
                                                          main_robe_handle main_robe_handle_id robe_handle_supplier main_robe_handle_quantity
                                                          drawer_handle drawer_handle_sku drawer_handle_supplier drawer_handle_quantity
                                                          interior_handle interior_handle_sku interior_handle_supplier interior_handle_quantity cable_outlet_quantity]).freeze

      # Rows for the HubSpot tab: [{ prop, label, section, hubspot, value, shown, send, flag }].
      def self.plan(model, parts)
        l = HubSpotRoom.link(model) or return { 'linked' => false, 'design_visit' => HubSpotRoom.design_visit?(model), 'saved' => !model.path.to_s.empty? }
        m = HubSpotRoom.meta
        calc = HubSpotRoom.calculated(model, m)
        mine = {}
        QTY_FIELDS.each { |p| mine[p] = [calc.dig(p, 'value'), calc.dig(p, 'shown'), 'Quantities'] if calc.key?(p) }
        PartsList.room_values(parts).each { |p, v| mine[p] = [v, nil, p.start_with?('cut_and') ? 'Cut and edged strips' : 'Sheets'] }
        # every colour field gets a value (0 when the colour isn't used)
        unused = m.keys.select { |p| p.start_with?('mfc_sheets_') && !mine.key?(p) }
        need = needs(model, parts)
        required = (Settings.get['hubspot_required'] || {}).values.flatten.map(&:to_s)
        props = (mine.keys + unused + need.keys + required + %w[hs_pipeline_stage order_parts_list]).uniq
        theirs = HubSpot.read_one('listings', l['room_id'], props.select { |p| m[p] } + %w[hs_pipeline_stage])['properties'] || {}
        # colours not in this job: only cleared to 0 if HubSpot still has a number for them
        unused.each { |p| mine[p] = [0, nil, 'Sheets'] unless theirs[p].to_s.empty? || theirs[p].to_s == '0' }
        rows = mine.filter_map do |p, (v, shown, section)|
          next unless m[p]
          cur = theirs[p]
          { 'prop' => p, 'label' => m[p]['label'], 'section' => section, 'hubspot' => HubSpotRoom.label_of(cur, m[p]['all_options'] || m[p]['options'] || []), 'value' => v,
            'shown' => shown || (v.nil? ? nil : HubSpotRoom.label_of(v, m[p]['all_options'] || m[p]['options'] || [])),
            'send' => v.to_s != cur.to_s && !(v.nil? && cur.to_s.empty?) }
        end
        missing_colours = parts['groups'].map { |g| g['material'] }.uniq.reject { |n| m["mfc_sheets_#{PartsList.slug(n)}"] }
        statuses = need.filter_map do |p, (present, why)|
          next unless m[p]
          # HubSpot gives the option value ("pending"); compare and show the label ("Needs Ordering")
          cur = HubSpotRoom.label_of(theirs[p].to_s, m[p]['all_options'] || m[p]['options'] || []).to_s
          want = present ? NEEDS : NA
          done = STATUS_DONE.include?(cur)
          flag = if done && !present then "#{cur} in HubSpot, but nothing in the model needs it (#{why}) - check it"
                 elsif done then "Already #{cur} - left as it is. Check the order still matches the model."
                 end
          { 'prop' => p, 'label' => m[p]['label'], 'section' => 'Order statuses', 'hubspot' => cur, 'value' => done ? cur : want,
            'why' => why, 'send' => !done && cur != want, 'flag' => flag, 'locked' => done }
        end
        { 'linked' => true, 'room' => l['room_name'], 'room_id' => l['room_id'], 'rows' => rows + statuses,
          'stage' => HubSpotRoom.stage_info(theirs['hs_pipeline_stage']), 'stage_id' => theirs['hs_pipeline_stage'],
          'theirs' => theirs, 'missing_colours' => missing_colours, 'labels' => required.to_h { |r| [r, m.dig(r, 'label') || r] }.merge('order_parts_list' => 'Order / Parts List'),
          'has_files' => !theirs['order_parts_list'].to_s.empty?, 'url' => (HubSpot.record_url('listings', l['room_id']) rescue nil) }
      end

      # Saves the door order and the parts list (PDF each; CSV too if set in Settings). Returns [paths..., versions].
      def self.save(model, parts)
        door = Report.write_order(model, parts: parts)
        part = PartsList.export(model, parts)
        # One Room Plan PDF (cover, product list, installation plan, pod sheet, panel list).
        plan = begin
          RoomPlan.write(model, parts)
        rescue StandardError => e
          Log.error('room plan', e)
          nil
        end
        { 'files' => [door[1], door[0], part[1], part[0]].compact, 'plan' => plan&.first, 'door_v' => door[2], 'parts_v' => part[2], 'plan_v' => plan&.last }
      end

      # --- checks when the window opens, fixed with one click ------------------------------

      # What can be put right straight away: scribes off (turned on with the job's runouts) and
      # colours not set up in OpenCutList (parts left out of the lists). [{ id, text, ... }]
      def self.checks(model, parts)
        out = []
        if !HubSpotRoom.customer_link(model) && !model.path.to_s.empty? && !(defined?(LibraryExport) && LibraryExport.master?(model))
          out << { 'id' => 'hubspot', 'text' => 'This file isn\'t linked to its HubSpot customer - the PDFs and labels need the customer, account and drawing number.',
                   'fix' => 'Link it: pick the customer\'s project, then its Room (or Design Visit if it has none).' }
        end
        wrong = wrong_hinges(model)
        unless wrong.empty?
          out << { 'id' => 'hinges', 'text' => "#{wrong.size} door(s) have the wrong hinges: #{wrong.first(6).map { |w| "#{w[:label]} (#{w[:have]}, should be #{w[:want]})" }.join(', ')}#{wrong.size > 6 ? '...' : ''}.",
                   'fix' => 'Redraw those doors with the right hinges (style kept).' }
        end
        units = Runouts.units(model.entities)
        if !parts['scribes_on'] && !units.empty?
          v = Runouts.job_values(model)
          out << { 'id' => 'scribes', 'text' => 'Scribes are OFF (every runout 0) - panel sizes may be wrong.',
                   'fix' => "Turn scribes on for #{units.size} unit(s): #{Runouts::SIDES.map { |s, _, l| "#{l.sub(/\ARunout - /, '').sub(' (mm)', '')} #{v[s].round}" }.join(', ')} mm" }
        end
        known = OpenCutList.desired
        cols = Array(parts['untyped']).reject { |u| u['name'].empty? }.map do |u|
          want = known[u['name']]
          { 'name' => u['name'], 'count' => u['count'], 'known' => want ? want['why'] : nil,
            'default' => want ? (want['type'] == OpenCutList::HARDWARE ? 'hardware' : 'sheet') : (u['name'] =~ /HARDWARE|INTERFIT|BLUM|STEEL|CHROME|ALUMIN/i ? 'hardware' : 'sheet') }
        end
        unless cols.empty?
          out << { 'id' => 'colours', 'text' => "#{cols.sum { |c| c['count'] }} part(s) have a colour that isn't set up as a sheet good or hardware, so they're left out.", 'colours' => cols }
        end
        none = Array(parts['untyped']).find { |u| u['name'].empty? }
        if none && !(defined?(LibraryExport) && LibraryExport.master?(model))
          cur = Colours.job_choices(model)
          dft = Colours.defaults
          groups = Colours::GROUPS.reject { |id, _| %w[panels_22 drawer_box].include?(id) }.map do |id, label|
            pick = [cur[id], dft[id]].find { |v| v && v != Colours::DEFAULT } || Colours::DEFAULT
            door = [cur['door'], dft['door']].find { |v| v && v != Colours::DEFAULT }
            dlabel = id != 'door' && door ? "#{Colours::DEFAULT} (#{door})" : Colours::DEFAULT
            { 'id' => id, 'label' => label, 'value' => pick, 'options' => [[Colours::DEFAULT, dlabel]] + Colours.names_for(id).map { |n| [n, n] } }
          end
          which = Array(parts['nocolour'])
          out << { 'id' => 'nocolour', 'text' => "#{none['count']} part(s) have no colour (no job colour chosen for their group yet), so they're left out: #{which.first(8).join(', ')}#{which.size > 8 ? '...' : ''}.",
                   'fix' => 'Apply the job colours (as the Colours window) - pick them below. Default on Exterior / Interior / Worktop = the door colour.', 'groups' => groups }
        end
        out
      end

      # Converted doors whose hinges aren't the ones they should have now (their own, the
      # default for their name - the stable wardrobe's big door 155 - or the job's): drawn
      # before the setting changed. [{ inst:, label:, have:, want: }]
      def self.wrong_hinges(model)
        job = Settings.job_hinge_type(model)
        Doors.processed(model, [:door]).filter_map do |inst, _k|
          next if Finder.fixed?(inst)
          d = inst.definition
          kids = d.entities.grep(Sketchup::ComponentInstance).select { |e| e.get_attribute(DICT, 'role') == 'hinge' }
          have = kids.first ? kids.first.get_attribute(DICT, 'type').to_s : d.get_attribute(DICT, 'hinge_type').to_s
          next if have.empty?
          want = Converter.hinge_for(inst, job)
          next if have == want
          { inst: inst, label: Finder.label(inst), have: Settings::HINGE_TYPES.fetch(have, have), want: Settings::HINGE_TYPES.fetch(want, want) }
        end
      end

      def self.fix_hinges(model)
        pairs = wrong_hinges(model).map { |w| [w[:inst], :door] }
        Converter.apply(pairs, nil, 'Redraw doors with the right hinges') unless pairs.empty?
        pairs.size
      end

      # Applies the job colours chosen in the checks box (the rest stay as they are).
      def self.set_job_colours(model, picks)
        choices = Colours.job_choices(model).transform_values { |v| v || Colours::DEFAULT }
        choices['drawer_box'] = DrawerBox::DEFAULT if choices['drawer_box'] == Colours::DEFAULT
        choices.merge!(picks.select { |k, _| choices.key?(k) })
        ColoursWindow.apply(model, choices)
      end

      # What stops the Workshop Pack being saved: anything that makes the lists wrong or
      # unfinished. A thickness outside the standard list is only a warning.
      def self.blockers(model, parts)
        out = []
        unless HubSpotRoom.customer_link(model)
          out << 'Link this file to its HubSpot customer first (HubSpot > Link this file) - the PDFs and labels take the customer, account and drawing number from it.'
        end
        wh = wrong_hinges(model).size
        out << "#{wh} door(s) have the wrong hinges - redraw them (Before you start box, or right-click > Rebuild selected)." if wh.positive?
        out << 'Scribes are OFF - turn them on (every runout is 0).' if !parts['scribes_on'] && !Runouts.units(model.entities).empty?
        n = Array(parts['untyped']).sum { |u| u['count'].to_i }
        out << "#{n} part(s) are left out (no colour, or a colour not set up as a sheet good or hardware)." if n.positive?
        parts['groups'].each do |g|
          next if %w[vinyl white_back].include?(g['section'])
          name = "#{g['material']} #{PartsList.fmt(g['thickness'])} mm"
          out << "#{name}: enter the full sheets needed (Sheet goods tab)." if g['ask'] && g['sheets'].nil?
          out << "#{name}: part(s) #{Array(g['too_big']).join(', ')} are bigger than the sheet." unless Array(g['too_big']).empty?
          out << "#{g['material']}: no sheet size set - no board count." if !g['sheet'] && !g['strip_group']
        end
        out
      end

      # Sets the chosen colours up in OpenCutList (as Settings > Cut list would). choice: name =>
      # 'sheet' / 'hardware' / '' (left as it is). One undo step.
      def self.set_colours(model, choice)
        known = OpenCutList.desired
        n = 0
        Ops.run(model, 'Set up colours (OpenCutList)') do
          choice.each do |name, kind|
            mat = model.materials[name] or next
            next if kind.to_s.empty?
            want = known[name]
            want = nil if want && (want['type'] == OpenCutList::HARDWARE) != (kind == 'hardware')
            want ||= if kind == 'hardware'
                       { 'type' => OpenCutList::HARDWARE }
                     else
                       { 'type' => OpenCutList::SHEET, 'std_thicknesses' => OpenCutList.thicknesses_s(OpenCutList.thicknesses_for(name)),
                         'std_sizes' => OpenCutList.sizes_s(OpenCutList.sheet_sizes), 'grained' => mat.texture ? true : false }
                     end
            mat.set_attribute(OpenCutList::DICT_NAME, 'type', want['type'])
            if want['type'] == OpenCutList::SHEET
              %w[std_thicknesses std_sizes grained].each { |k| mat.set_attribute(OpenCutList::DICT_NAME, k, want[k]) }
            end
            n += 1
          end
        end
        n
      end

      # Scribes on for every unit with the job's runouts (as the Scribe window's Apply), then after.
      def self.scribes_on(model, after)
        v = Runouts.job_values(model)
        Runouts.apply(model, Runouts.units(model.entities), v, 'Scribes on',
                      "Scribes on: #{Runouts::SIDES.map { |s, _, _| "#{s} #{v[s].round}" }.join(', ')} mm.",
                      before: lambda {
                        model.set_attribute(DICT, 'scribe_on', true)
                        model.set_attribute(DICT, 'scribe_values', JSON.generate(v))
                      }, after: after)
      end

      PDF_KINDS = [['DOOR_ORDER', 'Door / Vinyl order'], ['PARTS_LIST', 'Parts list'], ['ROOM_PLAN', 'Room Plan']].freeze

      # The latest PDF of each kind saved for this model (next to it): [{ title, name, path, v, date }].
      def self.pdfs(model)
        return [] if model.path.to_s.empty?
        dir = File.dirname(model.path)
        base = Report.safe_name(File.basename(model.path, '.skp'))
        return [] unless Dir.exist?(dir)
        names = Dir.children(dir)
        PDF_KINDS.filter_map do |kind, title|
          re = /\A#{kind}_v(\d+)_#{Regexp.escape(base)}\.pdf\z/i
          best = names.filter_map { |n| (m = n.match(re)) && [m[1].to_i, n] }.max_by(&:first)
          next unless best
          path = File.join(dir, best[1])
          { 'title' => "#{title} v#{best[0]}", 'name' => best[1], 'path' => path, 'v' => best[0], 'date' => File.mtime(path).strftime('%d/%m/%Y %H:%M') }
        end
      end

      # The labels of a pack, saved next to the PDFs as the exact ZPL that will be printed.
      def self.save_labels(model, zpl, version)
        path = File.join(File.dirname(model.path), "LABELS_v#{version}_#{Report.safe_name(File.basename(model.path, '.skp'))}.zpl")
        File.binwrite(path, zpl)
        path
      end

      # Uploads the four files into Order / Parts List (replacing the last ones), sends the
      # ticked values and, only if chosen, moves the stage.
      def self.send_room(model, room_id, files, values, stage, plan: nil)
        folder = HubSpotPictures.config['files_folder']
        ids = files.map { |f| HubSpot.upload(f, folder) }
        props = values.merge(PartsList::FIELD => ids.join(';'))
        if plan && File.exist?(plan)
          # Floor Plan keeps the survey pictures; the last installation plan is replaced.
          pid = HubSpot.upload(plan, folder)
          cur = (HubSpot.read_one('listings', room_id, ['floor_plan'])['properties'] || {})['floor_plan'].to_s.split(';')
          last = model.get_attribute(DICT, 'plan_hs_file').to_s
          props['floor_plan'] = (cur.reject { |x| x == last || x.empty? } + [pid]).join(';')
          Ops.run(model, 'HubSpot: record plan', transparent: true) { model.set_attribute(DICT, 'plan_hs_file', pid.to_s) }
          ids << pid
        end
        props['hs_pipeline_stage'] = stage if stage && !stage.to_s.empty?
        HubSpot.update_room(room_id, props)
        Ops.run(model, 'HubSpot: record workshop send', transparent: true) { model.set_attribute(DICT, 'hs_workshop_sent_at', Time.now.strftime('%d/%m/%Y %H:%M')) }
        ids.size
      end
    end
  end
end
