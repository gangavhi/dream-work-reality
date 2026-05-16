const statusEl = document.getElementById("status");
const profileSelectEl = document.getElementById("profileSelect");

function setStatus(message) {
  statusEl.textContent = message;
}

function normalizeProfileName(name) {
  return String(name || "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function profileIdFromName(name) {
  // Core API demo uses an id string. We derive it from the profile name.
  const n = normalizeProfileName(name);
  return n ? `profile-${n.replace(/[^a-z0-9]+/g, "-")}` : "profile-unknown";
}

function profileKeyField(profileName) {
  const n = normalizeProfileName(profileName);
  return n ? { profile_key: n } : {};
}

async function getStoredProfiles() {
  const { selectedProfileName } = await chrome.storage.local.get({
    selectedProfileName: ""
  });
  return { selectedProfileName: normalizeProfileName(selectedProfileName) };
}

async function setStoredProfiles({ selectedProfileName }) {
  await chrome.storage.local.set({ selectedProfileName });
}

async function fetchPeopleProfiles() {
  // Returns array of profile_key strings from core-api's persisted People.
  const resp = await fetch("http://127.0.0.1:18081/manual-entry/profile-keys");
  if (!resp.ok) throw new Error(`Core API unavailable: HTTP ${resp.status}`);
  const rows = await resp.json();
  const keys = (Array.isArray(rows) ? rows : [])
    .map((r) => normalizeProfileName(r?.profile_key || ""))
    .filter(Boolean);
  return Array.from(new Set(keys));
}

async function refreshProfileUI() {
  const { selectedProfileName: storedSelected } = await getStoredProfiles();
  let profiles = [];
  try {
    profiles = await fetchPeopleProfiles();
  } catch (e) {
    setStatus(`Core API not reachable.\nStart demo/core-api then reopen popup.\n\n${e?.message || e}`);
    profileSelectEl.innerHTML = "";
    profileSelectEl.disabled = true;
    return;
  }

  profileSelectEl.disabled = false;
  profileSelectEl.innerHTML = "";
  if (!profiles.length) {
    setStatus("No People profiles found in core-api yet.");
    return;
  }

  // Default selection: stored selection if valid; otherwise prefer alex carter if present.
  const preferred = profiles.find((p) => p === "alex carter") || profiles[0];
  const selected = profiles.includes(storedSelected) ? storedSelected : preferred;
  if (selected !== storedSelected) {
    await setStoredProfiles({ selectedProfileName: selected });
  }

  profiles.forEach((p) => {
    const opt = document.createElement("option");
    opt.value = p;
    opt.textContent = p;
    if (p === selected) opt.selected = true;
    profileSelectEl.appendChild(opt);
  });
}

async function getSelectedProfileName() {
  const v = normalizeProfileName(profileSelectEl?.value || "");
  if (v) return v;
  const { selectedProfileName } = await getStoredProfiles();
  return normalizeProfileName(selectedProfileName);
}

async function loadPerson(profileName) {
  const id = profileIdFromName(profileName);
  const response = await fetch(`http://127.0.0.1:18081/manual-entry/${encodeURIComponent(id)}`);
  if (!response.ok) {
    // If the record doesn't exist yet, just fall back to local defaults.
    if (response.status === 404) return buildProfileDefaults(profileName);
    throw new Error(`Read failed: HTTP ${response.status}`);
  }
  const person = await response.json();
  const defaults = buildProfileDefaults(profileName);
  const displayName = person.display_name || defaults.display_name || profileName;
  const storedFields = person.fields || {};
  // Prefer stored core-api fields, then fall back to extension defaults.
  const merged = { ...defaults, ...storedFields, display_name: displayName };

  // Normalize DOB so forms consistently get MM/DD/YYYY under `date_of_birth`.
  if (!merged.date_of_birth && merged.date_of_birth_mmddyyyy) {
    merged.date_of_birth = merged.date_of_birth_mmddyyyy;
  }
  if (!merged.date_of_birth_mmddyyyy && merged.date_of_birth) {
    merged.date_of_birth_mmddyyyy = merged.date_of_birth;
  }
  return merged;
}

function buildProfileDefaults(profileName) {
  const name = normalizeProfileName(profileName);

  // For now, keep defaults local in the extension.
  // This gives immediate multi-profile autofill even before core-api stores all fields.
  if (name === "daughter") {
    return {
      display_name: "Demo Child",
      first_name: "Demo",
      last_name: "Lee",
      // Demo form uses MM/DD/YYYY.
      date_of_birth: "03/24/2023",
      guardian_name: "Alex Carter",
      guardian_email: "guardian@example.com",
      guardian_phone: "+1 555-555-5555",
      address_line_1: "2528 Burnely Ct",
      city: "Ridgewood",
      state: "TX",
      postal_code: "78701",
      insurance_provider: "UHG",
      policy_number: "1234"
    };
  }

  if (name === "son") {
    return {
      display_name: "Son",
      date_of_birth: ""
    };
  }

  if (name === "wife") {
    return {
      display_name: "Wife",
      date_of_birth: ""
    };
  }

  // Generic fallback
  return {
    display_name: profileName
  };
}

async function fillActiveTab(data) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No active tab.");

  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    args: [data],
    func: (formData) => {
      const allInputs = Array.from(document.querySelectorAll("input, textarea, select"));
      const normalize = (s) => (s || "").toString().trim().toLowerCase();

      function bestLabelFor(el) {
        const id = el.id;
        const name = el.getAttribute("name") || "";
        const placeholder = el.getAttribute("placeholder") || "";
        const aria = el.getAttribute("aria-label") || "";
        let labelText = "";
        if (id) {
          const lbl = document.querySelector(`label[for="${CSS.escape(id)}"]`);
          if (lbl) labelText = lbl.textContent || "";
        }
        return normalize([labelText, aria, placeholder, name, id].filter(Boolean).join(" "));
      }

      // Canonical keys -> list of hints
      const hints = {
        first_name: ["first name", "given name", "fname"],
        last_name: ["last name", "surname", "family name", "lname"],
        display_name: ["full name", "display name", "student full name", "name"],
        date_of_birth: ["date of birth", "dob", "birth date", "birthday"],
        guardian_name: ["parent", "guardian", "parent or guardian", "guardian name", "parent name"],
        guardian_email: ["guardian email", "parent email", "email", "e-mail"],
        guardian_phone: ["guardian phone", "parent phone", "phone", "mobile", "cell"],
        height: ["height", "hgt", "ht"],
        eye_color: ["eye color", "eyes", "eye"],
        address_line_1: ["address", "street", "street address", "address line 1"],
        city: ["city", "town"],
        state: ["state", "province"],
        postal_code: ["zip", "zipcode", "postal"],
        insurance_provider: ["insurance provider", "provider", "insurance"],
        policy_number: ["policy number", "policy #", "member id", "policy id"]
      };

      function setValue(el, value) {
        if (value == null) return;
        const tag = el.tagName.toLowerCase();
        if (tag === "select") {
          // best-effort: match option text/value
          const v = value.toString();
          const opt = Array.from(el.options).find(o => o.value === v || normalize(o.textContent) === normalize(v));
          if (opt) el.value = opt.value;
        } else {
          el.value = value;
        }
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      }

      // Fill by exact id/name first
      Object.entries(formData).forEach(([key, value]) => {
        const el = document.getElementById(key) || document.querySelector(`[name="${CSS.escape(key)}"]`);
        if (el) setValue(el, value);
      });

      // Then fill remaining by label matching (“fill all active forms”)
      for (const el of allInputs) {
        const label = bestLabelFor(el);
        if (!label) continue;

        for (const [key, value] of Object.entries(formData)) {
          if (value == null || value === "") continue;
          const keyHints = hints[key];
          if (!keyHints) continue;
          if (keyHints.some(h => label.includes(h))) {
            // Always overwrite so switching profiles updates the form.
            setValue(el, value);
          }
        }
      }
    }
  });
}

