module HarryWardrobes
  module DoorStyle
    # Tags the raw faces and edges INSIDE each door / drawer front so the tag
    # travels with every copy of the component, and puts each door on DOOR (so its
    # hinges hide with it).
    #   doors                         -> DOOR
    #   drawer fronts (ext. and int.) -> DRAWER_FRONT
    # and puts every hardware component on its own tag (Settings "hardware_tags":
    # hinges, shelf_brackets, drawer_rails ...) so nothing is left on HARDWARE.
    module Tagger
      OLD_HARDWARE_TAG = 'HARDWARE'.freeze

      def self.base_name(defn)
        defn.name.sub(/#\d+\z/, '').strip.upcase
      end

      # Tag for a hardware definition (by its name or DC _name), or nil.
      def self.hardware_tag_name(defn)
        names = [base_name(defn), defn.get_attribute('dynamic_attributes', '_name').to_s.strip.upcase]
        Settings.hardware_tags.each { |tag, list| return tag if (names & list).any? }
        nil
      end

      # Every listed hardware component: its instances and the faces/edges inside it.
      # Returns { instances: n, geometry: n }.
      def self.tag_hardware(model)
        n = { instances: 0, geometry: 0 }
        model.definitions.each do |d|
          next if d.image? || d.group?
          tname = Hardware.ours?(d) ? Settings.get['hinge_tag'] : hardware_tag_name(d)
          next unless tname
          tag = layer(model, tname)
          n[:geometry] += tag_geometry(d.entities, tag)
          d.instances.each do |i|
            next if i.layer == tag
            i.layer = tag
            n[:instances] += 1
          end
        end
        n
      end

      # Anything still on the old HARDWARE tag: { "name (instance|geometry)" => count }.
      def self.hardware_leftovers(model)
        old = model.layers[OLD_HARDWARE_TAG] or return {}
        left = Hash.new(0)
        model.definitions.each do |d|
          next if d.image?
          d.entities.each do |e|
            next unless e.layer == old
            if e.respond_to?(:definition)
              left["#{base_name(e.definition)} (component)"] += 1
            elsif e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
              left["#{base_name(d)} (faces/edges)"] += 1
            end
          end
        end
        model.entities.each { |e| left["#{e.respond_to?(:definition) ? base_name(e.definition) : e.typename} (top level)"] += 1 if e.layer == old }
        left
      end
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
        door_tag = tag_for(model, :door)
        Finder.all_targets(model, [:door, :ext_drawer, :int_drawer]).each do |inst, kind|
          # The door itself on DOOR too, so hiding DOOR (e.g. scene "D internal") hides its hinges.
          if kind == :door && inst.layer != door_tag
            inst.layer = door_tag
            n += 1
          end
          next if seen[inst.definition.entityID]
          seen[inst.definition.entityID] = true
          n += tag_item(inst, kind)
        end
        hw = tag_hardware(model)
        n + hw[:instances] + hw[:geometry] + hide_hinges_with_doors(model)
      end

      # Every scene that hides the DOOR tag (e.g. "D internal") hides the hinges tag too
      # (not scenes named HARDWARE / HINGE...),
      # so hinges never show without their doors - even on a door the component made
      # itself on Layer0 (a Double / Single change re-makes the second door).
      def self.hide_hinges_with_doors(model)
        door = model.layers[Settings.get['door_tag']] or return 0
        hinge = model.layers[Settings.get['hinge_tag']] or return 0
        model.pages.count do |pg|
          hidden = Array(pg.layers)
          next false if pg.name =~ /hardware|hinge/i # scenes for showing the hardware itself
          next false unless pg.use_hidden_layers? && hidden.include?(door) && !hidden.include?(hinge)
          pg.set_visibility(hinge, false)
          true
        end
      end
    end
  end
end
