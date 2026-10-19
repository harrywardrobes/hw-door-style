module HarryWardrobes
  module DoorStyle
    # OpenCutList (lairdubois) link - information only for now.
    #
    # OpenCutList keeps its settings in the "ladb_opencutlist" attribute dictionary:
    #   materials : type (0 unknown, 1 solid wood, 2 sheet good, 3 dimensional, 4 edge,
    #               5 hardware, 6 veneer), thickness, std_thicknesses, std_sizes, grained ...
    #   components: tags, symmetrical, ignore_grain_direction, orientation_locked_on_axis ...
    # Nothing is written yet; this reports what the plugin could set.
    module OpenCutList
      DICT_NAME = 'ladb_opencutlist'.freeze
      TYPES = { 0 => 'Unknown', 1 => 'Solid wood', 2 => 'Sheet good', 3 => 'Dimensional', 4 => 'Edge',
                5 => 'Hardware', 6 => 'Veneer' }.freeze

      def self.extension
        Sketchup.extensions.find { |e| e.name.to_s =~ /open\s*cut\s*list/i }
      end

      # What the plugin would set on each material it manages.
      def self.plan
        rows = Colours.library.map do |c|
          { 'material' => c['name'], 'type' => 'Sheet good', 'thickness' => '18mm (22mm for 22mm Panels)',
            'grained' => c['texture'] ? 'Yes (woodgrain)' : 'No' }
        end
        rows += DrawerBox.library.map do |b|
          { 'material' => b['material'] || b['name'], 'type' => 'Hardware (bought-in Interfit box)',
            'thickness' => "#{b['thickness_mm']}mm", 'grained' => '-' }
        end
        rows << { 'material' => Settings.get['hardware_material'], 'type' => 'Hardware (hinges, TIP-ON)', 'thickness' => '-', 'grained' => '-' }
        rows
      end

      # Status for the Settings tab.
      def self.status(model = Sketchup.active_model)
        ext = extension
        set = model.materials.count { |m| !m.get_attribute(DICT_NAME, 'type').nil? }
        { 'installed' => !ext.nil?, 'loaded' => ext ? ext.loaded? : false, 'version' => ext&.version.to_s,
          'materials_with_ocl' => set, 'materials' => model.materials.count, 'plan' => plan }
      rescue StandardError => e
        { 'installed' => false, 'error' => e.message, 'plan' => [] }
      end
    end
  end
end
