import { copyFieldValue } from './field-copy.js';
import { DEFAULT_VAULT_WINDOW_SIZE } from './window-layout.js';

const invoke = window.__TAURI__.core.invoke;
const listen = window.__TAURI__.event.listen;
const currentWindow = window.__TAURI__.window.getCurrentWindow();

const ICONS = {
  "key-round": '<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l1.4-1.4a1 1 0 0 0 0-1.4l-2.3-2.3"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  lock: '<rect width="14" height="11" x="5" y="11" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
  "sun-moon": '<path d="M12 8a4 4 0 1 0 4 4c0-.6-.13-1.16-.36-1.67A6 6 0 0 1 12 8z"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>',
  folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  "folder-plus": '<path d="M12 10v6M9 13h6"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  "file-plus": '<path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><path d="M12 18v-6M9 15h6"/>',
  "chevron-down": '<path d="m6 9 6 6 6-6"/>',
  pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v5M14 11v5"/>',
  eye: '<path d="M2.06 12.35a1 1 0 0 1 0-.7C3.73 7.9 7.1 5.5 12 5.5s8.27 2.4 9.94 6.15a1 1 0 0 1 0 .7C20.27 16.1 16.9 18.5 12 18.5s-8.27-2.4-9.94-6.15Z"/><circle cx="12" cy="12" r="3"/>',
  "eye-off": '<path d="m2 2 20 20M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 4.24A9.8 9.8 0 0 1 12 4c5 0 8.27 2.4 9.94 6.15a1 1 0 0 1 0 .7 11.8 11.8 0 0 1-2.17 3.2M6.61 6.61a11.7 11.7 0 0 0-4.55 5.04 1 1 0 0 0 0 .7C3.73 16.1 7 18.5 12 18.5c1.15 0 2.2-.13 3.16-.37"/>',
  check: '<path d="m20 6-11 11-5-5"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
  grip: '<circle cx="9" cy="5" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="5" r="1" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="9" cy="19" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="19" r="1" fill="currentColor" stroke="none"/>',
};

function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.classList.add('icon');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = ICONS[name] ?? '';
  return svg;
}

function hydrateIcons(scope = document) {
  scope.querySelectorAll('[data-icon]').forEach((slot) => {
    slot.replaceChildren(icon(slot.dataset.icon));
  });
}

function iconButton(name, label, handler, className = 'icon-button') {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = className;
  button.setAttribute('aria-label', label);
  button.append(icon(name));
  if (handler) button.addEventListener('click', handler);
  return button;
}

hydrateIcons();

const views = {
  loading: document.querySelector('#loading-view'),
  setup: document.querySelector('#setup-view'),
  unlock: document.querySelector('#unlock-view'),
  vault: document.querySelector('#vault-view'),
};

const dialogs = {
  vault: document.querySelector('#vault-dialog'),
  settings: document.querySelector('#settings-dialog'),
};

const workspaceTree = document.querySelector('#workspace-tree');
let appState = {
  vaults: [],
  settings: { autostart: false, auto_lock_seconds: 300, clipboard_clear_seconds: 30 },
  current: null,
};
let searchQuery = '';
let autoLockTimer = null;
let toastTimer = null;
let currentWindowLayout = null;
let draggedNode = null;
let nodeDrop = null;
let draggedFieldRow = null;
const expandedGroupIds = new Set();
const expandedEntryIds = new Set();
const revealedFields = new Map();

function afterNextPaint() {
  return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
}

async function setWindowLayout(name) {
  if (currentWindowLayout === name) return;
  try {
    await afterNextPaint();
    let { width, height } = DEFAULT_VAULT_WINDOW_SIZE;
    if (name === 'setup' || name === 'unlock') {
      const panel = views[name].querySelector('.setup-panel, .unlock-panel');
      const chromeHeight = document.querySelector('.window-chrome').offsetHeight;
      const frameStyle = getComputedStyle(document.querySelector('#window-frame'));
      const frameMargins = Number.parseFloat(frameStyle.marginTop)
        + Number.parseFloat(frameStyle.marginBottom);
      width = 520;
      height = Math.ceil(panel.scrollHeight + chromeHeight + frameMargins);
    }
    await invoke('resize_window', { width, height });
    currentWindowLayout = name;
  } catch (error) {
    notify(`Cannot resize window: ${String(error)}`);
  }
}

function showView(name) {
  document.body.dataset.view = name;
  Object.entries(views).forEach(([key, element]) => {
    element.hidden = key !== name;
  });
  document.querySelectorAll('[data-vault-only]').forEach((element) => {
    element.hidden = name !== 'vault';
  });
  if (name !== 'vault') {
    document.querySelector('#window-brand-kicker').textContent = 'Local vault';
    document.querySelector('#current-vault-name').textContent = 'bunch-of-keys';
  }
}

function setBusy(container, busy) {
  container.querySelectorAll('button, input, select').forEach((element) => {
    element.disabled = busy;
  });
}

