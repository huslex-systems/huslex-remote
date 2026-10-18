# Dytech Remote - rebrand source changes (prepared, NOT built, NOT committed)

Nothing here was compiled (the prep environment has no Windows/Rust/Flutter toolchain). First build = first compile check.
Earlier uncommitted work (icons, RS_PUB_KEY, printer/AV1 fixes) is untouched.

## 1. Client <-> panel wiring (priority 1)
Panel contract (panel/app.py, unchanged):
- POST /api/register  {license, id, hostname} -> 200 {password, token}; 403 invalid/used, 429 rate, 400 bad id.
- POST /api/heartbeat {token} -> 200 {ok:true}; 403 invalid.  "Online" = last_seen < 180 s, so 60 s beats are fine.

Design (no flutter_rust_bridge codegen needed):
- NEW `src/dytech_panel.rs`
  - `start_activate(license)`: thread -> register -> `ui_interface::set_permanent_password_with_result(password)` (IPC to the service) -> `ui_interface::set_option("dytech-token", encrypted)` (stored in the SERVICE config, token encrypted with `password_security::encrypt_str_or_original`). Progress in local option `dytech-activate-status` = busy | ok | err:<English message>.
  - Optional response field `station` (int) -> option `dytech-station` = "DT-0001" (tray shows it). The panel does NOT send it yet (see "Panel follow-up").
  - `start_heartbeat()`: thread in the --server process, first beat after 10 s, then every 60 s, reads+decrypts `dytech-token`, POSTs /api/heartbeat. Silent when no token. Never logs the token/password.
  - Uses `hbbs_http::create_http_client_with_url` (existing reqwest blocking client, no new deps). Panel URL is the const `PANEL` = https://cp-remote.huslex.com.
- `src/lib.rs`: `mod dytech_panel;` (desktop only).
- `src/ui_interface.rs` `set_local_option`: key `dytech-activate` is intercepted -> `start_activate(value)`.
- `src/server.rs` `start_server`: `dytech_panel::start_heartbeat()` right after `set_server_running(true)` (is_server branch).
- NEW `flutter/lib/desktop/widgets/dytech_activate.dart` (`DytechActivateCard`): English "Activate this station" card (license field + Activate button + error text). Shown only while option `dytech-token` is empty; polls every 1 s; hides itself once linked.
- `flutter/lib/desktop/pages/desktop_home_page.dart`: card inserted above the ID board (not in the outgoing-only console); import added.

Risks / notes
- The panel burns the license on /api/register. If applying the password fails afterwards the user sees "Ask for a new license" -> regenerate in the panel (menu > New license).
- `disable-settings: Y` in custom.txt may block `set_permanent_password_with_result`/`set_option` from the GUI (the CLI --password was blocked by it earlier). Not verified for the IPC path used here. If activation reports "Could not apply the access password", test with client-test.custom.txt (settings not disabled) or relax the block for these two calls.
- Token encryption uses the machine key from hbb_common; GUI (user) and service (SYSTEM) are on the same machine so decrypt works; if decrypt fails the raw string is used and the panel answers 403 (visible in the log as "dytech heartbeat rejected").
- Dart: `bind.mainGetOption` is awaited, `mainGetLocalOption` is sync (same usage as existing code).

## 2. Branding (English)
- `src/lang/en.rs`: "RustDesk" -> "dytech Remote" in the 21 VALUES (keys untouched, 0 occurrences left).
- `flutter/windows/runner/Runner.rc`: CompanyName=DYTECH, FileDescription/ProductName="dytech Remote" (Task Manager / file properties). InternalName/OriginalFilename left as is on purpose.
- `flutter/lib/desktop/widgets/tabbar_widget.dart`: tab-bar title text "RustDesk" -> "dytech Remote".
- `src/tray.rs`: menu is now: "dytech Remote" | "ID: 123 456 789" (or "DT-xxxx · ID ..." when `dytech-station` exists; refreshed every 5 s by a thread via IPC) | "Version x.y.z" | separator | Open | Stop service (existing, unchanged) | separator | "Dytech". Header/footer items are disabled (labels).

NOT done (risky / needs decision)
- Main window title "dytech Remote": the title is also the lookup key (FindWindowW in `flutter/windows/runner/main.cpp`, `platform::windows::send_message_to_hnwd`, `getWindowName()` in common.dart) for single-instance/URI dispatch. Changing only one side creates duplicate windows. Needs a coordinated change of all three; skipped. Title stays "Dytech-Remote" (= app-name).
- Tray "Close": the existing item is "Stop service" (it uninstalls the service). Not renamed. Recommended: add `hide-stop-service: Y` to custom.txt (needs re-signing, see below) so unattended stations cannot be stopped from the tray.
- UI language: other languages still say "RustDesk". Recommended: add `"lang": "en"` under override-settings in tools/client.json + cpanel.json and re-sign with tools/sign_custom.py. I did not touch keys/signing.
- "Powered by": already hidden by `hide-powered-by-me: Y`.

## 3. Console (outgoing-only)
- `desktop_home_page.dart`: settings gear (bottom-left) disabled (`if (false && isOutgoingOnly)`), Install card not built when outgoing-only (`&& !bind.isOutgoingOnly()`).
- The incoming client still has the settings (3-dot) menu in the ID board; hidden/limited by `disable-settings: Y` in custom.txt.

