# One-off (applied to Components V20): every divider / end panel takes the floor
# runout (down from the floor) and the ceiling runout (up, only when not topped),
# as well as the back runout it already had. Uses the re-ordered names.
#   load 'tools/div_runouts.rb'; HWDivRunout.apply!(Sketchup.active_model)  # inside your operation
module HWDivRunout
  DCD = 'dynamic_attributes'.freeze
  NAMES = /\A(WRD_DIV|WRD_DIV_R|WLK_DIV|WLK_DIV_R|LIN_DIV|LIN_DIV_R|TPBX_DIV_INT|TPBX_DIV_R|BKS_DIV)(#\d+)?\z/

  def self.set(d, key, f)
    ([d] + d.instances).each do |o|
      dd = o.attribute_dictionary(DCD) or next
      %W[_#{key}_formula _inst__#{key}_formula].each { |k| dd[k] = f if dd[k] }
    end
    d.set_attribute(DCD, "_#{key}_formula", f)
  end

  def self.get(d, key)
    ([d] + d.instances).map { |o| o.get_attribute(DCD, "_#{key}_formula") }.compact.first.to_s
  end

  def self.apply!(model)
    log = []
    model.definitions.select { |d| d.name =~ NAMES }.each do |d|
      lz = get(d, 'lenz')
      next if lz.empty?
      add = []
      add << 'parent!J01_RUNOUT_FLOOR' unless lz =~ /RUNOUT_FLOOR/i
      add << 'parent!ZZ_RUNOUT_CEILING' unless lz =~ /RUNOUT_CEILING/i
      next if add.empty?
      set(d, 'lenz', ([lz] + add).join(' + '))
      if add.include?('parent!J01_RUNOUT_FLOOR')
        z = get(d, 'z').strip
        set(d, 'z', z.empty? || z == '0' ? '-parent!J01_RUNOUT_FLOOR' : "#{z} - parent!J01_RUNOUT_FLOOR")
      end
      log << "#{d.name}: +#{add.map { |a| a[/FLOOR|CEILING/].downcase }.join('+')}"
    end
    log
  end
end
