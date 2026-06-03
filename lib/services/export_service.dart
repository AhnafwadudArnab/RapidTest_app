import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/dataset_record_model.dart';
import 'export_downloader_stub.dart'
    if (dart.library.html) 'export_downloader_web.dart';
import 'export_file_saver_stub.dart'
    if (dart.library.io) 'export_file_saver_io.dart';

class ExportService {
  ExportService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _downloadsChannel = MethodChannel('rapid_test/downloads');

  final FirebaseFirestore _firestore;

  Future<String> exportRecords(String format) async {
    final snapshot = await _firestore.collection('dataset_records').get();
    final rows =
        snapshot.docs
            .map((doc) => DatasetRecordModel.fromMap(doc.id, doc.data()))
            .map(_toExportRow)
            .toList();
    final safeFormat = format.toLowerCase();
    final fileName =
        'dataset_records_${DateTime.now().millisecondsSinceEpoch}.$safeFormat';
    final contents = switch (safeFormat) {
      'json' => const JsonEncoder.withIndent('  ').convert(rows),
      'xls' => _toExcelHtml(rows),
      _ => _toCsv(rows),
    };

    if (kIsWeb) {
      final downloaded = await saveWebDownload(
        fileName: fileName,
        contents: contents,
        mimeType: _mimeType(safeFormat),
      );
      if (downloaded != null) return downloaded;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final savedPath = await _saveAndroidDownload(
        fileName: fileName,
        contents: contents,
        mimeType: _mimeType(safeFormat),
      );
      if (savedPath != null) return savedPath;
    }

    final savedPath = await saveLocalExportFile(
      fileName: fileName,
      contents: contents,
    );
    if (savedPath != null) return savedPath;

    throw UnsupportedError('Dataset download is not supported on this device.');
  }

  Future<String?> _saveAndroidDownload({
    required String fileName,
    required String contents,
    required String mimeType,
  }) async {
    try {
      final path = await _downloadsChannel
          .invokeMethod<String>('saveFileToDownloads', {
            'fileName': fileName,
            'mimeType': mimeType,
            'bytes': Uint8List.fromList(utf8.encode(contents)),
          });
      return path;
    } on MissingPluginException {
      return null;
    }
  }

  String _mimeType(String format) {
    return switch (format) {
      'json' => 'application/json',
      'xls' => 'application/vnd.ms-excel',
      _ => 'text/csv',
    };
  }

  String _toCsv(List<Map<String, dynamic>> rows) {
    final lines = <String>[
      _headers.map(_escapeCsv).join(','),
      ...rows.map(
        (row) => _headers.map((header) => _escapeCsv(row[header])).join(','),
      ),
    ];
    return lines.join('\n');
  }

  String _toExcelHtml(List<Map<String, dynamic>> rows) {
    final headerCells = _headers.map(
      (header) => '<th>${_escapeHtml(header)}</th>',
    );
    final bodyRows = rows.map((row) {
      final cells = _headers.map(
        (header) => '<td>${_escapeHtml(row[header])}</td>',
      );
      return '<tr>${cells.join()}</tr>';
    });

    return '''
<html>
<head><meta charset="utf-8"></head>
<body>
<table>
<thead><tr>${headerCells.join()}</tr></thead>
<tbody>${bodyRows.join()}</tbody>
</table>
</body>
</html>
''';
  }

  String _escapeCsv(Object? value) {
    final text = (value ?? '').toString();
    return '"${text.replaceAll('"', '""')}"';
  }

  String _escapeHtml(Object? value) {
    return (value ?? '')
        .toString()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  Map<String, dynamic> _toExportRow(DatasetRecordModel record) {
    return {
      'recordId': record.recordId,
      'qrCodeValue': record.qrCodeValue,
      'kitId': record.kitId,
      'kitName': record.kitDisplayName,
      'testType': record.testType,
      'selectedResult': record.selectedResult,
      'imageUrl': record.imageUrl,
      'imageName': record.imageName,
      'submittedAt': record.submittedAtDigital,
    };
  }

  List<String> get _headers => const [
    'recordId',
    'qrCodeValue',
    'kitId',
    'kitName',
    'testType',
    'selectedResult',
    'imageUrl',
    'imageName',
    'submittedAt',
  ];
}
