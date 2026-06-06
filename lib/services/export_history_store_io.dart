import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _historyFileName = 'rapid_test_export_history.json';

Future<List<Map<String, dynamic>>> loadExportHistoryMaps() async {
  final file = await _historyFile();
  if (!await file.exists()) return const [];

  final contents = await file.readAsString();
  if (contents.trim().isEmpty) return const [];

  final decoded = jsonDecode(contents);
  if (decoded is! List) return const [];

  return decoded
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Future<void> saveExportHistoryMaps(List<Map<String, dynamic>> exports) async {
  final file = await _historyFile();
  await file.writeAsString(jsonEncode(exports));
}

Future<File> _historyFile() async {
  final directory = await _resolveHistoryDirectory();
  return File('${directory.path}/$_historyFileName');
}

Future<Directory> _resolveHistoryDirectory() async {
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