function setFormError(form, message = '') {
  form.querySelector('.form-error').textContent = message;
}

function notify(message) {
  const toast = document.querySelector('#toast');
  toast.textContent = message;
  toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.hidden = true;
  }, 3200);
}

function protectInlineWork(except = null) {
  const active = workspaceTree.querySelector('.draft, .editing');
  if (!active || active === except) return false;
  notify('Save or cancel the current inline editor first.');
  active.querySelector('input, button')?.focus();
  return true;
}

function selectedVaultName() {
  const id = appState.current?.id;
  return appState.vaults.find((vault) => vault.id === id)?.name ?? 'Unlocked';
}

function updateVaultSelect() {
  const select = document.querySelector('#vault-select');
  const previous = select.value;
  select.replaceChildren();
  appState.vaults.forEach((vault) => {
    const option = document.createElement('option');
    option.value = vault.id;
    option.textContent = vault.name;
    select.append(option);
  });
  if (appState.vaults.some((vault) => vault.id === previous)) select.value = previous;
}

function enterLockedState() {
  appState.current = null;
  searchQuery = '';
  expandedGroupIds.clear();
  expandedEntryIds.clear();
  revealedFields.clear();
  clearTimeout(autoLockTimer);
  workspaceTree.replaceChildren();
  document.querySelector('#search-input').value = '';
  Object.values(dialogs).forEach((dialog) => {
    if (dialog.open) dialog.close();
  });
  updateVaultSelect();
  const view = appState.vaults.length ? 'unlock' : 'setup';
  showView(view);
  void setWindowLayout(view);
  const password = document.querySelector('#unlock-form input[name="password"]');
  password.value = '';
  if (appState.vaults.length) password.focus();
}

function enterVault(vault) {
  appState.current = vault;
  searchQuery = '';
  expandedGroupIds.clear();
  expandedEntryIds.clear();
  revealedFields.clear();
  document.querySelector('#search-input').value = '';
  document.querySelector('#window-brand-kicker').textContent = 'Current vault';
  document.querySelector('#current-vault-name').textContent = selectedVaultName();
  showView('vault');
  void setWindowLayout('vault');
  renderWorkspace();
  scheduleAutoLock();
}

function scheduleAutoLock() {
  clearTimeout(autoLockTimer);
  if (!appState.current) return;
  autoLockTimer = setTimeout(async () => invoke('lock_vault'), appState.settings.auto_lock_seconds * 1000);
}

function activity() {
  if (appState.current) scheduleAutoLock();
}

function allGroups(nodes, output = [], path = '') {
  nodes.forEach((node) => {
    if (node.type !== 'group') return;
    const nextPath = path ? `${path}.${node.name}` : node.name;
    output.push({ node, path: nextPath });
    allGroups(node.children, output, nextPath);
  });
  return output;
}

function nodeMatches(node, query) {
  if (!query) return true;
  if (node.name.toLowerCase().includes(query)) return true;
  if (node.type === 'entry') {
    return node.fields.some((field) => [field.label, field.value ?? ''].some((value) => value.toLowerCase().includes(query)));
  }
  return node.children.some((child) => nodeMatches(child, query));
}

function descendantCounts(group) {
  let groups = 0;
  let entries = 0;
  const visit = (nodes) => nodes.forEach((node) => {
    if (node.type === 'group') {
      groups += 1;
      visit(node.children);
    } else {
      entries += 1;
    }
  });
  visit(group.children);
  return { groups, entries };
}

function countLabel(group) {
  const { groups, entries } = descendantCounts(group);
  const parts = [];
  if (groups) parts.push(`${groups} ${groups === 1 ? 'group' : 'groups'}`);
  if (entries) parts.push(`${entries} ${entries === 1 ? 'entry' : 'entries'}`);
  return parts.join(' · ') || 'Empty';
}

function renderWorkspace() {
  if (!appState.current) return;
  workspaceTree.replaceChildren();
  const visibleNodes = appState.current.nodes.filter((node) => nodeMatches(node, searchQuery));
  visibleNodes.forEach((node, index) => workspaceTree.append(renderNode(node, '', null, index)));
  document.querySelector('#empty-state').hidden = appState.current.nodes.length > 0 || Boolean(searchQuery);
  document.querySelector('#search-empty-state').hidden = !searchQuery || visibleNodes.length > 0;
}

function renderNode(node, parentPath, parentId, index) {
  return node.type === 'group'
    ? renderGroup(node, parentPath, parentId, index)
    : renderEntry(node, parentPath, parentId, index);
}

function configureDraggableHeader(header, node) {
  header.draggable = true;
  header.dataset.dragHeader = '';
  header.setAttribute('aria-label', `Drag ${node.name}`);
}

