require 'json'

module HarryWardrobes
  module DoorStyle
    # The Colours window (toolbar: colours): this job's door, exterior,
    # interior, worktop, 22mm panel and drawer box colours.
    module ColoursWindow
      def self.show
        model = Sketchup.active_model
        dlg = Dialog.open('colours', title: 'HW Door Style - Colours', key: 'hw_door_style_colours',
                                     width: 480, height: 380, data: Colours.dialog_data(model), scrollable: false)
        dlg.add_action_callback('apply') do |_c, json|
          choices = JSON.parse(json)
          begin
            result = apply(model, choices)
            dlg.close
            UI.messagebox("Colours applied.\n\n#{summary(model, choices, result).join("\n")}")
          rescue StandardError => e
            UI.messagebox("Colours not applied (undone).\n\n#{e.message}")
            Log.error('colours', e)
          end
        end
        dlg.show
      end

      # Paints the model (one undo step). Units whose drawer box thickness
      # changed are then redrawn by the DC engine and repainted, merged into
      # the same undo step (a redraw can rebuild copied drawers).
      def self.apply(model, choices)
        box = choices['drawer_box'] || DrawerBox::DEFAULT
        counts, thick = Ops.run(model, 'Apply colours') do
          c = Colours.apply(model, choices)
          t = Settings.get['box_thickness_follows_finish'] ? DrawerBox.set_thickness(model, box) : { changed: [], open: [] }
          [c, t]
        end
        problems = []
        unless thick[:changed].empty?
          problems = DrawerBox.redraw(thick[:changed])
          Ops.run(model, 'Re-apply colours after redraw', transparent: true) { Colours.reapply(model) }
        end
        { counts: counts, thick: thick, problems: problems }
      end

      def self.summary(model, choices, result)
        shown = Colours.resolved(model, choices)
        lines = Colours::GROUPS.map do |id, label|
          name = shown[id] == Colours::DEFAULT ? 'no material' : shown[id]
          name = "Default (#{name})" if choices[id] == Colours::DEFAULT && id != 'drawer_box'
          name = "#{name} #{format('%g', DrawerBox.thickness_mm(name))}mm" if id == 'drawer_box'
          "#{label}: #{name} - #{result[:counts][id]} part(s)"
        end
        thick = result[:thick]
        lines << '' << "Box thickness updated on: #{thick[:changed].map { |u| Finder.label(u) }.uniq.join(', ')}" unless thick[:changed].empty?
        lines << '' << "NOT updated (drawers open - close them and apply again): #{thick[:open].uniq.join(', ')}" unless thick[:open].empty?
        lines << '' << 'Check:' << result[:problems] unless result[:problems].empty?
        lines.flatten
      end

      # Menu: every library colour saved as a .skm file.
      def self.export_library
        dir = UI.select_directory(title: 'Choose a folder for the colour .skm files')
        return unless dir
        model = Sketchup.active_model
        files = Ops.run(model, 'Export colour library') { Colours.export_skm(model, dir) }
        UI.messagebox("#{files.size} materials saved to:\n#{dir}")
      rescue StandardError => e
        UI.messagebox("Export failed: #{e.message}")
        Log.error('colour library', e)
      end
    end
  end
end
