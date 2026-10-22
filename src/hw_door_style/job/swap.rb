module HarryWardrobes
  module DoorStyle
    # Right-click > HW Door Style > Replace with: swaps a placed unit for another library
    # component (or a fresh copy of the same one) in the same place, keeping what was set
    # on it:
    #
    #   Component Options  every option the new component also has, by name - width, depth,
    #                      doors, walls, Top of unit, shelves, drawers, internals... Names
    #                      that differ between components are paired up (ALIASES), dropdown
    #                      choices are matched by value, then label, then size ("600mm"), and
    #                      the wardrobe layouts / stable rail type are translated (PAIRS).
    #   the job            runouts, bottom facing, ceiling, depth, drawer fronts, door style,
    #                      hinges and colours as the + window sets them on a new unit; a
    #                      depth that was changed on the old unit is kept.
    #   the Product List   its Pod number and joins (plugin attributes copied; parts joined
    #                      to it follow it).
    #
    # Settings that only exist on one of the two are left at the new component's default.
    # Door-level choices (a hinge override on one door, a Front type) are not kept - they
    # belong to the old doors.
    module Swap
      # Options that mean the same thing under different names (base names, any prefix).
      ALIASES = [
        %w[frame_width size_width frame_size cab_width],
        %w[frame_height_ceiling frame_height ceiling_height size_height unit_height],
        %w[wall_depth depth cab_depth],
        %w[facing_left facing_width_l fllr_left filler_left],
        %w[facing_right facing_width_r fllr_right filler_right]
      ].freeze

      # Dropdown values that mean the same as a plainer one on another component
      # (the wall options: "FALSE (no div)" and "+9mm (end panel)" are not a wall; "TRUE
      # (no scribe)" is a wall).
      VALUE_ALIASES = { 'NODIV' => 'FALSE', 'END' => 'FALSE', 'NOSCRIBE' => 'TRUE' }.freeze

      # Options translated between two components: [from base, to base, { value => value }]
      # (both ways are listed).
      PAIRS = [
        ['layout_left', 'rail_type', { 'DOUBLE' => '2', 'SINGLE' => '1', 'RAILSH' => '1', 'SHELVED' => '0' }],
        ['rail_type', 'layout_left', { '2' => 'DOUBLE', '1' => 'SINGLE', '0' => 'SHELVED' }],
        ['shelves_left', 'sh_no', nil],
        ['sh_no', 'shelves_left', nil]
      ].freeze

      # Never carried: set by the job (Room settings / Settings) on every unit.
      JOB_SET = %w[facing_btm drwr_front_height drwr_front_sm_height door_top_height worktop_height].freeze

      # The shelf top height on a linen press is measured from its worktop, elsewhere from
      # the floor - not carried between the two.
      WORKTOP_DATUM = %w[LINEN_PRESS].freeze

      KEY_RE = /\A[a-z]\d{1,2}_(.+)\z/.freeze
      USER_ACCESS = %w[TEXTBOX LIST].freeze
      LENGTH_UNITS = %w[MILLIMETERS CENTIMETERS INCHES METERS FEET].freeze

      # --- pure mapping (tested offline) -----------------------------------------------

      # "&300mm=11.81&400mm=15.75&" -> [['300mm', '11.81'], ...]
      def self.parse_options(s)
        s.to_s.split('&').reject(&:empty?).map do |pair|
          l, v = pair.split('=', 2)
          [unescape(l), unescape(v.to_s)]
        end
      end

      def self.unescape(s)
        s.to_s.gsub(/%([0-9A-Fa-f]{2})/) { $1.hex.chr }
      end

      def self.num(v)
        Float(v.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def self.same?(a, b)
        return true if a.to_s == b.to_s
        fa, fb = num(a), num(b)
        fa && fb && (fa - fb).abs < 1e-6
      end

      # An option as { v:, a: access, u: units, o: options }. Its size in mm, or nil: a
      # dropdown labelled "600mm", else a length (stored in inches).
      def self.mm_of(opt)
        if opt[:a] == 'LIST'
          label = parse_options(opt[:o]).find { |_, x| same?(x, opt[:v]) }&.first
          return label[/(\d+(?:\.\d+)?)\s*mm/i, 1].to_f if label && label =~ /\d\s*mm/i
        end
        return nil unless LENGTH_UNITS.include?(opt[:u].to_s.upcase) || opt[:u].to_s.upcase == 'DEFAULT'
        n = num(opt[:v]) or return nil
        n * 25.4
      end

      # The value to put in dst for src's value, or nil (leave the default).
      def self.convert(src, dst, map = nil)
        v = src[:v]
        return nil if v.nil? || v.to_s.strip.empty?
        v = map[v.to_s] || return if map
        case dst[:a].to_s.upcase
        when 'LIST'
          opts = parse_options(dst[:o])
          return nil if opts.empty?
          hit = opts.find { |_, x| same?(x, v) }
          hit ||= opts.find { |_, x| same?(x, VALUE_ALIASES[v.to_s]) } if VALUE_ALIASES.key?(v.to_s)
          return hit[1] if hit
          if src[:a] == 'LIST'
            label = parse_options(src[:o]).find { |_, x| same?(x, src[:v]) }&.first
            hit = opts.find { |l, _| l == label } if label
            return hit[1] if hit
          end
          mm = mm_of(src)
          return nil unless mm
          hit = opts.find { |l, _| l =~ /(\d+(?:\.\d+)?)\s*mm/i && ($1.to_f - mm).abs < 0.5 }
          hit && hit[1]
        when 'TEXTBOX'
          dst_len = LENGTH_UNITS.include?(dst[:u].to_s.upcase)
          if dst_len
            mm = mm_of(src) or return nil
            mm / 25.4
          else
            return nil if src[:a] == 'LIST' && !mm_of(src).nil? && !LENGTH_UNITS.include?(src[:u].to_s.upcase) && dst[:u].to_s.upcase != 'STRING'
            n = num(v)
            return n.nil? ? nil : n unless dst[:u].to_s.upcase == 'STRING'
            n && n == n.floor ? n.to_i.to_s : v.to_s
          end
        end
      end

      # Source base names to try for a target base: itself, then its aliases.
      def self.sources_for(base)
        group = ALIASES.find { |g| g.include?(base) }
        group ? [base] + (group - [base]) : [base]
      end

      # Plan the carry from one set of options to another. Both are { key => { v:, a:, u:, o: } }
      # with every option (the target's user-facing ones decide what is carried). Returns
      # { target key => value }. from_name / to_name: component names (for the worktop datum).
      def self.plan(src, dst, from_name: '', to_name: '')
        out = {}
        by_base = ->(h) { h.keys.to_h { |k| [(KEY_RE.match(k) ? $1 : k), k] } }
        sb = by_base.call(src)
        linen = WORKTOP_DATUM.include?(from_name.to_s.upcase) != WORKTOP_DATUM.include?(to_name.to_s.upcase)
        dst.each do |dk, d|
          next unless USER_ACCESS.include?(d[:a].to_s.upcase)
          base = KEY_RE.match(dk) ? $1 : dk
          next if JOB_SET.include?(base) || base.start_with?('runout_')
          next if linen && base == 'sh_top_height'
          sk = sources_for(base).map { |b| sb[b] }.compact.first
          map = nil
          unless sk
            pair = PAIRS.find { |from, to, _| to == base && sb[from] && !sb[base] }
            next unless pair
            sk = sb[pair[0]]
            map = pair[2]
          end
          v = convert(src[sk], d, map)
          out[dk] = v unless v.nil?
        end
        out
      end

      # --- SketchUp side -----------------------------------------------------------------

      # The options of an instance as plan() wants them (instance values over the definition's).
      def self.options_of(inst)
        d = DC.dict(inst.definition) or return {}
        d.keys.select { |k| k =~ KEY_RE }.to_h do |k|
          [k, { v: DC.read(inst, k), a: d["_#{k}_access"].to_s.upcase, u: d["_#{k}_units"].to_s, o: d["_#{k}_options"].to_s }]
        end
      end

      def self.base(inst) = inst.definition.name.sub(/#\d+\z/, '').strip.upcase

      # Can this be replaced: a top-level library unit (in the library index by name).
      def self.swappable?(inst)
        return false unless inst.is_a?(Sketchup::ComponentInstance) && inst.definition.attribute_dictionary(DC::DICT_NAME)
        !library_entry(base(inst)).nil?
      end

      def self.library_entry(name)
        LibraryCache.index.values.find { |e| e['name'].to_s.upcase == name.to_s.upcase && File.exist?(e['file'].to_s) }
      rescue StandardError
        nil
      end

      # Library components a unit can be swapped for: the same group (T, W, B...), itself
      # first ("fresh copy"). [{ 'key', 'name', 'label', 'self' }]
      def self.candidates(inst)
        me = base(inst)
        group = LibraryCache.group('cat' => '', 'name' => me)
        LibraryCache.cards.select { |c| c['cat'] == group && !c['plain'] }
                    .map { |c| { 'key' => c['key'], 'name' => c['name'], 'label' => c['label'], 'self' => c['name'].to_s.upcase == me } }
                    .sort_by { |c| [c['self'] ? 0 : 1, c['label']] }
      end

      # Right-click > Replace with.
      def self.menu(sub, inst)
        list = candidates(inst)
        return if list.empty?
        m = sub.add_submenu('Replace with (settings kept)')
        list.each do |c|
          label = c['self'] ? "Fresh copy of #{c['label']} from the library" : c['label']
          m.add_item(label) { replace(inst, c['key']) }
          m.add_separator if c['self'] && list.size > 1
        end
      end

      # Swaps inst for the library component key, in one undo step. Returns the new instance.
      def self.replace(inst, key)
        model = inst.model
        e = LibraryCache.index[key]
        return UI.messagebox('That component is not on this computer yet - open the + window and press Check library.') unless e && File.exist?(e['file'].to_s)
        label = LibraryCache.pretty(e['name'])
        notes = []
        new_inst = nil
        Ops.run(model, "Replace with #{label}") do
          defn = model.definitions.load(e['file'])
          new_inst, notes = swap(model, inst, defn)
        end
        model.selection.clear
        model.selection.add(new_inst) if new_inst&.valid?
        Sketchup.status_text = "Replaced with #{label}: #{notes.join(', ')}."
        new_inst
      rescue StandardError => err
        Log.error('replace component', err)
        UI.messagebox("Couldn't replace it: #{err.message}")
        nil
      end

      # Inside the caller's step: the new instance in the old one's place, options and
      # plugin attributes carried, the old one gone, the job applied.
      def self.swap(model, old, defn)
        parent = old.parent.entities
        new_inst = parent.add_instance(defn, old.transformation)
        new_inst.layer = old.layer
        new_inst.name = old.name
        new_inst.material = old.material if old.material

        # 1. its options
        carried = plan(options_of(old), options_of(new_inst), from_name: base(old), to_name: defn.name)
        carried.each do |k, v|
          cur = DC.get(defn, k)
          new_inst.set_attribute(DC::DICT_NAME, k, cur.is_a?(String) ? v.to_s : DC.plain(v))
        end
        custom_depth = Depth.has?(old) && Depth.mm(old) && (Depth.mm(old) - Depth.target(old, model)).abs >= 1 ? Depth.mm(old) : nil

        # 2. plugin attributes (Pod number, joins, plan notes...) and the parts joined to it
        old_pid = old.persistent_id.to_s
        Array(old.attribute_dictionaries).each do |d|
          next if d.name == DC::DICT_NAME
          d.each_pair { |k, v| new_inst.set_attribute(d.name, k, v) }
        end
        parent.each do |x|
          next unless (x.is_a?(Sketchup::ComponentInstance) || x.is_a?(Sketchup::Group)) && x.get_attribute(DICT, Products::KEY_HOST) == old_pid
          x.set_attribute(DICT, Products::KEY_HOST, new_inst.persistent_id.to_s)
        end
        parent.erase_entities(old)

        # 3. the job on it, as the + window does; then a depth that had been changed
        job = { 'runouts' => Runouts.expected(model), 'facing' => Facing.mm(model), 'ceiling' => Ceiling.mm(model), 'front' => DrawerFront.job(model) }
        notes = ComponentPicker.setup(model, new_inst, job, depth: custom_depth, redraw: !carried.empty?)
        notes << "depth #{custom_depth.round} kept" if custom_depth && Depth.has?(new_inst)
        notes.unshift("#{carried.size} option(s) carried")
        [new_inst, notes]
      end
    end
  end
end
