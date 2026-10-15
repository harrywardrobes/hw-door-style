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
end

$LOAD_PATH.unshift File.expand_path('../src', __dir__)
module HarryWardrobes
  module DoorStyle
    PATH = File.expand_path('../src/hw_door_style', __dir__)
    VERSION = 'test'
    DICT = 'hw_door_style'
  end
end
require 'hw_door_style/settings'
require 'hw_door_style/finder'
require 'hw_door_style/styles'
require 'hw_door_style/report'

include HarryWardrobes::DoorStyle
$fail = 0
def check(name, cond)
  puts "#{cond ? 'PASS' : 'FAIL'}  #{name}"
  $fail += 1 unless cond
end
def mm(v); (v * 25.4).round(1); end

# --- settings
check 'door frame 100mm', (mm(Settings.mm('door_frame_mm')) == 100.0)
check 'drawer frame 50mm', (mm(Settings.mm('drawer_frame_mm')) == 50.0)
check 'IDRW_FRONT is internal', Settings.names('int_drawer_names').include?('IDRW_FRONT')
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
check 'drawer 50mm frame', r == [[50.0, 50.0, 346.0, 178.0, 6.0]]

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
require 'hw_door_style/colours'
check '13 colours', Colours.names.size == 13 && Colours.names.include?('Stone Grey')
check 'woodgrain textures bundled', Colours.library.select { |c| c['texture'] }.all? { |c| File.exist?(File.join(Colours::TEXTURES, c['texture'])) }
check 'defaults start as Default', Colours.defaults.values.uniq == ['Default']
check 'interior group has STL, not HARDWARE', Colours.group_tags['interior'].include?('STL') && !Colours.group_tags.values.flatten.include?('HARDWARE')
check 'Default follows door colour', Colours.resolve('interior', 'Default', 'Cashmere') == 'Cashmere'
check 'manual choice kept', Colours.resolve('worktop', 'Graphite', 'Cashmere') == 'Graphite'
check 'door Default = no material', Colours.resolve('door', 'Default', nil) == 'Default'
check 'others Default with no door = no material', Colours.resolve('exterior', 'Default', 'Default') == 'Default'
check 'hinges on DOOR tag', Settings.get['hinge_tag'] == 'DOOR'

# --- export naming + versioning
require 'tmpdir'
require 'hw_door_style/pdf'
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

puts $fail.zero? ? "\nAll checks passed" : "\n#{$fail} check(s) FAILED"
exit($fail.zero? ? 0 : 1)
