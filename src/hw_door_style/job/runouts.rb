require 'json'

module HarryWardrobes
  module DoorStyle
    # Runouts (scribes) on every unit in the model.
    #
    #   Scribes ON  : every unit gets the job's floor / ceiling / left / right /
    #                 back runout (the pencil window, see Pencil).
    #   Scribes OFF : every runout 0, so units line up and move easily.
    #
    # The plugin only sets the values. Each component's own switches decide
    # what is used: WALL_LEFT / WALL_RIGHT / WALL_BACK, TOPPED (no ceiling
    # runout); the floor runout always applies.
    #
    # A "unit" is the outermost component that has runout options. Parts inside
    # it follow through parent! formulas and are never touched.
    #
    # Values are DC string options in inches (e.g. "0.984251968503937" = 25mm),
    # with a dropdown of Settings "runout_values_mm" plus 0.
    module Runouts
      SIDES = [
        ['floor',   'runout_floor',     'Runout - floor (mm)'],
        ['ceiling', 'runout_ceiling',   'Runout - ceiling (mm)'],
        ['left',    'runout_l',         'Runout - left (mm)'],
        ['right',   'runout_r',         'Runout - right (mm)'],
        ['back',    'runout_back_wall', 'Runout - back wall (mm)']
      ].freeze
      KEYS = SIDES.to_h { |s, k, _| [s, k] }.freeze
      ZERO = SIDES.to_h { |s, _, _| [s, 0.0] }.freeze
      TOL = 0.3 # mm

      # Any runout key, with or without a section prefix (j01_runout_floor).
      UNIT_KEY = /\A(?:[a-z]\d{1,2}_)?(?:#{KEYS.values.map { |k| Regexp.escape(k) }.join('|')})\z/.freeze

      # --- settings / job values -------------------------------------------

      def self.values_list
        Array(Settings.get['runout_values_mm']).map(&:to_f).select(&:positive?).uniq.sort
      end

      def self.defaults
        d = Settings.get['runout_defaults_mm'] || {}
        SIDES.to_h { |s, _, _| [s, (d[s] || 25).to_f] }
      end

      # Last values used on this job (mm), else the Settings defaults.
      def self.job_values(model = Sketchup.active_model)
        saved = JSON.parse(model.get_attribute(DICT, 'scribe_values', '{}')) rescue {}
        defaults.merge(saved.transform_values(&:to_f).slice(*KEYS.keys))
      end

      # What every unit should have right now (all 0 when scribes are off).
      def self.expected(model = Sketchup.active_model)
        Pencil.on?(model) ? job_values(model) : ZERO
      end

      # --- finding units ---------------------------------------------------

      # One pass over each attribute list (a key-by-key lookup re-scanned the
      # list five times per part, which made the pencil check slow).
      def self.unit?(inst)
        return false unless inst.is_a?(Sketchup::ComponentInstance)
        [inst.definition, inst].any? do |e|
          d = e.attribute_dictionary(DC::DICT_NAME)
          d && d.keys.any? { |k| UNIT_KEY.match?(k) }
        end
      end

      def self.units(entities)
        found = []
        each_unit(entities) { |u| found << u }
        found
      end

      # Yields each outermost unit (looking inside groups and plain components).
      # Definitions with no units inside are remembered for the rest of the
      # walk, so repeated parts (hinges, shelves, drawer boxes) are looked into once.
      # is_unit: which instances count (default: has runout options).
      def self.each_unit(entities, is_unit = nil, &blk)
        is_unit ||= method(:unit?)
        empty = {}
        walk = lambda do |ents|
          any = false
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            defn = e.definition
            if e.is_a?(Sketchup::ComponentInstance) && is_unit.call(e)
              any = true
              blk.call(e)
            elsif !empty[defn]
              found = walk.call(defn.entities)
              empty[defn] = true unless found
              any ||= found
            end
          end
          any
        end
        walk.call(entities)
      end

      # Units in the current selection (or inside it).
      def self.selected(model = Sketchup.active_model)
        model.selection.grep(Sketchup::ComponentInstance).flat_map { |i| unit?(i) ? [i] : units(i.definition.entities) }.uniq
      end

      # --- reading / writing one unit --------------------------------------

      # True when any runout on the unit is above 0 (one pass per attribute
      # list; an instance value wins over its definition's).
      def self.any?(inst)
        vals = {}
        [inst.definition, inst].each do |e|
          d = e.attribute_dictionary(DC::DICT_NAME)
          d&.each_pair { |k, v| vals[k.sub(/\A[a-z]\d{1,2}_/, '')] = v if UNIT_KEY.match?(k) && !v.nil? }
        end
        vals.values.any? { |v| v.to_f * 25.4 > TOL }
      end

      def self.mm_of(inst, side)
        v = DC.value(inst, KEYS[side])
        v.nil? ? nil : (v.to_f * 25.4).round(1)
      end

      def self.inch_s(mm)
        (mm.to_f / 25.4).to_s
      end

      # Sets the values (mm by side) on one unit. Returns true if anything changed.
      def self.set(inst, values)
        changed = false
        values.each do |side, mm|
          base = KEYS[side.to_s] or next
          key = DC.key(inst, base) or next
          cur = DC.read(inst, key).to_f * 25.4
          next if (cur - mm.to_f).abs <= 0.05 && !inst.get_attribute(DC::DICT_NAME, key).nil?
          inst.set_attribute(DC::DICT_NAME, key, inch_s(mm))
          changed = true
        end
        changed
      end

      # Sides (and height) of this unit that differ from the job ([] = standard).
      def self.differences(inst, model = Sketchup.active_model)
        exp = expected(model)
        out = SIDES.filter_map do |s, _, _|
          v = mm_of(inst, s)
          next if v.nil? || (v - exp[s]).abs <= TOL
          "#{s} #{v.round}mm (job #{exp[s].round})"
        end
        out.concat(Ceiling.differences(inst, model)).concat(Facing.differences(inst, model))
      end

      # Every unit that differs from the job: [[label, [differences]]].
      def self.report(model = Sketchup.active_model)
        (units(model.entities) | Facing.units(model.entities)).filter_map do |u|
          d = differences(u, model)
          [Finder.label(u), d] unless d.empty?
        end
      end

      # --- applying to many units -------------------------------------------

      # Applies values (and optionally the ceiling height) to units, one undo
      # step with a progress window. values: { side => mm } or nil.
      # facing: bottom facing (mm) for units that have the option.
      def self.apply(model, units, values, title, done_msg, before: nil, ceiling: nil, facing: nil)
        return UI.messagebox('No units with runout settings found.') if units.empty?
        Batch.run(model, units, title, done: done_msg, before: before) do |inst|
          changed = values ? set(inst, values) : false
          changed = Facing.set(inst, facing) || changed if facing
          changed = Ceiling.set_worktop(inst) || changed
          # The ceiling step redraws itself; otherwise redraw once for the runouts.
          changed = false if ceiling && Ceiling.apply_to(inst, ceiling)
          if changed
            Drawers.close(inst.definition.entities)
            DC.redraw(inst)
          end
        end
      end

      # Pencil released: every runout to 0.
      def self.all_off(model)
        apply(model, units(model.entities), ZERO, 'Scribes off (all runouts 0)',
              'Scribes off: every runout set to 0.', before: -> { model.set_attribute(DICT, 'scribe_on', false) })
      end
    end
  end
end
