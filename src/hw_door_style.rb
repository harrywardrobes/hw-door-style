# HW Door Style — SketchUp extension loader
# Harry Wardrobes (Gautier Design Ltd)

require 'sketchup.rb'
require 'extensions.rb'

module HarryWardrobes
  module DoorStyle
    PLUGIN_ID = 'hw_door_style'.freeze
    VERSION   = '0.11.1'.freeze
    PATH      = File.join(File.dirname(__FILE__), PLUGIN_ID).freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('HW Door Style', File.join(PATH, 'main'))
      ext.description = 'Converts wardrobe doors and drawer fronts between Flat and Shaker ' \
                        'styles, adds hinge/TIP-ON parts and produces a door summary.'
      ext.version   = VERSION
      ext.creator   = 'Harry Wardrobes'
      ext.copyright = '2026 Gautier Design Ltd'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
