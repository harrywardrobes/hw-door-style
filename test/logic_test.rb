# Offline logic test (no SketchUp needed): ruby test/logic_test.rb
require 'fileutils'
# Stubs just enough of the SketchUp API to exercise settings, measuring,
# shaker panel layout, hinge spacing and the CSV export.

class Numeric
  def mm; self / 25.4; end
end

module Geom
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
    def length; Math.sqrt(x * x + y * y + z * z); end
    def normalize; l = length; Vector3d.new(x / l, y / l, z / l); end
  end
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
  end
  class BoundingBox
    attr_reader :min, :width, :height, :depth
    def initialize(min, w, h, d); @min, @width, @height, @depth = min, w, h, d; end
  end
  class Transformation
    def initialize(a); @a = a; end
    def to_a; @a; end
  end
end

module Sketchup
  class ComponentInstance; end
  class Group; end
  class ModelObserver; end
  class AppObserver; end
  @prefs = {}
  def self.read_default(sec, key, d = nil); @prefs.fetch([sec, key], d); end
  def self.write_default(sec, key, v); @prefs[[sec, key]] = v; end
end

require 'tmpdir'
ENV['APPDATA'] = Dir.mktmpdir('hw_appdata')

$LOAD_PATH.unshift File.expand_path('../src', __dir__)
module HarryWardrobes
  module DoorStyle
    PATH = File.expand_path('../src/hw_door_style', __dir__)
    VERSION = 'test'
    DICT = 'hw_door_style'
  end
end
require 'hw_door_style/core/log'
require 'hw_door_style/core/settings'
require 'hw_door_style/core/dc'
require 'hw_door_style/core/finder'
require 'hw_door_style/core/ops'
require 'hw_door_style/doors/styles'
require 'hw_door_style/job/report'

include HarryWardrobes::DoorStyle
$fail = 0
def check(name, cond)
  puts "#{cond ? 'PASS' : 'FAIL'}  #{name}"
  $fail += 1 unless cond
end
def mm(v); (v * 25.4).round(1); end

# --- settings location (0.12) ---
check 'settings in AppData', Settings::USER_FILE.start_with?(ENV['APPDATA']) && Settings::USER_FILE.end_with?('HW Door Style/settings.json')
check 'legacy file in plugin folder', Settings::LEGACY_FILE == File.join(PATH, 'settings.json')
Dir.mktmpdir do |plug|
  legacy = File.join(plug, 'settings.json')
  File.write(legacy, '{"door_frame_mm": 90}')
  Settings.send(:remove_const, :LEGACY_FILE); Settings.const_set(:LEGACY_FILE, legacy)
  Settings.migrate_location
  check 'old settings copied to AppData once', File.exist?(Settings::USER_FILE) && File.read(Settings::USER_FILE).include?('90')
  File.write(legacy, '{"door_frame_mm": 80}')
  Settings.migrate_location
  check 'AppData copy never overwritten', File.read(Settings::USER_FILE).include?('90')
  check 'loaded from AppData', Settings.load['door_frame_mm'] == 90
  File.delete(Settings::USER_FILE)
end
check 'no team file yet', Settings.team_file.nil?
Settings.team_file = 'G:/My Drive/team.json'
check 'team file remembered', Settings.team_file == 'G:/My Drive/team.json'
Dir.mktmpdir do |d|
  f = File.join(d, 'team.json')
  File.write(f, '{"hw_door_style_settings":"0.12","door_frame_mm":95,"junk":1}')
  t = Settings.read_backup(f)
  check 'team file read (known keys only)', t['door_frame_mm'] == 95 && !t.key?('junk')
end

