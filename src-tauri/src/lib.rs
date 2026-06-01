#[cfg(not(target_os = "macos"))]
mod tray_text;

use std::{
    fs,
    sync::Mutex,
    time::{Duration, Instant},
};

use chrono::{Datelike, Local, TimeZone, Timelike};
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, PhysicalPosition, Position, Size, State, WebviewWindow,
    WindowEvent,
};

const TRAY_ID: &str = "main-tray";
const SETTINGS_FILE: &str = "settings.json";

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Monthly salary in the chosen currency.
    pub monthly_salary: f64,
    /// Currency symbol shown before the amount, e.g. "₹", "$", "€".
    pub currency_symbol: String,
    /// Currency code, e.g. "INR", "USD". Free text — any currency works.
    pub currency_code: String,
    /// Use Indian digit grouping (1,23,45,678) instead of western (12,345,678).
    pub indian_grouping: bool,
    /// Whether the user has finished initial setup.
    pub configured: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            monthly_salary: 0.0,
            currency_symbol: "₹".to_string(),
            currency_code: "INR".to_string(),
            indian_grouping: true,
            configured: false,
        }
    }
}

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

struct AppState {
    settings: Mutex<Settings>,
    /// Set when the popover auto-hides on focus loss, so a tray click that
    /// caused that focus loss doesn't immediately re-open the window.
    last_auto_hide: Mutex<Option<Instant>>,
    /// Set when the popover is shown. Focus-loss events arriving right after
    /// a show are ignored: over a fullscreen Space the window may fail to
    /// become key and macOS can deliver a spurious focus-loss that would
    /// otherwise instantly hide the popover again.
    last_show: Mutex<Option<Instant>>,
    /// What the tray currently displays, so unchanged frames are skipped.
    /// (On Linux every icon update writes a temp PNG — worth avoiding.)
    last_tray_render: Mutex<String>,
}

// ---------------------------------------------------------------------------
// Earnings math
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
pub struct Earnings {
    /// Money earned so far this month.
    pub earned: f64,
    /// Money earned per second.
    pub per_second: f64,
    /// The full monthly salary.
    pub month_total: f64,
    /// Seconds elapsed since the start of the month.
    pub elapsed_secs: f64,
    /// Total seconds in the current month.
    pub total_secs: f64,
    /// 0.0 → 1.0 progress through the month.
    pub month_progress: f64,
    /// Unix timestamp (ms) when this snapshot was computed, for client-side interpolation.
    pub computed_at_ms: i64,
    /// Day of month, total days in month — for display.
    pub day_of_month: u32,
    pub days_in_month: u32,
}

/// Resolve a local datetime for the first instant of the given year/month,
/// tolerating DST gaps/ambiguities.
fn start_of_month(year: i32, month: u32) -> chrono::DateTime<Local> {
    Local
        .with_ymd_and_hms(year, month, 1, 0, 0, 0)
        .earliest()
        // DST gap exactly at midnight (extremely rare): fall back to 1 AM.
        .or_else(|| Local.with_ymd_and_hms(year, month, 1, 1, 0, 0).earliest())
        .expect("could not construct start of month")
}

fn compute_earnings(settings: &Settings) -> Earnings {
    let now = Local::now();
    let (year, month) = (now.year(), now.month());

    let month_start = start_of_month(year, month);
    let (next_year, next_month) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    let month_end = start_of_month(next_year, next_month);

    let total_secs = (month_end - month_start).num_milliseconds() as f64 / 1000.0;
    let elapsed_secs = ((now - month_start).num_milliseconds() as f64 / 1000.0)
        .clamp(0.0, total_secs);

    let month_progress = if total_secs > 0.0 {
        (elapsed_secs / total_secs).clamp(0.0, 1.0)
    } else {
        0.0
    };

    let days_in_month = (month_end.date_naive() - month_start.date_naive()).num_days() as u32;

    Earnings {
        earned: settings.monthly_salary * month_progress,
        per_second: if total_secs > 0.0 {
            settings.monthly_salary / total_secs
        } else {
            0.0
        },
        month_total: settings.monthly_salary,
        elapsed_secs,
        total_secs,
        month_progress,
        computed_at_ms: now.timestamp_millis(),
        day_of_month: now.day(),
        days_in_month,
    }
}

