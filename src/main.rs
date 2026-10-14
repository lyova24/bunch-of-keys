//! Private, pipe-only service embedded in the native macOS application.
#[cfg(not(target_os = "macos"))]
compile_error!("Keepy 2 supports macOS only");
mod app;
mod core;
mod legacy;
mod protocol;
mod ssh_session;
mod storage;
mod view;
use app::AppState;
use std::{io, sync::Arc};
use storage::AppStorage;
fn main() {
    if let Some(code) = ssh_session::run_terminal_helper_if_requested() {
        std::process::exit(code);
    }
    let storage = std::env::var_os("KEEPY_DATA_DIR").map_or_else(AppStorage::discover, |root| {
        AppStorage::new(std::path::PathBuf::from(root.clone()), root)
    });
    let result = storage.and_then(|storage| {
        let lock = storage.lock_instance()?;
        let config = storage.load_config()?;
        Ok((Arc::new(AppState::new(storage, config)), lock))
    });
    let (state, _instance_lock) = match result {
        Ok(result) => result,
        Err(error) => {
            let message = format!("The vault service could not initialize Keepy storage: {error}");
            let _ = protocol::serve_failure(io::stdin().lock(), io::stdout().lock(), &message);
            std::process::exit(1);
        }
    };
    state.spawn_idle_monitor();
    let _ = protocol::serve(io::stdin().lock(), io::stdout().lock(), &state);
    state.lock();
}
