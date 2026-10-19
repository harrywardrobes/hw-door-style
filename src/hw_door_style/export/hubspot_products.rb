require 'json'
require 'fileutils'

module HarryWardrobes
  module DoorStyle
    # Products (handles and other hardware), kept in HubSpot's Products and edited in
    # Settings > Products. A copy of the list is kept on this computer (products.json in
    # the settings folder) so the Door style window works without the internet.
    #
    # HubSpot product fields used:
    #   name, hs_sku, price (what you charge), hs_cost_of_goods_sold (what you pay),
    #   hs_url (supplier product link), hs_product_type (inventory / non-inventory / service),
    #   hs_images (picture link), supplier and product_category (made by the plugin).
    module HubSpotProducts
      FILE = File.join(Settings::USER_DIR, 'products.json')
      PROPS = %w[name hs_sku price hs_cost_of_goods_sold hs_url hs_product_type hs_images description
                 supplier product_category].freeze

      SUPPLIERS = %w[Integral HPP Interfit].freeze
      CATEGORIES = ['Robe handle', 'Drawer handle', 'Interior handle', 'Hinge', 'TIP-ON', 'Drawer box',
                    'Drawer runner', 'Mirror', 'Cable outlet', 'Other hardware'].freeze

      # Which category fills which handle dropdown in the Door style window.
      HANDLE_CATEGORY = {
        'main_robe_handle' => 'Robe handle', 'drawer_handle' => 'Drawer handle', 'interior_handle' => 'Interior handle'
      }.freeze

      # The plugin's own fields: product Supplier / Category, and a supplier per handle on the Room.
      ROOM_SUPPLIER = {
        'main_robe_handle' => ['robe_handle_supplier', 'Robe Handle Supplier'],
        'drawer_handle' => ['drawer_handle_supplier', 'Drawer Handle Supplier'],
        'interior_handle' => ['interior_handle_supplier', 'Interior Handle Supplier']
      }.freeze

      def self.slug(label)
        label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
      end

      def self.options_for(labels)
        labels.each_with_index.map { |l, i| { label: l, value: slug(l), displayOrder: i } }
      end

      # Makes the fields if they aren't there yet (never changes existing ones, so options
      # added in HubSpot stay). Returns the names made.
      def self.ensure_fields
        made = []
        have = HubSpot.get('/crm/v3/properties/products')['results'].map { |p| p['name'] }
        unless have.include?('supplier')
          HubSpot.post('/crm/v3/properties/products', { name: 'supplier', label: 'Supplier', type: 'enumeration', fieldType: 'select',
                                                        groupName: 'productinformation', options: options_for(SUPPLIERS),
                                                        description: 'Who we order it from (HW Door Style)' })
          made << 'Product: Supplier'
        end
        unless have.include?('product_category')
          HubSpot.post('/crm/v3/properties/products', { name: 'product_category', label: 'Category', type: 'enumeration', fieldType: 'checkbox',
                                                        groupName: 'productinformation', options: options_for(CATEGORIES),
                                                        description: 'Where it can be chosen in SketchUp (HW Door Style)' })
          made << 'Product: Category'
        end
        rooms = HubSpot.get('/crm/v3/properties/listings')['results'].map { |p| p['name'] }
        sup = supplier_options
        ROOM_SUPPLIER.each_value do |name, label|
          next if rooms.include?(name)
          HubSpot.post('/crm/v3/properties/listings', { name: name, label: label, type: 'enumeration', fieldType: 'select',
                                                        groupName: 'listing_information', description: 'Filled from the product (HW Door Style)',
                                                        options: sup.each_with_index.map { |(l, v), i| { label: l, value: v, displayOrder: i } } })
          made << "Room: #{label}"
        end
        HubSpotRoom.forget_meta! if made.any? { |x| x.start_with?('Room') }
        made
      end

      # [[label, value]] of HubSpot's product Supplier dropdown (as edited in HubSpot).
      def self.supplier_options
        Array(HubSpot.get('/crm/v3/properties/products/supplier')['options']).map { |o| [o['label'], o['value']] }
      rescue HubSpot::Error
        SUPPLIERS.map { |l| [l, slug(l)] }
      end

      def self.field_options
        {
          'suppliers' => supplier_options,
          'categories' => (Array(HubSpot.get('/crm/v3/properties/products/product_category')['options']).map { |o| [o['label'], o['value']] } rescue CATEGORIES.map { |l| [l, slug(l)] }),
          'types' => (Array(HubSpot.get('/crm/v3/properties/products/hs_product_type')['options']).map { |o| [o['label'], o['value']] } rescue [['Inventory', 'inventory'], ['Non-inventory', 'non_inventory'], ['Service', 'service']])
        }
      end

      # Every product from HubSpot -> the local copy. Returns the list.
      def self.refresh!
        list = []
        after = nil
        loop do
          q = "/crm/v3/objects/products?limit=100&archived=false&properties=#{PROPS.join(',')}"
          q += "&after=#{after}" if after
          r = HubSpot.get(q)
          list.concat(Array(r['results']).map { |x| x['properties'].slice(*PROPS).merge('id' => x['id']) })
          after = r.dig('paging', 'next', 'after')
          break unless after
        end
        opts = field_options
        save_local('products' => list.sort_by { |p| p['name'].to_s.downcase }, 'options' => opts, 'at' => Time.now.strftime('%d/%m/%Y %H:%M'))
        local
      end

      def self.local
        File.exist?(FILE) ? JSON.parse(File.read(FILE, encoding: 'UTF-8')) : { 'products' => [], 'options' => {} }
      rescue StandardError
        { 'products' => [], 'options' => {} }
      end

      def self.save_local(data)
        FileUtils.mkdir_p(File.dirname(FILE))
        File.write(FILE, JSON.pretty_generate(data))
      end

      def self.products
        Array(local['products'])
      end

      # Products in a category (by its label, e.g. "Robe handle").
      def self.in_category(label)
        v = slug(label)
        products.select { |p| p['product_category'].to_s.split(';').include?(v) }
      end

      def self.find(id)
        products.find { |p| p['id'].to_s == id.to_s }
      end

      def self.supplier_label(value)
        hit = Array(local.dig('options', 'suppliers')).find { |_l, v| v == value.to_s }
        hit ? hit[0] : value.to_s
      end

      # Creates or updates one product. form: the window's fields; image: a local picture
      # file to upload first (link-viewable, not indexed). Returns the saved product.
      def self.save(form, image = nil)
        props = form.slice(*PROPS).reject { |k, _| k == 'hs_images' }.transform_values { |v| v.is_a?(Array) ? v.join(';') : v.to_s.strip }
        if image && File.exist?(image)
          up = HubSpot.upload_file(image, '/products', access: 'PUBLIC_NOT_INDEXABLE')
          props['hs_images'] = up['url'].to_s
        end
        id = form['id'].to_s
        r = id.empty? ? HubSpot.post('/crm/v3/objects/products', { properties: props }) : HubSpot.patch("/crm/v3/objects/products/#{id}", { properties: props })
        saved = r['properties'].to_h.slice(*PROPS).merge('id' => r['id'])
        data = local
        data['products'] = Array(data['products']).reject { |p| p['id'].to_s == saved['id'].to_s } + [saved]
        data['products'].sort_by! { |p| p['name'].to_s.downcase }
        save_local(data)
        saved
      end
    end
  end
end
