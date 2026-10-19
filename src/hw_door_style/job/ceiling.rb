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
      HEIGHT_KEYS = %w[frame_height_ceiling frame_height ceiling_height size_height height].freeze

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

      # Only units that have the switch.
      def self.up_to_ceiling?(inst)
        c = TopOfUnit.choice(inst) if defined?(TopOfUnit)
        return c == TopOfUnit::SCRIBED unless c.nil?
        v = DC.value(inst, 'up_to_ceiling')
        !v.nil? && v.to_s.upcase != 'FALSE'
      end

      def self.height_mm(inst)
        k = height_key(inst) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Target height for this unit (nil = leave it). A BRIDGE_FRAME from before
      # 0.14 still has "Height below bridge": its height is the ceiling minus that.
      def self.target_mm(inst, ceiling)
        return nil unless ceiling.to_f.positive? && height_key(inst) && up_to_ceiling?(inst)
        below = DC.value(inst, 'height_below')
        return ceiling.to_f unless below
        b = below.to_f * 25.4
        b.positive? ? ceiling.to_f - b : nil
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
          inst.set_attribute(DC::DICT_NAME, k, old.is_a?(String) ? (mm / 25.4).to_s : mm / 25.4)
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
        return unless Standardise.ready?(model)
        units = Runouts.units(model.entities)
        data = { 'ceiling' => mm(model), 'count' => units.count { |u| target_mm(u, 1.0) }, 'top_door' => top_door_mm }
        dlg = Dialog.open('ceiling', title: 'HW - Ceiling height', key: 'hw_ceiling', width: 360, height: 230,
                                     data: data, resizable: false, scrollable: false)
        dlg.add_action_callback('apply') do |_c, value|
          ceil = value.to_f
          dlg.close
          next unless ceil.positive?
          Runouts.apply(model, units, nil, 'Ceiling height',
                        "Ceiling height #{ceil.round} mm (top doors #{top_door_mm.round} mm) applied to every 'Up to ceiling' unit.",
                        ceiling: ceil, before: -> { model.set_attribute(DICT, 'ceiling_mm', ceil) })
        end
        dlg.show
      end
    end
  end
end
