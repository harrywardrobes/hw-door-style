require 'json'

module HarryWardrobes
  module DoorStyle
    # Hardware products (Extensions > HW Door Style > HubSpot > Hardware products): the
    # handles and other hardware kept in HubSpot's Products. Every save goes straight to
    # HubSpot - nothing is kept in the plugin's settings.
    module ProductsWindow
      def self.show
        dlg = Dialog.open('products', title: 'HW Door Style - Hardware products', key: 'hw_door_style_products_v1',
                                      width: 820, height: 600, data: { '_products' => ProductImages.with_images(HubSpotProducts.local) })
        dlg.add_action_callback('prodLoad') do |_c|
          made = []
          Steps.run(dlg, [['Checking the Supplier and Category fields', -> { HubSpotProducts.ensure_fields }, :bg, ->(r) { made = r }],
                          ['Reading products from HubSpot', -> { HubSpotProducts.refresh! }, :bg]],
                    done: lambda { |_r|
                      dlg.execute_script("prodList(#{JSON.generate('data' => ProductImages.with_images(HubSpotProducts.local), 'made' => made)})")
                      ProductImages.sync(dlg, HubSpotProducts.products)
                    },
                    fail: ->(e) { dlg.execute_script("prodList(#{JSON.generate('error' => e.message)})") })
        end
        dlg.add_action_callback('prodImport') { |_c| SupplierImport.show }
        dlg.add_action_callback('prodPickImage') do |_c|
          f = UI.openpanel('Picture of the product', nil, 'Images|*.jpg;*.jpeg;*.png;*.webp||')
          next unless f
          ext = File.extname(f).downcase.delete('.')
          mime = { 'jpg' => 'jpeg', 'jpeg' => 'jpeg', 'png' => 'png', 'webp' => 'webp' }[ext] || 'jpeg'
          prev = File.size(f) < 8_000_000 ? "data:image/#{mime};base64,#{[File.binread(f)].pack('m0')}" : ''
          dlg.execute_script("prodImage(#{JSON.generate('path' => f, 'preview' => prev)})")
        end
        dlg.add_action_callback('prodSave') do |_c, json|
          req = JSON.parse(json)
          saved = nil
          Steps.run(dlg, [['Saving the product to HubSpot' + (req['image'] ? ' (with its picture)' : ''), -> { saved = HubSpotProducts.save(req['form'], req['image']) }]],
                    done: lambda { |_r|
                      dlg.execute_script("prodSaved(#{JSON.generate('data' => ProductImages.with_images(HubSpotProducts.local), 'name' => saved['name'])})")
                      ProductImages.sync(dlg, HubSpotProducts.products)
                    },
                    fail: ->(e) { dlg.execute_script("prodSaved(#{JSON.generate('error' => e.message)})") }, count: false)
        end
        dlg.add_action_callback('prodDelete') do |_c, json|
          ids = Array(JSON.parse(json)['ids'])
          n = 0
          Steps.run(dlg, [["Deleting #{ids.size} product(s) from HubSpot", -> { n = HubSpotProducts.delete(ids) }]],
                    done: ->(_r) { dlg.execute_script("prodDeleted(#{JSON.generate('data' => ProductImages.with_images(HubSpotProducts.local), 'n' => n)})") },
                    fail: ->(e) { dlg.execute_script("prodDeleted(#{JSON.generate('error' => e.message)})") }, count: false)
        end
        dlg.show
        UI.start_timer(1.0, false) { ProductImages.sync(dlg, HubSpotProducts.products) if dlg.visible? }
      end
    end
  end
end
