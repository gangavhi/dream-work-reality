This document serves as the **Master Engineering Specification** for the TrustNest platform. Coding agents and developers should use this as the single source of truth for architectural, functional, and UX requirements.

---

# TrustNest Master Specification: Privacy-First Household Automation

## 1. Project Overview & End Goal

TrustNest is an on-device, privacy-first mobile platform designed to act as a "digital nest" for household information.

* **End Goal:** Automate the filling of complex forms (insurance, school, medical) by intelligently retrieving and synthesizing data from a household's private, locally stored document collection.
* **Philosophy:** Human-in-the-loop. The AI does the heavy lifting, but the human remains in absolute control through transparent, verifiable evidence.

---

## 2. Technology Stack & Architecture

* **Database:** Single-file **SQLite** with the **`sqlite-vec`** extension.
* **Storage Pattern:** Hybrid Architecture (Relational metadata + Virtual Vector tables).
* **Execution:** On-device processing (Local LLM/OCR) to ensure data privacy. No data leaves the device without explicit user action.

### Database Schema (Relational Anchor Pattern)

```sql
-- Profiles: The household members (Mapped to UI "Circles")
CREATE TABLE profiles (
    individual_id TEXT PRIMARY KEY, 
    household_id TEXT NOT NULL,     
    name TEXT NOT NULL,
    relationship_type TEXT CHECK(relationship_type IN ('Primary', 'Spouse', 'Dependent'))
);

-- Documents: Metadata store
CREATE TABLE documents (
    doc_id TEXT PRIMARY KEY,
    individual_id TEXT NOT NULL,
    household_id TEXT NOT NULL,
    document_type TEXT,
    file_path TEXT NOT NULL,
    FOREIGN KEY(individual_id) REFERENCES profiles(individual_id)
);

-- Virtual Vector Table: Semantic index
CREATE VIRTUAL TABLE document_vectors USING vec0(
    embedding float[768]
);

```

---

## 3. User Experience: "The TrustNest Wheel"

The application is navigated via the "TrustNest Wheel" on the home screen.

* **The Wheel:** A central icon representing the household, surrounded by orbiting circles for each family member.
* **The ADD Node:** An always-present circle with a `+` icon to add new members.
* **Contextual Interaction:** * Tapping an "ADD" node triggers `ProfileManager`.
* Tapping a member circle activates that profile. All subsequent scans are automatically tagged with that `individual_id`.
* This provides a **seamless scan-to-profile** flow, ensuring every document is correctly categorized without manual effort.



---

## 4. Automated Form-Filling Engine

The platform uses a Retrieval-Augmented Generation (RAG) pipeline to populate forms:

1. **Field Parsing:** Forms are parsed into a list of required fields.
2. **Hybrid Retrieval:**
* **Constraint:** Never perform global search. Always filter by `household_id` and `individual_id`.
* **Logic:** Join `documents` and `document_vectors` on `rowid`. Use the semantic embedding of the form field to rank potential matches.


3. **Synthesis & Verification (Human-in-the-loop):**
* **Evidence Badges:** Every auto-filled field displays an `[Source: Document Name]` badge.
* **Verification:** Tapping the badge opens the original scanned document for instant human validation.
* **Conflict Handling:** If the AI finds conflicting information, it presents all candidates to the user rather than guessing.



---

## 5. Engineering Directives for Developers

1. **Background Threading:** All SQLite, vector, and LLM operations must execute on background threads to prevent UI blocking.
2. **ACID Compliance:** Wrap document/metadata ingestion in `BEGIN TRANSACTION` and `COMMIT` blocks to ensure the relational data and vector index never drift.
3. **Resource Management:** Use vector quantization (e.g., `sqlite-vec` quantization features) to minimize RAM usage.
4. **No Leaks:** Ensure the `household_id` is applied at the query level for **every** SQL operation to guarantee data isolation between families.

---

## 6. Implementation Checklist

* [ ] **UI:** Build the "TrustNest Wheel" widget (Central House, Member Circles, "ADD" node).
* [ ] **Data:** Implement `ProfileManager` for CRUD; setup `sqlite-vec` extension initialization.
* [ ] **Ingestion:** Create `processDocument(file, individual_id)` to handle OCR, embedding, and relational tagging.
* [ ] **Search:** Implement the hybrid search orchestrator that filters by metadata before similarity ranking.
* [ ] **Form Automation:** - [ ] Build the `ExtractField` service (Query -> Hybrid Search -> Local LLM Synthesis).
* [ ] Implement the UI "Evidence Badge" with document-viewer linking.
* [ ] Add the manual override callback to allow users to correct the AI.



---

### Pro-Tip for Coding Agents:

* When generating code, always prioritize the **Relationship Integrity**. If a document applies to multiple people, you may duplicate the metadata record (pointing to the same file path) so that each member's profile independently retrieves the shared document.
* **Always include inline comments** explaining the SQL join logic between `documents` and `document_vectors` so the code remains human-readable for future maintenance.