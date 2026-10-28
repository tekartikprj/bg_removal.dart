import 'package:flutter/material.dart';

import 'src/home_page.dart';

/// Takes or picks a photo, removes its background (the person and what they
/// carry stay), shows both, and saves the cut-out.
void main() {
  runApp(
    MaterialApp(
      title: 'Background removal',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomePage(),
    ),
  );
}
