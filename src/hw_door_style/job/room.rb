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

      def self.customers(folder)
        return [] unless folder && File.directory?(folder)
        Dir.children(folder).select { |d| d !~ /\A[._]/ && File.directory?(File.join(folder, d)) }
           .sort_by { |d| -(File.mtime(File.join(folder, d)).to_i rescue 0) }
      rescue StandardError
        []
      end

      def self.safe(name)
        name.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '').strip.sub(/\.skp\z/i, '')
      end

      def self.data(model)
        jf = jobs_folder
        p = parts(model)
        r = get(model) || {}
        { 'saved' => !model.path.to_s.empty?, 'file' => File.basename(model.path.to_s, '.skp'),
          'jobs' => jf, 'customers' => customers(jf),
          'width' => r['width'], 'length' => r['length'], 'ceiling' => r['ceiling'] || (Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil),
          'has_floor' => !p[:floor].nil?, 'has_ceiling' => !p[:ceiling].nil? }
      end

      def self.show(model = Sketchup.active_model)
        dlg = Dialog.open('room', title: 'HW - Room setup', key: 'hw_room_v1', width: 440, height: 560, data: data(model), resizable: true)
        dlg.add_action_callback('browse') do |_c|
          f = UI.select_directory(title: 'Customers folder (holds a folder per customer)', directory: jobs_folder || Dir.home)
          if f
            Sketchup.write_default(Settings::PREFS, PREF_JOBS, f.tr('\\', '/'))
            dlg.execute_script("setJobs(#{JSON.generate('jobs' => jobs_folder, 'customers' => customers(jobs_folder))})")
          end
        end
        dlg.add_action_callback('never') do |_c|
          Ops.run(model, 'Room: don\'t ask', transparent: true) { model.set_attribute(DICT, SKIP, true) }
          dlg.close
        end
        dlg.add_action_callback('apply') do |_c, json|
          o = JSON.parse(json)
          err = save_and_apply(model, o)
          err ? dlg.execute_script("problem(#{JSON.generate(err)})") : dlg.close
        end
        dlg.show
        dlg
      end

      # Saves the file first if it hasn't been (so a typo in the name changes nothing),
      # then sizes the room in one undo step. Returns an error message or nil.
      def self.save_and_apply(model, o)
        w, l, c = o['width'].to_f, o['length'].to_f, o['ceiling'].to_f
        return 'Enter the ceiling height.' unless c.positive?
        p = parts(model)
        return 'Enter the room width and length.' if (p[:floor] || p[:ceiling]) && !(w.positive? && l.positive?)
        if model.path.to_s.empty?
          jf = jobs_folder or return 'Choose the customers folder first.'
          cust = safe(o['customer'])
          file = safe(o['file'])
          return 'Enter the customer folder.' if cust.empty?
          return 'Enter the file name.' if file.empty?
          dir = File.join(jf, cust)
          path = File.join(dir, "#{file}.skp")
          return "#{file}.skp is already in #{cust} - choose another name." if File.exist?(path)
          FileUtils.mkdir_p(dir)
        end
        Ops.run(model, 'Room setup') { apply(model, width: w, length: l, ceiling: c) }
        if path
          ok = model.save(path)
          return "SketchUp couldn't save #{path}." unless ok
        end
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
