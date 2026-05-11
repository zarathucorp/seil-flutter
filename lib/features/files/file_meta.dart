import 'package:path/path.dart' as p;

import '../../shared/models.dart';

const _textExtensions = {
  'c',
  'cc',
  'conf',
  'cpp',
  'cs',
  'css',
  'env',
  'go',
  'h',
  'hpp',
  'html',
  'ini',
  'java',
  'js',
  'json',
  'jsx',
  'log',
  'lua',
  'md',
  'mjs',
  'py',
  'r',
  'rb',
  'rs',
  'sh',
  'sql',
  'text',
  'toml',
  'ts',
  'tsx',
  'txt',
  'xml',
  'yaml',
  'yml',
};

const _downloadOnlyExtensions = {
  'doc',
  'docx',
  'hwp',
  'pdf',
  'ppt',
  'pptx',
  'xls',
  'xlsx',
};
const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
const _iconByExtension = {
  'c': 'file_type_c.svg',
  'cc': 'file_type_cpp.svg',
  'conf': 'file_type_config.svg',
  'cpp': 'file_type_cpp.svg',
  'cs': 'file_type_csharp.svg',
  'css': 'file_type_css.svg',
  'doc': 'file_type_word.svg',
  'docx': 'file_type_word.svg',
  'env': 'file_type_dotenv.svg',
  'go': 'file_type_go.svg',
  'h': 'file_type_cheader.svg',
  'hpp': 'file_type_cppheader.svg',
  'html': 'file_type_html.svg',
  'ini': 'file_type_config.svg',
  'java': 'file_type_java.svg',
  'jpeg': 'file_type_image.svg',
  'jpg': 'file_type_image.svg',
  'js': 'file_type_js.svg',
  'json': 'file_type_json.svg',
  'jsx': 'file_type_reactjs.svg',
  'log': 'file_type_log.svg',
  'lua': 'file_type_lua.svg',
  'md': 'file_type_markdown.svg',
  'mjs': 'file_type_js.svg',
  'pdf': 'file_type_pdf.svg',
  'png': 'file_type_image.svg',
  'ppt': 'file_type_powerpoint.svg',
  'pptx': 'file_type_powerpoint.svg',
  'py': 'file_type_python.svg',
  'qmd': 'file_type_quarto.svg',
  'r': 'file_type_r.svg',
  'rb': 'file_type_ruby.svg',
  'rmd': 'file_type_rmd.svg',
  'rs': 'file_type_rust.svg',
  'sh': 'file_type_shell.svg',
  'sql': 'file_type_sql.svg',
  'text': 'file_type_text.svg',
  'toml': 'file_type_toml.svg',
  'ts': 'file_type_typescript.svg',
  'tsx': 'file_type_reactts.svg',
  'txt': 'file_type_text.svg',
  'webp': 'file_type_image.svg',
  'xls': 'file_type_excel.svg',
  'xlsx': 'file_type_excel.svg',
  'xml': 'file_type_xml.svg',
  'yaml': 'file_type_yaml.svg',
  'yml': 'file_type_yaml.svg',
};

FileMeta inferFileMeta(String filePath, String entryKind) {
  if (entryKind == 'dir') {
    return const FileMeta(
      iconName: 'default_folder.svg',
      previewKind: FilePreviewKind.dir,
      typeLabel: 'DIR',
      language: null,
    );
  }

  final extension = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  final iconName = _iconByExtension[extension] ??
      (extension.isEmpty ? 'default_file.svg' : 'file_type_$extension.svg');

  if (_imageExtensions.contains(extension)) {
    return FileMeta(
      iconName: iconName,
      previewKind: FilePreviewKind.image,
      typeLabel: extension.toUpperCase(),
      language: null,
    );
  }

  if (_downloadOnlyExtensions.contains(extension)) {
    return FileMeta(
      iconName: iconName,
      previewKind: FilePreviewKind.download,
      typeLabel: extension.isEmpty ? 'FILE' : extension.toUpperCase(),
      language: null,
    );
  }

  if (extension == 'md' || extension == 'rmd' || extension == 'qmd') {
    return FileMeta(
      iconName: iconName,
      previewKind: FilePreviewKind.markdown,
      typeLabel: extension.toUpperCase(),
      language: 'markdown',
    );
  }

  if (extension == 'log') {
    return FileMeta(
      iconName: iconName,
      previewKind: FilePreviewKind.code,
      typeLabel: 'LOG',
      language: 'log',
    );
  }

  if (_textExtensions.contains(extension)) {
    return FileMeta(
      iconName: iconName,
      previewKind: FilePreviewKind.code,
      typeLabel: extension.isEmpty ? 'TEXT' : extension.toUpperCase(),
      language: extension,
    );
  }

  return FileMeta(
    iconName: iconName,
    previewKind: FilePreviewKind.code,
    typeLabel: extension.isEmpty ? 'FILE' : extension.toUpperCase(),
    language: extension.isEmpty ? 'text' : extension,
  );
}

class FileMeta {
  const FileMeta({
    required this.iconName,
    required this.previewKind,
    required this.typeLabel,
    required this.language,
  });

  final String iconName;
  final FilePreviewKind previewKind;
  final String typeLabel;
  final String? language;
}
