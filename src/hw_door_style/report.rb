require 'json'

module HarryWardrobes
  module DoorStyle
    # On-screen summary of every door / drawer front, with CSV export and print-to-PDF.
    module Report
      HEADERS = ['#', 'Unit', 'Item', 'Kind', 'Width mm', 'Height mm', 'Style', 'Mid-rail',
                 'Hinge type', 'Hinges', 'TIP-ON', 'Notes'].freeze

      def self.path_label(path)
        return '(model)' if path.empty?
        path.map do |p|
          n = p.respond_to?(:definition) ? Finder.label(p) : p.name
          p.name.to_s.empty? ? n : "#{n} (#{p.name})"
        end.join(' > ')
      end

      def self.rows(model = Sketchup.active_model)
        rows = []
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
          notes << 'Resized since conversion - press Rebuild styles' if style && Finder.scaled?(inst)
          rows << {
            'unit' => path_label(path), 'item' => Finder.label(inst),
            'kind' => Finder::KINDS[kind], 'width' => Finder.mm_s(w), 'height' => Finder.mm_s(h),
            'style' => Styles.label(style || 'flat'),
            'midrail' => d.get_attribute(DICT, 'midrail') ? 'Yes' : '',
            'hinge_type' => hinges.empty? ? '' : Settings::HINGE_TYPES.fetch(hinges.first.get_attribute(DICT, 'type').to_s, hinges.first.get_attribute(DICT, 'type').to_s),
            'hinges' => hinges.size, 'tip_on' => tips,
            'notes' => notes.reject(&:empty?).join('; ')
          }
        end
        rows.each_with_index { |r, i| r['n'] = i + 1 }
        rows
      end

      def self.totals(rows)
        t = { 'by_style' => Hash.new(0), 'hinges' => Hash.new(0), 'tip_on' => 0, 'items' => rows.size }
        rows.each do |r|
          t['by_style']["#{r['kind']} - #{r['style']}"] += 1
          t['hinges'][r['hinge_type']] += r['hinges'] if r['hinges'] > 0
          t['tip_on'] += r['tip_on']
        end
        t
      end

      def self.csv(rows)
        q = ->(v) { s = v.to_s; s =~ /[",\n]/ ? "\"#{s.gsub('"', '""')}\"" : s }
        lines = [HEADERS.map(&q).join(',')]
        rows.each do |r|
          lines << [r['n'], r['unit'], r['item'], r['kind'], r['width'], r['height'], r['style'],
                    r['midrail'], r['hinge_type'], r['hinges'], r['tip_on'], r['notes']].map(&q).join(',')
        end
        lines.join("\r\n")
      end

      def self.export_csv(model = Sketchup.active_model)
        base = File.basename(model.path.to_s, '.skp')
        base = 'door_summary' if base.empty?
        dir = model.path.to_s.empty? ? nil : File.dirname(model.path)
        file = UI.savepanel('Export door summary', dir, "#{base}_doors.csv")
        return unless file
        file += '.csv' unless file.downcase.end_with?('.csv')
        File.write(file, "﻿" + csv(rows(model)), mode: 'w:UTF-8')
        UI.messagebox("Saved:\n#{file}")
      end

      def self.payload(model = Sketchup.active_model)
        r = rows(model)
        {
          'job' => File.basename(model.path.to_s, '.skp'),
          'hinge_type' => Settings::HINGE_TYPES[Settings.job_hinge_type(model)],
          'date' => Time.now.strftime('%d/%m/%Y %H:%M'),
          'version' => VERSION,
          'rows' => r, 'totals' => totals(r)
        }
      end

      def self.show
        @dlg&.close
        @dlg = UI::HtmlDialog.new(dialog_title: 'HW Door Style - Summary', preferences_key: 'hw_door_style_summary',
                                  width: 1000, height: 650, resizable: true, scrollable: true,
                                  style: UI::HtmlDialog::STYLE_DIALOG)
        html = File.read(File.join(PATH, 'html', 'summary.html'))
        @dlg.set_html(html.sub('/*DATA*/null', JSON.generate(payload)))
        @dlg.add_action_callback('exportCsv') { |_ctx| export_csv }
        @dlg.add_action_callback('refresh') { |_ctx| @dlg.execute_script("render(#{JSON.generate(payload)})") }
        @dlg.show
      end
    end
  end
end
