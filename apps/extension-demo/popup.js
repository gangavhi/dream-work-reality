const statusEl = document.getElementById("status");
const profileSelectEl = document.getElementById("profileSelect");
const newProfileNameEl = document.getElementById("newProfileName");

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
  const { profiles, selectedProfileName } = await chrome.storage.local.get({
    profiles: ["wife", "daughter", "son"],
    selectedProfileName: "wife"
  });
  const unique = Array.from(new Set((profiles || []).map(normalizeProfileName).filter(Boolean)));
  const selected = normalizeProfileName(selectedProfileName) || unique[0] || "wife";
  return { profiles: unique.length ? unique : ["wife"], selectedProfileName: selected };
}

async function setStoredProfiles({ profiles, selectedProfileName }) {
  await chrome.storage.local.set({ profiles, selectedProfileName });
}

async function refreshProfileUI() {
  const { profiles, selectedProfileName } = await getStoredProfiles();
  profileSelectEl.innerHTML = "";
  profiles.forEach((p) => {
    const opt = document.createElement("option");
    opt.value = p;
    opt.textContent = p;
    if (p === selectedProfileName) opt.selected = true;
    profileSelectEl.appendChild(opt);
  });
}

async function getSelectedProfileName() {
  const { selectedProfileName } = await getStoredProfiles();
  return selectedProfileName;
}

async function seedPerson(profileName) {
  const defaults = buildProfileDefaults(profileName);
  const payload = {
    id: profileIdFromName(profileName),
    display_name: defaults.display_name || profileName,
    fields: { ...profileKeyField(profileName), ...defaults }
  };
  const response = await fetch("http://127.0.0.1:18081/manual-entry", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    throw new Error(`Seed failed: HTTP ${response.status}`);
  }
}

async function loadPerson(profileName) {
  const id = profileIdFromName(profileName);
  const response = await fetch(`http://127.0.0.1:18081/manual-entry/${encodeURIComponent(id)}`);
  if (!response.ok) {
    // If the record doesn't exist yet, create a minimal one and continue with local profile defaults.
    if (response.status === 404) {
      await seedPerson(profileName);
      return buildProfileDefaults(profileName);
    }
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
      display_name: "Sahasra Kota",
      first_name: "Sahasra",
      last_name: "Kota",
      // Demo form uses MM/DD/YYYY.
      date_of_birth: "03/24/2023",
      guardian_name: "Sreenivasulu Kota",
      guardian_email: "sreenivasulu.kota@gmail.com",
      guardian_phone: "+1 678 2306669",
      address_line_1: "2528 Burnely Ct",
      city: "Celina",
      state: "TX",
      postal_code: "75009",
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
      const out = {};
      const els = Array.from(document.querySelectorAll("input, textarea, select"));
      for (const el of els) {
        const id = normalize(el.id);
        const name = normalize(el.getAttribute("name") || "");
        const key = id || name;
        if (!key) continue;

        let value = "";
        const tag = (el.tagName || "").toLowerCase();
        if (tag === "select") {
          value = normalize(el.value);
        } else {
          value = normalize(el.value);
        }
        if (!value) continue;
        out[key] = value;
      }
      return out;
    }
  });

  return (result && typeof result === "object") ? result : {};
}

async function savePersonFromForm(profileName) {
  const fields = await collectActiveTabValues();
  // Normalize common aliases into canonical keys used by the demo form + core-api.
  // This makes "email"/"phone"/"mobile_phone" still persist into guardian_email/guardian_phone.
  const normalized = { ...profileKeyField(profileName), ...fields };
  const email = fields.guardian_email || fields.email || fields.guardianEmail;
  const phone =
    fields.guardian_phone ||
    fields.phone ||
    fields.mobile_phone ||
    fields.mobilePhone ||
    fields.guardianPhone;
  if (!normalized.guardian_email && email) normalized.guardian_email = email;
  if (!normalized.guardian_phone && phone) normalized.guardian_phone = phone;

  const payload = {
    id: profileIdFromName(profileName),
    display_name: normalized.display_name || buildProfileDefaults(profileName).display_name || profileName,
    fields: normalized
  };
  const response = await fetch("http://127.0.0.1:18081/manual-entry", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    throw new Error(`Save failed: HTTP ${response.status}`);
  }
}

document.getElementById("seed").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    // If the user has already typed into the active form, treat this as "save" so
    // the UX matches expectations (seed/update the selected profile).
    const existing = await collectActiveTabValues();
    const hasAny = Object.values(existing).some((v) => String(v || "").trim().length > 0);
    if (hasAny) {
      setStatus(`Saving active form fields into "${profileName}"...`);
      await savePersonFromForm(profileName);
      setStatus("Saved to core-api.");
    } else {
      setStatus(`Seeding profile "${profileName}" into core-api...`);
      await seedPerson(profileName);
      setStatus("Seed complete.");
    }
  } catch (error) {
    setStatus(`Seed error:\n${error.message}`);
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

document.getElementById("saveFromForm").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    setStatus(`Saving active form fields into "${profileName}"...`);
    await savePersonFromForm(profileName);
    setStatus("Saved to core-api. Next Fill will use stored values.");
  } catch (error) {
    setStatus(`Save error:\n${error.message}`);
  }
});

profileSelectEl.addEventListener("change", async () => {
  const selected = normalizeProfileName(profileSelectEl.value);
  const { profiles } = await getStoredProfiles();
  await setStoredProfiles({ profiles, selectedProfileName: selected });
  setStatus(`Selected profile: ${selected}`);
});

document.getElementById("addProfile").addEventListener("click", async () => {
  const name = normalizeProfileName(newProfileNameEl.value);
  if (!name) return;
  const { profiles } = await getStoredProfiles();
  const next = Array.from(new Set([...profiles, name]));
  await setStoredProfiles({ profiles: next, selectedProfileName: name });
  newProfileNameEl.value = "";
  await refreshProfileUI();
  setStatus(`Added profile: ${name}`);
});

document.getElementById("removeProfile").addEventListener("click", async () => {
  const { profiles, selectedProfileName } = await getStoredProfiles();
  const remaining = profiles.filter((p) => p !== selectedProfileName);
  const nextSelected = remaining[0] || "wife";
  await setStoredProfiles({ profiles: remaining.length ? remaining : [nextSelected], selectedProfileName: nextSelected });
  await refreshProfileUI();
  setStatus(`Removed profile. Selected: ${nextSelected}`);
});

// Init
refreshProfileUI().catch((e) => setStatus(`Init error:\n${e.message}`));
