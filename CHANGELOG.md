# Changelog

## 2.2.1 - 2026-10-15

- Enable arrow-key navigation immediately after opening or unlocking a vault,
  while leaving the tree unselected until the first navigation action (#46).
- Retry initial focus when the outline actually joins its window; preserve
  search, editor and dialog focus and handle empty trees without selecting rows.

## 2.2.0 - 2026-10-15

- Add authenticated in-app updates with Sparkle, manual menu checks, automatic
  check preferences, release notes, download progress and recoverable errors (#43).
- Protect open editors and unsaved Settings before quitting or updating, and
  lock the vault and stop the service before restart.
- Publish signed architecture-specific update archives and feeds alongside
  recovery DMGs; require Ed25519 authentication even for ad-hoc builds.

## 2.1.1 - 2026-10-14

- Add a reproducible Diplodoc documentation site with navigation, local search,
  pull request checks, and GitHub Pages publishing (#44).
- Illustrate the user and SSH guides with native application screenshots using
  synthetic data, including theme settings; document isolated demo preparation.
- Preserve the Markdown sources and reuse the root security policy, changelog,
  and logo assets during the site build.
- Complete the Keepy rename across application identity, executables, native
  sources, runtime paths and documentation (#9).
- Move existing Application Support data and backups to Keepy automatically,
  preserving encrypted vaults and settings with guarded migration.
- Migrate system preferences and caches to the new bundle identity and show
  the actual installed version in Settings. Re-register an enabled login item
  under the Keepy identity and explain startup migration failures.

## 2.1.0 - 2026-10-14

- Renamed the application to Keepy with a thin green/blue wordmark and a
  matching vector keyring on a shared ring, reused in the application icon, menu bar, authentication
  and empty workspace. Generate all icon sizes from the same native path (#9).
- Preserve existing vaults, encryption, storage locations and application
  identity during the rename. Native bundles and DMGs now use the Keepy name.

## 2.0.1 - 2026-10-13

- Added macOS-style colored tags for groups and entries, with visible tag
  indicators, tag editing, and filtering combined with text search (#41).
- Keep ancestor groups visible around matches and show descendants of a tagged
  group; tags stay encrypted, survive edits and moves, and older vaults open
  with no tags. Clear temporary filters when locking or switching vaults.
- Added keyboard access to tag filtering: Shift-Tab opens the popover, arrow
  keys navigate colors, Return toggles tags, and Escape restores the opener's
  focus.
- Aligned tag markers to a consistent right margin across nesting depths,
  window resizing, and scrollbar changes.

## 2.0.0 - 2026-10-09

- Replaced Tauri and the web interface with a native SwiftUI/AppKit macOS
  application, standard window controls, and one compact tree for groups,
  entries, fields and inline editors. Added native menus, settings, file panels,
  a single toolbar creation menu, and direct tree and field drag-and-drop.
- Added optional native Liquid Glass on macOS 26 and later, with system,
  light, and dark appearance and accessibility-aware rendering.
- Applied the Liquid Glass preference to the entire main and Settings windows,
  including their title bars, with native behind-window blur and an opaque
  fallback when disabled or Reduce Transparency is enabled.
- Preserved encrypted vault compatibility, multiple vaults, structured fields,
  YAML import, reusable SSH keys, and the in-memory SSH agent.
- Added native clipboard ownership checks, sleep/session locking, and login
  items through ServiceManagement. Removed Linux and Windows support and
  replaced packaging and CI with macOS-only builds. Requires macOS 14+.

## 1.7.1 - 2026-09-29

- Fixed ephemeral SSH agent startup with long macOS temporary paths by using
  a short private session directory when the Unix socket path would be too long.
- Added regression coverage for long runtime paths, socket permissions, and cleanup.

## 1.7.0 - 2026-09-29

- Added macOS support with native application and DMG bundles, browser and
  Terminal integration, macOS runtime storage for ephemeral SSH agents, and a
  manual Intel and Apple Silicon package workflow.
- Kept Linux-only D-Bus monitoring and dependencies isolated from macOS builds
  while preserving the existing Debian package.
- Documented macOS installation for both architectures, checksum verification,
  the unsigned-build warning, scoped Gatekeeper overrides, updates, data
  retention, and uninstall behavior.

## 1.6.1 - 2026-09-24

- Indented entry containers alongside nested groups and applied the same
  container offset to credentials so parent-child relationships are clear.

## 1.6.0 - 2026-09-24

- Enabled immediate vault-tree keyboard navigation without an initial click
  and made Left Arrow move from child content to its containing group or entry
  before a repeated press collapses it; the active row now uses a compact blue
  indicator on its left edge instead of a surrounding focus frame.

## 1.5.2 - 2026-09-24

- Disabled text selection throughout the non-editable application interface
  while preserving normal selection inside text inputs and text areas.

## 1.5.1 - 2026-09-21

- Added change-aware CI that skips native builds for documentation-only
  updates, caches Cargo artifacts, and runs locked Rust and UI checks.
- Added weekly and dependency-change security checks with RustSec auditing,
  license and source policy enforcement, and grouped Dependabot updates.
- Added synchronized version validation and a manual Debian artifact build
  without automatic releases, tags, or package signing.

## 1.5.0 - 2026-09-21

- Added click-to-toggle group headers and accessible keyboard navigation across
  visible groups, entries, and expanded fields, including copy, browser, and
  SSH field activation.

## 1.4.0 - 2026-09-21

- Added secure SSH connection launching in the system terminal through a
  per-connection, owner-only, in-memory SSH agent with direct argument passing,
  encrypted-key passphrase prompts, bounded lifetime, lock/exit cleanup, and
  persistent failure output so connection errors remain visible; connection
  controls now return to their ready state when the terminal closes, and the
  selected agent key is used consistently across hosts regardless of SSH
  configuration-specific `IdentityFile` rules.

## 1.3.0 - 2026-09-21

- Added structured SSH connection fields and reusable named OpenSSH private
  keys with encrypted vault storage, safe metadata-only frontend views,
  reference-preserving rename and replacement, guarded deletion, validation,
  and backward-compatible schema migration.

## 1.2.1 - 2026-09-21

- Removed the large standalone logo from the unlock screen and tightened the
  heading spacing while preserving the window-header branding.

## 1.2.0 - 2026-09-20

- Added System, Light, and Dark appearance modes, persisted the selected mode,
  followed live operating-system appearance changes in System mode, and kept
  existing explicit Light and Dark preferences compatible.

## 1.1.7 - 2026-09-20

- Reflowed group and entry editors at compact window sizes so names, fields,
  status badges, drag controls, and actions remain readable without overflow,
  allowed unsaved drafts to be dragged directly into their target group, and
  made the last opened or clicked group the default destination for new drafts
  until the user clicks outside that group and its entries.

## 1.1.6 - 2026-09-20

- Replaced oversized group and entry drag snapshots with header-only previews
  that preserve the row width at 105% of its original size across display
  scaling levels and retain translucent drag feedback.

## 1.1.5 - 2026-09-20

- Removed the duplicate Note field type while transparently loading legacy
  Note fields as Text without changing their labels or values.

## 1.1.4 - 2026-09-20

- Kept the in-app minimize and close controls visible at compact window sizes
  and tightened the header without sacrificing accessible actions.
- Centered a compact, capped-width search field between the vault identity and
  the right-side action groups on wide headers.

## 1.1.3 - 2026-09-20

- Made the configured minimum window dimensions the default size for the vault
  workspace while preserving content-based setup and unlock sizing.

## 1.1.2 - 2026-09-20

- Replaced the square native window shadow with a visible, soft CSS shadow that
  follows the rounded app surface on light and dark backgrounds and aligned
  resizing with the visible window edge.

## 1.1.1 - 2026-09-20

- Hid the search placeholder while the field is focused and restored it when
  the empty field loses focus.

## 1.1.0 - 2026-09-17

- Made each displayed field value an accessible copy target and removed the
  separate copy button.
- Added brief inline and toast feedback after copying while keeping reveal and
  edit controls independent.

## 1.0.0 - 2026-09-16

- Replaced the sidebar and group/entry creation dialogs with one compact
  workspace for inline creation, editing, and inspection.
- Added root-level and nested drafts, full read-only entry paths, compact
  collapsed entry rows, and direct drag-and-drop for moving or reordering
  groups and entries with cyclic nesting prevention.
- Matched the workspace across light, dark, desktop, and narrow layouts with
  dense hierarchy lines, compact fields, and consistent icon controls.

## 0.5.0 - 2026-09-16

- Added field-order controls to the entry editor and persisted the selected
  order without changing field identifiers, values, types, or masking.

## 0.4.0 - 2026-09-16

- Collapsed entries by default and added per-entry controls that reveal or
  hide their fields at every group nesting level.

## 0.3.0 - 2026-09-16

- Collapsed all sidebar groups by default and added accessible controls for
  expanding and collapsing nested groups.

## 0.2.1 - 2026-09-16

- Made window dragging reliable by using Tauri's native drag region while
  keeping title-bar controls interactive.

## 0.2.0 - 2026-09-16

- Replaced the GNOME window frame with a compact in-app title bar.
- Made setup and unlock forms the window surface instead of nesting them in a
  second card.
- Added rounded, transparent window edges and a restrained window shadow.
- Added in-app minimize, hide-to-tray, explicit window dragging, and
  edge/corner resize controls.
- Added content-measured startup sizing for setup/unlock and a larger vault
  workspace.
- Reduced the minimum master-password length from 12 to 8 characters.

## 0.1.0 - 2026-09-16

- Initial Linux release with encrypted vaults, a hierarchical credential tree,
  YAML import, tray integration, autostart, auto-lock, and Debian packaging.
