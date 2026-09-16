use std::{thread, time::Duration};

use dbus::{blocking::Connection, message::MatchRule};
use tauri::AppHandle;

use crate::app::lock_and_notify;

pub fn spawn(app: &AppHandle) {
    spawn_screen_lock_monitor(app.clone());
    spawn_suspend_monitor(app.clone());
}

fn spawn_screen_lock_monitor(app: AppHandle) {
    thread::spawn(move || {
        let Ok(connection) = Connection::new_session() else {
            return;
        };
        let freedesktop_app = app.clone();
        let freedesktop_rule =
            MatchRule::new_signal("org.freedesktop.ScreenSaver", "ActiveChanged");
        if connection
            .add_match(freedesktop_rule, move |(active,): (bool,), _, _| {
                if active {
                    lock_and_notify(&freedesktop_app);
                }
                true
            })
            .is_err()
        {
            return;
        }
        let gnome_rule = MatchRule::new_signal("org.gnome.ScreenSaver", "ActiveChanged");
        if connection
            .add_match(gnome_rule, move |(active,): (bool,), _, _| {
                if active {
                    lock_and_notify(&app);
                }
                true
            })
            .is_err()
        {
            return;
        }
        loop {
            if connection.process(Duration::from_secs(30)).is_err() {
                return;
            }
        }
    });
}

fn spawn_suspend_monitor(app: AppHandle) {
    thread::spawn(move || {
        let Ok(connection) = Connection::new_system() else {
            return;
        };
        let rule = MatchRule::new_signal("org.freedesktop.login1.Manager", "PrepareForSleep");
        if connection
            .add_match(rule, move |(suspending,): (bool,), _, _| {
                if suspending {
                    lock_and_notify(&app);
                }
                true
            })
            .is_err()
        {
            return;
        }
        loop {
            if connection.process(Duration::from_secs(30)).is_err() {
                return;
            }
        }
    });
}
