import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/dataset_record_model.dart';
import 'qr_parser_service.dart';

class DatabaseService {
  DatabaseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _records =>
      _firestore.collection('dataset_records');

  CollectionReference<Map<String, dynamic>> get _qrKits =>
      _firestore.collection('qr_kits');

  static const List<QrKitRecord> defaultQrKits = [
    QrKitRecord(
      qrCode: 'CRATS160525',
      kitName: 'Covid-19 Rapid Antigen Test Kit',
      category: 'Infectious disease',
      sampleType: 'Nasal swab',
      manufacturer: 'Rapid Test Kit',
      description: 'Admin default kit for QR code CRATS160525.',
    ),
    QrKitRecord(
      qrCode: 'MRATC120525',
      kitName: 'Malaria Pf/Pan Combo Test Kit',
      category: 'Infectious disease',
      sampleType: 'Blood',
      manufacturer: 'Rapid Test Kit',
      description: 'Admin default kit for QR code MRATC120525.',
    ),
  ];

  Future<void> submitDatasetRecord({
    required ParsedQrData? qrData,
    required String selectedResult,
    required String fallbackTestType,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    if (!DatasetRecordModel.allowedResults.contains(selectedResult)) {
      throw ArgumentError('Invalid selected result.');
    }

    final user = await _refreshCurrentUser();
    if (user == null) {
      throw StateError('User must be logged in.');
    }

    final userProfile = await _loadUserProfile(user.uid);
    final doc = _records.doc();
    final now = FieldValue.serverTimestamp();
    final resolvedTestType =
        (qrData?.testType ?? '').isNotEmpty
            ? qrData!.testType
            : fallbackTestType;
    final qrExtraData = qrData?.extraData ?? const <String, dynamic>{};
    final matchedKitDetails =
        qrExtraData['matchedKitDetails'] is Map<String, dynamic>
            ? qrExtraData['matchedKitDetails'] as Map<String, dynamic>
            : const <String, dynamic>{};
    var imageStoragePath = '';
    var imageUrl = '';
    var imageUploadError = '';

    if (imageFile != null || imageBytes != null) {
      final safeImageName = _safeImageName(imageName, doc.id);
      imageStoragePath =
          'rapid_test_reports/${user.uid}/${doc.id}_${DateTime.now().millisecondsSinceEpoch}_$safeImageName';
      try {
        final ref = _storage.ref(imageStoragePath);
        final metadata = SettableMetadata(
          contentType: _contentTypeFor(safeImageName),
        );
        final uploadTask =
            imageBytes != null
                ? await ref.putData(imageBytes, metadata)
                : await ref.putFile(imageFile!, metadata);
        imageUrl = await uploadTask.ref.getDownloadURL();
      } on FirebaseException catch (e) {
        imageUploadError =
            e.code == 'permission-denied'
                ? 'Kit photo upload permission denied.'
                : 'Kit photo upload failed: ${e.message ?? e.code}';
        imageStoragePath = '';
        imageUrl = '';
      }
    }

    await doc.set({
      'recordId': doc.id,
      'userId': user.uid,
      'userName': userProfile['name'] ?? user.displayName ?? '',
      'userEmail': user.email ?? userProfile['email'] ?? '',
      'qrCodeValue': resolvedTestType,
      'kitId': qrData?.kitId ?? '',
      'testType': resolvedTestType,
      'isKnownQrKit': qrData?.isKnownKit == true,
      'matchedQrKitId': qrExtraData['matchedQrKitId'] ?? '',
      'matchedQrCode': qrExtraData['matchedQrCode'] ?? '',
      'matchedKitName': qrExtraData['matchedKitName'] ?? '',
      'kitCategory': matchedKitDetails['category'] ?? '',
      'kitSampleType': matchedKitDetails['sampleType'] ?? '',
      'kitManufacturer': matchedKitDetails['manufacturer'] ?? '',
      'kitDescription': matchedKitDetails['description'] ?? '',
      'kitQrImageUrl': matchedKitDetails['qrImageUrl'] ?? '',
      'kitQrImageName': matchedKitDetails['qrImageName'] ?? '',
      'selectedResult': selectedResult,
      'imageUrl': imageUrl,
      'imageName': imageName ?? '',
      'imageStoragePath': imageStoragePath,
      'reviewStatus': 'Approved',
      'adminComment': imageUploadError,
      'reviewedBy': 'Auto Approval',
      'reviewedAt': now,
      'qrParsedData': qrExtraData,
      'submittedAt': now,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchQrKits() {
    return _qrKits.orderBy('kitName').snapshots();
  }

  Future<void> saveQrKit({
    required String qrCode,
    required String kitName,
    String category = '',
    String sampleType = '',
    String manufacturer = '',
    String description = '',
    Uint8List? qrImageBytes,
    String? qrImageName,
  }) async {
    final normalizedCode = normalizeQrKitCode(qrCode);
    final cleanKitName = kitName.trim();
    if (normalizedCode.isEmpty || cleanKitName.isEmpty) {
      throw ArgumentError('QR code and kit name are required.');
    }

    final docRef = _qrKits.doc(qrKitDocumentId(normalizedCode));
    final existing = await docRef.get();
    final existingData = existing.data() ?? const <String, dynamic>{};
    var qrImageUrl = (existingData['qrImageUrl'] ?? '').toString();
    var qrImageStoragePath =
        (existingData['qrImageStoragePath'] ?? '').toString();
    final cleanQrImageName = qrImageName?.trim() ?? '';

    if (qrImageBytes != null && qrImageBytes.isNotEmpty) {
      final safeImageName = _safeImageName(
        cleanQrImageName.isEmpty ? null : cleanQrImageName,
        docRef.id,
      );
      qrImageStoragePath =
          'qr_kit_images/${docRef.id}/${DateTime.now().millisecondsSinceEpoch}_$safeImageName';
      final ref = _storage.ref(qrImageStoragePath);
      final uploadTask = await ref.putData(
        qrImageBytes,
        SettableMetadata(contentType: _contentTypeFor(safeImageName)),
      );
      qrImageUrl = await uploadTask.ref.getDownloadURL();
    }

    final data = {
      'qrCode': normalizedCode,
      'qrCodeNormalized': normalizedCode,
      'kitName': cleanKitName,
      'category': category.trim(),
      'sampleType': sampleType.trim(),
      'manufacturer': manufacturer.trim(),
      'description': description.trim(),
      'qrImageUrl': qrImageUrl,
      'qrImageName':
          cleanQrImageName.isNotEmpty
              ? cleanQrImageName
              : (existingData['qrImageName'] ?? '').toString(),
      'qrImageStoragePath': qrImageStoragePath,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data, SetOptions(merge: true));
  }

  Future<void> deleteQrKit(String qrCode) {
    return _qrKits.doc(qrKitDocumentId(qrCode)).delete();
  }

  Future<void> seedDefaultQrKits() async {
    for (final kit in defaultQrKits) {
      await saveQrKit(
        qrCode: kit.qrCode,
        kitName: kit.kitName,
        category: kit.category,
        sampleType: kit.sampleType,
        manufacturer: kit.manufacturer,
        description: kit.description,
      );
    }
  }

  Future<ParsedQrData> resolveQrKit(ParsedQrData qrData) async {
    final candidates = <String>{
      normalizeQrKitCode(qrData.rawValue),
      normalizeQrKitCode(qrData.kitId),
      normalizeQrKitCode(qrData.testType),
    }..removeWhere((value) => value.isEmpty);

    try {
      for (final code in candidates) {
        final doc = await _qrKits.doc(qrKitDocumentId(code)).get();
        final kit = QrKitRecord.fromMap(doc.id, doc.data());
        if (kit != null && kit.isActive) {
          return _applyResolvedKit(qrData, kit);
        }
      }

      if (candidates.isNotEmpty) {
        final snapshot =
            await _qrKits
                .where(
                  'qrCodeNormalized',
                  whereIn: candidates.take(10).toList(),
                )
                .limit(1)
                .get();
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final kit = QrKitRecord.fromMap(doc.id, doc.data());
          if (kit != null && kit.isActive) {
            return _applyResolvedKit(qrData, kit);
          }
        }
      }
    } on FirebaseException {
      // Local bundled kits still resolve when rules are not deployed yet.
    }

    for (final code in candidates) {
      final kit = _defaultQrKitFor(code);
      if (kit != null && kit.isActive) {
        return _applyResolvedKit(qrData, kit);
      }
    }

    return qrData;
  }

  QrKitRecord? _defaultQrKitFor(String code) {
    final normalizedCode = normalizeQrKitCode(code);
    for (final kit in defaultQrKits) {
      if (normalizeQrKitCode(kit.qrCode) == normalizedCode) return kit;
    }
    return null;
  }

  ParsedQrData _applyResolvedKit(ParsedQrData qrData, QrKitRecord kit) {
    return qrData.copyWith(
      kitId: kit.qrCode,
      testType: kit.kitName,
      isKnownKit: true,
      extraData: {
        ...qrData.extraData,
        'isKnownKit': true,
        'matchedQrCode': kit.qrCode,
        'matchedKitName': kit.kitName,
        'matchedQrKitId': qrKitDocumentId(kit.qrCode),
        'matchedKitDetails': kit.toMap(),
      },
    );
  }

  static String normalizeQrKitCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static String qrKitDocumentId(String value) {
    final normalized = normalizeQrKitCode(value);
    final safe = normalized.replaceAll(RegExp(r'[^A-Z0-9_-]'), '_');
    return safe.isEmpty ? 'UNKNOWN_QR_KIT' : safe;
  }

  String _contentTypeFor(String imageName) {
    final lowerName = imageName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _safeImageName(String? imageName, String docId) {
    final trimmed = imageName?.trim();
    final fallback = 'kit_photo_$docId.jpg';
    final value = trimmed == null || trimmed.isEmpty ? fallback : trimmed;
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecords() {
    return _records.orderBy('createdAt', descending: true).snapshots();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchRecordsPage({
    int limit = 25,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    String? selectedResult,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    Query<Map<String, dynamic>> query = _records;
    if (selectedResult != null && selectedResult.isNotEmpty) {
      query = query.where('selectedResult', isEqualTo: selectedResult);
    }
    if (startDate != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }
    query = query.orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    return query.get();
  }

  Future<int> countRecords({
    String? selectedResult,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query<Map<String, dynamic>> query = _records;
    if (selectedResult != null && selectedResult.isNotEmpty) {
      query = query.where('selectedResult', isEqualTo: selectedResult);
    }
    if (startDate != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCurrentUserRecords() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _records.where('userId', isEqualTo: uid).snapshots();
  }

  Future<void> updateReviewStatus({
    required String recordId,
    required String reviewStatus,
    required String adminComment,
  }) {
    if (!DatasetRecordModel.allowedStatuses.contains(reviewStatus)) {
      throw ArgumentError('Invalid review status.');
    }

    return _records.doc(recordId).update({
      'reviewStatus': reviewStatus,
      'adminComment': adminComment,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> _loadUserProfile(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      return userDoc.data() ?? {};
    } on FirebaseException {
      return {};
    }
  }

  Future<User?> _refreshCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      await user.reload();
      await user.getIdToken(true);
    } catch (_) {
      return null;
    }

    return _auth.currentUser;
  }
}

class QrKitRecord {
  const QrKitRecord({
    required this.qrCode,
    required this.kitName,
    this.category = '',
    this.sampleType = '',
    this.manufacturer = '',
    this.description = '',
    this.qrImageUrl = '',
    this.qrImageName = '',
    this.qrImageStoragePath = '',
    this.isActive = true,
  });

  final String qrCode;
  final String kitName;
  final String category;
  final String sampleType;
  final String manufacturer;
  final String description;
  final String qrImageUrl;
  final String qrImageName;
  final String qrImageStoragePath;
  final bool isActive;

  static QrKitRecord? fromMap(String id, Map<String, dynamic>? data) {
    if (data == null) return null;
    final qrCode =
        (data['qrCode'] ?? data['qrCodeNormalized'] ?? id).toString();
    final kitName = (data['kitName'] ?? data['testType'] ?? '').toString();
    if (qrCode.trim().isEmpty || kitName.trim().isEmpty) return null;
    return QrKitRecord(
      qrCode: DatabaseService.normalizeQrKitCode(qrCode),
      kitName: kitName.trim(),
      category: (data['category'] ?? '').toString().trim(),
      sampleType: (data['sampleType'] ?? '').toString().trim(),
      manufacturer: (data['manufacturer'] ?? '').toString().trim(),
      description: (data['description'] ?? '').toString().trim(),
      qrImageUrl: (data['qrImageUrl'] ?? '').toString().trim(),
      qrImageName: (data['qrImageName'] ?? '').toString().trim(),
      qrImageStoragePath: (data['qrImageStoragePath'] ?? '').toString().trim(),
      isActive: data['isActive'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'qrCode': qrCode,
      'kitName': kitName,
      'category': category,
      'sampleType': sampleType,
      'manufacturer': manufacturer,
      'description': description,
      'qrImageUrl': qrImageUrl,
      'qrImageName': qrImageName,
      'qrImageStoragePath': qrImageStoragePath,
      'isActive': isActive,
    };
  }
}
