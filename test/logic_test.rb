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
check 'team file is settings.json in the team folder (shared drive)', Settings.team_file('team_folder' => 'H:/Shared drives/HW/8_SKETCHUP/HW Plugin').tr('\\', '/') == 'H:/Shared drives/HW/8_SKETCHUP/HW Plugin/settings.json' && Settings.defaults['team_folder'].start_with?('H:/Shared drives/Harry Wardrobes/8_SKETCHUP')
check 'reshipped settings replace a saved copy from an older file, others kept', Settings.clean({ 'settings_version' => 13, 'components' => { 'X' => {} }, 'parts_sheet_waste_pct' => 9 }, Settings.defaults) == { 'settings_version' => 13, 'parts_sheet_waste_pct' => 9 } && Settings.clean({ 'settings_version' => 22, 'components' => { 'X' => {} } }, Settings.defaults)['components'] == { 'X' => {} } && !Settings.clean({ 'settings_version' => 21, 'components' => { 'X' => {} } }, Settings.defaults).key?('components')
Dir.mktmpdir do |d|
  f = File.join(d, 'team.json')
  File.write(f, '{"hw_door_style_settings":"0.12","zebra_share":"Z1","parts_sheet_waste_pct":7,"junk":1}')
  t = Settings.read_backup(f)
  check 'backup read: known shared keys only (no computer keys, no junk)', !t.key?('junk') && !t.key?('zebra_share') && t['parts_sheet_waste_pct'] == 7
end
sd = Settings.derive(Settings.defaults)
check 'component table derives the old name lists', sd['door_names'].include?('WST_DOOR') && sd['door_names'].include?('WST_STABLE_PANEL') && sd['fixed_panel_names'] == ['WST_STABLE_PANEL'] && sd['no_midrail_names'] == ['WST_DOOR_UPPER'] && sd['ext_drawer_names'] == ['DRW_FRONT'] && sd['int_drawer_names'] == ['INT_DRW_FRONT'] && sd['framed_drawer_units'] == ['LINEN_PRESS'] && sd['export_skip'].sort == %w[BACK_WALL CEILING FLOOR LEFT_WALL RIGHT_WALL] && sd['template_keep'].sort == %w[BACK_WALL CEILING FLOOR LEFT_WALL RIGHT_WALL] && sd['depth_short_components'].sort == %w[BRIDGE_FRAME BRIDGE_SKELETON BXEND DRAWER_FITTED WORKTOP_KNEE_HOLE] && sd['depth_by_component'] == { 'BOX_SHELF' => 225.0, 'BOOKCASE' => 475.0, 'DRAWER_UNFITTED' => 460.0, 'COVER_WITH_WORKTOP' => 256.0 }
check 'computer keys never go in the team file / backups', (Settings::COMPUTER_KEYS & %w[pdf_printer library_folder local_folder update_folder zebra_share sumatra_path]).size == 6