function renderGroup(group, parentPath, parentId, index) {
  const section = document.createElement('section');
  section.className = 'node group-node';
  section.dataset.nodeId = group.id;
  section.dataset.nodeType = 'group';
  section.dataset.parentId = parentId ?? '';
  section.dataset.index = String(index);

  const expanded = Boolean(searchQuery) || expandedGroupIds.has(group.id);
  section.classList.toggle('collapsed', !expanded);
  const header = document.createElement('header');
  header.className = 'group-header';
  configureDraggableHeader(header, group);

  const disclosure = iconButton('chevron-down', `${expanded ? 'Collapse' : 'Expand'} ${group.name}`, () => {
    if (protectInlineWork()) return;
    if (expandedGroupIds.has(group.id)) expandedGroupIds.delete(group.id);
    else expandedGroupIds.add(group.id);
    renderWorkspace();
  }, 'disclosure');
  disclosure.setAttribute('aria-expanded', String(expanded));

  const folder = document.createElement('span');
  folder.className = 'node-icon';
  folder.append(icon('folder'));
  const name = document.createElement('span');
  name.className = 'node-name';
  name.textContent = group.name;
  const meta = document.createElement('small');
  meta.className = 'node-meta';
  meta.textContent = countLabel(group);
  const actions = document.createElement('div');
  actions.className = 'node-actions';
  actions.append(
    iconButton('pencil', `Rename ${group.name}`, () => startGroupEdit(section, group)),
    createAddControl(group.id, group.name),
  );
  header.append(disclosure, folder, name, meta, actions);

  const children = document.createElement('div');
  children.className = 'node-children';
  children.dataset.children = '';
  children.dataset.parentId = group.id;
  const groupPath = parentPath ? `${parentPath}.${group.name}` : group.name;
  group.children
    .filter((node) => nodeMatches(node, searchQuery))
    .forEach((node, childIndex) => children.append(renderNode(node, groupPath, group.id, childIndex)));
  section.append(header, children);
  return section;
}

function renderEntry(entry, parentPath, parentId, index) {
  const article = document.createElement('article');
  article.className = 'node entry-node';
  article.dataset.nodeId = entry.id;
  article.dataset.nodeType = 'entry';
  article.dataset.parentId = parentId ?? '';
  article.dataset.index = String(index);

  const header = document.createElement('header');
  header.className = 'entry-header';
  configureDraggableHeader(header, entry);
  const key = document.createElement('span');
  key.className = 'node-icon';
  key.append(icon('key-round'));
  const title = document.createElement('div');
  title.className = 'entry-name';
  if (parentPath) {
    const path = document.createElement('span');
    path.className = 'entry-path';
    path.textContent = `${parentPath}.`;
    title.append(path);
  }
  const ownName = document.createElement('span');
  ownName.textContent = entry.name;
  title.append(ownName);
  const meta = document.createElement('small');
  meta.className = 'node-meta';
  meta.textContent = `${entry.fields.length} ${entry.fields.length === 1 ? 'field' : 'fields'}`;
  const actions = document.createElement('div');
  actions.className = 'node-actions';
  const edit = iconButton('pencil', `Edit ${entry.name}`, () => void startEntryEdit(article, entry, parentPath));
  actions.append(edit);
  header.append(key, title, meta, actions);
  header.addEventListener('click', (event) => {
    if (event.target.closest('button, input, select, summary, details')) return;
    if (protectInlineWork()) return;
    if (expandedEntryIds.has(entry.id)) expandedEntryIds.delete(entry.id);
    else expandedEntryIds.add(entry.id);
    renderWorkspace();
  });
  article.append(header);

  if (expandedEntryIds.has(entry.id)) article.append(renderEntryFields(entry));
  return article;
}

function renderEntryFields(entry) {
  const fields = document.createElement('div');
  fields.className = 'entry-fields-view';
  if (!entry.fields.length) {
    const empty = document.createElement('div');
    empty.className = 'field-view-row muted';
    empty.textContent = 'No fields';
    fields.append(empty);
    return fields;
  }
  entry.fields.forEach((field) => {
    const row = document.createElement('div');
    row.className = 'field-view-row';
    const valueBox = document.createElement('button');
    valueBox.type = 'button';
    valueBox.className = 'field-value';
    valueBox.setAttribute('aria-label', `Copy ${field.label}`);
    valueBox.title = `Copy ${field.label}`;
    const label = document.createElement('small');
    label.textContent = field.label;
    const value = document.createElement('code');
    const revealKey = `${entry.id}:${field.id}`;
    const revealed = revealedFields.get(revealKey);
    value.textContent = field.masked ? (revealed ?? '••••••••••••••••') : (field.value || '—');
    value.classList.toggle('masked-value', field.masked && !revealed);
    const feedback = document.createElement('span');
    feedback.className = 'field-copy-feedback';
    feedback.textContent = 'Copied';
    feedback.setAttribute('aria-hidden', 'true');
    valueBox.append(label, value, feedback);
    valueBox.addEventListener('click', () => void copyFieldValue({
      target: valueBox,
      copy: () => invoke('copy_field', { entryId: entry.id, fieldId: field.id }),
      onSuccess: () => notify(`Copied. Clipboard will clear in ${appState.settings.clipboard_clear_seconds} seconds.`),
      onError: (error) => notify(String(error)),
    }));
    row.append(valueBox);
    if (field.masked) {
      row.append(iconButton(revealed ? 'eye-off' : 'eye', revealed ? 'Hide value' : 'Reveal value', async () => {
        if (revealedFields.has(revealKey)) {
          revealedFields.delete(revealKey);
        } else {
          try {
            revealedFields.set(revealKey, await invoke('reveal_field', { entryId: entry.id, fieldId: field.id }));
          } catch (error) {
            notify(String(error));
          }
        }
        renderWorkspace();
      }));
    }
    fields.append(row);
  });
  return fields;
}

