# Keepy

![Keepy green and blue wordmark](_assets/wordmark.svg)

Keep your credentials in local, encrypted vaults on your Mac. Keepy is a native
macOS application with nested groups, colored tags, flexible fields, and SSH
connections through an in-memory agent.

## Start here

- [Install Keepy](INSTALL_MACOS.md): download a DMG, verify its checksum, and
  install or update the application. Requires macOS 14 or later.
- [Use your vault](USER_GUIDE.md): create a vault, organize entries, search and
  filter by tags, and manage locking and appearance.
- [Update Keepy](UPDATES.md): check for updates, install and restart in the app.
- [Connect with SSH](SSH_KEYS_V2.md): keep reusable keys inside your encrypted
  vault and connect through the system OpenSSH client.

![Keepy demonstration vault with nested groups, colored tags, and masked credentials](images/main-window.png)

*One tree for groups, entries, and fields. Screenshots use synthetic demo data.*

## Understand and contribute

- [Security policy](SECURITY.md): encryption, runtime handling, and the threat
  model. There is no cloud sync, account requirement, or password recovery.
- [Development](DEVELOPMENT.md) and [architecture](ARCHITECTURE.md): build the
  native application and understand its SwiftUI/AppKit and Rust components.
- [Documentation workflow](DOCUMENTATION.md): preview this site and update its
  screenshots.
- [Changelog](CHANGELOG.md): releases and changes.

The [source repository](https://github.com/lyova24/keepy) contains the application
and these documentation sources. Download installers from
[GitHub Releases](https://github.com/lyova24/keepy/releases).
