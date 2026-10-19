# One-off (Components V21): the bridge is built from its door height.
#
#   BRIDGE_FRAME     new "Top door height (mm)" (b02, default 460 = TOPBOX top door).
#                    Frame height = door + facing top (unless topped) + margin + half a board.
#                    "Ceiling height (mm)" (a02) is now typed / set by the plugin, not the
#                    stretched size; the frame positions itself so its top is at the ceiling
#                    (Z formula). "Height below bridge" removed.
#   BRIDGE_SKELETON  same Ceiling height / Top door height / Topped options; sits under the
#                    frame (Z = ceiling - frame height - soffit and MDF build-up).
#
# The plugin fills both numbers from the ceiling height (pencil / ceiling button) and
# Settings > Components > Top door height. Without the plugin, type them in Component Options.
#
#   load 'tools/bridge_door_height.rb'
#   HWBridgeDoor.apply!(Sketchup.active_model, ceiling_mm: 2400, door_mm: 460)  # inside YOUR operation
#
# Does not open its own undo step.
module HWBridgeDoor
  DCD = 'dynamic_attributes'.freeze

  # Hidden frame height. Named zz_ (calculated, never shown) so the plugin's
  # height search ("frame_height", "ceiling_height"...) never picks it up.
  FRAME_H = 'zz_frame_h'.freeze
  FRAME_HEIGHT = 'IF(I04_TOPPED, B02_DOOR_TOP_HEIGHT + MARGIN + (THICKNESS / 2), ' \
                 'B02_DOOR_TOP_HEIGHT + D02_FACING_TOP + MARGIN + (THICKNESS / 2))'.freeze
  TOPPED_OPTIONS = '&Topped%20Off=1&To%20Ceiling=0&'.freeze
  UP_OPTIONS = '&TRUE=TRUE&FALSE=FALSE&'.freeze

  def self.inch_s(mm) = (mm.to_f / 25.4).to_s

  def self.del(o, *keys)
    d = o.attribute_dictionary(DCD) or return
    keys.each { |k| d.delete_key(k) if d.keys.include?(k) }
  end

  # A visible option (Component Options), on definition and instance.
  def self.option(objs, key, formlabel:, access:, units:, value: nil, options: nil, formula: nil, formulaunits: 'CENTIMETERS')
    objs.each do |o|
      o.set_attribute(DCD, key, value) unless value.nil?
      o.set_attribute(DCD, "_#{key}_label", key.upcase)
      o.set_attribute(DCD, "_#{key}_formlabel", formlabel)
      o.set_attribute(DCD, "_#{key}_access", access)
      o.set_attribute(DCD, "_#{key}_units", units)
      o.set_attribute(DCD, "_#{key}_formulaunits", formulaunits)
      o.set_attribute(DCD, "_#{key}_options", options) if options
      formula ? o.set_attribute(DCD, "_#{key}_formula", formula) : del(o, "_#{key}_formula", "_#{key}_error")
    end
  end

  # A hidden calculated value (formula on the definition only). Given a
  # starting value: a formula that refers to a value DC hasn't stored yet
  # fails on the first redraw.
  def self.calc(defn, inst, key, formula, start = nil)
    defn.set_attribute(DCD, "_#{key}_label", key.upcase)
    defn.set_attribute(DCD, "_#{key}_formula", formula)
    [defn, inst].each { |o| o.set_attribute(DCD, key, start) } unless start.nil?
    del(inst, "_#{key}_formula")
  end

  # Frame height for the starting value (not topped).
  def self.frame_mm(door_mm) = door_mm + 97 + 2 + 9

  # Position / size formula (lenz, z) on the component itself.
  def self.own(defn, inst, attr, formula)
    defn.set_attribute(DCD, "_#{attr}_label", { 'z' => 'Z', 'lenz' => 'LenZ' }[attr])
    defn.set_attribute(DCD, "_#{attr}_access", 'NONE')
    defn.set_attribute(DCD, "_#{attr}_formula", formula)
    del(inst, "_#{attr}_formula")
  end

  def self.frame(model, ceiling_mm, door_mm, rep)
    d = model.definitions['BRIDGE_FRAME'] or return rep[:missing] << 'BRIDGE_FRAME'
    objs = [d] + d.instances
    d.instances.each { |i| del(i, '_a02_ceiling_height_formula', '_a02_ceiling_height_error') }
    option(objs, 'a02_ceiling_height', formlabel: 'Ceiling height (mm)', access: 'TEXTBOX', units: 'MILLIMETERS',
                                       value: inch_s(ceiling_mm), options: '&')
    objs.each { |o| del(o, *%w[a03_height_below _a03_height_below_access _a03_height_below_formlabel _a03_height_below_formulaunits _a03_height_below_label _a03_height_below_units _a03_height_below_options _a03_height_below_formula _a03_height_below_error]) }
    option(objs, 'b02_door_top_height', formlabel: 'Top door height (mm)', access: 'TEXTBOX', units: 'MILLIMETERS',
                                        value: inch_s(door_mm), options: '&')
    d.instances.each do |i|
      calc(d, i, 'door_height', 'B02_DOOR_TOP_HEIGHT')
      calc(d, i, FRAME_H, FRAME_HEIGHT, inch_s(frame_mm(door_mm)))
      own(d, i, 'lenz', FRAME_H.upcase)
      own(d, i, 'z', "A02_CEILING_HEIGHT - #{FRAME_H.upcase}")
    end
    # Parts inside the frame used the frame's height (A02) - now ZZ_FRAME_H.
    n = 0
    d.entities.grep(Sketchup::ComponentInstance).flat_map { |c| [c, c.definition] }.uniq.each do |o|
      dd = o.attribute_dictionary(DCD) or next
      dd.keys.grep(/_formula\z/).each do |k|
        v = dd[k]
        next unless v.is_a?(String) && v.include?('parent!A02_CEILING_HEIGHT')
        dd[k] = v.gsub('parent!A02_CEILING_HEIGHT', "parent!#{FRAME_H.upcase}")
        n += 1
      end
    end
    rep[:frame_part_formulas] = n
  end

  def self.skeleton(model, ceiling_mm, door_mm, rep)
    d = model.definitions['BRIDGE_SKELETON'] or return rep[:missing] << 'BRIDGE_SKELETON'
    objs = [d] + d.instances
    option(objs, 'a02_ceiling_height', formlabel: 'Ceiling height (mm)', access: 'TEXTBOX', units: 'MILLIMETERS',
                                       value: inch_s(ceiling_mm), options: '&')
    option(objs, 'b00_door_label', formlabel: 'DOORS (bridge frame above)', access: 'VIEW', units: 'STRING',
                                   value: '-----', formula: '"-----"', formulaunits: 'STRING')
    option(objs, 'b02_door_top_height', formlabel: 'Top door height (mm)', access: 'TEXTBOX', units: 'MILLIMETERS',
                                        value: inch_s(door_mm), options: '&')
    option(objs, 'd02_facing_top', formlabel: 'Facing Top (mm default 97)', access: 'VIEW', units: 'MILLIMETERS',
                                   value: inch_s(97), options: '&')
    option(objs, 'i04_topped', formlabel: 'Topped off? (same as the frame)', access: 'LIST', units: 'BOOLEAN',
                               value: '0', options: TOPPED_OPTIONS, formulaunits: 'STRING')
    option(objs, 'i05_up_to_ceiling', formlabel: 'Up to ceiling', access: 'LIST', units: 'STRING',
                                      value: 'TRUE', options: UP_OPTIONS, formulaunits: 'STRING')
    # The skeleton is drawn in inches; a hidden calculated value would be stored in
    # different units, so the frame height is worked out inside the Z formula itself.
    objs.each { |o| del(o, 'frame_height', '_frame_height_label', '_frame_height_formula', '_frame_height_error', FRAME_H, "_#{FRAME_H}_label", "_#{FRAME_H}_formula") }
    d.instances.each { |i| own(d, i, 'z', "A02_CEILING_HEIGHT - #{FRAME_HEIGHT} - THICKNESS - MDF_HEIGHT") }
  end

  # V21 was first changed with the hidden value named frame_height: rename it.
  def self.rename_frame_height!(model)
    d = model.definitions['BRIDGE_FRAME'] or return 0
    n = 0
    objs = [d] + d.instances
    d.entities.grep(Sketchup::ComponentInstance).each { |c| objs << c << c.definition }
    objs.uniq.each do |o|
      dd = o.attribute_dictionary(DCD) or next
      if dd.keys.include?('frame_height') && [d, *d.instances].include?(o)
        dd[FRAME_H] = dd['frame_height']
        dd["_#{FRAME_H}_label"] = FRAME_H.upcase
        dd["_#{FRAME_H}_formula"] = dd['_frame_height_formula'] if dd['_frame_height_formula']
        %w[frame_height _frame_height_label _frame_height_formula _frame_height_error].each { |k| dd.delete_key(k) if dd.keys.include?(k) }
        n += 1
      end
      dd.keys.grep(/_formula\z/).each do |k|
        v = dd[k]
        next unless v.is_a?(String) && v =~ /\bFRAME_HEIGHT\b/
        dd[k] = v.gsub(/\bFRAME_HEIGHT\b/, FRAME_H.upcase)
        n += 1
      end
    end
    n
  end

  def self.apply!(model, ceiling_mm:, door_mm: 460)
    rep = { missing: [] }
    frame(model, ceiling_mm, door_mm, rep)
    skeleton(model, ceiling_mm, door_mm, rep)
    rep
  end
end
