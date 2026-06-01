/* ============================================================
   SILLY MOTIVATION — frontend brain
   Talks to the Rust backend, spins the odometer, dispenses wisdom.
   ============================================================ */

"use strict";

// ---------------------------------------------------------------------------
// Tauri bridge (falls back to a mock when opened in a plain browser)
// ---------------------------------------------------------------------------

const tauri = window.__TAURI__;

const invoke = tauri
  ? tauri.core.invoke
  : (() => {
      // Browser mock so the UI can be previewed standalone.
      // Open ui/index.html?preview=counter[&salary=10000000] to preview states.
      const previewParams = new URLSearchParams(location.search);
      const previewCounter = previewParams.get("preview") === "counter";
      const previewSalary = parseFloat(previewParams.get("salary")) || 100000;
      let mockSettings = {
        monthly_salary: previewCounter ? previewSalary : 0,
        currency_symbol: "₹",
        currency_code: "INR",
        indian_grouping: true,
        configured: previewCounter,
      };
      const mockEarnings = () => {
        const now = new Date();
        const start = new Date(now.getFullYear(), now.getMonth(), 1);
        const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
        const total = (end - start) / 1000;
        const elapsed = (now - start) / 1000;
        const progress = elapsed / total;
        return {
          earned: mockSettings.monthly_salary * progress,
          per_second: mockSettings.monthly_salary / total,
          month_total: mockSettings.monthly_salary,
          elapsed_secs: elapsed,
          total_secs: total,
          month_progress: progress,
          computed_at_ms: Date.now(),
          day_of_month: now.getDate(),
          days_in_month: Math.round(total / 86400),
        };
      };
      return async (cmd, args) => {
        switch (cmd) {
          case "get_settings":
            return { ...mockSettings };
          case "save_settings":
            mockSettings = { ...args.settings, configured: args.settings.monthly_salary > 0 };
            return mockEarnings();
          case "get_earnings":
            return mockEarnings();
          default:
            return null;
        }
      };
    })();

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let settings = null;
let snapshot = null; // last earnings snapshot from backend
let snapshotAtPerf = 0; // performance.now() when snapshot was taken
let rafId = null;
let resyncTimer = null;
let fortuneTimer = null;
let fortuneIndex = -1;

// ---------------------------------------------------------------------------
// DOM
// ---------------------------------------------------------------------------

const $ = (id) => document.getElementById(id);

const viewCounter = $("view-counter");
const viewSettings = $("view-settings");
const odometerEl = $("odometer");
const currencySymbolEl = $("currency-symbol");
const rateValueEl = $("rate-value");
const progressFillEl = $("progress-fill");
const progressDayEl = $("progress-day");
const progressPctEl = $("progress-pct");
const fortuneTextEl = $("fortune-text");
const settingsTitleEl = $("settings-title");
const settingsSubEl = $("settings-sub");
const salaryInput = $("salary-input");
const salaryPrefix = $("salary-prefix");
const currencyGrid = $("currency-grid");
const chipCustom = $("chip-custom");
const customCurrencyEl = $("custom-currency");
const customSymbolInput = $("custom-symbol");
const customCodeInput = $("custom-code");
const indianGroupingInput = $("indian-grouping");
const formError = $("form-error");
const saveBtn = $("save-btn");
const saveBtnText = saveBtn.querySelector(".save-btn-text");
const backBtn = $("back-btn");

// ---------------------------------------------------------------------------
// Money math + formatting
// ---------------------------------------------------------------------------

/** Current interpolated earnings value. */
function currentValue() {
  if (!snapshot) return 0;
  const elapsed = (performance.now() - snapshotAtPerf) / 1000;
  const value = snapshot.earned + snapshot.per_second * elapsed;
  return Math.min(value, snapshot.month_total); // never exceed the month's salary
}