# --- settings
check 'Shaker door frame 100mm', (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['door_frame_mm'] == 100
check 'Shaker drawer rails 50mm, mid-rail 815', (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['drawer_frame_mm'] == 50 && (Settings.get['door_styles'].find { |x| x['id'] == 'shaker' } || {})['midrail_centre_mm'] == 815
check 'INT_DRW_FRONT is internal', Settings.names('int_drawer_names') == ['INT_DRW_FRONT']
check 'DRW_FRONT is external', Settings.names('ext_drawer_names') == ['DRW_FRONT']
check 'hardware tags list', Settings.hardware_tags['shelf_brackets'] == %w[SHELF_BRACKET] && Settings.hardware_tags['drawer_rails'] == ['DRW_RUNNER_410']
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

  data = { 'job' => 'Smith Wardrobes', 'head' => { 'customer' => 'SMITH, John', 'room' => 'Master Bedroom', 'drawing' => 'X830735284436', 'account' => 'HW123456789' }, 'hinge_type' => 'Soft Close 110', 'date' => '15/10/2026 11:00',
           'version' => '0.2.0', 'export_version' => 4,
           'rows' => Array.new(75) { |i| rows[0].merge('n' => i + 1, 'hand' => i.even? ? 'LH' : 'RH', 'unit' => "WARDROBE #{i / 4 + 1} > a very long unit path name that must be cut") } }
  data['rows'].each_with_index { |r, i| r['hinge_type'] = i % 9 == 0 ? 'Soft Close 155' : (i % 13 == 0 ? 'PTO 110' : 'Soft Close 110') }
  data['rows'].each_with_index { |r, i| r.merge!('kind_id' => i % 5 == 4 ? 'ext_drawer' : 'door', 'kind' => i % 5 == 4 ? 'Drawer front' : 'Wardrobe Door', 'height' => i % 5 == 4 ? '228' : '2024', 'width' => i % 5 == 4 ? '596' : '400', 't' => "T#{i / 4 + 1}", 'stile_mm' => 95, 'rail_mm' => 95, 'midrail_mm' => i % 5 == 4 ? 0 : 815, 'midrail_w' => i % 5 == 4 ? 0 : 100, 'hinges' => i % 5 == 4 ? 0 : 4, 'holes' => i % 5 == 4 ? [] : [100, 708, 1316, 1924], 'handles' => 1) }
  data['totals'] = Report.totals(data['rows'])
  data['hinge_key'] = Report.mark_hinges(data['rows'], 'Soft Close 110')
  data['lines'] = Report.order_lines(data['rows'])
  data['colour'] = 'Super Matt Sage Green'
  check 'order lines: identical fronts on one line with qty and pods; holes read from top then bottom', data['lines'].sum { |l| l['qty'] } == 75 && data['lines'].size < 20 && data['lines'].first['pods'].is_a?(Array) &&
        Report.hole_lines([100, 708, 1316, 1924], 2024) == ['H1: 100 (from top of door)', 'H2: 708 (from top of door)', 'H3: 708 (from bottom of door)', 'H4: 100 (from bottom of door)'] &&
        Report.hole_lines([100, 1012, 1924], 2024) == ['H1: 100 (from top of door)', 'H2: 1012 (from bottom of door)', 'H3: 100 (from bottom of door)']
  check 'odd hinges: usual one plain, others marked * / ** with grey shades', data['hinge_key'].map { |m, t, _s| [m, t] } == [['*', 'Soft Close 155'], ['**', 'PTO 110']] &&
        data['rows'][0]['hinge_mark'] == '*' && data['rows'][1]['hinge_mark'].nil? && Report.mark_hinges([{ 'hinge_type' => 'A' }, { 'hinge_type' => 'A' }]).empty?
  pdf = File.join(dir, 'DOOR_ORDER_v4_Smith Wardrobes.pdf')
  require 'hw_door_style/job/worktop_view'
  module HarryWardrobes; module DoorStyle; module DoorView; def self.title(w, many) = (many ? "Door elevation - #{w['wall']}" : 'Door elevation'); def self.draw_pdf(page, wall, bx, by, bw, bh); page.rect(bx, by, bw, bh, 0.5, 0.3); end; end; end; end unless defined?(HarryWardrobes::DoorStyle::DoorView)
  WV = HarryWardrobes::DoorStyle::WorktopView
  data['vinyl'] = [{ 'title' => '22mm panels (white back)', 'note' => 'white backed', 'cols' => [['#', 26, :left], ['Name', nil, :left], ['Colour', 110, :left], ['Length', 50, :right], ['Width', 50, :right], ['Qty', 30, :right]],
                     'rows' => [[7, 'BKS_SH', 'Frost White', '960', '280', 3]] }]
  data['worktops'] = [{ 'name' => 'WRKTP', 'pod' => 'B1', 'length' => 1200, 'depth' => 518, 'thickness' => 25, 'material' => 'Mussel', 'edges' => { 'front' => true, 'left' => true, 'right' => false, 'back' => false } },
                      { 'name' => 'EXT_DRW_WORKTOP', 'pod' => 'L1', 'length' => 700, 'depth' => 480, 'thickness' => 25, 'material' => 'Mussel', 'edges' => { 'front' => true, 'left' => false, 'right' => false, 'back' => false } }]
  data['elevation'] = [{ 'wall' => 'back wall', 'width' => 1000, 'height' => 2300, 'fronts' => [{ 'u0' => 0, 'u1' => 498, 'z0' => 0, 'z1' => 2300, 'panels' => [] }, { 'u0' => 502, 'u1' => 1000, 'z0' => 0, 'z1' => 2300, 'panels' => [] }], 'dims' => [], 'texts' => [], 'labels' => [] }]
  Pdf.write(pdf, data)
  dtxt = File.binread(pdf).scan(/\((.*?)\) Tj/).flatten.join(' ')
check 'door / vinyl order: FIRST - LAST - DOORS (else DOOR / VINYL ORDER); items by style across; DRILLED LEFT / RIGHT; no hinges / totals blocks, pods or account; HW footer; 22mm panels on a page of their own; elevation and worktop pages',
      dtxt.include?('DOOR / VINYL ORDER') && Pdf.doors_title({ 'first' => 'Rebecca', 'last' => 'Williams' }) == 'REBECCA - WILLIAMS - DOORS' && dtxt.include?('ITEMS BY STYLE') && dtxt.include?('DRILLED LEFT') && dtxt.include?('DRILLED RIGHT') &&
      !dtxt.include?('TOTALS') && !dtxt.include?('Different hinges') && !dtxt.include?('Pods') && !dtxt.include?('Account') && !dtxt.include?('hinge holes') && dtxt.include?('HW 0.2.0') && !dtxt.include?('HW Door Style') &&
      dtxt.include?('Worktop order') && File.binread(pdf).scan('/Type /Page ').size == 5
  bytes = File.binread(pdf)
  check 'pdf header/footer', bytes.start_with?('%PDF-1.4') && bytes.rstrip.end_with?('%%EOF')
  check 'pdf multi-page', bytes.scan('/Type /Page ').size >= 2
  FileUtils.cp(pdf, ENV['PDF_OUT']) if ENV['PDF_OUT']
end

# --- library export (file names, versions, _old)
require 'tmpdir'
require 'hw_door_style/export/library_export'
require 'hw_door_style/job/products'
require 'hw_door_style/core/local'
LE = LibraryExport
Dir.mktmpdir do |root|
  %w[_old WARDROBES DRAWERS BRIDGE BOOKCASE SHELVING _HW\ Door\ Style].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
  { 'WARDROBES' => %w[WARDROBE_V1.skp TOPBOX_V5.skp LINEN_PRESS_V1.skp],
    'DRAWERS' => ['INT_DRAWER_V3.skp', 'INT_DRAWER_PLUS_V2.skp', 'SHOE_PULL_OUT V2.skp'],
    'BRIDGE' => %w[BRIDGE_FRAME_V5.skp], 'BOOKCASE' => %w[BOOKCASE_4.skp],
    '_old' => %w[BRIDGE_FRAME_V2.skp BRIDGE_FRAME_V4.skp BRIDGE_FRAME.skp INT_DRAWER.skp],
    '.' => ['END_PAN.skp', 'Components V16.skp', 'Components V16.skb', 'Components V17.skp'] }.each do |d, fs|
    fs.each { |f| File.write(File.join(root, d, f), 'x') }
  end
  model = Struct.new(:path).new(File.join(root, 'Components V17.skp'))
  check 'export: only in a "Components" file', LE.master?(model) && !LE.master?(Struct.new(:path).new(File.join(root, 'Smith job.skp')))
  check 'export: folders skip _old and _HW Door Style, add the pod folders', LE.folders(model) == ['B - Base units', 'BOOKCASE', 'BRIDGE', 'DRAWERS', 'F - Facings', 'Other', 'SHELVING', 'T - Tall units', 'T - Wardrobe internals', 'W - Wall and bridge units', 'WARDROBES']
  w = LE.scan(model, 'WARDROBE')
  check 'export: WARDROBE finds WARDROBE_V1 -> next V2', w[:version] == 1 && w[:current].map { |p| File.basename(p) } == ['WARDROBE_V1.skp']
  check 'export: BRIDGE_FRAME next V6 (V5 current, older in _old)', LE.scan(model, 'BRIDGE_FRAME')[:version] == 5
  i = LE.scan(model, 'INT_DRAWER')
  check 'export: INT_DRAWER does not pick up INT_DRAWER_PLUS', i[:current].map { |p| File.basename(p) } == ['INT_DRAWER_V3.skp']
  check 'export: SHOE_PULL_OUT finds "SHOE_PULL_OUT V2"', LE.scan(model, 'SHOE_PULL_OUT')[:version] == 2
  check 'export: BOOKCASE_4 counts as V4', LE.scan(model, 'BOOKCASE')[:version] == 4
  check 'export: loose END_PAN in main folder found (V1)', LE.scan(model, 'END_PAN')[:current].size == 1
  check 'export: brand new component starts at V1', LE.scan(model, 'NEW_THING')[:version].zero?
  check 'export: folder from the pod table', LE.folder_for('WALK-IN') == 'T - Tall units' && LE.folder_for('INT_DRAWER_PLUS') == 'T - Wardrobe internals' && LE.folder_for('DRAWER_FITTED') == 'B - Base units' && LE.folder_for('DRAWER_UNFITTED_V3') == 'B - Base units' && LE.folder_for('BOX_SHELF') == 'W - Wall and bridge units' && LE.folder_for('FACING_BLOCK_L_HALF') == 'F - Facings' && LE.folder_for('BULLNOSE') == 'Other' && LE.folder_for('COVER_WITH_WORKTOP') == 'Other'
  Dir.mktmpdir do |loc|
    HarryWardrobes::DoorStyle::Settings.get['local_folder'] = loc
    LOC = HarryWardrobes::DoorStyle::Local
    File.write(File.join(root, 'WARDROBES', 'WARDROBE_V2.skp'), 'v2')
    d1 = LOC.mirror_file(File.join(root, 'WARDROBES', 'WARDROBE_V1.skp'), root)
    d2 = LOC.mirror_file(File.join(root, 'WARDROBES', 'WARDROBE_V2.skp'), root, ['WARDROBE_V1.skp'])
    check 'local mirror: same sub-folder, older version dropped, outside the library ignored', d1 == File.join(loc, 'SketchUp Components', 'WARDROBES', 'WARDROBE_V1.skp') && File.exist?(d2) && !File.exist?(d1) && LOC.mirror_file('/elsewhere/x.skp', root).nil?
    n = LOC.mirror_all(root)
    check 'local mirror: everything current copied, nothing from _old', n > 3 && File.exist?(File.join(loc, 'SketchUp Components', 'Components V17.skp')) && !File.exist?(File.join(loc, 'SketchUp Components', '_old', 'BRIDGE_FRAME_V2.skp')) && !File.exist?(File.join(loc, 'SketchUp Components', 'Components V16.skb'))
    b = LOC.backup_settings('x' => 1)
    check 'settings backup written locally with the mark', b && File.exist?(b) && JSON.parse(File.read(b))[HarryWardrobes::DoorStyle::Settings::BACKUP_MARK] && b.start_with?(File.join(loc, 'Settings backups'))
    HarryWardrobes::DoorStyle::Settings.get.delete('local_folder')
  end
  moved = LE.move_to_old(model, File.join(root, 'WARDROBES', 'WARDROBE_V1.skp'))
  check 'export: old file moved to _old', File.exist?(moved) && File.dirname(moved) == File.join(root, '_old') && !File.exist?(File.join(root, 'WARDROBES', 'WARDROBE_V1.skp'))
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
require 'hw_door_style/job/pencil'
RO = Runouts
PN = Pencil
check 'runout defaults 0 all sides (set by hand per room)', RO.defaults.values.uniq == [0.0] && RO.defaults.keys == %w[floor ceiling left right back]
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
missing = used - Settings.defaults.keys - Settings::DERIVED.keys
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
check 'reset all: library back to built-in', Settings.get['colour_library'] == [] && Settings.get['top_door_height_mm'] == 460
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
  Dir.mktmpdir do |root|
    up = File.join(root, 'Updates'); dev = File.join(root, 'Dev'); Dir.mkdir(up); Dir.mkdir(dev)
    File.write(File.join(up, 'hw_door_style_v0.44.4.rbz'), ''); File.write(File.join(dev, 'hw_door_style_v0.67.5.rbz'), '')
    check 'test builds in Dev beside Updates are offered (and can be turned off)', Updater.latest(up, test_builds: true)[:version] == '0.67.5' && Updater.latest(up, test_builds: true)[:test] &&
          Updater.latest(up, test_builds: false)[:version] == '0.44.4'
  end
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
HSR_M = { 'sheets_order_status' => { 'type' => 'enumeration', 'field' => 'select', 'options' => [['Needs Ordering', 'pending'], ['Not Applicable', 'not_required']] },
           'carpet' => { 'type' => 'bool', 'field' => 'booleancheckbox', 'options' => [['Yes', 'true'], ['No', 'false']] },
           'sides' => { 'type' => 'enumeration', 'field' => 'checkbox', 'options' => [['Left', 'left'], ['Right', 'right']] },
           'notes' => { 'type' => 'string', 'field' => 'text', 'options' => [] } }
check 'HubSpot: labels sent as option values (Needs Ordering -> pending, Yes -> true, checkboxes), others kept',
      HarryWardrobes::DoorStyle::HubSpotRoom.to_values({ 'sheets_order_status' => 'Needs Ordering', 'carpet' => 'Yes', 'sides' => 'Left;right', 'notes' => 'Needs Ordering', 'x' => 'y' }, HSR_M) ==
      { 'sheets_order_status' => 'pending', 'carpet' => 'true', 'sides' => 'left;right', 'notes' => 'Needs Ordering', 'x' => 'y' } &&
      HarryWardrobes::DoorStyle::HubSpotRoom.to_values({ 'sheets_order_status' => 'not_required' }, HSR_M) == { 'sheets_order_status' => 'not_required' }
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
require 'hw_door_style/job/labels'
require 'hw_door_style/job/parts_list' unless defined?(HarryWardrobes::DoorStyle::PartsList.part_order)
LB = HarryWardrobes::DoorStyle::Labels
PLX = HarryWardrobes::DoorStyle::PartsList
check 'label sizes read in mm', LB.mm('102 mm') == 102 && LB.mm('5mm') == 5 && LB.mm('0') == 0 && LB.mm('1"') == 25.4 && LB.mm('2cm') == 20
o = LB.normalise('page_width' => '102 mm', 'page_height' => '76 mm', 'col_count' => 1, 'row_count' => 1, 'layout' => [{ 'formula' => 'part.number', 'size' => '0.75', 'x' => 0.3, 'y' => -0.4 }])
check 'OpenCutList label preset normalised', o['page_width'] == 102 && o['margin_top'] == 10 && o['layout'][0]['size'] == 0.75
check 'custom (Ruby) label formulas are never run', LB.eval_formula('system("dir")', nil).is_a?(Hash) && LB.eval_formula('@layer', nil).is_a?(Hash) && !File.exist?(File.join(HarryWardrobes::DoorStyle::PATH, 'core/formula_parser.rb'))
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
IgnDef = Struct.new(:path)
IgnEnt = Struct.new(:layer, :definition)
IgnLay = Struct.new(:name)
sock = IgnEnt.new(IgnLay.new('Untagged'), IgnDef.new('G:\\My Drive\\1_Gautier Design Ltd\\4_Assets\\SketchUp Components\\Electrical Faceplates\\Double UK 3 Pin Power Socket.skp'))
plate = IgnEnt.new(IgnLay.new('Sockets Switches and Plugs'), IgnDef.new(''))
hinge = IgnEnt.new(IgnLay.new('HARDWARE'), IgnDef.new('G:\\My Drive\\1_Gautier Design Ltd\\4_Assets\\SketchUp Components\\Harry Wardrobes\\Components V36.skp'))
check 'electrical faceplates ignored by library folder and by tag, hardware kept', PLX.ignored?([sock]) && PLX.ignored?([hinge, plate]) && !PLX.ignored?([hinge])

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
  def initialize(h, d = {}); @h = h; @d = d; end
  def definition; self; end
  def get_attribute(_d, k, default = nil); @h.key?(k) ? @h[k] : (@d.key?(k) ? @d[k] : default); end
end
check 'Top of unit read from the dropdown (instance, else definition; none = nil)', TU.choice(TUFake.new('i04_top_of_unit' => '3')) == TU::NO_FACING &&
  TU.choice(TUFake.new({}, 'i04_top_of_unit' => 1.0)) == TU::SCRIBED && TU.choice(TUFake.new({})).nil? && TU.label(TU::CUSTOM) == 'Custom Scribe Height (Lower Section)'
check 'scribe window sends ceiling height apart from the ceiling runout', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/scribe.html')).include?('o.ceiling_height = c')

puts "\n== Library cache (Add component)"
require 'hw_door_style/core/library_cache'
require 'hw_door_style/job/products' unless defined?(HarryWardrobes::DoorStyle::Products)
LC = HarryWardrobes::DoorStyle::LibraryCache
check 'versions read from file names', LC.parse('WARDROBE_V10') == ['WARDROBE', 10] && LC.parse('SHOE_UNIT V2') == ['SHOE_UNIT', 2] && LC.parse('CAB') == ['CAB', 0] && LC.parse('INT_DRAWER_PLUS_V9') == ['INT_DRAWER_PLUS', 9]
check 'names made readable', LC.pretty('INT_DRAWER_PLUS') == 'Int Drawer Plus' && LC.pretty('WALK-IN') == 'Walk-In' && LC.pretty('MAIN COMPONENTS') == 'Main Components'
check 'mixed-case names kept; Electrical Faceplates is a plain category after Main Components', LC.pretty('Double UK 3 Pin Power Socket') == 'Double UK 3 Pin Power Socket' && LC.plain?('ELECTRICAL FACEPLATES') && !LC.plain?('WARDROBES') && LC.cat_order('ELECTRICAL FACEPLATES') > LC.cat_order('F')
lib = Dir.mktmpdir('hw_lib')
{ 'WARDROBES' => %w[WARDROBE_V9.skp WARDROBE_V10.skp TOPBOX_V13.skp desktop.ini], 'DRAWERS' => %w[DRAWER_FITTED_V8.skp], '_old' => %w[WARDROBE_V11.skp], 'SURVEY RENDERS' => %w[a.jpg] }.each do |d, fs|
  FileUtils.mkdir_p(File.join(lib, d))
  fs.each { |f| File.write(File.join(lib, d, f), f) }
end
File.write(File.join(lib, 'Components V28.skp'), 'master')
File.write(File.join(lib, 'COVER_WITH_WORKTOP.skp'), 'x')
sc = LC.scan(lib)
check 'scan: latest version of each, _old and the master file skipped', sc.map { |e| [e['key'], e['ver']] }.sort == [['DRAWERS/DRAWER_FITTED', 8], ['OTHER/COVER_WITH_WORKTOP', 0], ['WARDROBES/TOPBOX', 13], ['WARDROBES/WARDROBE', 10]]
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
check 'cards: grouped by pod letter (T, B, then Other), colour coded', cs.map { |c| [c['key'], c['cat']] } == [['WARDROBES/WARDROBE', 'T'], ['DRAWERS/DRAWER_FITTED', 'B'], ['OTHER/COVER_WITH_WORKTOP', 'OTHER']] && cs.first['colour'] == LC::COLOURS['T'] && cs.first['label'] == 'Wardrobe' && cs.first['cat_label'] == 'T - Tall units'
check 'groups: internals under T - Wardrobe internals, box shelf W', LC.group('cat' => 'DRAWERS', 'name' => 'INT_DRAWER_PLUS') == LC::INTERNALS && LC.group('cat' => 'DRAWERS', 'name' => 'SHOE_PULL_OUT') == LC::INTERNALS && LC.group_label(LC::INTERNALS) == 'T - Wardrobe internals' && LC.group('cat' => 'SHELVING', 'name' => 'BOX_SHELF') == 'W' && LC.group('cat' => 'DRAWERS', 'name' => 'DRAWER_FITTED') == 'B'
check 'groups: bridge W, worktop B, facings F, bullnose Other, faceplates their own', LC.group('cat' => 'BRIDGE', 'name' => 'BRIDGE_FRAME') == 'W' && LC.group('cat' => 'MAIN COMPONENTS', 'name' => 'WORKTOP_KNEE_HOLE') == 'B' && LC.group('cat' => 'MAIN COMPONENTS', 'name' => 'FACING_BLOCK_L') == 'F' && LC.group('cat' => 'MAIN COMPONENTS', 'name' => 'BULLNOSE') == 'OTHER' && LC.group('cat' => 'ELECTRICAL FACEPLATES', 'name' => 'Phone socket') == 'ELECTRICAL FACEPLATES'
check 'scan of a missing folder raises (window then uses the copy)', (begin; LC.scan(File.join(lib, 'nope')); false; rescue SystemCallError; true; end)
sh = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/settings.html'))
check 'settings page: 7 tabs, General first, component table, no products editor', sh.scan(/<a data-s="(\w+)"/).flatten == %w[general components doors colours job workshop hubspot] && sh.include?('pcTable') && !sh.include?('prodDraw') && !sh.include?('product_types') && !sh.include?('door_names')
sc = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/scribe.html'))
check 'drawer front height: pencil field, job default 228, module loaded with the plugin', sc.include?('id="front"') && sc.include?('o.front') && HarryWardrobes::DoorStyle::Settings.defaults['drawer_front_mm'] == 228 && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'main.rb')).include?('job/drawer_front')
check 'room settings: small drawer fronts row, room icon, pencil is on/off', sc.include?('id="small"') && File.exist?(File.join(HarryWardrobes::DoorStyle::PATH, 'icons/room.svg')) && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'ui/menus.rb')).include?(':pencil, :room') && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job/pencil.rb')).include?('Runouts.all_on(model)') && HarryWardrobes::DoorStyle::Settings.defaults['drawer_front_sm_mm'] == 142
check 'new rooms: every runout 0 by default; workshop blocks on unset runouts', !HarryWardrobes::DoorStyle::Settings.defaults.key?('runout_defaults_mm') && !File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/settings.html')).include?('rd_floor') && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job/workshop.rb')).include?('Runouts not set') && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job/workshop.rb')).include?("when 'runouts', 'ceiling'")
check 'products and setup pages wired up', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/products.html')).include?('sketchup.prodSave') && %w[sketchup.fix sketchup.finish setChecks].all? { |w| File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/setup.html')).include?(w) }
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
check 'template keeps the room parts (floor, ceiling, walls) by default', HarryWardrobes::DoorStyle::Settings.names('template_keep').sort == %w[BACK_WALL CEILING FLOOR LEFT_WALL RIGHT_WALL]

