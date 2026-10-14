const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/scripts/auto_interest_script.dart', `file://${__filename}`), 'utf8');
const script = source.match(/autoSelectInterestScript = r'''([\s\S]*?)''';/)[1];

function setup(options = {}) {
  const timeouts = [], intervals = [], acknowledgements = [], choices = [];
  let mutation, locked = false, counterOverride = null;
  const element = text => ({
    innerText: text, textContent: text, isConnected: true, hidden: false,
    disabled: false, clicks: 0, attributes: {},
    getAttribute(name) { return this.attributes[name] ?? null; },
    getClientRects() { return this.hidden ? [] : [{}]; },
    classList: { contains() { return false; } },
    click() { this.clicks++; },
  });
  const heading = element(options.title ?? 'What would you like to watch on TikTok?');
  const button = element('Continue (0/3)'), login = element('Log in');
  const outsideContinue = element('Continue');
  const modal = element('');
  modal.querySelectorAll = selector => {
    if (selector.startsWith('h1')) return [heading];
    if (selector.startsWith('button,')) return [button, login];
    return choices;
  };
  const document = { hidden: false, documentElement: {},
    querySelectorAll: () => modal.isConnected ? [modal] : [],
  };
  const refresh = () => {
    const count = choices.filter(choice => choice.selected).length;
    button.innerText = button.textContent = `${options.continueLabel ?? 'Continue'} (${counterOverride ?? count}/3)`;
    button.disabled = locked || count !== 3;
  };
  const addChoice = label => {
    const choice = element(label);
    choice.selected = false;
    choice.classList.contains = value => value === 'selected' && choice.selected;
    choice.click = () => {
      choice.clicks++;
      const acknowledge = () => { choice.selected = !choice.selected; refresh(); mutation?.(); };
      if (options.asyncClicks) acknowledgements.push(acknowledge);
      else acknowledge();
    };
    choices.push(choice);
    return choice;
  };
  for (const name of ['Animals', 'Comedy', 'Travel', 'Food', 'Sports', 'Art'].slice(0, options.choiceCount ?? 6)) addChoice(name);
  for (let i = 0; i < (options.selected ?? 0); i++) choices[i].selected = true;
  refresh();
  const math = Object.create(Math);
  math.random = options.random ?? (() => 0.4);
  const window = {};
  const context = {
    window, document, location: { origin: options.origin ?? 'https://www.tiktok.com' },
    getComputedStyle: node => ({ display: node.hidden ? 'none' : 'block', visibility: 'visible', opacity: '1' }),
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} },
    Math: math, WeakMap, WeakSet,
    setTimeout: callback => { timeouts.push(callback); return timeouts.length; },
    setInterval: callback => { intervals.push(callback); return intervals.length; },
  };
  const tick = () => { const queued = timeouts.splice(0); queued.forEach(callback => callback()); };
  return { window, document, heading, button, login, outsideContinue, modal, choices, intervals,
    run: () => runInNewContext(script, context),
    check: () => window.__flutterInterestSelection?.check(),
    tick, settle: () => { for (let i = 0; i < 8; i++) tick(); },
    addChoice, mutate: () => mutation?.(),
    acknowledge: () => acknowledgements.shift()?.(),
    lockContinue(value) { locked = value; refresh(); },
    setCounter(value) { counterOverride = value; refresh(); },
  };
}

test('selects exactly three distinct random interests and continues once', () => {
  for (const random of [() => 0, () => 0.4, () => 0.999]) {
    const env = setup({ random });
    assert.equal(env.run(), true);
    env.settle();
    assert.equal(env.choices.filter(choice => choice.selected).length, 3);
    assert.equal(env.choices.reduce((sum, choice) => sum + choice.clicks, 0), 3);
    assert.ok(env.choices.every(choice => choice.clicks <= 1));
    assert.equal(env.button.clicks, 1);
    assert.equal(env.login.clicks, 0);
    assert.equal(env.outsideContinue.clicks, 0);
    env.run(); env.mutate(); env.settle(); env.check();
    assert.equal(env.button.clicks, 1);
    assert.equal(env.intervals.length, 1);
  }
});

