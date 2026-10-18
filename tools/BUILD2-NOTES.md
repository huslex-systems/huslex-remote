# Build 2 notes (branch build2; master untouched)

All code is UNCOMPILED (no Dart/Rust toolchain available while preparing). First compile happens in GitHub Actions.

## Changed files
- src/dytech_panel.rs - heartbeat now parses `suspended`/`state`; stores options `dytech-suspended`, `dytech-state`; adds `is_suspended()`.
- src/server/connection.rs - at login (after `if self.authorized`), if suspended: send "Subscription paused..." login error and refuse.
- flutter/lib/desktop/widgets/dytech_activate.dart - red "Subscription paused" card when activated and suspended (polls option); strings via translate().
- flutter/lib/common.dart - `dytechIsNight()` (offline NOAA sunrise/sunset, Bucharest 44.43N 26.10E); "system" theme preference now = Dytech Auto; Flutter ThemeMode.system never used.
- flutter/lib/main.dart - 3-minute timer re-evaluates Auto theme; brightness handler uses dytechIsNight(); timer cancelled in dispose().
- src/lang/en.rs - "Follow System" shown as "Auto (sunrise/sunset)".
- src/lang/ro.rs - RustDesk->dytech Remote in values; Auto label; 17 new entries for activation/paused strings.
- tools/client.build2.json, tools/cpanel.build2.json - same as originals but `lang` moved from override-settings to default-settings (lets users switch language). Not signed; sign with tools/sign_custom.py using your key.

## Not done
- Goal 4 (file transfer page polish): skipped, too risky without a compiler.
- Language selector only becomes usable after re-signing custom.txt from the *.build2.json files AND the settings UI being reachable (client has settings; disable-settings would hide it).
- libs/scrap/src/common/codec.rs modification is pre-existing and unrelated: do not commit it with build2.

## Risky / to check in CI
- `Get.isDarkMode` usage in main.dart timer.
- `r.json::<Value>()` inside guarded match arm in dytech_panel.rs (needs reqwest json feature / Value import).
- `#[cfg(...)]` on an `if` statement in connection.rs.
- `Config::set_option` called from the heartbeat thread.
- translate() applied to dynamic error strings (falls back to key).

## Suspension approach
Persisted option `dytech-suspended`=Y checked on every login; survives restart and panel outages (cleared by next successful heartbeat with suspended=false). Chosen over stop-service (service/tray side effects) and over swapping the password.

## Verify
1. Build via Actions; install.
2. Theme: set Auto, change system clock to ~03:00 / ~13:00 Bucharest; theme flips within 3 min.
3. Suspension: mark customer paused in panel; after next heartbeat the card shows "Subscription paused" and a connection attempt is refused with the message; unpause -> works again.
4. Language: after re-signed custom.txt, pick Romanian in settings; no "RustDesk" text.

## Rollback
`git checkout -- src flutter` for the files above (and delete tools/*.build2.json / this file), or just don't merge branch build2.
