import 'dart:convert';
import 'dart:ui';

/// Read-only geometry for HTML comboboxes whose options Chromium omits from
/// Accessibility. All coordinates use the signup design space (400 x 800).
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

  static SignupBirthdayMenu? fromResult(dynamic result) {
    if (result is String) result = jsonDecode(result);
    if (result is! Map || result['field'] == null) return null;
    if (!const ['Year', 'Month', 'Day'].contains(result['field'])) {
      throw StateError('Dropdown không phải trường ngày sinh.');
    }
    final width = (result['width'] as num).toDouble();
    final height = (result['height'] as num).toDouble();
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        (width / height - 0.5).abs() > 0.003) {
      throw StateError('Kích thước dropdown ngày sinh không khớp WebView.');
    }
    Rect rect(dynamic raw) {
      final values = (raw as List).cast<num>();
      return Rect.fromLTRB(
        values[0] * 400 / width,
        values[1] * 800 / height,
        values[2] * 400 / width,
        values[3] * 800 / height,
      );
    }

    return SignupBirthdayMenu(
      field: result['field'] as String,
      expanded: result['expanded'] == true,
      bounds: rect(result['bounds']),
      scrollable: result['scrollable'] == true,
      options: [
        for (final option in result['options'] as List)
          SignupBirthdayOption(
            option['text'] as String,
            rect(option['bounds']),
          ),
      ],
    );
  }
}

class SignupBirthdayOption {
  const SignupBirthdayOption(this.text, this.bounds);
  final String text;
  final Rect bounds;
}

String buildReadSignupBirthdayMenuScript(String field) {
  if (!const ['Year', 'Month', 'Day'].contains(field)) {
    throw ArgumentError.value(field, 'field');
  }
  return '''
(() => {
  const name = ${jsonEncode(field)};
  const field = Array.from(document.querySelectorAll('[role="combobox"]')).find(
    e => (e.getAttribute('aria-label') || '').startsWith(name + '.') &&
      e.getBoundingClientRect().width > 0);
  if (!field) return null;
  const list = field.querySelector('[role="listbox"]');
  const box = e => {
    const r = e.getBoundingClientRect();
    return [r.left, r.top, r.right, r.bottom];
  };
  const expanded = field.getAttribute('aria-expanded') === 'true' &&
    list && list.getBoundingClientRect().height > 0;
  const result = {field: name, width: innerWidth, height: innerHeight,
    expanded: !!expanded, bounds: [0,0,0,0], scrollable: false, options: []};
  if (!expanded) return result;
  // Clip against scroll containers, the modal and the viewport; offscreen
  // option rectangles still have a nonzero size in this TikTok dropdown.
  const clip = box(list);
  clip[0] = Math.max(0, clip[0]); clip[1] = Math.max(0, clip[1]);
  clip[2] = Math.min(innerWidth, clip[2]); clip[3] = Math.min(innerHeight, clip[3]);
  for (let p = list.parentElement; p; p = p.parentElement) {
    const style = getComputedStyle(p), r = box(p);
    if (/auto|scroll|hidden|clip/.test(style.overflowX)) {
      clip[0] = Math.max(clip[0], r[0]); clip[2] = Math.min(clip[2], r[2]);
    }
    if (/auto|scroll|hidden|clip/.test(style.overflowY)) {
      clip[1] = Math.max(clip[1], r[1]); clip[3] = Math.min(clip[3], r[3]);
    }
  }
  result.bounds = clip;
  result.scrollable = list.scrollHeight > list.clientHeight + 1;
  result.options = Array.from(list.querySelectorAll('[role="option"]')).flatMap(e => {
    const r = box(e);
    const visible = [Math.max(r[0],clip[0]), Math.max(r[1],clip[1]),
      Math.min(r[2],clip[2]), Math.min(r[3],clip[3])];
    if (visible[2]-visible[0] < 4 || visible[3]-visible[1] < 8 ||
        (r[1]+r[3])/2 <= clip[1]+2 || (r[1]+r[3])/2 >= clip[3]-2) return [];
    const hit = document.elementFromPoint((visible[0]+visible[2])/2,
      (visible[1]+visible[3])/2);
    if (!hit || !(e === hit || e.contains(hit))) return [];
    return [{text: e.textContent.trim(), bounds: visible}];
  });
  return result;
})()
''';
}
