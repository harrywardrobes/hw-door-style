HARRY WARDROBES - COLOUR MATERIALS
==================================

SketchUp's .skm material files can only be written by SketchUp itself, so this
folder has everything needed plus a script that makes them in about 5 seconds.

1. Unzip this folder somewhere, e.g. C:\Users\User\Downloads\HW Colours
2. Open SketchUp > Window > Ruby Console
3. Type (change the path if you unzipped elsewhere) and press Enter:
     load 'C:/Users/User/Downloads/HW Colours/make_skm.rb'
4. Restart SketchUp. The 13 colours appear in the Materials panel under
   the "Harry Wardrobes" collection. Copies are also saved in the "skm" folder here.

Contents
  colour_values.txt   RGB / hex for every colour
  colours.json        same data the plugin uses
  textures/           Lissa Oak and Opera Walnut seamless grain (600 mm tile, grain vertical)
  swatches/           256 px preview of each colour (solid, no border)
  make_skm.rb         the script above

Plain colours are solid colour (no image), so they never show tile edges.
The HW Door Style plugin already contains all of this - you only need these
files to use the colours in other models or other software.
