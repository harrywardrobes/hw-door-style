require 'json'

module HarryWardrobes
  module DoorStyle
    # One SketchUp file = one HubSpot Room (Listing). Extensions > HW Door Style > HubSpot.
    #
    #   New room from HubSpot  pick a Project, then one of its Rooms: the survey file is
    #                          made in the customer's folder (1_CUSTOMERS\... (<contact id>))
    #                          as "SURVEY - <room> - <customer>.skp", linked to the Room.
    #   Link this file         the same, for a file that already exists.
    #   Design Visit           a project with no Rooms yet: the file is linked to the project
    #                          and customer only ("DESIGN VISIT - <customer>.skp"). Opening it
    #                          again checks the project: once a Room exists it asks which one
    #                          and saves the file as the usual SURVEY file linked to it (the
    #                          design visit file is left as it was).
    #   Send to HubSpot        every agreed field, SketchUp next to HubSpot; nothing is
    #                          written until Send is pressed. Some fields can also be
    #                          taken from HubSpot into the file (ceiling, runouts, colours).
    #
    # The link lives on the model (dictionary hw_door_style, keys hs_*).
    module HubSpotRoom
      CUSTOMERS_DIR = 'H:/Shared drives/Harry Wardrobes/1_CUSTOMERS'.freeze
      ROOM_PROPS = %w[hs_name].freeze
      CONTACT_PROPS = %w[firstname lastname address city zip].freeze

      # Fields HubSpot keeps that SketchUp only shows (handles, door range).
      INFO_FIELDS = [
        ['door_style', 'Door style'],
        ['main_robe_handle', 'Robe handle'], ['main_robe_handle_id', 'Robe handle SKU'],
        ['drawer_handle', 'Drawer handle'], ['drawer_handle_sku', 'Drawer handle SKU'],
        ['interior_handle', 'Interior handle'], ['interior_handle_sku', 'Interior handle SKU']
      ].freeze

      HINGE_FIELDS = {
        'soft_close_110' => 'hinge_quantity_blum_110',
        'soft_close_155' => 'hinge_quantity_blum_155',
        'pto_110' => 'hinge_quantity_blum_110_pto',
        'pto_155' => 'hinge_quantity_blum_155_pto'
      }.freeze

      COLOUR_FIELDS = {
        'door' => 'door_drawer_colour', 'exterior' => 'exterior_panel_trim_colour',
        'interior' => 'interior_colour', 'worktop' => 'worktop_colour'
      }.freeze

      RUNOUT_FIELDS = {
        'floor' => 'runout_floor_mm', 'ceiling' => 'runout_ceiling_mm', 'left' => 'runout_left_mm',
        'right' => 'runout_right_mm', 'back' => 'runout_back_wall_mm'
      }.freeze

      # --- the link -------------------------------------------------------------------

      LINK_KEYS = %w[hs_room_id hs_project_id hs_contact_id hs_room_name hs_customer hs_first_name hs_last_name hs_address hs_info hs_design_visit].freeze

      def self.link(model = Sketchup.active_model)
        h = LINK_KEYS.to_h { |k| [k.sub('hs_', ''), model.get_attribute(DICT, k, nil)] }
        h['info'] = (JSON.parse(h['info'].to_s) rescue {})
        h['room_id'] ? h : nil
      end

      # The link to the customer, with or without a Room (a design visit has none).
      def self.customer_link(model = Sketchup.active_model)
        h = LINK_KEYS.to_h { |k| [k.sub('hs_', ''), model.get_attribute(DICT, k, nil)] }
        h['info'] = (JSON.parse(h['info'].to_s) rescue {})
        h['room_id'] || h['project_id'] ? h : nil
      end

      def self.design_visit?(model = Sketchup.active_model)
        h = customer_link(model)
        !!(h && !h['room_id'] && h['design_visit'])
      end

      def self.store_link(model, l)
        LINK_KEYS.each do |k|
          v = l[k.sub('hs_', '')]
          v = JSON.generate(v) if v.is_a?(Hash)
          model.set_attribute(DICT, k, v.nil? ? nil : v.to_s)
        end
      end

      # --- names and folders (no SketchUp / HubSpot needed: tested offline) -----------

      # "Kenny Hasprey - Connah's Quay - Master Bedroom" -> "Master Bedroom"
      def self.room_part(name)
        s = name.to_s.split(' - ').last.to_s.strip
        s.empty? ? 'room' : s
      end

      # "SURVEY - grace's room - charlotte reid.skp" / "DESIGN VISIT - master bedroom - charlotte reid.skp"
      # (room and customer in small letters).
      def self.job_file_name(room, customer, design_visit: false)
        parts = [design_visit ? 'DESIGN VISIT' : 'SURVEY', room.to_s.strip.gsub(/\s+/, ' ').downcase, customer.to_s.strip.gsub(/\s+/, ' ').downcase]
        Report.safe_name(parts.reject(&:empty?).join(' - ')) + '.skp'
      end

      # A HubSpot Room's file: its name's room part ("Kenny Hasprey - Connah's Quay - Master Bedroom").
      def self.file_name(room_name, customer) = job_file_name(room_part(room_name), customer)

      def self.design_file_name(customer, room = nil) = job_file_name(room, customer, design_visit: true)

      # A new customer folder: "REID, Charlotte - Chester - (870739371231)" (no town: "REID, Charlotte - (870739371231)").
      def self.folder_name(l)
        head = [l['last_name'].to_s.strip.upcase, first_names(l)].reject(&:empty?).join(', ')
        [head, l['city'].to_s.strip.gsub(/\s+/, ' '), "(#{l['contact_id']})"].reject(&:empty?).join(' - ')
      end

      # The customer's folder: "WILLIAMS Rebecca (Rossett - 830735284436)" or "... (830735284436)".
      def self.customer_folder(contact_id, root = CUSTOMERS_DIR)
        return nil if contact_id.to_s.empty? || !Dir.exist?(root)
        d = Dir.children(root).find { |n| n =~ /\((?:[^()]*\D)?#{Regexp.escape(contact_id.to_s)}\)\s*\z/ && File.directory?(File.join(root, n)) }
        d && File.join(root, d)
      end

      # Plugin colour name -> HubSpot dropdown value. Letters and numbers only, any case;
      # one or two letters out still matches (HubSpot's "Ingigo Blue" = Indigo Blue).
      def self.match_option(name, options)
        return nil if name.to_s.empty?
        norm = ->(s) { s.to_s.downcase.gsub(/[^a-z0-9]/, '') }
        n = norm.call(name)
        hit = options.find { |l, v| norm.call(l) == n || norm.call(v) == n }
        hit ||= options.map { |l, v| [distance(norm.call(l), n), l, v] }.select { |d, _, _| d <= 2 && n.size > 4 }.min_by(&:first)&.drop(1)
        hit && hit[1]
      end

      def self.distance(a, b)
        prev = (0..b.size).to_a
        a.each_char.with_index(1) do |ca, i|
          cur = [i]
          b.each_char.with_index(1) { |cb, j| cur << [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb ? 0 : 1)].min }
          prev = cur
        end
        prev.last
      end

      # Dropdown / yes-no / checkbox fields take HubSpot's internal option values ("pending"),
      # not the labels shown ("Needs Ordering"): any label is swapped for its value before
      # sending (checkboxes: each of the ;-separated answers). Values already right are kept.
      def self.to_values(props, m = (meta rescue {}))
        props.to_h do |p, v|
          opts = m.dig(p, 'all_options') || m.dig(p, 'options')
          next [p, v] if opts.nil? || opts.empty? || v.nil? || v.to_s.empty? || !%w[enumeration bool].include?(m[p]['type'])
          fix = lambda do |x|
            x = x.to_s.strip
            next x if opts.any? { |_l, val| val.to_s == x }
            hit = opts.find { |l, _val| l.to_s.casecmp?(x) }
            hit ? hit[1].to_s : x
          end
          [p, m[p]['field'] == 'checkbox' ? v.to_s.split(';').map(&fix).join(';') : fix.call(v)]
        end
      end

      def self.label_of(value, options)
        hit = options.find { |_l, v| v.to_s == value.to_s }
        hit ? hit[0] : value
      end

      # Number fields: blank and 0 count as the same.
      def self.same?(a, b, number)
        return (a.to_s.strip.empty? ? 0.0 : a.to_f).round(1) == (b.to_s.strip.empty? ? 0.0 : b.to_f).round(1) if number
        a.to_s.strip == b.to_s.strip
      end

      # --- the Room card, as laid out in HubSpot ---------------------------------------------

      FILE_FIELDS = %w[render_1 floor_plan survey_door_dimensions_1 installation_reference_images order_parts_list].freeze

      LAYOUT = [
        ['Survey (SketchUp)', %w[room_width_mm room_depth_mm bottom_facing_mm runout_floor_mm runout_ceiling_mm
                                 runout_left_mm runout_right_mm runout_back_wall_mm runout_exceptions]],
        ['Survey Questions', %w[type_of_flooring flooring_requirements flooring_requirement_notes bed_requirements
                                bed_requirement_notes cutting_location cutting_location_notes internal_sides
                                internal_sides_description notes]],
        ['Colours + Style', %w[door_drawer_colour door_style exterior_panel_trim_colour interior_colour worktop_colour]],
        ['Internal + External Hardware', %w[main_robe_handle main_robe_handle_id robe_handle_supplier main_robe_handle_quantity
                                            drawer_handle drawer_handle_sku drawer_handle_supplier drawer_handle_quantity
                                            interior_handle interior_handle_sku interior_handle_supplier interior_handle_quantity
                                            cable_outlet_quantity internal_mirror_quantity_1150x300]],
        ['Blum Hinges', %w[hinge_quantity_blum_110 hinge_quantity_blum_110_pto hinge_quantity_blum_155
                           hinge_quantity_blum_155_pto hinge_restrictors_required blum_push_tipon_set]],
        ['Drawer Boxes', %w[drawer_type drawer_total_quantity]],
        ['Order List', %w[door_vinyl_order_status door_vinyl_order_ref door_vinyl_delivery_date drawer_order_status
                          drawer_order_ref drawer_delivery_date sheets_order_status sheets_order_ref sheets_delivery_date
                          hardware_order_status hardware_order_ref hardware_delivery_date worktop_order_status
                          worktop_order_ref worktop_delivery_date stock_screw_caps stock_wax_stick order_parts_list]],
        ['Renders + Floor Plan', %w[render_1 floor_plan survey_door_dimensions_1]],
        ['Installation Info', %w[ceiling_height_mm hs_listing_type room_subtype project_surveyor_assigned installer_assigned
                                 installation_notes project_site_requirements installation_reference_images carpet_line_present]],
        ['Delivery Info', %w[project_material_delivery_date delivery_notes material_delivery_date]],
        ['Object Dimensions', %w[bed_width_mm bed_length_mm bed_height_mm tv_width_mm tv_height_mm]]
      ].freeze

      # Field details from HubSpot (label, kind of field, dropdown options), read once a session.
      def self.meta
        @meta ||= begin
          all = HubSpot.get('/crm/v3/properties/listings')['results']
          owners = nil
          all.to_h do |p|
            # archived (hidden) answers aren't offered; 'all_options' keeps them for reading old values
            all_opts = Array(p['options']).map { |o| [o['label'], o['value']] }
            opts = Array(p['options']).reject { |o| o['hidden'] }.map { |o| [o['label'], o['value']] }
            note = nil
            if p['referencedObjectType'] == 'OWNER'
              owners ||= (HubSpot.owners rescue :none)
              opts = owners == :none ? [] : owners
              note = 'needs the Users permission on the key' if owners == :none
            end
            ro = (p['modificationMetadata'] || {})['readOnlyValue'] ? true : false
            [p['name'], { 'label' => p['label'], 'type' => p['type'], 'field' => p['fieldType'], 'options' => opts, 'all_options' => all_opts, 'group' => p['groupName'], 'hidden' => p['hidden'] ? true : false,
                          'readonly' => ro || !note.nil?, 'note' => note || (ro ? 'set on the Project' : nil) }]
          end
        end
      end

      def self.forget_meta!
        @meta = nil
      end

      # --- what SketchUp says ---------------------------------------------------------------

      def self.floor(model)
        hit = nil
        walk = lambda do |ents, tr, depth|
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            t = tr * e.transformation
            n = (e.is_a?(Sketchup::ComponentInstance) ? (DC.read(e, '_name') || e.definition.name) : e.name).to_s
            return hit = [e, t] if n =~ /\Afloor\z/i
            walk.call(e.definition.entities, t, depth + 1) if depth < 6
            return if hit
          end
        end
        walk.call(model.entities, Geom::Transformation.new, 0)
        hit
      end

      # Room width x depth (mm) from the FLOOR component as drawn: its own size times
      # every scale on the way down (the Scale tool doesn't update the DC LenX / LenY).
      def self.floor_mm(model)
        e, t = floor(model)
        return nil unless e
        b = e.definition.bounds
        sx = Geom::Vector3d.new(t.to_a[0], t.to_a[1], t.to_a[2]).length.to_f
        sy = Geom::Vector3d.new(t.to_a[4], t.to_a[5], t.to_a[6]).length.to_f
        [(b.width.to_f * sx * 25.4).round, (b.height.to_f * sy * 25.4).round]
      end

      CABLE_OUTLET = /\ACABLE_OUTLET/i.freeze

      # Cable outlets showing in the model (a WORKTOP's outlets switched off in its options
      # are hidden, so they don't count).
      def self.cable_outlets(ents)
        ents.sum do |e|
          next 0 unless (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && e.visible?
          next 1 if e.respond_to?(:definition) && e.definition.name =~ CABLE_OUTLET
          cable_outlets(e.respond_to?(:definition) ? e.definition.entities : e.entities)
        end
      end

      def self.counts(model)
        rows = Report.rows(model)
        by_label = Settings::HINGE_TYPES.invert
        hinges = Hash.new(0)
        rows.each { |r| hinges[by_label[r['hinge_type']] || r['hinge_type']] += r['hinges'].to_i if r['hinges'].to_i > 0 }
        kinds = ->(k) { rows.select { |r| r['kind_id'] == k.to_s } }
        handles = ->(k) { kinds.call(k).sum { |r| r['handles'].to_i } }
        {
          'hinges' => hinges, 'tip_on' => rows.sum { |r| r['tip_on'].to_i },
          'ext_drawers' => kinds.call(:ext_drawer).size, 'int_drawers' => kinds.call(:int_drawer).size,
          'h_door' => handles.call(:door), 'h_ext' => handles.call(:ext_drawer), 'h_int' => handles.call(:int_drawer),
          'cable_outlets' => cable_outlets(model.entities)
        }
      end

      def self.drawer_type(ext, int)
        return 'Both (Internal and External)' if ext > 0 && int > 0
        return 'External' if ext > 0
        return 'Internal' if int > 0
        'None / Not Applicable'
      end

      def self.exceptions(model)
        Runouts.report(model).map { |label, d| "#{label}: #{d.join(', ')}" }.join("\n")
      end

      # The job's colour for each row as painted: "Default" exterior / interior / worktop
      # follow the door colour, like the Colours window.
      def self.colour_names(model)
        choices = Colours.defaults.merge(Colours.job_choices(model).compact)
        Colours.resolved(model, choices).transform_values { |n| n == Colours::DEFAULT ? nil : n }
      end

      # Values SketchUp works out: { prop => { 'value' (HubSpot form), 'shown', 'take' (file can take
      # HubSpot's value), 'note' } }.
      def self.calculated(model, m = meta)
        c = counts(model)
        out = {}
        put = ->(prop, value, take: false, shown: nil, note: nil) { out[prop] = { 'value' => value, 'shown' => shown, 'take' => take, 'note' => note } }
        w, d = floor_mm(model)
        put.call('room_width_mm', w, note: w ? nil : 'no FLOOR component')
        put.call('room_depth_mm', d, note: d ? nil : 'no FLOOR component')
        ceil = Ceiling.mm(model)
        put.call('ceiling_height_mm', ceil > 0 ? ceil.round : nil, take: true)
        put.call('bottom_facing_mm', Facing.mm(model).round, take: true)
        jv = Runouts.job_values(model)
        RUNOUT_FIELDS.each { |side, prop| put.call(prop, jv[side].round, take: true) }
        put.call('runout_exceptions', exceptions(model))
        names = colour_names(model)
        COLOUR_FIELDS.each do |gid, prop|
          name = names[gid]
          val = match_option(name, m.dig(prop, 'options') || [])
          put.call(prop, val, take: !(name && !val), shown: name, note: name && !val ? "#{name} isn't in HubSpot's list" : nil)
        end
        Settings::HINGE_TYPES.each_key { |id| put.call(HINGE_FIELDS[id], c['hinges'][id].to_i) }
        put.call('blum_push_tipon_set', c['tip_on'])
        put.call('drawer_total_quantity', c['ext_drawers'] + c['int_drawers'])
        dt = drawer_type(c['ext_drawers'], c['int_drawers'])
        put.call('drawer_type', match_option(dt, m.dig('drawer_type', 'options') || []), shown: dt)
        names = DoorStyleWindow.handle_names(model)
        DoorStyleWindow::HANDLE_NAMES.each { |prop, _l| put.call(prop, names[prop].to_s.empty? ? nil : names[prop], take: true) }
        HubSpotProducts::ROOM_SUPPLIER.each_value do |prop, _l|
          v = names[prop].to_s
          put.call(prop, v.empty? ? nil : v, take: true, shown: v.empty? ? nil : HubSpotProducts.supplier_label(v))
        end
        put.call('main_robe_handle_quantity', c['h_door'])
        put.call('drawer_handle_quantity', c['h_ext'])
        put.call('interior_handle_quantity', c['h_int'])
        put.call('cable_outlet_quantity', c['cable_outlets'])
        out
      end

      # Everything the window needs: sections of rows with HubSpot's value and SketchUp's.
      def self.card(model, room_id)
        m = meta
        calc = calculated(model, m)
        theirs = room_values(room_id, m)
        [card_sections(m, calc, theirs), theirs['hs_name'], stage_info(theirs['hs_pipeline_stage'])]
      end

      def self.room_values(room_id, m = meta)
        props = LAYOUT.flat_map(&:last).select { |p| m[p] }
        HubSpot.read_one('listings', room_id, props + %w[hs_name hs_pipeline_stage])['properties'] || {}
      end

      def self.card_sections(m, calc, theirs)
        LAYOUT.map do |title, list|
          rows = list.filter_map do |p|
            f = m[p] or next
            hs = theirs[p]
            hs = hs.to_s[0, 10] if f['type'] == 'date' && hs
            r = { 'prop' => p, 'label' => f['label'], 'field' => f['field'], 'type' => f['type'], 'options' => f['options'],
                  'hubspot' => hs, 'file' => FILE_FIELDS.include?(p),
                  'readonly' => f['readonly'] || f['field'] == 'calculation_equation', 'note' => f['note'] }
            r.merge!('calc' => true, 'sketchup' => calc[p]['value'], 'shown' => calc[p]['shown'], 'take' => calc[p]['take'], 'note' => calc[p]['note'] || r['note']) if calc[p]
            r
          end
          { 'title' => title, 'rows' => rows }
        end
      end

      # The Room's stage and the stages after it, each with the fields needed to move
      # into it (Settings > HubSpot > Required to move on).
      def self.stage_info(current_id)
        stages = HubSpot.room_stages rescue []
        req = Settings.get['hubspot_required'] || {}
        i = stages.index { |st| st['id'] == current_id.to_s }
        later = i ? stages[(i + 1)..] : stages
        { 'current' => i ? stages[i]['label'] : nil,
          'next' => later.map { |st| { 'id' => st['id'], 'label' => st['label'], 'required' => Array(req[st['id']]) } } }
      end

      # Fields still empty that the chosen stage needs: [labels]. values: { prop => value }.
      def self.missing(required, values, labels = {})
        required.select { |p| values[p].to_s.strip.empty? }.map { |p| labels[p] || p }
      end

      # --- doing it ------------------------------------------------------------------------

      # send: { prop => new HubSpot value }; take: { prop => value for this file }.
      def self.send_and_take(model, room_id, send, take)
        HubSpot.update_room(room_id, send) unless send.empty?
        took = take_values(model, take)
        Ops.run(model, 'HubSpot: record send', transparent: true) do
          model.set_attribute(DICT, 'hs_sent_at', Time.now.strftime('%d/%m/%Y %H:%M'))
        end
        took
      end

      # Into this file. Job values first (one step), then colours (their own step);
      # the units are then offered the new values through the pencil window.
      def self.take_values(model, take)
        return [] if take.empty?
        took = []
        runouts = Runouts.job_values(model)
        Ops.run(model, 'Values from HubSpot') do
          take.each do |prop, v|
            case prop
            when 'ceiling_height_mm'
              model.set_attribute(DICT, 'ceiling_mm', v.to_f)
              Room.apply(model, ceiling: v.to_f) if defined?(Room) && v.to_f.positive?
              took << 'ceiling'
            when 'bottom_facing_mm'
              model.set_attribute(DICT, 'facing_btm_mm', v.to_f)
              took << 'bottom facing'
            else
              side = RUNOUT_FIELDS.key(prop)
              if side
                runouts[side] = v.to_f
                took << 'runouts'
              end
            end
          end
          model.set_attribute(DICT, 'scribe_values', JSON.generate(runouts)) if took.include?('runouts')
          hn = (DoorStyleWindow::HANDLE_NAMES.map(&:first) + HubSpotProducts::ROOM_SUPPLIER.values.map(&:first)) & take.keys
          unless hn.empty?
            names = DoorStyleWindow.handle_names(model).merge(take.slice(*hn).transform_values(&:to_s))
            model.set_attribute(DICT, 'job_handle_names', JSON.generate(names))
            took << 'handle names'
          end
        end
        colours = COLOUR_FIELDS.select { |_gid, prop| take.key?(prop) }
        unless colours.empty?
          choices = Colours.job_choices(model).compact
          choices['drawer_box'] ||= Colours.defaults['drawer_box']
          colours.each do |gid, prop|
            label = label_of(take[prop], meta.dig(prop, 'all_options') || meta.dig(prop, 'options') || [])
            choices[gid] = label.to_s.empty? ? Colours::DEFAULT : closest_colour(label, gid)
          end
          ColoursWindow.apply(model, choices)
          took << 'colours'
        end
        took.uniq
      end

      # HubSpot colour label -> the plugin's own colour name (same matching rule).
      def self.closest_colour(label, gid)
        names = Colours.names_for(gid).map { |n| [n, n] }
        match_option(label, names) || label
      end

      # --- windows ---------------------------------------------------------------------------

      def self.ready?
        return true if HubSpot.key?
        UI.messagebox("No HubSpot key yet.\n\nSettings > HubSpot: paste the private app key, then Test connection.")
        false
      end

      def self.fail(what, e)
        Log.error("hubspot #{what}", e) unless e.is_a?(HubSpot::Error)
        UI.messagebox("HubSpot: #{what} failed.\n\n#{e.message}")
      end

      # mode :new (make the survey file) or :link (link the open file).
      # after: called once the file has been linked (the Workshop reopens with the new link).
      def self.show_pick(mode, after: nil)
        return unless ready?
        model = Sketchup.active_model
        cur = link(model)
        if mode == :link && model.path.to_s.empty?
          return UI.messagebox('Save this file first, or use "New room from HubSpot" to make it in the customer folder.')
        end
        dv = customer_link(model) if mode == :connect
        data = { 'mode' => mode.to_s, 'linked' => cur ? cur['room_name'] : (design_visit?(model) ? 'a design visit (no Room)' : nil),
                 'file' => File.basename(model.path.to_s), 'project_id' => dv && dv['project_id'], 'customer' => dv && dv['customer'] }
        title = { new: 'HW - New room from HubSpot', link: 'HW - Link to a HubSpot room', connect: 'HW - Connect this design visit to a Room' }[mode]
        dlg = Dialog.open('hubspot_pick', title: title,
                                          key: 'hw_hubspot_pick', width: 560, height: 520, data: data)
        dlg.add_action_callback('search') do |_c, q|
          Steps.one(dlg, q.to_s.strip.empty? ? 'Reading recent projects' : "Searching HubSpot for \"#{q.to_s.strip}\"",
                    done: ->(r) { dlg.execute_script("projects(#{JSON.generate('projects' => r)})") },
                    fail: ->(e) { dlg.execute_script("projects(#{JSON.generate('error' => e.message)})") }, bg: true) { HubSpot.search_projects(q) }
        end
        dlg.add_action_callback('project') do |_c, pid|
          Steps.one(dlg, 'Reading the rooms and customer',
                    done: ->(r) { dlg.execute_script("rooms(#{JSON.generate(r)})") },
                    fail: ->(e) { dlg.execute_script("rooms(#{JSON.generate('error' => e.message)})") }, bg: true) { project_details(pid.to_s) }
        end
        dlg.add_action_callback('choose') do |_c, json|
          pick = JSON.parse(json)
          dlg.close
          before = customer_link(model)
          case mode
          when :new then create_file(pick)
          when :connect then connect_design_visit(model, pick)
          else link_open_file(model, pick)
          end
          after.call if after && model.valid? && customer_link(model) != before
        end
        dlg.show
      end

      # Rooms of a project, the customer and their folder.
      def self.project_details(pid)
        room_ids = HubSpot.linked_ids('projects', pid, 'listings')
        rooms = HubSpot.read_many('listings', room_ids, ROOM_PROPS).map { |r| { 'id' => r['id'], 'name' => r.dig('properties', 'hs_name').to_s } }
        contact_id = HubSpot.linked_ids('projects', pid, 'contacts').first
        c = contact_id ? (HubSpot.read_one('contacts', contact_id, CONTACT_PROPS)['properties'] || {}) : {}
        customer = [c['firstname'], c['lastname']].compact.join(' ').strip
        folder = customer_folder(contact_id)
        rooms.each do |r|
          r['file'] = file_name(r['name'], customer)
          r['exists'] = folder ? File.exist?(File.join(folder, r['file'])) : false
        end
        design = design_file_name(customer)
        { 'project_id' => pid, 'rooms' => rooms.sort_by { |r| r['name'] }, 'contact_id' => contact_id, 'customer' => customer,
          'first_name' => c['firstname'].to_s.strip, 'last_name' => c['lastname'].to_s.strip, 'city' => c['city'].to_s.strip,
          'address' => [c['address'], c['city'], c['zip']].compact.map { |x| x.gsub(/[\s,]*\n\s*/, ', ').strip }.reject(&:empty?).join(', '),
          'folder' => folder, 'folder_name' => folder && File.basename(folder), 'design_file' => design }
      end

      def self.link_from(pick)
        dv = pick['design_visit'] ? true : false
        { 'room_id' => dv ? nil : pick['room_id'], 'project_id' => pick['project_id'], 'contact_id' => pick['contact_id'],
          'room_name' => dv ? nil : pick['room_name'], 'customer' => pick['customer'], 'first_name' => pick['first_name'],
          'last_name' => pick['last_name'], 'address' => pick['address'], 'info' => {}, 'design_visit' => dv ? '1' : nil }
      end

      # "WILLIAMS Rebecca" (last name in capitals, first names capitalised).
      def self.customer_tag(l)
        [l['last_name'].to_s.strip.upcase, first_names(l)].reject(&:empty?).join(' ')
      end

      # "mary-jane" -> "Mary-Jane"
      def self.first_names(l)
        l['first_name'].to_s.strip.split(/(\s+|-)/).map { |w| w =~ /\A[\s-]+\z/ ? w : w[0].to_s.upcase + w[1..].to_s.downcase }.join
      end

      def self.create_file(pick)
        folder = pick['folder']
        unless folder && Dir.exist?(folder)
          folder = UI.select_directory(title: "Customer folder for #{pick['customer']} not found - choose it",
                                       directory: Dir.exist?(CUSTOMERS_DIR) ? CUSTOMERS_DIR : nil)
          return unless folder
        end
        path = File.join(folder, pick['design_visit'] ? design_file_name(pick['customer']) : file_name(pick['room_name'], pick['customer']))
        if File.exist?(path)
          return unless UI.messagebox("#{File.basename(path)} already exists.\n\nOpen it?", MB_YESNO) == IDYES
          return Sketchup.open_file(path)
        end
        cur = Sketchup.active_model
        fresh = cur.path.to_s.empty? && (cur.entities.length.zero? || (defined?(Room) && Room.blank?(cur)))
        unless fresh
          guid = cur.guid
          Sketchup.file_new
          # "Save changes?" cancelled: the old model is still the open one.
          return if Sketchup.active_model.guid == guid
        end
        model = Sketchup.active_model
        Ops.run(model, 'Link to HubSpot room') { store_link(model, link_from(pick)) }
        model.save(path)
        return UI.messagebox("Saved as #{File.basename(path)}\nin #{File.basename(folder)}, linked to #{pick['customer']} as a design visit (no Room).\n\nWhen a Room is added to the project in HubSpot, opening this file asks to connect it.") if pick['design_visit']
        after_link(model, pick, "Saved as #{File.basename(path)}\nin #{File.basename(folder)}.")
      rescue StandardError => e
        fail('new room', e)
      end

      def self.link_open_file(model, pick)
        cur = link(model)
        target = pick['design_visit'] ? "a design visit for #{pick['customer']}" : pick['room_name']
        if cur && cur['room_id'] != pick['room_id']
          return unless UI.messagebox("This file is linked to #{cur['room_name']}.\n\nLink it to #{target} instead?", MB_YESNO) == IDYES
        end
        Ops.run(model, 'Link to HubSpot room') { store_link(model, link_from(pick)) }
        return UI.messagebox("#{File.basename(model.path)} is linked to #{pick['customer']} as a design visit (no Room).\n\nWhen a Room is added to the project in HubSpot, opening this file asks to connect it.") if pick['design_visit']
        after_link(model, pick, "#{File.basename(model.path)} is linked to #{target}.")
      rescue StandardError => e
        fail('link', e)
      end

      # A design visit gets its Room: saved as the room's SURVEY file next to it (the design
      # visit file stays as it was last saved) and linked to the Room.
      def self.connect_design_visit(model, pick)
        dir = File.dirname(model.path.to_s)
        path = File.join(dir, file_name(pick['room_name'], pick['customer']))
        if File.exist?(path)
          return unless UI.messagebox("#{File.basename(path)} already exists.\n\nLink this file to #{pick['room_name']} and save over it?", MB_YESNO) == IDYES
        end
        Ops.run(model, 'Link to HubSpot room') do
          store_link(model, link_from(pick.merge('design_visit' => nil)))
          model.set_attribute(DICT, 'room_name', JobInfo.room_from_link(pick['room_name'])) if defined?(JobInfo)
        end
        model.save(path)
        after_link(model, pick, "Saved as #{File.basename(path)} and linked to #{pick['room_name']}.\nThe design visit file is left as it was.")
      rescue StandardError => e
        fail('connect design visit', e)
      end

      # Opening a design visit file: once its project has a Room, ask to connect it. A HubSpot
      # that can't be reached is said so (try again), never silently skipped.
      def self.check_design_visit(model)
        return unless model.valid? && model == Sketchup.active_model && design_visit?(model) && HubSpot.key?
        pid = customer_link(model)['project_id']
        ids = HubSpot.linked_ids('projects', pid, 'listings')
        return if ids.empty?
        show_pick(:connect)
      rescue StandardError => e
        Log.error('design visit check', e) unless e.is_a?(HubSpot::Error)
        UI.messagebox("This is a design visit file. Couldn't check HubSpot for a Room to connect it to - the connection isn't good.\n\n#{e.message}\n\nTry again: reopen the file, or HubSpot > Link this file.")
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onOpenModel(model); UI.start_timer(1.5, false) { HubSpotRoom.check_design_visit(model) }; end
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
      end

      # Read HubSpot's values once linked; offer the ones the file can take.
      def self.after_link(model, pick, msg)
        refresh_info(model)
        UI.messagebox("#{msg}\n\nNext: HubSpot > Send to HubSpot shows HubSpot's values next to this file's, " \
                      'and lets you take ceiling, runouts and colours from HubSpot.')
      end

      # Handles and door range from HubSpot, kept on the model for the windows.
      def self.refresh_info(model)
        l = link(model) or return {}
        theirs = HubSpot.read_one('listings', l['room_id'], INFO_FIELDS.map(&:first))['properties'] || {}
        info = INFO_FIELDS.to_h { |k, label| [label, theirs[k]] }.reject { |_k, v| v.to_s.empty? }
        info['Door style'] = label_of(theirs['door_style'], HubSpot.options('door_style')) if theirs['door_style']
        Ops.run(model, 'HubSpot details', transparent: true) { store_link(model, l.merge('info' => info)) }
        info
      rescue HubSpot::Error
        {}
      end

      CARD_KEEP_S = 120

      def self.show_send
        return unless ready?
        model = Sketchup.active_model
        l = link(model)
        unless l
          return unless UI.messagebox("This file isn't linked to a HubSpot room yet.\n\nLink it now?", MB_YESNO) == IDYES
          return show_pick(model.path.to_s.empty? ? :new : :link)
        end
        dlg = Dialog.open('hubspot_send', title: 'HW - HubSpot room', key: 'hw_hubspot_send2', width: 820, height: 760,
                                          data: { 'loading' => true, 'room' => l['room_name'] })
        m = calc = theirs = nil
        show_card = lambda do
          data = { 'room' => theirs['hs_name'] || l['room_name'], 'customer' => l['customer'],
                   'sections' => card_sections(m, calc, theirs), 'stage' => stage_info(theirs['hs_pipeline_stage']),
                   'project' => !l['project_id'].to_s.empty?,
                   'sent_at' => model.get_attribute(DICT, 'hs_sent_at', nil), 'scribes_on' => Pencil.on?(model) }
          dlg.execute_script("init(#{JSON.generate(data)})")
        end
        fetch_card = lambda do
          Steps.run(dlg, [
            ['Reading the HubSpot Room fields', -> { meta }, :bg, ->(r) { m = r }],
            ['Measuring this model (floor, hinges, handles, drawers)', -> { calc = calculated(model, m) }],
            ['Reading the Room from HubSpot', -> { room_values(l['room_id'], m) }, :bg, ->(r) { theirs = r }],
            ['Reading the Room stages', -> { HubSpot.room_stages rescue [] }, :bg]
          ], done: lambda { |_r|
            @card = { room: l['room_id'], at: Time.now, rev: Ops.revision(model), model: model, m: m, calc: calc, theirs: theirs }
            show_card.call
          }, fail: ->(e) { dlg.execute_script("loadFailed(#{JSON.generate(e.message)})") })
        end
        # Back on the tab within CARD_KEEP_S: what HubSpot said last time, at once (the model is
        # measured again only if it changed). After a send, or later, it is read again.
        load_card = lambda do
          c = @card
          if c && c[:room] == l['room_id'] && c[:model] == model && Time.now - c[:at] < CARD_KEEP_S
            m = c[:m]
            theirs = c[:theirs]
            calc = c[:rev] == Ops.revision(model) ? c[:calc] : calculated(model, m)
            show_card.call
          else
            fetch_card.call
          end
        end
        dlg.add_action_callback('ready') { |_c| load_card.call }
        dlg.add_action_callback('openRoom') { |_c| open_record('listings', l['room_id']) }
        dlg.add_action_callback('openProject') { |_c| open_record('projects', l['project_id']) }
        dlg.add_action_callback('pictures') do |_c|
          HubSpotPictures.show(lambda {
            Steps.one(dlg, 'Reading the pictures on the Room', done: lambda { |files|
              dlg.execute_script("filesUpdated(#{JSON.generate(files.slice(*FILE_FIELDS))})")
            }, fail: ->(_e) {}, bg: true) { HubSpot.read_one('listings', l['room_id'], FILE_FIELDS)['properties'] || {} }
          })
        end
        dlg.add_action_callback('send') do |_c, json|
          req = JSON.parse(json)
          send = req['send'] || {}
          take = req['take'] || {}
          took = []
          steps = []
          steps << ["Sending #{send.size} field(s) to HubSpot", -> { HubSpot.update_room(l['room_id'], send) }, :bg] unless send.empty?
          steps << ['Updating this file', -> { took = take_values(model, take) }] unless take.empty?
          steps << ['Finishing', lambda {
            Ops.run(model, 'HubSpot: record send', transparent: true) { model.set_attribute(DICT, 'hs_sent_at', Time.now.strftime('%d/%m/%Y %H:%M')) }
          }]
          Steps.run(dlg, steps, done: lambda { |_r|
            @card = nil # read fresh next time
            dlg.close
            msg = [send.empty? ? 'Nothing sent to HubSpot.' : "#{send.size} field(s) sent to HubSpot (#{l['room_name']})."]
            msg << "Into this file: #{took.join(', ')}." unless took.empty?
            job = (took & ['ceiling', 'bottom facing', 'runouts']).any?
            if job
              msg << (Pencil.on?(model) ? "\nThe units still have the old values - the pencil window opens next so you can apply them." :
                                           "\nScribes are off: the new values are used when you press the pencil.")
            end
            UI.messagebox(msg.join("\n"))
            Pencil.show(model, nil) if job && Pencil.on?(model)
          }, fail: ->(e) { dlg.execute_script("sendFailed(#{JSON.generate(e.message)})") })
        end
        dlg.show
      end

      def self.open_record(type, id)
        return UI.messagebox('Not linked.') if id.to_s.empty?
        UI.openURL(HubSpot.record_url(type, id))
      rescue StandardError => e
        fail('open', e)
      end

      def self.open_in_hubspot(type = 'listings')
        l = link(Sketchup.active_model)
        return UI.messagebox("This file isn't linked to a HubSpot room yet.") unless l
        open_record(type, type == 'projects' ? l['project_id'] : l['room_id'])
      end
    end
  end
end