function createAddControl(parentId, parentName) {
  const details = document.createElement('details');
  details.className = 'add-control';
  const summary = document.createElement('summary');
  summary.className = 'icon-button';
  summary.setAttribute('aria-label', `Add inside ${parentName}`);
  summary.append(icon('plus'));
  const menu = document.createElement('div');
  menu.className = 'add-menu';
  menu.setAttribute('role', 'menu');
  menu.append(
    addMenuButton('folder-plus', 'Group', 'group', parentId),
    addMenuButton('file-plus', 'Entry', 'entry', parentId),
  );
  details.append(summary, menu);
  return details;
}

function addMenuButton(iconName, label, kind, parentId) {
  const button = document.createElement('button');
  button.type = 'button';
  button.setAttribute('role', 'menuitem');
  button.dataset.addKind = kind;
  button.dataset.parentId = parentId ?? '';
  button.append(icon(iconName), document.createTextNode(label));
  return button;
}

function childrenContainer(parentId) {
  return [...document.querySelectorAll('[data-children]')]
    .find((container) => container.dataset.parentId === (parentId ?? '')) ?? null;
}

function createDraft(kind, parentId) {
  if (protectInlineWork()) return;
  if (parentId) expandedGroupIds.add(parentId);
  renderWorkspace();
  const container = childrenContainer(parentId);
  if (!container) return;
  const draft = kind === 'group' ? createGroupDraft(parentId) : createEntryDraft(parentId);
  container.append(draft);
  draft.querySelector('[data-name-input]').focus();
}

function createGroupDraft(parentId) {
  const section = document.createElement('section');
  section.className = 'node group-node draft';
  section.dataset.nodeType = 'group';
  section.dataset.parentId = parentId ?? '';
  const header = document.createElement('header');
  header.className = 'group-header';
  const spacer = document.createElement('span');
  spacer.className = 'disclosure';
  const symbol = document.createElement('span');
  symbol.className = 'node-icon';
  symbol.append(icon('folder-plus'));
  const input = document.createElement('input');
  input.className = 'inline-input group-name-input';
  input.dataset.nameInput = '';
  input.setAttribute('aria-label', 'Group name');
  input.maxLength = 200;
  input.required = true;
  const state = document.createElement('small');
  state.className = 'draft-state';
  state.textContent = 'Unsaved draft';
  const actions = document.createElement('div');
  actions.className = 'draft-actions';
  actions.append(
    compactButton('Cancel', () => section.remove()),
    compactButton('Save group', () => void saveGroupDraft(section), true),
  );
  header.append(spacer, symbol, input, state, actions);
  section.append(header);
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') void saveGroupDraft(section);
    if (event.key === 'Escape') section.remove();
  });
  return section;
}

function createEntryDraft(parentId) {
  const article = document.createElement('article');
  article.className = 'node entry-node draft editing';
  article.dataset.nodeType = 'entry';
  article.dataset.parentId = parentId ?? '';
  const path = parentId ? allGroups(appState.current.nodes).find(({ node }) => node.id === parentId)?.path ?? '' : '';
  const header = editorHeader('', path, 'Unsaved draft');
  const editor = createEntryEditor([{ id: null, label: '', value: '', kind: 'text', masked: false }]);
  const footer = editorFooter(article, editor, {
    cancelLabel: 'Cancel',
    saveLabel: 'Save entry',
    onCancel: () => article.remove(),
    onSave: () => void saveEntryDraft(article, editor, parentId),
  });
  article.append(header, editor, footer);
  return article;
}

function editorHeader(name, path, stateText = '') {
  const header = document.createElement('header');
  header.className = 'entry-header';
  const symbol = document.createElement('span');
  symbol.className = 'node-icon';
  symbol.append(icon('key-round'));
  const nameEditor = document.createElement('div');
  nameEditor.className = 'entry-name-editor';
  if (path) {
    const prefix = document.createElement('span');
    prefix.className = 'entry-path';
    prefix.textContent = `${path}.`;
    nameEditor.append(prefix);
  }
  const input = document.createElement('input');
  input.className = 'inline-input';
  input.dataset.nameInput = '';
  input.setAttribute('aria-label', 'Entry name');
  input.maxLength = 200;
  input.required = true;
  input.value = name;
  nameEditor.append(input);
  header.append(symbol, nameEditor);
  if (stateText) {
    const state = document.createElement('small');
    state.className = 'draft-state';
    state.textContent = stateText;
    header.append(state);
  }
  return header;
}

