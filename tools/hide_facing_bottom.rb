# One-off (Components V22): hide the bottom facing option ("bottom", d01_facing_btm)
# in Component Options on every component. The job value is now set in the pencil
# window, or per unit from the right-click menu (HW Door Style 0.19). The option and
# its value stay, so every formula keeps working. A FACING section header left with
# nothing to show is hidden too.
#
#   load 'tools/hide_facing_bottom.rb'
#   HWHideFacing.apply!(Sketchup.active_model)   # inside YOUR operation
module HWHideFacing
  DCD = 'dynamic_attributes'.freeze
  KEY = /\A(?:[a-z]\d{1,2}_)?facing_btm\z/.freeze
  HEADER = /\A[a-z]00_facing_label\z/.freeze

  def self.visible?(dd, k)
    a = dd["_#{k}_access"].to_s
    !a.empty? && a != 'NONE'
  end

  def self.apply!(model)
    rep = { hidden: [], headers: [] }
    model.definitions.reject(&:image?).each do |d|
      dd = d.attribute_dictionary(DCD) or next
      keys = dd.keys.select { |k| k =~ KEY && !k.start_with?('_') }
      next if keys.empty?
      keys.each do |k|
        next unless visible?(dd, k) || d.instances.any? { |i| (i.attribute_dictionary(DCD) || {})["_#{k}_access"].to_s =~ /TEXTBOX|LIST|VIEW/ }
        ([d] + d.instances).each { |o| o.set_attribute(DCD, "_#{k}_access", 'NONE') if o == d || o.get_attribute(DCD, "_#{k}_access") }
        rep[:hidden] << "#{d.name}.#{k}"
      end
      # Section header with nothing left under it.
      dd.keys.select { |k| k =~ HEADER }.each do |h|
        sec = h[0]
        others = dd.keys.select { |k| k !~ /\A_/ && k =~ /\A#{sec}\d\d_/ && k != h && visible?(dd, k) }
        next unless others.empty? && visible?(dd, h)
        ([d] + d.instances).each { |o| o.set_attribute(DCD, "_#{h}_access", 'NONE') if o == d || o.get_attribute(DCD, "_#{h}_access") }
        rep[:headers] << "#{d.name}.#{h}"
      end
    end
    rep
  end
end
