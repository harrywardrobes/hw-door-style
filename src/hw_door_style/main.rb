require 'sketchup.rb'
require 'json'

module HarryWardrobes
  module DoorStyle
    DICT = 'hw_door_style'.freeze

    Sketchup.require(File.join(PATH, 'settings'))
    Sketchup.require(File.join(PATH, 'finder'))
    Sketchup.require(File.join(PATH, 'styles'))
    Sketchup.require(File.join(PATH, 'tagger'))
    Sketchup.require(File.join(PATH, 'hardware'))
    Sketchup.require(File.join(PATH, 'pdf'))
    Sketchup.require(File.join(PATH, 'converter'))
    Sketchup.require(File.join(PATH, 'report'))

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

    def self.convert_all(kind, style)
      model = Sketchup.active_model
      pairs = Finder.all_targets(model, [kind])
      if pairs.empty?
        UI.messagebox("No #{Finder::KINDS[kind].downcase}s found.\nCheck the component names in HW Door Style > Settings.")
        return
      end
      name = "All #{Finder::KINDS[kind].downcase}s - #{Styles.label(style)}"
      run(name) { Converter.apply(pairs, style, name) }
    end

    # Every door and external drawer front -> Flat style (hardware kept), one undo step.
    def self.reset_all_flat
      model = Sketchup.active_model
      pairs = Finder.all_targets(model, STYLED_KINDS)
      return UI.messagebox('No doors or drawer fronts found.') if pairs.empty?
      return unless UI.messagebox("Reset all #{pairs.size} doors and drawer fronts to Flat?", MB_YESNO) == IDYES
      run('Reset all to Flat') { Converter.apply(pairs, 'flat', 'Reset all to Flat') }
    end

    def self.apply_tags
      model = Sketchup.active_model
      model.start_operation('Apply door / drawer front tags', true)
      n = Tagger.tag_all(model)
      model.commit_operation
      Sketchup.status_text = "Tags applied: #{n} faces/edges updated"
      UI.messagebox("#{n} faces and edges re-tagged.") if n > 0
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("Tagging failed and was undone.\n\n#{e.message}")
    end

    def self.processed_targets(model, kinds = STYLED_KINDS)
      Finder.all_targets(model, kinds).select { |i, _k| i.definition.get_attribute(DICT, 'style') }
    end

    def self.rebuild_all
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
      all = selection_targets
      pairs = all.reject { |_i, k| k == :int_drawer }
      return UI.messagebox('Internal drawer fronts always stay flat.') if pairs.empty? && !all.empty?
      name = "Selected - #{Styles.label(style)}"
      run(name) { Converter.apply(pairs, style, name) }
    end

    def self.rebuild_selection
      pairs = selection_targets.reject { |_i, k| k == :int_drawer }
      run('Rebuild selected') { Converter.apply(pairs, nil, 'Rebuild selected') }
    end

    # --- settings dialog ----------------------------------------------------

    def self.show_settings
      @settings_dlg&.close
      dlg = UI::HtmlDialog.new(dialog_title: 'HW Door Style - Settings', preferences_key: 'hw_door_style_settings',
                               width: 620, height: 720, resizable: true, scrollable: true,
                               style: UI::HtmlDialog::STYLE_DIALOG)
      html = File.read(File.join(PATH, 'html', 'settings.html'))
      dlg.set_html(html.sub('/*DATA*/null', JSON.generate(Settings.get)))
      dlg.add_action_callback('cancel') { |_c| dlg.close }
      dlg.add_action_callback('reset') do |_c|
        next unless UI.messagebox('Reset all settings to the plugin defaults?', MB_YESNO) == IDYES
        Settings.reset
        dlg.close
        offer_rebuild
      end
      dlg.add_action_callback('save') do |_c, json|
        begin
          data = JSON.parse(json)
          Settings.save(Settings.get.merge(data))
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

      doors_menu = menu.add_submenu('All doors')
      Styles.ids.each { |s| doors_menu.add_item("#{Styles.label(s)}") { convert_all(:door, s) } }
      drawers_menu = menu.add_submenu('All external drawer fronts')
      Styles.ids.each { |s| drawers_menu.add_item("#{Styles.label(s)}") { convert_all(:ext_drawer, s) } }

      cmd_reset = command('Reset all to Flat', 'Set every door and external drawer front back to Flat (hinges kept).', 'reset') { reset_all_flat }
      menu.add_item(cmd_reset)

      cmd_rebuild = command('Rebuild styles', 'Redraw every converted door and drawer front at its current size.', 'rebuild') { rebuild_all }
      menu.add_item(cmd_rebuild)
      menu.add_item('Apply DOOR / DRAWER_FRONT tags') { apply_tags }

      hinge_menu = menu.add_submenu('Hinge type (this job)')
      Settings::HINGE_TYPES.each do |id, label|
        c = UI::Command.new(label) { set_hinge_type(id) }
        c.set_validation_proc { Settings.job_hinge_type == id ? MF_CHECKED : MF_UNCHECKED }
        hinge_menu.add_item(c)
      end

      menu.add_separator
      cmd_summary = command('Door summary', 'Show the door and drawer front summary (CSV / PDF export).', 'summary') { Report.show }
      cmd_settings = command('Settings', 'Frame sizes, mid-rail, hinge rules and component names.', 'settings') { show_settings }
      cmd_export = command('Export door order (CSV + PDF)', 'Save DOOR_ORDER_v<N>_<file name>.csv and .pdf next to the SketchUp file.', 'export') { Report.export_order }
      menu.add_item(cmd_summary)
      menu.add_item(cmd_export)
      menu.add_item(cmd_settings)

      tb = UI::Toolbar.new('HW Door Style')
      tb.add_item(command('All doors - Shaker', 'Convert every door in the model to Shaker.', 'doors') { convert_all(:door, 'shaker') })
      tb.add_item(command('All external drawer fronts - Shaker', 'Convert every external drawer front to Shaker (50 mm frame).', 'drawers') { convert_all(:ext_drawer, 'shaker') })
      tb.add_item(cmd_reset)
      tb.add_separator
      tb.add_item(cmd_rebuild)
      tb.add_item(cmd_summary)
      tb.add_item(cmd_export)
      tb.add_item(cmd_settings)
      tb.restore

      UI.add_context_menu_handler do |cm|
        targets = selection_targets
        next if targets.empty?
        sub = cm.add_submenu('HW Door Style')
        if targets.all? { |_i, k| k == :int_drawer }
          id = sub.add_item('Internal drawer fronts stay flat') {}
          sub.set_validation_proc(id) { MF_GRAYED }
        else
          Styles.ids.each { |s| sub.add_item("Style: #{Styles.label(s)}") { convert_selection(s) } }
          sub.add_separator
          sub.add_item('Rebuild selected') { rebuild_selection }
        end
      end

      file_loaded(__FILE__)
    end
  end
end
