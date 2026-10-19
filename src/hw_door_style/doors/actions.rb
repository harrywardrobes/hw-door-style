module HarryWardrobes
  module DoorStyle
    # What the door menu items and toolbar buttons do. Each change is one undo
    # step (Converter.apply / Ops.run); messages come after the step is done.
    module Doors
      STYLED_KINDS = [:door, :ext_drawer].freeze

      # Runs a Converter job and reports it. Returns the result, or nil on failure.
      def self.run(op_name)
        result = yield
        msg = "#{op_name}: #{result[:items]} item(s) updated"
        msg += "\n\n" + result[:notes].join("\n") unless result[:notes].empty?
        Sketchup.status_text = msg.lines.first.strip
        UI.messagebox(msg) unless result[:notes].empty?
        result
      rescue StandardError => e
        UI.messagebox("HW Door Style - #{op_name} failed and was undone.\n\n#{e.message}")
        Log.error(op_name, e)
        nil
      end

      # Doors can't be edited until the job has a Door / Drawer colour.
      def self.colour_ready?
        return true if Colours.door_colour_chosen?
        UI.messagebox('Choose a Door / Drawer colour for this job before editing doors.')
        ColoursWindow.show
        false
      end

      # Every door AND external drawer front to one style, in one undo step.
      # Pressing it again redraws everything at its current size (same as Rebuild).
      def self.convert_all(style)
        return unless colour_ready?
        pairs = Finder.all_targets(Sketchup.active_model, STYLED_KINDS)
        if pairs.empty?
          UI.messagebox("No doors or drawer fronts found.\nCheck the component names in HW Door Style > Settings.")
          return
        end
        name = "All doors & drawer fronts - #{Styles.label(style)}"
        run(name) { Converter.apply(pairs, style, name) }
      end

      # Every door and external drawer front -> Flat (hardware kept), one undo step.
      def self.reset_all_flat
        return unless colour_ready?
        pairs = Finder.all_targets(Sketchup.active_model, STYLED_KINDS)
        return UI.messagebox('No doors or drawer fronts found.') if pairs.empty?
        return unless UI.messagebox("Reset all #{pairs.size} doors and drawer fronts to Flat?", MB_YESNO) == IDYES
        run('Reset all to Flat') { Converter.apply(pairs, 'flat', 'Reset all to Flat') }
      end

      def self.repair
        r = Repair.run(Sketchup.active_model)
        UI.messagebox(Repair.message(r), MB_MULTILINE, 'HW Door Style - Repair doors')
      rescue StandardError => e
        UI.messagebox("Repair failed and was undone.\n\n#{e.message}")
        Log.error('repair', e)
      end

      def self.apply_tags
        model = Sketchup.active_model
        n = Ops.run(model, 'Apply door, drawer front and hardware tags') { Tagger.tag_all(model) }
        Sketchup.status_text = "Tags applied: #{n} items updated"
        left = Tagger.hardware_leftovers(model)
        msg = "#{n} faces, edges and hardware components re-tagged."
        msg += "\n\nHardware tags:\n" + Settings.hardware_tags.map { |t, ns| "#{t}: #{ns.join(', ')}" }.join("\n")
        msg += if left.empty?
                 "\n\nNothing is on the HARDWARE tag."
               else
                 "\n\nStill on HARDWARE (add these to Settings > Hardware tags):\n" + left.map { |k, c| "#{k} x#{c}" }.join("\n")
               end
        UI.messagebox(msg)
      rescue StandardError => e
        UI.messagebox("Tagging failed and was undone.\n\n#{e.message}")
        Log.error('tags', e)
      end

      # Doors / drawer fronts the plugin has converted at least once.
      def self.processed(model, kinds = STYLED_KINDS)
        Finder.all_targets(model, kinds).select { |i, _k| i.definition.get_attribute(DICT, 'style') }
      end

      def self.rebuild_all
        return unless colour_ready?
        pairs = processed(Sketchup.active_model)
        if pairs.empty?
          UI.messagebox('Nothing to rebuild - no doors or drawer fronts have been converted yet.')
          return
        end
        run('Rebuild styles') { Converter.apply(pairs, nil, 'Rebuild styles') }
      end

      # After Settings change: offer to redraw what's already converted.
      def self.offer_rebuild
        return if processed(Sketchup.active_model).empty?
        rebuild_all if UI.messagebox('Settings saved. Rebuild the converted doors and drawer fronts in this model now?', MB_YESNO) == IDYES
      end

      def self.set_hinge_type(type)
        model = Sketchup.active_model
        pairs = processed(model, [:door])
        if pairs.empty?
          Ops.run(model, 'Set hinge type') { Settings.set_job_hinge_type(type, model) }
          Sketchup.status_text = "Hinge type for this job: #{Settings::HINGE_TYPES[type]}"
        else
          name = "Hinge type - #{Settings::HINGE_TYPES[type]}"
          run(name) { Converter.apply(pairs, nil, name, hinge_type: type) }
        end
      end

      def self.selection_targets
        Finder.targets(Sketchup.active_model.selection.to_a, [:door, :ext_drawer, :int_drawer])
      end

      # Right-click: the selected items to one style. They keep it when Apply is pressed in
      # the Door style window (override), until "Follow the Door style window".
      def self.convert_selection(style)
        return unless colour_ready?
        pairs = selection_targets
        return if pairs.empty?
        name = "Selected - #{Styles.label(style)}"
        run(name) { Converter.apply(pairs, style, name, override: true) }
      end

      # Right-click: back to the job's style for each item's row.
      def self.follow_job(pairs = selection_targets)
        return unless colour_ready?
        return if pairs.empty?
        styles = DoorStyleWindow.job_styles
        model = Sketchup.active_model
        run('Follow the Door style window') do
          Ops.run(model, 'Follow the Door style window') do
            r = { items: 0, definitions: 0, notes: [] }
            pairs.group_by { |_i, k| styles[k.to_s] }.each do |style, ps|
              x = Converter.rebuild(model, ps, style, override: false, finish: false)
              r[:items] += x[:items]
              r[:notes].concat(x[:notes])
            end
            Converter.finish(model)
            r
          end
        end
      end

      def self.rebuild_selection
        return unless colour_ready?
        pairs = selection_targets
        run('Rebuild selected') { Converter.apply(pairs, nil, 'Rebuild selected') }
      end
    end
  end
end
