import 'dart:math';

enum NurtureMode {
  feed('Nuôi news feed'),
  search('Nuôi search keyword');

  const NurtureMode(this.label);
  final String label;
}

class NurturePlan {
  const NurturePlan(this.mode, [this.keyword = '']);
  final NurtureMode mode;
  final String keyword;
  String get initialUrl => mode == NurtureMode.search
      ? Uri.https('www.tiktok.com', '/search', {'q': keyword}).toString()
      : 'https://www.tiktok.com/';

  static NurturePlan choose(List<String> keywords, {Random? random}) {
    final options = keywords
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toSet()
        .toList();
    final generator = random ?? Random();
    if (options.isEmpty || generator.nextBool()) {
      return const NurturePlan(NurtureMode.feed);
    }
    return NurturePlan(
      NurtureMode.search,
      options[generator.nextInt(options.length)],
    );
  }
}

class NurtureTotals {
  const NurtureTotals({
    this.watchMilliseconds = 0,
    this.videos = 0,
    this.fullVideos = 0,
    this.skippedVideos = 0,
    this.comments = 0,
  });
  final int watchMilliseconds;
  final int videos;
  final int fullVideos;
  final int skippedVideos;
  final int comments;

  double get minutes => watchMilliseconds / 60000;

  NurtureTotals operator +(NurtureTotals other) => NurtureTotals(
    watchMilliseconds: watchMilliseconds + other.watchMilliseconds,
    videos: videos + other.videos,
    fullVideos: fullVideos + other.fullVideos,
    skippedVideos: skippedVideos + other.skippedVideos,
    comments: comments + other.comments,
  );

  static NurtureTotals fromMap(Map<String, Object?> row) => NurtureTotals(
    watchMilliseconds: (row['watch_ms'] as num?)?.toInt() ?? 0,
    videos: (row['videos'] as num?)?.toInt() ?? 0,
    fullVideos: (row['full_videos'] as num?)?.toInt() ?? 0,
    skippedVideos: (row['skipped_videos'] as num?)?.toInt() ?? 0,
    comments: (row['comments'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toMap() => {
    'watch_ms': watchMilliseconds,
    'videos': videos,
    'full_videos': fullVideos,
    'skipped_videos': skippedVideos,
    'comments': comments,
  };
}

class NurtureSnapshot {
  const NurtureSnapshot(
    this.sessionId,
    this.segmentId,
    this.sequence,
    this.totals,
  );
  final String sessionId;
  final String segmentId;
  final int sequence;
  final NurtureTotals totals;

  static NurtureSnapshot? parse(dynamic value) {
    if (value is! Map ||
        value['session'] is! String ||
        value['segment'] is! String) {
      return null;
    }
    const names = [
      'sequence',
      'watch_ms',
      'videos',
      'full_videos',
      'skipped_videos',
      'comments',
    ];
    for (final name in names) {
      final number = value[name];
      if (number is! num ||
          !number.isFinite ||
          number < 0 ||
          number != number.roundToDouble()) {
        return null;
      }
    }
    final totals = NurtureTotals.fromMap({
      for (final name in names) name: value[name],
    });
    if (totals.videos != totals.fullVideos + totals.skippedVideos ||
        totals.watchMilliseconds > const Duration(hours: 24).inMilliseconds ||
        totals.videos > 100000 ||
        totals.comments > 100000) {
      return null;
    }
    return NurtureSnapshot(
      value['session'] as String,
      value['segment'] as String,
      (value['sequence'] as num).toInt(),
      totals,
    );
  }
}

class NurtureAccount {
  const NurtureAccount({
    required this.key,
    required this.email,
    this.configurationId,
    this.configurationName = '',
    this.totals = const NurtureTotals(),
    this.phase = 'idle',
    this.mode = NurtureMode.feed,
    this.keyword = '',
    this.updatedAt,
  });
  final String key;
  final String email;
  final int? configurationId;
  final String configurationName;
  final NurtureTotals totals;
  final String phase;
  final NurtureMode mode;
  final String keyword;
  final DateTime? updatedAt;
  String get phaseLabel => switch (phase) {
    'waiting' => 'Đang chờ',
    'running' => 'Đang xem',
    'paused' => 'Tạm dừng',
    'completed' => 'Đã hoàn tất',
    'error' => 'Cần kiểm tra',
    'stopped' => 'Đã dừng',
    _ => 'Chưa nuôi',
  };
}

String nurtureAccountKey(String email) => email.trim().toLowerCase();
