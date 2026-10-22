require 'json'
require 'net/http'
require 'openssl'
require 'uri'
require 'cgi'
require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Settings > Products > Import from supplier: reads a supplier's handle / knob pages
    # (from this computer), lists every item with its picture, name, SKU and link, and adds
    # the ticked ones to HubSpot as Non-inventory products (supplier set, link copied, the
    # picture copied into HubSpot). Costs aren't read.
    #
    # Each supplier is a SOURCE: start pages + a reader for its listing pages (and, where the
    # listing has no exact SKU, its product page). A page that changes its layout only breaks
    # its own reader.
    module SupplierImport
      UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36'.freeze

      class Error < StandardError; end

      # --- fetching -------------------------------------------------------------------

      # A page (as UTF-8 text), or with binary: true a file's bytes untouched (pictures).
      def self.get(url, tries: 3, binary: false)
        uri = URI(url)
        1.upto(tries) do |attempt|
          begin
            6.times do
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = uri.scheme == 'https'
              http.verify_mode = OpenSSL::SSL::VERIFY_PEER
              http.open_timeout = 15
              http.read_timeout = 30
              req = Net::HTTP::Get.new(uri)
              req['User-Agent'] = UA
              req['Accept'] = binary ? 'image/jpeg,image/png;q=0.9,image/*;q=0.5' : 'text/html,application/json;q=0.9,*/*;q=0.8'
              req['Accept-Language'] = 'en-GB,en;q=0.9'
              res = http.request(req)
              if res.is_a?(Net::HTTPRedirection) && res['location']
                uri = URI.join(uri.to_s, res['location'])
                next
              end
              raise Error, "#{uri.host} said #{res.code}" unless res.code.to_i.between?(200, 299)
              body = res.body.to_s
              return body.b if binary
              return body.force_encoding('UTF-8').valid_encoding? ? body : body.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
            end
            raise Error, "too many redirects at #{url}"
          rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
            raise Error, "Can't reach #{uri.host} (#{e.class.name.split('::').last})" if attempt == tries
            sleep(attempt * 0.5)
          end
        end
      end

      # The real picture type from its first bytes (nil if it isn't a picture).
      def self.image_ext(bytes)
        b = bytes.to_s.b
        return '.jpg' if b.start_with?("\xFF\xD8\xFF".b)
        return '.png' if b.start_with?("\x89PNG".b)
        return '.gif' if b.start_with?('GIF8')
        return '.webp' if b[0, 4] == 'RIFF' && b[8, 4] == 'WEBP'
        nil
      end

      # Saves a picture to a temporary file named for its real type; raises if what came
      # back isn't a picture.
      def self.download(url)
        bytes = get(url, binary: true)
        ext = image_ext(bytes) or raise Error, "#{URI(url).host} didn't send a picture"
        path = File.join(Dir.tmpdir, "hw_import_#{Process.pid}_#{rand(1_000_000)}#{ext}")
        File.binwrite(path, bytes)
        path
      end

      def self.text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
      end

      def self.abs(base, href)
        return nil if href.to_s.strip.empty?
        URI.join(base, CGI.unescapeHTML(href.strip)).to_s
      rescue URI::Error
        nil
      end

      # --- readers ----------------------------------------------------------------------
      # Each supplier: 'start' pages, 'links' (html, url) -> more pages to read (sub-categories
      # and numbered pages, never outside the section) and 'items' (html, url) -> products.

      def self.attr_of(tag, name)
        v = tag[/\b#{name}="([^"]*)"/, 1]
        v && CGI.unescapeHTML(v)
      end

      # Same-site link, tidied so one page has one address: no #part, no slash before ?, no page=1.
      def self.same_site(base, href)
        u = abs(base, href) or return nil
        return nil unless URI(u).host == URI(base).host
        u.sub(/#.*\z/, '').sub(%r{/\?}, '?').sub(/[?&]page=1\z/, '')
      rescue URI::Error
        nil
      end

      # Interfit (BigCommerce): sub-category tiles, ?page=N, list items with the code in the
      # picture's alt text; the exact SKU is on the product page (BCData "sku").
      INTERFIT = {
        'links' => lambda do |html, url|
          subs = html.scan(/class="subcategory-link"[^>]*href="([^"]+)"/).flatten
          pages = html.scan(/href="([^"]*[?&]page=\d+[^"]*)"/).flatten.select { |h| h.start_with?(url.sub(/\?.*\z/, '')) }
          (subs + pages).filter_map { |h| SupplierImport.same_site(url, h) }
        end,
        'items' => lambda do |html, url|
          group = SupplierImport.text(html[%r{<h2 class="container-header">([^<]*)</h2>\s*<div class="category-main-image}m, 1])
          html.scan(%r{<article class="listItem">(.*?)</article>}m).filter_map do |(card)|
            link = card[%r{<h4 class="listItem-title">\s*<a href="([^"]+)"}m, 1]
            name = SupplierImport.text(card[%r{<h4 class="listItem-title">(.*?)</h4>}m, 1])
            img = card[/<img[^>]*>/].to_s
            alt = SupplierImport.attr_of(img, 'alt').to_s
            next if link.nil? || name.empty?
            { 'name' => name, 'url' => SupplierImport.abs(url, link), 'image' => SupplierImport.attr_of(img, 'data-src') || SupplierImport.attr_of(img, 'src'),
              'sku' => alt[/\A\s*([A-Z0-9][A-Z0-9.\-\/]{2,})\s/, 1].to_s, 'sku_exact' => false, 'group' => group,
              'price' => card[/data-product-price-without-tax[^>]*>\s*([^<]+)</, 1].to_s.strip }
          end
        end,
        'sku' => ->(html) { html[/"product_attributes":\{"sku":"([^"]+)"/, 1] || SupplierImport.text(html[/data-product-sku[^>]*>(.*?)</m, 1]) }
      }.freeze

      # HPP: category tiles down to family pages; each family page has a table per section
      # (code, description, finish) and pictures named by finish.
      HPP = {
        'links' => lambda do |html, url|
          html.scan(/<a href="([^"]+)" class="category__products-item[^"]*"/).flatten.filter_map { |h| SupplierImport.same_site(url, h) }
        end,
        'items' => lambda do |html, url|
          pics = {}
          html.scan(%r{<h3 id="(\d+)" class="two-col__heading">.*?<div class="category__images swiper"[^>]*>(.*?)<div class="swiper-nav}m).each do |node, block|
            pics[node] = block.scan(/<img[^>]*>/).map { |t| [SupplierImport.attr_of(t, 'alt').to_s, SupplierImport.abs(url, SupplierImport.attr_of(t, 'src'))] }
          end
          fallback = SupplierImport.abs(url, html[/<meta property="og:image" content="([^"]+)"/, 1])
          out = []
          html.scan(%r{<div[^>]*class="metricGroup"[^>]*>.*?</table>}m).each do |grp|
            node = grp[/data-nodeid="(\d+)"/, 1]
            group = CGI.unescapeHTML(grp[/data-category1="([^"]*)"/, 1].to_s)
            grp.scan(%r{<tr data-productcode="([^"]+)"[^>]*title="([^"]*)"[^>]*>(.*?)</tr>}m).each do |code, title, row|
              finish = SupplierImport.text(row[%r{data-metric="Finish">(.*?)</td>}m, 1])
              list = pics[node] || []
              img = (list.find { |a, _| a.casecmp?(finish) } || list.first || [nil, fallback])[1]
              # HPP's picture service takes a size: 600 px is plenty for a product picture.
              img = img.to_s.sub(/\/(\d+)w\d+h\d+\//, '/\\1w600h600/').sub(/width=\d+&height=\d+/, 'width=600&height=600') if img
              size = SupplierImport.text(row[%r{data-metric="(?:Centres|Diameter|Length|Size)">(.*?)</td>}m, 1])
              out << { 'name' => CGI.unescapeHTML(title), 'sku' => code, 'sku_exact' => true, 'image' => img,
                       'finish' => finish, 'size' => size, 'range' => CGI.unescapeHTML([grp[/data-category3="([^"]*)"/, 1], grp[/data-category2="([^"]*)"/, 1]].find { |x| !x.to_s.strip.empty? }.to_s),
                       'url' => "#{url.sub(/#.*\z/, '')}#{node ? "##{node}" : ''}", 'group' => group, 'price' => '' }
            end
          end
          out
        end
      }.freeze

      # Handles4u: sub-categories under the section and ?page=N; products are in the page's
      # structured data (name, SKU, picture, link, price).
      HANDLES4U = {
        'links' => lambda do |html, url|
          base = URI(url).path.sub(%r{/\z}, '')
          root = (@h4u_roots || []).find { |r| base.start_with?(r) } || base
          html.scan(/href="([^"]+)"/).flatten.filter_map do |h|
            next if h.include?('search::') || h.include?('%20') || h.include?('nofilters')
            u = SupplierImport.same_site(url, h) or next
            path = URI(u).path.sub(%r{/\z}, '')
            next unless path.start_with?(root)
            next if path.split('/').last.to_s =~ /\A\d+\z/ # a product page
            u
          end
        end,
        'items' => lambda do |html, url|
          j = html.gsub('\\"', '"').gsub('\\\\/', '/').gsub('\\/', '/')
          j.scan(/"@type":"Product","name":"(.*?)","offers":\[\{.*?"price":([\d.]+).*?"url":"(.*?)".*?\}\],"sku":"(.*?)".*?"image":"(.*?)"/).map do |name, price, link, sku, img|
            { 'name' => name.gsub(/\\u0026|&amp;/, '&'), 'sku' => sku, 'sku_exact' => true, 'image' => img.gsub('\\', ''),
              'url' => link.gsub('\\', ''), 'group' => CGI.unescape(URI(url).path.split('/').last.to_s).tr('+', ' '), 'price' => "£#{price}" }
          end
        end
      }.freeze

      # Any other site: products in the page's structured data (schema.org Product), else the
      # page's own title and picture. Follows ?page=N on the same page only.
      GENERIC = {
        'links' => lambda do |html, url|
          path = url.sub(/\?.*\z/, '')
          html.scan(/href="([^"]*[?&]page=\d+[^"]*)"/).flatten.filter_map { |h| SupplierImport.same_site(url, h) }.select { |u| u.start_with?(path) }
        end,
        'items' => lambda do |html, url|
          out = []
          html.scan(%r{<script[^>]*application/ld\+json[^>]*>(.*?)</script>}m).each do |(js)|
            data = (JSON.parse(js) rescue nil) or next
            walk = lambda do |x|
              case x
              when Array then x.each { |y| walk.call(y) }
              when Hash
                if Array(x['@type']).include?('Product')
                  img = x['image']
                  img = img.first if img.is_a?(Array)
                  img = img['url'] if img.is_a?(Hash)
                  offer = x['offers'].is_a?(Array) ? x['offers'].first : x['offers']
                  offer = {} unless offer.is_a?(Hash)
                  code = (x['sku'] || x['mpn']).to_s
                  out << { 'name' => CGI.unescapeHTML(x['name'].to_s), 'sku' => code, 'sku_exact' => !code.empty?,
                           'image' => SupplierImport.abs(url, img.to_s), 'url' => SupplierImport.abs(url, (offer['url'] || x['url'] || url).to_s),
                           'price' => offer['price'] ? "£#{offer['price']}" : '' }
                end
                x.each_value { |y| walk.call(y) if y.is_a?(Hash) || y.is_a?(Array) }
              end
            end
            walk.call(data)
          end
          if out.empty?
            title = CGI.unescapeHTML((html[/<meta property="og:title" content="([^"]*)"/, 1] || html[%r{<title>(.*?)</title>}m, 1]).to_s).strip
            img = html[/<meta property="og:image" content="([^"]*)"/, 1]
            out << { 'name' => title, 'sku' => '', 'sku_exact' => false, 'image' => SupplierImport.abs(url, img.to_s), 'url' => url, 'price' => '' } unless title.empty?
          end
          out.reject { |i| i['name'].to_s.empty? }
        end
      }.freeze

      READERS = { 'hpp' => HPP, 'interfit' => INTERFIT, 'handles4u' => HANDLES4U, 'generic' => GENERIC }.freeze
      HOSTS = { 'hpponline.co.uk' => 'hpp', 'interfitco.com' => 'interfit', 'handles4u.co.uk' => 'handles4u' }.freeze

      # The reader for a pasted page address.
      def self.reader_for(url)
        HOSTS[URI(url).host.to_s.sub(/\Awww\./, '')] || 'generic'
      rescue URI::Error
        'generic'
      end

      # --- range - finish - size ------------------------------------------------------
      FINISHES = ['Brushed Satin Brass', 'Satin Brass', 'Aged Brass', 'Antique Brass', 'Brushed Brass', 'Polished Brass', 'Unlacquered Brass',
                  'Matt Black', 'Satin Black', 'Gloss Black', 'Black', 'Polished Chrome', 'Satin Chrome', 'Brushed Chrome', 'Chrome',
                  'Satin Nickel', 'Brushed Nickel', 'Polished Nickel', 'Pewter', 'Dark Bronze', 'Antique Bronze', 'Satin Bronze', 'Bronze', 'Dark Grey', 'Light Grey', 'Grey', 'Antique Copper', 'Copper',
                  'Stainless Steel', 'Brushed Steel', 'Satin Steel', 'Gunmetal', 'Graphite', 'Anthracite', 'Brushed Gold', 'Rose Gold', 'Gold',
                  'Matt White', 'White', 'Oak', 'Walnut', 'Glass', 'Porcelain', 'Iron', 'Nickel', 'Brass', 'Steel', 'Aluminium', 'Champagne'].freeze
      BRANDS = /\A(?:Alexander\s*&\s*Wilks|Carlisle Brass|Fingertip Design|Hafele|Häfele|M Marcus|Hoxton)\s+/i.freeze
      SIZE = /(\d+(?:\.\d+)?)\s?mm(?:\s*(?:-|to|\/|&)\s*\d+(?:\.\d+)?\s?mm)?/i.freeze

      def self.titleize(s)
        s.to_s.split(/(\s+)/).map { |w| w =~ /\A[a-z]/ ? w.capitalize : w }.join
      end

      # { 'range', 'finish', 'size', 'title' } for an item: "Venice Handle - Aged Brass - 128mm".
      def self.describe(item)
        name = item['name'].to_s.sub(/\s*\|.*\z/, '').strip
        finish = item['finish'].to_s.strip
        finish = FINISHES.find { |x| name =~ /\b#{Regexp.escape(x)}\b/i }.to_s if finish.empty?
        size = item['size'].to_s.strip
        size = (name[SIZE] || '').gsub(/\s+/, '') if size.empty?
        range = item['range'].to_s.strip
        if range.empty?
          r = name.sub(BRANDS, '')
          r = r.gsub(/\b#{Regexp.escape(item['sku'].to_s)}\b/i, '') unless item['sku'].to_s.empty?
          r = r.gsub(/\b[A-Z]{1,4}\d{2,}[A-Z0-9\-.]*\b/, '')                                   # other codes
          r = r.gsub(/\b#{Regexp.escape(finish)}\b(?:\s+finish)?/i, '') unless finish.empty?
          r = r.gsub(/#{SIZE.source}(?:\s+(?:centres|centers|diameter|dia))?/i, '')
          r = r.gsub(/\s+by\s+[A-Z][\w&' ]+\z/, '')
          parts = r.split(/\s+[-–]\s+|\s*,\s*|\s+in\s*(?=\z|\s+-)/i).map { |x| x.strip.sub(/\A(?:in|-)\s+/i, '').sub(/\s+(?:in|-)\z/i, '') }.reject(&:empty?)
          range = parts.join(' ').gsub(/\s{2,}/, ' ').strip
          range = name if range.empty?
        end
        range = titleize(range)
        finish = titleize(finish)
        { 'range' => range, 'finish' => finish, 'size' => size, 'title' => [range, finish, size].reject(&:empty?).join(' - ') }
      end

      SOURCES = [
        { 'id' => 'hpp', 'name' => 'HPP', 'supplier' => 'HPP', 'reader' => HPP,
          'start' => ['https://www.hpponline.co.uk/cat/226/furniture-handles', 'https://www.hpponline.co.uk/cat/681/knobs'] },
        { 'id' => 'interfit', 'name' => 'Interfit', 'supplier' => 'Interfit', 'reader' => INTERFIT,
          'start' => ['https://www.interfitco.com/cupboard-handles/'] },
        { 'id' => 'handles4u', 'name' => 'Handles4u', 'supplier' => 'Handles4u', 'reader' => HANDLES4U,
          'start' => ['https://www.handles4u.co.uk/products/Cabinet+Furniture/Cabinet+Knobs',
                      'https://www.handles4u.co.uk/products/Cabinet+Furniture/Cabinet+Handles'] }
      ].freeze

      MAX_PAGES = 800 # per supplier, a safety stop
      PAUSE = 0.15    # seconds between pages, to be polite to the supplier's site

      def self.source(id)
        s = SOURCES.find { |x| x['id'] == id.to_s } or raise Error, "No reader for #{id}"
        s.merge('reader_id' => s['id'])
      end

      # A pasted address: its own reader (a known supplier's, or the general one), starting there.
      def self.url_source(url, supplier)
        rid = reader_for(url)
        u = same_site(url, url) || url
        { 'id' => 'url', 'name' => URI(u).host.to_s.sub(/\Awww\./, ''), 'supplier' => supplier.to_s, 'reader' => READERS[rid],
          'reader_id' => rid, 'start' => [u] }
      end

      # Reads one page: [items, more pages].
      def self.read_page(src, url)
        html = get(url)
        r = src['reader']
        items = r['items'].call(html, url).map { |i| i.merge('source' => src['id'], 'reader' => src['reader_id'], 'supplier' => src['supplier']).merge(describe(i)) }
        [items, r['links'].call(html, url).uniq]
      end

      # Exact SKU from the product page, when the listing only had a guess.
      def self.exact_sku(item)
        return item['sku'] if item['sku_exact'] || item['url'].to_s.empty?
        reader = READERS[item['reader'].to_s] or return item['sku']
        return item['sku'] unless reader['sku']
        s = reader['sku'].call(get(item['url']))
        s.to_s.strip.empty? ? item['sku'] : s.strip
      end

      # Matches a supplier name to HubSpot's Supplier dropdown value (any case), or nil.
      def self.supplier_value(name)
        opts = Array(HubSpotProducts.local.dig('options', 'suppliers'))
        hit = opts.find { |l, v| l.to_s.casecmp?(name.to_s) || v.to_s.casecmp?(name.to_s) }
        hit && hit[1]
      end

      # Already in HubSpot: by supplier link, or by SKU.
      def self.mark_existing(items)
        have = HubSpotProducts.products
        urls = have.map { |p| p['hs_url'].to_s.downcase.chomp('/') }.reject(&:empty?)
        skus = have.map { |p| p['hs_sku'].to_s.downcase }.reject(&:empty?)
        items.each do |i|
          i['have'] = urls.include?(i['url'].to_s.downcase.chomp('/')) || (i['sku_exact'] && !i['sku'].to_s.empty? && skus.include?(i['sku'].to_s.downcase))
        end
      end

      # Adds one item to HubSpot (picture copied in). Returns the saved product.
      def self.add(item, categories, use_price = false)
        sku = exact_sku(item)
        img = item['image'].to_s.empty? ? nil : (download(item['image']) rescue nil)
        form = { 'name' => (item['title'].to_s.empty? ? item['name'] : item['title']), 'hs_sku' => sku, 'supplier' => supplier_value(item['supplier']).to_s,
                 'hs_product_type' => 'non_inventory', 'hs_url' => item['url'], 'product_category' => Array(categories) }
        price = item['price'].to_s[/[\d.]+/]
        form['hs_cost_of_goods_sold'] = price if use_price && price && price.to_f > 0
        HubSpotProducts.save(form, img)
      ensure
        File.delete(img) if img && File.exist?(img)
      end

      # Is a product's picture in HubSpot a real picture? (Pictures imported before 0.34 were
      # damaged on the way in.) nil when it has none.
      def self.picture_ok?(product)
        u = product['hs_images'].to_s.split(';').first.to_s
        return nil if u.empty?
        bytes = get(u, binary: true)
        # Damaged ones were turned into text, so they read as valid UTF-8; a real picture never does.
        !image_ext(bytes).nil? && !bytes.dup.force_encoding('UTF-8').valid_encoding?
      rescue Error
        false
      end

      # Copies the picture again from the product's own page on the supplier's website
      # (only pages that show one product, so a shared range page can't give the wrong
      # finish). Returns the new picture link, or nil if the page has no single picture.
      def self.repicture(product)
        url = product['hs_url'].to_s
        return nil if url.empty?
        html = get(url)
        list = GENERIC['items'].call(html, url).reject { |i| i['image'].to_s.empty? }
        img = list.size == 1 ? list[0]['image'] : nil
        return nil unless img
        path = download(img)
        begin
          up = HubSpot.upload_file(path, '/products', access: 'PUBLIC_NOT_INDEXABLE')
        ensure
          File.delete(path) if File.exist?(path)
        end
        link = up['url'].to_s
        HubSpot.patch("/crm/v3/objects/products/#{product['id']}", { properties: { hs_images: link } })
        data = HubSpotProducts.local
        Array(data['products']).each { |p| p['hs_images'] = link if p['id'].to_s == product['id'].to_s }
        HubSpotProducts.save_local(data)
        link
      end

      # --- window ---------------------------------------------------------------------

      def self.show
        return unless HubSpotRoom.ready?
        data = { 'sources' => SOURCES.map { |s| { 'id' => s['id'], 'name' => s['name'], 'supplier' => s['supplier'],
                                                  'supplier_ok' => !supplier_value(s['supplier']).nil? } },
                 'suppliers' => Array(HubSpotProducts.local.dig('options', 'suppliers')),
                 'categories' => Array(HubSpotProducts.local.dig('options', 'categories')) }
        dlg = Dialog.open('product_import', title: 'HW - Import products from a supplier', key: 'hw_product_import', width: 900, height: 720, data: data)
        items = []
        dlg.add_action_callback('read') do |_c, json|
          req = JSON.parse(json)
          src = req['url'].to_s.strip.empty? ? source(req['source']) : url_source(req['url'].strip, req['supplier'])
          @h4u_roots = src['start'].map { |u| URI(u).path.sub(%r{/\z}, '') } # Handles4u: stay inside these sections
          items = []
          seen_items = {}
          visited = {}
          queue = src['start'].map { |u| same_site(u, u) }
          pages = 0
          step = lambda do
            url = queue.shift
            url = queue.shift while url && visited[url]
            if url.nil? || pages >= MAX_PAGES
              Steps.busy(dlg, nil)
              mark_existing(items)
              msg = pages >= MAX_PAGES ? "Stopped after #{MAX_PAGES} pages." : nil
              next dlg.execute_script("listed(#{JSON.generate('items' => items, 'error' => msg, 'pages' => pages)})")
            end
            visited[url] = true
            pages += 1
            Steps.busy(dlg, { 'text' => "Reading #{src['name']} - page #{pages}, #{items.size} found (#{queue.size} to go)", 'done' => 0, 'total' => 0 })
            UI.start_timer(PAUSE, false) do
              begin
                got, more = read_page(src, url)
                got.each do |i|
                  # Same product listed twice: by exact SKU, or by link when the SKU is only a guess
                  # (finishes of one handle share the guessed code).
                  key = i['sku_exact'] && !i['sku'].to_s.empty? ? i['sku'].downcase : i['url']
                  next if seen_items[key]
                  seen_items[key] = true
                  items << i
                end
                more.each { |u| queue << u unless visited[u] || queue.include?(u) }
                dlg.execute_script("partial(#{items.size}, #{pages})") if (pages % 10).zero?
              rescue Error => e
                Log.info("supplier import: #{url}: #{e.message}")
              rescue StandardError => e
                Log.error('supplier import', e)
              end
              step.call
            end
          end
          step.call
        end
        dlg.add_action_callback('add') do |_c, json|
          req = JSON.parse(json)
          chosen = req['keys'].filter_map { |k| items.find { |i| "#{i['url']}|#{i['sku']}" == k } }
          done = []
          steps = chosen.map { |i| ["Adding #{i['title'] || i['name']}", -> { done << add(i, req['categories'], req['use_price']); i['have'] = true }] }
          Steps.run(dlg, steps,
                    done: lambda { |_r|
                      dlg.execute_script("added(#{JSON.generate('n' => done.size, 'items' => items)})")
                      Dialog['products']&.execute_script("prodList(#{JSON.generate('data' => HubSpotProducts.local)})") rescue nil
                    },
                    fail: ->(e) { dlg.execute_script("added(#{JSON.generate('n' => done.size, 'items' => items, 'error' => e.message)})") })
        end
        dlg.show
      end
    end
  end
end
