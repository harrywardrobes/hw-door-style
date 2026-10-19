require 'json'

module HarryWardrobes
  module DoorStyle
    # Updates without uninstalling or restarting SketchUp.
    #
    # Releases are saved to an updates folder on Google Drive (Settings
    # "update_folder"): hw_door_style_v<version>.rbz, plus hw_door_style_latest.json
    # ({ "version", "file", "notes": [...] }) for the "what's new" text.
    #
    # The plugin looks there a few seconds after SketchUp starts (and when you press
    # Check for updates). Update now = SketchUp installs the .rbz over the old files,
    # then the plugin loads its new code in place (Updater.reload!).
    #
    # Menus and the toolbar are built once per SketchUp session, so a release that
    # adds a button or menu item shows it after the next restart.
    module Updater
      PATTERN = /\Ahw_door_style_v(\d+)\.(\d+)\.(\d+)\.rbz\z/i.freeze

      # The updates folder. An old "_plugin_updates" path that no longer exists falls
      # back to its new home, "_HW Door Style\Updates" beside it.
      def self.folder
        f = Settings.get['update_folder'].to_s.strip
        if !f.empty? && !Dir.exist?(f) && f =~ /_plugin_updates\z/i
          moved = File.join(File.dirname(f), '_HW Door Style', 'Updates')
          return moved if Dir.exist?(moved)
        end
        f
      end

      def self.parse(version)
        version.to_s.split('.').map(&:to_i)
      end

      def self.newer?(a, b)
        (parse(a) <=> parse(b)) == 1
      end

      # Newest release in the folder: { version:, path:, notes: [] } or nil.
      def self.latest(dir = folder)
        return nil if dir.empty? || !Dir.exist?(dir)
        best = Dir.children(dir).filter_map do |f|
          m = PATTERN.match(f) or next
          { version: m.captures.join('.'), path: File.join(dir, f) }
        end.max_by { |r| parse(r[:version]) }
        return nil unless best
        info = JSON.parse(File.read(File.join(dir, 'hw_door_style_latest.json'))) rescue {}
        best[:notes] = info['version'] == best[:version] ? Array(info['notes']) : []
        best
      end

      # The newest release if it is newer than the one running, else nil.
      def self.available(dir = folder)
        r = latest(dir)
        r && newer?(r[:version], VERSION) ? r : nil
      end

      # A few seconds after start-up: offer a newer version once (not again if
      # you said No to that version; Settings > General still shows it).
      def self.check_at_startup
        return unless Settings.get['update_check_at_start']
        UI.start_timer(6, false) do
          r = available
          next unless r && Sketchup.read_default(Settings::PREFS, 'update_skipped', '') != r[:version]
          if offer(r)
            install(r[:path])
          else
            Sketchup.write_default(Settings::PREFS, 'update_skipped', r[:version])
          end
        rescue StandardError => e
          Log.error('update check', e)
        end
      end

      def self.offer(r)
        notes = r[:notes].first(8).map { |n| "- #{n}" }.join("\n")
        msg = "HW Door Style #{r[:version]} is available (you have #{VERSION}).\n\n" \
              "#{notes.empty? ? '' : "#{notes}\n\n"}Update now? No restart needed."
        UI.messagebox(msg, MB_YESNO) == IDYES
      end

      # Installs an .rbz over the current plugin and loads the new code.
      # Returns true when installed (the new code loads a moment later), nil if cancelled / failed.
      # Installs the .rbz and loads the new code straight away, with a progress window
      # (one step per timer tick, so SketchUp never looks frozen):
      # install -> each code file -> settings and windows.
      def self.install(path)
        Dialog.close_all
        before = VERSION
        win = progress_window
        show = ->(i, n, msg) { win.execute_script("progress(#{i}, #{n}, #{JSON.generate(msg)})") rescue nil }
        version = files = nil
        total = 3
        i = 0
        later = ->(&blk) { UI.start_timer(0.05, false, &blk) }
        fail = lambda do |msg, e|
          win.close rescue nil
          Log.error('update', e) if e
          UI.messagebox(msg)
        end
        finish = lambda do
          verbose = $VERBOSE
          $VERBOSE = nil
          begin
            apply_version(version, files)
          ensure
            $VERBOSE = verbose
          end
          show.call(total, total, 'Done')
          Sketchup.write_default(Settings::PREFS, 'update_skipped', '')
          UI.start_timer(0.4, false) do
            win.close rescue nil
            UI.messagebox("HW Door Style #{VERSION} is running (was #{before}).\n\n" \
                          'If this version added a new toolbar button or menu item, it appears after the next restart.')
          end
        end
        load_next = lambda do
          f = files[i - 2]
          next finish.call if f.nil?
          show.call(i, total, "Loading the new version: #{f}")
          later.call do
            begin
              verbose = $VERBOSE
              $VERBOSE = nil
              load File.join(PATH, "#{f}.rb")
              $VERBOSE = verbose
              i += 1
              load_next.call
            rescue StandardError, ScriptError => e
              $VERBOSE = verbose
              fail.call("The new version is installed but couldn't be loaded straight away (#{e.message}). Restart SketchUp to use it.", e)
            end
          end
        end
        show.call(0, total, 'Installing the new version - SketchUp may ask you to confirm...')
        later.call do
          begin
            ok = Sketchup.install_from_archive(path)
            next win.close unless ok
            # Let SketchUp finish its own install first, then load the new code.
            UI.start_timer(0.5, false) do
              begin
                version, files = read_new_version
                total = files.size + 2
                i = 2
                load_next.call
              rescue StandardError => e
                fail.call("The new version is installed but couldn't be loaded straight away (#{e.message}). Restart SketchUp to use it.", e)
              end
            end
          rescue Interrupt
            win.close rescue nil # cancelled in SketchUp's install prompt
          rescue StandardError => e
            fail.call("Update not installed: #{e.message}", e)
          end
        end
        true
      end

      def self.progress_window
        d = Dialog.open('progress', title: 'HW Door Style - Updating', key: 'hw_update_progress', width: 440, height: 150,
                                    resizable: false, scrollable: false, utility: true)
        d.show
        d
      end

      # VERSION from the loader and the file list from main.rb of the installed copy.
      def self.read_new_version
        loader = File.read(File.join(File.dirname(PATH), 'hw_door_style.rb'), encoding: 'UTF-8')
        main = File.read(File.join(PATH, 'main.rb'), encoding: 'UTF-8')
        version = loader[/VERSION\s*=\s*'([^']+)'/, 1]
        files = main[/FILES\s*=\s*%w\[(.*?)\]/m, 1].to_s.split
        raise 'could not read the new version / file list' if version.nil? || files.empty?
        [version, files]
      end

      def self.apply_version(version, files)
        DoorStyle.send(:remove_const, :VERSION)
        DoorStyle.const_set(:VERSION, version.freeze)
        DoorStyle.send(:remove_const, :FILES)
        DoorStyle.const_set(:FILES, files.freeze)
        Settings.reload!
        Dialog.reset!
        Pencil.invalidate
        UI.refresh_toolbars if UI.respond_to?(:refresh_toolbars)
        Sketchup.status_text = "HW Door Style #{VERSION} loaded"
      end

      # Loads the plugin's code again from disk without re-running the start-up
      # files (Developer > Reload plugin code): menus are left as they are.
      def self.reload!
        verbose = $VERBOSE
        $VERBOSE = nil
        version, files = read_new_version
        files.each { |f| load File.join(PATH, "#{f}.rb") }
        apply_version(version, files)
      ensure
        $VERBOSE = verbose
      end
    end
  end
end
