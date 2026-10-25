import 'dart:typed_data';

/// A decoded, top-to-bottom 24-bit RGB image.
class RgbImage {
  RgbImage({
    required this.width,
    required this.height,
    required List<int> rgb,
    List<int>? bmpBytes,
  })  : rgb = List<int>.unmodifiable(rgb),
        bmpBytes = bmpBytes == null ? null : List<int>.unmodifiable(bmpBytes) {
    if (width <= 0 || height <= 0 || rgb.length != width * height * 3) {
      throw ArgumentError('RGB image dimensions do not match its pixel data.');
    }
    if (rgb.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('RGB channel values must be between 0 and 255.');
    }
  }

  final int width;
  final int height;
  final List<int> rgb;

  /// The exact source bytes, when this image was decoded from a BMP.
  final List<int>? bmpBytes;

  int channelAt(int x, int y, int channel) =>
      rgb[(y * width + x) * 3 + channel];
}

/// Decodes uncompressed Windows BMP images used by OBS screenshots.
///
/// Supports 24/32-bit BI_RGB and BI_BITFIELDS images, either row orientation,
/// and the four-byte row padding required by the BMP format.
RgbImage decodeBmpImage(List<int> bytes) {
  const maxFileBytes = 8000000;
  const maxPixels = 16000000;
  if (bytes.length < 54 || bytes.length > maxFileBytes) {
    throw const FormatException('BMP size is outside the supported bounds.');
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  if (data.getUint8(0) != 0x42 || data.getUint8(1) != 0x4d) {
    throw const FormatException('BMP signature is missing.');
  }

  final declaredFileSize = data.getUint32(2, Endian.little);
  final pixelOffset = data.getUint32(10, Endian.little);
  final headerSize = data.getUint32(14, Endian.little);
  if (headerSize < 40 || headerSize > bytes.length - 14) {
    throw const FormatException('Unsupported or truncated BMP header.');
  }
  if (declaredFileSize != 0 && declaredFileSize > bytes.length) {
    throw const FormatException('BMP file is truncated.');
  }

  final width = data.getInt32(18, Endian.little);
  final signedHeight = data.getInt32(22, Endian.little);
  final planes = data.getUint16(26, Endian.little);
  final bitsPerPixel = data.getUint16(28, Endian.little);
  final compression = data.getUint32(30, Endian.little);
  final imageSize = data.getUint32(34, Endian.little);
  if (width <= 0 || signedHeight == 0 || signedHeight == -0x80000000) {
    throw const FormatException('BMP dimensions are invalid.');
  }
  final height = signedHeight.abs();
  if (width * height > maxPixels) {
    throw const FormatException('BMP dimensions exceed the supported bounds.');
  }
  if (planes != 1) {
    throw const FormatException('BMP must contain exactly one image plane.');
  }
  if (bitsPerPixel != 24 && bitsPerPixel != 32) {
    throw FormatException('Unsupported BMP bit depth: $bitsPerPixel.');
  }
  if (compression != 0 && compression != 3) {
    throw FormatException('Unsupported BMP compression type: $compression.');
  }

  final bytesPerPixel = bitsPerPixel ~/ 8;
  final rowStride = ((width * bitsPerPixel + 31) ~/ 32) * 4;
  final requiredBytes = rowStride * height;
  if (pixelOffset < 14 + headerSize ||
      pixelOffset > bytes.length ||
      requiredBytes > bytes.length - pixelOffset ||
      (imageSize != 0 && imageSize < requiredBytes)) {
    throw const FormatException('BMP pixel data is missing or truncated.');
  }

  _BmpChannelMask? redMask;
  _BmpChannelMask? greenMask;
  _BmpChannelMask? blueMask;
  if (compression == 3) {
    final masksOffset = headerSize >= 52 ? 14 + 40 : 14 + headerSize;
    if (masksOffset + 12 > pixelOffset || masksOffset + 12 > bytes.length) {
      throw const FormatException('BMP bitfield color masks are missing.');
    }
    final red = data.getUint32(masksOffset, Endian.little);
    final green = data.getUint32(masksOffset + 4, Endian.little);
    final blue = data.getUint32(masksOffset + 8, Endian.little);
    if (red == 0 ||
        green == 0 ||
        blue == 0 ||
        red & green != 0 ||
        red & blue != 0 ||
        green & blue != 0) {
      throw const FormatException('BMP bitfield color masks are invalid.');
    }
    redMask = _BmpChannelMask(red);
    greenMask = _BmpChannelMask(green);
    blueMask = _BmpChannelMask(blue);
  }

  final rgb = List<int>.filled(width * height * 3, 0);
  final topDown = signedHeight < 0;
  for (var sourceY = 0; sourceY < height; sourceY++) {
    final targetY = topDown ? sourceY : height - sourceY - 1;
    final sourceRow = pixelOffset + sourceY * rowStride;
    for (var x = 0; x < width; x++) {
      final offset = sourceRow + x * bytesPerPixel;
      final target = (targetY * width + x) * 3;
      if (compression == 0) {
        rgb[target] = data.getUint8(offset + 2);
        rgb[target + 1] = data.getUint8(offset + 1);
        rgb[target + 2] = data.getUint8(offset);
      } else {
        final pixel = bitsPerPixel == 32
            ? data.getUint32(offset, Endian.little)
            : data.getUint8(offset) |
                (data.getUint8(offset + 1) << 8) |
                (data.getUint8(offset + 2) << 16);
        rgb[target] = redMask!.decode(pixel);
        rgb[target + 1] = greenMask!.decode(pixel);
        rgb[target + 2] = blueMask!.decode(pixel);
      }
    }
  }
  return RgbImage(
    width: width,
    height: height,
    rgb: rgb,
    bmpBytes: bytes,
  );
}

class _BmpChannelMask {
  _BmpChannelMask(this.mask) {
    while (((mask >> shift) & 1) == 0) {
      shift++;
    }
    final shifted = mask >> shift;
    if ((shifted & (shifted + 1)) != 0) {
      throw const FormatException(
          'BMP bitfield channel mask is not contiguous.');
    }
    maximum = shifted;
  }

  final int mask;
  int shift = 0;
  late final int maximum;

  int decode(int pixel) =>
      ((((pixel & mask) >> shift) * 255 + maximum ~/ 2) ~/ maximum);
}
