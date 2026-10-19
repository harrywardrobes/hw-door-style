require 'json'

module HarryWardrobes
  module DoorStyle
    # The Door style window (toolbar: door style), laid out like Colours: one row each for
    # Doors, Drawer fronts and Internal drawers, the job's hinge type and its handles.
    # Everything is saved on the model (it travels with the file):
    #   job_styles        { 'door' => id, 'ext_drawer' => id, 'int_drawer' => id }
    #   hinge_type        (Settings.job_hinge_type)
    #   job_handles       handle rules (Settings.job_handles)
    #   job_handle_names  handle names and SKUs (sent to / taken from HubSpot)
    #
    # Apply redraws only what changed, a group at a time with the window's progress bar,
    # in one undo step. Items styled by right-click keep their style unless "Reset" is ticked.
    module DoorStyleWindow
      ROWS = [
        ['door', 'Doors', 'Wardrobe, linen, top box, bridge and walk-in doors'],
        ['ext_drawer', 'Drawer fronts', 'External drawer fronts'],
        ['int_drawer', 'Internal drawers', 'Internal drawer fronts - usually Flat']
      ].freeze

      HANDLE_NAMES = [
        ['main_robe_handle', 'Robe handle'], ['main_robe_handle_id', 'Robe handle SKU'],
        ['drawer_handle', 'Drawer handle'], ['drawer_handle_sku', 'Drawer handle SKU'],
        ['interior_handle', 'Interior handle'], ['interior_handle_sku', 'Interior handle SKU']
      ].freeze

      def self.json_attr(model, key)
        v = JSON.parse(model.get_attribute(DICT, key, '{}'))
        v.is_a?(Hash) ? v : {}
      rescue StandardError
        {}
      end

      # The job's style per row. Jobs from before this window: the style most of their
      # converted items have, else the Settings defaults.
      def self.job_styles(model = Sketchup.active_model)
        saved = json_attr(model, 'job_styles')
        defaults = Settings.get['default_door_styles'] || {}
        ROWS.to_h do |kind, _l, _h|
          s = saved[kind]
          s ||= Finder.all_targets(model, [kind.to_sym]).filter_map { |i, _k| i.definition.get_attribute(DICT, 'requested_style') }
                      .tally.max_by(&:last)&.first
          s ||= defaults[kind] || (kind == 'int_drawer' ? 'flat' : 'shaker')
          [kind, Styles.ready?(s) ? s : 'flat']
        end
      end

      def self.handle_names(model = Sketchup.active_model)
        saved = json_attr(model, 'job_handle_names')
        HANDLE_NAMES.to_h { |k, _| [k, saved[k].to_s] }
      end

      # Items of each row: { kind => { 'total', 'override', 'styled' } }.
      def self.counts(model)
        ROWS.to_h do |kind, _l, _h|
          pairs = Finder.all_targets(model, [kind.to_sym])
          [kind, { 'total' => pairs.size, 'override' => pairs.count { |i, _| Converter.override?(i) },
                   'styled' => pairs.count { |i, _| i.definition.get_attribute(DICT, 'style') } }]
        end
      end

      def self.data(model = Sketchup.active_model)
        {
          'job' => File.basename(model.path.to_s, '.skp'),
          'rows' => ROWS, 'current' => job_styles(model), 'counts' => counts(model),
          'styles' => Styles.profiles.map do |p|
            { 'id' => p['id'], 'name' => p['name'], 'ready' => Styles.ready?(p['id']), 'missing' => Styles.missing(p),
              'handleless' => p['handleless'] ? true : false, 'midrail' => p['midrail_centre_mm'],
              'drawing' => Styles::DRAWINGS.key?(p['id']) ? p['id'] : nil }
          end,
          'hinge_types' => Settings::HINGE_TYPES, 'hinge' => Settings.job_hinge_type(model),
          'handles' => Settings.job_handles(model), 'handle_defaults' => Settings.job_handles,
          'names' => handle_names(model), 'name_labels' => HANDLE_NAMES
        }
      end

      # What Apply has to redraw: [[label, pairs, style or nil, override]] (nil style = keep
      # each item's style, e.g. a new hinge type).
      def self.plan(model, styles, hinge, reset)
        old_hinge = Settings.job_hinge_type(model)
        work = []
        touched = {}
        ROWS.each do |kind, label, _h|
          style = styles[kind]
          pairs = Finder.all_targets(model, [kind.to_sym])
          pairs = pairs.reject { |i, _| Converter.override?(i) } unless reset
          pairs = pairs.reject do |i, _|
            cur = i.definition.get_attribute(DICT, 'requested_style')
            # Internal drawers never converted stay as they are while their row is Flat.
            next true if kind == 'int_drawer' && cur.nil? && style == 'flat'
            cur == style && !(reset && Converter.override?(i)) && !(kind == 'door' && hinge != old_hinge)
          end
          next if pairs.empty?
          pairs.each { |i, _| touched[i.entityID] = true }
          pairs.group_by { |i, _| i.definition }.each_value do |chunk|
            work << ["#{label}: #{Styles.label(style)} (#{chunk.size})", chunk, style, reset ? false : nil]
          end
        end
        if hinge != old_hinge
          rest = Doors.processed(model, [:door]).reject { |i, _| touched[i.entityID] }
          rest.group_by { |i, _| i.definition }.each_value { |chunk| work << ["Doors: new hinges (#{chunk.size})", chunk, nil, nil] }
        end
        work
      end

      def self.show(model = Sketchup.active_model)
        dlg = Dialog.open('door_style', title: 'HW - Door style', key: 'hw_door_style_window', width: 620, height: 720, data: data(model))
        dlg.add_action_callback('apply') do |_c, json|
          req = JSON.parse(json)
          styles = ROWS.to_h { |k, _l, _h| [k, Styles.ready?(req.dig('styles', k)) ? req.dig('styles', k) : 'flat'] }
          hinge = Settings::HINGE_TYPES.key?(req['hinge']) ? req['hinge'] : Settings.job_hinge_type(model)
          handles = Settings::HANDLE_KEYS.to_h { |k| [k, req.dig('handles', k)] }
          handles['handle_double_min_width_mm'] = handles['handle_double_min_width_mm'].to_f
          names = HANDLE_NAMES.to_h { |k, _| [k, req.dig('names', k).to_s.strip] }
          work = plan(model, styles, hinge, req['reset'] ? true : false)
          next if !work.empty? && !Doors.colour_ready?

          first = true
          step = lambda do |&blk|
            r = Ops.run(model, 'Door style', transparent: !first, &blk)
            first = false
            r
          end
          notes = []
          items = 0
          steps = [['Saving the job settings', lambda {
            step.call do
              model.set_attribute(DICT, 'job_styles', JSON.generate(styles))
              model.set_attribute(DICT, 'job_handles', JSON.generate(handles))
              model.set_attribute(DICT, 'job_handle_names', JSON.generate(names))
              Settings.set_job_hinge_type(hinge, model)
            end
          }]]
          work.each do |label, pairs, style, override|
            steps << ["Redrawing #{label}", lambda {
              r = step.call { Converter.rebuild(model, pairs, style, hinge_type: hinge, override: override, finish: false) }
              items += r[:items]
              notes.concat(r[:notes])
            }]
          end
          steps << ['Tags and colours', -> { step.call { Converter.finish(model) } }] unless work.empty?
          Steps.run(dlg, steps, done: lambda { |_r|
            dlg.execute_script("applied(#{JSON.generate('data' => data(model), 'items' => items, 'notes' => notes.uniq)})")
          }, fail: lambda { |e|
            Log.error('door style', e)
            dlg.execute_script("applied(#{JSON.generate('data' => data(model), 'error' => e.message)})")
          })
        end
        dlg.show
      end
    end
  end
end
