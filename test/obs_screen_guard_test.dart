import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/services/bmp_image.dart';
import 'package:afterimage/services/obs_screen_guard.dart';

import 'support/obs_test_support.dart';
import 'support/screen_test_support.dart';

void main() {
  group('screenCheckScore', () {
    test('crops the 192x108 menu row and compares all RGB channels', () {
      final reference = _solidImage(100, 100, 100);
      final movedHighlight = _imageWithMenuRow((x, y) => [190, 100, 100]);

      expect(
        screenCheckScore(
          ScreenCheck.replayMenuViewHighlighted,
          movedHighlight,
          reference,
        ),
        30,
      );
      expect(
        screenCheckScore(
          ScreenCheck.replayList,
          movedHighlight,
          reference,
        ),
        0,
      );
    });

    test('the screen guard uses the inclusive RGB threshold of 25', () async {
      final referenceBytes = makeTestBmp(
        width: 192,
        height: 108,
        pixelAt: (x, y) => const [100, 100, 100],
      );
      final liveBytes = makeTestBmp(
        width: 192,
        height: 108,
        pixelAt: _menuRowPixel((x, y) => const [175, 100, 100]),
      );
      final source = _FakeThumbnailSource(decodeBmpImage(liveBytes));
      final references = _MemoryScreenReferenceStore()
        ..values[ScreenCheck.replayMenuViewHighlighted] = referenceBytes;

      final result = await ObsScreenGuard(
        source: source,
        references: references,
      ).check(ScreenCheck.replayMenuViewHighlighted);

      expect(result.score, 25);
      expect(result.matched, isTrue);
      expect(source.captureCalls, 1);
    });
  });

  group('FileScreenReferenceStore', () {
    test('round-trips the raw BMP reference under its check name', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final store = FileScreenReferenceStore(directoryPath: directory.path);
      final bytes = makeTestBmp(width: 1, height: 1);

      await store.writeBmp(ScreenCheck.replayList, bytes);

      expect(await store.readBmp(ScreenCheck.replayList), bytes);
      expect(await store.fileFor(ScreenCheck.replayList).exists(), isTrue);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('.tmp-'))
            .toList(),
        isEmpty,
      );
      await expectLater(
        store.writeBmp(ScreenCheck.replayList, [0, 1, 2]),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing and undecodable references never match', () async {
      final references = _MemoryScreenReferenceStore()
        ..values[ScreenCheck.replayList] = [1, 2, 3];
      final source = _FakeThumbnailSource(_solidImage(0, 0, 0));
      final guard = ObsScreenGuard(source: source, references: references);

      final missing = await guard.check(ScreenCheck.replayMenuViewHighlighted);
      final invalid = await guard.check(ScreenCheck.replayList);

      expect(missing.matched, isFalse);
      expect(missing.error, contains('not been taught'));
      expect(invalid.matched, isFalse);
      expect(invalid.error, isNotNull);
      expect(source.captureCalls, 0);
    });
  });
}

RgbImage _solidImage(int red, int green, int blue) => RgbImage(
      width: 192,
      height: 108,
      rgb: List<int>.generate(
        192 * 108 * 3,
        (index) => switch (index % 3) {
          0 => red,
          1 => green,
          _ => blue,
        },
      ),
    );

RgbImage _imageWithMenuRow(List<int> Function(int x, int y) pixel) {
  final reference = _solidImage(100, 100, 100);
  final rgb = List<int>.of(reference.rgb);
  for (var y = 43; y < 49; y++) {
    for (var x = 48; x < 141; x++) {
      final value = pixel(x, y);
      final offset = (y * 192 + x) * 3;
      rgb.setRange(offset, offset + 3, value);
    }
  }
  return RgbImage(width: 192, height: 108, rgb: rgb);
}

TestRgbPixel _menuRowPixel(List<int> Function(int x, int y) highlight) =>
    (x, y) => x >= 48 && x < 141 && y >= 43 && y < 49
        ? highlight(x, y)
        : const [100, 100, 100];

class _FakeThumbnailSource implements ObsThumbnailSource {
  _FakeThumbnailSource(this.image);

  final RgbImage image;
  int captureCalls = 0;

  @override
  Future<RgbImage> captureThumbnail() async {
    captureCalls++;
    return image;
  }
}

class _MemoryScreenReferenceStore implements ScreenReferenceStore {
  final Map<ScreenCheck, List<int>> values = {};

  @override
  Future<List<int>?> readBmp(ScreenCheck check) async => values[check];

  @override
  Future<void> writeBmp(ScreenCheck check, List<int> bytes) async {
    values[check] = bytes;
  }
}