# --- settings
check 'door frame 100mm', (mm(Settings.mm('door_frame_mm')) == 100.0)
check 'drawer frame 50mm', (mm(Settings.mm('drawer_frame_mm')) == 50.0)
check 'INT_DRW_FRONT is internal', Settings.names('int_drawer_names') == ['INT_DRW_FRONT']
check 'DRW_FRONT is external', Settings.names('ext_drawer_names') == ['DRW_FRONT']
old = { 'ext_drawer_names' => ['XDRW_FRONT'], 'hinge_tag' => 'DOOR', 'colour_groups' => { 'exterior' => ['FACING', 'MY_TAG'] } }
mig = Settings.migrate(old, Settings.defaults)
check 'old settings migrated: drawer names', mig['ext_drawer_names'] == ['DRW_FRONT']
check 'old settings migrated: hinge tag', mig['hinge_tag'] == 'hinges'
check 'old settings migrated: EXT_SH + BOOKCASE added, own tags kept', (%w[EXT_SH BOOKCASE MY_TAG] - mig['colour_groups']['exterior']).empty?
check 'migration runs once', Settings.migrate({ 'settings_version' => 2, 'hinge_tag' => 'X' }, Settings.defaults)['hinge_tag'] == 'X'
check 'hardware tags list', Settings.hardware_tags['shelf_brackets'] == %w[SHELF_BRACKET BKS_SHELF_BRACKET] && Settings.hardware_tags['drawer_rails'] == ['DRW_RUNNER_410']
check 'hinges 2024mm door = 5', Settings.hinge_count(2024.mm) == 5
check 'hinges 1327mm door = 3', Settings.hinge_count(1327.mm) == 3
check 'hinges 396mm door = 2', Settings.hinge_count(396.mm) == 2
check 'PTO detected', Settings.pto?('pto_155') && !Settings.pto?('soft_close_110')

# --- decompose WRD_DOOR transform (scale z 1.042)
t = Geom::Transformation.new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1.042, 0, 10, 20, 30, 1])
scale, axes, origin = Finder.decompose(t)
check 'scale z 1.042', (scale[2] - 1.042).abs < 1e-9
check 'axis normalised', (axes[2].normalize.length - 1).abs < 1e-9
check 'origin kept', origin.x == 10 && origin.z == 30

# --- shaker layout: record recess calls instead of drawing
module HarryWardrobes::DoorStyle::Styles
  class << self
    attr_accessor :calls
    def box(*) ; (@calls ||= []) << [:box]; end
    def recess(_e, x0, z0, x1, z1, d); (@calls ||= []) << [:recess, x0, z0, x1, z1, d]; true; end
  end
end
def layout(w, h, kind)
  Styles.calls = []
  info = Styles.build('shaker', nil, w.mm, 18.mm, h.mm, kind)
  [info, Styles.calls.select { |c| c[0] == :recess }.map { |c| c[1..5].map { |v| mm(v) } }]
end

info, r = layout(400, 2024, :door)
check '2024 door has mid-rail', info[:midrail] && r.size == 2
check 'lower panel 100..765', r[0] == [100.0, 100.0, 300.0, 765.0, 6.0]
check 'upper panel 865..1924', r[1] == [100.0, 865.0, 300.0, 1924.0, 6.0]

info, r = layout(400, 1327, :door)
check '1327 door no mid-rail', !info[:midrail] && r == [[100.0, 100.0, 300.0, 1227.0, 6.0]]

info, r = layout(396, 228, :ext_drawer)
check 'drawer: 100mm stiles (line up with doors), 50mm rails', r == [[100.0, 50.0, 296.0, 178.0, 6.0]]
check 'drawer stile setting 100mm', mm(Settings.mm('drawer_stile_mm')) == 100.0

info, r = layout(400, 210, :door)
check 'tiny door falls back to flat', info[:style] == 'flat' && r.empty? && !info[:note].empty?

# --- csv
rows = [{ 'n' => 1, 'unit' => 'WARDROBE', 'item' => 'WRD_DOOR', 'kind' => 'Door', 'width' => '400', 'height' => '2024',
          'style' => 'Shaker', 'midrail' => 'Yes', 'hinge_type' => 'Soft Close 110', 'hinges' => 5, 'tip_on' => 0,
          'notes' => 'a, "b"' }]
csv = Report.csv(rows)
check 'csv header + row', csv.lines.size == 2 && csv.include?('"a, ""b"""')
t = Report.totals(rows)
check 'totals hinges', t['hinges']['Soft Close 110'] == 5

# --- handles
check 'door 1 handle', Settings.handle_count(:door, 400.mm, false) == 1
check 'PTO door 0 handles', Settings.handle_count(:door, 400.mm, true) == 0
check 'drawer 500 wide = 1', Settings.handle_count(:ext_drawer, 500.mm, false) == 1
check 'drawer 802 wide = 2', Settings.handle_count(:ext_drawer, 802.mm, false) == 2
check 'internal drawer 696 = 2', Settings.handle_count(:int_drawer, 696.mm, false) == 2
rows[0]['handles'] = 1

