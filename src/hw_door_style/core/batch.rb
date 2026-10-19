require 'json'

module HarryWardrobes
  module DoorStyle
    # Works through a list one item per timer tick with a progress window, so
    # SketchUp stays responsive and the bar moves. All the work is ONE undo
    # step: the first item opens it, the rest are merged in (transparent).
    #
    #   Batch.run(model, units, 'Scribes on', done: 'Scribes on.') do |unit|
    #     ...change one unit...     # an error here is listed, the rest carry on
    #   end
    #
    # before: runs inside the same undo step, before the first item.
    # The pencil check is held while a batch runs (see Pencil.hold).
    module Batch
      def self.running?
        @running ? true : false
      end

      def self.run(model, items, title, done: nil, before: nil, label: ->(i) { Finder.label(i) }, &work)
        return false if running?
        @running = true
        Pencil.hold
        dlg = progress_window(title)
        queue = items.dup
        total = queue.size
        n = 0
        errors = []
        first = true
        tick = lambda do
          item = queue.shift
          return finish(dlg, total, done, errors) if item.nil?
          dlg.execute_script("progress(#{n}, #{total}, #{JSON.generate("Updating #{label.call(item)}...")})")
          UI.start_timer(0.02, false) do
            Ops.run(model, title, transparent: !first) do
              if first
                before&.call
                first = false
              end
              begin
                work.call(item)
              rescue StandardError => e
                errors << "#{label.call(item)}: #{e.message}"
                Log.error("#{title} - #{label.call(item)}", e)
              end
            end
            n += 1
            tick.call
          rescue StandardError => e
            # Something outside an item failed (e.g. the window was closed): stop cleanly.
            stop
            Log.error("#{title} stopped", e)
          end
        end
        tick.call
        true
      end

      def self.finish(dlg, total, done, errors)
        stop
        dlg.execute_script("progress(#{total}, #{total}, 'Done')")
        UI.start_timer(0.4, false) { dlg.close }
        msg = done.to_s
        msg += "\n\nCould not update:\n" + errors.join("\n") unless errors.empty?
        Sketchup.status_text = msg.lines.first.to_s
        UI.messagebox(msg) unless errors.empty?
      end

      def self.stop
        @running = false
        Pencil.release
      end

      def self.progress_window(title)
        d = Dialog.open('progress', title: title, key: 'hw_scribe_progress', width: 420, height: 150,
                                    resizable: false, scrollable: false, utility: true)
        d.show
        d
      end
    end
  end
end
