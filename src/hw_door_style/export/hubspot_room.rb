require 'json'

module HarryWardrobes
  module DoorStyle
    # One SketchUp file = one HubSpot Room (Listing). Extensions > HW Door Style > HubSpot.
    #
    #   New room from HubSpot  pick a Project, then one of its Rooms: the survey file is
    #                          made in the customer's folder (1_CUSTOMERS\... (<contact id>))
    #                          as "SURVEY - <room> - <customer>.skp", linked to the Room.
    #   Link this file         the same, for a file that already exists.
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

      LINK_KEYS = %w[hs_room_id hs_project_id hs_contact_id hs_room_name hs_customer hs_address hs_info].freeze

      def self.link(model = Sketchup.active_model)
        h = LINK_KEYS.to_h { |k| [k.sub('hs_', ''), model.get_attribute(DICT, k, nil)] }
        h['info'] = (JSON.parse(h['info'].to_s) rescue {})
        h['room_id'] ? h : nil
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

      def self.file_name(room_name, customer)
        Report.safe_name("SURVEY - #{room_part(room_name).downcase} - #{customer.to_s.downcase}") + '.skp'
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

      def self.label_of(value, options)
        hit = options.find { |_l, v| v.to_s == value.to_s }
        hit ? hit[0] : value
      end

      # Number fields: blank and 0 count as the same.
      def self.same?(a, b, number)
        return (a.to_s.strip.empty? ? 0.0 : a.to_f).round(1) == (b.to_s.strip.empty? ? 0.0 : b.to_f).round(1) if number
        a.to_s.strip == b.to_s.strip
      end

      # --- what SketchUp says ---------------------------------------------------------------

      def self.floor(model)
        found = nil
        Finder.each_instance(model.entities) do |i|
          n = (DC.read(i, '_name') || i.definition.name).to_s
          found ||= i if n =~ /\Afloor\z/i
        end
        found
      end

      # Room width x depth (mm) from the FLOOR component: [w, d] or nil.
      def self.floor_mm(model)
        f = floor(model) or return nil
        x = DC.read(f, 'lenx').to_f
        y = DC.read(f, 'leny').to_f
        x, y = [f.bounds.width, f.bounds.height].map(&:to_f) unless x > 0 && y > 0
        [(x * 25.4).round, (y * 25.4).round]
      end

      def self.counts(model)
        rows = Report.rows(model)
        by_label = Settings::HINGE_TYPES.invert
        hinges = Hash.new(0)
        rows.each { |r| hinges[by_label[r['hinge_type']] || r['hinge_type']] += r['hinges'].to_i if r['hinges'].to_i > 0 }
        kinds = ->(k) { rows.select { |r| r['kind'] == Finder::KINDS[k] } }
        handles = ->(k) { kinds.call(k).sum { |r| r['handles'].to_i } }
        {
          'hinges' => hinges, 'tip_on' => rows.sum { |r| r['tip_on'].to_i },
          'ext_drawers' => kinds.call(:ext_drawer).size, 'int_drawers' => kinds.call(:int_drawer).size,
          'h_door' => handles.call(:door), 'h_ext' => handles.call(:ext_drawer), 'h_int' => handles.call(:int_drawer)
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

      # Every field: { prop, label, group, number, mine (value to send), shown (text),
      #                can_send, can_take }
      def self.fields(model)
        c = counts(model)
        out = []
        add = lambda do |prop, label, group, mine, number: true, take: false, shown: nil|
          out << { 'prop' => prop, 'label' => label, 'group' => group, 'number' => number,
                   'mine' => mine, 'shown' => shown || (mine.nil? ? '' : mine.to_s), 'can_take' => take }
        end
        w, d = floor_mm(model)
        add.call('room_width_mm', 'Room width (FLOOR)', 'Room', w)
        add.call('room_depth_mm', 'Room depth (FLOOR)', 'Room', d)
        ceil = Ceiling.mm(model)
        add.call('ceiling_height_mm', 'Ceiling height', 'Room', ceil > 0 ? ceil.round : nil, take: true)
        add.call('bottom_facing_mm', 'Bottom facing', 'Runouts', Facing.mm(model).round, take: true)
        jv = Runouts.job_values(model)
        RUNOUT_FIELDS.each { |side, prop| add.call(prop, "Runout - #{side}", 'Runouts', jv[side].round, take: true) }
        add.call('runout_exceptions', 'Units set differently', 'Runouts', exceptions(model), number: false)

        choices = Colours.job_choices(model)
        COLOUR_FIELDS.each do |gid, prop|
          name = choices[gid]
          name = nil if name == Colours::DEFAULT
          opts = HubSpot.options(prop)
          val = match_option(name, opts)
          add.call(prop, Colours::GROUPS.to_h[gid], 'Colours', val, number: false, take: true,
                                                                     shown: name ? (val ? name : "#{name} (not in HubSpot's list)") : '')
          out.last['colour'] = gid
          out.last['options'] = opts
          out.last['blocked'] = name && !val ? true : false
        end

        Settings::HINGE_TYPES.each { |id, label| add.call(HINGE_FIELDS[id], "Hinges - #{label}", 'Hardware', c['hinges'][id].to_i) }
        add.call('blum_push_tipon_set', 'TIP-ON', 'Hardware', c['tip_on'])
        add.call('drawer_total_quantity', 'Drawers (total)', 'Hardware', c['ext_drawers'] + c['int_drawers'])
        dt = drawer_type(c['ext_drawers'], c['int_drawers'])
        dt_opts = HubSpot.options('drawer_type')
        add.call('drawer_type', 'Drawer type', 'Hardware', match_option(dt, dt_opts), number: false, shown: dt)
        out.last['options'] = dt_opts
        add.call('main_robe_handle_quantity', 'Handles - robe doors', 'Hardware', c['h_door'])
        add.call('drawer_handle_quantity', 'Handles - drawers', 'Hardware', c['h_ext'])
        add.call('interior_handle_quantity', 'Handles - interior', 'Hardware', c['h_int'])
        out
      end

      # The send window's rows: each field with HubSpot's value and what to do.
      def self.compare(model, room_id)
        f = fields(model)
        theirs = HubSpot.read_one('listings', room_id, f.map { |x| x['prop'] } + INFO_FIELDS.map(&:first) + ROOM_PROPS)['properties'] || {}
        rows = f.map do |x|
          hs = theirs[x['prop']]
          x['hubspot'] = hs
          x['hubspot_shown'] = x['options'] ? label_of(hs, x['options']).to_s : hs.to_s
          x['same'] = same?(x['mine'], hs, x['number'])
          mine_blank = x['number'] ? x['mine'].nil? : x['mine'].to_s.empty?
          hs_blank = hs.to_s.strip.empty?
          x['action'] = if x['same'] then 'none'
                        elsif x['blocked'] then 'none'
                        elsif mine_blank && !hs_blank && x['can_take'] then 'take'
                        elsif mine_blank then 'none'
                        else 'send'
                        end
          x.delete('options') unless x['colour']
          x
        end
        info = INFO_FIELDS.to_h { |k, label| [label, theirs[k]] }
        info['Door style'] = label_of(theirs['door_style'], HubSpot.options('door_style')) if theirs['door_style']
        [rows, info.reject { |_k, v| v.to_s.empty? }, theirs['hs_name']]
      end

      # --- doing it ------------------------------------------------------------------------

      def self.send_and_take(model, room_id, rows, picks)
        send = {}
        take = {}
        rows.each do |r|
          case picks[r['prop']]
          when 'send' then send[r['prop']] = r['mine'].nil? ? '' : r['mine'].to_s
          when 'take' then take[r['prop']] = r
          end
        end
        HubSpot.update_room(room_id, send) unless send.empty?
        took = take_values(model, take)
        Ops.run(model, 'HubSpot: record send', transparent: true) do
          model.set_attribute(DICT, 'hs_sent_at', Time.now.strftime('%d/%m/%Y %H:%M'))
        end
        [send.size, took]
      end

      # HubSpot -> this file. Job values first (one step), then colours (their own step),
      # then the units are offered the new values through the pencil window.
      def self.take_values(model, take)
        return [] if take.empty?
        took = []
        runouts = Runouts.job_values(model)
        Ops.run(model, 'Values from HubSpot') do
          take.each do |prop, r|
            v = r['hubspot']
            case prop
            when 'ceiling_height_mm'
              model.set_attribute(DICT, 'ceiling_mm', v.to_f)
              took << 'ceiling'
            when 'bottom_facing_mm'
              model.set_attribute(DICT, 'facing_btm_mm', v.to_f)
              took << 'facing'
            else
              side = RUNOUT_FIELDS.key(prop)
              if side
                runouts[side] = v.to_f
                took << 'runouts'
              end
            end
          end
          model.set_attribute(DICT, 'scribe_values', JSON.generate(runouts)) if took.include?('runouts')
        end
        colours = take.values.select { |r| r['colour'] }
        unless colours.empty?
          choices = Colours.job_choices(model).compact
          choices['drawer_box'] ||= Colours.defaults['drawer_box']
          colours.each { |r| choices[r['colour']] = closest_colour(label_of(r['hubspot'], r['options']), r['colour']) }
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
      def self.show_pick(mode)
        return unless ready?
        model = Sketchup.active_model
        cur = link(model)
        if mode == :link && model.path.to_s.empty?
          return UI.messagebox('Save this file first, or use "New room from HubSpot" to make it in the customer folder.')
        end
        data = { 'mode' => mode.to_s, 'linked' => cur && cur['room_name'], 'file' => File.basename(model.path.to_s) }
        dlg = Dialog.open('hubspot_pick', title: mode == :new ? 'HW - New room from HubSpot' : 'HW - Link to a HubSpot room',
                                          key: 'hw_hubspot_pick', width: 560, height: 520, data: data)
        dlg.add_action_callback('search') do |_c, q|
          r = begin
            { 'projects' => HubSpot.search_projects(q) }
          rescue StandardError => e
            Log.error('hubspot search', e) unless e.is_a?(HubSpot::Error)
            { 'error' => e.message }
          end
          dlg.execute_script("projects(#{JSON.generate(r)})")
        end
        dlg.add_action_callback('project') do |_c, pid|
          r = begin
            project_details(pid.to_s)
          rescue StandardError => e
            Log.error('hubspot project', e) unless e.is_a?(HubSpot::Error)
            { 'error' => e.message }
          end
          dlg.execute_script("rooms(#{JSON.generate(r)})")
        end
        dlg.add_action_callback('choose') do |_c, json|
          pick = JSON.parse(json)
          dlg.close
          mode == :new ? create_file(pick) : link_open_file(model, pick)
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
        { 'project_id' => pid, 'rooms' => rooms.sort_by { |r| r['name'] }, 'contact_id' => contact_id, 'customer' => customer,
          'address' => [c['address'], c['city'], c['zip']].compact.map { |x| x.gsub(/[\s,]*\n\s*/, ', ').strip }.reject(&:empty?).join(', '),
          'folder' => folder, 'folder_name' => folder && File.basename(folder) }
      end

      def self.link_from(pick)
        { 'room_id' => pick['room_id'], 'project_id' => pick['project_id'], 'contact_id' => pick['contact_id'],
          'room_name' => pick['room_name'], 'customer' => pick['customer'], 'address' => pick['address'], 'info' => {} }
      end

      def self.create_file(pick)
        folder = pick['folder']
        unless folder && Dir.exist?(folder)
          folder = UI.select_directory(title: "Customer folder for #{pick['customer']} not found - choose it",
                                       directory: Dir.exist?(CUSTOMERS_DIR) ? CUSTOMERS_DIR : nil)
          return unless folder
        end
        path = File.join(folder, file_name(pick['room_name'], pick['customer']))
        if File.exist?(path)
          return unless UI.messagebox("#{File.basename(path)} already exists.\n\nOpen it?", MB_YESNO) == IDYES
          return Sketchup.open_file(path)
        end
        cur = Sketchup.active_model
        fresh = cur.path.to_s.empty? && cur.entities.length.zero?
        unless fresh
          guid = cur.guid
          Sketchup.file_new
          # "Save changes?" cancelled: the old model is still the open one.
          return if Sketchup.active_model.guid == guid
        end
        model = Sketchup.active_model
        Ops.run(model, 'Link to HubSpot room') { store_link(model, link_from(pick)) }
        model.save(path)
        after_link(model, pick, "Saved as #{File.basename(path)}\nin #{File.basename(folder)}.")
      rescue StandardError => e
        fail('new room', e)
      end

      def self.link_open_file(model, pick)
        cur = link(model)
        if cur && cur['room_id'] != pick['room_id']
          return unless UI.messagebox("This file is linked to #{cur['room_name']}.\n\nLink it to #{pick['room_name']} instead?", MB_YESNO) == IDYES
        end
        Ops.run(model, 'Link to HubSpot room') { store_link(model, link_from(pick)) }
        after_link(model, pick, "#{File.basename(model.path)} is linked to #{pick['room_name']}.")
      rescue StandardError => e
        fail('link', e)
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

      def self.show_send
        return unless ready?
        model = Sketchup.active_model
        l = link(model)
        unless l
          return unless UI.messagebox("This file isn't linked to a HubSpot room yet.\n\nLink it now?", MB_YESNO) == IDYES
          return show_pick(model.path.to_s.empty? ? :new : :link)
        end
        rows, info, name = begin
          compare(model, l['room_id'])
        rescue StandardError => e
          return fail('read room', e)
        end
        Ops.run(model, 'HubSpot details', transparent: true) { store_link(model, l.merge('info' => info)) } unless info == l['info']
        data = { 'room' => name || l['room_name'], 'customer' => l['customer'], 'rows' => rows, 'info' => info,
                 'sent_at' => model.get_attribute(DICT, 'hs_sent_at', nil), 'scribes_on' => Pencil.on?(model) }
        dlg = Dialog.open('hubspot_send', title: 'HW - Send to HubSpot', key: 'hw_hubspot_send', width: 760, height: 640, data: data)
        dlg.add_action_callback('open') { |_c| UI.openURL(HubSpot.room_url(l['room_id'])) rescue nil }
        dlg.add_action_callback('send') do |_c, json|
          picks = JSON.parse(json)
          dlg.close
          begin
            sent, took = send_and_take(model, l['room_id'], rows, picks)
          rescue StandardError => e
            next fail('send', e)
          end
          msg = ["#{sent} field(s) sent to HubSpot (#{l['room_name']})."]
          msg << "Taken from HubSpot: #{took.join(', ')}." unless took.empty?
          job = (took & %w[ceiling facing runouts]).any?
          if job
            msg << (Pencil.on?(model) ? "\nThe units still have the old values - the pencil window opens next so you can apply them." :
                                         "\nScribes are off: the new values are used when you press the pencil (ceiling: the ceiling button).")
          end
          UI.messagebox(msg.join("\n"))
          Pencil.show(model, nil) if job && Pencil.on?(model)
        end
        dlg.show
      end

      def self.open_in_hubspot
        l = link(Sketchup.active_model)
        return UI.messagebox("This file isn't linked to a HubSpot room yet.") unless l
        UI.openURL(HubSpot.room_url(l['room_id']))
      rescue StandardError => e
        fail('open', e)
      end
    end
  end
end
