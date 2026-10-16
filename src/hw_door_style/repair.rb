module HarryWardrobes
  module DoorStyle
    # "Repair doors in model": brings every door / styled drawer front up to the
    # wrapper contract (see Converter), in one undo step. Idempotent - items that
    # already meet the contract are left untouched.
    module Repair
      TOL = 0.1 / 25.4 # 0.1 mm in inches

      def self.scale_ok?(inst)
        s, = Finder.decompose(inst.transformation)
        s.all? { |v| (v - 1.0).abs < 0.0005 }
      end

      # Kind for an item whose name isn't in Settings but which holds a slab.
      def self.guess_kind(inst)
        n = Finder.names_for(inst).join(' ')
        return :int_drawer if n =~ /\AINT_|IDRW/
        return :ext_drawer if n =~ /DRW|DRAWER|FRONT/
        :door
      end

      # Every door wrapper, plus anything that already holds a slab (any name) -
      # including inside component definitions that aren't placed in the model.
      def self.candidates(model)
        found = {}
        lists = [model.entities] + model.definitions.reject { |d| d.image? }.map(&:entities)
        lists.each do |ents|
          ents.each do |inst|
            next unless inst.is_a?(Sketchup::ComponentInstance)
            next if found[inst.entityID]
            kind = Finder.kind_of(inst)
            has_slab = !Converter.slab_of(inst).nil?
            next unless kind == :door || has_slab
            found[inst.entityID] = [inst, kind || guess_kind(inst)]
          end
        end
        found.values
      end

      # Removes STYLE_* definitions the plugin made that nothing uses any more.
      def self.purge_old_slabs(model)
        old = model.definitions.select { |d| d.name =~ /\ASTYLE_/i && d.instances.empty? }
        old.each { |d| model.definitions.remove(d) }
        old.size
      end

      # Returns a list of reasons the item breaks the contract ([] = OK).
      def self.problems(inst, kind)
        p = []
        d = inst.definition
        p << 'wrapper has Len formulas' unless (DC.len_formulas(inst) + DC.len_formulas(d)).empty?
        p << 'no DOOR_W/T/H' unless %w[door_w door_t door_h].all? { |k| DC.read(inst, k).is_a?(Numeric) }
        p << 'wrapper scaled' unless scale_ok?(inst)
        p << 'loose faces in wrapper' unless d.entities.grep(Sketchup::Face).empty?
        kids = d.entities.grep(Sketchup::ComponentInstance)
        p << 'STYLE_* slab' if kids.any? { |k| k.definition.name =~ /\ASTYLE_/i }
        slabs = kids.select { |k| k.get_attribute(DICT, 'role') == 'style' }
        if slabs.size != 1
          p << "#{slabs.size} slabs"
        else
          s = slabs.first
          p << 'slab name' unless DC.read(s, '_name') == Converter.slab_name(kind)
          p << 'no DOOR_STYLE' if DC.read(s, 'door_style').to_s.empty?
          p << 'slab formulas' unless DC.read(s, '_lenx_formula') == 'parent!DOOR_W' &&
                                      DC.read(s, '_leny_formula') == 'parent!DOOR_T' &&
                                      DC.read(s, '_lenz_formula') == 'parent!DOOR_H'
          size = Finder.real_size(inst)
          ss, = Finder.decompose(s.transformation)
          b = s.definition.bounds
          got = [b.width * ss[0], b.height * ss[1], b.depth * ss[2]]
          p << 'slab size' if got.zip(size).any? { |g, w| (g - w).abs > TOL }
          p << 'shaker slab stretched' if DC.read(s, 'door_style').to_s.upcase == 'SHAKER' && !scale_ok?(s)
        end
        if kind == :door
          hinges = kids.select { |k| k.get_attribute(DICT, 'role') == 'hinge' }
          h = Finder.real_size(inst)[2]
          p << "hinges #{hinges.size} (rule #{Settings.hinge_count(h)})" if hinges.size != Settings.hinge_count(h)
          p << 'hinge scaled' unless hinges.all? { |k| scale_ok?(k) }
          p << 'hinge size' unless hinges.all? { |k| DC.read(k, '_leny_formula').to_s.include?('ZZ_HINGE_D') }
          p << 'hinge formulas' unless hinges.all? { |k| (f = DC.read(k, '_z_formula').to_s).include?('DOOR_H') && f !~ /\bMIN\(/i }
        end
        p
      end

      def self.top_level(inst, model)
        # Walk up via definition instances until we reach the model.
        cur = inst
        loop do
          parent = cur.parent
          return cur if parent.is_a?(Sketchup::Model)
          owner = parent.respond_to?(:instances) ? parent.instances.first : nil
          return cur unless owner
          cur = owner
        end
      end

      # Returns a report hash. Runs in one operation (redraw included).
      def self.run(model = Sketchup.active_model)
        cands = candidates(model)
        broken = cands.map { |inst, kind| [inst, kind, problems(inst, kind)] }.reject { |_i, _k, pr| pr.empty? }
        report = { checked: cands.size, fixed: [], skipped: [], components: [], after: [], purged: 0 }
        if broken.empty?
          stale = model.definitions.count { |d| d.name =~ /\ASTYLE_/i && d.instances.empty? }
          return report if stale.zero?
          model.start_operation('Repair doors in model', true)
          report[:purged] = purge_old_slabs(model)
          model.commit_operation
          return report
        end

        model.start_operation('Repair doors in model', true)
        begin
          pairs = broken.map { |i, k, _| [i, k] }
          res = Converter.rebuild(model, pairs, nil)
          report[:notes] = res[:notes]
          broken.each { |i, k, pr| report[:fixed] << "#{Finder.label(i)} (#{Finder::KINDS[k]}): #{pr.join(', ')}" }

          report[:purged] = purge_old_slabs(model)
          tops = broken.map { |i, _k, _| top_level(i, model) }.uniq
          tops.each do |t|
            next unless t.parent.is_a?(Sketchup::Model) # unplaced library definitions: nothing to redraw
            DC.redraw(t)
            report[:components] << t.definition.name
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          raise e
        end

        # Re-check after redraw.
        candidates(model).each do |inst, kind|
          pr = problems(inst, kind)
          report[:after] << "#{Finder.label(inst)}: #{pr.join(', ')}" unless pr.empty?
        end
        report
      end

      def self.message(r)
        if r[:fixed].empty?
          return "Checked #{r[:checked]} doors / drawer fronts - all correct. Removed #{r[:purged]} unused old STYLE_* definitions." if r[:purged].to_i > 0
          return "Checked #{r[:checked]} doors / drawer fronts - all already correct. No changes made."
        end
        lines = ["Repaired #{r[:fixed].size} of #{r[:checked]} doors / drawer fronts.",
                 "Old STYLE_* definitions removed: #{r[:purged]}",
                 "Components redrawn: #{r[:components].uniq.join(', ')}", '']
        lines += r[:fixed].first(25)
        lines << "... and #{r[:fixed].size - 25} more" if r[:fixed].size > 25
        unless r[:after].empty?
          lines += ['', 'Still not right after repair:'] + r[:after].first(15)
        end
        lines += ['', 'Notes:'] + r[:notes] unless r[:notes].to_a.empty?
        lines.join("\n")
      end
    end
  end
end
