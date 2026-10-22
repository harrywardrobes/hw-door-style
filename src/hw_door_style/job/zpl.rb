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
      # line is the total, the material line the Pod numbers it's for.
      def self.mm_s(s) = s.to_s.sub(/\s*mm\z/, '')

      def self.edging(e)
        ed = e['edges'] || {}
        long = %w[ymin ymax].count { |k| !ed[k].to_s.empty? }
        short = %w[xmin xmax].count { |k| !ed[k].to_s.empty? }
        return 'No edging' if long.zero? && short.zero?
        "Edged: #{[long.positive? ? "#{long} long" : nil, short.positive? ? "#{short} short" : nil].compact.join(', ')}"
      end

      # Width (mm) a text element has from its anchor point to the label edge(s).
      def self.room(anchor, x, lw)
        case anchor.split('-').first
        when 'start' then (0.5 - x) * lw
        when 'end' then (x + 0.5) * lw
        else 2 * [0.5 - x, x + 0.5].min * lw
        end.clamp(lw * 0.1, lw)
      end

      # OpenCutList's proportional thumbnail as ZPL boxes: the part's outline to its length /
      # width ratio, edged sides drawn thick, the others as a thin dashed line.
      def self.outline(el, e, cx, cy, area, min_unit, anchor)
        pw = [min_unit / 7.0, area / 18.0].max
        dw = min_unit / 20.0
        lr, wr = ratios(el['formula'], e)
        rw = (area - pw) * lr
        rh = (area - pw) * wr
        return [] if rw <= 0 || rh <= 0
        tx = case anchor.split('-').first
             when 'middle' then -area / 2
             when 'end' then -area
             else 0
             end
        ty = anchor.end_with?('top') ? 0 : -area
        ox = cx + tx + (area - rw) / 2
        oy = cy + ty + (area - rh) / 2
        edges = e['edges'] || {}
        thick = [dots(pw), 3].max
        thin = [dots(dw), 1].max
        dash = [dots(dw * 4), 4].max
        out = []
        # [x, y, length, horizontal?, edge key] - top = ymax, bottom = ymin, right = xmax, left = xmin
        [[ox, oy, rw, true, 'ymax'], [ox, oy + rh, rw, true, 'ymin'], [ox + rw, oy, rh, false, 'xmax'], [ox, oy, rh, false, 'xmin']].each do |x, y, len, horiz, key|
          if edges[key].to_s.empty?
            n = dots(len)
            pos = 0
            while pos < n
              seg = [dash, n - pos].min
              out << (horiz ? "^FO#{dots(x) + pos},#{dots(y)}^GB#{seg},#{thin},#{thin}^FS" : "^FO#{dots(x)},#{dots(y) + pos}^GB#{thin},#{seg},#{thin}^FS")
              pos += dash * 2
            end
          else
            h0 = thick / 2
            out << (horiz ? "^FO#{[dots(x) - h0, 0].max},#{[dots(y) - h0, 0].max}^GB#{dots(len) + thick},#{thick},#{thick}^FS" : "^FO#{[dots(x) - h0, 0].max},#{[dots(y) - h0, 0].max}^GB#{thick},#{dots(len) + thick},#{thick}^FS")
          end
        end
        out
      end

      # Width / height of the outline as fractions of its box: 'thumbnail.shape' = the part's
      # own length : width (thin strips kept visible), 'proportional' = OpenCutList's (to the
      # biggest part of its material), else a square.
      def self.ratios(formula, e)
        f = formula.to_s
        if f.include?('shape')
          l = mm_s(e['length']).to_f
          w = mm_s(e['width']).to_f
          m = [l, w].max
          return [1.0, 1.0] unless m.positive?
          [[l / m, 0.14].max, [w / m, 0.14].max]
        elsif f.include?('proportional')
          [e['l_ratio'].to_f, e['w_ratio'].to_f]
        else
          [1.0, 1.0]
        end
      end

      # Code 128 width in modules with automatic code sets (as ^BC mode A / JsBarcode): runs of
      # 4+ digits go in code C (two digits per symbol).
      def self.code128_modules(payload)
        symbols = 0
        set = nil
        s = payload.to_s
        i = 0
        while i < s.length
          run = s[i..][/\A\d+/].to_s.length
          if run >= 4
            pairs = run / 2
            symbols += 1 if set # switch to C
            set = :c
            symbols += pairs
            i += pairs * 2
          else
            symbols += 1 if set == :c
            set = :b
            symbols += 1
            i += 1
          end
        end
        11 * (symbols + 2) + 13 # start + data + check, stop
      end

      def self.value(el, e, job, idx)
        terms = el['formula'].to_s.split('.')
        key = terms[1]
        agg = e['kind'] == 'aggregate'
        case terms[0]
        when 'part'
          case key
          when 'number' then agg ? e['name'].to_s : [e['t'], e['number']].reject { |x| x.to_s.empty? }.join('  ')
          when 'name' then e['name'].to_s
          when 't', 't_number' then e['t'].to_s
          when 'no' then agg ? "H#{e['agg_index']}" : e['number'].to_s
          when 't_of' then agg ? e['ts'].to_s : [e['t'], "#{e['position']} of #{e['count']}"].reject { |x| x.to_s.empty? }.join('   ')
          when 'ts', 't_numbers' then (e['ts'] || e['t']).to_s
          when 'note' then e['note'].to_s
          when 'dims' then agg ? "Qty #{e['count']}" : [mm_s(e['length']), mm_s(e['width'])].reject(&:empty?).join(' x ')
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
            e['note'].to_s
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
        if e['kind'] == 'divider'
          hd = dots([lh / 5.0, 12].min)
          return ['^XA', '^CI28', "^PW#{dots(o['page_width'])}", "^LL#{dots(o['page_height'])}", "^LH#{dots(o['margin_left'])},#{dots(o['margin_top'])}",
                  "^FO0,#{dots(lh / 2.0) - hd / 2}^A0N,#{hd},#{hd}^FB#{dots(lw)},1,0,C,0^FD#{clean(e['name'].to_s)}^FS", '^XZ'].join("\n")
        end
        min_unit = [lw / 12.0, lh / 12.0].min
        out = ['^XA', '^CI28', "^PW#{dots(o['page_width'])}", "^LL#{dots(o['page_height'])}", "^LH#{dots(o['margin_left'])},#{dots(o['margin_top'])}"]
        Array(o['layout']).each_with_index do |el, idx|
          f = el['formula'].to_s
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
            modules = code128_modules(payload)
            mod = [[(dots(w) / modules.to_f).floor, 1].max, 4].min
            bw = modules * mod
            x = case anchor.split('-').first
                when 'start' then dots(cx)
                when 'end' then dots(cx) - bw
                else dots(cx) - bw / 2
                end
            bar_h = [dots(h), 20].max
            y = top ? dots(cy) : dots(cy) - bar_h
            out << "^BY#{mod}^FO#{[x, 0].max},#{[y, 0].max}^BCN,#{bar_h},N,N,N,A^FD#{clean(payload)}^FS"
          elsif f.start_with?('thumbnail')
            next if e['kind'] == 'aggregate'
            out.concat(outline(el, e, cx, cy, size, min_unit, anchor))
          else
            text = clean(value(el, e, job, idx))
            next if text.empty?
            block = dots(room(anchor, el['x'].to_f, lw))
            # shrink long values to fit the room they have (as the window does), not wrap over themselves
            hd = [[dots(size), (block / (text.length * 0.55)).floor].min, 10].max
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
        ok = system('cmd', '/c', 'copy', '/b', tmp.tr('/', '\\'), target, out: File::NULL, err: File::NULL)
        File.delete(tmp) rescue nil
        return true if ok
        raise "Couldn't reach the Zebra at #{target} (#{e.message}). Share it in Windows: Printers > Zebra GK420D > Printer properties > Sharing > share as \"#{share}\" (Settings > Labels)."
      end

      # A sample label with every field, for Settings > Labels > Test print.
      def self.test_label(o = nil)
        o ||= Labels.normalise(Labels::ZEBRA_DEFAULT)
        e = { 'kind' => 'sheet', 't' => 'T3', 'number' => 12, 'name' => 'WRD_FL', 'length' => '788 mm', 'width' => '490 mm', 'thickness' => '18 mm',
              'count' => 2, 'position' => 1, 'material_name' => 'Frost White', 'std_dimension' => '18 mm', 'edges' => { 'ymax' => 'EDGE 0.8mm ABS' },
              'l_ratio' => 1.0, 'w_ratio' => 0.62, 'barcode' => 'HW-TEST-12', 'custom' => [] }
        job = { 'customer' => 'SMITH JA', 'room_id' => 'SMI26102001', 'room_name' => 'Test label' }
        label(o, e, job)
      end
    end
  end
end
