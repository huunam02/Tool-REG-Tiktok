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
        return covered ? {} : control;
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
}