# --- colours
require 'hw_door_style/colours/colours'
check '13 colours', Colours.names.size == 13 && Colours.names.include?('Stone Grey')
check 'woodgrain textures bundled', Colours.library.select { |c| c['texture'] }.all? { |c| File.exist?(File.join(Colours::TEXTURES, c['texture'])) }
check 'defaults start as Default (box, 22mm panels aside)', Colours.defaults.reject { |k, _| %w[drawer_box panels_22].include?(k) }.values.uniq == ['Default']
check '22mm panels default = Default (Frost White)', Colours.defaults['panels_22'] == 'Default' && Colours.resolve('panels_22', 'Default', 'Cashmere') == 'Frost White'
check 'no separate White colour; Frost White offered on 22mm row', !Colours.names_for('panels_22').include?('White') && Colours.names_for('panels_22').include?('Frost White')
check 'plain (export) strips 22mm colour too', Colours.resolved(nil, { 'panels_22' => 'Default' }, plain: true)['panels_22'] == 'Default'
check 'empty saved library = built-in colours', Colours.library == Colours.builtin && Colours.names.size == 13
check 'texture found in plugin folder', Colours.texture_path('lissa_oak.jpg').to_s.end_with?('lissa_oak.jpg') && Colours.texture_path('nope.jpg').nil?
check '22mm Panels row in the Colours window', Colours::GROUPS.map(&:first).include?('panels_22')
check 'interior group has STL, not HARDWARE', Colours.group_tags['interior'].include?('STL') && !Colours.group_tags.values.flatten.include?('HARDWARE')
check 'Default follows door colour', Colours.resolve('interior', 'Default', 'Cashmere') == 'Cashmere'
check 'manual choice kept', Colours.resolve('worktop', 'Graphite', 'Cashmere') == 'Graphite'
check 'door Default = no material', Colours.resolve('door', 'Default', nil) == 'Default'
check 'others Default with no door = no material', Colours.resolve('exterior', 'Default', 'Default') == 'Default'
check 'hinges on hinges tag', Settings.get['hinge_tag'] == 'hinges'

# --- drawer box
require 'hw_door_style/doors/drawer_box'
check 'Windsor Oak, Light Grey, Graphite Grey', DrawerBox.names == ['Windsor Oak', 'Light Grey', 'Graphite Grey']
check 'Windsor 15mm, Light Grey 16mm', DrawerBox.thickness_mm('Windsor Oak') == 15 && DrawerBox.thickness_mm('Light Grey') == 16 && DrawerBox.thickness_mm('Graphite Grey') == 16
check 'Interfit-Box- material names', DrawerBox.library.map { |b| b['material'] } == ['Interfit-Box-Windsor-Oak', 'Interfit-Box-Light-Grey', 'Interfit-Box-Graphite-Grey']
check 'Windsor texture bundled', File.exist?(File.join(Colours::TEXTURES, DrawerBox.spec('Windsor Oak')['texture']))
check 'drawer box default Windsor Oak', Colours.resolve('drawer_box', 'Default', 'Cashmere') == 'Windsor Oak' && Colours.defaults['drawer_box'] == 'Windsor Oak'
check 'old saved finish falls back to Windsor Oak', DrawerBox.spec('Lugano Oak')['name'] == 'Windsor Oak'
check 'drawer box ignores door colour', Colours.resolve('drawer_box', 'Light Grey', 'Cashmere') == 'Light Grey'
check 'hooks/runners not box parts', !Settings.names('drawer_box_parts').any? { |n| n =~ /HOOK|RUNNER/ }