test('keeps existing choices and fills only the missing selections', () => {
  for (const selected of [1, 2, 3]) {
    const env = setup({ selected });
    env.run(); env.settle();
    assert.equal(env.choices.filter(choice => choice.selected).length, 3);
    assert.ok(env.choices.slice(0, selected).every(choice => choice.clicks === 0));
    assert.equal(env.choices.reduce((sum, choice) => sum + choice.clicks, 0), 3 - selected);
    assert.equal(env.button.clicks, 1);
  }
});

test('waits for React to acknowledge each choice before selecting another', () => {
  const env = setup({ asyncClicks: true });
  env.run(); env.settle();
  env.check(); env.mutate(); env.settle();
  assert.equal(env.choices.reduce((sum, choice) => sum + choice.clicks, 0), 1);
  assert.equal(env.button.clicks, 0);
  for (let i = 0; i < 3; i++) { env.acknowledge(); env.settle(); }
  assert.equal(env.choices.filter(choice => choice.selected).length, 3);
  assert.equal(env.choices.reduce((sum, choice) => sum + choice.clicks, 0), 3);
  assert.equal(env.button.clicks, 1);
});

test('waits for both the 3/3 counter and enabled Continue button', () => {
  const env = setup();
  env.lockContinue(true); env.setCounter(0);
  env.run(); env.settle();
  assert.equal(env.choices.filter(choice => choice.selected).length, 3);
  assert.equal(env.button.clicks, 0);
  env.lockContinue(false); env.check();
  assert.equal(env.button.clicks, 0);
  env.setCounter(3); env.check();
  assert.equal(env.button.clicks, 1);
});

test('handles a modal inserted later after SPA navigation', () => {
  const env = setup();
  env.modal.isConnected = false;
  env.run(); env.settle();
  assert.equal(env.button.clicks, 0);
  env.modal.isConnected = true;
  env.mutate(); env.settle();
  assert.equal(env.button.clicks, 1);
});

test('waits while hidden and resumes selecting when the page is visible', () => {
  const env = setup();
  env.document.hidden = true;
  env.run(); env.settle();
  assert.ok(env.choices.every(choice => choice.clicks === 0));
  env.document.hidden = false;
  env.intervals[0](); env.settle();
  assert.equal(env.button.clicks, 1);
});

test('ignores other origins, unrelated dialogs and hidden interest dialogs', () => {
  for (const options of [ { origin: 'https://example.com' }, { title: 'Create username' }, { title: 'Log in' } ]) {
    const env = setup(options);
    env.run(); env.settle();
    assert.ok(env.choices.every(choice => choice.clicks === 0));
    assert.equal(env.button.clicks, 0);
  }
  const hidden = setup(); hidden.modal.hidden = true;
  hidden.run(); hidden.settle();
  assert.equal(hidden.button.clicks, 0);
});

test('waits for enough available choices and excludes hidden or disabled choices', () => {
  const env = setup({ choiceCount: 2 });
  env.run(); env.settle();
  assert.ok(env.choices.every(choice => choice.clicks === 0));
  const hidden = env.addChoice('Hidden'); hidden.hidden = true;
  const disabled = env.addChoice('Disabled'); disabled.disabled = true;
  const ariaDisabled = env.addChoice('Aria disabled'); ariaDisabled.attributes['aria-disabled'] = 'true';
  env.addChoice('Travel'); env.mutate(); env.settle();
  assert.equal(env.button.clicks, 1);
  assert.equal(hidden.clicks + disabled.clicks + ariaDisabled.clicks, 0);
});

test('does not change or submit more than three preselected interests', () => {
  const env = setup({ selected: 4 });
  env.run(); env.settle();
  assert.equal(env.button.clicks, 0);
  assert.ok(env.choices.every(choice => choice.clicks === 0));
});

test('recognizes the Vietnamese interest dialog and Continue label', () => {
  const env = setup({ title: 'Bạn muốn xem gì trên TikTok?', continueLabel: 'Tiếp tục' });
  env.run(); env.settle();
  assert.equal(env.button.clicks, 1);
});
