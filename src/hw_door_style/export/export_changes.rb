require 'json'
require 'zlib'
require 'base64'

module HarryWardrobes
  module DoorStyle
    # What changed in a library component since its last export, for the Export window's
    # "changed" dropdown.
    #
    # Each export records a snapshot of the component as it went into its file (cleaned:
    # Default colours, drawers shut, runouts 0) - every part by its path in the component
    # ("WARDROBE > SHELF (2)"), with its definition, position, rotation / scale, tag,
    # material, hidden flag, Dynamic Component values and formulas, and each definition's
    # geometry (faces, edges, area, box) and face materials / tags. The window compares the
    # component now with that snapshot.
    #
    # A component exported before this was recorded (0.91.0) gets its snapshot the first
    # time the window finds it unchanged; one that had already changed can only show its
    # changes from its next export on.
    module ExportChanges
      KEY_PREFIX = 'snap_'.freeze
      DICT_NAME = 'dynamic_attributes'.freeze
      # DC's own scratch values (as LibraryExport::VOLATILE).
      VOLATILE = /_error\z|\A_?onclick_state|\A_lastmodified|\A_?formatversion\z|\A_inst_[^_]/i.freeze
      LABELS = {
        'definition' => 'component (definition)', 'position' => 'position', 'axes' => 'rotation / scale',
        'tag' => 'tag', 'material' => 'material', 'hidden' => 'hidden', 'geometry' => 'geometry', 'faces' => 'face materials / tags'
      }.freeze

      def self.mm(v) = (v.to_f * 25.4).round(1)

      def self.val(v)
        v.is_a?(Float) ? v.round(5).to_s : v.to_s.gsub('&quot;', '"')
      end

      def self.base(defn)
        DC.base_name(defn)
      rescue StandardError
        defn.name.to_s
      end

      # { "PATH|key" => "value" } for a placed component (inside the caller's step).
      def self.snapshot(inst)
        out = {}
        attrs = lambda do |obj, path, pre|
          d = obj.attribute_dictionary(DICT_NAME) or next
          d.each_pair { |k, v| out["#{path}|#{pre}#{k}"] = val(v) unless k =~ VOLATILE }
        end
        walk = lambda do |d, path, depth|
          faces = d.entities.grep(Sketchup::Face)
          b = d.bounds
          area = (faces.sum(&:area) * 645.16).round(0) # in2 -> mm2
          out["#{path}|geometry"] = "#{faces.size} faces, #{d.entities.grep(Sketchup::Edge).size} edges, area #{area} mm2, " \
                                    "box #{mm(b.width)} x #{mm(b.height)} x #{mm(b.depth)} mm from (#{mm(b.min.x)}, #{mm(b.min.y)}, #{mm(b.min.z)})"
          fm = faces.map { |f| "#{f.material&.name || 'no material'} on #{f.layer.name}" }.tally.sort.map { |k, n| "#{k} x#{n}" }.join(', ')
          out["#{path}|faces"] = fm unless fm.empty?
          attrs.call(d, path, 'definition ')
          next if depth > 12
          count = Hash.new(0)
          d.entities.each do |e|
            next unless e.respond_to?(:definition)
            n = base(e.definition)
            count[n] += 1
            cp = "#{path} > #{n}#{count[n] > 1 ? " (#{count[n]})" : ''}"
            t = e.transformation
            out["#{cp}|definition"] = e.definition.name
            out["#{cp}|position"] = "(#{mm(t.origin.x)}, #{mm(t.origin.y)}, #{mm(t.origin.z)}) mm"
            ax = [t.xaxis, t.yaxis, t.zaxis].map { |v| v.to_a.map { |x| x.round(3) } }
            sc = [X_AXIS, Y_AXIS, Z_AXIS].map { |a| (t * a).length.to_f.round(4) } rescue [1, 1, 1]
            unless ax == [[1, 0, 0], [0, 1, 0], [0, 0, 1]] && sc.all? { |s| (s - 1).abs < 1e-4 }
              out["#{cp}|axes"] = "x #{ax[0]}, y #{ax[1]}, z #{ax[2]}, scale #{sc.join(' / ')}"
            end
            out["#{cp}|tag"] = e.layer.name
            out["#{cp}|material"] = e.material&.name.to_s
            out["#{cp}|hidden"] = e.hidden?.to_s
            attrs.call(e, cp, '')
            walk.call(e.definition, cp, depth + 1)
          end
        end
        top = base(inst.definition)
        out["#{top}|material"] = inst.material&.name.to_s
        attrs.call(inst, top, '')
        walk.call(inst.definition, top, 0)
        out
      end

      def self.path_of(key) = key.split('|', 2)[0]

      def self.parent?(path, paths) = paths.any? { |p| path.start_with?("#{p} > ") }

      # What differs: { 'added' => [paths], 'removed' => [paths], 'parts' => [{ 'part', 'changes' => [[what, was, now]] }] }.
      # A part added or removed is listed once (not everything inside it).
      def self.diff(old, now)
        op = old.keys.map { |k| path_of(k) }.uniq
        np = now.keys.map { |k| path_of(k) }.uniq
        added = np - op
        removed = op - np
        added = added.reject { |p| parent?(p, added) }
        removed = removed.reject { |p| parent?(p, removed) }
        gone = ->(p) { added.include?(p) || removed.include?(p) || parent?(p, added) || parent?(p, removed) }
        by = Hash.new { |h, k| h[k] = [] }
        (old.keys | now.keys).each do |k|
          p, what = k.split('|', 2)
          next if gone.call(p)
          a = old[k]
          b = now[k]
          next if a == b
          by[p] << [LABELS[what] || what, a, b]
        end
        order = (np | op)
        parts = by.keys.sort_by { |p| order.index(p) || 0 }.map { |p| { 'part' => p, 'changes' => by[p].sort_by(&:first) } }
        { 'added' => added, 'removed' => removed, 'parts' => parts }
      end

      def self.empty?(d) = d['added'].empty? && d['removed'].empty? && d['parts'].empty?

      # --- kept in the master -----------------------------------------------------------

      def self.pack(snap) = Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(snap)))

      def self.unpack(s)
        s.to_s.empty? ? nil : JSON.parse(Zlib::Inflate.inflate(Base64.strict_decode64(s)))
      rescue StandardError
        nil
      end

      def self.stored(model, name) = unpack(model.get_attribute(LibraryExport::META, KEY_PREFIX + name.to_s))

      # Inside the caller's step.
      def self.store(model, name, snap)
        model.set_attribute(LibraryExport::META, KEY_PREFIX + name.to_s, pack(snap))
      end
    end
  end
end
