module HarryWardrobes
  module DoorStyle
    # Formula fixes for library components, applied to any file that still has the old
    # formula (the exact old text must match, so anything already changed by hand is left).
    # Run with the Top of unit upgrade: on opening a file, and before the Scribe / Workshop
    # windows. Takes effect the next time the unit is redrawn.
    module ComponentFixes
      D = 'dynamic_attributes'.freeze

      FIXES = [
        {
          id: 'shelf_clear_of_top_rail',
          why: 'Top shelf stops under the top frame rail when a wardrobe is made shorter',
          key: 'sh_top_height_max',
          old: 'A02_FRAME_HEIGHT_CEILING - D02_FACING_TOP-ZZ_FLOOR_HEIGHT',
          new: 'IF(I04_TOPPED, A02_FRAME_HEIGHT_CEILING - THICKNESS, A02_FRAME_HEIGHT_CEILING - D02_FACING_TOP - MARGIN - (THICKNESS / 2)) - ZZ_FLOOR_HEIGHT - THICKNESS'
        },
        {
          id: 'lower_rail_splits_space',
          why: 'Lower hanging rail keeps its drop while it fits, else sits halfway between the floor and the shelf',
          key: 'rail_drop',
          old: 'parent!G06_RAIL_DROP',
          new: 'SMALLEST(parent!G06_RAIL_DROP, parent!F03_SH_TOP_HEIGHT_CALC / 2)'
        }
      ].freeze

      def self.norm(s)
        s.to_s.gsub('&quot;', '"').gsub(/\s+/, '')
      end

      # Entities (definitions and their instances, which can carry their own copy of a
      # formula) still on an old formula: [[entity, fix]].
      def self.pending(model)
        out = []
        model.definitions.each do |dfn|
          next if dfn.image?
          FIXES.each do |f|
            k = "_#{f[:key]}_formula"
            out << [dfn, f] if norm(dfn.get_attribute(D, k)) == norm(f[:old])
            dfn.instances.each { |i| out << [i, f] if norm(i.get_attribute(D, k)) == norm(f[:old]) }
          end
        end
        out
      end

      # Applies the fixes in one hidden step. Returns { fix id => entities changed }.
      def self.apply(model = Sketchup.active_model)
        todo = pending(model)
        return {} if todo.empty?
        counts = Hash.new(0)
        Ops.run(model, 'Component fixes', transparent: true) do
          todo.each do |e, f|
            e.set_attribute(D, "_#{f[:key]}_formula", f[:new])
            counts[f[:id]] += 1
          end
        end
        Log.info("component fixes: #{counts.map { |k, v| "#{k} x#{v}" }.join(', ')}")
        counts
      rescue StandardError => e
        Log.error('component fixes', e)
        {}
      end
    end
  end
end
