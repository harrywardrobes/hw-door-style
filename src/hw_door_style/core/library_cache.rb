require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # A copy of the component library on this computer, for the Add component (+) window.
    #
    #   library folder (Google Drive)               this computer (%APPDATA%\HW Door Style\library)
    #   WARDROBES/WARDROBE_V10.skp       ->         WARDROBES/WARDROBE_V10.skp + WARDROBE_V10.png
    #   _old/...                                    (never copied)
    #
    # Only the latest version of each component is kept. The window opens on the copy here
    # straight away (no waiting on Drive) and brings it up to date in the background:
    # new / newer files copied, the picture taken from the file's own thumbnail, components
    # gone from the library dropped. If the library can't be reached the copy is used as it is.
    module LibraryCache
      DIR = File.join(Settings::USER_DIR, 'library')
      INDEX = File.join(DIR, 'index.json')
      DEFAULT_ROOT = 'G:/My Drive/1_Gautier Design Ltd/4_Assets/SketchUp Components/Harry Wardrobes'.freeze
      SKIP_DIR = /\A(_|\.)/.freeze           # _old, _HW Door Style, hidden folders
      MASTER = /\AComponents V\d+/i.freeze     # the master library file itself
      OTHER = 'OTHER'.freeze                   # loose .skp files in the library's own folder
      VER_RE = /\A(.+?)[ _-]+V(\d+)\z/i.freeze # WARDROBE_V10, "SHOE_UNIT V2"

      # Groups in the window: the Pod number letters (T tall, W wall / bridge, B base, L drawer
      # units, F facings, M misc - Settings "product_refs" / "product_ref_names"), then the
      # categories that aren't pods (Electrical Faceplates), then everything else.
      ORDER = ['T', 'W', 'B', 'L', 'F', 'M', 'ELECTRICAL FACEPLATES', OTHER].freeze
      COLOURS = {
        'T' => '#2f4a3f', 'W' => '#3d5a80', 'B' => '#7a4e2d', 'L' => '#b4541a', 'F' => '#6d4c7d', 'M' => '#6b7f3a',
        'ELECTRICAL FACEPLATES' => '#9a7b0a', OTHER => '#6a737d'
      }.freeze

      # The group a library component is shown under: a plain category (faceplates) is its
      # own group; a pod (a product type, or a name in product_refs) goes under its letter;
      # the rest (bullnose, ceiling, cover) under Other.
      def self.group(e)
        return e['cat'] if plain?(e['cat'])
        n = e['name'].to_s.upcase
        c = Products.cfg
        return OTHER if Products.skip?(n, c)
        return Products.ref_of(n, c) if Products.type_of(n, c) || c['refs'].keys.any? { |k| n == k || n.start_with?(k) }
        OTHER
      end

      def self.group_label(g)
        return pretty(g) unless g =~ /\A[A-Z]\z/
        name = (Settings.get['product_ref_names'] || {})[g].to_s
        name.empty? ? g : "#{g} - #{name}"
      end

      # A category that isn't furniture (Settings "ignore_component_folders", e.g. Electrical
      # Faceplates): placed as it is - no job colours, scribes or door style - and left out
      # of the Workshop.
      def self.plain?(cat)
        folders = Array(Settings.get['ignore_component_folders']).map { |f| f.to_s.downcase }
        folders.include?(cat.to_s.downcase)
      end

      def self.root
        r = Settings.get['library_folder'].to_s.strip
        r.empty? ? DEFAULT_ROOT : r
      end

      # 'WARDROBE_V10' -> ['WARDROBE', 10]; no version -> [name, 0].
      def self.parse(base)
        m = VER_RE.match(base)
        m ? [m[1], m[2].to_i] : [base, 0]
      end

      # 'INT_DRAWER_PLUS' -> 'Int Drawer Plus', 'WALK-IN' -> 'Walk-In', 'MAIN COMPONENTS' -> 'Main Components'.
      # A name already in mixed case ('Double UK 3 Pin Power Socket') is left as it is.
      def self.pretty(name)
        return name.to_s.tr('_', ' ').squeeze(' ').strip if name.to_s =~ /[a-z]/
        name.to_s.tr('_', ' ').split(/(\s+|-)/).map { |w| w =~ /\A[A-Za-z]/ ? w.capitalize : w }.join.squeeze(' ').strip
      end

      def self.cat_order(cat)
        ORDER.index(cat) || ORDER.size
      end

      def self.colour(cat)
        COLOURS[cat] || '#6a737d'
      end

      def self.key(cat, name)
        "#{cat}/#{name.upcase}"
      end

      # The library as it is now: latest .skp of each component.
      # [{ 'key', 'cat', 'name', 'ver', 'src', 'size', 'mtime' }]. Raises if the folder isn't there.
      def self.scan(dir = root)
        raise Errno::ENOENT, dir unless File.directory?(dir)
        found = {}
        add = lambda do |cat, folder|
          Dir.children(folder).each do |f|
            next unless f =~ /\.skp\z/i
            base = File.basename(f, '.*')
            next if cat == OTHER && base =~ MASTER
            name, ver = parse(base)
            path = File.join(folder, f)
            k = key(cat, name)
            next if found[k] && found[k]['ver'] >= ver
            st = File.stat(path)
            found[k] = { 'key' => k, 'cat' => cat, 'name' => name, 'ver' => ver, 'src' => path, 'size' => st.size, 'mtime' => st.mtime.to_i }
          end
        end
        Dir.children(dir).sort.each do |d|
          p = File.join(dir, d)
          add.call(d.upcase, p) if File.directory?(p) && d !~ SKIP_DIR
        end
        add.call(OTHER, dir)
        found.values
      end

      # --- the copy on this computer -----------------------------------------

      def self.index
        JSON.parse(File.read(INDEX))
      rescue StandardError
        {}
      end

      def self.save_index(idx)
        FileUtils.mkdir_p(DIR)
        tmp = "#{INDEX}.tmp"
        File.write(tmp, JSON.pretty_generate(idx))
        File.rename(tmp, INDEX)
      end

      def self.safe(s)
        s.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '_').strip
      end

      def self.local_path(e)
        File.join(DIR, safe(e['cat']), "#{safe(e['name'])}_V#{e['ver']}.skp")
      end

      # What needs copying (new or changed) and what has gone from the library.
      def self.plan(scanned, idx = index)
        get = scanned.select do |e|
          have = idx[e['key']]
          have.nil? || have['ver'] != e['ver'] || have['size'] != e['size'] || !File.exist?(have['file'].to_s)
        end
        gone = idx.keys - scanned.map { |e| e['key'] }
        [get, gone]
      end

      # Copies one component here (and its picture). Returns the index entry.
      def self.fetch(e, idx)
        dst = local_path(e)
        FileUtils.mkdir_p(File.dirname(dst))
        tmp = "#{dst}.part"
        FileUtils.cp(e['src'], tmp)
        File.rename(tmp, dst)
        png = dst.sub(/\.skp\z/i, '.png')
        png = nil unless thumbnail(dst, png)
        old = idx[e['key']]
        drop_files(old) if old && old['file'] != dst
        idx[e['key']] = e.reject { |k, _| k == 'src' }.merge('file' => dst, 'png' => png, 'at' => Time.now.to_i)
      end

      def self.thumbnail(skp, png)
        return false unless defined?(Sketchup) && Sketchup.respond_to?(:save_thumbnail)
        Sketchup.save_thumbnail(skp, png) && File.exist?(png)
      rescue StandardError
        false
      end

      # Our own copies only (never the library).
      def self.drop_files(entry)
        [entry['file'], entry['png']].compact.each do |f|
          File.delete(f) if f.start_with?(DIR) && File.exist?(f)
        rescue StandardError
          nil
        end
      end

      def self.forget(keys, idx)
        keys.each { |k| (e = idx.delete(k)) && drop_files(e) }
      end

      # --- for the window --------------------------------------------------------

      def self.img(png)
        return nil unless png && File.exist?(png)
        @imgs ||= {}
        stamp = File.mtime(png).to_i
        hit = @imgs[png]
        return hit[1] if hit && hit[0] == stamp
        url = "data:image/png;base64,#{[File.binread(png)].pack('m0')}"
        @imgs[png] = [stamp, url]
        url
      end

      # Cards: [{ key, cat, name, label, ver, img, colour }] sorted by category then name.
      def self.cards(idx = index)
        idx.values.select { |e| File.exist?(e['file'].to_s) }
           .map { |e| [group(e), e] }
           .sort_by { |g, e| [cat_order(g), g, e['name']] }
           .map do |g, e|
             { 'key' => e['key'], 'cat' => g, 'cat_label' => group_label(g), 'folder' => e['cat'], 'name' => e['name'], 'label' => pretty(e['name']),
               'ver' => e['ver'], 'img' => img(e['png']), 'colour' => colour(g), 'plain' => plain?(e['cat']) }
           end
      end
    end
  end
end
