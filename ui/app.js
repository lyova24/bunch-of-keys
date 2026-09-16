const invoke = window.__TAURI__.core.invoke;
const listen = window.__TAURI__.event.listen;

const views = {
  loading: document.querySelector('#loading-view'),
  setup: document.querySelector('#setup-view'),
  unlock: document.querySelector('#unlock-view'),
  vault: document.querySelector('#vault-view'),
};

const dialogs = {
  vault: document.querySelector('#vault-dialog'),
  group: document.querySelector('#group-dialog'),
  entry: document.querySelector('#entry-dialog'),
  settings: document.querySelector('#settings-dialog'),
};

let appState = {
  vaults: [],
  settings: { autostart: false, auto_lock_seconds: 300, clipboard_clear_seconds: 30 },
  current: null,
};
let selectedGroupId = null;
let searchQuery = '';
let autoLockTimer = null;
let toastTimer = null;
const revealedFields = new Map();

function showView(name) {
  Object.entries(views).forEach(([key, element]) => {
    element.hidden = key !== name;
  });
}

function setBusy(form, busy) {
  form.querySelectorAll('button, input, select').forEach((element) => {
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
  if (appState.vaults.some((vault) => vault.id === previous)) {
    select.value = previous;
  }
}

function enterLockedState() {
  appState.current = null;
  selectedGroupId = null;
  revealedFields.clear();
  clearTimeout(autoLockTimer);
  document.querySelector('#entry-list').replaceChildren();
  document.querySelector('#group-tree').replaceChildren();
  document.querySelector('#field-editor').replaceChildren();
  document.querySelector('#search-input').value = '';
  Object.values(dialogs).forEach((dialog) => {
    if (dialog.open) dialog.close();
  });
  updateVaultSelect();
  showView(appState.vaults.length ? 'unlock' : 'setup');
  const password = document.querySelector('#unlock-form input[name="password"]');
  password.value = '';
  if (appState.vaults.length) password.focus();
}

function enterVault(vault) {
  appState.current = vault;
  selectedGroupId = null;
  searchQuery = '';
  revealedFields.clear();
  document.querySelector('#search-input').value = '';
  document.querySelector('#current-vault-name').textContent = selectedVaultName();
  showView('vault');
  renderVault();
  scheduleAutoLock();
}

function scheduleAutoLock() {
  clearTimeout(autoLockTimer);
  if (!appState.current) return;
  autoLockTimer = setTimeout(async () => {
    await invoke('lock_vault');
  }, appState.settings.auto_lock_seconds * 1000);
}

function activity() {
  if (appState.current) scheduleAutoLock();
}

function allEntries(nodes, output = []) {
  nodes.forEach((node) => {
    if (node.type === 'entry') output.push(node);
    if (node.type === 'group') allEntries(node.children, output);
  });
  return output;
}

function allGroups(nodes, output = [], prefix = '') {
  nodes.forEach((node) => {
    if (node.type !== 'group') return;
    const path = prefix ? `${prefix} / ${node.name}` : node.name;
    output.push({ id: node.id, name: node.name, path, node });
    allGroups(node.children, output, path);
  });
  return output;
}

function findGroup(id) {
  return allGroups(appState.current?.nodes ?? []).find((group) => group.id === id)?.node ?? null;
}

function findEntry(id) {
  return allEntries(appState.current?.nodes ?? []).find((entry) => entry.id === id) ?? null;
}

function entriesForCurrentSelection() {
  const source = selectedGroupId ? findGroup(selectedGroupId)?.children ?? [] : appState.current.nodes;
  let entries = allEntries(source, []);
  if (searchQuery) {
    entries = entries.filter((entry) => {
      const searchable = [
        entry.name,
        ...entry.fields.flatMap((field) => [field.label, field.value ?? '']),
      ].join('\n').toLowerCase();
      return searchable.includes(searchQuery);
    });
  }
  return entries;
}

function renderVault() {
  if (!appState.current) return;
  const entries = allEntries(appState.current.nodes, []);
  document.querySelector('#entry-count').textContent = String(entries.length);
  renderTree();
  renderEntries();
}

function renderTree() {
  const tree = document.querySelector('#group-tree');
  tree.replaceChildren();
  appState.current.nodes
    .filter((node) => node.type === 'group')
    .forEach((group) => tree.append(renderGroup(group)));
  document.querySelector('#all-entries-button').classList.toggle('selected', selectedGroupId === null);
}

function renderGroup(group) {
  const container = document.createElement('div');
  const row = document.createElement('div');
  row.className = 'tree-row';
  row.classList.toggle('selected', group.id === selectedGroupId);

  const name = document.createElement('button');
  name.type = 'button';
  name.className = 'tree-name';
  name.textContent = group.name;
  name.addEventListener('click', () => {
    selectedGroupId = group.id;
    renderVault();
  });

  const edit = document.createElement('button');
  edit.type = 'button';
  edit.className = 'tree-action';
  edit.textContent = '✎';
  edit.setAttribute('aria-label', `Rename ${group.name}`);
  edit.addEventListener('click', () => openGroupDialog(group));

  const remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'tree-action';
  remove.textContent = '×';
  remove.setAttribute('aria-label', `Delete ${group.name}`);
  remove.addEventListener('click', () => deleteNode(group));

  row.append(name, edit, remove);
  container.append(row);
  const childGroups = group.children.filter((node) => node.type === 'group');
  if (childGroups.length) {
    const children = document.createElement('div');
    children.className = 'tree-children';
    childGroups.forEach((child) => children.append(renderGroup(child)));
    container.append(children);
  }
  return container;
}

function renderEntries() {
  const entries = entriesForCurrentSelection();
  const list = document.querySelector('#entry-list');
  list.replaceChildren();
  entries.forEach((entry) => list.append(renderEntry(entry)));
  document.querySelector('#empty-state').hidden = entries.length > 0;

  const group = selectedGroupId ? findGroup(selectedGroupId) : null;
  document.querySelector('#content-title').textContent = group?.name ?? 'All entries';
  const suffix = searchQuery ? ' matching the search' : '';
  document.querySelector('#content-subtitle').textContent = `${entries.length} ${entries.length === 1 ? 'entry' : 'entries'}${suffix}`;
}

function renderEntry(entry) {
  const card = document.createElement('article');
  card.className = 'entry-card';

  const header = document.createElement('div');
  header.className = 'entry-header';
  const symbol = document.createElement('div');
  symbol.className = 'entry-symbol';
  symbol.textContent = '⌁';
  const title = document.createElement('div');
  title.className = 'entry-title';
  title.textContent = entry.name;
  const edit = actionButton('✎', `Edit ${entry.name}`, () => openEntryDialog(entry));
  const remove = actionButton('×', `Delete ${entry.name}`, () => deleteNode(entry));
  header.append(symbol, title, edit, remove);
  card.append(header);

  entry.fields.forEach((field) => {
    const row = document.createElement('div');
    row.className = 'field-row';
    const valueBox = document.createElement('div');
    valueBox.className = 'field-value';
    const label = document.createElement('span');
    label.textContent = field.label;
    const value = document.createElement('code');
    const revealKey = `${entry.id}:${field.id}`;
    const revealed = revealedFields.get(revealKey);
    value.textContent = field.masked ? (revealed ?? '••••••••••••••••') : (field.value || '—');
    value.classList.toggle('masked-value', field.masked && !revealed);
    valueBox.append(label, value);
    row.append(valueBox);

    if (field.masked) {
      row.append(actionButton(revealed ? '◉' : '◎', revealed ? 'Hide value' : 'Reveal value', async () => {
        if (revealedFields.has(revealKey)) {
          revealedFields.delete(revealKey);
        } else {
          try {
            const secret = await invoke('reveal_field', { entryId: entry.id, fieldId: field.id });
            revealedFields.set(revealKey, secret);
          } catch (error) {
            notify(String(error));
          }
        }
        renderEntries();
      }));
    }
    row.append(actionButton('⧉', `Copy ${field.label}`, async () => {
      try {
        await invoke('copy_field', { entryId: entry.id, fieldId: field.id });
        notify(`Copied. Clipboard will clear in ${appState.settings.clipboard_clear_seconds} seconds.`);
      } catch (error) {
        notify(String(error));
      }
    }));
    card.append(row);
  });
  return card;
}

function actionButton(text, label, handler) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'entry-action';
  button.textContent = text;
  button.setAttribute('aria-label', label);
  button.addEventListener('click', handler);
  return button;
}

function fillGroupSelect(select, selectedId = null) {
  select.replaceChildren();
  const root = document.createElement('option');
  root.value = '';
  root.textContent = 'Vault root';
  select.append(root);
  allGroups(appState.current?.nodes ?? []).forEach((group) => {
    const option = document.createElement('option');
    option.value = group.id;
    option.textContent = group.path;
    select.append(option);
  });
  select.value = selectedId ?? '';
}

function openGroupDialog(group = null) {
  const form = document.querySelector('#group-form');
  form.reset();
  setFormError(form);
  form.elements.nodeId.value = group?.id ?? '';
  form.elements.name.value = group?.name ?? '';
  document.querySelector('#group-dialog-title').textContent = group ? 'Rename group' : 'New group';
  document.querySelector('#group-parent-label').hidden = Boolean(group);
  fillGroupSelect(form.elements.parentId, selectedGroupId);
  dialogs.group.showModal();
  form.elements.name.focus();
}

async function openEntryDialog(entry = null) {
  const form = document.querySelector('#entry-form');
  form.reset();
  setFormError(form);
  form.elements.entryId.value = entry?.id ?? '';
  form.elements.name.value = entry?.name ?? '';
  document.querySelector('#entry-dialog-title').textContent = entry ? 'Edit entry' : 'New entry';
  document.querySelector('#entry-parent-label').hidden = Boolean(entry);
  fillGroupSelect(form.elements.parentId, selectedGroupId);
  const editor = document.querySelector('#field-editor');
  editor.replaceChildren();

  if (entry) {
    setBusy(form, true);
    try {
      const fields = await Promise.all(entry.fields.map(async (field) => ({
        ...field,
        value: field.masked
          ? await invoke('reveal_field', { entryId: entry.id, fieldId: field.id })
          : field.value,
      })));
      fields.forEach((field) => addFieldEditorRow(field));
    } catch (error) {
      notify(String(error));
      return;
    } finally {
      setBusy(form, false);
    }
  } else {
    addFieldEditorRow({ label: 'Username', value: '', kind: 'text', masked: false });
    addFieldEditorRow({ label: 'Password', value: '', kind: 'secret', masked: true });
  }
  dialogs.entry.showModal();
  form.elements.name.focus();
}

function addFieldEditorRow(field = {}) {
  const row = document.createElement('div');
  row.className = 'field-editor-row';
  row.dataset.fieldId = field.id ?? '';

  const label = labeledInput('Label', 'text', field.label ?? '');
  const value = labeledInput('Value', field.masked ? 'password' : 'text', field.value ?? '');
  const kindLabel = document.createElement('label');
  kindLabel.textContent = 'Type';
  const kind = document.createElement('select');
  ['text', 'secret', 'url', 'note'].forEach((name) => {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name[0].toUpperCase() + name.slice(1);
    kind.append(option);
  });
  kind.value = field.kind ?? 'text';
  kindLabel.append(kind);

  const masked = document.createElement('label');
  masked.className = 'compact-check';
  const checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  checkbox.checked = Boolean(field.masked);
  const maskedText = document.createElement('span');
  maskedText.textContent = 'Mask';
  masked.append(checkbox, maskedText);
  checkbox.addEventListener('change', () => {
    value.input.type = checkbox.checked ? 'password' : 'text';
    if (checkbox.checked && kind.value === 'text') kind.value = 'secret';
  });

  const remove = actionButton('×', 'Remove field', () => row.remove());
  row.append(label.wrapper, value.wrapper, kindLabel, masked, remove);
  row._inputs = { label: label.input, value: value.input, kind, masked: checkbox };
  document.querySelector('#field-editor').append(row);
}

function labeledInput(text, type, value) {
  const wrapper = document.createElement('label');
  wrapper.textContent = text;
  const input = document.createElement('input');
  input.type = type;
  input.value = value;
  input.required = true;
  wrapper.append(input);
  return { wrapper, input };
}

function readFieldEditor() {
  return [...document.querySelectorAll('.field-editor-row')].map((row) => ({
    id: row.dataset.fieldId || null,
    label: row._inputs.label.value,
    value: row._inputs.value.value,
    kind: row._inputs.kind.value,
    masked: row._inputs.masked.checked,
  }));
}

async function deleteNode(node) {
  const kind = node.type === 'group' ? 'group and everything inside it' : 'entry';
  if (!window.confirm(`Delete the ${kind} “${node.name}”? This cannot be undone.`)) return;
  try {
    appState.current = await invoke('delete_node', { nodeId: node.id });
    if (node.id === selectedGroupId) selectedGroupId = null;
    renderVault();
  } catch (error) {
    notify(String(error));
  }
}

async function submitCreateVault(form) {
  setFormError(form);
  const data = new FormData(form);
  if (data.get('password') !== data.get('confirmPassword')) {
    setFormError(form, 'Passwords do not match.');
    return;
  }
  setBusy(form, true);
  try {
    const vault = await invoke('create_vault', {
      name: data.get('name'),
      password: data.get('password'),
    });
    const snapshot = await invoke('bootstrap');
    appState = snapshot;
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
  submitCreateVault(event.currentTarget);
});

document.querySelector('#vault-form').addEventListener('submit', (event) => {
  event.preventDefault();
  submitCreateVault(event.currentTarget);
});

document.querySelector('#unlock-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  setFormError(form);
  setBusy(form, true);
  try {
    const vault = await invoke('unlock_vault', {
      vaultId: data.get('vaultId'),
      password: data.get('password'),
    });
    form.elements.password.value = '';
    enterVault(vault);
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    setBusy(form, false);
  }
});

