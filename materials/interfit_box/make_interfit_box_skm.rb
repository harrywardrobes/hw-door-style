# Harry Wardrobes - make the three Interfit drawer box .skm files.
# In SketchUp: Window > Ruby Console, then type:
#   load 'G:/My Drive/1_Gautier Design Ltd/4_Assets/SketchUp Components/Harry Wardrobes/HW Colours/Interfit Box/make_interfit_box_skm.rb'
# Saves Interfit-Box-Windsor-Oak / -Light-Grey / -Graphite-Grey .skm in this folder and in
# SketchUp's Materials > "Harry Wardrobes" collection. Your open model is left unchanged.
require 'fileutils'
module HWInterfitSkm
  def self.run
    dir = File.dirname(File.expand_path(__FILE__))
    lib = File.join(ENV['APPDATA'].to_s, 'SketchUp', "SketchUp 20#{Sketchup.version.to_i}", 'SketchUp', 'Materials', 'Harry Wardrobes')
    FileUtils.mkdir_p(lib) rescue nil
    specs = [
      { 'name' => 'Interfit-Box-Windsor-Oak', 'rgb' => [186, 156, 117], 'tex' => File.join(dir, 'Interfit-Box-Windsor-Oak.jpg'), 'size_mm' => [700, 583] },
      { 'name' => 'Interfit-Box-Light-Grey',  'rgb' => [196, 197, 193] },
      { 'name' => 'Interfit-Box-Graphite-Grey', 'rgb' => [91, 86, 83] }
    ]
    m = Sketchup.active_model
    saved = []
    m.start_operation('Make Interfit box .skm', true)
    begin
      specs.each do |s|
        old = m.materials[s['name']]
        old.name = "HWTMP_OLD #{s['name']}" if old
        mat = m.materials.add(s['name'])
        mat.color = Sketchup::Color.new(*s['rgb'])
        if s['tex']
          raise "Texture missing: #{s['tex']}" unless File.exist?(s['tex'])
          mat.texture = s['tex']
          mat.texture.size = s['size_mm'].map { |v| v / 25.4 }
        end
        [dir, lib].each do |d|
          next unless File.directory?(d)
          f = File.join(d, "#{s['name']}.skm")
          saved << f if mat.save_as(f)
        end
      end
    ensure
      m.abort_operation
    end
    UI.messagebox("#{saved.size} .skm files saved:\n\n#{saved.join("\n")}\n\nRestart SketchUp to see them in Materials > Harry Wardrobes.")
  rescue StandardError => e
    UI.messagebox("Could not make the .skm files: #{e.message}")
  end
end
HWInterfitSkm.run
