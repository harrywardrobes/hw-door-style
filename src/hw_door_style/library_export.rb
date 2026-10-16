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
      SKIP_DIRS = /\A(_|\.)|\AHW Colours\z/i.freeze
      MASTER_RE = /\AComponents V(\d+)\.(skp|skb)\z/i.freeze
      MAIN = 'MAIN COMPONENTS'.freeze
      GUESS = [
        [/WARDROBE|\AWRD|WALK|\AWLK|LINEN|TOPBOX|TPBX/i, 'WARDROBES'],
        [/DRAWER|DRW|SHOE/i, 'DRAWERS'],
        [/BRIDGE|\ABRG/i, 'BRIDGE'],
        [/BOOKCASE|\ABKS/i, 'BOOKCASE'],
        [/SHELF|\ABXSH|\ACAB/i, 'SHELVING']
      ].freeze

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
        (dirs | [MAIN]).sort
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
        model.entities.grep(Sketchup::ComponentInstance).each do |i|
          next if seen[i.definition]
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

      # Older file names that hold the same component, e.g. WARDROBE <- WRD.
      def self.aliases(name)
        a = Settings.get['export_aliases']
        list = a.is_a?(Hash) ? Array(a.find { |k, _| k.to_s.casecmp?(name) }&.last) : []
        ([name] + list.map(&:to_s)).map(&:strip).reject(&:empty?).uniq
      end

      def self.file_re(names)
        alt = names.map { |n| Regexp.escape(n) }.join('|')
        /\A(?:#{alt})(?:[_ ]V?(\d+))?\.skp\z/i
      end

      # Every .skp for the component: { current: [paths outside _old], version: highest }.
      def self.scan(model, name)
        re = file_re(aliases(name))
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

      def self.guess_folder(name, folders)
        GUESS.each { |re, f| return f if name =~ re && folders.include?(f) }
        MAIN
      end

      # Changes whenever the component or anything inside it is edited or redrawn.
      def self.fingerprint(inst)
        guids = []
        seen = {}
        walk = lambda do |d|
          next if seen[d]
          seen[d] = true
          guids << "#{d.name}:#{d.guid}:#{d.entities.size}"
          d.entities.grep(Sketchup::ComponentInstance).each { |c| walk.call(c.definition) }
        end
        walk.call(inst.definition)
        dc = inst.attribute_dictionary('dynamic_attributes')
        attrs = dc ? dc.to_a.sort_by { |k, _| k }.map { |k, v| "#{k}=#{v}" } : []
        Digest::MD5.hexdigest((guids.sort + attrs).join("\n"))
      end

      # Rows for the window.
      def self.rows(model)
        m = meta(model)
        fl = folders(model)
        components(model).map do |name, inst|
          s = scan(model, name)
          rec = m[name] || {}
          from_file = s[:current].map { |p| File.basename(File.dirname(p)) }.find { |f| fl.include?(f) }
          folder = rec['folder'] if fl.include?(rec['folder'].to_s)
          folder ||= from_file || guess_folder(name, fl)
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

      # Drawers moved by onClick ANIMATE: put back to Y = 0. Returns names closed.
      def self.close_drawers(entities)
        closed = []
        Finder.each_instance(entities) do |i|
          d = i.attribute_dictionary('dynamic_attributes') or next
          oc = d['onclick'] || i.definition.get_attribute('dynamic_attributes', 'onclick')
          next unless oc.to_s =~ /ANIMATE/i
          y = d['y'].to_f
          next unless y.abs > 0.0001 || d['_onclick_state1'].to_s.to_i != 0
          if y.abs > 0.0001
            t = i.transformation
            i.transformation = Geom::Transformation.translation([0, -y, 0]) * t
          end
          i.set_attribute('dynamic_attributes', 'y', 0.0)
          i.set_attribute('dynamic_attributes', '_onclick_state1', 0) if d['_onclick_state1']
          closed << Finder.label(i)
        end
        closed
      end

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
        { components: defs.map(&:name).sort, materials: unused_materials(model, used) }
      end

      def self.unused_materials(model, used)
        inuse = {}
        note = ->(m) { inuse[m] = true if m }
        scan = lambda do |ents|
          ents.each do |e|
            note.call(e.material) if e.respond_to?(:material)
            note.call(e.back_material) if e.respond_to?(:back_material)
          end
        end
        scan.call(model.entities)
        used.each_key { |d| scan.call(d.entities) }
        model.definitions.select(&:group?).each { |d| scan.call(d.entities) }
        model.materials.reject { |m| inuse[m] }.map(&:name).sort
      end

      # Clean the master in place (one undo step): colours Default, drawers closed,
      # optionally purge unused components and materials.
      def self.clean_model(model, purge)
        report = { painted: 0, closed: [], purged_components: 0, purged_materials: 0 }
        model.start_operation('Clean model for export', true)
        begin
          report[:painted] = Colours.apply(model, Colours.all_default).values.sum
          report[:closed] = close_drawers(model.entities)
          if purge
            u = unused(model)
            report[:purged_components] = u[:components].size
            report[:purged_materials] = u[:materials].size
            model.definitions.purge_unused
            model.materials.purge_unused
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          raise e
        end
        report
      end

      # --- exporting ------------------------------------------------------

      def self.save_version
        Sketchup::Model.const_defined?(:VERSION_2026) ? Sketchup::Model::VERSION_2026 : nil
      end

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

        model.start_operation("Export #{row['name']}", true)
        begin
          Colours.apply(model, Colours.all_default, root: inst, record: false)
          inst.material = nil
          close_drawers(inst.definition.entities)
          # Carry the instance's Dynamic Component values ("as drawn") into the file.
          if (dc = inst.attribute_dictionary('dynamic_attributes'))
            dc.each_pair { |k, val| inst.definition.set_attribute('dynamic_attributes', k, val) }
          end
          ok = save_version ? inst.definition.save_as(path, save_version) : inst.definition.save_as(path)
          raise "SketchUp could not save #{path}" unless ok && File.exist?(path)
        ensure
          model.abort_operation
        end

        moved = s[:current].reject { |p| File.expand_path(p) == File.expand_path(path) }.map { |p| move_to_old(model, p) }

        m = meta(model)
        m[row['name']] = { 'folder' => row['folder'], 'version' => v, 'file' => path,
                           'fingerprint' => before, 'exported' => Time.now.strftime('%d/%m/%Y %H:%M') }
        model.start_operation('Record component export', true, false, true)
        save_meta(model, m)
        model.commit_operation
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
        { file: File.basename(target), moved: moved }
      end

      # --- window ---------------------------------------------------------

      def self.payload(model)
        u = unused(model)
        { 'master' => File.basename(model.path), 'root' => root(model), 'old' => File.basename(old_dir(model)),
          'folders' => folders(model), 'rows' => rows(model), 'next_master' => File.basename(next_master(model)),
          'unused' => { 'components' => u[:components], 'materials' => u[:materials] } }
      end

      def self.show
        model = Sketchup.active_model
        unless master?(model)
          UI.messagebox("Export components only works in a saved library file with \"Components\" in its name\n(e.g. Components V17.skp).\n\nThis file: #{model.path.to_s.empty? ? '(not saved)' : File.basename(model.path)}")
          return
        end
        @dlg&.close
        @dlg = dlg = UI::HtmlDialog.new(dialog_title: 'HW - Export components', preferences_key: 'hw_library_export',
                                        width: 900, height: 680, resizable: true, scrollable: true,
                                        style: UI::HtmlDialog::STYLE_DIALOG)
        html = File.read(File.join(PATH, 'html', 'export.html'))
        dlg.set_html(html.sub('/*DATA*/null', JSON.generate(payload(model))))
        dlg.add_action_callback('close') { |_c| dlg.close }
        dlg.add_action_callback('refresh') { |_c| dlg.execute_script("load(#{JSON.generate(payload(model))})") }
        dlg.add_action_callback('clean') do |_c, purge|
          begin
            r = clean_model(model, purge.to_s == 'true')
            msg = "Model cleaned (one undo step): #{r[:painted]} parts set to Default colour, " \
                  "#{r[:closed].size} drawers closed, #{r[:purged_components]} unused components and " \
                  "#{r[:purged_materials]} unused materials purged. Check it over, then export."
            dlg.execute_script("load(#{JSON.generate(payload(model))}); note(#{JSON.generate(msg)})")
          rescue StandardError => e
            dlg.execute_script("note(#{JSON.generate("Clean failed and was undone: #{e.message}")})")
          end
        end
        dlg.add_action_callback('export') do |_c, json|
          req = JSON.parse(json)
          run(model, dlg, req['rows'], req['save_master'])
        end
        dlg.show
      end

      # Exports one component per timer tick so the progress bar can update.
      def self.run(model, dlg, rows, save_master)
        total = rows.size + (save_master ? 1 : 0)
        done = []
        errors = []
        queue = rows.dup
        js = ->(s) { dlg.execute_script(s) }
        js.call("progress(0, #{total}, 'Starting...')")
        finish = lambda do
          master = nil
          if save_master
            js.call("progress(#{total - 1}, #{total}, #{JSON.generate("Saving #{File.basename(next_master(model))}...")})")
            begin
              master = save_master(model)
            rescue StandardError => e
              errors << "Master file: #{e.message}"
            end
          end
          js.call("progress(#{total}, #{total}, 'Done')")
          js.call("finished(#{JSON.generate('done' => done, 'errors' => errors, 'master' => master)}); load(#{JSON.generate(payload(model))})")
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
          end
        end
        step.call
      end
    end
  end
end
