# HW Door Style - acceptance tests. The tests now live in the plugin
# (src/hw_door_style/dev/acceptance.rb) and run from Extensions > HW Door Style >
# Developer > Run tests (turn on Settings > General > Developer mode, restart SketchUp).
#
# From the Ruby Console:
#   puts HarryWardrobes::DoorStyle::Acceptance.report_text
#
# This file is kept so the old command still works:
#   load '.../tools/acceptance_test.rb'; puts HWDoorAcceptance.run_report
module HWDoorAcceptance
  def self.run_report = HarryWardrobes::DoorStyle::Acceptance.report_text
end
