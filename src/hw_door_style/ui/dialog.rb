require 'json'

module HarryWardrobes
  module DoorStyle
    # Every window is html/<name>.html. A page marks where the shared look goes
    # with <!--HW--> (html/hw.css + html/hw.js are put there) and receives its
    # data through the literal /*DATA*/null in its script:
    #
    #   var D = /*DATA*/null;
    #
    # The job pages - Add, Colours, Doors, Room settings, Workshop, HubSpot - are tabs of ONE
    # window (TABS): opening one swaps the page into that window (it resizes to the page
    # and stays centred) and a strip of icons along the top switches between them. Everything
    # else (Settings, Export, Setup...) is its own window, one per id.
    module Dialog
      DIR = File.join(PATH, 'html')
      MAIN_KEY = 'hw_main_v1'.freeze
      MIN_WIDTH = 560 # room for the tab strip

      # [tab id, page name, label, icon file]; what opens each is in SHOW (looked up when
      # pressed, so this file needs nothing loaded before it).
      TABS = [
        ['add', 'component_picker', 'Add', 'plus'],
        ['colours', 'colours', 'Colours', 'colours'],
        ['doors', 'door_style', 'Doors', 'doors'],
        ['room', 'scribe', 'Room', 'room'],
        ['workshop', 'parts_list', 'Workshop', 'parts'],
        ['hubspot', 'hubspot_send', 'HubSpot', 'hubspot']
      ].freeze
      SHOW = {
        'add' => -> { ComponentPicker.show },
        'colours' => -> { ColoursWindow.show },
        'doors' => -> { DoorStyleWindow.show },
        'room' => -> { Pencil.show(Sketchup.active_model, nil) },
        'workshop' => -> { PartsList.show },
        'hubspot' => -> { HubSpotRoom.show_send }
      }.freeze

      def self.tabbed?(name) = TABS.any? { |_t, page, _l, _i| page == name.to_s }

      def self.shared
        @shared ||= "<style>\n#{File.read(File.join(DIR, 'hw.css'))}</style>\n" \
                    "<script>\n#{File.read(File.join(DIR, 'hw.js'))}</script>"
      end

      def self.icon(file)
        @icons ||= {}
        @icons[file] ||= File.read(File.join(PATH, 'icons', "#{file}.svg")).sub(/<\?xml[^>]*>/, '').strip
      rescue StandardError
        ''
      end

      # The icon strip for a tabbed page (the page's own tab marked).
      def self.tab_strip(name)
        items = TABS.map do |id, page, label, ico|
          "<a#{page == name ? ' class="on"' : ''} onclick=\"hwTab('#{id}')\" title=\"#{label}\">#{icon(ico)}<span>#{label}</span></a>"
        end
        "<div id=\"hwTabs\">#{items.join}</div>"
      end

      # Highlight something the next time page name opens (Workshop > Fix this): sel = CSS
      # selectors to outline, note = what to do (a banner at the top), js = run first (e.g.
      # switch to the right Settings section), back = run when that page is done (its Apply
      # finished, or Cancel) - the Workshop coming back.
      def self.focus_next(name, sel: [], note: nil, js: nil, back: nil)
        (@focus ||= {})[name.to_s] = { 'sel' => Array(sel), 'note' => note, 'js' => js }
        (@back ||= {})[name.to_s] = back if back
      end

      # Is a "back to" waiting for page name?
      def self.pending?(name) = !((@back ||= {})[name.to_s]).nil?

      # A page is done (Apply finished or Cancel): runs what was waiting (true), or nothing (false).
      def self.done(name)
        blk = (@back ||= {}).delete(name.to_s) or return false
        UI.start_timer(0.05, false) { blk.call }
        true
      end

      # A page closing itself after Apply: not when something is waiting to take its place.
      def self.leave(dlg, name)
        dlg.close unless pending?(name)
      end

      # The page's HTML with the shared look and data filled in.
      def self.html(name, data = nil)
        page = File.read(File.join(DIR, "#{name}.html"))
        f = (@focus ||= {}).delete(name.to_s)
        extra = f ? "\n<script>var HW_FOCUS = #{JSON.generate(f)};</script>" : ''
        page = page.sub('<!--HW-->') { shared + extra }
        page = page.sub(/<body[^>]*>/) { "#{Regexp.last_match(0)}\n#{tab_strip(name)}" } if tabbed?(name)
        # <!--VENDOR:file.js--> -> that bundled library inline (html/vendor; no CDN - the window may be offline)
        page = page.gsub(/<!--VENDOR:([\w.\-]+)-->/) { "<script>\n#{File.read(File.join(DIR, 'vendor', Regexp.last_match(1)))}\n</script>" }
        page.sub('/*DATA*/null') { JSON.generate(data) }
      end

      # Opens html/<name>.html. id: one window per id (defaults to name).
      # key: SketchUp remembers size and position under it.
      # Returns the UI::HtmlDialog so the caller can add callbacks; call #show.
      def self.open(name, title:, key:, width:, height:, data: nil, id: name,
                    resizable: true, scrollable: true, utility: false)
        @open ||= {}
        return open_tab(name, width, height, data) if tabbed?(name)
        @open[id]&.close
        dlg = UI::HtmlDialog.new(dialog_title: title, preferences_key: key, width: width, height: height,
                                 resizable: resizable, scrollable: scrollable,
                                 style: utility ? UI::HtmlDialog::STYLE_UTILITY : UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(html(name, data))
        dlg.add_action_callback('cancel') { |_c| dlg.close unless done(name) }
        @open[id] = dlg
      end

      # The one job window: a new page swapped into it (resized to the page, centred).
      def self.open_tab(name, width, height, data)
        @main = nil unless @main&.visible?
        @main ||= UI::HtmlDialog.new(dialog_title: 'HW Door Style', preferences_key: MAIN_KEY, width: width, height: height,
                                     resizable: true, scrollable: true, style: UI::HtmlDialog::STYLE_DIALOG)
        dlg = @main
        dlg.set_html(html(name, data))
        dlg.set_size([width, MIN_WIDTH].max, height)
        dlg.center
        dlg.add_action_callback('cancel') { |_c| dlg.close unless done(name) }
        dlg.add_action_callback('hwTab') do |_c, id|
          show = SHOW[id.to_s] or next
          done(name) # anything waiting on this page is dropped - the user went elsewhere
          UI.start_timer(0.05, false) { show.call }
        end
        @main_page = name
        @open[name] = dlg
        dlg
      end

      # Which page the job window shows (nil = closed).
      def self.main_page
        @main&.visible? ? @main_page : nil
      end

      def self.[](id)
        (@open ||= {})[id]
      end

      # Closes every plugin window (before an update replaces their pages).
      def self.close_all
        (@open || {}).each_value { |d| d.close rescue nil }
        @open = {}
        @main = nil
      end

      # Forget the cached shared css / js (after an update).
      def self.reset!
        @shared = nil
        @icons = nil
      end
    end
  end
end
