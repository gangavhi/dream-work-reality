# Brainstorming: filling a form in another app

This document explores **how** the companion product could help users complete forms that appear **inside a third-party native app** (banking, benefits, school portal app, etc.)—not only in a web browser. The companion app holds **local structured memory** populated by **OCR/parsers** and **generative structuring** (same dynamic-schema model as in `idea-brainstorming.md`). It focuses on **technical feasibility** and **platform guardrails** on **iOS**, **Android**, and **macOS**. It is **brainstorming**, not a shipping spec or legal review.

**Related docs:** `idea-brainstorming.md` (scenario B/C tablet and phone), `features-list.md`, `how-secure-is-the-data-locally.md`.

---

## 1. What “fill another app’s form” means

| Interpretation | Description |
|----------------|-------------|
| **A — True in-app automation** | Our app (or an extension) **reads** another app’s UI, **finds** text fields, and **writes** values into them with minimal user steps. |
| **B — Assisted handoff** | Our app **does not** touch the other app’s widgets directly; it shows **structured values** and the user **copies**, **pastes**, or uses **OS share** / **drag-and-drop** where available. |
| **C — OS autofill integration** | We register as an **Autofill provider** (Android) or participate in **Password AutoFill** workflows (iOS) so the **system** offers our data when the other app’s fields are focused—subject to field type and OS rules. |

The **privacy story** (“data stays on device”) is compatible with all three, but **A** has the highest **review, abuse, and security** scrutiny.

---

## 2. Why this is hard (shared constraints)

- **Sandboxing:** Apps cannot arbitrarily read another app’s memory or view hierarchy—by design.
- **No “DOM” in native UI:** Unlike HTML, native controls are **not** a single document tree exposed to strangers; discovery relies on **accessibility trees**, **autofill APIs**, or **user-mediated** transfer.
- **Abuse potential:** Anything that can **inject text into other apps** can be misused for **fraud** or **credential stuffing**. Stores and OS vendors **limit** or **gate** such capabilities.

So feasibility is less “can we build a perfect bot?” and more “which **narrow, user-consented** paths exist per platform?”

---

## 3. Apple iOS (iPhone / iPad)

### 3.1 Guardrails in practice

- **App sandbox:** Third-party apps cannot inspect or control another app’s views without **special entitlements** or **user-granted** capabilities.
- **Accessibility:** **VoiceOver** and the accessibility APIs expose a **semantic tree** (labels, roles, values) so assistive technologies can navigate apps. Technically, a **custom accessibility client** could *in theory* traverse another app’s UI **if** the user grants **full accessibility** permission to our app (similar to some automation utilities).  
  - **Risk:** Apple **scrutinizes** apps that use accessibility for non-accessibility purposes; rejection or removal is possible if the behavior looks like **remote control** or **malware-like** automation.
- **AutoFill / Passwords:** iOS routes some fields through **Password AutoFill** and **Associated Domains**; that model is **web- and credential-centric**. Native apps can adopt **ASCredentialIdentityStore**-style flows in specific cases, but **general “fill any UITextField with arbitrary household JSON”** is **not** an open API.
- **Clipboard:** Universal pasteboard—**feasible** but **user-mediated**; we already document copy-based fallback. **Paste** requires user focus in the target field (or paste action).
- **Share extensions / intents:** Good for **handing a file or text** into another app, not for **mapping** field-by-field into arbitrary forms.
- **Screen-based automation (visual OCR + tap):** Theoretically possible with **screen recording** + ML; **extremely** fragile, high battery use, and **privacy-hostile** if mis-implemented. Not aligned with a **trust-first** product unless extremely bounded and user-visible.

### 3.2 Feasibility summary (iOS)

| Approach | Feasibility | Notes |
|----------|-------------|--------|
| **Copy / paste / share sheet (B)** | **High** | Aligns with App Store norms; no special entitlements beyond normal app. |
| **System AutoFill–style deep integration (C)** | **Low–medium** for arbitrary household fields | Strong for **passwords**; limited for **rich custom schemas** across random apps. |
| **Accessibility-driven fill (A)** | **Technically possible**, **product/policy risky** | Depends on user enabling **full accessibility** for our app; Apple review and user trust are the bottleneck. |

**Bottom line:** On iOS, a **credible v1** for “another app” is **assisted handoff (B)** plus **excellent UX** (clipboard queue, field checklist, optional **Shortcuts** user installs). **Full automation (A)** is the hardest to justify under Apple’s security and review model.

---

## 4. Google Android (phone / tablet)

### 4.1 Relevant mechanisms

- **Autofill framework (Android 8+):** Apps can implement an **`AutofillService`**. When the user focuses a field in **another** app, the system can ask our service for **suggestions** based on **field hints** (email, phone, name, etc.).  
  - **Feasibility:** **Medium–high** for fields that map to standard **autofill hints**. **Lower** for arbitrary custom labels unless we invest in **heuristics** and **saved mappings** per app (still on-device).  
  - **Guardrails:** Service must be **declared** in manifest; user must **select** our app as autofill provider in system settings; **scoped** to what the OS exposes.
