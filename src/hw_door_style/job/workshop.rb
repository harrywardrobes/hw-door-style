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
        doors = Report.rows(model).size
        worktop = parts['groups'].any? { |g| (g['thickness'] - 25).abs < 0.5 && g['material'] != 'MDF' }
        sheets = parts['groups'].any? { |g| !((g['thickness'] - 25).abs < 0.5 && g['material'] != 'MDF') }
        {
          'door_vinyl_order_status' => [doors.positive?, "#{doors} door(s) / drawer front(s)"],
          'drawer_order_status' => [(c['ext_drawers'] + c['int_drawers']).positive?, "#{c['ext_drawers'] + c['int_drawers']} drawer(s)"],
          'sheets_order_status' => [sheets, sheets ? 'board in the parts list' : 'no boards'],
          'hardware_order_status' => [!parts['hardware'].empty? || parts['handles'].any? { |h| h['qty'].to_i.positive? }, "#{parts['hardware'].sum { |h| h['qty'] }} hardware piece(s)"],
          'worktop_order_status' => [worktop, worktop ? '25mm board (worktop)' : 'no 25mm worktop board']
        }
      end

      QTY_FIELDS = (HubSpotRoom::HINGE_FIELDS.values + %w[blum_push_tipon_set drawer_total_quantity drawer_type
                                                          main_robe_handle main_robe_handle_id robe_handle_supplier main_robe_handle_quantity
                                                          drawer_handle drawer_handle_sku drawer_handle_supplier drawer_handle_quantity
                                                          interior_handle interior_handle_sku interior_handle_supplier interior_handle_quantity]).freeze

      # Rows for the HubSpot tab: [{ prop, label, section, hubspot, value, shown, send, flag }].
      def self.plan(model, parts)
        l = HubSpotRoom.link(model) or return { 'linked' => false }
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
          { 'prop' => p, 'label' => m[p]['label'], 'section' => section, 'hubspot' => cur, 'value' => v, 'shown' => shown,
            'send' => v.to_s != cur.to_s && !(v.nil? && cur.to_s.empty?) }
        end
        missing_colours = parts['groups'].map { |g| g['material'] }.uniq.reject { |n| m["mfc_sheets_#{PartsList.slug(n)}"] }
        statuses = need.filter_map do |p, (present, why)|
          next unless m[p]
          cur = theirs[p].to_s
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

      # Saves the door order and the parts list (CSV + PDF each). Returns [paths..., versions].
      def self.save(model, parts)
        door = Report.write_order(model)
        part = PartsList.export(model, parts)
        { 'files' => [door[1], door[0], part[1], part[0]], 'door_v' => door[2], 'parts_v' => part[2] }
      end

      # Uploads the four files into Order / Parts List (replacing the last ones), sends the
      # ticked values and, only if chosen, moves the stage.
      def self.send_room(model, room_id, files, values, stage)
        folder = HubSpotPictures.config['files_folder']
        ids = files.map { |f| HubSpot.upload(f, folder) }
        props = values.merge(PartsList::FIELD => ids.join(';'))
        props['hs_pipeline_stage'] = stage if stage && !stage.to_s.empty?
        HubSpot.update_room(room_id, props)
        Ops.run(model, 'HubSpot: record workshop send', transparent: true) { model.set_attribute(DICT, 'hs_workshop_sent_at', Time.now.strftime('%d/%m/%Y %H:%M')) }
        ids.size
      end
    end
  end
end
