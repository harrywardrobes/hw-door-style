require 'json'
require 'base64'
require 'fileutils'
require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # Pictures for the HubSpot Room (Extensions > HW Door Style > HubSpot > Pictures to HubSpot).
    #
    # 1. Tick the scenes for each picture field (Renders, Survey Floor Plan, Survey Door
    #    Dimensions); Settings > HubSpot sets which scenes are ticked to start with.
    # 2. Make pictures: each scene is saved as an image next to the .skp (in the
    #    "SURVEY RENDERS" folder by default) and shown in the window.
    # 3. Upload: the ticked pictures go to HubSpot and onto the Room's field, replacing
    #    or adding to what is there (per field).
    module HubSpotPictures
      def self.config
        s = Settings.get
        rows = Array(s['hubspot_pictures']).select { |r| r.is_a?(Hash) && !r['field'].to_s.empty? }
        w, h = s['hubspot_picture_size'].to_s.downcase.split('x').map(&:to_i)
        {
          'rows' => rows.map { |r| { 'field' => r['field'], 'label' => r['label'].to_s.empty? ? r['field'] : r['label'], 'scenes' => Array(r['scenes']).map(&:to_s) } },
          'width' => w.to_i > 0 ? w : 1920, 'height' => h.to_i > 0 ? h : 1080,
          'format' => s['hubspot_picture_format'].to_s == 'png' ? 'png' : 'jpg',
          'folder' => s['hubspot_picture_folder'].to_s, 'mode' => s['hubspot_picture_mode'].to_s == 'add' ? 'add' : 'replace',
          'files_folder' => s['hubspot_files_folder'].to_s.empty? ? '/crm-properties-file-values' : s['hubspot_files_folder'].to_s
        }
      end

      # Scene names in this model ticked by default for a field (any case).
      def self.preset(names, wanted)
        w = wanted.map { |x| x.strip.downcase }
        names.select { |n| w.include?(n.strip.downcase) }
      end

      def self.out_dir(model, folder)
        base = File.dirname(model.path)
        folder.to_s.strip.empty? ? base : File.join(base, folder.strip)
      end

      # "Master Bedroom - view 3, WILLIAMS Rebecca.jpg". Views are numbered across every
      # picture made, carrying on from the highest number already in the folder, so
      # earlier pictures are never overwritten.
      def self.stem(link)
        "#{HubSpotRoom.room_part(link['room_name'])} - view "
      end

      def self.file_for(link, n, ext)
        Report.safe_name("#{stem(link)}#{n}, #{HubSpotRoom.customer_tag(link)}") + ".#{ext}"
      end

      def self.last_view(dir, link)
        return 0 unless Dir.exist?(dir)
        pat = /\A#{Regexp.escape(Report.safe_name(stem(link)))}\s*(\d+),/i
        Dir.children(dir).map { |f| f[pat, 1].to_i }.max.to_i
      end

      # Making pictures, one scene at a time (so the window can show progress):
      #   job = Shoot.new(model, cfg, link); job.shot(field, scene) ...; job.finish
      # finish puts back the scene / camera that was showing.
      class Shoot
        attr_reader :out

        def initialize(model, cfg, link)
          @model = model
          @cfg = cfg
          @link = link
          @dir = HubSpotPictures.out_dir(model, cfg['folder'])
          FileUtils.mkdir_p(@dir)
          @view = model.active_view
          @pages = model.pages
          @was_page = @pages.selected_page
          c = @view.camera
          @was_cam = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.fov)
          @po = model.options['PageOptions']
          @was_trans = @po['ShowTransition']
          @po['ShowTransition'] = false
          @n = HubSpotPictures.last_view(@dir, link)
          @thumb = File.join(Dir.tmpdir, "hw_thumb_#{Process.pid}.jpg")
          @out = {}
        end

        def shot(field, name)
          (@out[field] ||= [])
          page = @pages[name] or return nil
          @pages.selected_page = page
          @view.refresh
          @n += 1
          path = File.join(@dir, HubSpotPictures.file_for(@link, @n, @cfg['format']))
          opts = { filename: path, width: @cfg['width'], height: @cfg['height'], antialias: true, transparent: false }
          opts[:compression] = 0.9 if @cfg['format'] == 'jpg'
          @view.write_image(opts) or raise "Couldn't save #{File.basename(path)}"
          tw = 360
          @view.write_image(filename: @thumb, width: tw, height: (tw * @cfg['height'] / @cfg['width'].to_f).round, antialias: true, compression: 0.7)
          pic = { 'scene' => name, 'path' => path, 'name' => File.basename(path),
                  'thumb' => "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(@thumb))}" }
          @out[field] << pic
          pic
        end

        def finish
          File.delete(@thumb) if File.exist?(@thumb)
          @was_page ? (@pages.selected_page = @was_page) : (@view.camera = @was_cam)
          @po['ShowTransition'] = @was_trans
          @out
        end
      end

      # All at once (no window). picks: { field => [scene names] }.
      def self.export(model, picks, cfg = config, link = HubSpotRoom.link(model))
        job = Shoot.new(model, cfg, link)
        picks.each { |field, scenes| Array(scenes).each { |n| job.shot(field, n) } }
        job.out
      ensure
        job&.finish
      end

      # New value of a Room picture field: the new file ids, or added to the old ones.
      def self.merged(old, ids, mode)
        o = old.to_s.split(';').reject(&:empty?)
        (mode == 'add' ? o + ids : ids).uniq.join(';')
      end

      def self.show(after = nil)
        return unless HubSpotRoom.ready?
        model = Sketchup.active_model
        l = HubSpotRoom.link(model)
        return UI.messagebox("Link this file to a HubSpot room first (HubSpot > Link this file).") unless l
        return UI.messagebox('Save the SketchUp file first - the pictures are saved next to it.') if model.path.to_s.empty?
        cfg = config
        names = model.pages.map(&:name)
        return UI.messagebox("This file has no scenes yet.\n\nAdd scenes (View > Animation > Add Scene) for the views you want as pictures.") if names.empty?
        data = cfg.merge('room' => l['room_name'], 'scenes' => names, 'dir' => out_dir(model, cfg['folder']),
                         'rows' => cfg['rows'].map { |r| r.merge('ticked' => preset(names, r['scenes'])) })
        dlg = Dialog.open('hubspot_pictures', title: 'HW - Pictures to HubSpot', key: 'hw_hubspot_pictures', width: 820, height: 680, data: data)
        labels = cfg['rows'].to_h { |r| [r['field'], r['label']] }

        dlg.add_action_callback('make') do |_c, json|
          picks = JSON.parse(json)
          job = begin
            Shoot.new(model, cfg, l)
          rescue StandardError => e
            next dlg.execute_script("made(#{JSON.generate('error' => e.message)})")
          end
          steps = picks.flat_map { |f, scenes| Array(scenes).map { |n| ["Making #{labels[f] || f}: #{n}", -> { job.shot(f, n) }] } }
          Steps.run(dlg, steps,
                    done: ->(_r) { dlg.execute_script("made(#{JSON.generate('made' => job.finish)})") },
                    fail: lambda { |e|
                      job.finish
                      Log.error('hubspot pictures', e)
                      dlg.execute_script("made(#{JSON.generate('error' => e.message)})")
                    })
        end
        dlg.add_action_callback('openFolder') do |_c|
          d = out_dir(model, cfg['folder'])
          UI.openURL("file:///#{d.tr('\\', '/')}") if Dir.exist?(d)
        end
        dlg.add_action_callback('upload') do |_c, json|
          ups = JSON.parse(json)
          ids = Hash.new { |h, k| h[k] = [] }
          current = {}
          steps = [['Reading the Room', -> { current = HubSpot.read_one('listings', l['room_id'], ups.keys)['properties'] || {} }]]
          ups.each do |field, u|
            Array(u['paths']).each do |path|
              steps << ["Uploading #{File.basename(path)}", -> { ids[field] << HubSpot.upload(path, cfg['files_folder']) }]
            end
          end
          steps << ['Putting the pictures on the Room', lambda {
            props = ids.to_h { |field, list| [field, merged(current[field], list, ups[field]['mode'])] }
            HubSpot.update_room(l['room_id'], props) unless props.empty?
          }]
          Steps.run(dlg, steps,
                    done: lambda { |_r|
                      dlg.execute_script("uploaded(#{JSON.generate('done' => ids.transform_values(&:size))})")
                      after&.call
                    },
                    fail: ->(e) { dlg.execute_script("uploaded(#{JSON.generate('error' => e.message, 'done' => ids.transform_values(&:size))})") })
        end
        dlg.show
      end
    end
  end
end