function createEntryEditor(fields) {
  const editor = document.createElement('div');
  editor.className = 'entry-editor';
  const fieldEditor = document.createElement('div');
  fieldEditor.className = 'field-editor';
  fields.forEach((field) => fieldEditor.append(createFieldEditorRow(field, fieldEditor)));
  const error = document.createElement('p');
  error.className = 'inline-error';
  error.setAttribute('role', 'alert');
  editor.append(fieldEditor, error);
  return editor;
}

function createFieldEditorRow(field, editor) {
  const row = document.createElement('div');
  row.className = 'field-editor-row';
  row.dataset.fieldId = field.id ?? '';
  const dragHandle = iconButton('grip', `Drag ${field.label || 'field'} to reorder`, null, 'field-drag-handle');
  dragHandle.draggable = true;
  dragHandle.title = 'Drag to reorder';
  dragHandle.addEventListener('dragstart', (event) => {
    draggedFieldRow = row;
    row.classList.add('field-dragging');
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', row.dataset.fieldId || 'new-field');
  });
  dragHandle.addEventListener('dragend', () => {
    row.classList.remove('field-dragging');
    draggedFieldRow = null;
    clearFieldDropIndicators(editor);
  });
  row.addEventListener('dragover', (event) => {
    if (!draggedFieldRow || draggedFieldRow === row) return;
    event.preventDefault();
    clearFieldDropIndicators(editor);
    const after = event.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2;
    row.classList.add(after ? 'field-drop-after' : 'field-drop-before');
  });
  row.addEventListener('drop', (event) => {
    if (!draggedFieldRow || draggedFieldRow === row) return;
    event.preventDefault();
    const after = event.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2;
    editor.insertBefore(draggedFieldRow, after ? row.nextSibling : row);
    clearFieldDropIndicators(editor);
  });

  const label = labeledInput('Label', 'text', field.label ?? '', true);
  const value = labeledInput('Value', field.masked ? 'password' : 'text', field.value ?? '', false);
  const kindLabel = document.createElement('label');
  const kindText = document.createElement('small');
  kindText.textContent = 'Type';
  const kind = document.createElement('select');
  ['text', 'secret', 'url'].forEach((name) => {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name[0].toUpperCase() + name.slice(1);
    kind.append(option);
  });
  kind.value = field.kind ?? 'text';
  kindLabel.append(kindText, kind);
  let masked = Boolean(field.masked);
  kind.addEventListener('change', () => {
    masked = kind.value === 'secret';
    value.input.type = masked ? 'password' : 'text';
  });
  const actions = document.createElement('div');
  actions.className = 'field-actions';
  actions.append(iconButton('x', 'Remove field', () => row.remove()));
  row.append(dragHandle, label.wrapper, value.wrapper, kindLabel, actions);
  row._inputs = { label: label.input, value: value.input, kind, masked: () => masked };
  return row;
}

function clearFieldDropIndicators(editor) {
  editor.querySelectorAll('.field-editor-row').forEach((row) => {
    row.classList.remove('field-drop-before', 'field-drop-after');
  });
}

function labeledInput(text, type, value, required) {
  const wrapper = document.createElement('label');
  const label = document.createElement('small');
  label.textContent = text;
  const input = document.createElement('input');
  input.type = type;
  input.value = value;
  input.required = required;
  wrapper.append(label, input);
  return { wrapper, input };
}

function editorFooter(owner, editor, options) {
  const footer = document.createElement('footer');
  footer.className = 'entry-editor-footer';
  const addField = document.createElement('button');
  addField.type = 'button';
  addField.className = 'text-button';
  addField.append(icon('plus'), document.createTextNode('Add field'));
  addField.addEventListener('click', () => {
    const fieldEditor = editor.querySelector('.field-editor');
    const row = createFieldEditorRow({ label: '', value: '', kind: 'text', masked: false }, fieldEditor);
    fieldEditor.append(row);
    row.querySelector('input').focus();
  });
  const actions = document.createElement('div');
  actions.className = 'draft-actions';
  actions.append(
    compactButton(options.cancelLabel, options.onCancel),
    compactButton(options.saveLabel, options.onSave, true),
  );
  if (options.onDelete) actions.prepend(iconButton('trash', 'Delete entry', options.onDelete));
  footer.append(addField, actions);
  return footer;
}

function compactButton(text, handler, primary = false) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `button compact-button ${primary ? 'primary' : 'secondary'}`;
  button.textContent = text;
  button.addEventListener('click', handler);
  return button;
}

