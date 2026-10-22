require 'json'
require 'digest'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # The Harry Wardrobes template for "Welcome to SketchUp", saved with Export components.
    #
    # Made from the library file with no components in it - only what Settings
    # "template_keep" names (the floor, later the ceiling) - so it keeps the library's
    # units, tags, scenes, styles and materials. The plugin's own job settings
    # (colours, styles, scribes, HubSpot link) and the export records are left out, so
    # every new job starts clean.
    #
    #   <library>/_TEMPLATES/Harry Wardrobes Template V3.skp    versioned; older ones to _old
    #   %APPDATA%/SketchUp/SketchUp 2026/SketchUp/Templates/     the copy Welcome to SketchUp lists
    #
    # A new version is only saved when the template's content changed. Every computer with
    # the plugin picks up the latest from the library when SketchUp starts.
    module TemplateExport
      FOLDER = '_TEMPLATES'.freeze
      NAME = 'Harry Wardrobes Template'.freeze
      FILE_RE = /\AHarry Wardrobes Template V(\d+)\.skp\z/i.freeze
      META_KEY = 'template'.freeze

      def self.keep_names
        n = Settings.names('template_keep')
        n.empty? ? %w[FLOOR CEILING] : n
      end

      def self.keep?(e)
        return false unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
        names = [e.name.to_s.strip.upcase]
        names << e.definition.name.sub(/#\d+\z/, '').strip.upcase if e.respond_to?(:definition)
        (names & keep_names).any?
      end

      def self.dir(root) = File.join(root, FOLDER)

      # [[version, path]] of the template files in a folder, highest first.
      def self.versions(folder)
        return [] unless File.directory?(folder)
        Dir.children(folder).filter_map { |f| (m = FILE_RE.match(f)) && [m[1].to_i, File.join(folder, f)] }.sort_by { |v, _| -v }
      end

      def self.top_version(model)
        [versions(dir(LibraryExport.root(model))), versions(LibraryExport.old_dir(model))].flatten(1).map(&:first).max.to_i
      end

      def self.file_name(v) = "#{NAME} V#{v}.skp"

      # What the template holds: the kept parts, tags, scenes, styles and units.
      def self.fingerprint(model)
        keep = model.entities.select { |e| keep?(e) }
        parts = keep.map do |e|
          e.is_a?(Sketchup::ComponentInstance) ? LibraryExport.fingerprint(e) : [e.name, e.entities.size, LibraryExport.round_a(e.transformation.to_a)].inspect
        end.sort
        parts << model.layers.map(&:name).sort.inspect
        parts << model.pages.map(&:name).inspect
        parts << model.styles.map(&:name).sort.inspect
        parts << model.options['UnitsOptions'].keys.sort.map { |k| "#{k}=#{model.options['UnitsOptions'][k]}" }.inspect
        parts << Room.default_mm.inspect
        Digest::MD5.hexdigest(parts.join("\n"))
      end

      def self.record(model)
        LibraryExport.meta(model)[META_KEY] || {}
      end

      # For the Export window.
      def self.status(model)
        rec = record(model)
        v = top_version(model) + 1
        st = if versions(dir(LibraryExport.root(model))).empty? then 'new'
             elsif rec['fingerprint'] == fingerprint(model) then 'unchanged'
             else 'changed'
             end
        { 'status' => st, 'version' => v, 'file' => file_name(v), 'keeps' => model.entities.select { |e| keep?(e) }.map { |e| e.respond_to?(:definition) ? e.definition.name : e.name }.uniq,
          'current' => versions(dir(LibraryExport.root(model))).first&.last&.then { |p| File.basename(p) } }
      end

      # Saves the next version (inside a step that is undone again, so the library file
      # is left as it was). Returns { file:, moved:, installed: } or nil when unchanged.
      def self.default? = Settings.get['template_default'] != false

      # New files (File > New, and SketchUp's start-up file) start from it.
      def self.make_default(path)
        return unless path && Sketchup.respond_to?(:template=)
        Sketchup.template = path
      rescue StandardError => e
        Log.error('set default template', e)
      end

      def self.export(model, force: false, default: default?)
        root = LibraryExport.root(model)
        fp = fingerprint(model)
        return nil if !force && record(model)['fingerprint'] == fp && !versions(dir(root)).empty?
        FileUtils.mkdir_p(dir(root))
        v = top_version(model) + 1
        path = File.join(dir(root), file_name(v))
        old = versions(dir(root)).map(&:last)
        view = model.active_view
        c = view.camera
        cam = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov)
        desc = model.description
        Ops.throwaway(model, 'Export template') do
          drop = model.entities.select { |e| (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) && !keep?(e) }
          model.entities.erase_entities(drop) unless drop.empty?
          model.definitions.purge_unused
          # the floor and ceiling at the default room size (Settings > General); the room
          # itself isn't recorded, so Room setup still asks, with blank boxes
          d = Room.default_mm
          Room.apply(model, width: d['width'], length: d['length'], ceiling: d['ceiling'])
          [LibraryExport::META, DICT].each { |d2| model.attribute_dictionaries&.delete(d2) }
          model.description = "Harry Wardrobes job template V#{v} (#{Time.now.strftime('%d/%m/%Y')})"
          view.zoom_extents
          ok = model.save_copy(path)
          raise "SketchUp could not save #{path}" unless ok && File.exist?(path)
        end
        view.camera = cam
        model.description = desc if model.description != desc
        moved = old.reject { |p| File.expand_path(p) == File.expand_path(path) }.map { |p| File.basename(LibraryExport.move_to_old(model, p)) }
        Local.mirror_file(path, root, moved)
        m = LibraryExport.meta(model)
        m[META_KEY] = { 'version' => v, 'file' => path, 'fingerprint' => fp, 'exported' => Time.now.strftime('%d/%m/%Y %H:%M') }
        Ops.run(model, 'Record template export', transparent: true) { LibraryExport.save_meta(model, m) }
        installed = install_local(path)
        make_default(installed) if default
        { file: "#{FOLDER}/#{File.basename(path)}", moved: moved, installed: installed, default: default && installed ? true : false }
      end

      # --- this computer's Welcome to SketchUp ---------------------------------

      # SketchUp's own templates folder for this user (Welcome to SketchUp lists it).
      def self.user_dir
        year = "20#{Sketchup.version.to_i}"
        base = ENV['APPDATA'] || File.join(Dir.home, 'Library', 'Application Support')
        File.join(base, 'SketchUp', "SketchUp #{year}", 'SketchUp', 'Templates')
      end

      # Copies the template in (replacing older versions of ours there). Returns the path or nil.
      def self.install_local(src)
        d = user_dir
        FileUtils.mkdir_p(d)
        dst = File.join(d, File.basename(src))
        FileUtils.cp(src, dst) unless File.exist?(dst) && File.size(dst) == File.size(src)
        versions(d).each do |_v, p|
          next if File.expand_path(p) == File.expand_path(dst)
          File.delete(p) rescue nil # our own older copies only (the library keeps every version)
        end
        dst
      rescue StandardError => e
        Log.error('template install', e)
        nil
      end

      # At start-up: the latest template from the library, if this computer hasn't got it.
      def self.sync_local
        latest = versions(dir(LibraryCache.root)).first or return
        have = versions(user_dir).first
        if have && have[0] >= latest[0]
          # still the default if it should be (e.g. after SketchUp was reinstalled)
          make_default(have[1]) if default? && Sketchup.template.to_s.empty?
          return
        end
        dst = install_local(latest[1])
        make_default(dst) if default? && (Sketchup.template.to_s.empty? || File.basename(Sketchup.template.to_s) =~ FILE_RE)
        Log.info("template #{File.basename(latest[1])} added to Welcome to SketchUp")
      rescue StandardError => e
        Log.error('template sync', e)
      end

      def self.start
        return if @started
        @started = true
        UI.start_timer(6, false) { sync_local }
      end
    end
  end
end
