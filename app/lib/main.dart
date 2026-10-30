import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'controller.dart';
import 'data/database.dart';
import 'data/http_source.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDatabase database;
  if (Platform.isAndroid || Platform.isIOS) {
    database = await AppDatabase.openMobile();
  } else {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final directory = Directory(p.join(home, '.smp_guide'));
    await directory.create(recursive: true);
    database = await AppDatabase.openFile(p.join(directory.path, 'smp_guide.sqlite'));
  }
  final repository = ContentRepository(database);
  final snapshot = await rootBundle.loadString('assets/snapshot.json');
  await repository.ensureBundled(snapshot);
  final controller = ContentController(
    repository: repository,
    source: SnapshotHttpClient(),
  );
  await controller.load();
  runApp(SmpApp(controller: controller));
}
