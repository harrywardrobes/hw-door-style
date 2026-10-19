require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # Where settings live:
    #   <plugin>/settings_default.json      shipped defaults (replaced on update)
    #   %APPDATA%/HW Door Style/settings.json  this computer's changes (kept on update)
    #   team file (optional)                 a settings backup on Google Drive that
    #                                        anyone can load with "Load team settings"
    # Versions up to 0.11 kept settings.json in the plugin folder, where a
    # reinstall wiped it; it is copied to AppData once (see migrate_location).
    module Settings
      DEFAULT_FILE = File.join(PATH, 'settings_default.json')
      USER_DIR     = File.join(ENV['APPDATA'] || Dir.home, 'HW Door Style')
      USER_FILE    = File.join(USER_DIR, 'settings.json')
      LEGACY_FILE  = File.join(PATH, 'settings.json')
      PREFS        = 'HW Door Style'.freeze # Sketchup.read_default section

      HINGE_TYPES = {
        'soft_close_110' => 'Soft Close 110',
        'soft_close_155' => 'Soft Close 155',
        'pto_110'        => 'PTO 110',
        'pto_155'        => 'PTO 155'
      }.freeze

      def self.defaults
        JSON.parse(File.read(DEFAULT_FILE))
      end

      SETTINGS_VERSION = 4

      # Brings settings saved by an older version up to date (names and tags
      # that changed in the model). Never removes the user's own extra tags.
      def self.migrate(user, d)
        v = user['settings_version'].to_i
        if v < 2
          %w[ext_drawer_names int_drawer_names hinge_tag hardware_tags].each { |k| user[k] = d[k] }
          cg = user['colour_groups']
          if cg.is_a?(Hash)
            ext = Array(cg['exterior'])
            cg['exterior'] = ext + (d['colour_groups']['exterior'] - ext)
          end
        end
        # 0.20: the plugin's Drive folders moved into "_HW Door Style".
        if v < 3 && user['update_folder'].to_s =~ /_plugin_updates\z/i
          user['update_folder'] = d['update_folder']
        end
        # 0.26: frame / recess / mid-rail sizes belong to each door style (Shaker had them).
        if v < 4
          old = OLD_SIZE_KEYS.to_h { |k| [k, user.delete(k)] }.compact
          unless old.empty?
            list = (user['door_styles'].is_a?(Array) ? user['door_styles'] : JSON.parse(JSON.generate(d['door_styles'])))
            sh = list.find { |st| st['id'] == 'shaker' }
            sh&.merge!(old)
            user['door_styles'] = list
          end
        end
        user['settings_version'] = SETTINGS_VERSION
        user
      end

      OLD_SIZE_KEYS = %w[door_frame_mm drawer_stile_mm drawer_frame_mm recess_mm min_panel_mm
                         midrail_min_door_height_mm midrail_centre_mm midrail_width_mm].freeze

      # One-time copy of a pre-0.12 settings.json from the plugin folder.
      def self.migrate_location
        return if File.exist?(USER_FILE) || !File.exist?(LEGACY_FILE)
        FileUtils.mkdir_p(USER_DIR)
        FileUtils.cp(LEGACY_FILE, USER_FILE)
        Log.info("settings moved to #{USER_FILE}")
      rescue StandardError => e
        Log.info("could not move old settings (#{e.message}).")
      end

      def self.load
        migrate_location
        s = defaults
        if File.exist?(USER_FILE)
          begin
            s.merge!(migrate(JSON.parse(File.read(USER_FILE)), s))
          rescue StandardError => e
            Log.info("could not read settings.json (#{e.message}); using defaults.")
          end
        end
        s
      end

      # Read the files again (after an update, so new defaults appear).
      def self.reload!
        @settings = nil
      end

      def self.get
        @settings ||= load
      end

      def self.save(hash)
        FileUtils.mkdir_p(USER_DIR)
        File.write(USER_FILE, JSON.pretty_generate(hash.merge('settings_version' => SETTINGS_VERSION)))
        @settings = load
      end

      # Back to the shipped defaults. keep: setting names to carry over
      # (e.g. ['colour_library'] keeps your own colours).
      def self.reset(keep: [])
        kept = keep.to_h { |k| [k, get[k]] }.reject { |_, v| v.nil? }
        File.delete(USER_FILE) if File.exist?(USER_FILE)
        unless kept.empty?
          FileUtils.mkdir_p(USER_DIR)
          File.write(USER_FILE, JSON.pretty_generate(kept.merge('settings_version' => SETTINGS_VERSION)))
        end
        @settings = load
      end

      # --- backup -------------------------------------------------------

      BACKUP_MARK = 'hw_door_style_settings'.freeze

      def self.export_backup(hash)
        name = "HW_Door_Style_settings_#{Time.now.strftime('%Y-%m-%d')}.json"
        file = UI.savepanel('Download settings backup', nil, name)
        return unless file
        file += '.json' unless file.downcase.end_with?('.json')
        out = { BACKUP_MARK => VERSION, 'saved' => Time.now.strftime('%d/%m/%Y %H:%M') }.merge(hash)
        File.write(file, JSON.pretty_generate(out))
        UI.messagebox("Settings backup saved:\n#{file}")
      rescue StandardError => e
        UI.messagebox("Backup not saved: #{e.message}")
      end

      # Returns the known settings from a backup file (unknown keys ignored), or nil.
      # With no file given, asks for one.
      def self.import_backup(file = nil)
        file ||= UI.openpanel('Upload settings backup', nil, 'Settings backup|*.json||')
        return nil unless file
        read_backup(file)
      rescue StandardError => e
        UI.messagebox("Backup not loaded: #{e.message}")
        nil
      end

      def self.read_backup(file)
        raw = JSON.parse(File.read(file))
        raise 'not an HW Door Style settings backup' unless raw.is_a?(Hash) && raw.key?(BACKUP_MARK)
        known = defaults.keys
        data = migrate(raw.select { |k, _| known.include?(k) || OLD_SIZE_KEYS.include?(k) }, defaults)
        raise 'no settings found in the file' if data.empty?
        data
      end

      # --- team settings file ---------------------------------------------
      # A settings backup kept somewhere shared (e.g. Google Drive). The path is
      # remembered per computer in SketchUp's own preferences.

      def self.team_file
        f = Sketchup.read_default(PREFS, 'team_settings_file', '').to_s
        f.empty? ? nil : f
      end

      def self.team_file=(file)
        Sketchup.write_default(PREFS, 'team_settings_file', file.to_s)
      end

      # Asks for the team file (starting at the last one used), remembers it and
      # returns its settings, or nil.
      # "Team settings" next to the updates folder (Harry Wardrobes\_HW Door Style).
      def self.team_dir
        d = File.join(File.dirname(get['update_folder'].to_s), 'Team settings')
        Dir.exist?(d) ? d : nil
      end

      def self.load_team
        last = team_file
        dir = last ? File.dirname(last) : team_dir
        file = UI.openpanel('Load team settings (a settings backup on Drive)', dir, 'Settings backup|*.json||')
        return nil unless file
        data = read_backup(file)
        self.team_file = file
        data
      rescue StandardError => e
        UI.messagebox("Team settings not loaded: #{e.message}")
        nil
      end

      def self.mm(key)
        get[key].to_f.mm
      end

      # { tag => [component names] } for hardware (hinges, brackets, runners ...).
      def self.hardware_tags
        h = get['hardware_tags']
        return {} unless h.is_a?(Hash)
        h.to_h { |tag, ns| [tag.to_s.strip, Array(ns).map { |n| n.to_s.strip.upcase }.reject(&:empty?)] }
         .reject { |tag, _| tag.empty? }
      end

      def self.names(key)
        Array(get[key]).map { |n| n.to_s.strip.upcase }.reject(&:empty?)
      end

      # Job hinge type is stored on the model so it travels with the file.
      def self.job_hinge_type(model = Sketchup.active_model)
        t = model.get_attribute(DICT, 'hinge_type', nil)
        HINGE_TYPES.key?(t) ? t : get['default_hinge_type']
      end

      def self.set_job_hinge_type(type, model = Sketchup.active_model)
        model.set_attribute(DICT, 'hinge_type', type)
      end

      def self.pto?(type)
        type.to_s.start_with?('pto')
      end

      # Changes whenever a setting that affects style geometry changes, so
      # shared style components are never reused with out-of-date sizes.
      # --- handles ----------------------------------------------------------------
      HANDLE_KEYS = %w[handles_on_pto_doors handles_on_internal_drawers handle_double_min_width_mm].freeze

      # The job's handle rules (Door style window), starting from the Settings defaults.
      def self.job_handles(model = nil)
        saved = model ? (JSON.parse(model.get_attribute(DICT, 'job_handles', '{}')) rescue {}) : {}
        HANDLE_KEYS.to_h { |k| [k, saved.key?(k) ? saved[k] : get[k]] }
      end

      # Handles on one door / drawer front: drawer fronts get two when wider than
      # handle_double_min_width_mm. Push-to-open doors get none unless handles_on_pto_doors;
      # handleless styles get none.
      def self.handle_count(kind, width, pto, rules: nil, handleless: false)
        return 0 if handleless
        r = rules || job_handles
        two = width.to_f * 25.4 > r['handle_double_min_width_mm'].to_f ? 2 : 1
        case kind
        when :door       then pto && !r['handles_on_pto_doors'] ? 0 : 1
        when :ext_drawer then two
        when :int_drawer then r['handles_on_internal_drawers'] ? two : 0
        else 0
        end
      end

      def self.hinge_count(height)
        h_mm = height.to_f * 25.4
        rule = get['hinge_rules'].find { |max, _n| h_mm <= max.to_f }
        rule ? rule[1].to_i : 2
      end
    end
  end
end
