require 'json'

module HarryWardrobes
  module DoorStyle
    # Slow work in an open window (HubSpot calls, making pictures) done one step per
    # timer tick, with the window's busy bar (hwBusy in html/hw.js) showing each step.
    # Between steps SketchUp handles its messages, so neither SketchUp nor the window
    # shows "Not Responding".
    #
    #   Steps.run(dlg, [['Reading the Room', -> { ... }], ...],
    #             done: ->(results) { ... }, fail: ->(error) { ... })
    #
    # A step's result goes into results (in order). An error stops the rest, hides the
    # bar and calls fail (or shows a message box).
    module Steps
      # A step is [label, work] (runs on SketchUp's thread - anything touching the model or a
      # window), or [label, work, :bg, after] - work runs on a background thread (network,
      # files: it must not touch the model or a window) while SketchUp and the window carry on
      # responding; after (optional) then gets its result on SketchUp's thread.
      def self.run(dlg, steps, done: nil, fail: nil, count: true)
        results = []
        total = steps.size
        i = 0
        tick = nil
        failed = lambda do |label, e|
          busy(dlg, nil)
          Log.error('steps', e) unless defined?(HubSpot::Error) && e.is_a?(HubSpot::Error)
          fail ? fail.call(e) : UI.messagebox("#{label} failed.\n\n#{e.message}")
        end
        advance = lambda do |r|
          results << r
          i += 1
          tick.call
        end
        tick = lambda do
          if i >= total
            busy(dlg, nil)
            next done&.call(results)
          end
          label, work, mode, after = steps[i]
          busy(dlg, { 'text' => label, 'done' => i, 'total' => count ? total : 0 })
          if mode == :bg
            background(work) do |ok, r|
              begin
                ok ? advance.call(after ? after.call(r) : r) : failed.call(label, r)
              rescue StandardError => e
                failed.call(label, e)
              end
            end
          else
            UI.start_timer(0.03, false) do
              begin
                advance.call(work.call)
              rescue StandardError => e
                failed.call(label, e)
              end
            end
          end
        end
        tick.call
      end

      # Runs work on a thread; then (on SketchUp's thread) yields [true, result] or
      # [false, error]. SketchUp only lets a Ruby thread run while Ruby is busy, so a short
      # timer keeps handing it time (join with a few ms) - the window and the model stay usable.
      def self.background(work, &finish)
        HubSpot.key if defined?(HubSpot) # read once here - a thread mustn't call SketchUp
        thr = Thread.new do
          Thread.current.report_on_exception = false
          begin
            [true, work.call]
          rescue StandardError => e
            [false, e] # handed back as a value: join would otherwise raise it into the timer
          end
        end
        busy_tick = false
        timer = nil
        timer = UI.start_timer(0.02, true) do
          next if busy_tick
          busy_tick = true
          begin
            next if thr.join(0.008).nil? # still working
            UI.stop_timer(timer)
            finish.call(*thr.value)
          ensure
            busy_tick = false
          end
        end
        timer
      end

      # Background work with no window: a moving status-bar message, then done / fail.
      def self.bg(label, done: nil, fail: nil, &work)
        Sketchup.status_text = "#{label}..."
        background(work) do |ok, r|
          Sketchup.status_text = ''
          ok ? done&.call(r) : (fail ? fail.call(r) : Log.error(label, r))
        end
      end

      # One slow job with a moving bar (no count).
      def self.one(dlg, label, done: nil, fail: nil, bg: false, &work)
        run(dlg, [bg ? [label, work, :bg] : [label, work]], done: ->(r) { done&.call(r.first) }, fail: fail, count: false)
      end

      def self.busy(dlg, o)
        dlg.execute_script("hwBusy(#{JSON.generate(o)})") if dlg && dlg.visible?
      rescue StandardError
        nil
      end
    end
  end
end
