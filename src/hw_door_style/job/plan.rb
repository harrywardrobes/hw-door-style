require 'json'
require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Floor plan / Installation Plan.
    #
    #   Notes       right-click a part > HW Door Style > Plan note > a standard message (Settings
    #               "plan_messages") or your own text. A SketchUp text with an arrow to the part,
    #               on the "Plan notes" tag - shown only in the plan scene(s). {size} {width}
    #               {depth} {height} fill in from the part (mm).
    #   Dimensions  "Dimension the plan": the room (floor) and each product's width along the
    #               wall, on the "Plan dimensions" tag (made again each time).
    #   PDF         INSTALLATION_PLAN_v<N>_<file>.pdf: the plan scene with its notes, dimensions
    #               and Pod numbers, the ceiling height and top fascia. Saved with the workshop
    #               pack and sent to the Room's Floor Plan field.
    module Plan
      NOTE = 'plan_note'.freeze
      DIM = 'plan_dim'.freeze

      def self.s = Settings.get

      def self.scene_re
        r = s['plan_scenes'].to_s.strip
        Regexp.new(r.empty? ? 'top|plan' : r, Regexp::IGNORECASE)
      end

      # Tags in the "dimensions / labels" folder (Tags): room_dims and plan_notes by default.
      def self.notes_tag(model) = Tags.get(model, 'plan_notes_tag')
      def self.dims_tag(model) = Tags.get(model, 'plan_dims_tag')

      # Shown only in the plan scenes (and hidden now unless a plan scene is showing) - only
      # for a tag the plugin made; one that was already yours (room_dims) is left as it is.
      def self.plan_only(model, layer)
        return unless Tags.ours?(layer)
        re = scene_re
        model.pages.each { |pg| pg.set_visibility(layer, pg.name =~ re ? true : false) }
        sel = model.pages.selected_page
        layer.visible = sel ? (sel.name =~ re ? true : false) : true
      end

      def self.plan_page(model)
        model.pages.find { |pg| pg.name =~ scene_re }
      end

      def self.messages
        list = Array(s['plan_messages']).map(&:to_s).reject(&:empty?)
        list.empty? ? ['CABLE PORT'] : list
      end

      def self.mm(v) = (v.to_f * 25.4).round

      # The text for a message on a part: {size} = its width (or the smaller of width / depth
      # for a tall narrow part like a filler), {width} {depth} {height}.
      def self.fill(msg, inst)
        b = inst.bounds
        w = mm(b.width)
        d = mm(b.height)
        h = mm(b.depth)
        size = [w, d].min
        msg.gsub('{size}', size.to_s).gsub('{width}', w.to_s).gsub('{depth}', d.to_s).gsub('{height}', h.to_s)
      end

      # Arrow from the part to the text: the text goes out into the room (away from the back
      # wall), past the part's front, to the side it is nearer.
      def self.add(model, inst, text)
        b = inst.bounds
        target = Geom::Point3d.new(b.center.x, b.center.y, b.max.z)
        room = model.bounds
        out_x = b.center.x < room.center.x ? -1 : 1
        off = Geom::Vector3d.new(out_x * (s['plan_note_offset_mm'] || 350).to_f / 25.4, -(b.height / 2 + (s['plan_note_offset_mm'] || 350).to_f / 25.4), 0)
        n = nil
        Ops.run(model, 'Plan note') do
          t = model.entities.add_text(text, target, off)
          t.layer = notes_tag(model)
          t.arrow_type = 2 if t.respond_to?(:arrow_type=) # closed arrow
          t.set_attribute(DICT, NOTE, text)
          plan_only(model, notes_tag(model))
          n = t
        end
        n
      end

      # Right-click > Plan note.
      def self.menu(sub, inst)
        model = Sketchup.active_model
        pn = sub.add_submenu('Plan note')
        messages.each do |msg|
          label = fill(msg, inst)
          pn.add_item(label) { add(model, inst, label) }
        end
        pn.add_separator
        pn.add_item('Other text...') do
          r = UI.inputbox(['Note (use {size} for the part\'s size)'], [''], 'Plan note')
          txt = r && r.first.to_s.strip
          add(model, inst, fill(txt, inst)) if txt && !txt.empty?
        end
      end

      # Notes in the model: [{ id, text }].
      def self.notes(model)
        model.entities.grep(Sketchup::Text).select { |t| t.get_attribute(DICT, NOTE) }.map { |t| { 'id' => t.entityID, 'text' => t.text } }
      end

      def self.edit(model, id, text)
        t = model.entities.grep(Sketchup::Text).find { |x| x.entityID == id.to_i } or return
        Ops.run(model, 'Plan note') do
          if text.to_s.strip.empty?
            t.erase!
          else
            t.text = text.to_s
            t.set_attribute(DICT, NOTE, text.to_s)
          end
        end
      end

      # --- dimensions --------------------------------------------------------------------

      # Which wall a product stands against: the way its back faces (a unit's green axis
      # points at the wall behind it) - :back, :front, :left, :right, or nil when it's turned
      # at an angle.
      WALL_DIRS = { back: [0, 1], front: [0, -1], left: [-1, 0], right: [1, 0] }.freeze

      def self.wall_of(host)
        y = host.transformation.yaxis
        v = Geom::Vector3d.new(y.x, y.y, 0)
        return nil if v.length < 0.5
        v.normalize!
        WALL_DIRS.find { |_k, (x, yy)| v.x * x + v.y * yy > 0.9 }&.first
      end

      def self.knee_hole?(host) = DC.base_name(host.definition) =~ /KNEE_HOLE/i ? true : false

      # The product's run along its wall [from, to] (inches, on the wall's axis): its whole
      # extent - for a knee-hole worktop, the opening (its width from its origin along the unit).
      def self.span(host, bb, wall)
        along_x = %i[back front].include?(wall)
        if knee_hole?(host) && (w = DC.value(host, 'a01_unit_width').to_f).positive?
          o = host.transformation.origin
          e = o.offset(host.transformation.xaxis, w)
          return along_x ? [o.x, e.x].minmax : [o.y, e.y].minmax
        end
        along_x ? [bb.min.x, bb.max.x] : [bb.min.y, bb.max.y]
      end

      # [a, b, offset] for a dimension of [from, to] along a wall, on the wall's line (the
      # floor's edge, else the product's back) and out past it.
      def self.wall_dim(wall, from, to, fb, bb, z, gap)
        case wall
        when :back
          y = fb ? fb.max.y : bb.max.y
          [[from, y, z], [to, y, z], [0, gap, 0]]
        when :front
          y = fb ? fb.min.y : bb.min.y
          [[from, y, z], [to, y, z], [0, -gap, 0]]
        when :left
          x = fb ? fb.min.x : bb.min.x
          [[x, from, z], [x, to, z], [-gap, 0, 0]]
        when :right
          x = fb ? fb.max.x : bb.max.x
          [[x, from, z], [x, to, z], [gap, 0, 0]]
        end
      end

      # The points along a wall (length len, inches) for a chain of dimensions from corner to
      # corner: both corners and the ends of every product against it, merged when closer
      # than merge. Spans are [from, to] from the wall's start.
      def self.chain(len, spans, merge = 10 / 25.4)
        pts = ([0.0, len.to_f] + spans.flatten.map { |v| v.to_f.clamp(0.0, len.to_f) }).sort
        out = pts.each_with_object([]) { |v, o| o << v if o.empty? || v - o.last >= merge }
        out[-1] = len.to_f if (len.to_f - out[-1]).abs < merge
        out
      end

      # Dimensions all the way round the room, outside the walls, as on an architectural
      # plan: on each wall a chain from corner to corner through every product against it
      # (its width along that wall - a knee-hole worktop by its opening - and the gaps between),
      # then the wall's full length further out. A file with no floor gets each product's
      # width along its wall. Also the plan cut (plan_cut).
      def self.dimension(model)
        tag = dims_tag(model)
        gap = (s['plan_dim_offset_mm'] || 250).to_f / 25.4
        made = 0
        Ops.run(model, 'Dimension the plan') do
          old = model.entities.grep(Sketchup::Dimension).select { |d| d.get_attribute(DICT, DIM) }
          model.entities.erase_entities(old) unless old.empty?
          add = lambda do |a, b, off|
            d = model.entities.add_dimension_linear(Geom::Point3d.new(*a), Geom::Point3d.new(*b), off)
            d.layer = tag
            d.set_attribute(DICT, DIM, true)
            made += 1
          end
          floor = Room.parts(model)[:floor]
          fb = floor&.bounds
          rows, = Products.list(model)
          # just under the plan cut: over everything the plan shows (walls included), not cut away
          top = (fb ? fb.min.z : 0) + (cut_height_mm(model) - 10) / 25.4
          by_pid = Products.candidates(model.entities).to_h { |e, _| [e.persistent_id.to_s, e] }
          runs = Hash.new { |h, k| h[k] = [] }
          rows.each do |r|
            h = by_pid[r['pid']] or next
            bb = Geom::BoundingBox.new
            bb.add(h.bounds)
            r['members'].each { |m| (e = by_pid[m['pid']]) && bb.add(e.bounds) }
            wall = wall_of(h) or next
            from, to = span(h, bb, wall)
            next if (to - from) < 1 / 25.4
            if fb
              runs[wall] << [from, to]
            else
              a, b, off = wall_dim(wall, from, to, nil, bb, top, gap)
              add.call(a, b, off)
            end
          end
          if fb
            t = Room.wall_mm / 25.4
            %i[back front left right].each do |wall|
              along_x = %i[back front].include?(wall)
              o = along_x ? fb.min.x : fb.min.y
              len = along_x ? fb.width : fb.height
              pts = chain(len, runs[wall].map { |a, b| [a - o, b - o] })
              if pts.size > 2
                pts.each_cons(2) do |a, b|
                  pa, pb, off = wall_dim(wall, o + a, o + b, fb, nil, top, t + gap)
                  add.call(pa, pb, off)
                end
              end
              pa, pb, off = wall_dim(wall, o, o + len, fb, nil, top, t + gap * 2.2)
              add.call(pa, pb, off)
            end
          end
          plan_cut(model, fb)
          # the plan scenes leave off what Settings > Floor plan hides (cable outlets, hinges...)
          hidden_tags(model).each { |l| model.pages.each { |pg| pg.set_visibility(l, false) if pg.name =~ scene_re } }
          plan_only(model, tag)
        end
        made
      end

      # The plan's horizontal section ("HW plan cut"), just under the ceiling: the plan
      # picture is looked at through it, so walls and full-height units show cut (filled) as on
      # an architectural plan and everything lower is seen from above. Settings "plan_cut_mm"
      # sets its height above the floor (blank = 100 mm under the ceiling).
      CUT_NAME = 'HW plan cut'.freeze

      def self.cut_height_mm(model)
        v = s['plan_cut_mm'].to_f
        return v if v.positive?
        c = Ceiling.mm(model)
        c.positive? ? c - 100 : 2300
      end

      def self.plan_cut(model, fb)
        z = (fb ? fb.min.z : 0) + cut_height_mm(model) / 25.4
        sp = cut_plane(model) || model.entities.add_section_plane([0, 0, z], [0, 0, -1])
        sp.set_plane([0, 0, -1, z])
        sp.name = CUT_NAME
        sp.layer = dims_tag(model) # shown (and cutting) only with the plan's dimensions
        sp
      end

      def self.cut_plane(model) = model.entities.grep(Sketchup::SectionPlane).find { |x| x.name == CUT_NAME }

      # --- picture + PDF --------------------------------------------------------------------

      # The plan scene as a JPEG (the scene / camera showing now is put back).
      ROTATION = 'plan_rotation'.freeze

      # The job's plan turned by 0 / 90 / 180 / 270 degrees (Workshop > Floor Plan > Rotate 90).
      def self.rotation(model) = model.get_attribute(DICT, ROTATION, 0).to_i % 360

      def self.rotate!(model)
        Ops.run(model, 'Rotate the plan') { model.set_attribute(DICT, ROTATION, (rotation(model) + 90) % 360) }
        refresh(model, force: true) # the Pod numbers turn with it
      end

      # Pod numbers and dimensions on the plan, made again when the model has changed since
      # last time (or force). Returns true when they were redone.
      def self.refresh(model, force: false)
        rev = Ops.revision(model)
        return false if !force && @refreshed && @refreshed[0] == model && @refreshed[1] == rev
        Products.label(model)
        dimension(model)
        @refreshed = [model, Ops.revision(model)]
        true
      end

      def self.picture(model, path, width = 2400)
        pg = plan_page(model) or raise "No plan scene - add a scene whose name has \"#{s['plan_scenes'].to_s.empty? ? 'top or plan' : s['plan_scenes']}\" (e.g. S top)."
        view = model.active_view
        was_page = model.pages.selected_page
        c = view.camera
        cam = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov)
        cam.height = c.height unless c.perspective?
        opts = model.options['PageOptions']
        trans = opts['ShowTransition']
        ro = model.rendering_options
        keep = %w[BackgroundColor DrawGround DrawHorizon DrawSky HideConstructionGeometry DisplaySectionCuts DisplaySectionPlanes SectionCutFilled
                  SectionDefaultFillColor SectionDefaultCutColor SectionCutWidth RenderMode Texture].to_h { |k| [k, (ro[k] rescue nil)] }
        si = model.shadow_info
        shadows = si['DisplayShadows']
        begin
          opts['ShowTransition'] = false
          was_cut = model.entities.active_section_plane
          model.pages.selected_page = pg
          [notes_tag(model), dims_tag(model)].each { |l| l.visible = true }
          # and their tag folder (a plan scene may hide "dimensions / labels")
          folders = [notes_tag(model), dims_tag(model)].filter_map { |l| l.respond_to?(:folder) ? l.folder : nil }.uniq.reject(&:visible?)
          folders.each { |f| f.visible = true }
          # the Pod numbers go on as bold text over the picture (labels below), not drawn in it
          Products.label_tag(model).visible = false
          hidden = hidden_tags(model).select(&:visible?)
          hidden.each { |l| l.visible = false }
          # white paper: no sky, ground or horizon
          ro['BackgroundColor'] = Sketchup::Color.new(255, 255, 255)
          %w[DrawGround DrawHorizon DrawSky].each { |k| ro[k] = false unless ro[k].nil? }
          ro['HideConstructionGeometry'] = true # no guide lines on the plan
          # outlined, as an architectural plan: SketchUp's Hidden Line face style, no shadows
          ro['RenderMode'] = 1
          ro['Texture'] = false
          si['DisplayShadows'] = false
          # looked at through the plan cut: walls and tall units cut and filled
          if (cut = cut_plane(model))
            model.entities.active_section_plane = cut
            ro['DisplaySectionCuts'] = true
            ro['DisplaySectionPlanes'] = false
            ro['SectionCutFilled'] = true
            ro['SectionDefaultFillColor'] = Sketchup::Color.new(150, 150, 150)
            ro['SectionDefaultCutColor'] = Sketchup::Color.new(0, 0, 0)
            ro['SectionCutWidth'] = 2
          end
          # SketchUp's Top view in Parallel Projection (whatever the scene's camera is), back wall
          # at the top, turned by the job's rotation, then zoomed to what's on show with a margin
          c0 = model.bounds.center
          up = Y_AXIS
          r = rotation(model)
          up = Geom::Transformation.rotation(ORIGIN, Z_AXIS, r.degrees) * up if r.positive?
          cam2 = Sketchup::Camera.new(Geom::Point3d.new(c0.x, c0.y, model.bounds.max.z + 1000), Geom::Point3d.new(c0.x, c0.y, model.bounds.min.z), up, false)
          view.camera = cam2
          # fit to what's on show - not guide lines (endless) or anything hidden
          shown = model.entities.select do |e|
            e.is_a?(Sketchup::Drawingelement) && !e.is_a?(Sketchup::ConstructionLine) && !e.is_a?(Sketchup::ConstructionPoint) && !e.is_a?(Sketchup::SectionPlane) &&
              e.visible? && e.layer.visible? && !(e.respond_to?(:definition) && e.definition.name =~ /\Aceiling\z/i)
          end
          shown.empty? ? view.zoom_extents : view.zoom(shown)
          view.zoom(0.92)
          @labels = picture_labels(model, view)
          h = (width * view.vpheight / view.vpwidth.to_f).round
          view.write_image(filename: path, width: width, height: h, antialias: true, compression: 0.9) or raise "Couldn't make the plan picture"
        ensure
          keep.each { |k, val| (ro[k] = val) unless val.nil? }
          si['DisplayShadows'] = shadows unless shadows.nil?
          Array(folders).each { |f| f.visible = false if f.valid? }
          Array(hidden).each { |l| l.visible = true if l.valid? }
          model.pages.selected_page = was_page if was_page
          model.entities.active_section_plane = was_cut if was_page.nil? || !was_page.use_section_planes?
          view.camera = cam
          opts['ShowTransition'] = trans
          [notes_tag(model), dims_tag(model), Products.label_tag(model)].each { |l| plan_only(model, l) }
        end
        path
      end

      # Where each Pod number goes on the picture: [{ 't' => 'B4', 'pre' => 'UNFITTED', 'fx', 'fy' }]
      # (fractions of the picture across / down).
      def self.picture_labels(model, view)
        model.entities.grep(Sketchup::Group).filter_map do |g|
          t = g.get_attribute(DICT, 'product_label') or next
          pt = view.screen_coords(g.bounds.center)
          { 't' => t.to_s, 'pre' => g.get_attribute(DICT, 'product_label_pre').to_s,
            'fx' => (pt.x / view.vpwidth.to_f).round(4), 'fy' => (pt.y / view.vpheight.to_f).round(4) }
        end
      end

      # The Pod numbers from the last picture.
      def self.labels = Array(@labels)

      # The Pod numbers over the plan picture drawn at x, y (bottom-left), w x h points, as on
      # an architectural plan: a black disc with the number in white bold, "UNFITTED" in small
      # bold under it for an unfitted unit.
      NUM_PT = 7.5
      PRE_PT = 5.5
      K = 0.5523 # circle from four curves

      def self.disc(pg, cx, cy, r)
        c = r * K
        pg.ops << format('0 g %.2f %.2f m %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c f',
                         cx + r, cy, cx + r, cy + c, cx + c, cy + r, cx, cy + r, cx - c, cy + r, cx - r, cy + c, cx - r, cy,
                         cx - r, cy - c, cx - c, cy - r, cx, cy - r, cx + c, cy - r, cx + r, cy - c, cx + r, cy)
      end

      def self.badge_r(t) = [Pdf.width(t, 'F2', NUM_PT) / 2 + 3, 7.5].max

      def self.overlay(pg, labels, x, y, w, h)
        labels.each do |l|
          cx = x + l['fx'].to_f * w
          cy = y + (1 - l['fy'].to_f) * h
          next if cx < x || cx > x + w || cy < y || cy > y + h
          t = Pdf.clean(l['t'].to_s)
          r = badge_r(t)
          disc(pg, cx, cy, r)
          pg.ops << format('1 g BT /F2 %.1f Tf %.2f %.2f Td (%s) Tj ET 0 g', NUM_PT, cx - Pdf.width(t, 'F2', NUM_PT) / 2, cy - NUM_PT * 0.35, Pdf.esc(t))
          pre = l['pre'].to_s
          next if pre.empty?
          pw = Pdf.width(pre, 'F2', PRE_PT)
          pg.rect_fill(cx - pw / 2 - 1.5, cy - r - PRE_PT - 2.5, pw + 3, PRE_PT + 2, 1.0)
          pg.text(cx - pw / 2, cy - r - PRE_PT - 1, pre, font: 'F2', size: PRE_PT)
        end
      end

      # Tags left off the plan picture (Settings > Floor plan: hardware - hinges, rails...).
      def self.hidden_tags(model)
        names = s['plan_hidden_tags'].to_s.split(/[,;\n]/).map(&:strip).reject(&:empty?)
        names.filter_map { |n| model.layers[n] }
      end

      def self.top_fascia(model)
        vals = Runouts.units(model.entities).filter_map do |u|
          v = DC.value(u, 'facing_top')
          v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round
        end
        vals.tally.max_by(&:last)&.first
      end

      def self.version(dir, base, recorded)
        re = /\AINSTALLATION_PLAN_v(\d+)_#{Regexp.escape(Report.safe_name(base))}\.pdf\z/i
        on_disk = Dir.exist?(dir) ? Dir.children(dir).filter_map { |f| f[re, 1]&.to_i }.max.to_i : 0
        [on_disk, recorded.to_i].max + 1
      end

      # Writes INSTALLATION_PLAN_v<N>_<file>.pdf next to the .skp. Returns [path, version].
      def self.write(model)
        raise 'Save the SketchUp file first - the plan is saved next to it.' if model.path.to_s.empty?
        dir = File.dirname(model.path)
        base = File.basename(model.path, '.skp')
        v = version(dir, base, model.get_attribute(DICT, 'plan_version', 0))
        jpg = File.join(Dir.tmpdir, "hw_plan_#{Process.pid}.jpg")
        picture(model, jpg)
        im = Pdf.jpeg(jpg)
        w = Pdf::PAGE_W
        h = Pdf::PAGE_H
        m = Pdf::MARGIN
        pg = Pdf::Page.new
        pg.text(w / 2 - Pdf.width('Installation Plan', 'F2', 15) / 2, h - m - 6, 'Installation Plan', font: 'F2', size: 15)
        info = []
        c = Ceiling.mm(model)
        info << "CEILING #{c.round}mm" if c.positive?
        f = top_fascia(model)
        info << "TOP FASCIA #{f}mm" if f
        info.each_with_index { |t, i| pg.text(m, h - m - 6 - i * 11, t, size: 8.5) }
        pg.text(w - m, h - m - 6, "#{base}  -  v#{v}  -  #{Time.now.strftime('%d/%m/%Y')}", size: 7.5, align: :right)
        box_w = w - 2 * m
        box_h = h - 2 * m - 34
        scale = [box_w / im['w'], box_h / im['h']].min
        iw = im['w'] * scale
        ih = im['h'] * scale
        pg.image('Im1', m + (box_w - iw) / 2, m + (box_h - ih) / 2, iw, ih)
        overlay(pg, labels, m + (box_w - iw) / 2, m + (box_h - ih) / 2, iw, ih)
        path = File.join(dir, "INSTALLATION_PLAN_v#{v}_#{Report.safe_name(base)}.pdf")
        File.binwrite(path, Pdf.document([pg.to_s], images: { 'Im1' => im }))
        File.delete(jpg) rescue nil
        Ops.run(model, 'Record plan export', transparent: true) { model.set_attribute(DICT, 'plan_version', v) }
        [path, v]
      end

      # For the Workshop's Floor Plan tab: picture (data URL), notes, scene, ceiling / fascia.
      def self.data(model, with_picture: true)
        pg = plan_page(model)
        refresh(model) if pg && with_picture
        out = { 'scene' => pg&.name, 'notes' => notes(model), 'messages' => messages, 'ceiling' => Ceiling.mm(model).round,
                'fascia' => top_fascia(model), 'dims' => model.entities.grep(Sketchup::Dimension).count { |d| d.get_attribute(DICT, DIM) },
                'last' => model.get_attribute(DICT, 'room_plan_version', 0).to_i }
        if pg && with_picture
          jpg = File.join(Dir.tmpdir, "hw_plan_view_#{Process.pid}.jpg")
          picture(model, jpg, 1400)
          out['img'] = "data:image/jpeg;base64,#{[File.binread(jpg)].pack('m0')}"
          out['labels'] = labels
          File.delete(jpg) rescue nil
        end
        out
      end
    end
  end
end
