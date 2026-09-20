#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod core;
#[cfg(unix)]
mod ssh_session;
mod storage;
mod system_monitor;
mod view;

use app::AppState;
use storage::AppStorage;
use tauri::{
    Manager, WindowEvent,
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tauri_plugin_autostart::MacosLauncher;

const TRAY_ICON_SIZE: usize = 32;
const TRAY_ICON_SIZE_U32: u32 = 32;

fn main() {
    #[cfg(unix)]
    if let Some(exit_code) = ssh_session::run_terminal_helper_if_requested() {
        std::process::exit(exit_code);
    }

    let storage = AppStorage::discover().expect("cannot initialize application directories");
    let config = storage
        .load_config()
        .expect("cannot load application configuration");
    let state = AppState::new(storage, config);

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            show_main_window(app);
        }))
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--hidden"]),
        ))
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            app::bootstrap,
            app::create_vault,
            app::unlock_vault,
            app::lock_vault,
            app::minimize_window,
            app::hide_window,
            app::resize_window,
            app::add_group,
            app::add_entry,
            app::update_entry,
            app::add_ssh_key,
            app::update_ssh_key,
            app::delete_ssh_key,
            app::rename_node,
            app::delete_node,
            app::move_node,
            app::import_yaml_file,
            app::reveal_field,
            app::copy_field,
            app::connect_ssh,
            app::update_settings,
        ])
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_icon(application_icon());
                if std::env::args().any(|argument| argument == "--hidden") {
                    let _ = window.hide();
                }
            }
            setup_tray(app)?;
            system_monitor::spawn(app.handle());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running bunch-of-keys");
}

fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open bunch-of-keys", true, None::<&str>)?;
    let lock = MenuItem::with_id(app, "lock", "Lock vault", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &lock, &quit])?;

    TrayIconBuilder::new()
        .icon(application_icon())
        .tooltip("bunch-of-keys")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => show_main_window(app),
            "lock" => app::lock_and_notify(app),
            "quit" => {
                app::lock_and_notify(app);
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                show_main_window(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn application_icon() -> Image<'static> {
    let mut pixels = vec![0_u8; TRAY_ICON_SIZE * TRAY_ICON_SIZE * 4];
    for y in 0..TRAY_ICON_SIZE {
        for x in 0..TRAY_ICON_SIZE {
            let index = (y * TRAY_ICON_SIZE + x) * 4;
            let rounded =
                (3..TRAY_ICON_SIZE - 3).contains(&x) || (3..TRAY_ICON_SIZE - 3).contains(&y);
            if rounded {
                pixels[index..index + 4].copy_from_slice(&[49, 94, 232, 255]);
            }
        }
    }
    // A small white key silhouette.
    for y in 9_usize..17 {
        for x in 7_usize..15 {
            let dx = x.abs_diff(11);
            let dy = y.abs_diff(13);
            if dx * dx + dy * dy <= 16 {
                let index = (y * TRAY_ICON_SIZE + x) * 4;
                pixels[index..index + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
    }
    for x in 13..25 {
        for y in 12..15 {
            let index = (y * TRAY_ICON_SIZE + x) * 4;
            pixels[index..index + 4].copy_from_slice(&[255, 255, 255, 255]);
        }
    }
    for x in 20..23 {
        for y in 14..19 {
            let index = (y * TRAY_ICON_SIZE + x) * 4;
            pixels[index..index + 4].copy_from_slice(&[255, 255, 255, 255]);
        }
    }
    Image::new_owned(pixels, TRAY_ICON_SIZE_U32, TRAY_ICON_SIZE_U32)
}
