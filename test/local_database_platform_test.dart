import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/storage/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows database factory can create and query a SQLite database',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final directory = await Directory.systemTemp.createTemp('seil-windows-db-');
    addTearDown(() => directory.delete(recursive: true));
    final database = await seilDatabaseFactoryForPlatform().openDatabase(
      '${directory.path}/seil.db',
      options: OpenDatabaseOptions(version: 1),
    );
    addTearDown(database.close);

    await database.execute('CREATE TABLE probe (value TEXT NOT NULL)');
    await database.insert('probe', {'value': 'windows-ready'});
    final rows = await database.query('probe');

    expect(rows.single['value'], 'windows-ready');
  });
}