/** Group an integer string: Indian (1,23,45,678) or western (12,345,678). */
function groupDigits(intStr, indian) {
  const n = intStr.length;
  let out = "";
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const fromRight = n - i;
      const comma = indian
        ? fromRight === 3 || (fromRight > 3 && (fromRight - 3) % 2 === 0)
        : fromRight % 3 === 0;
      if (comma) out += ",";
    }
    out += intStr[i];
  }
  return out;
}

function formatMoney(amount, decimals, indian) {
  const fixed = Math.max(0, amount).toFixed(decimals);
  const [intPart, decPart] = fixed.split(".");
  const grouped = groupDigits(intPart, indian);
  return decPart ? `${grouped}.${decPart}` : grouped;
}

/** How many decimals the popover odometer shows (more for tiny rates). */
function odoDecimals(perSecond) {
  if (perSecond >= 1 || perSecond <= 0) return 2;
  return Math.min(4, Math.ceil(-Math.log10(perSecond)) + 1);
}

// ---------------------------------------------------------------------------
// Odometer
// ---------------------------------------------------------------------------

// base (unscaled) cell metrics — must stay in sync with styles.css
const CELL = {
  int: { w: 30, h: 52, font: 30 },
  dec: { w: 24, h: 42, font: 22 },
};

let odoCells = []; // [{strip, place, height}] — place is the power-of-ten divisor

/** Count grouping commas for an integer of `n` digits. */
function countCommas(n, indian) {
  let count = 0;
  for (let fromRight = 1; fromRight < n; fromRight++) {
    const comma = indian
      ? fromRight === 3 || (fromRight > 3 && (fromRight - 3) % 2 === 0)
      : fromRight % 3 === 0;
    if (comma) count++;
  }
  return count;
}

function buildOdometer(maxValue, decimals, indian) {
  odometerEl.innerHTML = "";
  odoCells = [];

  const intDigits = Math.max(1, String(Math.floor(Math.max(1, maxValue))).length);
  const commas = countCommas(intDigits, indian);

  // Scale-to-fit: compute the odometer's natural width at scale 1, then shrink
  // uniformly so it always fits the space left next to the currency symbol.
  const hero = document.querySelector(".counter-hero");
  const heroWidth = hero && hero.clientWidth > 0 ? hero.clientWidth : 324;
  const symbolWidth = Math.max(currencySymbolEl.getBoundingClientRect().width, 14);
  const available = heroWidth - symbolWidth - 10;

  const naturalWidth =
    intDigits * (CELL.int.w + 3) + // int cells + margins
    decimals * (CELL.dec.w + 3) + // decimal cells + margins
    commas * (26 * 0.62 + 2) + // comma separators (Menlo ~0.62em advance)
    (30 * 0.62 + 2); // decimal point

  const scale = Math.max(0.4, Math.min(1, available / naturalWidth));

  // integer cells, most significant first (group separators added between cells)
  for (let i = intDigits - 1; i >= 0; i--) {
    addCellWithSeparator(i, intDigits, indian, scale);
  }

  // decimal point
  addSeparator(".", scale, true);

  // decimal cells
  for (let d = 1; d <= decimals; d++) {
    addCell(Math.pow(10, -d), true, scale);
  }
}

function addSeparator(char, scale, isPoint) {
  const sep = document.createElement("span");
  sep.className = "odo-sep" + (isPoint ? " point" : "");
  sep.textContent = char;
  sep.style.fontSize = `${Math.round((isPoint ? 30 : 26) * scale)}px`;
  odometerEl.appendChild(sep);
}

/** Adds the comma (if grouping calls for one) then the integer cell for 10^i. */
function addCellWithSeparator(i, intDigits, indian, scale) {
  const fromRight = i + 1; // 1-based position from the right
  const isLeftmost = fromRight === intDigits;

  if (!isLeftmost) {
    // a comma sits to the LEFT of this digit if this digit starts a new group
    const startsGroup = indian
      ? fromRight === 3 || (fromRight > 3 && (fromRight - 3) % 2 === 0)
      : fromRight % 3 === 0;
    if (startsGroup) {
      addSeparator(",", scale, false);
    }
  }

  addCell(Math.pow(10, i), false, scale);
}

