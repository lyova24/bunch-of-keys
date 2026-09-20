import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const styles = await readFile(new URL('./styles.css', import.meta.url), 'utf8');
const tauriConfig = JSON.parse(
  await readFile(new URL('../tauri.conf.json', import.meta.url), 'utf8'),
);
const markup = await readFile(new URL('./index.html', import.meta.url), 'utf8');
const app = await readFile(new URL('./app.js', import.meta.url), 'utf8');

test('field type selector contains only distinct field behaviors', () => {
  assert.match(app, /\['text', 'secret', 'url'\]\.forEach/);
  assert.doesNotMatch(app, /\['text', 'secret', 'url', 'note'\]/);
});

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

test('compact header keeps accessible window controls visible', () => {
  assert.match(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.window-controls\s*\{[^}]*display:\s*flex;[^}]*grid-column:\s*3;/,
  );
  assert.doesNotMatch(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.window-controls\s*\{[^}]*display:\s*none;/,
  );
  assert.match(
    markup,
    /<button id="lock-button"[^>]*aria-label="Lock vault"/,
  );
});

test('wide header places search between the vault identity and actions', () => {
  assert.match(
    styles,
    /\.window-chrome\s*\{[^}]*grid-template-columns:\s*fit-content\(220px\) minmax\(180px, 1fr\) auto auto;/s,
  );
  assert.match(
    styles,
    /\.chrome-search\s*\{[^}]*justify-self:\s*center;[^}]*width:\s*min\(100%, 360px\);/s,
  );
});
