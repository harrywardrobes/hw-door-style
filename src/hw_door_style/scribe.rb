require 'json'

module HarryWardrobes
  module DoorStyle
    # Scribe / runout for every unit in the model (pencil button).
    #
    #   Pencil pressed  = scribes ON  : every unit gets the job's floor / ceiling /
    #                                   left / right / back runout.
    #   Pencil released = scribes OFF : every runout 0, so units line up and move easily.
    #
    # The plugin only sets the values. Each component's own switches decide what
    # is used: WALL_LEFT / WALL_RIGHT / WALL_BACK, topped off (no ceiling runout);
    # the floor runout always applies.
    #
    # Values are DC string attributes in inches (e.g. "0.984251968503937" = 25mm),
    # with a dropdown of Settings "runout_values_mm" plus 0.
    module Scribe
      DCD = 'dynamic_attributes'.freeze
      SIDES = [
        ['floor',   'runout_floor',     'Runout - floor (mm)'],
        ['ceiling', 'runout_ceiling',   'Runout - ceiling (mm)'],
        ['left',    'runout_l',         'Runout - left (mm)'],
        ['right',   'runout_r',         'Runout - right (mm)'],
        ['back',    'runout_back_wall', 'Runout - back wall (mm)']
      ].freeze
      KEYS = SIDES.to_h { |s, k, _| [s, k] }.freeze
      OLD_KEYS = { 'scribe_l' => 'runout_l', 'scribe_r' => 'runout_r' }.freeze
      TOL = 0.3 # mm

      # --- settings / job state -------------------------------------------

      def self.values_list
        Array(Settings.get['runout_values_mm']).map(&:to_f).select(&:positive?).uniq.sort
      end

      def self.defaults
        d = Settings.get['runout_defaults_mm'] || {}
        SIDES.to_h { |s, _, _| [s, (d[s] || 25).to_f] }
      end

      def self.on?(model = Sketchup.active_model)
        model.get_attribute(DICT, 'scribe_on', true) ? true : false
      end

      # Last values used on this job (mm), else the Settings defaults.
      def self.job_values(model = Sketchup.active_model)
        saved = JSON.parse(model.get_attribute(DICT, 'scribe_values', '{}')) rescue {}
        defaults.merge(saved.transform_values(&:to_f).slice(*KEYS.keys))
      end

      # What every unit should have right now (all 0 when scribes are off).
      def self.expected(model = Sketchup.active_model)
        on?(model) ? job_values(model) : SIDES.to_h { |s, _, _| [s, 0.0] }
      end

      # --- units --------------------------------------------------------------

      # key may be a base name ("runout_floor"); the library may store it with
      # a section prefix ("j01_runout_floor").
      def self.real_key(inst, key)
        DC.key(inst, key) || key
      end

      def self.read(inst, key)
        k = real_key(inst, key)
        v = inst.get_attribute(DCD, k)
        v = inst.definition.get_attribute(DCD, k) if v.nil?
        v
      end

      def self.unit?(inst)
        inst.is_a?(Sketchup::ComponentInstance) && KEYS.values.any? { |k| !read(inst, k).nil? }
      end

      # Outermost instances that carry runout attributes (nested parts are driven
      # by their unit through parent! formulas, so they are not touched).
      def self.units(entities)
        found = []
        walk = lambda do |ents|
          ents.each do |e|
            if e.is_a?(Sketchup::ComponentInstance)
              unit?(e) ? (found << e) : walk.call(e.definition.entities)
            elsif e.is_a?(Sketchup::Group)
              walk.call(e.definition.entities)
            end
          end
        end
        walk.call(entities)
        found
      end

      def self.mm_of(inst, side)
        v = read(inst, KEYS[side])
        v.nil? ? nil : (v.to_f * 25.4).round(1)
      end

      def self.inch_s(mm)
        (mm.to_f / 25.4).to_s
      end

      # Sides of this unit that differ from what the job expects ([] = standard).
      def self.differences(inst, model = Sketchup.active_model)
        exp = expected(model)
        out = SIDES.filter_map do |s, _, _|
          v = mm_of(inst, s)
          next if v.nil? || (v - exp[s]).abs <= TOL
          "#{s} #{v.round}mm (job #{exp[s].round})"
        end
        want = target_height_mm(inst, ceiling_mm(model))
        h = height_mm(inst)
        out << "height #{h.round}mm (ceiling #{want.round})" if want && h && (h - want).abs > 1
        out
      end

      # --- ceiling height ---------------------------------------------------
      # Every unit with "Up to ceiling" = TRUE (missing = TRUE) is built to the
      # job's ceiling height. Runouts add on top. Scribes off never changes it.
      HEIGHT_KEYS = %w[frame_height_ceiling frame_height ceiling_height size_height height].freeze

      def self.ceiling_mm(model = Sketchup.active_model)
        model.get_attribute(DICT, 'ceiling_mm', 0).to_f
      end

      def self.height_key(inst)
        HEIGHT_KEYS.each do |b|
          k = DC.key(inst, b)
          return k if k
        end
        nil
      end

      # Only units that have the switch (so drawers etc. are never touched).
      def self.up_to_ceiling?(inst)
        v = read(inst, 'up_to_ceiling')
        !v.nil? && v.to_s.upcase != 'FALSE'
      end

      def self.height_mm(inst)
        k = height_key(inst) or return nil
        v = read(inst, k)
        v.nil? || v.to_s.strip.empty? ? nil : (v.to_f * 25.4).round(1)
      end

      # Target height for this unit (nil = leave it). BRIDGE_FRAME sits on something:
      # its height is the ceiling minus "Height below bridge".
      def self.target_height_mm(inst, ceiling)
        return nil unless ceiling.to_f.positive? && height_key(inst) && up_to_ceiling?(inst)
        below = read(inst, 'height_below')
        return ceiling.to_f unless below
        b = below.to_f * 25.4
        b.positive? ? ceiling.to_f - b : nil
      end

      # Sets the height. Heights worked out from the stretched size (CURRENT("LenZ"))
      # are changed by stretching in Z about the unit's origin, like the Scale tool.
      def self.set_height(inst, mm)
        k = height_key(inst) or return false
        cur = height_mm(inst)
        return false if cur && (cur - mm).abs < 0.5
        f = [inst.get_attribute(DCD, "_#{k}_formula"), inst.definition.get_attribute(DCD, "_#{k}_formula")].compact.join
        if f =~ /CURRENT/i && cur.to_f.positive?
          t = inst.transformation
          inst.transformation = Geom::Transformation.scaling(t.origin, 1, 1, mm / cur) * t
        else
          old = read(inst, k)
          inst.set_attribute(DCD, k, old.is_a?(String) ? (mm / 25.4).to_s : mm / 25.4)
        end
        true
      end

      # Sets the height and redraws, correcting up to 3 times (a stretched unit's
      # size can differ slightly from its height option). Returns true if changed.
      def self.fit_height(inst, mm)
        changed = false
        3.times do
          break unless set_height(inst, mm)
          changed = true
          LibraryExport.close_drawers(inst.definition.entities)
          DC.redraw(inst)
        end
        changed
      end

      # --- standardising the components ---------------------------------

      # "scribe_l" / "_scribe_l_label" / "_inst__scribe_l_formula" -> runout_l versions.
      def self.rename_key(k)
        OLD_KEYS.each do |old, new|
          nk = k.sub(/\A(_?(?:inst__)?)#{old}(?=_|\z)/, "\\1#{new}")
          return nk unless nk == k
        end
        k
      end

      # SCRIBE_L / parent!SCRIBE_R -> RUNOUT_L / parent!RUNOUT_R (ZZ_SCRIBE_L is left alone).
      def self.rename_formula(v)
        v.gsub(/\bSCRIBE_([LR])\b/i) { "RUNOUT_#{Regexp.last_match(1).upcase}" }
      end

      def self.options_string
        (['0mm=0.0'] + values_list.map { |v| "#{v.round}mm=#{inch_s(v)}" }).map { |o| "&#{o}" }.join + '&'
      end

      # Renames SCRIBE_L/R -> RUNOUT_L/R (keys and every formula that mentions
      # them), and gives every runout dropdown the Settings list.
      # Call inside an operation. Returns a report hash.
      def self.standardise(model)
        rep = { renamed: [], formulas: 0, options: 0 }
        objs = model.definitions.reject(&:image?).flat_map { |d| [d] + d.instances }
        objs.each do |o|
          dd = o.attribute_dictionary(DCD) or next
          # 1. keys
          dd.keys.each do |k|
            nk = rename_key(k)
            unless nk == k
              val = dd[k]
              val = val.sub(/\ASCRIBE_([LR])\z/i) { "RUNOUT_#{Regexp.last_match(1).upcase}" } if k.end_with?('_label') && val.is_a?(String)
              dd[nk] = val if dd[nk].nil?
              dd.delete_key(k)
              rep[:renamed] |= [o.respond_to?(:definition) ? o.definition.name : o.name]
            end
          end
          %w[_scribe_1_label_formlabel _scribe_1_label_formula _scribe_1_label_label _scribe_1_label_units scribe_1_label].each { |k| dd.delete_key(k) if dd[k] }
          # 2. formulas
          dd.keys.each do |k|
            v = dd[k]
            next unless k.end_with?('_formula') && v.is_a?(String) && v =~ /\bSCRIBE_[LR]\b/i
            dd[k] = rename_formula(v)
            rep[:formulas] += 1
          end
          # 3. dropdowns + labels
          SIDES.each do |_s, base, label|
            key = DC.key_in(dd, base) || base
            next if dd[key].nil? && dd["_#{key}_label"].nil?
            dd["_#{key}_options"] = options_string
            dd["_#{key}_formlabel"] = label
            dd["_#{key}_units"] = 'STRING'
            rep[:options] += 1
          end
        end
        rep
      end

      def self.needs_standardising?(model)
        model.definitions.any? do |d|
          dd = d.attribute_dictionary(DCD) or next false
          fk = DC.key_in(dd, 'runout_floor')
          dd.keys.any? { |k| k =~ /\A_?scribe_[lr](_|\z)/ } ||
            (fk && dd["_#{fk}_options"] != options_string)
        end
      end

      # --- applying values ----------------------------------------------------

      # Sets the values (mm by side) on one unit. Returns true if anything changed.
      def self.set_values(inst, values)
        changed = false
        values.each do |side, mm|
          key = KEYS[side.to_s] or next
          next if read(inst, key).nil?
          cur = read(inst, key).to_f * 25.4
          rk = real_key(inst, key)
          next if (cur - mm.to_f).abs <= 0.05 && !inst.get_attribute(DCD, rk).nil?
          inst.set_attribute(DCD, rk, inch_s(mm))
          changed = true
        end
        changed
      end

      # Applies values to units with a progress window, one undo step.
      # values: { side => mm } or a lambda(inst) -> values.
      # before: optional lambda run inside the same undo step (job state changes).
      def self.run(model, units, values, title, done_msg, before: nil, ceiling: nil)
        return UI.messagebox('No units with runout settings found.') if units.empty?
        dlg = progress_dialog(title)
        queue = units.dup
        total = queue.size
        n = 0
        errors = []
        first = true
        tick = lambda do
          inst = queue.shift
          if inst.nil?
            dlg.execute_script("progress(#{total}, #{total}, 'Done')")
            UI.start_timer(0.4, false) { dlg.close }
            msg = done_msg.to_s
            msg += "\n\nCould not update:\n" + errors.join("\n") unless errors.empty?
            Sketchup.status_text = msg.lines.first.to_s
            UI.messagebox(msg) unless errors.empty?
            next
          end
          dlg.execute_script("progress(#{n}, #{total}, #{JSON.generate("Updating #{Finder.label(inst)}...")})")
          UI.start_timer(0.02, false) do
            # First unit opens the undo step; the rest are merged into it (transparent).
            model.start_operation(title, true, false, !first)
            if first
              before&.call
              first = false
            end
            begin
              v = values.respond_to?(:call) ? values.call(inst) : values
              changed = v ? set_values(inst, v) : false
              want = ceiling ? target_height_mm(inst, ceiling) : nil
              # fit_height redraws itself; otherwise redraw once for the runouts.
              if want && fit_height(inst, want)
                changed = false
              end
              if changed
                LibraryExport.close_drawers(inst.definition.entities)
                DC.redraw(inst)
              end
            rescue StandardError => e
              errors << "#{Finder.label(inst)}: #{e.message}"
              puts "HW Door Style scribe: #{Finder.label(inst)}: #{e.class}: #{e.message}\n  #{e.backtrace.first(5).join("\n  ")}"
            end
            model.commit_operation
            n += 1
            tick.call
          end
        end
        tick.call
      end

      def self.progress_dialog(title)
        d = UI::HtmlDialog.new(dialog_title: title, preferences_key: 'hw_scribe_progress', width: 420, height: 150,
                               resizable: false, scrollable: false, style: UI::HtmlDialog::STYLE_UTILITY)
        d.set_html(File.read(File.join(PATH, 'html', 'progress.html')))
        d.show
        d
      end

      # Pencil: ON -> all 0 straight away. OFF -> window with the dropdowns.
      def self.toggle(model = Sketchup.active_model)
        return unless ready?(model)
        if on?(model)
          run(model, units(model.entities), SIDES.to_h { |s, _, _| [s, 0.0] }, 'Scribes off (all runouts 0)',
              'Scribes off: every runout set to 0.', before: -> { model.set_attribute(DICT, 'scribe_on', false) })
        else
          show(model, nil)
        end
      end

      # Standardise the components first if they still use SCRIBE_L/R or old dropdowns.
      def self.ready?(model)
        return true unless needs_standardising?(model)
        msg = "This model's components need a one-off update first:\n\n" \
              "- SCRIBE_L / SCRIBE_R renamed RUNOUT_L / RUNOUT_R (formulas updated)\n" \
              "- runout dropdowns set to 0 / #{values_list.map(&:round).join(' / ')} mm\n\nDo it now? (one undo step)"
        return false unless UI.messagebox(msg, MB_YESNO) == IDYES
        model.start_operation('Standardise runouts', true)
        standardise(model)
        model.commit_operation
        true
      end

      # Window: whole model (targets nil) or the selected units.
      def self.show(model, targets)
        @dlg&.close
        sel = targets && !targets.empty?
        cur = sel ? SIDES.to_h { |s, _, _| [s, mm_of(targets.first, s) || job_values(model)[s]] } : job_values(model)
        data = {
          'title' => sel ? "Runouts - #{targets.size == 1 ? Finder.label(targets.first) : "#{targets.size} selected units"}" : 'Scribes on - runouts for every unit',
          'selection' => sel ? true : false,
          'sides' => SIDES.map { |s, _, l| [s, l.sub(/\ARunout - /, '').sub(' (mm)', '')] },
          'values' => [0.0] + values_list, 'current' => cur, 'job' => job_values(model),
          'ceiling' => sel ? nil : ceiling_mm(model)
        }
        @dlg = dlg = UI::HtmlDialog.new(dialog_title: 'HW - Scribe / runout', preferences_key: 'hw_scribe',
                                        width: 380, height: 360, resizable: false, scrollable: false,
                                        style: UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(File.read(File.join(PATH, 'html', 'scribe.html')).sub('/*DATA*/null', JSON.generate(data)))
        dlg.add_action_callback('cancel') { |_c| dlg.close }
        dlg.add_action_callback('apply') do |_c, json|
          raw = JSON.parse(json)
          ceil = raw['ceiling'].to_f
          v = raw.transform_values(&:to_f).slice(*KEYS.keys)
          dlg.close
          if sel
            run(model, targets, v, 'Runouts (selected)', "Runouts updated on #{targets.size} unit(s).")
          else
            run(model, units(model.entities), v, 'Scribes on',
                "Scribes on: #{SIDES.map { |s, _, _| "#{s} #{v[s].round}" }.join(', ')} mm. Ceiling #{ceil.round} mm.",
                ceiling: ceil,
                before: lambda {
                  model.set_attribute(DICT, 'scribe_on', true)
                  model.set_attribute(DICT, 'scribe_values', JSON.generate(v))
                  model.set_attribute(DICT, 'ceiling_mm', ceil)
                })
          end
        end
        dlg.show
      end

      # Ceiling height button: any time, scribes on or off. Runouts untouched.
      def self.show_ceiling(model = Sketchup.active_model)
        @cdlg&.close
        data = { 'ceiling' => ceiling_mm(model), 'count' => units(model.entities).count { |u| target_height_mm(u, 1.0) } }
        @cdlg = dlg = UI::HtmlDialog.new(dialog_title: 'HW - Ceiling height', preferences_key: 'hw_ceiling',
                                         width: 360, height: 230, resizable: false, scrollable: false,
                                         style: UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(File.read(File.join(PATH, 'html', 'ceiling.html')).sub('/*DATA*/null', JSON.generate(data)))
        dlg.add_action_callback('cancel') { |_c| dlg.close }
        dlg.add_action_callback('apply') do |_c, mm|
          ceil = mm.to_f
          dlg.close
          next unless ceil.positive?
          run(model, units(model.entities), nil, 'Ceiling height', "Ceiling height #{ceil.round} mm applied to every 'Up to ceiling' unit.",
              ceiling: ceil, before: -> { model.set_attribute(DICT, 'ceiling_mm', ceil) })
        end
        dlg.show
      end

      # Units in the current selection (or containing it).
      def self.selected_units(model = Sketchup.active_model)
        model.selection.grep(Sketchup::ComponentInstance).flat_map { |i| unit?(i) ? [i] : units(i.definition.entities) }.uniq
      end

      # Every unit that differs from the job values: [[label, [differences]]].
      def self.report(model = Sketchup.active_model)
        units(model.entities).filter_map do |u|
          d = differences(u, model)
          [Finder.label(u), d] unless d.empty?
        end
      end
    end
  end
end
