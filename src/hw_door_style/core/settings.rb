require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # Where settings live:
    #   <plugin>/settings_default.json          shipped defaults (replaced on update)
    #   <team_folder>/settings.json             (H:\Shared drives\Harry Wardrobes\8_SKETCHUP\HW Plugin)
    #                                           the TEAM settings - the shared ones (doors,
    #                                           colours, components...) - the source of truth
    #                                           when Drive is reachable; every Save writes it
    #   %APPDATA%/HW Door Style/settings.json   a copy of the team settings on this computer
    #                                           (used when Drive isn't reachable)
    #   %APPDATA%/HW Door Style/computer.json   THIS computer only (COMPUTER_KEYS: folders,
    #                                           printers, updates) - never in the team file or
    #                                           a backup
    module Settings
      DEFAULT_FILE  = File.join(PATH, 'settings_default.json')
      USER_DIR      = File.join(ENV['APPDATA'] || Dir.home, 'HW Door Style')
      USER_FILE     = File.join(USER_DIR, 'settings.json')
      COMPUTER_FILE = File.join(USER_DIR, 'computer.json')
      PREFS         = 'HW Door Style'.freeze # Sketchup.read_default section
      TEAM_NAME     = 'settings.json'.freeze

      # Settings that belong to one computer, not the team.
      COMPUTER_KEYS = %w[library_folder local_folder team_folder update_folder update_check_at_start update_test_builds
                         pdf_printer pdf_sides zebra_share sumatra_path setup_done].freeze

      HINGE_TYPES = {
        'soft_close_110' => 'Soft Close 110',
        'soft_close_155' => 'Soft Close 155',
        'pto_110'        => 'PTO 110',
        'pto_155'        => 'PTO 155'
      }.freeze

      def self.defaults
        JSON.parse(File.read(DEFAULT_FILE))
      end

      # Settings files carry this; a file from an older plugin isn't converted - unknown keys
      # are dropped and the shipped defaults fill the rest.
      SETTINGS_VERSION = 17

      # Settings whose shipped value replaced a saved one: a file older than the version
      # listed drops those keys, so the new default applies (the rest of the file is kept).
      RESHIPPED = { 12 => %w[product_ref_names], 13 => %w[product_components], 14 => %w[components], 15 => %w[runout_defaults_mm], 16 => %w[label_display_names drawer_runner_type], 17 => %w[components product_depth_keys] }.freeze

      def self.clean(user, d)
        ver = user['settings_version'].to_i
        drop = RESHIPPED.select { |v, _| ver < v }.values.flatten
        user.select { |k, _| d.key?(k) && !drop.include?(k) }
      end

      def self.read_json(file)
        JSON.parse(File.read(file))
      rescue StandardError => e
        Log.info("could not read #{File.basename(file)} (#{e.message}); ignored.")
        {}
      end

      # The team file: Settings "team_folder" (this computer's path to the shared drive folder).
      def self.team_file(computer = nil)
        computer ||= File.exist?(COMPUTER_FILE) ? read_json(COMPUTER_FILE) : {}
        dir = (computer['team_folder'] || defaults['team_folder']).to_s.strip
        dir.empty? ? nil : File.join(dir.tr('\\', '/'), TEAM_NAME)
      end

      def self.team_reachable?
        f = team_file
        f && File.exist?(f)
      end

      # defaults + team (or the copy here) + this computer, then the derived lists.
      def self.load
        s = defaults
        computer = File.exist?(COMPUTER_FILE) ? clean(read_json(COMPUTER_FILE), s).slice(*COMPUTER_KEYS) : {}
        team = team_file(computer)
        shared = if team && File.exist?(team)
                   t = clean(read_json(team), s)
                   cache_team(t) unless t.empty?
                   t
                 elsif File.exist?(USER_FILE)
                   clean(read_json(USER_FILE), s)
                 else
                   {}
                 end
        s.merge!(shared.reject { |k, _| COMPUTER_KEYS.include?(k) })
        s.merge!(computer)
        derive(s)
      end

      def self.cache_team(t)
        FileUtils.mkdir_p(USER_DIR)
        File.write(USER_FILE, JSON.pretty_generate(t.merge('settings_version' => SETTINGS_VERSION)))
      rescue StandardError => e
        Log.info("could not cache the team settings (#{e.message})")
      end

      # Read the files again (after an update, so new defaults appear).
      def self.reload!
        @settings = nil
      end

      def self.get
        @settings ||= load
      end

      # Saves: this computer's keys here, the rest to the team file (when Drive is there)
      # and the copy here; a dated backup in the local folder.
      def self.save(hash)
        Ops.bump_settings if defined?(Ops)
        hash = hash.reject { |k, _| DERIVED.key?(k) }
        FileUtils.mkdir_p(USER_DIR)
        computer = hash.slice(*COMPUTER_KEYS)
        shared = hash.reject { |k, _| COMPUTER_KEYS.include?(k) }
        File.write(COMPUTER_FILE, JSON.pretty_generate(computer.merge('settings_version' => SETTINGS_VERSION)))
        File.write(USER_FILE, JSON.pretty_generate(shared.merge('settings_version' => SETTINGS_VERSION)))
        team = team_file(computer)
        if team
          begin
            FileUtils.mkdir_p(File.dirname(team))
            File.write(team, JSON.pretty_generate(shared.merge('settings_version' => SETTINGS_VERSION)))
          rescue StandardError => e
            Log.info("team settings not written (#{e.message}) - kept on this computer")
          end
        end
        @settings = load
        Local.backup_settings(shared) if defined?(Local)
      end

      # Back to the shipped defaults (team file too). keep: setting names to carry over
      # (e.g. ['colour_library'] keeps your own colours). This computer's keys are kept.
      def self.reset(keep: [])
        kept = (keep + COMPUTER_KEYS).to_h { |k| [k, get[k]] }.reject { |_, v| v.nil? }
        save(kept)
      end

      # --- the component table -----------------------------------------------------------
      #
      # Settings "components": NAME -> { role, product, letter, depth, no_midrail, framed }.
      # The old name lists are derived from it so the rest of the plugin reads them as before.
      ROLES = {
        'unit' => 'Unit - a product of its own', 'joiner' => 'Part of a product', 'internal' => 'Internal - inside a unit',
        'skip' => 'Never a product', 'door' => 'Door', 'ext_drawer' => 'Drawer front', 'int_drawer' => 'Internal drawer front',
        'fixed_panel' => 'Fixed panel (flat, no hinges)', 'room' => 'Room (floor / ceiling)'
      }.freeze

      def self.components(s = get)
        (s['components'] || {}).to_h { |k, v| [k.to_s.upcase, v.is_a?(Hash) ? v : {}] }
      end

      def self.with_role(s, *roles)
        components(s).select { |_n, r| roles.include?(r['role'].to_s) }.keys
      end

      DERIVED = {
        'door_names' => ->(s) { with_role(s, 'door', 'fixed_panel') },
        'ext_drawer_names' => ->(s) { with_role(s, 'ext_drawer') },
        'int_drawer_names' => ->(s) { with_role(s, 'int_drawer') },
        'fixed_panel_names' => ->(s) { with_role(s, 'fixed_panel') },
        'no_midrail_names' => ->(s) { components(s).select { |_n, r| r['no_midrail'] }.keys },
        'framed_drawer_units' => ->(s) { components(s).select { |_n, r| r['framed'] }.keys },
        'export_skip' => ->(s) { with_role(s, 'room') },
        'template_keep' => ->(s) { with_role(s, 'room') },
        'depth_short_components' => ->(s) { components(s).select { |_n, r| r['depth'].to_s == 'short' }.keys },
        'depth_by_component' => ->(s) { components(s).select { |_n, r| r['depth'].to_f.positive? }.to_h { |n, r| [n, r['depth'].to_f] } }
      }.freeze

      def self.derive(s)
        DERIVED.each { |k, f| s[k] = f.call(s) }
        s
      end

      # --- backup -------------------------------------------------------

      BACKUP_MARK = 'hw_door_style_settings'.freeze

      def self.export_backup(hash)
        hash = hash.reject { |k, _| COMPUTER_KEYS.include?(k) || DERIVED.key?(k) }
        name = "HW_Door_Style_settings_#{Time.now.strftime('%Y-%m-%d')}.json"
        file = UI.savepanel('Download settings backup', (defined?(Local) && File.directory?(Local.backups) ? Local.backups : nil), name)
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
        data = clean(raw, defaults).reject { |k, _| COMPUTER_KEYS.include?(k) }
        raise 'no settings found in the file' if data.empty?
        data
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
