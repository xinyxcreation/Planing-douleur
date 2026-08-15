import 'dart:typed_data';

Future<void> downloadBytes(Uint8List bytes, String filename) async {
  throw UnsupportedError('Browser download is only available on Web.');
}
