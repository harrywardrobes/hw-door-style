# HW Door Style — SketchUp extension loader
# Harry Wardrobes (Gautier Design Ltd)

require 'sketchup.rb'
require 'extensions.rb'

module HarryWardrobes
  module DoorStyle
    PLUGIN_ID = 'hw_door_style'.freeze
    VERSION   = '0.88.5'.freeze
    PATH      = File.join(File.dirname(__FILE__), PLUGIN_ID).freeze

    MIN_SKETCHUP = 21 # SketchUp 2021; everything the plugin uses exists from here

    unless file_loaded?(__FILE__)
      if Sketchup.version.to_i < MIN_SKETCHUP
        # Not registered at all, so nothing half-loads; say why once SketchUp is up.
        UI.start_timer(1, false) do
          UI.messagebox("HW Door Style #{VERSION} needs SketchUp 2021 or newer " \
                        "(this is SketchUp 20#{Sketchup.version.to_i}).")
        end
      else
        ext = SketchupExtension.new('HW Door Style', File.join(PATH, 'main'))
        ext.description = 'Harry Wardrobes job tools: Flat / Shaker doors and drawer fronts, hinges and ' \
                          'handles, colours, scribes / runouts and ceiling height, door order, ' \
                          'and component library export.'
        ext.version   = VERSION
        ext.creator   = 'Harry Wardrobes'
        ext.copyright = '2026 Gautier Design Ltd'
        Sketchup.register_extension(ext, true)
      end
      file_loaded(__FILE__)
    end
  end
end
