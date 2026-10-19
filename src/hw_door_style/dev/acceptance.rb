module HarryWardrobes
  module DoorStyle
    # Acceptance tests run inside SketchUp on the open model (Developer > Run tests,
    # or Acceptance.report_text in the Ruby Console). Best on the component library.
    #
    # Every suite runs in an Ops.throwaway step, so the model is left exactly as
    # it was. Anything that would open its own undo step inside a suite raises
    # Ops::NestedStep instead of committing - so the tests only call the
    # step-free parts of the plugin (Converter.rebuild, Runouts.set,
    # Ceiling.apply_to, Colours.apply, DC.redraw ...).
    #
    # A row: { suite:, item:, case:, ok:, detail: }
    module Acceptance
      MM = 25.4
      TOL = 0.11 # mm

      SUITES = %w[doors runouts ceiling colours cutlist export].freeze

      def self.mm(v) = v.to_f * MM

      def self.row(suite, item, kase, ok, detail = '')
        { suite: suite, item: item.to_s, case: kase.to_s, ok: ok ? true : false, detail: detail.to_s }
      end

      def self.run(model = Sketchup.active_model, suites: SUITES)
        rows = []
        suites.each do |s|
          started = Time.now
          begin
            rows.concat(send("suite_#{s}", model))
          rescue StandardError => e
            rows << row(s, '-', 'suite ran', false, "#{e.class}: #{e.message}")
            Log.error("test #{s}", e)
          end
          Log.debug("test #{s}: #{(Time.now - started).round(1)}s")
        end
        rows
      end

      # --- helpers -------------------------------------------------------------

      def self.scale1?(e)
        s, = Finder.decompose(e.transformation)
        s.all? { |v| (v - 1).abs < 0.0005 }
      end

      def self.top_unit(model, name)
        model.entities.find { |e| e.is_a?(Sketchup::ComponentInstance) && e.definition.name == name }
      end

      # Formula errors DC recorded on these objects (definition + instance).
      def self.formula_errors(objs)
        objs.flat_map { |o| [o, o.definition] }.uniq.flat_map do |o|
          d = DC.dict(o) or next []
          d.keys.select { |k| k.end_with?('_error') && d[k].to_s.include?('subformula-error') }
               .map { |k| "#{o.definition.name rescue o.name}.#{k.sub(/\A_/, '').sub(/_error\z/, '')}" }
        end
      end

      # World z range (mm) of the first part named like re inside inst.
      def self.part_z(inst, re)
        t = inst.transformation
        c = inst.definition.entities.grep(Sketchup::ComponentInstance).find { |k| k.definition.name =~ re } or return nil
        b = c.bounds
        [mm((t * b.min).z).round(1), mm((t * b.max).z).round(1)]
      end

      def self.bounds_mm(inst)
        b = inst.bounds
        [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z].map { |v| mm(v).round(1) }
      end

      # --- doors: DOOR_W/T/H contract, slab, hinges ------------------------------

      DOOR_UNITS = {
        'WARDROBE'     => { width: 'frame_width', double: 'door_double', margin: 2 },
        'WALK-IN'      => { width: 'frame_width', double: 'door_double', margin: 2 },
        'LINEN_PRESS'  => { width: 'frame_width', double: 'door_double', margin: 2 },
        'TOPBOX'       => { width: 'frame_width', double: 'door_double', margin: 2 },
        'BRIDGE_FRAME' => { width: 'frame_size',  double: 'double',      margin: 2 }
      }.freeze
      DOOR_SIZES = [[300, 400], [450, 1300], [600, 2300]].freeze

      def self.set_attr(objs, key, value, formula = nil)
        objs.each do |o|
          o.set_attribute(DC::DICT_NAME, key, value)
          o.set_attribute(DC::DICT_NAME, "_#{key}_formula", formula) if formula
        end
      end

      def self.wrappers_in(unit)
        Repair.candidates(unit.model).select { |i, k| k == :door && Repair.top_level(i, unit.model) == unit }.map(&:first)
      end

      def self.check_door(wrapper, thickness_mm)
        fails = []
        w = mm(DC.read(wrapper, 'door_w')); t = mm(DC.read(wrapper, 'door_t')); h = mm(DC.read(wrapper, 'door_h'))
        fails << 'wrapper scale' unless scale1?(wrapper)
        kids = wrapper.definition.entities.grep(Sketchup::ComponentInstance)
        slab = kids.find { |k| k.get_attribute(DICT, 'role') == 'style' }
        if slab.nil?
          fails << 'no slab'
        else
          ss, = Finder.decompose(slab.transformation)
          b = slab.definition.bounds
          sw, sd, sh = [b.width * ss[0], b.height * ss[1], b.depth * ss[2]].map { |v| mm(v) }
          fails << "slab depth #{sd.round(2)}" if (sd - thickness_mm).abs > TOL || (t - thickness_mm).abs > TOL
          fails << "slab W #{sw.round(1)}<>#{w.round(1)}" if (sw - w).abs > TOL
          fails << "slab H #{sh.round(1)}<>#{h.round(1)}" if (sh - h).abs > TOL
          fails << 'slab named STYLE' if slab.definition.name =~ /STYLE_/ || DC.read(slab, '_name').to_s =~ /STYLE_/
        end
        hinges = kids.select { |k| k.get_attribute(DICT, 'role') == 'hinge' }
        inset = [mm(DC.read(wrapper, 'zz_hinge_inset')), h / 4.0].min
        half = mm(DC.read(wrapper, 'zz_hinge_half'))
        hx = mm(DC.read(wrapper, 'zz_hinge_x'))
        n = hinges.size
        hinges.each do |hg|
          fails << 'hinge scale' unless scale1?(hg)
          b = hg.definition.bounds
          size = [b.width, b.height, b.depth].map { |v| mm(v).round(1) }
          fails << "hinge size #{size}" unless size == [35.0, 12.0, 35.0] || size == [35.0, 10.0, 35.0]
          o = hg.transformation.origin
          i = DC.read(hg, 'zz_hinge_i').to_i
          want_z = n <= 1 ? h / 2 - half : inset + i * (h - 2 * inset) / (n - 1) - half
          fails << "hinge#{i} z #{mm(o.z).round(1)}<>#{want_z.round(1)}" if (mm(o.z) - want_z).abs > TOL
          fails << "hinge#{i} y" if (mm(o.y) - t).abs > TOL
          fails << "hinge#{i} x" if (mm(o.x) - hx).abs > TOL
        end
        [fails, "#{w.round(1)} x #{h.round(1)} x #{t.round(1)}, #{n} hinges (rule #{Settings.hinge_count(h / MM)})"]
      end

      def self.suite_doors(model)
        rows = []
        Ops.throwaway(model, 'HW tests: doors (discarded)') do
          DOOR_UNITS.each do |uname, cfg|
            unit = top_unit(model, uname)
            next rows << row('doors', uname, '-', true, 'not in this model - skipped') unless unit
            th = mm(DC.read(unit, 'thickness'))
            [%w[single 0], %w[double 1]].each do |label, dbl|
              DOOR_SIZES.each do |w, h|
                frame = dbl == '1' ? 2 * w + 3 * cfg[:margin] : w + 2 * cfg[:margin]
                set_attr([unit, unit.definition], DC.key(unit, cfg[:double]) || cfg[:double], dbl)
                set_attr([unit, unit.definition], DC.key(unit, cfg[:width]) || cfg[:width], frame / MM)
                wrappers_in(unit).each { |wr| set_attr([wr, wr.definition], 'door_h', h / MM, format('%g', h / 10.0)) }
                DC.redraw(unit)
                wrappers_in(unit).each do |wr|
                  fails, info = check_door(wr, th)
                  rows << row('doors', "#{uname} / #{Finder.label(wr)}", "#{label} #{w}x#{h}", fails.empty?, fails.empty? ? info : fails.join('; '))
                end
              end
            end
          end
          rows << row('doors', 'model', 'no STYLE_* components left', model.definitions.none? { |d| d.name =~ /\ASTYLE_/i })
        end
        broken = Repair.candidates(model).reject { |i, k| Repair.problems(i, k).empty? }
        stale = model.definitions.count { |d| d.name =~ /\ASTYLE_/i && d.instances.empty? }
        rows << row('doors', 'model', 'Repair would change nothing', broken.empty? && stale.zero?,
                    (broken.map { |i, _| Finder.label(i) } + (stale.zero? ? [] : ["#{stale} unused STYLE_ definitions"])).join(', '))
      end

      # --- runouts: every unit takes 25mm and goes back exactly -------------------

      def self.suite_runouts(model)
        rows = []
        units = Runouts.units(model.entities)
        return [row('runouts', 'model', 'units with runouts', false, 'none found')] if units.empty?
        Ops.throwaway(model, 'HW tests: runouts (discarded)') do
          start = units.to_h { |u| [u, [bounds_mm(u), Runouts::SIDES.to_h { |s, _, _| [s, Runouts.mm_of(u, s) || 0.0] }]] }
          all25 = Runouts::SIDES.to_h { |s, _, _| [s, 25.0] }
          units.each do |u|
            Runouts.set(u, all25)
            Drawers.close(u.definition.entities)
            DC.redraw(u)
          end
          rows << row('runouts', 'model', 'pencil sees runouts on', Pencil.detect(model))
          units.each do |u|
            errs = formula_errors([u])
            moved = bounds_mm(u) != start[u][0]
            rows << row('runouts', Finder.label(u), '25 mm all sides', errs.empty? && Runouts.any?(u),
                        errs.empty? ? (moved ? 'size changed' : 'no change (walls off)') : errs.join(', '))
          end
          units.each do |u|
            Runouts.set(u, start[u][1])
            Drawers.close(u.definition.entities)
            DC.redraw(u)
          end
          units.each do |u|
            a = bounds_mm(u)
            b = start[u][0]
            same = a.zip(b).all? { |x, y| (x - y).abs <= 0.5 }
            rows << row('runouts', Finder.label(u), 'back to the start exactly', same, same ? '' : "#{b} -> #{a}")
          end
        end
        rows
      end

      # --- ceiling + top doors + bridge -------------------------------------------

      def self.suite_ceiling(model)
        rows = []
        units = Runouts.units(model.entities).select { |u| Ceiling.target_mm(u, 1000.0) }
        return [row('ceiling', 'model', '"Up to ceiling" units', true, 'none - skipped')] if units.empty?
        door = Ceiling.top_door_mm
        [2200.0, 2600.0].each do |ceil|
          Ops.throwaway(model, "HW tests: ceiling #{ceil.round} (discarded)") do
            units.each { |u| Ceiling.apply_to(u, ceil) }
            units.each do |u|
              want = Ceiling.target_mm(u, ceil)
              h = Ceiling.height_mm(u)
              errs = formula_errors([u])
              td = Ceiling.top_door_of(u)
              ok = h && (h - want).abs <= 1 && errs.empty? && (td.nil? || (td - door).abs <= 1)
              rows << row('ceiling', Finder.label(u), "ceiling #{ceil.round}", ok,
                          errs.empty? ? "height #{h&.round}#{td ? ", top door #{td.round}" : ''}" : errs.join(', '))
            end
            rows.concat(bridge_rows(model, ceil))
          end
        end
        rows
      end

      def self.bridge_rows(model, ceil)
        out = []
        tb = top_unit(model, 'TOPBOX')
        fr = top_unit(model, 'BRIDGE_FRAME')
        sk = top_unit(model, 'BRIDGE_SKELETON')
        if tb && fr && Ceiling.top_door_of(fr)
          a = part_z(tb, /TPBX_DOOR_TOP/)
          b = part_z(fr, /BRGFR_DOOR/)
          out << row('ceiling', 'TOPBOX + BRIDGE_FRAME', "top doors line up (#{ceil.round})", a && b && a == b, "TOPBOX #{a.inspect}, bridge #{b.inspect}")
        end
        if fr && sk && Ceiling.top_door_of(sk)
          gap = mm(fr.transformation.origin.z - sk.transformation.origin.z).round(1)
          out << row('ceiling', 'BRIDGE_SKELETON', "sits under the frame (#{ceil.round})", (gap - 90).abs <= 0.5, "frame - skeleton = #{gap} mm")
        end
        out
      end

      # --- colours ------------------------------------------------------------------

      def self.suite_colours(model)
        rows = []
        lib = Colours.names
        return [row('colours', 'library', 'colours available', false, 'colour library is empty')] if lib.empty?
        pick = lib.first
        choices = Colours::GROUPS.to_h { |id, _| [id, id == 'drawer_box' ? DrawerBox.names.first : pick] }
        Ops.throwaway(model, 'HW tests: colours (discarded)') do
          counts = Colours.apply(model, choices)
          %w[door exterior interior].each do |g|
            rows << row('colours', g, "paints with #{pick}", counts[g].to_i.positive?, "#{counts[g].to_i} parts")
          end
          plain = Colours.apply(model, Colours.all_default, plain: true)
          rows << row('colours', 'all groups', 'back to Default (no material)', plain.values.sum.positive?, "#{plain.values.sum} parts")
        end
        rows << row('colours', 'library', 'every colour has a name and RGB',
                    Colours.library.all? { |c| !c['name'].to_s.strip.empty? && Array(c['rgb']).size == 3 })
      end

      # --- cut list: OpenCutList set-up ------------------------------------------------

      def self.suite_cutlist(model)
        rows = []
        Ops.throwaway(model, 'HW tests: OpenCutList (discarded)') do
          rep = OpenCutList.setup!(model, overwrite: true)
          plan = OpenCutList.plan(model)
          rows << row('cutlist', 'materials', 'all set after set-up', plan.all? { |r| r['state'] == 'same' }, "#{plan.size} materials, #{rep[:set].size} written")
          parts = OpenCutList.door_parts(model)
          ok = !Settings.get['ocl_doors_bought_in'] || parts.all? { |d| OpenCutList.bought_in?(d) }
          rows << row('cutlist', 'doors / drawer fronts', "tagged #{OpenCutList.tag}", ok, "#{parts.size} parts")
          again = OpenCutList.setup!(model)
          rows << row('cutlist', 'set-up', 'second run changes nothing', again[:set].empty? && again[:tagged].zero?)
        end
        rows
      end

      # --- export (read-only: nothing is saved) -----------------------------------------

      def self.suite_export(model)
        return [row('export', 'model', 'library file', true, 'not a Components file - skipped')] unless LibraryExport.master?(model)
        rows = []
        p = LibraryExport.payload(model)
        rows << row('export', 'model', 'export list builds', !p['rows'].empty?, "#{p['rows'].size} components")
        dup = p['rows'].group_by { |r| r['name'] }.select { |_, v| v.size > 1 }.keys
        rows << row('export', 'model', 'component names unique', dup.empty?, dup.join(', '))
        same = p['rows'].all? do |r|
          inst = model.entities.find { |e| e.entityID == r['id'] }
          inst && LibraryExport.fingerprint(inst) == LibraryExport.fingerprint(inst)
        end
        rows << row('export', 'model', 'change check is stable', same)
        rows
      end

      # --- output -----------------------------------------------------------------

      def self.report_text(rows = run)
        lines = rows.map { |r| "#{r[:ok] ? 'PASS' : 'FAIL'}  [#{r[:suite]}] #{r[:item]} - #{r[:case]}#{r[:detail].empty? ? '' : "  (#{r[:detail]})"}" }
        fails = rows.count { |r| !r[:ok] }
        lines << '' << "#{rows.size - fails} passed, #{fails} failed"
        lines.join("\n")
      end
    end
  end
end
