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
  check 'loaded from AppData, old frame size moved onto Shaker', Settings.load['door_styles'].find { |x| x['id'] == 'shaker' }['door_frame_mm'] == 90 && !Settings.load.key?('door_frame_mm')
  File.delete(Settings::USER_FILE)
end
check 'no team file yet', Settings.team_file.nil?
Settings.team_file = 'G:/My Drive/team.json'
check 'team file remembered', Settings.team_file == 'G:/My Drive/team.json'
Dir.mktmpdir do |d|
  f = File.join(d, 'team.json')
  File.write(f, '{"hw_door_style_settings":"0.12","door_frame_mm":95,"junk":1}')
  t = Settings.read_backup(f)
  check 'team file read (known keys only), old sizes onto Shaker', t['door_styles'].find { |x| x['id'] == 'shaker' }['door_frame_mm'] == 95 && !t.key?('junk') && !t.key?('door_frame_mm')
end

# --- settings
check 'Shaker door frame 100mm', (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['door_frame_mm'] == 100
check 'Shaker drawer rails 50mm, mid-rail 815', (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['drawer_frame_mm'] == 50 && (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['midrail_centre_mm'] == 815
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

check 'choosable styles: Flat and Shaker only (no drawings for the rest yet)', Styles.ids == %w[flat shaker]
check 'Ascot listed, waiting for its drawing', Styles.profile('ascot')['midrail_centre_mm'] == 820 && Styles.missing(Styles.profile('ascot')) == ['no drawing yet'] && !Styles.ready?('ascot')
check 'Avienda handleless', Styles.handleless?('avienda') && !Styles.handleless?('shaker')
check 'not-ready style drawn flat', Styles.build('vienna', nil, 400.mm, 18.mm, 2024.mm, :door)[:style] == 'flat'
sh = Settings.get['door_styles'].find { |x| x['id'] == 'shaker' }
saved = sh.dup
sh['midrail_centre_mm'] = 820
info2, r2 = layout(400, 2024, :door)
check 'mid-rail comes from the style (820 -> lower panel to 770)', r2[0] == [100.0, 100.0, 300.0, 770.0, 6.0]
sh.delete('recess_mm')
check 'style with a size missing cannot be chosen', !Styles.ready?('shaker') && Styles.missing(sh) == ['Recess depth']
sh.replace(saved)
check 'handleless style: no handles', Settings.handle_count(:door, 400.mm, false, handleless: true) == 0
jr = { 'handles_on_pto_doors' => true, 'handles_on_internal_drawers' => false, 'handle_double_min_width_mm' => 900 }
check 'job handle rules', Settings.handle_count(:door, 400.mm, true, rules: jr) == 1 && Settings.handle_count(:int_drawer, 696.mm, false, rules: jr) == 0 && Settings.handle_count(:ext_drawer, 802.mm, false, rules: jr) == 1

info, r = layout(400, 1327, :door)
check '1327 door no mid-rail', !info[:midrail] && r == [[100.0, 100.0, 300.0, 1227.0, 6.0]]

info, r = layout(396, 228, :ext_drawer)
check 'drawer: 100mm stiles (line up with doors), 50mm rails', r == [[100.0, 50.0, 296.0, 178.0, 6.0]]
check 'drawer stile setting 100mm', (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['drawer_stile_mm'] == 100

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
  %w[_old WARDROBES DRAWERS BRIDGE BOOKCASE SHELVING _HW\ Door\ Style].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
  { 'WARDROBES' => %w[WRD_V1.skp TOPBOX_V5.skp LINEN_PRESS_V1.skp],
    'DRAWERS' => ['INT_DRAWER_228_V3.skp', 'INT_DRAWER_228_PLUS_V2.skp', 'SHOE_UNIT V2.skp'],
    'BRIDGE' => %w[BRIDGE_FRAME_V5.skp], 'BOOKCASE' => %w[BOOKCASE_4.skp],
    '_old' => %w[BRIDGE_FRAME_V2.skp BRIDGE_FRAME_V4.skp BRIDGE_FRAME.skp INT_DRAWER_228.skp],
    '.' => ['END_PAN.skp', 'Components V16.skp', 'Components V16.skb', 'Components V17.skp'] }.each do |d, fs|
    fs.each { |f| File.write(File.join(root, d, f), 'x') }
  end
  model = Struct.new(:path).new(File.join(root, 'Components V17.skp'))
  check 'export: only in a "Components" file', LE.master?(model) && !LE.master?(Struct.new(:path).new(File.join(root, 'Smith job.skp')))
  check 'export: folders skip _old and _HW Door Style, add MAIN COMPONENTS', LE.folders(model) == ['BOOKCASE', 'BRIDGE', 'DRAWERS', 'MAIN COMPONENTS', 'SHELVING', 'WARDROBES']
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
check 'every window uses the shared look', pages.all? { |n| File.read(File.join(PATH, 'html', "#{n}.html"), encoding: 'UTF-8').include?('<!--HW-->') }
h = Dialog.html('ceiling', { 'ceiling' => 2400, 'note' => 'a\\b $1' })
check 'window gets shared css/js + data', h.include?('--accent') && h.include?('function esc(') && h.include?('"ceiling":2400') && h.include?('$1') && !h.include?('/*DATA*/null')
check 'no window defines its own esc()', pages.none? { |n| File.read(File.join(PATH, 'html', "#{n}.html"), encoding: 'UTF-8') =~ /function esc\(/ }

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
Settings.save(Settings.get.merge('top_door_height_mm' => 500, 'colour_library' => [{ 'name' => 'Mine', 'rgb' => [1, 2, 3] }]))
Settings.reset(keep: ['colour_library'])
check 'reset keeps colour library when asked', Settings.get['top_door_height_mm'] == 460 && Settings.get['colour_library'] == [{ 'name' => 'Mine', 'rgb' => [1, 2, 3] }]
Settings.reset
check 'reset all: library back to built-in', Settings.get['colour_library'] == [] && !File.exist?(Settings::USER_FILE)
check 'display keys never saved', SettingsWindow.saveable({ 'a' => 1, '_debug' => true, '_job' => {} }) == { 'a' => 1 }
Dir.mktmpdir do |d|
  f = File.join(d, 'CHANGELOG.md')
  File.write(f, "# Changelog\n\n## 0.2.0 — x\n- **Bold** item\n  continues\n  - sub point\n- `code` two\n\n## 0.1.0 — y\nIntro line\n- a\n\n## 0.0.1\n- old\n")
  w = SettingsWindow.whats_new(2, f)
  check "what's new: newest entries, tidy text", w.size == 2 && w[0]['title'] == '0.2.0 — x' && w[0]['items'] == ['Bold item continues', 'sub point', 'code two'] && w[1]['items'] == ['Intro line', 'a']
end
check "what's new reads the real changelog", SettingsWindow.whats_new(1, File.expand_path('../CHANGELOG.md', __dir__)).first['title'].start_with?('0.')

# --- OpenCutList (0.17) ---
require 'hw_door_style/export/opencutlist'
OC = OpenCutList
v22_sizes = '2800 mm x 90 mm;2800 mm x 160 mm;2800 mm x 300 mm;2800 mm x 500 mm;2800 mm x 570 mm;2800 mm x 610 mm;2800 mm x 1000 mm;2800 mm x 2070 mm'
check 'OCL sizes match V22 format', OC.sizes_s(OC.sheet_sizes) == v22_sizes
check 'OCL thicknesses: boards 18/25, Frost White adds 22', OC.thicknesses_s(OC.thicknesses_for('Graphite')) == '18 mm;25 mm' && OC.thicknesses_s(OC.thicknesses_for('Frost White')) == '18 mm;22 mm;25 mm'
check 'OCL list compare ignores order / spaces', OC.same_list?('25mm;18 mm', '18 mm;25 mm') && !OC.same_list?('18 mm', '18 mm;25 mm')
class FMat
  attr_reader :h
  def initialize(h = nil); @h = h; end
  def attribute_dictionary(_n); @h; end
  def set_attribute(_d, k, v); (@h ||= {})[k] = v; end
  def get_attribute(_d, k, dflt = nil); @h&.key?(k) ? @h[k] : dflt; end
end
want = OC.desired
lissa = want['Lissa Oak']
check 'woodgrain colour is grained sheet good', lissa['type'] == 2 && lissa['grained'] == true
check 'drawer boxes and hinges are hardware', want.values_at(*DrawerBox.library.map { |b| b['material'] || b['name'] }, 'HARDWARE').all? { |w| w && w['type'] == 5 }
v22 = FMat.new({ 'type' => 2, 'std_thicknesses' => '18 mm;25 mm', 'std_sizes' => v22_sizes, 'grained' => true })
check 'V22 Lissa Oak already matches', OC.state(v22, lissa) == :same
check 'no OCL settings = missing', OC.state(FMat.new, lissa) == :missing && OC.state(FMat.new({ 'type' => 0 }), lissa) == :missing
check 'own settings = different', OC.state(FMat.new({ 'type' => 2, 'std_thicknesses' => '19 mm', 'std_sizes' => v22_sizes, 'grained' => true }), lissa) == :different
door = FMat.new({ 'tags' => ['mine'] })
check 'bought-in tag added, own tags kept', OC.mark_bought_in(door) && door.h['tags'] == %w[bought-in mine] && !OC.mark_bought_in(door)
old = FMat.new({ 'labels' => 'a;b' })
check 'old OCL "labels" read as tags', OC.tags_of(old) == %w[a b]

# --- updater (0.18) ---
main_src = File.read(File.join(PATH, 'main.rb'), encoding: 'UTF-8')
check 'updater can read the file list from main.rb', main_src[/FILES\s*=\s*%w\[(.*?)\]/m, 1].to_s.split.include?('core/updater')
check 'updater can read VERSION from the loader', File.read(File.expand_path('../src/hw_door_style.rb', __dir__), encoding: 'UTF-8')[/VERSION\s*=\s*'([^']+)'/, 1] =~ /\A\d+\.\d+\.\d+\z/
require 'hw_door_style/core/updater'
check 'version compare', Updater.newer?('0.18.0', '0.17.9') && Updater.newer?('0.18.10', '0.18.9') && !Updater.newer?('0.17.0', '0.17.0')
Dir.mktmpdir do |d|
  %w[hw_door_style_v0.9.0.rbz hw_door_style_v0.18.0.rbz hw_door_style_v0.17.2.rbz other.rbz HW_Colours.zip].each { |f| File.write(File.join(d, f), 'x') }
  File.write(File.join(d, 'hw_door_style_latest.json'), '{"version":"0.18.0","notes":["Updates without restarting"]}')
  r = Updater.latest(d)
  check 'newest release found (not by name order)', r[:version] == '0.18.0' && r[:path].end_with?('hw_door_style_v0.18.0.rbz') && r[:notes] == ['Updates without restarting']
  check 'missing folder: nothing offered', Updater.latest(File.join(d, 'nope')).nil? && Updater.latest('').nil?
end

# --- bottom facing (0.19) ---
require 'hw_door_style/job/facing'
check 'bottom facing default 79', Facing.default_mm == 79.0
fw = FDcInst.new({ 'd01_facing_btm' => (79 / 25.4).to_s }, {})
check 'facing read (prefixed)', Facing.of(fw) == 79.0
check 'facing set keeps text', Facing.set(fw, 100) && fw.attrs['d01_facing_btm'].is_a?(String) && Facing.of(fw) == 100.0 && !Facing.set(fw, 100)
fb = FDcInst.new({ 'facing_btm' => 79 / 25.4 }, {})
check 'facing set keeps number (unprefixed key)', Facing.set(fb, 90) && fb.attrs['facing_btm'].is_a?(Float) && Facing.of(fb) == 90.0
check 'no facing option: untouched', !Facing.set(FDcInst.new({ 'a01_frame_width' => 1.0 }, {}), 90)

# --- folders moved into "_HW Door Style" (0.20) ---
old = { 'settings_version' => 2, 'update_folder' => 'G:\\X\\Harry Wardrobes\\_plugin_updates' }
check 'old updates folder setting moved', Settings.migrate(old, Settings.defaults)['update_folder'].end_with?('_HW Door Style\\Updates')
mine = { 'settings_version' => 2, 'update_folder' => 'D:\\My updates' }
check 'own updates folder kept', Settings.migrate(mine, Settings.defaults)['update_folder'] == 'D:\\My updates'
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, '_HW Door Style', 'Updates'))
  Settings.get['update_folder'] = File.join(d, '_plugin_updates')
  check 'missing _plugin_updates falls back to the new folder', Updater.folder == File.join(d, '_HW Door Style', 'Updates')
  Settings.reload!
end
check 'export skips _HW Door Style', '_HW Door Style' =~ LibraryExport::SKIP_DIRS && 'WARDROBES' !~ LibraryExport::SKIP_DIRS

# --- HubSpot (0.21) ---
require 'net/http'
require 'hw_door_style/export/hubspot'
check 'no key: hint empty', HubSpot.key_hint.nil? && !HubSpot.key?
HubSpot.key = '  pat-eu1-1234567890abcdefWXYZ  '
check 'key trimmed, hint hides the middle', HubSpot.key == 'pat-eu1-1234567890abcdefWXYZ' && HubSpot.key_hint == 'pat-eu1-…WXYZ'
check 'key never in settings', !File.exist?(Settings::USER_FILE) || !File.read(Settings::USER_FILE).include?('pat-eu1')
check 'key not in a settings backup', !JSON.generate(Settings.get).include?('pat-eu1')
check '401 message is plain English', HubSpot.message_for(401, {}).include?('did not accept the key')
HubSpot.key = ''
err = (HubSpot.get('/x') rescue $!)
check 'no key: clear error, no request', err.is_a?(HubSpot::Error) && err.message.include?('No HubSpot key')

# --- HubSpot rooms (0.22) ---
require 'hw_door_style/export/hubspot_room'
R = HubSpotRoom
check 'room part of a Room name', R.room_part("Kenny Hasprey - Connah's Quay - Master Bedroom") == 'Master Bedroom' && R.room_part('Front Room') == 'Front Room'
check 'survey file name like the existing ones', R.file_name('Rebecca Williams - Rossett - Felix', 'Rebecca Williams') == 'SURVEY - felix - rebecca williams.skp'
Dir.mktmpdir do |root|
  %w[WILLIAMS\ Rebecca\ (Rossett\ -\ 830735284436) WOOD\ Lindsey\ (507750999271) OTHER\ (1830735284436)].each { |n| Dir.mkdir(File.join(root, n.delete('\\'))) }
  check 'customer folder: (Town - id)', File.basename(R.customer_folder('830735284436', root).to_s) == 'WILLIAMS Rebecca (Rossett - 830735284436)'
  check 'customer folder: (id)', File.basename(R.customer_folder('507750999271', root).to_s) == 'WOOD Lindsey (507750999271)'
  check 'customer folder: no partial id match', R.customer_folder('35284436', root).nil? && R.customer_folder('', root).nil?
end
opts = [['Alby Blue', 'alby_blue'], ['Ingigo Blue', 'indigo_blue_x'], ['Dark / Onyx Grey', 'dark_onyx_grey'], ['Frost White', 'frost_white']]
check 'colour match: exact, any case', R.match_option('frost white', opts) == 'frost_white' && R.match_option('Alby Blue', opts) == 'alby_blue'
check 'colour match: HubSpot typo still matches', R.match_option('Indigo Blue', opts) == 'indigo_blue_x'
check 'colour match: punctuation ignored', R.match_option('Dark Onyx Grey', opts) == 'dark_onyx_grey'
check 'colour match: unknown -> nil', R.match_option('Sage Green', opts).nil? && R.match_option(nil, opts).nil?
check 'numbers: blank = 0, 2400 = 2400.0', R.same?(0, nil, true) && R.same?(2400, '2400.0', true) && !R.same?(25, '50', true)
check 'drawer type', R.drawer_type(2, 0) == 'External' && R.drawer_type(0, 3) == 'Internal' && R.drawer_type(1, 1).start_with?('Both') && R.drawer_type(0, 0).start_with?('None')
require 'base64'
require 'hw_door_style/export/hubspot_pictures'
P = HubSpotPictures
check 'pictures: default scenes matched any case', P.preset(['room', 'D external', 'D internal', 'S top'], ['d external', 'S TOP', 'Gone']) == ['D external', 'S top']
fm2 = Struct.new(:path).new('H:/x/WILLIAMS Rebecca (Rossett - 1)/SURVEY - felix - rebecca williams.skp')
lk = { 'room_name' => "Rebecca Williams - Rossett - Felix's Room", 'first_name' => 'rebecca anne', 'last_name' => 'Williams' }
check 'pictures: file name', P.file_for(lk, 3, 'jpg') == "Felix's Room - view 3, WILLIAMS Rebecca Anne.jpg"
check 'customer tag: double-barrelled', R.customer_tag('first_name' => 'mary-jane', 'last_name' => 'Muir-Buckley') == 'MUIR-BUCKLEY Mary-Jane'
check 'customer tag: older links (one name)', R.customer_tag('customer' => 'Kenny Hasprey') == 'HASPREY Kenny'
Dir.mktmpdir do |d|
  ["Felix's Room - view 1, WILLIAMS Rebecca Anne.jpg", "Felix's Room - view 4, WILLIAMS Rebecca Anne.png", "Beatrice's Room - view 9, WILLIAMS Rebecca.jpg"].each { |f| File.write(File.join(d, f), '') }
  check 'views carry on from the highest in the folder (this room only)', P.last_view(d, lk) == 4 && P.last_view(File.join(d, 'none'), lk) == 0
end
check 'pictures: saved in SURVEY RENDERS next to the file', P.out_dir(fm2, 'SURVEY RENDERS').end_with?('(Rossett - 1)/SURVEY RENDERS') && P.out_dir(fm2, '').end_with?('(Rossett - 1)')
cfg = P.config
check 'pictures: settings defaults', cfg['rows'].map { |r| r['field'] } == %w[render_1 floor_plan survey_door_dimensions_1] && cfg['width'] == 1920 && cfg['format'] == 'jpg' && cfg['mode'] == 'replace'
check 'required: empty fields listed by label', R.missing(%w[a b c], { 'a' => '1', 'b' => ' ', 'c' => nil }, { 'b' => 'Bed' }) == %w[Bed c]
require 'hw_door_style/core/steps'
module UI; def self.start_timer(*_a, &b); b.call; end; end unless UI.respond_to?(:start_timer)
fd = Struct.new(:js) { def execute_script(x); (self.js ||= []) << x; end; def visible?; true; end }.new
got = nil
Steps.run(fd, [['One', -> { 1 }], ['Two', -> { 2 }]], done: ->(r) { got = r })
check 'steps: run in order, bar shown then hidden', got == [1, 2] && fd.js.first.include?('"text":"One"') && fd.js[1].include?('"done":1') && fd.js.last == 'hwBusy(null)'
err = nil
Steps.run(fd, [['Bad', -> { raise HubSpot::Error, 'nope' }], ['Never', -> { got = :ran }]], fail: ->(e) { err = e.message })
check 'steps: an error stops the rest', err == 'nope' && got == [1, 2]
require 'hw_door_style/doors/hardware' unless defined?(HarryWardrobes::DoorStyle::Hardware)
check 'unit option values: 1 / "1" / TRUE are on; 0 / "0" / blank off', [1, '1', 'TRUE', 1.0].all? { |v| Hardware.truthy?(v) } && [0, '0', '0.0', '', nil, 'FALSE'].none? { |v| Hardware.truthy?(v) }
require 'hw_door_style/core/updater' unless Updater.respond_to?(:read_new_version)
check 'updater reads the installed version and file list', (Updater.read_new_version rescue nil).then { |v, f| v.to_s =~ /\A\d+\.\d+\.\d+\z/ && Array(f).include?('core/updater') }
module Sketchup; class PagesObserver; end; end unless defined?(Sketchup::PagesObserver)
module Sketchup; class AppObserver; end; end unless defined?(Sketchup::AppObserver)
require 'hw_door_style/core/scenes'
Settings.save(Settings.get.merge('hubspot_pictures' => [{ 'field' => 'render_1', 'label' => 'Renders', 'scenes' => ['D external', 'D internal'] }]))
check 'renamed scene renamed in Settings (any case)', Scenes.rename_in_settings([['d external', 'view 1']]) && Settings.get['hubspot_pictures'][0]['scenes'] == ['view 1', 'D internal']
check 'scene not in Settings: nothing saved', !Scenes.rename_in_settings([['room', 'room 2']])
Settings.reset
require 'hw_door_style/export/supplier_import'
SI = SupplierImport
if_html = '<h2 class="container-header">Pull Handles</h2>  <div class="category-main-image 3"></div><ul><li class="product"><article class="listItem"><figure><a href="https://www.interfitco.com/lines/"><img class="listItem-image lazyload" src="https://x/loading.svg" data-src="https://cdn/FTD710BSB.jpg?c=1" alt="FTD710 Lines Pull Handle - Satin Brass"></a></figure><h4 class="listItem-title"><a href="https://www.interfitco.com/lines/">Lines Pull Handle - Satin Brass</a></h4><span data-product-price-without-tax class="price">£12.60</span></article></li></ul>'
it = SI::INTERFIT['items'].call(if_html, 'https://www.interfitco.com/pull-handles/').first
check 'Interfit: name, picture, code guess, group, price', it && it['name'] == 'Lines Pull Handle - Satin Brass' && it['image'] == 'https://cdn/FTD710BSB.jpg?c=1' && it['sku'] == 'FTD710' && it['group'] == 'Pull Handles' && it['price'] == '£12.60'
check 'Interfit: exact SKU from the product page', SI::INTERFIT['sku'].call('var BCData = {"product_attributes":{"sku":"FTD710BSB","upc":null}}') == 'FTD710BSB'
hpp = '<h3 id="5138" class="two-col__heading">Banbury Knob</h3><div class="category__images swiper" data-x="1"><div class="swiper-wrapper"><div class="swiper-slide"><img alt="Brushed Satin Brass" src="/imagehandler/1/a"></div><div class="swiper-slide"><img alt="Chrome" src="/imagehandler/2/b"></div></div><div class="swiper-nav"></div></div>' \
      '<div data-sortdirection="ASC" class="metricGroup" data-nodeid="5138" data-category1="Banbury Handle and Knob"><table><tbody><tr data-productcode="H200.032.CH" class="GridRepeaterBodyRow" title="Banbury Knob &amp; Plate Chrome, 32mm"><td>x</td><td class="GridRepeaterRowMetric" data-metric="Finish">Chrome</td></tr></tbody></table></div>'
h = SI::HPP['items'].call(hpp, 'https://www.hpponline.co.uk/cat/5136/banbury').first
check 'HPP: code, name, picture of the same finish, link to the section', h && h['sku'] == 'H200.032.CH' && h['name'] == 'Banbury Knob & Plate Chrome, 32mm' && h['image'] == 'https://www.hpponline.co.uk/imagehandler/2/b' && h['url'].end_with?('#5138')
h4 = 'var x = "{\"@type\":\"Product\",\"name\":\"Hanover Knob 30mm\",\"offers\":[{\"@type\":\"Offer\",\"price\":4.37,\"url\":\"https:\\\/\\\/handles4u.co.uk\\\/products\\\/A\\\/123\",\"availability\":\"InStock\"}],\"sku\":\"AW821-30-AB\",\"mpn\":\"AW821\",\"image\":\"https:\\\/\\\/handles4u.co.uk\\\/img\\\/AW821.jpg\"}"'
k = SI::HANDLES4U['items'].call(h4, 'https://www.handles4u.co.uk/products/Cabinet+Furniture/Cabinet+Knobs/Brass+Knobs').first
check 'Handles4u: name, SKU, picture, link, price from the page data', k && k['sku'] == 'AW821-30-AB' && k['image'] == 'https://handles4u.co.uk/img/AW821.jpg' && k['url'] == 'https://handles4u.co.uk/products/A/123' && k['price'] == '£4.37' && k['group'] == 'Brass Knobs'
check 'one address per page', SI.same_site('https://a.co/x/', '/x/?page=1') == 'https://a.co/x' && SI.same_site('https://a.co/x/', '/x/?page=2') == 'https://a.co/x?page=2' && SI.same_site('https://a.co/', 'https://b.co/y').nil?

puts "\n== Products: delete"
require 'hw_door_style/export/hubspot_products' unless defined?(HarryWardrobes::DoorStyle::HubSpotProducts)
HPD = HarryWardrobes::DoorStyle::HubSpotProducts
HSD = HarryWardrobes::DoorStyle::HubSpot
calls = []
orig_post = HSD.method(:post)
HSD.define_singleton_method(:post) { |path, body| calls << [path, body]; {} }
keep_file = File.exist?(HPD::FILE) ? File.read(HPD::FILE) : nil
HPD.save_local('products' => (1..103).map { |i| { 'id' => i.to_s, 'name' => "P#{i}" } }, 'options' => {})
n = HPD.delete((1..102).map(&:to_s) + ['5'])
check 'deletes in batches of 100 from HubSpot', calls.size == 2 && calls[0][0] == '/crm/v3/objects/products/batch/archive' && calls[0][1][:inputs].size == 100 && calls[1][1][:inputs].size == 2
check 'and from the local list', n == 102 && HPD.products.map { |p| p['id'] } == ['103']
HSD.define_singleton_method(:post, orig_post)
keep_file ? File.write(HPD::FILE, keep_file) : File.delete(HPD::FILE)

puts "\n== Supplier pictures"
SIP = HarryWardrobes::DoorStyle::SupplierImport
jpg = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\xC8\xFA".b
webp = "RIFF\x10\x00\x00\x00WEBPVP8 \xA0\xB1".b
check 'picture type read from its first bytes', SIP.image_ext(jpg) == '.jpg' && SIP.image_ext(webp) == '.webp' && SIP.image_ext("\x89PNG\r\n".b) == '.png' && SIP.image_ext('<html>').nil?
damaged = jpg.dup.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace) rescue jpg.dup.force_encoding('UTF-8').scrub
check 'a picture damaged into text is spotted', !damaged.b.force_encoding('UTF-8').valid_encoding? == false && jpg.dup.force_encoding('UTF-8').valid_encoding? == false

puts "\n== Parts list + labels (OpenCutList rules)"
require 'hw_door_style/core/formula_parser'
require 'hw_door_style/job/labels'
require 'hw_door_style/job/parts_list' unless defined?(HarryWardrobes::DoorStyle::PartsList.part_order)
LB = HarryWardrobes::DoorStyle::Labels
PLX = HarryWardrobes::DoorStyle::PartsList
check 'label sizes read in mm', LB.mm('102 mm') == 102 && LB.mm('5mm') == 5 && LB.mm('0') == 0 && LB.mm('1"') == 25.4 && LB.mm('2cm') == 20
o = LB.normalise('page_width' => '102 mm', 'page_height' => '76 mm', 'col_count' => 1, 'row_count' => 1, 'layout' => [{ 'formula' => 'part.number', 'size' => '0.75', 'x' => 0.3, 'y' => -0.4 }])
check 'OpenCutList label preset normalised', o['page_width'] == 102 && o['margin_top'] == 10 && o['layout'][0]['size'] == 0.75
dat = LB::Data.new(layer: 'STL', filename: 'Job.skp', batch: LB::Batch.new(2, 6), name: 'WRD_STL')
check 'custom formulas: @layer, @filename.sub, @batch', LB.eval_formula('@layer', dat) == 'STL' && LB.eval_formula("@filename.sub(/\\.skp\\z/i, '')", dat) == 'Job' && LB.eval_formula('@batch', dat) == '2/6'
check 'custom formulas: forbidden commands refused', LB.eval_formula('system("dir")', dat).is_a?(Hash) && LB.eval_formula('File.read("x")', dat).is_a?(Hash) && LB.eval_formula('`dir`', dat).is_a?(Hash)
ea = { 'group_key' => [0, 'graphite', -18.0], 'number' => 'B', 'name' => 'X', 'entity_named_path' => '', 'entity_name' => '', 'position' => 2 }
eb = ea.merge('position' => 1)
ec = ea.merge('number' => 'AA', 'position' => 1)
srt = LB.sort([ec, ea, eb], 'number>name>entity_named_path>entity_name>bin')
check 'labels: AA after B, then position in batch', srt.map { |e| [e['number'], e['position']] } == [['B', 1], ['B', 2], ['AA', 1]]
pa = { 'length' => 2400.0, 'width' => 600.0, 'thickness' => 18.0, 'name' => 'A', 'qty' => 2, 'edge_count' => 1, 'edge_pattern' => '1000', 'tags' => [], 'flipped' => false }
pb = pa.merge('length' => 1200.0)
pc = pa.merge('flipped' => true)
st = '-thickness>-length>-width>-count>name>-edge_pattern>tags>thickness_layer_count'
check 'parts: longest first, mirrored after', [pb, pc, pa].sort { |x, y| PLX.part_order(x, y, st) }.map { |x| [x['length'], x['flipped']] } == [[2400.0, false], [2400.0, true], [1200.0, false]]

puts "\n== Workshop: strips and Room values"
gx = { 'material' => 'Graphite', 'all_sizes' => [[2800.0, 2070.0], [2800.0, 610.0]] }
px = [{ 'number' => 'A', 'length' => 2000.0, 'width' => 90.0, 'qty' => 3 }, { 'number' => 'B', 'length' => 700.0, 'width' => 90.0, 'qty' => 2 }, { 'number' => 'C', 'length' => 2400.0, 'width' => 610.0, 'qty' => 1 }, { 'number' => 'D', 'length' => 900.0, 'width' => 450.0, 'qty' => 4 }]
sx, mx = PLX.strips_for(gx, px + [{ 'number' => 'E', 'length' => 1200.0, 'width' => 460.0, 'qty' => 2 }, { 'number' => 'F', 'length' => 800.0, 'width' => 60.0, 'qty' => 1 }, { 'number' => 'G', 'length' => 900.0, 'width' => 700.0, 'qty' => 1 }])
s90 = sx.find { |x| x['width'] == 90 }
check 'strips: 60mm filler goes in 90, 3x2000 + 2x700 + 800 pack into 3 strips', s90 && s90['count'] == 3 && s90['numbers'] == %w[A B F]
check 'strips: 460 and 450 wide use 500 (next size up)', sx.find { |x| x['width'] == 500 }['numbers'] == %w[D E]
check 'strips: wider than 610 asks for sheets', mx.map { |p| p['number'] } == %w[G]
rv = PLX.room_values('groups' => [{ 'material' => 'Graphite', 'sheets' => 6, 'strips' => sx.reject { |x| x['width'] == 500 } }, { 'material' => 'Graphite', 'sheets' => 1, 'strips' => [] }, { 'material' => 'Frost White', 'sheets' => 2, 'strips' => [] }])
check 'Room: sheets per colour, total, strips per width', rv['mfc_sheets_graphite'] == 7 && rv['mfc_sheets_frost_white'] == 2 && rv['mfc_quantity'] == 9 && rv['cut_and_edged_90mm_quantity'] == 3 && rv['cut_and_edged_300mm_quantity'] == 0

puts "\n== Top of unit"
require 'hw_door_style/core/top_of_unit'
TU = HarryWardrobes::DoorStyle::TopOfUnit
class TUFake
  def initialize(h); @h = h; end
  def get_attribute(_d, k, default = nil); @h.key?(k) ? @h[k] : default; end
end
check 'old switches -> Top of unit', TU.from_old(TUFake.new('i04_topped' => '0', 'i05_up_to_ceiling' => 'TRUE'), 'i04_topped', 'i05_up_to_ceiling') == TU::SCRIBED &&
  TU.from_old(TUFake.new('i04_topped' => '0', 'i05_up_to_ceiling' => 'FALSE'), 'i04_topped', 'i05_up_to_ceiling') == TU::CUSTOM &&
  TU.from_old(TUFake.new('i04_topped' => '1', 'i05_up_to_ceiling' => 'TRUE'), 'i04_topped', 'i05_up_to_ceiling') == TU::NO_FACING
check 'Top of unit options encoded for the DC list', TU.options_s == '&Scribed%20To%20Ceiling=1&Custom%20Scribe%20Height%20%28Lower%20Section%29=2&No%20Upper%20Facing=3&'
class TUDict
  def initialize(keys); @keys = keys; end
  attr_reader :keys
end
check 'Top of unit keys: both switches, one switch, unprefixed', TU.keys_of(TUDict.new(%w[i04_topped i05_up_to_ceiling])) == ['i04_topped', 'i05_up_to_ceiling', 'i04_top_of_unit'] &&
  TU.keys_of(TUDict.new(%w[b02_up_to_ceiling lenx])) == [nil, 'b02_up_to_ceiling', 'b02_top_of_unit'] &&
  TU.keys_of(TUDict.new(%w[topped_off])) == ['topped_off', nil, 'top_of_unit'] && TU.keys_of(TUDict.new(%w[lenx])).nil?
check 'one switch only: two options (no option that does nothing)', TU.choices(nil, 'u').map(&:last) == [1, 2] && TU.choices('t', nil).map(&:last) == [2, 3] && TU.choices('t', 'u').size == 3
check 'one switch only: setting read from it', TU.from_old(TUFake.new('b02_up_to_ceiling' => 'TRUE'), nil, 'b02_up_to_ceiling') == TU::SCRIBED &&
  TU.from_old(TUFake.new('topped' => '1'), 'topped', nil) == TU::NO_FACING && TU.from_old(TUFake.new('topped' => '0'), 'topped', nil) == TU::CUSTOM
class TUDefn
  def initialize(h); @h = h; end
  def get_attribute(_d, k, default = nil); @h.key?(k) ? @h[k] : default; end
end
check 'only switches still showing are upgraded (hidden copies in parts left alone)', TU.shown?(TUDefn.new('_a_access' => 'LIST'), 'a') && !TU.shown?(TUDefn.new('_a_access' => 'NONE'), 'a') && !TU.shown?(TUDefn.new({}), 'a') && !TU.shown?(TUDefn.new({}), nil)
class TUObj
  attr_reader :h, :instances
  def initialize(h, instances = []); @h = h; @instances = instances; end
  def get_attribute(_d, k, default = nil); @h.key?(k) ? @h[k] : default; end
  def set_attribute(_d, k, v); @h[k] = v; end
  def attribute_dictionary(_d); TUDict.new(@h.keys); end
  attr_writer :defn
  def definition; @defn || self; end
end
done_def = { 'i04_topped' => '0', 'i05_up_to_ceiling' => 'TRUE', 'i04_top_of_unit' => '1', '_i04_top_of_unit_access' => 'LIST',
             '_i04_topped_access' => 'NONE', '_i05_up_to_ceiling_access' => 'NONE', '_i04_topped_formula' => 'IF(I04_TOP_OF_UNIT=3, 1, 0)', '_i05_up_to_ceiling_formula' => 'x' }
clean = TUObj.new(done_def.dup, [TUObj.new({})])
check 'upgraded component with clean copies: nothing to do', !TU.needs_upgrade?(clean)
ov_inst = TUObj.new('_i04_topped_access' => 'LIST', '_i05_up_to_ceiling_access' => 'LIST')
ov = TUObj.new(done_def.dup, [ov_inst])
ov_inst.defn = ov
check 'placed copy still showing the old switches (its own _access) is found', TU.needs_upgrade?(ov)
TU.upgrade_definition(ov)
check '... and hidden on the copy', ov_inst.h['_i04_topped_access'] == 'NONE' && ov_inst.h['_i05_up_to_ceiling_access'] == 'NONE' && ov_inst.h['i04_top_of_unit'] == '1'
lost_inst = TUObj.new('i04_top_of_unit' => '2', 'i04_topped' => '1', 'i05_up_to_ceiling' => 'FALSE')
lost = TUObj.new(done_def.merge('_i04_topped_formula' => '', '_i05_up_to_ceiling_formula' => ''), [lost_inst])
TU.upgrade_definition(lost)
check 'old switches that lost their formulas: relinked, dropdown set from how it is drawn', lost.h['_i04_topped_formula'] =~ /I04_TOP_OF_UNIT=3/ && lost_inst.h['i04_top_of_unit'] == '3'
check 'scribe window sends ceiling height apart from the ceiling runout', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/scribe.html')).include?('o.ceiling_height = c')

puts "\n== Component fixes"
require 'hw_door_style/core/component_fixes'
CFX = HarryWardrobes::DoorStyle::ComponentFixes
check 'old formulas matched however they are spaced / quoted', CFX.norm('A02_FRAME_HEIGHT_CEILING - D02_FACING_TOP-ZZ_FLOOR_HEIGHT') == CFX.norm(CFX::FIXES[0][:old]) && CFX.norm('parent!G06_RAIL_DROP ') == CFX.norm('parent!G06_RAIL_DROP')
check 'new formulas differ from old (so a fixed file is left alone)', CFX::FIXES.all? { |f| CFX.norm(f[:new]) != CFX.norm(f[:old]) }

puts "\n== Library cache (Add component)"
require 'hw_door_style/core/library_cache'
LC = HarryWardrobes::DoorStyle::LibraryCache
check 'versions read from file names', LC.parse('WARDROBE_V10') == ['WARDROBE', 10] && LC.parse('SHOE_UNIT V2') == ['SHOE_UNIT', 2] && LC.parse('CAB') == ['CAB', 0] && LC.parse('INT_DRAWER_PLUS_V9') == ['INT_DRAWER_PLUS', 9]
check 'names made readable', LC.pretty('INT_DRAWER_PLUS') == 'Int Drawer Plus' && LC.pretty('WALK-IN') == 'Walk-In' && LC.pretty('MAIN COMPONENTS') == 'Main Components'
lib = Dir.mktmpdir('hw_lib')
{ 'WARDROBES' => %w[WARDROBE_V9.skp WARDROBE_V10.skp TOPBOX_V13.skp desktop.ini], 'DRAWERS' => %w[EXT_DRAWER_V8.skp], '_old' => %w[WARDROBE_V11.skp], 'SURVEY RENDERS' => %w[a.jpg] }.each do |d, fs|
  FileUtils.mkdir_p(File.join(lib, d))
  fs.each { |f| File.write(File.join(lib, d, f), f) }
end
File.write(File.join(lib, 'Components V28.skp'), 'master')
File.write(File.join(lib, 'COVER_WITH_WORKTOP.skp'), 'x')
sc = LC.scan(lib)
check 'scan: latest version of each, _old and the master file skipped', sc.map { |e| [e['key'], e['ver']] }.sort == [['DRAWERS/EXT_DRAWER', 8], ['OTHER/COVER_WITH_WORKTOP', 0], ['WARDROBES/TOPBOX', 13], ['WARDROBES/WARDROBE', 10]]
idx = {}
get, gone = LC.plan(sc, idx)
check 'plan: everything new is copied', get.size == 4 && gone.empty?
get.each { |e| LC.fetch(e, idx) }
check 'fetch: copied to this computer, not the library', idx.values.all? { |e| File.exist?(e['file']) && e['file'].start_with?(LC::DIR) } && File.read(idx['WARDROBES/WARDROBE']['file']) == 'WARDROBE_V10.skp'
get, gone = LC.plan(sc, idx)
check 'plan: nothing to do when up to date', get.empty? && gone.empty?
File.rename(File.join(lib, 'WARDROBES', 'WARDROBE_V10.skp'), File.join(lib, '_old', 'WARDROBE_V10.skp'))
File.write(File.join(lib, 'WARDROBES', 'WARDROBE_V11.skp'), 'WARDROBE_V11.skp')
File.delete(File.join(lib, 'WARDROBES', 'TOPBOX_V13.skp'))
old_file = idx['WARDROBES/WARDROBE']['file']
get, gone = LC.plan(LC.scan(lib), idx)
check 'plan: newer version copied, removed component dropped', get.map { |e| e['key'] } == ['WARDROBES/WARDROBE'] && gone == ['WARDROBES/TOPBOX']
get.each { |e| LC.fetch(e, idx) }
LC.forget(gone, idx)
check 'old copy replaced by the new version', !File.exist?(old_file) && idx['WARDROBES/WARDROBE']['ver'] == 11 && !idx.key?('WARDROBES/TOPBOX')
LC.save_index(idx)
cs = LC.cards
check 'cards: by category order, colour coded', cs.map { |c| c['key'] } == ['WARDROBES/WARDROBE', 'DRAWERS/EXT_DRAWER', 'OTHER/COVER_WITH_WORKTOP'] && cs.first['colour'] == LC::COLOURS['WARDROBES'] && cs.first['label'] == 'Wardrobe'
check 'scan of a missing folder raises (window then uses the copy)', (begin; LC.scan(File.join(lib, 'nope')); false; rescue SystemCallError; true; end)
check 'picker page wired up', %w[sketchup.place sketchup.ready setCards setJob].all? { |w| File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/component_picker.html')).include?(w) }

puts "\n== Job template"
module Sketchup; def self.version; '26.1.189'; end; end
require 'hw_door_style/export/template_export'
TX = HarryWardrobes::DoorStyle::TemplateExport
td = Dir.mktmpdir('hw_tpl')
%w[Harry\ Wardrobes\ Template\ V2.skp Harry\ Wardrobes\ Template\ V10.skp other.skp].each { |f| File.write(File.join(td, f), f) }
check 'template versions read (highest first, others ignored)', TX.versions(td).map(&:first) == [10, 2] && TX.file_name(11) == 'Harry Wardrobes Template V11.skp'
check 'template goes in SketchUp 2026 user Templates folder', TX.user_dir.end_with?(File.join('SketchUp', 'SketchUp 2026', 'SketchUp', 'Templates'))
FileUtils.mkdir_p(TX.user_dir)
File.write(File.join(TX.user_dir, 'Harry Wardrobes Template V2.skp'), 'old')
File.write(File.join(TX.user_dir, 'My own template.skp'), 'mine')
TX.install_local(File.join(td, 'Harry Wardrobes Template V10.skp'))
check 'Welcome copy replaced by the new version, own templates untouched', TX.versions(TX.user_dir).map(&:first) == [10] && File.exist?(File.join(TX.user_dir, 'My own template.skp'))
check 'template keeps floor and ceiling by default', HarryWardrobes::DoorStyle::Settings.names('template_keep') == %w[FLOOR CEILING]

puts "\n== Room"
require 'hw_door_style/job/room'
RM = HarryWardrobes::DoorStyle::Room
check 'file / folder names made safe', RM.safe('Liam Tunney: Chester/1.skp') == 'Liam Tunney Chester1' && RM.safe(' Smith ') == 'Smith'
cf = Dir.mktmpdir('hw_cust')
%w[Old_Customer New_Customer _archive].each { |d| FileUtils.mkdir_p(File.join(cf, d)) }
File.utime(Time.now - 86_400, Time.now - 86_400, File.join(cf, 'Old_Customer'))
check 'customer folders listed newest first, _ folders hidden', RM.customers(cf) == %w[New_Customer Old_Customer]
rh = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/room.html'))
check 'room window sends width, length, ceiling, customer and file', %w[width length ceiling customer file sketchup.apply sketchup.browse sketchup.never].all? { |w| rh.include?(w) }
check 'scribe window sends the room size with the ceiling', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/scribe.html')).include?('o.room_width')

puts $fail.zero? ? "\nAll checks passed" : "\n#{$fail} check(s) FAILED"
exit($fail.zero? ? 0 : 1)
