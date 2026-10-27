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
    this.likes = 0,
  });
  final int watchMilliseconds;
  final int videos;
  final int fullVideos;
  final int skippedVideos;
  final int comments;
  final int likes;

  double get minutes => watchMilliseconds / 60000;

  NurtureTotals withWatchMilliseconds(int value) => NurtureTotals(
    watchMilliseconds: value,
    videos: videos,
    fullVideos: fullVideos,
    skippedVideos: skippedVideos,
    comments: comments,
    likes: likes,
  );

  NurtureTotals operator +(NurtureTotals other) => NurtureTotals(
    watchMilliseconds: watchMilliseconds + other.watchMilliseconds,
    videos: videos + other.videos,
    fullVideos: fullVideos + other.fullVideos,
    skippedVideos: skippedVideos + other.skippedVideos,
    comments: comments + other.comments,
    likes: likes + other.likes,
  );

  static NurtureTotals fromMap(Map<String, Object?> row) => NurtureTotals(
    watchMilliseconds: (row['watch_ms'] as num?)?.toInt() ?? 0,
    videos: (row['videos'] as num?)?.toInt() ?? 0,
    fullVideos: (row['full_videos'] as num?)?.toInt() ?? 0,
    skippedVideos: (row['skipped_videos'] as num?)?.toInt() ?? 0,
    comments: (row['comments'] as num?)?.toInt() ?? 0,
    likes: (row['likes'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toMap() => {
    'watch_ms': watchMilliseconds,
    'videos': videos,
    'full_videos': fullVideos,
    'skipped_videos': skippedVideos,
    'comments': comments,
    'likes': likes,
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
    // The page's viewing script reports no likes; only the runner does.
    for (final name in [...names, if (value.containsKey('likes')) 'likes']) {
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
      'likes': value['likes'],
    });
    if (totals.videos != totals.fullVideos + totals.skippedVideos ||
        totals.watchMilliseconds > const Duration(hours: 24).inMilliseconds ||
        totals.videos > 100000 ||
        totals.comments > 100000 ||
        totals.likes > 100000) {
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
    this.nurtureCount = 0,
    this.lastNurturedAt,
    this.registeredAt,
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

  /// Nurture sessions that watched at least one video.
  final int nurtureCount;
  final DateTime? lastNurturedAt;

  /// When the account was registered; null for accounts registered before
  /// this was recorded.
  final DateTime? registeredAt;
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

/// Nurture behaviour of one configuration. Rates are whole percentages.
class NurtureSettings {
  const NurtureSettings({
    this.likePercent = 30,
    this.commentPercent = 20,
    this.longWatchPercent = 50,
    this.minMinutes = 2,
    this.maxMinutes = 3,
  });

  static const defaults = NurtureSettings();

  /// Longest nurture session that can be configured.
  static const maxSessionMinutes = 120;

  /// Share of posts that are liked; a liked post is watched in full.
  final int likePercent;

  /// Share of posts that get a comment; a commented post is watched in full.
  final int commentPercent;

  /// Share of the remaining posts watched for a long random time instead of
  /// being swiped after a few seconds.
  final int longWatchPercent;

  /// Each session lasts a random time between these bounds.
  final int minMinutes;
  final int maxMinutes;

  double get likeRate => likePercent / 100;
  double get commentRate => commentPercent / 100;
  double get longWatchRate => longWatchPercent / 100;
  Duration get minDuration => Duration(minutes: minMinutes);
  Duration get maxDuration => Duration(minutes: maxMinutes);

  /// The first problem with these values, or null when they are valid.
  String? get error {
    for (final (name, value) in [
      ('Tỷ lệ thả tim', likePercent),
      ('Tỷ lệ bình luận', commentPercent),
      ('Tỷ lệ xem lâu', longWatchPercent),
    ]) {
      if (value < 0 || value > 100) return '$name phải từ 0 đến 100%.';
    }
    if (minMinutes < 1 || maxMinutes > maxSessionMinutes) {
      return 'Thời gian nuôi phải từ 1 đến $maxSessionMinutes phút.';
    }
    if (minMinutes > maxMinutes) {
      return 'Thời gian nuôi tối thiểu không được lớn hơn tối đa.';
    }
    return null;
  }

  String get summary =>
      'Tim $likePercent% · Bình luận $commentPercent% · '
      'Xem lâu $longWatchPercent% · $minMinutes–$maxMinutes phút';

  /// Read from a configurations row; invalid values fall back to the
  /// defaults.
  static NurtureSettings fromMap(Map<String, Object?> row) {
    int read(String name, int fallback) =>
        (row[name] as num?)?.toInt() ?? fallback;
    final settings = NurtureSettings(
      likePercent: read('nurture_like_percent', defaults.likePercent),
      commentPercent: read('nurture_comment_percent', defaults.commentPercent),
      longWatchPercent: read(
        'nurture_long_watch_percent',
        defaults.longWatchPercent,
      ),
      minMinutes: read('nurture_min_minutes', defaults.minMinutes),
      maxMinutes: read('nurture_max_minutes', defaults.maxMinutes),
    );
    return settings.error == null ? settings : defaults;
  }

  /// Columns of the configurations table.
  Map<String, Object?> toMap() => {
    'nurture_like_percent': likePercent,
    'nurture_comment_percent': commentPercent,
    'nurture_long_watch_percent': longWatchPercent,
    'nurture_min_minutes': minMinutes,
    'nurture_max_minutes': maxMinutes,
  };

  @override
  bool operator ==(Object other) =>
      other is NurtureSettings &&
      other.likePercent == likePercent &&
      other.commentPercent == commentPercent &&
      other.longWatchPercent == longWatchPercent &&
      other.minMinutes == minMinutes &&
      other.maxMinutes == maxMinutes;

  @override
  int get hashCode => Object.hash(
    likePercent,
    commentPercent,
    longWatchPercent,
    minMinutes,
    maxMinutes,
  );
}