function readEditor(editor) {
  return [...editor.querySelectorAll('.field-editor-row')].map((row) => ({
    id: row.dataset.fieldId || null,
    label: row._inputs.label.value.trim(),
    value: row._inputs.value.value,
    kind: row._inputs.kind.value,
    masked: row._inputs.masked(),
  }));
}

function validateInlineEntry(owner, editor) {
  const error = editor.querySelector('.inline-error');
  error.textContent = '';
  const nameInput = owner.querySelector('[data-name-input]');
  const name = nameInput.value.trim();
  if (!name) {
    error.textContent = 'Entry name is required.';
    nameInput.focus();
    return null;
  }
  const fields = readEditor(editor);
  if (!fields.length) {
    error.textContent = 'Add at least one field.';
    return null;
  }
  const emptyField = fields.findIndex((field) => !field.label);
  if (emptyField >= 0) {
    error.textContent = 'Every field needs a label.';
    editor.querySelectorAll('.field-editor-row')[emptyField]._inputs.label.focus();
    return null;
  }
  return { name, fields };
}

async function saveGroupDraft(draft) {
  const input = draft.querySelector('[data-name-input]');
  const name = input.value.trim();
  if (!name) {
    input.focus();
    return;
  }
  setBusy(draft, true);
  try {
    appState.current = await invoke('add_group', { parentId: draft.dataset.parentId || null, name });
    renderWorkspace();
    notify(`${name} saved.`);
  } catch (error) {
    notify(String(error));
    setBusy(draft, false);
  }
}

async function saveEntryDraft(draft, editor, parentId) {
  const data = validateInlineEntry(draft, editor);
  if (!data) return;
  setBusy(draft, true);
  try {
    appState.current = await invoke('add_entry', { parentId: parentId || null, name: data.name, fields: data.fields });
    renderWorkspace();
    notify(`${data.name} saved.`);
  } catch (error) {
    editor.querySelector('.inline-error').textContent = String(error);
    setBusy(draft, false);
  }
}

function startGroupEdit(section, group) {
  if (protectInlineWork(section)) return;
  const header = section.querySelector('.group-header');
  section.classList.add('editing');
  header.draggable = false;
  const disclosure = header.querySelector('.disclosure');
  const symbol = header.querySelector('.node-icon');
  const input = document.createElement('input');
  input.className = 'inline-input group-name-input';
  input.value = group.name;
  input.maxLength = 200;
  input.setAttribute('aria-label', 'Group name');
  const actions = document.createElement('div');
  actions.className = 'draft-actions';
  const cancel = iconButton('x', 'Cancel rename', renderWorkspace);
  const save = iconButton('check', 'Save group name', () => void saveGroupEdit());
  const remove = iconButton('trash', `Delete ${group.name}`, () => void deleteNode(group));
  actions.append(remove, cancel, save);
  header.replaceChildren(disclosure, symbol, input, actions);
  input.focus();
  input.select();

  const saveGroupEdit = async () => {
    const name = input.value.trim();
    if (!name) {
      input.focus();
      return;
    }
    setBusy(section, true);
    try {
      appState.current = await invoke('rename_node', { nodeId: group.id, name });
      renderWorkspace();
      notify(`${name} renamed.`);
    } catch (error) {
      notify(String(error));
      setBusy(section, false);
    }
  };
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') void saveGroupEdit();
    if (event.key === 'Escape') renderWorkspace();
  });
}

async function startEntryEdit(article, entry, path) {
  if (protectInlineWork(article)) return;
  article.classList.add('editing');
  setBusy(article, true);
  let fields;
  try {
    fields = await Promise.all(entry.fields.map(async (field) => ({
      ...field,
      value: field.masked ? await invoke('reveal_field', { entryId: entry.id, fieldId: field.id }) : field.value,
    })));
  } catch (error) {
    notify(String(error));
    article.classList.remove('editing');
    setBusy(article, false);
    return;
  }
  article.replaceChildren();
  const header = editorHeader(entry.name, path);
  const editor = createEntryEditor(fields);
  const footer = editorFooter(article, editor, {
    cancelLabel: 'Cancel',
    saveLabel: 'Save changes',
    onCancel: renderWorkspace,
    onSave: () => void saveEntryEdit(article, editor, entry),
    onDelete: () => void deleteNode(entry),
  });
  article.append(header, editor, footer);
  article.querySelector('[data-name-input]').focus();
  article.querySelector('[data-name-input]').select();
}

async function saveEntryEdit(article, editor, entry) {
  const data = validateInlineEntry(article, editor);
  if (!data) return;
  setBusy(article, true);
  try {
    appState.current = await invoke('update_entry', { entryId: entry.id, name: data.name, fields: data.fields });
    expandedEntryIds.delete(entry.id);
    renderWorkspace();
    notify(`${data.name} saved.`);
  } catch (error) {
    editor.querySelector('.inline-error').textContent = String(error);
    setBusy(article, false);
  }
}

