import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/bmp_image.dart';

import 'support/screen_test_support.dart';

void main() {
  group('decodeBmpImage', () {
    test('decodes bottom-up 24-bit rows and four-byte padding', () {
      final bytes = makeTestBmp(
        width: 2,
        height: 2,
        pixelAt: (x, y) => y == 0
            ? (x == 0 ? [255, 0, 0] : [0, 255, 0])
            : (x == 0 ? [0, 0, 255] : [255, 255, 255]),
      );

      final image = decodeBmpImage(bytes);

      expect(image.width, 2);
      expect(image.height, 2);
      expect(image.rgb, [
        255,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        255,
        255,
        255,
        255,
      ]);
      expect(image.bmpBytes, bytes);
    });

    test('decodes top-down 32-bit BI_RGB and ignores its unused alpha byte',
        () {
      final image = decodeBmpImage(makeTestBmp(
        width: 1,
        height: 2,
        bitsPerPixel: 32,
        topDown: true,
        pixelAt: (_, y) => y == 0 ? [12, 34, 56] : [78, 90, 123],
      ));

      expect(image.rgb, [12, 34, 56, 78, 90, 123]);
    });

    test('decodes 32-bit BI_BITFIELDS channels', () {
      final image = decodeBmpImage(makeTestBmp(
        width: 1,
        height: 1,
        bitsPerPixel: 32,
        compression: 3,
        topDown: true,
        pixelAt: (x, y) => [11, 122, 233],
      ));

      expect(image.rgb, [11, 122, 233]);
    });

    test('rejects unsupported compression, bit depth, and truncation', () {
      expect(
        () => decodeBmpImage(makeTestBmp(
          width: 1,
          height: 1,
          compression: 1,
        )),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('compression'),
        )),
      );
      expect(
        () => decodeBmpImage(makeTestBmp(
          width: 1,
          height: 1,
          bitsPerPixel: 16,
        )),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('bit depth'),
        )),
      );
      expect(
        () => decodeBmpImage(makeTestBmp(width: 1, height: 1).sublist(0, 56)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
