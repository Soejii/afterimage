import '../domain/recorder_contracts.dart';

class SystemReplayClock implements ReplayClock {
  SystemReplayClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}
