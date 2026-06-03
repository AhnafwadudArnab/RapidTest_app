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
    var imageStoragePath = '';
    var imageUrl = '';

    if ((imageFile != null || imageBytes != null) &&
        imageName != null &&
        imageName.isNotEmpty) {
      imageStoragePath =
          'rapid_test_reports/${user.uid}/${doc.id}_${DateTime.now().millisecondsSinceEpoch}_$imageName';
      try {
        final ref = _storage.ref(imageStoragePath);
        final uploadTask =
            imageBytes != null
                ? await ref.putData(
                  imageBytes,
                  SettableMetadata(contentType: _contentTypeFor(imageName)),
                )
                : await ref.putFile(imageFile!);
        imageUrl = await uploadTask.ref.getDownloadURL();
      } on FirebaseException catch (e) {
        throw StateError(
          e.code == 'permission-denied'
              ? 'Kit photo upload permission denied. Check Firebase Storage rules for rapid_test_reports.'
              : 'Kit photo upload failed: ${e.message ?? e.code}',
        );
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
      'selectedResult': selectedResult,
      'imageUrl': imageUrl,
      'imageName': imageName ?? '',
      'imageStoragePath': imageStoragePath,
      'reviewStatus': 'Approved',
      'adminComment': '',
      'reviewedBy': 'Auto Approval',
      'reviewedAt': now,
      'qrParsedData': qrData?.extraData ?? {},
      'submittedAt': now,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  String _contentTypeFor(String imageName) {
    final lowerName = imageName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
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
