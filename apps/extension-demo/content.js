function normalize(s) {
  return String(s || "").trim();
}

function normLower(s) {
  return normalize(s).toLowerCase();
}

function bestLabelFor(el) {
  const pick = (s) => (s == null ? "" : String(s));
  const id = pick(el.id);
  const name = pick(el.getAttribute("name"));
  const ph = pick(el.getAttribute("placeholder"));
  const aria = pick(el.getAttribute("aria-label"));
  const ariaLabelledBy = pick(el.getAttribute("aria-labelledby"));
  let label = "";
  if (id) {
    const lbl = document.querySelector(`label[for="${CSS.escape(id)}"]`);
    if (lbl) label = pick(lbl.textContent);
  }

  // aria-labelledby references (common in component libraries)
  let labelledByText = "";
  if (ariaLabelledBy) {
    const parts = ariaLabelledBy.split(/\s+/g).filter(Boolean);
    const texts = [];
    for (const pid of parts) {
      const n = document.getElementById(pid);
      if (n && n.textContent) texts.push(pick(n.textContent));
    }
    labelledByText = texts.join(" ");
  }

  // nearest wrapping label (e.g. <label><input ...> Text</label>)
  let parentLabelText = "";
  try {
    const p = el.closest("label");
    if (p && p.textContent) parentLabelText = pick(p.textContent);
  } catch (_) {}

  // nearby text for controls without label association (Athena does this a lot)
  let nearby = "";
  try {
    const container = el.closest("[role='group'], [role='radiogroup'], .field, .form-field, .question, .MuiFormControl-root") || el.parentElement;
    if (container && container.textContent) nearby = pick(container.textContent);
  } catch (_) {}

  return normLower([label, parentLabelText, labelledByText, aria, ph, name, id, nearby].filter(Boolean).join(" "));
}

function canonicalHints() {
  return {
    first_name: ["first name", "given name", "fname"],
    last_name: ["last name", "surname", "family name", "lname"],
    display_name: ["full name", "display name", "name"],
    date_of_birth: ["date of birth", "dob", "birth date", "birthday"],
    email: ["email", "e-mail"],
    phone: ["phone", "mobile", "cell", "tel"],
    phone_type: ["phone type", "type of phone", "phone kind"],
    address_line_1: ["address", "street", "street address", "address line 1"],
    address_line_2: ["address line 2", "apt", "apartment", "suite", "unit"],
    city: ["city", "town"],
    state: ["state", "province", "region"],
    postal_code: ["zip", "zipcode", "postal"],
    country: ["country"],

    // Athena / check-in flows
    is_patient: ["i am the patient", "i am not the patient", "patient"],
    insurance_provider: ["insurance provider", "insurance company", "payer", "plan"],
    member_id: ["member id", "subscriber id", "policy number", "policy #", "member number"],
    group_number: ["group number", "group #"],
    pharmacy: ["pharmacy", "preferred pharmacy"],
    medications: ["medications", "meds"],
    allergies: ["allergies"],
    social_history: ["social history"],
    health_history: ["health histories", "health history", "medical history"]

    ,
    preferred_language: ["preferred language", "language"],
    race: ["race"],
    hispanic_latino: ["hispanic or latino", "hispanic", "latino", "ethnicity"],
    marital_status: ["marital status"]
    ,
    adl_self_care_independent: ["care for yourself", "care for yourself independently", "activities of daily living"],
    walk_independent: ["walk independently", "without assistance", "assistive devices"],
    difficulty_walking_stairs: ["difficulty walking", "climbing stairs", "walking or climbing stairs"],
    transportation_difficulties: ["transportation difficulties", "difficulty with transportation", "transportation"]
    ,
    advance_directive: ["advance directive", "advanced directive", "living will", "health care proxy", "medical power of attorney"]
  };
}

function maybeAddCanonical(out, labelBlob, value) {
  if (!labelBlob || !value) return;
  const hints = canonicalHints();
  for (const [key, list] of Object.entries(hints)) {
    if (out[key]) continue;
    if (list.some((h) => labelBlob.includes(h))) {
      out[key] = value;
      return;
    }
  }
}

