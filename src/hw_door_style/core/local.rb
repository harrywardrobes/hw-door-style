require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # The local folder on this computer (Settings "local_folder", e.g. Documents\Harry
    # Wardrobes) - the plugin's offline copies, nothing to do with Google Drive:
    #
    #   <local>/SketchUp Components/   a mirror of the library's current files - every
    #                                  exported component (same sub-folders), the master,
    #                                  the templates. No _old.
    #   <local>/Settings backups/      a dated settings backup, written every time Settings
    #                                  is saved (the last 30 kept).
    module Local
      MIRROR = 'SketchUp Components'.freeze
      BACKUPS = 'Settings backups'.freeze
      KEEP_BACKUPS = 30

      def self.root
        r = Settings.get['local_folder'].to_s.strip.tr('\\', '/')
        return r unless r.empty?
        File.join(ENV['USERPROFILE'].to_s.tr('\\', '/'), 'Documents', 'Harry Wardrobes')
      end

      def self.mirror = File.join(root, MIRROR)
      def self.backups = File.join(root, BACKUPS)

      # Copies a library file (under the library root) to the same place in the mirror;
      # older versions of the same component there are removed (the mirror holds current
      # files only - Drive's _old keeps the history). Returns the mirror path, or nil.
      def self.mirror_file(src, lib_root, old_names = [])
        rel = src.tr('\\', '/').sub(%r{\A#{Regexp.escape(lib_root.tr('\\', '/'))}/?}, '')
        return nil if rel == src.tr('\\', '/') # not under the library
        dst = File.join(mirror, rel)
        FileUtils.mkdir_p(File.dirname(dst))
        tmp = "#{dst}.part"
        FileUtils.cp(src, tmp)
        File.rename(tmp, dst)
        old_names.each do |n|
          f = File.join(File.dirname(dst), n)
          File.delete(f) if File.exist?(f) && File.expand_path(f) != File.expand_path(dst)
        end
        dst
      rescue StandardError => e
        Log.error('local mirror', e)
        nil
      end

      # Everything current in the library (no _old / hidden / plugin folders) copied to
      # the mirror. Returns the number of files copied.
      def self.mirror_all(lib_root)
        n = 0
        skip = %r{(\A|/)(_old|_HW Door Style|\.)}
        Dir.glob(File.join(lib_root.tr('\\', '/'), '**', '*')).each do |f|
          next if File.directory?(f) || f.sub(lib_root.tr('\\', '/'), '') =~ skip || File.basename(f) =~ /\A(desktop\.ini|.*\.skb)\z/i
          dst = File.join(mirror, f.sub(%r{\A#{Regexp.escape(lib_root.tr('\\', '/'))}/?}, ''))
          next if File.exist?(dst) && File.size(dst) == File.size(f) && File.mtime(dst) >= File.mtime(f)
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(f, dst, preserve: true)
          n += 1
        end
        n
      end

      # A dated settings backup (the same file as Download backup). Returns the path.
      def self.backup_settings(hash)
        FileUtils.mkdir_p(backups)
        path = File.join(backups, "HW Door Style settings #{Time.now.strftime('%Y-%m-%d %H%M%S')}.json")
        out = { Settings::BACKUP_MARK => VERSION, 'saved' => Time.now.strftime('%d/%m/%Y %H:%M') }.merge(hash)
        File.write(path, JSON.pretty_generate(out))
        old = Dir.glob(File.join(backups, 'HW Door Style settings *.json')).sort
        old[0...-KEEP_BACKUPS].each { |f| File.delete(f) } if old.size > KEEP_BACKUPS
        path
      rescue StandardError => e
        Log.error('settings backup', e)
        nil
      end
    end
  end
end
