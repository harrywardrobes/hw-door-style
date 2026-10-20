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
      ui/dialog core/batch core/steps core/scenes core/updater ui/colours_window ui/door_style_window ui/settings_window
      export/hubspot_room export/hubspot_pictures export/hubspot_products export/supplier_import export/product_images
      core/component_fixes core/top_of_unit core/formula_parser job/parts_pdf job/labels job/parts_list job/workshop core/library_cache ui/component_picker export/template_export job/room job/products job/depth job/plan job/room_plan job/midrail job/door_view
      dev/acceptance dev/developer ui/menus
    ].freeze
    FILES.each { |f| Sketchup.require(File.join(PATH, f)) }

    unless file_loaded?(__FILE__)
      Menus.build
      Pencil.start_watching # keeps the pencil button in step with the open model
      Scenes.start # renamed scenes are renamed in Settings too
      TopOfUnit.start # one 'Top of unit' dropdown in place of Topped off? / Up to ceiling
      Room.start # a file without a room asks for it (and where to save a new job)
      TemplateExport.start # latest job template from the library into Welcome to SketchUp
      Updater.check_at_startup # newer version in the updates folder? offer it
      file_loaded(__FILE__)
    end
  end
end
