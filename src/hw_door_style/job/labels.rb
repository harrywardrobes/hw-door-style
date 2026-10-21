# HW Door Style - part labels.
#
# Adapted from OpenCutList by L'Air du Bois (https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension),
# GNU General Public License v3.0: ruby/worker/cutlist/cutlist_labels_worker.rb (one label per piece,
# position in batch, part order strategy),
# model/formula/formula_wrapper.rb, and the label layout presets OpenCutList saves (dictionary
# "cutlist_labels_options"), read here so the labels print the way they do in OpenCutList.
# The drawing itself (twig/tabs/cutlist/_slide-labels.twig, _label-element.twig) is ported to
# html/parts_list.html.
#
# This file is part of HW Door Style and is distributed under the GNU GPL v3.0 (see LICENSE).

require 'json'

module HarryWardrobes
  module DoorStyle
    module Labels
      OCL = 'ladb_opencutlist'.freeze
      PRESETS_KEY = 'core.presets'.freeze
      DICTIONARY = 'cutlist_labels_options'.freeze

      # OpenCutList's own default (json/defaults/cutlist_labels_options.json, metric).
      APP_DEFAULT = {
        'page_width' => '210mm', 'page_height' => '297mm', 'margin_top' => '10mm', 'margin_right' => '0', 'margin_bottom' => '10mm',
        'margin_left' => '0', 'spacing_h' => '0', 'spacing_v' => '0', 'col_count' => 2, 'row_count' => 4, 'offset' => 0,
        'cutting_marks' => false, 'part_order_strategy' => 'number>name>entity_named_path>entity_name>bin',
        'layout' => [
          { 'formula' => 'part.number', 'x' => 0, 'y' => -0.083, 'rotation' => 0, 'size' => 3, 'anchor' => 'middle', 'color' => '#000000' },
          { 'formula' => 'part.name', 'x' => 0, 'y' => 0.083, 'rotation' => 0, 'size' => 1, 'anchor' => 'middle', 'color' => '#000000' },
          { 'formula' => 'part.size', 'x' => 0, 'y' => 0.25, 'rotation' => 0, 'size' => 2, 'anchor' => 'middle', 'color' => '#000000' }
        ]
      }.freeze

      # HW's Zebra layout (Settings "label_layouts" keeps edited copies). x / y: fraction of the
      # label from its centre; size: twelfths of the label's short side (as OpenCutList).
      ZEBRA_DEFAULT = {
        'page_width' => '102mm', 'page_height' => '76mm', 'margin_top' => '5mm', 'margin_right' => '5mm', 'margin_bottom' => '5mm',
        'margin_left' => '5mm', 'spacing_h' => '0', 'spacing_v' => '0', 'col_count' => 1, 'row_count' => 1, 'offset' => 0, 'cutting_marks' => false,
        'part_order_strategy' => '', 'printer' => 'zebra',
        # Left: Pod number + "1 of 2" (small), part name, length x width, material / thickness,
        # customer / room. Top right: the part's outline (its own shape, edged sides thick, as
        # OpenCutList's thumbnail). Bottom right: the part number (big), then the barcode
        # (bars only), both right-aligned.
        'layout' => [
          { 'formula' => 'part.t_of', 'x' => -0.5, 'y' => -0.5, 'size' => 0.9, 'anchor' => 'start-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'thumbnail.shape', 'x' => 0.5, 'y' => -0.5, 'size' => 4.2, 'anchor' => 'end-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'part.name', 'x' => -0.5, 'y' => -0.3, 'size' => 0.95, 'anchor' => 'start-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'part.dims', 'x' => -0.5, 'y' => -0.17, 'size' => 1.05, 'anchor' => 'start-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'group.material', 'x' => -0.5, 'y' => -0.04, 'size' => 0.8, 'anchor' => 'start-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'customer_room', 'x' => -0.5, 'y' => 0.08, 'size' => 0.72, 'anchor' => 'start-top', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'part.no', 'x' => -0.09, 'y' => 0.5, 'size' => 2.4, 'anchor' => 'end', 'rotation' => 0, 'color' => '#000000' },
          { 'formula' => 'barcode', 'x' => 0.5, 'y' => 0.5, 'size' => 1.3, 'width' => 0.57, 'anchor' => 'end', 'rotation' => 0, 'color' => '#000000' }
        ]
      }.freeze

      def self.hw_layouts
        saved = Settings.get['label_layouts']
        saved = {} unless saved.is_a?(Hash)
        base = { 'Zebra 102 x 76' => ZEBRA_DEFAULT }
        base.merge(saved)
      end

      def self.parse(v)
        v = JSON.parse(v) if v.is_a?(String)
        v.is_a?(Hash) ? v : {}
      rescue JSON::ParserError
        {}
      end

      # "102 mm", "10mm", "0.5\"", "0" -> mm
      def self.mm(v)
        s = v.to_s.strip.tr(',', '.')
        n = s[/-?[\d.]+/].to_f
        case s
        when /cm\z/ then n * 10
        when /mm\z/ then n
        when /m\z/ then n * 1000
        when /("|in)\z/ then n * 25.4
        when /ft\z|'\z/ then n * 304.8
        else n # model units in OpenCutList; HW models are mm
        end
      end

      def self.normalise(o)
        o = APP_DEFAULT.merge(o.to_h)
        %w[page_width page_height margin_top margin_right margin_bottom margin_left spacing_h spacing_v].each { |k| o[k] = mm(o[k]) }
        o['col_count'] = [o['col_count'].to_i, 1].max
        o['row_count'] = [o['row_count'].to_i, 1].max
        o['layout'] = Array(o['layout']).map { |e| e.merge('size' => e['size'].to_f, 'x' => e['x'].to_f, 'y' => e['y'].to_f, 'rotation' => e['rotation'].to_f) }
        o['printer'] = 'zebra' # labels only go to the Zebra (the Brother prints the PDFs)
        o
      end

      # { 'presets' => { name => options (mm) }, 'active' => name }. The open model's own label
      # settings come first ("This model"), then the presets saved in OpenCutList, then its default.
      def self.options(model = Sketchup.active_model)
        presets = {}
        hw_layouts.each { |name, o| presets[name] = normalise(o).merge('hw' => true) }
        mine = parse(model.get_attribute(OCL, PRESETS_KEY, {}))[DICTIONARY]
        mine = parse(mine)['0'] if mine
        presets['This model (OpenCutList)'] = normalise(mine) if mine.is_a?(Hash) && !mine.empty?
        global = parse(Sketchup.read_default(OCL, PRESETS_KEY, {}))
        g = parse(parse(global[DICTIONARY])['0'])
        g.each { |name, o| presets[name == '_default' ? 'OpenCutList default' : name] = normalise(o) if o.is_a?(Hash) }
        presets.select! { |_n, o| o['col_count'] == 1 && o['row_count'] == 1 }
        presets['Zebra 102 x 76'] = normalise(ZEBRA_DEFAULT).merge('hw' => true) if presets.empty?
        active = Settings.get['label_layout_active'].to_s
        { 'presets' => presets, 'active' => presets.key?(active) ? active : presets.keys.first }
      rescue StandardError => e
        Log.error('label presets', e)
        { 'presets' => { 'Built-in' => normalise({}) }, 'active' => 'Built-in' }
      end

      # --- values the labels use ----------------------------------------------------------

      Material = Struct.new(:name, :type, :color, :grained, :std_dimension) do
        def to_s = name.to_s
        def export = to_s
        def +(o) = to_s + o.to_s
      end

      # Custom (Ruby) label formulas aren't supported: they would be run as code, and a layout
      # can arrive inside a model file. Every HW field is a fixed field instead.
      def self.eval_formula(_formula, _data)
        { 'error' => 'custom formulas are not supported' }
      end

      # --- entries (OpenCutList CutlistLabelsWorker) ---------------------------------------

      # One entry per piece: sheet goods then hardware, each part's pieces sorted by name.
      # --- grouped labels (hardware and consumables) ---------------------------------------
      # A part gets one label per piece ("part") or one label per name with the total
      # ("aggregate"). Aggregate when: its material is a Hardware type; or its name matches
      # Settings "label_aggregate_names" (L_BRACKET, HINGE*...); or it's timber (dimensional,
      # e.g. the 2x1 battens). The Labels tab can switch any part name either way for the job
      # (kept on the model, "label_modes").
      MODES = 'label_modes'.freeze
      BARCODE = 'barcode'.freeze

      # --- barcodes (Code 128) ---------------------------------------------------------------
      # HW-{ROOM_ID}-{PART_NO} on a part label, HW-{ROOM_ID}-H{n} on a grouped label. Kept on
      # each piece ("barcode") so a scan can be matched back to the part later.
      def self.room_code(room_id)
        r = room_id.to_s.upcase.gsub(/[^A-Z0-9]/, '')
        r.empty? ? 'ROOM' : r
      end

      def self.barcode(room_id, number) = "HW-#{room_code(room_id)}-#{number}"

      # Writes each piece's barcode (only where it changed; not in the library master).
      def self.store_barcodes(model, entries, pieces)
        return if defined?(LibraryExport) && LibraryExport.master?(model)
        want = {}
        entries.each { |e| Array(e['eids']).each { |id| want[id] = e['barcode'] } }
        changed = want.select { |id, code| (p = pieces[id]) && p.valid? && p.get_attribute(DICT, BARCODE) != code }
        return if changed.empty?
        Ops.run(model, 'Label barcodes', transparent: true) { changed.each { |id, code| pieces[id].set_attribute(DICT, BARCODE, code) } }
      end
      STOCK = 'timber_stock_mm'.freeze

      def self.glob?(name, pattern)
        re = Regexp.new("\\A#{Regexp.escape(pattern.to_s.strip.upcase).gsub('\\*', '.*')}\\z")
        name.to_s.upcase.match?(re)
      end

      def self.rule_aggregate?(name, kind)
        return true if %w[hardware timber].include?(kind)
        Settings.names('label_aggregate_names').any? { |pat| glob?(name, pat) }
      end

      def self.modes(model) = (JSON.parse(model.get_attribute(DICT, MODES, '{}')) rescue {})

      def self.aggregate?(name, kind, modes)
        m = modes[name.to_s.upcase]
        m ? m == 'aggregate' : rule_aggregate?(name, kind)
      end

      def self.stock_mm(model)
        v = model.get_attribute(DICT, STOCK).to_i
        [2100, 2400].include?(v) ? v : 2400
      end

      # Settings "label_display_names" (L_BRACKET -> L Brackets), else the name tidied
      # (OVAL_SH_BRACKET -> Oval Sh Bracket).
      def self.display_name(name, kind = nil)
        return '2x1 Timber' if kind == 'timber' && name.to_s.upcase =~ /2X1|TIMBER/
        return 'MDF lengths' if kind == 'timber' && name.to_s.upcase =~ /MDF/
        # shipped names plus your own (Settings > Labels), so a new component name has a label name
        map = (Settings.defaults['label_display_names'] || {}).merge(Settings.get['label_display_names'] || {}).to_h { |k, v| [k.to_s.upcase, v.to_s] }
        base = name.to_s.sub(/#\d+\z/, '').strip
        map[base.upcase] || base.split(/[_\s]+/).map { |w| w =~ /\d/ ? w : w.capitalize }.join(' ')
      end

      # First fit (longest first) of the cut lengths into stock lengths. Returns
      # { 'stock' => lengths needed, 'cuts' => "4 x 2400, 2 x 1850" }. A cut longer than the
      # stock takes whole lengths of its own.
      def self.timber_bins(lengths, stock)
        stock = stock.to_f
        bins = []
        extra = 0
        lengths.map(&:to_f).sort.reverse.each do |len|
          next if len <= 0
          if len > stock
            extra += (len / stock).ceil
            next
          end
          b = bins.index { |left| left >= len }
          b ? bins[b] -= len : bins << stock - len
        end
        cuts = lengths.map { |l| l.to_f.round }.tally.sort_by { |l, _| -l }.map { |l, n| "#{n} x #{l}" }.join(', ')
        { 'stock' => bins.size + extra, 'cuts' => cuts }
      end

      # One label per name for the aggregate parts: name, total (timber: stock lengths), the
      # Pod numbers it belongs to, and the running index n (barcode HW-{room}-H{n}).
      def self.aggregates(parts, tops, stock)
        by = {}
        # hardware that shares a label name but not a length (hanging rails) is kept apart by length
        names = parts.group_by { |p, kind| [display_name(p['name'], kind), kind] }
        split = names.select { |(_n, kind), list| kind == 'hardware' && list.map { |p, _k| p['length'].to_f.round }.uniq.size > 1 }.keys.map(&:first)
        parts.each do |p, kind|
          key = display_name(p['name'], kind)
          key = "#{key} #{p['length'].to_f.round}" if kind == 'hardware' && split.include?(key)
          a = (by[key] ||= { 'kind' => 'aggregate', 'source' => kind, 'name' => key, 'count' => 0, 'ts' => [], 'lengths' => [], 'parts' => [], 'eids' => [] })
          a['count'] += p['qty'].to_i
          a['parts'] << p['name']
          Array(p['instances']).each do |i|
            a['eids'] << i['eid'] if i['eid']
            t = tops[i['top']].to_s
            a['ts'] << t unless t.empty?
            a['lengths'] << p['length'].to_f if kind == 'timber'
          end
        end
        list = by.values.sort_by { |a| [a['source'] == 'timber' ? 1 : 0, a['name'].downcase] }
        list.each_with_index do |a, i|
          a['agg_index'] = i + 1
          a['ts'] = a['ts'].uniq.sort_by { |t| t_key(t) }.join(', ')
          a['parts'] = a['parts'].uniq
          a['eids'] = a['eids'].uniq
          if a['source'] == 'timber'
            b = timber_bins(a.delete('lengths'), stock)
            a['count'] = b['stock']
            a['stock'] = stock
            a['cuts'] = b['cuts']
            a['note'] = "#{b['stock']} x #{stock}  (cuts: #{b['cuts']})"
          else
            a.delete('lengths')
          end
        end
        list
      end

      # tops: Products.list's top-level entity id -> Pod number, so each piece carries its
      # product's Pod number (blank when it isn't in one). Printed Pod number, then part number;
      # the grouped labels come after the part labels.
      def self.entries(list, preset, tops = {}, modes: {}, stock: 2400, which: '', room_id: '')
        layout = Array(preset['layout'])
        out = []
        all = list['groups'].flat_map { |g| g['parts'].map { |p| [p, g, 'sheet'] } } + list['hardware'].map { |h| [h, nil, 'hardware'] } +
              Array(list['timber']).map { |t| [t, nil, 'timber'] }
        agg, parts = all.partition { |p, _g, kind| aggregate?(p['name'], kind, modes) }
        parts = [] if which == 'agg'
        parts.each do |p, g, kind|
          insts = Array(p['instances']).sort_by { |i| i['entity_name'].to_s }
          insts.each_with_index do |inst, i|
            mat = g ? Material.new(g['material'], 'sheet_good', nil, g['grained'], PartsList.length_s(g['thickness'])) : Material.new(p['material'], kind == 'timber' ? 'dimensional' : 'hardware', nil, false, '')
            e = {
              'kind' => kind, 'number' => p['number'], 't' => tops[inst['top']].to_s, 'name' => p['name'],
              'barcode' => barcode(room_id, p['number']), 'eids' => [inst['eid']].compact, 'length' => p['length_s'], 'width' => p['width_s'],
              'thickness' => p['thickness_s'], 'count' => p['qty'], 'position' => i + 1,
              'material_name' => mat.name, 'std_dimension' => mat.std_dimension, 'grained' => mat.grained ? true : false,
              'edges' => p['edges'] || {}, 'edge_colors' => p['edge_colors'] || {}, 'l_ratio' => p['l_ratio'], 'w_ratio' => p['w_ratio'],
              'group_key' => [kind == 'sheet' ? 0 : 3, mat.name.to_s.empty? ? '~' : mat.name.to_s.downcase, -(g ? g['thickness'].to_f : 0)],
              'layer' => inst['layer'], 'entity_name' => inst['entity_name'], 'entity_named_path' => inst['named_path']
            }
            e['custom'] = layout.map { |el| el['formula'].to_s.start_with?('custom') ? eval_formula(nil, nil) : nil }
            out << e
          end
        end
        by_t(out) + aggregates(agg.map { |p, _g, kind| [p, kind] }, tops, stock).map do |a|
          a.merge('barcode' => barcode(room_id, "H#{a['agg_index']}"), 'number' => '', 't' => '', 'position' => 1, 'length' => '', 'width' => '', 'thickness' => '', 'material_name' => '',
                  'edges' => {}, 'edge_colors' => {}, 'custom' => layout.map { nil })
        end
      end

      # Print range: '' all, 'agg' grouped labels only, 'T3' one Pod number, [numbers] chosen parts.
      def self.range(entries, r)
        return entries if r.nil? || r == '' || r == 'all'
        return entries.select { |e| e['kind'] == 'aggregate' } if r == 'agg'
        return entries.select { |e| e['t'] == r || e['ts'].to_s.split(', ').include?(r) } if r.is_a?(String)
        nums = Array(r).map(&:to_s)
        entries.select { |e| nums.include?(e['number'].to_s) || nums.include?("H#{e['agg_index']}") }
      end

      T_ORDER = %w[T W B F].freeze

      # Pod number (T1, T2... W1... in list order; none last), then part number, then piece.
      def self.t_key(t)
        return [1, 99, 0, ''] if t.to_s.empty?
        l = t[/\A[A-Z]+/].to_s
        [0, T_ORDER.index(l) || 9, t[/\d+/].to_i, l]
      end

      def self.by_t(list)
        list.sort_by { |e| [t_key(e['t']), e['number'].to_i, e['number'].to_s, e['position']] }
      end

      # OpenCutList LabelEntry.entry_order: "number>name>entity_named_path>entity_name>bin", "-" = descending.
      def self.sort(list, strategy)
        keys = strategy.to_s.split('>').reject(&:empty?)
        list.sort do |a, b|
          r = a['group_key'] <=> b['group_key']
          next r unless r.zero?
          keys.each do |k|
            desc = k.start_with?('-')
            k = k.delete_prefix('-')
            av, bv = case k
                     when 'number' then [a['number'].to_s.rjust(3, ' '), b['number'].to_s.rjust(3, ' ')]
                     when 'bin' then [0, 0]
                     else [a[k].to_s, b[k].to_s]
                     end
            r = (av <=> bv).to_i
            r = -r if desc
            break unless r.zero?
          end
          r.zero? ? (a['position'] <=> b['position']) : r # then position in batch, as OpenCutList
        end
      end

    end
  end
end
