import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/features/files/file_meta.dart';
import 'package:seil_mobile/shared/models.dart';

void main() {
  test('uppercase R files remain downloadable editable text files', () {
    final meta = inferFileMeta('/analysis/model.R', 'file');

    expect(meta.previewKind, FilePreviewKind.code);
    expect(meta.typeLabel, 'R');
    expect(meta.language, 'r');
    expect(meta.iconName, 'file_type_r.svg');
  });

  test('CSV files remain downloadable editable text files', () {
    final meta = inferFileMeta('/analysis/results.csv', 'file');

    expect(meta.previewKind, FilePreviewKind.code);
    expect(meta.typeLabel, 'CSV');
    expect(meta.language, 'csv');
    expect(meta.iconName, 'default_file.svg');
  });
}
