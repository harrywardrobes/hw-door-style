require 'json'

module HarryWardrobes
  module DoorStyle
    # The Settings window (toolbar: settings). Nothing is kept until Save;
    # a loaded backup or team file only fills the window.
    module SettingsWindow
      def self.data
        Settings.get.merge('_colour_library' => Colours.editor_library, '_ocl' => OpenCutList.status)
      end

      def self.show
        dlg = Dialog.open('settings', title: 'HW Door Style - Settings', key: 'hw_door_style_settings',
                                      width: 660, height: 520, data: data)
        pending = {} # settings from a loaded backup / team file, kept on Save

        dlg.add_action_callback('pickTexture') do |_c, idx|
          f = UI.openpanel('Choose a texture image', nil, 'Images|*.jpg;*.jpeg;*.png||')
          next unless f
          name = Colours.import_texture(f)
          dlg.execute_script("textureChosen(#{idx.to_i}, #{JSON.generate(name)}, #{JSON.generate(Colours.data_url(name))})")
        end

        dlg.add_action_callback('reset') do |_c|
          next unless UI.messagebox('Reset all settings to the plugin defaults?', MB_YESNO) == IDYES
          Settings.reset
          dlg.close
          Doors.offer_rebuild
        end

        dlg.add_action_callback('exportSettings') do |_c, json|
          Settings.export_backup(Settings.get.merge(pending).merge(JSON.parse(json)))
        end

        show_loaded = lambda do |loaded, what|
          next unless loaded
          pending = loaded
          dlg.execute_script("load(#{JSON.generate(Settings.defaults.merge(loaded))})")
          UI.messagebox("#{what} loaded into the Settings window.\nPress Save to keep it, or Cancel to discard.")
        end
        dlg.add_action_callback('importSettings') { |_c| show_loaded.call(Settings.import_backup, 'Backup') }
        dlg.add_action_callback('loadTeam') { |_c| show_loaded.call(Settings.load_team, 'Team settings') }

        dlg.add_action_callback('save') do |_c, json|
          begin
            save(JSON.parse(json), pending)
            dlg.close
            Doors.offer_rebuild
          rescue StandardError => e
            UI.messagebox("Settings not saved: #{e.message}")
            Log.error('settings', e)
          end
        end
        dlg.show
      end

      # The colour library is stored only when it differs from the built-in one
      # (so plugin updates can add colours); materials of the same name in the
      # open model are updated to match.
      def self.save(data, pending = {})
        lib = Array(data['colour_library']).map { |c| c.reject { |k, _| k == 'img' } }
        data['colour_library'] = lib == Colours.builtin ? [] : lib
        Settings.save(Settings.get.merge(pending).merge(data))
        m = Sketchup.active_model
        Ops.run(m, 'Update colour materials') { Colours.refresh_materials(m) }
      end
    end
  end
end
