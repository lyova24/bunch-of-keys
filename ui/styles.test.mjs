import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const styles = await readFile(new URL('./styles.css', import.meta.url), 'utf8');
const tauriConfig = JSON.parse(
  await readFile(new URL('../tauri.conf.json', import.meta.url), 'utf8'),
);

test('focused search input hides its placeholder', () => {
  assert.match(
    styles,
    /\.chrome-search input:focus::placeholder\s*\{[^}]*color:\s*transparent;/,
  );
});

test('rounded app surface owns the window shadow', () => {
  assert.equal(tauriConfig.app.windows[0].shadow, false);
  assert.match(styles, /--window-gutter:\s*18px;/);
  assert.match(
    styles,
    /#window-frame\s*\{[^}]*box-shadow:\s*0 2px 5px var\(--window-shadow-near\),\s*0 6px 14px var\(--window-shadow-far\);/s,
  );
});

test('resize handles track the visible window edge', () => {
  assert.match(
    styles,
    /\.resize-n\s*\{\s*top:\s*calc\(var\(--window-gutter\) - 4px\);\s*\}/,
  );
  assert.match(
    styles,
    /\.resize-nw\s*\{[^}]*top:\s*calc\(var\(--window-gutter\) - 7px\);[^}]*left:\s*calc\(var\(--window-gutter\) - 7px\);/s,
  );
});
