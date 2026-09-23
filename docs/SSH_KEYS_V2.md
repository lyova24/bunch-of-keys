# SSH private keys: proposed v2 design

Status: implemented and current in version 1.6.1.

## Recommendation

SSH private-key material is stored as a reusable encrypted vault object and is
exposed to OpenSSH through a per-connection in-memory agent. The implementation
never writes a private-key file.

Each connection uses a private runtime directory containing:

```text
$XDG_RUNTIME_DIR/bunch-of-keys/connection-<random UUID>/agent.sock
$XDG_RUNTIME_DIR/bunch-of-keys/connection-<random UUID>/identity.pub
```

`identity.pub` contains only the selected public key and makes that key an
explicit OpenSSH identity even when host-specific `~/.ssh/config` rules differ.
The private key remains in memory. Each owner-only socket exposes one selected
key, and both runtime files disappear when the terminal session exits, after a
bounded timeout, when the vault locks, or when the process exits. The vault
stores:

- the OpenSSH private-key document;
- public key, algorithm, comment, and fingerprint metadata;
- the encrypted OpenSSH document unchanged when the source key has a
  passphrase.

## User workflow

1. Create or import a named private key from an SSH field editor.
2. Store an SSH field with user, address, optional port, and the key reference.
3. Use **Connect via SSH**. Encrypted keys request a masked passphrase in-app.
4. The app starts an owner-only one-key agent and launches the system `ssh`
   executable in the preferred terminal with direct arguments,
   `IdentityAgent=<socket>`, `IdentityFile=<public identity>`,
   `IdentitiesOnly=yes`, and `ForwardAgent=no`.
5. The normal OpenSSH host-key and authentication prompts remain interactive.
   If `ssh` exits with an error, the terminal keeps the original output visible
   until Enter is pressed.

`xdg-terminal-exec` is preferred. Known terminal emulators are supported as
direct-argument fallbacks, and `BUNCH_OF_KEYS_TERMINAL` can select one of those
executables explicitly. No launcher path uses `sh -c`.

## Security properties and limitations

An agent prevents accidental private-key file exposure, but any process running
as the same user and knowing the unpredictable socket path could ask an active
agent to sign data. This is normal SSH-agent behavior. The implementation limits
that exposure with:

- one selected key per socket;
- explicit user activation and duplicate-launch prevention;
- a five-minute maximum lifetime and deterministic lock/exit cleanup;
- socket and public-identity mode `0600` inside `0700` per-connection
  directories;
- disabled SSH forwarding and no private data in argv, environment, clipboard,
  terminal output, or frontend vault state.

## Rejected alternatives

### Temporary private-key files

Writing a key under `$XDG_RUNTIME_DIR` and invoking `ssh -i` is simple and could
serve as a compatibility fallback. It still creates filesystem material,
depends on reliable cleanup, and does not help applications that cannot be
wrapped by the utility.

### Clipboard copy

Copying a private key to the clipboard is both unsafe and inconvenient. It also
does not integrate with OpenSSH authentication.

### Replacing the SSH client

Embedding a complete SSH client would only help commands launched by this
application and would duplicate mature OpenSSH behavior. An agent remains the
smallest interoperable boundary.
