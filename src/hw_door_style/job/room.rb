require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # The room: width (left-right, red X), length (into the room, green Y) and ceiling
    # height, in mm. Sizes the FLOOR and CEILING parts from the job template and is the
    # job's ceiling height (the Scribe / runout window's "Ceiling height").
    #
    # A file without a room asks for it when it is opened (Room setup window); an unsaved
    # file is saved there too: <customers folder>\<customer folder>\<file>.skp, the
    # customers folder (e.g. 1_CUSTOMERS) remembered on this computer.
    module Room
      KEY = 'room'.freeze
      SKIP = 'room_skip'.freeze
      PREF_JOBS = 'jobs_folder'.freeze
      FLOOR = /\Afloor\z/i.freeze
      CEILING = /\Aceiling\z/i.freeze
      # The walls round the room: the back one behind the floor, the front one in front of it,
      # left and right either side, each Settings "wall_thickness_mm" thick, floor to ceiling.
      # Named back_wall / front_wall / left_wall / right_wall (or with a space). A template
      # with no front wall gets one (like the back wall: its material and tag).
      WALLS = { back: /\Aback[ _]wall\z/i, front: /\Afront[ _]wall\z/i, left: /\Aleft[ _]wall\z/i, right: /\Aright[ _]wall\z/i }.freeze
      FRONT_WALL = 'front_wall'.freeze
      # The scenes Room setup keeps to the room (as in the components file): "room" looking
      # down with the ceiling tag off, and two cut through the room a third of the way in -
      # "view 1" looking at the back wall (section "Section 1"), "view 2" at the front wall
      # (section "Section 2").
      ROOM_PAGE = 'room'.freeze
      VIEWS = [
        { page: 'view 1', plane: 'Section 1', look: 1 },  # a third in from the front, facing the back wall
        { page: 'view 2', plane: 'Section 2', look: -1 }  # a third in from the back, facing the front wall
      ].freeze
      FOV = 35.0

      def self.wall_mm
        v = Settings.get['wall_thickness_mm'].to_f
        v.positive? ? v : 300.0
      end

      # The size the template's floor and ceiling are saved at (Settings "room_default_mm").
      # Only the template: a new job's Room setup starts blank.
      def self.default_mm
        d = Settings.get['room_default_mm']
        d = {} unless d.is_a?(Hash)
        { 'width' => (d['width'] || 4000).to_f, 'length' => (d['length'] || 3000).to_f, 'ceiling' => (d['ceiling'] || 2400).to_f }
      end

      def self.get(model = Sketchup.active_model)
        r = JSON.parse(model.get_attribute(DICT, KEY, 'null'))
        r.is_a?(Hash) ? r : nil
      rescue StandardError
        nil
      end

      def self.base(e)
        e.respond_to?(:definition) ? DC.base_name(e.definition) : e.name.to_s
      end

      # The floor and ceiling parts (top level, by component or instance name).
      def self.part(model, re)
        model.entities.find do |e|
          (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && (base(e) =~ re || e.name.to_s =~ re)
        end
      end

      def self.parts(model)
        { floor: part(model, FLOOR), ceiling: part(model, CEILING) }.merge(WALLS.to_h { |k, re| [k, part(model, re)] })
      end

      # Sizes a part to w x l x h (inches; nil = leave that one) with its corner at x, y, z.
      def self.box(inst, w, l, h, x, y, z)
        b = inst.bounds
        s = [[w, b.width], [l, b.height], [h, b.depth]].map { |want, have| want && have > 0.001 ? want / have : 1.0 }
        if s.any? { |v| (v - 1).abs > 1e-6 }
          inst.transformation = Geom::Transformation.scaling(b.min, *s) * inst.transformation
        end
        b = inst.bounds
        move = Geom::Vector3d.new(x - b.min.x, y - b.min.y, z - b.min.z)
        inst.transform!(Geom::Transformation.translation(move)) if move.length > 0.0001
        inst
      end

      # Stretches a part in X / Y (like the Scale tool, about its corner) and moves its
      # corner to x, y (and its underside to z). Sizes in inches; nil = leave as it is.
      def self.fit(inst, w, l, x, y, z = nil)
        b = inst.bounds
        sx = w && b.width > 0.001 ? w / b.width : 1.0
        sy = l && b.height > 0.001 ? l / b.height : 1.0
        if (sx - 1).abs > 1e-6 || (sy - 1).abs > 1e-6
          inst.transformation = Geom::Transformation.scaling(b.min, sx, sy, 1.0) * inst.transformation
        end
        b = inst.bounds
        move = Geom::Vector3d.new(x - b.min.x, y - b.min.y, z ? z - b.min.z : 0)
        inst.transform!(Geom::Transformation.translation(move)) if move.length > 0.0001
        DC.redraw(inst) if inst.respond_to?(:definition) && inst.attribute_dictionary('dynamic_attributes')
        inst
      end

      # Sets the room (mm; nil / 0 keeps the current value) inside the caller's step.
      # Floor stays where it is and takes the width / length; the ceiling sits over it,
      # its underside at the ceiling height above the floor's top. Returns the room.
      def self.apply(model, width: nil, length: nil, ceiling: nil)
        cur = get(model) || {}
        r = {
          'width' => width.to_f.positive? ? width.to_f : cur['width'],
          'length' => length.to_f.positive? ? length.to_f : cur['length'],
          'ceiling' => ceiling.to_f.positive? ? ceiling.to_f : (cur['ceiling'] || (Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil))
        }
        w = r['width'] && r['width'] / 25.4
        l = r['length'] && r['length'] / 25.4
        p = parts(model)
        fb = p[:floor]&.bounds
        if p[:floor]
          fit(p[:floor], w, l, fb.min.x, fb.min.y)
          fb = p[:floor].bounds
        end
        if p[:ceiling]
          cb = p[:ceiling].bounds
          x = fb ? fb.min.x : cb.min.x
          y = fb ? fb.min.y : cb.min.y
          z = r['ceiling'] ? (fb ? fb.max.z : 0) + r['ceiling'] / 25.4 : nil
          fit(p[:ceiling], w, l, x, y, z)
        end
        walls(model, p, fb, r['ceiling'])
        views(model, fb, r['ceiling']) if fb
        model.set_attribute(DICT, KEY, JSON.generate(r))
        model.set_attribute(DICT, 'ceiling_mm', r['ceiling']) if r['ceiling']
        r
      end

      # The walls round the floor (fb: its bounds): back behind it and front in front of it
      # (across the corners, so the room is closed in plan), left and right the floor's length,
      # all from the floor's underside to the ceiling. Each wall is drawn again as a true box
      # (solid), so it is straight and level whatever its geometry was (a template wall drawn
      # on a slope was stretched with its slope). No front wall: one is made like the others.
      def self.walls(model, p, fb, ceiling_mm)
        return unless fb
        t = wall_mm / 25.4
        z0 = fb.min.z
        top = ceiling_mm ? fb.max.z + ceiling_mm.to_f / 25.4 : nil
        like = p[:back] || p[:left] || p[:right]
        p[:front] ||= add_wall(model, FRONT_WALL, like) if like
        h = ->(inst) { top ? top - z0 : inst.bounds.depth }
        solid(p[:back], fb.width + 2 * t, t, h.call(p[:back]), fb.min.x - t, fb.max.y, z0) if p[:back]
        solid(p[:front], fb.width + 2 * t, t, h.call(p[:front]), fb.min.x - t, fb.min.y - t, z0) if p[:front]
        solid(p[:left], t, fb.height, h.call(p[:left]), fb.min.x - t, fb.min.y, z0) if p[:left]
        solid(p[:right], t, fb.height, h.call(p[:right]), fb.max.x, fb.min.y, z0) if p[:right]
      end

      # The material and tag a wall's faces have.
      def self.look_of(inst)
        return [inst.material, inst.layer] unless inst.respond_to?(:definition)
        f = inst.definition.entities.grep(Sketchup::Face).first
        [f&.material, f&.layer]
      end

      # A new wall like another (same tag on the instance, same material and tag on its
      # faces), sized by solid afterwards.
      def self.add_wall(model, name, like)
        mat, tag = look_of(like)
        d = model.definitions.add(name)
        draw_box(d.entities, 1, 1, 1, mat, tag)
        inst = model.entities.add_instance(d, Geom::Transformation.new)
        inst.layer = like.layer
        inst.material = like.material if like.material
        inst
      end

      # A box w x l x h (inches) from the origin up, faces out.
      def self.draw_box(ents, w, l, h, mat, tag)
        f = ents.add_face([0, 0, 0], [w, 0, 0], [w, l, 0], [0, l, 0])
        f.reverse! if f.normal.z.positive?
        f.pushpull(-h) # up from z = 0
        ents.grep(Sketchup::Face).each { |fc| fc.material = mat; fc.layer = tag if tag }
        ents.grep(Sketchup::Edge).each { |e| e.layer = tag if tag }
      end

      # A wall as a plain box w x l x h (inches) with its corner at x, y, z: its own definition
      # (made unique if shared) holding just the box, placed with no rotation or scaling. The
      # faces keep the wall's material and tag.
      def self.solid(inst, w, l, h, x, y, z)
        return box(inst, w, l, h, x, y, z) unless inst.is_a?(Sketchup::ComponentInstance)
        inst.make_unique if inst.definition.instances.size > 1
        mat, tag = look_of(inst)
        d = inst.definition
        d.entities.clear!
        draw_box(d.entities, w, l, h, mat, tag)
        inst.transformation = Geom::Transformation.translation([x, y, z])
        inst
      end

      # --- the scenes -----------------------------------------------------------------

      def self.view_aspect(model)
        v = model.active_view
        a = v.vpheight.to_f.positive? ? v.vpwidth.to_f / v.vpheight : 1.6
        a.clamp(1.2, 2.2)
      rescue StandardError
        1.6
      end

      # Where the two cut views look from: { page:, plane:, look:, y:, eye:, target: } (inches).
      # The section is a third of the room in; the camera sits back from it, far enough for
      # the whole cut (walls included) to fit the view, a little above the middle, looking
      # very slightly down.
      def self.view_cameras(fb, height, wall, aspect)
        tan = Math.tan((FOV / 2).degrees)
        cx = fb.center.x
        z0 = fb.min.z
        half_w = fb.width / 2 + wall
        dist = [(height / 2) / tan, half_w / (tan * aspect)].max * 1.1
        VIEWS.map do |v|
          y = v[:look].positive? ? fb.min.y + fb.height / 3 : fb.max.y - fb.height / 3
          far = v[:look].positive? ? fb.max.y : fb.min.y
          v.merge(y: y, eye: [cx, y - v[:look] * dist, z0 + height * 0.6], target: [cx, far, z0 + height * 0.45])
        end
      end

      # The room scene: its own direction kept (else from the front, above), aimed at the
      # room's middle and far enough back for the whole room.
      def self.room_camera(fb, height, wall, dir = nil)
        dir = Geom::Vector3d.new(*(dir || [0.15, 0.6, -0.8]))
        dir.normalize!
        c = Geom::Point3d.new(fb.center.x, fb.center.y, fb.min.z + height / 2)
        r = Math.sqrt((fb.width + 2 * wall)**2 + (fb.height + 2 * wall)**2 + height**2) / 2
        d = r / Math.sin((FOV / 2).degrees) * 1.05
        [c.offset(dir.reverse, d).to_a, c.to_a]
      end

      def self.set_camera(page, eye, target)
        dir = Geom::Vector3d.new(target[0] - eye[0], target[1] - eye[1], target[2] - eye[2])
        side = dir * Z_AXIS
        up = side.length > 1e-9 ? side * dir : Y_AXIS
        page.camera.set(Geom::Point3d.new(*eye), Geom::Point3d.new(*target), up)
        page.camera.perspective = true
        page.camera.fov = FOV
      end

      # Section planes "Section 1" / "Section 2" and the scenes "view 1" / "view 2" through
      # them, "room" with the ceiling tag off - made when missing, moved to this room when there.
      def self.views(model, fb, ceiling_mm)
        ents = model.entities
        pages = model.pages
        height = ceiling_mm ? ceiling_mm.to_f / 25.4 : 2400 / 25.4
        wall = wall_mm / 25.4
        ceiling_tag = model.layers['ceiling'] || (cp = part(model, CEILING)) && cp.layer
        was_active = ents.active_section_plane
        room = pages[ROOM_PAGE]
        unless room
          room = pages.add(ROOM_PAGE, PAGE_USE_ALL, 0)
          ents.active_section_plane = nil
          room.update(PAGE_USE_SECTION_PLANES)
        end
        room.set_visibility(ceiling_tag, false) if ceiling_tag
        eye, target = room_camera(fb, height, wall, room.camera.direction.to_a)
        set_camera(room, eye, target)
        hidden = room.layers.to_a - [ceiling_tag]
        view_cameras(fb, height, wall, view_aspect(model)).each do |v|
          sp = ents.grep(Sketchup::SectionPlane).find { |s| s.name == v[:plane] } || ents.add_section_plane([0, v[:y], 0], [0, v[:look], 0])
          sp.set_plane([0, v[:look], 0, -v[:look] * v[:y]])
          sp.name = v[:plane]
          sp.symbol = v[:plane][/\d+/].to_s if sp.respond_to?(:symbol=)
          pg = pages[v[:page]]
          unless pg
            pg = pages.add(v[:page])
            model.layers.each { |l| pg.set_visibility(l, !hidden.include?(l)) }
          end
          set_camera(pg, v[:eye], v[:target])
          pg.use_section_planes = true
          ents.active_section_plane = sp
          pg.update(PAGE_USE_SECTION_PLANES)
        end
        ents.active_section_plane = was_active&.valid? ? was_active : nil
      end

      # After Room setup: the room scene (sized to the room), without the scene animation.
      def self.show_room(model)
        pg = model.pages[ROOM_PAGE] or return
        po = model.options['PageOptions']
        tr = po['ShowTransition']
        po['ShowTransition'] = false
        model.pages.selected_page = pg
        po['ShowTransition'] = tr
      rescue StandardError => e
        Log.error('room scene', e)
      end

      # Is a wall a true box, level and square (8 corners on its bounding box)?
      def self.straight?(inst)
        d = inst.definition
        b = d.bounds
        pts = d.entities.grep(Sketchup::Edge).flat_map { |e| e.vertices.map(&:position) }.uniq { |pt| pt.to_a.map { |v| v.round(3) } }
        corners = [b.min.x, b.max.x].product([b.min.y, b.max.y], [b.min.z, b.max.z])
        t = inst.transformation
        pts.size == 8 && pts.all? { |pt| corners.any? { |c| (pt.x - c[0]).abs < 0.01 && (pt.y - c[1]).abs < 0.01 && (pt.z - c[2]).abs < 0.01 } } &&
          t.xaxis.parallel?(X_AXIS) && t.yaxis.parallel?(Y_AXIS) && t.zaxis.parallel?(Z_AXIS)
      end

      # A room part (floor, ceiling, a wall): never a product, a part or an export.
      def self.part?(e)
        return false unless e.respond_to?(:definition) || e.is_a?(Sketchup::Group)
        n = base(e)
        [FLOOR, CEILING, *WALLS.values].any? { |re| n =~ re || e.name.to_s =~ re }
      end

      # --- asking when a file is opened ------------------------------------------

      # Nothing in it but the template's floor / ceiling (a new job).
      def self.blank?(model)
        model.path.to_s.empty? && model.entities.all? { |e| e.is_a?(Sketchup::SectionPlane) || ((e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && part?(e)) }
      end

      def self.ask?(model)
        return false unless model && model.valid?
        return false if LibraryExport.master?(model)
        return false if model.get_attribute(DICT, SKIP, false)
        r = get(model)
        return true if r.nil?
        # a ceiling height alone (e.g. from HubSpot) still needs the floor / ceiling sizing
        p = parts(model)
        (p[:floor] || p[:ceiling]) && (r['width'].nil? || r['length'].nil?) ? true : false
      end

      # The customers folder: always 1_CUSTOMERS on the shared drive when it's there. Only a
      # computer without it uses the folder chosen with "customers folder..." (never a
      # customer's own folder).
      def self.customers_dir? = defined?(HubSpotRoom) && File.directory?(HubSpotRoom::CUSTOMERS_DIR)

      def self.jobs_folder
        return HubSpotRoom::CUSTOMERS_DIR if customers_dir?
        f = Sketchup.read_default(Settings::PREFS, PREF_JOBS, '').to_s
        f.empty? || !File.directory?(f) || customer_folder?(f) ? nil : f
      end

      # "REID, Charlotte - Chester - (870739371231)", "WILLIAMS Rebecca (830735284436)"
      def self.customer_folder?(f) = File.basename(f.to_s) =~ /\(\s*(?:[^()]*\D)?\d{5,}\s*\)\s*\z/ ? true : false

      def self.safe(name)
        name.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '').strip.sub(/\.skp\z/i, '')
      end

      # The customer's folder in the customers folder, found by the HubSpot contact ID, else
      # the name a new one would get: "REID, Charlotte - Chester - (870739371231)".
      def self.folder_for(pick, jf)
        found = HubSpotRoom.customer_folder(pick['contact_id'], jf)
        return { 'folder' => found, 'name' => File.basename(found), 'exists' => true, 'customer' => pick['customer'] } if found
        name = safe(HubSpotRoom.folder_name(pick))
        { 'folder' => File.join(jf, name), 'name' => name, 'exists' => false, 'customer' => pick['customer'] }
      end

      # The customer's full name from a customer folder's name ("Charlotte Reid").
      def self.customer_from_folder(f)
        JobInfo.split_name(File.basename(f.to_s)).reject(&:empty?).join(' ')
      end

      # The room name kept for the labels and PDFs: as typed, or capitalised when typed all
      # in small letters ("grace's room" -> "Grace's Room").
      def self.room_label(name)
        n = name.to_s.strip.gsub(/\s+/, ' ')
        n == n.downcase ? JobInfo.title(n) : n
      end

      def self.data(model)
        jf = jobs_folder
        p = parts(model)
        r = get(model) || {}
        { 'saved' => !model.path.to_s.empty?, 'file' => File.basename(model.path.to_s, '.skp'),
          'jobs' => jf, 'jobs_fixed' => customers_dir? ? true : false, 'hubspot' => HubSpot.key?,
          'width' => r['width'], 'length' => r['length'], 'ceiling' => r['ceiling'] || (Ceiling.mm(model).positive? ? Ceiling.mm(model) : nil),
          'has_floor' => !p[:floor].nil?, 'has_ceiling' => !p[:ceiling].nil? }
      end

      # New job: the customer from HubSpot (search, then the project's Room or Design Visit),
      # the folder found by contact ID (or made), the file name checked, then the room size.
      def self.show(model = Sketchup.active_model)
        dlg = Dialog.open('room', title: 'HW - Room setup', key: 'hw_room_v2', width: 460, height: 640, data: data(model), resizable: true)
        js = ->(fn, obj) { dlg.execute_script("#{fn}(#{JSON.generate(obj)})") }
        dlg.add_action_callback('browse') do |_c|
          f = UI.select_directory(title: 'Customers folder (holds a folder per customer)', directory: jobs_folder || Dir.home)
          if f && customer_folder?(f)
            UI.messagebox("#{File.basename(f)} is a customer's folder.\n\nChoose the folder that holds the customer folders (e.g. 1_CUSTOMERS).")
          elsif f
            Sketchup.write_default(Settings::PREFS, PREF_JOBS, f.tr('\\', '/'))
            js.call('setJobs', 'jobs' => jobs_folder)
          end
        end
        dlg.add_action_callback('search') do |_c, q|
          Steps.one(dlg, q.to_s.strip.empty? ? 'Reading recent projects' : "Searching HubSpot for \"#{q.to_s.strip}\"",
                    done: ->(r) { js.call('projects', 'projects' => r) }, fail: ->(e) { js.call('projects', 'error' => e.message) }, bg: true) { HubSpot.search_projects(q) }
        end
        dlg.add_action_callback('project') do |_c, pid|
          Steps.one(dlg, 'Reading the rooms and customer',
                    done: lambda { |r|
                      jf = jobs_folder
                      r['found'] = jf ? folder_for(r, jf) : nil
                      js.call('rooms', r)
                    }, fail: ->(e) { js.call('rooms', 'error' => e.message) }) { HubSpotRoom.project_details(pid.to_s) }
        end
        # "select folder manually": any folder inside the customers folder.
        dlg.add_action_callback('pickFolder') do |_c|
          f = UI.select_directory(title: 'Customer folder', directory: jobs_folder || Dir.home)
          js.call('setFolder', 'folder' => f.tr('\\', '/'), 'name' => File.basename(f), 'exists' => true, 'customer' => customer_from_folder(f)) if f
        end
        dlg.add_action_callback('never') do |_c|
          Ops.run(model, 'Room: don\'t ask', transparent: true) { model.set_attribute(DICT, SKIP, true) }
          dlg.close
        end
        dlg.add_action_callback('openExisting') do |_c, path|
          dlg.close
          Sketchup.open_file(path) if File.exist?(path.to_s)
        end
        dlg.add_action_callback('apply') do |_c, json|
          o = JSON.parse(json)
          err = save_and_apply(model, o)
          err.is_a?(Hash) ? js.call('exists', err) : (err ? js.call('problem', err) : dlg.close)
        end
        dlg.show
        dlg
      end

      # Saves the file first if it hasn't been (so a typo in the name changes nothing), links
      # it to HubSpot when a customer was picked, then sizes the room in one undo step.
      # Returns nil, an error message, or { 'path' } when that file already exists.
      def self.save_and_apply(model, o)
        w, l, c = o['width'].to_f, o['length'].to_f, o['ceiling'].to_f
        return 'Enter the ceiling height.' unless c.positive?
        p = parts(model)
        return 'Enter the room width and length.' if (p[:floor] || p[:ceiling]) && !(w.positive? && l.positive?)
        pick = o['pick'].is_a?(Hash) ? o['pick'] : nil
        room = o['room'].to_s.strip
        if model.path.to_s.empty?
          jf = jobs_folder or return 'Choose the customers folder first.'
          dir = o['folder'].to_s.strip.tr('\\', '/')
          dir = File.join(jf, safe(File.basename(dir))) unless dir.start_with?(jf) # keep it inside the customers folder
          return 'Pick the project (or select the folder manually).' if File.basename(dir).empty? || File.expand_path(dir) == File.expand_path(jf)
          return 'Enter the room name.' if room.empty?
          customer = pick ? pick['customer'] : customer_from_folder(dir)
          file = HubSpotRoom.job_file_name(room, customer, design_visit: pick && pick['design_visit'])
          path = File.join(dir, file)
          return { 'path' => path, 'name' => file, 'folder' => File.basename(dir) } if File.exist?(path)
          FileUtils.mkdir_p(dir)
        end
        Ops.run(model, 'Room setup') do
          apply(model, width: w, length: l, ceiling: c)
          HubSpotRoom.store_link(model, HubSpotRoom.link_from(pick)) if pick
          model.set_attribute(DICT, 'room_name', room_label(room)) unless room.empty?
        end
        show_room(model)
        # always saved: a new job where it was chosen, an existing one where it is
        path ||= model.path.to_s
        ok = model.save(path)
        return "SketchUp couldn't save #{path}." unless ok
        HubSpotRoom.refresh_info(model) if pick && !pick['design_visit']
        Pencil.invalidate(model) if defined?(Pencil)
        Sketchup.status_text = "Room #{w.round} x #{l.round} mm, ceiling #{c.round} mm - saved as #{path}."
        nil
      rescue StandardError => e
        Log.error('room setup', e)
        "Couldn't set up the room: #{e.message}"
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); Room.later(model); end
        def onOpenModel(model); Room.later(model); end
      end

      def self.later(model)
        UI.start_timer(1.0, false) { show(model) if model.valid? && model == Sketchup.active_model && ask?(model) }
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
      end
    end
  end
end
