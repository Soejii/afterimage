import 'dart:typed_data';

typedef TestRgbPixel = List<int> Function(int x, int y);

Uint8List makeTestBmp({
  required int width,
  required int height,
  int bitsPerPixel = 24,
  int compression = 0,
  bool topDown = false,
  TestRgbPixel? pixelAt,
}) {
  final bytesPerPixel = bitsPerPixel ~/ 8;
  final rowStride = ((width * bitsPerPixel + 31) ~/ 32) * 4;
  final pixelOffset = compression == 3 ? 66 : 54;
  final fileSize = pixelOffset + rowStride * height;
  final bytes = Uint8List(fileSize);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0x42;
  bytes[1] = 0x4d;
  data
    ..setUint32(2, fileSize, Endian.little)
    ..setUint32(10, pixelOffset, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, topDown ? -height : height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, bitsPerPixel, Endian.little)
    ..setUint32(30, compression, Endian.little)
    ..setUint32(34, rowStride * height, Endian.little);
  if (compression == 3) {
    data
      ..setUint32(54, 0x00ff0000, Endian.little)
      ..setUint32(58, 0x0000ff00, Endian.little)
      ..setUint32(62, 0x000000ff, Endian.little);
  }
  final colorAt = pixelAt ?? (x, y) => const [0, 0, 0];
  for (var storageY = 0; storageY < height; storageY++) {
    final y = topDown ? storageY : height - storageY - 1;
    final rowOffset = pixelOffset + storageY * rowStride;
    for (var x = 0; x < width; x++) {
      final rgb = colorAt(x, y);
      final offset = rowOffset + x * bytesPerPixel;
      bytes[offset] = rgb[2];
      bytes[offset + 1] = rgb[1];
      bytes[offset + 2] = rgb[0];
      if (bytesPerPixel == 4) {
        bytes[offset + 3] = 0;
      }
    }
  }
  return bytes;
}