// ---------------------------------------------------------------------------
// Money formatting
// ---------------------------------------------------------------------------

/// Group an integer digit string with thousands separators.
/// Indian style groups the last 3 digits then pairs: 1,23,45,678.
/// Western style groups in threes: 12,345,678.
fn group_digits(int_str: &str, indian: bool) -> String {
    let digits: Vec<char> = int_str.chars().collect();
    let n = digits.len();
    let mut out = String::with_capacity(n + n / 2);

    for (i, c) in digits.iter().enumerate() {
        if i > 0 {
            let from_right = n - i;
            let needs_comma = if indian {
                from_right == 3 || (from_right > 3 && (from_right - 3) % 2 == 0)
            } else {
                from_right % 3 == 0
            };
            if needs_comma {
                out.push(',');
            }
        }
        out.push(*c);
    }
    out
}

/// Format an amount with the given number of decimals and grouping style.
fn format_money(amount: f64, decimals: usize, indian: bool) -> String {
    let formatted = format!("{:.*}", decimals, amount.max(0.0));
    match formatted.split_once('.') {
        Some((int_part, dec_part)) => {
            format!("{}.{}", group_digits(int_part, indian), dec_part)
        }
        None => group_digits(&formatted, indian),
    }
}

/// Pick how many decimals the menu bar counter needs so that it visibly
/// moves every second (more decimals for smaller per-second rates).
fn tray_decimals(per_second: f64) -> usize {
    if per_second >= 1.0 || per_second <= 0.0 {
        return 2;
    }
    let needed = (-per_second.log10()).ceil() as usize + 1;
    needed.clamp(2, 5)
}

fn tray_title(settings: &Settings) -> String {
    // The tray shows a template icon next to this text, so no emoji needed.
    if !settings.configured || settings.monthly_salary <= 0.0 {
        return "set me up".to_string();
    }
    let earnings = compute_earnings(settings);
    let decimals = tray_decimals(earnings.per_second);
    format!(
        "{}{}",
        settings.currency_symbol,
        format_money(earnings.earned, decimals, settings.indian_grouping)
    )
}

/// Compact form of an amount that fits inside a tray icon (≤ 6 chars).
/// Used on Windows/Linux where the tray cannot show title text.
/// (Compiled everywhere so unit tests cover it on all platforms.)
#[cfg_attr(target_os = "macos", allow(dead_code))]
fn compact_amount(value: f64, indian: bool) -> String {
    let v = value.max(0.0);

    // Format with one decimal then drop a trailing ".0" → "8.5L", "99L".
    let one_decimal = |x: f64| -> String {
        let s = format!("{:.1}", x);
        s.strip_suffix(".0").map(str::to_string).unwrap_or(s)
    };

    // Past a trillion a tray icon stops being a useful financial instrument.
    if v >= 1.0e12 {
        return "LOTS".to_string();
    }

    // Thresholds sit just below each tier so values that ROUND up to the next
    // tier are promoted ("999,999" → "1M", not "1000k").
    if indian {
        if v >= 9_995_000.0 {
            format!("{}Cr", one_decimal(v / 1.0e7))
        } else if v >= 99_950.0 {
            format!("{}L", one_decimal(v / 1.0e5))
        } else {
            format!("{:.0}", v)
        }
    } else if v >= 999_500_000.0 {
        format!("{}B", one_decimal(v / 1.0e9))
    } else if v >= 999_500.0 {
        format!("{}M", one_decimal(v / 1.0e6))
    } else if v >= 99_950.0 {
        format!("{:.0}k", v / 1000.0)
    } else if v >= 1.0e4 {
        format!("{}k", one_decimal(v / 1000.0))
    } else {
        format!("{:.0}", v)
    }
}