# --- export naming + versioning
require 'tmpdir'
require 'hw_door_style/job/pdf'
Dir.mktmpdir do |dir|
  check 'first export is v1', Report.next_version(dir, 'Smith Wardrobes') == 1
  check 'stem format', Report.order_stem(1, 'Smith Wardrobes') == 'DOOR_ORDER_v1_Smith Wardrobes'
  File.write(File.join(dir, 'DOOR_ORDER_v1_Smith Wardrobes.csv'), '')
  File.write(File.join(dir, 'DOOR_ORDER_v3_Smith Wardrobes.pdf'), '')
  File.write(File.join(dir, 'DOOR_ORDER_v9_Jones.pdf'), '')
  check 'next after v3 is v4 (other jobs ignored)', Report.next_version(dir, 'Smith Wardrobes') == 4
  check 'model record wins if higher', Report.next_version(dir, 'Smith Wardrobes', 6) == 7

  data = { 'job' => 'Smith Wardrobes', 'hinge_type' => 'Soft Close 110', 'date' => '15/10/2026 11:00',
           'version' => '0.2.0', 'export_version' => 4,
           'rows' => Array.new(45) { |i| rows[0].merge('n' => i + 1, 'unit' => "WARDROBE #{i / 4 + 1} > a very long unit path name that must be cut") } }
  data['totals'] = Report.totals(data['rows'])
  pdf = File.join(dir, 'DOOR_ORDER_v4_Smith Wardrobes.pdf')
  Pdf.write(pdf, data)
  bytes = File.binread(pdf)
  check 'pdf header/footer', bytes.start_with?('%PDF-1.4') && bytes.rstrip.end_with?('%%EOF')
  check 'pdf multi-page', bytes.scan('/Type /Page ').size >= 2
  FileUtils.cp(pdf, ENV['PDF_OUT']) if ENV['PDF_OUT']
end

# --- library export (file names, versions, _old)
require 'tmpdir'
require 'hw_door_style/export/library_export'
LE = LibraryExport
Dir.mktmpdir do |root|
  %w[_old WARDROBES DRAWERS BRIDGE BOOKCASE SHELVING HW\ Colours].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
  { 'WARDROBES' => %w[WRD_V1.skp TOPBOX_V5.skp LINEN_PRESS_V1.skp],
    'DRAWERS' => ['INT_DRAWER_228_V3.skp', 'INT_DRAWER_228_PLUS_V2.skp', 'SHOE_UNIT V2.skp'],
    'BRIDGE' => %w[BRIDGE_FRAME_V5.skp], 'BOOKCASE' => %w[BOOKCASE_4.skp],
    '_old' => %w[BRIDGE_FRAME_V2.skp BRIDGE_FRAME_V4.skp BRIDGE_FRAME.skp INT_DRAWER_228.skp],
    '.' => ['END_PAN.skp', 'Components V16.skp', 'Components V16.skb', 'Components V17.skp'] }.each do |d, fs|
    fs.each { |f| File.write(File.join(root, d, f), 'x') }
  end
  model = Struct.new(:path).new(File.join(root, 'Components V17.skp'))
  check 'export: only in a "Components" file', LE.master?(model) && !LE.master?(Struct.new(:path).new(File.join(root, 'Smith job.skp')))
  check 'export: folders skip _old and HW Colours, add MAIN COMPONENTS', LE.folders(model) == ['BOOKCASE', 'BRIDGE', 'DRAWERS', 'MAIN COMPONENTS', 'SHELVING', 'WARDROBES']
  w = LE.scan(model, 'WARDROBE')
  check 'export: WARDROBE finds WRD_V1 -> next V2', w[:version] == 1 && w[:current].map { |p| File.basename(p) } == ['WRD_V1.skp']
  check 'export: BRIDGE_FRAME next V6 (V5 current, older in _old)', LE.scan(model, 'BRIDGE_FRAME')[:version] == 5
  i = LE.scan(model, 'INT_DRAWER')
  check 'export: INT_DRAWER does not pick up INT_DRAWER_228_PLUS', i[:current].map { |p| File.basename(p) } == ['INT_DRAWER_228_V3.skp']
  check 'export: SHOE_PULL_OUT finds "SHOE_UNIT V2"', LE.scan(model, 'SHOE_PULL_OUT')[:version] == 2
  File.write(File.join(root, 'DRAWERS', 'EXT_DRAWER_228.skp'), 'x')
  check 'export: EXT_DRAWER_228.skp is the old name (V1), not version 228', LE.scan(model, 'EXT_DRAWER')[:version] == 1
  check 'export: BOOKCASE_4 counts as V4', LE.scan(model, 'BOOKCASE')[:version] == 4
  check 'export: loose END_PAN in main folder found (V1)', LE.scan(model, 'END_PAN')[:current].size == 1
  check 'export: brand new component starts at V1', LE.scan(model, 'NEW_THING')[:version].zero?
  check 'export: folder guesses', LE.guess_folder('WALK-IN', LE.folders(model)) == 'WARDROBES' && LE.guess_folder('EXT_DRAWER', LE.folders(model)) == 'DRAWERS' && LE.guess_folder('BULLNOSE', LE.folders(model)) == 'MAIN COMPONENTS'
  moved = LE.move_to_old(model, File.join(root, 'WARDROBES', 'WRD_V1.skp'))
  check 'export: old file moved to _old', File.exist?(moved) && File.dirname(moved) == File.join(root, '_old') && !File.exist?(File.join(root, 'WARDROBES', 'WRD_V1.skp'))
  File.write(File.join(root, 'BRIDGE', 'BRIDGE_FRAME_V2.skp'), 'y')
  m2 = LE.move_to_old(model, File.join(root, 'BRIDGE', 'BRIDGE_FRAME_V2.skp'))
  check 'export: name clash in _old never overwrites', File.basename(m2) =~ /\ABRIDGE_FRAME_V2_moved_\d+_\d+\.skp\z/ && File.read(File.join(root, '_old', 'BRIDGE_FRAME_V2.skp')) == 'x'
  check 'export: next master is Components V18', File.basename(LE.next_master(model)) == 'Components V18.skp'
  check 'export: unsafe characters removed from names', LE.safe('A/B:C') == 'A_B_C'