puts "\n== Room"
require 'hw_door_style/job/room'
RM = HarryWardrobes::DoorStyle::Room
check 'file / folder names made safe', RM.safe('Liam Tunney: Chester/1.skp') == 'Liam Tunney Chester1' && RM.safe(' Smith ') == 'Smith'
cf = Dir.mktmpdir('hw_cust')
FileUtils.mkdir_p(File.join(cf, 'WILLIAMS Rebecca (Rossett - 830735284436)'))
pick = { 'contact_id' => '830735284436', 'first_name' => 'Rebecca', 'last_name' => 'Williams' }
check 'template room defaults 4000 x 3000, ceiling 2400 (Settings room_default_mm)', RM.default_mm == { 'width' => 4000.0, 'length' => 3000.0, 'ceiling' => 2400.0 }
check 'customer folder found by contact ID, else named SURNAME First (id)', RM.folder_for(pick, cf) == { 'folder' => File.join(cf, 'WILLIAMS Rebecca (Rossett - 830735284436)'), 'name' => 'WILLIAMS Rebecca (Rossett - 830735284436)', 'exists' => true } &&
  RM.folder_for({ 'contact_id' => '1', 'first_name' => 'John', 'last_name' => 'Smith' }, cf) == { 'folder' => File.join(cf, 'SMITH John (1)'), 'name' => 'SMITH John (1)', 'exists' => false }
