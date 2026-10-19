import 'package:flutter/material.dart';

/// Small frosted tag over a sample dish photo (the CC0 / public-domain set),
/// so customers know it isn't the restaurant's own picture — web: .sample-tag.
class SamplePhotoTag extends StatelessWidget {
  final bool small;
  const SamplePhotoTag({super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 9, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: const Color(0x9E0B1A2F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        small ? 'Sample' : 'Sample photo',
        style: TextStyle(color: Colors.white, fontSize: small ? 8.5 : 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
