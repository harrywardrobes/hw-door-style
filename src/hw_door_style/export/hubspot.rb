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

      # Read once on SketchUp's thread and kept (requests run on a background thread, which
      # mustn't call SketchUp); saving a new key replaces it.
      def self.key
        @key ||= Sketchup.read_default(Settings::PREFS, PREF, '').to_s.strip
      end

      def self.key?
        !key.empty?
      end

      def self.key=(value)
        Sketchup.write_default(Settings::PREFS, PREF, value.to_s.strip)
        @key = value.to_s.strip
      end

      # "pat-eu1-…ab12" - enough to recognise the key, never the whole of it.
      def self.key_hint
        k = key
        k.empty? ? nil : "#{k[0, 8]}…#{k[-4..]}"
      end

      # --- requests ---------------------------------------------------------------

      # Network hiccups worth another try. Some networks / security software drop a share
      # of NEW connections straight away (ECONNRESET), so one connection is kept open and
      # reused, and a dropped one is reopened and the call tried again.
      NET_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, IOError,
                    Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
                    OpenSSL::SSL::SSLError].freeze

      def self.request(method, path, body = nil, tries: 3)
        raise Error, 'No HubSpot key saved (Settings > HubSpot).' unless key?
        uri = URI("#{BASE}#{path}")
        perform(tries) do
          req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
          req['Content-Type'] = 'application/json'
          req.body = JSON.generate(body) if body
          req
        end
      end

      # Sends the request the block builds (a new one each try) on the shared connection.
      # Returns the parsed JSON; raises HubSpot::Error with a plain-English message.
      def self.perform(tries = 3, read_timeout: 20)
        1.upto(tries) do |attempt|
          begin
            req = yield
            req['Authorization'] = "Bearer #{key}"
            res = connection(read_timeout).request(req)
          rescue *NET_ERRORS => e
            drop_connection
            next sleep(attempt < 3 ? 0.3 : attempt * 1.0) if attempt < tries
            raise Error, "Can't reach HubSpot (#{e.class.name.split('::').last}). Check the internet connection."
          end
          code = res.code.to_i
          next sleep(attempt * 1.5) if (code == 429 || code >= 500) && attempt < tries
          data = res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue { 'message' => res.body.to_s[0, 200] })
          raise Error.new(message_for(code, data), code) unless code.between?(200, 299)
          return data
        end
      end

      def self.connection(read_timeout = 30)
        if @http.nil? || !@http.started?
          uri = URI(BASE)
          @http = Net::HTTP.new(uri.host, uri.port)
          @http.use_ssl = true
          @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          @http.open_timeout = 10
          @http.keep_alive_timeout = 30
          @http.start
        end
        @http.read_timeout = read_timeout
        @http
      end

      def self.drop_connection
        @http&.finish
      rescue StandardError
        nil
      ensure
        @http = nil
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
        ['files',    'Files (door order PDF, pictures)',           '/files/v3/files/search?limit=1'],
        ['owners',   'Users (Installer / Surveyor fields)',        '/crm/v3/owners?limit=1'],
        ['products', 'Products (handles and hardware)',            '/crm/v3/objects/products?limit=1']
      ].freeze

      # { 'portal' =>, 'region' =>, 'checks' => [{ id, label, ok, detail }] }
      def self.test
        info = get('/account-info/v3/details')
        { 'portal' => info['portalId'], 'region' => info['dataHostingLocation'], 'checks' => PROBES.map { |pr| probe(*pr) } }
      end

      def self.probe(id, label, path)
        get(path)
        { 'id' => id, 'label' => label, 'ok' => true, 'detail' => 'OK' }
      rescue Error => e
        { 'id' => id, 'label' => label, 'ok' => false, 'detail' => e.status == 403 ? 'needs permission' : e.message }
      end

      def self.post(path, body)
        request(:post, path, body)
      end

      def self.patch(path, body)
        request(:patch, path, body)
      end

      # Portal number and region, read once per SketchUp session (for record links).
      def self.account
        @account ||= get('/account-info/v3/details')
      end

      TYPE_IDS = { 'listings' => '0-420', 'projects' => '0-970', 'contacts' => '0-1' }.freeze

      # Link to a record in the HubSpot app ('listings' = Rooms, 'projects').
      def self.record_url(type, id)
        a = account
        host = a['uiDomain'] || (a['dataHostingLocation'].to_s.start_with?('eu') ? 'app-eu1.hubspot.com' : 'app.hubspot.com')
        "https://#{host}/contacts/#{a['portalId']}/record/#{TYPE_IDS.fetch(type)}/#{id}"
      end

      def self.room_url(room_id)
        record_url('listings', room_id)
      end

      # HubSpot users, for the Installer / Surveyor fields: [[name, id]].
      # Needs the key's crm.objects.owners.read permission.
      def self.owners
        Array(get('/crm/v3/owners?limit=100')['results']).map do |o|
          [[o['firstName'], o['lastName']].compact.join(' ').strip.then { |n| n.empty? ? o['email'].to_s : n }, o['id'].to_s]
        end
      end

      # --- records -----------------------------------------------------------------

      # Projects matching the text - by project name, or through one of its Room names
      # (some projects are named by address): [{ 'id', 'name' }], newest first.
      def self.search_projects(text, limit: 25)
        q = text.to_s.strip
        found = search('projects', q, limit)
        unless q.empty?
          room_ids = search('listings', q, limit).map { |r| r['id'] }
          extra = linked_many('listings', room_ids, 'projects').values.flatten.uniq - found.map { |r| r['id'] }
          found += read_many('projects', extra, %w[hs_name hs_lastmodifieddate])
        end
        found.uniq { |r| r['id'] }
             .sort_by { |r| r.dig('properties', 'hs_lastmodifieddate').to_s }.reverse
             .map { |r| { 'id' => r['id'], 'name' => r.dig('properties', 'hs_name').to_s } }
      end

      def self.search(type, q, limit)
        body = { limit: limit, properties: %w[hs_name hs_lastmodifieddate],
                 sorts: [{ propertyName: 'hs_lastmodifieddate', direction: 'DESCENDING' }] }
        body[:query] = q unless q.empty?
        Array(post("/crm/v3/objects/#{type}/search", body)['results'])
      end

      # { from id => [linked ids] } for several records in one call.
      def self.linked_many(from_type, ids, to_type)
        return {} if ids.empty?
        res = post("/crm/v4/associations/#{from_type}/#{to_type}/batch/read", { inputs: ids.map { |i| { id: i } } })
        Array(res['results']).to_h { |r| [r.dig('from', 'id').to_s, Array(r['to']).map { |t| t['toObjectId'].to_s }] }
      end

      # Ids of records of another type linked to this one.
      def self.linked_ids(from_type, id, to_type)
        Array(get("/crm/v4/objects/#{from_type}/#{id}/associations/#{to_type}?limit=100")['results']).map { |r| r['toObjectId'].to_s }
      end

      # Several records at once: [{ 'id', 'properties' }].
      def self.read_many(type, ids, props)
        return [] if ids.empty?
        Array(post("/crm/v3/objects/#{type}/batch/read", { inputs: ids.map { |i| { id: i } }, properties: props })['results'])
      end

      def self.read_one(type, id, props)
        get("/crm/v3/objects/#{type}/#{id}?properties=#{props.join(',')}")
      end

      # Room pipeline stages in order: [{ 'id', 'label', 'pipeline' }] (cached for the session).
      def self.room_stages
        @stages ||= Array(get('/crm/v3/pipelines/listings')['results']).sort_by { |p| p['displayOrder'].to_i }.flat_map do |p|
          Array(p['stages']).sort_by { |st| st['displayOrder'].to_i }.map { |st| { 'id' => st['id'], 'label' => st['label'], 'pipeline' => p['label'] } }
        end
      end

      # Uploads one picture to HubSpot's file manager; returns its file id.
      # Same folder as a file added on the Room card in HubSpot; private (signed-in users only).
      def self.upload(path, folder)
        upload_file(path, folder)['id'].to_s
      end

      # One file to HubSpot's file manager; returns HubSpot's file record (id, url...).
      # PRIVATE: only signed-in HubSpot users can open it (HIDDEN_PRIVATE, which HubSpot
      # itself uses for record files, is refused through the API as "Invalid JSON").
      # PUBLIC_NOT_INDEXABLE: anyone with the link (product pictures).
      def self.upload_file(path, folder, access: 'PRIVATE')
        raise Error, 'No HubSpot key saved (Settings > HubSpot).' unless key?
        uri = URI("#{BASE}/files/v3/files")
        opts = JSON.generate(access: access)
        data = nil
        File.open(path, 'rb') do |io|
          data = perform(5, read_timeout: 120) do
            io.rewind
            req = Net::HTTP::Post.new(uri)
            req.set_form([['file', io, { filename: File.basename(path) }], ['folderPath', folder.to_s], ['options', opts]], 'multipart/form-data')
            req
          end
        end
        data
      end

      def self.update_room(id, props)
        props = HubSpotRoom.to_values(props) if defined?(HubSpotRoom)
        patch("/crm/v3/objects/listings/#{id}", { properties: props })
      end

      # Options of a dropdown Room field: [[label, value]] (cached for the session).
      def self.options(field)
        (@options ||= {})[field] ||= Array(get("/crm/v3/properties/listings/#{field}")['options']).reject { |o| o['hidden'] }.map { |o| [o['label'], o['value']] }
      end

      def self.forget_cache!
        @options = nil
        @account = nil
        @stages = nil
      end

      # The Room (Listings) fields: [{ name, label, type, group }], HubSpot's own
      # system fields left out.
      def self.room_fields
        data = get('/crm/v3/properties/listings')
        Array(data['results']).reject { |p| p['hubspotDefined'] }.map do |p|
          { 'name' => p['name'], 'label' => p['label'], 'type' => p['type'], 'field' => p['fieldType'],
            'group' => p['groupName'], 'options' => Array(p['options']).reject { |o| o['hidden'] }.map { |o| o['label'] } }
        end.sort_by { |p| [p['group'].to_s, p['label'].to_s] }
      end
    end
  end
end
