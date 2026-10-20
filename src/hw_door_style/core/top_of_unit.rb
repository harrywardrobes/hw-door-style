module HarryWardrobes
  module DoorStyle
    # "Top of unit" - the dropdown on every unit (key i04_top_of_unit):
    #
    #   1  Scribed To Ceiling                     job ceiling height, top facing scribed to the ceiling
    #   2  Custom Scribe Height (Lower Section)   its own height, top facing scribed (bulkhead / lower ceiling)
    #   3  No Upper Facing                        its own height, no top facing, no ceiling runout
    #
    # The component's formulas read it through two hidden derived values, ZZ_TOPPED (option 3)
    # and ZZ_UP_TO_CEILING (option 1).
    module TopOfUnit
      SCRIBED = 1
      CUSTOM = 2
      NO_FACING = 3
      OPTIONS = [['Scribed To Ceiling', SCRIBED], ['Custom Scribe Height (Lower Section)', CUSTOM], ['No Upper Facing', NO_FACING]].freeze
      KEY = 'i04_top_of_unit'.freeze
      D = 'dynamic_attributes'.freeze

      # 1 / 2 / 3, or nil when the component has no Top of unit dropdown.
      def self.choice(inst)
        defn = inst.respond_to?(:definition) ? inst.definition : inst
        v = inst.get_attribute(D, KEY, defn.get_attribute(D, KEY))
        v.nil? || v.to_s.strip.empty? ? nil : v.to_f.round
      end

      def self.label(choice)
        OPTIONS.find { |_l, v| v == choice }&.first
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
    end
  end
end
