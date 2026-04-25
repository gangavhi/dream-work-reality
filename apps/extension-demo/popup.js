const statusEl = document.getElementById("status");

function setStatus(message) {
  statusEl.textContent = message;
}

async function seedPerson() {
  const payload = {
    id: "person-42",
    display_name: "Alex Carter"
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

async function loadPerson() {
  const response = await fetch("http://127.0.0.1:18081/manual-entry/person-42");
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
    setStatus("Seeding person into core-api...");
    await seedPerson();
    setStatus("Seed complete.");
  } catch (error) {
    setStatus(`Seed error:\n${error.message}`);
  }
});

document.getElementById("fill").addEventListener("click", async () => {
  try {
    setStatus("Loading person from core-api...");
    const data = await loadPerson();
    await fillActiveTab(data);
    setStatus("Form filled on active tab.");
  } catch (error) {
    setStatus(`Fill error:\n${error.message}`);
  }
});
