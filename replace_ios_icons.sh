#!/bin/zsh

# Path to your source icon
SRC_ICON="assets/bravo_icon.png"
# Path to the iOS AppIcon asset catalog
ICONSET="ios/Runner/Assets.xcassets/AppIcon.appiconset"

# List of required icon sizes and filenames for iOS
typeset -A ICON_SIZES
ICON_SIZES=(
  "Icon-App-20x20@1x.png"    20
  "Icon-App-20x20@2x.png"    40
  "Icon-App-20x20@3x.png"    60
  "Icon-App-29x29@1x.png"    29
  "Icon-App-29x29@2x.png"    58
  "Icon-App-29x29@3x.png"    87
  "Icon-App-40x40@1x.png"    40
  "Icon-App-40x40@2x.png"    80
  "Icon-App-40x40@3x.png"    120
  "Icon-App-50x50@1x.png"    50
  "Icon-App-50x50@2x.png"    100
  "Icon-App-57x57@1x.png"    57
  "Icon-App-57x57@2x.png"    114
  "Icon-App-60x60@2x.png"    120
  "Icon-App-60x60@3x.png"    180
  "Icon-App-72x72@1x.png"    72
  "Icon-App-72x72@2x.png"    144
  "Icon-App-76x76@1x.png"    76
  "Icon-App-76x76@2x.png"    152
  "Icon-App-83.5x83.5@2x.png" 167
  "Icon-App-1024x1024@1x.png" 1024
)

echo "Replacing iOS app icons with $SRC_ICON..."

for icon in ${(k)ICON_SIZES}; do
  size=${ICON_SIZES[$icon]}
  outpath="$ICONSET/$icon"
  sips -z $size $size "$SRC_ICON" --out "$outpath"
  echo "Generated $outpath ($size x $size)"
done

echo "All iOS app icons replaced. Clean and rebuild your iOS project to see the new icon."