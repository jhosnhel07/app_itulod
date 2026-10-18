// ignore_for_file: avoid_print
// One-off asset prep for the app's home-screen icon, run with:
//   dart run tool/make_launcher_icon.dart
//   dart run flutter_launcher_icons
//
// Uses the circular iTULOD illustration (assets/images/splash_icon.png, made
// by make_splash_icon.dart) — the "iTULOD" wordmark is unreadable at icon size
// and the phone prints the app name under the icon anyway. Produces:
//   * launcher_icon.png       — emblem on white, for older (non-adaptive) icons
//   * launcher_foreground.png — emblem on transparent, sized to stay inside the
//     adaptive-icon safe zone (the centre 66/108 of the canvas) so circle,
//     squircle and rounded-square masks never clip it
import 'dart:io';
import 'package:image/image.dart' as img;

img.Image _emblem() {
  final src = img.decodePng(File('assets/images/splash_icon.png').readAsBytesSync())!;
  int minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (src.getPixel(x, y).a > 12) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  final size = (maxX - minX) > (maxY - minY) ? (maxX - minX) : (maxY - minY);
  print('emblem bbox: ($minX,$minY)-($maxX,$maxY), size $size');
  return img.copyCrop(src, x: minX, y: minY, width: size + 1, height: size + 1);
}

img.Image _canvas(int size, {required bool white}) {
  final c = img.Image(width: size, height: size, numChannels: 4);
  img.fill(c, color: white ? c.getColor(255, 255, 255, 255) : c.getColor(0, 0, 0, 0));
  return c;
}

void _place(img.Image canvas, img.Image emblem, double fraction) {
  final target = (canvas.width * fraction).round();
  final scaled = img.copyResize(emblem,
      width: target, height: target, interpolation: img.Interpolation.cubic);
  final off = ((canvas.width - target) / 2).round();
  img.compositeImage(canvas, scaled, dstX: off, dstY: off);
}

void main() {
  const size = 1024;
  final emblem = _emblem();

  // Legacy square icon: emblem fills most of a white tile.
  final legacy = _canvas(size, white: true);
  _place(legacy, emblem, 0.86);
  File('assets/images/launcher_icon.png').writeAsBytesSync(img.encodePng(legacy));

  // Adaptive foreground: a circle of diameter 0.60 sits inside the 0.61 safe zone.
  final fg = _canvas(size, white: false);
  _place(fg, emblem, 0.60);
  File('assets/images/launcher_foreground.png').writeAsBytesSync(img.encodePng(fg));

  print('wrote assets/images/launcher_icon.png and launcher_foreground.png');
}
