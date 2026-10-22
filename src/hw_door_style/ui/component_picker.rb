require 'json'

module HarryWardrobes
  module DoorStyle
    # Add component (+ button): picture cards of the latest library components, grouped and
    # colour coded by category, from the copy on this computer (LibraryCache). Click a card,
    # then click in the model to place it - like File > Import, without the file browser.
    #
    # Once placed, the unit is set up to this job in one quick step (merged into the place,
    # so one Undo takes it away): runouts / bottom facing as the pencil has them, the ceiling
    # height for "Scribed To Ceiling" units, the job's door style and hinges on its doors and
    # drawer fronts, and the job's colours. Only the new unit is touched - nothing else in the
    # model is scanned or redrawn, so it stays quick on older computers.
    module ComponentPicker
      ID = 'component_picker'.freeze
      PREF = 'picker_setup'.freeze
      KINDS = [:door, :ext_drawer, :int_drawer].freeze
      AUTO_SYNC_S = 600 # opening the window checks the library at most every 10 minutes

      def self.setup_on?
        Sketchup.read_default(Settings::PREFS, PREF, true) ? true : false
      end

      # What a placed unit will get, in words (top of the window).
      def self.job_summary(model)
        ch = Colours.job_choices(model).reject { |_k, v| v.nil? }
        styles = DoorStyleWindow.job_styles(model)
        c = Ceiling.mm(model)
        {
          'colours' => ch.empty? ? 'none chosen yet' : ch.map { |k, v| "#{k.tr('_', ' ')}: #{v}" }.join(', '),
          'doors' => Colours.door_colour_chosen?(model) ? "#{Styles.label(styles['door'])} doors, #{Styles.label(styles['ext_drawer'])} drawer fronts, #{Settings::HINGE_TYPES[Settings.job_hinge_type(model)] || 'job'} hinges" : 'not set - choose a Door colour first',
          'scribes' => Pencil.on?(model) ? "on (#{Runouts.job_values(model).map { |s, v| "#{s} #{v.round}" }.join(', ')})" : 'off (all 0)',
          'ceiling' => c.positive? ? "#{c.round} mm" : 'not set'
        }
      rescue StandardError => e
        Log.error('picker summary', e)
        {}
      end

      def self.data(model)
        { 'cards' => LibraryCache.cards, 'root' => LibraryCache.root, 'setup' => setup_on?, 'job' => job_summary(model),
          'cats' => LibraryCache::ORDER.map { |c| [c, LibraryCache.group_label(c), LibraryCache.colour(c)] } }
      end

      def self.show
        model = Sketchup.active_model
        dlg = Dialog.open(ID, title: 'Add component', key: 'hw_component_picker_v1', width: 780, height: 640,
                              data: data(model), utility: true)
        dlg.add_action_callback('ready') { |_c| sync(dlg) if @synced_at.nil? || Time.now - @synced_at > AUTO_SYNC_S }
        dlg.add_action_callback('sync') { |_c| sync(dlg) }
        dlg.add_action_callback('place') { |_c, key| place(dlg, key.to_s) }
        dlg.add_action_callback('setSetup') { |_c, on| Sketchup.write_default(Settings::PREFS, PREF, on ? true : false) }
        dlg.add_action_callback('openFolder') { |_c| UI.openURL("file:///#{LibraryCache.root}") }
        dlg.add_action_callback('job') { |_c| push(dlg, 'setJob', job_summary(Sketchup.active_model)) }
        dlg.show
        dlg
      end

      # A message: in the window if it's still open, else SketchUp's status bar.
      def self.tell(dlg, text)
        if dlg && dlg.visible?
          push(dlg, 'status', 'text' => text)
        else
          Sketchup.status_text = text
        end
      end

      def self.push(dlg, fn, o)
        dlg.execute_script("#{fn}(#{JSON.generate(o)})") if dlg && dlg.visible?
      rescue StandardError
        nil
      end

      # --- keeping the copy up to date (in the background) ------------------------

      def self.sync(dlg)
        return if @syncing
        @syncing = true
        idx = LibraryCache.index
        Steps.one(dlg, 'Checking the library for new versions...',
                  done: lambda { |scanned|
                    @synced_at = Time.now
                    get, gone = LibraryCache.plan(scanned, idx)
                    LibraryCache.forget(gone, idx)
                    LibraryCache.save_index(idx) unless gone.empty?
                    if get.empty?
                      @syncing = false
                      push(dlg, 'setCards', 'cards' => LibraryCache.cards(idx), 'note' => gone.empty? ? 'Up to date with the library.' : "#{gone.size} removed (no longer in the library).")
                      next
                    end
                    steps = get.map do |e|
                      ["Copying #{LibraryCache.pretty(e['name'])} V#{e['ver']} (#{(e['size'] / 1024.0 / 1024).round(1)} MB)", lambda {
                        LibraryCache.fetch(e, idx)
                        LibraryCache.save_index(idx)
                        push(dlg, 'setCards', 'cards' => LibraryCache.cards(idx))
                        e['key']
                      }]
                    end
                    Steps.run(dlg, steps,
                              done: lambda { |r|
                                @syncing = false
                                push(dlg, 'setCards', 'cards' => LibraryCache.cards(idx), 'note' => "#{r.size} updated from the library.")
                              },
                              fail: lambda { |err|
                                @syncing = false
                                LibraryCache.save_index(idx)
                                push(dlg, 'setCards', 'cards' => LibraryCache.cards(idx), 'note' => "Stopped copying: #{err.message}", 'warn' => true)
                              })
                  },
                  fail: lambda { |_err|
                    @syncing = false
                    push(dlg, 'setCards', 'cards' => LibraryCache.cards(idx), 'warn' => true,
                                          'note' => "Library folder not reachable - showing the copy on this computer. (#{LibraryCache.root})")
                  }, bg: true) { LibraryCache.scan }
      rescue StandardError => e
        @syncing = false
        Log.error('library sync', e)
      end

      # --- placing ----------------------------------------------------------------

      def self.place(dlg, key)
        model = Sketchup.active_model
        e = LibraryCache.index[key]
        unless e && File.exist?(e['file'].to_s)
          return tell(dlg, 'That component is not on this computer yet - press Check library.')
        end
        defn = model.definitions.load(e['file'])
        # Scribes on / off as the model is NOW (the new unit's own runouts mustn't decide it).
        # Not for a faceplate or anything else that isn't furniture - placed as it is.
        job = setup_on? && !LibraryCache.plain?(e['cat']) ? { 'runouts' => Runouts.expected(model), 'facing' => Facing.mm(model), 'ceiling' => Ceiling.mm(model), 'front' => DrawerFront.job(model) } : nil
        @watch&.stop
        @watch = PlaceWatch.new(model, defn, job, dlg, LibraryCache.pretty(e['name']))
        model.add_observer(@watch)
        # Out of the way so the model can be clicked; the result goes to SketchUp's status bar.
        # Closed first, then placed on the next tick with the model window in focus - placing
        # from inside the click left the window open on top and the model without focus.
        begin
          dlg&.close
        rescue StandardError
          nil
        end
        UI.start_timer(0.05, false) do
          Sketchup.focus if Sketchup.respond_to?(:focus)
          model.place_component(defn, false)
          Sketchup.status_text = "Click to place #{LibraryCache.pretty(e['name'])} (Esc to cancel)."
        end
      rescue StandardError => err
        Log.error('place component', err)
        UI.messagebox("Couldn't load that component: #{err.message}")
      end

      # Told when the component is put down; sets it up once, then stops listening.
      class PlaceWatch < Sketchup::ModelObserver
        def initialize(model, defn, job, dlg, label)
          super()
          @model, @defn, @job, @dlg, @label = model, defn, job, dlg, label
        end

        def onPlaceComponent(inst)
          return unless inst.is_a?(Sketchup::ComponentInstance) && inst.definition == @defn
          stop
          UI.start_timer(0, false) { ComponentPicker.after_place(@model, inst, @job, @dlg, @label) }
        end

        def stop
          @model.remove_observer(self)
        rescue StandardError
          nil
        end
      end

      def self.after_place(model, inst, job, dlg, label)
        return unless inst.valid?
        unless job
          return tell(dlg, "#{label} placed (not set up to the job - the tick is off).")
        end
        t = Time.now
        notes = []
        Ops.run(model, "Add #{label}", transparent: true) { notes = setup(model, inst, job) }
        tell(dlg, "#{label} placed and set up in #{(Time.now - t).round(1)} s: #{notes.join(', ')}.")
      rescue StandardError => e
        Log.error('set up placed component', e)
        UI.messagebox("#{label} was placed, but setting it up to the job failed:\n\n#{e.message}")
      end

      # The job's settings on one newly placed component (inside the caller's step).
      # Returns what was done, in words.
      # depth: a depth to use instead of the job's (Replace with keeps a changed depth);
      # redraw: true redraws every unit even when nothing here changed (options were set first).
      def self.setup(model, inst, job, depth: nil, redraw: false)
        done = []

        # 1. sizes: runouts, bottom facing, ceiling - then one redraw (ceiling redraws itself)
        units = Runouts.unit?(inst) || Facing.has?(inst) || Depth.has?(inst) || Midrail.has?(inst) || DrawerFront.has?(inst) ? [inst] : (Runouts.units(inst.definition.entities) | Facing.units(inst.definition.entities) | Depth.units(inst.definition.entities) | Midrail.units(inst.definition.entities) | DrawerFront.units(inst.definition.entities))
        units.each do |u|
          changed = redraw
          changed = Runouts.set(u, job['runouts']) || changed if Runouts.unit?(u)
          changed = Facing.set(u, job['facing']) || changed if Facing.has?(u)
          changed = Ceiling.set_worktop(u) || changed
          changed = Depth.set(u, depth || Depth.target(u, model)) || changed if Depth.has?(u)
          changed = Midrail.set(u, Midrail.job_values(model)) || changed if Midrail.has?(u)
          changed = DrawerFront.set(u, job['front'] || DrawerFront.job(model)) || changed if DrawerFront.has?(u)
          changed = false if job['ceiling'].to_f.positive? && Ceiling.apply_to(u, job['ceiling'])
          next unless changed
          Drawers.close(u.definition.entities)
          DC.redraw(u)
        end
        done << (job['runouts'].values.all?(&:zero?) ? 'scribes off' : 'runouts') unless units.empty?
        done << 'ceiling height' if job['ceiling'].to_f.positive? && units.any? { |u| Ceiling.up_to_ceiling?(u) }

        # 2. doors and drawer fronts: the job's style and hinges (needs the door colour, as the window does)
        pairs = Finder.targets([inst], KINDS)
        if pairs.any?
          if Colours.door_colour_chosen?(model)
            styles = DoorStyleWindow.job_styles(model)
            pairs.group_by { |_i, k| styles[k.to_s] }.each do |style, ps|
              Converter.rebuild(model, ps, style, override: false, finish: false)
            end
            door_tag = Tagger.tag_for(model, :door)
            pairs.each do |i, k|
              i.layer = door_tag if k == :door && i.layer != door_tag
              Tagger.tag_item(i, k)
            end
            Tagger.tag_hardware(model, definitions_in(inst))
            done << "#{pairs.size} door(s) / front(s) styled"
          else
            done << 'door style skipped (choose a Door colour first)'
          end
        end

        # 3. colours
        choices = Colours.job_choices(model).reject { |_k, v| v.nil? }
        unless choices.empty?
          Colours.apply(model, choices, root: inst, record: false)
          done << 'colours'
        end
        done
      end

      # Every definition used inside inst (for tagging its hardware only).
      def self.definitions_in(inst)
        seen = {}
        stack = [inst.definition]
        until stack.empty?
          d = stack.pop
          next if seen[d]
          seen[d] = true
          d.entities.each { |e| stack << e.definition if e.respond_to?(:definition) }
        end
        seen.keys
      end
    end
  end
end