async function deleteNode(node) {
  const kind = node.type === 'group' ? 'group and everything inside it' : 'entry';
  if (!window.confirm(`Delete the ${kind} “${node.name}”? This cannot be undone.`)) return;
  try {
    appState.current = await invoke('delete_node', { nodeId: node.id });
    expandedGroupIds.delete(node.id);
    expandedEntryIds.delete(node.id);
    renderWorkspace();
  } catch (error) {
    notify(String(error));
  }
}

function clearNodeDropIndicators() {
  document.querySelectorAll('.drop-before, .drop-after, .drop-inside').forEach((element) => {
    element.classList.remove('drop-before', 'drop-after', 'drop-inside');
  });
  nodeDrop = null;
}

function savedSiblings(container) {
  return [...container.children].filter((child) => child.matches('.node[data-node-id]') && child.dataset.nodeId !== draggedNode?.id);
}

function setNodeDrop(event) {
  if (!draggedNode) return false;
  const draggedElement = document.querySelector(`.node[data-node-id="${draggedNode.id}"]`);
  const hoveredHeader = event.target.closest('.group-header, .entry-header');
  const hoveredContainer = event.target.closest('[data-children]');
  const target = hoveredHeader?.closest('.node[data-node-id]') ?? null;
  clearNodeDropIndicators();
  if (target) {
    if (target.dataset.nodeId === draggedNode.id || (draggedElement && draggedElement.contains(target))) return false;
    const rect = hoveredHeader.getBoundingClientRect();
    const offset = event.clientY - rect.top;
    const inside = target.dataset.nodeType === 'group' && offset >= rect.height * .27 && offset <= rect.height * .73;
    if (inside) {
      target.classList.add('drop-inside');
      nodeDrop = { mode: 'inside', target };
    } else {
      const mode = offset > rect.height / 2 ? 'after' : 'before';
      target.classList.add(`drop-${mode}`);
      nodeDrop = { mode, target };
    }
    return true;
  }
  const container = hoveredContainer;
  if (!container || (draggedElement && draggedElement.contains(container))) return false;
  container.classList.add('drop-inside');
  nodeDrop = { mode: 'container', container };
  return true;
}

async function commitNodeDrop() {
  if (!draggedNode || !nodeDrop) return;
  let parentId;
  let index;
  if (nodeDrop.mode === 'inside') {
    parentId = nodeDrop.target.dataset.nodeId;
    const container = [...nodeDrop.target.children].find((child) => child.matches('[data-children]'));
    index = savedSiblings(container).length;
  } else if (nodeDrop.mode === 'container') {
    parentId = nodeDrop.container.dataset.parentId || null;
    index = savedSiblings(nodeDrop.container).length;
  } else {
    const container = nodeDrop.target.parentElement;
    parentId = container.dataset.parentId || null;
    const siblings = savedSiblings(container);
    index = siblings.indexOf(nodeDrop.target) + (nodeDrop.mode === 'after' ? 1 : 0);
  }
  try {
    appState.current = await invoke('move_node', { nodeId: draggedNode.id, parentId, index });
    if (parentId) expandedGroupIds.add(parentId);
    renderWorkspace();
  } catch (error) {
    notify(String(error));
  }
}

workspaceTree.addEventListener('click', (event) => {
  const add = event.target.closest('[data-add-kind]');
  if (!add) return;
  const details = add.closest('details');
  if (details) details.open = false;
  createDraft(add.dataset.addKind, add.dataset.parentId || null);
});

document.querySelector('#root-add-menu').addEventListener('click', (event) => {
  const add = event.target.closest('[data-add-kind]');
  if (!add) return;
  event.currentTarget.open = false;
  createDraft(add.dataset.addKind, null);
});

workspaceTree.addEventListener('dragstart', (event) => {
  if (draggedFieldRow) return;
  if (protectInlineWork()) {
    event.preventDefault();
    return;
  }
  const header = event.target.closest('[data-drag-header]');
  if (!header || event.target.closest('button, input, select, label, details, summary')) {
    event.preventDefault();
    return;
  }
  const node = header.closest('.node[data-node-id]');
  draggedNode = { id: node.dataset.nodeId, type: node.dataset.nodeType };
  node.classList.add('dragging');
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', draggedNode.id);
});

workspaceTree.addEventListener('dragover', (event) => {
  if (!draggedNode || !setNodeDrop(event)) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
});

workspaceTree.addEventListener('drop', (event) => {
  if (!draggedNode || !nodeDrop) return;
  event.preventDefault();
  void commitNodeDrop();
  clearNodeDropIndicators();
});

workspaceTree.addEventListener('dragend', () => {
  workspaceTree.querySelector('.dragging')?.classList.remove('dragging');
  draggedNode = null;
  clearNodeDropIndicators();
});