- **Accessibility services:** Can **observe** and **interact** with other apps’ UI. Used by assistive tech and, historically, by automation tools—**heavily** flagged by Google as **high risk**.  
  - **Play policy:** Using accessibility for **non-accessibility** purposes can lead to **policy violations** or required disclosures. **Feasibility:** technically strong for (A); **business/review risk** is the constraint.
- **Overlay / bubbles:** `SYSTEM_ALERT_WINDOW` for floating UI—possible for **our** copy UI; does not by itself fill foreign fields without accessibility or autofill.
- **Intent / share:** Same as iOS—good for **documents**, not full form mapping.

### 4.2 Feasibility summary (Android)

| Approach | Feasibility | Notes |
|----------|-------------|--------|
| **Autofill provider (C)** | **Medium–high** for standard field types | Best “official” path for cross-app assist; needs user opt-in in settings. |
| **Copy / paste / overlay helper (B)** | **High** | Safest default story. |
| **Accessibility automation (A)** | **Technically high**, **policy risk** | Must align with **Google Play** policies and **disclosure** requirements. |

**Bottom line:** Android offers a **more structured** path than iOS for **Autofill-based** cross-app help; it is the most realistic place to pursue **semi-automatic** fill **without** fighting the OS—**if** field hints align. **Accessibility-based** full automation remains **sensitive**.

---

## 5. macOS

### 5.1 Relevant mechanisms

- **Accessibility APIs:** Apps can request **Accessibility** permission (user must approve in **System Settings → Privacy & Security**). With permission, apps can **inspect** other apps’ accessibility trees and **set values** on focused elements in some cases—similar in spirit to assistive tech.  
  - **Feasibility:** **Medium** for automation (A) on paper; **fragile** across app updates; **user trust** and **malware optics** matter.
- **Not sandboxed vs sandboxed:** **Mac App Store** sandboxed apps face **tighter** limits; **Developer ID / outside store** distribution can offer more capability at the cost of **distribution** and **notarization** scrutiny.
- **Apple Events / scripting:** Some apps expose **scripting**; **not** universal for random forms.
- **Browser vs native:** Our **Chrome extension + companion** path already covers **web** on Mac; “another app” here means **Slack, Zoom, native banking**, etc.

### 5.2 Feasibility summary (macOS)

| Approach | Feasibility | Notes |
|----------|-------------|--------|
| **Clipboard + companion panel (B)** | **High** | Low friction to ship. |
| **Accessibility-assisted fill (A)** | **Medium** (technical), **variable** (distribution) | Possible for power users; requires clear **permission** UX and **honest** failure modes. |
| **Autofill** | **Weaker** than Android’s unified service for arbitrary third-party native apps | Web and credentials are better covered than rich custom household schemas. |

**Bottom line:** macOS is **more permissive** than iOS for **user-approved** automation APIs, but **not** a free pass—**permission**, **sandbox**, and **review** (if App Store) still matter.

---

## 6. Cross-cutting product strategy (recommended direction)

1. **Tier 1 (all platforms):** **Assisted handoff**—structured preview, **per-field copy**, **keyboard switching** hints, optional **queue** of values for long forms. **No** special OS permissions beyond normal app.
2. **Tier 2 (platform-specific):** **Android Autofill service** as the **primary** “native” integration for standard field types; **iOS** focus on **Shortcuts** / **Share** / **clipboard** until/unless a compliant autofill-related path matures for our data model.
3. **Tier 3 (optional, high scrutiny):** **Accessibility-based** automation only with **explicit** user education, **minimal scope**, **auditability**, and **legal/product** review—**not** a launch default on iOS.

---

## 7. Alignment with our privacy model

- **No server-side** fill: all candidate mechanisms keep **payload generation** on-device.
- **User consent layers:** OS-level permissions (Accessibility, Autofill provider) must be **transparent** and **revocable**.
- **Honest marketing:** “We can help with **any** app’s form” is **false**; “We help **where the OS allows** and fall back to **copy/paste**” is **defensible**.

---

## 8. Open questions

1. **Minimum viable** “other app” story for v1: **Tier 1 only** vs invest in **Android Autofill** early?
2. **Per-app allowlists** for any semi-automatic path to reduce abuse surface?
3. **Enterprise** distribution (MDM) where **policy** allows more controlled assist—separate SKU?

---

## 9. Summary

| Platform | Easiest credible path | Hardest path |
|----------|------------------------|--------------|
| **iOS** | Copy/paste + guided UI; narrow system integrations | Unrestricted automation of other apps’ fields |
| **Android** | Same + **AutofillService** for hinted fields | Unrestricted accessibility automation without policy risk |
| **macOS** | Same + user-granted **Accessibility** for power users | Universal, reliable automation across all apps |

**Technical feasibility:** **Yes**, for **user-mediated** and **OS-sanctioned** channels (especially **Android Autofill**). **Full silent automation** of arbitrary third-party apps is **not** reliably feasible **and** not aligned with **Apple/Google** guardrails without heavy tradeoffs in **policy**, **review**, and **trust**.

This document should be revisited when **minimum OS versions** and **store policies** are chosen for the product.
