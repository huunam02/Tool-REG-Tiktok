import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Applies to document/frame JavaScript, not Android or worker globals.
String webViewTimeZoneScript(String timeZoneId) => webViewTimeZoneScriptTemplate
    .replaceAll('__PROXY_TIME_ZONE__', jsonEncode(timeZoneId));

UserScript webViewTimeZoneUserScript(String timeZoneId) => UserScript(
  source: webViewTimeZoneScript(timeZoneId),
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
);

const webViewTimeZoneScriptTemplate = r'''
(() => {
  'use strict';
  const zone = __PROXY_TIME_ZONE__;
  const marker = Symbol.for('test_tiktok.webview.timezone');
  if (globalThis[marker] === zone) return;
  const NativeDate = globalThis.Date;
  const NativeFormat = Intl.DateTimeFormat;
  // Validate before modifying any API. Use native ICU rules, including DST.
  const partsFormat = new NativeFormat('en-US-u-ca-gregory-nu-latn', {
    timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', era: 'short'
  });
  const nameFormat = new NativeFormat('en-US', {timeZone: zone, timeZoneName: 'long'});
  const proto = NativeDate.prototype;
  const native = Object.fromEntries(Object.getOwnPropertyNames(proto)
    .filter(key => typeof proto[key] === 'function').map(key => [key, proto[key]]));
  const stamp = date => native.getTime.call(date);
  const call = (name, date, args = []) => Reflect.apply(native[name], date, args);
  const define = (object, key, value) => Object.defineProperty(object, key, {
    value, configurable: true, writable: true, enumerable: false
  });
  const utcWall = (year, month, day, hour, minute, second, ms = 0) => {
    const date = new NativeDate(0);
    call('setUTCFullYear', date, [year, month, day]);
    call('setUTCHours', date, [hour, minute, second, ms]);
    return stamp(date);
  };
  const offset = time => {
    if (!Number.isFinite(time)) return NaN;
    const parts = Object.fromEntries(partsFormat.formatToParts(time).map(p => [p.type, p.value]));
    const year = parts.era === 'BC' ? 1 - Number(parts.year) : Number(parts.year);
    return utcWall(year, Number(parts.month) - 1, Number(parts.day),
      Number(parts.hour) % 24, Number(parts.minute), Number(parts.second)) - Math.floor(time / 1000) * 1000;
  };
  const localDate = date => {
    const time = stamp(date);
    return new NativeDate(time + offset(time));
  };
  const fromWall = wall => {
    if (!Number.isFinite(wall)) return NaN;
    // Sample both sides of a transition. For repeats choose the earlier
    // instant; for gaps advance by the gap, as native Date does (compatible).
    const offsets = new Set([-36, -12, 0, 12, 36].map(h => offset(wall + h * 3600000)));
    const candidates = Array.from(offsets, off => wall - off).filter(Number.isFinite);
    const exact = candidates.filter(t => t + offset(t) === wall);
    if (exact.length) return Math.min(...exact);
    const later = candidates.filter(t => t + offset(t) > wall);
    return later.length ? Math.min(...later) : NaN;
  };
  const withZone = options => {
    if (options === undefined) return {timeZone: zone};
    if (options === null || options.timeZone !== undefined) return options;
    const copy = Object.create(Object(options));
    Object.defineProperty(copy, 'timeZone', {value: zone});
    return copy;
  };
  const nativeParse = NativeDate.parse;
  const primitive = (value, hint) => {
    if (value === null || (typeof value !== 'object' && typeof value !== 'function')) return value;
    const exotic = value[Symbol.toPrimitive];
    if (exotic !== undefined && exotic !== null) {
      const result = Reflect.apply(exotic, value, [hint]);
      if (Object(result) !== result) return result;
      throw new TypeError('Cannot convert object to primitive value');
    }
    for (const key of hint === 'string' ? ['toString', 'valueOf'] : ['valueOf', 'toString']) {
      if (typeof value[key] !== 'function') continue;
      const result = Reflect.apply(value[key], value, []);
      if (Object(result) !== result) return result;
    }
    throw new TypeError('Cannot convert object to primitive value');
  };
  const parse = value => {
    const text = '' + primitive(value, 'string');
    // ISO date-only strings are UTC; explicit offsets must stay explicit.
    if (/^[+-]?\d{4,6}(?:-\d\d){0,2}$/.test(text) ||
        /(?:Z|[+-]\d\d:?\d\d)\s*$/i.test(text) || /\b(?:GMT|UTC|[ECMP][DS]T)\b/i.test(text)) {
      return nativeParse(text);
    }
    // Parse standard local ISO strings as wall time without host DST effects.
    if (/^[+-]?\d{4,6}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d+)?)?$/.test(text)) {
      return fromWall(nativeParse(text + 'Z'));
    }
    const date = new NativeDate(nativeParse(text));
    if (!Number.isFinite(stamp(date))) return NaN;
    return fromWall(utcWall(call('getFullYear', date), call('getMonth', date), call('getDate', date),
      call('getHours', date), call('getMinutes', date), call('getSeconds', date), call('getMilliseconds', date)));
  };
  // Real Date internal slots/timestamps are retained, so UTC/JSON/arithmetic,
  // instanceof, subclassing and dates returned by browser APIs keep working.
  const ProxyDate = new Proxy(NativeDate, {
    apply() { return new NativeDate().toString(); },
    construct(target, args, newTarget) {
      let actual = args;
      if (args.length > 1) actual = [fromWall(Reflect.apply(NativeDate.UTC, NativeDate, args))];
      else if (args.length === 1) {
        let value;
        try { value = stamp(args[0]); }
        catch (_) { value = primitive(args[0], 'default'); }
        actual = [typeof value === 'string' ? parse(value) : value];
      }
      return Reflect.construct(target, actual, newTarget);
    },
    get(target, key, receiver) { return key === 'parse' ? parse : Reflect.get(target, key, receiver); }
  });
  const fields = ['FullYear', 'Month', 'Date', 'Day', 'Hours', 'Minutes', 'Seconds', 'Milliseconds'];
  for (const field of fields) {
    define(proto, 'get' + field, function() { return call('getUTC' + field, localDate(this)); });
  }
  define(proto, 'getTimezoneOffset', function() {
    const minutes = -offset(stamp(this)) / 60000;
    return minutes === 0 ? 0 : Math.trunc(minutes);
  });
  define(proto, 'getYear', function() { return this.getFullYear() - 1900; });
  for (const field of fields.filter(field => field !== 'Day')) {
    define(proto, 'set' + field, function(...args) {
      const time = stamp(this);
      const local = field === 'FullYear' && Number.isNaN(time) ? new NativeDate(0) : localDate(this);
      call('setUTC' + field, local, args);
      return call('setTime', this, [fromWall(stamp(local))]);
    });
  }
  define(proto, 'setYear', function(year) {
    let value = +year;
    if (Number.isFinite(value) && Math.trunc(value) >= 0 && Math.trunc(value) <= 99) value = 1900 + Math.trunc(value);
    return this.setFullYear(value);
  });
  const pad = value => String(value).padStart(2, '0');
  const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  define(proto, 'toDateString', function() {
    if (!Number.isFinite(stamp(this))) return 'Invalid Date';
    const year = this.getFullYear();
    const yearText = (year < 0 ? '-' : '') + String(Math.abs(year)).padStart(4, '0');
    return weekdays[this.getDay()] + ' ' + months[this.getMonth()] + ' ' + pad(this.getDate()) + ' ' + yearText;
  });
  define(proto, 'toTimeString', function() {
    const time = stamp(this);
    if (!Number.isFinite(time)) return 'Invalid Date';
    const minutes = Math.trunc(offset(time) / 60000);
    const name = nameFormat.formatToParts(time).find(p => p.type === 'timeZoneName').value;
    return pad(this.getHours()) + ':' + pad(this.getMinutes()) + ':' + pad(this.getSeconds()) +
      ' GMT' + (minutes < 0 ? '-' : '+') + pad(Math.floor(Math.abs(minutes) / 60)) + pad(Math.abs(minutes) % 60) + ' (' + name + ')';
  });
  define(proto, 'toString', function() {
    return Number.isFinite(stamp(this)) ? this.toDateString() + ' ' + this.toTimeString() : 'Invalid Date';
  });
  for (const method of ['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString']) {
    define(proto, method, function(locales, options) { return call(method, this, [locales, withZone(options)]); });
  }
  const Format = new Proxy(NativeFormat, {
    construct(target, args, newTarget) {
      return Reflect.construct(target, [args[0], withZone(args[1])], newTarget);
    },
    apply(target, receiver, args) { return Reflect.apply(target, receiver, [args[0], withZone(args[1])]); }
  });
  define(proto, 'constructor', ProxyDate);
  define(globalThis, 'Date', ProxyDate);
  define(Intl, 'DateTimeFormat', Format);
  define(globalThis, marker, zone);
})();
''';
