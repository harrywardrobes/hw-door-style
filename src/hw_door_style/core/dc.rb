module HarryWardrobes
  module DoorStyle
    # Small helpers for Dynamic Component attributes.
    #
    # DC attributes live in the 'dynamic_attributes' dictionary on both the
    # instance and the definition (instance values win). Lengths are stored in
    # inches; formulas are read in the component's _lengthunits (CENTIMETERS).
    module DC
      DICT_NAME = 'dynamic_attributes'.freeze
      LEN_KEY = /\A_?(inst__)?len[xyz](_|\z)/.freeze
      LEN_FORMULA = /\A_(inst__)?len[xyz]_formula\z/.freeze

      # DC compares stored values; a SketchUp Length breaks those comparisons, so
      # every number goes in as a plain Float.
      def self.plain(v)
        v.is_a?(Length) || v.is_a?(Integer) ? v.to_f : v
      end

      # A definition's part name without the copy number: "SHELF_MID#2" -> "SHELF_MID".
      # SketchUp drops trailing digits when it names a copy ("CABLE_OUTLET_80" ->
      # "CABLE_OUTLET_#2"); the Dynamic Component keeps the real name in _name, so that's used.
      def self.base_name(defn)
        n = defn.name.to_s
        return n.strip unless n =~ /#\d+\z/
        b = n.sub(/#\d+\z/, '').strip
        dn = (defn.respond_to?(:get_attribute) ? defn.get_attribute(DICT_NAME, '_name') : nil).to_s.strip
        dn.length > b.length && dn.upcase.start_with?(b.upcase) ? dn : b
      end

      def self.dict(obj)
        obj.attribute_dictionary(DICT_NAME)
      end

      def self.get(obj, key)
        d = dict(obj)
        d && d[key]
      end

      # Component Options are ordered by attribute name, so the library prefixes
      # them with a section code ("j01_runout_floor"). Find the real key for a
      # base name in one dictionary (exact name first, then any prefix).
      def self.key_in(dd, base)
        return nil unless dd
        return base unless dd[base].nil?
        dd.keys.find { |k| k =~ /\A[a-z]\d{1,2}_#{Regexp.escape(base)}\z/ }
      end

      # Real key for base on an instance (instance first, then its definition).
      def self.key(inst, base)
        key_in(dict(inst), base) || (inst.respond_to?(:definition) ? key_in(dict(inst.definition), base) : nil)
      end

      # Reading values - the one way to do it:
      #   DC.read(inst, 'j01_runout_floor')  exact key
      #   DC.value(inst, 'runout_floor')     base name, finds any section prefix
      # Both look on the instance first, then its definition (an empty
      # instance value counts as not set). nil = the component hasn't got it.
      def self.read(inst, key)
        v = get(inst, key)
        v = get(inst.definition, key) if (v.nil? || v.to_s.empty?) && inst.respond_to?(:definition)
        v
      end

      def self.value(inst, base)
        k = key(inst, base) or return nil
        read(inst, k)
      end

      # Sets an option on the instance by base name, under its real (prefixed)
      # key. Returns the key used, or nil if the component hasn't got it.
      def self.set_value(inst, base, v)
        k = key(inst, base) or return nil
        inst.set_attribute(DICT_NAME, k, plain(v))
        k
      end

      # The formula behind a key (instance first, then definition), or ''.
      def self.formula_of(inst, key)
        f = get(inst, "_#{key}_formula")
        f = get(inst.definition, "_#{key}_formula") if f.to_s.strip.empty? && inst.respond_to?(:definition)
        f.to_s
      end

      def self.set(objs, key, value)
        Array(objs).each { |o| o.set_attribute(DICT_NAME, key, plain(value)) }
      end

      # Hidden length attribute (MILLIMETERS shown, CENTIMETERS formula).
      def self.length_attr(objs, name, formula, value_in)
        attr(objs, name, formula, value_in, units: 'MILLIMETERS', formulaunits: 'CENTIMETERS')
      end

      # Hidden plain-number attribute.
      def self.number_attr(objs, name, formula, value)
        attr(objs, name, formula, value.to_f, units: 'FLOAT', formulaunits: 'FLOAT')
      end

      # Hidden text attribute.
      def self.string_attr(objs, name, value)
        attr(objs, name, nil, value.to_s, units: 'STRING', formulaunits: 'STRING')
      end

      def self.attr(objs, name, formula, value, units:, formulaunits:, access: 'NONE')
        key = name.downcase
        Array(objs).each do |o|
          o.set_attribute(DICT_NAME, key, plain(value)) unless value.nil?
          o.set_attribute(DICT_NAME, "_#{key}_label", name.upcase)
          o.set_attribute(DICT_NAME, "_#{key}_access", access)
          o.set_attribute(DICT_NAME, "_#{key}_units", units)
          o.set_attribute(DICT_NAME, "_#{key}_formulaunits", formulaunits)
          if formula && !formula.to_s.strip.empty?
            o.set_attribute(DICT_NAME, "_#{key}_formula", formula.to_s.strip)
          else
            d = dict(o)
            d.delete_key("_#{key}_formula") if d && d["_#{key}_formula"]
          end
        end
      end

      # Position/size formulas on a child (x/y/z/lenx/leny/lenz), with current values.
      def self.formula(objs, key, formula, value_in = nil)
        Array(objs).each do |o|
          o.set_attribute(DICT_NAME, "_#{key}_formula", formula)
          o.set_attribute(DICT_NAME, key, plain(value_in)) unless value_in.nil?
        end
      end

      def self.len_keys(obj)
        d = dict(obj)
        d ? d.keys.grep(LEN_KEY) : []
      end

      # Len FORMULAS (the thing that makes DC scale a wrapper). Plain lenx/leny/lenz
      # values are written back by DC on every redraw and are harmless.
      def self.len_formulas(obj)
        d = dict(obj)
        d ? d.keys.grep(LEN_FORMULA).reject { |k| d[k].to_s.strip.empty? } : []
      end

      def self.remove_len!(obj)
        d = dict(obj) or return 0
        keys = d.keys.grep(LEN_KEY)
        keys.each { |k| d.delete_key(k) }
        keys.size
      end

      # Marks a definition/instance as a DC child with a name.
      def self.child(objs, name)
        Array(objs).each do |o|
          o.set_attribute(DICT_NAME, '_name', name)
          o.set_attribute(DICT_NAME, '_lengthunits', 'CENTIMETERS')
          o.set_attribute(DICT_NAME, '_formatversion', 1.0)
        end
      end

      def self.cm(len_in)
        format('%.4f', len_in.to_f * 2.54).sub(/\.?0+\z/, '')
      end

      # Redraws a top-level DC through the Dynamic Components engine (no own undo step).
      # The DC progress bar keeps a start time that is only set once DC has shown
      # it at least once; on a fresh SketchUp a plain redraw(inst) can fail with
      # "can't convert NilClass into an exact number". So: no DC progress bar
      # (we show our own), and fall back to the other entry points.
      def self.redraw(inst)
        klass = defined?($dc_observers) && $dc_observers ? $dc_observers.get_latest_class : nil
        return false unless klass
        attempts = []
        attempts << -> { klass.redraw(inst, false) } if klass.respond_to?(:redraw) && klass.method(:redraw).arity != 1
        attempts << -> { klass.redraw(inst) } if klass.respond_to?(:redraw)
        attempts << -> { klass.redraw_with_undo(inst) } if klass.respond_to?(:redraw_with_undo)
        last = nil
        attempts.each do |a|
          begin
            a.call
            return true
          rescue TypeError, ArgumentError, NoMethodError => e
            last = e
          end
        end
        raise last if last
        false
      end
    end
  end
end
