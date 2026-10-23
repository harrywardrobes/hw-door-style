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
      job/runouts job/ceiling job/facing job/drawer_front job/pencil job/pdf job/report
      export/export_changes export/library_export export/opencutlist export/hubspot
      ui/dialog core/batch core/steps core/scenes core/updater ui/colours_window ui/door_style_window ui/settings_window ui/products_window ui/setup
      export/hubspot_room export/hubspot_pictures export/hubspot_products export/supplier_import export/product_images
      core/tags core/top_of_unit job/parts_pdf job/labels job/parts_list job/workshop core/local core/library_cache core/unshare core/no_scale ui/component_picker export/template_export job/room job/products job/depth job/swap job/plan job/room_plan job/midrail job/door_view job/worktop_view job/job_info job/zpl job/pdf_print job/survey
      dev/acceptance dev/developer ui/menus
    ].freeze
    FILES.each { |f| Sketchup.require(File.join(PATH, f)) }

    unless file_loaded?(__FILE__)
      Menus.build
      Pencil.start_watching # keeps the pencil button in step with the open model
      Scenes.start # renamed scenes are renamed in Settings too
      Room.start # a file without a room asks for it (and where to save a new job)
      OpenCutList.start # a job's plugin colours set up for OpenCutList as the file opens
      HubSpotRoom.start # a design visit file asks to connect to its Room once there is one
      TemplateExport.start # latest job template from the library into Welcome to SketchUp
      Updater.check_at_startup # newer version in the updates folder? offer it
      Setup.start # first run on this computer: the setup checklist
      file_loaded(__FILE__)
    end
  end
end
