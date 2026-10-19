# One-off: re-order Component Options in the library (Components V19+).
#
# Component Options lists attributes alphabetically by attribute name, so each
# visible attribute gets a section prefix (<letter><nn>_). Labels you see are
# unchanged; formulas are rewritten to the new names.
#
#   A size / framework  B doors  C depths  D facing  E div + end panel / compartments
#   F shelves  G rails  H drawers / runners / fitting  I wall & topped  J runout
#
#   load 'tools/reorder_options.rb'
#   HWReorder.apply!(Sketchup.active_model)   # inside YOUR operation
module HWReorder
  DCD = 'dynamic_attributes'.freeze

  # old key (any old section prefix removed) => new key
  MAP = {
    # A - size / framework / cabinet
    'frame_1_label' => 'a00_size_label', 'size_1_label' => 'a00_size_label', 'size_label' => 'a00_size_label',
    'cab_1_label' => 'a00_size_label',
    'frame_width' => 'a01_frame_width', 'size_width' => 'a01_size_width', 'width' => 'a01_width', 'cab_width' => 'a01_cab_width',
    'frame_size' => 'a01_frame_size',
    'frame_height_ceiling' => 'a02_frame_height_ceiling', 'frame_height' => 'a02_frame_height', 'size_height' => 'a02_size_height',
    'ceiling_height' => 'a02_ceiling_height', 'unit_height' => 'a02_unit_height', 'cab_height' => 'a02_cab_height',
    'depth' => 'a03_depth', 'size_depth' => 'a03_size_depth', 'cab_depth' => 'a03_cab_depth',
    'size_depth_finished' => 'a04_size_depth_finished', 'depth_finished' => 'a04_depth_finished',
    'frame_support' => 'a05_frame_support', 'thickness' => 'a06_thickness', 'margin' => 'a07_margin',
    'overhang' => 'a08_overhang', 'coving_height' => 'a08_coving_height', 'rail_width' => 'a09_rail_width',
    'skirting_height' => 'a09_skirting_height',
    # B - doors
    'door_1_label' => 'b00_door_label', 'door_double' => 'b01_door_double', 'double' => 'b01_double',
    'door_width' => 'b02_door_width', 'door_height' => 'b03_door_height', 'door_top_height' => 'b04_door_top_height',
    # C - depths
    'depth_1_label' => 'c00_depth_label', 'depth_fl_div' => 'c01_depth_fl_div', 'depth_sh' => 'c02_depth_sh',
    # D - facing / fillers
    'facing_1_label' => 'd00_facing_label', 'facing_label' => 'd00_facing_label',
    'facing_btm' => 'd01_facing_btm', 'facing_top' => 'd02_facing_top', 'facing_left' => 'd03_facing_left',
    'facing_right' => 'd04_facing_right', 'facing_width' => 'd05_facing_width',
    'fllr_left' => 'd06_fllr_left', 'fllr_right' => 'd07_fllr_right', 'filler_left' => 'd06_filler_left', 'filler_right' => 'd07_filler_right',
    # E - dividers / compartments
    'div_end_1_label' => 'e00_div_label', 'comp_label' => 'e00_comp_label',
    'div_left_div' => 'e01_div_left_div', 'div_right_div' => 'e02_div_right_div',
    'comp_no' => 'e03_comp_no', 'comp_centre_width' => 'e04_comp_centre_width',
    # F - shelves
    'sh_1_label' => 'f00_sh_label', 'sh_label' => 'f00_sh_label', 'sh_no' => 'f01_sh_no',
    'sh_top_height' => 'f02_sh_top_height', 'sh_top_height_calc' => 'f03_sh_top_height_calc', 'sh_depth' => 'f04_sh_depth',
    # G - rails
    'a_1_label' => 'g00_rails_label', 'a_survey_rail_height_btm' => 'g01_survey_rail_height_btm',
    'a_survey_rail_height_top' => 'g02_survey_rail_height_top', 'rail_1_label' => 'g05_rail_label',
    'rail_drop' => 'g06_rail_drop', 'rail_type' => 'g07_rail_type',
    # H - drawers / runners / fitting
    'blum_1_label' => 'h00_blum_label', 'blum_runner_length' => 'h01_blum_runner_length',
    'drwr_1_label' => 'h03_drwr_label', 'drwr_no' => 'h04_drwr_no', 'drwr_front_height' => 'h05_drwr_front_height',
    'drwr_box_height' => 'h06_drwr_box_height', 'drwr_sm_no' => 'h07_drwr_sm_no',
    'drwr_front_sm_height' => 'h08_drwr_front_sm_height', 'drwr_box_sm_height' => 'h09_drwr_box_sm_height',
    'pullout_no' => 'h04_pullout_no', 'pullout_height' => 'h05_pullout_height',
    'fit_1_label' => 'h11_fit_label', 'fitted' => 'h12_fitted',
    # I - wall & topped
    'wall_1_label' => 'i00_wall_label', 'wall_left' => 'i01_wall_left', 'wall_right' => 'i02_wall_right',
    'wall_back' => 'i03_wall_back', 'topped' => 'i04_topped',
    # J - runout
    'runout_1_label' => 'j00_runout_label', 'runout_floor' => 'j01_runout_floor', 'runout_ceiling' => 'j02_runout_ceiling',
    'runout_l' => 'j03_runout_l', 'runout_r' => 'j04_runout_r', 'runout_back_wall' => 'j05_runout_back_wall'
  }.freeze

  HEADERS = { 'a' => 'SIZE', 'b' => 'DOORS', 'c' => 'DEPTHS', 'd' => 'FACING', 'e' => 'DIV + END PANEL',
              'f' => 'SHELVES', 'g' => 'RAILS', 'h' => 'DRAWERS', 'i' => 'WALL / TOPPED', 'j' => 'RUNOUT' }.freeze
  HEADER_KEY = { 'a' => 'a00_size_label', 'b' => 'b00_door_label', 'c' => 'c00_depth_label', 'd' => 'd00_facing_label',
                 'e' => 'e00_div_label', 'f' => 'f00_sh_label', 'g' => 'g00_rails_label', 'h' => 'h00_blum_label',
                 'i' => 'i00_wall_label', 'j' => 'j00_runout_label' }.freeze
  def self.strip(k)
    k.sub(/\A[a-z]\d{1,2}_(?=[a-z])/, '')
  end

  def self.target(k)
    return nil if k.start_with?('_')
    return k if k =~ /\A[a-j]\d\d_/ && MAP.value?(k)
    MAP[k] || MAP[strip(k)]
  end

  def self.objs(d)
    [d] + d.instances
  end

  def self.dict(o)
    o.attribute_dictionary(DCD)
  end

  def self.visible?(d, k)
    objs(d).any? { |o| %w[LIST TEXTBOX VIEW].include?(dict(o)&.[]("_#{k}_access")) }
  end

  # { old_key => new_key } for one unit definition (visible attributes only).
  def self.plan(d)
    dd = dict(d) or return {}
    dd.keys.reject { |k| k.start_with?('_') }.each_with_object({}) do |k, h|
      t = target(k)
      next unless t && t != k && visible?(d, k)
      h[k] = t
    end
  end

  # DC keeps an attribute's settings in "_<name>_<suffix>" keys. Match these
  # exactly, so renaming sh_top_height never touches sh_top_height_calc.
  SUFFIXES = %w[label formlabel access units formulaunits formula options error].freeze

  def self.rename_keys(o, renames)
    dd = dict(o) or return
    renames.each do |old, new|
      pairs = [[old, new]]
      SUFFIXES.each do |sfx|
        pairs << ["_#{old}_#{sfx}", "_#{new}_#{sfx}"]
        pairs << ["_inst__#{old}_#{sfx}", "_inst__#{new}_#{sfx}"]
      end
      pairs.each do |from, to|
        next if dd[from].nil?
        dd[to] = dd[from] if dd[to].nil?
        dd.delete_key(from)
      end
      dd["_#{new}_label"] = new.upcase if dd["_#{new}_label"] || dd[new]
    end
  end

  def self.sub_names(text, renames, prefix)
    renames.reduce(text) do |t, (old, new)|
      t.gsub(/(?<![A-Za-z0-9_!])#{Regexp.escape(prefix)}#{Regexp.escape(old)}(?![A-Za-z0-9_])/i, "#{prefix}#{new.upcase}")
    end
  end

  def self.rewrite_formulas(o, renames, own:)
    dd = dict(o) or return 0
    n = 0
    dd.keys.each do |k|
      next unless k.end_with?('_formula') || k == 'onclick' || k == '_onclick'
      v = dd[k]
      next unless v.is_a?(String)
      nv = own ? sub_names(v, renames, '') : v
      nv = sub_names(nv, renames, 'parent!')
      next if nv == v
      dd[k] = nv
      n += 1
    end
    n
  end

  def self.each_descendant(d, seen = {}, &blk)
    d.entities.each do |e|
      next unless e.respond_to?(:definition)
      cd = e.definition
      next if seen[cd]
      seen[cd] = true
      blk.call(cd)
      each_descendant(cd, seen, &blk)
    end
  end

  def self.rewrite_named(o, renames, unit_name)
    dd = dict(o) or return 0
    n = 0
    dd.keys.each do |k|
      next unless k.end_with?('_formula') || k == 'onclick'
      v = dd[k]
      next unless v.is_a?(String) && v.downcase.include?("#{unit_name.downcase}!")
      nv = sub_names(v, renames, "#{unit_name}!")
      next if nv == v
      dd[k] = nv
      n += 1
    end
    n
  end

  def self.add_header(d, key, title)
    objs(d).each do |o|
      o.set_attribute(DCD, key, '-----')
      { '_access' => 'VIEW', '_formlabel' => title, '_formula' => '"-----"', '_label' => key.upcase,
        '_units' => 'STRING', '_formulaunits' => 'STRING' }.each { |sfx, v| o.set_attribute(DCD, "_#{key}#{sfx}", v) }
    end
  end

  def self.remove_attr(d, key)
    objs(d).each { |o| (dd = dict(o)) && dd.keys.select { |k| k == key || k.start_with?("_#{key}_") }.each { |k| dd.delete_key(k) } }
  end

  def self.apply!(model)
    log = Hash.new { |h, k| h[k] = [] }
    units = model.entities.grep(Sketchup::ComponentInstance).map(&:definition).uniq.reject { |d| d.name == 'floor' }
    plans = units.to_h { |d| [d, plan(d)] }
    renamed_units = plans.reject { |_d, p| p.empty? }

    # Children of each unit that will need parent!NEW, and every parent they have.
    renamed_units.each do |d, renames|
      objs(d).each { |o| rename_keys(o, renames) }
      objs(d).each { |o| log[:formulas] << "#{d.name}:#{rewrite_formulas(o, renames, own: true)}" }
      kids = d.entities.grep(Sketchup::ComponentInstance).map(&:definition).uniq
      kids.each do |k|
        n = objs(k).sum { |o| rewrite_formulas(o, renames, own: false) }
        next if n.zero?
        log[:child_formulas] << "#{d.name}>#{k.name}:#{n}"
        # Other parents of this child that are NOT renamed units: give them an alias.
        k.instances.map(&:parent).grep(Sketchup::ComponentDefinition).uniq.each do |p|
          next if p == d || renamed_units.key?(p)
          renames.each do |old, new|
            next if objs(p).none? { |o| dict(o) && !dict(o)[old].nil? }
            next if objs(p).any? { |o| dict(o) && !dict(o)[new].nil? }
            objs(p).each do |o|
              o.set_attribute(DCD, new, dict(o)&.[](old)) if dict(o) && !dict(o)[old].nil?
              { '_access' => 'NONE', '_label' => new.upcase, '_formula' => old.upcase }.each { |sfx, v| o.set_attribute(DCD, "_#{new}#{sfx}", v) }
            end
            log[:aliases] << "#{p.name}.#{new.upcase}=#{old.upcase}"
          end
        end
      end
      # Parts anywhere inside the unit that name it directly (INT_DRAWER!FLLR_RIGHT),
      # and the unit naming itself (TOPBOX!SH_NO in TOPBOX - missed in V20, fixed in V22).
      names = ([d.name.sub(/#\d+\z/, '')] + objs(d).map { |o| dict(o)&.[]('_name').to_s }).reject(&:empty?).uniq
      self_n = objs(d).sum { |o| names.sum { |nm| rewrite_named(o, renames, nm) } }
      log[:named_refs] << "#{d.name} (itself):#{self_n}" if self_n.positive?
      each_descendant(d) do |dsc|
        n = objs(dsc).sum do |o|
          names.sum { |nm| rewrite_named(o, renames, nm) }
        end
        log[:named_refs] << "#{d.name}>#{dsc.name}:#{n}" if n.positive?
      end
      log[:renamed] << "#{d.name}: #{renames.size}"
    end

    # Section headers: one per section that has options; drop empty ones.
    units.each do |d|
      dd = dict(d) or next
      vis = dd.keys.reject { |k| k.start_with?('_') }.select { |k| visible?(d, k) }
      HEADER_KEY.each do |sec, hk|
        members = vis.select { |k| k =~ /\A#{sec}\d\d_/ && k != hk && k !~ /_label\z/ }
        has_header = vis.any? { |k| k =~ /\A#{sec}\d\d_.*_label\z/ }
        if members.empty?
          vis.select { |k| k =~ /\A#{sec}\d\d_.*_label\z/ }.each { |k| remove_attr(d, k); log[:headers_removed] << "#{d.name}.#{k}" }
        elsif !has_header
          add_header(d, hk, HEADERS[sec])
          log[:headers_added] << "#{d.name}.#{hk}"
        end
      end
      # Wall section title covers topped too.
      %w[i00_wall_label].each { |k| objs(d).each { |o| o.set_attribute(DCD, "_#{k}_formlabel", HEADERS['i']) if dict(o)&.[]("_#{k}_access") } }
    end
    log
  end
end
