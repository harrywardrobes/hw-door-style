require 'json'

module HarryWardrobes
  module DoorStyle
    # Drawer box finish (Interfit melamine range + Lissa Oak).
    #
    # Paints only the drawer box parts (settings: drawer_box_parts, default
    # DRW_BOX / DRW_BOX_SIDE / DRW_BOX_END / DRW_BOX_BASE). Runners, hooks and
    # other hardware are never touched. Optionally sets each drawer unit's
    # DRWR_BOX_THICKNESS to the finish's board thickness and redraws the unit.
    module DrawerBox
      DEFAULT = 'Lissa Oak'.freeze

      def self.library
        @library ||= JSON.parse(File.read(Colours::FILE))['drawer_boxes']
      end

      def self.names
        library.map { |c| c['name'] }
      end

      def self.spec(name)
        library.find { |c| c['name'] == name } || library.find { |c| c['name'] == DEFAULT }
      end

      def self.thickness_mm(name)
        spec(name)['thickness_mm'].to_f
      end

      # Uses an existing material of that name; otherwise a door-library colour
      # (Lissa Oak) or a plain-colour approximation.
      def self.material(model, name)
        s = spec(name)
        mname = s['material']
        m = model.materials[mname]
        return m if m
        return Colours.material(model, mname) if Colours.spec(mname)
        m = model.materials.add(mname)
        m.color = Sketchup::Color.new(*s['rgb'])
        m.set_attribute(DICT, 'library', true)
        m
      end

      def self.part?(inst)
        list = Settings.names('drawer_box_parts')
        inst.is_a?(Sketchup::ComponentInstance) && (Finder.names_for(inst) & list).any?
      end

      # --- thickness ------------------------------------------------------

      def self.dc(obj)
        obj.attribute_dictionary('dynamic_attributes')
      end

      # Drawer units = instances whose own DRWR_BOX_THICKNESS formula is a plain number
      # (pass-through copies use parent! references and are left alone).
      def self.units(model)
        found = []
        Finder.each_instance(model.entities) do |inst|
          [dc(inst), dc(inst.definition)].compact.each do |d|
            f = d['_drwr_box_thickness_formula'].to_s.strip
            next unless f =~ /\A-?\d+(\.\d+)?\z/
            found << inst
            break
          end
        end
        found.uniq
      end

      def self.current_mm(unit)
        v = dc(unit)&.[]('drwr_box_thickness') || dc(unit.definition)&.[]('drwr_box_thickness')
        v ? (v.to_f * 25.4).round(1) : nil
      end

      # Any drawer inside the unit pulled open (onClick ANIMATE moved it)?
      def self.open?(unit)
        open = false
        Finder.each_instance(unit.definition.entities) do |i|
          d = dc(i)
          next unless d && d['onclick'].to_s =~ /ANIMATE/i
          open ||= d['_onclick_state1'].to_s.to_i != 0 || d['y'].to_f.abs > 0.01
        end
        open
      end

      # Sets DRWR_BOX_THICKNESS on both dictionaries of each unit that needs it.
      # Call inside an operation. Returns { changed: [units], open: [names] }.
      def self.set_thickness(model, name)
        mm = thickness_mm(name)
        res = { changed: [], open: [] }
        units(model).each do |u|
          next if (current_mm(u).to_f - mm).abs < 0.05
          if open?(u)
            res[:open] << Finder.label(u)
            next
          end
          [u, u.definition].each do |o|
            o.set_attribute('dynamic_attributes', '_drwr_box_thickness_formula', format('%g', mm / 10.0))
            o.set_attribute('dynamic_attributes', 'drwr_box_thickness', mm / 25.4)
          end
          res[:changed] << u
        end
        res
      end

      def self.size_mm(inst)
        b = inst.bounds
        [b.width, b.height, b.depth].map { |v| (v.to_f * 25.4).round(1) }
      end

      def self.formula_errors(inst)
        errs = []
        check = lambda do |o, label|
          d = dc(o) or return
          d.each_pair { |k, v| errs << "#{label}: #{k}" if k.end_with?('_error') && v.to_s.include?('subformula-error') }
        end
        check.call(inst, Finder.label(inst))
        Finder.each_instance(inst.definition.entities) { |i| check.call(i, Finder.label(i)) }
        errs
      end

      # Redraws each unit through the Dynamic Components engine and checks it.
      # Returns a list of problems (empty = all good).
      def self.redraw(units)
        problems = []
        klass = defined?($dc_observers) && $dc_observers ? $dc_observers.get_latest_class : nil
        return ['Dynamic Components extension not available - units not redrawn'] unless klass
        units.each do |u|
          before = size_mm(u)
          klass.redraw_with_undo(u)
          after = size_mm(u)
          if before.zip(after).any? { |a, b| (a - b).abs > 0.5 }
            problems << "#{Finder.label(u)} changed size #{before.join('x')} -> #{after.join('x')} mm"
          end
          formula_errors(u).first(5).each { |e| problems << "Formula error in #{e}" }
        end
        problems
      end
    end
  end
end