/// Tray icon text + hover tooltip for platforms without tray titles.
#[cfg(not(target_os = "macos"))]
fn tray_compact_and_tooltip(settings: &Settings) -> (String, String) {
    if !settings.configured || settings.monthly_salary <= 0.0 {
        return ("?".to_string(), "Silly Motivation — click to set up".to_string());
    }
    let earnings = compute_earnings(settings);
    let compact = compact_amount(earnings.earned, settings.indian_grouping);
    let tooltip = format!(
        "{}{} earned this month ({}{}/sec)",
        settings.currency_symbol,
        format_money(earnings.earned, 2, settings.indian_grouping),
        settings.currency_symbol,
        format_money(earnings.per_second, 4, settings.indian_grouping),
    );
    (compact, tooltip)
}

// ---------------------------------------------------------------------------
// Settings persistence
// ---------------------------------------------------------------------------

fn settings_path(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|dir| dir.join(SETTINGS_FILE))
}

/// Clamp settings to sane values regardless of where they came from
/// (the UI, a hand-edited settings.json, etc.).
fn sanitize_settings(mut settings: Settings) -> Settings {
    if !settings.monthly_salary.is_finite() || settings.monthly_salary < 0.0 {
        settings.monthly_salary = 0.0;
    }
    settings.monthly_salary = settings.monthly_salary.min(1e15);

    settings.currency_symbol = settings.currency_symbol.trim().chars().take(8).collect();
    if settings.currency_symbol.is_empty() {
        settings.currency_symbol = "💵".to_string();
    }

    settings.currency_code = settings
        .currency_code
        .trim()
        .chars()
        .take(8)
        .collect::<String>()
        .to_uppercase();
    if settings.currency_code.is_empty() {
        settings.currency_code = "???".to_string();
    }

    settings.configured = settings.configured && settings.monthly_salary > 0.0;
    settings
}

fn load_settings(app: &AppHandle) -> Settings {
    let raw = settings_path(app)
        .and_then(|path| fs::read_to_string(path).ok())
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    sanitize_settings(raw)
}

