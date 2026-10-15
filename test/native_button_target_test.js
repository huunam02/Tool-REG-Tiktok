// Run with: node --test test/native_button_target_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

for (const flow of ['login', 'signup']) {
  const source = readFileSync(
    new URL(`../lib/core/scripts/auto_${flow}_script.dart`, `file://${__filename}`), 'utf8',
  );
  const targetFunction = source.match(/const nativeButtonTarget = ([\s\S]*?\n  });/)[1];

  test(`${flow} tap varies slightly inside large, tiny and viewport-edge buttons`, () => {
    const viewport = { offsetLeft: 100, offsetTop: 200, width: 400, height: 600 };
    let rect;
    let randomValue;
    let hitPoint;
    let covered = false;
    const control = { getBoundingClientRect: () => rect, contains: () => false };
    const target = runInNewContext(`(${targetFunction})`, {
      window: { visualViewport: viewport },
      Math: Object.assign(Object.create(Math), { random: () => randomValue }),
      document: { elementFromPoint: (x, y) => {
        hitPoint = { x, y };
        const inside = x >= rect.left && x < rect.left + rect.width &&
          y >= rect.top && y < rect.top + rect.height;
        return covered || !inside ? {} : control;
      } },
    });
    for (rect of [
      { left: 150, top: 240, width: 100, height: 40 },
      { left: 150, top: 240, width: 2, height: 1 },
      { left: 51, top: 181, width: 100, height: 40 },
      { left: 449, top: 779, width: 100, height: 40 },
    ]) {
      const points = [];
      for (randomValue of [0, 0.25, 0.75, 1 - Number.EPSILON]) {
        const point = target(control);
        assert.ok(point);
        const x = point.x + viewport.offsetLeft;
        const y = point.y + viewport.offsetTop;
        assert.ok(x > rect.left && x < rect.left + rect.width);
        assert.ok(y > rect.top && y < rect.top + rect.height);
        assert.ok(point.x >= 0 && point.x < viewport.width);
        assert.ok(point.y >= 0 && point.y < viewport.height);
        assert.ok(Math.abs(x - (rect.left + rect.width / 2)) <= 6);
        assert.ok(Math.abs(y - (rect.top + rect.height / 2)) <= 6);
        assert.deepEqual(hitPoint, { x, y });
        points.push(`${x},${y}`);
      }
      assert.equal(new Set(points).size, 4);
    }
    covered = true;
    assert.equal(target(control), null);
  });

  test(`${flow} reuses a button region and remeasures after it moves or the viewport changes`, () => {
    let measurements = 0;
    let rect = {left: 100, top: 200, width: 100, height: 40};
    let covered = false;
    let current;
    const makeControl = () => ({
      getBoundingClientRect() { measurements++; return rect; },
      contains: () => false,
    });
    current = makeControl();
    const viewport = {offsetLeft: 0, offsetTop: 0, width: 400, height: 800};
    const window = {visualViewport: viewport, scrollX: 0, scrollY: 0, location: {pathname: '/login'}};
    const target = runInNewContext(`(${targetFunction})`, {
      window,
      Math: Object.assign(Object.create(Math), {random: () => 0.5}),
      document: {elementFromPoint: (x, y) => !covered &&
        x >= rect.left && x < rect.left + rect.width &&
        y >= rect.top && y < rect.top + rect.height ? current : null},
    });
    assert.ok(target(current, 'send-code'));
    assert.ok(target(current, 'send-code'));
    assert.equal(measurements, 1);
    // A fresh form can reuse the same safe region even with a new DOM node.
    current = makeControl();
    assert.ok(target(current, 'send-code'));
    assert.equal(measurements, 1);
    rect = {...rect, top: 400};
    assert.equal(target(current, 'send-code').y, 420);
    assert.equal(measurements, 2);
    window.scrollY = 20;
    assert.ok(target(current, 'send-code'));
    assert.equal(measurements, 2); // Fixed modal stayed in the same place.
    window.location.pathname = '/login/email';
    assert.ok(target(current, 'send-code'));
    assert.equal(measurements, 2);
    viewport.width = 390;
    assert.ok(target(current, 'send-code'));
    assert.equal(measurements, 3);
    covered = true;
    assert.equal(target(current, 'send-code'), null);
    assert.equal(window.__flutterNativeTapTargets.has('send-code'), false);
  });

  test(`${flow} remeasures a failed action without dropping other cached buttons`, () => {
    let measurements = 0;
    const control = {
      getBoundingClientRect() { measurements++; return {left: 100, top: 200, width: 100, height: 40}; },
      contains: () => false,
    };
    const window = {innerWidth: 400, innerHeight: 800};
    const target = runInNewContext(`(${targetFunction})`, {
      window, document: {elementFromPoint: () => control},
    });
    target(control, 'password');
    target(control, 'otp');
    window.__flutterNativeTapTargets.delete('password');
    target(control, 'password');
    target(control, 'otp');
    assert.equal(measurements, 3);
  });

  test(`${flow} keeps action caches separate and bounds their memory`, () => {
    let measurements = 0;
    const control = {
      getBoundingClientRect() { measurements++; return {left: 100, top: 200, width: 100, height: 40}; },
      contains: () => false,
    };
    const window = {innerWidth: 400, innerHeight: 800};
    const target = runInNewContext(`(${targetFunction})`, {
      window, document: {elementFromPoint: () => control},
    });
    assert.ok(target(control, 'password'));
    assert.ok(target(control, 'otp'));
    assert.ok(target(control, 'password'));
    assert.equal(measurements, 2);
    for (let i = 0; i < 30; i++) assert.ok(target(control, `step-${i}`));
    assert.equal(window.__flutterNativeTapTargets.size, 16);
  });
}
