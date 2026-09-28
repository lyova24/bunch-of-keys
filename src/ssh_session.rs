use std::{
    env,
    ffi::{OsStr, OsString},
    fs,
    io::{self, Write},
    os::unix::{
        ffi::OsStrExt,
        fs::{DirBuilderExt, PermissionsExt},
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Arc,
    thread,
    time::Duration,
};

use rand::thread_rng;
use rsa::{
    pkcs1v15::SigningKey,
    sha2::{Sha256, Sha512},
};
use sha1::Sha1;
use signature::{RandomizedSigner, SignatureEncoding, Signer};
use ssh_agent_lib::{
    agent::{Session, listen},
    error::AgentError,
    proto::{Identity, SignRequest},
};
use ssh_key::{Algorithm, PrivateKey, Signature, private::KeypairData, public::PublicKey};
use thiserror::Error;
use tokio::{net::UnixListener, runtime::Builder, sync::watch, time::sleep};
use uuid::Uuid;

const AGENT_LIFETIME: Duration = Duration::from_secs(5 * 60);
const SSH_HELPER_ARGUMENT: &str = "--bunch-of-keys-ssh-session";
const SSH_AGENT_RSA_SHA2_256: u32 = 2;
const SSH_AGENT_RSA_SHA2_512: u32 = 4;

#[derive(Debug, Error)]
pub enum SshSessionError {
    #[cfg(target_os = "linux")]
    #[error("XDG_RUNTIME_DIR is unavailable; cannot create a private SSH agent socket")]
    RuntimeDirectoryUnavailable,
    #[error("cannot prepare the private SSH agent runtime directory")]
    RuntimeDirectory,
    #[error("cannot start the private SSH agent")]
    AgentStart,
    #[error(
        "no compatible system terminal was found; install xdg-terminal-exec or set BUNCH_OF_KEYS_TERMINAL to a supported terminal"
    )]
    TerminalUnavailable,
    #[error("BUNCH_OF_KEYS_TERMINAL names an unsupported terminal")]
    UnsupportedTerminalOverride,
    #[error("the system terminal could not be launched")]
    TerminalLaunch,
}

#[derive(Clone)]
struct SingleKeyAgent {
    private_key: Arc<PrivateKey>,
    public_key: PublicKey,
    comment: String,
}

#[ssh_agent_lib::async_trait]
impl Session for SingleKeyAgent {
    async fn request_identities(&mut self) -> Result<Vec<Identity>, AgentError> {
        Ok(vec![Identity {
            credential: self.public_key.key_data().clone().into(),
            comment: self.comment.clone(),
        }])
    }

    async fn sign(&mut self, request: SignRequest) -> Result<Signature, AgentError> {
        let requested: PublicKey = request.credential.key_data().clone().into();
        if requested.key_data() != self.public_key.key_data() {
            return Err(AgentError::Failure);
        }
        match self.private_key.key_data() {
            KeypairData::Rsa(key) => sign_rsa(key, &request),
            _ => self
                .private_key
                .try_sign(&request.data)
                .map_err(AgentError::other),
        }
    }
}

fn sign_rsa(
    key: &ssh_key::private::RsaKeypair,
    request: &SignRequest,
) -> Result<Signature, AgentError> {
    let private_key = rsa::RsaPrivateKey::from_components(
        rsa::BigUint::try_from(&key.public.n).map_err(AgentError::other)?,
        rsa::BigUint::try_from(&key.public.e).map_err(AgentError::other)?,
        rsa::BigUint::try_from(&key.private.d).map_err(AgentError::other)?,
        vec![
            rsa::BigUint::try_from(&key.private.p).map_err(AgentError::other)?,
            rsa::BigUint::try_from(&key.private.q).map_err(AgentError::other)?,
        ],
    )
    .map_err(AgentError::other)?;
    let mut rng = thread_rng();
    let (algorithm, bytes) = if request.flags & SSH_AGENT_RSA_SHA2_512 != 0 {
        (
            "rsa-sha2-512",
            SigningKey::<Sha512>::new(private_key)
                .sign_with_rng(&mut rng, &request.data)
                .to_bytes()
                .to_vec(),
        )
    } else if request.flags & SSH_AGENT_RSA_SHA2_256 != 0 {
        (
            "rsa-sha2-256",
            SigningKey::<Sha256>::new(private_key)
                .sign_with_rng(&mut rng, &request.data)
                .to_bytes()
                .to_vec(),
        )
    } else {
        (
            "ssh-rsa",
            SigningKey::<Sha1>::new(private_key)
                .sign_with_rng(&mut rng, &request.data)
                .to_bytes()
                .to_vec(),
        )
    };
    Signature::new(Algorithm::new(algorithm).map_err(AgentError::other)?, bytes)
        .map_err(AgentError::other)
}

