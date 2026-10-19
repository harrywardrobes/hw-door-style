require 'json'

module HarryWardrobes
  module DoorStyle
    # The pencil (scribe) button and its window.
    #
    # Its pressed state comes from the model itself, like SketchUp's own
    # toggles (X-ray, Hidden Geometry): pressed when any unit has a runout
    # above 0, released when every runout is 0. Worked out once and cached per
    # model; the cache is cleared after every change / undo / redo and when a
    # file is opened or switched (observers below).
    module Pencil
      # --- state -------------------------------------------------------------

      def self.on?(model = Sketchup.active_model)
        return true unless model
        @state ||= {}
        k = model.object_id
        @state[k] = detect(model) unless @state.key?(k)
        @state[k]
      end

      # Stops at the first unit with a runout. With no units at all, the last
      # pencil state saved on the model is used.
      def self.detect(model)
        seen = false
        Runouts.each_unit(model.entities) do |u|
          seen = true
          return true if Runouts.any?(u)
        end
        seen ? false : (model.get_attribute(DICT, 'scribe_on', true) ? true : false)
      end

      # While a long job runs (a Batch, Export components) every unit commits
      # its own step; the check is held until the job ends instead of
      # re-scanning per unit.
      def self.invalidate(model = nil)
        @state ||= {}
        return @dirty = true if busy?
        model ? @state.delete(model.object_id) : @state.clear
      end

      def self.busy?
        @busy ? true : false
      end

      def self.hold
        @busy = true
      end

      def self.release
        @busy = false
        invalidate if @dirty
        @dirty = false
        UI.refresh_toolbars if UI.respond_to?(:refresh_toolbars)
      end

      # --- button -------------------------------------------------------------

      # Pressed -> every runout 0 straight away. Released -> the window.
      def self.toggle(model = Sketchup.active_model)
        return if busy? || !Standardise.ready?(model)
        on?(model) ? Runouts.all_off(model) : show(model, nil)
      end

      # Window: every unit (targets nil) or just the selected units. Runouts,
      # bottom facing and (every unit only) the ceiling height.
      def self.show(model, targets)
        return unless Standardise.ready?(model)
        TopOfUnit.upgrade(model)
        sel = targets && !targets.empty?
        units = sel ? targets : (Runouts.units(model.entities) | Facing.units(model.entities))
        job = Runouts.job_values(model)
        first_r = units.find { |u| Runouts.unit?(u) }
        first_f = units.find { |u| Facing.has?(u) }
        cur = sel && first_r ? Runouts::SIDES.to_h { |s, _, _| [s, Runouts.mm_of(first_r, s) || job[s]] } : job
        label = sel ? (targets.size == 1 ? Finder.label(targets.first) : "#{targets.size} selected units") : nil
        data = {
          'title' => sel ? "Runouts & bottom facing - #{label}" : 'Scribes on - runouts for every unit',
          'selection' => sel ? true : false,
          'sides' => Runouts::SIDES.map { |s, _, l| [s, l.sub(/\ARunout - /, '').sub(' (mm)', '')] },
          'values' => [0.0] + Runouts.values_list, 'current' => cur, 'job' => job,
          'has_runouts' => !first_r.nil?, 'has_facing' => !first_f.nil?,
          'facing' => (sel && first_f ? Facing.of(first_f) : nil) || Facing.mm(model), 'facing_job' => Facing.mm(model),
          'ceiling' => sel ? nil : Ceiling.mm(model), 'top_door' => Ceiling.top_door_mm,
          'own' => TopOfUnit.own_height(units)
        }
        # Taller, and resizable: ceiling + bottom facing + five runouts didn't fit in 400 (Apply was cut off).
        # New key so SketchUp doesn't reuse the old remembered size.
        dlg = Dialog.open('scribe', title: 'HW - Scribe / runout', key: 'hw_scribe_v2', width: 400, height: 600,
                                    data: data, resizable: true, scrollable: false)
        dlg.add_action_callback('apply') do |_c, json|
          raw = JSON.parse(json)
          ceil = raw.delete('ceiling_height').to_f
          facing = raw.key?('facing') ? raw['facing'].to_f : nil
          heights = raw.delete('own') || {}
          v = data['has_runouts'] ? raw.transform_values(&:to_f).slice(*Runouts::KEYS.keys) : nil
          dlg.close
          # Units with their own height (Custom Scribe Height / No Upper Facing): set the ones you changed.
          changed = data['own'].select { |o| heights[o['id'].to_s].to_f.positive? && (heights[o['id'].to_s].to_f - o['height']).abs >= 1 }
          unless changed.empty?
            Ops.run(model, 'Unit heights') do
              changed.each do |o|
                u = units.find { |x| x.valid? && x.entityID == o['id'] } or next
                Ceiling.fit(u, heights[o['id'].to_s].to_f)
              end
            end
          end
          if sel
            Runouts.apply(model, targets, v, 'Runouts (selected)', "Runouts / bottom facing updated on #{targets.size} unit(s).", facing: facing)
          else
            Runouts.apply(model, units, v, 'Scribes on',
                          "Scribes on: #{v ? Runouts::SIDES.map { |s, _, _| "#{s} #{v[s].round}" }.join(', ') + ' mm. ' : ''}Ceiling #{ceil.round} mm, top doors #{Ceiling.top_door_mm.round} mm, bottom facing #{facing.to_f.round} mm.",
                          ceiling: ceil, facing: facing,
                          before: lambda {
                            model.set_attribute(DICT, 'scribe_on', true)
                            model.set_attribute(DICT, 'scribe_values', JSON.generate(v)) if v
                            model.set_attribute(DICT, 'ceiling_mm', ceil)
                            model.set_attribute(DICT, 'facing_btm_mm', facing) if facing
                          })
          end
        end
        dlg.show
      end

      # --- observers -----------------------------------------------------------
      # Started once from ui/menus.rb at load; one ModelWatch serves every model.

      class ModelWatch < Sketchup::ModelObserver
        def onTransactionCommit(model); Pencil.invalidate(model); end
        def onTransactionUndo(model); Pencil.invalidate(model); end
        def onTransactionRedo(model); Pencil.invalidate(model); end
        def onTransactionAbort(model); Pencil.invalidate(model); end
      end

      class AppWatch < Sketchup::AppObserver
        # Also told about the model SketchUp opens at start-up (or by double-click).
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); Pencil.watch(model); end
        def onOpenModel(model); Pencil.watch(model); end
        def onActivateModel(model); Pencil.watch(model); end
      end

      def self.watch(model)
        return unless model
        @watched ||= {}
        unless @watched[model.object_id]
          model.add_observer(@model_watch ||= ModelWatch.new)
          @watched[model.object_id] = true
        end
        invalidate(model)
        UI.refresh_toolbars if UI.respond_to?(:refresh_toolbars)
      end

      def self.start_watching
        return if @app_watch
        @app_watch = AppWatch.new
        Sketchup.add_observer(@app_watch)
        watch(Sketchup.active_model)
      end
    end
  end
end
