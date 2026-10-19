module HarryWardrobes
  module DoorStyle
    # Bottom facing (plinth) height for the job.
    #
    # Components keep it in their "facing_btm" option (d01_facing_btm), which is
    # hidden in Component Options: the job value is set in the pencil window for
    # every unit, or per unit from the right-click menu (like door styles).
    # Units are every outermost component that has the option - including the
    # internal drawers and shoe pull-out, which have no runouts.
    module Facing
      KEY = 'facing_btm'.freeze

      def self.default_mm
        Settings.get['facing_bottom_mm'].to_f
      end

      # This job's value (the Settings default until it is set in the pencil window).
      def self.mm(model = Sketchup.active_model)
        v = model.get_attribute(DICT, 'facing_btm_mm', nil)
        v.nil? ? default_mm : v.to_f
      end

      def self.has?(inst)
        inst.is_a?(Sketchup::ComponentInstance) && !DC.key(inst, KEY).nil?
      end

      def self.units(entities)
        found = []
        Runouts.each_unit(entities, method(:has?)) { |u| found << u }
        found
      end

      def self.selected(model = Sketchup.active_model)
        model.selection.grep(Sketchup::ComponentInstance).flat_map { |i| has?(i) ? [i] : units(i.definition.entities) }.uniq
      end

      def self.of(inst)
        k = DC.key(inst, KEY) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Sets the unit's bottom facing (text options stay text). True if it changed.
      def self.set(inst, mm)
        k = DC.key(inst, KEY) or return false
        cur = DC.read(inst, k)
        return false if cur && (cur.to_f * 25.4 - mm.to_f).abs < 0.05 && !inst.get_attribute(DC::DICT_NAME, k).nil?
        inst.set_attribute(DC::DICT_NAME, k, cur.is_a?(String) ? (mm.to_f / 25.4).to_s : mm.to_f / 25.4)
        true
      end

      # ["bottom facing 100mm (job 79)"] when the unit differs from the job.
      def self.differences(inst, model = Sketchup.active_model)
        v = of(inst) or return []
        job = mm(model)
        (v - job).abs > 0.3 ? ["bottom facing #{v.round}mm (job #{job.round})"] : []
      end
    end
  end
end