document.querySelector('#group-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  setFormError(form);
  setBusy(form, true);
  try {
    appState.current = data.get('nodeId')
      ? await invoke('rename_node', { nodeId: data.get('nodeId'), name: data.get('name') })
      : await invoke('add_group', { parentId: data.get('parentId') || null, name: data.get('name') });
    dialogs.group.close();
    renderVault();
  } catch (error) {
    setFormError(form, String(error));
  } finally {
    setBusy(form, false);
  }
});

document.querySelector('#entry-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const data = new FormData(form);
  const fields = readFieldEditor();
  if (!fields.length) {
    setFormError(form, 'Add at least one field.');
    return;
  }
  setFormError(form);
  setBusy(form, true);
  try {
    appState.current = data.get('entryId')
      ? await invoke('update_entry', { entryId: data.get('entryId'), name: data.get('name'), fields })
      : await invoke('add_entry', {
          parentId: data.get('parentId') || null,
          name: data.get('name'),
          fields,
        });
    dialogs.entry.close();
    renderVault();
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
  if (!file) return;
  if (!window.confirm(`Import entries from “${file.name}” into this vault?`)) return;
  try {
    const source = await file.text();
    appState.current = await invoke('import_yaml_file', { source });
    renderVault();
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
document.querySelector('#open-new-vault').addEventListener('click', () => dialogs.vault.showModal());
document.querySelector('#new-group-button').addEventListener('click', () => openGroupDialog());
document.querySelector('#new-entry-button').addEventListener('click', () => openEntryDialog());
document.querySelector('#add-field-button').addEventListener('click', () => addFieldEditorRow());
document.querySelector('#all-entries-button').addEventListener('click', () => {
  selectedGroupId = null;
  renderVault();
});
document.querySelector('#search-input').addEventListener('input', (event) => {
  searchQuery = event.currentTarget.value.trim().toLowerCase();
  renderEntries();
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
  if (appState.current) {
    enterVault(appState.current);
  } else {
    enterLockedState();
  }
} catch (error) {
  showView('loading');
  document.querySelector('#loading-view p').textContent = `Cannot start: ${String(error)}`;
}
