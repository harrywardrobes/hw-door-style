module HarryWardrobes
  module DoorStyle
    # No library component is sized by stretching it with the Scale tool. Every size is a
    # typed option, so a unit always comes out of its options the same way (Replace with,
    # the pencil, the job's ceiling all set values - nothing has to be stretched to match).
    #
    #   scale handles   all hidden (Dynamic Components "ScaleTool" = 127)
    #   CURRENT(...)    a size worked out from the stretched size ("ROUND(CURRENT("LenZ"), 1)")
    #                   becomes a plain typed value (the size it has now), shown in Component
    #                   Options in mm
    #
    # The room parts (floor, ceiling, walls) are sized by the plugin and left as they are.
    # Library export: Clean model fixes any component, and an export isn't allowed until it's done.
    module NoScale
      DICT_NAME = 'dynamic_attributes'.freeze
      ALL_HIDDEN = '127'.freeze
      LABELS = { 'LENX' => 'Width (mm)', 'LENY' => 'Depth (mm)', 'LENZ' => 'Height (mm)' }.freeze

      def self.tops(model)
        Unshare.tops(model).reject { |d| Room.part?(d.instances.first) }
      rescue StandardError
        Unshare.tops(model)
      end

      # Keys whose value is worked out from the stretched size: { key => 'LENZ' ... }.
      def self.current_keys(defn)
        d = defn.attribute_dictionary(DICT_NAME) or return {}
        d.keys.filter_map do |k|
          md = k.match(/\A_(?!inst__)(.+)_formula\z/) or next
          axis = d[k].to_s.gsub('&quot;', '"')[/CURRENT\(\s*"(Len[XYZ])"/i, 1] or next
          [md[1], axis.upcase]
        end.to_h
      end

      def self.handles_shown?(inst)
        v = inst.get_attribute(DICT_NAME, 'scaletool') || inst.definition.get_attribute(DICT_NAME, 'scaletool')
        v.to_s.strip != ALL_HIDDEN
      end

      # Components that can still be stretched: [[definition, ['scale handles', 'height from its stretched size'...]]].
      def self.issues(model)
        tops(model).filter_map do |d|
          i = d.instances.find { |x| x.parent.is_a?(Sketchup::Model) } || d.instances.first
          next unless i
          why = []
          why << 'scale handles' if handles_shown?(i)
          current_keys(d).each_value { |ax| why << "#{LABELS[ax].sub(' (mm)', '').downcase} from its stretched size" }
          why.empty? ? nil : [d, why.uniq]
        end
      end

      # Inside the caller's step. Returns the names fixed.
      def self.fix!(model)
        fixed = []
        issues(model).each do |d, _why|
          insts = d.instances.select { |x| x.parent.is_a?(Sketchup::Model) }
          dd = d.attribute_dictionary(DICT_NAME)
          ([d] + insts).each { |o| o.set_attribute(DICT_NAME, 'scaletool', ALL_HIDDEN) }
          current_keys(d).each do |k, axis|
            units = dd["_#{k}_units"].to_s.upcase
            per = insts.first ? Ceiling.mm_per(insts.first, k) : 25.4
            # the value it has now, then no formula: a typed size
            ([d] + insts).each do |o|
              ["_#{k}_formula", "_inst__#{k}_formula"].each { |f| o.attribute_dictionary(DICT_NAME)&.delete_key(f) }
              next unless (v = o.get_attribute(DICT_NAME, k))
              # a size kept in the model's own units (no units set) is put in inches, shown in mm
              o.set_attribute(DICT_NAME, k, (v.to_f * per / 25.4).to_s) if units.empty? || units == 'DEFAULT'
            end
            d.set_attribute(DICT_NAME, "_#{k}_units", 'MILLIMETERS') if units.empty? || units == 'DEFAULT'
            d.set_attribute(DICT_NAME, "_#{k}_formulaunits", 'CENTIMETERS') if dd["_#{k}_formulaunits"].to_s.empty?
            d.set_attribute(DICT_NAME, "_#{k}_label", k.upcase) if dd["_#{k}_label"].to_s.empty?
            if %w[NONE VIEW].include?(dd["_#{k}_access"].to_s.upcase) || dd["_#{k}_access"].to_s.empty?
              d.set_attribute(DICT_NAME, "_#{k}_access", 'TEXTBOX')
              d.set_attribute(DICT_NAME, "_#{k}_formlabel", LABELS[axis]) if dd["_#{k}_formlabel"].to_s.empty? || dd["_#{k}_formlabel"].to_s == dd["_#{k}_formlabel"].to_s.upcase
            end
          end
          insts.each do |i|
            Drawers.close(i.definition.entities)
            DC.redraw(i)
          end
          fixed << d.name
        end
        fixed
      end
    end
  end
end
