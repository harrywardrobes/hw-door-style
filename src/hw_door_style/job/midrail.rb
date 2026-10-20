module HarryWardrobes
  module DoorStyle
    # Mid-rail line: units whose fronts line up with the doors' mid-rail carry the door
    # style's mid-rail centre and width as options (a VIEW in Component Options):
    #
    #   WARDROBE_STABLE  b06_midrail_centre / b07_midrail_width
    #                    stable panel = centre - width / 2 - margin
    #   LINEN_PRESS      h07_midrail_centre / h08_midrail_width
    #                    drawer fronts = (centre - width / 2 - margin - gaps) / number of fronts
    #
    # The values come from the job's door style (Settings > Door styles, e.g. Shaker 815 / 100),
    # or the first style that has a mid-rail when the job's doors are flat. They are set when a
    # unit is placed from the + window and when the Door style window is applied.
    module Midrail
      KEY_RE = /\A[a-z]\d\d_midrail_(centre|width)\z/.freeze

      # { 'centre' => mm, 'width' => mm } or nil.
      def self.values(style = nil)
        p = style && Styles.profile(style)
        p = Styles.profiles.find { |x| x['midrail_centre_mm'].to_f.positive? } unless p && p['midrail_centre_mm'].to_f.positive?
        p ? { 'centre' => p['midrail_centre_mm'].to_f, 'width' => p['midrail_width_mm'].to_f } : nil
      end

      def self.job_values(model)
        values(DoorStyleWindow.job_styles(model)['door'])
      rescue StandardError
        values
      end

      # { 'centre' => key, 'width' => key } or nil.
      def self.keys(inst)
        return nil unless inst.is_a?(Sketchup::ComponentInstance)
        d = inst.definition.attribute_dictionary(DC::DICT_NAME) or return nil
        found = d.keys.filter_map { |k| (m = k.match(KEY_RE)) && [m[1], k] }.to_h
        found.size == 2 ? found : nil
      end

      def self.has?(inst) = !keys(inst).nil?

      # Sets the unit's mid-rail options (mm). True if anything changed; the caller redraws.
      def self.set(inst, vals)
        ks = keys(inst) or return false
        return false unless vals
        changed = false
        ks.each do |what, k|
          cur = DC.read(inst, k).to_f * 25.4
          next if (cur - vals[what].to_f).abs < 0.5
          inst.set_attribute(DC::DICT_NAME, k, vals[what].to_f / 25.4)
          changed = true
        end
        changed
      end

      def self.units(entities)
        found = []
        walk = lambda do |ents, depth|
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            if has?(e)
              found << e
            elsif depth < 3
              walk.call(e.respond_to?(:definition) ? e.definition.entities : e.entities, depth + 1)
            end
          end
        end
        walk.call(entities, 0)
        found
      end

      # Every unit in the model to the given door style's mid-rail (inside the caller's
      # operation): changed units are redrawn and their doors / fronts restyled at the new
      # size. Returns the number of units changed.
      def self.sync(model, style)
        vals = values(style)
        changed = units(model.entities).select { |u| set(u, vals) }
        changed.each do |u|
          Drawers.close(u.definition.entities)
          DC.redraw(u)
        end
        pairs = Finder.targets(changed, %i[door ext_drawer int_drawer])
        Converter.rebuild(model, pairs, nil, override: false, finish: false) unless pairs.empty?
        changed.size
      end
    end
  end
end
