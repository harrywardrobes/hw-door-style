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

      def self.options_s
        '&' + OPTIONS.map { |l, v| "#{enc(l)}=#{v}" }.join('&') + '&'
      end

      def self.keys_of(dict)
        return nil unless dict
        t = dict.keys.find { |k| k =~ /\A[a-z]\d\d_topped\z/ }
        u = dict.keys.find { |k| k =~ /\A[a-z]\d\d_up_to_ceiling\z/ }
        t && u ? [t, u, t.sub('topped', 'top_of_unit')] : nil
      end

      def self.keys(inst)
        keys_of(inst.definition.attribute_dictionary(D))
      end

      def self.truthy?(v)
        !v.nil? && !%w[FALSE 0 NO].include?(v.to_s.strip.upcase) && !v.to_s.strip.empty?
      end

      # The setting from the old two (instance value first, then the definition's).
      def self.from_old(inst, tk, uk)
        defn = inst.respond_to?(:definition) ? inst.definition : nil
        read = ->(k) { inst.get_attribute(D, k, defn ? defn.get_attribute(D, k) : nil) }
        return NO_FACING if truthy?(read.call(tk))
        truthy?(read.call(uk)) ? SCRIBED : CUSTOM
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

      # Turns one definition over to the dropdown. Returns true if it changed.
      def self.upgrade_definition(defn)
        d = defn.attribute_dictionary(D)
        tk, uk, nk = keys_of(d)
        return false unless nk
        return false if defn.get_attribute(D, "_#{nk}_access") == 'LIST' && defn.get_attribute(D, "_#{tk}_access") == 'NONE'
        up = nk.upcase
        defn.set_attribute(D, nk, from_old(defn, tk, uk).to_s) if defn.get_attribute(D, nk).nil?
        { 'access' => 'LIST', 'formlabel' => LABEL, 'label' => up, 'options' => options_s, 'units' => 'STRING', 'formulaunits' => 'STRING' }.each do |m, v|
          defn.set_attribute(D, "_#{nk}_#{m}", v)
        end
        defn.set_attribute(D, "_#{tk}_formula", "IF(#{up}=#{NO_FACING}, 1, 0)")
        defn.set_attribute(D, "_#{tk}_access", 'NONE')
        defn.set_attribute(D, "_#{uk}_formula", %(IF(#{up}=#{SCRIBED}, "TRUE", "FALSE")))
        defn.set_attribute(D, "_#{uk}_access", 'NONE')
        # The height box: plain words (it's the unit's height whichever option is chosen).
        hk = d.keys.find { |k| k =~ /\A[a-z]\d\d_frame_height_ceiling\z/ }
        defn.set_attribute(D, "_#{hk}_formlabel", 'Height (mm)') if hk
        true
      end

      # Every unit in the model: definitions upgraded, each placed unit keeps its own setting.
      # Returns the number of units changed.
      def self.upgrade(model = Sketchup.active_model)
        ComponentFixes.apply(model) if defined?(ComponentFixes)
        todo = model.definitions.select { |dfn| (ks = keys_of(dfn.attribute_dictionary(D))) && dfn.get_attribute(D, "_#{ks[0]}_access") != 'NONE' }
        return 0 if todo.empty?
        n = 0
        Ops.run(model, 'Top of unit (upgrade)', transparent: true) do
          todo.each do |dfn|
            tk, uk, nk = keys_of(dfn.attribute_dictionary(D))
            dfn.instances.each do |inst|
              next unless inst.get_attribute(D, nk).nil?
              inst.set_attribute(D, nk, from_old(inst, tk, uk).to_s)
              n += 1
            end
            upgrade_definition(dfn)
          end
        end
        Log.info("Top of unit: #{todo.size} component(s), #{n} unit(s) upgraded") if n.positive? || todo.any?
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