## 4. Single installer - findings
- The workflow `.github/workflows/dytech-windows.yml` already builds ONE self-extracting packer exe per product with the signed custom.txt inside (`cp tools/*.custom.txt ./rustdesk/custom.txt` then `generate.py`). The installer step (`install_me`) XCOPYs the whole extracted folder (so custom.txt) into Program Files\<app-name>.
- The packer only runs as an INSTALLER if the exe file name ends with `install.exe` (libs/portable/src/main.rs: `click_setup`); otherwise it runs portable. The old output names (`dytech-remote-1.5.1.exe`) were therefore portable runs. CHANGED: output names are now `dytech-remote-<ver>-install.exe` and `dytech-remote-cpanel-<ver>-install.exe` (workflow lines 348/354/370/376). Double-click -> UAC -> installs to Program Files, service, shortcuts, tray autostart.
- To embed the config you need nothing more than the signed custom.txt (already done). Server key/addresses are in custom.txt override-settings.
- Silent install for scripts: `<exe> --silent-install`.
- Check on first test: the installed folder contains custom.txt; service runs; tray shows the new menu; Activate card shows until a license is entered.

## Panel follow-up (not touched here)
- Optional: return `station: <device id>` in /api/register so the tray can show DT-xxxx (client already supports it).

## Files changed / added
Added: src/dytech_panel.rs, flutter/lib/desktop/widgets/dytech_activate.dart, REBRAND-CHANGES.md
Modified: src/lib.rs, src/ui_interface.rs, src/server.rs, src/tray.rs, src/lang/en.rs, flutter/lib/desktop/pages/desktop_home_page.dart, flutter/lib/desktop/widgets/tabbar_widget.dart, flutter/windows/runner/Runner.rc, .github/workflows/dytech-windows.yml

## 5. Visual theme (Dytech navy) - prepared, NOT built, NOT committed
Files changed / added
- `flutter/lib/common.dart` (MyTheme only, values only, no structure change):
  - accent #0071FF -> #3B7BF0 (accent50/80 same hue), idColor -> #4F8BFF, button -> #1D5FE6, grayBg -> #E9EEF7.
  - Light: scaffold #F2F5FA, hover #DCE4F2, primary + elevated button #1D5FE6.
  - Dark: scaffold #0A1226, dialog #111C36, cards/inputs/outlined bg #16243F, dialog border #1B2B4B, hover #16243F, menu bar #0D172E, primary + elevated button #4F8BFF.
  - ColorThemeExtension.dark: border #2A3B5E, border2 #9FB1D6, highlight #1B2B4B (navy instead of neutral gray).
  - Default theme already follows the system (`themeModeFromString` default -> ThemeMode.system), unchanged.
- `flutter/lib/desktop/pages/server_page.dart`: connection-manager accent 0xff0071ff -> 0xff3b7bf0.
- `flutter/lib/desktop/pages/desktop_setting_page.dart` (About page, mostly hidden by disable-settings): links rustdesk.com -> https://dytech.ro, banner blue -> #1D5FE6, copyright text -> "(c) <year> DYTECH / Built on open-source software (AGPL-3.0)." (keeps a licence notice on purpose, AGPL requires attribution; `license` local var is now unused = warning only).
- NEW `flutter/assets/icon.png` (256x256, Dytech "d" logo from Downloads\dytech (1).png). `loadIcon()` already prefers `assets/icon.png` and only falls back to the RustDesk `assets/icon.svg`, so the header/tab-bar/connection-manager icons are now Dytech. NOTE: `.gitignore` has `*png`, so commit with `git add -f flutter/assets/icon.png`.
- `src/lang/en.rs`: Slogan_tip -> "Remote support by DYTECH"; added keys "About RustDesk" -> "About dytech Remote" and "Keep RustDesk background service" -> "Keep dytech Remote background service" (these keys were displayed verbatim because they had no en entry).

Window titles of file-transfer / remote / port-forward / terminal windows come from `getWindowNameWithId` = "<peer> - <app-name>", i.e. "Dytech-Remote-Console" / "Dytech-Remote" from custom.txt; no RustDesk text there. Main window title untouched (coordinated change, see section 2).

Not done / decisions
- No Flutter font bundled: IBM Plex Sans is only available as woff2 (panel/static/fonts); Flutter needs ttf, and an untested pubspec font entry would risk the build. Default Windows font (Segoe UI) stays.
- `assets/logo.png` (header logo on the home page, 300x60 max) NOT added: the client home window has a fixed size (280x300 incoming-only), an extra 72px header would risk overflow. Add later with a window-size tweak if wanted.
- Fallback `assets/icon.svg` and `res/icon.png` (1024, RustDesk) untouched: icon.svg is only used if icon.png fails to load; res/icon.png is used only by flutter_launcher_icons (not the Windows build). Source PNG is 512px so a 1024 replacement would be upscaled.
- Doc URLs in en.rs (doc_mac_permission, doc_fix_wayland) still point to rustdesk.com; they are links (Linux/mac only), not visible text.
- Other languages still show "RustDesk": set `"lang": "en"` in custom.txt (needs re-signing, not done here).
- Console Install card / settings gear: already handled in section 3 (no further change).

Risks
- Colour constants only; all edits are literal replacements inside existing const/ThemeData expressions (no new types), so compile risk is low. The one new warning is the unused `license` variable.
- `MyTheme.accent` is shared by both themes (#3B7BF0), a compromise between #4F8BFF (dark) and #1D5FE6 (light); buttons use the exact per-theme colours.
- AGPL: do not remove the "Built on open-source software" line; publish source for the distributed binaries (fork is public).

Eyeball after the build: dark navy window background and dialogs; light theme #F2F5FA; Dytech "d" icon in the tab bar/connection manager (not the RustDesk logo); file-transfer window colours; About page text; no "RustDesk" anywhere in the console menus.