rh = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/room.html'))
check 'room window: HubSpot customer search, room pick, folder (manual link), file name', %w[width length ceiling sketchup.search sketchup.project sketchup.pickFolder sketchup.apply sketchup.browse sketchup.never sketchup.openExisting select\ folder\ manually].all? { |w| rh.include?(w.tr('\\', '')) }
check 'scribe window sends the room size with the ceiling', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/scribe.html')).include?('o.room_width')

puts "\n== Product list"
require 'hw_door_style/job/products'
PR = HarryWardrobes::DoorStyle::Products
pcc = { 'WARDROBE' => %w[Wardrobe unit T], 'INT_DRAWER' => ['Internal drawers', 'internal', 'T'], 'INT_DRAWER_PLUS' => ['Internal drawers+', 'internal', 'T'], 'BRIDGE_SKELETON' => ['Bridge unit', 'unit', 'W'], 'BOX_SHELF' => ['Box shelves', 'joiner', 'W'], 'EXT_DRAWER' => ['Drawer unit', 'unit', 'B'], 'FACING_BLOCK' => ['Facing', 'skip', ''], 'BULLNOSE' => ['Bullnose', 'skip', ''] }.to_h { |k, (pn, r, l)| [k, { 'product' => pn, 'role' => r, 'letter' => l }] }
pc = { 'comps' => pcc, 'keys' => pcc.keys.sort_by { |x| -x.size } }
check 'product types: exact, longer names, longest match wins', PR.type_of('WARDROBE', pc) == 'Wardrobe' && PR.type_of('WARDROBE_LEFT', pc) == 'Wardrobe' && PR.type_of('INT_DRAWER_PLUS', pc) == 'Internal drawers+' && PR.type_of('FLOOR', pc).nil? && PR.type_of('BULLNOSE', pc).nil?
check 'roles: unit, joiner / internal, skipped', PR.unit?('WARDROBE', pc) && PR.joiner?('INT_DRAWER_PLUS', pc) && PR.internal?('INT_DRAWER_PLUS', pc) && PR.joiner?('BOX_SHELF', pc) && !PR.internal?('BOX_SHELF', pc) && !PR.joiner?('WARDROBE', pc) && PR.skip?('FACING_BLOCK_L_HALF', pc) && PR.skip?('BULLNOSE', pc) && !PR.skip?('WARDROBE', pc) && PR.role('NOT_LISTED', pc).nil?
check 'Workshop has the Product List first', File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/parts_list.html'), encoding: 'UTF-8') =~ /data-t="products" class="on">Product List/

puts "\n== Depth"
require 'hw_door_style/job/depth'
DPT = HarryWardrobes::DoorStyle::Depth
check 'Depth option names: wardrobe c01_depth and the others a03_wall_depth', %w[c01_depth a03_wall_depth].all? { |k| k =~ DPT::KEY_RE } && !('c01_depth_fl_div' =~ DPT::KEY_RE) && !('a04_depth_finished' =~ DPT::KEY_RE)

puts "\n== Room Plan"
check 'reference letters: W bridge, B drawers, W box shelves, T otherwise', PR.ref_of('BRIDGE_SKELETON', pc) == 'W' && PR.ref_of('EXT_DRAWER_3', pc) == 'B' && PR.ref_of('BOX_SHELF', pc) == 'W' && PR.ref_of('WARDROBE', pc) == 'T'
check 'shipped table: box shelf W, ext drawer B, letters T W B F, internals, skips, ceiling never exported', PR.ref_of('BOX_SHELF') == 'W' && PR.ref_of('DRAWER_FITTED') == 'B' && PR.ref_of('DRAWER_UNFITTED') == 'B' && PR.type_of('DRAWER_UNFITTED') == 'Drawer unit' && PR.role('EXT_DRAWER').nil? && PR.role('DRAWER_GROUP').nil? && PR.order == %w[T W B F] && PR.internal?('SHOE_PULL_OUT') && PR.internal?('INT_DRAWER_PLUS') && PR.joiner?('INT_DRAWER') && !PR.internal?('BOX_SHELF') && PR.role('CAB').nil? && PR.skip?('COVER_WITH_WORKTOP') && PR.skip?('END_PAN_HALF') && PR.skip?('CABLE_OUTLET_80') && PR.cfg['comps'].values.all? { |r| PR::ROLES.key?(r['role']) } && HarryWardrobes::DoorStyle::Settings.names('export_skip').include?('CEILING')
require 'hw_door_style/job/pdf'
require 'hw_door_style/job/parts_pdf'
require 'hw_door_style/job/room_plan'
RP = HarryWardrobes::DoorStyle::RoomPlan
module HarryWardrobes; module DoorStyle; module PartsList; def self.fmt(v) = (v.to_f == v.to_f.round ? v.to_f.round.to_s : v.to_s); end; VERSION = 'test' unless const_defined?(:VERSION); end; end
doors = [{ 'kind_id' => 'door', 'style' => 'Shaker', 'height' => '2300', 'hinge_type' => 'Soft Close 155', 'hand' => 'LH', 'top_id' => 1, 'kind' => 'Door', 'item' => 'D1', 'width' => '500' },
         { 'kind_id' => 'door', 'style' => 'Shaker', 'height' => '2300', 'hinge_type' => 'Soft Close 155', 'hand' => 'RH', 'top_id' => 1, 'kind' => 'Door', 'item' => 'D2', 'width' => '500' },
         { 'kind_id' => 'int_drawer', 'top_id' => 1, 'kind' => 'Internal drawer', 'item' => 'ID', 'style' => 'Flat', 'width' => '400', 'height' => '150' }]
parts = { 'groups' => [{ 'material' => 'Frost White MFC', 'thickness' => 18, 'section' => 'sheets', 'parts' => [
            { 'number' => 'A', 'name' => 'SHELF', 'length' => 960, 'width' => 560, 'thickness' => 18, 'qty' => 3, 'instances' => [{ 'top' => 1 }] * 3 },
            { 'number' => 'B', 'name' => 'FACING_72', 'length' => 2300, 'width' => 72, 'thickness' => 18, 'qty' => 1, 'instances' => [{ 'top' => 2 }] }] },
          { 'material' => 'MDF 25', 'thickness' => 25, 'section' => 'sheets', 'parts' => [{ 'number' => 'C', 'name' => 'MDF_25_L', 'length' => 2300, 'width' => 25, 'thickness' => 25, 'qty' => 1, 'instances' => [{ 'top' => 1 }] }] },
          { 'material' => 'Oak worktop', 'thickness' => 25, 'section' => 'worktops', 'parts' => [{ 'number' => 'D', 'name' => 'WRKTP', 'length' => 1200, 'width' => 500, 'thickness' => 25, 'qty' => 1, 'instances' => [{ 'top' => 2 }] }] }],
          'hardware' => [{ 'number' => 'H1', 'name' => 'HANGING_RAIL', 'material' => 'HARDWARE', 'instances' => [{ 'top' => 1 }] }] }
tops = { 1 => 'T1', 2 => 'B1' }
info = RP.by_ref(parts, doors, tops)
check 'room plan: doors per ref with hands and 155 flagged', RP.door_text(info['T1']['doors']) == '2 x Shaker 2300 high (LH + RH) - 155 HINGES'
check 'room plan: interior summary', RP.interior_text(info['T1']) == '3 shelves, 1 hanging rail, 1 internal drawer'
rows = [{ 't' => 'T1', 'ref' => 'T', 'num' => 1, 'type' => 'Wardrobe', 'size' => [1000, 598, 2400], 'depth' => 580, 'finished' => 598 },
        { 't' => 'B1', 'ref' => 'B', 'num' => 1, 'type' => 'Worktop', 'size' => [1200, 518, 771], 'depth' => 500, 'finished' => 518 }]