async function collectActiveTabFields() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No active tab.");

  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => {
      const inputs = Array.from(document.querySelectorAll("input, textarea, select"));
      const normalize = (s) => (s || "").toString().trim();

      function labelFor(el) {
        if (el.id) {
          const lbl = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
          if (lbl) return normalize(lbl.textContent || "");
        }
        return "";
      }

      return inputs.map((el) => ({
        id: normalize(el.id),
        name: normalize(el.getAttribute("name") || ""),
        label: labelFor(el),
        placeholder: normalize(el.getAttribute("placeholder") || ""),
        aria_label: normalize(el.getAttribute("aria-label") || ""),
        type: normalize(el.getAttribute("type") || el.tagName.toLowerCase())
      }));
    }
  });

  return Array.isArray(result) ? result : [];
}

async function collectActiveTabValues() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No active tab.");

  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => {
      const normalize = (s) => (s || "").toString().trim();
      const normLower = (s) => normalize(s).toLowerCase();
      const out = {};
      const els = Array.from(document.querySelectorAll("input, textarea, select"));

      function bestLabelFor(el) {
        const id = normalize(el.id);
        const name = normalize(el.getAttribute("name") || "");
        const placeholder = normalize(el.getAttribute("placeholder") || "");
        const aria = normalize(el.getAttribute("aria-label") || "");
        let label = "";
        if (id) {
          const lbl = document.querySelector(`label[for="${CSS.escape(id)}"]`);
          if (lbl) label = normalize(lbl.textContent || "");
        }
        return normLower([label, aria, placeholder, name, id].filter(Boolean).join(" "));
      }

      function maybeAddCanonical(labelBlob, value) {
        if (!labelBlob || !value) return;
        const hints = {
          first_name: ["first name", "given name", "fname"],
          last_name: ["last name", "surname", "family name", "lname"],
          display_name: ["full name", "display name", "name"],
          date_of_birth: ["date of birth", "dob", "birth date", "birthday"],
          email: ["email", "e-mail"],
          phone: ["phone", "mobile", "cell", "tel"],
          address_line_1: ["address", "street", "street address", "address line 1"],
          address_line_2: ["address line 2", "apt", "apartment", "suite", "unit"],
          city: ["city", "town"],
          state: ["state", "province", "region"],
          postal_code: ["zip", "zipcode", "postal"],
          country: ["country"]
        };
        for (const [key, list] of Object.entries(hints)) {
          if (out[key]) continue;
          if (list.some((h) => labelBlob.includes(h))) {
            out[key] = value;
            return;
          }
        }
      }

      for (const el of els) {
        const id = normalize(el.id);
        const name = normalize(el.getAttribute("name") || "");
        const key = id || name;

        let value = "";
        const tag = (el.tagName || "").toLowerCase();
        if (tag === "select") {
          value = normalize(el.value);
        } else {
          const t = normLower(el.getAttribute("type") || "");
          if (t === "password" || t === "file") continue;
          if (t === "checkbox") {
            if (!el.checked) continue;
            value = el.value ? normalize(el.value) : "true";
          } else if (t === "radio") {
            if (!el.checked) continue;
            value = normalize(el.value);
          } else {
            value = normalize(el.value);
          }
        }
        if (!value) continue;
        if (key) out[key] = value;

        const labelBlob = bestLabelFor(el);
        maybeAddCanonical(labelBlob, value);
      }
      return out;
    }
  });

  return (result && typeof result === "object") ? result : {};
}