end

# --- scribe / runout
require 'hw_door_style/core/drawers'
require 'hw_door_style/job/runouts'
require 'hw_door_style/job/ceiling'
require 'hw_door_style/job/standardise'
require 'hw_door_style/job/pencil'
RO = Runouts
ST = Standardise
PN = Pencil
check 'runout dropdown 0/25/50/75/100/150', ST.options_string == '&0mm=0.0' + [25, 50, 75, 100, 150].map { |v| "&#{v}mm=#{v / 25.4}" }.join + '&'
check 'runout defaults 25 all sides', RO.defaults.values.uniq == [25.0] && RO.defaults.keys == %w[floor ceiling left right back]
check 'rename SCRIBE_L key', ST.rename_key('scribe_l') == 'runout_l' && ST.rename_key('_scribe_r_label') == '_runout_r_label' && ST.rename_key('_inst__scribe_l_formula') == '_inst__runout_l_formula'
check 'rename leaves others', ST.rename_key('zz_scribe_l') == 'zz_scribe_l' && ST.rename_key('scribe_1_label') == 'scribe_1_label' && ST.rename_key('_scribe_l_options') == '_runout_l_options'
check 'rename formulas', ST.rename_formula('IF(WALL_LEFT="TRUE", SCRIBE_L, 0)') == 'IF(WALL_LEFT="TRUE", RUNOUT_L, 0)' &&
                         ST.rename_formula('(THICKNESS / 2) + parent!SCRIBE_R') == '(THICKNESS / 2) + parent!RUNOUT_R' &&
                         ST.rename_formula('parent!ZZ_SCRIBE_L') == 'parent!ZZ_SCRIBE_L'
h = { 'j01_runout_floor' => '1', 'runout_ceiling' => '2', 'a01_frame_width' => 3, 'zz_runout_back' => 4 }
check 'prefixed key found', DC.key_in(h, 'runout_floor') == 'j01_runout_floor' && DC.key_in(h, 'frame_width') == 'a01_frame_width'
check 'plain key still found', DC.key_in(h, 'runout_ceiling') == 'runout_ceiling'
check 'no false match (zz_ / partial)', DC.key_in(h, 'runout_back') .nil? && DC.key_in(h, 'width').nil?
check 'unit key match (plain + prefixed)', %w[runout_floor j01_runout_floor j05_runout_back_wall runout_l].all? { |k| RO::UNIT_KEY.match?(k) } &&
                                          %w[zz_runout_l runout_lx _runout_l_label runout_back].none? { |k| RO::UNIT_KEY.match?(k) }
FDict = Struct.new(:h) do
  def each_pair(&b); h.each_pair(&b); end
end
FE = Struct.new(:dd) do
  def attribute_dictionary(_n); dd && FDict.new(dd); end
