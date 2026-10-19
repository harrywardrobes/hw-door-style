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

      def self.file_for(dir, model, label, scene, ext)
        Report.safe_name("#{File.basename(model.path, '.skp')} - #{label} - #{scene}") + ".#{ext}"
      end

      # picks: { field => [scene names] }. Returns { field => [{ 'scene', 'path', 'thumb' }] }.
      def self.export(model, picks, cfg = config)
        dir = out_dir(model, cfg['folder'])
        FileUtils.mkdir_p(dir)
        view = model.active_view
        pages = model.pages
        was_page = pages.selected_page
        was_cam = Sketchup::Camera.new(view.camera.eye, view.camera.target, view.camera.up, view.camera.perspective?, view.camera.fov)
        po = model.options['PageOptions']
        was_trans = po['ShowTransition']
        po['ShowTransition'] = false
        labels = cfg['rows'].to_h { |r| [r['field'], r['label']] }
        thumb_file = File.join(Dir.tmpdir, "hw_thumb_#{Process.pid}.jpg")
        out = {}
        begin
          picks.each do |field, scenes|
            out[field] = Array(scenes).filter_map do |name|
              page = pages[name] or next
              pages.selected_page = page
              view.refresh
              path = File.join(dir, file_for(dir, model, labels[field] || field, name, cfg['format']))
              opts = { filename: path, width: cfg['width'], height: cfg['height'], antialias: true, transparent: false }
              opts[:compression] = 0.9 if cfg['format'] == 'jpg'
              view.write_image(opts) or raise "Couldn't save #{File.basename(path)}"
              tw = 360
              view.write_image(filename: thumb_file, width: tw, height: (tw * cfg['height'] / cfg['width'].to_f).round, antialias: true, compression: 0.7)
              { 'scene' => name, 'path' => path, 'name' => File.basename(path),
                'thumb' => "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(thumb_file))}" }
            end
          end
        ensure
          File.delete(thumb_file) if File.exist?(thumb_file)
          if was_page
            pages.selected_page = was_page
          else
            view.camera = was_cam
          end
          po['ShowTransition'] = was_trans
        end
        out
      end

      # uploads: { field => { 'paths' => [...], 'mode' => 'replace' | 'add' } }.
      # Returns { field => number uploaded }.
      def self.upload(room_id, uploads, cfg = config, &progress)
        current = HubSpot.read_one('listings', room_id, uploads.keys)['properties'] || {}
        props = {}
        done = {}
        uploads.each do |field, u|
          ids = Array(u['paths']).map do |path|
            progress&.call(File.basename(path))
            HubSpot.upload(path, cfg['files_folder'])
          end
          next if ids.empty?
          old = current[field].to_s.split(';').reject(&:empty?)
          props[field] = (u['mode'] == 'add' ? old + ids : ids).uniq.join(';')
          done[field] = ids.size
        end
        HubSpot.update_room(room_id, props) unless props.empty?
        done
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
        dlg.add_action_callback('make') do |_c, json|
          picks = JSON.parse(json)
          r = begin
            { 'made' => export(model, picks, cfg) }
          rescue StandardError => e
            Log.error('hubspot pictures', e)
            { 'error' => e.message }
          end
          dlg.execute_script("made(#{JSON.generate(r)})")
        end
        dlg.add_action_callback('openFolder') do |_c|
          d = out_dir(model, cfg['folder'])
          UI.openURL("file:///#{d.tr('\\', '/')}") if Dir.exist?(d)
        end
        dlg.add_action_callback('upload') do |_c, json|
          ups = JSON.parse(json)
          r = begin
            done = upload(l['room_id'], ups, cfg) { |name| dlg.execute_script("uploading(#{JSON.generate(name)})") }
            { 'done' => done }
          rescue StandardError => e
            Log.error('hubspot upload', e) unless e.is_a?(HubSpot::Error)
            { 'error' => e.message }
          end
          dlg.execute_script("uploaded(#{JSON.generate(r)})")
          after&.call if r['done']
        end
        dlg.show
      end
    end
  end
end
