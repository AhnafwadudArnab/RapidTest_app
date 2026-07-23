import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
  });

  final String secureUrl;
  final String publicId;
}

class CloudinaryService {
  const CloudinaryService({
    this.cloudName = const String.fromEnvironment(
      'CLOUDINARY_CLOUD_NAME',
      defaultValue: 'hvz22w32',
    ),
    this.uploadPreset = const String.fromEnvironment(
      'CLOUDINARY_UPLOAD_PRESET',
      defaultValue: 'rapid_test_upload',
    ),
  });

  final String cloudName;
  final String uploadPreset;

  bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;

  Future<CloudinaryUploadResult> uploadImageBytes({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async {
    if (!isConfigured) {
      throw StateError('Cloudinary is not configured.');
    }

    final uri = Uri.https(
      'api.cloudinary.com',
      '/v1_1/${cloudName.trim()}/image/upload',
    );
    final request =
        http.MultipartRequest('POST', uri)
          ..fields['upload_preset'] = uploadPreset.trim()
          ..fields['folder'] = folder
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cloudinary upload failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = (data['secure_url'] ?? '').toString();
    final publicId = (data['public_id'] ?? '').toString();
    if (secureUrl.isEmpty) {
      throw StateError('Cloudinary upload did not return an image URL.');
    }

    return CloudinaryUploadResult(secureUrl: secureUrl, publicId: publicId);
  }
}
