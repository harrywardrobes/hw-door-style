module HarryWardrobes
  module DoorStyle
    # The plugin's own tags for plan dimensions, plan notes, Pod numbers and the doors view: named in Settings
    # and kept in the "dimensions / labels" tag folder (Settings "label_tag_folder").
    #
    # A tag the plugin makes is marked; only those are switched to show in the plan scenes
    # only. A tag that was already in the model (e.g. room_dims, which has your own room
    # dimensions too) keeps the visibility you gave it in each scene.
    module Tags
      MARK = 'plugin_tag'.freeze
      # setting => default tag name
      KEYS = {
        'plan_dims_tag' => 'room_dims',
        'plan_notes_tag' => 'plan_notes',
        'product_label_tag' => 'Pod_numbers',
        'door_view_tag' => 'door_elevation'
      }.freeze

      def self.name(key)
        n = Settings.get[key].to_s.strip
        n.empty? ? KEYS[key] : n
      end

      def self.folder(model)
        n = Settings.get['label_tag_folder'].to_s.strip
        return nil if n.empty? || !model.layers.respond_to?(:folders)
        model.layers.folders.find { |f| f.name == n } || model.layers.add_folder(n)
      end

      # The tag for a setting: made if missing (marked as the plugin's), moved into the folder.
      def self.get(model, key)
        layers = model.layers
        want = name(key)
        layer = layers[want]
        unless layer
          layer = layers.add(want)
          layer.set_attribute(DICT, MARK, true)
        end
        f = folder(model)
        f.add_layer(layer) if f && layer.folder != f
        layer
      rescue StandardError => e
        Log.error("tag #{key}", e)
        layers[want] || layers.add(want)
      end

      def self.ours?(layer) = layer.get_attribute(DICT, MARK) ? true : false
    end
  end
end
