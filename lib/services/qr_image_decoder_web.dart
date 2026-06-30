import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector(_BarcodeDetectorOptions options);
  external JSPromise<JSArray<_DetectedBarcode>> detect(web.ImageBitmap image);
}

extension type _BarcodeDetectorOptions._(JSObject _) implements JSObject {
  external factory _BarcodeDetectorOptions({JSArray<JSString> formats});
}

extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external JSString? get rawValue;
}

Future<String?> decodeQrFromImageBytes(Uint8List bytes) async {
  if (!globalContext.hasProperty('BarcodeDetector'.toJS).toDart) return null;

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/jpeg'),
  );
  final bitmap = await web.window.createImageBitmap(blob).toDart;
  final detector = _BarcodeDetector(
    _BarcodeDetectorOptions(formats: ['qr_code'.toJS].toJS),
  );

  try {
    final barcodes = await detector.detect(bitmap).toDart;
    final length = (barcodes.getProperty<JSNumber>('length'.toJS)).toDartInt;
    for (var i = 0; i < length; i += 1) {
      final rawValue =
          barcodes.getProperty<_DetectedBarcode>(i.toJS).rawValue?.toDart;
      final value = rawValue?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
  } finally {
    bitmap.close();
  }

  return null;
}
