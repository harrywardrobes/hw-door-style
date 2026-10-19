require 'json'

module HarryWardrobes
  module DoorStyle
    # Keeps scene names in Settings in step with the model: rename a scene (Scenes panel)
    # and every setting that names it is updated - for now Settings > HubSpot > Pictures to
    # HubSpot. A scene is followed by its persistent id, so a rename isn't mistaken for a
    # new scene. If the Settings window is open, its fields change too.
    module Scenes
      # { model guid => { page persistent id => name } }
      def self.known
        @known ||= {}
      end

      def self.snapshot(model)
        model.pages.to_h { |p| [p.persistent_id, p.name] }
      end

      # Renamed scenes since last time: [[old, new]].
      def self.renames(model)
        before = known[model.guid] || {}
        now = snapshot(model)
        known[model.guid] = now
        now.filter_map { |id, name| [before[id], name] if before[id] && before[id] != name }
      end

      # Applies renames to the settings (any case). Returns true if anything changed.
      def self.rename_in_settings(pairs)
        return false if pairs.empty?
        s = Settings.get
        pics = Array(s['hubspot_pictures']).map { |r| r.dup }
        changed = false
        pairs.each do |old, new|
          pics.each do |r|
            list = Array(r['scenes'])
            next unless list.any? { |x| x.strip.casecmp?(old.strip) }
            r['scenes'] = list.map { |x| x.strip.casecmp?(old.strip) ? new : x }
            changed = true
          end
        end
        return false unless changed
        Settings.save(s.merge('hubspot_pictures' => pics))
        pairs.each { |old, new| Dialog['settings']&.execute_script("sceneRenamed(#{JSON.generate(old)}, #{JSON.generate(new)})") rescue nil }
        Log.info("scene renamed: #{pairs.map { |o, n| "#{o} -> #{n}" }.join(', ')} (Pictures to HubSpot updated)")
        true
      end

      class PagesWatch < Sketchup::PagesObserver
        def initialize(model)
          super()
          @model = model
        end

        # SketchUp calls this before the new name is set, so look a moment later.
        def onContentsModified(_pages)
          return if @pending
          @pending = true
          UI.start_timer(0.1, false) do
            @pending = false
            begin
              Scenes.rename_in_settings(Scenes.renames(@model)) if @model.valid?
            rescue StandardError => e
              Log.error('scenes', e)
            end
          end
        end
      end

      class AppWatch < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); Scenes.watch(model); end
        def onOpenModel(model); Scenes.watch(model); end
        def onActivateModel(model); Scenes.watch(model); end
      end

      def self.watch(model)
        return unless model
        @watched ||= {}
        known[model.guid] = snapshot(model)
        return if @watched[model.guid]
        model.pages.add_observer(PagesWatch.new(model))
        @watched[model.guid] = true
      end

      def self.start
        return if @started
        @started = true
        Sketchup.add_observer(AppWatch.new)
        watch(Sketchup.active_model)
      end
    end
  end
end
