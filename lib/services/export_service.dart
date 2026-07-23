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

  Future<String> exportRecords(
    String format, {
    List<DatasetRecordModel>? records,
  }) async {
    final rows =
        (records ?? await _fetchAllRecords()).map(_toExportRow).toList();
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

  Future<List<DatasetRecordModel>> _fetchAllRecords() async {
    final snapshot = await _firestore.collection('dataset_records').get();
    return snapshot.docs
        .map((doc) => DatasetRecordModel.fromMap(doc.id, doc.data()))
        .toList();
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
    final columnStyles = _headers.map((header) {
      return '<col style="width:${_excelColumnWidth(header)}px">';
    });
    final headerCells = _headers.map(
      (header) =>
          '<th class="header ${_excelCellClass(header)}">${_escapeHtml(header)}</th>',
    );
    final bodyRows = rows.map((row) {
      final cells = _headers.map(
        (header) =>
            '<td class="${_excelCellClass(header)}">${_escapeHtml(row[header])}</td>',
      );
      return '<tr>${cells.join()}</tr>';
    });

    return '''
<html>
<head>
<meta charset="utf-8">
<style>
  table { border-collapse: collapse; table-layout: fixed; }
  tr { height: 28px; }
  th, td {
    border: 1px solid #d9e2ec;
    font-family: Arial, sans-serif;
    font-size: 12px;
    padding: 6px 8px;
    mso-number-format: "\\@";
    vertical-align: top;
    white-space: normal;
    word-wrap: break-word;
  }
  th.header {
    background: #eaf4ff;
    color: #0b1f3a;
    font-weight: 700;
  }
  .short { text-align: left; }
  .medium { text-align: left; }
  .long { text-align: left; }
  .url { color: #334155; font-size: 11px; }
</style>
</head>
<body>
<table>
<colgroup>${columnStyles.join()}</colgroup>
<thead><tr>${headerCells.join()}</tr></thead>
<tbody>${bodyRows.join()}</tbody>
</table>
</body>
</html>
''';
  }

  int _excelColumnWidth(String header) {
    return switch (header) {
      'RecordId' => 190,
      'QrCodeValue' => 260,
      'KitId' => 170,
      'KitName' => 260,
      'TestType' => 240,
      'SelectedResult' => 130,
      'ImageUrl' => 360,
      'ImageName' => 190,
      'SubmittedAt' => 180,
      _ => 160,
    };
  }

  String _excelCellClass(String header) {
    return switch (header) {
      'ImageUrl' => 'url',
      'QrCodeValue' || 'KitName' || 'TestType' => 'long',
      'RecordId' || 'KitId' || 'ImageName' || 'SubmittedAt' => 'medium',
      _ => 'short',
    };
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
      'RecordId': record.recordId,
      'QrCodeValue': record.qrCodeValue,
      'KitId': record.kitId,
      'KitName': record.kitDisplayName,
      'TestType': record.testType,
      'SelectedResult': record.selectedResult,
      'ImageUrl': record.imageUrl,
      'ImageName': record.imageName,
      'SubmittedAt': record.submittedAtDigital,
    };
  }

  List<String> get _headers => const [
    'RecordId',
    'QrCodeValue',
    'KitId',
    'KitName',
    'TestType',
    'SelectedResult',
    'ImageUrl',
    'ImageName',
    'SubmittedAt',
  ];
}
