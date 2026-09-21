# bunch-of-keys

`bunch-of-keys` is a Linux-first desktop application for keeping structured
credential collections encrypted on the local machine. The current release is
**1.5.1**.

The application is intentionally local-only: it has no cloud sync, remote web
interface, telemetry, account requirement, or password-recovery service.

## Core features

- Multiple independent encrypted vaults protected by separate master
  passwords.
- A recursive tree of groups and entries with inline editing, search, and
  direct drag-and-drop reordering.
- Masked secrets, explicit reveal controls, click-to-copy values, system
  browser URL opening, and secure SSH launching.
- Full mouse and keyboard navigation across groups, entries, and fields.
- Reorderable `Text`, `Secret`, `URL`, and structured `SSH` fields.
- Reusable named OpenSSH private keys stored only inside the encrypted vault.
- YAML import with automatic secret and URL detection.
- Configurable inactivity locking, conditional clipboard clearing, autostart,
  and automatic locking on supported Linux screen-lock and suspend signals.
- System-following, light, and dark themes; tray operation; and a compact,
  frameless window.

## Why use it

- **Local by design.** Vault contents never require an external service or
  network account.
- **Safe desktop actions.** Copying is handled by the Rust backend, clipboard
  clearing is conditional, URLs use validated HTTP(S) destinations, and SSH
  private keys stay out of files, command lines, terminals, and the clipboard.
- **Encrypted beyond individual values.** Group names, entry names, field
  labels, values, and reusable SSH keys are all part of the encrypted vault.
- **Fast for nested collections.** Groups, inline editing, drag-and-drop, and
  keyboard control keep large credential trees practical without modal-heavy
  workflows.
- **Transparent and portable.** The on-disk format, security boundaries, build
  process, and Linux integration are documented and independently testable.

## Documentation

- [User guide](docs/USER_GUIDE.md) — vaults, tree navigation, field actions,
  settings, import, desktop behavior, and data locations.
- [SSH key design](docs/SSH_KEYS_V2.md) — reusable keys, the ephemeral agent,
  terminal launch, and security properties.
- [Security policy and threat model](SECURITY.md) — cryptography, runtime
  handling, limitations, and reporting guidance.
- [Architecture](docs/ARCHITECTURE.md) — components, encrypted storage,
  transactional updates, and the UI trust boundary.
- [Development and packaging](docs/DEVELOPMENT.md) — dependencies, checks,
  local development, and Debian builds.
- [Changelog](CHANGELOG.md) — release-by-release changes.