end
fu = FE.new({ 'j01_runout_floor' => '0.0', 'j03_runout_l' => '0' })
def fu.definition; FE.new({ 'j01_runout_floor' => (25 / 25.4).to_s, 'a01_frame_width' => '20' }); end
check 'instance runout 0 wins over definition 25', RO.any?(fu) == false
fu2 = FE.new(nil)
def fu2.definition; FE.new({ 'j05_runout_back_wall' => (25 / 25.4).to_s }); end
check 'definition runout used when instance has none', RO.any?(fu2) == true
# Fake tree: model > group > [unit A, unit B, 3 hinges sharing one definition]
FDef = Struct.new(:entities, :name)
class FInst < Sketchup::ComponentInstance
  attr_reader :definition, :runout
  attr_accessor :runout
  def initialize(defn, unit, runout = 0.0); @definition, @unit, @runout = defn, unit, runout; end
  def unit; @unit; end
end
class FGroup < Sketchup::Group
  attr_reader :definition
  def initialize(defn); @definition = defn; end
end
$visits = Hash.new(0)
class FEnts < Array
  def each(&b); $visits[object_id] += 1; super; end
end
screw = FEnts.new
hinge_def = FDef.new(FEnts.new([FInst.new(FDef.new(screw, 'SCREW'), false)]), 'HINGE')
ua = FInst.new(FDef.new(FEnts.new, 'A'), true)
ub = FInst.new(FDef.new(FEnts.new, 'B'), true)
hinges = Array.new(3) { FInst.new(hinge_def, false) }
grp = FGroup.new(FDef.new(FEnts.new([ua] + hinges + [ub]), 'G'))
fake_m = Struct.new(:entities).new(FEnts.new([grp]))
def fake_m.get_attribute(*_a); true; end
RO.define_singleton_method(:unit?) { |i| i.unit }
RO.define_singleton_method(:any?) { |u| u.runout > RO::TOL }
check 'units found inside groups', RO.units(fake_m.entities) == [ua, ub]
check 'repeated parts looked into once', $visits[hinge_def.entities.object_id] == 1 && $visits[screw.object_id] == 1
check 'pencil off when every runout is 0', PN.detect(fake_m) == false
ua.runout = 25.0
$visits.clear
check 'pencil on when any runout > 0', PN.detect(fake_m) == true
check 'pencil check stops at first unit with a runout', $visits[hinge_def.entities.object_id].zero?
empty_m = Struct.new(:entities).new(FEnts.new)
def empty_m.get_attribute(*_a); false; end
check 'no units: stored pencil state used', PN.detect(empty_m) == false
PN.invalidate
PN.hold
PN.invalidate
check 'pencil check held during a long job', PN.busy?
module UI; def self.refresh_toolbars; end; end unless defined?(UI)
PN.release
check 'released after the job', !PN.busy?
check '25mm stored as inches string', RO.inch_s(25) == (25 / 25.4).to_s

# --- undo steps (core/ops) and windows (ui/dialog) ---
class FakeModel
  attr_reader :log
  def initialize; @log = []; end
  def start_operation(n, *a); @log << [:start, n, a.last]; end
  def commit_operation; @log << [:commit]; end
  def abort_operation; @log << [:abort]; end
