require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # The Settings window (toolbar: settings). Sections down the left; nothing
    # is kept until Save. A loaded backup or team file only fills the window.
    # Closing with unsaved changes asks first.
    #
    # Keys starting with "_" in the window's data are for display only (lists,
    # version, job info) and are never saved to settings.json.
    module SettingsWindow
      def self.data(model = Sketchup.active_model)
        Settings.get.merge(
          '_colour_library' => Colours.editor_library,
          '_colour_rows' => Colours::GROUPS.map { |id, label| [id, label, id == 'drawer_box' ? DrawerBox.names : Colours.names_for(id)] },
          '_hinge_types' => Settings::HINGE_TYPES,
          '_ocl' => OpenCutList.status,
          '_version' => VERSION,
          '_whats_new' => whats_new,
          '_settings_file' => Settings::USER_FILE,
          '_team_file' => Settings.team_file,
          '_debug' => Log.debug?,
          '_job' => job_info(model)
        )
      end

      def self.job_info(model)
        { 'title' => File.basename(model.path.to_s, '.skp'), 'scribes_on' => Pencil.on?(model),
          'ceiling' => Ceiling.mm(model), 'units' => Runouts.units(model.entities).size }
      rescue StandardError
        {}
      end

      def self.show
        dlg = Dialog.open('settings', title: 'HW Door Style - Settings', key: 'hw_door_style_settings_v2',
                                      width: 820, height: 600, data: data, scrollable: false)
        dirty = false
        pending = {} # settings from a loaded backup / team file, kept on Save
        discard_ok = -> { !dirty || UI.messagebox('Close Settings without saving your changes?', MB_YESNO) == IDYES }
        close = lambda do
          dirty = false
          dlg.close
        end

        dlg.set_can_close { discard_ok.call }
        dlg.add_action_callback('dirty') { |_c, flag| dirty = flag ? true : false }
        dlg.add_action_callback('cancel') { |_c| close.call if discard_ok.call }

        dlg.add_action_callback('pickTexture') do |_c, idx|
          f = UI.openpanel('Choose a texture image', nil, 'Images|*.jpg;*.jpeg;*.png||')
          next unless f
          name = Colours.import_texture(f)
          dlg.execute_script("textureChosen(#{idx.to_i}, #{JSON.generate(name)}, #{JSON.generate(Colours.data_url(name))})")
        end

        dlg.add_action_callback('reset') do |_c|
          next unless UI.messagebox("Reset all settings to the plugin defaults?\n\nThis can't be undone (Download backup first if unsure).", MB_YESNO) == IDYES
          lib = Settings.get['colour_library']
          keep = []
          if lib.is_a?(Array) && !lib.empty?
            keep << 'colour_library' unless UI.messagebox("Also reset the colour library to the built-in colours?\n\nYes: your own colours are removed from the list.\nNo: keep your colour library.", MB_YESNO) == IDYES
          end
          Settings.reset(keep: keep)
          close.call
          Doors.offer_rebuild
        end

        dlg.add_action_callback('exportSettings') do |_c, json|
          Settings.export_backup(Settings.get.merge(pending).merge(saveable(JSON.parse(json))))
        end

        show_loaded = lambda do |loaded, what|
          next unless loaded
          pending = loaded
          dlg.execute_script("loaded(#{JSON.generate(Settings.defaults.merge(loaded))})")
          UI.messagebox("#{what} loaded into the Settings window.\nPress Save to keep it, or Cancel to discard.")
        end
        dlg.add_action_callback('importSettings') { |_c| show_loaded.call(Settings.import_backup, 'Backup') }
        dlg.add_action_callback('loadTeam') { |_c| show_loaded.call(Settings.load_team, 'Team settings') }

        dlg.add_action_callback('openFolder') do |_c|
          FileUtils.mkdir_p(Settings::USER_DIR)
          UI.openURL("file:///#{Settings::USER_DIR.tr('\\', '/')}")
        end
        dlg.add_action_callback('oclSetup') do |_c, overwrite|
          if dirty
            UI.messagebox('Save your Settings first - the set-up uses the saved board sizes and tag.')
            next
          end
          model = Sketchup.active_model
          begin
            rep = Ops.run(model, 'Set up OpenCutList') { OpenCutList.setup!(model, overwrite: overwrite ? true : false) }
            msg = "Set: #{rep[:set].size} material(s), #{rep[:tagged]} door part(s) tagged." +
                  (rep[:kept].empty? ? '' : " Kept your own settings on: #{rep[:kept].join(', ')}.")
            dlg.execute_script("oclDone(#{JSON.generate(OpenCutList.status(model))}, #{JSON.generate(msg)})")
          rescue StandardError => e
            UI.messagebox("OpenCutList set-up failed and was undone.\n\n#{e.message}")
            Log.error('opencutlist', e)
          end
        end
        dlg.add_action_callback('diagnostics') { |_c| dlg.execute_script("copyText(#{JSON.generate(diagnostics)})") }

        dlg.add_action_callback('save') do |_c, json|
          begin
            save(JSON.parse(json), pending)
            close.call
            Doors.offer_rebuild
          rescue StandardError => e
            UI.messagebox("Settings not saved: #{e.message}")
            Log.error('settings', e)
          end
        end
        dlg.show
      end

      # Only real settings (no "_" display keys).
      def self.saveable(data)
        data.reject { |k, _| k.start_with?('_') }
      end

      # The colour library is stored only when it differs from the built-in one
      # (so plugin updates can add colours); materials of the same name in the
      # open model are updated to match. "_debug" is a SketchUp preference.
      def self.save(data, pending = {})
        Sketchup.write_default(Settings::PREFS, 'debug', data['_debug'] ? true : false) if data.key?('_debug')
        data = saveable(data)
        lib = Array(data['colour_library']).map { |c| c.reject { |k, _| k == 'img' } }
        data['colour_library'] = lib == Colours.builtin ? [] : lib
        Settings.save(Settings.get.merge(pending).merge(data))
        m = Sketchup.active_model
        Ops.run(m, 'Update colour materials') { Colours.refresh_materials(m) }
      end

      # The newest entries of CHANGELOG.md (shipped in the plugin folder):
      # [{ 'title' => '0.15.0 — 2026-10-19', 'items' => ['...'] }]
      def self.whats_new(count = 3, file = File.join(PATH, 'CHANGELOG.md'))
        return [] unless File.exist?(file)
        entries = []
        File.read(file, encoding: 'UTF-8').each_line do |line|
          if line.start_with?('## ')
            break if entries.size == count
            entries << { 'title' => line[3..].strip, 'items' => [] }
          elsif (cur = entries.last)
            if line.start_with?('- ')
              cur['items'] << line[2..].strip
            elsif line.start_with?('  ') && !cur['items'].empty?
              cur['items'][-1] += " #{line.strip}"
            elsif !line.strip.empty? && cur['items'].empty?
              cur['items'] << line.strip
            end
          end
        end
        entries.each { |e| e['items'].map! { |i| i.gsub(/\*\*|`/, '') } }
      rescue StandardError
        []
      end

      # Text for "Copy diagnostics".
      def self.diagnostics(model = Sketchup.active_model)
        ocl = OpenCutList.status rescue {}
        job = job_info(model)
        [
          "HW Door Style #{VERSION}",
          "SketchUp #{Sketchup.version} (#{Sketchup.platform rescue 'windows'})",
          "Settings: #{Settings::USER_FILE} (#{File.exist?(Settings::USER_FILE) ? 'saved' : 'defaults'})",
          "Team file: #{Settings.team_file || '-'}",
          "Model: #{model.path.to_s.empty? ? '(not saved)' : model.path}",
          "Units: #{job['units']}, scribes #{job['scribes_on'] ? 'on' : 'off'}, ceiling #{job['ceiling'].to_f.round} mm, top doors #{Ceiling.top_door_mm.round} mm",
          "Hinge type: #{Settings.job_hinge_type(model)}",
          "OpenCutList: #{ocl['installed'] ? "v#{ocl['version']}" : 'not installed'}",
          "Debug log: #{Log.debug? ? 'on' : 'off'}"
        ].join("\n")
      end
    end
  end
end