function addCell(place, isDecimal, scale) {
  const m = isDecimal ? CELL.dec : CELL.int;
  const w = Math.round(m.w * scale);
  const h = Math.round(m.h * scale);
  const font = Math.round(m.font * scale);

  const cell = document.createElement("div");
  cell.className = "odo-cell" + (isDecimal ? " decimal" : "");
  cell.style.width = `${w}px`;
  cell.style.height = `${h}px`;

  const strip = document.createElement("div");
  strip.className = "odo-strip";

  // 0–9 plus a wraparound 0 for seamless 9→0 rolls
  for (let d = 0; d <= 10; d++) {
    const digit = document.createElement("div");
    digit.className = "odo-digit";
    digit.textContent = String(d % 10);
    digit.style.height = `${h}px`;
    digit.style.fontSize = `${font}px`;
    strip.appendChild(digit);
  }

  cell.appendChild(strip);
  odometerEl.appendChild(cell);
  odoCells.push({ strip, place, height: h });
}

function renderOdometer(value) {
  // Mechanical odometer cascade: the fastest (last) wheel spins continuously;
  // each slower wheel only rolls while the wheel below it sweeps from 9 → 0.
  // This keeps the number readable at every instant.
  let carry = 0;
  for (let i = odoCells.length - 1; i >= 0; i--) {
    const cell = odoCells[i];
    let pos;
    if (i === odoCells.length - 1) {
      pos = (value / cell.place) % 10; // continuous spin
    } else {
      pos = (Math.floor(value / cell.place) % 10) + carry;
    }
    // how far this wheel is past "9" → fractional roll handed to the next wheel up
    carry = Math.max(0, pos - 9);
    cell.strip.style.transform = `translateY(${-pos * cell.height}px)`;
  }
}

// ---------------------------------------------------------------------------
// Counter view rendering
// ---------------------------------------------------------------------------

function startCounter() {
  stopCounter();

  // set the symbol BEFORE building so scale-to-fit can measure its width
  currencySymbolEl.textContent = settings.currency_symbol;
  const decimals = odoDecimals(snapshot.per_second);
  buildOdometer(snapshot.month_total, decimals, settings.indian_grouping);

  // rate line
  const rateDecimals = Math.min(6, Math.max(2, decimals + 1));
  rateValueEl.textContent = `+${settings.currency_symbol}${formatMoney(
    snapshot.per_second,
    rateDecimals,
    settings.indian_grouping
  )}`;

  // month progress
  updateProgress();

  // animation loop
  const tick = () => {
    renderOdometer(currentValue());
    rafId = requestAnimationFrame(tick);
  };
  rafId = requestAnimationFrame(tick);

  // periodic re-sync with the backend (handles sleep/wake, month rollover)
  resyncTimer = setInterval(resync, 15000);

  // silly messages
  startFortunes();
}

function stopCounter() {
  if (rafId) cancelAnimationFrame(rafId);
  if (resyncTimer) clearInterval(resyncTimer);
  if (fortuneTimer) clearInterval(fortuneTimer);
  rafId = null;
  resyncTimer = null;
  fortuneTimer = null;
}

async function resync() {
  try {
    const fresh = await invoke("get_earnings");
    const monthChanged =
      snapshot && Math.abs(fresh.month_total - snapshot.month_total) < 1e-9 &&
      fresh.elapsed_secs < snapshot.elapsed_secs - 60; // big backwards jump = new month
    snapshot = fresh;
    snapshotAtPerf = performance.now();
    updateProgress();
    if (monthChanged) {
      // new month: rebuild so leading zeros reset
      startCounter();
    }
  } catch (e) {
    /* backend briefly unavailable — keep interpolating */
  }
}

