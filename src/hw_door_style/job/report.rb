require 'json'

module HarryWardrobes
  module DoorStyle
    # On-screen summary of every door / drawer front, with CSV export and print-to-PDF.
    module Report
      HEADERS = ['#', 'Unit', 'Item', 'Kind', 'Width mm', 'Height mm', 'Style', 'Mid-rail',
                 'Hinge type', 'Hinges', 'TIP-ON', 'Handles', 'Notes'].freeze

      def self.path_label(path)
        return '(model)' if path.empty?
        path.map do |p|
          n = p.respond_to?(:definition) ? Finder.label(p) : p.name
          p.name.to_s.empty? ? n : "#{n} (#{p.name})"
        end.join(' > ')
      end

      def self.rows(model = Sketchup.active_model)
        rows = []
        pto = Settings.pto?(Settings.job_hinge_type(model))
        rules = Settings.job_handles(model)
        Finder.each_occurrence(model.entities) do |inst, kind, path|
          d = inst.definition
          w, _t, h = Finder.real_size(inst)
          kids = d.entities.grep(Sketchup::ComponentInstance)
          hinges = kids.select { |e| e.get_attribute(DICT, 'role') == 'hinge' }
          tips   = kids.count  { |e| e.get_attribute(DICT, 'role') == 'tip_on' }
          style  = d.get_attribute(DICT, 'style')
          notes  = []
          notes << d.get_attribute(DICT, 'note').to_s
          notes << 'Not processed yet' if style.nil? && kind != :int_drawer
          if style
            pr = Repair.problems(inst, kind)
            notes << "Needs Repair / re-run: #{pr.join(', ')}" unless pr.empty?
          end
          rows << {
            'unit' => path_label(path), 'item' => Finder.label(inst),
            'kind' => Finder::KINDS[kind], 'width' => Finder.mm_s(w), 'height' => Finder.mm_s(h),
            'style' => Styles.label(style || 'flat'),
            'midrail' => d.get_attribute(DICT, 'midrail') ? 'Yes' : '',
            'hinge_type' => hinges.empty? ? '' : Settings::HINGE_TYPES.fetch(hinges.first.get_attribute(DICT, 'type').to_s, hinges.first.get_attribute(DICT, 'type').to_s),
            'hinges' => hinges.size, 'tip_on' => tips,
            'handles' => Settings.handle_count(kind, w, pto, rules: rules,
                                                handleless: Styles.handleless?(d.get_attribute(DICT, 'requested_style') || style || 'flat')),
            'notes' => notes.reject(&:empty?).join('; ')
          }
        end
        rows.each_with_index { |r, i| r['n'] = i + 1 }
        rows
      end

      def self.totals(rows)
        t = { 'by_style' => Hash.new(0), 'hinges' => Hash.new(0), 'tip_on' => 0, 'handles' => 0, 'items' => rows.size }
        rows.each do |r|
          t['by_style']["#{r['kind']} - #{r['style']}"] += 1
          t['hinges'][r['hinge_type']] += r['hinges'] if r['hinges'] > 0
          t['tip_on'] += r['tip_on']
          t['handles'] += r['handles'].to_i
        end
        t
      end

      def self.csv(rows)
        q = ->(v) { s = v.to_s; s =~ /[",\n]/ ? "\"#{s.gsub('"', '""')}\"" : s }
        lines = [HEADERS.map(&q).join(',')]
        rows.each do |r|
          lines << [r['n'], r['unit'], r['item'], r['kind'], r['width'], r['height'], r['style'],
                    r['midrail'], r['hinge_type'], r['hinges'], r['tip_on'], r['handles'], r['notes']].map(&q).join(',')
        end
        lines.join("\r\n")
      end

      # --- export: DOOR_ORDER_v<N>_<file name>.csv + .pdf next to the .skp ---

      def self.safe_name(s)
        s.to_s.gsub(/[<>:"\/\\|?*\x00-\x1F]/, '_').strip
      end

      def self.order_stem(version, base)
        "DOOR_ORDER_v#{version}_#{safe_name(base)}"
      end

      # Next version = highest found in the folder or recorded in the model, + 1.
      def self.next_version(dir, base, recorded = 0)
        pattern = /\ADOOR_ORDER_v(\d+)_#{Regexp.escape(safe_name(base))}\.(csv|pdf)\z/i
        found = Dir.exist?(dir) ? Dir.children(dir).map { |f| f[pattern, 1].to_i }.max.to_i : 0
        [found, recorded.to_i].max + 1
      end

      def self.export_order(model = Sketchup.active_model)
        unless Pencil.on?(model) || Runouts.units(model.entities).empty?
          return nil unless UI.messagebox("Scribes are OFF - every runout is 0, so sizes may be wrong.\n\nExport the door order anyway?", MB_YESNO) == IDYES
        end
        if model.path.to_s.empty?
          UI.messagebox('Save the SketchUp file first - the door order is saved next to it and named after it.')
          return nil
        end
        dir  = File.dirname(model.path)
        base = File.basename(model.path, '.skp')
        v    = next_version(dir, base, model.get_attribute(DICT, 'export_version', 0))
        stem = File.join(dir, order_stem(v, base))
        data = payload(model).merge('export_version' => v)

        File.write("#{stem}.csv", "﻿" + csv(data['rows']), mode: 'w:UTF-8')
        Pdf.write("#{stem}.pdf", data)

        Ops.run(model, 'Record door order export') { model.set_attribute(DICT, 'export_version', v) }

        UI.messagebox("Door order v#{v} saved in:\n#{dir}\n\n#{File.basename(stem)}.csv\n#{File.basename(stem)}.pdf")
        v
      rescue StandardError => e
        UI.messagebox("Export failed: #{e.message}\n\nIf the file is open in Excel or a PDF viewer, close it and try again.")
        nil
      end

      def self.payload(model = Sketchup.active_model)
        r = rows(model)
        {
          'job' => File.basename(model.path.to_s, '.skp'),
          'hinge_type' => Settings::HINGE_TYPES[Settings.job_hinge_type(model)],
          'date' => Time.now.strftime('%d/%m/%Y %H:%M'),
          'version' => VERSION,
          'last_export' => model.get_attribute(DICT, 'export_version', 0).to_i,
          'rows' => r, 'totals' => totals(r),
          'runouts' => { 'on' => Pencil.on?(model), 'changed' => Runouts.report(model) }
        }
      end

      def self.show
        dlg = Dialog.open('summary', title: 'HW Door Style - Summary', key: 'hw_door_style_summary',
                                     width: 1000, height: 650, data: payload)
        dlg.add_action_callback('exportOrder') do |_ctx|
          export_order
          dlg.execute_script("render(#{JSON.generate(payload)})")
        end
        dlg.add_action_callback('refresh') { |_ctx| dlg.execute_script("render(#{JSON.generate(payload)})") }
        dlg.show
      end
    end
  end
end
