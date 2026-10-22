import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A tricycle (motorcycle + covered sidecar). Font Awesome has none, so this
/// is the same drawing the web uses (assets/icons/tricycle.svg, .fa-tricycle
/// in css/main.css), tinted like an FaIcon.
class TricycleIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const TricycleIcon({super.key, this.size = 20, this.color});

  static const String svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 512"><path fill-rule="evenodd" d="M40 40h278a24 24 0 0 1 24 24v26H16V64a24 24 0 0 1 24-24zM30 90h300v214a26 26 0 0 1-26 26H56a26 26 0 0 1-26-26zM78 122v94a10 10 0 0 0 10 10h184a10 10 0 0 0 10-10v-94z"/><path d="M330 330V258a22 22 0 0 1 22-22h96l34-38a16 16 0 0 1 12-6h40v52l-26 86z"/><g fill="none" stroke="#000" stroke-linecap="round"><path stroke-width="38" d="M506 150l26 250"/><path stroke-width="32" d="M462 150l96-16"/><circle cx="128" cy="408" r="62" stroke-width="50"/><circle cx="528" cy="408" r="62" stroke-width="50"/></g></svg>''';

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.black;
    return SvgPicture.string(
      svg,
      width: size * 1.25,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: 'Tricycle',
    );
  }
}
