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
  assert.match(app, /\['text', 'secret', 'url', 'ssh'\]\.forEach/);
  assert.doesNotMatch(app, /\['text', 'secret', 'url', 'note'\]/);
});

test('SSH fields use dedicated connection inputs and reusable named keys', () => {
  assert.match(app, /createSshFieldInputs\(field\.ssh, row\)/);
  assert.match(app, /user:\s*row\._inputs\.ssh\.user\.value\.trim\(\)/);
  assert.match(app, /address:\s*row\._inputs\.ssh\.address\.value\.trim\(\)/);
  assert.match(app, /key_id:\s*row\._inputs\.ssh\.key\.value/);
  assert.match(markup, /<dialog id="ssh-key-dialog">/);
  assert.match(markup, /<textarea name="privateKey"[^>]*autocomplete="off"[^>]*spellcheck="false"/);
  assert.match(styles, /\.ssh-field-inputs\s*\{[^}]*grid-template-columns:/s);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*\.ssh-field-inputs\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\);/);
});

test('valid SSH fields expose a safe terminal action and masked passphrase prompt', () => {
  assert.match(app, /iconButton\('terminal', 'Connect via SSH'/);
  assert.match(app, /invoke\('connect_ssh', \{ entryId: entry\.id, fieldId: field\.id, passphrase \}\)/);
  assert.match(markup, /<dialog id="ssh-passphrase-dialog">/);
  assert.match(markup, /<input name="passphrase" type="password" autocomplete="off" required>/);
  assert.match(app, /form\.elements\.passphrase\.value = '';/);
});

test('vault tree supports mouse disclosure and roving keyboard field actions', () => {
  assert.match(markup, /id="workspace-tree"[^>]*role="tree"/);
  assert.match(app, /header\.addEventListener\('click',[\s\S]*?toggle\(\);/);
  assert.match(app, /event\.key === 'ArrowUp' \|\| event\.key === 'ArrowDown'/);
  assert.match(app, /event\.key === 'ArrowRight' && item\._expandTreeItem/);
  assert.match(app, /event\.key === 'ArrowLeft' && item\._collapseTreeItem/);
  assert.match(app, /event\.key === 'Enter' && item\._activateTreeItem/);
  assert.match(app, /keyboardTreeSelection = false;[\s\S]*?updateTreeSelectionStyle\(\);/);
  assert.match(app, /invoke\('open_url', \{ entryId: entry\.id, fieldId: field\.id \}\)/);
  assert.match(styles, /\.field-value\.keyboard-selected/);
});

test('theme control exposes all three modes with an accessible selected state', () => {
  for (const mode of ['system', 'light', 'dark']) {
    assert.match(
      markup,
      new RegExp(`role="menuitemradio" aria-checked="false" data-theme-mode="${mode}"`),
    );
  }
  assert.match(markup, /id="theme-button"[^>]*role="button"[^>]*aria-label="Theme: System"[^>]*aria-haspopup="menu"[^>]*aria-expanded="false"[^>]*aria-controls="theme-menu"/);
  assert.match(styles, /\.theme-menu button\[aria-checked="true"\][^{]*\{[^}]*background:\s*var\(--accent-soft\);/s);
  assert.match(app, /createThemeController\(\{[\s\S]*matchMedia\('\(prefers-color-scheme: dark\)'\)/);
});

test('unlock screen omits the standalone logo and closes its former gap', () => {
  const unlockMarkup = markup.match(/<section id="unlock-view"[\s\S]*?<\/section>/)?.[0] ?? '';

  assert.doesNotMatch(unlockMarkup, /class="brand-mark"/);
  assert.match(unlockMarkup, /<h1>Unlock vault<\/h1>/);
  assert.match(styles, /\.unlock-panel h1\s*\{[^}]*margin-top:\s*0;/s);
  assert.match(markup, /class="window-brand-mark"/);
});

test('node dragging uses a compact custom preview', () => {
  assert.match(app, /const NODE_DRAG_PREVIEW_SCALE = 1\.05;/);
  assert.match(app, /const NODE_DRAG_PREVIEW_OPACITY = 0\.72;/);
  assert.match(app, /const preview = header\.cloneNode\(true\);/);
  assert.match(app, /preview\.querySelectorAll\('\.disclosure, \.node-actions, \.draft-actions'\)/);
  assert.match(app, /preview\.style\.zoom = String\(NODE_DRAG_PREVIEW_SCALE \/ displayScale\);/);
  assert.match(app, /dataTransfer\.setDragImage\(preview, offsetX, offsetY\);/);
  assert.match(styles, /\.node-drag-preview\s*\{[^}]*pointer-events:\s*none;/s);
});

test('focused search input hides its placeholder', () => {
  assert.match(
    styles,
    /\.chrome-search input:focus::placeholder\s*\{[^}]*color:\s*transparent;/,
  );
});

test('interface text is not selectable while editable fields remain selectable', () => {
  assert.match(
    styles,
    /\*\s*\{[^}]*user-select:\s*none;[^}]*-webkit-user-select:\s*none;/s,
  );
  assert.match(
    styles,
    /input,\s*textarea\s*\{[^}]*user-select:\s*text;[^}]*-webkit-user-select:\s*text;/s,
  );
  assert.doesNotMatch(styles, /code\s*\{[^}]*user-select:\s*text;/s);
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

test('compact inline editors reflow without collapsing their inputs', () => {
  assert.match(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.group-node\.draft > \.group-header[\s\S]*grid-template-columns:\s*28px 18px minmax\(0, 1fr\);/,
  );
  assert.match(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.entry-node\.editing > \.entry-header[\s\S]*grid-template-columns:\s*18px minmax\(0, 1fr\);/,
  );
  assert.match(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.field-editor-row\s*\{\s*grid-template-columns:\s*24px minmax\(0, 1fr\) 30px;/,
  );
  assert.match(
    styles,
    /@media \(max-width: 520px\)[\s\S]*\.entry-editor-footer\s*\{[^}]*flex-wrap:\s*wrap;/,
  );
});

test('unsaved groups and entries can move to a group before saving', () => {
  assert.match(app, /header\.dataset\.draftDragHeader = '';/);
  assert.match(app, /function commitDraftDrop\(\)/);
  assert.match(app, /draggedDraft\.element\.dataset\.parentId = parentId \?\? '';/);
  assert.match(app, /parentId: draft\.dataset\.parentId \|\| null,/);
  assert.match(app, /updateEntryDraftPath\(draggedDraft\.element, parentId\);/);
});

test('the active group becomes the default creation target', () => {
  assert.match(app, /let activeGroupId = null;/);
  assert.match(app, /group\.classList\.toggle\('active-group', group\.dataset\.nodeId === activeGroupId\);/);
  assert.match(app, /createDraft\(add\.dataset\.addKind, activeGroupId\);/);
  assert.match(app, /if \(activeGroup && !activeGroup\.contains\(event\.target\)\) \{\s*setActiveGroup\(null\);/);
  assert.match(
    styles,
    /\.group-node\.active-group > \.group-header\s*\{[^}]*background:\s*var\(--accent-soft\);[^}]*box-shadow:\s*inset 2px 0 var\(--accent\);/s,
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
