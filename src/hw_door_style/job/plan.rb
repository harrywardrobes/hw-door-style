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
    #               and T numbers, the ceiling height and top fascia. Saved with the workshop
    #               pack and sent to the Room's Floor Plan field.
    module Plan
      NOTE = 'plan_note'.freeze
      DIM = 'plan_dim'.freeze

      def self.s = Settings.get

      def self.scene_re
        r = s['plan_scenes'].to_s.strip
        Regexp.new(r.empty? ? 'top|plan' : r, Regexp::IGNORECASE)
      end

      def self.tag(model, key, default)
        n = s[key].to_s.strip
        n = default if n.empty?
        model.layers[n] || model.layers.add(n)
      end

      def self.notes_tag(model) = tag(model, 'plan_notes_tag', 'Plan notes')
      def self.dims_tag(model) = tag(model, 'plan_dims_tag', 'Plan dimensions')

      # Shown only in the plan scenes (and hidden now unless a plan scene is showing).
      def self.plan_only(model, layer)
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

      def self.dimension(model)
        tag = dims_tag(model)
        gap = (s['plan_dim_offset_mm'] || 250).to_f / 25.4
        made = 0
        Ops.run(model, 'Dimension the plan') do
          old = model.entities.grep(Sketchup::Dimension).select { |d| d.get_attribute(DICT, DIM) }
          model.entities.erase_entities(old) unless old.empty?
          add = lambda do |a, b, off|
            d = model.entities.add_dimension_linear(a, b, off)
            d.layer = tag
            d.set_attribute(DICT, DIM, true)
            made += 1
          end
          floor = Room.parts(model)[:floor]
          if floor
            fb = floor.bounds
            add.call(Geom::Point3d.new(fb.min.x, fb.min.y, 0), Geom::Point3d.new(fb.max.x, fb.min.y, 0), [0, -gap * 3, 0])
            add.call(Geom::Point3d.new(fb.min.x, fb.min.y, 0), Geom::Point3d.new(fb.min.x, fb.max.y, 0), [-gap * 3, 0, 0])
          end
          rows, = Products.list(model)
          by_pid = Products.candidates(model.entities).to_h { |e, _| [e.persistent_id.to_s, e] }
          rows.each do |r|
            h = by_pid[r['pid']] or next
            bb = Geom::BoundingBox.new
            bb.add(h.bounds)
            r['members'].each { |m| (e = by_pid[m['pid']]) && bb.add(e.bounds) }
            z = bb.max.z
            # along the back wall, outside the room
            add.call(Geom::Point3d.new(bb.min.x, bb.max.y, z), Geom::Point3d.new(bb.max.x, bb.max.y, z), [0, gap, 0])
          end
          plan_only(model, tag)
        end
        made
      end

      # --- picture + PDF --------------------------------------------------------------------

      # The plan scene as a JPEG (the scene / camera showing now is put back).
      def self.picture(model, path, width = 2400)
        pg = plan_page(model) or raise "No plan scene - add a scene whose name has \"#{s['plan_scenes'].to_s.empty? ? 'top or plan' : s['plan_scenes']}\" (e.g. S top)."
        view = model.active_view
        was_page = model.pages.selected_page
        c = view.camera
        cam = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov)
        cam.height = c.height unless c.perspective?
        opts = model.options['PageOptions']
        trans = opts['ShowTransition']
        begin
          opts['ShowTransition'] = false
          model.pages.selected_page = pg
          [notes_tag(model), dims_tag(model), Products.label_tag(model)].each { |l| l.visible = true }
          h = (width * view.vpheight / view.vpwidth.to_f).round
          view.write_image(filename: path, width: width, height: h, antialias: true, compression: 0.9) or raise "Couldn't make the plan picture"
        ensure
          model.pages.selected_page = was_page if was_page
          view.camera = cam
          opts['ShowTransition'] = trans
          [notes_tag(model), dims_tag(model), Products.label_tag(model)].each { |l| plan_only(model, l) }
        end
        path
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
        path = File.join(dir, "INSTALLATION_PLAN_v#{v}_#{Report.safe_name(base)}.pdf")
        File.binwrite(path, Pdf.document([pg.to_s], images: { 'Im1' => im }))
        File.delete(jpg) rescue nil
        Ops.run(model, 'Record plan export', transparent: true) { model.set_attribute(DICT, 'plan_version', v) }
        [path, v]
      end

      # For the Workshop's Floor Plan tab: picture (data URL), notes, scene, ceiling / fascia.
      def self.data(model, with_picture: true)
        pg = plan_page(model)
        out = { 'scene' => pg&.name, 'notes' => notes(model), 'messages' => messages, 'ceiling' => Ceiling.mm(model).round,
                'fascia' => top_fascia(model), 'dims' => model.entities.grep(Sketchup::Dimension).count { |d| d.get_attribute(DICT, DIM) },
                'last' => model.get_attribute(DICT, 'room_plan_version', 0).to_i }
        if pg && with_picture
          jpg = File.join(Dir.tmpdir, "hw_plan_view_#{Process.pid}.jpg")
          picture(model, jpg, 1400)
          out['img'] = "data:image/jpeg;base64,#{[File.binread(jpg)].pack('m0')}"
          File.delete(jpg) rescue nil
        end
        out
      end
    end
  end
end
