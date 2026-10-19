require 'json'
require 'fileutils'
require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Colour library + painting by tag group.
    #
    # Groups (tag lists editable in Settings):
    #   door      Door / Drawer colour            DOOR, DRAWER_FRONT
    #   exterior  Exterior Panel / Trim colour    FACING, END_PAN, NOSING, FILLER
    #   interior  Interior colour                 STL, SH, DIV, INT_DIV, FL, DRAWER, BACK, WALKIN, MDF
    #   worktop   Worktop colour                  WORKTOP
    #   panels_22 22mm Panels                     any panel 22mm thick (by size, not tag),
    #                                             e.g. bookcase shelves/dividers/ends.
    #                                             "Default" = Frost White (Settings panels_22_default).
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
        ['panels_22', '22mm Panels'],
        ['drawer_box', 'Drawer Box']
      ].freeze

      # Built-in colours (colours.json), unless the user has edited the library in
      # Settings -> Colours & materials (saved as "colour_library").
      def self.builtin
        JSON.parse(File.read(FILE))['colours']
      end

      def self.library
        user = Settings.get['colour_library']
        user.is_a?(Array) && !user.empty? ? user : builtin
      end

      # User textures live outside the plugin folder so an update never removes them.
      def self.user_textures
        base = ENV['APPDATA'] || ENV['HOME'] || Dir.tmpdir
        File.join(base, 'HW Door Style', 'textures')
      end

      def self.texture_path(file)
        return nil if file.to_s.empty?
        [File.join(user_textures, file), File.join(TEXTURES, file)].find { |f| File.exist?(f) }
      end

      # Copies a picked image into the user texture folder; returns its file name.
      def self.import_texture(src)
        FileUtils.mkdir_p(user_textures)
        name = File.basename(src).gsub(/[^A-Za-z0-9._ -]/, '_')
        FileUtils.cp(src, File.join(user_textures, name)) unless File.expand_path(src) == File.expand_path(File.join(user_textures, name))
        name
      end

      def self.data_url(file)
        f = texture_path(file) or return nil
        mime = File.extname(f).downcase == '.png' ? 'image/png' : 'image/jpeg'
        "data:#{mime};base64,#{[File.binread(f)].pack('m0')}"
      end

      # Library for the Settings editor (with texture previews).
      def self.editor_library
        library.map { |c| c.merge('img' => data_url(c['texture'])) }
      end

      # After the library is saved: update the model's materials of the same name.
      def self.refresh_materials(model)
        n = 0
        library.each do |c|
          m = model.materials[c['name']] or next
          m.color = Sketchup::Color.new(*c['rgb'])
          if (tp = texture_path(c['texture']))
            m.texture = tp
            size = c['size_mm'].to_f.mm
            m.texture.size = [size, size] if m.texture && size > 0
          elsif m.texture
            m.texture = nil
          end
          n += 1
        end
        n
      end

      # Colours offered on every row (door colours).
      def self.names
        library.reject { |c| c['only'] }.map { |c| c['name'] }
      end

      # Colours offered on one row (adds row-only colours such as White for 22mm panels).
      def self.names_for(gid)
        library.select { |c| c['only'].nil? || c['only'].include?(gid) }.map { |c| c['name'] }
      end

      # --- 22mm panels (matched by thickness) ---

      PANEL_TOL = 0.3 # mm

      def self.panel_mm
        Settings.get['panel_22_mm'].to_f.then { |v| v > 0 ? v : 22.0 }
      end

      PANEL_MIN_FACE = 50 # mm: both other sides at least this, so rails / blocks don't count

      # Real dimensions in mm, thinnest first (DC LenX/Y/Z, else bounds x scale).
      def self.dims_mm(inst)
        dims = %w[lenx leny lenz].map { |k| DC.read(inst, k) }
        unless dims.all? { |v| v.is_a?(Numeric) && v > 0 }
          s, = Finder.decompose(inst.transformation)
          b = inst.definition.bounds
          dims = [b.width * s[0], b.height * s[1], b.depth * s[2]]
        end
        dims.map { |v| v.to_f * 25.4 }.sort
      end

      def self.panel_22?(inst)
        t, a, = dims_mm(inst)
        (t - panel_mm).abs <= PANEL_TOL && a >= PANEL_MIN_FACE
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
        if (tp = texture_path(s['texture']))
          m.texture = tp
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
        # Shipped defaults fill rows the saved settings don't have yet (e.g. new 22mm Panels row).
        d = (Settings.defaults['default_colours'] || {}).merge(Settings.get['default_colours'] || {})
        d['panels_22'] = DEFAULT if d['panels_22'] && !names_for('panels_22').include?(d['panels_22'])
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
        Finder.hardware?(inst) || Hardware.ours?(inst.definition) ||
          !Tagger.hardware_tag_name(inst.definition).nil? ||
          Settings.hardware_tags.key?(inst.layer.name) || inst.layer.name.casecmp?(Tagger::OLD_HARDWARE_TAG)
      end

      # Paints every matching instance with the group's material (nil = Default).
      # Returns { group_id => count }.
      # "Default" on Exterior / Interior / Worktop means "same as the door colour".
      # Default on the door itself means no material.
      # Colour "Default" means on the 22mm Panels row (not the door colour).
      def self.panel_default
        n = Settings.get['panels_22_default'].to_s
        n.empty? ? 'Frost White' : n
      end

      def self.resolve(gid, name, door)
        return (name.nil? || name == DEFAULT ? DrawerBox::DEFAULT : name) if gid == 'drawer_box'
        return name unless name.nil? || name == DEFAULT
        return panel_default if gid == 'panels_22'
        gid == 'door' ? DEFAULT : (door || DEFAULT)
      end

      # plain: every row resolves to no material (library export / Clean model).
      def self.resolved(model, choices, plain: false)
        return choices.to_h { |gid, _| [gid, DEFAULT] } if plain
        door = choices['door'] || model.get_attribute(DICT, 'colour_door', nil)
        choices.to_h { |gid, name| [gid, resolve(gid, name, door)] }
      end

      # root:   entities to walk (default the whole model); an instance is painted too.
      # record: store the choices on the model as the job's colours.
      # dry:    change nothing; count only the parts that would change.
      def self.apply(model, choices, root: nil, record: true, plain: false, dry: false)
        tags = group_tags
        lookup = {}
        tags.each { |gid, list| list.each { |t| lookup[t] = gid } }
        res = resolved(model, choices, plain: plain)
        mats = res.to_h { |gid, name| [gid, gid == 'drawer_box' ? DrawerBox.material(model, name) : material(model, name)] }
        counts = Hash.new(0)
        walk = lambda do |&blk|
          if root.is_a?(Sketchup::ComponentInstance)
            blk.call(root)
            Finder.each_instance(root.definition.entities, &blk)
          else
            Finder.each_instance(root || model.entities, &blk)
          end
        end
        walk.call do |inst|
          next if skip?(inst)
          # Drawer box parts only ever take the Drawer Box finish, never a tag-group colour.
          gid = DrawerBox.part?(inst) ? 'drawer_box' : lookup[effective_tag(inst)]
          # 22mm panels take their own colour (never doors / drawer fronts / boxes).
          gid = 'panels_22' if gid != 'door' && gid != 'drawer_box' && choices.key?('panels_22') && panel_22?(inst)
          next unless gid && choices.key?(gid)
          mat = mats[gid]
          dc = inst.attribute_dictionary('dynamic_attributes')
          dc_mat = dc && dc.keys.include?('material') && !dc['_material_formula'].to_s.strip.start_with?('=')
          if dry
            want = mat ? mat.name : ''
            counts[gid] += 1 if inst.material != mat || (dc_mat && dc['material'].to_s != want)
            next
          end
          inst.material = mat unless inst.material == mat
          inst.set_attribute('dynamic_attributes', 'material', mat ? mat.name : '') if dc_mat
          counts[gid] += 1
        end
        choices.each { |gid, name| model.set_attribute(DICT, "colour_#{gid}", name) } if record && !dry
        counts
      end

      # Every colour row except the drawer box set to Default (no material).
      def self.all_default
        GROUPS.map(&:first).reject { |g| g == 'drawer_box' }.to_h { |g| [g, DEFAULT] }
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
          sw = { 'rgb' => b['rgb'] }
          f = b['texture'] && File.join(TEXTURES, b['texture'])
          sw['img'] = "data:image/jpeg;base64,#{[File.binread(f)].pack('m0')}" if f && File.exist?(f)
          [b['name'], sw]
        end
        swatches = library.to_h do |c|
          sw = { 'rgb' => c['rgb'] }
          sw['img'] = data_url(c['texture']) if c['texture']
          [c['name'], sw]
        end
        {
          'job' => File.basename(model.path.to_s, '.skp'),
          'groups' => GROUPS, 'names' => names, 'swatches' => swatches,
          'group_names' => GROUPS.to_h { |id, _| [id, names_for(id)] }, 'panel_default' => panel_default,
          'box' => DrawerBox.library.map { |b| { 'name' => b['name'], 'thickness' => b['thickness_mm'], 'code' => b['code'], 'material' => b['material'] } },
          'box_swatches' => box_swatches,
          'current' => job_choices(model), 'defaults' => defaults
        }
      end

      # Writes every library colour and drawer box finish to <dir>/<material name>.skm.
      def self.export_skm(model, dir)
        mats = library.map { |c| material(model, c['name']) } + DrawerBox.names.map { |n| DrawerBox.material(model, n) }
        mats.map do |m|
          path = File.join(dir, "#{m.name}.skm")
          m.save_as(path)
          path
        end
      end
    end
  end
end
