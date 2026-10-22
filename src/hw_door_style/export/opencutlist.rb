module HarryWardrobes
  module DoorStyle
    # OpenCutList (lairdubois) set-up: Settings > Cut list > "Set up OpenCutList
    # for this model".
    #
    # OpenCutList keeps its settings in the "ladb_opencutlist" attribute dictionary
    # (format checked against OpenCutList 7.x, model/attributes/*_attributes.rb):
    #   material   type (0 unknown, 1 solid wood, 2 sheet good, 3 dimensional, 4 edge,
    #              5 hardware, 6 veneer), std_thicknesses "18 mm;25 mm",
    #              std_sizes "2800 mm x 2070 mm;2800 mm x 600 mm", grained true/false.
    #              Anything not written falls back to OpenCutList's own defaults.
    #   definition tags ["bought-in"], ignore_grain_direction ...
    #
    # What the plugin sets (only on materials already in the model, and only where
    # OpenCutList has nothing yet - unless "overwrite" is ticked):
    #   library colours   sheet good, Settings thicknesses (+ the 22mm panel thickness
    #                     for the 22mm Panels colour), Settings sheet sizes, grained when
    #                     the colour has a woodgrain texture
    #   drawer box finishes and the hinge / TIP-ON material   hardware (counted, not cut)
    #   door and drawer front parts   tag "bought-in" (filter it out of the cutting
    #                     diagrams in OpenCutList); new Shaker parts get it as they are made
    #
    # Grain: OpenCutList runs the grain along each part's longest side and never
    # rotates a grained part, so tall doors / panels come out vertical and wide drawer
    # fronts horizontal. (Locking to the component axes would turn doors sideways -
    # their X axis is the width - so the plugin doesn't.)
    module OpenCutList
      DICT_NAME = 'ladb_opencutlist'.freeze
      TYPES = { 0 => 'Unknown', 1 => 'Solid wood', 2 => 'Sheet good', 3 => 'Dimensional', 4 => 'Edge',
                5 => 'Hardware', 6 => 'Veneer' }.freeze
      SHEET = 2
      DIMENSIONAL = 3
      HARDWARE = 5

      def self.extension
        Sketchup.extensions.find { |e| e.name.to_s =~ /open\s*cut\s*list/i }
      end

      # --- settings ----------------------------------------------------------------

      def self.tag
        Settings.get['ocl_bought_in_tag'].to_s.strip.then { |t| t.empty? ? 'bought-in' : t }
      end

      def self.mm_s(v)
        "#{format('%g', v.to_f)} mm"
      end

      # "18 mm;25 mm"
      def self.thicknesses_s(list)
        list.map(&:to_f).uniq.sort.map { |t| mm_s(t) }.join(';')
      end

      # "2800 mm x 90 mm;2800 mm x 2070 mm" (narrowest first, as OpenCutList lists them)
      def self.sizes_s(list)
        list.map { |l, w| [l.to_f, w.to_f] }.uniq.sort_by { |l, w| [l, w] }.map { |l, w| "#{mm_s(l)} x #{mm_s(w)}" }.join(';')
      end

      # [[2800, 2070], ...] from Settings "ocl_sheet_sizes" ("2800x2070" strings or pairs).
      def self.sheet_sizes
        Array(Settings.get['ocl_sheet_sizes']).filter_map do |s|
          l, w = s.is_a?(Array) ? s : s.to_s.downcase.split('x')
          l.to_f.positive? && w.to_f.positive? ? [l.to_f, w.to_f] : nil
        end
      end

      # Every standard colour comes as 25 mm worktop as well as 18 mm board, whatever the
      # Settings list says (an older saved list was just 18).
      WORKTOP_MM = 25.0

      def self.thicknesses_for(colour_name)
        t = Array(Settings.get['ocl_thicknesses_mm']).map(&:to_f).select(&:positive?)
        t << WORKTOP_MM
        t << Settings.get['panel_22_mm'].to_f if colour_name == Colours.panel_default
        t.uniq
      end

      # "18 mm;25 mm" -> [18.0, 25.0]
      def self.mm_values(s)
        s.to_s.split(';').filter_map { |x| x[/\d+(?:[.,]\d+)?/]&.tr(',', '.')&.to_f }
      end

      # --- what the plugin would set ------------------------------------------------

      # { material name => { 'type' =>, 'std_thicknesses' =>, 'std_sizes' =>, 'grained' =>, 'why' => } }
      def self.desired
        out = {}
        Colours.library.each do |c|
          out[c['name']] = { 'type' => SHEET, 'std_thicknesses' => thicknesses_s(thicknesses_for(c['name'])),
                             'std_sizes' => sizes_s(sheet_sizes), 'grained' => c['texture'] ? true : false,
                             'why' => c['texture'] ? 'board colour (woodgrain)' : 'board colour' }
        end
        DrawerBox.library.each do |b|
          out[b['material'] || b['name']] = { 'type' => HARDWARE, 'why' => 'Interfit drawer box (bought-in)' }
        end
        out[Settings.get['hardware_material'].to_s] = { 'type' => HARDWARE, 'why' => 'hinges / TIP-ON' }
        # Timber and MDF are ordered as lengths (Settings > Cut list > Length materials).
        Array(Settings.get['ocl_length_materials']).each { |n| out[n.to_s] = { 'type' => DIMENSIONAL, 'why' => 'ordered as lengths (Timber / MDF)' } }
        out
      end

      def self.current(mat)
        d = mat.attribute_dictionary(DICT_NAME)
        d ? d.to_a.to_h : {}
      end

      # Compares ignoring order and spacing ("18mm;25 mm" == "25 mm;18 mm").
      def self.same_list?(a, b)
        norm = ->(s) { s.to_s.downcase.delete(' ').split(';').reject(&:empty?).sort }
        norm.call(a) == norm.call(b)
      end

      # :missing (OpenCutList has nothing), :same, or :different.
      def self.state(mat, want)
        cur = current(mat)
        return :missing if cur['type'].to_i.zero?
        return :different unless cur['type'].to_i == want['type']
        if want['type'] == SHEET
          return :different unless same_list?(cur['std_thicknesses'], want['std_thicknesses']) &&
                                   same_list?(cur['std_sizes'], want['std_sizes']) &&
                                   (cur['grained'] ? true : false) == want['grained']
        end
        :same
      end

      # One row per plugin-managed material that is in this model.
      def self.plan(model = Sketchup.active_model)
        desired.filter_map do |name, want|
          mat = model.materials[name] or next
          cur = current(mat)
          {
            'material' => name, 'why' => want['why'], 'state' => state(mat, want).to_s,
            'type' => TYPES[want['type']], 'current_type' => TYPES[cur['type'].to_i],
            'thickness' => want['std_thicknesses'] ? want['std_thicknesses'].tr(';', ', ') : '-',
            'grained' => want['type'] == SHEET ? (want['grained'] ? 'Yes' : 'No') : '-'
          }
        end
      end

      # --- doors and drawer fronts: bought-in ---------------------------------------

      # The parts OpenCutList lists for each door / drawer front: the slab inside the
      # wrapper, or the wrapper itself when it has no slab (not converted yet).
      def self.door_parts(model)
        Finder.all_targets(model, [:door, :ext_drawer, :int_drawer]).map do |inst, _kind|
          slab = inst.definition.entities.grep(Sketchup::ComponentInstance).find { |c| c.get_attribute(DICT, 'role') == 'style' }
          (slab || inst).definition
        end.uniq
      end

      def self.tags_of(defn)
        t = defn.get_attribute(DICT_NAME, 'tags', defn.get_attribute(DICT_NAME, 'labels', []))
        t = t.split(';') if t.is_a?(String)
        Array(t).map { |x| x.to_s.strip }.reject(&:empty?)
      end

      def self.bought_in?(defn)
        tags_of(defn).include?(tag)
      end

      # Adds the tag (keeps any tags already there). True if it changed.
      def self.mark_bought_in(defn)
        return false if bought_in?(defn)
        defn.set_attribute(DICT_NAME, 'tags', (tags_of(defn) + [tag]).uniq.sort)
        true
      end

      # Used by Converter when it makes a new door / drawer front part.
      def self.mark_new_part(defn)
        mark_bought_in(defn) if Settings.get['ocl_doors_bought_in']
      end

      # --- set up -------------------------------------------------------------------

      # Writes the settings. Call inside an undo step (Ops.run). overwrite: also
      # replace OpenCutList settings that differ from the plugin's.
      # Returns { set: [names], kept: [names], same: n, tagged: n }.
      def self.setup!(model, overwrite: false)
        rep = { set: [], kept: [], same: 0, tagged: 0 }
        desired.each do |name, want|
          mat = model.materials[name] or next
          case state(mat, want)
          when :same then rep[:same] += 1; next
          when :different
            next rep[:kept] << name unless overwrite
          end
          mat.set_attribute(DICT_NAME, 'type', want['type'])
          if want['type'] == SHEET
            mat.set_attribute(DICT_NAME, 'std_thicknesses', want['std_thicknesses'])
            mat.set_attribute(DICT_NAME, 'std_sizes', want['std_sizes'])
            mat.set_attribute(DICT_NAME, 'grained', want['grained'])
          end
          rep[:set] << name
        end
        if Settings.get['ocl_doors_bought_in']
          door_parts(model).each { |d| rep[:tagged] += 1 if mark_bought_in(d) }
        end
        rep
      end

      # Every plugin material in the model that OpenCutList knows nothing about yet gets the
      # plugin's settings (a different setting of yours is left alone). Returns the names set.
      # Called by the Colours window and the Workshop, so a known colour is always ready.
      def self.ensure!(model)
        set = []
        desired.each do |name, want|
          mat = model.materials[name] or next
          st = state(mat, want)
          if st == :different && want['type'] == SHEET && current(mat)['type'].to_i == SHEET
            # a standard thickness missing from its list (set before it was standard): added,
            # anything else on the list kept
            have = mm_values(current(mat)['std_thicknesses'])
            add = mm_values(want['std_thicknesses']).reject { |t| have.any? { |h| (h - t).abs < 0.01 } }
            unless add.empty?
              mat.set_attribute(DICT_NAME, 'std_thicknesses', thicknesses_s(have + add))
              set << name
            end
            next
          end
          next unless st == :missing
          mat.set_attribute(DICT_NAME, 'type', want['type'])
          if want['type'] == SHEET
            mat.set_attribute(DICT_NAME, 'std_thicknesses', want['std_thicknesses'])
            mat.set_attribute(DICT_NAME, 'std_sizes', want['std_sizes'])
            mat.set_attribute(DICT_NAME, 'grained', want['grained'])
          end
          set << name
        end
        set
      end

      # When a job file is opened (or a new one started): its plugin colours are set up for
      # OpenCutList straight away, so the Workshop is ready without changing a colour first.
      # One transparent step, only when something was missing.
      def self.ensure_on_open(model)
        return if model.nil? || !model.valid?
        missing = desired.any? { |name, want| (mat = model.materials[name]) && state(mat, want) == :missing }
        return unless missing
        Ops.run(model, 'OpenCutList settings for the plugin colours', transparent: true) { ensure!(model) }
      rescue StandardError => e
        Log.error('opencutlist on open', e)
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); UI.start_timer(2.0, false) { OpenCutList.ensure_on_open(model) }; end
        def onOpenModel(model); UI.start_timer(2.0, false) { OpenCutList.ensure_on_open(model) }; end
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
        ensure_on_open(Sketchup.active_model)
      end

      # --- checks for the Cut list section ----------------------------------------------

      def self.warnings(model = Sketchup.active_model)
        w = []
        unless Pencil.on?(model) || Runouts.units(model.entities).empty?
          w << 'Scribes are off (every runout 0): press the pencil before running the cut list, so parts are full size.'
        end
        unless Colours.door_colour_chosen?(model)
          w << 'No colours chosen for this job yet: parts without a material are grouped as "no material" in OpenCutList.'
        end
        if Settings.get['ocl_doors_bought_in']
          untagged = door_parts(model).count { |d| !bought_in?(d) }
          w << "#{untagged} door / drawer front part(s) are not tagged \"#{tag}\" yet - press Set up OpenCutList." if untagged.positive?
        end
        missing = plan(model).count { |r| r['state'] == 'missing' }
        w << "#{missing} material(s) have no OpenCutList settings yet - press Set up OpenCutList." if missing.positive?
        w
      rescue StandardError => e
        Log.error('cut list checks', e)
        []
      end

      # Everything the Settings > Cut list section shows.
      def self.status(model = Sketchup.active_model)
        ext = extension
        set = model.materials.count { |m| !m.get_attribute(DICT_NAME, 'type').to_i.zero? }
        parts = door_parts(model)
        { 'installed' => !ext.nil?, 'loaded' => ext ? ext.loaded? : false, 'version' => ext&.version.to_s,
          'materials_with_ocl' => set, 'materials' => model.materials.count, 'plan' => plan(model),
          'doors' => parts.size, 'doors_tagged' => parts.count { |d| bought_in?(d) }, 'tag' => tag,
          'warnings' => warnings(model) }
      rescue StandardError => e
        { 'installed' => false, 'error' => e.message, 'plan' => [], 'warnings' => [] }
      end
    end
  end
end