function updateProgress() {
  if (!snapshot) return;
  const pct = snapshot.month_progress * 100;
  progressFillEl.style.width = `${pct.toFixed(2)}%`;
  progressDayEl.textContent = `DAY ${snapshot.day_of_month} OF ${snapshot.days_in_month}`;
  progressPctEl.textContent = `${pct.toFixed(1)}% CONQUERED`;
}

// ---------------------------------------------------------------------------
// Silly messages
// ---------------------------------------------------------------------------

const FORTUNES = [
  "You earn {sleep} every single night just by sleeping. Literal dream job.",
  "Each blink earns you {blink}. Blink twice if you love money.",
  "That 10-minute bathroom break? {poop}. Sponsored by your employer. 🚽",
  "Reading this sentence just earned you {sec5}. You're welcome.",
  "Money printer goes brrrrr 🖨️ — and the printer is YOU.",
  "One hour of pretending to work = {hour}. Acting is lucrative.",
  "Your boss is literally paying you to read silly messages right now.",
  "Compound interest is for nerds. This is REAL-TIME income, baby.",
  "You: existing. Also you: getting paid {persec} every second for it.",
  "That meeting that could've been an email? Still earned you {meeting}. 📧",
  "Coffee break = {coffee} of sponsored hydration. Sip slower. ☕",
  "Every doomscroll session is technically a micro-payday. 📱",
  "Your chair has no idea it's a money-making machine. 🪑",
  "Today alone you've already printed {today}. Look at you go.",
  "Somewhere, a spreadsheet just updated in your favor. Cha-ching.",
  "Existential dread? In THIS economy? You're earning through it.",
  "You make {hour} an hour. Even at 3 AM. ESPECIALLY at 3 AM.",
  "A salary is just a subscription your company pays for your existence.",
  "Don't call it Monday. Call it +{hour}-per-hour day.",
  "Procrastination station? More like compensation station. 🚂",
  "Naps are just unpaid-looking paid activities. 😴",
  "Your plants are growing. Your money is growing. Everything is fine.",
  "Inhale. Exhale. That breath was worth {blink}. Breathe more.",
  "Weekend? You mean two days of getting paid to not be there.",
];

function fillFortune(template) {
  if (!snapshot || !settings) return template;
  const sym = settings.currency_symbol;
  const ind = settings.indian_grouping;
  const ps = snapshot.per_second;
  const fmt = (v) => {
    const decimals = v >= 100 ? 0 : v >= 1 ? 2 : Math.min(4, Math.ceil(-Math.log10(Math.max(v, 1e-9))) + 1);
    return sym + formatMoney(v, decimals, ind);
  };

  // seconds since local midnight, for {today}
  const now = new Date();
  const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const secsToday = (now - midnight) / 1000;

  return template
    .replace("{sleep}", fmt(ps * 8 * 3600))
    .replace("{blink}", fmt(ps * 0.3))
    .replace("{poop}", fmt(ps * 600))
    .replace("{sec5}", fmt(ps * 5))
    .replace("{hour}", fmt(ps * 3600))
    .replace("{persec}", fmt(ps))
    .replace("{meeting}", fmt(ps * 3600))
    .replace("{coffee}", fmt(ps * 900))
    .replace("{today}", fmt(ps * secsToday));
}

function nextFortune() {
  // pick a random message that isn't the current one
  let idx;
  do {
    idx = Math.floor(Math.random() * FORTUNES.length);
  } while (idx === fortuneIndex && FORTUNES.length > 1);
  fortuneIndex = idx;

  fortuneTextEl.classList.add("swapping");
  setTimeout(() => {
    fortuneTextEl.textContent = fillFortune(FORTUNES[fortuneIndex]);
    fortuneTextEl.classList.remove("swapping");
  }, 400);
}

function startFortunes() {
  // first one immediately (no fade delay)
  fortuneIndex = Math.floor(Math.random() * FORTUNES.length);
  fortuneTextEl.textContent = fillFortune(FORTUNES[fortuneIndex]);
  fortuneTimer = setInterval(nextFortune, 7000);
}

