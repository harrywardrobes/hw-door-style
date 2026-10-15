# Harry Wardrobes - make the 13 colour .skm files
#
# In SketchUp: Window > Ruby Console, then type (with your own path):
#   load 'C:/Users/User/Downloads/HW Colours/make_skm.rb'
#
# Saves:
#   1. <this folder>/skm/*.skm
#   2. SketchUp's own Materials folder, collection "Harry Wardrobes",
#      so they appear in the Materials panel (restart SketchUp to see them).
# Your open model is left unchanged.
require 'json'

module HWMakeSkm
  def self.run
    here = File.dirname(File.expand_path(__FILE__))
    # Zip pack: colours.json + textures/ sit next to this script.
    # Repo checkout: they live in src/hw_door_style/.
    data = File.exist?(File.join(here, 'colours.json')) ? here : File.join(here, '..', 'src', 'hw_door_style')
    raw = JSON.parse(File.read(File.join(data, 'colours.json')))
    lib = raw['colours'] + (raw['drawer_boxes'] || []).map { |b| b.merge('name' => b['material'], 'size_mm' => (b['texture_size_mm'] || [600, 600])) }
    out1 = File.join(here, 'skm')
    out2 = File.join(ENV['APPDATA'].to_s, 'SketchUp', "SketchUp 20#{Sketchup.version.to_i}", 'SketchUp', 'Materials', 'Harry Wardrobes')
    [out1, out2].each { |d| FileUtils.mkdir_p(d) rescue nil }

    model = Sketchup.active_model
    model.start_operation('Make HW colour .skm files', true)
    saved = []
    lib.each do |c|
      # Free the exact name for the duration (undone at the end) so every .skm carries it.
      old = model.materials[c['name']]
      old.name = "HWTMP_OLD #{c['name']}" if old
      m = model.materials.add(c['name'])
      m.color = Sketchup::Color.new(*c['rgb'])
      if c['texture']
        m.texture = File.join(data, 'textures', c['texture'])
        sz = Array(c['size_mm']).map { |v| v.to_f / 25.4 }
        m.texture.size = sz.size == 2 ? sz : [sz[0], sz[0]]
      end
      [out1, out2].each do |d|
        next unless File.directory?(d)
        f = File.join(d, "#{c['name']}.skm")
        saved << f if m.save_as(f)
      end
    end
    model.abort_operation
    puts saved.join("\n")
    UI.messagebox("#{saved.size} .skm files saved.\n\n#{out1}\n#{out2}\n\nRestart SketchUp to see the 'Harry Wardrobes' collection in the Materials panel.")
  rescue StandardError => e
    model.abort_operation if model
    UI.messagebox("Could not make the .skm files: #{e.message}")
  end
end
require 'fileutils'
HWMakeSkm.run
