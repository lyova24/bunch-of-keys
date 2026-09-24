const ICONS = Object.freeze({
  'key-round': '<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l1.4-1.4a1 1 0 0 0 0-1.4l-2.3-2.3"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>',
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
  'folder-plus': '<path d="M12 10v6M9 13h6"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  'file-plus': '<path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><path d="M12 18v-6M9 15h6"/>',
  'chevron-down': '<path d="m6 9 6 6 6-6"/>',
  pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v5M14 11v5"/>',
  eye: '<path d="M2.06 12.35a1 1 0 0 1 0-.7C3.73 7.9 7.1 5.5 12 5.5s8.27 2.4 9.94 6.15a1 1 0 0 1 0 .7C20.27 16.1 16.9 18.5 12 18.5s-8.27-2.4-9.94-6.15Z"/><circle cx="12" cy="12" r="3"/>',
  'eye-off': '<path d="m2 2 20 20M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 4.24A9.8 9.8 0 0 1 12 4c5 0 8.27 2.4 9.94 6.15a1 1 0 0 1 0 .7 11.8 11.8 0 0 1-2.17 3.2M6.61 6.61a11.7 11.7 0 0 0-4.55 5.04 1 1 0 0 0 0 .7C3.73 16.1 7 18.5 12 18.5c1.15 0 2.2-.13 3.16-.37"/>',
  check: '<path d="m20 6-11 11-5-5"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
  terminal: '<path d="m4 17 6-6-6-6M12 19h8"/>',
  grip: '<circle cx="9" cy="5" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="5" r="1" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="9" cy="19" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="19" r="1" fill="currentColor" stroke="none"/>',
});

export function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.classList.add('icon');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = ICONS[name] ?? '';
  return svg;
}

export function hydrateIcons(scope = document) {
  scope.querySelectorAll('[data-icon]').forEach((slot) => {
    slot.replaceChildren(icon(slot.dataset.icon));
  });
}

export function iconButton(name, label, handler, className = 'icon-button') {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = className;
  button.setAttribute('aria-label', label);
  button.append(icon(name));
  if (handler) button.addEventListener('click', handler);
  return button;
}

export function compactButton(text, handler, primary = false) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `button compact-button ${primary ? 'primary' : 'secondary'}`;
  button.textContent = text;
  button.addEventListener('click', handler);
  return button;
}

export function labeledInput(text, type, value, required) {
  const wrapper = document.createElement('label');
  const label = document.createElement('small');
  label.className = 'field-label-text';
  label.textContent = text;
  const input = document.createElement('input');
  input.type = type;
  input.value = value;
  input.required = required;
  wrapper.append(label, input);
  return { wrapper, input };
}

export function setBusy(container, busy) {
  container.toggleAttribute('aria-busy', busy);
  container.querySelectorAll('button, input, select, textarea').forEach((element) => {
    element.disabled = busy;
  });
}

export function setFormError(form, message = '') {
  const error = form.querySelector('.form-error');
  error.textContent = message;
  form.classList.toggle('has-error', Boolean(message));
}
