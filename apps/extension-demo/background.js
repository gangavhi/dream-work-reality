async function getSettings() {
  const { selectedProfileName } = await chrome.storage.local.get({
    selectedProfileName: ""
  });
  return { selectedProfileName: normalizeProfileName(selectedProfileName) };
}

function normalizeProfileName(name) {
  return String(name || "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function profileIdFromName(name) {
  const n = normalizeProfileName(name);
  return n ? `profile-${n.replace(/[^a-z0-9]+/g, "-")}` : "profile-unknown";
}

function profileKeyField(profileName) {
  const n = normalizeProfileName(profileName);
  return n ? { profile_key: n } : {};
}

function normalizeCapturedFields(fields) {
  const out = { ...(fields || {}) };
  const email = out.guardian_email || out.email || out.guardianEmail;
  const phone =
    out.guardian_phone ||
    out.phone ||
    out.mobile_phone ||
    out.mobilePhone ||
    out.guardianPhone;
  if (!out.guardian_email && email) out.guardian_email = email;
  if (!out.guardian_phone && phone) out.guardian_phone = phone;
  return out;
}

async function saveManualEntry({ profileName, fields }) {
  const id = profileIdFromName(profileName);
  const normalized = normalizeCapturedFields(fields);
  const displayName =
    normalized.display_name ||
    normalized.full_name ||
    normalized.name ||
    profileName;

  const payload = {
    id,
    display_name: String(displayName || profileName),
    fields: { ...profileKeyField(profileName), ...normalized }
  };

  const resp = await fetch("http://127.0.0.1:18081/manual-entry", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });

  if (!resp.ok) {
    throw new Error(`Core API save failed: HTTP ${resp.status}`);
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    const { selectedProfileName } = await getSettings();
    if (!selectedProfileName) {
      sendResponse({ ok: false, error: "No profile selected in extension popup." });
      return;
    }

    if (msg?.type === "DW_GET_PROFILE") {
      const id = profileIdFromName(selectedProfileName);
      const resp = await fetch(`http://127.0.0.1:18081/manual-entry/${encodeURIComponent(id)}`);
      if (resp.status === 404) {
        sendResponse({ ok: true, profileName: selectedProfileName, values: {} });
        return;
      }
      if (!resp.ok) throw new Error(`Core API read failed: HTTP ${resp.status}`);
      const person = await resp.json();
      const fields = person?.fields || {};
      const values = { ...(fields || {}) };
      if (person?.display_name) values.display_name = person.display_name;
      sendResponse({ ok: true, profileName: selectedProfileName, values });
      return;
    }

    if (msg?.type === "DW_SAVE_FIELDS") {
      await saveManualEntry({ profileName: selectedProfileName, fields: msg.fields || {} });
      sendResponse({ ok: true });
      return;
    }
  })().catch((e) => {
    sendResponse({ ok: false, error: String(e?.message || e) });
  });
  return true;
});

