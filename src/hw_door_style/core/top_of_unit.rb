module HarryWardrobes
  module DoorStyle
    # "Top of unit" - one dropdown in place of the two switches that used to sit side by side
    # ("Topped off?" and "Up to ceiling"), which sounded the same but did different things:
    #
    #   1  Scribed To Ceiling                     job ceiling height, top facing scribed to the ceiling
    #   2  Custom Scribe Height (Lower Section)   its own height, top facing scribed (bulkhead / lower ceiling)
    #   3  No Upper Facing                        its own height, no top facing, no ceiling runout
    #
    # The old two stay in the component (its formulas use them) but are hidden and follow the
    # dropdown. Units are upgraded when a file is opened (their setting kept), so older job files
    # and the library pick it up; Export components then carries it into the library files.
    module TopOfUnit
      SCRIBED = 1
      CUSTOM = 2
      NO_FACING = 3
      OPTIONS = [['Scribed To Ceiling', SCRIBED], ['Custom Scribe Height (Lower Section)', CUSTOM], ['No Upper Facing', NO_FACING]].freeze
      LABEL = 'Top of unit'.freeze
      D = 'dynamic_attributes'.freeze

      def self.enc(s)
        s.gsub(/[^A-Za-z0-9]/) { |c| format('%%%02X', c.ord) }
      end

      # The options a component can offer: Scribed To Ceiling needs its "Up to ceiling"
      # switch, No Upper Facing its "Topped off?" switch (a unit with only one of them gets two).
      def self.choices(tk, uk)
        OPTIONS.select { |_l, v| (v != SCRIBED || uk) && (v != NO_FACING || tk) }
      end

      def self.options_s(list = OPTIONS)
        '&' + list.map { |l, v| "#{enc(l)}=#{v}" }.join('&') + '&'
      end

      TOPPED_RE = /\A(?:[a-z]\d\d_)?topped(?:_off)?\z/.freeze
      UP_RE = /\A(?:[a-z]\d\d_)?up_to_ceiling\z/.freeze

      # [topped key or nil, up to ceiling key or nil, dropdown key], or nil if the
      # component has neither switch. The dropdown sits where the old switch was
      # (same section prefix).
      def self.keys_of(dict)
        return nil unless dict
        ks = dict.keys
        t = ks.find { |k| k =~ TOPPED_RE }
        u = ks.find { |k| k =~ UP_RE }
        return nil unless t || u
        n = t ? t.sub(/topped(?:_off)?\z/, 'top_of_unit') : u.sub(/up_to_ceiling\z/, 'top_of_unit')
        [t, u, n]
      end

      def self.keys(inst)
        keys_of(inst.definition.attribute_dictionary(D))
      end

      def self.truthy?(v)
        !v.nil? && !%w[FALSE 0 NO].include?(v.to_s.strip.upcase) && !v.to_s.strip.empty?
      end

      # The setting from the old switches (instance value first, then the definition's).
      def self.from_old(inst, tk, uk)
        defn = inst.respond_to?(:definition) ? inst.definition : nil
        read = ->(k) { k && inst.get_attribute(D, k, defn ? defn.get_attribute(D, k) : nil) }
        return NO_FACING if tk && truthy?(read.call(tk))
        uk && truthy?(read.call(uk)) ? SCRIBED : CUSTOM
      end

      # 1 / 2 / 3, or nil if the unit has neither switch.
      def self.choice(inst)
        ks = keys(inst) or return nil
        v = inst.get_attribute(D, ks[2], inst.definition.get_attribute(D, ks[2]))
        v.nil? || v.to_s.strip.empty? ? from_old(inst, ks[0], ks[1]) : v.to_f.round
      end

      def self.label(choice)
        OPTIONS.find { |_l, v| v == choice }&.first
      end

      SHOWN = %w[LIST TEXTBOX].freeze

      # An old switch still showing in Component Options (parts inside a unit carry
      # hidden copies that follow the unit - those are left alone).
      def self.shown?(defn, k)
        k && SHOWN.include?(defn.get_attribute(D, "_#{k}_access").to_s.upcase)
      end

      # What still needs doing on a definition: the old switches showing (on the definition,
      # or on a placed copy - DC keeps per-copy "_access" overrides that win over the
      # definition's), or an already-made dropdown whose old switches lost their formulas.
      def self.needs_upgrade?(defn)
        tk, uk, nk = keys_of(defn.attribute_dictionary(D))
        return false unless nk
        olds = [tk, uk].compact
        return true if olds.any? { |k| shown?(defn, k) }
        made = defn.get_attribute(D, "_#{nk}_access") == 'LIST'
        return false unless made
        return true if olds.any? { |k| defn.get_attribute(D, "_#{k}_formula").to_s.strip.empty? }
        defn.instances.any? { |i| olds.any? { |k| shown?(i, k) } }
      end

      # Turns one definition (and its placed copies) over to the dropdown. True if it changed.
      def self.upgrade_definition(defn)
        return false unless needs_upgrade?(defn)
        d = defn.attribute_dictionary(D)
        tk, uk, nk = keys_of(d)
        up = nk.upcase
        # Old switches that lost their formulas still decide how the unit is drawn, so
        # the dropdown is set from them (it may have drifted) before they follow it again.
        relink = [tk, uk].compact.any? { |k| defn.get_attribute(D, "_#{k}_formula").to_s.strip.empty? }
        # each placed copy keeps its own setting
        defn.instances.each do |inst|
          inst.set_attribute(D, nk, from_old(inst, tk, uk).to_s) if relink || inst.get_attribute(D, nk).nil?
          [tk, uk].compact.each { |k| inst.set_attribute(D, "_#{k}_access", 'NONE') if shown?(inst, k) }
        end
        defn.set_attribute(D, nk, from_old(defn, tk, uk).to_s) if relink || defn.get_attribute(D, nk).nil?
        { 'access' => 'LIST', 'formlabel' => LABEL, 'label' => up, 'options' => options_s(choices(tk, uk)), 'units' => 'STRING', 'formulaunits' => 'STRING' }.each do |m, v|
          defn.set_attribute(D, "_#{nk}_#{m}", v)
        end
        if tk
          defn.set_attribute(D, "_#{tk}_formula", "IF(#{up}=#{NO_FACING}, 1, 0)")
          defn.set_attribute(D, "_#{tk}_access", 'NONE')
        end
        if uk
          defn.set_attribute(D, "_#{uk}_formula", %(IF(#{up}=#{SCRIBED}, "TRUE", "FALSE")))
          defn.set_attribute(D, "_#{uk}_access", 'NONE')
        end
        # The height box: plain words (it's the unit's height whichever option is chosen).
        hk = d.keys.find { |k| k =~ /\A[a-z]\d\d_frame_height_ceiling\z/ }
        defn.set_attribute(D, "_#{hk}_formlabel", 'Height (mm)') if hk
        true
      end

      # Every unit in the model: definitions upgraded, each placed unit keeps its own setting.
      # Returns the number of units changed.
      def self.upgrade(model = Sketchup.active_model)
        ComponentFixes.apply(model) if defined?(ComponentFixes)
        todo = model.definitions.reject(&:image?).select { |dfn| needs_upgrade?(dfn) }
        return 0 if todo.empty?
        n = 0
        Ops.run(model, 'Top of unit (upgrade)', transparent: true) do
          todo.each { |dfn| n += 1 if upgrade_definition(dfn) }
        end
        Log.info("Top of unit: #{n} component(s) upgraded")
        n
      rescue StandardError => e
        Log.error('top of unit upgrade', e)
        0
      end

      # Units with their own height (options 2 and 3) among units, for the Scribe window.
      def self.own_height(units)
        units.filter_map do |u|
          c = choice(u)
          next unless c && c != SCRIBED
          h = Ceiling.height_mm(u) or next
          { 'id' => u.entityID, 'name' => Finder.label(u), 'top' => label(c), 'height' => h.round }
        end
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onOpenModel(model); UI.start_timer(0.5, false) { TopOfUnit.upgrade(model) if model.valid? }; end
        def onNewModel(model); end
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
        UI.start_timer(0.5, false) { upgrade(Sketchup.active_model) if Sketchup.active_model }
      end
    end
  end
end
