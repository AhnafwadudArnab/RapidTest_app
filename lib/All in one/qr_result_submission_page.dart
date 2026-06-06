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

    if (selectedResult == null) {
      _showSnackBar('Select Positive or Negative.');
      return;
    }
    final imageFile = _selectedImage;
    final imageBytes = _selectedImageBytes;
    final imageName = _selectedImageName;
    if (imageFile == null && imageBytes == null) {
      _showSnackBar('Take or upload a kit photo before submitting.');
      return;
    }
    final fallbackTestType =
        widget.name.trim().isNotEmpty
            ? widget.name.trim()
            : 'Kit photo without QR';
    final submittedKitName =
        qrData?.testType.trim().isNotEmpty == true
            ? qrData!.testType
            : fallbackTestType;

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

    setState(() => _qrData = _qrParserService.parse(rawValue));
    _showSnackBar('QR code scanned.');
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1600,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImage = kIsWeb ? null : File(pickedFile.path);
        _selectedImageBytes = imageBytes;
        _selectedImageName = pickedFile.name;
      });
      if (kIsWeb) {
        if (mounted && _qrData == null) {
          _showSnackBar('Photo kept. Use Scan QR if the kit has a QR code.');
        }
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
      final value = await _readQrValueFromImageCandidates(path);

      if (!mounted) return;
      if (value == null || value.isEmpty) {
        _showSnackBar(
          _qrData == null
              ? 'No QR code found. Photo kept; select result and submit.'
              : 'No new QR found in this photo. Previous QR details kept.',
        );
        return;
      }

      setState(() => _qrData = _qrParserService.parse(value));
      _showSnackBar('QR code read from photo.');
    } catch (e) {
      if (mounted) _showSnackBar('Could not read QR from photo: $e');
    } finally {
      if (mounted) setState(() => _isReadingQr = false);
    }
  }

  Future<String?> _readQrValueFromImageCandidates(String path) async {
    final originalValue = await _readQrValueFromImage(path);
    if (originalValue != null) return originalValue;

    final cropPaths = await _createZoomedQrScanCrops(path);
    try {
      for (final cropPath in cropPaths) {
        final cropValue = await _readQrValueFromImage(cropPath);
        if (cropValue != null) return cropValue;
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

    return null;
  }

  Future<String?> _readQrValueFromImage(String path) async {
    final capture = await _scannerController.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    );

    return capture?.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
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
        _fractionRect(image, 0.00, 0.00, 0.55, 0.65),
        _fractionRect(image, 0.00, 0.15, 0.55, 0.65),
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Photo and Submit Result'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTestSummary(),
            const SizedBox(height: 16),
            _buildPhotoUpload(),
            const SizedBox(height: 16),
            _buildQrArea(),
            const SizedBox(height: 16),
            _buildResultCards(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveRecord,
              icon:
                  _isSaving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_alt),
              label: const Text('Submit Result'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9CCCEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasFallbackInfo ? widget.name : 'Upload Your Test Kit Photo',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (widget.code.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Code: ${widget.code}'),
          ],
          if (widget.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.description),
          ],
          if (!hasFallbackInfo) ...[
            const SizedBox(height: 6),
            const Text(
              'Take or upload a kit photo. If it has a QR code, scan it for kit details; otherwise submit the photo with the selected result.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQrArea() {
    final qrData = _qrData;
    if (qrData != null) {
      final kitName =
          qrData.testType.isEmpty ? 'Kit name not found' : qrData.testType;
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.18),
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
                  Icon(Icons.qr_code_2, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Kit Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InfoLine(label: 'Kit Name', value: kitName),
              _InfoLine(label: 'Kit ID', value: qrData.kitId),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _scanQrWithCamera,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Again'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(
            _isReadingQr ? Icons.manage_search : Icons.qr_code_scanner,
            color: Colors.blue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isReadingQr
                  ? 'Reading QR code from selected photo...'
                  : 'No QR detected yet. Scan QR if the kit has one, or submit with the kit photo only.',
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _isReadingQr ? null : _scanQrWithCamera,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Scan QR'),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasImage ? Colors.green : Colors.grey.shade300,
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
              Icon(Icons.photo_camera_outlined, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Test Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  imageBytes != null
                      ? Image.memory(
                        imageBytes,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                      : Image.file(
                        image!,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
            )
          else
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF9CCCEC)),
              ),
              child: const Center(
                child: Text(
                  'Take a photo with camera or select one from your device.',
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
              );
              final selectPhotoButton = OutlinedButton.icon(
                onPressed: _isReadingQr ? null : _selectPhotoFromDevice,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Select Photo'),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
      child: Text('$label: $value'),
    );
  }
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
      appBar: AppBar(title: const Text('Scan Kit QR Code'), centerTitle: true),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Place the QR code inside the box.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
