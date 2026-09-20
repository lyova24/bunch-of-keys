# SSH private keys: proposed v2 design

Status: reusable SSH fields and encrypted key storage implemented in version
1.3.0; connection launching is tracked separately.

## Recommendation

Store SSH private-key material as an encrypted vault field and expose selected
keys through an embedded SSH agent over a Unix-domain socket. Do not write a
normal private-key file merely to make OpenSSH consume it.

The agent socket would live under:

```text
$XDG_RUNTIME_DIR/bunch-of-keys/agent.sock
```

The socket and in-memory agent disappear when the vault locks or the process
exits. The vault stores:

- the OpenSSH private-key document;
- an optional import passphrase, or a normalized decrypted key representation;
- public key, algorithm, comment, and fingerprint metadata;
- whether agent use requires per-request confirmation;
- an optional activation timeout.

## User workflow

1. Import a private key or paste it into an SSH-key entry.
2. Unlock the vault.
3. Select `Enable in SSH agent` for one or more keys.
4. Run one of:

   ```bash
   eval "$(bok ssh-env)"
   bok ssh user@example.com
   ```

5. The normal OpenSSH client sends signing requests to the agent. Private key
   bytes are not returned to the client.
6. Locking the vault closes the agent and zeroizes its loaded keys.

The shell helper is necessary because a tray process cannot retroactively
change `SSH_AUTH_SOCK` in terminals that are already running.

## Security properties and limitations

An agent prevents accidental private-key file exposure, but any process running
as the same user can ask an unlocked agent to sign data. This is normal SSH
agent behavior. The v2 implementation should therefore include:

- explicit activation rather than automatically loading every stored key;
- short key lifetimes;
- optional confirmation for every signature;
- destination constraints where the OpenSSH agent protocol permits them;
- socket mode `0600` inside a user-only runtime directory;
- clear UI showing which keys are currently active.

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
