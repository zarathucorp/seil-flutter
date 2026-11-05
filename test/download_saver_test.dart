import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/platform/download_saver.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.savedPath);

  final String? savedPath;
  Uint8List? receivedBytes;
  String? receivedInitialDirectory;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    receivedBytes = bytes;
    receivedInitialDirectory = initialDirectory;
    return savedPath;
  }
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final fileName in ['analysis.R', 'results.csv']) {
    test('macOS writes $fileName after choosing its save path', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final directory = await Directory.systemTemp.createTemp('seil-download-');
      addTearDown(() => directory.delete(recursive: true));
      final savedPath = '${directory.path}/$fileName';
      final picker = _FakeFilePicker(savedPath);
      FilePicker.platform = picker;
      final expected = Uint8List.fromList([83, 69, 73, 76]);

      final result = await DownloadSaver(
        downloadsDirectoryProvider: () async => directory,
      ).save(
        dialogTitle: 'Download',
        fileName: fileName,
        bytes: expected,
      );

      expect(result, savedPath);
      expect(picker.receivedBytes, isNull);
      expect(picker.receivedInitialDirectory, directory.path);
      expect(await File(savedPath).readAsBytes(), expected);
    });
  }

  test('macOS cancellation does not create a file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final picker = _FakeFilePicker(null);
    FilePicker.platform = picker;

    final result = await DownloadSaver(
      downloadsDirectoryProvider: () async => null,
    ).save(
      dialogTitle: 'Download',
      fileName: 'cancelled.R',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(result, isNull);
    expect(picker.receivedBytes, isNull);
  });
}
