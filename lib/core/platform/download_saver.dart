import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

class DownloadSaver {
  const DownloadSaver();

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
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
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