end
fm = FakeModel.new
check 'Ops.run commits and returns the result', Ops.run(fm, 'A') { 42 } == 42 && fm.log == [[:start, 'A', false], [:commit]]
fm = FakeModel.new
err = (Ops.run(fm, 'B') { raise 'boom' } rescue $!)
check 'Ops.run undoes and re-raises on error', err.message == 'boom' && fm.log == [[:start, 'B', false], [:abort]]
fm = FakeModel.new
Ops.run(fm, 'C', transparent: true) { nil }
check 'Ops.run transparent step', fm.log.first == [:start, 'C', true]
fm = FakeModel.new
Ops.throwaway(fm, 'D') { 1 }
check 'Ops.throwaway always undone', fm.log == [[:start, 'D', true], [:abort]]
fm = FakeModel.new
nested = (Ops.throwaway(fm, 'test') { Ops.run(fm, 'inner') { 1 } } rescue $!)
check 'step inside a throwaway refused, outer still undone', nested.is_a?(Ops::NestedStep) && fm.log == [[:start, 'test', true], [:abort]] && !Ops.in_throwaway?
require 'hw_door_style/ui/dialog'
pages = Dir[File.join(PATH, 'html', '*.html')].map { |f| File.basename(f, '.html') }.reject { |n| n == 'hw' }
check 'every window uses the shared look', pages.all? { |n| File.read(File.join(PATH, 'html', "#{n}.html")).include?('<!--HW-->') }
h = Dialog.html('ceiling', { 'ceiling' => 2400, 'note' => 'a\\b $1' })
check 'window gets shared css/js + data', h.include?('--accent') && h.include?('function esc(') && h.include?('"ceiling":2400') && h.include?('$1') && !h.include?('/*DATA*/null')
check 'no window defines its own esc()', pages.none? { |n| File.read(File.join(PATH, 'html', "#{n}.html")) =~ /function esc\(/ }

# --- every setting the code reads is in settings_default.json ---
used = Dir[File.join(PATH, '**', '*.rb')].flat_map do |f|
  File.read(f, encoding: 'UTF-8').scan(/Settings\.(?:get\[|mm\(|names\()'([a-z0-9_]+)'/).flatten
end.uniq
missing = used - Settings.defaults.keys
check "settings keys used in code exist (#{used.size})", missing.empty? || (puts("  missing: #{missing.join(', ')}") || false)

# --- top door height (0.14) ---
check 'top door setting 460', Ceiling.top_door_mm == 460.0
class FDcInst
  attr_reader :attrs, :definition
  def initialize(inst, defn); @attrs = inst; @definition = Struct.new(:dd) { def attribute_dictionary(_n); dd; end }.new(defn); end
  def attribute_dictionary(_n); @attrs; end
  def get_attribute(_d, k); @attrs[k]; end
  def set_attribute(_d, k, v); @attrs[k] = v; end
end
tb = FDcInst.new({ 'b04_door_top_height' => 500 / 25.4 }, { 'b04_door_top_height' => 0.0, 'i05_up_to_ceiling' => 'TRUE' })
check 'top door read (prefixed key)', Ceiling.top_door_of(tb) == 500.0
check 'top door set to 460', Ceiling.set_top_door(tb) && (tb.attrs['b04_door_top_height'] * 25.4 - 460).abs < 0.01
check 'top door already right: no change', !Ceiling.set_top_door(tb)
br = FDcInst.new({ 'b02_door_top_height' => '18.11' }, {})
Ceiling.set_top_door(br)
check 'text value kept as text', br.attrs['b02_door_top_height'].is_a?(String) && (br.attrs['b02_door_top_height'].to_f * 25.4 - 460).abs < 0.01
none = FDcInst.new({ 'a01_frame_width' => 10.0 }, {})
check 'units without a top door untouched', !Ceiling.set_top_door(none) && none.attrs.keys == ['a01_frame_width']

# --- Settings window (0.15) ---
require 'hw_door_style/ui/settings_window'
Settings.save(Settings.get.merge('door_frame_mm' => 90, 'colour_library' => [{ 'name' => 'Mine', 'rgb' => [1, 2, 3] }]))
Settings.reset(keep: ['colour_library'])
check 'reset keeps colour library when asked', Settings.get['door_frame_mm'] == 100 && Settings.get['colour_library'] == [{ 'name' => 'Mine', 'rgb' => [1, 2, 3] }]
Settings.reset
check 'reset all: library back to built-in', Settings.get['colour_library'] == [] && !File.exist?(Settings::USER_FILE)
check 'display keys never saved', SettingsWindow.saveable({ 'a' => 1, '_debug' => true, '_job' => {} }) == { 'a' => 1 }
Dir.mktmpdir do |d|
  f = File.join(d, 'CHANGELOG.md')
  File.write(f, "# Changelog\n\n## 0.2.0 — x\n- **Bold** item\n  continues\n- `code` two\n\n## 0.1.0 — y\nIntro line\n- a\n\n## 0.0.1\n- old\n")
  w = SettingsWindow.whats_new(2, f)
  check "what's new: newest entries, tidy text", w.size == 2 && w[0]['title'] == '0.2.0 — x' && w[0]['items'] == ['Bold item continues', 'code two'] && w[1]['items'] == ['Intro line', 'a']
end
check "what's new reads the real changelog", SettingsWindow.whats_new(1, File.expand_path('../CHANGELOG.md', __dir__)).first['title'].start_with?('0.')

puts $fail.zero? ? "\nAll checks passed" : "\n#{$fail} check(s) FAILED"
exit($fail.zero? ? 0 : 1)
