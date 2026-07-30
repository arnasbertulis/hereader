import 'package:flutter/material.dart';
import 'reading/paste_reader_screen.dart';

void main() => runApp(const HereaderApp());

class HereaderApp extends StatelessWidget {
  const HereaderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hereader',
        theme: ThemeData(useMaterial3: true),
        home: const PasteReaderScreen(),
      );
}