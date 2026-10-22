module HarryWardrobes
  module DoorStyle
    # Drawer front height for the job - one value for every drawer unit (external fitted /
    # unfitted, internal drawers, internal drawers plus). Like the bottom facing:
    #
    # Components keep it in their "drwr_front_height" option (h05_drwr_front_height), hidden in
    # Component Options. The job value is set in the pencil window for every unit, or per unit
    # from the right-click menu; a unit that differs is flagged in the Summary. The drawer box
    # height follows it in the component (front - 78 mm).
    #
    # A unit whose front height is a formula (the linen press: from the mid-rail) isn't one of
    # these - the plugin never sets it.
    module DrawerFront
      KEY = 'drwr_front_height'.freeze
      DA = 'dynamic_attributes'.freeze

      def self.default_mm
        v = Settings.get['drawer_front_mm'].to_f
        v.positive? ? v : 228.0
      end

      # This job's value (the Settings default until it is set in the pencil window).
      def self.mm(model = Sketchup.active_model)
        v = model.get_attribute(DICT, 'drawer_front_mm', nil)
        v.nil? ? default_mm : v.to_f
      end

      def self.formula?(inst, k)
        [inst, inst.definition].any? { |o| !o.get_attribute(DA, "_#{k}_formula").to_s.strip.empty? }
      end

      def self.has?(inst)
        return false unless inst.is_a?(Sketchup::ComponentInstance)
        k = DC.key(inst, KEY)
        !k.nil? && !formula?(inst, k)
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

      # Sets the unit's drawer front height (text options stay text). True if it changed.
      def self.set(inst, mm)
        return false unless has?(inst) && mm.to_f.positive?
        k = DC.key(inst, KEY)
        cur = DC.read(inst, k)
        return false if cur && (cur.to_f * 25.4 - mm.to_f).abs < 0.05 && !inst.get_attribute(DA, k).nil?
        inst.set_attribute(DA, k, cur.is_a?(String) ? (mm.to_f / 25.4).to_s : mm.to_f / 25.4)
        true
      end

      # ["drawer fronts 250mm (job 228)"] when the unit differs from the job.
      def self.differences(inst, model = Sketchup.active_model)
        return [] unless has?(inst)
        v = of(inst) or return []
        job = mm(model)
        (v - job).abs > 0.3 ? ["drawer fronts #{v.round}mm (job #{job.round})"] : []
      end
    end
  end
end
