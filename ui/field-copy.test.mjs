import assert from 'node:assert/strict';
import test from 'node:test';

import { copyFieldValue } from './field-copy.js';

function copyTarget() {
  const classes = new Set();
  return {
    classes,
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
    },
  };
}

test('successful activation copies and briefly marks the value', async () => {
  const target = copyTarget();
  let copied = false;
  let announced = false;
  let reset;

  const result = await copyFieldValue({
    target,
    copy: async () => { copied = true; },
    onSuccess: () => { announced = true; },
    onError: assert.fail,
    schedule: (callback) => { reset = callback; return 1; },
  });

  assert.equal(result, true);
  assert.equal(copied, true);
  assert.equal(announced, true);
  assert.equal(target.classes.has('copied'), true);
  reset();
  assert.equal(target.classes.has('copied'), false);
});

test('failed copy reports the error without showing success feedback', async () => {
  const target = copyTarget();
  const expected = new Error('clipboard unavailable');
  let reported;

  const result = await copyFieldValue({
    target,
    copy: async () => { throw expected; },
    onSuccess: assert.fail,
    onError: (error) => { reported = error; },
    schedule: assert.fail,
  });

  assert.equal(result, false);
  assert.equal(reported, expected);
  assert.equal(target.classes.has('copied'), false);
});
