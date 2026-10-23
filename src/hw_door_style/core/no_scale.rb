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

      # --- fixed-size parts (cable outlets) ---------------------------------------------
      #
      # A cable outlet is a bought-in 80 mm grommet: always its own size (the definition's
      # 88 x 88 x 20 mm rim), round, whatever the unit around it does. Every one placed in a
      # component has no scaling (only its position and turn) and Dynamic Component sizes
      # fixed to the definition's (_lenx/_leny/_lenz formulas), so a unit redrawing or
      # being stretched can't change it.
      FIXED = /\ACABLE_OUTLET/i.freeze

      def self.fixed?(defn) = DC.base_name(defn) =~ FIXED ? true : false

      def self.size_cm(defn)
        b = defn.bounds
        [b.width, b.height, b.depth].map { |v| (v * 2.54).round(2) }
      end

      def self.cm_s(v) = (v % 1).zero? ? v.to_i.to_s : v.to_s

      # Is a placed outlet scaled (stretched or squashed)?
      def self.scaled?(inst)
        t = inst.transformation
        [X_AXIS, Y_AXIS, Z_AXIS].any? { |a| ((t * a).length.to_f - 1.0).abs > 1e-4 }
      end

      def self.fixed_formulas?(inst)
        want = size_cm(inst.definition)
        %w[lenx leny lenz].each_with_index.all? do |k, i|
          f = inst.get_attribute(DICT_NAME, "_#{k}_formula").to_s.strip
          f.match?(/\A-?[\d.]+\z/) && (f.to_f - want[i]).abs < 0.01
        end
      end

      # [[placed outlet, parent definition name, ['stretched', 'size not fixed']]] under the library components.
      def self.outlet_issues(model)
        Unshare.nested(Unshare.tops(model)).filter_map do |e|
          next unless fixed?(e.definition)
          why = []
          why << 'stretched' if scaled?(e)
          why << 'size not fixed' unless fixed_formulas?(e)
          next if why.empty?
          [e, e.parent.respond_to?(:name) ? e.parent.name : '', why]
        end
      end

      # Inside the caller's step: each outlet back to its own size (scaling taken out, its
      # position and turn kept) with the size fixed by formula; the components holding them
      # redrawn. Returns the number fixed.
      def self.fix_outlets!(model)
        list = outlet_issues(model)
        return 0 if list.empty?
        list.each do |e, _p, _w|
          t = e.transformation
          e.transformation = Geom::Transformation.axes(t.origin, t.xaxis.normalize, t.yaxis.normalize, t.zaxis.normalize)
          size_cm(e.definition).zip(%w[lenx leny lenz]).each do |cm, k|
            e.set_attribute(DICT_NAME, "_#{k}_formula", cm_s(cm))
            e.set_attribute(DICT_NAME, k, (cm / 2.54).to_s)
          end
        end
        parents = list.map { |e, _p, _w| e.parent }.uniq
        model.entities.grep(Sketchup::ComponentInstance).each do |i|
          next unless Unshare.tops(model).include?(i.definition)
          inside = Unshare.nested([i.definition]).map(&:parent).uniq
          next unless (inside & parents).any? || parents.include?(i.definition)
          Drawers.close(i.definition.entities)
          DC.redraw(i)
        end
        list.size
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
