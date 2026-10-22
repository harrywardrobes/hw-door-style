require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # Setup (first run, and Settings > General > Run setup again): one checklist that gets
    # the plugin working on this computer - library folder, local copy, template, updates,
    # team settings, printers, SumatraPDF, OpenCutList, HubSpot. Each line is checked when
    # the window opens and has a Fix button where the plugin can do it itself.
    module Setup
      DONE = 'setup_done'.freeze # computer.json: the plugin version that finished setup

      def self.done? = !Settings.get[DONE].to_s.empty?

      # Shown at the top of Settings while something still needs doing.
      def self.note
        return nil if done?
        'Setup hasn\'t been finished on this computer - General > Run setup again.'
      end

      # On start-up: open once if setup was never finished here.
      def self.start
        return if @started || done?
        @started = true
        UI.start_timer(3, false) { show }
      end

      # --- the checks: [{ id, label, status: ok|warn|fail, text, fix: label or nil }] -----

      def self.checks
        [library, local, cache, template, updates, team, printer_pdf, printer_zebra, sumatra, opencutlist, hubspot]
      end

      def self.row(id, label, status, text, fix = nil)
        { 'id' => id, 'label' => label, 'status' => status, 'text' => text, 'fix' => fix }
      end

      def self.library
        r = LibraryCache.root
        if File.directory?(r)
          row('library', 'Library folder (Drive)', 'ok', r)
        elsif File.directory?(Local.mirror)
          row('library', 'Library folder (Drive)', 'warn', "#{r} isn't reachable - the local copy is used (#{Local.mirror}).", 'Choose folder...')
        else
          row('library', 'Library folder (Drive)', 'fail', "#{r} isn't reachable and there's no local copy yet. Connect Google Drive, or choose the folder.", 'Choose folder...')
        end
      end

      def self.local
        m = Local.mirror
        n = File.directory?(m) ? Dir.glob(File.join(m, '**', '*.skp')).size : 0
        if n.positive?
          row('local', 'Local copy of the library', 'ok', "#{n} component file(s) in #{m}")
        elsif File.directory?(LibraryCache.root)
          row('local', 'Local copy of the library', 'warn', "Nothing in #{m} yet - copy the library so everything works offline.", 'Copy the library')
        else
          row('local', 'Local copy of the library', 'fail', "No local copy and Drive isn't reachable.")
        end
      end

      def self.cache
        n = LibraryCache.cards.size
        n.positive? ? row('cache', 'Add component (+) cache', 'ok', "#{n} component(s) ready") : row('cache', 'Add component (+) cache', 'warn', 'Not synced yet.', 'Sync now')
      end

      def self.template
        have = TemplateExport.versions(TemplateExport.user_dir).first
        latest = TemplateExport.versions(TemplateExport.dir(LibraryCache.root)).first rescue nil
        if have && (latest.nil? || have[0] >= latest[0])
          row('template', 'Job template', 'ok', "#{File.basename(have[1])} in Welcome to SketchUp#{TemplateExport.default? ? ' (default)' : ''}")
        elsif latest
          row('template', 'Job template', 'warn', "#{File.basename(latest[1])} is in the library but not installed here.", 'Install')
        else
          row('template', 'Job template', 'warn', 'No template in the library yet (Export components makes one).')
        end
      end

      def self.updates
        info = SettingsWindow.update_info
        if !info['folder_ok']
          row('updates', 'Updates folder', 'warn', "#{Updater.folder} isn't reachable - updates are checked when it is.")
        elsif info['newer']
          row('updates', 'Updates folder', 'warn', "Version #{info['latest']} is available (you have #{VERSION}).", 'Update')
        else
          row('updates', 'Updates folder', 'ok', "Up to date (#{VERSION})")
        end
      end

      def self.team
        f = Settings.team_file
        if f.nil?
          row('team', 'Team settings', 'fail', 'No library folder, so no team settings.')
        elsif File.exist?(f)
          row('team', 'Team settings', 'ok', "Shared with the team from #{f}")
        elsif File.directory?(LibraryCache.root)
          row('team', 'Team settings', 'warn', "No team settings file yet - this computer's settings become the team's.", 'Make it')
        else
          row('team', 'Team settings', 'warn', "Drive isn't reachable - the copy on this computer is used.")
        end
      end

      def self.printer_pdf
        name = PdfPrint.resolve
        row('pdf', 'A4 printer', 'ok', "#{name}#{PdfPrint.sumatra ? '' : ' (needs SumatraPDF, below)'}", 'Test print')
      rescue StandardError => e
        row('pdf', 'A4 printer', 'warn', e.message.sub(/ Set the name in.*\z/, ''), 'Choose printer...')
      end

      def self.printer_zebra
        list = PdfPrint.printers
        share = Zpl.share
        if list.nil?
          row('zebra', 'Label printer (Zebra)', 'warn', "Couldn't read the printers from Windows - share name set to #{share}.")
        elsif list.any? { |_n, s| s.casecmp?(share) }
          row('zebra', 'Label printer (Zebra)', 'ok', "Shared as #{share}", 'Test label')
        else
          row('zebra', 'Label printer (Zebra)', 'warn', "No printer shared as #{share}. Share the Zebra in Windows (Printer properties > Sharing), or pick it.", 'Choose printer...')
        end
      end

      def self.sumatra
        exe = PdfPrint.sumatra
        exe ? row('sumatra', 'SumatraPDF', 'ok', exe) : row('sumatra', 'SumatraPDF', 'warn', 'Not found - it prints the PDFs with no dialog. Install it (free) from sumatrapdfreader.org, then Locate it if it isn\'t found.', 'Locate...')
      end

      def self.opencutlist
        o = OpenCutList.status
        o['installed'] ? row('ocl', 'OpenCutList', 'ok', "v#{o['version']}#{o['loaded'] ? '' : ' (not loaded)'}") : row('ocl', 'OpenCutList', 'warn', 'Not installed - the cut list needs it. Install it from the Extension Warehouse (Window > Extension Warehouse, search OpenCutList).', 'About OpenCutList')
      end

      def self.hubspot
        HubSpot.key? ? row('hubspot', 'HubSpot', 'ok', "Key saved (#{HubSpot.key_hint}) - test it in Settings > HubSpot", 'Test') : row('hubspot', 'HubSpot', 'warn', 'No private app key on this computer. Paste it in Settings > HubSpot (it never leaves this computer).', 'Settings > HubSpot')
      end

      # --- the window --------------------------------------------------------------------

      def self.show(force: false)
        return if !force && done?
        dlg = Dialog.open('setup', title: 'HW Door Style - Setup', key: 'hw_door_style_setup_v1', width: 700, height: 560,
                                   data: { 'checks' => checks, 'version' => VERSION, 'first' => !done? })
        refresh = -> { dlg.execute_script("setChecks(#{JSON.generate(checks)})") }
        say = ->(id, msg) { dlg.execute_script("note(#{JSON.generate(id)}, #{JSON.generate(msg)})") }
        dlg.add_action_callback('refresh') { |_c| refresh.call }
        dlg.add_action_callback('fix') do |_c, id|
          begin
            fix(id, dlg, say)
          rescue StandardError => e
            Log.error("setup #{id}", e)
            say.call(id, e.message)
          end
          refresh.call
        end
        dlg.add_action_callback('finish') do |_c|
          Settings.save(Settings.get.merge(DONE => VERSION))
          dlg.close
        end
        dlg.add_action_callback('later') { |_c| dlg.close }
        dlg.show
      end

      def self.fix(id, dlg, say)
        case id
        when 'library'
          d = UI.select_directory(title: 'The component library on Google Drive (Harry Wardrobes)')
          Settings.save(Settings.get.merge('library_folder' => d.tr('\\', '/'))) if d
        when 'local'
          n = Local.mirror_all(LibraryCache.root)
          say.call(id, "#{n} file(s) copied.")
        when 'cache'
          idx = LibraryCache.index
          get, gone = LibraryCache.plan(LibraryCache.scan, idx)
          LibraryCache.forget(gone, idx)
          get.each { |e| LibraryCache.fetch(e, idx) }
          LibraryCache.save_index(idx)
          say.call(id, "#{get.size} copied, #{gone.size} removed.")
        when 'template'
          TemplateExport.sync_local
        when 'updates'
          r = Updater.latest
          if r && Updater.offer(r)
            dlg.close
            Updater.install(r[:path])
          end
        when 'team'
          Settings.save(Settings.get) # writes the team file from this computer's settings
        when 'pdf', 'zebra'
          list = PdfPrint.printers || []
          names = id == 'zebra' ? list.reject { |_n, s| s.empty? }.map { |_n, s| s } : list.map { |n, _s| n }
          if names.empty?
            say.call(id, id == 'zebra' ? 'No shared printers - share the Zebra in Windows first.' : 'No printers found.')
          else
            pick = UI.inputbox(['Printer'], [names.first], [names.join('|')], id == 'zebra' ? 'Which share is the Zebra?' : 'Which printer prints the A4 pack?')
            Settings.save(Settings.get.merge((id == 'zebra' ? 'zebra_share' : 'pdf_printer') => pick[0])) if pick
          end
        when 'pdf_test'
          PdfPrint.test_page
          say.call('pdf', 'Test page sent.')
        when 'zebra_test'
          Zpl.transmit(Zpl.test_label)
          say.call('zebra', 'Test label sent.')
        when 'sumatra'
          f = UI.openpanel('Where is SumatraPDF.exe?', ENV['ProgramFiles'], 'SumatraPDF|SumatraPDF.exe||')
          Settings.save(Settings.get.merge('sumatra_path' => f)) if f
        when 'ocl'
          UI.openURL('https://www.lairdubois.fr/opencutlist/')
        when 'hubspot'
          HubSpot.key? ? say.call(id, 'Test it in Settings > HubSpot > Test connection.') : SettingsWindow.show
        end
      end
    end
  end
end
