// Run with: node --test test/webview_timezone_script_test.js
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {execFileSync} = require('node:child_process');
const {test} = require('node:test');
const vm = require('node:vm');

process.env.TZ = 'Asia/Ho_Chi_Minh';
const source = readFileSync(`${__dirname}/../lib/core/webview_timezone.dart`, 'utf8');
const template = source.match(/webViewTimeZoneScriptTemplate = r'''([\s\S]*?)''';/)[1];
function context(zone) {
  const scope = vm.createContext({});
  vm.runInContext('globalThis.before = new Date("2026-07-15T12:34:56.789Z");', scope);
  vm.runInContext(template.replace('__PROXY_TIME_ZONE__', JSON.stringify(zone)), scope);
  return scope;
}
function equivalent(zone, expression) {
  const expected = execFileSync(process.execPath, ['-e', `console.log(JSON.stringify(${expression}))`],
    {env: {...process.env, TZ: zone}, encoding:'utf8'}).trim();
  const actual = vm.runInContext(`JSON.stringify(${expression})`, context(zone));
  // ICU's historical long display names can differ from V8 Date's names;
  // compare the complete date/time/offset, then test current zone names below.
  const normalize = text => text.replace(/ \([^()]*\)(?=")/g, '');
  assert.equal(normalize(actual), normalize(expected), zone);
}

test('Date local getters, strings and locale defaults follow proxy; UTC/timestamps stay intact', () => {
  for (const zone of ['America/New_York', 'Europe/Berlin', 'Asia/Kathmandu', 'Australia/Lord_Howe']) {
    equivalent(zone, `['2026-01-15T12:34:56.789Z','2026-07-15T12:34:56.789Z', '1970-01-01T00:00:00Z'].map(t => {
      const d=new Date(t); return [d.getTime(),d.getFullYear(),d.getMonth(),d.getDate(),d.getDay(),d.getHours(),
      d.getMinutes(),d.getSeconds(),d.getMilliseconds(),d.getTimezoneOffset(),d.getYear(),d.toString(),d.toDateString(),
      d.toTimeString(),d.toISOString(),d.toJSON(),d.toUTCString(),d.toLocaleString('en-US'),
      d.toLocaleDateString('en-US'),d.toLocaleTimeString('en-US'),d.toLocaleString('en-US',{timeZone:'UTC'})];})`);
  }
});

test('constructors and parsing respect local time, explicit offsets, UTC date-only, years 0-99 and overflow', () => {
  equivalent('America/New_York', `[
    new Date(2026,0,15,12,34,56,789),new Date(2026,6,15),new Date(26,0,1),new Date(2026,12,32),
    new Date('2026-07-15T12:00:00'),new Date('2026-07-15'),new Date('2026-07'),
    new Date('2026-07-15T12:00:00+07:00'),new Date('July 15, 2026 12:00:00'),
    new Date(0),new Date(null),new Date(new Date(0)),new Date(undefined),
    new Date(new String('2026-07-15T12:00:00')),new Date({valueOf(){return '2026-07-15T12:00:00';}}),
    new Date('Wed, 15 Jul 2026 12:00:00 EST')
  ].map(d=>[d.getTime(),d.toString()])`);
  equivalent('America/New_York', `['2026-07-15T12:00:00','2026-07-15','July 15, 2026 12:00:00','invalid'].map(t=>Date.parse(t))`);
});

test('DST gap advances and repeated wall time picks earlier instant', () => {
  equivalent('America/New_York', `[new Date(2026,2,8,2,30),new Date(2026,10,1,1,30),
    new Date('2026-03-08T02:30:00'),new Date('2026-11-01T01:30:00')].map(d=>[d.toISOString(),d.toString()])`);
  equivalent('Australia/Lord_Howe', `[new Date(2026,9,4,2,15),new Date(2026,3,5,1,45)].map(d=>[d.toISOString(),d.toString()])`);
});

test('local setters normalize values and cross DST without changing UTC setters', () => {
  equivalent('America/New_York', `['setFullYear','setMonth','setDate','setHours','setMinutes','setSeconds','setMilliseconds','setYear','setUTCHours','setTime'].map(method=>{
    const d=new Date('2026-03-07T12:30:00Z'); const value=d[method](method==='setFullYear'?2027:method==='setYear'?26:25);
    return [value,d.toISOString(),d.toString()];})`);
  equivalent('America/New_York', `(()=>{const d=new Date(2026,2,7,12);d.setDate(8);const invalid=new Date(NaN);
    invalid.setFullYear(2026);return [d.toISOString(),invalid.toISOString(),new Date(NaN).toString()];})()`);
});

test('Intl defaults use proxy; explicit zones and options validation keep native behavior', () => {
  const scope=context('America/New_York');
  assert.equal(vm.runInContext('Intl.DateTimeFormat().resolvedOptions().timeZone',scope),'America/New_York');
  assert.equal(vm.runInContext('new Intl.DateTimeFormat().resolvedOptions().timeZone',scope),'America/New_York');
  assert.equal(vm.runInContext('Intl.DateTimeFormat("en-US",{timeZone:"UTC"}).resolvedOptions().timeZone',scope),'UTC');
  assert.equal(vm.runInContext('Object.prototype.toString.call(new Date())',scope),'[object Date]');
  assert.equal(vm.runInContext('new Date() instanceof Date',scope),true);
  assert.match(vm.runInContext('new Date("2026-07-15T12:00:00Z").toString()',scope), /Eastern Daylight Time/);
  assert.equal(vm.runInContext('class Child extends Date {}; new Child(2026,0,1) instanceof Child',scope),true);
  assert.throws(()=>vm.runInContext('new Intl.DateTimeFormat("en-US",null)',scope),{name:'TypeError'});
  assert.throws(()=>vm.runInContext('new Date().toLocaleString("en-US",null)',scope),{name:'TypeError'});
  assert.throws(()=>vm.runInContext('Date.parse(Symbol())',scope),{name:'TypeError'});
  equivalent('America/New_York', `new Intl.DateTimeFormat('en-US',{hour:'numeric',timeZoneName:'short'}).format(new Date('2026-07-15T12:00:00Z'))`);
});

test('existing Date objects and reinjection work; changing proxy uses a fresh document', () => {
  const scope=context('America/New_York');
  assert.equal(vm.runInContext('before.getHours()',scope),8);
  vm.runInContext(template.replace('__PROXY_TIME_ZONE__','"America/New_York"'),scope);
  assert.equal(vm.runInContext('before.getHours()',scope),8);
  assert.equal(vm.runInContext('before.getHours()',context('Asia/Tokyo')),21);
  assert.equal(new Date('2026-07-15T12:34:56.789Z').getHours(),19);
});

test('unknown zones fail before replacing global Date', () => {
  const scope=vm.createContext({});
  vm.runInContext('globalThis.originalDate=Date',scope);
  assert.throws(()=>vm.runInContext(template.replace('__PROXY_TIME_ZONE__','"Invalid/Zone"'),scope),{name:'RangeError'});
  assert.equal(vm.runInContext('Date===originalDate',scope),true);
});

test('historical offsets use whole minutes and UTC offset is positive zero', () => {
  equivalent('America/New_York', `new Date('1880-01-01T00:00:00Z').getTimezoneOffset()`);
  const scope=context('UTC');
  assert.equal(vm.runInContext('Object.is(new Date(0).getTimezoneOffset(),0)',scope),true);
  assert.equal(vm.runInContext('Number.isNaN(new Date(NaN).getTimezoneOffset())',scope),true);
});
