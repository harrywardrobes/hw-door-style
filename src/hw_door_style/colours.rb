require 'json'

module HarryWardrobes
  module DoorStyle
    # Colour library + painting by tag group.
    #
    # Groups (tag lists editable in Settings):
    #   door      Door / Drawer colour            DOOR, DRAWER_FRONT
    #   exterior  Exterior Panel / Trim colour    FACING, END_PAN, NOSING, FILLER
    #   interior  Interior colour                 STL, SH, DIV, INT_DIV, FL, DRAWER, BACK, WALKIN, MDF
    #   worktop   Worktop colour                  WORKTOP
    #
    # Choices per job are stored in the model. "Default" = no material.
    module Colours
      FILE = File.join(PATH, 'colours.json')
      TEXTURES = File.join(PATH, 'textures')
      DEFAULT = 'Default'.freeze

      GROUPS = [
        ['door',     'Door / Drawer Colour'],
        ['exterior', 'Exterior Panel / Trim Colour'],
        ['interior', 'Interior Colour'],
        ['worktop',  'Worktop Colour'],
        ['drawer_box', 'Drawer Box']
      ].freeze

      def self.library
        @library ||= JSON.parse(File.read(FILE))['colours']
      end

      def self.names
        library.map { |c| c['name'] }
      end

      def self.spec(name)
        library.find { |c| c['name'] == name }
      end

      # Library material. Reuses a material of exactly the same name if the model
      # already has one; otherwise creates it from the library.
      def self.material(model, name)
        return nil if name.nil? || name == DEFAULT
        m = model.materials[name]
        return m if m
        s = spec(name) or return nil
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*s['rgb'])
        if s['texture']
          m.texture = File.join(TEXTURES, s['texture'])
          size = s['size_mm'].to_f.mm
          m.texture.size = [size, size] if m.texture
        end
        m.set_attribute(DICT, 'library', true)
        m
      end

      # --- per-job choices (model) and defaults (plugin settings) ---

      def self.job_choices(model = Sketchup.active_model)
        GROUPS.to_h { |id, _| [id, model.get_attribute(DICT, "colour_#{id}", nil)] }
      end

      def self.defaults
        d = Settings.get['default_colours'] || {}
        GROUPS.to_h { |id, _| [id, d[id] || (id == 'drawer_box' ? DrawerBox::DEFAULT : DEFAULT)] }
      end

      def self.door_colour_chosen?(model = Sketchup.active_model)
        c = model.get_attribute(DICT, 'colour_door', nil)
        !c.nil? && c != DEFAULT
      end

      # --- painting -------------------------------------------------------

      def self.group_tags
        g = Settings.get['colour_groups'] || {}
        g.transform_values { |list| Array(list).map { |t| t.to_s.strip.upcase } }
      end

      # Tag that decides an instance's group: its own tag, or (if Untagged) the
      # tag carried by most of the faces directly inside it.
      def self.effective_tag(inst)
        own = inst.layer
        return own.name.upcase unless own == inst.model.layers[0]
        faces = inst.definition.entities.grep(Sketchup::Face)
        return nil if faces.empty?
        faces.group_by(&:layer).max_by { |_l, fs| fs.size }[0].then { |l| l == inst.model.layers[0] ? nil : l.name.upcase }
      end

      def self.skip?(inst)
        Finder.hardware?(inst) || Hardware.ours?(inst.definition)
      end

      # Paints every matching instance with the group's material (nil = Default).
      # Returns { group_id => count }.
      # "Default" on Exterior / Interior / Worktop means "same as the door colour".
      # Default on the door itself means no material.
      def self.resolve(gid, name, door)
        return (name.nil? || name == DEFAULT ? DrawerBox::DEFAULT : name) if gid == 'drawer_box'
        return name unless name.nil? || name == DEFAULT
        gid == 'door' ? DEFAULT : (door || DEFAULT)
      end

      def self.resolved(model, choices)
        door = choices['door'] || model.get_attribute(DICT, 'colour_door', nil)
        choices.to_h { |gid, name| [gid, resolve(gid, name, door)] }
      end

      def self.apply(model, choices)
        tags = group_tags
        lookup = {}
        tags.each { |gid, list| list.each { |t| lookup[t] = gid } }
        res = resolved(model, choices)
        mats = res.to_h { |gid, name| [gid, gid == 'drawer_box' ? DrawerBox.material(model, name) : material(model, name)] }
        counts = Hash.new(0)
        Finder.each_instance(model.entities) do |inst|
          next if skip?(inst)
          # Drawer box parts only ever take the Drawer Box finish, never a tag-group colour.
          gid = DrawerBox.part?(inst) ? 'drawer_box' : lookup[effective_tag(inst)]
          next unless gid && choices.key?(gid)
          mat = mats[gid]
          inst.material = mat unless inst.material == mat
          dc = inst.attribute_dictionary('dynamic_attributes')
          if dc && dc.keys.include?('material') && !dc['_material_formula'].to_s.strip.start_with?('=')
            inst.set_attribute('dynamic_attributes', 'material', mat ? mat.name : '')
          end
          counts[gid] += 1
        end
        choices.each { |gid, name| model.set_attribute(DICT, "colour_#{gid}", name) }
        counts
      end

      # Re-applies the job's saved colours (used after converting doors so new
      # style parts pick up the door colour). Groups never chosen are left alone.
      def self.reapply(model)
        chosen = job_choices(model).reject { |_k, v| v.nil? }
        apply(model, chosen) unless chosen.empty?
      end

      # Data for the colour window: names, swatches (rgb or data-URL image), choices.
      def self.dialog_data(model)
        box_swatches = DrawerBox.library.to_h do |b|
          lib = spec(b['material'])
          [b['name'], lib ? nil : { 'rgb' => b['rgb'] }]
        end
        swatches = library.to_h do |c|
          sw = { 'rgb' => c['rgb'] }
          if c['texture']
            f = File.join(TEXTURES, c['texture'])
            sw['img'] = "data:image/jpeg;base64,#{[File.binread(f)].pack('m0')}" if File.exist?(f)
          end
          [c['name'], sw]
        end
        {
          'job' => File.basename(model.path.to_s, '.skp'),
          'groups' => GROUPS, 'names' => names, 'swatches' => swatches,
          'box' => DrawerBox.library.map { |b| { 'name' => b['name'], 'thickness' => b['thickness_mm'], 'code' => b['code'], 'material' => b['material'] } },
          'box_swatches' => box_swatches,
          'current' => job_choices(model), 'defaults' => defaults
        }
      end

      # Writes every library colour to <dir>/<name>.skm (SketchUp 2019.2+).
      def self.export_skm(model, dir)
        names.map do |n|
          m = material(model, n)
          path = File.join(dir, "#{n}.skm")
          m.save_as(path)
          path
        end
      end
    end
  end
end