async function deletePerson(id) {
  const response = await fetch(`http://127.0.0.1:18081/manual-entry/${encodeURIComponent(id)}`, {
    method: "DELETE"
  });
  if (!response.ok) {
    throw new Error(`Delete failed: HTTP ${response.status}`);
  }
  const body = await response.json().catch(() => ({}));
  if (!body.deleted) {
    throw new Error("Profile not deleted (not found?)");
  }
}

async function seedPerson() {
  const response = await fetch("http://127.0.0.1:18081/manual-entry", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id: "person-42", display_name: "Alex Carter" })
  });
  if (!response.ok) {
    throw new Error(`Seed failed: HTTP ${response.status}`);
  }
}

document.getElementById("seed").addEventListener("click", async () => {
  try {
    setStatus("Seeding person-42 in core-api...");
    await seedPerson();
    await refreshProfileUI();
    setStatus("Seeded person-42 (Alex Carter).");
  } catch (error) {
    setStatus(`Seed error:\n${error.message}`);
  }
});

document.getElementById("remove").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    const id = profileIdFromName(profileName);
    setStatus(`Removing ${id} from core-api...`);
    await deletePerson(id);
    await refreshProfileUI();
    setStatus(`Removed ${profileName}.`);
  } catch (error) {
    setStatus(`Remove error:\n${error.message}`);
  }
});

document.getElementById("fill").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    setStatus(`Mapping fields for "${profileName}"...`);

    const fields = await collectActiveTabFields();

    // Ask local mapping endpoint (acts as GenAI stub in demo).
    let mapped = null;
    try {
      const response = await fetch("http://127.0.0.1:18081/genai/map-fields", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ profile_name: profileName, fields })
      });
      if (response.ok) {
        const json = await response.json();
        mapped = json?.values || null;
      }
    } catch (_) {}

    // Fallback to local defaults/core-api display_name
    const data = await loadPerson(profileName);
    const finalData = mapped ? { ...data, ...mapped } : data;
    await fillActiveTab(finalData);
    setStatus("Form filled on active tab.");
  } catch (error) {
    setStatus(`Fill error:\n${error.message}`);
  }
});

profileSelectEl.addEventListener("change", async () => {
  const selected = normalizeProfileName(profileSelectEl.value);
  await setStoredProfiles({ selectedProfileName: selected });
  setStatus(`Selected profile: ${selected}`);
});

// Init
refreshProfileUI().catch((e) => setStatus(`Init error:\n${e.message}`));
