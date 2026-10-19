require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module HarryWardrobes
  module DoorStyle
    # HubSpot link (Settings > HubSpot).
    #
    # Uses a HubSpot private app key (the one Measure Once used). The key is kept
    # in SketchUp's own preferences on this computer only - never in settings.json,
    # settings backups or the team settings file - and is never shown again once saved.
    #
    # Every call: HTTPS with certificate checks, 15 s timeouts, and up to 3 tries when
    # HubSpot says "too many requests" (429) or has a hiccup (5xx), waiting longer each
    # time (the same rule Measure Once used).
    #
    # This first part only reads (connection test, which records the plugin can see,
    # the Room fields). Writing survey data comes later, after the field mapping is agreed.
    module HubSpot
      BASE = 'https://api.hubapi.com'.freeze
      PREF = 'hubspot_key'.freeze
      class Error < StandardError
        attr_reader :status
        def initialize(msg, status = nil)
          super(msg)
          @status = status
        end
      end

      # --- the key --------------------------------------------------------------

      def self.key
        Sketchup.read_default(Settings::PREFS, PREF, '').to_s.strip
      end

      def self.key?
        !key.empty?
      end

      def self.key=(value)
        Sketchup.write_default(Settings::PREFS, PREF, value.to_s.strip)
      end

      # "pat-eu1-…ab12" - enough to recognise the key, never the whole of it.
      def self.key_hint
        k = key
        k.empty? ? nil : "#{k[0, 8]}…#{k[-4..]}"
      end

      # --- requests ---------------------------------------------------------------

      def self.request(method, path, body = nil, tries: 3)
        raise Error, 'No HubSpot key saved (Settings > HubSpot).' unless key?
        uri = URI("#{BASE}#{path}")
        1.upto(tries) do |attempt|
          begin
            res = send_once(method, uri, body)
          rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET => e
            next sleep(attempt * 1.5) if attempt < tries
            raise Error, "Can't reach HubSpot (#{e.class.name.split('::').last}). Check the internet connection."
          end
          code = res.code.to_i
          next sleep(attempt * 1.5) if (code == 429 || code >= 500) && attempt < tries
          data = res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue { 'message' => res.body.to_s[0, 200] })
          raise Error.new(message_for(code, data), code) unless code.between?(200, 299)
          return data
        end
      end

      def self.send_once(method, uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 15
        http.read_timeout = 15
        req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
        req['Authorization'] = "Bearer #{key}"
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body) if body
        http.request(req)
      end

      def self.message_for(code, data)
        msg = data['message'].to_s
        case code
        when 401 then 'HubSpot did not accept the key (401). Check it was copied in full, or make a new one.'
        when 403 then "The key is missing a permission (403): #{msg[0, 160]}"
        when 404 then "Not found in HubSpot (404): #{msg[0, 120]}"
        else "HubSpot error #{code}: #{msg[0, 160]}"
        end
      end

      def self.get(path)
        request(:get, path)
      end

      # --- connection test -----------------------------------------------------------

      # What the plugin will need, and whether the key can do it.
      PROBES = [
        ['contacts', 'Contacts (customer name, address, folder)', '/crm/v3/objects/contacts?limit=1'],
        ['rooms',    'Rooms (Listings)',                           '/crm/v3/objects/listings?limit=1'],
        ['projects', 'Projects',                                   '/crm/v3/objects/projects?limit=1'],
        ['notes',    'Notes (to attach files)',                    '/crm/v3/objects/notes?limit=1'],
        ['files',    'Files (door order PDF, pictures)',           '/files/v3/files/search?limit=1']
      ].freeze

      # { 'portal' =>, 'region' =>, 'checks' => [{ id, label, ok, detail }] }
      def self.test
        info = get('/account-info/v3/details')
        checks = PROBES.map do |id, label, path|
          begin
            get(path)
            { 'id' => id, 'label' => label, 'ok' => true, 'detail' => 'OK' }
          rescue Error => e
            { 'id' => id, 'label' => label, 'ok' => false, 'detail' => e.status == 403 ? 'needs permission' : e.message }
          end
        end
        { 'portal' => info['portalId'], 'region' => info['dataHostingLocation'], 'checks' => checks }
      end

      # The Room (Listings) fields: [{ name, label, type, group }], HubSpot's own
      # system fields left out.
      def self.room_fields
        data = get('/crm/v3/properties/listings')
        Array(data['results']).reject { |p| p['hubspotDefined'] }.map do |p|
          { 'name' => p['name'], 'label' => p['label'], 'type' => p['type'], 'field' => p['fieldType'],
            'group' => p['groupName'], 'options' => Array(p['options']).map { |o| o['label'] } }
        end.sort_by { |p| [p['group'].to_s, p['label'].to_s] }
      end
    end
  end
end