check 'PDF customer: SURNAME, First names', RP.customer_name('Rebecca Jane', 'Williams') == 'WILLIAMS, Rebecca Jane' && RP.customer_name('', 'Smith') == 'SMITH'
check 'room plan: unit description', RP.describe(rows[0]) == '1000 Wardrobe (580 deep / 598 overall)'
hd = { 'customer' => 'WILLIAMS, Rebecca', 'room' => 'Master Bedroom', 'drawing' => 'X830735284436', 'account' => 'HW123456789', 'fit_week' => 'Week 44' }
doc = RP::Doc.new(hd); doc.start
RP.product_page(doc, rows, info)
land = HarryWardrobes::DoorStyle::Pdf::Page.new; land.text(30, 30, 'landscape'); doc.pages << land
pdf = HarryWardrobes::DoorStyle::Pdf.document(doc.pages.map(&:to_s), sizes: [nil, [842, 595]])
File.binwrite(File.join(Dir.tmpdir, 'room_plan_test.pdf'), pdf)
check 'room plan: product list renders; a landscape last page; no panel list', doc.pages.size == 2 && pdf.start_with?('%PDF') && pdf.include?('/MediaBox [0 0 842 595]') && pdf.include?('/MediaBox [0 0 595 842]') && !RP.respond_to?(:panel_page)

PPDF = HarryWardrobes::DoorStyle::PartsPdf
pd = { 'list_version' => 3, 'version' => 'test', 'head' => hd, 'scribes_on' => true, 'waste_pct' => 20, 'handles' => [], 'drawer_boxes' => [{ 'number' => 'DB', 'parent' => 'DRAWER_FITTED', 'material' => 'Interfit-Box-Light-Grey', 'width' => 664, 'height' => 150, 'runner' => '410mm Hook/Peg', 'qty' => 3 }],
       'timber_lines' => [{ 'numbers' => ['9'], 'name' => '2X1', 'material' => 'Timber 2x1', 'section' => '21 x 44', 'length' => 2400, 'qty' => 2 }], 'hardware_lines' => [{ 'numbers' => ['H1'], 'name' => 'Hinges 110° soft close', 'qty' => 12 }, { 'numbers' => ['H2'], 'name' => 'Shelf brackets', 'qty' => 8 }],
       'groups' => [{ 'material' => 'Light Grey', 'thickness' => 18, 'section' => 'sheets', 'strip_group' => true, 'count' => 6, 'sheets' => nil, 'sheet' => [2800, 2070], 'strips' => [{ 'width' => 90, 'length' => 2800, 'count' => 1 }, { 'width' => 300, 'length' => 2800, 'count' => 2 }],
                     'parts' => [{ 'number' => 1, 'name' => 'FACING', 'length' => 2300, 'width' => 72, 'qty' => 2, 'strip_width' => 90, 'edges' => {} }, { 'number' => 2, 'name' => 'SHELF', 'length' => 900, 'width' => 280, 'qty' => 3, 'strip_width' => 300, 'edges' => {} }, { 'number' => 3, 'name' => 'BIG', 'length' => 2000, 'width' => 900, 'qty' => 1, 'strip_width' => nil, 'edges' => {} }] },
                    { 'material' => 'Oak worktop', 'thickness' => 25, 'section' => 'worktops', 'count' => 1, 'parts' => [{ 'number' => 4, 'name' => 'WRKTP', 'length' => 1200, 'width' => 518, 'qty' => 1, 'edges' => {} }] }] }
ppdf = HarryWardrobes::DoorStyle::Pdf.document(PPDF.layout(pd))
File.binwrite(File.join(Dir.tmpdir, 'parts_list_test.pdf'), ppdf)
pptxt = ppdf.scan(/\((.*?)\) Tj/).flatten.join(' ')
check 'parts list: boards, then Hardware, then drawer boxes; no TIMBER heading; 18mm by strip width; no boards / edging / worktops; no ? after the hinges', !pptxt.include?('TIMBER') && pptxt.include?('Hardware') && pptxt.index('Hardware') < pptxt.index('Drawer boxes') && pptxt.index('Full sheet') < pptxt.index('Hardware') && pptxt.index('90 mm strips') < pptxt.index('300 mm strips') && pptxt.index('300 mm strips') < pptxt.index('Full sheet') && !pptxt.include?('WRKTP') && !pptxt.include?('Boards') && !pptxt.include?('Edging') && pptxt.include?('Hinges 110 soft close') && !pptxt.include?('110?') && pptxt.include?('410mm Hook/Peg')
FileUtils.cp(File.join(Dir.tmpdir, 'parts_list_test.pdf'), ENV['PARTS_OUT']) if ENV['PARTS_OUT']

puts "\n== Mid-rail line"
require 'hw_door_style/job/midrail'
MR = HarryWardrobes::DoorStyle::Midrail
check 'mid-rail option names (stable wardrobe and linen press)', %w[b06_midrail_centre b07_midrail_width h07_midrail_centre h08_midrail_width].all? { |k| k =~ MR::KEY_RE } && !('midrail_centre_mm' =~ MR::KEY_RE)

check 'reference letter key in list order, only the letters used', PR.key(%w[F T B]).map(&:first) == %w[T B F] && PR.key_text(%w[T]).start_with?('Key: T = ')

require 'hw_door_style/core/finder'
FD = HarryWardrobes::DoorStyle::Finder
check 'front types: door / drawer front / internal / fixed (styled as a door) / not a front', FD::ROLES['fixed'] == :door && FD::ROLES['none'].nil? && FD::ROLE_LABELS.map(&:first) == %w[door ext_drawer int_drawer fixed none]


check 'part type wins over the name / thickness rules (an 18mm worktop is still a worktop)', PLX.section_of(['LIN_WORKTOP'], 18, 'Oak', 'worktop') == 'worktops' && PLX.section_of(['WRKTP_FACING'], 25, 'Oak', 'sheet') == 'sheets' && PLX.section_of(['WRKTP'], 25, 'Oak') == 'worktops'

puts "\n== Labels"
class FakeModel; def path = "C:/CUSTOMERS/Smith/Bedroom.skp"; def title = "Bedroom"; def start_operation(*) = nil; def commit_operation = nil; def abort_operation = nil; end
nparts = [{ 'instances' => [{ 'part_no' => nil, 'eid' => 1 }] }, { 'instances' => [{ 'part_no' => 5, 'eid' => 2 }, { 'part_no' => 5, 'eid' => 9 }] }, { 'instances' => [{ 'part_no' => 5, 'eid' => 3 }] }]
PLX.number_parts(FakeModel.new, nparts)
check 'part numbers: kept when unchanged, a clash or a new part gets the next after the highest', nparts.map { |x| x['number'] } == [6, 5, 7]
fresh = [{ 'instances' => [{ 'eid' => 1 }] }, { 'instances' => [{ 'eid' => 2 }] }]
PLX.number_parts(FakeModel.new, fresh)
check 'part numbers start at 1', fresh.map { |x| x['number'] } == [1, 2]

require 'hw_door_style/job/labels'
ord = LB.by_t([{ 't' => '', 'number' => 1, 'position' => 1 }, { 't' => 'W1', 'number' => 2, 'position' => 1 }, { 't' => 'T2', 'number' => 1, 'position' => 1 }, { 't' => 'T10', 'number' => 3, 'position' => 1 }, { 't' => 'T2', 'number' => 10, 'position' => 1 }, { 't' => 'T2', 'number' => 9, 'position' => 1 }])
check 'labels print T number then part number (T2 9 before T2 10, T10 after T2, no T last)', ord.map { |e| "#{e['t']}#{e['t'].empty? ? '' : ':'}#{e['number']}" } == %w[T2:1 T2:9 T2:10 T10:3 W1:2 1]

require 'hw_door_style/job/job_info'
JI = HarryWardrobes::DoorStyle::JobInfo
check 'label name: SURNAME INITIALS (single, double-barrelled, hyphenated, lower case)',
      JI.customer_label('Jane Ann', 'Smith') == 'SMITH JA' && JI.customer_label('', 'Madonna') == 'MADONNA' && JI.customer_label('Andrew', 'Lloyd Webber') == 'LLOYD WEBBER A' &&
      JI.customer_label('mary-jane', 'smith-jones') == 'SMITH-JONES MJ' && JI.customer_label('john', 'o\'neill') == "O'NEILL J"
check 'customer folder -> first / surname', JI.split_name('WILLIAMS Rebecca (Rossett - 830735284436)') == %w[Rebecca Williams] && JI.split_name('Jane Smith') == %w[Jane Smith] &&
      JI.split_name('SMITH-JONES Mary Ann (123)') == ['Mary Ann', 'Smith-Jones'] && JI.split_name('SMITH') == ['', 'Smith']
