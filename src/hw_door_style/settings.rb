require 'json'

module HarryWardrobes
  module DoorStyle
    # Settings live inside the plugin folder.
    #   settings_default.json - shipped defaults (overwritten on update)
    #   settings.json         - local overrides written by the Settings dialog
    module Settings
      DEFAULT_FILE = File.join(PATH, 'settings_default.json')
      USER_FILE    = File.join(PATH, 'settings.json')

      HINGE_TYPES = {
        'soft_close_110' => 'Soft Close 110',
        'soft_close_155' => 'Soft Close 155',
        'pto_110'        => 'PTO 110',
        'pto_155'        => 'PTO 155'
      }.freeze

      def self.defaults
        JSON.parse(File.read(DEFAULT_FILE))
      end

      SETTINGS_VERSION = 2

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
        user['settings_version'] = SETTINGS_VERSION
        user
      end

      def self.load
        s = defaults
        if File.exist?(USER_FILE)
          begin
            s.merge!(migrate(JSON.parse(File.read(USER_FILE)), s))
          rescue StandardError => e
            puts "HW Door Style: could not read settings.json (#{e.message}); using defaults."
          end
        end
        s
      end

      def self.get
        @settings ||= load
      end

      def self.save(hash)
        File.write(USER_FILE, JSON.pretty_generate(hash.merge('settings_version' => SETTINGS_VERSION)))
        @settings = load
      end

      def self.reset
        File.delete(USER_FILE) if File.exist?(USER_FILE)
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
      def self.import_backup
        file = UI.openpanel('Upload settings backup', nil, 'Settings backup|*.json||')
        return nil unless file
        raw = JSON.parse(File.read(file))
        raise 'not an HW Door Style settings backup' unless raw.is_a?(Hash) && raw.key?(BACKUP_MARK)
        known = defaults.keys
        data = migrate(raw.select { |k, _| known.include?(k) }, defaults)
        raise 'no settings found in the file' if data.empty?
        data
      rescue StandardError => e
        UI.messagebox("Backup not loaded: #{e.message}")
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
      def self.geometry_signature
        %w[door_frame_mm drawer_stile_mm drawer_frame_mm recess_mm min_panel_mm
           midrail_min_door_height_mm midrail_centre_mm midrail_width_mm]
          .map { |k| get[k].to_f }.join(',')
      end

      # Handles / knobs: 1 per door and drawer front, 2 on drawer fronts wider
      # than handle_double_min_width_mm. Push-to-open doors get none unless
      # handles_on_pto_doors is set.
      def self.handle_count(kind, width, pto)
        two = width.to_f * 25.4 > get['handle_double_min_width_mm'].to_f ? 2 : 1
        case kind
        when :door       then pto && !get['handles_on_pto_doors'] ? 0 : 1
        when :ext_drawer then two
        when :int_drawer then get['handles_on_internal_drawers'] ? two : 0
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