pub struct EphemeralAgent {
    socket_path: PathBuf,
    identity_path: PathBuf,
    cancel: watch::Sender<bool>,
    thread: Option<thread::JoinHandle<()>>,
}

impl EphemeralAgent {
    pub fn start(private_key: PrivateKey, comment: String) -> Result<Self, SshSessionError> {
        #[cfg(target_os = "linux")]
        let runtime_root = env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .ok_or(SshSessionError::RuntimeDirectoryUnavailable)?;
        #[cfg(target_os = "macos")]
        let runtime_root = env::temp_dir();
        Self::start_in(&runtime_root, private_key, comment, AGENT_LIFETIME)
    }

    #[cfg(test)]
    pub(crate) fn start_for_test(
        runtime_root: &Path,
        private_key: PrivateKey,
    ) -> Result<Self, SshSessionError> {
        Self::start_in(
            runtime_root,
            private_key,
            "test key".to_owned(),
            Duration::from_secs(30),
        )
    }

    fn start_in(
        runtime_root: &Path,
        private_key: PrivateKey,
        comment: String,
        lifetime: Duration,
    ) -> Result<Self, SshSessionError> {
        let public_identity = private_key
            .public_key()
            .to_openssh()
            .map_err(|_| SshSessionError::AgentStart)?;
        let root = runtime_root.join("bunch-of-keys");
        fs::create_dir_all(&root).map_err(|_| SshSessionError::RuntimeDirectory)?;
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700))
            .map_err(|_| SshSessionError::RuntimeDirectory)?;
        let session_id = Uuid::new_v4();
        let mut session_dir = root.join(format!("connection-{session_id}"));
        // Darwin's sockaddr_un has 104 bytes including the trailing NUL.
        // TMPDIR can already consume most of that budget. Keep the fallback
        // short (do not canonicalize /tmp) and private from creation onward.
        if session_dir.join("agent.sock").as_os_str().as_bytes().len() >= 104 {
            session_dir = Path::new("/tmp").join(format!("bok-{session_id}"));
        }
        fs::DirBuilder::new()
            .mode(0o700)
            .create(&session_dir)
            .map_err(|_| SshSessionError::RuntimeDirectory)?;
        let socket_path = session_dir.join("agent.sock");
        let identity_path = session_dir.join("identity.pub");
        if fs::write(&identity_path, public_identity).is_err()
            || fs::set_permissions(&identity_path, fs::Permissions::from_mode(0o600)).is_err()
        {
            cleanup_session(&socket_path, &identity_path, &session_dir);
            return Err(SshSessionError::AgentStart);
        }
        let Ok(listener) = std::os::unix::net::UnixListener::bind(&socket_path) else {
            cleanup_session(&socket_path, &identity_path, &session_dir);
            return Err(SshSessionError::AgentStart);
        };
        if listener.set_nonblocking(true).is_err()
            || fs::set_permissions(&socket_path, fs::Permissions::from_mode(0o600)).is_err()
        {
            cleanup_session(&socket_path, &identity_path, &session_dir);
            return Err(SshSessionError::AgentStart);
        }

        let public_key = private_key.public_key().clone();
        let agent = SingleKeyAgent {
            private_key: Arc::new(private_key),
            public_key,
            comment,
        };
        let (cancel, mut cancelled) = watch::channel(false);
        let cleanup_socket = socket_path.clone();
        let cleanup_identity = identity_path.clone();
        let cleanup_dir = session_dir.clone();
        let Ok(agent_thread) = thread::Builder::new()
            .name("bunch-of-keys-ssh-agent".to_owned())
            .spawn(move || {
                if let Ok(runtime) = Builder::new_current_thread().enable_all().build() {
                    runtime.block_on(async move {
                        if let Ok(listener) = UnixListener::from_std(listener) {
                            tokio::select! {
                                _ = listen(listener, agent) => {}
                                _ = cancelled.changed() => {}
                                () = sleep(lifetime) => {}
                            }
                        }
                    });
                }
                cleanup_session(&cleanup_socket, &cleanup_identity, &cleanup_dir);
            })
        else {
            cleanup_session(&socket_path, &identity_path, &session_dir);
            return Err(SshSessionError::AgentStart);
        };

        Ok(Self {
            socket_path,
            identity_path,
            cancel,
            thread: Some(agent_thread),
        })
    }

    pub fn socket_path(&self) -> &Path {
        &self.socket_path
    }

    pub fn identity_path(&self) -> &Path {
        &self.identity_path
    }

    pub fn cancellation_sender(&self) -> watch::Sender<bool> {
        self.cancel.clone()
    }

    pub fn is_finished(&self) -> bool {
        self.thread
            .as_ref()
            .is_none_or(thread::JoinHandle::is_finished)
    }

    pub fn stop(mut self) {
        self.stop_inner();
    }

    fn stop_inner(&mut self) {
        let _ = self.cancel.send(true);
        if let Some(agent_thread) = self.thread.take() {
            let _ = agent_thread.join();
        }
    }
}

