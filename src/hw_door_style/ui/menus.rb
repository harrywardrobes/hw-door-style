module HarryWardrobes
  module DoorStyle
    # Extensions > HW Door Style menu, the toolbar and the right-click menu.
    # Built once when the plugin loads (main.rb).
    #
    # To add a button: make a command with Menus.command (icon = icons/<name>.svg),
    # add it to the menu below and, if it belongs on the toolbar, to TOOLBAR order.
    module Menus
      # An icon file of your own wins: %APPDATA%\HW Door Style\icons\<name>.svg (or .png),
      # e.g. the HubSpot logo from HubSpot's own brand kit as hubspot.svg / hubspot.png.
      def self.icon(name)
        own = %w[svg png].map { |x| File.join(Settings::USER_DIR, 'icons', "#{name}.#{x}") }.find { |f| File.exist?(f) }
        own || File.join(PATH, 'icons', "#{name}.svg")
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

        # Add a library component (picture cards, set up to the job when placed)
        c[:add] = command('Add component', 'Pick a component from the library (pictures by category) and place it - set up with this job\'s colours, door style, hinges, runouts and ceiling height.',
                          'plus') { ComponentPicker.show }
        menu.add_item(c[:add])
        menu.add_separator

        # Doors and drawer fronts
        c[:doors] = command('Door style', 'Styles for doors, drawer fronts and internal drawers, hinge type and handles for this job.',
                            'doors') { DoorStyleWindow.show }
        menu.add_item(c[:doors])
        menu.add_item('Rebuild styles (keep each item\'s style)') { Doors.rebuild_all }
        menu.add_item('Apply tags (doors, drawer fronts, hardware)') { Doors.apply_tags }
        menu.add_item('Repair doors in model') { Doors.repair }

        # Colours
        menu.add_separator
        c[:colours] = command('Colours', 'Set door, exterior, interior and worktop colours for this job.', 'colours') { ColoursWindow.show }
        menu.add_item(c[:colours])
        menu.add_item('Export colour library (.skm)') { ColoursWindow.export_library }

        # Summary and settings
        menu.add_separator
        c[:summary] = command('Door summary', 'Show the door and drawer front summary (PDF export).', 'summary') { Report.show }
        c[:settings] = command('Settings', 'Frame sizes, mid-rail, hinge rules and component names.', 'settings') { SettingsWindow.show }
        menu.add_item(c[:summary])
        c[:parts] = command('Workshop', 'Everything for the workshop in one window: door order, sheet goods (boards, strips, edging), hardware and handles, labels to print - saved as one pack and synced to the HubSpot Room. Parts rules from OpenCutList.',
                            'parts') { PartsList.show }
        menu.add_item(c[:parts])
        menu.add_item('Export Door / Vinyl order (PDF)') { Report.export_order }
        menu.add_item(c[:settings])

        # HubSpot (one file = one Room)
        hs = menu.add_submenu('HubSpot')
        hs.add_item('New room from HubSpot...') { HubSpotRoom.show_pick(:new) }
        hs.add_item('Link this file to a HubSpot room...') { HubSpotRoom.show_pick(:link) }
        c[:hubspot] = command('Send to HubSpot...', 'The whole HubSpot Room card with this file\'s sizes, runouts, colours and hardware filled in; you see every change before it is sent.',
                              'hubspot') { HubSpotRoom.show_send }
        hs.add_item(c[:hubspot])
        hs.add_item('Pictures to HubSpot...') { HubSpotPictures.show }
        hs.add_item('Hardware products...') { ProductsWindow.show }
        hs.add_item('Open Room in HubSpot') { HubSpotRoom.open_in_hubspot('listings') }
        hs.add_item('Open Project in HubSpot') { HubSpotRoom.open_in_hubspot('projects') }

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

      # Two toolbars (nil = separator). Everyday survey work, then the admin / library tools.
      TOOLBARS = {
        'HW measure once' => [:add, nil, :colours, :doors, nil, :pencil, :parts, :hubspot],
        'HW dev' => [:settings, :export]
      }.freeze

      def self.toolbar(cmds)
        TOOLBARS.each do |name, keys|
          tb = UI::Toolbar.new(name)
          keys.each { |k| k ? tb.add_item(cmds[k]) : tb.add_separator }
          tb.get_last_state == TB_HIDDEN ? tb.hide : tb.show
        end
      end

      def self.context_menu
        UI.add_context_menu_handler do |cm|
          # (front_menu below: right-click > HW Door Style > Front type)
          targets = Doors.selection_targets
          units = Runouts.selected | Facing.selected | DrawerFront.selected
          deep = Depth.selected
          sel = Sketchup.active_model.selection
          part = sel.size == 1 && (sel.first.is_a?(Sketchup::ComponentInstance) || sel.first.is_a?(Sketchup::Group)) ? sel.first : nil
          next if targets.empty? && units.empty? && deep.empty? && part.nil?
          sub = cm.add_submenu('HW Door Style')
          if part
            Plan.menu(sub, part)
            front_menu(sub, part) if part.is_a?(Sketchup::ComponentInstance)
            part_menu(sub, part) if part.is_a?(Sketchup::ComponentInstance)
            sub.add_separator unless deep.empty? && units.empty? && targets.empty?
          end
          unless deep.empty?
            Depth.menu(sub, deep)
            sub.add_separator unless units.empty? && targets.empty?
          end
          unless units.empty?
            sub.add_item(units.size == 1 ? 'Runouts / facing / drawer fronts (this unit)...' : "Runouts / facing / drawer fronts (#{units.size} units)...") do
              Pencil.show(Sketchup.active_model, units)
            end
            next if targets.empty?
            sub.add_separator
          end
          Styles.ids.each { |s| sub.add_item("Style: #{Styles.label(s)}") { Doors.convert_selection(s) } }
          if targets.any? { |_i, k| k == :door }
            sub.add_separator
            doors = targets.select { |_i, k| k == :door }.map(&:first)
            own = doors.map { |d| Converter.hinge_override(d) }.uniq
            cur = own.size == 1 && own.first ? Settings::HINGE_TYPES[own.first] : (own.size > 1 ? 'mixed' : "job's")
            hm = sub.add_submenu("Hinge (#{cur})")
            Settings::HINGE_TYPES.each { |k, l| hm.add_item("Hinge: #{l}") { Doors.hinge_selection(k) } }
            hm.add_separator
            hm.add_item("Hinge: the job's (#{Settings::HINGE_TYPES[Settings.job_hinge_type]})") { Doors.hinge_selection(nil) }
          end
          sub.add_separator
          sub.add_item('Follow the Door style window') { Doors.follow_job }
          sub.add_item('Rebuild selected') { Doors.rebuild_selection }
        end
      end

      # Right-click > Front type: what the component is (kept on it, so it travels with copies
      # and exports), or back to finding it by name.
      def self.front_menu(sub, inst)
        cur = Finder.role(inst)
        fm = sub.add_submenu("Front type (#{cur ? Finder::ROLE_LABELS.to_h[cur] : 'by name'})")
        set = lambda do |role, label|
          model = Sketchup.active_model
          Ops.run(model, "Front type: #{label}") { Finder.set_role([inst], role) }
          Sketchup.status_text = "#{inst.definition.name}: #{label}. Apply the Door style window to style it."
        end
        Finder::ROLE_LABELS.each do |role, label|
          item = fm.add_item(label) { set.call(role, label) }
          fm.set_validation_proc(item) { cur == role ? MF_CHECKED : MF_ENABLED }
        end
        fm.add_separator
        item = fm.add_item('By name (Settings > Doors)') { set.call(nil, 'by name') }
        fm.set_validation_proc(item) { cur.nil? ? MF_CHECKED : MF_ENABLED }
      end

      # Right-click > Part type: which Workshop section a part goes in (kept on it), or
      # automatic (name / thickness).
      def self.part_menu(sub, inst)
        cur = PartsList.part_role(inst.definition)
        fm = sub.add_submenu("Part type (#{cur ? PartsList::PART_ROLE_LABELS.to_h[cur] : 'automatic'})")
        set = lambda do |role, label|
          model = Sketchup.active_model
          Ops.run(model, "Part type: #{label}") { role ? inst.definition.set_attribute(DICT, PartsList::PART_ROLE, role) : inst.definition.delete_attribute(DICT, PartsList::PART_ROLE) }
          Sketchup.status_text = "#{inst.definition.name}: #{label}."
        end
        PartsList::PART_ROLE_LABELS.each do |role, label|
          item = fm.add_item(label) { set.call(role, label) }
          fm.set_validation_proc(item) { cur == role ? MF_CHECKED : MF_ENABLED }
        end
        fm.add_separator
        item = fm.add_item('Automatic (name / thickness)') { set.call(nil, 'automatic') }
        fm.set_validation_proc(item) { cur.nil? ? MF_CHECKED : MF_ENABLED }
      end
    end
  end
end
