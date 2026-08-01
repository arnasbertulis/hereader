import 'package:app/reading/library_screen.dart';
import 'package:flutter/material.dart';

void main() => runApp(const HereaderApp());

class HereaderApp extends StatelessWidget {
  const HereaderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hereader',
    theme: ThemeData(useMaterial3: true),
    home: const LibraryScreen(),
  );
}
