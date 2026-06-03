// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<String?> saveWebDownload({
  required String fileName,
  required String contents,
  required String mimeType,
}) async {
  final bytes = html.Blob([contents], mimeType);
  final url = html.Url.createObjectUrlFromBlob(bytes);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
  return 'Downloaded: $fileName';
}