function collectFormValues() {
  const out = {};
  const els = Array.from(document.querySelectorAll("input, textarea, select"));
  for (const el of els) {
    const id = normalize(el.id);
    const name = normalize(el.getAttribute("name") || "");
    const key = id || name;
    const keyLower = normLower(key);

    const tag = (el.tagName || "").toLowerCase();
    let value = "";
    if (tag === "select") {
      // Prefer selected option text (more stable/human-friendly than internal value).
      const opt = el.selectedOptions && el.selectedOptions[0];
      value = normalize((opt && opt.textContent) ? opt.textContent : el.value);
    } else {
      const t = normalize(el.getAttribute("type") || "").toLowerCase();
      if (t === "password" || t === "file") continue;
      if (t === "checkbox") {
        if (!el.checked) continue;
        // Prefer human label text when possible.
        const lb = bestLabelFor(el);
        value = lb || (el.value ? normalize(el.value) : "true");
      } else if (t === "radio") {
        if (!el.checked) continue;
        // Prefer human label text when possible.
        const lb = bestLabelFor(el);
        value = lb || normalize(el.value);
      } else {
        value = normalize(el.value);
      }
    }
    if (!value) continue;

    // Skip common bot/anti-abuse tokens that should never be stored as "profile" info.
    const labelBlob = bestLabelFor(el);
    if (keyLower.includes("recaptcha") || keyLower.includes("token") || labelBlob.includes("recaptcha")) {
      continue;
    }

    // Save the raw key if present (best fidelity).
    if (key) {
      // If a site reuses names for checkbox groups, preserve multiple values.
      if (out[key] && out[key] !== value) {
        out[key] = `${out[key]} | ${value}`;
      } else {
        out[key] = value;
      }
    } else {
      // Fallback key when there is no id/name: stable-enough label blob.
      if (labelBlob) out[`dw_label__${labelBlob.slice(0, 80)}`] = value;
    }

    // Also save canonical fields (best-effort) so the profile stays useful across sites.
    maybeAddCanonical(out, labelBlob, value);
  }

  return out;
}

