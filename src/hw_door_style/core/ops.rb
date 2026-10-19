module HarryWardrobes
  module DoorStyle
    # Undo steps. Every change to the model goes through Ops.run so a failure
    # part-way is always undone and an operation is never left open.
    #
    #   Ops.run(model, 'Apply colours') { Colours.apply(model, choices) }
    #
    # Messages and other UI belong after Ops.run returns, never inside it:
    # an error in a message box must not undo work that already succeeded.
    module Ops
      # Runs the block as one undo step and returns its result. If the block
      # raises, the step is undone and the error re-raised for the caller.
      # transparent: true merges this step into the previous one (one Ctrl+Z).
      def self.run(model, name, transparent: false)
        model.start_operation(name, true, false, transparent)
        begin
          result = yield
        rescue Exception # rubocop:disable Lint/RescueException - never leave the step open
          model.abort_operation
          raise
        end
        model.commit_operation
        result
      end

      # Runs the block in a step that is always undone afterwards - for work
      # on a temporary state (e.g. Export components saves a cleaned copy).
      def self.throwaway(model, name)
        model.start_operation(name, true)
        begin
          yield
        ensure
          model.abort_operation
        end
      end
    end
  end
end