check 'room from the file name', JI.room_from_file('SURVEY - master bedroom - williams rebecca') == 'Master Bedroom' && JI.room_from_file('Bedroom 2') == 'Bedroom 2'
check 'made-up Room ID {SUR}{YYMMDD}{NN}', JI.new_room_id('Williams', nil, Time.new(2026, 10, 20)) == 'WIL26102001' && JI.new_room_id("O'Neill", nil, Time.new(2026, 1, 2)) == 'ONE26010201' && JI.new_room_id('Ng', nil, Time.new(2026, 1, 2)) == 'NGX26010201'

b = LB.timber_bins([1850, 1850, 2400, 2400, 2400, 2400, 500, 500], 2400)
check 'timber: first fit into 2400 stock (4 x 2400, 2 x 1850 + 2 x 500 -> 6 lengths) and cut list', b['stock'] == 6 && b['cuts'] == '4 x 2400, 2 x 1850, 2 x 500'
check 'timber: a cut longer than the stock takes whole lengths', LB.timber_bins([3000], 2100)['stock'] == 2
check 'grouped label rules: hardware / timber always, name patterns (HINGE*, L_BRACKET), job override',
      LB.rule_aggregate?('BACK', 'hardware') && LB.rule_aggregate?('X', 'timber') && LB.rule_aggregate?('HINGE_110', 'sheet') && LB.rule_aggregate?('l_bracket', 'sheet') &&
      !LB.rule_aggregate?('WRD_FL', 'sheet') && !LB.aggregate?('HINGE_110', 'sheet', { 'HINGE_110' => 'part' }) && LB.aggregate?('WRD_FL', 'sheet', { 'WRD_FL' => 'aggregate' })
check 'label display names', LB.display_name('L_BRACKET') == 'L Brackets' && LB.display_name('OVAL_BRACKET_TOP#2') == 'Oval rail brackets (top)' && LB.display_name('MY_NEW_PART') == 'My New Part' && LB.display_name('WRKTP_2x1_SUPPORT', 'timber') == '2x1 Timber'
ag = LB.aggregates([[{ 'name' => 'L_BRACKET', 'qty' => 4, 'instances' => [{ 'top' => 1 }, { 'top' => 2 }, { 'top' => 2 }, { 'top' => 9 }] }, 'hardware'],
                    [{ 'name' => 'WRKTP_2x1_SUPPORT', 'qty' => 2, 'length' => 800, 'instances' => [{ 'top' => 1 }, { 'top' => 1 }] }, 'timber']], { 1 => 'T3', 2 => 'T1' }, 2400)
check 'grouped labels: total, T numbers in order, timber as stock lengths, running index', ag.map { |a| [a['name'], a['count'], a['ts'], a['agg_index']] } == [['L Brackets', 4, 'T1, T3', 1], ['2x1 Timber', 1, 'T3', 2]]

check 'barcode payloads HW-{ROOM}-{PART} / HW-{ROOM}-H{n}', LB.barcode('WIL26102001', 12) == 'HW-WIL26102001-12' && LB.barcode('830 735', 'H3') == 'HW-830735-H3' && LB.barcode('', 1) == 'HW-ROOM-1'
check 'JsBarcode bundled (no CDN) and put inline in the window', File.exist?(File.join(HarryWardrobes::DoorStyle::PATH, 'html/vendor/JsBarcode.code128.min.js')) && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/parts_list.html')).include?('<!--VENDOR:JsBarcode.code128.min.js-->')

require 'hw_door_style/job/zpl'
ZP = HarryWardrobes::DoorStyle::Zpl
zt = ZP.test_label
File.write(File.join(Dir.tmpdir, 'hw_test_label.zpl'), zt)
check 'ZPL label: 102 x 76 at 203 dpi (^PW816 ^LL608), 5mm home, T + qty left, part number right, L x W, outline, bars-only Code 128, UTF-8',
      zt.start_with?('^XA') && zt.include?('^PW816') && zt.include?('^LL608') && zt.include?('^LH40,40') && zt.include?('^FDT3   1 of 2^FS') && zt.include?(',R,0^FD12^FS') &&
      zt.include?('^FD788 x 490^FS') && zt.include?('^GB') && zt =~ /\^BCN,\d+,N,N,N/ && zt.include?('^FDHW-TEST-12^FS') && zt.include?('^CI28') && zt.end_with?('^XZ')

require 'hw_door_style/job/pdf_print'
PP = HarryWardrobes::DoorStyle::PdfPrint
pp_list = [['Adobe PDF', ''], ['Brother HL-L5000D series', 'BROTHER - Harry Wardrobes'], ['\\\\OFFICE\\Brother MFC', 'MFC']]
PP.define_singleton_method(:printers) { pp_list }
pp_try = ->(name) { PP.define_singleton_method(:printer) { name }; (PP.resolve rescue :none) }
check 'PDF printer found by Windows name, share name or \\\\pc\\share - never guessed',
      pp_try.call('BROTHER - Harry Wardrobes') == 'Brother HL-L5000D series' && pp_try.call('brother hl-l5000d series') == 'Brother HL-L5000D series' &&
      pp_try.call('\\\\OFFICE\\Brother MFC') == '\\\\OFFICE\\Brother MFC' && pp_try.call('Brother MFC') == '\\\\OFFICE\\Brother MFC' && pp_try.call('Brother') == :none


# --- Replace with: options carried between components ------------------------------
require 'hw_door_style/job/swap'
SW = HarryWardrobes::DoorStyle::Swap
sw_opt = ->(v, a, u, o = '') { { v: v, a: a, u: u, o: o } }
WALL4 = '&FALSE%20%28div%29=FALSE&FALSE%20%28no%20div%29=NODIV&TRUE=TRUE&%2B9mm%20%28end%20panel%29=END&'
WALL3 = '&FALSE=FALSE&TRUE%20%28no%20scribe%29=NOSCRIBE&TRUE%20%28scribed%29=TRUE&'
WALL2 = '&TRUE=TRUE&FALSE=FALSE&'
CABW_IN = '&300mm=11.811023622047244&400mm=15.748031496062992&600mm=23.62204724409449&'
CABW_CM = '&300mm=30&400mm=40&600mm=60&'
LAYOUT = '&Double%20hanging%20rail=DOUBLE&Single%20hanging%20rail=SINGLE&Single%20hanging%20rail%20%2B%20shelves=RAILSH&Shelved=SHELVED&'
RAIL = '&None=0&Single=1&Double=2&'
check 'Swap: dropdown options parsed with %20 and %28 unescaped',
      SW.parse_options(WALL3) == [['FALSE', 'FALSE'], ['TRUE (no scribe)', 'NOSCRIBE'], ['TRUE (scribed)', 'TRUE']]
check 'Swap: wall value aliases - no div / end panel = no wall, no scribe = wall; same value kept',
      SW.convert(sw_opt.call('NODIV', 'LIST', 'STRING', WALL4), sw_opt.call('TRUE', 'LIST', 'STRING', WALL3)) == 'FALSE' &&
      SW.convert(sw_opt.call('NOSCRIBE', 'LIST', 'STRING', WALL3), sw_opt.call('FALSE', 'LIST', 'STRING', WALL2)) == 'TRUE' &&
      SW.convert(sw_opt.call('END', 'LIST', 'STRING', WALL4), sw_opt.call('FALSE', 'LIST', 'STRING', WALL2)) == 'FALSE' &&
      SW.convert(sw_opt.call('TRUE', 'LIST', 'STRING', WALL2), sw_opt.call('FALSE', 'LIST', 'STRING', WALL4)) == 'TRUE'