function setValue(el, value) {
  if (value == null) return false;
  const v = String(value);
  if (!v.trim()) return false;

  const tag = (el.tagName || "").toLowerCase();
  const t = normLower(el.getAttribute("type") || "");

  if (t === "file" || t === "password") return false;

  if (tag === "select") {
    const opts = Array.from(el.options || []);
    const match = opts.find((o) => String(o.value) === v || normLower(o.textContent) === normLower(v));
    if (!match) return false;
    el.value = match.value;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  if (t === "checkbox") {
    const truthy = ["true", "yes", "1", "on", "checked"];
    const shouldCheck = truthy.includes(normLower(v));
    if (el.checked !== shouldCheck) {
      el.checked = shouldCheck;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
    return true;
  }

  if (t === "radio") {
    // If this is a radio option, check it when it matches.
    const lb = bestLabelFor(el);
    const want = normLower(v);
    const matches =
      normLower(el.value) === want ||
      (lb && (lb === want || lb.includes(want))) ||
      // Common UX: stored value "yes"/"no" but the input value is numeric/opaque.
      (["yes", "no"].includes(want) && lb && lb.includes(want));
    if (matches) {
      if (!el.checked) {
        el.checked = true;
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      }
      return true;
    }
    return false;
  }

  try {
    el.value = v;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  } catch (_) {
    return false;
  }
}

function autoFillFromProfile(values) {
  if (!values || typeof values !== "object") return { filled: 0 };
  let filled = 0;

  const els = Array.from(document.querySelectorAll("input, textarea, select"));
  for (const el of els) {
    const id = normalize(el.id);
    const name = normalize(el.getAttribute("name") || "");
    const key = id || name;

    // exact key match
    if (key && values[key] != null && String(values[key]).trim()) {
      if (setValue(el, values[key])) filled += 1;
      continue;
    }

    // canonical match by label
    const labelBlob = bestLabelFor(el);
    if (!labelBlob) continue;

    // label-fallback key match (covers forms without stable id/name)
    const labelKey = `dw_label__${labelBlob.slice(0, 80)}`;
    if (values[labelKey] != null && String(values[labelKey]).trim()) {
      if (setValue(el, values[labelKey])) {
        filled += 1;
        continue;
      }
    }

    for (const [ckey, hints] of Object.entries(canonicalHints())) {
      if (!hints.some((h) => labelBlob.includes(h))) continue;
      const v = values[ckey];
      if (v == null || !String(v).trim()) continue;
      if (setValue(el, v)) filled += 1;
      break;
    }
  }

  // Special-case: simple “I am the patient / I am not the patient” screens.
  // Store as canonical `is_patient` when possible.
  const blob = normLower(document.body?.innerText || "");
  if (blob.includes("i am the patient") && blob.includes("i am not the patient")) {
    const isPatient = values.is_patient;
    const pick = (wantPatient) => {
      const radios = Array.from(document.querySelectorAll('input[type="radio"]'));
      for (const r of radios) {
        const lb = bestLabelFor(r);
        if (wantPatient && lb.includes("i am the patient")) return r;
        if (!wantPatient && lb.includes("i am not the patient")) return r;
      }
      return null;
    };
    if (typeof isPatient === "string" || typeof isPatient === "boolean") {
      const wantPatient = ["true", "yes", "1"].includes(normLower(String(isPatient)));
      const el = pick(wantPatient);
      if (el && setValue(el, el.value)) filled += 1;
    }
  }

  return { filled };
}

let timer = null;
let lastHash = "";

function stableHash(obj) {
  try {
    const keys = Object.keys(obj || {}).sort();
    const parts = [];
    for (const k of keys) parts.push(`${k}=${String(obj[k])}`);
    return parts.join("&");
  } catch (_) {
    return "";
  }
}

function scheduleSave() {
  if (timer) clearTimeout(timer);
  timer = setTimeout(async () => {
    timer = null;
    const fields = collectFormValues();
    const h = stableHash(fields);
    if (!h || h === lastHash) return;
    lastHash = h;
    try {
      // Add a canonical for “patient vs not patient” screens if present.
      const blob = normLower(document.body?.innerText || "");
      if (blob.includes("i am the patient") && blob.includes("i am not the patient")) {
        const selected = Array.from(document.querySelectorAll('input[type="radio"]')).find((r) => r.checked);
        if (selected) {
          const lb = bestLabelFor(selected);
          if (lb.includes("i am the patient")) fields.is_patient = "true";
          if (lb.includes("i am not the patient")) fields.is_patient = "false";
        }
      }

      await chrome.runtime.sendMessage({ type: "DW_SAVE_FIELDS", fields });
    } catch (_) {
      // ignore
    }
  }, 150);
}

function isContinueLike(text) {
  const t = normLower(text);
  if (!t) return false;
  // Common multi-step wizards (Athena + generic forms)
  return (
    t === "continue" ||
    t === "next" ||
    t === "submit" ||
    t === "save" ||
    t === "finish" ||
    t.startsWith("continue ") ||
    t.startsWith("next ")
  );
}

function buttonText(el) {
  if (!el) return "";
  const tag = (el.tagName || "").toLowerCase();
  if (tag === "input") return normalize(el.value || "");
  return normalize(el.innerText || el.textContent || "");
}

// Save only when the user advances the flow (per your preference).
document.addEventListener(
  "click",
  (e) => {
    const el = e.target?.closest?.("button, input[type='submit'], input[type='button'], a[role='button']");
    if (!el) return;
    const txt = buttonText(el);
    if (!isContinueLike(txt)) return;
    scheduleSave();
  },
  true
);

// Also save when leaving the page (covers Enter-key submits and SPA navigations).
window.addEventListener("pagehide", () => scheduleSave(), true);
window.addEventListener("beforeunload", () => scheduleSave(), true);

// Auto-fill once on load, and again after short delays (SPAs / dynamic forms).
async function tryAutoFill() {
  try {
    const resp = await chrome.runtime.sendMessage({ type: "DW_GET_PROFILE" });
    if (!resp?.ok) return;
    autoFillFromProfile(resp.values || {});
  } catch (_) {}
}

tryAutoFill();
setTimeout(tryAutoFill, 1500);
setTimeout(tryAutoFill, 4000);

