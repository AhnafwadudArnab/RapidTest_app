import 'dart:convert';

class ParsedQrData {
  const ParsedQrData({
    required this.rawValue,
    required this.kitId,
    required this.testType,
    required this.extraData,
  });

  final String rawValue;
  final String kitId;
  final String testType;
  final Map<String, dynamic> extraData;
}

class QrParserService {
  ParsedQrData parse(String rawValue) {
    final trimmed = rawValue.trim();
    final detectedTestType = _detectKnownTestType(trimmed);
    final jsonData = _tryReadJson(trimmed);
    if (jsonData != null) {
      return ParsedQrData(
        rawValue: rawValue,
        kitId:
            _readFirst(jsonData, const ['kitId', 'kit_id', 'kitID', 'id']) ??
            '',
        testType:
            _readFirst(jsonData, const [
              'kitName',
              'kit_name',
              'kitType',
              'kit_type',
              'productName',
              'product_name',
              'testType',
              'test_type',
              'type',
              'testName',
              'name',
            ]) ??
            detectedTestType ??
            '',
        extraData: jsonData,
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      return ParsedQrData(
        rawValue: rawValue,
        kitId:
            _readFirst(uri.queryParameters, const ['kitId', 'kit_id', 'id']) ??
            '',
        testType:
            _readFirst(uri.queryParameters, const [
              'kitName',
              'kit_name',
              'kitType',
              'kit_type',
              'productName',
              'product_name',
              'testType',
              'test_type',
              'type',
              'testName',
              'name',
            ]) ??
            detectedTestType ??
            '',
        extraData: uri.queryParameters,
      );
    }

    final extractedTestType =
        _extractToken(trimmed, 'kitName') ??
        _extractToken(trimmed, 'kit name') ??
        _extractToken(trimmed, 'kit_name') ??
        _extractToken(trimmed, 'kitType') ??
        _extractToken(trimmed, 'kit type') ??
        _extractToken(trimmed, 'productName') ??
        _extractToken(trimmed, 'product name') ??
        _extractToken(trimmed, 'name') ??
        _extractToken(trimmed, 'test') ??
        detectedTestType ??
        _plainTextTestType(trimmed);

    return ParsedQrData(
      rawValue: rawValue,
      kitId: _extractToken(trimmed, 'kit') ?? '',
      testType: extractedTestType ?? '',
      extraData: const {},
    );
  }

  Map<String, dynamic>? _tryReadJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _readFirst(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return null;
  }

  String? _extractToken(String value, String label) {
    final pattern = RegExp(
      '$label\\s*[:=-]\\s*([^,;|]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(value);
    return match?.group(1)?.trim();
  }

  String? _detectKnownTestType(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      ' ',
    );

    if (normalized.contains('typhoid') &&
        normalized.contains('igg') &&
        normalized.contains('igm')) {
      return 'Typhoid IgG/IgM';
    }
    if (normalized.contains('dengue') &&
        normalized.contains('igg') &&
        normalized.contains('igm')) {
      return 'Dengue IgG/IgM';
    }
    if (normalized.contains('dengue') && normalized.contains('ns1')) {
      return 'Dengue NS1 Ag';
    }
    if (normalized.contains('covid') || normalized.contains('covid19')) {
      return 'COVID-19 Ag';
    }

    return null;
  }

  String? _plainTextTestType(String value) {
    if (value.contains('://')) return null;
    if (value.length > 80) return null;
    if (RegExp(r'[{}[\]]').hasMatch(value)) return null;

    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
