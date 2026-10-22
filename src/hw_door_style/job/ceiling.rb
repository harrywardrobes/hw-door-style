module HarryWardrobes
  module DoorStyle
    # Ceiling height for the job (ceiling button, and the pencil window).
    #
    # Every unit with "Up to ceiling" = TRUE is built to the job's ceiling
    # height; units without that option are never touched (drawers, boxes...).
    # Runouts add on top. Scribes off never changes the height.
    #
    # Top doors: units with a "door_top_height" option (TOPBOX top doors,
    # BRIDGE_FRAME / BRIDGE_SKELETON) get Settings "top_door_height_mm" at the
    # same time, so the doors line up along the run. The bridge components
    # work out their own height and position from it: frame = door + facing
    # top + gaps, its top at the ceiling; the skeleton sits under the frame.
    module Ceiling
      # The unit's height option, first match wins (base names; any section prefix).
      HEIGHT_KEYS = %w[unit_height frame_height_ceiling frame_height ceiling_height size_height height].freeze

      def self.mm(model = Sketchup.active_model)
        model.get_attribute(DICT, 'ceiling_mm', 0).to_f
      end

      def self.height_key(inst)
        HEIGHT_KEYS.each do |b|
          k = DC.key(inst, b)
          return k if k
        end
        nil
      end

      # Top of unit = Scribed To Ceiling.
      def self.up_to_ceiling?(inst)
        TopOfUnit.choice(inst) == TopOfUnit::SCRIBED
      end

      def self.height_mm(inst)
        k = height_key(inst) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * mm_per(inst, k)).round(1)
      end

      # mm per stored unit. Options with units are stored in inches; one with no units
      # set (BXEND "height" = ROUND(CURRENT("LenZ"), 1)) is kept by DC in the model's own
      # family - cm in a metric model. Reading that 94.5 (cm) as inches gave 2400 mm, so
      # a 945 mm BXEND looked as if it was already at a 2400 ceiling and was never stretched.
      def self.mm_per(inst, k)
        u = inst.definition.get_attribute(DC::DICT_NAME, "_#{k}_units").to_s.upcase
        return 25.4 unless u.empty? || u == 'DEFAULT'
        metric?(inst.model) ? 10.0 : 25.4
      end

      def self.metric?(model)
        [2, 3, 4].include?(model.options['UnitsOptions']['LengthUnit'].to_i)
      rescue StandardError
        true
      end

      # Target height for this unit (nil = leave it).
      def self.target_mm(inst, ceiling)
        return nil unless ceiling.to_f.positive? && height_key(inst) && up_to_ceiling?(inst)
        ceiling.to_f
      end

      # Sets the height. Heights worked out from the stretched size
      # (CURRENT("LenZ")) are changed by stretching in Z about the unit's
      # origin, like the Scale tool; others are typed in.
      def self.set(inst, mm)
        k = height_key(inst) or return false
        cur = height_mm(inst)
        return false if cur && (cur - mm).abs < 0.5
        if DC.formula_of(inst, k) =~ /CURRENT/i && cur.to_f.positive?
          t = inst.transformation
          inst.transformation = Geom::Transformation.scaling(t.origin, 1, 1, mm / cur) * t
        else
          old = DC.read(inst, k)
          v = mm / mm_per(inst, k)
          inst.set_attribute(DC::DICT_NAME, k, old.is_a?(String) ? v.to_s : v)
        end
        true
      end

      # Sets the height and redraws, correcting up to 3 times (a stretched
      # unit's size can differ slightly from its height option). True if changed.
      def self.fit(inst, mm)
        changed = false
        3.times do
          break unless set(inst, mm)
          changed = true
          Drawers.close(inst.definition.entities)
          DC.redraw(inst)
        end
        changed
      end

      # --- top doors ---------------------------------------------------------

      def self.top_door_mm
        Settings.get['top_door_height_mm'].to_f
      end

      def self.top_door_of(inst)
        v = DC.value(inst, 'door_top_height')
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Sets the unit's top door height to the setting. True if it changed.
      def self.set_top_door(inst)
        want = top_door_mm
        k = DC.key(inst, 'door_top_height')
        return false unless want.positive? && k
        cur = DC.read(inst, k)
        return false if cur && (cur.to_f * 25.4 - want).abs < 0.5
        inst.set_attribute(DC::DICT_NAME, k, cur.is_a?(String) ? (want / 25.4).to_s : want / 25.4)
        true
      end

      # --- worktops -------------------------------------------------------------

      def self.worktop_mm
        Settings.get['worktop_height_mm'].to_f
      end

      # Sets a WORKTOP's height (bottom of the board, Settings "worktop_height_mm",
      # the height of the half units). True if it changed; the caller redraws.
      def self.set_worktop(inst)
        want = worktop_mm
        k = DC.key(inst, 'worktop_height')
        return false unless want.positive? && k
        cur = DC.read(inst, k)
        return false if cur && (cur.to_f * mm_per(inst, k) - want).abs < 0.5
        v = want / mm_per(inst, k)
        inst.set_attribute(DC::DICT_NAME, k, cur.is_a?(String) ? v.to_s : v)
        true
      end

      # The ceiling height (and top door) for one unit, redrawn once.
      # Units without "Up to ceiling" are left alone. True if anything changed.
      def self.apply_to(inst, ceiling)
        want = target_mm(inst, ceiling) or return false
        door = set_top_door(inst)
        fitted = fit(inst, want)
        if door && !fitted
          Drawers.close(inst.definition.entities)
          DC.redraw(inst)
        end
        Doors.refit(inst.model, inst) if door || fitted
        door || fitted
      end

      # ["height 2380mm (ceiling 2400)", "top door 500mm (setting 460)"] for
      # an "Up to ceiling" unit that doesn't match the job.
      def self.differences(inst, model = Sketchup.active_model)
        want = target_mm(inst, mm(model))
        return [] unless want
        out = []
        h = height_mm(inst)
        out << "height #{h.round}mm (ceiling #{want.round})" if h && (h - want).abs > 1
        td = top_door_of(inst)
        out << "top door #{td.round}mm (setting #{top_door_mm.round})" if td && top_door_mm.positive? && (td - top_door_mm).abs > 1
        out
      end

      # Ceiling height button: any time, scribes on or off. Runouts untouched.
      def self.show(model = Sketchup.active_model)
        units = Runouts.units(model.entities)
        data = { 'ceiling' => mm(model), 'count' => units.count { |u| target_mm(u, 1.0) }, 'top_door' => top_door_mm }
        dlg = Dialog.open('ceiling', title: 'HW - Ceiling height', key: 'hw_ceiling', width: 360, height: 230,
                                     data: data, resizable: false, scrollable: false)
        dlg.add_action_callback('apply') do |_c, value|
          ceil = value.to_f
          dlg.close
          next unless ceil.positive?
          Ops.run(model, 'Room ceiling') { Room.apply(model, ceiling: ceil) }
          Runouts.apply(model, units, nil, 'Ceiling height',
                        "Ceiling height #{ceil.round} mm (top doors #{top_door_mm.round} mm) applied to every 'Up to ceiling' unit.",
                        ceiling: ceil, before: -> { model.set_attribute(DICT, 'ceiling_mm', ceil) })
        end
        dlg.show
      end
    end
  end
end
