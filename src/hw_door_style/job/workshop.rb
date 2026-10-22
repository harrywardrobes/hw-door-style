module HarryWardrobes
  module DoorStyle
    # Workshop: the one window for everything that goes to the workshop and HubSpot -
    # door order, parts list (sheet goods, edging, hardware), labels - saved as one pack and
    # synced to the HubSpot Room: files, quantities, sheets per colour, cut and edged strips,
    # order statuses, and (only when asked) the stage.
    module Workshop
      STATUS_DONE = ['Ordered', 'Received', 'Partially Received'].freeze
      NEEDS = 'Needs Ordering'.freeze
      NA = 'Not Applicable'.freeze

      # Status field -> what in the model needs ordering.
      def self.needs(model, parts)
        c = HubSpotRoom.counts(model)
        doors = Report.rows(model).size + parts['groups'].select { |g| %w[vinyl white_back].include?(g['section']) }.sum { |g| g['count'].to_i }
        worktop = parts['groups'].any? { |g| g['section'] == 'worktops' }
        sheets = parts['groups'].any? { |g| g['section'] == 'sheets' }
        {
          'door_vinyl_order_status' => [doors.positive?, "#{doors} door(s) / drawer front(s)"],
          'drawer_order_status' => [(c['ext_drawers'] + c['int_drawers']).positive?, "#{c['ext_drawers'] + c['int_drawers']} drawer(s)"],
          'sheets_order_status' => [sheets, sheets ? 'board in the parts list' : 'no boards'],
          'hardware_order_status' => [!parts['hardware'].empty? || parts['handles'].any? { |h| h['qty'].to_i.positive? }, "#{parts['hardware'].sum { |h| h['qty'] }} hardware piece(s)"],
          'worktop_order_status' => [worktop, worktop ? 'worktop in the parts list' : 'no worktop (22 / 25 mm)']
        }
      end

      QTY_FIELDS = (HubSpotRoom::HINGE_FIELDS.values + %w[blum_push_tipon_set drawer_total_quantity drawer_type
                                                          main_robe_handle main_robe_handle_id robe_handle_supplier main_robe_handle_quantity
                                                          drawer_handle drawer_handle_sku drawer_handle_supplier drawer_handle_quantity
                                                          interior_handle interior_handle_sku interior_handle_supplier interior_handle_quantity cable_outlet_quantity]).freeze

      # Rows for the HubSpot tab: [{ prop, label, section, hubspot, value, shown, send, flag }].
      def self.plan(model, parts)
        l = HubSpotRoom.link(model) or return { 'linked' => false, 'design_visit' => HubSpotRoom.design_visit?(model), 'saved' => !model.path.to_s.empty? }
        m = HubSpotRoom.meta
        calc = HubSpotRoom.calculated(model, m)
        mine = {}
        QTY_FIELDS.each { |p| mine[p] = [calc.dig(p, 'value'), calc.dig(p, 'shown'), 'Quantities'] if calc.key?(p) }
        PartsList.room_values(parts).each { |p, v| mine[p] = [v, nil, p.start_with?('cut_and') ? 'Cut and edged strips' : 'Sheets'] }
        # every colour field gets a value (0 when the colour isn't used)
        unused = m.keys.select { |p| p.start_with?('mfc_sheets_') && !mine.key?(p) }
        need = needs(model, parts)
        required = (Settings.get['hubspot_required'] || {}).values.flatten.map(&:to_s)
        props = (mine.keys + unused + need.keys + required + %w[hs_pipeline_stage order_parts_list]).uniq
        theirs = HubSpot.read_one('listings', l['room_id'], props.select { |p| m[p] } + %w[hs_pipeline_stage])['properties'] || {}
        # colours not in this job: only cleared to 0 if HubSpot still has a number for them
        unused.each { |p| mine[p] = [0, nil, 'Sheets'] unless theirs[p].to_s.empty? || theirs[p].to_s == '0' }
        rows = mine.filter_map do |p, (v, shown, section)|
          next unless m[p]
          cur = theirs[p]
          { 'prop' => p, 'label' => m[p]['label'], 'section' => section, 'hubspot' => HubSpotRoom.label_of(cur, m[p]['all_options'] || m[p]['options'] || []), 'value' => v,
            'shown' => shown || (v.nil? ? nil : HubSpotRoom.label_of(v, m[p]['all_options'] || m[p]['options'] || [])),
            'send' => v.to_s != cur.to_s && !(v.nil? && cur.to_s.empty?) }
        end
        missing_colours = parts['groups'].map { |g| g['material'] }.uniq.reject { |n| m["mfc_sheets_#{PartsList.slug(n)}"] }
        statuses = need.filter_map do |p, (present, why)|
          next unless m[p]
          # HubSpot gives the option value ("pending"); compare and show the label ("Needs Ordering")
          cur = HubSpotRoom.label_of(theirs[p].to_s, m[p]['all_options'] || m[p]['options'] || []).to_s
          want = present ? NEEDS : NA
          done = STATUS_DONE.include?(cur)
          flag = if done && !present then "#{cur} in HubSpot, but nothing in the model needs it (#{why}) - check it"
                 elsif done then "Already #{cur} - left as it is. Check the order still matches the model."
                 end
          { 'prop' => p, 'label' => m[p]['label'], 'section' => 'Order statuses', 'hubspot' => cur, 'value' => done ? cur : want,
            'why' => why, 'send' => !done && cur != want, 'flag' => flag, 'locked' => done }
        end
        { 'linked' => true, 'room' => l['room_name'], 'room_id' => l['room_id'], 'rows' => rows + statuses,
          'stage' => HubSpotRoom.stage_info(theirs['hs_pipeline_stage']), 'stage_id' => theirs['hs_pipeline_stage'],
          'theirs' => theirs, 'missing_colours' => missing_colours, 'labels' => required.to_h { |r| [r, m.dig(r, 'label') || r] }.merge('order_parts_list' => 'Order / Parts List'),
          'has_files' => !theirs['order_parts_list'].to_s.empty?, 'url' => (HubSpot.record_url('listings', l['room_id']) rescue nil) }
      end

      # Saves the door order and the parts list (PDF each; CSV too if set in Settings). Returns [paths..., versions].
      def self.save(model, parts)
        begin
          Plan.refresh(model) if Plan.plan_page(model) # Pod numbers and dimensions up to date on the Room Plan
        rescue StandardError => e
          Log.error('plan refresh', e)
        end
        door = Report.write_order(model, parts: parts)
        part = PartsList.export(model, parts)
        # One Room Plan PDF (cover, product list, installation plan, pod sheet, panel list).
        plan = begin
          RoomPlan.write(model, parts)
        rescue StandardError => e
          Log.error('room plan', e)
          nil
        end
        { 'files' => [door[1], door[0], part[1], part[0]].compact, 'plan' => plan&.first, 'door_v' => door[2], 'parts_v' => part[2], 'plan_v' => plan&.last }
      end

      # --- advice: things worth a look that don't stop the pack ---------------------------
      # [{ id, text, arg, fix }] - listed under the blockers in the Workshop (amber); fix = a
      # Fix this button (fix_blocker handles it).
      def self.warnings(model, parts)
        out = []
        master = defined?(LibraryExport) && LibraryExport.master?(model)
        units = Runouts.units(model.entities)
        diff = Runouts.unset(model).empty? && !master ? job_differences(model, units) : []
        unless diff.empty?
          out << { 'id' => 'jobdiff', 'fix' => true, 'text' => "#{diff.size} unit(s) aren't at the job's settings (fine if deliberate): #{diff.first(5).map { |u, d| "#{ref(u)} (#{d.join('; ')})" }.join(', ')}#{diff.size > 5 ? '...' : ''}." }
        end
        unknown = unknown_components(model)
        unless unknown.empty?
          out << { 'id' => 'unknown', 'fix' => false, 'text' => "Not in the component table (Settings > Components), so not a product and not checked: #{unknown.map { |n, c| c > 1 ? "#{n} x#{c}" : n }.join(', ')}." }
        end
        walls = wall_clashes(model, units)
        unless walls.empty?
          out << { 'id' => 'walls', 'fix' => false, 'text' => "Wall set where another unit sits (a facing / scribe instead of a join): #{walls.map { |u, side, other| "#{ref(u)} wall #{side} - #{ref(other)} is there" }.first(6).join(', ')}#{walls.size > 6 ? '...' : ''}. Check Wall left / right on those units." }
        end
        ext = wall_no_extend(units)
        unless ext.empty?
          out << { 'id' => 'wallextend', 'fix' => false, 'text' => "Wall set but its extend is 0 mm (floor / shelves won't reach into the scribe): #{ext.map { |u, side| "#{ref(u)} wall #{side}" }.first(6).join(', ')}#{ext.size > 6 ? '...' : ''}. Check Wall left / right: extend on those units." }
        end
        ovh = overhang_zero(units)
        unless ovh.empty?
          out << { 'id' => 'overhang', 'fix' => false, 'text' => "Wall set \"with overhang\" but its overhang is 0 mm: #{ovh.map { |u, side| "#{ref(u)} #{side}" }.first(6).join(', ')}#{ovh.size > 6 ? '...' : ''}. Enter the Overhang - left / right, or choose \"no overhang\"." }
        end
        out
      end

      # Units with Wall left / right "... (with overhang)" (FALSE_OH / TRUE_OH) but its
      # "Overhang - left / right" at 0: [[unit, 'left']].
      def self.overhang_zero(units)
        units.each_with_object([]) do |u, out|
          %w[left right].each do |side|
            v = DC.value(u, "wall_#{side}")
            next unless v && v.to_s.strip.upcase.end_with?('_OH')
            x = DC.value(u, "overhang_#{side}")
            next if x.nil? || x.to_s.strip.empty?
            out << [u, side] if x.to_f.abs < 0.01
          end
        end
      end

      # Units with Wall left / right TRUE but "Wall left / right: extend" at 0: [[unit, 'left']].
      def self.wall_no_extend(units)
        units.each_with_object([]) do |u, out|
          %w[left right].each do |side|
            v = DC.value(u, "wall_#{side}")
            next unless v && WALL_TRUE.include?(v.to_s.strip.upcase)
            x = DC.value(u, "wall_#{side}_extend")
            next if x.nil? || x.to_s.strip.empty?
            out << [u, side] if x.to_f.abs < 0.01
          end
        end
      end

      # Doors / drawer fronts never drawn in a style (plain library fronts): [[inst, kind]].
      def self.unstyled_fronts(model)
        Finder.all_targets(model, Doors::STYLED_KINDS).reject { |i, _k| i.definition.get_attribute(DICT, 'style') || Finder.fixed?(i) }
      end

      # Styled fronts whose size changed since (unit resized without a redraw of the fronts).
      def self.stale_fronts(model)
        Doors.processed(model).select { |i, _k| !Finder.fixed?(i) && Doors.stale?(i) }
      end

      # Units whose runouts / ceiling / bottom facing / drawer fronts differ from the job:
      # [[unit, ['left 50mm (job 25)', ...]]]. Deliberate changes show here too - untick them.
      def self.job_differences(model, units)
        units.filter_map do |u|
          d = Runouts.differences(u, model)
          d.empty? ? nil : [u, d]
        end
      end

      # Sets those units to the job (as Room settings does), then after.
      def self.fix_job_differences(model, after)
        units = job_differences(model, Runouts.units(model.entities)).map(&:first)
        return false if units.empty?
        front = DrawerFront.job(model)
        Runouts.apply(model, units, Runouts.expected(model), 'Job settings', "#{units.size} unit(s) set to the job's settings.",
                      ceiling: Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil, facing: Facing.mm(model), front: front, after: after)
      end

      # Draws the fronts that haven't been styled yet in the job's styles (one step).
      def self.fix_unstyled(model)
        pairs = unstyled_fronts(model)
        return 0 if pairs.empty? || !Colours.door_colour_chosen?(model)
        styles = DoorStyleWindow.job_styles(model)
        Ops.run(model, 'Draw doors in the job style') do
          pairs.group_by { |_i, k| styles[k.to_s] }.each { |style, ps| Converter.rebuild(model, ps, style, override: false, finish: false) }
          door_tag = Tagger.tag_for(model, :door)
          pairs.each do |i, k|
            i.layer = door_tag if k == :door && i.layer != door_tag
            Tagger.tag_item(i, k)
          end
          choices = Colours.job_choices(model).reject { |_k, v| v.nil? }
          Colours.apply(model, choices, record: false) unless choices.empty?
        end
        pairs.size
      end

      # Draws the stale fronts again at their new size.
      def self.fix_stale(model)
        pairs = stale_fronts(model)
        return 0 if pairs.empty?
        Ops.run(model, 'Redraw resized fronts') { Converter.rebuild(model, pairs, nil, override: false, finish: false) }
        pairs.size
      end

      # Top-level dynamic components that have no row in the component table (so the
      # Product List and these checks don't know what they are): { name => count }.
      def self.unknown_components(model)
        c = Products.cfg
        Products.candidates(model.entities).each_with_object(Hash.new(0)) do |(e, n), h|
          next unless e.is_a?(Sketchup::ComponentInstance) && e.definition.attribute_dictionary(DC::DICT_NAME)
          next if Products.row(n, c) || PartsList.ignored?([e])
          h[n] += 1
        end
      end

      WALL_TRUE = %w[TRUE NOSCRIBE TRUE_OH].freeze

      # Units with Wall left / right set where another unit actually sits: [[unit, 'left', other]].
      def self.wall_clashes(model, units)
        tol = 3.0 / 25.4
        others = Products.candidates(model.entities).map(&:first).select { |e| e.respond_to?(:bounds) }
        out = []
        units.each do |u|
          b = u.bounds
          { 'left' => ->(o) { (o.max.x - b.min.x).abs <= tol }, 'right' => ->(o) { (o.min.x - b.max.x).abs <= tol } }.each do |side, touch|
            v = DC.value(u, "wall_#{side}")
            next unless v && WALL_TRUE.include?(v.to_s.strip.upcase)
            hit = others.find do |o|
              next false if o == u
              ob = o.bounds
              touch.call(ob) && ob.min.y < b.max.y - tol && ob.max.y > b.min.y + tol && ob.min.z < b.max.z - tol && ob.max.z > b.min.z + tol
            end
            out << [u, side, hit] if hit
          end
        end
        out
      end

      # Converted doors whose hinges aren't the ones they should have now (their own, the
      # default for their name - the stable wardrobe's big door 155 - or the job's): drawn
      # before the setting changed. [{ inst:, label:, have:, want: }]
      def self.wrong_hinges(model)
        job = Settings.job_hinge_type(model)
        Doors.processed(model, [:door]).filter_map do |inst, _k|
          next if Finder.fixed?(inst)
          d = inst.definition
          kids = d.entities.grep(Sketchup::ComponentInstance).select { |e| e.get_attribute(DICT, 'role') == 'hinge' }
          have = kids.first ? kids.first.get_attribute(DICT, 'type').to_s : d.get_attribute(DICT, 'hinge_type').to_s
          next if have.empty?
          want = Converter.hinge_for(inst, job)
          next if have == want
          { inst: inst, label: Finder.label(inst), have: Settings::HINGE_TYPES.fetch(have, have), want: Settings::HINGE_TYPES.fetch(want, want) }
        end
      end

      def self.fix_hinges(model)
        pairs = wrong_hinges(model).map { |w| [w[:inst], :door] }
        Converter.apply(pairs, nil, 'Redraw doors with the right hinges') unless pairs.empty?
        pairs.size
      end

      # What stops the Workshop Pack being saved: anything that makes the lists wrong or
      # unfinished (a thickness outside the standard list is only a warning). Each is
      # { 'id', 'text', 'arg' } - the Workshop lists them at the top with a Fix this button that
      # opens the window to put it right (fix_blocker below) with the field highlighted.
      def self.blockers(model, parts)
        out = []
        add = ->(id, text, arg = nil) { out << { 'id' => id, 'text' => text, 'arg' => arg } }
        add.call('hubspot', "This file isn't linked to its HubSpot customer (the PDFs and labels need the customer, account and drawing number).") unless HubSpotRoom.customer_link(model)
        nh = PartsList.handles(model).select { |h| h['name'].to_s.start_with?('(not chosen') }
        add.call('handles', "Handles not chosen: #{nh.map { |h| h['kind'].downcase }.join(', ')} (or set them N/A).", nh.map { |h| h['key'] }) unless nh.empty?
        units = Runouts.units(model.entities)
        unset = Runouts.unset(model)
        add.call('runouts', "Runouts not set: #{unset.join(', ')} still 0 mm.", unset) if !unset.empty? && !units.empty?
        add.call('scribes', 'Scribes are OFF - every runout is 0 on the units.') if unset.empty? && !parts['scribes_on'] && !units.empty?
        add.call('ceiling', 'Ceiling height not set for this room.') if Ceiling.mm(model) <= 0 && units.any? { |u| Ceiling.up_to_ceiling?(u) }
        cols = Array(parts['untyped']).reject { |u| u['name'].empty? }
        add.call('colours', "#{cols.sum { |c| c['count'].to_i }} part(s) have a colour the plugin doesn't know: #{cols.map { |c| c['name'] }.join(', ')}.", cols.map { |c| c['name'] }) unless cols.empty?
        none = Array(parts['untyped']).find { |u| u['name'].empty? }
        add.call('nocolour', "#{none['count']} part(s) have no colour - a job colour isn't chosen yet.", unset_colour_groups(model)) if none
        un = unstyled_fronts(model)
        add.call('unstyled', "#{un.size} door(s) / drawer front(s) not drawn in a door style yet - they'd be missing from the order: #{refs(un.map(&:first))}.") unless un.empty?
        st = stale_fronts(model)
        add.call('stale', "#{st.size} door(s) / drawer front(s) changed size after they were drawn: #{refs(st.map(&:first))}.") unless st.empty?
        wh = wrong_hinges(model)
        add.call('hinges', "#{wh.size} door(s) have the wrong hinges: #{refs(wh.map { |w| w[:inst] })}.") unless wh.empty?
        li = Array(parts['loose_internals'])
        add.call('internals', "#{li.size} wardrobe internal(s) aren't inside a tall unit (no Pod number): #{li.first(6).map { |x| "[[#{x['pid']}|#{x['name'].to_s.tr('[]|', '()/')}]]" }.join(', ')}#{li.size > 6 ? '...' : ''}.") unless li.empty?
        parts['groups'].each do |g|
          next if %w[vinyl white_back].include?(g['section'])
          name = "#{g['material']} #{PartsList.fmt(g['thickness'])} mm"
          add.call('sheets', "#{name}: enter the full sheets needed.", g['gid']) if g['ask'] && g['sheets'].nil?
          add.call('too_big', "#{name}: part(s) #{Array(g['too_big']).join(', ')} are bigger than the sheet.", g['material']) unless Array(g['too_big']).empty?
          add.call('nosheet', "#{g['material']}: no sheet size set - no board count.", g['material']) if !g['sheet'] && !g['strip_group']
        end
        g = guides(model).size
        add.call('guides', "#{g} guide line(s) / point(s) in the model - Fix this deletes them all.") if g.positive?
        out
      end

      # Every guide (construction line or point) in the model, at the top level and inside
      # every group / component.
      def self.guides(model)
        lists = [model.entities] + model.definitions.reject(&:image?).map(&:entities)
        lists.flat_map { |es| es.select { |e| e.is_a?(Sketchup::ConstructionLine) || e.is_a?(Sketchup::ConstructionPoint) } }
      end

      def self.delete_guides(model)
        Ops.run(model, 'Delete all guides') do
          guides(model).group_by(&:parent).each { |par, es| par.entities.erase_entities(es) }
        end
      end

      # Plain text (for messages outside the Workshop): the component links as their names.
      def self.blocker_texts(model, parts) = blockers(model, parts).map { |b| plain(b['text']) }

      # --- component links in the texts ---------------------------------------------------
      # "[[persistent id|label]]" - the Workshop shows it bold and clickable (find below).
      REF_RE = /\[\[(\d+)\|([^\]]*)\]\]/.freeze

      def self.ref(e)
        return '?' unless e
        label = Finder.label(e).to_s.tr('[]|', '()/')
        e.respond_to?(:persistent_id) ? "[[#{e.persistent_id}|#{label}]]" : label
      end

      def self.refs(list, max = 6)
        list.first(max).map { |e| ref(e) }.join(', ') + (list.size > max ? '...' : '')
      end

      def self.plain(text) = text.to_s.gsub(REF_RE) { $2 }

      # Where an entity is: the instances / groups from the model down to it, or nil.
      # Each definition is looked inside once (the first path found is used).
      def self.path_to(model, target)
        seen = {}
        walk = lambda do |ents, path|
          ents.each do |x|
            next unless x.is_a?(Sketchup::ComponentInstance) || x.is_a?(Sketchup::Group)
            return path + [x] if x == target
          end
          ents.each do |x|
            next unless x.is_a?(Sketchup::ComponentInstance) || x.is_a?(Sketchup::Group)
            d = x.definition
            next if seen[d]
            seen[d] = true
            r = walk.call(d.entities, path + [x])
            return r if r
          end
          nil
        end
        walk.call(model.entities, [])
      end

      # Click a component in a check: opens the groups it's in, selects it and zooms to it.
      def self.find(model, pid)
        e = model.find_entity_by_persistent_id(pid.to_i)
        return false unless e&.valid?
        path = path_to(model, e) or return false
        begin
          model.active_path = path.size > 1 ? path[0..-2] : nil
        rescue ArgumentError, TypeError
          model.active_path = nil
        end
        model.selection.clear
        model.selection.add(e)
        v = model.active_view
        v.zoom(model.selection) rescue nil
        v.zoom(0.6) rescue nil
        v.invalidate
        Sketchup.status_text = "#{Finder.label(e)} is selected."
        true
      end

      # Colour groups still on Default with no door colour to fall back on (door first).
      def self.unset_colour_groups(model)
        cur = Colours.job_choices(model)
        door = cur['door'] && cur['door'] != Colours::DEFAULT
        Colours::GROUPS.map(&:first).reject { |id| %w[panels_22 drawer_box].include?(id) }
                .select { |id| (cur[id].nil? || cur[id] == Colours::DEFAULT) && (id == 'door' || !door) }
      end

      # Fix this: what to do for one blocker / warning. Returns :reload (fixed here - the
      # Workshop recalculates), :page (another page opened with the field highlighted; the
      # Workshop comes back by itself when that page is done), :busy (a batch is running and
      # brings the Workshop back after), or :tab (the Workshop's own page handles it).
      def self.fix_blocker(model, id, arg, reopen)
        back = { back: reopen }
        case id
        when 'hubspot'
          HubSpotRoom.show_pick(:link, after: reopen)
          :page
        when 'handles'
          Dialog.focus_next('door_style', sel: Array(arg).map { |k| "#hr_#{k}" },
                                          note: 'Choose the highlighted handle(s) - or N/A when there are none - then Apply; the Workshop comes back.', **back)
          DoorStyleWindow.show(model)
          :page
        when 'runouts', 'ceiling'
          sel = id == 'ceiling' ? ['#ceiling'] : Array(arg).map { |s| "#s_#{s}" }
          Dialog.focus_next('scribe', sel: sel, note: id == 'ceiling' ? 'Enter the ceiling height, then Apply; the Workshop comes back.' :
                                                     'Measure in the highlighted runout(s) (25 mm minimum), then Apply; the Workshop comes back.', **back)
          Pencil.show(model, nil)
          :page
        when 'colours', 'nocolour'
          groups = id == 'nocolour' ? Array(arg) : []
          Dialog.focus_next('colours', sel: groups.map { |g| "#sel_#{g}" },
                                       note: id == 'nocolour' ? 'Choose the highlighted job colour(s), then Apply; the Workshop comes back.' :
                                                                "Parts are painted #{Array(arg).join(', ')}, which isn't one of the plugin's colours: choose the job colours here and Apply (it repaints them); the Workshop comes back.", **back)
          ColoursWindow.show
          :page
        when 'unstyled'
          unless Colours.door_colour_chosen?(model)
            Dialog.focus_next('colours', sel: ['#sel_door'], note: 'Choose the door colour first, then Apply; the Workshop comes back and draws the doors from there.', **back)
            ColoursWindow.show
            return :page
          end
          fix_unstyled(model)
          :reload
        when 'stale'
          fix_stale(model)
          :reload
        when 'guides'
          delete_guides(model)
          :reload
        when 'hinges'
          fix_hinges(model)
          :reload
        when 'scribes'
          scribes_on(model, reopen) ? :busy : :reload
        when 'jobdiff'
          fix_job_differences(model, reopen) ? :busy : :reload
        when 'nosheet', 'too_big'
          Dialog.focus_next('settings', js: "show('workshop')", sel: ['#ocl_sheet_sizes'],
                                        note: id == 'nosheet' ? "Add the sheet size for #{arg} (e.g. 2800x2070), then Save; the Workshop updates." :
                                                                "Check the sheet sizes for #{arg} - a part is bigger than every size listed. Save; the Workshop updates.", **back)
          SettingsWindow.show
          :page
        else
          :tab # internals, sheets: on the Workshop's own tabs
        end
      end

      # Scribes on for every unit with the job's runouts (as the Scribe window's Apply), then after.
      def self.scribes_on(model, after)
        v = Runouts.job_values(model)
        Runouts.apply(model, Runouts.units(model.entities), v, 'Scribes on',
                      "Scribes on: #{Runouts::SIDES.map { |s, _, _| "#{s} #{v[s].round}" }.join(', ')} mm.",
                      before: lambda {
                        model.set_attribute(DICT, 'scribe_on', true)
                        model.set_attribute(DICT, 'scribe_values', JSON.generate(v))
                      }, after: after)
      end

      PDF_KINDS = [['DOOR_ORDER', 'Door / Vinyl order'], ['PARTS_LIST', 'Parts list'], ['ROOM_PLAN', 'Room Plan']].freeze

      # The latest PDF of each kind saved for this model (next to it): [{ title, name, path, v, date }].
      def self.pdfs(model)
        return [] if model.path.to_s.empty?
        dir = File.dirname(model.path)
        base = Report.safe_name(File.basename(model.path, '.skp'))
        return [] unless Dir.exist?(dir)
        names = Dir.children(dir)
        PDF_KINDS.filter_map do |kind, title|
          re = /\A#{kind}_v(\d+)_#{Regexp.escape(base)}\.pdf\z/i
          best = names.filter_map { |n| (m = n.match(re)) && [m[1].to_i, n] }.max_by(&:first)
          next unless best
          path = File.join(dir, best[1])
          { 'title' => "#{title} v#{best[0]}", 'name' => best[1], 'path' => path, 'v' => best[0], 'date' => File.mtime(path).strftime('%d/%m/%Y %H:%M') }
        end
      end

      # The labels of a pack, saved next to the PDFs as the exact ZPL that will be printed.
      def self.save_labels(model, zpl, version)
        path = File.join(File.dirname(model.path), "LABELS_v#{version}_#{Report.safe_name(File.basename(model.path, '.skp'))}.zpl")
        File.binwrite(path, zpl)
        path
      end

      # Uploads the four files into Order / Parts List (replacing the last ones), sends the
      # ticked values and, only if chosen, moves the stage.
      def self.send_room(model, room_id, files, values, stage, plan: nil)
        folder = HubSpotPictures.config['files_folder']
        ids = files.map { |f| HubSpot.upload(f, folder) }
        props = values.merge(PartsList::FIELD => ids.join(';'))
        if plan && File.exist?(plan)
          # Floor Plan keeps the survey pictures; the last installation plan is replaced.
          pid = HubSpot.upload(plan, folder)
          cur = (HubSpot.read_one('listings', room_id, ['floor_plan'])['properties'] || {})['floor_plan'].to_s.split(';')
          last = model.get_attribute(DICT, 'plan_hs_file').to_s
          props['floor_plan'] = (cur.reject { |x| x == last || x.empty? } + [pid]).join(';')
          Ops.run(model, 'HubSpot: record plan', transparent: true) { model.set_attribute(DICT, 'plan_hs_file', pid.to_s) }
          ids << pid
        end
        props['hs_pipeline_stage'] = stage if stage && !stage.to_s.empty?
        HubSpot.update_room(room_id, props)
        Ops.run(model, 'HubSpot: record workshop send', transparent: true) { model.set_attribute(DICT, 'hs_workshop_sent_at', Time.now.strftime('%d/%m/%Y %H:%M')) }
        ids.size
      end
    end
  end
end
