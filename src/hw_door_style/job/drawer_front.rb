module HarryWardrobes
  module DoorStyle
    # Drawer front heights for the job, like the bottom facing - two values:
    #
    #   main   drwr_front_height     every drawer unit (fitted / unfitted, internal drawers,
    #                                internal drawers plus); the box follows (front - 78 mm)
    #   small  drwr_front_sm_height  the small top drawers on internal drawers plus (box 100)
    #
    # Components keep them in hidden options (h05 / h08). The job values are set in Room settings
    # for every unit, or per unit from the right-click menu; a unit that differs is flagged in the
    # Summary. A front height that is a formula (the linen press: from its mid-rail) is never set.
    module DrawerFront
      KINDS = { 'main' => 'drwr_front_height', 'small' => 'drwr_front_sm_height' }.freeze
      MODEL = { 'main' => 'drawer_front_mm', 'small' => 'drawer_front_sm_mm' }.freeze
      FALLBACK = { 'main' => 228.0, 'small' => 142.0 }.freeze
      LABEL = { 'main' => 'drawer fronts', 'small' => 'small drawer fronts' }.freeze
      DA = 'dynamic_attributes'.freeze

      def self.default_mm(kind = 'main')
        v = Settings.get[MODEL[kind]].to_f
        v.positive? ? v : FALLBACK[kind]
      end

      # This job's value (the Settings default until it is set in Room settings).
      def self.mm(model = Sketchup.active_model, kind = 'main')
        v = model.get_attribute(DICT, MODEL[kind], nil)
        v.nil? ? default_mm(kind) : v.to_f
      end

      def self.job(model = Sketchup.active_model) = KINDS.keys.to_h { |k| [k, mm(model, k)] }

      def self.formula?(inst, k)
        [inst, inst.definition].any? { |o| !o.get_attribute(DA, "_#{k}_formula").to_s.strip.empty? }
      end

      def self.key(inst, kind)
        k = DC.key(inst, KINDS[kind])
        k && !formula?(inst, k) ? k : nil
      end

      # Has any settable drawer front height (or the given kind).
      def self.has?(inst, kind = nil)
        return false unless inst.is_a?(Sketchup::ComponentInstance)
        (kind ? [kind] : KINDS.keys).any? { |k| key(inst, k) }
      end

      def self.units(entities)
        found = []
        Runouts.each_unit(entities, method(:has?)) { |u| found << u }
        found
      end

      def self.selected(model = Sketchup.active_model)
        model.selection.grep(Sketchup::ComponentInstance).flat_map { |i| has?(i) ? [i] : units(i.definition.entities) }.uniq
      end

      def self.of(inst, kind = 'main')
        k = key(inst, kind) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Sets the unit's front heights: vals { 'main' => mm, 'small' => mm } (or one number = main).
      # True if anything changed; the caller redraws.
      def self.set(inst, vals)
        vals = { 'main' => vals } unless vals.is_a?(Hash)
        changed = false
        vals.each do |kind, mm|
          k = key(inst, kind) or next
          next unless mm.to_f.positive?
          cur = DC.read(inst, k)
          next if cur && (cur.to_f * 25.4 - mm.to_f).abs < 0.05 && !inst.get_attribute(DA, k).nil?
          inst.set_attribute(DA, k, cur.is_a?(String) ? (mm.to_f / 25.4).to_s : mm.to_f / 25.4)
          changed = true
        end
        changed
      end

      # ["drawer fronts 250mm (job 228)"] for each height that differs from the job.
      def self.differences(inst, model = Sketchup.active_model)
        KINDS.keys.filter_map do |kind|
          v = of(inst, kind) or next
          job = mm(model, kind)
          (v - job).abs > 0.3 ? "#{LABEL[kind]} #{v.round}mm (job #{job.round})" : nil
        end
      end
    end
  end
end
