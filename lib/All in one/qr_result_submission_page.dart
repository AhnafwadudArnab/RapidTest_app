import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/database_service.dart';
import '../services/qr_image_decoder_stub.dart'
    if (dart.library.html) '../services/qr_image_decoder_web.dart';
import '../services/qr_parser_service.dart';
import '../widgets/result_option_card.dart';

class QrResultSubmissionPage extends StatefulWidget {
  final String slug;
  final String name;
  final String description;
  final String code;

  const QrResultSubmissionPage({
    super.key,
    this.slug = '',
    this.name = '',
    this.description = '',
    this.code = '',
  });

  @override
  State<QrResultSubmissionPage> createState() => _QrResultSubmissionPageState();
}

class _QrResultSubmissionPageState extends State<QrResultSubmissionPage> {
  final DatabaseService _databaseService = DatabaseService();
  final QrParserService _qrParserService = QrParserService();
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _results = const ['Positive', 'Negative'];

  ParsedQrData? _qrData;
  File? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  Uint8List? _qrCandidatePreviewBytes;
  String? _selectedResult;
  bool _isReadingQr = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _saveRecord() async {
    final qrData = _qrData;
    final selectedResult = _selectedResult;

    final imageFile = _selectedImage;
    final imageBytes = _selectedImageBytes;
    final imageName = _selectedImageName;
    if (qrData == null) {
      _showSnackBar('QR code must be read before submitting.');
      return;
    }
    if (selectedResult == null) {
      _showSnackBar('Select Positive or Negative.');
      return;
    }
    final fallbackTestType =
        widget.name.trim().isNotEmpty
            ? widget.name.trim()
            : qrData.testType.trim().isNotEmpty
            ? qrData.testType.trim()
            : qrData.rawValue.trim();
    final submittedKitName =
        qrData.testType.trim().isNotEmpty ? qrData.testType : fallbackTestType;

    setState(() => _isSaving = true);
    try {
      await _databaseService.submitDatasetRecord(
        qrData: qrData,
        selectedResult: selectedResult,
        fallbackTestType: fallbackTestType,
        imageFile: imageFile,
        imageBytes: imageBytes,
        imageName: imageName,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => SubmissionSuccessPage(
                kitName: submittedKitName,
                selectedResult: selectedResult,
              ),
        ),
      );
    } on FirebaseException catch (e) {
      final message =
          e.code == 'permission-denied'
              ? 'Permission denied. Check Firestore rules for dataset_records create permission.'
              : 'Could not save result: ${e.message ?? e.code}';
      _showSnackBar(message);
    } on StateError catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('Could not save result: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _takePhoto() {
    return _pickImage(ImageSource.camera);
  }

  Future<void> _selectPhotoFromDevice() {
    return _pickImage(ImageSource.gallery);
  }

