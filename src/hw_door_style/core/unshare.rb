module HarryWardrobes
  module DoorStyle
    # No nested part is shared between two different library components.
    #
    # Dynamic Components keep some results on the part's definition (a hidden flag, sizes),
    # so a part used in two components can be changed by the other one: the stable wardrobe's
    # top shelf hid itself because the wardrobe's top shelf (same part) was hidden, and the
    # worktop's battens because the unfitted drawer's were. So every component gets its own
    # copy of every part inside it - copies keep the part's name with "#n" (the plugin reads
    # the name without it).
    #
    # The one exception is plain bought-in hardware with no rules at all: no formulas on the
    # part or anything inside it, and every place it's used carries the same formulas of its
    # own (hinges, drawer boxes, cable outlets). Nothing about it is worked out, so there is
    # nothing for one component to change for another.
    #
    # Library export: Clean model makes the copies, and an export isn't allowed while any part
    # is still shared.
    module Unshare
      DICT_NAME = 'dynamic_attributes'.freeze

      def self.formula_keys(dict)
        return [] unless dict
        dict.keys.select { |k| k.end_with?('_formula') && !dict[k].to_s.strip.empty? }
      end

      # Formulas the definition keeps for itself (not the ones it gives its instances).
      def self.own_rules?(defn)
        formula_keys(defn.attribute_dictionary(DICT_NAME)).any? { |k| !k.start_with?('_inst__') }
      end

      # Rules on the definition or anything inside it.
      def self.rules_inside?(defn, memo = {})
        return memo[defn] unless memo[defn].nil?
        memo[defn] = false
        memo[defn] = own_rules?(defn) || defn.entities.any? { |e| e.respond_to?(:definition) && rules_inside?(e.definition, memo) }
      end

      # Can it stay shared: no rules of its own or inside, and every instance places it with
      # the same formulas.
      def self.plain_hardware?(defn, memo = {})
        return false if rules_inside?(defn, memo)
        sets = defn.instances.map { |i| formula_keys(i.attribute_dictionary(DICT_NAME)).sort }.uniq
        sets.size <= 1
      end

      # The library components: top-level dynamic components, by name.
      def self.tops(model)
        model.entities.grep(Sketchup::ComponentInstance).select { |i| i.definition.attribute_dictionary(DICT_NAME) }
                      .map(&:definition).uniq.sort_by(&:name)
      end

      # { nested definition => [top-level definitions it's in] }
      def self.owners(model, top_defs = tops(model))
        out = Hash.new { |h, k| h[k] = [] }
        top_defs.each do |td|
          seen = {}
          stack = [td]
          until stack.empty?
            d = stack.pop
            d.entities.each do |e|
              next unless e.respond_to?(:definition)
              cd = e.definition
              next if seen[cd]
              seen[cd] = true
              out[cd] << td
              stack << cd
            end
          end
        end
        out
      end

      # Nested parts in two or more components that must get their own copies: [definition].
      def self.shared(model)
        memo = {}
        owners(model).select { |d, o| o.uniq.size > 1 && !plain_hardware?(d, memo) }.keys.sort_by(&:name)
      end

      # Every nested instance under the components (each definition looked in once).
      def self.nested(top_defs)
        out = []
        seen = {}
        stack = top_defs.dup
        until stack.empty?
          d = stack.pop
          next if seen[d]
          seen[d] = true
          d.entities.grep(Sketchup::ComponentInstance).each { |e| out << e; stack << e.definition }
        end
        out
      end

      # SketchUp names a copy of "CABLE_OUTLET_80" "CABLE_OUTLET_#2" (it drops trailing
      # digits): the copy is named "<part>#n" instead, so it reads as the same part.
      def self.name_copy(model, copy, original)
        base = DC.base_name(original)
        return if DC.base_name(copy) == base
        n = 1
        n += 1 while model.definitions["#{base}##{n}"]
        copy.name = "#{base}##{n}"
      end

      def self.hide_rule?(inst)
        [inst.get_attribute(DICT_NAME, '_hidden_formula'), inst.definition.get_attribute(DICT_NAME, '_hidden_formula'),
         inst.definition.get_attribute(DICT_NAME, '_inst__hidden_formula')].any? { |f| !f.to_s.strip.empty? }
      end

      # Inside the caller's step: the first component (by name) keeps each shared part, every
      # other one gets its own copy (one per component, shared by its own uses). A part with no
      # hide rule keeps the visibility it had in its component (the copy's stored hidden flag
      # set to match - a flag left by another component is what hid them). Then every
      # component is redrawn. Returns { copies:, parts: [names], mixed: [names] }.
      def self.fix!(model)
        top_defs = tops(model)
        own = owners(model, top_defs)
        todo = shared(model)
        return { copies: 0, parts: [], mixed: [] } if todo.empty?
        state = nested(top_defs).reject { |e| hide_rule?(e) }.to_h { |e| [e, e.hidden?] }
        copies = 0
        top_defs.each do |td|
          map = {}
          walk = lambda do |d|
            d.entities.to_a.each do |e|
              next unless e.is_a?(Sketchup::ComponentInstance)
              cd = e.definition
              if todo.include?(cd) && own[cd].uniq.first != td
                if map[cd]
                  e.definition = map[cd]
                else
                  e.make_unique
                  name_copy(model, e.definition, cd)
                  map[cd] = e.definition
                  copies += 1
                end
                cd = e.definition
              end
              walk.call(cd)
            end
          end
          walk.call(td)
        end
        mixed = []
        state.select { |e, _| e.valid? }.group_by { |e, _| e.definition }.each do |d, list|
          vals = list.map(&:last).uniq
          next mixed << d.name if vals.size > 1
          d.set_attribute(DICT_NAME, 'hidden', vals[0] ? 1.0 : 0.0)
        end
        model.entities.grep(Sketchup::ComponentInstance).select { |i| top_defs.include?(i.definition) }.each do |i|
          Drawers.close(i.definition.entities)
          DC.redraw(i)
        end
        { copies: copies, parts: todo.map(&:name), mixed: mixed }
      end
    end
  end
end
