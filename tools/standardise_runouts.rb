# One-off: standardise runouts in the component library (Components V19+).
#
#   load 'tools/standardise_runouts.rb'
#   HWStandardise.apply!(Sketchup.active_model)   # call inside YOUR operation
#
# Does NOT start or commit an operation itself, so it can be tested inside an
# aborted operation. Requires the HW Door Style plugin (Standardise, DC) loaded.
module HWStandardise
  DS = HarryWardrobes::DoorStyle
  DCD = 'dynamic_attributes'.freeze

  WALL_BACK_UNITS = %w[WARDROBE WALK-IN LINEN_PRESS TOPBOX END_PAN BXEND BOOKCASE].freeze
  NEW_TOPPED_UNITS = %w[END_PAN BXEND BULLNOSE BOOKCASE FACING_BLOCK_L FACING_BLOCK_R].freeze
  NO_BACK_UNITS = %w[BULLNOSE].freeze
  FLOOR_CEILING_PARTS = %w[FACING_L INT_FACING_L FACING_R INT_FACING_R].freeze
  RUNOUT_KEYS = %w[runout_floor runout_ceiling runout_l runout_r runout_back_wall topped wall_left wall_right wall_back].freeze
  NO_RUNOUT_UNITS = %w[INT_DRAWER INT_DRAWER_PLUS SHOE_PULL_OUT].freeze
  FACING_TOP = %w[WRD_FACING_TOP LIN_FACING_TOP TPBX_FACING_TOP].freeze
  FACING_BTM = %w[WRD_FACING_BTM WLK_FACING_BTM LIN_FACING_BTM TPBX_FACING_BTM].freeze
  BKS_FLOOR = %w[BKS_FACING_L BKS_FACING_R BKS_END_PAN_L BKS_END_PAN_R].freeze
  TOPPED_OPTIONS = '&Topped%20Off=1&To%20Ceiling=0&'.freeze

  def self.base(d)
    d.name.sub(/#\d+\z/, '')
  end

  def self.defs(model, names)
    model.definitions.select { |d| names.include?(base(d)) }
  end

  def self.objs(d)
    [d] + d.instances
  end

  def self.dict(o)
    o.attribute_dictionary(DCD)
  end

  def self.has?(d, key)
    objs(d).any? { |o| dict(o) && !dict(o)[key].nil? }
  end

  def self.set_all(d, h)
    objs(d).each { |o| h.each { |k, v| o.set_attribute(DCD, k, v) } }
  end

  # --- 2. TOPPED ---------------------------------------------------------
  def self.topped!(model, log)
    model.definitions.reject(&:image?).each do |d|
      objs(d).each do |o|
        dd = dict(o) or next
        dd.keys.each do |k|
          nk = k.sub(/\A(_?(?:inst__)?)frame_topped(?=_|\z)/, '\1topped')
          next if nk == k
          v = dd[k]
          v = 'TOPPED' if k == '_frame_topped_label'
          dd[nk] = v if dd[nk].nil?
          dd.delete_key(k)
          log[:topped_renamed] |= [base(d)]
        end
        dd.keys.each do |k|
          v = dd[k]
          next unless k.end_with?('_formula') && v.is_a?(String) && v =~ /\bFRAME_TOPPED\b/
          dd[k] = v.gsub(/\bFRAME_TOPPED\b/, 'TOPPED')
          log[:topped_formulas] += 1
        end
        if dd['_topped_options'] || dd['_topped_label']
          dd['_topped_options'] = TOPPED_OPTIONS
          dd['_topped_formlabel'] = 'Topped off?'
        end
      end
    end
    defs(model, NEW_TOPPED_UNITS).each do |d|
      next if has?(d, 'topped')
      set_all(d, '_topped_access' => 'LIST', '_topped_formlabel' => 'Topped off?', '_topped_formulaunits' => 'STRING',
                 '_topped_label' => 'TOPPED', '_topped_options' => TOPPED_OPTIONS, '_topped_units' => 'BOOLEAN', 'topped' => '0')
      log[:topped_added] << base(d)
    end
  end

  # --- 3. WALL_BACK ------------------------------------------------------
  def self.wall_back!(model, log)
    defs(model, WALL_BACK_UNITS).each do |d|
      next if has?(d, 'wall_back')
      set_all(d, '_wall_back_access' => 'LIST', '_wall_back_formlabel' => 'Wall back', '_wall_back_formulaunits' => 'STRING',
                 '_wall_back_label' => 'WALL_BACK', '_wall_back_options' => '&TRUE=TRUE&FALSE=FALSE&', '_wall_back_units' => 'STRING',
                 'wall_back' => 'TRUE')
      log[:wall_back_added] << base(d)
    end
  end

  # --- 4. facings ---------------------------------------------------------
  def self.formula!(d, key, new_formula)
    objs(d).each do |o|
      dd = dict(o) or next
      %W[_#{key}_formula _inst__#{key}_formula].each { |fk| dd[fk] = new_formula if dd[fk] }
    end
    d.set_attribute(DCD, "_#{key}_formula", new_formula)
  end

  def self.read_formula(d, key)
    objs(d).map { |o| dict(o)&.[]("_#{key}_formula") }.compact.first
  end

  def self.facings!(model, log)
    defs(model, FACING_TOP).each do |d|
      f = read_formula(d, 'lenz').to_s
      next if f =~ /RUNOUT_CEILING/i
      formula!(d, 'lenz', "#{f} + parent!RUNOUT_CEILING")
      log[:facings] << "#{base(d)} lenz +ceiling"
    end
    (defs(model, FACING_BTM) + defs(model, BKS_FLOOR)).each do |d|
      f = read_formula(d, 'lenz').to_s
      next if f =~ /RUNOUT_FLOOR/i
      formula!(d, 'lenz', "#{f} + parent!RUNOUT_FLOOR")
      z = read_formula(d, 'z').to_s.strip
      formula!(d, 'z', z.empty? || z == '0' ? '-parent!RUNOUT_FLOOR' : "#{z} - parent!RUNOUT_FLOOR")
      log[:facings] << "#{base(d)} lenz/z +floor"
    end
    # Facing blocks: full-height facings take floor AND ceiling.
    defs(model, FLOOR_CEILING_PARTS).each do |d|
      f = read_formula(d, 'lenz').to_s
      next if f.strip.empty?
      add = []
      add << 'parent!RUNOUT_FLOOR' unless f =~ /RUNOUT_FLOOR/i
      add << 'parent!RUNOUT_CEILING' unless f =~ /RUNOUT_CEILING/i
      next if add.empty?
      formula!(d, 'lenz', ([f] + add).join(' + '))
      if add.include?('parent!RUNOUT_FLOOR')
        z = read_formula(d, 'z').to_s.strip
        formula!(d, 'z', z.empty? || z == '0' ? '-parent!RUNOUT_FLOOR' : "#{z} - parent!RUNOUT_FLOOR")
      end
      log[:facings] << "#{base(d)} lenz +#{add.map { |a| a[/FLOOR|CEILING/].downcase }.join('+')}"
    end
  end

  # BULLNOSE etc.: no back runout at all.
  def self.drop_back!(model, log)
    defs(model, NO_BACK_UNITS).each do |d|
      used = false
      DS::Finder.each_instance(d.entities) { |i| [i, i.definition].each { |o| dict(o)&.each_pair { |k, v| used = true if k.end_with?('_formula') && v.to_s =~ /RUNOUT_BACK/i } } }
      next log[:kept_back] << base(d) if used
      objs(d).each { |o| (dd = dict(o)) && dd.keys.grep(/\A_?(inst__)?(runout_back_wall|zz_runout_back|wall_back)(_|\z)/).each { |k| dd.delete_key(k) } }
      log[:back_removed] << base(d)
    end
  end

  # Every runout / switch shows in Component Options (access LIST).
  def self.visible!(model, log)
    model.entities.grep(Sketchup::ComponentInstance).map(&:definition).uniq.each do |d|
      RUNOUT_KEYS.each do |k|
        next unless has?(d, k)
        objs(d).each do |o|
          next unless dict(o)
          next if dict(o)["_#{k}_access"] == 'LIST'
          o.set_attribute(DCD, "_#{k}_access", 'LIST')
          log[:made_visible] |= ["#{base(d)}.#{k}"]
        end
      end
    end
  end

  # --- 5. switched values ------------------------------------------------
  # Replace parent!USER with parent!ZZ in every formula, then give every parent of
  # a changed part a ZZ attribute: units get unit_formula, groups pass it through.
  def self.wire!(model, user, zz, log)
    user_re = /parent!#{user}\b/i
    changed = model.definitions.reject(&:image?).select do |d|
      objs(d).any? { |o| (dd = dict(o)) && dd.keys.any? { |k| k.end_with?('_formula') && dd[k].to_s =~ user_re } }
    end
    changed.each do |d|
      objs(d).each do |o|
        dd = dict(o) or next
        dd.keys.each do |k|
          next unless k.end_with?('_formula') && dd[k].to_s =~ user_re
          dd[k] = dd[k].gsub(user_re, "parent!#{zz}")
          log[:wired] += 1
        end
      end
    end
    queue = changed.flat_map { |d| d.instances.map(&:parent) }.grep(Sketchup::ComponentDefinition).uniq
    done = {}
    until queue.empty?
      p = queue.shift
      next if done[p]
      done[p] = true
      next if has?(p, zz.downcase)
      own = has?(p, user.downcase) && read_formula(p, user.downcase).to_s.strip.empty?
      f = if own
            yield(p)
          else
            queue.concat(p.instances.map(&:parent).grep(Sketchup::ComponentDefinition))
            "parent!#{zz}"
          end
      cur = objs(p).map { |o| dict(o)&.[](user.downcase) }.compact.first.to_f
      set_all(p, "_#{zz.downcase}_access" => 'NONE', "_#{zz.downcase}_label" => zz, "_#{zz.downcase}_formula" => f,
                 "_#{zz.downcase}_formulaunits" => 'CENTIMETERS', zz.downcase => cur)
      log[:zz_added] << "#{base(p)}.#{zz}=#{f}"
    end
  end

  # --- 6. drawers without runouts --------------------------------------
  def self.drop_runouts!(model, log)
    defs(model, NO_RUNOUT_UNITS).each do |d|
      used = false
      DS::Finder.each_instance(d.entities) do |i|
        [i, i.definition].each { |o| dict(o)&.each_pair { |k, v| used = true if k.end_with?('_formula') && v.to_s =~ /RUNOUT|SCRIBE/i } }
      end
      next log[:kept_runouts] << base(d) if used
      objs(d).each do |o|
        dd = dict(o) or next
        dd.keys.grep(/\A_?(inst__)?(runout|scribe)_/).each { |k| dd.delete_key(k) }
      end
      log[:runouts_removed] << base(d)
    end
  end

  def self.apply!(model)
    log = Hash.new { |h, k| h[k] = [] }
    log[:topped_formulas] = 0
    log[:wired] = 0
    log[:scribe] = DS::Standardise.run(model)
    topped!(model, log)
    wall_back!(model, log)
    facings!(model, log)
    wire!(model, 'RUNOUT_BACK_WALL', 'ZZ_RUNOUT_BACK', log) do |p|
      has?(p, 'wall_back') ? 'IF(WALL_BACK="TRUE", RUNOUT_BACK_WALL, 0)' : 'RUNOUT_BACK_WALL'
    end
    wire!(model, 'RUNOUT_CEILING', 'ZZ_RUNOUT_CEILING', log) do |p|
      has?(p, 'topped') ? 'IF(TOPPED, 0, RUNOUT_CEILING)' : 'RUNOUT_CEILING'
    end
    drop_runouts!(model, log)
    drop_back!(model, log)
    visible!(model, log)
    log
  end
end
