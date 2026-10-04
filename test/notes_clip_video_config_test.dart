import 'package:afterimage/presentation/widgets/notes_clip_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  test('clip video renders in software and draws no controls of its own', () {
    // The GL texture path rendered solid blue on an RX 9060 XT under Wayland,
    // and media_kit's default controls stacked on top of the page's own bar.
    expect(notesClipVideoConfiguration.enableHardwareAcceleration, isFalse);
    expect(notesClipVideoControls, same(NoVideoControls));
  });
}
