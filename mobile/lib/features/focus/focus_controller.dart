import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'focus_models.dart';
import 'focus_repository.dart';

/// The server owns transitions; this clock only renders persisted timestamps.
class FocusController extends ChangeNotifier {
  FocusController(
    this.repository, {
    DateTime Function()? clock,
    bool tick = true,
  }) : clock = clock ?? DateTime.now {
    _subscription = repository.changes.listen((_) => unawaited(reload()));
    if (tick) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        final current = state;
        if (current != null &&
            focusLocalDate(now, current.timezone) != current.localDate) {
          if (!_rollingDay) {
            _rollingDay = true;
            unawaited(reload().whenComplete(() => _rollingDay = false));
          }
        }
        if (current?.activeSession != null) notifyListeners();
      });
    }
    unawaited(reload());
  }
  final FocusRepository repository;
  final DateTime Function() clock;
  FocusState? state;
  List<FocusReminder> reminders = [];
  String? error;
  bool loading = true, busy = false;
  bool _disposed = false, _rollingDay = false;
  int _generation = 0;
  Duration _offset = Duration.zero;
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  DateTime get now => clock().toUtc().add(_offset);
  FocusSession? get session => state?.activeSession;
  Future<bool> reload() async {
    final generation = ++_generation;
    try {
      final values = await Future.wait<Object>([
        repository.load(),
        repository.reminders(),
      ]);
      if (_disposed || generation != _generation) return false;
      state = values[0] as FocusState;
      reminders = values[1] as List<FocusReminder>;
      _offset = state!.serverNow.difference(clock().toUtc());
      error = null;
      loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (!_disposed && generation == _generation) {
        error = focusError(e);
        loading = false;
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> mutate(Future<void> Function() action) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      if (!await reload()) {
        if (!_disposed) error = 'Your change may have saved. Reload Focus to confirm before retrying.';
        return false;
      }
      return true;
    } catch (e) {
      final message = focusError(e);
      await reload();
      if (!_disposed) error = message;
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    repository.dispose();
    super.dispose();
  }
}

String focusError(Object error) {
  if (error is PostgrestException) {
    if (['PGRST202', 'PGRST205', '42P01', '42883'].contains(error.code)) {
      return "Focus isn't available yet. Your reminders still work. Try again after the app is updated.";
    }
    if (error.code == '40001') {
      return 'This session changed on another device. Review it and try again.';
    }
    if (error.code == '23505') {
      return 'You already have a focus session. Open it to continue.';
    }
    return error.message;
  }
  return 'Could not confirm the change. Check your connection and try again.';
}
