require 'sketchup.rb'
require 'json'

module HarryWardrobes
  module DoorStyle
    DICT = 'hw_door_style'.freeze

    Sketchup.require(File.join(PATH, 'settings'))
    Sketchup.require(File.join(PATH, 'dc'))
    Sketchup.require(File.join(PATH, 'finder'))
    Sketchup.require(File.join(PATH, 'styles'))
    Sketchup.require(File.join(PATH, 'tagger'))
    Sketchup.require(File.join(PATH, 'hardware'))
    Sketchup.require(File.join(PATH, 'pdf'))
    Sketchup.require(File.join(PATH, 'colours'))
    Sketchup.require(File.join(PATH, 'drawer_box'))
    Sketchup.require(File.join(PATH, 'converter'))
    Sketchup.require(File.join(PATH, 'report'))
    Sketchup.require(File.join(PATH, 'repair'))
    Sketchup.require(File.join(PATH, 'library_export'))
    Sketchup.require(File.join(PATH, 'scribe'))
    Sketchup.require(File.join(PATH, 'opencutlist'))

    STYLED_KINDS = [:door, :ext_drawer].freeze

    # --- actions -----------------------------------------------------------

    def self.run(op_name)
      result = yield
      msg = "#{op_name}: #{result[:items]} item(s) updated"
      msg += "\n\n" + result[:notes].join("\n") unless result[:notes].empty?
      Sketchup.status_text = msg.lines.first.strip
      UI.messagebox(msg) unless result[:notes].empty?
      result
    rescue StandardError => e
      UI.messagebox("HW Door Style - #{op_name} failed and was undone.\n\n#{e.message}")
      puts e.full_message
      nil
    end

    # Doors can't be edited until the job has a Door / Drawer colour.
    def self.colour_ready?
      return true if Colours.door_colour_chosen?
      UI.messagebox('Choose a Door / Drawer colour for this job before editing doors.')
      show_colours
      false
    end

    # Every door AND external drawer front to one style, in one undo step.
    # Pressing it again redraws everything at its current size (same as Rebuild).
    def self.convert_all(style)
      return unless colour_ready?
      model = Sketchup.active_model
      pairs = Finder.all_targets(model, STYLED_KINDS)
      if pairs.empty?
        UI.messagebox("No doors or drawer fronts found.\nCheck the component names in HW Door Style > Settings.")
        return
      end
      name = "All doors & drawer fronts - #{Styles.label(style)}"
      run(name) { Converter.apply(pairs, style, name) }
    end

    # Every door and external drawer front -> Flat style (hardware kept), one undo step.
    def self.reset_all_flat
      return unless colour_ready?
      model = Sketchup.active_model
      pairs = Finder.all_targets(model, STYLED_KINDS)
      return UI.messagebox('No doors or drawer fronts found.') if pairs.empty?
      return unless UI.messagebox("Reset all #{pairs.size} doors and drawer fronts to Flat?", MB_YESNO) == IDYES
      run('Reset all to Flat') { Converter.apply(pairs, 'flat', 'Reset all to Flat') }
    end

    def self.repair_doors
      model = Sketchup.active_model
      r = Repair.run(model)
      UI.messagebox(Repair.message(r), MB_MULTILINE, 'HW Door Style - Repair doors')
    rescue StandardError => e
      UI.messagebox("Repair failed and was undone.\n\n#{e.message}")
      puts e.full_message
    end

    def self.apply_tags
      model = Sketchup.active_model
      model.start_operation('Apply door, drawer front and hardware tags', true)
      n = Tagger.tag_all(model)
      model.commit_operation
      Sketchup.status_text = "Tags applied: #{n} items updated"
      left = Tagger.hardware_leftovers(model)
      msg = "#{n} faces, edges and hardware components re-tagged."
      msg += "\n\nHardware tags:\n" + Settings.hardware_tags.map { |t, ns| "#{t}: #{ns.join(', ')}" }.join("\n")
      if left.empty?
        msg += "\n\nNothing is on the HARDWARE tag."
      else
        msg += "\n\nStill on HARDWARE (add these to Settings > Hardware tags):\n" +
               left.map { |k, c| "#{k} x#{c}" }.join("\n")
      end
      UI.messagebox(msg)
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("Tagging failed and was undone.\n\n#{e.message}")
    end

    def self.processed_targets(model, kinds = STYLED_KINDS)
      Finder.all_targets(model, kinds).select { |i, _k| i.definition.get_attribute(DICT, 'style') }
    end

    def self.rebuild_all
      return unless colour_ready?
      pairs = processed_targets(Sketchup.active_model)
      if pairs.empty?
        UI.messagebox('Nothing to rebuild - no doors or drawer fronts have been converted yet.')
        return
      end
      run('Rebuild styles') { Converter.apply(pairs, nil, 'Rebuild styles') }
    end

    def self.set_hinge_type(type)
      model = Sketchup.active_model
      pairs = processed_targets(model, [:door])
      if pairs.empty?
        model.start_operation('Set hinge type', true)
        Settings.set_job_hinge_type(type, model)
        model.commit_operation
        Sketchup.status_text = "Hinge type for this job: #{Settings::HINGE_TYPES[type]}"
      else
        name = "Hinge type - #{Settings::HINGE_TYPES[type]}"
        run(name) { Converter.apply(pairs, nil, name, hinge_type: type) }
      end
    end

    def self.selection_targets
      sel = Sketchup.active_model.selection.to_a
      Finder.targets(sel, [:door, :ext_drawer, :int_drawer])
    end

    def self.convert_selection(style)
      return unless colour_ready?
      all = selection_targets
      pairs = all.reject { |_i, k| k == :int_drawer }
      return UI.messagebox('Internal drawer fronts always stay flat.') if pairs.empty? && !all.empty?
      name = "Selected - #{Styles.label(style)}"
      run(name) { Converter.apply(pairs, style, name) }
    end

    def self.rebuild_selection
      return unless colour_ready?
      pairs = selection_targets.reject { |_i, k| k == :int_drawer }
      run('Rebuild selected') { Converter.apply(pairs, nil, 'Rebuild selected') }
    end

    # --- colours dialog -----------------------------------------------------

    def self.show_colours
      @colours_dlg&.close
      model = Sketchup.active_model
      dlg = UI::HtmlDialog.new(dialog_title: 'HW Door Style - Colours', preferences_key: 'hw_door_style_colours',
                               width: 480, height: 380, resizable: true, scrollable: false,
                               style: UI::HtmlDialog::STYLE_DIALOG)
      html = File.read(File.join(PATH, 'html', 'colours.html'))
      dlg.set_html(html.sub('/*DATA*/null', JSON.generate(Colours.dialog_data(model))))
      dlg.add_action_callback('cancel') { |_c| dlg.close }
      dlg.add_action_callback('apply') do |_c, json|
        choices = JSON.parse(json)
        model.start_operation('Apply colours', true)
        begin
          counts = Colours.apply(model, choices)
          box = choices['drawer_box'] || DrawerBox::DEFAULT
          thick = { changed: [], open: [] }
          thick = DrawerBox.set_thickness(model, box) if Settings.get['box_thickness_follows_finish']
          model.commit_operation
          dlg.close

          # Units whose box thickness changed are redrawn by the DC engine, then
          # repainted (a redraw can rebuild copied drawers).
          problems = []
          unless thick[:changed].empty?
            problems = DrawerBox.redraw(thick[:changed])
            model.start_operation('Re-apply colours after redraw', true, false, true)
            Colours.reapply(model)
            model.commit_operation
          end

          shown = Colours.resolved(model, choices)
          lines = Colours::GROUPS.map do |id, label|
            name = shown[id] == Colours::DEFAULT ? 'no material' : shown[id]
            name = "Default (#{name})" if choices[id] == Colours::DEFAULT && id != 'drawer_box'
            name = "#{name} #{format('%g', DrawerBox.thickness_mm(name))}mm" if id == 'drawer_box'
            "#{label}: #{name} - #{counts[id]} part(s)"
          end
          unless thick[:changed].empty?
            lines << '' << "Box thickness updated on: #{thick[:changed].map { |u| Finder.label(u) }.uniq.join(', ')}"
          end
          unless thick[:open].empty?
            lines << '' << "NOT updated (drawers open - close them and apply again): #{thick[:open].uniq.join(', ')}"
          end
          lines << '' << 'Check:' << problems unless problems.empty?
          UI.messagebox("Colours applied.\n\n#{lines.flatten.join("\n")}")
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Colours not applied (undone).\n\n#{e.message}")
        end
      end
      dlg.add_action_callback('setDefault') do |_c, json|
        Settings.save(Settings.get.merge('default_colours' => JSON.parse(json)))
        UI.messagebox('Saved as the default colours. They will be pre-selected on jobs with no colours chosen yet.')
      end
      @colours_dlg = dlg
      dlg.show
    end

    def self.export_colour_library
      dir = UI.select_directory(title: 'Choose a folder for the colour .skm files')
      return unless dir
      model = Sketchup.active_model
      model.start_operation('Export colour library', true)
      files = Colours.export_skm(model, dir)
      model.commit_operation
      UI.messagebox("#{files.size} materials saved to:\n#{dir}")
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("Export failed: #{e.message}")
    end

    # --- settings dialog ----------------------------------------------------

    def self.show_settings
      @settings_dlg&.close
      dlg = UI::HtmlDialog.new(dialog_title: 'HW Door Style - Settings', preferences_key: 'hw_door_style_settings',
                               width: 660, height: 520, resizable: true, scrollable: true,
                               style: UI::HtmlDialog::STYLE_DIALOG)
      html = File.read(File.join(PATH, 'html', 'settings.html'))
      dlg.set_html(html.sub('/*DATA*/null', JSON.generate(Settings.get.merge('_colour_library' => Colours.editor_library,
                                                                             '_ocl' => OpenCutList.status))))
      dlg.add_action_callback('pickTexture') do |_c, idx|
        f = UI.openpanel('Choose a texture image', nil, 'Images|*.jpg;*.jpeg;*.png||')
        next unless f
        name = Colours.import_texture(f)
        dlg.execute_script("textureChosen(#{idx.to_i}, #{JSON.generate(name)}, #{JSON.generate(Colours.data_url(name))})")
      end
      dlg.add_action_callback('cancel') { |_c| dlg.close }
      dlg.add_action_callback('reset') do |_c|
        next unless UI.messagebox('Reset all settings to the plugin defaults?', MB_YESNO) == IDYES
        Settings.reset
        dlg.close
        offer_rebuild
      end
      pending = {}
      dlg.add_action_callback('exportSettings') do |_c, json|
        Settings.export_backup(Settings.get.merge(pending).merge(JSON.parse(json)))
      end
      # Backup and team file both load into the window; nothing is kept until Save.
      show_loaded = lambda do |data, what|
        next unless data
        pending = data
        dlg.execute_script("load(#{JSON.generate(Settings.defaults.merge(data))})")
        UI.messagebox("#{what} loaded into the Settings window.\nPress Save to keep it, or Cancel to discard.")
      end
      dlg.add_action_callback('importSettings') { |_c| show_loaded.call(Settings.import_backup, 'Backup') }
      dlg.add_action_callback('loadTeam') { |_c| show_loaded.call(Settings.load_team, 'Team settings') }
      dlg.add_action_callback('save') do |_c, json|
        begin
          data = JSON.parse(json)
          lib = Array(data['colour_library']).map { |c| c.reject { |k, _| k == 'img' } }
          data['colour_library'] = lib == Colours.builtin ? [] : lib
          Settings.save(Settings.get.merge(pending).merge(data))
          m = Sketchup.active_model
          m.start_operation('Update colour materials', true)
          Colours.refresh_materials(m)
          m.commit_operation
          dlg.close
          offer_rebuild
        rescue StandardError => e
          UI.messagebox("Settings not saved: #{e.message}")
        end
      end
      @settings_dlg = dlg
      dlg.show
    end

    def self.offer_rebuild
      return if processed_targets(Sketchup.active_model).empty?
      rebuild_all if UI.messagebox('Settings saved. Rebuild the converted doors and drawer fronts in this model now?', MB_YESNO) == IDYES
    end

    # --- UI ----------------------------------------------------------------

    def self.icon(name)
      File.join(PATH, 'icons', "#{name}.svg")
    end

    def self.command(text, tip, icon_name = nil, &blk)
      cmd = UI::Command.new(text, &blk)
      cmd.tooltip = text
      cmd.status_bar_text = tip
      if icon_name
        cmd.small_icon = icon(icon_name)
        cmd.large_icon = icon(icon_name)
      end
      cmd
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('HW Door Style')

      cmd_shaker = command('Shaker - all doors & drawer fronts',
                           'Make every door and external drawer front Shaker. Press again after resizing to redraw them.',
                           'doors') { convert_all('shaker') }
      menu.add_item(cmd_shaker)
      style_menu = menu.add_submenu('All doors & drawer fronts')
      Styles.ids.each { |s| style_menu.add_item(Styles.label(s)) { convert_all(s) } }

      cmd_reset = command('Reset all to Flat', 'Set every door and external drawer front back to Flat (hinges kept).', 'reset') { reset_all_flat }
      menu.add_item(cmd_reset)

      menu.add_item('Rebuild styles (keep each item\'s style)') { rebuild_all }
      menu.add_item('Apply tags (doors, drawer fronts, hardware)') { apply_tags }
      menu.add_item('Repair doors in model') { repair_doors }

      hinge_menu = menu.add_submenu('Hinge type (this job)')
      Settings::HINGE_TYPES.each do |id, label|
        c = UI::Command.new(label) { set_hinge_type(id) }
        c.set_validation_proc { Settings.job_hinge_type == id ? MF_CHECKED : MF_UNCHECKED }
        hinge_menu.add_item(c)
      end

      menu.add_separator
      cmd_colours = command('Colours', 'Set door, exterior, interior and worktop colours for this job.', 'colours') { show_colours }
      menu.add_item(cmd_colours)
      menu.add_item('Export colour library (.skm)') { export_colour_library }
      menu.add_separator
      cmd_summary = command('Door summary', 'Show the door and drawer front summary (CSV / PDF export).', 'summary') { Report.show }
      cmd_settings = command('Settings', 'Frame sizes, mid-rail, hinge rules and component names.', 'settings') { show_settings }
      menu.add_item(cmd_summary)
      menu.add_item('Export door order (CSV + PDF)') { Report.export_order }
      menu.add_item(cmd_settings)
      menu.add_separator
      cmd_export = command('Export components',
                           'Library file only: export each component to its own versioned file (old versions to _old).',
                           'rocket') { LibraryExport.show }
      menu.add_item(cmd_export)
      cmd_scribe = command('Scribe / runout',
                           'Pressed: every unit has the job runouts. Click to set all to 0 (easier to move); click again to choose floor, ceiling, left, right and back.',
                           'pencil') { Scribe.toggle }
      cmd_scribe.set_validation_proc { Scribe.on? ? MF_CHECKED : MF_UNCHECKED }
      menu.add_item(cmd_scribe)
      cmd_ceiling = command('Ceiling height',
                            'Set the ceiling height for every unit with "Up to ceiling" = TRUE (any time; scribes not changed).',
                            'ceiling') { m = Sketchup.active_model; Scribe.show_ceiling(m) if Scribe.ready?(m) }
      menu.add_item(cmd_ceiling)
      menu.add_item('Runouts - re-apply job values to every unit') do
        m = Sketchup.active_model
        Scribe.show(m, nil) if Scribe.ready?(m)
      end

      tb = UI::Toolbar.new('HW Door Style')
      tb.add_item(cmd_colours)
      tb.add_item(cmd_shaker)
      tb.add_item(cmd_reset)
      tb.add_separator
      tb.add_item(cmd_summary)
      tb.add_item(cmd_settings)
      tb.add_separator
      tb.add_item(cmd_export)
      tb.add_item(cmd_scribe)
      tb.add_item(cmd_ceiling)
      tb.restore

      UI.add_context_menu_handler do |cm|
        targets = selection_targets
        units = Scribe.selected_units
        next if targets.empty? && units.empty?
        sub = cm.add_submenu('HW Door Style')
        unless units.empty?
          sub.add_item(units.size == 1 ? 'Runouts (this unit)...' : "Runouts (#{units.size} units)...") do
            m = Sketchup.active_model
            Scribe.show(m, units) if Scribe.ready?(m)
          end
          next if targets.empty?
          sub.add_separator
        end
        if targets.all? { |_i, k| k == :int_drawer }
          id = sub.add_item('Internal drawer fronts stay flat') {}
          sub.set_validation_proc(id) { MF_GRAYED }
        else
          Styles.ids.each { |s| sub.add_item("Style: #{Styles.label(s)}") { convert_selection(s) } }
          sub.add_separator
          sub.add_item('Rebuild selected') { rebuild_selection }
        end
      end

      # Observers: keep the pencil button in step with the open model.
      Scribe.start_watching

      file_loaded(__FILE__)
    end
  end
end
