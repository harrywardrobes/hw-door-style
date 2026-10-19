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
      def self.run(dlg, steps, done: nil, fail: nil, count: true)
        results = []
        total = steps.size
        i = 0
        tick = lambda do
          if i >= total
            busy(dlg, nil)
            next done&.call(results)
          end
          label, work = steps[i]
          busy(dlg, { 'text' => label, 'done' => i, 'total' => count ? total : 0 })
          UI.start_timer(0.03, false) do
            begin
              results << work.call
              i += 1
              tick.call
            rescue StandardError => e
              busy(dlg, nil)
              Log.error('steps', e) unless defined?(HubSpot::Error) && e.is_a?(HubSpot::Error)
              fail ? fail.call(e) : UI.messagebox("#{label} failed.\n\n#{e.message}")
            end
          end
        end
        tick.call
      end

      # One slow job with a moving bar (no count).
      def self.one(dlg, label, done: nil, fail: nil, &work)
        run(dlg, [[label, work]], done: ->(r) { done&.call(r.first) }, fail: fail, count: false)
      end

      def self.busy(dlg, o)
        dlg.execute_script("hwBusy(#{JSON.generate(o)})") if dlg && dlg.visible?
      rescue StandardError
        nil
      end
    end
  end
end
