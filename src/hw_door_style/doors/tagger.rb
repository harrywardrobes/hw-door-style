module HarryWardrobes
  module DoorStyle
    # Tags the raw faces and edges INSIDE each door / drawer front so the tag
    # travels with every copy of the component, and puts each door on DOOR (so its
    # hinges hide with it).
    #   doors                         -> DOOR
    #   drawer fronts (ext. and int.) -> DRAWER_FRONT
    # and puts every hardware component on its own tag (Settings "hardware_tags":
    # hinges, shelf_brackets, drawer_rails ...).
    module Tagger
      def self.base_name(defn)
        DC.base_name(defn).upcase
      end

      # Tag for a hardware definition (by its name or DC _name), or nil.
      def self.hardware_tag_name(defn)
        names = [base_name(defn), defn.get_attribute('dynamic_attributes', '_name').to_s.strip.upcase]
        Settings.hardware_tags.each { |tag, list| return tag if (names & list).any? }
        nil
      end

      # Every listed hardware component: its instances and the faces/edges inside it.
      # Returns { instances: n, geometry: n }. defs: only these definitions (default all).
      def self.tag_hardware(model, defs = model.definitions)
        n = { instances: 0, geometry: 0 }
        defs.each do |d|
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

      def self.layer(model, name)
        model.layers[name] || model.layers.add(name)
      end

      # The tag for a front: doors DOOR, drawer fronts (external and internal) DRAWER_FRONT, a
      # fixed panel (the stable panel) its own (Settings "fixed_panel_tag") - so hiding the doors
      # hides only the doors (and their hinges).
      def self.tag_name(kind, inst = nil)
        if kind == :door && inst && Finder.fixed?(inst)
          n = Settings.get['fixed_panel_tag'].to_s.strip
          return n.empty? ? 'STABLE_PANEL' : n
        end
        kind == :door ? Settings.get['door_tag'] : Settings.get['drawer_tag']
      end

      def self.tag_for(model, kind, inst = nil)
        layer(model, tag_name(kind, inst))
      end

      # The front itself on its tag. True if it changed.
      def self.tag_instance(inst, kind)
        tag = tag_for(inst.model, kind, inst)
        return false if inst.layer == tag
        inst.layer = tag
        true
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
        tag = tag_for(inst.model, kind, inst)
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
          # The front itself on its tag too: doors on DOOR (so hiding DOOR, e.g. scene "D internal",
          # hides their hinges), drawer fronts on DRAWER_FRONT, the stable panel on its own.
          n += 1 if tag_instance(inst, kind)
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
