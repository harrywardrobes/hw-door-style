module HarryWardrobes
  module DoorStyle
    # Workshop > Survey: the Room's survey questions, read from HubSpot and saved back to it.
    #
    #   Questions  Settings > HubSpot > Survey questions: HubSpot Room field names, in order
    #              (pick more from the Room's fields, or make a new one in HubSpot there).
    #   Values     read from the linked Room each time the tab opens; Save sends only the ones
    #              you changed. A design visit has no Room yet, so nothing to sync.
    module Survey
      DEFAULT = %w[type_of_flooring flooring_requirements flooring_requirement_notes bed_requirements bed_requirement_notes
                   cutting_location cutting_location_notes internal_sides internal_sides_description notes].freeze

      def self.fields
        f = Array(Settings.get['survey_questions']).map { |x| x.to_s.strip }.reject(&:empty?)
        f.empty? ? DEFAULT.dup : f
      end

      # { linked, room, url, questions: [{ name, label, field, type, options, value, readonly }], missing }
      def self.data(model)
        l = HubSpotRoom.link(model)
        return { 'linked' => false, 'design_visit' => HubSpotRoom.design_visit?(model) } unless l
        m = HubSpotRoom.meta
        names = fields.select { |n| m[n] }
        theirs = names.empty? ? {} : (HubSpot.read_one('listings', l['room_id'], names)['properties'] || {})
        qs = names.map do |n|
          d = m[n]
          opts = d['options'].dup
          # an answer that has since been archived in HubSpot: still shown (marked) when it's the current one
          Array(theirs[n]).join.split(';').each do |cv|
            next if cv.empty? || opts.any? { |_l, v| v == cv }
            old = Array(d['all_options']).find { |_l, v| v == cv }
            opts << ["#{old ? old[0] : cv} (archived)", cv] if old
          end
          { 'name' => n, 'label' => d['label'], 'type' => d['type'], 'field' => d['field'], 'options' => opts,
            'readonly' => d['readonly'], 'value' => theirs[n] }
        end
        { 'linked' => true, 'room' => l['room_name'], 'questions' => qs, 'missing' => fields - names }
      end

      # Sends the changed answers. values: { name => value } (only known, writable fields).
      def self.save(model, values)
        l = HubSpotRoom.link(model) or raise 'Link this file to a HubSpot Room first.'
        m = HubSpotRoom.meta
        props = values.select { |k, _| m[k] && !m[k]['readonly'] }.transform_values { |v| v.nil? ? '' : v.to_s }
        HubSpot.update_room(l['room_id'], props) unless props.empty?
        props.size
      end

      # The Room's fields to pick from in Settings: [[name, label]].
      def self.available
        HubSpotRoom.meta.reject { |_n, d| d['readonly'] || d['hidden'] }.map { |n, d| [n, d['label'].to_s] }.sort_by { |_n, l| l.downcase }
      end

      KINDS = {
        'text' => %w[string text], 'paragraph' => %w[string textarea], 'number' => %w[number number],
        'dropdown' => %w[enumeration select], 'checkboxes' => %w[enumeration checkbox],
        'yesno' => %w[bool booleancheckbox], 'date' => %w[date date]
      }.freeze

      def self.slug(label)
        s = label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
        s = "q_#{s}" if s =~ /\A\d/
        s[0, 60]
      end

      # Makes a new question on the HubSpot Room (in the survey questions' group) and adds it
      # to the list. kind: one of KINDS; options: labels for dropdown / checkboxes.
      def self.create(label, kind, options)
        type, field = KINDS.fetch(kind) { raise "Unknown kind #{kind}" }
        name = slug(label)
        raise 'Give the question a name.' if name.empty?
        m = HubSpotRoom.meta
        raise "HubSpot already has a Room field \"#{name}\" - pick it from the list instead." if m[name]
        group = fields.filter_map { |n| m[n] && m[n]['group'] }.first || 'listinginformation'
        body = { name: name, label: label.to_s.strip, type: type, fieldType: field, groupName: group }
        if type == 'bool'
          body[:options] = [{ label: 'Yes', value: 'true', displayOrder: 0 }, { label: 'No', value: 'false', displayOrder: 1 }]
        elsif type == 'enumeration'
          opts = Array(options).map { |o| o.to_s.strip }.reject(&:empty?)
          raise 'Add the answers to choose from.' if opts.empty?
          body[:options] = opts.each_with_index.map { |o, i| { label: o, value: slug(o), displayOrder: i } }
        end
        HubSpot.post('/crm/v3/properties/listings', body)
        HubSpotRoom.forget_meta!
        name
      end
    end
  end
end
