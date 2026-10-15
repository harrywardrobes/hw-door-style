module HWInspect2
  PATTERN = /DOOR|DRAWER|DRW|FRONT|HINGE|TIP/i
  @out = []
  def self.p(s) ; @out << s ; end
  def self.mm(l) ; (l.to_f * 25.4).round(1) ; end
  def self.sc(t, a) ; Geom::Vector3d.new(*a).transform(t).length.to_f.round(4) ; end
  def self.mat(m)
    return "none" unless m
    s = m.display_name
    s += " [tex #{mm(m.texture.width)}x#{mm(m.texture.height)}]" if m.texture
    s
  end
  def self.dc(obj)
    d = obj.attribute_dictionary("dynamic_attributes")
    return "" unless d
    d.keys.first(40).map { |k| "#{k}=#{d[k].to_s[0, 45]}" }.join("; ")
  end
  def self.walk(ents, path, pmat, depth)
    return if depth > 8
    ents.each do |e|
      next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      d = e.definition
      label = e.is_a?(Sketchup::Group) ? "[grp]#{e.name}" : d.name
      label += "('#{e.name}')" if e.is_a?(Sketchup::ComponentInstance) && !e.name.empty?
      mat = e.material || pmat
      if d.name =~ PATTERN || e.name =~ PATTERN
        @hits += 1
        @count[d.name] = (@count[d.name] || []) << nil
        t = e.transformation
        s = [sc(t, [1, 0, 0]), sc(t, [0, 1, 0]), sc(t, [0, 0, 1])]
        b = d.bounds
        loc = [mm(b.width), mm(b.height), mm(b.depth)]
        real = loc.each_with_index.map { |v, i| (v * s[i]).round(1) }
        @count[d.name][-1] = real.join("x")
        if @hits <= 80
          ents2 = d.entities
          kids = ents2.select { |x| x.respond_to?(:definition) }.map { |x| x.definition.name }
          p "#{(path + [label]).join(' > ')}"
          p "   copies=#{d.instances.size} tag=#{e.layer.name} mat=#{mat(e.material)} inherited=#{e.material ? 'no' : mat(pmat)}"
          p "   local=#{loc.join('x')} scale=#{s.join(',')} REAL=#{real.join('x')} faces=#{ents2.grep(Sketchup::Face).size}"
          p "   face mats=#{ents2.grep(Sketchup::Face).map { |f| f.material }.compact.uniq.map { |m| m.display_name }.join('|')}"
          p "   inner tags=#{ents2.map { |x| x.layer.name }.uniq.join('|')} nested=#{kids.join('|')}"
          p "   DC def: #{dc(d)}"
          p "   DC inst: #{dc(e)}"
        end
      end
      walk(d.entities, path + [label], mat, depth + 1)
    end
  end
  def self.run
    @out = [] ; @hits = 0 ; @count = {}
    m = Sketchup.active_model
    p "=== HW INSPECT v2  SketchUp #{Sketchup.version}  file=#{File.basename(m.path.to_s)}"
    p "--- TAGS: #{m.layers.map { |l| l.name }.join(' | ')}"
    p "--- MATERIALS:"
    m.materials.each { |x| p "   #{mat(x)}" }
    p "--- DEFINITIONS matching door/drawer/hinge/tip:"
    m.definitions.each do |d|
      next if d.image? || d.name !~ PATTERN
      p "   #{d.name}  instances=#{d.instances.size}  dc=#{d.attribute_dictionary('dynamic_attributes') ? 'yes' : 'no'}"
    end
    p "--- INSTANCES (path from model root):"
    walk(m.entities, [], nil, 0)
    p "--- SUMMARY (definition => real sizes found, mm):"
    @count.each { |k, v| p "   #{k} x#{v.size}: #{v.uniq.join(', ')}" }
    p "=== END (#{@hits} matches)"
    txt = @out.join("\n")
    desk = File.join(ENV["USERPROFILE"] || Dir.home, "Desktop")
    desk = Dir.home unless File.directory?(desk)
    f = File.join(desk, "hw_inspect.txt")
    File.write(f, txt)
    puts txt[0, 6000]
    puts "\n>>> Full report saved to: #{f}"
  rescue => err
    puts "Inspector error: #{err.message} @ #{err.backtrace.first}"
  end
end
HWInspect2.run; nil
