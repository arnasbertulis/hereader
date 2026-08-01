import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/library_repository.dart';
import 'reading/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();
  runApp(HereaderApp(repository: LibraryRepository(database)));
}

class HereaderApp extends StatelessWidget {
  final LibraryRepository repository;

  const HereaderApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hereader',
      theme: ThemeData(useMaterial3: true),
      home: LibraryScreen(repository: repository),
    );
  }
}
