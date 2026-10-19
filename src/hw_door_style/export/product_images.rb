require 'fileutils'
require 'uri'

module HarryWardrobes
  module DoorStyle
    # Product pictures kept on this computer (%APPDATA%\HW Door Style\product_images\<id>.jpg),
    # so the handle pictures show straight away and offline - the windows never load them
    # from the internet. Missing ones are copied down in the background (one per tick, the
    # window's busy bar showing it) when a window that shows them opens, and after the
    # products are read from HubSpot.
    module ProductImages
      DIR = File.join(Settings::USER_DIR, 'product_images')
      EXTS = %w[.jpg .png .webp .gif].freeze

      def self.remote(p)
        p['hs_images'].to_s.split(';').first.to_s.strip
      end

      # The picture on this computer, or nil (also nil when HubSpot now has a different picture).
      def self.path(p)
        id = p['id'].to_s
        return nil if id.empty?
        f = EXTS.map { |x| File.join(DIR, "#{id}#{x}") }.find { |x| File.exist?(x) && File.size(x).positive? } or return nil
        src = File.join(DIR, "#{id}.src")
        return nil if File.exist?(src) && !remote(p).empty? && File.read(src).strip != remote(p)
        f
      end

      def self.url(p)
        f = path(p) or return nil
        "file:///#{f.tr('\\', '/')}?#{File.mtime(f).to_i}"
      end

      # { id => local url } for a product list.
      def self.urls(products)
        products.each_with_object({}) { |p, h| (u = url(p)) && h[p['id'].to_s] = u }
      end

      # The product list for a window: the local pictures added as 'images' { id => url }.
      def self.with_images(local)
        local.merge('images' => urls(Array(local['products'])))
      end

      def self.missing(products)
        products.select { |p| !remote(p).empty? && path(p).nil? }
      end

      # Downloads one picture. Returns its local url.
      def self.fetch(p)
        bytes = SupplierImport.get(remote(p), binary: true)
        ext = SupplierImport.image_ext(bytes) or raise "#{p['name']}: no picture at #{URI(remote(p)).host}"
        FileUtils.mkdir_p(DIR)
        dst = File.join(DIR, "#{p['id']}#{ext}")
        EXTS.each { |x| o = File.join(DIR, "#{p['id']}#{x}"); File.delete(o) if o != dst && File.exist?(o) }
        File.binwrite("#{dst}.part", bytes)
        File.rename("#{dst}.part", dst)
        File.write(File.join(DIR, "#{p['id']}.src"), remote(p))
        url(p)
      end

      # Copies down every missing picture, telling the window as each one arrives
      # (js_fn(id, url)). A picture that fails is skipped; the rest carry on.
      def self.sync(dlg, products, js_fn: 'imageReady', done: nil)
        todo = missing(products)
        return done&.call(0) if todo.empty? || @syncing
        @syncing = true
        n = 0
        steps = todo.map do |p|
          ["Saving product pictures on this computer (#{p['name']})", lambda {
            begin
              u = fetch(p)
              n += 1
              dlg.execute_script("#{js_fn}(#{JSON.generate(p['id'].to_s)}, #{JSON.generate(u)})") if dlg&.visible? && js_fn
            rescue StandardError => e
              Log.error('product picture', e)
            end
            nil
          }]
        end
        Steps.run(dlg, steps, done: ->(_r) { @syncing = false; done&.call(n) },
                              fail: ->(_e) { @syncing = false; done&.call(n) })
      end
    end
  end
end
