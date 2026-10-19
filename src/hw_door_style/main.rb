require 'sketchup.rb'
require 'json'

# HW Door Style - loaded by ../hw_door_style.rb (the extension loader).
#
# Folder layout (each file is one module, named after the file):
#   core/     settings, DC attributes, finding parts, undo steps, batches, logging
#   doors/    door / drawer front styles, hinges, tags, repair, menu actions
#   colours/  the job's colours and the colour library
#   job/      runouts (pencil), ceiling height, door summary and order
#   export/   component library export, OpenCutList
#   ui/       windows, menus and toolbar  (html/ and icons/ hold the pages / icons)
#   dev/      acceptance tests and the Developer menu (developer switch on)
#
# CONTRIBUTING.md (repo root) explains how to add a setting, a window or a button.
module HarryWardrobes
  module DoorStyle
    DICT = 'hw_door_style'.freeze # this plugin's own attributes on models / definitions

    FILES = %w[
      core/log core/settings core/dc core/finder core/ops core/drawers
      doors/styles doors/tagger doors/hardware doors/drawer_box doors/converter doors/repair doors/actions
      colours/colours
      job/runouts job/ceiling job/facing job/standardise job/pencil job/pdf job/report
      export/library_export export/opencutlist export/hubspot
      ui/dialog core/batch core/steps core/updater ui/colours_window ui/door_style_window ui/settings_window
      export/hubspot_room export/hubspot_pictures export/hubspot_products
      dev/acceptance dev/developer ui/menus
    ].freeze
    FILES.each { |f| Sketchup.require(File.join(PATH, f)) }

    unless file_loaded?(__FILE__)
      Menus.build
      Pencil.start_watching # keeps the pencil button in step with the open model
      Updater.check_at_startup # newer version in the updates folder? offer it
      file_loaded(__FILE__)
    end
  end
end
