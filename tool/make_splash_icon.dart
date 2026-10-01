// ignore_for_file: avoid_print
// One-off asset prep for the native splash screen, run with:
//   dart run tool/make_splash_icon.dart
//
// Android 12's splash API masks the icon to a circle, so we can't feed it the
// full logo (illustration + "iTULOD" wordmark) — the wordmark gets clipped.
// Instead we split logo.png into two assets:
//   * splash_icon.png     — just the circular illustration, transparent-padded
//   * splash_wordmark.png  — just the "iTULOD" wordmark, for the branding slot
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/images/logo.png').readAsBytesSync())!;
  print('source: ${src.width}x${src.height}');

  // Opaque bounding box of everything in the logo.
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
  print('content bbox: ($minX,$minY)-($maxX,$maxY)');

  // ── 1. The circular illustration = the top square of that bbox. ──────────
  final diameter = maxX - minX;
  final circle =
      img.copyCrop(src, x: minX, y: minY, width: diameter, height: diameter);

  final iconCanvas = (diameter * 1.5).round();
  final icon = img.Image(width: iconCanvas, height: iconCanvas, numChannels: 4);
  img.fill(icon, color: icon.getColor(0, 0, 0, 0));
  final iconOff = ((iconCanvas - diameter) / 2).round();
  img.compositeImage(icon, circle, dstX: iconOff, dstY: iconOff);
  File('assets/images/splash_icon.png').writeAsBytesSync(img.encodePng(icon));
  print('wrote assets/images/splash_icon.png ${iconCanvas}x$iconCanvas');

  // ── 2. The "iTULOD" wordmark = everything below the circle. ─────────────
  final wordTop = minY + diameter; // just under the circle
  var wm = img.copyCrop(src,
      x: minX, y: wordTop, width: diameter, height: maxY - wordTop);

  // Re-trim the wordmark crop tight to its own ink.
  int wMinX = wm.width, wMinY = wm.height, wMaxX = 0, wMaxY = 0;
  for (var y = 0; y < wm.height; y++) {
    for (var x = 0; x < wm.width; x++) {
      if (wm.getPixel(x, y).a > 12) {
        if (x < wMinX) wMinX = x;
        if (x > wMaxX) wMaxX = x;
        if (y < wMinY) wMinY = y;
        if (y > wMaxY) wMaxY = y;
      }
    }
  }
  wm = img.copyCrop(wm,
      x: wMinX, y: wMinY, width: wMaxX - wMinX, height: wMaxY - wMinY);

  // Pad with a little breathing room.
  final pad = (wm.height * 0.35).round();
  final wmCanvas = img.Image(
      width: wm.width + pad * 2, height: wm.height + pad * 2, numChannels: 4);
  img.fill(wmCanvas, color: wmCanvas.getColor(0, 0, 0, 0));
  img.compositeImage(wmCanvas, wm, dstX: pad, dstY: pad);
  File('assets/images/splash_wordmark.png')
      .writeAsBytesSync(img.encodePng(wmCanvas));
  print('wrote assets/images/splash_wordmark.png '
      '${wmCanvas.width}x${wmCanvas.height}');

  // ── 3. Circle + wordmark stacked, sized so the whole composition stays
  //       inside Android 12's circular splash mask. This is the native
  //       launch icon so the logo AND the name show, un-clipped. ──────────
  const canvas = 1152;
  final comp = img.Image(width: canvas, height: canvas, numChannels: 4);
  img.fill(comp, color: comp.getColor(0, 0, 0, 0));

  final circD = (canvas * 0.46).round();
  final wmW = (canvas * 0.40).round();
  final wmH = (wm.height * wmW / wm.width).round();
  const gap = 34;
  final totalH = circD + gap + wmH;
  final top = ((canvas - totalH) / 2).round();

  final circR = img.copyResize(circle, width: circD, height: circD);
  img.compositeImage(comp, circR,
      dstX: ((canvas - circD) / 2).round(), dstY: top);

  final wmR = img.copyResize(wm, width: wmW, height: wmH);
  img.compositeImage(comp, wmR,
      dstX: ((canvas - wmW) / 2).round(), dstY: top + circD + gap);

  File('assets/images/splash_native.png')
      .writeAsBytesSync(img.encodePng(comp));
  print('wrote assets/images/splash_native.png ${canvas}x$canvas');
}
