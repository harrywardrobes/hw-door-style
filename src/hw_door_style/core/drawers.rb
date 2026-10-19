module HarryWardrobes
  module DoorStyle
    # Drawers are DC parts with an ANIMATE onclick that slides them out in Y.
    # Close every drawer before a redraw or an export, so nothing is saved or
    # rebuilt half open (a redraw keeps the open offset otherwise).
    module Drawers
      # Closes every open drawer inside entities. Returns the labels closed.
      def self.close(entities)
        closed = []
        Finder.each_instance(entities) do |i|
          d = DC.dict(i) or next
          next unless DC.read(i, 'onclick').to_s =~ /ANIMATE/i
          y = d['y'].to_f
          next unless y.abs > 0.0001 || d['_onclick_state1'].to_s.to_i != 0
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
