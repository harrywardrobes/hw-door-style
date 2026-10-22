require 'json'
require 'digest'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # Exports each top-level component of the master library file
    # ("Components V17.skp") to its own versioned .skp in the folder structure
    # next to it:
    #
    #   <root>/WARDROBES/WARDROBE_V2.skp      new version
    #   <root>/_old/WRD_V1.skp                previous file(s) moved here
    #
    # Every export is cleaned first (colours to Default, drawers closed, origin
    # = component origin, only what the component uses), as drawn, SketchUp 2026.
    # Folder / version / fingerprint per component are remembered in the master.
    module LibraryExport
      META = 'hw_library_export'.freeze
      SKIP_DIRS = /\A(_|\.)/.freeze # _old, _HW Door Style, hidden folders
      MASTER_RE = /\AComponents V(\d+)\.(skp|skb)\z/i.freeze

      # Sub-folder for a component, from the Product list table: its Pod letter (T, W, B, F),
      # internals under T_INTERNALS, everything else OTHER - names in Settings "export_folders".
      def self.folder_for(name)
        n = name.to_s.upcase
        c = Products.cfg
        key = case Products.role(n, c)
              when 'unit', 'joiner' then Products.ref_of(n, c)
              when 'internal' then 'T_INTERNALS'
              else 'OTHER'
              end
        f = (Settings.get['export_folders'] || {})
        f[key] || f['OTHER'] || 'Other'
      end

      def self.main = (Settings.get['export_folders'] || {})['OTHER'] || 'Other'

      # --- where things are ---------------------------------------------

      def self.master?(model)
        !model.path.to_s.empty? && File.basename(model.path) =~ /components/i
      end

      def self.root(model)
        File.dirname(model.path)
      end

      def self.old_dir(model)
        File.join(root(model), Settings.get['export_old_folder'].to_s.strip.then { |s| s.empty? ? '_old' : s })
      end

      # Sub-folders a component can go in ('' = the main folder).
      def self.folders(model)
        dirs = Dir.children(root(model)).select { |d| File.directory?(File.join(root(model), d)) && d !~ SKIP_DIRS }.sort
        (dirs | (Settings.get['export_folders'] || {}).values.map(&:to_s).reject(&:empty?)).sort
      end

      def self.safe(name)
        name.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '_').strip
      end

      # --- components ---------------------------------------------------

      def self.base(defn)
        defn.name.sub(/#\d+\z/, '').strip
      end

      # Top-level components, one row per definition. Returns [[name, instance], ...].
      def self.components(model)
        seen = {}
        list = []
        skip = Settings.names('export_skip')
        model.entities.grep(Sketchup::ComponentInstance).each do |i|
          next if seen[i.definition]
          next if skip.include?(base(i.definition).upcase)
          seen[i.definition] = true
          list << i
        end
        counts = Hash.new(0)
        list.each { |i| counts[base(i.definition)] += 1 }
        list.map do |i|
          n = base(i.definition)
          n = i.definition.name.tr('#', '-') if counts[n] > 1
          [safe(n), i]
        end.sort_by(&:first)
      end

      def self.file_re(name)
        /\A#{Regexp.escape(name)}(?:[_ ]V?(\d+))?\.skp\z/i
      end

      # Every .skp for the component: { current: [paths outside _old], version: highest }.
      def self.scan(model, name)
        re = file_re(name)
        current = []
        top = 0
        dirs = [root(model)] + folders(model).map { |f| File.join(root(model), f) }
        dirs.each do |d|
          next unless File.directory?(d)
          Dir.children(d).each do |f|
            next unless (md = re.match(f))
            current << File.join(d, f)
            top = [top, (md[1] || 1).to_i].max
          end
        end
        if File.directory?(old_dir(model))
          Dir.children(old_dir(model)).each do |f|
            md = re.match(f) or next
            top = [top, (md[1] || 1).to_i].max
          end
        end
        { current: current, version: top }
      end

      def self.meta(model)
        JSON.parse(model.get_attribute(META, 'components', '{}'))
      rescue StandardError
        {}
      end

      def self.save_meta(model, data)
        model.set_attribute(META, 'components', JSON.generate(data))
      end

      def self.guess_folder(name, _folders = nil)
        folder_for(name)
      end

      VOLATILE = /_error\z|\A_?onclick_state|\A_lastmodified|\A_?formatversion\z/i.freeze

      def self.attrs_sig(obj)
        d = obj.attribute_dictionary('dynamic_attributes')
        return '' unless d
        d.to_a.reject { |k, _| k =~ VOLATILE }.sort_by(&:first).map do |k, v|
          "#{k}=#{v.is_a?(Float) ? v.round(5) : v}"
        end.join('|')
      end

      def self.round_a(a)
        a.map { |x| x.round(4) }
      end

      # Content of the component and everything inside it (geometry, positions,
      # sizes, materials, tags, DC values). Same content = same fingerprint,
      # whatever SketchUp does to its internal ids.
      def self.fingerprint(inst)
        parts = []
        seen = {}
        walk = lambda do |d|
          next if seen[d]
          seen[d] = true
          faces = d.entities.grep(Sketchup::Face)
          b = d.bounds
          parts << [d.name, d.entities.size, faces.size, d.entities.grep(Sketchup::Edge).size,
                    faces.sum(&:area).round(3), round_a([b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z]),
                    faces.map { |f| "#{f.material&.name}/#{f.layer.name}" }.tally.sort, attrs_sig(d)].inspect
          d.entities.each do |e|
            next unless e.respond_to?(:definition)
            parts << [d.name, e.definition.name, round_a(e.transformation.to_a), e.material&.name,
                      e.layer.name, e.hidden?, attrs_sig(e)].inspect
            walk.call(e.definition)
          end
        end
        walk.call(inst.definition)
        parts << ['top', inst.material&.name, attrs_sig(inst)].inspect
        Digest::MD5.hexdigest(parts.sort.join("\n"))
      end

      # Rows for the window.
      def self.rows(model)
        m = meta(model)
        fl = folders(model)
        components(model).map do |name, inst|
          s = scan(model, name)
          rec = m[name] || {}
          folder = folder_for(name)
          v = s[:version] + 1
          status = if rec['fingerprint'].nil? then s[:current].empty? ? 'new' : 'not exported yet'
                   elsif rec['fingerprint'] == fingerprint(inst) then 'unchanged'
                   else 'changed'
                   end
          {
            'name' => name, 'id' => inst.entityID, 'folder' => folder, 'status' => status,
            'current' => s[:current].map { |p| p.sub(root(model) + File::SEPARATOR, '').tr('\\', '/') },
            'version' => v, 'file' => "#{name}_V#{v}.skp"
          }
        end
      end

      # --- cleaning -------------------------------------------------------

      # What "Purge unused" would remove.
      def self.unused(model)
        used = {}
        mark = lambda do |ents|
          ents.each do |e|
            next unless e.respond_to?(:definition)
            d = e.definition
            next if used[d]
            used[d] = true
            mark.call(d.entities)
          end
        end
        mark.call(model.entities)
        defs = model.definitions.reject { |d| d.image? || used[d] || d.group? }
        { components: defs.map(&:name).sort }
      end

      KINDS = [:door, :ext_drawer, :int_drawer].freeze

      # Doors and drawer fronts that aren't flat (the library ships flat; the job's style is
      # put on when a unit is placed).
      def self.styled(model)
        Finder.all_targets(model, KINDS).reject { |i, _k| (i.definition.get_attribute(DICT, 'style') || 'flat') == 'flat' }
      end

      # Clean the master in place (one undo step): colours Default, doors and drawer fronts
      # flat, drawers closed, optionally purge unused components (materials are never purged).
      def self.clean_model(model, purge)
        report = { painted: 0, closed: [], purged_components: 0, flat: 0 }
        Ops.run(model, 'Clean model for export') do
          report[:painted] = Colours.apply(model, Colours.all_default, plain: true).values.sum
          report[:closed] = Drawers.close(model.entities)
          st = styled(model)
          unless st.empty?
            Converter.rebuild(model, st, 'flat', override: false, finish: false)
            report[:flat] = st.size
          end
          if purge
            u = unused(model)
            report[:purged_components] = u[:components].size
            model.definitions.purge_unused # components only - materials are always kept
          end
        end
        report
      end

      # What still needs cleaning before an export is allowed:
      # { 'painted' => parts with a colour, 'open' => open drawers, 'ok' => true/false }.
      def self.check(model)
        painted = Colours.apply(model, Colours.all_default, record: false, plain: true, dry: true).values.sum
        open = Drawers.open_ones(model.entities)
        styled = styled(model).size
        { 'painted' => painted, 'open' => open.size, 'open_names' => open.first(8), 'styled' => styled,
          'ok' => painted.zero? && open.empty? && styled.zero? }
      end

      def self.not_clean_message(c)
        bits = []
        bits << "#{c['painted']} part(s) still have a colour" if c['painted'].positive?
        bits << "#{c['open']} drawer(s) are open" if c['open'].positive?
        bits << "#{c['styled']} door(s) / drawer front(s) aren't flat" if c['styled'].to_i.positive?
        "Clean the model first: #{bits.join(' and ')}. Press Clean model, check it over, then export."
      end

      # --- exporting ------------------------------------------------------

      def self.move_to_old(model, path)
        FileUtils.mkdir_p(old_dir(model))
        dest = File.join(old_dir(model), File.basename(path))
        if File.exist?(dest)
          ext = File.extname(path)
          dest = File.join(old_dir(model), "#{File.basename(path, ext)}_moved_#{Time.now.strftime('%Y%m%d_%H%M%S')}#{ext}")
        end
        File.rename(path, dest)
        dest
      end

      # Exports one component. The cleaning happens in an operation that is
      # undone again, so the master is left exactly as it was.
      # Returns { name:, file:, moved: [...] }.
      def self.export_one(model, row)
        inst = model.entities.find { |e| e.entityID == row['id'] }
        raise "#{row['name']} is no longer in the model" unless inst

        dir = row['folder'] == '' ? root(model) : File.join(root(model), row['folder'])
        FileUtils.mkdir_p(dir)
        s = scan(model, row['name'])
        v = s[:version] + 1
        path = File.join(dir, "#{row['name']}_V#{v}.skp")
        before = fingerprint(inst)

        Ops.throwaway(model, "Export #{row['name']}") do
          Colours.apply(model, Colours.all_default, root: inst, record: false, plain: true)
          inst.material = nil
          Drawers.close(inst.definition.entities)
          # Library files always carry runouts at 0 (the job sets them with the pencil).
          DC.redraw(inst) if Runouts.set(inst, Runouts::ZERO)
          # Carry the instance's Dynamic Component values ("as drawn") into the file.
          if (dc = inst.attribute_dictionary('dynamic_attributes'))
            dc.each_pair { |k, val| inst.definition.set_attribute('dynamic_attributes', k, val) }
          end
          # Saved in the running SketchUp's own file version.
          ok = inst.definition.save_as(path)
          raise "SketchUp could not save #{path}" unless ok && File.exist?(path)
        end

        moved = s[:current].reject { |p| File.expand_path(p) == File.expand_path(path) }.map { |p| move_to_old(model, p) }
        Local.mirror_file(path, root(model), moved.map { |p| File.basename(p) })

        m = meta(model)
        m[row['name']] = { 'folder' => row['folder'], 'version' => v, 'file' => path,
                           'fingerprint' => before, 'exported' => Time.now.strftime('%d/%m/%Y %H:%M') }
        Ops.run(model, 'Record component export', transparent: true) { save_meta(model, m) }
        { name: row['name'], file: path.sub(root(model) + File::SEPARATOR, ''), moved: moved.map { |p| File.basename(p) } }
      end

      # Master saved as the next "Components V<n>"; older masters moved to _old.
      def self.next_master(model)
        n = File.basename(model.path)[/V(\d+)/i, 1].to_i
        File.join(root(model), "Components V#{n + 1}.skp")
      end

      def self.save_master(model)
        target = next_master(model)
        n_new = File.basename(target)[/V(\d+)/i, 1].to_i
        ok = model.save(target)
        raise "SketchUp could not save #{target}" unless ok
        moved = Dir.children(root(model)).select do |f|
          (md = MASTER_RE.match(f)) && md[1].to_i < n_new
        end.map { |f| File.basename(move_to_old(model, File.join(root(model), f))) }
        Local.mirror_file(target, root(model), moved)
        { file: File.basename(target), moved: moved }
      end

      # --- window ---------------------------------------------------------

      def self.payload(model)
        u = unused(model)
        { 'master' => File.basename(model.path), 'root' => root(model), 'old' => File.basename(old_dir(model)),
          'folders' => folders(model), 'rows' => rows(model), 'next_master' => File.basename(next_master(model)),
          'unused' => { 'components' => u[:components] }, 'clean' => check(model),
          'template' => (TemplateExport.status(model).merge('default' => TemplateExport.default?) rescue { 'status' => 'error', 'error' => $!.message }) }
      end

      def self.show
        model = Sketchup.active_model
        unless master?(model)
          UI.messagebox("Export components only works in a saved library file with \"Components\" in its name\n(e.g. Components V17.skp).\n\nThis file: #{model.path.to_s.empty? ? '(not saved)' : File.basename(model.path)}")
          return
        end
        dlg = Dialog.open('export', title: 'HW - Export components', key: 'hw_library_export',
                                    width: 900, height: 680, data: payload(model))
        dlg.add_action_callback('close') { |_c| dlg.close }
        dlg.add_action_callback('refresh') { |_c| dlg.execute_script("load(#{JSON.generate(payload(model))})") }
        dlg.add_action_callback('clean') do |_c, purge|
          begin
            r = clean_model(model, purge.to_s == 'true')
            msg = "Model cleaned (one undo step): #{r[:painted]} parts set to Default colour, " \
                  "#{r[:flat]} doors / drawer fronts set to Flat, #{r[:closed].size} drawers closed, #{r[:purged_components]} unused components purged " \
                  "(materials kept). Check it over, then export."
            dlg.execute_script("load(#{JSON.generate(payload(model))}); note(#{JSON.generate(msg)})")
          rescue StandardError => e
            dlg.execute_script("note(#{JSON.generate("Clean failed and was undone: #{e.message}")})")
          end
        end
        dlg.add_action_callback('export') do |_c, json|
          req = JSON.parse(json)
          c = check(model)
          if c['ok']
            if req.key?('template_default')
              Settings.save(Settings.get.merge('template_default' => req['template_default'] ? true : false))
            end
            run(model, dlg, req['rows'], req['save_master'], template: req['template'])
          else
            dlg.execute_script("load(#{JSON.generate(payload(model))}); stopped(#{JSON.generate(not_clean_message(c))})")
          end
        end
        dlg.show
      end

      # Exports one component per timer tick so the progress bar can update.
      def self.run(model, dlg, rows, save_master, template: false)
        total = rows.size + (save_master ? 1 : 0) + (template ? 1 : 0)
        done = []
        errors = []
        queue = rows.dup
        js = ->(s) { dlg.execute_script(s) }
        js.call("progress(0, #{total}, 'Starting...')")
        Pencil.hold
        finish = lambda do
          Pencil.release
          master = nil
          tpl = nil
          if template
            js.call("progress(#{total - (save_master ? 2 : 1)}, #{total}, 'Saving the template...')")
            begin
              tpl = TemplateExport.export(model) || { unchanged: true }
            rescue StandardError => e
              errors << "Template: #{e.message}"
              Log.error('template export', e)
            end
          end
          if save_master
            js.call("progress(#{total - 1}, #{total}, #{JSON.generate("Saving #{File.basename(next_master(model))}...")})")
            begin
              master = save_master(model)
            rescue StandardError => e
              errors << "Master file: #{e.message}"
            end
          end
          js.call("progress(#{total}, #{total}, 'Done')")
          js.call("finished(#{JSON.generate('done' => done, 'errors' => errors, 'master' => master, 'template' => tpl)}); load(#{JSON.generate(payload(model))})")
          UI.openURL("file:///#{root(model).tr('\\', '/')}")
        end
        step = lambda do
          row = queue.shift
          return finish.call unless row
          js.call("progress(#{done.size + errors.size}, #{total}, #{JSON.generate("Exporting #{row['name']}...")})")
          UI.start_timer(0.05, false) do
            begin
              done << export_one(model, row)
            rescue StandardError => e
              errors << "#{row['name']}: #{e.message}"
            end
            step.call
          rescue StandardError => e
            Pencil.release
            Log.error("export stopped", e)
          end
        end
        step.call
      end
    end
  end
end
