require 'json'

module HarryWardrobes
  module DoorStyle
    # Extensions > HW Door Style > Developer - only built when the developer
    # switch is on (Settings > General > Developer, then restart SketchUp).
    module Developer
      def self.enabled?
        Log.debug?
      end

      def self.add_menu(menu)
        return unless enabled?
        dev = menu.add_submenu('Developer')
        dev.add_item('Run tests (all)') { run_tests }
        sub = dev.add_submenu('Run one suite')
        Acceptance::SUITES.each { |s| sub.add_item(s.capitalize) { run_tests([s]) } }
        dev.add_separator
        dev.add_item('Inspect selected component') { inspect_selection }
        dev.add_item('Reload plugin code') { reload }
        dev.add_item('Ruby Console') { Sketchup.send_action('showRubyPanel:') }
      end

      # Runs the acceptance tests on the open model and shows the results.
      def self.run_tests(suites = Acceptance::SUITES)
        model = Sketchup.active_model
        Sketchup.status_text = 'HW Door Style: running tests...'
        started = Time.now
        rows = Acceptance.run(model, suites: suites)
        data = { 'model' => model.title, 'version' => VERSION, 'seconds' => (Time.now - started).round(1),
                 'rows' => rows.map { |r| r.transform_keys(&:to_s) }, 'text' => Acceptance.report_text(rows) }
        dlg = Dialog.open('tests', title: 'HW Door Style - Tests', key: 'hw_tests', width: 860, height: 640, data: data)
        dlg.add_action_callback('rerun') { |_c| dlg.close; run_tests(suites) }
        dlg.show
        Log.info(data['text'].lines.last.to_s.strip)
        rows
      end

      # DC options of the selected component, in the Ruby Console.
      def self.inspect_selection
        inst = Sketchup.active_model.selection.grep(Sketchup::ComponentInstance).first
        return UI.messagebox('Select a component first.') unless inst
        keys = [inst.definition, inst].flat_map { |o| (DC.dict(o)&.keys || []) }.uniq.reject { |k| k.start_with?('_') }.sort
        lines = keys.map do |k|
          v = DC.read(inst, k)
          f = DC.formula_of(inst, k)
          acc = DC.read(inst, "_#{k}_access")
          "#{k.ljust(28)} #{v.inspect.ljust(24)} #{acc && acc != 'NONE' ? "[#{acc}] " : ''}#{f.empty? ? '' : "= #{f}"}"
        end
        puts "\n== #{Finder.label(inst)} (#{inst.definition.name})", lines
        Sketchup.send_action('showRubyPanel:')
      end

      # Loads every plugin file again (menus and toolbar stay as they are).
      def self.reload
        Updater.reload!
      end
    end
  end
end
