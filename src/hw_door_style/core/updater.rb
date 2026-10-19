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
      def self.install(path)
        Dialog.close_all
        ok = Sketchup.install_from_archive(path)
        return nil unless ok
        before = VERSION
        # Let SketchUp finish its own install first, then load the new code.
        UI.start_timer(0.5, false) do
          reload!
          Sketchup.write_default(Settings::PREFS, 'update_skipped', '')
          UI.messagebox("HW Door Style #{VERSION} is running (was #{before}).\n\n" \
                        'If this version added a new toolbar button or menu item, it appears after the next restart.')
        rescue StandardError => e
          UI.messagebox("The new version is installed but couldn't be loaded straight away (#{e.message}). Restart SketchUp to use it.")
          Log.error('update reload', e)
        end
        true
      rescue Interrupt
        nil # cancelled in SketchUp's install prompt
      rescue StandardError => e
        UI.messagebox("Update not installed: #{e.message}")
        Log.error('update', e)
        nil
      end

      # Loads the plugin's code again from disk without re-running the start-up
      # files: VERSION is read from the loader and the file list from main.rb (so
      # files added by the new version are loaded too); menus are left as they are.
      def self.reload!
        verbose = $VERBOSE
        $VERBOSE = nil
        loader = File.read(File.join(File.dirname(PATH), 'hw_door_style.rb'), encoding: 'UTF-8')
        main = File.read(File.join(PATH, 'main.rb'), encoding: 'UTF-8')
        version = loader[/VERSION\s*=\s*'([^']+)'/, 1]
        files = main[/FILES\s*=\s*%w\[(.*?)\]/m, 1].to_s.split
        raise 'could not read the new version / file list' if version.nil? || files.empty?
        files.each { |f| load File.join(PATH, "#{f}.rb") }
        DoorStyle.send(:remove_const, :VERSION)
        DoorStyle.const_set(:VERSION, version.freeze)
        DoorStyle.send(:remove_const, :FILES)
        DoorStyle.const_set(:FILES, files.freeze)
        Settings.reload!
        Dialog.reset!
        Pencil.invalidate
        UI.refresh_toolbars if UI.respond_to?(:refresh_toolbars)
        Sketchup.status_text = "HW Door Style #{VERSION} loaded"
      ensure
        $VERBOSE = verbose
      end
    end
  end
end
