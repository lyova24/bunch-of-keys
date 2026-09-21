import { copyFieldValue } from './field-copy.js';
import { createThemeController } from './theme.js';
import { DEFAULT_VAULT_WINDOW_SIZE } from './window-layout.js';

const NODE_DRAG_PREVIEW_SCALE = 1.05;
const NODE_DRAG_PREVIEW_OPACITY = 0.72;

const ICONS = {
  "key-round": '<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l1.4-1.4a1 1 0 0 0 0-1.4l-2.3-2.3"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  lock: '<rect width="14" height="11" x="5" y="11" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>',
  moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z"/>',
  monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8M12 17v4"/>',
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
  terminal: '<path d="m4 17 6-6-6-6M12 19h8"/>',
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

createThemeController({
  root: document.documentElement,
  trigger: document.querySelector('#theme-button'),
  options: [...document.querySelectorAll('[data-theme-mode]')],
  mediaQuery: matchMedia('(prefers-color-scheme: dark)'),
  storage: localStorage,
});

const invoke = window.__TAURI__.core.invoke;
const listen = window.__TAURI__.event.listen;
const currentWindow = window.__TAURI__.window.getCurrentWindow();

const views = {
  loading: document.querySelector('#loading-view'),
  setup: document.querySelector('#setup-view'),
  unlock: document.querySelector('#unlock-view'),
  vault: document.querySelector('#vault-view'),
};

const dialogs = {
  vault: document.querySelector('#vault-dialog'),
  settings: document.querySelector('#settings-dialog'),
  sshKey: document.querySelector('#ssh-key-dialog'),
  sshPassphrase: document.querySelector('#ssh-passphrase-dialog'),
};

const workspaceTree = document.querySelector('#workspace-tree');
let appState = {
  vaults: [],
  settings: { autostart: false, auto_lock_seconds: 300, clipboard_clear_seconds: 30 },
  current: null,
};
let searchQuery = '';
let activeGroupId = null;
let autoLockTimer = null;
let toastTimer = null;
let currentWindowLayout = null;
let draggedNode = null;
let draggedDraft = null;
let nodeDrop = null;
let nodeDragPreview = null;
let draggedFieldRow = null;
let sshKeyTargetRow = null;
let pendingSshConnection = null;
let focusedTreeItemKey = null;
let keyboardTreeSelection = false;
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
  container.querySelectorAll('button, input, select, textarea').forEach((element) => {
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
  activeGroupId = null;
  focusedTreeItemKey = null;
  keyboardTreeSelection = false;
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
  activeGroupId = null;
  focusedTreeItemKey = null;
  keyboardTreeSelection = false;
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

function setActiveGroup(groupId) {
  const groups = allGroups(appState.current?.nodes ?? []);
  activeGroupId = groups.some(({ node }) => node.id === groupId) ? groupId : null;
  workspaceTree.querySelectorAll('.group-node[data-node-id]').forEach((group) => {
    group.classList.toggle('active-group', group.dataset.nodeId === activeGroupId);
  });
  const active = groups.find(({ node }) => node.id === activeGroupId)?.node;
  const add = document.querySelector('#root-add-menu > summary');
  const label = active ? `Add inside ${active.name}` : 'Add to vault root';
  add.setAttribute('aria-label', label);
  add.title = label;
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
  const restoreTreeFocus = Boolean(document.activeElement?.closest?.('[data-tree-item]'));
  if (activeGroupId && !allGroups(appState.current.nodes).some(({ node }) => node.id === activeGroupId)) {
    activeGroupId = null;
  }
  workspaceTree.replaceChildren();
  const visibleNodes = appState.current.nodes.filter((node) => nodeMatches(node, searchQuery));
  visibleNodes.forEach((node, index) => workspaceTree.append(renderNode(node, '', null, index)));
  document.querySelector('#empty-state').hidden = appState.current.nodes.length > 0 || Boolean(searchQuery);
  document.querySelector('#search-empty-state').hidden = !searchQuery || visibleNodes.length > 0;
  setActiveGroup(activeGroupId);
  syncTreeTabStop(restoreTreeFocus);
}

function visibleTreeItems() {
  return [...workspaceTree.querySelectorAll('[data-tree-item]')].filter(
    (item) => !item.closest('.group-node.collapsed > .node-children'),
  );
}

function syncTreeTabStop(restoreFocus = false) {
  const items = visibleTreeItems();
  let focused = items.find((item) => item.dataset.treeKey === focusedTreeItemKey);
  if (!focused) focused = items[0] ?? null;
  focusedTreeItemKey = focused?.dataset.treeKey ?? null;
  items.forEach((item) => { item.tabIndex = item === focused ? 0 : -1; });
  updateTreeSelectionStyle();
  if (restoreFocus && focused) focused.focus({ preventScroll: true });
}

function updateTreeSelectionStyle() {
  workspaceTree.querySelectorAll('[data-tree-item]').forEach((item) => {
    item.classList.toggle(
      'keyboard-selected',
      keyboardTreeSelection && item.dataset.treeKey === focusedTreeItemKey,
    );
  });
}

function configureTreeItem(element, { key, kind, label, activate, expand, collapse }) {
  element.dataset.treeItem = '';
  element.dataset.treeKey = key;
  element.dataset.treeKind = kind;
  element.setAttribute('role', 'treeitem');
  element.setAttribute('aria-label', label);
  element.tabIndex = -1;
  element._activateTreeItem = activate;
  element._expandTreeItem = expand;
  element._collapseTreeItem = collapse;
  element.addEventListener('focus', () => {
    focusedTreeItemKey = key;
    visibleTreeItems().forEach((item) => { item.tabIndex = item === element ? 0 : -1; });
    updateTreeSelectionStyle();
  });
}

function renderNode(node, parentPath, parentId, index) {
  return node.type === 'group'
    ? renderGroup(node, parentPath, parentId, index)
    : renderEntry(node, parentPath, parentId, index);
}

function configureDraggableHeader(header, node, expanded, controls) {
  header.draggable = true;
  header.dataset.dragHeader = '';
  header.setAttribute('aria-expanded', String(expanded));
  configureTreeItem(header, {
    key: `node:${node.id}`,
    kind: node.type,
    label: node.name,
    ...controls,
  });
}

function removeNodeDragPreview() {
  nodeDragPreview?.remove();
  nodeDragPreview = null;
}

function createNodeDragPreview(header, clientX, clientY) {
  removeNodeDragPreview();
  const rect = header.getBoundingClientRect();
  const preview = header.cloneNode(true);
  preview.classList.add('node-drag-preview');
  preview.removeAttribute('draggable');
  preview.removeAttribute('aria-label');
  preview.removeAttribute('data-drag-header');
  preview.setAttribute('aria-hidden', 'true');
  preview.querySelectorAll('.disclosure, .node-actions, .draft-actions').forEach((element) => element.remove());
  preview.querySelectorAll('[id]').forEach((element) => element.removeAttribute('id'));
  preview.style.width = `${rect.width}px`;
  preview.style.height = `${rect.height}px`;
  preview.style.background = getComputedStyle(header).background;
  const displayScale = Math.max(window.devicePixelRatio || 1, 1);
  preview.style.zoom = String(NODE_DRAG_PREVIEW_SCALE / displayScale);
  preview.style.opacity = String(NODE_DRAG_PREVIEW_OPACITY);
  const offsetX = Math.max(0, Math.min(rect.width, clientX - rect.left)) * NODE_DRAG_PREVIEW_SCALE;
  const offsetY = Math.max(0, Math.min(rect.height, clientY - rect.top)) * NODE_DRAG_PREVIEW_SCALE;
  preview.style.left = `${clientX - offsetX}px`;
  preview.style.top = `${clientY - offsetY}px`;
  document.body.append(preview);
  nodeDragPreview = preview;
  return { preview, offsetX, offsetY };
}

function renderGroup(group, parentPath, parentId, index) {
  const section = document.createElement('section');
  section.className = 'node group-node';
  section.dataset.nodeId = group.id;
  section.dataset.nodeType = 'group';
  section.dataset.parentId = parentId ?? '';
  section.dataset.index = String(index);
  section.classList.toggle('active-group', activeGroupId === group.id);

  const expanded = Boolean(searchQuery) || expandedGroupIds.has(group.id);
  section.classList.toggle('collapsed', !expanded);
  const header = document.createElement('header');
  header.className = 'group-header';
  const toggle = () => {
    if (protectInlineWork()) return;
    setActiveGroup(group.id);
    if (expandedGroupIds.has(group.id)) expandedGroupIds.delete(group.id);
    else expandedGroupIds.add(group.id);
    renderWorkspace();
  };
  configureDraggableHeader(header, group, expanded, {
    activate: toggle,
    expand: expanded ? null : toggle,
    collapse: expanded && !searchQuery ? toggle : null,
  });

  const disclosure = iconButton('chevron-down', `${expanded ? 'Collapse' : 'Expand'} ${group.name}`, () => {
    toggle();
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
  header.addEventListener('click', (event) => {
    if (event.target.closest('button, input, select, summary, details')) return;
    toggle();
  });

  const children = document.createElement('div');
  children.className = 'node-children';
  children.setAttribute('role', 'group');
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
  const expanded = expandedEntryIds.has(entry.id);
  const toggle = () => {
    if (protectInlineWork()) return;
    if (expandedEntryIds.has(entry.id)) expandedEntryIds.delete(entry.id);
    else expandedEntryIds.add(entry.id);
    renderWorkspace();
  };
  configureDraggableHeader(header, entry, expanded, {
    activate: toggle,
    expand: expanded ? null : toggle,
    collapse: expanded ? toggle : null,
  });
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
    toggle();
  });
  article.append(header);

  if (expanded) article.append(renderEntryFields(entry));
  return article;
}

function renderEntryFields(entry) {
  const fields = document.createElement('div');
  fields.className = 'entry-fields-view';
  fields.setAttribute('role', 'group');
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
    if (field.kind === 'ssh') {
      const summary = document.createElement('div');
      summary.className = 'field-value ssh-field-summary';
      configureTreeItem(summary, {
        key: `field:${entry.id}:${field.id}`,
        kind: 'field',
        label: `${field.label}, SSH connection`,
        activate: () => {
          const connect = row.querySelector('[data-ssh-field-id]');
          void connectViaSsh(entry, field, connect);
        },
      });
      const label = document.createElement('small');
      label.textContent = field.label;
      const connection = document.createElement('code');
      const port = field.ssh.port ? `:${field.ssh.port}` : '';
      connection.textContent = `${field.ssh.user}@${field.ssh.address}${port}`;
      const key = document.createElement('small');
      key.className = 'ssh-key-metadata';
      key.textContent = `${field.ssh.key.name} · ${field.ssh.key.algorithm} · ${field.ssh.key.fingerprint}`;
      summary.append(label, connection, key);
      const connect = iconButton('terminal', 'Connect via SSH', () => void connectViaSsh(entry, field, connect));
      connect.title = 'Connect via SSH';
      connect.dataset.sshEntryId = entry.id;
      connect.dataset.sshFieldId = field.id;
      row.append(summary, connect);
      fields.append(row);
      return;
    }
    const valueBox = document.createElement('button');
    valueBox.type = 'button';
    valueBox.className = 'field-value';
    valueBox.title = `${field.kind === 'url' ? 'Open' : 'Copy'} ${field.label}`;
    const activate = field.kind === 'url'
      ? () => void openFieldUrl(entry, field)
      : () => void copyEntryField(entry, field, valueBox);
    configureTreeItem(valueBox, {
      key: `field:${entry.id}:${field.id}`,
      kind: 'field',
      label: `${field.label}, ${field.kind === 'url' ? 'URL' : 'value'}`,
      activate,
    });
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
    valueBox.addEventListener('click', activate);
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

async function copyEntryField(entry, field, target) {
  await copyFieldValue({
    target,
    copy: () => invoke('copy_field', { entryId: entry.id, fieldId: field.id }),
    onSuccess: () => notify(`Copied. Clipboard will clear in ${appState.settings.clipboard_clear_seconds} seconds.`),
    onError: (error) => notify(String(error)),
  });
}

async function openFieldUrl(entry, field) {
  try {
    await invoke('open_url', { entryId: entry.id, fieldId: field.id });
    notify('Opened in the system browser.');
  } catch (error) {
    notify(String(error));
  }
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
  if (parentId) {
    expandedGroupIds.add(parentId);
    setActiveGroup(parentId);
  }
  renderWorkspace();
  let container = childrenContainer(parentId);
  if (!container && searchQuery) {
    searchQuery = '';
    document.querySelector('#search-input').value = '';
    renderWorkspace();
    container = childrenContainer(parentId);
  }
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
  header.draggable = true;
  header.dataset.draftDragHeader = '';
  header.setAttribute('aria-label', 'Drag new group to choose its parent');
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
  header.draggable = true;
  header.dataset.draftDragHeader = '';
  header.setAttribute('aria-label', 'Drag new entry to choose its group');
  const editor = createEntryEditor([{ id: null, label: '', value: '', kind: 'text', masked: false }]);
  const footer = editorFooter(article, editor, {
    cancelLabel: 'Cancel',
    saveLabel: 'Save entry',
    onCancel: () => article.remove(),
    onSave: () => void saveEntryDraft(article, editor),
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
  label.wrapper.className = 'field-label-input';
  const value = labeledInput('Value', field.masked ? 'password' : 'text', field.value ?? '', false);
  value.wrapper.className = 'generic-field-value';
  const kindLabel = document.createElement('label');
  kindLabel.className = 'field-kind-input';
  const kindText = document.createElement('small');
  kindText.textContent = 'Type';
  const kind = document.createElement('select');
  ['text', 'secret', 'url', 'ssh'].forEach((name) => {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name === 'ssh' ? 'SSH' : name[0].toUpperCase() + name.slice(1);
    kind.append(option);
  });
  kind.value = field.kind ?? 'text';
  kindLabel.append(kindText, kind);
  const ssh = createSshFieldInputs(field.ssh, row);
  let masked = Boolean(field.masked);
  const syncKind = () => {
    masked = kind.value === 'secret';
    value.input.type = masked ? 'password' : 'text';
    const isSsh = kind.value === 'ssh';
    row.classList.toggle('ssh-field-row', isSsh);
    value.wrapper.hidden = isSsh;
    ssh.wrapper.hidden = !isSsh;
  };
  kind.addEventListener('change', syncKind);
  const actions = document.createElement('div');
  actions.className = 'field-actions';
  actions.append(iconButton('x', 'Remove field', () => row.remove()));
  row.append(dragHandle, label.wrapper, value.wrapper, kindLabel, actions, ssh.wrapper);
  row._inputs = {
    label: label.input,
    value: value.input,
    kind,
    masked: () => masked,
    ssh,
  };
  syncKind();
  return row;
}

function createSshFieldInputs(connection, row) {
  const wrapper = document.createElement('div');
  wrapper.className = 'ssh-field-inputs';
  const user = labeledInput('User', 'text', connection?.user ?? '', true);
  const address = labeledInput('Address', 'text', connection?.address ?? '', true);
  const port = labeledInput('Port (optional)', 'number', connection?.port ?? '', false);
  port.input.min = '1';
  port.input.max = '65535';
  const keyWrapper = document.createElement('label');
  const keyLabel = document.createElement('small');
  keyLabel.textContent = 'SSH secret key';
  const key = document.createElement('select');
  key.className = 'ssh-key-select';
  key.dataset.selectedKeyId = connection?.key?.id ?? connection?.key_id ?? '';
  key.required = true;
  keyWrapper.append(keyLabel, key);
  const manage = document.createElement('button');
  manage.type = 'button';
  manage.className = 'button secondary compact-button manage-ssh-keys';
  manage.textContent = 'Manage keys';
  manage.addEventListener('click', () => openSshKeyManager(row));
  wrapper.append(user.wrapper, address.wrapper, port.wrapper, keyWrapper, manage);
  populateSshKeySelect(key, key.dataset.selectedKeyId);
  return { wrapper, user: user.input, address: address.input, port: port.input, key };
}

function populateSshKeySelect(select, selected = select.value) {
  select.replaceChildren();
  const keys = appState.current?.ssh_keys ?? [];
  if (!keys.length) {
    const option = document.createElement('option');
    option.value = '';
    option.textContent = 'Add an SSH key first';
    select.append(option);
    return;
  }
  keys.forEach((sshKey) => {
    const option = document.createElement('option');
    option.value = sshKey.id;
    option.textContent = `${sshKey.name} · ${sshKey.algorithm}`;
    select.append(option);
  });
  select.value = keys.some((sshKey) => sshKey.id === selected) ? selected : keys[0].id;
}

function syncSshKeySelects() {
  document.querySelectorAll('.ssh-key-select').forEach((select) => {
    populateSshKeySelect(select, select.value);
  });
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
  return [...editor.querySelectorAll('.field-editor-row')].map((row) => {
    const kind = row._inputs.kind.value;
    const port = row._inputs.ssh.port.value.trim();
    return {
      id: row.dataset.fieldId || null,
      label: row._inputs.label.value.trim(),
      value: kind === 'ssh' ? '' : row._inputs.value.value,
      kind,
      masked: kind === 'ssh' ? false : row._inputs.masked(),
      ssh: kind === 'ssh' ? {
        user: row._inputs.ssh.user.value.trim(),
        address: row._inputs.ssh.address.value.trim(),
        port: port ? Number(port) : null,
        key_id: row._inputs.ssh.key.value,
      } : null,
    };
  });
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
  const invalidSshField = fields.findIndex((field) => field.kind === 'ssh'
    && (!field.ssh.user || !field.ssh.address || !field.ssh.key_id
      || (field.ssh.port !== null && (!Number.isInteger(field.ssh.port) || field.ssh.port < 1 || field.ssh.port > 65535))));
  if (invalidSshField >= 0) {
    error.textContent = 'Every SSH field needs a user, address, valid optional port, and named key.';
    editor.querySelectorAll('.field-editor-row')[invalidSshField]._inputs.ssh.user.focus();
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

async function saveEntryDraft(draft, editor) {
  const data = validateInlineEntry(draft, editor);
  if (!data) return;
  setBusy(draft, true);
  try {
    appState.current = await invoke('add_entry', {
      parentId: draft.dataset.parentId || null,
      name: data.name,
      fields: data.fields,
    });
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
  if (!draggedNode && !draggedDraft) return false;
  const draggedElement = draggedDraft?.element
    ?? document.querySelector(`.node[data-node-id="${draggedNode.id}"]`);
  const hoveredHeader = event.target.closest('.group-header, .entry-header');
  const hoveredContainer = event.target.closest('[data-children]');
  const target = hoveredHeader?.closest('.node[data-node-id]') ?? null;
  clearNodeDropIndicators();
  if (target) {
    if (draggedNode && (target.dataset.nodeId === draggedNode.id || (draggedElement && draggedElement.contains(target)))) {
      return false;
    }
    if (draggedDraft) {
      if (target.dataset.nodeType !== 'group') return false;
      target.classList.add('drop-inside');
      nodeDrop = { mode: 'inside', target };
      return true;
    }
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

function updateEntryDraftPath(draft, parentId) {
  if (draft.dataset.nodeType !== 'entry') return;
  const nameEditor = draft.querySelector('.entry-name-editor');
  let path = nameEditor.querySelector('.entry-path');
  const parentPath = parentId
    ? allGroups(appState.current.nodes).find(({ node }) => node.id === parentId)?.path ?? ''
    : '';
  if (!parentPath) {
    path?.remove();
    return;
  }
  if (!path) {
    path = document.createElement('span');
    path.className = 'entry-path';
    nameEditor.prepend(path);
  }
  path.textContent = `${parentPath}.`;
}

function commitDraftDrop() {
  if (!draggedDraft || !nodeDrop) return;
  let container;
  if (nodeDrop.mode === 'inside') {
    container = [...nodeDrop.target.children].find((child) => child.matches('[data-children]'));
    nodeDrop.target.classList.remove('collapsed');
  } else if (nodeDrop.mode === 'container') {
    container = nodeDrop.container;
  }
  if (!container) return;
  const parentId = container.dataset.parentId || null;
  if (parentId) expandedGroupIds.add(parentId);
  setActiveGroup(parentId);
  draggedDraft.element.dataset.parentId = parentId ?? '';
  container.append(draggedDraft.element);
  updateEntryDraftPath(draggedDraft.element, parentId);
  draggedDraft.element.querySelector('[data-name-input]')?.focus();
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
  if (add) {
    const details = add.closest('details');
    if (details) details.open = false;
    createDraft(add.dataset.addKind, add.dataset.parentId || null);
    return;
  }
  const group = event.target.closest('.group-header')?.closest('.group-node[data-node-id]');
  if (group) {
    setActiveGroup(group.dataset.nodeId);
    return;
  }
  const activeGroup = [...workspaceTree.querySelectorAll('.group-node[data-node-id]')]
    .find((candidate) => candidate.dataset.nodeId === activeGroupId);
  if (activeGroup && !activeGroup.contains(event.target)) {
    setActiveGroup(null);
  }
});

document.querySelector('#root-add-menu').addEventListener('click', (event) => {
  const add = event.target.closest('[data-add-kind]');
  if (!add) return;
  event.currentTarget.open = false;
  createDraft(add.dataset.addKind, activeGroupId);
});

workspaceTree.addEventListener('dragstart', (event) => {
  if (draggedFieldRow) return;
  const draftHeader = event.target.closest('[data-draft-drag-header]');
  if (draftHeader) {
    if (event.target.closest('button, input, select, label, details, summary')) {
      event.preventDefault();
      return;
    }
    const draft = draftHeader.closest('.draft');
    draggedDraft = { element: draft, type: draft.dataset.nodeType };
    draft.classList.add('dragging');
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', `new-${draggedDraft.type}`);
    const { preview, offsetX, offsetY } = createNodeDragPreview(draftHeader, event.clientX, event.clientY);
    event.dataTransfer.setDragImage(preview, offsetX, offsetY);
    requestAnimationFrame(() => {
      if (nodeDragPreview === preview) removeNodeDragPreview();
    });
    return;
  }
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
  const { preview, offsetX, offsetY } = createNodeDragPreview(header, event.clientX, event.clientY);
  event.dataTransfer.setDragImage(preview, offsetX, offsetY);
  requestAnimationFrame(() => {
    if (nodeDragPreview === preview) removeNodeDragPreview();
  });
});

workspaceTree.addEventListener('dragover', (event) => {
  if ((!draggedNode && !draggedDraft) || !setNodeDrop(event)) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
});

workspaceTree.addEventListener('drop', (event) => {
  if ((!draggedNode && !draggedDraft) || !nodeDrop) return;
  event.preventDefault();
  if (draggedDraft) commitDraftDrop();
  else void commitNodeDrop();
  clearNodeDropIndicators();
});

workspaceTree.addEventListener('dragend', () => {
  workspaceTree.querySelector('.dragging')?.classList.remove('dragging');
  draggedNode = null;
  draggedDraft = null;
  removeNodeDragPreview();
  clearNodeDropIndicators();
});

workspaceTree.addEventListener('keydown', (event) => {
  const item = event.target.closest?.('[data-tree-item]');
  if (!item || event.target !== item) return;
  const items = visibleTreeItems();
  const index = items.indexOf(item);
  keyboardTreeSelection = true;
  updateTreeSelectionStyle();
  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
    event.preventDefault();
    const offset = event.key === 'ArrowUp' ? -1 : 1;
    const next = items[index + offset];
    if (next) next.focus();
    return;
  }
  if (event.key === 'ArrowRight' && item._expandTreeItem) {
    event.preventDefault();
    item._expandTreeItem();
    return;
  }
  if (event.key === 'ArrowLeft' && item._collapseTreeItem) {
    event.preventDefault();
    item._collapseTreeItem();
    return;
  }
  if (event.key === 'Enter' && item._activateTreeItem) {
    event.preventDefault();
    item._activateTreeItem();
  }
});

async function connectViaSsh(entry, field, button, passphrase = null) {
  button.disabled = true;
  try {
    await invoke('connect_ssh', { entryId: entry.id, fieldId: field.id, passphrase });
    button.title = 'SSH session active';
    notify(`SSH connection to ${field.ssh.user}@${field.ssh.address} started.`);
    return true;
  } catch (error) {
    if (passphrase === null && String(error).includes('SSH key passphrase is required')) {
      pendingSshConnection = { entry, field, button };
      const form = document.querySelector('#ssh-passphrase-form');
      form.reset();
      setFormError(form);
      dialogs.sshPassphrase.showModal();
      form.elements.passphrase.focus();
      return false;
    }
    notify(String(error));
    button.disabled = false;
    return false;
  }
}

document.querySelector('#ssh-passphrase-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  if (!pendingSshConnection) return;
  const launch = pendingSshConnection;
  const passphrase = form.elements.passphrase.value;
  setFormError(form);
  setBusy(form, true);
  try {
    await invoke('connect_ssh', {
      entryId: launch.entry.id,
      fieldId: launch.field.id,
      passphrase,
    });
    pendingSshConnection = null;
    dialogs.sshPassphrase.close();
    launch.button.title = 'SSH session active';
    notify(`SSH connection to ${launch.field.ssh.user}@${launch.field.ssh.address} started.`);
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    form.elements.passphrase.value = '';
    setBusy(form, false);
  }
});

dialogs.sshPassphrase.addEventListener('close', () => {
  document.querySelector('#ssh-passphrase-form').reset();
  if (pendingSshConnection) pendingSshConnection.button.disabled = false;
  pendingSshConnection = null;
});

function resetSshKeyForm() {
  const form = document.querySelector('#ssh-key-form');
  form.reset();
  form.elements.keyId.value = '';
  form.elements.privateKey.required = true;
  document.querySelector('#ssh-key-secret-hint').textContent = 'Paste an OpenSSH private key. Its contents stay encrypted inside this vault.';
  setFormError(form);
}

function editSshKey(sshKey) {
  const form = document.querySelector('#ssh-key-form');
  form.elements.keyId.value = sshKey.id;
  form.elements.name.value = sshKey.name;
  form.elements.privateKey.value = '';
  form.elements.privateKey.required = false;
  document.querySelector('#ssh-key-secret-hint').textContent = 'Leave the private key blank to keep the current encrypted value.';
  setFormError(form);
  form.elements.name.focus();
  form.elements.name.select();
}

function renderSshKeyList() {
  const list = document.querySelector('#ssh-key-list');
  list.replaceChildren();
  const keys = appState.current?.ssh_keys ?? [];
  if (!keys.length) {
    const empty = document.createElement('p');
    empty.className = 'muted ssh-key-list-empty';
    empty.textContent = 'No reusable SSH keys yet.';
    list.append(empty);
    return;
  }
  keys.forEach((sshKey) => {
    const item = document.createElement('div');
    item.className = 'ssh-key-item';
    const copy = document.createElement('span');
    copy.className = 'ssh-key-item-copy';
    const name = document.createElement('strong');
    name.textContent = sshKey.name;
    const metadata = document.createElement('small');
    metadata.textContent = `${sshKey.algorithm} · ${sshKey.fingerprint}${sshKey.encrypted ? ' · encrypted' : ''}`;
    copy.append(name, metadata);
    const actions = document.createElement('span');
    actions.className = 'ssh-key-item-actions';
    actions.append(
      iconButton('pencil', `Edit ${sshKey.name}`, () => editSshKey(sshKey)),
      iconButton('trash', `Delete ${sshKey.name}`, async () => {
        if (!window.confirm(`Delete SSH key “${sshKey.name}”?`)) return;
        try {
          appState.current = await invoke('delete_ssh_key', { keyId: sshKey.id });
          renderSshKeyList();
          syncSshKeySelects();
          resetSshKeyForm();
        } catch (error) {
          setFormError(document.querySelector('#ssh-key-form'), String(error));
        }
      }),
    );
    item.append(copy, actions);
    list.append(item);
  });
}

function openSshKeyManager(targetRow = null) {
  sshKeyTargetRow = targetRow;
  resetSshKeyForm();
  renderSshKeyList();
  dialogs.sshKey.showModal();
  document.querySelector('#ssh-key-form').elements.name.focus();
}

document.querySelector('#ssh-key-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  const keyId = data.get('keyId');
  const privateKey = data.get('privateKey');
  if (!keyId && !privateKey.trim()) {
    setFormError(form, 'Private key is required.');
    form.elements.privateKey.focus();
    return;
  }
  const existingIds = new Set((appState.current?.ssh_keys ?? []).map((key) => key.id));
  setFormError(form);
  setBusy(form, true);
  try {
    appState.current = keyId
      ? await invoke('update_ssh_key', { keyId, name: data.get('name'), privateKey: privateKey.trim() || null })
      : await invoke('add_ssh_key', { name: data.get('name'), privateKey });
    const added = appState.current.ssh_keys.find((key) => !existingIds.has(key.id));
    syncSshKeySelects();
    if (added && sshKeyTargetRow?.isConnected) {
      sshKeyTargetRow._inputs.ssh.key.value = added.id;
    }
    renderSshKeyList();
    resetSshKeyForm();
    notify(keyId ? 'SSH key updated.' : 'SSH key added.');
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    form.elements.privateKey.value = '';
    setBusy(form, false);
  }
});

document.querySelector('#reset-ssh-key-form').addEventListener('click', resetSshKeyForm);
dialogs.sshKey.addEventListener('close', () => {
  sshKeyTargetRow = null;
  resetSshKeyForm();
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
document.addEventListener('pointerdown', () => {
  keyboardTreeSelection = false;
  document.activeElement?.closest?.('[data-tree-item]')?.blur();
  updateTreeSelectionStyle();
}, { passive: true });
document.addEventListener('keydown', (event) => {
  if (event.key === 'Tab') keyboardTreeSelection = true;
});

await listen('vault-locked', () => {
  enterLockedState();
  notify('Vault locked.');
});

await listen('ssh-session-ended', ({ payload }) => {
  const button = [...workspaceTree.querySelectorAll('[data-ssh-entry-id]')].find(
    (candidate) => candidate.dataset.sshEntryId === payload.entryId
      && candidate.dataset.sshFieldId === payload.fieldId,
  );
  if (!button) return;
  button.disabled = false;
  button.title = 'Connect via SSH';
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