  Future<void> _scanQrWithCamera() async {
    final rawValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const _LiveQrScannerPage()),
    );
    if (!mounted || rawValue == null || rawValue.trim().isEmpty) return;

    final qrData = await _parseQrData(rawValue);
    if (!mounted) return;
    setState(() {
      _qrData = qrData;
    });
    _showSnackBar('QR code scanned.');
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 900,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();
      final qrCandidatePreviewBytes = await _createQrPreviewCandidateBytes(
        imageBytes,
      );
      setState(() {
        _selectedImage = kIsWeb ? null : File(pickedFile.path);
        _selectedImageBytes = imageBytes;
        _selectedImageName = pickedFile.name;
        _qrCandidatePreviewBytes = qrCandidatePreviewBytes;
      });
      if (kIsWeb) {
        await _readQrFromImageBytes(imageBytes);
      } else {
        await _readQrFromImage(pickedFile.path);
      }
    } on PlatformException {
      final message =
          source == ImageSource.camera
              ? 'Camera could not be opened. Please allow camera permission and try again.'
              : 'Photo picker could not be opened. Please allow photo access and try again.';
      if (mounted) _showSnackBar(message);
    }
  }

  Future<void> _readQrFromImage(String path) async {
    setState(() => _isReadingQr = true);

    try {
      final scanResult = await _readQrValueFromImageCandidates(path);

      if (!mounted) return;
      if (scanResult == null || scanResult.value.isEmpty) {
        _showSnackBar(
          _qrData == null
              ? 'No QR code found. Please scan a clear QR code before submit.'
              : 'No new QR found in this photo. Previous QR details kept.',
        );
        return;
      }

      final qrData = await _parseQrData(scanResult.value);
      if (!mounted) return;
      setState(() {
        _qrData = qrData;
        _qrCandidatePreviewBytes = scanResult.previewBytes;
      });
      _showSnackBar('QR code read from photo.');
    } catch (e) {
      if (mounted) _showSnackBar('Could not read QR from photo: $e');
    } finally {
      if (mounted) setState(() => _isReadingQr = false);
    }
  }

  Future<void> _readQrFromImageBytes(Uint8List bytes) async {
    setState(() => _isReadingQr = true);

    try {
      final candidateBytes = _qrCandidatePreviewBytes;
      final value =
          await decodeQrFromImageBytes(bytes) ??
          (candidateBytes == null
              ? null
              : await decodeQrFromImageBytes(candidateBytes));

      if (!mounted) return;
      if (value == null || value.isEmpty) {
        _showSnackBar(
          'No QR code found. Use Scan QR or upload a clearer QR photo.',
        );
        return;
      }

      final qrData = await _parseQrData(value);
      if (!mounted) return;
      setState(() => _qrData = qrData);
      _showSnackBar('QR code read from photo.');
    } catch (e) {
      if (mounted) _showSnackBar('Could not read QR from photo: $e');
    } finally {
      if (mounted) setState(() => _isReadingQr = false);
    }
  }

  Future<_QrImageScanResult?> _readQrValueFromImageCandidates(
    String path,
  ) async {
    final originalResult = await _readQrValueFromImage(path);
    if (originalResult != null && originalResult.previewBytes != null) {
      return originalResult;
    }

    final cropPaths = await _createZoomedQrScanCrops(path);
    try {
      for (final cropPath in cropPaths) {
        final cropResult = await _readQrValueFromImage(
          cropPath,
          useWholeImageAsPreview: true,
        );
        if (cropResult != null) return cropResult;
      }
    } finally {
      for (final cropPath in cropPaths) {
        try {
          await File(cropPath).delete();
        } catch (_) {
          // Temporary scan crops are best-effort cleanup.
        }
      }
    }

    return originalResult;
  }

  Future<ParsedQrData> _parseQrData(String rawValue) async {
    final parsedData = _qrParserService.parse(rawValue);
    try {
      return await _databaseService.resolveQrKit(parsedData);
    } on FirebaseException {
      return parsedData;
    }
  }

  Future<_QrImageScanResult?> _readQrValueFromImage(
    String path, {
    bool useWholeImageAsPreview = false,
  }) async {
    final capture = await _scannerController.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    );

    final barcode = capture?.barcodes.firstWhere(
      (barcode) => barcode.rawValue?.trim().isNotEmpty == true,
      orElse: () => const Barcode(),
    );
    final value = barcode?.rawValue?.trim();
    if (barcode == null || value == null || value.isEmpty) return null;

    final previewBytes =
        await _cropBarcodePreviewBytes(path, barcode) ??
        (useWholeImageAsPreview ? await File(path).readAsBytes() : null);
    return _QrImageScanResult(value: value, previewBytes: previewBytes);
  }

  Future<Uint8List?> _cropBarcodePreviewBytes(
    String path,
    Barcode barcode,
  ) async {
    final file = File(path);
    if (!await file.exists() || barcode.corners.isEmpty) return null;

    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rect = _barcodeCropRect(image, barcode);
      if (rect == null) return null;
      return _renderCropToBytes(image, rect);
    } finally {
      image.dispose();
    }
  }

  Rect? _barcodeCropRect(ui.Image image, Barcode barcode) {
    final corners = barcode.corners;
    if (corners.isEmpty) return null;

    final maxX = corners.map((point) => point.dx).reduce(math.max);
    final maxY = corners.map((point) => point.dy).reduce(math.max);
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    final scaleX =
        maxX <= 1.2
            ? sourceWidth
            : barcode.size.width > 0
            ? sourceWidth / barcode.size.width
            : 1.0;
    final scaleY =
        maxY <= 1.2
            ? sourceHeight
            : barcode.size.height > 0
            ? sourceHeight / barcode.size.height
            : 1.0;
    final scaled = [
      for (final point in corners) Offset(point.dx * scaleX, point.dy * scaleY),
    ];
    final left = scaled.map((point) => point.dx).reduce(math.min);
    final top = scaled.map((point) => point.dy).reduce(math.min);
    final right = scaled.map((point) => point.dx).reduce(math.max);
    final bottom = scaled.map((point) => point.dy).reduce(math.max);
    final width = math.max(1.0, right - left);
    final height = math.max(1.0, bottom - top);
    final side = math.max(width, height);
    final padding = math.max(24.0, side * 0.28);
    final center = Offset((left + right) / 2, (top + bottom) / 2);
    final cropSide = math.min(
      math.max(side + padding, 1.0),
      math.min(sourceWidth, sourceHeight),
    );
    final cropLeft = (center.dx - cropSide / 2).clamp(
      0.0,
      sourceWidth - cropSide,
    );
    final cropTop = (center.dy - cropSide / 2).clamp(
      0.0,
      sourceHeight - cropSide,
    );

    return Rect.fromLTWH(cropLeft, cropTop, cropSide, cropSide);
  }

  Future<Uint8List?> _renderCropToBytes(ui.Image image, Rect sourceRect) async {
    final targetSide = math.max(360, math.min(1100, sourceRect.width.round()));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImageRect(
      image,
      sourceRect,
      Rect.fromLTWH(0, 0, targetSide.toDouble(), targetSide.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(targetSide, targetSide);
    final pngBytes = await croppedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    croppedImage.dispose();
    picture.dispose();
    return pngBytes?.buffer.asUint8List();
  }

  Future<List<String>> _createZoomedQrScanCrops(String path) async {
    final file = File(path);
    if (!await file.exists()) return const [];

    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    try {
      final crops = <Rect>[
        _fractionRect(image, 0.18, 0.02, 0.64, 0.42),
        _fractionRect(image, 0.22, 0.08, 0.56, 0.40),
        _fractionRect(image, 0.26, 0.12, 0.48, 0.36),
        _fractionRect(image, 0.00, 0.00, 0.55, 0.65),
        _fractionRect(image, 0.22, 0.00, 0.56, 0.65),
        _fractionRect(image, 0.45, 0.00, 0.55, 0.65),
        _fractionRect(image, 0.00, 0.15, 0.55, 0.65),
        _fractionRect(image, 0.22, 0.15, 0.56, 0.65),
        _fractionRect(image, 0.06, 0.20, 0.42, 0.42),
        _fractionRect(image, 0.10, 0.25, 0.36, 0.36),
        _fractionRect(image, 0.18, 0.12, 0.45, 0.50),
        _fractionRect(image, 0.00, 0.00, 1.00, 0.55),
        _fractionRect(image, 0.52, 0.00, 0.48, 0.60),
      ];

      final cropPaths = <String>[];
      for (var i = 0; i < crops.length; i += 1) {
        final cropPath = await _writeZoomedCrop(image, crops[i], i);
        if (cropPath != null) cropPaths.add(cropPath);
      }
      return cropPaths;
    } finally {
      image.dispose();
    }
  }

  Rect _fractionRect(
    ui.Image image,
    double left,
    double top,
    double width,
    double height,
  ) {
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    final x = (sourceWidth * left).clamp(0.0, sourceWidth - 1);
    final y = (sourceHeight * top).clamp(0.0, sourceHeight - 1);
    final w = math.min(sourceWidth * width, sourceWidth - x);
    final h = math.min(sourceHeight * height, sourceHeight - y);

    return Rect.fromLTWH(x, y, math.max(1, w), math.max(1, h));
  }

  Future<String?> _writeZoomedCrop(
    ui.Image image,
    Rect sourceRect,
    int index,
  ) async {
    final longSide = math.max(sourceRect.width, sourceRect.height);
    final scale = longSide < 1400 ? 1400 / longSide : 1.0;
    final contentWidth = math.max(1, (sourceRect.width * scale).round());
    final contentHeight = math.max(1, (sourceRect.height * scale).round());
    final padding = math.max(
      32,
      (math.max(contentWidth, contentHeight) * 0.08).round(),
    );
    final targetWidth = contentWidth + (padding * 2);
    final targetHeight = contentHeight + (padding * 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImageRect(
      image,
      sourceRect,
      Rect.fromLTWH(
        padding.toDouble(),
        padding.toDouble(),
        contentWidth.toDouble(),
        contentHeight.toDouble(),
      ),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(targetWidth, targetHeight);
    final pngBytes = await croppedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    croppedImage.dispose();
    picture.dispose();
    if (pngBytes == null) return null;

    final tempPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'rapid_test_qr_${DateTime.now().microsecondsSinceEpoch}_$index.png';
    await File(tempPath).writeAsBytes(pngBytes.buffer.asUint8List());
    return tempPath;
  }

  Future<Uint8List?> _createQrPreviewCandidateBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final portrait = image.height >= image.width;
      final rect =
          portrait
              ? _fractionRect(image, 0.18, 0.02, 0.64, 0.42)
              : _fractionRect(image, 0.12, 0.02, 0.48, 0.60);
      return _renderCropToBytes(image, rect);
    } finally {
      image.dispose();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSelectedPhotoPreview({
    required File? image,
    required Uint8List? imageBytes,
  }) {
    return showDialog<void>(
      context: context,
      builder:
          (context) => Dialog(
            insetPadding: const EdgeInsets.all(22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Selected Test Photo',
                          style: TextStyle(
                            color: _UserSubmitColors.navy,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: double.infinity,
                      height: MediaQuery.sizeOf(context).height * 0.46,
                      child: _FullPhotoImage(
                        image: image,
                        imageBytes: imageBytes,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _UserSubmitColors.page,
      body: SafeArea(
        child: Column(
          children: [
            const _SubmitTopBar(title: 'Submit Result'),
            Expanded(
              child: _AnimatedSubmitBackground(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _buildTestSummary(),
                    const SizedBox(height: 16),
                    _buildPhotoUpload(),
                    const SizedBox(height: 16),
                    _buildQrArea(),
                    const SizedBox(height: 16),
                    _buildResultCards(),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveRecord,
                      icon:
                          _isSaving
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.save_alt_rounded),
                      label: const Text('Submit Report'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: _UserSubmitColors.blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _UserSubmitColors.border,
                        disabledForegroundColor: _UserSubmitColors.muted,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestSummary() {
    final hasFallbackInfo =
        widget.name.isNotEmpty ||
        widget.code.isNotEmpty ||
        widget.description.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _UserSubmitColors.blue.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubmitSoftIcon(
            icon: Icons.info_outline_rounded,
            color: _UserSubmitColors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFallbackInfo ? widget.name : 'Scan Test Kit QR',
                  style: const TextStyle(
                    color: _UserSubmitColors.navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.code.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Code: ${widget.code}',
                    style: const TextStyle(color: _UserSubmitColors.muted),
                  ),
                ],
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.description,
                    style: const TextStyle(color: _UserSubmitColors.muted),
                  ),
                ],
                if (!hasFallbackInfo) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Scan the kit QR code, choose Positive or Negative, then submit. Photo is optional.',
                    style: TextStyle(
                      color: _UserSubmitColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrArea() {
    final qrData = _qrData;
    if (qrData != null) {
      final kitName =
          qrData.testType.isEmpty ? 'Kit name not found' : qrData.testType;
      final matchedKitDetails =
          qrData.extraData['matchedKitDetails'] is Map<String, dynamic>
              ? qrData.extraData['matchedKitDetails'] as Map<String, dynamic>
              : const <String, dynamic>{};
      final kitQrImageUrl =
          (matchedKitDetails['qrImageUrl'] ?? '').toString().trim();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(scale: 0.96 + (0.04 * value), child: child),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.86),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _UserSubmitColors.green, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _UserSubmitColors.green.withOpacity(0.14),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_2, color: _UserSubmitColors.green),
                  SizedBox(width: 8),
                  Text(
                    'Kit Details',
                    style: TextStyle(
                      color: _UserSubmitColors.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MatchedKitImagePreview(imageUrl: kitQrImageUrl),
              _InfoLine(label: 'Kit Name', value: kitName),
              _InfoLine(label: 'Kit ID', value: qrData.kitId),
              _InfoLine(
                label: 'Category',
                value: (matchedKitDetails['category'] ?? '').toString(),
              ),
              _InfoLine(
                label: 'Sample Type',
                value: (matchedKitDetails['sampleType'] ?? '').toString(),
              ),
              _InfoLine(
                label: 'Manufacturer',
                value: (matchedKitDetails['manufacturer'] ?? '').toString(),
              ),
              _InfoLine(
                label: 'Description',
                value: (matchedKitDetails['description'] ?? '').toString(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _scanQrWithCamera,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Again'),
                  style: TextButton.styleFrom(
                    foregroundColor: _UserSubmitColors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _UserSubmitColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _SubmitSoftIcon(
            icon: _isReadingQr ? Icons.manage_search : Icons.qr_code_scanner,
            color: _UserSubmitColors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isReadingQr
                  ? 'Reading QR code from selected photo...'
                  : 'No QR detected yet. Scan QR or upload a clearer QR photo. QR read is required before submit.',
              style: const TextStyle(
                color: _UserSubmitColors.muted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _isReadingQr ? null : _scanQrWithCamera,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Scan QR'),
            style: FilledButton.styleFrom(
              backgroundColor: _UserSubmitColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoUpload() {
    final image = _selectedImage;
    final imageBytes = _selectedImageBytes;
    final hasImage = image != null || imageBytes != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasImage ? _UserSubmitColors.green : _UserSubmitColors.border,
          width: hasImage ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _SubmitSoftIcon(
                icon: Icons.photo_camera_outlined,
                color: _UserSubmitColors.blue,
                size: 38,
                iconSize: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Test Photo (Optional)',
                style: TextStyle(
                  color: _UserSubmitColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasImage)
            _SelectedTestPhotoPreview(
              image: image,
              imageBytes: imageBytes,
              onTap:
                  () => _showSelectedPhotoPreview(
                    image: image,
                    imageBytes: imageBytes,
                  ),
            )
          else
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _UserSubmitColors.blue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _UserSubmitColors.blue.withOpacity(0.2),
                ),
              ),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Optional. Scan QR first, then submit Positive or Negative.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _UserSubmitColors.muted),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final takePhotoButton = OutlinedButton.icon(
                onPressed: _isReadingQr ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take Photo'),
                style: _submitOutlinedButtonStyle(),
              );
              final selectPhotoButton = OutlinedButton.icon(
                onPressed: _isReadingQr ? null : _selectPhotoFromDevice,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Select Photo'),
                style: _submitOutlinedButtonStyle(),
              );

              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    takePhotoButton,
                    const SizedBox(height: 10),
                    selectPhotoButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: takePhotoButton),
                  const SizedBox(width: 10),
                  Expanded(child: selectPhotoButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Result',
          style: TextStyle(
            color: _UserSubmitColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ..._results.map((result) {
          final selected = _selectedResult == result;
          return ResultOptionCard(
            label: result,
            selected: selected,
            onTap: () => setState(() => _selectedResult = result),
          );
        }),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(
            color: _UserSubmitColors.navy,
            fontWeight: FontWeight.w900,
          ),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _UserSubmitColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchedKitImagePreview extends StatelessWidget {
  const _MatchedKitImagePreview({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return const SizedBox.shrink();

    final dataUrlBytes = _imageBytesFromDataUrl(imageUrl);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 190),
          color: _UserSubmitColors.blue.withOpacity(0.05),
          child:
              dataUrlBytes != null
                  ? Image.memory(
                    dataUrlBytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  )
                  : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
        ),
      ),
    );
  }
}

Uint8List? _imageBytesFromDataUrl(String value) {
  final commaIndex = value.indexOf(',');
  if (!value.startsWith('data:image/') || commaIndex < 0) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

class _SelectedTestPhotoPreview extends StatelessWidget {
  const _SelectedTestPhotoPreview({
    required this.image,
    required this.imageBytes,
    required this.onTap,
  });

  final File? image;
  final Uint8List? imageBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 230,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _UserSubmitColors.blue.withOpacity(0.04),
          border: Border.all(color: _UserSubmitColors.blue.withOpacity(0.18)),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _FullPhotoImage(image: image, imageBytes: imageBytes),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Tap to view',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullPhotoImage extends StatelessWidget {
  const _FullPhotoImage({required this.image, required this.imageBytes});

  final File? image;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    final file = image;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    return const Center(
      child: Text(
        'No photo selected',
        style: TextStyle(color: _UserSubmitColors.muted),
      ),
    );
  }
}

class _QrImageScanResult {
  const _QrImageScanResult({required this.value, required this.previewBytes});

  final String value;
  final Uint8List? previewBytes;
}

class _SubmitTopBar extends StatelessWidget {
  const _SubmitTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      height: compact ? 86 : 104,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071B45), Color(0xFF0A2F66)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 28),
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 22 : 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 54),
        ],
      ),
    );
  }
}

class _AnimatedSubmitBackground extends StatefulWidget {
  const _AnimatedSubmitBackground({required this.child});

  final Widget child;

  @override
  State<_AnimatedSubmitBackground> createState() =>
      _AnimatedSubmitBackgroundState();
}

class _AnimatedSubmitBackgroundState extends State<_AnimatedSubmitBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.9 + value * 0.6, -1),
              end: Alignment(0.8 - value * 0.4, 1),
              colors: const [
                Color(0xFFF8FAFD),
                Color(0xFFEFF7FF),
                Color(0xFFF7FFFC),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SubmitSoftIcon extends StatelessWidget {
  const _SubmitSoftIcon({
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

ButtonStyle _submitOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: _UserSubmitColors.blue,
    side: const BorderSide(color: _UserSubmitColors.blue),
    minimumSize: const Size.fromHeight(48),
    textStyle: const TextStyle(fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
  );
}

class _UserSubmitColors {
  static const page = Color(0xFFF4F7FB);
  static const navy = Color(0xFF111D35);
  static const muted = Color(0xFF657086);
  static const border = Color(0xFFE2E6EF);
  static const blue = Color(0xFF137AC9);
  static const green = Color(0xFF14976A);
}

class _LiveQrScannerPage extends StatefulWidget {
  const _LiveQrScannerPage();

  @override
  State<_LiveQrScannerPage> createState() => _LiveQrScannerPageState();
}

class _LiveQrScannerPageState extends State<_LiveQrScannerPage> {
  late final MobileScannerController _controller;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_hasScanned) return;

    final rawValue =
        capture.barcodes
            .map((barcode) => barcode.rawValue)
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .firstOrNull;
    if (rawValue == null) return;

    _hasScanned = true;
    await _controller.stop();
    if (mounted) Navigator.pop(context, rawValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan Kit QR Code'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final guideSize = math.min(constraints.maxWidth * 0.78, 290.0);
          final guideWindow = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
            width: guideSize,
            height: guideSize,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _handleDetect),
              CustomPaint(painter: _ScannerOverlayPainter(guideWindow)),
              Positioned.fromRect(
                rect: guideWindow,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(
                    children: const [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Auto scan anywhere',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.68),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Keep the QR code visible anywhere in the camera frame. The app will detect it automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter(this.scanWindow);

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final cornerPaint =
        Paint()
          ..color = _UserSubmitColors.green
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    const cornerLength = 34.0;
    final radius = RRect.fromRectAndRadius(
      scanWindow.deflate(2),
      const Radius.circular(14),
    );
    final rect = radius.outerRect;

    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(0, cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(0, cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(0, -cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(0, -cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}

class SubmissionSuccessPage extends StatelessWidget {
  const SubmissionSuccessPage({
    super.key,
    required this.kitName,
    required this.selectedResult,
  });

  final String kitName;
  final String selectedResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submission Complete')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 82,
              ),
            ),
            const SizedBox(height: 18),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: const Text(
                'Result submitted and approved.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 18),
            Text('Selected Result: $selectedResult'),
            if (kitName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Kit Name: $kitName'),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
