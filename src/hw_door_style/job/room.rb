require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # The room: width (left-right, red X), length (into the room, green Y) and ceiling
    # height, in mm. Sizes the FLOOR and CEILING parts from the job template and is the
    # job's ceiling height (the Scribe / runout window's "Ceiling height").
    #
    # A file without a room asks for it when it is opened (Room setup window); an unsaved
    # file is saved there too: <customers folder>\<customer folder>\<file>.skp, the
    # customers folder (e.g. 1_CUSTOMERS) remembered on this computer.
    module Room
      KEY = 'room'.freeze
      SKIP = 'room_skip'.freeze
      PREF_JOBS = 'jobs_folder'.freeze
      FLOOR = /\Afloor\z/i.freeze
      CEILING = /\Aceiling\z/i.freeze

      # The size the template's floor and ceiling are saved at (Settings "room_default_mm").
      # Only the template: a new job's Room setup starts blank.
      def self.default_mm
        d = Settings.get['room_default_mm']
        d = {} unless d.is_a?(Hash)
        { 'width' => (d['width'] || 4000).to_f, 'length' => (d['length'] || 3000).to_f, 'ceiling' => (d['ceiling'] || 2400).to_f }
      end

      def self.get(model = Sketchup.active_model)
        r = JSON.parse(model.get_attribute(DICT, KEY, 'null'))
        r.is_a?(Hash) ? r : nil
      rescue StandardError
        nil
      end

      def self.base(e)
        e.respond_to?(:definition) ? e.definition.name.sub(/#\d+\z/, '').strip : e.name.to_s
      end

      # The floor and ceiling parts (top level, by component or instance name).
      def self.part(model, re)
        model.entities.find do |e|
          (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && (base(e) =~ re || e.name.to_s =~ re)
        end
      end

      def self.parts(model)
        { floor: part(model, FLOOR), ceiling: part(model, CEILING) }
      end

      # Stretches a part in X / Y (like the Scale tool, about its corner) and moves its
      # corner to x, y (and its underside to z). Sizes in inches; nil = leave as it is.
      def self.fit(inst, w, l, x, y, z = nil)
        b = inst.bounds
        sx = w && b.width > 0.001 ? w / b.width : 1.0
        sy = l && b.height > 0.001 ? l / b.height : 1.0
        if (sx - 1).abs > 1e-6 || (sy - 1).abs > 1e-6
          inst.transformation = Geom::Transformation.scaling(b.min, sx, sy, 1.0) * inst.transformation
        end
        b = inst.bounds
        move = Geom::Vector3d.new(x - b.min.x, y - b.min.y, z ? z - b.min.z : 0)
        inst.transform!(Geom::Transformation.translation(move)) if move.length > 0.0001
        DC.redraw(inst) if inst.respond_to?(:definition) && inst.attribute_dictionary('dynamic_attributes')
        inst
      end

      # Sets the room (mm; nil / 0 keeps the current value) inside the caller's step.
      # Floor stays where it is and takes the width / length; the ceiling sits over it,
      # its underside at the ceiling height above the floor's top. Returns the room.
      def self.apply(model, width: nil, length: nil, ceiling: nil)
        cur = get(model) || {}
        r = {
          'width' => width.to_f.positive? ? width.to_f : cur['width'],
          'length' => length.to_f.positive? ? length.to_f : cur['length'],
          'ceiling' => ceiling.to_f.positive? ? ceiling.to_f : (cur['ceiling'] || (Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil))
        }
        w = r['width'] && r['width'] / 25.4
        l = r['length'] && r['length'] / 25.4
        p = parts(model)
        fb = p[:floor]&.bounds
        if p[:floor]
          fit(p[:floor], w, l, fb.min.x, fb.min.y)
          fb = p[:floor].bounds
        end
        if p[:ceiling]
          cb = p[:ceiling].bounds
          x = fb ? fb.min.x : cb.min.x
          y = fb ? fb.min.y : cb.min.y
          z = r['ceiling'] ? (fb ? fb.max.z : 0) + r['ceiling'] / 25.4 : nil
          fit(p[:ceiling], w, l, x, y, z)
        end
        model.set_attribute(DICT, KEY, JSON.generate(r))
        model.set_attribute(DICT, 'ceiling_mm', r['ceiling']) if r['ceiling']
        r
      end

      # --- asking when a file is opened ------------------------------------------

      # Nothing in it but the template's floor / ceiling (a new job).
      def self.blank?(model)
        model.path.to_s.empty? && model.entities.all? { |e| (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && (base(e) =~ FLOOR || base(e) =~ CEILING) }
      end

      def self.ask?(model)
        return false unless model && model.valid?
        return false if LibraryExport.master?(model)
        return false if model.get_attribute(DICT, SKIP, false)
        r = get(model)
        return true if r.nil?
        # a ceiling height alone (e.g. from HubSpot) still needs the floor / ceiling sizing
        p = parts(model)
        (p[:floor] || p[:ceiling]) && (r['width'].nil? || r['length'].nil?) ? true : false
      end

      def self.jobs_folder
        f = Sketchup.read_default(Settings::PREFS, PREF_JOBS, '').to_s
        f = HubSpotRoom::CUSTOMERS_DIR if (f.empty? || !File.directory?(f)) && defined?(HubSpotRoom)
        f.empty? || !File.directory?(f) ? nil : f
      end

      def self.safe(name)
        name.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '').strip.sub(/\.skp\z/i, '')
      end

      # The customer's folder in the customers folder, found by the HubSpot contact ID, else
      # the name a new one would get: "WILLIAMS Rebecca (830735284436)".
      def self.folder_for(pick, jf)
        found = HubSpotRoom.customer_folder(pick['contact_id'], jf)
        return { 'folder' => found, 'name' => File.basename(found), 'exists' => true } if found
        name = safe("#{HubSpotRoom.customer_tag(pick)} (#{pick['contact_id']})".strip)
        { 'folder' => File.join(jf, name), 'name' => name, 'exists' => false }
      end

      def self.data(model)
        jf = jobs_folder
        p = parts(model)
        r = get(model) || {}
        { 'saved' => !model.path.to_s.empty?, 'file' => File.basename(model.path.to_s, '.skp'),
          'jobs' => jf, 'hubspot' => HubSpot.key?,
          'width' => r['width'], 'length' => r['length'], 'ceiling' => r['ceiling'] || (Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil),
          'has_floor' => !p[:floor].nil?, 'has_ceiling' => !p[:ceiling].nil? }
      end

      # New job: the customer from HubSpot (search, then the project's Room or Design Visit),
      # the folder found by contact ID (or made), the file name checked, then the room size.
      def self.show(model = Sketchup.active_model)
        dlg = Dialog.open('room', title: 'HW - Room setup', key: 'hw_room_v2', width: 460, height: 640, data: data(model), resizable: true)
        js = ->(fn, obj) { dlg.execute_script("#{fn}(#{JSON.generate(obj)})") }
        dlg.add_action_callback('browse') do |_c|
          f = UI.select_directory(title: 'Customers folder (holds a folder per customer)', directory: jobs_folder || Dir.home)
          if f
            Sketchup.write_default(Settings::PREFS, PREF_JOBS, f.tr('\\', '/'))
            js.call('setJobs', 'jobs' => jobs_folder)
          end
        end
        dlg.add_action_callback('search') do |_c, q|
          Steps.one(dlg, q.to_s.strip.empty? ? 'Reading recent projects' : "Searching HubSpot for \"#{q.to_s.strip}\"",
                    done: ->(r) { js.call('projects', 'projects' => r) }, fail: ->(e) { js.call('projects', 'error' => e.message) }, bg: true) { HubSpot.search_projects(q) }
        end
        dlg.add_action_callback('project') do |_c, pid|
          Steps.one(dlg, 'Reading the rooms and customer',
                    done: lambda { |r|
                      jf = jobs_folder
                      r['found'] = jf ? folder_for(r, jf) : nil
                      r['design_file'] = HubSpotRoom.design_file_name(r['customer'])
                      js.call('rooms', r)
                    }, fail: ->(e) { js.call('rooms', 'error' => e.message) }) { HubSpotRoom.project_details(pid.to_s) }
        end
        # "select folder manually": any folder inside the customers folder.
        dlg.add_action_callback('pickFolder') do |_c|
          f = UI.select_directory(title: 'Customer folder', directory: jobs_folder || Dir.home)
          js.call('setFolder', 'folder' => f.tr('\\', '/'), 'name' => File.basename(f), 'exists' => true) if f
        end
        dlg.add_action_callback('never') do |_c|
          Ops.run(model, 'Room: don\'t ask', transparent: true) { model.set_attribute(DICT, SKIP, true) }
          dlg.close
        end
        dlg.add_action_callback('openExisting') do |_c, path|
          dlg.close
          Sketchup.open_file(path) if File.exist?(path.to_s)
        end
        dlg.add_action_callback('apply') do |_c, json|
          o = JSON.parse(json)
          err = save_and_apply(model, o)
          err.is_a?(Hash) ? js.call('exists', err) : (err ? js.call('problem', err) : dlg.close)
        end
        dlg.show
        dlg
      end

      # Saves the file first if it hasn't been (so a typo in the name changes nothing), links
      # it to HubSpot when a customer was picked, then sizes the room in one undo step.
      # Returns nil, an error message, or { 'path' } when that file already exists.
      def self.save_and_apply(model, o)
        w, l, c = o['width'].to_f, o['length'].to_f, o['ceiling'].to_f
        return 'Enter the ceiling height.' unless c.positive?
        p = parts(model)
        return 'Enter the room width and length.' if (p[:floor] || p[:ceiling]) && !(w.positive? && l.positive?)
        pick = o['pick'].is_a?(Hash) ? o['pick'] : nil
        if model.path.to_s.empty?
          jf = jobs_folder or return 'Choose the customers folder first.'
          dir = o['folder'].to_s.strip
          dir = File.join(jf, safe(File.basename(dir))) unless dir.start_with?(jf) # keep it inside the customers folder
          file = safe(o['file'])
          return 'Pick the customer (or select the folder manually).' if File.basename(dir).empty?
          return 'Enter the file name.' if file.empty?
          path = File.join(dir, "#{file}.skp")
          return { 'path' => path, 'name' => "#{file}.skp", 'folder' => File.basename(dir) } if File.exist?(path)
          FileUtils.mkdir_p(dir)
        end
        Ops.run(model, 'Room setup') do
          apply(model, width: w, length: l, ceiling: c)
          if pick
            HubSpotRoom.store_link(model, HubSpotRoom.link_from(pick))
            model.set_attribute(DICT, 'room_name', pick['design_visit'] ? 'Design visit' : JobInfo.room_from_link(pick['room_name']))
          end
        end
        if path
          ok = model.save(path)
          return "SketchUp couldn't save #{path}." unless ok
        end
        HubSpotRoom.refresh_info(model) if pick && !pick['design_visit']
        Pencil.invalidate(model) if defined?(Pencil)
        Sketchup.status_text = "Room #{w.round} x #{l.round} mm, ceiling #{c.round} mm#{path ? " - saved as #{path}" : ''}."
        nil
      rescue StandardError => e
        Log.error('room setup', e)
        "Couldn't set up the room: #{e.message}"
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); Room.later(model); end
        def onOpenModel(model); Room.later(model); end
      end

      def self.later(model)
        UI.start_timer(1.0, false) { show(model) if model.valid? && model == Sketchup.active_model && ask?(model) }
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
      end
    end
  end
end
