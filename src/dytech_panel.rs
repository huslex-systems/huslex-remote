// Dytech: link between this client and the Dytech Remote Center panel.
//
//  * activation (GUI process, user context): the license typed in the "Activate" card is sent to
//    POST /api/register {license, id, hostname}; the panel answers {password, token}. The password
//    becomes the permanent password (applied through IPC to the service) and the token is stored,
//    encrypted at rest, in the service config under the `dytech-token` option.
//  * heartbeat (--server process, runs as SYSTEM): every 60 s POST /api/heartbeat {token}.
//
// The GUI talks to this module without any flutter_rust_bridge codegen: Dart writes the local
// option `dytech-activate` (the license) and polls `dytech-activate-status`
// ("busy" | "ok" | "err:<message>") and the synced option `dytech-token`.
use hbb_common::{
    config::{Config, LocalConfig},
    log, password_security as ps,
};
use serde_json::{json, Value};
use std::{
    sync::{
        atomic::{AtomicU8, Ordering},
        Once,
    },
    time::Duration,
};

const PANEL: &str = "https://cp-remote.huslex.com";
pub const LOCAL_ACTIVATE: &str = "dytech-activate";
pub const LOCAL_STATUS: &str = "dytech-activate-status";
pub const OPT_TOKEN: &str = "dytech-token";
pub const OPT_STATION: &str = "dytech-station";
/// "Y" while the panel reports the customer subscription as paused (set by the heartbeat).
pub const OPT_SUSPENDED: &str = "dytech-suspended";
/// Last plan state reported by the panel: free | trial | active | grace | paused.
pub const OPT_STATE: &str = "dytech-state";

/// True when incoming connections must be refused (checked at every login in server/connection.rs).
/// Persisted in the service config, so it also holds across restarts and while the panel is unreachable.
pub fn is_suspended() -> bool {
    Config::get_option(OPT_SUSPENDED) == "Y"
}

fn set_status(v: &str) {
    LocalConfig::set_option(LOCAL_STATUS.to_owned(), v.to_owned());
}

/// Called from `ui_interface::set_local_option` when Dart writes the license.
pub fn start_activate(license: String) {
    set_status("busy");
    std::thread::spawn(move || match activate(license.trim()) {
        Ok(()) => set_status("ok"),
        Err(e) => {
            log::warn!("dytech activation failed: {}", e);
            set_status(&format!("err:{}", e));
        }
    });
}

fn activate(license: &str) -> Result<(), String> {
    if license.len() < 8 {
        return Err("Enter the license key.".into());
    }
    let id = crate::ui_interface::get_id();
    if id.is_empty() {
        return Err("The service is not ready yet. Try again in a moment.".into());
    }
    let host = crate::common::whoami_hostname();
    let client = crate::hbbs_http::create_http_client_with_url(PANEL);
    let resp = client
        .post(format!("{}/api/register", PANEL))
        .timeout(Duration::from_secs(20))
        .json(&json!({ "license": license, "id": id, "hostname": host }))
        .send()
        .map_err(|_| "Cannot reach the control panel. Check the internet connection.".to_owned())?;
    let code = resp.status().as_u16();
    if code != 200 {
        return Err(match code {
            403 => "Invalid or already used license.",
            429 => "Too many attempts. Try again later.",
            400 => "The request was rejected.",
            _ => "The control panel returned an error.",
        }
        .into());
    }
    let body: Value = resp.json().map_err(|_| "Unexpected panel response.".to_owned())?;
    let password = body.get("password").and_then(|v| v.as_str()).unwrap_or("");
    let token = body.get("token").and_then(|v| v.as_str()).unwrap_or("");
    if password.is_empty() || token.is_empty() {
        return Err("Unexpected panel response.".into());
    }
    // NOTE: the license is consumed by the panel at this point. If one of the steps below fails,
    // generate a new license for the station in the panel (menu > New license).
    if !crate::ui_interface::set_permanent_password_with_result(password.to_owned()) {
        return Err("Could not apply the access password. Ask for a new license.".into());
    }
    crate::ui_interface::set_option(
        OPT_TOKEN.to_owned(),
        ps::encrypt_str_or_original(token, "00", 4096),
    );
    // Optional field (not sent by the panel yet): station number shown in the tray as DT-xxxx.
    if let Some(n) = body.get("station").and_then(|v| v.as_i64()) {
        crate::ui_interface::set_option(OPT_STATION.to_owned(), format!("DT-{:04}", n));
    }
    Ok(())
}

/// Started once from the --server process.
pub fn start_heartbeat() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let r = std::thread::Builder::new()
            .name("dytech-heartbeat".into())
            .spawn(|| {
                std::thread::sleep(Duration::from_secs(10));
                loop {
                    beat();
                    std::thread::sleep(Duration::from_secs(60));
                }
            });
        if let Err(e) = r {
            log::warn!("dytech heartbeat thread not started: {}", e);
        }
    });
}

static REJECTED: AtomicU8 = AtomicU8::new(0);

fn beat() {
    let raw = Config::get_option(OPT_TOKEN);
    if raw.is_empty() {
        return;
    }
    let (token, _, _) = ps::decrypt_str_or_original(&raw, "00");
    if token.is_empty() {
        return;
    }
    let client = crate::hbbs_http::create_http_client_with_url(PANEL);
    match client
        .post(format!("{}/api/heartbeat", PANEL))
        .timeout(Duration::from_secs(15))
        .json(&json!({ "token": token }))
        .send()
    {
        Ok(r) if r.status().is_success() => {
            REJECTED.store(0, Ordering::SeqCst);
            // Panel answer: {"ok":true,"suspended":bool,"state":"free|trial|active|grace|paused"}.
            // An old panel without these fields means "not suspended".
            if let Ok(v) = r.json::<Value>() {
                let suspended = v.get("suspended").and_then(|x| x.as_bool()).unwrap_or(false);
                let state = v.get("state").and_then(|x| x.as_str()).unwrap_or("");
                Config::set_option(
                    OPT_SUSPENDED.to_owned(),
                    if suspended { "Y" } else { "" }.to_owned(),
                );
                Config::set_option(OPT_STATE.to_owned(), state.to_owned());
            }
        }
        Ok(r) if r.status().as_u16() == 403 => {
            // The panel no longer knows this token (license regenerated / station removed).
            // After 3 consecutive rejections (3 minutes) forget it, so the "Activate" card
            // comes back and a new license can be entered.
            let n = REJECTED.fetch_add(1, Ordering::SeqCst) + 1;
            log::warn!("dytech heartbeat rejected (403), count {}", n);
            if n >= 3 {
                Config::set_option(OPT_TOKEN.to_owned(), "".to_owned());
                Config::set_option(OPT_STATION.to_owned(), "".to_owned());
                REJECTED.store(0, Ordering::SeqCst);
            }
        }
        Ok(r) => log::warn!("dytech heartbeat rejected: {}", r.status()),
        Err(e) => log::debug!("dytech heartbeat failed: {}", e),
    }
}