fn persist_settings(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let path = settings_path(app).ok_or("could not resolve config directory")?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(|e| e.to_string())?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tray + window helpers
// ---------------------------------------------------------------------------

/// Push the current earnings into the tray.
///
/// macOS: title text next to the template icon (updates every second).
/// Windows/Linux: counter rendered INTO the icon + tooltip; the icon is only
/// re-rendered when its compact text actually changes.
fn refresh_tray(app: &AppHandle) {
    let Some(tray) = app.tray_by_id(TRAY_ID) else {
        return;
    };
    let state = app.state::<AppState>();

    #[cfg(target_os = "macos")]
    {
        let title = {
            let settings = state.settings.lock().unwrap();
            tray_title(&settings)
        };
        let mut last = state.last_tray_render.lock().unwrap();
        if *last != title {
            *last = title.clone();
            let _ = tray.set_title(Some(title));
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        let (compact, tooltip, title) = {
            let settings = state.settings.lock().unwrap();
            let (compact, tooltip) = tray_compact_and_tooltip(&settings);
            (compact, tooltip, tray_title(&settings))
        };

        let mut last = state.last_tray_render.lock().unwrap();
        if *last != compact {
            *last = compact.clone();
            if let Ok(icon) = tray_text::render_icon(&compact) {
                let _ = tray.set_icon(Some(icon));
            }
        }
        // Tooltip shows the precise amount on hover (Windows; no-op on Linux).
        let _ = tray.set_tooltip(Some(&tooltip));
        // Some Linux DEs (KDE Plasma) can show a label next to the icon too.
        #[cfg(target_os = "linux")]
        let _ = tray.set_title(Some(&title));
        #[cfg(not(target_os = "linux"))]
        let _ = title; // unused on Windows
    }
}

/// Continuously update the menu bar counter, ticking on wall-clock second
/// boundaries so the amount visibly grows every second.
fn spawn_tray_updater(app: AppHandle) {
    std::thread::spawn(move || loop {
        refresh_tray(&app);
        // Sleep until just after the next wall-clock second boundary.
        let subsec_ms = u64::from(Local::now().nanosecond() / 1_000_000) % 1000;
        std::thread::sleep(Duration::from_millis(1005 - subsec_ms.min(1000)));
    });
}

/// Place the popover window next to the tray icon, clamped to the monitor's
/// visible area. Opens BELOW the tray on top bars (macOS menu bar) and ABOVE
/// it on bottom bars (Windows taskbar).
fn position_window_under_tray(window: &WebviewWindow, tray_rect: &tauri::Rect) {
    // Tray rect coordinates arrive as physical or logical depending on platform;
    // normalize everything to physical pixels.
    let scale = window
        .current_monitor()
        .ok()
        .flatten()
        .map(|m| m.scale_factor())
        .unwrap_or_else(|| window.scale_factor().unwrap_or(1.0));

    let (tray_x, tray_w, tray_top, tray_bottom) = match (tray_rect.position, tray_rect.size) {
        (Position::Physical(p), Size::Physical(s)) => (
            p.x as f64,
            s.width as f64,
            p.y as f64,
            p.y as f64 + s.height as f64,
        ),
        (Position::Logical(p), Size::Logical(s)) => (
            p.x * scale,
            s.width * scale,
            p.y * scale,
            (p.y + s.height) * scale,
        ),
        (Position::Physical(p), Size::Logical(s)) => (
            p.x as f64,
            s.width * scale,
            p.y as f64,
            p.y as f64 + s.height * scale,
        ),
        (Position::Logical(p), Size::Physical(s)) => (
            p.x * scale,
            s.width as f64,
            p.y * scale,
            p.y * scale + s.height as f64,
        ),
    };

    let (win_width, win_height) = window
        .outer_size()
        .map(|s| (s.width as f64, s.height as f64))
        .unwrap_or((360.0 * scale, 600.0 * scale));

    let mut x = tray_x + tray_w / 2.0 - win_width / 2.0;

    // Default: below the tray. If the tray sits in the lower half of the
    // monitor (e.g. Windows taskbar), open above it instead.
    let mut y = tray_bottom + 6.0 * scale;
    if let Ok(Some(monitor)) = window.current_monitor() {
        let mon_pos = monitor.position();
        let mon_size = monitor.size();

        let monitor_mid_y = mon_pos.y as f64 + mon_size.height as f64 / 2.0;
        if tray_top > monitor_mid_y {
            y = tray_top - win_height - 6.0 * scale;
        }

        // Keep the window inside the monitor horizontally.
        let min_x = mon_pos.x as f64 + 8.0;
        let max_x = mon_pos.x as f64 + mon_size.width as f64 - win_width - 8.0;
        x = x.clamp(min_x, max_x.max(min_x));
    }

    let _ = window.set_position(Position::Physical(PhysicalPosition::new(
        x.round() as i32,
        y.round() as i32,
    )));
}

/// Fallback when no tray rect is available (Linux app indicators don't expose
/// one): pin the popover to the top-right of the primary monitor.
fn position_window_fallback(window: &WebviewWindow) {
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let mon_pos = monitor.position();
        let mon_size = monitor.size();
        let win_width = window.outer_size().map(|s| s.width as f64).unwrap_or(360.0);
        let x = mon_pos.x as f64 + mon_size.width as f64 - win_width - 16.0;
        let y = mon_pos.y as f64 + 48.0;
        let _ = window.set_position(Position::Physical(PhysicalPosition::new(
            x.round() as i32,
            y.round() as i32,
        )));
    }
}

/// Make the popover behave like a real menu bar popover: float above
/// fullscreen apps, follow the user across Spaces, stay out of Cmd+` cycling.
#[cfg(target_os = "macos")]
fn elevate_popover(window: &WebviewWindow) {
    use objc2::msg_send;
    use objc2::runtime::AnyObject;

    if let Ok(ptr) = window.ns_window() {
        let ns_window = ptr as *mut AnyObject;
        unsafe {
            // NSWindowCollectionBehavior:
            //   CanJoinAllSpaces (1<<0) | IgnoresCycle (1<<6) | FullScreenAuxiliary (1<<8)
            let behavior: usize = (1 << 0) | (1 << 6) | (1 << 8);
            let _: () = msg_send![ns_window, setCollectionBehavior: behavior];
            // NSPopUpMenuWindowLevel (101): same level macOS uses for menu bar
            // popovers, which renders above fullscreen application windows.
            let level: isize = 101;
            let _: () = msg_send![ns_window, setLevel: level];
        }
    }
}

#[cfg(not(target_os = "macos"))]
fn elevate_popover(_window: &WebviewWindow) {}

fn show_popover(app: &AppHandle, tray_rect: Option<&tauri::Rect>) {
    if let Some(window) = app.get_webview_window("main") {
        // Use the click's rect when given; otherwise ask the tray icon where it
        // lives so menu-driven and first-run opens are anchored too.
        let resolved = tray_rect.cloned().or_else(|| {
            app.tray_by_id(TRAY_ID)
                .and_then(|tray| tray.rect().ok())
                .flatten()
        });
        match resolved {
            Some(rect) => position_window_under_tray(&window, &rect),
            // Linux app indicators never report a rect.
            None => position_window_fallback(&window),
        }
        // Re-apply on every show in case anything reset the level/behavior.
        elevate_popover(&window);
        *app.state::<AppState>().last_show.lock().unwrap() = Some(Instant::now());
        let _ = window.show();
        let _ = window.set_focus();
        // Tell the webview to re-derive its view from persisted state.
        let _ = app.emit("popover-shown", ());
    }
}

fn hide_popover(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
        // Tell the webview to stop its animation/sync loops.
        let _ = app.emit("popover-hidden", ());
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

#[tauri::command]
fn get_settings(state: State<'_, AppState>) -> Settings {
    state.settings.lock().unwrap().clone()
}

#[tauri::command]
fn save_settings(app: AppHandle, state: State<'_, AppState>, settings: Settings) -> Result<Earnings, String> {
    if !settings.monthly_salary.is_finite() || settings.monthly_salary < 0.0 {
        return Err("Salary must be a positive number".to_string());
    }
    if settings.monthly_salary > 1e15 {
        return Err("Okay, nobody earns that much. Be serious. 😄".to_string());
    }

    let mut sanitized = sanitize_settings(settings);
    sanitized.configured = sanitized.monthly_salary > 0.0;

    {
        let mut guard = state.settings.lock().unwrap();
        *guard = sanitized.clone();
    }
    persist_settings(&app, &sanitized)?;
    refresh_tray(&app);

    Ok(compute_earnings(&sanitized))
}

#[tauri::command]
fn get_earnings(state: State<'_, AppState>) -> Earnings {
    let settings = state.settings.lock().unwrap();
    compute_earnings(&settings)
}

#[tauri::command]
fn hide_window(app: AppHandle) {
    hide_popover(&app);
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

// ---------------------------------------------------------------------------
// App entry
// ---------------------------------------------------------------------------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            // Pure menu bar app: no Dock icon, no app switcher entry.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let settings = load_settings(&app.handle().clone());
            app.manage(AppState {
                settings: Mutex::new(settings),
                last_auto_hide: Mutex::new(None),
                last_show: Mutex::new(None),
                last_tray_render: Mutex::new(String::new()),
            });

            // Right-click menu.
            let open_item = MenuItem::with_id(app, "open", "Open Silly Motivation", true, None::<&str>)?;
            let reset_item = MenuItem::with_id(app, "reset", "Reset Settings", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, Some("Cmd+Q"))?;
            let separator = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&open_item, &separator, &reset_item, &quit_item])?;

            // --- platform-specific tray construction -------------------------
            // macOS: monochrome template glyph + live title text.
            // Windows/Linux: counter rendered into the icon + tooltip.
            #[cfg(target_os = "macos")]
            let tray_builder = {
                let initial_title = {
                    let state = app.state::<AppState>();
                    let guard = state.settings.lock().unwrap();
                    tray_title(&guard)
                };
                let tray_icon =
                    tauri::image::Image::from_bytes(include_bytes!("../icons/tray-template.png"))?;
                TrayIconBuilder::with_id(TRAY_ID)
                    .icon(tray_icon)
                    .icon_as_template(true)
                    .title(&initial_title)
            };

            #[cfg(not(target_os = "macos"))]
            let tray_builder = {
                let (compact, tooltip) = {
                    let state = app.state::<AppState>();
                    let guard = state.settings.lock().unwrap();
                    tray_compact_and_tooltip(&guard)
                };
                let icon = tray_text::render_icon(&compact)
                    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
                TrayIconBuilder::with_id(TRAY_ID)
                    .icon(icon)
                    .tooltip(&tooltip)
            };

            tray_builder
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show_popover(app, None),
                    "reset" => {
                        let state = app.state::<AppState>();
                        {
                            let mut guard = state.settings.lock().unwrap();
                            *guard = Settings::default();
                        }
                        let defaults = Settings::default();
                        let _ = persist_settings(app, &defaults);
                        refresh_tray(app);
                        show_popover(app, None);
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                // NOTE: tray click events only exist on macOS and Windows.
                // Linux (libappindicator) never delivers them — there, both
                // clicks open the context menu and the popover is opened via
                // the menu's "Open" item instead.
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        rect,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        let state = app.state::<AppState>();

                        // If the popover just auto-hid because this very click
                        // stole its focus, treat the click as "close" and stop.
                        // Consume the marker so the NEXT click opens immediately.
                        let recently_hidden = {
                            let mut guard = state.last_auto_hide.lock().unwrap();
                            let recent = guard
                                .map(|t| t.elapsed() < Duration::from_millis(400))
                                .unwrap_or(false);
                            *guard = None;
                            recent
                        };

                        if recently_hidden {
                            return;
                        }

                        let visible = app
                            .get_webview_window("main")
                            .and_then(|w| w.is_visible().ok())
                            .unwrap_or(false);

                        if visible {
                            hide_popover(app);
                        } else {
                            show_popover(app, Some(&rect));
                        }
                    }
                })
                .build(app)?;

            spawn_tray_updater(app.handle().clone());

            // First launch: open the popover so the user can set their salary.
            {
                let state = app.state::<AppState>();
                let configured = state.settings.lock().unwrap().configured;
                if !configured {
                    show_popover(app.handle(), None);
                }
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            // Behave like a real menu bar popover: hide when focus is lost.
            if let WindowEvent::Focused(false) = event {
                if window.label() == "main" && window.is_visible().unwrap_or(false) {
                    let app = window.app_handle();
                    let state = app.state::<AppState>();

                    // Ignore focus-loss arriving right after a show (e.g. the
                    // popover failing to take key focus over a fullscreen
                    // Space) — hiding here would make it flash and vanish.
                    let just_shown = state
                        .last_show
                        .lock()
                        .unwrap()
                        .map(|t| t.elapsed() < Duration::from_millis(300))
                        .unwrap_or(false);
                    if just_shown {
                        return;
                    }

                    *state.last_auto_hide.lock().unwrap() = Some(Instant::now());
                    hide_popover(app);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            get_earnings,
            hide_window,
            quit_app
        ])
        .run(tauri::generate_context!())
        .expect("error while running Silly Motivation");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn western_grouping() {
        assert_eq!(group_digits("1234567", false), "1,234,567");
        assert_eq!(group_digits("123", false), "123");
        assert_eq!(group_digits("1", false), "1");
        assert_eq!(group_digits("1000", false), "1,000");
    }

    #[test]
    fn indian_grouping() {
        assert_eq!(group_digits("1234567", true), "12,34,567");
        assert_eq!(group_digits("12345678", true), "1,23,45,678");
        assert_eq!(group_digits("123", true), "123");
        assert_eq!(group_digits("1234", true), "1,234");
        assert_eq!(group_digits("100000", true), "1,00,000");
    }

    #[test]
    fn money_formatting() {
        assert_eq!(format_money(1234.5, 2, false), "1,234.50");
        assert_eq!(format_money(123456.789, 2, true), "1,23,456.79");
        assert_eq!(format_money(0.0, 2, false), "0.00");
        assert_eq!(format_money(-5.0, 2, false), "0.00"); // negatives clamp to zero
    }

    #[test]
    fn adaptive_tray_decimals() {
        assert_eq!(tray_decimals(2.5), 2); // big rate → 2 decimals
        assert_eq!(tray_decimals(0.0386), 3); // ₹1L/month → 3 decimals
        assert_eq!(tray_decimals(0.0038), 4); // ₹10k/month → 4 decimals
        assert_eq!(tray_decimals(0.0), 2); // unset → 2 decimals
    }

    #[test]
    fn earnings_are_sane() {
        let settings = Settings {
            monthly_salary: 100_000.0,
            configured: true,
            ..Default::default()
        };
        let earnings = compute_earnings(&settings);
        assert!(earnings.earned >= 0.0);
        assert!(earnings.earned <= 100_000.0);
        assert!(earnings.per_second > 0.0);
        assert!(earnings.month_progress >= 0.0 && earnings.month_progress <= 1.0);
        assert!(earnings.total_secs > 27.0 * 86_400.0); // at least 28 days
        assert!(earnings.total_secs < 32.0 * 86_400.0); // at most 31 days
        assert_eq!(earnings.month_total, 100_000.0);
    }

    #[test]
    fn compact_amounts_western() {
        assert_eq!(compact_amount(0.0, false), "0");
        assert_eq!(compact_amount(2628.4, false), "2628");
        assert_eq!(compact_amount(9999.0, false), "9999");
        assert_eq!(compact_amount(84_567.0, false), "84.6k");
        assert_eq!(compact_amount(845_000.0, false), "845k");
        assert_eq!(compact_amount(1_200_000.0, false), "1.2M");
        assert_eq!(compact_amount(2_000_000_000.0, false), "2B");
        // values that round up to the next tier get promoted
        assert_eq!(compact_amount(999_999.0, false), "1M");
        assert_eq!(compact_amount(99_999.0, false), "100k");
    }

    #[test]
    fn compact_amounts_tier_promotion_indian() {
        assert_eq!(compact_amount(9_999_999.0, true), "1Cr");
        assert_eq!(compact_amount(99_999.0, true), "1L");
    }

    #[test]
    fn compact_amounts_indian() {
        assert_eq!(compact_amount(2628.4, true), "2628");
        assert_eq!(compact_amount(84_567.0, true), "84567");
        assert_eq!(compact_amount(850_000.0, true), "8.5L");
        assert_eq!(compact_amount(10_000_000.0, true), "1Cr");
        assert_eq!(compact_amount(125_000_000.0, true), "12.5Cr");
    }

    #[test]
    fn compact_amounts_fit_tray() {
        // everything must fit in ~6 characters, even absurd inputs
        for v in [
            0.0, 1.0, 999.0, 9999.0, 99_999.0, 999_999.0, 9_999_999.0, 1e9, 1e12, 1e15,
        ] {
            for indian in [true, false] {
                let s = compact_amount(v, indian);
                assert!(s.len() <= 6, "'{s}' too long for a tray icon ({v}, indian={indian})");
            }
        }
        assert_eq!(compact_amount(5.0e12, false), "LOTS");
    }

    #[test]
    fn unconfigured_tray_title() {
        let settings = Settings::default();
        assert_eq!(tray_title(&settings), "set me up");
    }

    #[test]
    fn configured_tray_title_has_currency() {
        let settings = Settings {
            monthly_salary: 100_000.0,
            configured: true,
            ..Default::default()
        };
        let title = tray_title(&settings);
        assert!(title.starts_with("₹"));
    }
}
