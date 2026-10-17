import 'dart:async';
import 'dart:math';

import 'nurture_data.dart';
import 'nurture_store.dart';

/// Persists passive statistics from manual viewing or automatic nurturing.
class ManualViewingSession {
  ManualViewingSession({
    required this.repository,
    required this.email,
    required this.plan,
    this.configurationId,
    this.onError,
  }) : id =
           '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  final NurtureRepository repository;
  final String email;
  final NurturePlan plan;
  final int? configurationId;
  final void Function()? onError;
  final String id;
  final _segments = <String, NurtureSnapshot?>{};
  Future<void> _writes = Future.value();
  int _revision = 0;
  bool _started = false;
  bool _finished = false;
  bool _errorReported = false;

  Future<void> _enqueue(Future<void> Function() operation) =>
      _writes = _writes.then((_) async {
        try {
          await operation();
        } catch (_) {
          if (!_errorReported) {
            _errorReported = true;
            onError?.call();
          }
        }
      });

  Future<void> start() {
    if (_started) return _writes;
    _started = true;
    return _enqueue(
      () => repository.beginSession(
        id: id,
        email: email,
        configurationId: configurationId,
        plan: plan,
        phase: 'running',
      ),
    );
  }

  String addSegment() {
    final segment = '${_segments.length + 1}';
    _segments[segment] = null;
    return segment;
  }

  Future<void> accept(dynamic value) {
    final snapshot = NurtureSnapshot.parse(value);
    if (_finished ||
        !_started ||
        snapshot == null ||
        snapshot.sessionId != id ||
        !_segments.containsKey(snapshot.segmentId)) {
      return _writes;
    }
    final old = _segments[snapshot.segmentId];
    if (old != null &&
        (snapshot.sequence <= old.sequence ||
            snapshot.totals.watchMilliseconds < old.totals.watchMilliseconds ||
            snapshot.totals.videos < old.totals.videos ||
            snapshot.totals.fullVideos < old.totals.fullVideos ||
            snapshot.totals.skippedVideos < old.totals.skippedVideos ||
            snapshot.totals.comments < old.totals.comments)) {
      return _writes;
    }
    _segments[snapshot.segmentId] = snapshot;
    final totals = _segments.values.fold(
      const NurtureTotals(),
      (sum, value) => sum + (value?.totals ?? const NurtureTotals()),
    );
    final revision = ++_revision;
    return _enqueue(() => repository.saveProgress(id, revision, totals));
  }

  Future<void> setForeground(bool active) {
    if (!_started || _finished) return _writes;
    return _enqueue(
      () => repository.setPhase(id, active ? 'running' : 'paused'),
    );
  }

  Future<void> finish({bool error = false, bool completed = false}) {
    if (_finished) return _writes;
    _finished = true;
    if (!_started) return _writes;
    return _enqueue(
      () => repository.setPhase(
        id,
        error
            ? 'error'
            : completed
            ? 'completed'
            : 'stopped',
      ),
    );
  }
}
