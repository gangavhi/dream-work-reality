# TestFlight build 30 — multi-agent intelligence architecture (foundation)

**Version:** 1.1.0 (30)  
**Branch:** `ganga-2026-05-16-2`

## Shipped in this build

Modular **standalone-model agent pipeline** (software architecture + heuristic fallbacks until CoreML/GGUF artifacts ship):

| Module | Path | Status |
|--------|------|--------|
| Model registry | `Intelligence/Models/ModelArtifactRegistry.swift` | 9 model slots, lazy-load when `.mlmodelc` / GGUF present |
| Preprocessing | `Intelligence/Preprocessing/ImagePreprocessor.swift` | Contrast + horizon hint |
| Layout agent | `Intelligence/Agents/LayoutIntelligenceAgent.swift` | Heuristic layout; LayoutLM slot |
| Classification agent | `Intelligence/Agents/ClassificationAgent.swift` | Heuristic + Rust type; Phi/Qwen slot |
| Extraction agent | `Intelligence/Agents/ExtractionAgent.swift` | Hybrid extract + NER stub |
| Fraud agent | `Intelligence/Agents/FraudDetectionAgent.swift` | Heuristic PDF checks |
| Orchestrator | `Intelligence/Agents/DocumentIntelligenceOrchestrator.swift` | Wires all agents |
| Confidence engine | `Intelligence/Validation/ConfidenceOrchestrator.swift` | OCR + semantic + validation + grounding |
| Semantic mapping | `Intelligence/Embeddings/SemanticFieldLabelMapper.swift` | Synonym similarity; MiniLM slot |
| Knowledge graph | `Intelligence/Knowledge/DocumentKnowledgeGraph.swift` | Entity typing from fields |
| Vector memory | `Intelligence/Retrieval/VectorDocumentMemory.swift` | Local token search stub |
| Incremental learning | `Intelligence/Learning/IncrementalLearningStore.swift` | User correction capture on save |

## Still requires bundled models (not in IPA)

PaddleOCR, LayoutLMv3, DistilBERT NER, MiniLM CoreML, Qwen GGUF inference, fraud ML, VLM — registry shows **not installed** until artifacts added.

## Build

```bash
cd apps/ios && ./scripts/archive-for-testflight.sh RNBNZW828G
```
