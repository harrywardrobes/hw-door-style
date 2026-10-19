module HarryWardrobes
  module DoorStyle
    # Ruby Console messages, all prefixed "HW Door Style" so they are easy to
    # find. Log.debug only prints with the developer switch on:
    #   Sketchup.write_default('HW Door Style', 'debug', true)
    module Log
      PREFIX = 'HW Door Style'.freeze

      def self.info(msg)
        puts "#{PREFIX}: #{msg}"
      end

      # where: what was running ("scribe", "export"); e: the exception.
      def self.error(where, e)
        trace = Array(e.backtrace).first(5).join("\n  ")
        puts "#{PREFIX} #{where}: #{e.class}: #{e.message}\n  #{trace}"
      end

      def self.debug(msg)
        puts "#{PREFIX} [debug]: #{msg}" if debug?
      end

      def self.debug?
        defined?(Sketchup) && Sketchup.respond_to?(:read_default) ? Sketchup.read_default(PREFIX, 'debug', false) == true : false
      end
    end
  end
end
