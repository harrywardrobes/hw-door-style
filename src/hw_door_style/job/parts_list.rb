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
        m
      end

      # --- finding parts (OpenCutList _fetch_useful_instance_infos) ---------------------------
      # A part is a component instance that holds faces itself. HW: tag visibility is ignored
      # (scenes hide DOOR / hinges), only hidden entities (DC options switched off) are skipped.

      def self.collect(ents, path, out, cache)
        count = 0
        ents.each do |e|
          next if e.is_a?(Sketchup::Edge)
          next unless e.visible?
          if e.is_a?(Sketchup::Group)
            count += collect(e.entities, path + [e], out, cache)
          elsif e.is_a?(Sketchup::ComponentInstance)
            next if e.definition.behavior.always_face_camera?
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

      def self.generate(model = Sketchup.active_model)
        opts = cutlist_options(model)
        found = []
        collect(model.entities, [], found, {})
        groups = {}
        hardware = {}
        skipped = Hash.new(0)
        found.each do |path, bounds|
          if bought_in?(path)
            skipped['bought_in'] += 1
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
            gid = "#{mat.name}|#{th_std}"
            g = (groups[gid] ||= { 'material' => mat.name, 'thickness' => th_std, 'std_ok' => true, 'grained' => mat.get_attribute(OCL, 'grained', false) ? true : false,
                                   'sheet' => sizes_list(mat.get_attribute(OCL, 'std_sizes', '')).max_by { |a, b| a * b }, 'parts' => {} })
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
            h = (hg[pid] ||= { 'name' => name, 'material' => mat.name, 'length' => l_mm, 'width' => w_mm, 'thickness' => th_mm, 'raw' => size.map(&:to_f), 'qty' => 0, 'flipped' => flipped,
                               'edge_pattern' => '', 'edge_count' => 0, 'tags' => tags_of(defn), 'instances' => [] })
            h['qty'] += 1
            h['instances'] << instance_info(path)
          else
            skipped[type == TYPE_UNKNOWN ? 'no_type' : 'other'] += 1
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
        { 'layer' => e.layer.name, 'entity_name' => e.name.to_s,
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

      def self.first_number(opts)
        opts['part_number_with_letters'] ? 'A' : 1
      end

      # OpenCutList phase 2: groups by material type > name > thickness; parts sorted by the
      # part order strategy and numbered A, B ... (again from A in each group, as set in OpenCutList).
      def self.finish(model, groups, hardware, skipped, opts = CUTLIST_DEFAULTS)
        number = first_number(opts)
        strategy = opts['part_order_strategy']
        edging = Hash.new { |h, k| h[k] = { 'material' => k[0], 'height' => k[1], 'metres' => 0.0, 'parts' => 0 } }
        sheet_groups = groups.values.sort_by { |g| [g['material'].downcase, -g['thickness']] }.map do |g|
          number = first_number(opts) if opts['part_number_sequence_by_group']
          parts = g['parts'].values.sort { |a, b| part_order(a, b, strategy) }
          parts.each do |p|
            p['number'] = number
            number = number.succ
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
          area = parts.sum { |p| p['area_m2'] }
          sheet = g['sheet']
          sheets = nil
          if sheet
            usable = sheet[0] * sheet[1] / 1_000_000.0 * (1 - waste_pct / 100.0)
            sheets = usable > 0 ? (area / usable).ceil : nil
          end
          too_big = sheet ? parts.select { |p| [p['length'], p['width']].max > sheet.max || [p['length'], p['width']].min > sheet.min }.map { |p| p['number'] } : []
          g.merge('parts' => parts, 'count' => parts.sum { |p| p['qty'] }, 'area_m2' => area.round(2), 'sheets' => sheets, 'too_big' => too_big)
        end
        edge_list = edging.values.map { |e| e.merge('metres' => e['metres'].round(1)) }.sort_by { |e| [e['material'], e['height']] }
        hw = hardware.keys.sort_by(&:downcase).flat_map do |mname|
          number = first_number(opts) if opts['part_number_sequence_by_group']
          hardware[mname].values.sort { |a, b| part_order(a, b, strategy) }.each do |h|
            add_strings(h)
            h['number'] = number
            number = number.succ
          end
        end
        {
          'job' => File.basename(model.path.to_s, '.skp'), 'date' => Time.now.strftime('%d/%m/%Y %H:%M'), 'version' => VERSION,
          'groups' => sheet_groups, 'edging' => edge_list, 'hardware' => hw, 'handles' => handles(model),
          'skipped' => skipped, 'waste_pct' => waste_pct, 'scribes_on' => Pencil.on?(model) || Runouts.units(model.entities).empty?,
          'filename' => File.basename(model.path.to_s), 'model_name' => model.name.to_s, 'page_name' => model.pages.selected_page&.name.to_s,
          'labels' => Labels.options(model), 'cutlist_options' => opts
        }
      end

      # HW: handles aren't drawn - they come from the Door style window and the door summary counts.
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
        File.write("#{s}.csv", "﻿" + csv(d), mode: 'w:UTF-8')
        PartsPdf.write("#{s}.pdf", d.merge('list_version' => v))
        Ops.run(model, 'Record parts list export', transparent: true) { model.set_attribute(DICT, 'parts_list_version', v) }
        ["#{s}.csv", "#{s}.pdf", v]
      end

      # --- HubSpot: the Room's "Order / Parts List" file field --------------------------------

      FIELD = 'order_parts_list'.freeze

      def self.ensure_field
        HubSpot.get("/crm/v3/properties/listings/#{FIELD}")
        false
      rescue HubSpot::Error => e
        raise unless e.status == 404
        HubSpot.post('/crm/v3/properties/listings', { name: FIELD, label: 'Order / Parts List', type: 'string', fieldType: 'file',
                                                      groupName: (HubSpot.get('/crm/v3/properties/listings/sheets_order_status')['groupName'] rescue 'listinginformation'), description: 'Parts list PDF + CSV from SketchUp (HW Door Style)' })
        HubSpotRoom.forget_meta!
        true
      end

      # Uploads the PDF and CSV and puts them in the field (replacing the last ones there).
      def self.send_to_room(model, files)
        l = HubSpotRoom.link(model) or raise 'Link this file to a HubSpot room first (HubSpot > Link this file).'
        ensure_field
        folder = HubSpotPictures.config['files_folder']
        ids = files.map { |f| HubSpot.upload(f, folder) }
        HubSpot.update_room(l['room_id'], { FIELD => ids.join(';') })
        ids.size
      end

      # --- window ------------------------------------------------------------------------------

      def self.show
        model = Sketchup.active_model
        dlg = nil
        data = nil
        build = -> { data = generate(model) }
        dlg = Dialog.open('parts_list', title: 'HW - Parts list', key: 'hw_parts_list', width: 1000, height: 700, data: nil)
        reload = lambda do
          Steps.run(dlg, [['Reading the parts in the model', build]],
                    done: ->(_r) { dlg.execute_script("render(#{JSON.generate(data)})") },
                    fail: ->(e) { dlg.execute_script("failed(#{JSON.generate(e.message)})") }, count: false)
        end
        dlg.add_action_callback('ready') { |_c| reload.call }
        dlg.add_action_callback('refresh') { |_c| reload.call }
        dlg.add_action_callback('close') { |_c| dlg.close }
        dlg.add_action_callback('export') do |_c|
          files = nil
          Steps.run(dlg, [['Writing the CSV and PDF', -> { files = export(model, data) }]],
                    done: lambda { |_r|
                      dlg.execute_script("exported(#{JSON.generate('csv' => File.basename(files[0]), 'pdf' => File.basename(files[1]), 'v' => files[2], 'dir' => File.dirname(files[0]))})")
                    },
                    fail: ->(e) { dlg.execute_script("failed(#{JSON.generate(e.message)})") }, count: false)
        end
        dlg.add_action_callback('labels') do |_c, json|
          req = JSON.parse(json)
          begin
            preset = data['labels']['presets'][req['preset']] || data['labels']['presets'].values.first
            list = data
            w = req['which'].to_s
            if w == 'hw'
              list = data.merge('groups' => [])
            elsif w.start_with?('g')
              list = data.merge('groups' => [data['groups'][w[1..].to_i]].compact, 'hardware' => [])
            end
            entries = Labels.entries(list, preset)
            errors = entries.count { |e| e['custom'].any? { |c| c.is_a?(Hash) } }
            dlg.execute_script("labelEntries(#{JSON.generate('entries' => entries, 'errors' => errors)})")
          rescue StandardError => e
            Log.error('labels', e)
            dlg.execute_script("failed(#{JSON.generate("Labels: #{e.message}")})")
          end
        end
        dlg.add_action_callback('openFolder') { |_c| UI.openURL("file:///#{File.dirname(model.path).tr('\\', '/')}") unless model.path.to_s.empty? }
        dlg.add_action_callback('send') do |_c|
          next unless HubSpotRoom.ready?
          files = nil
          n = 0
          Steps.run(dlg, [['Writing the CSV and PDF', -> { files = export(model, data) }],
                          ['Uploading to the HubSpot Room', -> { n = send_to_room(model, files[0, 2]) }]],
                    done: ->(_r) { dlg.execute_script("sent(#{JSON.generate('n' => n, 'v' => files[2], 'pdf' => File.basename(files[1]))})") },
                    fail: ->(e) { dlg.execute_script("failed(#{JSON.generate(e.message)})") }, count: false)
        end
        dlg.show
      end
    end
  end
end
