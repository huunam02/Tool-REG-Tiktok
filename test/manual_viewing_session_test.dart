import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/manual_viewing_session.dart';
import 'package:test_tiktok/core/nurture_data.dart';

import 'support/memory_nurture_store.dart';

void main() {
  late MemoryNurtureRepository repository;
  late ManualViewingSession session;
  setUp(() {
    repository = MemoryNurtureRepository(() async => []);
    session = ManualViewingSession(
      repository: repository,
      email: 'person@example.com',
      plan: const NurturePlan(NurtureMode.search, 'Du lịch'),
    );
  });
  Map<String, Object?> snapshot(
    String segment,
    int sequence,
    int milliseconds, {
    int videos = 0,
    int comments = 0,
  }) => {
    'session': session.id,
    'segment': segment,
    'sequence': sequence,
    'watch_ms': milliseconds,
    'videos': videos,
    'full_videos': videos,
    'skipped_videos': 0,
    'comments': comments,
  };

  test(
    'cumulative snapshots are idempotent and document segments sum once',
    () async {
      await session.start();
      final first = session.addSegment();
      await session.accept(snapshot(first, 1, 2000));
      await session.accept(snapshot(first, 1, 2000));
      await session.accept(snapshot(first, 2, 4000, videos: 1, comments: 1));
      await session.accept(snapshot(first, 1, 2000));
      await session.accept(snapshot(first, 3, 1000));
      final second = session.addSegment();
      await session.accept(snapshot(second, 1, 3000, videos: 1));
      expect(repository.totals[session.id]!.watchMilliseconds, 7000);
      expect(repository.totals[session.id]!.videos, 2);
      expect(repository.totals[session.id]!.comments, 1);
      expect(repository.revisions[session.id], 3);
    },
  );

  test(
    'unknown sessions, unregistered segments and malformed payloads are rejected',
    () async {
      await session.start();
      final segment = session.addSegment();
      await session.accept({...snapshot(segment, 1, 5000), 'session': 'other'});
      await session.accept(snapshot('unknown', 1, 5000));
      for (final invalid in [
        null,
        {},
        {...snapshot(segment, 1, 5000), 'watch_ms': double.nan},
        {...snapshot(segment, 1, 5000), 'videos': 2},
        {...snapshot(segment, 1, 5000), 'comments': -1},
      ]) {
        await session.accept(invalid);
      }
      expect(repository.totals, isEmpty);
    },
  );

  test('screen time replaces playback time and never decreases', () async {
    session = ManualViewingSession(
      repository: repository,
      email: 'person@example.com',
      plan: const NurturePlan(NurtureMode.feed),
      countsScreenTime: true,
    );
    await session.start();
    final segment = session.addSegment();
    await session.accept(snapshot(segment, 1, 5000, videos: 1, comments: 1));
    expect(repository.totals[session.id]!.watchMilliseconds, 0);
    await session.recordScreenTime(const Duration(seconds: 40));
    await session.recordScreenTime(const Duration(seconds: 30));
    await session.accept(snapshot(segment, 2, 9000, videos: 2, comments: 1));
    expect(repository.totals[session.id]!.watchMilliseconds, 40000);
    expect(repository.totals[session.id]!.videos, 2);
    expect(repository.totals[session.id]!.comments, 1);
    await session.finish(completed: true);
    await session.recordScreenTime(const Duration(minutes: 5));
    expect(repository.totals[session.id]!.watchMilliseconds, 40000);
  });

  test('manual viewing ignores screen time', () async {
    await session.start();
    await session.recordScreenTime(const Duration(seconds: 40));
    expect(repository.totals, isEmpty);
  });

  test(
    'pause and finish preserve mode and queued progress; late updates are ignored',
    () async {
      await session.start();
      final segment = session.addSegment();
      final update = session.accept(snapshot(segment, 1, 60000, videos: 1));
      await session.setForeground(false);
      expect(repository.phases[session.id], 'paused');
      await session.setForeground(true);
      await session.finish();
      await update;
      await session.accept(snapshot(segment, 2, 120000, videos: 2));
      await session.setForeground(true);
      expect(repository.phases[session.id], 'stopped');
      expect(repository.sessions[session.id]!.plan.keyword, 'Du lịch');
      expect(repository.totals[session.id]!.watchMilliseconds, 60000);
    },
  );
}
