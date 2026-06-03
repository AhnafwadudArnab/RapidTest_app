import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> saveLocalExportFile({
  required String fileName,
  required String contents,
}) async {
  final directory = await _resolveExportDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(contents);
  return file.path;
}

Future<Directory> _resolveExportDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } on MissingPluginException {
    final fallbackDirectory = Directory(
      '${Directory.systemTemp.path}/rapid_test_exports',
    );
    if (!await fallbackDirectory.exists()) {
      await fallbackDirectory.create(recursive: true);
    }
    return fallbackDirectory;
  }
}
