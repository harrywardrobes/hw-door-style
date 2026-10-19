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
      # Raised when a step would open inside a throwaway step: SketchUp would
      # commit the outer step instead of undoing it.
      class NestedStep < StandardError; end

      def self.run(model, name, transparent: false)
        raise NestedStep, "'#{name}' would commit the test / export step it is inside" if @throwaway
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
      # Ops.run inside it raises NestedStep (instead of silently committing).
      def self.throwaway(model, name)
        raise NestedStep, "'#{name}' inside '#{@throwaway}'" if @throwaway
        model.start_operation(name, true)
        @throwaway = name
        begin
          yield
        ensure
          @throwaway = nil
          model.abort_operation
        end
      end

      def self.in_throwaway?
        @throwaway ? true : false
      end
    end
  end
end
