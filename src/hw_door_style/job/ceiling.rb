module HarryWardrobes
  module DoorStyle
    # Ceiling height for the job (ceiling button, and the pencil window).
    #
    # Every unit with "Up to ceiling" = TRUE is built to the job's ceiling
    # height; units without that option are never touched (drawers, boxes...).
    # Runouts add on top. Scribes off never changes the height.
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
        v = DC.value(inst, 'up_to_ceiling')
        !v.nil? && v.to_s.upcase != 'FALSE'
      end

      def self.height_mm(inst)
        k = height_key(inst) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Target height for this unit (nil = leave it). BRIDGE_FRAME sits on
      # something: its height is the ceiling minus "Height below bridge".
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

      # ["height 2380mm (ceiling 2400)"] when the unit isn't at the ceiling.
      def self.differences(inst, model = Sketchup.active_model)
        want = target_mm(inst, mm(model))
        h = height_mm(inst)
        want && h && (h - want).abs > 1 ? ["height #{h.round}mm (ceiling #{want.round})"] : []
      end

      # Ceiling height button: any time, scribes on or off. Runouts untouched.
      def self.show(model = Sketchup.active_model)
        return unless Standardise.ready?(model)
        units = Runouts.units(model.entities)
        data = { 'ceiling' => mm(model), 'count' => units.count { |u| target_mm(u, 1.0) } }
        dlg = Dialog.open('ceiling', title: 'HW - Ceiling height', key: 'hw_ceiling', width: 360, height: 230,
                                     data: data, resizable: false, scrollable: false)
        dlg.add_action_callback('apply') do |_c, value|
          ceil = value.to_f
          dlg.close
          next unless ceil.positive?
          Runouts.apply(model, units, nil, 'Ceiling height', "Ceiling height #{ceil.round} mm applied to every 'Up to ceiling' unit.",
                        ceiling: ceil, before: -> { model.set_attribute(DICT, 'ceiling_mm', ceil) })
        end
        dlg.show
      end
    end
  end
end
