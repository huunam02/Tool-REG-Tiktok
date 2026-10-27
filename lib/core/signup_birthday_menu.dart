import 'dart:math';
import 'dart:ui';

/// An open birthday list as Accessibility exposes it, in the signup design
/// space of the frame.
class SignupBirthdayMenu {
  const SignupBirthdayMenu({
    required this.field,
    required this.expanded,
    required this.bounds,
    required this.scrollable,
    required this.options,
  });

  final String field;
  final bool expanded, scrollable;
  final Rect bounds;
  final List<SignupBirthdayOption> options;
}

class SignupBirthdayOption {
  const SignupBirthdayOption(this.text, this.bounds);
  final String text;
  final Rect bounds;
}

/// Calibrated geometry of the desktop birthday lists (design px). A list
/// opens at its first entry (last year, January, 1) and every swipe from
/// 80% to 20% of its height scrolls the same distance, so the row to tap is
/// computed without reading the page.
class SignupBirthdayGeometry {
  const SignupBirthdayGeometry({
    required this.top,
    required this.bottom,
    required this.rowHeight,
    required this.scrollHeight,
    required this.swipeScroll,
    required this.columns,
    this.firstYearBeforeCurrent = 1,
  });

  /// [top]..[bottom] is the visible, tappable part of a list. Its scroller
  /// is [scrollHeight] tall, which is where a short list stops scrolling.
  final double top, bottom, rowHeight, scrollHeight, swipeScroll;
  final Map<String, (double, double)> columns;
  final int firstYearBeforeCurrent;

  static SignupBirthdayGeometry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double value(String key) => (raw[key] as num).toDouble();
    final columns = raw['columns'] as Map;
    return SignupBirthdayGeometry(
      top: value('top'),
      bottom: value('bottom'),
      rowHeight: value('rowHeight'),
      scrollHeight: value('scrollHeight'),
      swipeScroll: value('swipeScroll'),
      columns: {
        for (final MapEntry(:key, :value) in columns.entries)
          key as String: (
            ((value as List)[0] as num).toDouble(),
            (value[1] as num).toDouble(),
          ),
      },
      firstYearBeforeCurrent:
          (raw['firstYearBeforeCurrent'] as num?)?.toInt() ?? 1,
    );
  }

  Rect? list(String field) => switch (columns[field]) {
    (final left, final right) => Rect.fromLTRB(left, top, right, bottom),
    null => null,
  };

  /// Row of [target] counted from the top of the freshly opened list.
  int index(String field, int target, DateTime now) =>
      field == 'Year' ? now.year - firstYearBeforeCurrent - target : target - 1;

  /// Lengths the list can have; null when it never ends before the target.
  static List<int?> _lengths(String field) => switch (field) {
    'Month' => const [12],
    'Day' => const [28, 29, 30, 31],
    _ => const [null],
  };

  /// Swipes that bring row [index] into view and the y to tap it at. The
  /// tap lies inside the row for every possible list length (a day's list
  /// may end at 28 to 31); null when no such point exists.
  ({int swipes, double tapY})? plan(String field, int index) {
    if (index < 0 || list(field) == null) return null;
    final needed = (index + 1) * rowHeight - (bottom - top);
    final swipes = needed <= 0 ? 0 : (needed / swipeScroll).ceil();
    double low = top, high = bottom;
    var placed = false;
    for (final length in _lengths(field)) {
      if (length != null && index >= length) continue;
      final end = length == null
          ? double.infinity
          : max(0.0, length * rowHeight - scrollHeight);
      final rowTop = top + index * rowHeight - min(swipes * swipeScroll, end);
      low = max(low, rowTop);
      high = min(high, rowTop + rowHeight);
      placed = true;
    }
    // A row clipped to a sliver (December at the end of its list) is still
    // tappable; the selection is confirmed afterwards.
    if (!placed || high - low < 3) return null;
    return (swipes: swipes, tapY: (low + high) / 2);
  }
}
