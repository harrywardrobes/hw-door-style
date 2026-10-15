module HarryWardrobes
  module DoorStyle
    # Tags the raw faces and edges INSIDE each door / drawer front so the tag
    # travels with every copy of the component.
    #   doors                         -> DOOR
    #   drawer fronts (ext. and int.) -> DRAWER_FRONT
    module Tagger
      def self.layer(model, name)
        model.layers[name] || model.layers.add(name)
      end

      def self.tag_for(model, kind)
        layer(model, kind == :door ? Settings.get['door_tag'] : Settings.get['drawer_tag'])
      end

      # Faces and edges only. Returns the number of entities changed.
      def self.tag_geometry(entities, tag)
        n = 0
        entities.each do |e|
          next unless e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
          next if e.layer == tag
          e.layer = tag
          n += 1
        end
        n
      end

      # Raw geometry in the item's definition, plus our nested style part and its geometry.
      def self.tag_item(inst, kind)
        tag = tag_for(inst.model, kind)
        d = inst.definition
        n = tag_geometry(d.entities, tag)
        d.entities.grep(Sketchup::ComponentInstance).each do |c|
          next unless c.get_attribute(DICT, 'role') == 'style'
          c.layer = tag unless c.layer == tag
          n += tag_geometry(c.definition.entities, tag)
        end
        n
      end

      # Every recognised door and drawer front in the model (incl. internal and not-yet-converted).
      def self.tag_all(model)
        seen = {}
        n = 0
        Finder.all_targets(model, [:door, :ext_drawer, :int_drawer]).each do |inst, kind|
          next if seen[inst.definition.entityID]
          seen[inst.definition.entityID] = true
          n += tag_item(inst, kind)
        end
        n
      end
    end
  end
end
