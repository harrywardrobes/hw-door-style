module HarryWardrobes
  module DoorStyle
    # Extensions > HW Door Style menu, the toolbar and the right-click menu.
    # Built once when the plugin loads (main.rb).
    #
    # To add a button: make a command with Menus.command (icon = icons/<name>.svg),
    # add it to the menu below and, if it belongs on the toolbar, to TOOLBAR order.
    module Menus
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

      def self.build
        menu = UI.menu('Extensions').add_submenu('HW Door Style')
        c = {}

        # Doors and drawer fronts
        c[:shaker] = command('Shaker - all doors & drawer fronts',
                             'Make every door and external drawer front Shaker. Press again after resizing to redraw them.',
                             'doors') { Doors.convert_all('shaker') }
        menu.add_item(c[:shaker])
        style_menu = menu.add_submenu('All doors & drawer fronts')
        Styles.ids.each { |s| style_menu.add_item(Styles.label(s)) { Doors.convert_all(s) } }
        c[:reset] = command('Reset all to Flat', 'Set every door and external drawer front back to Flat (hinges kept).',
                            'reset') { Doors.reset_all_flat }
        menu.add_item(c[:reset])
        menu.add_item('Rebuild styles (keep each item\'s style)') { Doors.rebuild_all }
        menu.add_item('Apply tags (doors, drawer fronts, hardware)') { Doors.apply_tags }
        menu.add_item('Repair doors in model') { Doors.repair }
        hinge_menu = menu.add_submenu('Hinge type (this job)')
        Settings::HINGE_TYPES.each do |id, label|
          h = UI::Command.new(label) { Doors.set_hinge_type(id) }
          h.set_validation_proc { Settings.job_hinge_type == id ? MF_CHECKED : MF_UNCHECKED }
          hinge_menu.add_item(h)
        end

        # Colours
        menu.add_separator
        c[:colours] = command('Colours', 'Set door, exterior, interior and worktop colours for this job.', 'colours') { ColoursWindow.show }
        menu.add_item(c[:colours])
        menu.add_item('Export colour library (.skm)') { ColoursWindow.export_library }

        # Summary and settings
        menu.add_separator
        c[:summary] = command('Door summary', 'Show the door and drawer front summary (CSV / PDF export).', 'summary') { Report.show }
        c[:settings] = command('Settings', 'Frame sizes, mid-rail, hinge rules and component names.', 'settings') { SettingsWindow.show }
        menu.add_item(c[:summary])
        menu.add_item('Export door order (CSV + PDF)') { Report.export_order }
        menu.add_item(c[:settings])

        # Library export, scribes, ceiling
        menu.add_separator
        c[:export] = command('Export components',
                             'Library file only: export each component to its own versioned file (old versions to _old).',
                             'rocket') { LibraryExport.show }
        menu.add_item(c[:export])
        c[:pencil] = command('Scribe / runout',
                             'Pressed: every unit has the job runouts. Click to set all to 0 (easier to move); click again to choose floor, ceiling, left, right and back.',
                             'pencil') { Pencil.toggle }
        c[:pencil].set_validation_proc { Pencil.on? ? MF_CHECKED : MF_UNCHECKED }
        menu.add_item(c[:pencil])
        c[:ceiling] = command('Ceiling height',
                              'Set the ceiling height for every unit with "Up to ceiling" = TRUE (any time; scribes not changed).',
                              'ceiling') { Ceiling.show }
        menu.add_item(c[:ceiling])
        menu.add_item('Runouts - re-apply job values to every unit') { Pencil.show(Sketchup.active_model, nil) }

        # Developer (only with the developer switch on)
        menu.add_separator if Developer.enabled?
        Developer.add_menu(menu)

        toolbar(c)
        context_menu
      end

      TOOLBAR = [:colours, :shaker, :reset, nil, :summary, :settings, nil, :export, :pencil, :ceiling].freeze # nil = separator

      def self.toolbar(cmds)
        tb = UI::Toolbar.new('HW Door Style')
        TOOLBAR.each { |k| k ? tb.add_item(cmds[k]) : tb.add_separator }
        tb.restore
      end

      def self.context_menu
        UI.add_context_menu_handler do |cm|
          targets = Doors.selection_targets
          units = Runouts.selected
          next if targets.empty? && units.empty?
          sub = cm.add_submenu('HW Door Style')
          unless units.empty?
            sub.add_item(units.size == 1 ? 'Runouts (this unit)...' : "Runouts (#{units.size} units)...") do
              Pencil.show(Sketchup.active_model, units)
            end
            next if targets.empty?
            sub.add_separator
          end
          if targets.all? { |_i, k| k == :int_drawer }
            id = sub.add_item('Internal drawer fronts stay flat') {}
            sub.set_validation_proc(id) { MF_GRAYED }
          else
            Styles.ids.each { |s| sub.add_item("Style: #{Styles.label(s)}") { Doors.convert_selection(s) } }
            sub.add_separator
            sub.add_item('Rebuild selected') { Doors.rebuild_selection }
          end
        end
      end
    end
  end
end
