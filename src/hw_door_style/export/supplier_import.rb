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

      def self.get(url, tries: 3)
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
              req['Accept'] = 'text/html,application/json;q=0.9,*/*;q=0.8'
              req['Accept-Language'] = 'en-GB,en;q=0.9'
              res = http.request(req)
              if res.is_a?(Net::HTTPRedirection) && res['location']
                uri = URI.join(uri.to_s, res['location'])
                next
              end
              raise Error, "#{uri.host} said #{res.code}" unless res.code.to_i.between?(200, 299)
              body = res.body.to_s
              return body.force_encoding('UTF-8').valid_encoding? ? body : body.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
            end
            raise Error, "too many redirects at #{url}"
          rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
            raise Error, "Can't reach #{uri.host} (#{e.class.name.split('::').last})" if attempt == tries
            sleep(attempt * 0.5)
          end
        end
      end

      def self.download(url)
        ext = File.extname(URI(url).path)[/\.(jpe?g|png|webp|gif)\z/i] || '.jpg'
        path = File.join(Dir.tmpdir, "hw_import_#{Process.pid}_#{rand(1_000_000)}#{ext}")
        File.binwrite(path, get(url))
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
              out << { 'name' => CGI.unescapeHTML(title), 'sku' => code, 'sku_exact' => true, 'image' => img,
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
        SOURCES.find { |s| s['id'] == id.to_s } or raise Error, "No reader for #{id}"
      end

      # Reads one page: [items, more pages].
      def self.read_page(src, url)
        html = get(url)
        r = src['reader']
        items = r['items'].call(html, url).map { |i| i.merge('source' => src['id']) }
        [items, r['links'].call(html, url).uniq]
      end

      # Exact SKU from the product page, when the listing only had a guess.
      def self.exact_sku(item)
        return item['sku'] if item['sku_exact'] || item['url'].to_s.empty?
        src = source(item['source'])
        return item['sku'] unless src['reader']['sku']
        s = src['reader']['sku'].call(get(item['url']))
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
        form = { 'name' => item['name'], 'hs_sku' => sku, 'supplier' => supplier_value(source(item['source'])['supplier']).to_s,
                 'hs_product_type' => 'non_inventory', 'hs_url' => item['url'], 'product_category' => Array(categories) }
        price = item['price'].to_s[/[\d.]+/]
        form['hs_cost_of_goods_sold'] = price if use_price && price && price.to_f > 0
        HubSpotProducts.save(form, img)
      ensure
        File.delete(img) if img && File.exist?(img)
      end

      # --- window ---------------------------------------------------------------------

      def self.show
        return unless HubSpotRoom.ready?
        data = { 'sources' => SOURCES.map { |s| { 'id' => s['id'], 'name' => s['name'], 'supplier' => s['supplier'],
                                                  'supplier_ok' => !supplier_value(s['supplier']).nil? } },
                 'categories' => Array(HubSpotProducts.local.dig('options', 'categories')) }
        dlg = Dialog.open('product_import', title: 'HW - Import products from a supplier', key: 'hw_product_import', width: 900, height: 720, data: data)
        items = []
        dlg.add_action_callback('read') do |_c, sid|
          src = source(sid)
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
          chosen = req['urls'].filter_map { |u| items.find { |i| i['url'] == u } }
          done = []
          steps = chosen.map { |i| ["Adding #{i['name']}", -> { done << add(i, req['categories'], req['use_price']); i['have'] = true }] }
          Steps.run(dlg, steps,
                    done: lambda { |_r|
                      dlg.execute_script("added(#{JSON.generate('n' => done.size, 'items' => items)})")
                      Dialog['settings']&.execute_script("prodList(#{JSON.generate('data' => HubSpotProducts.local)})") rescue nil
                    },
                    fail: ->(e) { dlg.execute_script("added(#{JSON.generate('n' => done.size, 'items' => items, 'error' => e.message)})") })
        end
        dlg.show
      end
    end
  end
end