// ---------------------------------------------------------------------------
// View switching
// ---------------------------------------------------------------------------

function showCounterView() {
  viewSettings.hidden = true;
  viewCounter.hidden = false;
  startCounter();
}

function showSettingsView() {
  stopCounter();
  viewCounter.hidden = true;
  viewSettings.hidden = false;

  const isFirstRun = !settings.configured;
  settingsTitleEl.innerHTML = isFirstRun ? "LET'S GET<br/>SILLY RICH" : "ADJUST THE<br/>MACHINE";
  settingsSubEl.textContent = isFirstRun
    ? "Tell the machine what you make. It does the rest."
    : "Change your numbers. The printer adapts instantly.";
  saveBtnText.textContent = isFirstRun ? "START THE MONEY PRINTER" : "UPDATE THE PRINTER";
  // a configured user can always bail back to their counter
  backBtn.hidden = isFirstRun;

  // pre-fill current settings
  if (settings.monthly_salary > 0) {
    salaryInput.value = String(settings.monthly_salary);
  }
  salaryPrefix.textContent = settings.currency_symbol;
  selectChipFromSettings();
}

// ---------------------------------------------------------------------------
// Settings form
// ---------------------------------------------------------------------------

let chosenCurrency = { symbol: "₹", code: "INR", indian: true, custom: false };

function selectChipFromSettings() {
  const chips = currencyGrid.querySelectorAll(".chip");
  let matched = false;

  chips.forEach((chip) => {
    chip.classList.remove("selected");
    if (!chip.dataset.custom && chip.dataset.code === settings.currency_code) {
      chip.classList.add("selected");
      matched = true;
      chosenCurrency = {
        symbol: chip.dataset.symbol,
        code: chip.dataset.code,
        indian: chip.dataset.indian === "true",
        custom: false,
      };
    }
  });

  if (!matched && settings.configured) {
    // custom currency in use
    chipCustom.classList.add("selected");
    customCurrencyEl.hidden = false;
    customSymbolInput.value = settings.currency_symbol;
    customCodeInput.value = settings.currency_code;
    indianGroupingInput.checked = settings.indian_grouping;
    chosenCurrency = {
      symbol: settings.currency_symbol,
      code: settings.currency_code,
      indian: settings.indian_grouping,
      custom: true,
    };
  } else if (!matched) {
    // default: INR
    chips[0].classList.add("selected");
    customCurrencyEl.hidden = true;
  } else {
    customCurrencyEl.hidden = true;
  }
}

currencyGrid.addEventListener("click", (e) => {
  const chip = e.target.closest(".chip");
  if (!chip) return;

  currencyGrid.querySelectorAll(".chip").forEach((c) => c.classList.remove("selected"));
  chip.classList.add("selected");

  if (chip.dataset.custom) {
    customCurrencyEl.hidden = false;
    chosenCurrency = {
      symbol: customSymbolInput.value || "💵",
      code: customCodeInput.value || "???",
      indian: indianGroupingInput.checked,
      custom: true,
    };
    customSymbolInput.focus();
  } else {
    customCurrencyEl.hidden = true;
    chosenCurrency = {
      symbol: chip.dataset.symbol,
      code: chip.dataset.code,
      indian: chip.dataset.indian === "true",
      custom: false,
    };
  }
  salaryPrefix.textContent = chosenCurrency.symbol;
});

customSymbolInput.addEventListener("input", () => {
  chosenCurrency.symbol = customSymbolInput.value || "💵";
  salaryPrefix.textContent = chosenCurrency.symbol;
});

customCodeInput.addEventListener("input", () => {
  chosenCurrency.code = customCodeInput.value.trim() || "???";
});

indianGroupingInput.addEventListener("change", () => {
  chosenCurrency.indian = indianGroupingInput.checked;
});