async function submitCreateVault(form) {
  setFormError(form);
  const data = new FormData(form);
  if (data.get('password') !== data.get('confirmPassword')) {
    setFormError(form, 'Passwords do not match.');
    return;
  }
  setBusy(form, true);
  try {
    const vault = await invoke('create_vault', { name: data.get('name'), password: data.get('password') });
    appState = await invoke('bootstrap');
    if (form.closest('dialog')) form.closest('dialog').close();
    form.reset();
    enterVault(vault);
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    setBusy(form, false);
  }
}

document.querySelector('#setup-form').addEventListener('submit', (event) => {
  event.preventDefault();
  void submitCreateVault(event.currentTarget);
});

document.querySelector('#vault-form').addEventListener('submit', (event) => {
  event.preventDefault();
  void submitCreateVault(event.currentTarget);
});

document.querySelector('#unlock-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  setFormError(form);
  setBusy(form, true);
  try {
    const vault = await invoke('unlock_vault', { vaultId: data.get('vaultId'), password: data.get('password') });
    form.elements.password.value = '';
    enterVault(vault);
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    setBusy(form, false);
  }
});

document.querySelector('#settings-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  const settings = {
    autostart: data.get('autostart') === 'on',
    auto_lock_seconds: Number(data.get('autoLockSeconds')),
    clipboard_clear_seconds: Number(data.get('clipboardClearSeconds')),
  };
  setFormError(form);
  setBusy(form, true);
  try {
    await invoke('update_settings', { settings });
    appState.settings = settings;
    dialogs.settings.close();
    scheduleAutoLock();
    notify('Settings saved.');
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    setBusy(form, false);
  }
});

document.querySelector('#yaml-input').addEventListener('change', async (event) => {
  const input = event.currentTarget;
  const file = input.files?.[0];
  input.value = '';
  if (!file || !window.confirm(`Import entries from “${file.name}” into this vault?`)) return;
  try {
    appState.current = await invoke('import_yaml_file', { source: await file.text() });
    dialogs.settings.close();
    renderWorkspace();
    notify('YAML import complete. Review which fields are masked.');
  } catch (error) {
    notify(String(error));
  }
});

document.querySelector('#settings-button').addEventListener('click', () => {
  const form = document.querySelector('#settings-form');
  setFormError(form);
  form.elements.autostart.checked = appState.settings.autostart;
  form.elements.autoLockSeconds.value = String(appState.settings.auto_lock_seconds);
  form.elements.clipboardClearSeconds.value = String(appState.settings.clipboard_clear_seconds);
  dialogs.settings.showModal();
});

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  const nextTheme = theme === 'dark' ? 'light' : 'dark';
  document.querySelector('#theme-button').setAttribute('aria-label', `Use ${nextTheme} theme`);
  try {
    localStorage.setItem('bunch-of-keys-theme', theme);
  } catch (_) {
    // Theme persistence is best-effort in restricted webviews.
  }
}

let initialTheme = 'dark';
try {
  initialTheme = localStorage.getItem('bunch-of-keys-theme')
    ?? (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
} catch (_) {
  initialTheme = 'dark';
}
applyTheme(initialTheme);

document.querySelector('#theme-button').addEventListener('click', () => {
  applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
});
document.querySelector('#lock-button').addEventListener('click', () => invoke('lock_vault'));
document.querySelector('#minimize-window').addEventListener('click', async () => {
  try { await invoke('minimize_window'); } catch (error) { notify(String(error)); }
});
document.querySelector('#close-window').addEventListener('click', async () => {
  try { await invoke('hide_window'); } catch (error) { notify(String(error)); }
});
document.querySelectorAll('[data-resize-direction]').forEach((handle) => {
  handle.addEventListener('pointerdown', async (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    try {
      await currentWindow.startResizeDragging(handle.dataset.resizeDirection);
    } catch (error) {
      notify(`Cannot resize window: ${String(error)}`);
    }
  });
});
document.querySelector('#open-new-vault').addEventListener('click', () => dialogs.vault.showModal());
document.querySelector('#search-input').addEventListener('input', (event) => {
  if (protectInlineWork()) {
    event.currentTarget.value = searchQuery;
    return;
  }
  searchQuery = event.currentTarget.value.trim().toLowerCase();
  renderWorkspace();
});
document.querySelectorAll('.dialog-close').forEach((button) => {
  button.addEventListener('click', () => button.closest('dialog').close());
});
document.addEventListener('pointerdown', activity, { passive: true });
document.addEventListener('keydown', activity);

await listen('vault-locked', () => {
  enterLockedState();
  notify('Vault locked.');
});

try {
  appState = await invoke('bootstrap');
  updateVaultSelect();
  if (appState.current) enterVault(appState.current);
  else enterLockedState();
} catch (error) {
  showView('loading');
  document.querySelector('#loading-view p').textContent = `Cannot start: ${String(error)}`;
}