fn cleanup_session(socket_path: &Path, identity_path: &Path, session_dir: &Path) {
    let _ = fs::remove_file(socket_path);
    let _ = fs::remove_file(identity_path);
    let _ = fs::remove_dir(session_dir);
}

impl Drop for EphemeralAgent {
    fn drop(&mut self) {
        self.stop_inner();
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TerminalKind {
    Xdg,
    DashE,
    DoubleDash,
    Gnome,
    #[cfg(target_os = "macos")]
    MacTerminal,
}

#[derive(Debug, Clone)]
pub struct TerminalLauncher {
    program: PathBuf,
    kind: TerminalKind,
}

#[derive(Debug, PartialEq, Eq)]
struct CommandSpec {
    program: PathBuf,
    args: Vec<OsString>,
}

impl TerminalLauncher {
    pub fn detect() -> Result<Self, SshSessionError> {
        let path = env::var_os("PATH").unwrap_or_default();
        if let Some(override_program) = env::var_os("BUNCH_OF_KEYS_TERMINAL") {
            let program = resolve_program(&override_program, &path)
                .ok_or(SshSessionError::TerminalUnavailable)?;
            let kind =
                terminal_kind(&program).ok_or(SshSessionError::UnsupportedTerminalOverride)?;
            return Ok(Self { program, kind });
        }
        #[cfg(target_os = "macos")]
        if executable(Path::new("/usr/bin/open")) {
            return Ok(Self {
                program: PathBuf::from("/usr/bin/open"),
                kind: TerminalKind::MacTerminal,
            });
        }
        [
            "xdg-terminal-exec",
            "gnome-terminal",
            "kgx",
            "x-terminal-emulator",
            "konsole",
            "kitty",
            "alacritty",
            "foot",
            "xterm",
        ]
        .into_iter()
        .find_map(|candidate| {
            find_in_path(candidate, &path).map(|program| Self {
                kind: terminal_kind(&program).expect("known terminal candidate"),
                program,
            })
        })
        .ok_or(SshSessionError::TerminalUnavailable)
    }

    pub fn launch_ssh(
        &self,
        socket_path: &Path,
        identity_path: &Path,
        user: &str,
        address: &str,
        port: Option<u16>,
    ) -> Result<Child, SshSessionError> {
        let executable = env::current_exe().map_err(|_| SshSessionError::TerminalLaunch)?;
        let helper_args = helper_arguments(socket_path, identity_path, user, address, port);
        let spec = self.command_spec(&executable, &helper_args)?;
        spawn_command(spec)
    }

    #[allow(clippy::unnecessary_wraps)] // macOS creates a fallible Terminal command file.
    fn command_spec(
        &self,
        executable: &Path,
        arguments: &[OsString],
    ) -> Result<CommandSpec, SshSessionError> {
        #[cfg(target_os = "macos")]
        if self.kind == TerminalKind::MacTerminal {
            return mac_terminal_command(&self.program, executable, arguments);
        }
        let mut args = match self.kind {
            TerminalKind::Xdg => Vec::new(),
            TerminalKind::DashE => vec![OsString::from("-e")],
            TerminalKind::DoubleDash => vec![OsString::from("--")],
            TerminalKind::Gnome => vec![OsString::from("--wait"), OsString::from("--")],
            #[cfg(target_os = "macos")]
            TerminalKind::MacTerminal => unreachable!(),
        };
        args.push(executable.as_os_str().to_owned());
        args.extend_from_slice(arguments);
        Ok(CommandSpec {
            program: self.program.clone(),
            args,
        })
    }
}

#[cfg(target_os = "macos")]
fn mac_terminal_command(
    program: &Path,
    executable: &Path,
    arguments: &[OsString],
) -> Result<CommandSpec, SshSessionError> {
    let session_dir = arguments
        .get(1)
        .map(PathBuf::from)
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .unwrap_or_else(env::temp_dir);
    let script = session_dir.join("ssh-session.command");
    let mut command = String::from("#!/bin/sh\nscript=$0\nrm -f -- \"$script\"\nexec ");
    command.push_str(&shell_quote(executable.as_os_str()));
    for argument in arguments {
        command.push(' ');
        command.push_str(&shell_quote(argument));
    }
    command.push('\n');
    fs::write(&script, command).map_err(|_| SshSessionError::TerminalLaunch)?;
    fs::set_permissions(&script, fs::Permissions::from_mode(0o700))
        .map_err(|_| SshSessionError::TerminalLaunch)?;
    Ok(CommandSpec {
        program: program.to_path_buf(),
        args: vec![
            OsString::from("-W"),
            OsString::from("-n"),
            OsString::from("-a"),
            OsString::from("Terminal"),
            script.into_os_string(),
        ],
    })
}

#[cfg(target_os = "macos")]
fn shell_quote(value: &OsStr) -> String {
    let value = value.to_string_lossy();
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn spawn_command(spec: CommandSpec) -> Result<Child, SshSessionError> {
    Command::new(spec.program)
        .args(spec.args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| SshSessionError::TerminalLaunch)
}

fn terminal_kind(program: &Path) -> Option<TerminalKind> {
    match program.file_name()?.to_str()? {
        "xdg-terminal-exec" => Some(TerminalKind::Xdg),
        "x-terminal-emulator" | "konsole" | "alacritty" | "xterm" => Some(TerminalKind::DashE),
        "gnome-terminal" | "kgx" => Some(TerminalKind::Gnome),
        "kitty" | "foot" => Some(TerminalKind::DoubleDash),
        _ => None,
    }
}

fn resolve_program(program: &OsStr, path: &OsStr) -> Option<PathBuf> {
    let candidate = PathBuf::from(program);
    if candidate.components().count() > 1 {
        executable(&candidate).then_some(candidate)
    } else {
        find_in_path(program, path)
    }
}

fn find_in_path(program: impl AsRef<OsStr>, path: &OsStr) -> Option<PathBuf> {
    env::split_paths(path)
        .map(|directory| directory.join(program.as_ref()))
        .find(|candidate| executable(candidate))
}

fn executable(path: &Path) -> bool {
    path.metadata()
        .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
}

fn ssh_arguments(
    socket_path: &Path,
    identity_path: &Path,
    user: &str,
    address: &str,
    port: Option<u16>,
) -> Vec<OsString> {
    let mut arguments = vec![
        OsString::from("-o"),
        OsString::from(format!("IdentityAgent={}", socket_path.display())),
        OsString::from("-o"),
        OsString::from(format!("IdentityFile={}", identity_path.display())),
        OsString::from("-o"),
        OsString::from("IdentitiesOnly=yes"),
        OsString::from("-o"),
        OsString::from("ForwardAgent=no"),
        OsString::from("-o"),
        OsString::from("AddKeysToAgent=no"),
    ];
    if let Some(port) = port {
        arguments.push(OsString::from("-p"));
        arguments.push(OsString::from(port.to_string()));
    }
    arguments.push(OsString::from("--"));
    arguments.push(OsString::from(format!("{user}@{address}")));
    arguments
}

fn helper_arguments(
    socket_path: &Path,
    identity_path: &Path,
    user: &str,
    address: &str,
    port: Option<u16>,
) -> Vec<OsString> {
    vec![
        OsString::from(SSH_HELPER_ARGUMENT),
        socket_path.as_os_str().to_owned(),
        identity_path.as_os_str().to_owned(),
        OsString::from(user),
        OsString::from(address),
        OsString::from(port.map_or_else(String::new, |value| value.to_string())),
    ]
}

struct HelperRequest {
    socket_path: PathBuf,
    identity_path: PathBuf,
    user: String,
    address: String,
    port: Option<u16>,
}

fn parse_helper_request(mut arguments: impl Iterator<Item = OsString>) -> Option<HelperRequest> {
    arguments.next()?;
    if arguments.next()?.to_str()? != SSH_HELPER_ARGUMENT {
        return None;
    }
    let socket_path = PathBuf::from(arguments.next()?);
    let identity_path = PathBuf::from(arguments.next()?);
    let user = arguments.next()?.into_string().ok()?;
    let address = arguments.next()?.into_string().ok()?;
    let port_value = arguments.next()?.into_string().ok()?;
    let port = if port_value.is_empty() {
        None
    } else {
        Some(port_value.parse::<u16>().ok().filter(|port| *port != 0)?)
    };
    if arguments.next().is_some()
        || socket_path.as_os_str().is_empty()
        || identity_path.as_os_str().is_empty()
        || user.is_empty()
        || address.is_empty()
        || user.chars().any(char::is_control)
        || address.chars().any(char::is_control)
    {
        return None;
    }
    Some(HelperRequest {
        socket_path,
        identity_path,
        user,
        address,
        port,
    })
}

pub fn run_terminal_helper_if_requested() -> Option<i32> {
    let request = parse_helper_request(env::args_os())?;
    let path = env::var_os("PATH").unwrap_or_default();
    let Some(ssh) = find_in_path("ssh", &path) else {
        eprintln!("bunch-of-keys: the system ssh executable was not found.");
        pause_after_failure();
        return Some(127);
    };
    let status = Command::new(ssh)
        .args(ssh_arguments(
            &request.socket_path,
            &request.identity_path,
            &request.user,
            &request.address,
            request.port,
        ))
        .status();
    match status {
        Ok(status) if status.success() => Some(0),
        Ok(status) => {
            eprintln!("\nssh exited with {status}.");
            pause_after_failure();
            Some(status.code().unwrap_or(1))
        }
        Err(error) => {
            eprintln!("bunch-of-keys: could not start ssh: {error}");
            pause_after_failure();
            Some(127)
        }
    }
}

fn pause_after_failure() {
    eprint!("Press Enter to close this window...");
    let _ = io::stderr().flush();
    let mut input = String::new();
    let _ = io::stdin().read_line(&mut input);
}

pub fn monitor_terminal(
    mut child: Child,
    cancel: watch::Sender<bool>,
    on_exit: impl FnOnce() + Send + 'static,
) {
    thread::spawn(move || {
        let _ = child.wait();
        let _ = cancel.send(true);
        on_exit();
    });
}

#[cfg(test)]
mod tests {
    use ssh_key::{Algorithm, private::PrivateKey, rand_core::OsRng};
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn command_construction_keeps_untrusted_values_as_structured_arguments() {
        let launcher = TerminalLauncher {
            program: PathBuf::from("/usr/bin/xdg-terminal-exec"),
            kind: TerminalKind::Xdg,
        };
        let arguments = helper_arguments(
            Path::new("/run/user/1000/bunch-of-keys/agent socket"),
            Path::new("/run/user/1000/bunch-of-keys/identity.pub"),
            "deploy",
            "host;touch-pwned",
            Some(2222),
        );
        let spec = launcher
            .command_spec(Path::new("/usr/bin/bunch-of-keys"), &arguments)
            .unwrap();

        assert_eq!(spec.program, Path::new("/usr/bin/xdg-terminal-exec"));
        assert_eq!(spec.args[0], "/usr/bin/bunch-of-keys");
        assert_eq!(spec.args[1], SSH_HELPER_ARGUMENT);
        assert_eq!(spec.args[4], "deploy");
        assert_eq!(spec.args[5], "host;touch-pwned");
        assert!(
            !spec
                .args
                .iter()
                .any(|argument| argument == "sh" || argument == "-c")
        );
        let request = parse_helper_request(spec.args.into_iter()).unwrap();
        let ssh_args = ssh_arguments(
            &request.socket_path,
            &request.identity_path,
            &request.user,
            &request.address,
            request.port,
        );
        assert_eq!(ssh_args.last().unwrap(), "deploy@host;touch-pwned");
        assert!(ssh_args.contains(&OsString::from("ForwardAgent=no")));
        assert!(ssh_args.contains(&OsString::from("IdentitiesOnly=yes")));
        assert!(ssh_args.contains(&OsString::from(
            "IdentityFile=/run/user/1000/bunch-of-keys/identity.pub"
        )));
    }

    #[test]
    fn single_key_agent_exposes_only_its_key_and_signs_requests() {
        let mut private_key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519).unwrap();
        private_key.set_comment("/home/example/.ssh/id_ed25519");
        let public_key = private_key.public_key().clone();
        let mut agent = SingleKeyAgent {
            private_key: Arc::new(private_key),
            public_key: public_key.clone(),
            comment: "selected".to_owned(),
        };
        let runtime = Builder::new_current_thread().enable_all().build().unwrap();

        runtime.block_on(async {
            let identities = agent.request_identities().await.unwrap();
            assert_eq!(identities.len(), 1);
            assert_eq!(identities[0].comment, "selected");
            let signature = agent
                .sign(SignRequest {
                    credential: public_key.key_data().clone().into(),
                    data: b"ssh authentication request".to_vec(),
                    flags: 0,
                })
                .await
                .unwrap();
            assert_eq!(signature.algorithm(), Algorithm::Ed25519);
            assert!(!signature.as_bytes().is_empty());
        });
    }

    #[test]
    fn ephemeral_agent_supports_long_runtime_paths() {
        let directory = tempdir().unwrap();
        let runtime_root = directory.path().join("a".repeat(120));
        let key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519).unwrap();
        let agent = EphemeralAgent::start_for_test(&runtime_root, key).unwrap();
        let socket = agent.socket_path().to_owned();
        let identity = agent.identity_path().to_owned();
        assert!(socket.as_os_str().as_bytes().len() < 104);
        assert_eq!(
            socket.metadata().unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            socket
                .parent()
                .unwrap()
                .metadata()
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
        assert_eq!(
            identity.metadata().unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(std::os::unix::net::UnixStream::connect(&socket).is_ok());
        agent.stop();
        assert!(!socket.exists());
        assert!(!identity.exists());
        assert!(!socket.parent().unwrap().exists());
    }

    #[test]
    fn ephemeral_agent_uses_owner_only_permissions_and_cleans_up() {
        let directory = tempdir().unwrap();
        let key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519).unwrap();
        let agent = EphemeralAgent::start_in(
            directory.path(),
            key,
            "test".to_owned(),
            Duration::from_secs(30),
        )
        .unwrap();
        let socket = agent.socket_path().to_owned();
        let identity = agent.identity_path().to_owned();

        assert_eq!(
            socket.metadata().unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            socket
                .parent()
                .unwrap()
                .metadata()
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
        assert_eq!(
            identity.metadata().unwrap().permissions().mode() & 0o777,
            0o600
        );
        agent.stop();

        assert!(!socket.exists());
        assert!(!identity.exists());
        assert!(!socket.parent().unwrap().exists());
    }

    #[test]
    fn unsupported_terminal_overrides_fail_without_a_shell_fallback() {
        assert_eq!(terminal_kind(Path::new("/usr/bin/custom-terminal")), None);
        assert!(matches!(
            spawn_command(CommandSpec {
                program: PathBuf::from("/definitely/missing/terminal"),
                args: Vec::new(),
            }),
            Err(SshSessionError::TerminalLaunch)
        ));
    }
}
