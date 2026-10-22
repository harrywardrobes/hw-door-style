require 'json'

module HarryWardrobes
  module DoorStyle
    # Every window is html/<name>.html. A page marks where the shared look goes
    # with <!--HW--> (html/hw.css + html/hw.js are put there) and receives its
    # data through the literal /*DATA*/null in its script:
    #
    #   var D = /*DATA*/null;
    #
    # Dialog.open keeps one window per id: opening it again closes the old one.
    module Dialog
      DIR = File.join(PATH, 'html')

      def self.shared
        @shared ||= "<style>\n#{File.read(File.join(DIR, 'hw.css'))}</style>\n" \
                    "<script>\n#{File.read(File.join(DIR, 'hw.js'))}</script>"
      end

      # Highlight something the next time window name opens (Workshop > Fix this): sel = CSS
      # selectors to outline, note = what to do (a banner at the top), js = run first (e.g.
      # switch to the right Settings section). The page finds them once it has drawn.
      def self.focus_next(name, sel: [], note: nil, js: nil)
        (@focus ||= {})[name.to_s] = { 'sel' => Array(sel), 'note' => note, 'js' => js }
      end

      # The page's HTML with the shared look and data filled in.
      def self.html(name, data = nil)
        page = File.read(File.join(DIR, "#{name}.html"))
        f = (@focus ||= {}).delete(name.to_s)
        page = page.sub('<!--HW-->') { shared + (f ? "\n<script>var HW_FOCUS = #{JSON.generate(f)};</script>" : '') }
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
        @open[id]&.close
        dlg = UI::HtmlDialog.new(dialog_title: title, preferences_key: key, width: width, height: height,
                                 resizable: resizable, scrollable: scrollable,
                                 style: utility ? UI::HtmlDialog::STYLE_UTILITY : UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(html(name, data))
        dlg.add_action_callback('cancel') { |_c| dlg.close }
        @open[id] = dlg
      end

      def self.[](id)
        (@open ||= {})[id]
      end

      # Closes every plugin window (before an update replaces their pages).
      def self.close_all
        (@open || {}).each_value { |d| d.close rescue nil }
        @open = {}
      end

      # Forget the cached shared css / js (after an update).
      def self.reset!
        @shared = nil
      end
    end
  end
end
