export const THEME_STORAGE_KEY = 'bunch-of-keys-theme';
export const THEME_MODES = Object.freeze(['system', 'light', 'dark']);

const THEME_LABELS = Object.freeze({
  system: 'System',
  light: 'Light',
  dark: 'Dark',
});

export function normalizeThemeMode(value) {
  return THEME_MODES.includes(value) ? value : 'system';
}

export function resolveThemeMode(mode, prefersDark) {
  return mode === 'system' ? (prefersDark ? 'dark' : 'light') : mode;
}

function storedThemeMode(storage) {
  try {
    return normalizeThemeMode(storage?.getItem(THEME_STORAGE_KEY));
  } catch (_) {
    return 'system';
  }
}

function persistThemeMode(storage, mode) {
  try {
    storage?.setItem(THEME_STORAGE_KEY, mode);
  } catch (_) {
    // Theme persistence is best-effort in restricted webviews.
  }
}

export function createThemeController({ root, trigger, options, mediaQuery, storage }) {
  let mode = storedThemeMode(storage);
  const control = trigger.closest('details');

  function syncExpandedState() {
    trigger.setAttribute('aria-expanded', String(Boolean(control?.open)));
  }

  function render() {
    const resolved = resolveThemeMode(mode, Boolean(mediaQuery?.matches));
    root.dataset.themeMode = mode;
    root.dataset.theme = resolved;
    trigger.dataset.themeMode = mode;
    const label = mode === 'system'
      ? `Theme: System (currently ${resolved})`
      : `Theme: ${THEME_LABELS[mode]}`;
    trigger.setAttribute('aria-label', label);
    trigger.title = label;
    options.forEach((option) => {
      option.setAttribute('aria-checked', String(option.dataset.themeMode === mode));
    });
  }

  function select(nextMode) {
    mode = normalizeThemeMode(nextMode);
    persistThemeMode(storage, mode);
    render();
  }

  options.forEach((option) => {
    option.addEventListener('click', () => {
      select(option.dataset.themeMode);
      if (control) control.open = false;
      syncExpandedState();
    });
  });

  control?.addEventListener('toggle', syncExpandedState);

  const handleSystemChange = () => {
    if (mode === 'system') render();
  };
  if (typeof mediaQuery?.addEventListener === 'function') {
    mediaQuery.addEventListener('change', handleSystemChange);
  } else if (typeof mediaQuery?.addListener === 'function') {
    mediaQuery.addListener(handleSystemChange);
  }

  select(mode);
  syncExpandedState();

  return {
    get mode() { return mode; },
    get resolvedTheme() { return resolveThemeMode(mode, Boolean(mediaQuery?.matches)); },
    select,
  };
}
