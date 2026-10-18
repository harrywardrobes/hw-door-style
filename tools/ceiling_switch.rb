# One-off (Components V20): "Up to ceiling" switch on every unit with a height,
# and "Height below bridge" on BRIDGE_FRAME. Call inside your operation.
module HWCeiling
  DCD = 'dynamic_attributes'.freeze
  UNITS = %w[WARDROBE WALK-IN LINEN_PRESS TOPBOX BOOKCASE FACING_BLOCK_L FACING_BLOCK_R END_PAN BULLNOSE BXEND BRIDGE_FRAME].freeze

  def self.set_all(d, h)
    ([d] + d.instances).each { |o| h.each { |k, v| o.set_attribute(DCD, k, v) } }
  end

  def self.apply!(model)
    log = []
    model.definitions.select { |d| UNITS.include?(d.name) }.each do |d|
      next if d.get_attribute(DCD, 'i05_up_to_ceiling')
      set_all(d, '_i05_up_to_ceiling_access' => 'LIST', '_i05_up_to_ceiling_formlabel' => 'Up to ceiling',
                 '_i05_up_to_ceiling_label' => 'I05_UP_TO_CEILING', '_i05_up_to_ceiling_options' => '&TRUE=TRUE&FALSE=FALSE&',
                 '_i05_up_to_ceiling_units' => 'STRING', '_i05_up_to_ceiling_formulaunits' => 'STRING', 'i05_up_to_ceiling' => 'TRUE')
      log << "#{d.name}: Up to ceiling"
    end
    if (b = model.definitions['BRIDGE_FRAME'])
      unless b.get_attribute(DCD, 'a03_height_below')
        set_all(b, '_a03_height_below_access' => 'TEXTBOX', '_a03_height_below_formlabel' => 'Height below bridge (mm)',
                   '_a03_height_below_label' => 'A03_HEIGHT_BELOW', '_a03_height_below_units' => 'MILLIMETERS',
                   '_a03_height_below_formulaunits' => 'CENTIMETERS', 'a03_height_below' => 0.0)
        log << 'BRIDGE_FRAME: Height below bridge'
      end
      set_all(b, '_a02_ceiling_height_formlabel' => 'Ceiling height (mm)') if b.get_attribute(DCD, 'a02_ceiling_height')
    end
    log
  end
end
