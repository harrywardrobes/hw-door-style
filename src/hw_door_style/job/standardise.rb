module HarryWardrobes
  module DoorStyle
    # One-off update for models made before the runout options were tidied:
    # SCRIBE_L / SCRIBE_R become RUNOUT_L / RUNOUT_R (keys and every formula
    # that mentions them) and every runout dropdown gets the Settings list.
    # Offered automatically (Standardise.ready?) before the pencil or ceiling
    # windows open on such a model.
    module Standardise
      OLD_KEYS = { 'scribe_l' => 'runout_l', 'scribe_r' => 'runout_r' }.freeze

      # "scribe_l" / "_scribe_l_label" / "_inst__scribe_l_formula" -> runout_l versions.
      def self.rename_key(k)
        OLD_KEYS.each do |old, new|
          nk = k.sub(/\A(_?(?:inst__)?)#{old}(?=_|\z)/, "\\1#{new}")
          return nk unless nk == k
        end
        k
      end

      # SCRIBE_L / parent!SCRIBE_R -> RUNOUT_L / parent!RUNOUT_R (ZZ_SCRIBE_L is left alone).
      def self.rename_formula(v)
        v.gsub(/\bSCRIBE_([LR])\b/i) { "RUNOUT_#{Regexp.last_match(1).upcase}" }
      end

      # DC dropdown: "&0mm=0.0&25mm=0.98...&"
      def self.options_string
        (['0mm=0.0'] + Runouts.values_list.map { |v| "#{v.round}mm=#{Runouts.inch_s(v)}" }).map { |o| "&#{o}" }.join + '&'
      end

      def self.needed?(model)
        model.definitions.any? do |d|
          dd = DC.dict(d) or next false
          fk = DC.key_in(dd, 'runout_floor')
          dd.keys.any? { |k| k =~ /\A_?scribe_[lr](_|\z)/ } ||
            (fk && dd["_#{fk}_options"] != options_string)
        end
      end

      # Call inside an operation. Returns { renamed:, formulas:, options: }.
      def self.run(model)
        rep = { renamed: [], formulas: 0, options: 0 }
        objs = model.definitions.reject(&:image?).flat_map { |d| [d] + d.instances }
        objs.each do |o|
          dd = DC.dict(o) or next
          # 1. keys
          dd.keys.each do |k|
            nk = rename_key(k)
            next if nk == k
            val = dd[k]
            val = val.sub(/\ASCRIBE_([LR])\z/i) { "RUNOUT_#{Regexp.last_match(1).upcase}" } if k.end_with?('_label') && val.is_a?(String)
            dd[nk] = val if dd[nk].nil?
            dd.delete_key(k)
            rep[:renamed] |= [o.respond_to?(:definition) ? o.definition.name : o.name]
          end
          %w[_scribe_1_label_formlabel _scribe_1_label_formula _scribe_1_label_label _scribe_1_label_units scribe_1_label].each { |k| dd.delete_key(k) if dd[k] }
          # 2. formulas
          dd.keys.each do |k|
            v = dd[k]
            next unless k.end_with?('_formula') && v.is_a?(String) && v =~ /\bSCRIBE_[LR]\b/i
            dd[k] = rename_formula(v)
            rep[:formulas] += 1
          end
          # 3. dropdowns + labels
          Runouts::SIDES.each do |_s, base, label|
            key = DC.key_in(dd, base) || base
            next if dd[key].nil? && dd["_#{key}_label"].nil?
            dd["_#{key}_options"] = options_string
            dd["_#{key}_formlabel"] = label
            dd["_#{key}_units"] = 'STRING'
            rep[:options] += 1
          end
        end
        rep
      end

      # True when the model is ready (or was just updated with the user's OK).
      def self.ready?(model)
        return true unless needed?(model)
        msg = "This model's components need a one-off update first:\n\n" \
              "- SCRIBE_L / SCRIBE_R renamed RUNOUT_L / RUNOUT_R (formulas updated)\n" \
              "- runout dropdowns set to 0 / #{Runouts.values_list.map(&:round).join(' / ')} mm\n\nDo it now? (one undo step)"
        return false unless UI.messagebox(msg, MB_YESNO) == IDYES
        Ops.run(model, 'Standardise runouts') { run(model) }
        true
      end
    end
  end
end