function parseSalary(raw) {
  // lenient: strip currency symbols, commas, spaces; keep digits and one dot
  const cleaned = raw.replace(/[^\d.]/g, "");
  const value = parseFloat(cleaned);
  return Number.isFinite(value) ? value : NaN;
}

$("settings-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  formError.hidden = true;

  const salary = parseSalary(salaryInput.value);
  if (!Number.isFinite(salary) || salary <= 0) {
    formError.textContent = "Enter a salary above zero. The printer needs fuel. ⛽";
    formError.hidden = false;
    return;
  }

  const newSettings = {
    monthly_salary: salary,
    currency_symbol: chosenCurrency.symbol,
    currency_code: chosenCurrency.code,
    indian_grouping: chosenCurrency.indian,
    configured: true,
  };

  try {
    saveBtn.disabled = true;
    const earnings = await invoke("save_settings", { settings: newSettings });
    settings = { ...newSettings };
    snapshot = earnings;
    snapshotAtPerf = performance.now();

    // celebrate 🎉
    saveBtn.classList.add("saved");
    saveBtnText.textContent = "PRINTER ACTIVATED! 🎉";
    burstConfetti();

    setTimeout(() => {
      saveBtn.classList.remove("saved");
      saveBtn.disabled = false;
      showCounterView();
    }, 900);
  } catch (err) {
    saveBtn.disabled = false;
    formError.textContent = typeof err === "string" ? err : "Something broke. The printer is embarrassed.";
    formError.hidden = false;
  }
});

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

function burstConfetti() {
  const layer = $("confetti-layer");
  const emoji = ["💸", "💰", "🤑", "💵", "🪙", "✨"];
  for (let i = 0; i < 36; i++) {
    const piece = document.createElement("span");
    piece.className = "confetti";
    piece.textContent = emoji[Math.floor(Math.random() * emoji.length)];
    piece.style.left = `${Math.random() * 100}%`;
    piece.style.animationDuration = `${1.2 + Math.random() * 1.6}s`;
    piece.style.animationDelay = `${Math.random() * 0.4}s`;
    piece.style.fontSize = `${12 + Math.random() * 14}px`;
    layer.appendChild(piece);
    setTimeout(() => piece.remove(), 3500);
  }
}

// ---------------------------------------------------------------------------
// Buttons + keyboard
// ---------------------------------------------------------------------------

$("close-btn").addEventListener("click", () => invoke("hide_window"));
$("quit-btn").addEventListener("click", () => invoke("quit_app"));
$("edit-settings-btn").addEventListener("click", showSettingsView);
backBtn.addEventListener("click", async () => {
  // discard unsaved edits: re-fetch persisted settings, return to the counter
  await boot();
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") invoke("hide_window");
});

// ---------------------------------------------------------------------------
// Lifecycle: the Rust backend tells us when the popover is shown/hidden.
// On every show we re-derive the whole view from persisted state, so Reset,
// abandoned edits, and out-of-band changes are always reflected correctly.
// ---------------------------------------------------------------------------

if (tauri) {
  tauri.event.listen("popover-shown", () => {
    boot();
  });
  tauri.event.listen("popover-hidden", () => {
    stopCounter();
  });
}

// secondary safety net (also drives the standalone browser preview)
document.addEventListener("visibilitychange", async () => {
  if (document.hidden) {
    stopCounter();
  } else if (settings && settings.configured && !viewCounter.hidden && !rafId) {
    await resync();
    startCounter();
  }
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

async function boot() {
  try {
    settings = await invoke("get_settings");
  } catch (e) {
    settings = {
      monthly_salary: 0,
      currency_symbol: "₹",
      currency_code: "INR",
      indian_grouping: true,
      configured: false,
    };
  }

  if (settings.configured && settings.monthly_salary > 0) {
    snapshot = await invoke("get_earnings");
    snapshotAtPerf = performance.now();
    showCounterView();
  } else {
    showSettingsView();
  }
}

boot();
