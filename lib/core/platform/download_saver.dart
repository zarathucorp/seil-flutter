import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef DownloadsDirectoryProvider = Future<Directory?> Function();

class DownloadSaver {
  DownloadSaver({DownloadsDirectoryProvider? downloadsDirectoryProvider})
      : _downloadsDirectoryProvider =
            downloadsDirectoryProvider ?? getDownloadsDirectory;

  final DownloadsDirectoryProvider _downloadsDirectoryProvider;

  Future<String?> save({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    if (isDesktop) {
      Directory? downloadsDirectory;
      try {
        downloadsDirectory = await _downloadsDirectoryProvider();
      } on UnsupportedError {
        downloadsDirectory = null;
      }
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: downloadsDirectory?.path,
      );
      if (savedPath == null) {
        return null;
      }
      await File(savedPath).writeAsBytes(bytes, flush: true);
      return savedPath;
    }

    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
  }
}
