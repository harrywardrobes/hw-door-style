# HW Door Style - part labels.
#
# Adapted from OpenCutList by L'Air du Bois (https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension),
# GNU General Public License v3.0: ruby/worker/cutlist/cutlist_labels_worker.rb (one label per piece,
# position in batch, part order strategy, custom formulas), worker/common/common_eval_formula_worker.rb,
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
        o
      end

      # { 'presets' => { name => options (mm) }, 'active' => name }. The open model's own label
      # settings come first ("This model"), then the presets saved in OpenCutList, then its default.
      def self.options(model = Sketchup.active_model)
        presets = {}
        mine = parse(model.get_attribute(OCL, PRESETS_KEY, {}))[DICTIONARY]
        mine = parse(mine)['0'] if mine
        presets['This model (OpenCutList)'] = normalise(mine) if mine.is_a?(Hash) && !mine.empty?
        global = parse(Sketchup.read_default(OCL, PRESETS_KEY, {}))
        g = parse(parse(global[DICTIONARY])['0'])
        g.each { |name, o| presets[name == '_default' ? 'OpenCutList default' : name] = normalise(o) if o.is_a?(Hash) }
        presets['Built-in'] = normalise({}) if presets.empty?
        { 'presets' => presets, 'active' => presets.keys.first }
      rescue StandardError => e
        Log.error('label presets', e)
        { 'presets' => { 'Built-in' => normalise({}) }, 'active' => 'Built-in' }
      end

      # --- formula values (OpenCutList FormulaWrapper, the parts labels use) ---------------

      class Len
        def initialize(mm)
          @mm = mm.to_f
        end

        def to_s
          PartsList.length_s(@mm)
        end

        def to_f
          (@mm / PartsList::MM)
        end

        def to_mm; @mm; end
        def to_cm; @mm / 10.0; end
        def to_m; @mm / 1000.0; end
        def to_inch; @mm / PartsList::MM; end
        def export; to_s; end
        def +(o) = o.is_a?(String) ? to_s + o : Len.new(@mm + (o.is_a?(Len) ? o.to_mm : o.to_f * PartsList::MM))
        def -(o) = Len.new(@mm - (o.is_a?(Len) ? o.to_mm : o.to_f * PartsList::MM))
        def *(o) = Len.new(@mm * o.to_f)
        def /(o) = Len.new(@mm / o.to_f)
      end

      class Batch
        attr_reader :position, :count

        def initialize(position, count)
          @position = position
          @count = count
        end

        def to_s = "#{@position}/#{@count}"
        def export = to_s
        def +(o) = o.is_a?(String) ? to_s + o : self
      end

      Material = Struct.new(:name, :type, :color, :grained, :std_dimension) do
        def to_s = name.to_s
        def export = to_s
        def +(o) = to_s + o.to_s
      end

      Edge = Struct.new(:name, :color) do
        def to_s = name.to_s
        def export = to_s
        def material_name = name.to_s
        def +(o) = to_s + o.to_s
      end

      # The instance variables a custom formula can use (OpenCutList LabelData).
      class Data
        def initialize(vars)
          vars.each { |k, v| instance_variable_set("@#{k}", v) }
        end

        def get_binding
          binding
        end
      end

      def self.eval_formula(formula, data)
        FormulaParser.new(formula.to_s, data).parse
        v = eval(formula.to_s, data.get_binding) # rubocop:disable Security/Eval -- checked by FormulaParser, as OpenCutList does
        v = v.export if v.respond_to?(:export)
        v.to_s
      rescue ForbiddenFormulaError => e
        { 'error' => e.message }
      rescue Exception => e # rubocop:disable Lint/RescueException -- a bad formula must not stop the labels
        { 'error' => e.message.to_s.split(/labels[.]rb:\d+:/).last.to_s }
      end

      # --- entries (OpenCutList CutlistLabelsWorker) ---------------------------------------

      # One entry per piece: sheet goods then hardware, each part's pieces sorted by name.
      # tops: Products.list's top-level entity id -> T number, so each piece carries its
      # product's T number (blank when it isn't in one). Printed T number, then part number.
      def self.entries(list, preset, tops = {})
        layout = Array(preset['layout'])
        out = []
        parts = list['groups'].flat_map { |g| g['parts'].map { |p| [p, g, 'sheet'] } } + list['hardware'].map { |h| [h, nil, 'hardware'] }
        parts.each do |p, g, kind|
          insts = Array(p['instances']).sort_by { |i| i['entity_name'].to_s }
          insts.each_with_index do |inst, i|
            mat = g ? Material.new(g['material'], 'sheet_good', nil, g['grained'], PartsList.length_s(g['thickness'])) : Material.new(p['material'], 'hardware', nil, false, '')
            edges = (p['edges'] || {}).to_h { |k, v| [k, Edge.new(v, (p['edge_colors'] || {})[k])] }
            e = {
              'kind' => kind, 'number' => p['number'], 't' => tops[inst['top']].to_s, 'name' => p['name'], 'length' => p['length_s'], 'width' => p['width_s'],
              'thickness' => p['thickness_s'], 'count' => p['qty'], 'position' => i + 1,
              'material_name' => mat.name, 'std_dimension' => mat.std_dimension, 'grained' => mat.grained ? true : false,
              'edges' => p['edges'] || {}, 'edge_colors' => p['edge_colors'] || {}, 'l_ratio' => p['l_ratio'], 'w_ratio' => p['w_ratio'],
              'group_key' => [kind == 'sheet' ? 0 : 3, mat.name.to_s.empty? ? '~' : mat.name.to_s.downcase, -(g ? g['thickness'].to_f : 0)],
              'layer' => inst['layer'], 'entity_name' => inst['entity_name'], 'entity_named_path' => inst['named_path']
            }
            e['custom'] = layout.map do |el|
              next nil unless el['formula'].to_s.start_with?('custom')
              data = Data.new(
                number: p['number'].to_s, path: inst['named_path'].to_s, instance_name: inst['entity_name'].to_s, name: p['name'].to_s,
                cutting_length: Len.new(p['length']), cutting_width: Len.new(p['width']), cutting_thickness: Len.new(p['thickness']),
                edge_cutting_length: Len.new(p['length']), edge_cutting_width: Len.new(p['width']),
                bbox_length: Len.new(p['length']), bbox_width: Len.new(p['width']), bbox_thickness: Len.new(p['thickness']),
                final_area: (p['length'].to_f * p['width'].to_f / 1_000_000.0).round(3).to_s, material: mat,
                description: '', url: '', tags: [], edge_ymin: edges['ymin'], edge_ymax: edges['ymax'], edge_xmin: edges['xmin'], edge_xmax: edges['xmax'],
                layer: inst['layer'].to_s, batch: Batch.new(i + 1, p['qty']), bin: nil,
                filename: list['filename'].to_s, model_name: list['model_name'].to_s, model_description: '',
                page_name: list['page_name'].to_s, page_description: ''
              )
              eval_formula(el['custom_formula'], data)
            end
            out << e
          end
        end
        by_t(out)
      end

      T_ORDER = %w[T W B L F M].freeze

      # T number (T1, T2... W1... in list order; none last), then part number, then piece.
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
