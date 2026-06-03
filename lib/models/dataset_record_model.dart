import 'package:cloud_firestore/cloud_firestore.dart';

class DatasetRecordModel {
  static const allowedResults = ['Positive', 'Negative'];
  static const allowedStatuses = ['Pending', 'Approved', 'Rejected'];

  const DatasetRecordModel({
    required this.recordId,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.qrCodeValue,
    required this.kitId,
    required this.testType,
    required this.selectedResult,
    required this.imageUrl,
    required this.imageName,
    required this.imageStoragePath,
    required this.reviewStatus,
    required this.adminComment,
    required this.submittedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String recordId;
  final String userId;
  final String userName;
  final String userEmail;
  final String qrCodeValue;
  final String kitId;
  final String testType;
  final String selectedResult;
  final String imageUrl;
  final String imageName;
  final String imageStoragePath;
  final String reviewStatus;
  final String adminComment;
  final DateTime? submittedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get kitDisplayName {
    final cleanTestType = testType.trim();
    if (cleanTestType.isNotEmpty) return cleanTestType;

    final cleanKitId = kitId.trim();
    if (cleanKitId.isNotEmpty) return cleanKitId;

    return 'Kit name not found';
  }

  String get submittedAtDigital =>
      formatDigitalDateTime(submittedAt, fallback: 'Pending server time');

  static String formatDigitalDateTime(DateTime? value, {String fallback = ''}) {
    if (value == null) return fallback;

    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  factory DatasetRecordModel.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return DatasetRecordModel.fromMap(doc.id, doc.data());
  }

  factory DatasetRecordModel.fromMap(String id, Map<String, dynamic> data) {
    return DatasetRecordModel(
      recordId: data['recordId'] ?? id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userEmail: data['userEmail'] ?? '',
      qrCodeValue: data['qrCodeValue'] ?? data['qrValue'] ?? '',
      kitId: data['kitId'] ?? '',
      testType: data['testType'] ?? data['testName'] ?? '',
      selectedResult: data['selectedResult'] ?? '',
      imageUrl: _readFirstString(data, [
        'imageUrl',
        'kitPhotoUrl',
        'photoUrl',
        'testPhotoUrl',
        'imageDownloadUrl',
        'downloadUrl',
      ]),
      imageName: data['imageName'] ?? '',
      imageStoragePath: _readFirstString(data, [
        'imageStoragePath',
        'kitPhotoStoragePath',
        'photoStoragePath',
        'storagePath',
      ]),
      reviewStatus: data['reviewStatus'] ?? data['status'] ?? 'Pending',
      adminComment: data['adminComment'] ?? '',
      submittedAt: _readDate(data['submittedAt']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recordId': recordId,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'qrCodeValue': qrCodeValue,
      'kitId': kitId,
      'testType': testType,
      'selectedResult': selectedResult,
      'imageUrl': imageUrl,
      'imageName': imageName,
      'imageStoragePath': imageStoragePath,
      'reviewStatus': reviewStatus,
      'adminComment': adminComment,
      'submittedAt': submittedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static String _readFirstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return '';
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
