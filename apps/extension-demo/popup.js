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
  const payload = {
    id: profileIdFromName(profileName),
    display_name: profileName
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
    throw new Error(`Read failed: HTTP ${response.status}`);
  }
  const person = await response.json();
  if (!person.display_name) {
    throw new Error("No display_name returned from core-api.");
  }
  return {
    display_name: person.display_name,
    date_of_birth: "2012-09-14",
    guardian_name: "Jordan Carter",
    guardian_phone: "+1-555-010-0199",
    guardian_email: "jordan.carter@example.com",
    address_line_1: "2457 Meadowbrook Ave",
    city: "Austin",
    state: "TX",
    postal_code: "78701",
    insurance_provider: "Acme Health",
    policy_number: "ACME-9921-4438"
  };
}

async function fillActiveTab(data) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No active tab.");

  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    args: [data],
    func: (formData) => {
      Object.entries(formData).forEach(([key, value]) => {
        const input = document.getElementById(key) || document.querySelector(`[name="${key}"]`);
        if (input) {
          input.value = value;
          input.dispatchEvent(new Event("input", { bubbles: true }));
          input.dispatchEvent(new Event("change", { bubbles: true }));
        }
      });
    }
  });
}

document.getElementById("seed").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    setStatus(`Seeding profile "${profileName}" into core-api...`);
    await seedPerson(profileName);
    setStatus("Seed complete.");
  } catch (error) {
    setStatus(`Seed error:\n${error.message}`);
  }
});

document.getElementById("fill").addEventListener("click", async () => {
  try {
    const profileName = await getSelectedProfileName();
    setStatus(`Loading profile "${profileName}" from core-api...`);
    const data = await loadPerson(profileName);
    await fillActiveTab(data);
    setStatus("Form filled on active tab.");
  } catch (error) {
    setStatus(`Fill error:\n${error.message}`);
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
