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

      # An on / off switch: pressed -> every runout 0; released -> every unit back to the
      # job's runouts (Room settings changes them, without switching).
      def self.toggle(model = Sketchup.active_model)
        return if busy?
        on?(model) ? Runouts.all_off(model) : Runouts.all_on(model)
      end

      # Room settings (targets nil: every unit) or the right-click window for the selected units:
      # runouts, bottom facing, drawer fronts and (every unit only) ceiling, depth and room size.
      # Room settings never switches the scribes: with them off, the runouts are kept as the
      # job's values for when they're switched on, and the units stay at 0.
      def self.show(model, targets)
        sel = targets && !targets.empty?
        units = sel ? targets : (Runouts.units(model.entities) | Facing.units(model.entities) | Depth.units(model.entities) | DrawerFront.units(model.entities))
        job = Runouts.job_values(model)
        first_r = units.find { |u| Runouts.unit?(u) }
        first_f = units.find { |u| Facing.has?(u) }
        first_d = units.find { |u| DrawerFront.has?(u, 'main') }
        first_s = units.find { |u| DrawerFront.has?(u, 'small') }
        scribes = on?(model)
        cur = sel && first_r ? Runouts::SIDES.to_h { |s, _, _| [s, Runouts.mm_of(first_r, s) || job[s]] } : job
        label = sel ? (targets.size == 1 ? Finder.label(targets.first) : "#{targets.size} selected units") : nil
        data = {
          'title' => sel ? "Runouts, facing & drawer fronts - #{label}" : 'Room settings',
          'scribes_on' => scribes,
          'selection' => sel ? true : false,
          'sides' => Runouts::SIDES.map { |s, _, l| [s, l.sub(/\ARunout - /, '').sub(' (mm)', '')] },
          'values' => [0.0] + Runouts.values_list, 'current' => cur, 'job' => job,
          'has_runouts' => !first_r.nil?, 'has_facing' => !first_f.nil?,
          'facing' => (sel && first_f ? Facing.of(first_f) : nil) || Facing.mm(model), 'facing_job' => Facing.mm(model),
          'has_front' => !first_d.nil? || !sel, 'front' => (sel && first_d ? DrawerFront.of(first_d, 'main') : nil) || DrawerFront.mm(model, 'main'), 'front_job' => DrawerFront.mm(model, 'main'),
          'has_small' => !first_s.nil? || !sel, 'small' => (sel && first_s ? DrawerFront.of(first_s, 'small') : nil) || DrawerFront.mm(model, 'small'), 'small_job' => DrawerFront.mm(model, 'small'),
          'ceiling' => sel ? nil : Ceiling.mm(model), 'top_door' => Ceiling.top_door_mm,
          'own' => TopOfUnit.own_height(units),
          'depth' => sel ? nil : Depth.job_values(model),
          'room' => sel ? nil : (Room.get(model) || {}).merge('has_floor' => !Room.parts(model)[:floor].nil?, 'has_ceiling' => !Room.parts(model)[:ceiling].nil?)
        }
        # Taller, and resizable: ceiling + bottom facing + five runouts didn't fit in 400 (Apply was cut off).
        # New key so SketchUp doesn't reuse the old remembered size.
        dlg = Dialog.open('scribe', title: sel ? 'HW - Runouts / facing / drawer fronts' : 'HW - Room settings', key: 'hw_scribe_v2', width: 400, height: 680,
                                    data: data, resizable: true, scrollable: false)
        dlg.add_action_callback('apply') do |_c, json|
          raw = JSON.parse(json)
          ceil = raw.delete('ceiling_height').to_f
          facing = raw.key?('facing') ? raw['facing'].to_f : nil
          front = {}
          front['main'] = raw.delete('front').to_f if raw.key?('front')
          front['small'] = raw.delete('small').to_f if raw.key?('small')
          front = nil if front.empty?
          heights = raw.delete('own') || {}
          dep = raw.delete('depth')
          room_w = raw.delete('room_width').to_f
          room_l = raw.delete('room_length').to_f
          v = data['has_runouts'] ? raw.transform_values(&:to_f).slice(*Runouts::KEYS.keys) : nil
          Dialog.leave(dlg, 'scribe')
          fin = -> { Dialog.done('scribe') } # back to the Workshop (Fix this)
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
          # The room (floor / ceiling parts): its own step, so it happens even with no units yet.
          unless sel
            Ops.run(model, 'Room size') { Room.apply(model, width: room_w, length: room_l, ceiling: ceil) }
          end
          # Scribes off: keep the runouts as the job's values, leave the units at 0 - unless this is
          # the first time they're set (a new room starts at 0), when they go on straight away.
          first = !sel && !scribes && Runouts.unset(model).size == Runouts::SIDES.size
          run = sel || scribes || first ? v : nil
          if (sel ? targets : units).empty?
            fin.call
          elsif sel
            Runouts.apply(model, targets, v, 'Runouts (selected)', "Runouts / facing / drawer fronts updated on #{targets.size} unit(s).", facing: facing, front: front, after: fin)
          else
            Runouts.apply(model, units, run, 'Room settings',
                          "Room settings: #{v ? "runouts #{Runouts::SIDES.map { |s, _, _| "#{s} #{v[s].round}" }.join(', ')} mm#{scribes ? '' : ' (kept for when scribes are switched on)'}. " : ''}Ceiling #{ceil.round} mm, top doors #{Ceiling.top_door_mm.round} mm, bottom facing #{facing.to_f.round} mm#{front ? ", drawer fronts #{front['main'].to_f.round} / small #{front['small'].to_f.round} mm" : ''}.",
                          ceiling: ceil, facing: facing, depth: !dep.nil?, front: front, after: fin,
                          before: lambda {
                            model.set_attribute(DICT, 'scribe_on', true) if first
                            model.set_attribute(DICT, 'scribe_values', JSON.generate(v)) if v
                            model.set_attribute(DICT, 'ceiling_mm', ceil)
                            model.set_attribute(DICT, 'depth_job', JSON.generate(dep)) if dep
                            model.set_attribute(DICT, 'facing_btm_mm', facing) if facing
                            front&.each { |k, val| model.set_attribute(DICT, DrawerFront::MODEL[k], val) }
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
