# HW Door Style - acceptance tests for the door contract.
# Run in SketchUp (Ruby Console) with the plugin loaded:
#   load 'C:/path/to/hw-door-style/tools/acceptance_test.rb'
#   puts HWDoorAcceptance.run_report
#
# Everything happens inside ONE operation that is aborted at the end, so the
# model is left exactly as it was.
require 'json'

module HWDoorAcceptance
  DS = HarryWardrobes::DoorStyle
  MM = 25.4
  TOL = 0.11 # mm

  UNITS = {
    'WARDROBE'     => { width: 'frame_width', double: 'door_double', margin: 2 },
    'WALK-IN'      => { width: 'frame_width', double: 'door_double', margin: 2 },
    'LINEN_PRESS'  => { width: 'frame_width', double: 'door_double', margin: 2 },
    'TOPBOX'       => { width: 'frame_width', double: 'door_double', margin: 2, top: 'door_top_height' },
    'BRIDGE_FRAME' => { width: 'frame_size',  double: 'double',      margin: 2 }
  }.freeze
  SIZES = [[300, 400], [450, 1300], [600, 2300]].freeze

  def self.mm(v) = (v.to_f * MM)
  def self.scale1?(e)
    s, = DS::Finder.decompose(e.transformation)
    s.all? { |v| (v - 1).abs < 0.0005 }
  end

  def self.set(objs, key, value, formula = nil)
    objs.each do |o|
      o.set_attribute('dynamic_attributes', key, value)
      if formula
        o.set_attribute('dynamic_attributes', "_#{key}_formula", formula)
      end
    end
  end

  def self.wrappers_in(unit)
    DS::Repair.candidates(unit.model).select do |i, k|
      k == :door && DS::Repair.top_level(i, unit.model) == unit
    end.map(&:first)
  end

  # Checks one wrapper; returns [ok?, details]
  def self.check(wrapper, thickness_mm)
    fails = []
    w = mm(DS::DC.read(wrapper, 'door_w')); t = mm(DS::DC.read(wrapper, 'door_t')); h = mm(DS::DC.read(wrapper, 'door_h'))
    fails << 'wrapper scale' unless scale1?(wrapper)
    kids = wrapper.definition.entities.grep(Sketchup::ComponentInstance)
    slab = kids.find { |k| k.get_attribute(DS::DICT, 'role') == 'style' }
    if slab.nil?
      fails << 'no slab'
    else
      ss, = DS::Finder.decompose(slab.transformation)
      b = slab.definition.bounds
      sw, sd, sh = [b.width * ss[0], b.height * ss[1], b.depth * ss[2]].map { |v| mm(v) }
      fails << "slab depth #{sd.round(2)}" if (sd - thickness_mm).abs > TOL || (t - thickness_mm).abs > TOL
      fails << "slab W #{sw.round(1)}<>#{w.round(1)}" if (sw - w).abs > TOL
      fails << "slab H #{sh.round(1)}<>#{h.round(1)}" if (sh - h).abs > TOL
      fails << 'slab named STYLE' if slab.definition.name =~ /STYLE_/ || DS::DC.read(slab, '_name').to_s =~ /STYLE_/
    end
    hinges = kids.select { |k| k.get_attribute(DS::DICT, 'role') == 'hinge' }
    inset = [mm(DS::DC.read(wrapper, 'zz_hinge_inset')), h / 4.0].min
    half = mm(DS::DC.read(wrapper, 'zz_hinge_half'))
    hx = mm(DS::DC.read(wrapper, 'zz_hinge_x'))
    n = hinges.size
    hinges.each do |hg|
      fails << 'hinge scale' unless scale1?(hg)
      b = hg.definition.bounds
      size = [b.width, b.height, b.depth].map { |v| mm(v).round(1) }
      fails << "hinge size #{size}" unless size == [35.0, 12.0, 35.0] || size == [35.0, 10.0, 35.0]
      o = hg.transformation.origin
      i = DS::DC.read(hg, 'zz_hinge_i').to_i
      want_z = n <= 1 ? h / 2 - half : inset + i * (h - 2 * inset) / (n - 1) - half
      fails << "hinge#{i} z #{mm(o.z).round(1)}<>#{want_z.round(1)}" if (mm(o.z) - want_z).abs > TOL
      fails << "hinge#{i} y" if (mm(o.y) - t).abs > TOL
      fails << "hinge#{i} x" if (mm(o.x) - hx).abs > TOL
    end
    rule = DS::Settings.hinge_count(h / MM)
    { ok: fails.empty?, w: w.round(1), h: h.round(1), t: t.round(1), hinges: n, rule: rule, fails: fails }
  end

  def self.unit_thickness(unit)
    mm(unit.get_attribute('dynamic_attributes', 'thickness') || unit.definition.get_attribute('dynamic_attributes', 'thickness'))
  end

  def self.run
    model = Sketchup.active_model
    rows = []
    model.start_operation('HW acceptance tests (discarded)', true)
    begin
      UNITS.each do |uname, cfg|
        unit = model.entities.find { |e| e.respond_to?(:definition) && e.definition.name == uname }
        next rows << { unit: uname, case: '-', ok: false, fails: ['unit not found'] } unless unit
        th = unit_thickness(unit)
        [%w[single 0], %w[double 1]].each do |label, dbl|
          SIZES.each do |w, h|
            m = cfg[:margin]
            frame = dbl == '1' ? 2 * w + 3 * m : w + 2 * m
            set([unit, unit.definition], DS::DC.key(unit, cfg[:double]) || cfg[:double], dbl)
            set([unit, unit.definition], DS::DC.key(unit, cfg[:width]) || cfg[:width], frame / MM)
            # Door height: override the wrappers' DOOR_H (what the unit formulas feed).
            wrappers_in(unit).each { |wr| set([wr, wr.definition], 'door_h', h / MM, format('%g', h / 10.0)) }
            DS::DC.redraw(unit)
            wrappers_in(unit).each do |wr|
              r = check(wr, th)
              rows << { unit: uname, door: DS::Finder.label(wr), case: "#{label} #{w}x#{h}" }.merge(r)
            end
          end
        end
      end
      rows << { unit: 'model', case: 'no STYLE_* left', ok: model.definitions.none? { |d| d.name =~ /\ASTYLE_/i } }
    ensure
      model.abort_operation
    end
    second = DS::Repair.run(model)
    rows << { unit: 'model', case: 'Repair 2nd run changes nothing', ok: second[:fixed].empty? && second[:purged].to_i.zero? }
    rows
  end

  def self.run_report
    rows = run
    lines = ['| Unit | Door | Case | DOOR W x H x T | Hinges (rule) | Result |', '|---|---|---|---|---|---|']
    rows.each do |r|
      lines << "| #{r[:unit]} | #{r[:door]} | #{r[:case]} | #{r[:w]} x #{r[:h]} x #{r[:t]} | #{r[:hinges]} (#{r[:rule]}) | #{r[:ok] ? 'PASS' : 'FAIL ' + r[:fails].to_a.join('; ')} |"
    end
    lines.join("\n")
  end
end