check 'Swap: widths matched by the "600mm" label across inch / cm lists, and from a textbox length',
      SW.convert(sw_opt.call('23.62204724409449', 'LIST', 'STRING', CABW_IN), sw_opt.call('40', 'LIST', 'STRING', CABW_CM)) == '60' &&
      SW.convert(sw_opt.call('60', 'LIST', 'STRING', CABW_CM), sw_opt.call('11.8', 'LIST', 'STRING', CABW_IN)) == '23.62204724409449' &&
      SW.convert(sw_opt.call(600 / 25.4, 'TEXTBOX', 'MILLIMETERS'), sw_opt.call('40', 'LIST', 'STRING', CABW_CM)) == '60' &&
      (SW.convert(sw_opt.call('60', 'LIST', 'STRING', CABW_CM), sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS')) - 600 / 25.4).abs < 1e-6 &&
      SW.convert(sw_opt.call(610 / 25.4, 'TEXTBOX', 'MILLIMETERS'), sw_opt.call('40', 'LIST', 'STRING', CABW_CM)).nil?
check 'Swap: counts and text copied; a length never goes into a count',
      SW.convert(sw_opt.call('3', 'LIST', 'STRING', '&1=1&2=2&3=3&4=4&'), sw_opt.call('2', 'LIST', 'STRING', '&1=1&2=2&3=3&')) == '3' &&
      SW.convert(sw_opt.call('5', 'LIST', 'STRING', '&1=1&2=2&3=3&4=4&5=5&'), sw_opt.call('2', 'LIST', 'STRING', '&1=1&2=2&3=3&')).nil? &&
      SW.convert(sw_opt.call(4, 'TEXTBOX', 'INTEGER'), sw_opt.call(1, 'TEXTBOX', 'INTEGER')) == 4.0 &&
      SW.convert(sw_opt.call(23.6, 'TEXTBOX', 'MILLIMETERS'), sw_opt.call(1, 'TEXTBOX', 'INTEGER')) == 23.6
sw_src = {
  'a01_frame_width' => sw_opt.call(1000 / 25.4, 'TEXTBOX', 'MILLIMETERS'), 'a02_frame_height_ceiling' => sw_opt.call(2200 / 25.4, 'TEXTBOX', 'MILLIMETERS'),
  'b01_doors' => sw_opt.call('L', 'LIST', 'STRING', '&Double=D&Left%20%28single%29=L&Right%20%28single%29=R&'),
  'c01_depth' => sw_opt.call(580 / 25.4, 'TEXTBOX', 'MILLIMETERS'), 'd01_facing_btm' => sw_opt.call(79 / 25.4, 'TEXTBOX', 'MILLIMETERS'),
  'f02_sh_top_height' => sw_opt.call(1900 / 25.4, 'TEXTBOX', 'MILLIMETERS'),
  'i01_wall_left' => sw_opt.call('NODIV', 'LIST', 'STRING', WALL4), 'i02_wall_right' => sw_opt.call('TRUE', 'LIST', 'STRING', WALL4),
  'i04_top_of_unit' => sw_opt.call('2', 'LIST', 'STRING', '&Scribed=1&Custom=2&None=3&'), 'j01_runout_floor' => sw_opt.call(1, 'TEXTBOX', 'MILLIMETERS'),
  'g07_rail_type' => sw_opt.call('2', 'NONE', 'STRING', RAIL), 'f01_sh_no' => sw_opt.call(1, 'NONE', 'INTEGER'), 'k00_int_label' => sw_opt.call('-----', 'VIEW', 'STRING'),
  'k01_int_div' => sw_opt.call('FALSE', 'LIST', 'STRING', WALL2), 'k03_layout_left' => sw_opt.call('RAILSH', 'LIST', 'STRING', LAYOUT), 'k04_shelves_left' => sw_opt.call('3', 'TEXTBOX', 'STRING')
}
sw_stable = {
  'a01_frame_width' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'a02_frame_height_ceiling' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'),
  'b05_stable_side' => sw_opt.call('1', 'LIST', 'FLOAT', '&Left=0&Right=1&'), 'c01_depth' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'),
  'd01_facing_btm' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'f01_sh_no' => sw_opt.call(1, 'TEXTBOX', 'INTEGER'), 'f02_sh_top_height' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'),
  'g07_rail_type' => sw_opt.call('2', 'LIST', 'STRING', RAIL), 'i01_wall_left' => sw_opt.call('FALSE', 'LIST', 'STRING', WALL4), 'i02_wall_right' => sw_opt.call('NODIV', 'LIST', 'STRING', WALL4),
  'i04_top_of_unit' => sw_opt.call('1', 'LIST', 'STRING', '&Scribed=1&Custom=2&None=3&'), 'j01_runout_floor' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'zz_hidden' => sw_opt.call(1, 'NONE', 'FLOAT')
}
sw_plan = SW.plan(sw_src, sw_stable, from_name: 'WARDROBE', to_name: 'WARDROBE_STABLE')
check 'Swap plan WARDROBE -> WARDROBE_STABLE: sizes, walls, top of unit, shelf top carried; layout -> rail type, shelves -> amount (the wardrobe\'s hidden rail / shelf options ignored); facing / runouts / doors / hidden left',
      (sw_plan['a01_frame_width'] - 1000 / 25.4).abs < 1e-6 && sw_plan['i01_wall_left'] == 'NODIV' && sw_plan['i02_wall_right'] == 'TRUE' && sw_plan['i04_top_of_unit'] == '2' &&
      (sw_plan['f02_sh_top_height'] - 1900 / 25.4).abs < 1e-6 && sw_plan['g07_rail_type'] == '1' && sw_plan['f01_sh_no'] == 3.0 &&
      !sw_plan.key?('d01_facing_btm') && !sw_plan.key?('j01_runout_floor') && !sw_plan.key?('b05_stable_side') && !sw_plan.key?('zz_hidden')
sw_back = SW.plan(sw_stable.merge('f01_sh_no' => sw_opt.call(2, 'TEXTBOX', 'INTEGER')), sw_src, from_name: 'WARDROBE_STABLE', to_name: 'WARDROBE')
check 'Swap plan back: rail type Double -> layout left Double, amount -> shelves left; the wardrobe\'s own doors option left',
      sw_back['k03_layout_left'] == 'DOUBLE' && sw_back['k04_shelves_left'] == '2' && !sw_back.key?('b01_doors') && !sw_back.key?('k01_int_div')
sw_bk = { 'a01_frame_width' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'a03_wall_depth' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'i01_wall_left' => sw_opt.call('TRUE', 'LIST', 'STRING', WALL2), 'f02_sh_top_height' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS') }
sw_plan2 = SW.plan(sw_src, sw_bk, from_name: 'LINEN_PRESS', to_name: 'BOOKCASE')
check 'Swap plan: depth alias (depth -> wall_depth), wall no-div -> FALSE; linen press shelf top (from its worktop) not carried',
      (sw_plan2['a03_wall_depth'] - 580 / 25.4).abs < 1e-6 && sw_plan2['i01_wall_left'] == 'FALSE' && !sw_plan2.key?('f02_sh_top_height')
sw_fit = { 'a01_cab_width' => sw_opt.call('15.748031496062992', 'LIST', 'STRING', CABW_IN), 'd05_facing_width_l' => sw_opt.call(70 / 25.4, 'TEXTBOX', 'MILLIMETERS'), 'h04_drwr_no' => sw_opt.call('3', 'LIST', 'STRING', '&1=1&2=2&3=3&4=4&5=5&') }
sw_int = { 'a01_cab_width' => sw_opt.call('70', 'LIST', 'STRING', CABW_CM), 'd06_fllr_left' => sw_opt.call(0, 'TEXTBOX', 'MILLIMETERS'), 'h04_drwr_no' => sw_opt.call('2', 'LIST', 'STRING', '&1=1&2=2&3=3&4=4&5=5&') }
sw_plan3 = SW.plan(sw_fit, sw_int)
check 'Swap plan DRAWER_FITTED -> INT_DRAWER: 400mm width across value sets, facing width -> filler, drawer count',
      sw_plan3['a01_cab_width'] == '40' && (sw_plan3['d06_fllr_left'] - 70 / 25.4).abs < 1e-6 && sw_plan3['h04_drwr_no'] == '3'


# --- Workshop: every reason the pack is blocked has a Fix this route ------------------
wk_src = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job/workshop.rb'))
wk_ids = wk_src[/def self\.blockers.*?\n      end\n/m].scan(/add\.call\('(\w+)'/).flatten.uniq
wk_fix = wk_src[/def self\.fix_blocker.*?\n      end\n/m].scan(/when ((?:'\w+'(?:, )?)+)/).flatten.join(' ').scan(/'(\w+)'/).flatten
pl_js = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/parts_list.html'))
in_window = %w[sheets internals].select { |i| pl_js.include?("b.id === '#{i}'") }
check "Workshop blockers: each (#{wk_ids.size}) has a Fix this - another window or this window's tab",
      wk_ids.size >= 14 && (wk_ids - wk_fix - in_window).empty? && pl_js.include?('Fix this') && File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html/hw.js')).include?('function hwFocus')


# --- one job window with tabs; Fix this comes back ----------------------------------
require 'hw_door_style/ui/dialog'
DL = HarryWardrobes::DoorStyle::Dialog
tab_pages = DL::TABS.map { |t| t[1] }
check 'job window tabs: Add, Colours, Doors, Room, Workshop, HubSpot - each page exists with a body and an icon; Settings and Export are not tabs',
      tab_pages == %w[component_picker colours door_style scribe parts_list hubspot_send] && DL::TABS.all? { |t| File.exist?(File.join(DL::DIR, "#{t[1]}.html")) && File.exist?(File.join(HarryWardrobes::DoorStyle::PATH, 'icons', "#{t[3]}.svg")) } &&
      !DL.tabbed?('settings') && !DL.tabbed?('export') && DL.html('scribe', {}).include?('id="hwTabs"') && !DL.html('settings', {}).include?('id="hwTabs"')
DL.focus_next('colours', sel: ['#sel_door'], note: 'pick', back: -> { $came_back = true })
html_f = DL.html('colours', {})
check 'Fix this: the page opens with the field to outline and the note; done() brings the Workshop back once (Cancel or Apply), then nothing waits',
      html_f.include?('HW_FOCUS') && html_f.include?('#sel_door') && DL.pending?('colours') && DL.done('colours') && !DL.pending?('colours') && !DL.done('colours')
pl_html = File.read(File.join(DL::DIR, 'parts_list.html'))
check 'Workshop: no "Before you start" box - blockers (red, Fix this) and advice (amber) at the top', !pl_html.include?('fixChecks') && !pl_html.include?('showChecks') && pl_html.include?('fixWarning') && !File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job/parts_list.rb')).include?("data['checks']")


require 'hw_door_style/ui/component_picker' unless defined?(HarryWardrobes::DoorStyle::ComponentPicker)
CP = HarryWardrobes::DoorStyle::ComponentPicker
cp_dd = { 'a01_unit_width' => (600 / 25.4).to_s, '_a01_unit_width_access' => 'LIST', '_a01_unit_width_units' => 'STRING', '_a01_unit_width_formlabel' => 'Width (mm)',
          '_a01_unit_width_options' => "&500mm=#{500 / 25.4}&600mm=#{600 / 25.4}&",
          'a04_depth_manual' => '0', '_a04_depth_manual_access' => 'TEXTBOX', '_a04_depth_manual_units' => 'MILLIMETERS', '_a04_depth_manual_formlabel' => 'Depth - manual',
          'a03_unit_depth' => '20', '_a03_unit_depth_access' => 'NONE',
          'j01_runout_floor' => '1', '_j01_runout_floor_access' => 'TEXTBOX',
          'b02_facing_btm' => '1', '_b02_facing_btm_access' => 'TEXTBOX',
          'k04_shelves_left' => '5', '_k04_shelves_left_access' => 'TEXTBOX', '_k04_shelves_left_units' => 'STRING' }
cp_def = Struct.new(:dd) { def attribute_dictionary(_n) = dd }.new(cp_dd)
cp_f = CP.form(cp_def)
check 'Add: settings asked before placing - the options a user sees, in order, lengths in mm, list at its default; hidden, runouts and job-set ones left out',
      cp_f.map { |f| f['key'] } == %w[a01_unit_width a04_depth_manual k04_shelves_left] && cp_f[0]['list'] && cp_f[0]['value'] == (600 / 25.4).to_s &&
      cp_f[0]['options'].map(&:first) == %w[500mm 600mm] && cp_f[1]['mm'] && cp_f[1]['value'] == '0' && cp_f[1]['label'] == 'Depth - manual' && cp_f[2]['value'] == '5' && !cp_f[2]['mm']
cp_ph = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html', 'component_picker.html'))
check 'Add: a card opens its settings (form), Place sends only what changed', cp_ph.include?('sketchup.form(key)') && cp_ph.include?('sketchup.place(k, JSON.stringify(vals))')


require 'hw_door_style/job/workshop' unless defined?(HarryWardrobes::DoorStyle::Workshop)
WS_ = HarryWardrobes::DoorStyle::Workshop
we_u = Struct.new(:vals) { def definition = self; def attribute_dictionary(_n) = vals; def get_attribute(_d, k, x = nil) = vals.fetch(k, x) }
we_list = [we_u.new({ 'i01_wall_left' => 'TRUE', 'i06_wall_left_extend' => '0', 'i02_wall_right' => 'TRUE', 'i07_wall_right_extend' => (25 / 25.4).to_s }),
           we_u.new({ 'i01_wall_left' => 'NODIV', 'i06_wall_left_extend' => '0', 'i02_wall_right' => 'TRUE' })]
we = WS_.wall_no_extend(we_list) rescue [$!]
check 'Workshop warning: Wall TRUE with its extend at 0 (left only here: right extends 25, NODIV is no wall, no extend option is skipped)', we.map(&:last) == ['left'] && we.first.first.equal?(we_list[0])


check 'Workshop checks: components linked as [[pid|label]], shown as plain names elsewhere',
      WS_.plain('Wall set: [[123|WARDROBE (T1)]] wall left, [[9|BOOKCASE]].') == 'Wall set: WARDROBE (T1) wall left, BOOKCASE.' &&
      File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'html', 'parts_list.html')).include?('sketchup.findRef(')


require 'hw_door_style/export/opencutlist' unless defined?(HarryWardrobes::DoorStyle::OpenCutList)
OCLm = HarryWardrobes::DoorStyle::OpenCutList
check 'OpenCutList: every standard colour has 25 mm (worktops) on its list; "18 mm;22,5 mm" reads as numbers',
      OCLm.mm_values('18 mm;22,5 mm') == [18.0, 22.5] && OCLm.thicknesses_for('Dust Grey').include?(25.0) && OCLm.thicknesses_for('Dust Grey').include?(18.0)


require 'hw_door_style/core/unshare'
US = HarryWardrobes::DoorStyle::Unshare
UDef = Struct.new(:name, :dd, :entities, :instances) { def attribute_dictionary(_n) = dd }
UInst = Struct.new(:dd) { def attribute_dictionary(_n) = dd }
u_hinge = UDef.new('HINGE', {}, [], [UInst.new({}), UInst.new({})])
u_outlet = UDef.new('OUTLET', {}, [], [UInst.new({ '_hidden_formula' => 'X', '_lenx_formula' => '1' }), UInst.new({ '_hidden_formula' => 'Y' })])
u_shelf = UDef.new('SHELF', { '_hidden_formula' => 'parent!A', '_inst__x_formula' => '0' }, [], [UInst.new({}), UInst.new({})])
u_box = UDef.new('BOX', {}, [Struct.new(:definition).new(u_shelf)], [UInst.new({})])
check 'Unshare: only plain hardware stays shared (no rules in it or below, same formulas wherever it is used) - a part with rules, or used with different formulas, gets its own copy',
      US.plain_hardware?(u_hinge) && !US.plain_hardware?(u_outlet) && !US.plain_hardware?(u_shelf) && !US.plain_hardware?(u_box) &&
      US.own_rules?(u_shelf) && !US.own_rules?(UDef.new('X', { '_inst__x_formula' => '0' }, [], []))
pl_src = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'job', 'parts_list.rb'))
check 'Parts list: a part\'s own copy ("SHELF#2") is listed with the part (same name, size) - not by definition', pl_src.include?("pid = [name, l_mm, w_mm, th_mm, flipped].join('|')") && pl_src.include?("name = DC.base_name(defn)")
le_src = File.read(File.join(HarryWardrobes::DoorStyle::PATH, 'export', 'library_export.rb'))
check 'Library export: Clean model makes the copies; export locked while a part is shared', le_src.include?('Unshare.fix!(model)') && le_src.include?('shared.empty?')


