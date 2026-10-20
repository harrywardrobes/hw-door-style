module HarryWardrobes
  module DoorStyle
    # Customer and room for labels: one place, on the model (this plugin's dictionary):
    # customer_first, customer_last, room_id, room_name.
    #
    #   Filled from the HubSpot link when the file is linked (Room ID = the HubSpot Room record
    #   ID), else from the file path (...\1_CUSTOMERS\{Customer}\{Room}.skp): the customer
    #   folder gives the name ("WILLIAMS Rebecca (Rossett - 830735284436)" - surname in capitals
    #   first; otherwise the last word is the surname), the file name gives the room. The Room
    #   ID is then made up once - {SUR}{YYMMDD}{NN} - and kept, so it never changes (barcodes
    #   use it). The Labels tab shows the four fields to edit; they're saved back to the model.
    module JobInfo
      KEYS = %w[customer_first customer_last room_id room_name].freeze

      def self.read(model)
        KEYS.to_h { |k| [k, model.get_attribute(DICT, k).to_s] }
      end

      # The four fields, filling any that are empty (and keeping a made-up Room ID).
      def self.get(model)
        cur = read(model)
        guess = guessed(model)
        out = cur.to_h { |k, v| [k, v.strip.empty? ? guess[k].to_s : v] }
        save(model, 'room_id' => out['room_id']) if cur['room_id'].strip.empty? && !out['room_id'].empty? && !model.path.to_s.empty? &&
                                                     !(defined?(LibraryExport) && LibraryExport.master?(model))
        out.merge('customer' => customer_label(out['customer_first'], out['customer_last']))
      end

      def self.save(model, values)
        Ops.run(model, 'Customer / room for labels', transparent: true) do
          values.each { |k, v| model.set_attribute(DICT, k, v.to_s.strip) if KEYS.include?(k) }
        end
      end

      def self.guessed(model)
        l = (HubSpotRoom.link(model) rescue nil)
        if l
          first = l['first_name'].to_s
          last = l['last_name'].to_s
          first, last = split_name(l['customer']) if first.empty? && last.empty?
          return { 'customer_first' => first, 'customer_last' => last, 'room_id' => l['room_id'].to_s, 'room_name' => room_from_link(l['room_name']) }
        end
        path = model.path.to_s
        return { 'customer_first' => '', 'customer_last' => '', 'room_id' => '', 'room_name' => '' } if path.empty?
        folder = File.basename(File.dirname(path))
        first, last = split_name(folder)
        { 'customer_first' => first, 'customer_last' => last, 'room_name' => room_from_file(File.basename(path, '.skp')),
          'room_id' => new_room_id(last, File.dirname(path)) }
      end

      # "WILLIAMS Rebecca (Rossett - 830735284436)" -> ["Rebecca", "Williams"];
      # "Jane Smith" -> ["Jane", "Smith"]; "SMITH-JONES Mary Ann" -> ["Mary Ann", "Smith-Jones"].
      def self.split_name(s)
        words = s.to_s.sub(/\(.*\)\s*\z/, '').strip.split(/\s+/)
        return ['', ''] if words.empty?
        caps = words.take_while { |w| w =~ /[A-Z]/ && w == w.upcase && w =~ /\A[A-Z'\-]+\z/ }
        if !caps.empty? && caps.size < words.size
          [words.drop(caps.size).join(' '), caps.map { |w| title(w) }.join(' ')]
        elsif words.size == 1
          ['', title(words[0])]
        else
          [words[0..-2].join(' '), title(words[-1])]
        end
      end

      def self.title(w) = w.to_s.downcase.gsub(/(\A|[\s\-'])([a-z])/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).upcase}" }

      # "SURVEY - master bedroom - williams rebecca" -> "Master Bedroom"; else the file name.
      def self.room_from_file(base)
        parts = base.to_s.split(' - ')
        r = parts.size >= 3 ? parts[1] : base.to_s
        r == r.downcase ? title(r) : r
      end

      # "Kenny Hasprey - Connah's Quay - Master Bedroom" -> "Master Bedroom"
      def self.room_from_link(name)
        s = name.to_s.split(' - ').last.to_s.strip
        s.empty? ? name.to_s : s
      end

      # {SUR}{YYMMDD}{NN}: first three letters of the surname, today, and the number of
      # SketchUp files in the customer's folder (so two rooms made the same day differ).
      def self.new_room_id(surname, folder = nil, time = Time.now)
        sur = surname.to_s.upcase.gsub(/[^A-Z]/, '')[0, 3]
        sur = 'XXX' if sur.empty?
        n = folder && Dir.exist?(folder) ? Dir.children(folder).count { |f| f =~ /\.skp\z/i } : 1
        format('%s%s%02d', sur.ljust(3, 'X'), time.strftime('%y%m%d'), [n, 1].max % 100)
      end

      # Labels: "SMITH JA" - surname in capitals, then the first-name initials (no dots).
      # Double-barrelled / hyphenated surnames stay whole; hyphenated first names give an
      # initial for each part ("Mary-Jane" -> "MJ").
      def self.customer_label(first, last)
        sur = last.to_s.strip.upcase.gsub(/\s+/, ' ')
        initials = first.to_s.strip.split(/[\s\-]+/).map { |w| w[/[[:alpha:]]/].to_s.upcase }.join
        [sur, initials].reject(&:empty?).join(' ')
      end
    end
  end
end
