require 'json'

module HarryWardrobes
  module DoorStyle
    # Product list: the big things in a job (wardrobes, bridge units, worktops, drawer
    # units, box shelf sections...), each with a Pod number - T1, T2... - that the Workshop
    # tabs and the floor plan refer to.
    #
    #   Settings "components" says what each component is: a unit (a product of its
    #   own), a joiner (part of the product it sits in / under / on - a box end under a
    #   worktop, the bridge frame on its skeleton; the same joiners next to each other with
    #   no product to join make one section), an internal (only ever inside a unit of its
    #   letter - int drawers in a wardrobe) or skipped (bullnose, end panels, floor...).
    #
    # Joins are automatic, and can be changed in the Workshop's Product List (stored on the
    # part: "own" or the product it belongs to). Pod numbers are given left to right the first
    # time and then kept on each product, so a new unit gets the next number; Renumber gives
    # them out left to right again.
    module Products
      KEY_T = 'product_t'.freeze
      KEY_HOST = 'product_host'.freeze
      KEY_REF = 'product_ref'.freeze # on a joiner: 'own' or the host's persistent id
      TOUCH = 2.0 / 25.4 # 2 mm

      # Letters in key / list order (Settings "product_ref_names"); any other letter follows.
      def self.order
        (Settings.get['product_ref_names'] || {}).keys.map { |k| k.to_s.upcase }
      end

      ROLES = { 'unit' => 'A product of its own', 'joiner' => 'Part of the product it sits in, under or on',
                'internal' => 'Always inside a unit of its letter', 'skip' => 'Never a product' }.freeze

      # Settings "components" (the component table): NAME -> { role, product, letter... }.
      # The Product List only cares about these roles (doors, drawer fronts... are ignored):
      #   unit      a product of its own, numbered with its letter (T1, W1...)
      #   joiner    belongs to the product it sits in / under / on; alone it's a product of its
      #             own (its letter); the same joiners next to each other make one section
      #   internal  only ever part of a unit of its letter (int drawers in a T); alone = flagged
      #   skip      never a product (bullnose, end panels, floor...)
      # A component not in the table is ignored by the Product List.
      def self.cfg
        s = Settings.get
        rows = Settings.components(s).filter_map do |k, v|
          role = v['role'].to_s
          role = 'skip' if role == 'room'
          next unless ROLES.key?(role)
          [k, { 'product' => v['product'].to_s, 'role' => role, 'letter' => v['letter'].to_s.strip.upcase }]
        end.to_h
        { 'comps' => rows, 'keys' => rows.keys.sort_by { |x| -x.size } }
      end

      def self.base(e)
        n = e.respond_to?(:definition) ? e.definition.name : e.name.to_s
        n.sub(/#\d+\z/, '').strip.upcase
      end

      # name is the component, or the component with more after "_", " " or "(" -
      # EXT_DRAWER, EXT_DRAWER_2, "EXT_DRAWER (Fitted)".
      def self.named?(name, x) = name == x || name.start_with?("#{x}_", "#{x} ", "#{x}(")

      # The table row for a component name (longest matching name first), or nil.
      def self.row(name, c = cfg)
        k = c['keys'].find { |x| named?(name, x) }
        k && c['comps'][k]
      end

      def self.role(name, c = cfg) = row(name, c)&.fetch('role', nil)

      # Friendly product name, or nil for a component that's not a product.
      def self.type_of(name, c = cfg)
        r = row(name, c)
        r && r['role'] != 'skip' && !r['product'].empty? ? r['product'] : nil
      end

      def self.unit?(name, c = cfg) = role(name, c) == 'unit'
      def self.joiner?(name, c = cfg) = %w[joiner internal].include?(role(name, c))
      def self.internal?(name, c = cfg) = role(name, c) == 'internal'
      def self.skip?(name, c = cfg) = role(name, c) == 'skip'

      # Pod letter: the row's letter, else the first in the key (T).
      def self.ref_of(name, c = cfg)
        l = row(name, c)&.fetch('letter', '').to_s
        l.empty? ? (order.first || 'T') : l
      end

      # The key for the reference letters: [[letter, meaning]] for the letters given (or all),
      # in list order. Settings "product_ref_names".
      def self.key(letters = nil)
        names = (Settings.get['product_ref_names'] || {}).to_h { |k, v| [k.to_s.upcase, v.to_s] }
        ord = order
        list = (letters ? letters.map(&:to_s).uniq : names.keys).sort_by { |l| [ord.index(l) || 9, l] }
        list.map { |l| [l, names[l] || ''] }
      end

      # "Key: T = Tall units, W = Wall / bridge units..." for a PDF footer.
      def self.key_text(letters = nil)
        k = key(letters)
        k.empty? ? '' : "Key: #{k.map { |l, n| n.empty? ? l : "#{l} = #{n}" }.join(',  ')}"
      end

      # Every candidate in the model (top level, and inside plain groups): [[inst, name]].
      def self.candidates(ents, out = [], depth = 0)
        ents.each do |e|
          next unless (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && e.visible?
          n = base(e)
          if e.is_a?(Sketchup::Group) && depth < 3 && row(n).nil?
            candidates(e.entities, out, depth + 1)
          else
            out << [e, n]
          end
        end
        out
      end

      def self.mm(v) = (v.to_f * 25.4).round

      def self.touch?(a, b)
        a.min.x <= b.max.x + TOUCH && b.min.x <= a.max.x + TOUCH &&
          a.min.y <= b.max.y + TOUCH && b.min.y <= a.max.y + TOUCH &&
          a.min.z <= b.max.z + TOUCH && b.min.z <= a.max.z + TOUCH
      end

      def self.overlap_xy(a, b)
        [[a.max.x, b.max.x].min - [a.min.x, b.min.x].max, 0].max * [[a.max.y, b.max.y].min - [a.min.y, b.min.y].max, 0].max
      end

      def self.inside?(item, host)
        c = item.center
        c.x.between?(host.min.x - TOUCH, host.max.x + TOUCH) && c.y.between?(host.min.y - TOUCH, host.max.y + TOUCH) && c.z.between?(host.min.z - TOUCH, host.max.z + TOUCH)
      end

      # The automatic host for a joiner: the product it sits in, else the one resting on it
      # (worktop on a box end), else the one it rests on (bridge frame on its skeleton).
      def self.auto_host(item, hosts)
        b = item.bounds
        inside = hosts.select { |h, _| inside?(b, h.bounds) }
        return inside.max_by { |h, _| -h.bounds.diagonal }&.first unless inside.empty?
        touching = hosts.select { |h, _| touch?(b, h.bounds) && overlap_xy(b, h.bounds) > 0 }
        above = touching.select { |h, _| (h.bounds.min.z - b.max.z).abs <= TOUCH }
        return above.max_by { |h, _| overlap_xy(b, h.bounds) }&.first unless above.empty?
        below = touching.select { |h, _| (b.min.z - h.bounds.max.z).abs <= TOUCH }
        return below.max_by { |h, _| overlap_xy(b, h.bounds) }&.first unless below.empty?
        # overlapping (e.g. the bridge frame over its skeleton)
        touching.max_by { |h, _| overlap_xy(b, h.bounds) }&.first
      end

      # Depth (back wall to the back of the facing) / finished depth (to the front of the door
      # or facing), from the component's own options (Settings "product_depth_keys", first
      # found). Finished: its "depth finished" option, else depth + Settings "product_front_mm".
      def self.depths(inst)
        return [nil, nil] unless inst.respond_to?(:definition) && inst.definition.attribute_dictionary('dynamic_attributes')
        val = lambda do |base|
          k = DC.key(inst, base) or return nil
          v = DC.read(inst, k)
          v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * Ceiling.mm_per(inst, k)).round
        end
        keys = Array(Settings.get['product_depth_keys']).map(&:to_s)
        keys = %w[wall_depth depth cab_depth depth_fl_div] if keys.empty?
        base = keys.find { |k| val.call(k) }
        return [nil, nil] unless base
        d = val.call(base)
        f = val.call("#{base}_finished")
        f ||= d + Settings.get['product_front_mm'].to_f.round if Settings.get['product_front_mm'].to_f.positive?
        [d, f]
      end

      # The products: [{ 't', 'num', 'type', 'name', 'size', 'depth', 'finished', 'pid', 'members' => [...] }]
      # with every member (the product itself first) as { 'pid', 'name', 'auto', 'host' }.
      # Also returns { top-level instance entityID => T label } for the door order.
      def self.list(model, c = cfg)
        all = candidates(model.entities).reject { |_e, n| skip?(n, c) }
        hosts = all.select { |_e, n| unit?(n, c) }
        joiners = all.select { |_e, n| joiner?(n, c) }
        by_pid = (hosts + joiners).to_h { |e, _| [e.persistent_id.to_s, e] }
        groups = hosts.to_h { |e, n| [e, { 'host' => e, 'name' => n, 'members' => [] }] }
        loose = []
        @loose_internals = []
        joiners.each do |e, n|
          want = e.get_attribute(DICT, KEY_HOST)
          int = internal?(n, c)
          # an internal only joins a unit of its own letter (int drawers: a T)
          tall = int ? hosts.select { |_h, hn| ref_of(hn, c) == ref_of(n, c) } : hosts
          auto = auto_host(e, tall)
          host = if want == 'own' && !int then nil
                 elsif want && want != 'own' && by_pid[want] && groups[by_pid[want]] && (!int || tall.any? { |h, _| h == by_pid[want] }) then by_pid[want]
                 else auto
                 end
          if host
            groups[host]['members'] << { 'e' => e, 'name' => n, 'auto' => want.nil?, 'auto_host' => auto }
          elsif int
            # not inside any tall unit: not numbered - the Workshop checks say so
            @loose_internals << { 'pid' => e.persistent_id.to_s, 'name' => e.respond_to?(:definition) ? e.definition.name : n, 'x' => mm(e.bounds.min.x), 'letter' => ref_of(n, c) }
          else
            loose << [e, n, want]
          end
        end
        # Loose joiners next to each other (box shelves) make one section - unless split off ("own").
        sections = []
        loose.each do |e, n, want|
          sec = want == 'own' ? nil : sections.find { |s| !s['own'] && s['members'].any? { |m| touch?(m['e'].bounds, e.bounds) && base(m['e']) == n } }
          if sec
            sec['members'] << { 'e' => e, 'name' => n, 'auto' => true }
          else
            sections << { 'host' => e, 'name' => n, 'own' => want == 'own', 'members' => [] }
          end
        end
        prods = groups.values + sections
        prods.each { |p| p['ref'] = ref_of(p['name'], c) }
        number(model, prods)
        tops = {}
        ord = order
        rows = prods.sort_by { |p| [ord.index(p['ref']) || 9, p['ref'], p['num']] }.map do |p|
          h = p['host']
          bb = Geom::BoundingBox.new
          bb.add(h.bounds)
          p['members'].each { |m| bb.add(m['e'].bounds) }
          d, f = depths(h)
          t = "#{p['ref']}#{p['num']}"
          ([h] + p['members'].map { |m| m['e'] }).each { |e| tops[e.entityID] = t }
          type = type_of(p['name'], c) || (p['name'] =~ /SHELF/ ? 'Box shelves' : p['name'] =~ /BXEND/ ? 'Box end' : p['name'].tr('_', ' ').capitalize)
          {
            't' => t, 'ref' => p['ref'], 'num' => p['num'], 'type' => type, 'name' => "#{type} #{mm(h.bounds.width)}",
            'size' => [mm(bb.width), mm(bb.height), mm(bb.depth)], 'depth' => d, 'finished' => f,
            'pid' => h.persistent_id.to_s, 'component' => h.respond_to?(:definition) ? h.definition.name : h.name,
            'x' => mm(bb.min.x),
            'members' => p['members'].map do |m|
              { 'pid' => m['e'].persistent_id.to_s, 'name' => m['e'].respond_to?(:definition) ? m['e'].definition.name : m['name'],
                'size' => [mm(m['e'].bounds.width), mm(m['e'].bounds.height), mm(m['e'].bounds.depth)], 'auto' => m['auto'] }
            end
          }
        end
        [rows, tops]
      end

      # Wardrobe internals that aren't in any tall unit, from the last list (or this one).
      def self.loose_internals(model = nil)
        list(model) if model
        Array(@loose_internals)
      end

      # Pod numbers: kept on each product; new ones get the next numbers, left to right.
      # Numbers per letter (T1, T2... W1...): kept on each product (with its letter, so a
      # product that changes letter gets a new number); new ones get the next, left to right.
      def self.number(model, prods, renumber: false)
        prods.group_by { |p| p['ref'] }.each do |ref, list|
          saved = ->(p) { p['host'].get_attribute(DICT, KEY_REF) == ref ? p['host'].get_attribute(DICT, KEY_T).to_i : 0 }
          used = renumber ? [] : list.map { |p| saved.call(p) }.select(&:positive?)
          dup = used.tally.select { |_n, k| k > 1 }.keys
          todo = []
          list.each do |p|
            n = renumber ? 0 : saved.call(p)
            n.positive? && !dup.include?(n) ? p['num'] = n : todo << p
          end
          nxt = list.map { |p| p['num'].to_i }.max || 0
          todo.sort_by { |p| [p['host'].bounds.min.x.round(1), p['host'].bounds.min.y.round(1)] }.each { |p| p['num'] = (nxt += 1) }
        end
        changed = prods.select { |p| p['host'].get_attribute(DICT, KEY_T).to_i != p['num'] || p['host'].get_attribute(DICT, KEY_REF) != p['ref'] }
        # The library file is never numbered (its numbers would go into every job).
        return if changed.empty? || (defined?(LibraryExport) && LibraryExport.master?(model))
        Ops.run(model, 'Product numbers', transparent: true) do
          changed.each { |p| p['host'].set_attribute(DICT, KEY_T, p['num']); p['host'].set_attribute(DICT, KEY_REF, p['ref']) }
        end
      end

      def self.renumber(model)
        Ops.run(model, 'Renumber products') do
          candidates(model.entities).each { |e, _| [KEY_T, KEY_REF].each { |k| e.delete_attribute(DICT, k) if e.get_attribute(DICT, k) } }
        end
        list(model)
      end

      # A part's product: 'own', a host's persistent id, or '' (back to automatic).
      def self.set_host(model, pid, host)
        e = find(model, pid) or return
        Ops.run(model, 'Product: move part') do
          host.to_s.empty? ? e.delete_attribute(DICT, KEY_HOST) : e.set_attribute(DICT, KEY_HOST, host.to_s)
        end
      end

      def self.find(model, pid)
        candidates(model.entities).map(&:first).find { |e| e.persistent_id.to_s == pid.to_s }
      end

      # --- T labels on the floor plan -------------------------------------------------

      def self.label_tag(model) = Tags.get(model, 'product_label_tag')

      # Text over the middle of each product, on its own tag, shown only in the plan scenes
      # (Settings "product_label_scenes", e.g. "top"). Replaces the labels made last time.
      def self.label(model, rows = nil)
        rows ||= list(model).first
        tag = label_tag(model)
        pattern = Regexp.new(Settings.get['product_label_scenes'].to_s.strip.then { |s| s.empty? ? 'top|plan' : s }, Regexp::IGNORECASE)
        by_pid = candidates(model.entities).to_h { |e, _| [e.persistent_id.to_s, e] }
        n = 0
        Ops.run(model, 'Pod numbers on the plan') do
          old = model.entities.grep(Sketchup::Text).select { |t| t.get_attribute(DICT, 'product_label') }
          model.entities.erase_entities(old) unless old.empty?
          rows.each do |r|
            h = by_pid[r['pid']] or next
            bb = Geom::BoundingBox.new
            bb.add(h.bounds)
            r['members'].each { |m| (e = by_pid[m['pid']]) && bb.add(e.bounds) }
            pt = Geom::Point3d.new(bb.center.x, bb.center.y, bb.max.z + 1)
            depth = r['depth'] ? " (#{r['depth']}#{r['finished'] ? "/#{r['finished']}" : ''})" : ''
            t = model.entities.add_text("#{r['t']}#{depth}", pt)
            t.layer = tag
            t.display_leader = false
            t.set_attribute(DICT, 'product_label', r['t'])
            n += 1
          end
          # Hidden everywhere except the plan scenes.
          if Tags.ours?(tag)
            tag.visible = false unless model.pages.select { |pg| pg.name =~ pattern }.include?(model.pages.selected_page)
            model.pages.each { |pg| pg.set_visibility(tag, pg.name =~ pattern ? true : false) }
          end
        end
        n
      end
    end
  end
end
