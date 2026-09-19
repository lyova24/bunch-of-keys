import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const styles = await readFile(new URL('./styles.css', import.meta.url), 'utf8');

test('focused search input hides its placeholder', () => {
  assert.match(
    styles,
    /\.chrome-search input:focus::placeholder\s*\{[^}]*color:\s*transparent;/,
  );
});
