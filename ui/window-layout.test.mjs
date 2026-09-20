import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { DEFAULT_VAULT_WINDOW_SIZE } from './window-layout.js';

const tauriConfig = JSON.parse(
  await readFile(new URL('../tauri.conf.json', import.meta.url), 'utf8'),
);

test('default vault size matches the configured minimum window size', () => {
  const mainWindow = tauriConfig.app.windows[0];

  assert.deepEqual(DEFAULT_VAULT_WINDOW_SIZE, {
    width: mainWindow.minWidth,
    height: mainWindow.minHeight,
  });
});