DCb = HarryWardrobes::DoorStyle::DC
ubn = Struct.new(:name, :dn) { def get_attribute(_d, _k, _x = nil) = dn }
check 'Part names without the copy number - SketchUp\'s "CABLE_OUTLET_#2" (trailing digits dropped) reads as CABLE_OUTLET_80 from its DC name',
      DCb.base_name(ubn.new('CABLE_OUTLET_#2', 'CABLE_OUTLET_80')) == 'CABLE_OUTLET_80' && DCb.base_name(ubn.new('SHELF_MID#3', 'SHELF_MID')) == 'SHELF_MID' &&
      DCb.base_name(ubn.new('DOOR#10', 'Something else')) == 'DOOR' && DCb.base_name(ubn.new('WARDROBE', nil)) == 'WARDROBE'


PRf = HarryWardrobes::DoorStyle::Products
pf_u = Struct.new(:vals) { def definition = self; def attribute_dictionary(_n) = vals; def get_attribute(_d, k, x = nil) = vals.fetch(k, x) }
check 'Product list: "Back Panel: Yes" when the unit\'s Backs is TRUE, nothing when FALSE or no Backs option',
      PRf.flags(pf_u.new({ 'i08_backs' => 'TRUE' })) == [['Back Panel', 'Yes']] && PRf.flags(pf_u.new({ 'i08_backs' => 'FALSE' })).empty? && PRf.flags(pf_u.new({ 'a01_unit_width' => '1' })).empty?
require 'hw_door_style/job/worktop_view' unless defined?(HarryWardrobes::DoorStyle::WorktopView)
WV = HarryWardrobes::DoorStyle::WorktopView
check 'Wall "FALSE (with overhang)" is no wall, "TRUE (with overhang)" is a wall (worktop edges, swaps, checks)',
      (WV.nil? || (!WV.truthy?('FALSE_OH') && WV.truthy?('TRUE_OH') && !WV.truthy?('FALSE') && WV.truthy?('TRUE'))) &&
      HarryWardrobes::DoorStyle::Swap::VALUE_ALIASES['FALSE_OH'] == 'FALSE' && WS_::WALL_TRUE.include?('TRUE_OH')


# --- background steps (network / Drive off SketchUp's thread) -------------------------
st_out = `ruby #{File.join(__dir__, 'steps_test.rb')} 2>&1`
check 'Steps: a :bg step runs off the main thread, its after / the next step back on it, an error reaches fail, no timer left running',
      st_out.include?('[[:after, 42, true], [:main, true], [:done, [42, 7, "x"]]]') && st_out.include?('["no network"]') && st_out.lines.last.strip == '0'

puts $fail.zero? ? "\nAll checks passed" : "\n#{$fail} check(s) FAILED"
exit($fail.zero? ? 0 : 1)
