require 'json'

module HarryWardrobes
  module DoorStyle
    # Depth: every unit's "Depth (mm)" option - back wall to the back of the facing (the
    # finished depth adds the facing / door). Library units from V29 have their axis at the
    # back-left corner on the floor, so changing Depth moves the front, never the back.
    #
    #   Settings  depth_default_mm      standard (580)
    #             depth_short_mm        bridge units, worktops, box ends (500)
    #             depth_short_components which components use the short depth
    #             depth_by_component    own depth for a component (box shelves, bookcase...)
    #   Job       Scribe / runout window: the job's standard and short depth, set on every unit
    #   Unit      right-click > HW Door Style > Depth, or Component Options
    module Depth
      KEY_RE = /\A[a-z]\d\d_(?:wall_)?depth\z/.freeze

      def self.key(inst)
        return nil unless inst.respond_to?(:definition)
        d = inst.definition.attribute_dictionary(DC::DICT_NAME) or return nil
        d.keys.select { |k| k =~ KEY_RE }.find { |k| d["_#{k}_access"].to_s.upcase == 'TEXTBOX' }
      end

      def self.has?(inst) = !key(inst).nil?

      def self.mm(inst)
        k = key(inst) or return nil
        v = DC.read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * Ceiling.mm_per(inst, k)).round
      end

      def self.base(inst) = inst.definition.name.sub(/#\d+\z/, '').strip.upcase

      def self.short?(inst)
        Settings.names('depth_short_components').any? { |n| base(inst).start_with?(n) }
      end

      # The depth a unit should have on this job (nil = leave it): its own setting, else the
      # job's short / standard depth (Scribe window), else Settings.
      def self.target(inst, model = inst.model)
        own = (Settings.get['depth_by_component'] || {}).find { |n, _| base(inst).start_with?(n.to_s.upcase) }
        return own[1].to_f if own && own[1].to_f.positive?
        job = job_values(model)
        short?(inst) ? job['short'] : job['standard']
      end

      def self.job_values(model = Sketchup.active_model)
        saved = JSON.parse(model.get_attribute(DICT, 'depth_job', '{}')) rescue {}
        { 'standard' => (saved['standard'] || Settings.get['depth_default_mm'] || 580).to_f,
          'short' => (saved['short'] || Settings.get['depth_short_mm'] || 500).to_f }
      end

      # Sets the unit's Depth (mm). True if it changed; the caller redraws.
      def self.set(inst, value)
        k = key(inst) or return false
        cur = mm(inst)
        return false if cur && (cur - value.to_f).abs < 0.5
        inst.set_attribute(DC::DICT_NAME, k, (value.to_f / Ceiling.mm_per(inst, k)).to_s)
        true
      end

      # Every unit with a Depth option (outermost first; units inside units are left).
      def self.units(entities)
        found = []
        walk = lambda do |ents, depth|
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            if e.is_a?(Sketchup::ComponentInstance) && has?(e)
              found << e
            elsif depth < 3
              walk.call(e.respond_to?(:definition) ? e.definition.entities : e.entities, depth + 1)
            end
          end
        end
        walk.call(entities, 0)
        found
      end

      def self.selected(model = Sketchup.active_model)
        model.selection.grep(Sketchup::ComponentInstance).flat_map { |i| has?(i) ? [i] : units(i.definition.entities) }.uniq
      end

      # Sets Depth on units, one undo step with a progress window. value: mm, or :job (each
      # unit's job depth).
      def self.apply(model, list, value, title)
        return UI.messagebox('No units with a Depth option selected.') if list.empty?
        Batch.run(model, list, title, done: "#{title}: done.") do |u|
          want = value == :job ? target(u, model) : value
          next unless want && set(u, want)
          Drawers.close(u.definition.entities)
          DC.redraw(u)
          Doors.refit(model, u)
        end
      end

      # Right-click > Depth.
      def self.menu(sub, list)
        model = Sketchup.active_model
        job = job_values(model)
        cur = list.map { |u| mm(u) }.uniq
        d = sub.add_submenu(list.size == 1 ? "Depth (#{cur.first || '?'} mm)" : "Depth (#{list.size} units)")
        d.add_item("Standard - #{job['standard'].round} mm") { apply(model, list, job['standard'], "Depth #{job['standard'].round} mm") }
        d.add_item("Bridge / worktop - #{job['short'].round} mm") { apply(model, list, job['short'], "Depth #{job['short'].round} mm") }
        d.add_item('Job depth for each (as the + window sets them)') { apply(model, list, :job, 'Job depths') }
        d.add_item('Other...') do
          r = UI.inputbox(['Depth (mm) - back wall to the back of the facing'], [(cur.first || job['standard']).to_s], 'Depth')
          v = r && r.first.to_f
          apply(model, list, v, "Depth #{v.round} mm") if v&.positive?
        end
      end
    end
  end
end
