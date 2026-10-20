require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Labels straight to the Zebra GK420D as ZPL - no browser print, so no "first label blank"
    # after printing to another printer (Chromium keeps the last printer's page size).
    #
    #   Layout   the same label layout as the screen (elements at x / y as a fraction of the
    #            label from its centre, size in twelfths of the label's short side), turned
    #            into dots at 8 dots / mm (203 dpi).
    #   Sending  the Zebra shared in Windows (Printer properties > Sharing, share name in
    #            Settings > Labels, default ZEBRA): the ZPL is written to \\localhost\ZEBRA.
    #   Test     Settings > Labels > Test print.
    module Zpl
      DPMM = 8.0

      def self.share = (Settings.get['zebra_share'].to_s.strip.empty? ? 'ZEBRA' : Settings.get['zebra_share'].to_s.strip)

      def self.dots(mm) = (mm.to_f * DPMM).round

      # Text safe inside ^FD (^ and ~ are ZPL commands); UTF-8 via ^CI28.
      def self.clean(s) = s.to_s.gsub(/[\^~]/, ' ').gsub(/[\r\n]+/, ' ').strip

      # The value of a layout element for a label - the same as the window's element()
      # (html/parts_list.html). Grouped labels: the big number is the item's name, the name
      # line is the total, the material line the T numbers it's for.
      def self.mm_s(s) = s.to_s.sub(/\s*mm\z/, '')

      def self.edging(e)
        ed = e['edges'] || {}
        long = %w[ymin ymax].count { |k| !ed[k].to_s.empty? }
        short = %w[xmin xmax].count { |k| !ed[k].to_s.empty? }
        return 'No edging' if long.zero? && short.zero?
        "Edged: #{[long.positive? ? "#{long} long" : nil, short.positive? ? "#{short} short" : nil].compact.join(', ')}"
      end

      def self.value(el, e, job, idx)
        terms = el['formula'].to_s.split('.')
        key = terms[1]
        agg = e['kind'] == 'aggregate'
        case terms[0]
        when 'part'
          case key
          when 'number' then agg ? e['name'].to_s : [e['t'], e['number']].reject { |x| x.to_s.empty? }.join('  ')
          when 'name' then agg ? "Qty #{e['count']}" : e['name'].to_s
          when 't', 't_number' then e['t'].to_s
          when 'no' then agg ? '' : e['number'].to_s
          when 'ts', 't_numbers' then (e['ts'] || e['t']).to_s
          when 'note' then e['note'].to_s
          when 'dims' then agg ? e['note'].to_s : "#{[mm_s(e['length']), mm_s(e['width']), mm_s(e['thickness'])].reject(&:empty?).join(' x ')} mm"
          when 'size', 'cutting_size', 'edge_cutting_size' then agg ? e['note'].to_s : "#{e['length']} x #{e['width']}"
          when 'of' then agg ? '' : "#{e['position']} of #{e['count']}"
          when 'batch' then agg ? '' : "#{e['position']}/#{e['count']}"
          when 'edging' then agg ? '' : edging(e)
          when 'count' then e['count'].to_s
          when 'length', 'cutting_length' then e['length'].to_s
          when 'width', 'cutting_width' then e['width'].to_s
          when 'thickness', 'cutting_thickness' then e['thickness'].to_s
          when 'edge' then (e['edges'] || {})[terms[2]].to_s
          when 'bin', 'description', 'tags', 'face' then ''
          else e[key].to_s
          end
        when 'group'
          if agg
            e['ts'].to_s.empty? ? '' : "For #{e['ts']}"
          else
            case key
            when 'material' then [e['material_name'], e['std_dimension']].reject { |x| x.to_s.empty? }.join(' / ')
            when 'material_name' then e['material_name'].to_s
            when 'std_dimension' then e['std_dimension'].to_s
            else ''
            end
          end
        when 'customer' then job['customer'].to_s
        when 'room_id' then job['room_id'].to_s
        when 'room_name' then job['room_name'].to_s
        when 'room' then [job['room_id'], job['room_name']].reject { |x| x.to_s.empty? }.join('  ')
        when 'customer_room' then [job['customer'], job['room_id'], job['room_name']].reject { |x| x.to_s.empty? }.join('  |  ')
        when 'text' then el['text'].to_s
        when 'filename' then job['filename'].to_s
        when 'generated_at' then Time.now.strftime('%d/%m/%Y')
        when 'length_unit' then 'mm'
        when 'custom'
          c = Array(e['custom'])[idx]
          c.is_a?(Hash) ? '' : c.to_s
        else ''
        end
      end

      # One label (^XA ... ^XZ) for an entry with a layout (Labels.normalise, mm).
      def self.label(o, e, job)
        lw = o['page_width'] - o['margin_left'] - o['margin_right']
        lh = o['page_height'] - o['margin_top'] - o['margin_bottom']
        min_unit = [lw / 12.0, lh / 12.0].min
        out = ['^XA', '^CI28', "^PW#{dots(o['page_width'])}", "^LL#{dots(o['page_height'])}", "^LH#{dots(o['margin_left'])},#{dots(o['margin_top'])}"]
        Array(o['layout']).each_with_index do |el, idx|
          f = el['formula'].to_s
          next if f.start_with?('thumbnail')
          anchor = (el['anchor'] || 'middle').to_s
          cx = lw / 2.0 + el['x'].to_f * lw
          cy = lh / 2.0 + el['y'].to_f * lh
          size = el['size'].to_f * min_unit # mm, as the window's font size
          top = anchor.end_with?('top')
          if f == 'hr'
            w = (el['width'] || 0.9).to_f * lw
            out << "^FO#{dots(cx - w / 2)},#{dots(cy)}^GB#{dots(w)},#{[dots(el['size'].to_f * 0.25), 2].max},#{[dots(el['size'].to_f * 0.25), 2].max}^FS"
          elsif f == 'barcode'
            payload = e['barcode'].to_s
            next if payload.empty?
            w = (el['width'] || 0.8).to_f * lw
            h = size * 1.6
            modules = 11 * (payload.length + 2) + 13 # Code 128 B: start, data, check, stop
            mod = [[(dots(w) / modules.to_f).floor, 1].max, 4].min
            bw = modules * mod
            x = case anchor.split('-').first
                when 'start' then dots(cx)
                when 'end' then dots(cx) - bw
                else dots(cx) - bw / 2
                end
            text_h = [dots(size * 0.35), 18].max
            bar_h = [dots(h) - text_h - 4, 20].max
            y = top ? dots(cy) : dots(cy) - dots(h)
            out << "^BY#{mod}^FO#{[x, 0].max},#{[y, 0].max}^BCN,#{bar_h},Y,N,N^FD#{clean(payload)}^FS"
          else
            text = clean(value(el, e, job, idx))
            next if text.empty?
            hd = [dots(size), 10].max
            block = dots(lw)
            x0 = case anchor.split('-').first
                 when 'start' then dots(cx)
                 when 'end' then dots(cx) - block
                 else dots(cx) - block / 2
                 end
            just = { 'start' => 'L', 'end' => 'R' }.fetch(anchor.split('-').first, 'C')
            # the window draws text on its baseline (top anchors: from the top)
            y = top ? dots(cy) : dots(cy) - (hd * 0.8).round
            out << "^FO#{x0},#{[y, 0].max}^A0N,#{hd},#{hd}^FB#{block},1,0,#{just},0^FD#{text}^FS"
          end
        end
        out << '^XZ'
        out.join("\n")
      end

      def self.document(o, entries, job)
        raise 'The Zebra prints one label per page - choose a layout with 1 column and 1 row.' if o['col_count'].to_i != 1 || o['row_count'].to_i != 1
        entries.map { |e| label(o, e, job) }.join("\n")
      end

      # Sends ZPL to the shared Zebra. Raises with what to check when it can't.
      def self.transmit(zpl)
        target = "\\\\localhost\\#{share}"
        File.binwrite(target, zpl)
        true
      rescue StandardError => e
        tmp = File.join(Dir.tmpdir, "hw_labels_#{Process.pid}.zpl")
        File.binwrite(tmp, zpl)
        ok = system(%(cmd /c copy /b "#{tmp}" "#{target}" >nul 2>&1))
        File.delete(tmp) rescue nil
        return true if ok
        raise "Couldn't reach the Zebra at #{target} (#{e.message}). Share it in Windows: Printers > Zebra GK420D > Printer properties > Sharing > share as \"#{share}\" (Settings > Labels)."
      end

      # A sample label with every field, for Settings > Labels > Test print.
      def self.test_label(o = nil)
        o ||= Labels.normalise(Labels::ZEBRA_DEFAULT)
        e = { 'kind' => 'sheet', 't' => 'T3', 'number' => 12, 'name' => 'WRD_FL', 'length' => '788 mm', 'width' => '490 mm', 'thickness' => '18 mm',
              'count' => 2, 'position' => 1, 'material_name' => 'Frost White', 'std_dimension' => '18 mm', 'edges' => {}, 'barcode' => 'HW-TEST-12', 'custom' => [] }
        job = { 'customer' => 'SMITH JA', 'room_id' => 'SMI26102001', 'room_name' => 'Test label' }
        label(o, e, job)
      end
    end
  end
end
