import assert from 'node:assert/strict';
import test from 'node:test';

import {
  THEME_STORAGE_KEY,
  createThemeController,
  normalizeThemeMode,
  resolveThemeMode,
} from './theme.js';

class FakeElement {
  constructor(themeMode = null) {
    this.dataset = {};
    if (themeMode) this.dataset.themeMode = themeMode;
    this.attributes = new Map();
    this.listeners = new Map();
    this.title = '';
    this.control = null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, value);
  }

  getAttribute(name) {
    return this.attributes.get(name);
  }

  addEventListener(name, listener) {
    this.listeners.set(name, listener);
  }

  click() {
    this.listeners.get('click')?.();
  }

  closest(selector) {
    return selector === 'details' ? this.control : null;
  }
}

function fakeStorage(initialValue = null) {
  const values = new Map();
  if (initialValue !== null) values.set(THEME_STORAGE_KEY, initialValue);
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    value: () => values.get(THEME_STORAGE_KEY),
  };
}

function fakeMediaQuery(matches) {
  const listeners = [];
  return {
    matches,
    addEventListener: (name, listener) => {
      if (name === 'change') listeners.push(listener);
    },
    set(next) {
      this.matches = next;
      listeners.forEach((listener) => listener({ matches: next }));
    },
  };
}

function setup(initialValue, systemDark = false) {
  const root = new FakeElement();
  const trigger = new FakeElement();
  const control = {
    open: true,
    addEventListener() {},
  };
  trigger.control = control;
  const options = ['system', 'light', 'dark'].map((mode) => {
    const option = new FakeElement(mode);
    option.control = control;
    return option;
  });
  const mediaQuery = fakeMediaQuery(systemDark);
  const storage = fakeStorage(initialValue);
  const controller = createThemeController({ root, trigger, options, mediaQuery, storage });
  return { controller, root, trigger, control, options, mediaQuery, storage };
}

test('theme mode helpers default to System and resolve its current appearance', () => {
  assert.equal(normalizeThemeMode(null), 'system');
  assert.equal(normalizeThemeMode('unsupported'), 'system');
  assert.equal(resolveThemeMode('system', false), 'light');
  assert.equal(resolveThemeMode('system', true), 'dark');
});

test('existing explicit Light and Dark preferences remain explicit', () => {
  for (const mode of ['light', 'dark']) {
    const { controller, root, mediaQuery, storage } = setup(mode, mode !== 'dark');
    assert.equal(controller.mode, mode);
    assert.equal(root.dataset.theme, mode);
    assert.equal(storage.value(), mode);
    mediaQuery.set(mode === 'dark');
    assert.equal(root.dataset.theme, mode);
  }
});

test('System mode follows live appearance changes and persists the mode', () => {
  const { controller, root, trigger, options, mediaQuery, storage } = setup(null, false);
  assert.equal(controller.mode, 'system');
  assert.equal(root.dataset.themeMode, 'system');
  assert.equal(root.dataset.theme, 'light');
  assert.equal(storage.value(), 'system');
  assert.equal(trigger.getAttribute('aria-label'), 'Theme: System (currently light)');
  assert.equal(trigger.getAttribute('aria-expanded'), 'true');
  assert.deepEqual(options.map((option) => option.getAttribute('aria-checked')), ['true', 'false', 'false']);

  mediaQuery.set(true);
  assert.equal(root.dataset.theme, 'dark');
  assert.equal(trigger.getAttribute('aria-label'), 'Theme: System (currently dark)');

  mediaQuery.set(false);
  assert.equal(root.dataset.theme, 'light');
});

test('selecting an explicit mode closes the menu and ignores system changes', () => {
  const { controller, root, trigger, control, options, mediaQuery, storage } = setup('system', false);
  options[2].click();
  assert.equal(controller.mode, 'dark');
  assert.equal(root.dataset.theme, 'dark');
  assert.equal(storage.value(), 'dark');
  assert.equal(control.open, false);
  assert.equal(trigger.getAttribute('aria-expanded'), 'false');
  assert.deepEqual(options.map((option) => option.getAttribute('aria-checked')), ['false', 'false', 'true']);

  mediaQuery.set(true);
  mediaQuery.set(false);
  assert.equal(root.dataset.theme, 'dark');
});
