# HW Door Style - parts list.
#
# Adapted from OpenCutList by L'Air du Bois (https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension),
# Copyright (C) the OpenCutList contributors, licensed under the GNU General Public License v3.0.
# The part finding, sizing (auto-orient), smart material, edge banding detection, grouping by
# material + standard thickness and letter numbering follow OpenCutList's cut list generator
# (ruby/worker/cutlist/cutlist_generate_worker.rb, model/geom/size3d.rb, model/geom/scale3d.rb,
# helper/bounding_box_helper.rb, utils/axis_utils.rb). Changes for HW Door Style are marked "HW:".
#
# This file is part of HW Door Style and is distributed under the GNU GPL v3.0 (see LICENSE).

require 'set'
require 'json'

module HarryWardrobes
  module DoorStyle
    module PartsList
      OCL = 'ladb_opencutlist'.freeze
      TYPE_UNKNOWN = 0
      TYPE_SOLID_WOOD = 1
      TYPE_SHEET_GOOD = 2
      TYPE_DIMENSIONAL = 3
      TYPE_EDGE = 4
      TYPE_HARDWARE = 5
      TYPE_VENEER = 6
      # OpenCutList's MaterialAttributes.type_order (sheet goods first when a part's faces disagree).
      TYPE_ORDER = { TYPE_SHEET_GOOD => 0, TYPE_SOLID_WOOD => 1, TYPE_DIMENSIONAL => 2, TYPE_HARDWARE => 3,
                     TYPE_EDGE => 4, TYPE_VENEER => 5, TYPE_UNKNOWN => 6 }.freeze
      MM = 25.4

      # --- material attributes (OpenCutList's own, set in Settings > Cut list) ----------------

      def self.mat_type(mat)
        mat ? mat.get_attribute(OCL, 'type', TYPE_UNKNOWN).to_i : TYPE_UNKNOWN
      end

      # Edge and veneer materials are "virtual": they never make a part's material.
      def self.virtual?(mat)
        [TYPE_EDGE, TYPE_VENEER].include?(mat_type(mat))
      end

      def self.mm_list(s)
        s.to_s.split(';').map { |x| x[/[\d.]+/].to_f }.reject(&:zero?)
      end

      # [[length, width]] in mm from "2800 mm x 2070 mm;..."
      def self.sizes_list(s)
        s.to_s.split(';').filter_map do |x|
          a, b = x.split(/x/i).map { |v| v[/[\d.]+/].to_f }
          [a, b] if a.to_f > 0 && b.to_f > 0
        end
      end

      def self.edge_thickness_mm(mat)
        mat ? mat.get_attribute(OCL, 'thickness', '').to_s[/[\d.]+/].to_f : 0.0
      end

      # --- geometry helpers (OpenCutList BoundingBoxHelper / Scale3d / AxisUtils) --------------

      def self.scale_of(t)
        a = t.to_a
        [Geom::Vector3d.new(a[0], a[1], a[2]).length.to_f.round(6),
         Geom::Vector3d.new(a[4], a[5], a[6]).length.to_f.round(6),
         Geom::Vector3d.new(a[8], a[9], a[10]).length.to_f.round(6)]
      end

      def self.faces_bounds(ents, t = nil)
        bb = Geom::BoundingBox.new
        ents.each do |e|
          next if e.is_a?(Sketchup::Edge)
          next unless e.visible?
          if e.is_a?(Sketchup::Face)
            fb = e.bounds
            if t
              fb2 = Geom::BoundingBox.new
              fb2.add(fb.min.transform(t), fb.max.transform(t))
              fb = fb2
            end
            bb.add(fb)
          elsif e.is_a?(Sketchup::Group)
            bb.add(faces_bounds(e.entities, t ? t * e.transformation : e.transformation))
          end
        end
        bb
      end

      # OpenCutList Size3d.create_from_bounds with auto-orient: length = longest, thickness = thinnest;
      # equal values keep the default axis order. Returns [length, width, thickness] (inches) and the axes.
      def self.oriented(bounds, scale)
        ordered = [
          [bounds.width * scale[0], X_AXIS, 2], [bounds.height * scale[1], Y_AXIS, 1], [bounds.depth * scale[2], Z_AXIS, 0]
        ].sort_by { |v, _a, i| [v, i] }
        [[ordered[2][0], ordered[1][0], ordered[0][0]], [ordered[2][1], ordered[1][1], ordered[0][1]]]
      end

      # Faces of a definition (and its groups), split by which axis their normal follows.
      def self.main_faces(ents, x = [], y = [], z = [], t = nil)
        ents.each do |e|
          next if e.is_a?(Sketchup::Edge)
          next unless e.visible?
          if e.is_a?(Sketchup::Face)
            n = t ? e.normal.transform(t) : e.normal
            if n.parallel?(X_AXIS) then x << [e, t]
            elsif n.parallel?(Y_AXIS) then y << [e, t]
            elsif n.parallel?(Z_AXIS) then z << [e, t]
            end
          elsif e.is_a?(Sketchup::Group)
            main_faces(e.entities, x, y, z, t ? t * e.transformation : e.transformation)
          end
        end
        [x, y, z]
      end

      def self.faces_by_normal(axis, x, y, z)
        { X_AXIS => x, Y_AXIS => y, Z_AXIS => z }.find { |a, _| a == axis }&.last || []
      end

      # Faces on the min and max side of the part along one of its oriented axes.
      def self.min_max_faces(bounds, axis, x, y, z)
        mins = []
        maxs = []
        faces_by_normal(axis, x, y, z).each do |f, t|
          plane = (t ? t * f.plane : f.plane).map { |v| v.round(4) }
          if bounds.min.on_plane?(plane) then mins << f
          elsif bounds.max.on_plane?(plane) then maxs << f
          end
        end
        [mins, maxs]
      end

      def self.edge_material(faces)
        faces.map(&:material).compact.find { |m| mat_type(m) == TYPE_EDGE }
      end

      # --- smart material (OpenCutList _get_material) -----------------------------------------

      def self.dominant_child_material(e, level = 0)
        if e.is_a?(Sketchup::Group) || (e.is_a?(Sketchup::ComponentInstance) && level.zero?)
          counts = Hash.new(0)
          (e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities).each do |c|
            m = dominant_child_material(c, level + 1)
            counts[m] += 1 if m
          end
          return counts.min_by { |m, n| [-n, TYPE_ORDER[mat_type(m)] || 9] }&.first unless counts.empty?
          return e.material if level > 0 && !virtual?(e.material)
        elsif e.is_a?(Sketchup::Face)
          return e.material unless virtual?(e.material)
        end
        nil
      end

      def self.material_of(path)
        e = path.last
        m = e.material
        m = nil if virtual?(m)
        m ||= dominant_child_material(e)
        path[0...-1].reverse_each { |p| break if m; m = p.material unless virtual?(p.material) } unless m
        m || job_colour(path)
      end

      # A part with no material of its own (or from its units): the job colour of its colour
      # group (Settings > Colours tags) - its own tag, else the nearest tagged unit above it -
      # as the Colours window resolves it (Default exterior / interior / worktop = the door
      # colour). So an untagged shelf in a BOOKCASE unit counts as the exterior colour.
      def self.colour_context(model)
        lookup = {}
        Colours.group_tags.each { |gid, list| list.each { |t| lookup[t] = gid } }
        choices = Colours.job_choices(model).transform_values { |v| v || Colours::DEFAULT }
        mats = Colours.resolved(model, choices).to_h { |gid, name| [gid, name == Colours::DEFAULT ? nil : model.materials[name]] }
        hw = model.materials[Settings.get['hardware_material'].to_s]
        { lookup: lookup, mats: mats, hardware: hw && mat_type(hw) == TYPE_HARDWARE ? hw : nil }
      rescue StandardError => e
        Log.error('parts list job colours', e)
        nil
      end

      def self.job_colour(path)
        ctx = @colour_ctx or return nil
        g = colour_group(path)
        return ctx[:hardware] if g == :hardware
        return nil if g.nil? || %w[door drawer_box].include?(g)
        ctx[:mats][g]
      end

      # :hardware (hinges, cable outlets... - Settings hardware tags), a colour group id, or nil
      # when nothing in the path is in a colour group (not joinery: switches, sockets, room items).
      def self.colour_group(path)
        ctx = @colour_ctx or return nil
        path.reverse_each do |inst|
          return :hardware if Colours.skip?(inst)
          tag = inst == path.last ? Colours.effective_tag(inst) : (inst.layer == inst.model.layers[0] ? nil : inst.layer.name.upcase)
          gid = tag && ctx[:lookup][tag]
          return gid if gid
        end
        nil
      end

      # --- finding parts (OpenCutList _fetch_useful_instance_infos) ---------------------------
      # A part is a component instance that holds faces itself. HW: tag visibility is ignored
      # (scenes hide DOOR / hinges), only hidden entities (DC options switched off) are skipped.

      def self.collect(ents, path, out, cache)
        count = 0
        ents.each do |e|
          next if e.is_a?(Sketchup::Edge)
          next unless e.visible?
          next if e.is_a?(Sketchup::Group) && e.get_attribute(DICT, 'door_view') # the doors view drawing
          if e.is_a?(Sketchup::Group)
            count += collect(e.entities, path + [e], out, cache)
          elsif e.is_a?(Sketchup::ComponentInstance)
            next if e.definition.behavior.always_face_camera?
            # HW: a hardware component made of sub-parts (CABLE_OUTLET_80 = rim + lid) is one
            # piece of hardware, not its parts.
            if Tagger.hardware_tag_name(e.definition) && e.definition.entities.grep(Sketchup::Face).empty?
              bb = e.definition.bounds
              out << [path + [e], bb] unless bb.empty?
              next
            end
            n = collect(e.definition.entities, path + [e], out, cache)
            if n > 0
              bb = (cache[e.definition] ||= faces_bounds(e.definition.entities))
              if !bb.empty? && [bb.width, bb.height, bb.depth].min > 0
                out << [path + [e], bb]
                next
              end
            end
            count += n
          elsif e.is_a?(Sketchup::Face)
            count += 1
          end
        end
        count
      end

      def self.transformation_of(path)
        path.inject(Geom::Transformation.new) { |t, e| t * e.transformation }
      end

      # --- HW: what the list leaves out --------------------------------------------------------

      def self.tags_of(defn)
        Array(defn.get_attribute(OCL, 'tags', defn.get_attribute(OCL, 'labels', [])))
      end

      # Doors and drawer fronts (OpenCutList's bought-in tag) come with the door summary.
      def self.bought_in?(path)
        tag = OpenCutList.tag
        path.any? { |e| e.respond_to?(:definition) && tags_of(e.definition).include?(tag) }
      end

      # Not part of the furniture at all - electrical faceplates and the like: a component
      # from a library folder in Settings "ignore_component_folders" (by the file it was
      # loaded from), or anything on a tag in "ignore_tags" (sockets, switches).
      def self.ignored?(path)
        folders = Settings.get['ignore_component_folders']
        folders = Array(folders).map { |f| f.to_s.downcase }.reject(&:empty?)
        tags = Settings.get['ignore_tags']
        tags = Array(tags).map { |t| t.to_s.downcase }.reject(&:empty?)
        path.any? do |e|
          next true if tags.include?(e.layer.name.to_s.downcase)
          next false unless e.respond_to?(:definition)
          p = e.definition.path.to_s.tr('\\', '/').downcase
          !p.empty? && folders.any? { |f| p.include?("/#{f}/") }
        end
      end

      def self.r1(inches)
        (inches.to_f * MM).round(1)
      end

      # Nearest standard thickness ("available" = matches one exactly), OpenCutList _find_std_value.
      def self.std_thickness(t_mm, std)
        hit = std.find { |s| (s - t_mm).abs < 0.05 }
        [hit || t_mm, !hit.nil?]
      end

      # OpenCutList AxisUtils.flipped? (mirrored).
      def self.flipped?(x, y, z)
        skewed = ![x % y, y % z, z % x].all? { |v| v.abs < Float::EPSILON }
        skewed ? (x % X_AXIS) * (y % Y_AXIS) * (z % Z_AXIS) < 0 : !(x * y).samedirection?(z)
      end

      # OpenCutList's cut list options as saved for this model (else globally, else its defaults).
      CUTLIST_DEFAULTS = { 'flipped_detection' => true, 'dynamic_attributes_name' => false, 'part_number_with_letters' => true,
                           'part_number_sequence_by_group' => true, 'part_folding' => false,
                           'part_order_strategy' => '-thickness>-length>-width>-count>name>-edge_pattern>tags>thickness_layer_count' }.freeze

      def self.cutlist_options(model)
        read = ->(v) { v.is_a?(String) ? (JSON.parse(v) rescue {}) : (v.is_a?(Hash) ? v : {}) }
        m = read.call(read.call(model.get_attribute(OCL, 'core.presets', {}))['cutlist_options'])['0']
        g = read.call(read.call(read.call(Sketchup.read_default(OCL, 'core.presets', {}))['cutlist_options'])['0'])['_default'] rescue nil
        CUTLIST_DEFAULTS.merge(read.call(g)).merge(read.call(m)).slice(*CUTLIST_DEFAULTS.keys)
      end

      # --- the list ----------------------------------------------------------------------------
      # OpenCutList phase 1: a part = one definition at one size (and mirrored or not); the first
      # instance found sets its name and edges. Groups = material + standard thickness.

      # Which Workshop tab a board part goes on: bullnose / cornice and 22mm (white back)
      # panels with the doors (vinyl), worktops (22 / 25 mm) on their own, the rest is sheet goods.
      VINYL_RE = /BULLNOSE|CORNICE/i.freeze
      WORKTOP_RE = /WRKTP|WORKTOP/i.freeze

      # Part type kept on the part's component ("part_role" on the definition), like the
      # front types: worktop, vinyl (bullnose / cornice), white_back (22mm) or sheet. It wins
      # over the name / thickness rules below.
      PART_ROLE = 'part_role'.freeze
      PART_ROLES = { 'worktop' => 'worktops', 'vinyl' => 'vinyl', 'white_back' => 'white_back', 'sheet' => 'sheets' }.freeze
      PART_ROLE_LABELS = [['worktop', 'Worktop'], ['vinyl', 'Bullnose / cornice (vinyl)'], ['white_back', '22mm white back'], ['sheet', 'Sheet goods']].freeze

      def self.part_role(defn)
        r = defn.get_attribute(DICT, PART_ROLE).to_s
        r.empty? ? nil : r
      end

      def self.section_of(names, thickness, material, role = nil)
        return PART_ROLES[role] if role && PART_ROLES[role]
        return 'vinyl' if names.any? { |n| n.to_s =~ VINYL_RE }
        return 'worktops' if names.any? { |n| n.to_s =~ WORKTOP_RE } && [22, 25].include?(thickness.to_f.round) && material.to_s !~ /\AMDF\z/i
        # 22mm panels are white-backed vinyl, ordered with the doors.
        return 'white_back' if thickness.to_f.round == 22 && material.to_s !~ /\AMDF\z/i
        'sheets'
      end

      def self.gid_of(material, thickness, section)
        "#{material}|#{f1(thickness)}#{section == 'sheets' ? '' : "|#{section}"}"
      end

      def self.drawer_box?(name)
        Settings.names('drawer_box_parts').include?(name.to_s.sub(/#\d+\z/, '').strip.upcase)
      end

      def self.generate(model = Sketchup.active_model)
        # a plugin colour that OpenCutList doesn't know yet is set up on the spot (never a question)
        unless defined?(LibraryExport) && LibraryExport.master?(model)
          set = OpenCutList.ensure!(model)
          Log.info("OpenCutList settings written for #{set.join(', ')}") unless set.empty?
        end
        opts = cutlist_options(model)
        @pieces = {} # entity id -> the placed piece, so part numbers can be kept on it
        found = []
        collect(model.entities, [], found, {})
        groups = {}
        hardware = {}
        @timber = {}
        @untyped = Hash.new(0) # material name ('' = no colour) -> parts left out
        @nocolour = Hash.new(0) # part name -> pieces with no colour
        @colour_ctx = colour_context(model)
        skipped = Hash.new(0)
        found.each do |path, bounds|
          if bought_in?(path)
            skipped['bought_in'] += 1
            next
          end
          if ignored?(path)
            skipped['ignored'] += 1
            next
          end
          inst = path.last
          defn = inst.definition
          mat = material_of(path)
          type = mat_type(mat)
          t = transformation_of(path)
          size, axes = oriented(bounds, scale_of(t))
          l_mm, w_mm, th_mm = size.map { |v| r1(v) }
          flipped = opts['flipped_detection'] && !defn.get_attribute(OCL, 'symmetrical', false) && flipped?(t.xaxis, t.yaxis, t.zaxis)
          name = defn.name
          if opts['dynamic_attributes_name'] && (dn = inst.get_attribute('dynamic_attributes', 'name'))
            name = dn.to_s
          end
          pid = [defn.entityID, (opts['dynamic_attributes_name'] ? name : ''), l_mm, w_mm, th_mm, flipped].join('|')
          case type
          when TYPE_SHEET_GOOD
            std = mm_list(mat.get_attribute(OCL, 'std_thicknesses', ''))
            th_std, available = std_thickness(th_mm, std)
            section = section_of([name, defn.name], th_std, mat.name, part_role(defn))
            gid = gid_of(mat.name, th_std, section)
            g = (groups[gid] ||= { 'material' => mat.name, 'thickness' => th_std, 'std_ok' => true, 'section' => section, 'grained' => mat.get_attribute(OCL, 'grained', false) ? true : false,
                                   'sheet' => sizes_list(mat.get_attribute(OCL, 'std_sizes', '')).max_by { |a, b| a * b },
                                   'all_sizes' => sizes_list(mat.get_attribute(OCL, 'std_sizes', '')), 'parts' => {} })
            g['std_ok'] &&= available
            p = g['parts'][pid]
            unless p
              x, y, z = main_faces(defn.entities)
              swap = opts['flipped_detection'] && (flipped?(t.xaxis, t.yaxis, t.zaxis) ^ flipped?(*axes))
              xmin, xmax = min_max_faces(bounds, axes[0], x, y, z)
              xmin, xmax = xmax, xmin if swap
              ymin, ymax = min_max_faces(bounds, axes[1], x, y, z)
              # ymin / ymax run along the length, xmin / xmax are the ends.
              edges = { 'ymin' => edge_material(ymin), 'ymax' => edge_material(ymax), 'xmin' => edge_material(xmin), 'xmax' => edge_material(xmax) }
              p = g['parts'][pid] = { 'name' => name, 'length' => l_mm, 'width' => w_mm, 'thickness' => th_mm, 'raw' => size.map(&:to_f), 'qty' => 0, 'flipped' => flipped,
                                      'edges' => edges.transform_values { |m| m&.name }, 'edge_colors' => edges.transform_values { |m| m && color_hex(m.color) },
                                      'edge_pattern' => %w[ymax xmax ymin xmin].map { |k| edges[k] ? 1 : 0 }.join, 'edge_count' => edges.values.compact.size,
                                      'tags' => tags_of(defn), 'instances' => [] }
            end
            p['qty'] += 1
            p['instances'] << instance_info(path)
          when TYPE_HARDWARE
            hg = (hardware[mat.name] ||= {})
            h = (hg[pid] ||= { 'name' => name, 'material' => mat.name, 'drawer_box' => drawer_box?(defn.name) || drawer_box?(name) || runner?(defn.name), 'length' => l_mm, 'width' => w_mm, 'thickness' => th_mm, 'raw' => size.map(&:to_f), 'qty' => 0, 'flipped' => flipped,
                               'edge_pattern' => '', 'edge_count' => 0, 'tags' => tags_of(defn), 'instances' => [] })
            h['qty'] += 1
            h['instances'] << instance_info(path)
          when TYPE_DIMENSIONAL
            # Timber (e.g. the 2x1 battens): its length is the longest side; the section is the other two.
            dims = [l_mm, w_mm, th_mm].sort.reverse
            tp = (@timber[pid] ||= { 'name' => name, 'material' => mat.name, 'length' => dims[0], 'section' => "#{fmt(dims[2])} x #{fmt(dims[1])}",
                                     'width' => dims[1], 'thickness' => dims[2], 'raw' => size.map(&:to_f), 'qty' => 0, 'flipped' => flipped,
                                     'edge_pattern' => '', 'edge_count' => 0, 'tags' => tags_of(defn), 'instances' => [] })
            tp['qty'] += 1
            tp['instances'] << instance_info(path)
          else
            # no colour and not in any colour group: not joinery (a switch or socket on the
            # wall, a room item) - not a part, so not "left out" either
            if type == TYPE_UNKNOWN && mat.nil? && @colour_ctx && colour_group(path).nil?
              skipped['not_joinery'] += 1
              next
            end
            skipped[type == TYPE_UNKNOWN ? 'no_type' : 'other'] += 1
            @untyped[mat ? mat.name : ''] += 1 if type == TYPE_UNKNOWN
            @nocolour[name] += 1 if type == TYPE_UNKNOWN && mat.nil?
          end
        end
        finish(model, groups, hardware, skipped, opts)
      end

      # Lengths as SketchUp shows them in this model (what OpenCutList prints, e.g. "1200 mm").
      def self.length_s(mm)
        (mm.to_f / MM).to_l.to_s
      rescue StandardError
        "#{fmt(mm)} mm"
      end

      def self.add_strings(p)
        l, w, t = p.delete('raw') || [p['length'], p['width'], p['thickness']].map { |v| v / MM }
        p['length_s'] = l.to_l.to_s
        p['width_s'] = w.to_l.to_s
        p['thickness_s'] = t.to_l.to_s
        mx = [l, w].max.to_f
        p['l_ratio'] = mx > 0 ? l / mx : 1
        p['w_ratio'] = mx > 0 ? w / mx : 1
      end

      # What a label needs about one placed piece (OpenCutList InstanceInfo).
      def self.instance_info(path)
        e = path.last
        (@pieces ||= {})[e.entityID] = e
        { 'layer' => e.layer.name, 'entity_name' => e.name.to_s, 'top' => path.first&.entityID,
          'eid' => e.entityID, 'part_no' => e.get_attribute(DICT, PART_NO),
          'named_path' => path[0...-1].map { |x| x.name.to_s }.reject(&:empty?).join('.') } # OpenCutList PathUtils.get_named_path
      end

      # OpenCutList ColorUtils.color_visible_over_white + color_to_hex.
      def self.color_hex(c)
        return nil unless c
        l = (0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue) / 255.0
        if l >= 0.6
          amount = 0.2 * (l - 0.6) / 0.4
          c = c.blend(Sketchup::Color.new(0, 0, 0), 1.0 - [1, [0, amount].max].min)
        end
        format('#%02x%02x%02x', c.red, c.green, c.blue)
      end

      def self.waste_pct
        v = Settings.get['parts_sheet_waste_pct']
        v.nil? ? 20.0 : v.to_f
      end

      # OpenCutList PartDef.part_order (equal parts: not mirrored first).
      def self.part_order(a, b, strategy)
        av = []
        bv = []
        strategy.to_s.split('>').each do |prop|
          next if prop.empty?
          desc = prop.start_with?('-')
          prop = prop.delete_prefix('-')
          x, y = case prop
                 when 'length' then [[a['length']], [b['length']]]
                 when 'width' then [[a['width']], [b['width']]]
                 when 'thickness' then [[a['thickness']], [b['thickness']]]
                 when 'name' then [[a['name'].downcase], [b['name'].downcase]]
                 when 'count' then [[a['qty']], [b['qty']]]
                 when 'edge_pattern' then [[a['edge_count'], a['edge_pattern']], [b['edge_count'], b['edge_pattern']]]
                 when 'tags' then [[a['tags']], [b['tags']]]
                 when 'thickness_layer_count' then [[1], [1]]
                 else next
                 end
          desc ? (av.concat(y); bv.concat(x)) : (av.concat(x); bv.concat(y))
        end
        r = av <=> bv
        r = (av + [a['flipped'] ? 1 : 0]) <=> (bv + [b['flipped'] ? 1 : 0]) if r.to_i.zero?
        r.to_i
      end

      # Cut and edged strips (Settings > Cut list): HPP's 18mm strips, the next width up for
      # each part, packed end to end; 1000 x 2800 for the colours that offer it. Parts wider than
      # the widest strip (or longer than a strip) are "manual": you enter the full sheets.
      STRIP_THICKNESS = 18.0

      def self.strip_widths(material)
        s = Settings.get
        w = Array(s['strip_widths_mm']).map(&:to_f).select(&:positive?)
        w = [90, 160, 300, 500, 570, 610].map(&:to_f) if w.empty?
        w << 1000.0 if Array(s['strip_1000_colours']).any? { |c| c.to_s.casecmp?(material.to_s) }
        w.uniq.sort
      end

      def self.strip_length
        v = Settings.get['strip_length_mm'].to_f
        v.positive? ? v : 2800.0
      end

      def self.strip_group?(g)
        (g['thickness'] - STRIP_THICKNESS).abs < 0.5
      end

      # [strips, manual parts]: strips [{ width, length, count, numbers, pieces }].
      def self.strips_for(g, parts)
        widths = strip_widths(g['material'])
        len = strip_length
        by_w = Hash.new { |h, k| h[k] = [] }
        manual = []
        parts.each do |p|
          w = widths.find { |x| p['width'] <= x + 0.01 }
          if w.nil? || p['length'] > len + 0.01
            manual << p
          else
            by_w[w] << p
          end
        end
        strips = by_w.keys.sort.map do |w|
          ps = by_w[w]
          bins = []
          ps.flat_map { |p| [p['length']] * p['qty'] }.sort.reverse.each do |l|
            i = bins.index { |x| x + l <= len + 0.01 }
            i ? bins[i] += l : bins << l
          end
          { 'width' => w.round, 'length' => len, 'count' => bins.size, 'numbers' => ps.map { |p| p['number'] }, 'pieces' => ps.sum { |p| p['qty'] } }
        end
        [strips, manual]
      end

      def self.f1(v) = format('%g', v.to_f.round(1))

      # Full sheets you entered in the Workshop window, kept in the model: { "Graphite|18" => 2 }.
      def self.entered_sheets
        @entered || {}
      end

      def self.load_entered(model)
        @entered = JSON.parse(model.get_attribute(DICT, 'workshop_sheets', '{}').to_s) rescue {}
      end

      def self.save_entered(model, map)
        clean = map.to_h { |k, v| [k.to_s, v] }.reject { |_k, v| v.nil? || v.to_s.strip.empty? }.transform_values { |v| [v.to_i, 0].max }
        Ops.run(model, 'Workshop: sheets entered', transparent: true) { model.set_attribute(DICT, 'workshop_sheets', JSON.generate(clean)) }
        @entered = clean
      end

      def self.slug(s)
        s.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
      end

      # What the parts list puts on the Room: full sheets per colour (mfc_sheets_<colour>, only
      # the fields that exist), the total, and the cut and edged strips.
      def self.room_values(d)
        out = {}
        per = Hash.new(0)
        # MFC sheets only: worktops and bullnose / cornice are ordered on their own.
        d['groups'].each { |g| per[g['material']] += g['sheets'].to_i if g['section'].to_s.empty? || g['section'] == 'sheets' }
        per.each { |m, n| out["mfc_sheets_#{slug(m)}"] = n }
        out['mfc_quantity'] = per.values.sum
        widths = (strip_widths('') + [1000.0]).map(&:round).uniq
        widths.each { |w| out["cut_and_edged_#{w}mm_quantity"] = d['groups'].sum { |g| Array(g['strips']).select { |st| st['width'] == w }.sum { |st| st['count'] } } }
        out
      end

      # --- part numbers: 1, 2, 3 ... per room file -------------------------------------------
      # Identical parts share one number (as OpenCutList's letters did), running across the
      # whole file (sheet goods then hardware) so a number - and the label barcode built from
      # it - is unique in the room. Each number is kept on the part's pieces ("part_no"), so a
      # part keeps its number when the list is made again; new parts get the next number after
      # the highest. "Renumber parts" clears them and starts again from 1. The library master
      # is never numbered.
      PART_NO = 'part_no'.freeze

      # The placed pieces found by the last generate (entity id -> entity).
      def self.pieces = @pieces || {}

      def self.number_parts(model, parts)
        keep = !(defined?(LibraryExport) && LibraryExport.master?(model))
        taken = {}
        todo = []
        parts.each do |p|
          olds = Array(p['instances']).filter_map { |i| i['part_no'].to_i if i['part_no'].to_i.positive? }
          n = olds.tally.sort_by { |v, c| [-c, v] }.map(&:first).find { |v| !taken[v] }
          if keep && n
            p['number'] = n
            taken[n] = true
          else
            todo << p
          end
        end
        nxt = taken.keys.max.to_i
        todo.each { |p| p['number'] = (nxt += 1) }
        return unless keep
        changed = parts.flat_map { |p| Array(p['instances']).select { |i| i['part_no'].to_i != p['number'] }.map { |i| [i['eid'], p['number']] } }.uniq
        unless changed.empty?
          Ops.run(model, 'Part numbers', transparent: true) do
            changed.each do |eid, n|
              e = @pieces && @pieces[eid]
              e.set_attribute(DICT, PART_NO, n) if e&.valid?
            end
          end
        end
        parts.each { |p| Array(p['instances']).each { |i| i['part_no'] = p['number'] } }
      end

      # Every piece's number cleared (one undo step); the next list numbers from 1.
      def self.renumber_parts(model)
        Ops.run(model, 'Renumber parts') do
          seen = {}
          walk = lambda do |ents|
            ents.each do |e|
              next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
              next if seen[e.entityID]
              seen[e.entityID] = true
              e.delete_attribute(DICT, PART_NO) if e.get_attribute(DICT, PART_NO)
              walk.call(e.respond_to?(:definition) ? e.definition.entities : e.entities)
            end
          end
          walk.call(model.entities)
        end
      end

      def self.first_number(_opts) = 1

      # Hardware consolidated by its label name (Settings > Labels > Label names: SHELF_BRACKET
      # -> "Shelf pegs"): one line per name, with the part numbers and components it covers.
      # Items that share a name but not a length (the hanging rails) get the length in the
      # name - "Hanging rail 775" - so they stay apart.
      def self.hardware_lines(hardware)
        by = Hash.new { |h, k| h[k] = [] }
        hardware.each { |h| by[Labels.display_name(h['name'], 'hardware')] << h }
        by.flat_map do |name, list|
          lengths = list.map { |h| h['length'].to_f.round }.uniq
          list.group_by { |h| lengths.size > 1 ? h['length'].to_f.round : nil }.map do |len, part|
            { 'name' => len ? "#{name} #{len}" : name, 'qty' => part.sum { |h| h['qty'].to_i },
              'numbers' => part.map { |h| h['number'] }.uniq.sort, 'parts' => part.map { |h| h['name'] }.uniq,
              'material' => part.first['material'], 'drawer_box' => part.all? { |h| h['drawer_box'] } }
          end
        end.sort_by { |r| r['name'].downcase }
      end

      # Timber and MDF together (both ordered as lengths): one line per name, section and length.
      def self.timber_lines(timber)
        timber.group_by { |t| [t['name'], t['section'], t['length'].to_f.round] }.map do |(name, section, len), list|
          { 'name' => name, 'material' => list.first['material'], 'section' => section, 'length' => len,
            'qty' => list.sum { |t| t['qty'].to_i }, 'numbers' => list.map { |t| t['number'] }.uniq.sort }
        end.sort_by { |r| [r['material'].to_s.downcase, r['section'].to_s, -r['length']] }
      end

      # OpenCutList phase 2: groups by material type > name > thickness; parts sorted by the
      # part order strategy and numbered A, B ... (again from A in each group, as set in OpenCutList).
      def self.finish(model, groups, hardware, skipped, opts = CUTLIST_DEFAULTS)
        load_entered(model)
        strategy = opts['part_order_strategy']
        edging = Hash.new { |h, k| h[k] = { 'material' => k[0], 'height' => k[1], 'metres' => 0.0, 'parts' => 0 } }
        ordered = groups.values.sort_by { |g| [g['material'].downcase, -g['thickness']] }
        ordered.each { |g| g['parts'] = g['parts'].values.sort { |a, b| part_order(a, b, strategy) } }
        hw_parts = hardware.keys.sort_by(&:downcase).flat_map { |mname| hardware[mname].values.sort { |a, b| part_order(a, b, strategy) } }
        timber = (@timber || {}).values.sort_by { |t| [t['material'].to_s.downcase, -t['length']] }
        number_parts(model, ordered.flat_map { |g| g['parts'] } + hw_parts + timber)
        sheet_groups = ordered.map do |g|
          parts = g['parts']
          parts.each do |p|
            p['area_m2'] = (p['length'] * p['width'] * p['qty'] / 1_000_000.0).round(3)
            add_strings(p)
            p['edges'].each do |side, em|
              next unless em
              run = side.start_with?('y') ? p['length'] : p['width']
              e = edging[[em, g['thickness']]]
              e['metres'] += run * p['qty'] / 1000.0
              e['parts'] += p['qty']
            end
          end
          strips, manual = strip_group?(g) ? strips_for(g, parts) : [[], parts]
          in_strips = strips.flat_map { |st| st['numbers'] }
          area = manual.sum { |p| p['area_m2'] }
          sheet = g['sheet']
          estimate = nil
          if sheet && area.positive?
            usable = sheet[0] * sheet[1] / 1_000_000.0 * (1 - waste_pct / 100.0)
            estimate = usable > 0 ? (area / usable).ceil : nil
          end
          estimate = 0 if manual.empty?
          gid = gid_of(g['material'], g['thickness'], g['section'])
          entered = entered_sheets[gid]
          # 18mm: strips cover what they can; anything else you enter. Other thicknesses: the estimate, unless you changed it.
          ask = strip_group?(g) && !manual.empty?
          sheets = entered.nil? ? (ask ? nil : estimate) : entered.to_i
          too_big = sheet ? parts.select { |p| [p['length'], p['width']].max > sheet.max || [p['length'], p['width']].min > sheet.min }.map { |p| p['number'] } : []
          g.merge('parts' => parts, 'count' => parts.sum { |p| p['qty'] }, 'area_m2' => area.round(2), 'sheets' => sheets, 'too_big' => too_big,
                  'strips' => strips, 'in_strips' => in_strips, 'manual' => manual.map { |p| p['number'] }, 'ask' => ask,
                  'estimate' => estimate, 'entered' => !entered.nil?, 'gid' => gid, 'strip_group' => strip_group?(g))
        end
        edge_list = edging.values.map { |e| e.merge('metres' => e['metres'].round(1)) }.sort_by { |e| [e['material'], e['height']] }
        hw = hw_parts.each { |h| add_strings(h) }
        timber.each { |t| add_strings(t) }
        {
          'job' => File.basename(model.path.to_s, '.skp'), 'date' => Time.now.strftime('%d/%m/%Y %H:%M'), 'version' => VERSION,
          'head' => (RoomPlan.head(model, nil) rescue {}),
          'groups' => sheet_groups, 'edging' => edge_list, 'hardware' => hw, 'hardware_lines' => hardware_lines(hw.reject { |h| h['drawer_box'] }),
          'timber' => timber, 'timber_lines' => timber_lines(timber), 'handles' => handles(model), 'drawer_boxes' => drawer_boxes(model),
          'skipped' => skipped, 'untyped' => (@untyped || {}).map { |n, c| { 'name' => n, 'count' => c } }.sort_by { |u| u['name'] }, 'nocolour' => (@nocolour || {}).map { |n, c| c > 1 ? "#{n} x#{c}" : n }.sort, 'waste_pct' => waste_pct, 'scribes_on' => Pencil.on?(model) || Runouts.units(model.entities).empty?,
          'filename' => File.basename(model.path.to_s), 'model_name' => model.name.to_s, 'page_name' => model.pages.selected_page&.name.to_s,
          'labels' => Labels.options(model), 'cutlist_options' => opts
        }
      end

      # HW: handles aren't drawn - they come from the Door style window and the door summary counts.
      # --- drawer boxes (Drawer Boxes tab) ------------------------------------------------
      # One row per drawer unit, box material, size and runner: parent unit, internal cabinet
      # width (box width + the box clearance each side), box height (warning under 100 mm),
      # runner length with its type, quantity. Pull-outs with runners but no box get a row too.
      RUNNER_RE = /RUNNER_?(\d+)/i.freeze
      BOX_MIN_MM = 100

      def self.runner_label(mm)
        mm ? "#{mm.round}mm #{Settings.get['drawer_runner_type'].to_s.strip.then { |t| t.empty? ? 'Drawer Runners' : t }}" : '-'
      end

      def self.runner?(name)
        name.to_s =~ RUNNER_RE ? true : false
      end

      def self.unit_mm(unit, base)
        v = DC.value(unit, base)
        v.nil? || v.to_s.strip.empty? ? nil : v.to_f * 25.4
      end

      def self.drawer_boxes(model)
        rows = {}
        add = lambda do |unit, mat, width, height, runner|
          key = [unit.definition.name, mat, width, height, runner]
          r = (rows[key] ||= { 'parent' => unit.definition.name, 'material' => mat, 'width' => width, 'height' => height,
                               'runner_mm' => runner, 'runner' => runner_label(runner), 'qty' => 0,
                               'warn' => height && height < BOX_MIN_MM ? "Box height under #{BOX_MIN_MM} mm" : nil })
          r['qty'] += 1
        end
        walk = lambda do |ents, path, unit|
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            next unless e.visible?
            here = path + [e]
            u = unit
            u = e if e.is_a?(Sketchup::ComponentInstance) && DC.key(e, 'blum_runner_length')
            if e.is_a?(Sketchup::ComponentInstance) && drawer_box?(e.definition.name) && u
              i0 = here.index(u)
              t = transformation_of(here[i0..])
              sx, _sy, sz = scale_of(t)
              b = e.definition.bounds
              clear = unit_mm(u, 'drwr_box_clearance') || 5.0
              width = (b.width * sx * 25.4 + 2 * clear).round
              height = (b.depth * sz * 25.4).round
              runner = unit_mm(u, 'blum_runner_length')&.round
              add.call(u, material_of(here)&.name || '-', width, height, runner)
              next
            end
            if e.is_a?(Sketchup::ComponentInstance) && runner?(e.definition.name) && u
              # a pull-out (no box): one row per pair of runners
              (@pullout ||= Hash.new(0))[[u.entityID, path.last&.entityID]] += 1
            end
            walk.call(e.respond_to?(:definition) ? e.definition.entities : e.entities, here, u)
          end
        end
        @pullout = Hash.new(0)
        walk.call(model.entities, [], nil)
        list = rows.values
        boxed_units = list.map { |r| r['parent'] }
        units = {}
        model.definitions.each { |d| d.instances.each { |i| units[i.entityID] = i } } unless @pullout.empty?
        @pullout.each_key do |(uid, _grp)|
          u = units[uid] or next
          next if boxed_units.include?(u.definition.name)
          runner = unit_mm(u, 'blum_runner_length')&.round
          width = (unit_mm(u, 'width') || unit_mm(u, 'cab_width'))&.round
          key = [u.definition.name, '(pull-out)', width, nil, runner]
          r = (rows[key] ||= { 'parent' => u.definition.name, 'material' => '(pull-out, no box)', 'width' => width, 'height' => nil,
                               'runner_mm' => runner, 'runner' => runner_label(runner), 'qty' => 0, 'warn' => nil })
          r['qty'] += 1
        end
        letter = 'A'
        rows.values.sort_by { |r| [r['parent'], r['material'].to_s, -(r['height'] || 0)] }.each { |r| r['number'] = letter; letter = letter.succ }
      end

      def self.handles(model)
        c = HubSpotRoom.counts(model)
        names = DoorStyleWindow.handle_names(model)
        [['main_robe_handle', 'main_robe_handle_id', 'robe_handle_supplier', 'Robe handle', c['h_door']],
         ['drawer_handle', 'drawer_handle_sku', 'drawer_handle_supplier', 'Drawer handle', c['h_ext']],
         ['interior_handle', 'interior_handle_sku', 'interior_handle_supplier', 'Interior handle', c['h_int']]].filter_map do |k, sku, sup, label, qty|
          n = names[k].to_s
          next if n.casecmp?('n/a') || (n.empty? && qty.to_i.zero?)
          { 'kind' => label, 'name' => n.empty? ? '(not chosen - Door style)' : n, 'sku' => names[sku].to_s,
            'supplier' => names[sup].to_s.empty? ? '' : HubSpotProducts.supplier_label(names[sup]), 'qty' => qty.to_i }
        end
      rescue StandardError => e
        Log.error('parts list handles', e)
        []
      end

      # --- CSV ---------------------------------------------------------------------------------

      def self.csv(d)
        q = ->(v) { s = v.to_s; s =~ /[",\n]/ ? "\"#{s.gsub('"', '""')}\"" : s }
        rows = [%w[Section Number Name Material Length_mm Width_mm Thickness_mm Qty Edge_L1 Edge_L2 Edge_W1 Edge_W2 SKU Supplier]]
        d['groups'].each do |g|
          g['parts'].each do |p|
            rows << ['Sheet goods', p['number'], p['name'], g['material'], p['length'], p['width'], g['thickness'], p['qty'],
                     p['edges']['ymin'], p['edges']['ymax'], p['edges']['xmin'], p['edges']['xmax'], '', '']
          end
        end
        d['groups'].each { |g| rows << ['Boards', '', "#{g['material']} #{fmt(g['thickness'])}mm", g['material'], *(g['sheet'] || ['', '']), g['thickness'], g['sheets'], '', '', '', '', '', ''] }
        d['groups'].each { |g| Array(g['strips']).each { |st| rows << ['Cut and edged', st['numbers'].join(' '), "#{st['width']}mm strip", g['material'], st['length'], st['width'], g['thickness'], st['count'], '', '', '', '', '', ''] } }
        d['edging'].each { |e| rows << ['Edging', '', "#{e['material']} (#{fmt(e['height'])}mm)", e['material'], e['metres'] * 1000, '', e['height'], '', '', '', '', '', '', ''] }
        d['hardware'].each { |h| rows << ['Hardware', h['number'], h['name'], h['material'], h['length'], h['width'], h['thickness'], h['qty'], '', '', '', '', '', ''] }
        d['handles'].each { |h| rows << ['Handles', '', "#{h['kind']}: #{h['name']}", '', '', '', '', h['qty'], '', '', '', '', h['sku'], h['supplier']] }
        rows.map { |r| r.map(&q).join(',') }.join("\r\n") + "\r\n"
      end

      def self.fmt(v)
        f = v.to_f
        f == f.round ? f.round.to_s : format('%.1f', f)
      end

      # --- files next to the .skp: PARTS_LIST_v<N>_<file>.csv / .pdf --------------------------

      def self.stem(dir, base, v)
        File.join(dir, "PARTS_LIST_v#{v}_#{Report.safe_name(base)}")
      end

      def self.next_version(dir, base, recorded)
        re = /\APARTS_LIST_v(\d+)_#{Regexp.escape(Report.safe_name(base))}\.(csv|pdf)\z/i
        found = Dir.exist?(dir) ? Dir.children(dir).map { |f| f[re, 1].to_i }.max.to_i : 0
        [found, recorded.to_i].max + 1
      end

      # Writes both files; returns [csv_path, pdf_path, version].
      def self.export(model, d)
        raise 'Save the SketchUp file first - the parts list is saved next to it.' if model.path.to_s.empty?
        dir = File.dirname(model.path)
        base = File.basename(model.path, '.skp')
        v = next_version(dir, base, model.get_attribute(DICT, 'parts_list_version', 0))
        s = stem(dir, base, v)
        File.write("#{s}.csv", "﻿" + csv(d), mode: 'w:UTF-8') if Report.csv?
        PartsPdf.write("#{s}.pdf", d.merge('list_version' => v))
        Ops.run(model, 'Record parts list export', transparent: true) { model.set_attribute(DICT, 'parts_list_version', v) }
        [Report.csv? ? "#{s}.csv" : nil, "#{s}.pdf", v]
      end

      # --- HubSpot: the Room's "Order / Parts List" file field --------------------------------

      FIELD = 'order_parts_list'.freeze

      # --- window: Workshop (door order + parts list + labels + HubSpot) ---------------------

      def self.show
        model = Sketchup.active_model
        # The room name goes on the labels and PDFs: asked for once per file (pre-filled).
        if !model.path.to_s.empty? && JobInfo.room_name_needed?(model)
          r = UI.inputbox(['Room name'], [JobInfo.room_name_guess(model)], 'Workshop - which room is this?')
          JobInfo.save(model, 'room_name' => r[0]) if r && !r[0].to_s.strip.empty?
        end
        data = nil
        tops_map = {}
        # Labels tab: every part name with whether it gets one grouped label, and the timber stock.
        label_parts = lambda do
          modes = Labels.modes(model)
          rows = data['groups'].flat_map { |g| g['parts'].map { |p| [p, 'sheet'] } } + data['hardware'].map { |h| [h, 'hardware'] } + Array(data['timber']).map { |t| [t, 'timber'] }
          data['label_parts'] = rows.group_by { |p, _k| p['name'] }.map do |name, list|
            kind = list.first[1]
            { 'name' => name, 'kind' => kind, 'qty' => list.sum { |p, _k| p['qty'].to_i }, 'display' => Labels.display_name(name, kind),
              'aggregate' => Labels.aggregate?(name, kind, modes), 'rule' => Labels.rule_aggregate?(name, kind), 'set' => modes.key?(name.to_s.upcase) }
          end.sort_by { |r| [r['aggregate'] ? 0 : 1, r['name'].downcase] }
          data['timber_stock'] = Labels.stock_mm(model)
        end
        build = lambda do
          data = generate(model)
          data['door'] = Report.payload(model)
          data['export_csv'] = Report.csv?
          prods, tops_map = Products.list(model)
          data['products'] = prods
          data['loose_internals'] = Products.loose_internals
          data['product_key'] = Products.key(prods.map { |p| p['ref'] })
          data['job_info'] = JobInfo.get(model)
          data['pdfs'] = Workshop.pdfs(model)
          data['checks'] = (Workshop.checks(model, data) rescue (Log.error('workshop checks', $!); []))
          data['blockers'] = Workshop.blockers(model, data)
          label_parts.call
        end
        dlg = Dialog.open('parts_list', title: 'HW - Workshop', key: 'hw_parts_list', width: 1060, height: 740, data: nil)
        fail_js = ->(e) { dlg.execute_script("failed(#{JSON.generate(e.message)})") }
        reload = lambda do
          Steps.run(dlg, [['Reading the parts in the model', build]],
                    done: ->(_r) { dlg.execute_script("render(#{JSON.generate(data)})") }, fail: fail_js, count: false)
        end
        dlg.add_action_callback('ready') { |_c| reload.call }
        dlg.add_action_callback('refresh') { |_c| reload.call }
        # The checks prompt: fix what was ticked in one go, then open the window again.
        dlg.add_action_callback('fixChecks') do |_c, json|
          req = JSON.parse(json)
          reopen0 = lambda do
            dlg.close
            UI.start_timer(0.3, false) { PartsList.show }
          end
          # linking to HubSpot last (its own window); the Workshop reopens after it either way
          reopen = if req['hubspot']
                     lambda do
                       dlg.close
                       UI.start_timer(0.3, false) do
                         PartsList.show
                         HubSpotRoom.show_pick(:link, after: -> { PartsList.show })
                       end
                     end
                   else
                     reopen0
                   end
          if req['runouts']
            # measured in by hand: Room settings, not reopened (open the Workshop again after)
            dlg.close
            UI.start_timer(0.3, false) { Pencil.show(model, nil) }
            next
          end
          if req['colours']
            # colours the plugin doesn't know: change them in the Colours window, then reopen
            dlg.close
            UI.start_timer(0.3, false) { ColoursWindow.show }
            next
          end
          begin
            Workshop.fix_hinges(model) if req['hinges']
            Workshop.set_job_colours(model, req['job_colours']) unless (req['job_colours'] || {}).empty?
            if req['scribes']
              dlg.execute_script("$('status').textContent = 'Turning scribes on...'")
              Workshop.scribes_on(model, reopen) or reopen.call
            else
              reopen.call
            end
          rescue StandardError => e
            Log.error('workshop fix', e)
            fail_js.call(e)
          end
        end
        dlg.add_action_callback('close') { |_c| dlg.close }
        # Product list: move a part to another product / its own, renumber, label the plan.
        dlg.add_action_callback('setHost') do |_c, json|
          req = JSON.parse(json)
          Products.set_host(model, req['pid'], req['host'])
          reload.call
        end
        # Floor Plan tab
        plan_js = ->(d) { dlg.execute_script("planData(#{JSON.generate(d)})") }
        dlg.add_action_callback('planLoad') do |_c|
          Steps.one(dlg, 'Making the plan picture', done: ->(d) { plan_js.call(d) }, fail: ->(e) { plan_js.call('error' => e.message, 'notes' => Plan.notes(model)) }) { Plan.data(model) }
        end
        dlg.add_action_callback('planDims') do |_c|
          Steps.one(dlg, 'Dimensioning the plan', done: ->(d) { plan_js.call(d) }, fail: fail_js) { Plan.dimension(model); Plan.data(model) }
        end
        dlg.add_action_callback('planTs') do |_c|
          Steps.one(dlg, 'Pod numbers on the plan', done: ->(d) { plan_js.call(d) }, fail: fail_js) { Products.label(model); Plan.data(model) }
        end
        dlg.add_action_callback('planNote') do |_c, json|
          req = JSON.parse(json)
          Plan.edit(model, req['id'], req['text'])
          Steps.one(dlg, 'Updating the plan picture', done: ->(d) { plan_js.call(d) }, fail: fail_js) { Plan.data(model) }
        end
        dlg.add_action_callback('planPdf') do |_c|
          Steps.one(dlg, 'Saving the room plan', done: ->(r) { dlg.execute_script("planSaved(#{JSON.generate('name' => File.basename(r[0]), 'v' => r[1])})") }, fail: fail_js) { RoomPlan.write(model, data) }
        end
        dlg.add_action_callback('renumber') { |_c| Products.renumber(model); reload.call }
        dlg.add_action_callback('setLabelMode') do |_c, json|
          req = JSON.parse(json)
          m = Labels.modes(model)
          k = req['name'].to_s.upcase
          req['mode'].to_s.empty? ? m.delete(k) : m[k] = req['mode'].to_s
          Ops.run(model, 'Label mode', transparent: true) { model.set_attribute(DICT, Labels::MODES, JSON.generate(m)) }
          label_parts.call
          dlg.execute_script("labelParts(#{JSON.generate('parts' => data['label_parts'], 'stock' => data['timber_stock'])})")
        end
        dlg.add_action_callback('setTimberStock') do |_c, v|
          Ops.run(model, 'Timber stock length', transparent: true) { model.set_attribute(DICT, Labels::STOCK, v.to_i) }
          label_parts.call
          dlg.execute_script("labelParts(#{JSON.generate('parts' => data['label_parts'], 'stock' => data['timber_stock'])})")
        end
        dlg.add_action_callback('setJobInfo') do |_c, json|
          JobInfo.save(model, JSON.parse(json))
          data['job_info'] = JobInfo.get(model) if data
          dlg.execute_script("jobInfo(#{JSON.generate(data ? data['job_info'] : JobInfo.get(model))})")
        end
        dlg.add_action_callback('renumberParts') { |_c| PartsList.renumber_parts(model); reload.call }
        dlg.add_action_callback('doorView') do |_c|
          Steps.one(dlg, 'Drawing the doors view', done: ->(r) { dlg.execute_script("doorViewMade(#{JSON.generate(r)})") }, fail: fail_js) { DoorView.build(model) }
        end
        dlg.add_action_callback('labelPlan') do |_c|
          n = Products.label(model)
          dlg.execute_script("planLabelled(#{n})")
        end
        dlg.add_action_callback('selectProduct') do |_c, pid|
          e = Products.find(model, pid)
          if e
            model.selection.clear
            model.selection.add(e)
          end
        end
        # Survey tab: the Room's survey questions from HubSpot, saved back to it.
        survey_js = ->(d) { dlg.execute_script("surveyData(#{JSON.generate(d)})") }
        dlg.add_action_callback('surveyLoad') do |_c|
          next survey_js.call('error' => 'No HubSpot key saved (Settings > HubSpot).') unless HubSpot.key?
          Steps.one(dlg, 'Reading the survey from HubSpot', done: ->(d) { survey_js.call(d) }, fail: ->(e) { survey_js.call('error' => e.message) }) { Survey.data(model) }
        end
        dlg.add_action_callback('surveySave') do |_c, json|
          vals = JSON.parse(json)
          Steps.one(dlg, 'Saving the survey to HubSpot', done: lambda { |n|
            dlg.execute_script("$('status').textContent = #{JSON.generate("#{n} survey answer(s) saved to HubSpot.")}")
            survey_js.call(Survey.data(model))
          }, fail: ->(e) { survey_js.call('error' => e.message) }) { Survey.save(model, vals) }
        end
        # Open in HubSpot: the Room (a design visit: its project).
        dlg.add_action_callback('openHubspot') do |_c|
          l = HubSpotRoom.customer_link(model)
          next fail_js.call(StandardError.new('Link this file to HubSpot first.')) unless l
          l['room_id'] ? HubSpotRoom.open_record('listings', l['room_id']) : HubSpotRoom.open_record('projects', l['project_id'])
        end
        # HubSpot tab, file not linked: the Link window; the Workshop reopens once it's linked.
        dlg.add_action_callback('linkHubspot') do |_c|
          HubSpotRoom.show_pick(:link, after: -> { UI.start_timer(0.3, false) { PartsList.show } })
        end
        dlg.add_action_callback('openFolder') { |_c| UI.openURL("file:///#{File.dirname(model.path).tr('\\', '/')}") unless model.path.to_s.empty? }
        # The labels for a request (layout, which parts), barcodes kept on the pieces.
        label_entries = lambda do |req|
          preset = data['labels']['presets'][req['preset']] || data['labels']['presets'].values.first
          list = data
          w = req['which'].to_s
          if w == 'hw'
            list = data.merge('groups' => [])
          elsif w.start_with?('g')
            list = data.merge('groups' => [data['groups'][w[1..].to_i]].compact, 'hardware' => [], 'timber' => [])
          end
          entries = Labels.entries(list, preset, tops_map, modes: Labels.modes(model), stock: Labels.stock_mm(model), which: w,
                                                        room_id: (data['job_info'] || {})['room_id'])
          entries = Labels.range(entries, req['range'])
          Labels.store_barcodes(model, entries, PartsList.pieces)
          entries.each { |e| e.delete('eids') }
          [preset, entries]
        end
        dlg.add_action_callback('labels') do |_c, json|
          begin
            _preset, entries = label_entries.call(JSON.parse(json))
            errors = entries.count { |e| Array(e['custom']).any? { |c| c.is_a?(Hash) } }
            dlg.execute_script("labelEntries(#{JSON.generate('entries' => entries, 'errors' => errors)})")
          rescue StandardError => e
            Log.error('labels', e)
            fail_js.call(e)
          end
        end
        # Layout editor: HW layouts kept in the plugin settings ("label_layouts").
        dlg.add_action_callback('saveLayout') do |_c, json|
          begin
            req = JSON.parse(json)
            s = Settings.get.dup
            lay = (s['label_layouts'].is_a?(Hash) ? s['label_layouts'] : {}).dup
            lay[req['name'].to_s] = req['layout'].reject { |k, _| k == 'hw' }
            s['label_layouts'] = lay
            s['label_layout_active'] = req['name'].to_s
            Settings.save(s)
            data['labels'] = Labels.options(model)
            dlg.execute_script("layoutSaved(#{JSON.generate('labels' => data['labels'], 'name' => req['name'].to_s)})")
          rescue StandardError => e
            Log.error('save label layout', e)
            fail_js.call(e)
          end
        end
        dlg.add_action_callback('deleteLayout') do |_c, json|
          name = JSON.parse(json)['name'].to_s
          s = Settings.get.dup
          lay = (s['label_layouts'].is_a?(Hash) ? s['label_layouts'] : {}).dup
          lay.delete(name)
          s['label_layouts'] = lay
          Settings.save(s)
          data['labels'] = Labels.options(model)
          dlg.execute_script("D.labels = #{JSON.generate(data['labels'])}; renderLabels(D);")
        end
        # Zebra layouts: straight to the printer as ZPL (no print dialog).
        dlg.add_action_callback('printZpl') do |_c, json|
          begin
            preset, entries = label_entries.call(JSON.parse(json))
            raise 'No labels to print.' if entries.empty?
            job = (data['job_info'] || {}).merge('filename' => data['filename'])
            Zpl.transmit(Zpl.document(preset, entries, job))
            dlg.execute_script("$('status').textContent = #{JSON.generate("#{entries.size} label(s) sent to the Zebra (\\\\localhost\\#{Zpl.share}).")}")
          rescue StandardError => e
            Log.error('zebra', e)
            fail_js.call(e)
          end
        end
        dlg.add_action_callback('setSheets') do |_c, json|
          begin
            load_entered(model)
            m = entered_sheets.merge(JSON.parse(json))
            save_entered(model, m)
            reload.call
          rescue StandardError => e
            fail_js.call(e)
          end
        end
        dlg.add_action_callback('hubspot') do |_c|
          next dlg.execute_script("hubspotPlan(#{JSON.generate('error' => 'No HubSpot key saved (Settings > HubSpot).')})") unless HubSpot.key?
          plan = nil
          Steps.run(dlg, [['Reading the HubSpot Room', -> { plan = Workshop.plan(model, data) }]],
                    done: ->(_r) { dlg.execute_script("hubspotPlan(#{JSON.generate(plan)})") },
                    fail: ->(e) { dlg.execute_script("hubspotPlan(#{JSON.generate('error' => e.message)})") }, count: false)
        end
        # Check tab > Save Workshop Pack: the PDFs and the labels (ZPL, as printed), kept as the
        # pack the HubSpot tab sends and prints.
        pack = nil
        dlg.add_action_callback('save') do |_c, json|
          req = (JSON.parse(json.to_s) rescue {}).merge('range' => '')
          blocked = Workshop.blockers(model, data)
          next fail_js.call(StandardError.new("The Workshop Pack can't be saved yet: #{blocked.join(' ')}")) unless blocked.empty?
          out = nil
          steps = [['Saving the door order, parts list and Room Plan', -> { out = Workshop.save(model, data) }],
                   ['Making the labels', lambda {
                     preset, entries = label_entries.call(req)
                     job = (data['job_info'] || {}).merge('filename' => data['filename'])
                     out['labels'] = entries.empty? ? nil : Workshop.save_labels(model, Zpl.document(preset, entries, job), out['parts_v'])
                     out['label_count'] = entries.size
                   }]]
          Steps.run(dlg, steps,
                    done: lambda { |_r|
                      pack = out
                      pdfs = Workshop.pdfs(model)
                      mine = (out['files'] + [out['plan']]).compact
                      pdfs.each { |p| p['pack'] = mine.include?(p['path']) }
                      data['pdfs'] = pdfs
                      names = (out['files'] + [out['plan'], out['labels']]).compact.map { |f| File.basename(f) }
                      dlg.execute_script("saved(#{JSON.generate(out.merge('names' => names, 'pdfs' => pdfs, 'pdf_printer' => PdfPrint.printer))})")
                    },
                    fail: fail_js)
        end
        # A PDF for the preview (only ones listed for this model).
        dlg.add_action_callback('pdfData') do |_c, path|
          ok = Array(data && data['pdfs']).any? { |p| p['path'] == path } && File.exist?(path.to_s)
          r = ok ? { 'b64' => [File.binread(path)].pack('m0') } : { 'error' => "Can't open #{File.basename(path.to_s)}." }
          dlg.execute_script("pdfShow(#{JSON.generate(r)})")
        end
        # HubSpot tab > Send to HubSpot + print: uploads the saved pack and updates the Room, then
        # the labels to the Zebra and the PDFs to the Brother. A printer that can't be reached
        # doesn't stop the rest - it's reported at the end.
        dlg.add_action_callback('send') do |_c, json|
          req = JSON.parse(json)
          l = HubSpotRoom.link(model)
          next fail_js.call(StandardError.new('Link this file to a HubSpot room first (HubSpot > Link this file).')) unless l
          next fail_js.call(StandardError.new('Save the Workshop Pack on the Check tab first.')) unless pack
          want = req['do'].is_a?(Hash) ? req['do'] : { 'hubspot' => true, 'labels' => true, 'pdfs' => true }
          next fail_js.call(StandardError.new('Tick at least one: Send to HubSpot, Print labels or Print PDFs.')) unless want.values.any?
          n = 0
          zebra = 0
          brother = 0
          errors = []
          pdfs = (pack['files'] + [pack['plan']]).compact.select { |f| f =~ /\.pdf\z/i }
          # printing doesn't wait on HubSpot: a failed upload is reported, the prints still go
          steps = []
          steps << ['Uploading the files and updating the Room', lambda do
                     n = Workshop.send_room(model, l['room_id'], pack['files'], req['values'] || {}, req['stage'], plan: pack['plan'])
                   rescue StandardError => e
                     Log.error('workshop send', e) unless e.is_a?(HubSpot::Error)
                     errors << "HubSpot: #{e.message}"
                   end] if want['hubspot']
          steps << ['Printing the labels on the Zebra', lambda do
                     next unless pack['labels'] && File.exist?(pack['labels'])
                     Zpl.transmit(File.binread(pack['labels']))
                     zebra = pack['label_count']
                   rescue StandardError => e
                     Log.error('zebra', e)
                     errors << "Labels: #{e.message}"
                   end] if want['labels']
          steps << ['Printing the PDFs on the Brother', lambda do
                     brother = PdfPrint.print(pdfs)
                   rescue StandardError => e
                     Log.error('pdf print', e)
                     errors << "PDFs: #{e.message}"
                   end] if want['pdfs']
          Steps.run(dlg, steps,
                    done: lambda { |_r|
                      dlg.execute_script("sent(#{JSON.generate('n' => n, 'fields' => (req['values'] || {}).size, 'stage' => req['stage_label'], 'zebra' => zebra, 'brother' => brother, 'errors' => errors)})")
                      lines = []
                      lines << "HubSpot: #{errors.any? { |x| x.start_with?('HubSpot') } ? 'NOT sent' : "#{n} file(s) sent"}" if want['hubspot']
                      lines << "Zebra: #{zebra} label(s)" if want['labels']
                      lines << "#{(PdfPrint.resolve rescue PdfPrint.printer)}: #{brother} PDF(s)" if want['pdfs']
                      UI.messagebox((errors.empty? ? "Done.\n\n" : "Done, with problems:\n\n#{errors.join("\n\n")}\n\n") + lines.join("\n"))
                    },
                    fail: fail_js)
        end
        dlg.show
      end
    end
  end
end
