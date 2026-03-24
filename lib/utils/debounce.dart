import 'dart:async';

/// Coalesces rapid callbacks (e.g. search typing) to reduce rebuild/filter work.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 280)});

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
