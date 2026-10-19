module HarryWardrobes
  module DoorStyle
    # Drawers are DC parts with an ANIMATE onclick that slides them out in Y.
    # Close every drawer before a redraw or an export, so nothing is saved or
    # rebuilt half open (a redraw keeps the open offset otherwise).
    module Drawers
      def self.open?(i)
        d = DC.dict(i) or return false
        return false unless DC.read(i, 'onclick').to_s =~ /ANIMATE/i
        d['y'].to_f.abs > 0.0001 || d['_onclick_state1'].to_s.to_i != 0
      end

      # Labels of the open drawers inside entities (nothing changed).
      def self.open_ones(entities)
        list = []
        Finder.each_instance(entities) { |i| list << Finder.label(i) if open?(i) }
        list
      end

      # Closes every open drawer inside entities. Returns the labels closed.
      def self.close(entities)
        closed = []
        Finder.each_instance(entities) do |i|
          next unless open?(i)
          d = DC.dict(i)
          y = d['y'].to_f
          i.transformation = Geom::Transformation.translation([0, -y, 0]) * i.transformation if y.abs > 0.0001
          i.set_attribute(DC::DICT_NAME, 'y', 0.0)
          i.set_attribute(DC::DICT_NAME, '_onclick_state1', 0) if d['_onclick_state1']
          closed << Finder.label(i)
        end
        closed
      end
    end
  end
end
