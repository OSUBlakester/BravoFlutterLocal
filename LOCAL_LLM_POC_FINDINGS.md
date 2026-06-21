# Local LLM POC — Findings & No-Go Decision

**Date:** May 5, 2026  
**Decision:** No-go. Reverted to cloud-only (`PocConfig.llmEngineMode = LlmEngineMode.cloud`).

---

## Objective

Evaluate whether on-device LLM inference could replace or supplement the cloud `/llm` endpoint for generating AAC communication options — with full offline capability and no latency regression.

---

## What Was Built

- **Runtime:** `llama_cpp_dart 0.9.0-dev.6` via `LlamaEngine.spawnFromProcess`
- **`LocalLlmEngine`** class in `lib/services/llm_engine.dart` — drop-in replacement for `CloudLlmEngine`, same interface
- **`PocConfig`** flags for toggling engine mode without touching user-facing settings
- **Auto-download pipeline:** model fetched on first launch, stored in app Documents directory
- **GPU acceleration:** Metal backend on iOS (A-series), all transformer layers on GPU (`localModelGpuLayers = 99`)
- **Dynamic token budget:** scales with requested option count (45 tokens/option), no hard cap on admin-specified counts (up to 50)
- **Early-stop streaming:** generation halts when valid JSON with the correct option count is detected

---

## Model Tested

| Property | Value |
|---|---|
| Model | Qwen2.5-3B-Instruct-Q4_K_M.gguf |
| Size | ~1.9 GB |
| Quantization | Q4_K_M |
| Source | [bartowski/Qwen2.5-3B-Instruct-GGUF](https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF) |
| Parameters | 3 billion |

---

## Test Hardware

| Property | Value |
|---|---|
| Device | iPad (A16 chip) |
| GPU backend | Apple Metal (confirmed active) |
| GPU layers | 99 / 99 (all on GPU) |
| Context size | 1024 tokens |

---

## Results

| Metric | Cloud Baseline | Local (on-device) |
|---|---|---|
| Latency (10 options) | ~3 seconds | ~15 seconds |
| Quality | Conversational, natural | Noticeably less conversational |
| GPU utilization | N/A | Full Metal acceleration active |
| Offline capability | ❌ | ✅ |

---

## Why It Failed the Requirements

### 1. Latency — 5× over target
- **Requirement:** 10 options in under 4 seconds
- **Actual:** ~15 seconds on iPad A16 with a 3B Q4 model and all layers on GPU
- At ~10–15 tokens/second on current Apple Silicon, this is near the hardware ceiling for the 3B parameter class. A 1.5B model might reach 6–8 seconds; a 0.5B model might approach 4 seconds.

### 2. Quality degrades faster than latency improves
- Any model small enough to approach the 4-second target (≤1B parameters) produces output quality well below the 3B model, which users already found "less conversational" than cloud.
- For AAC, degraded option quality is a direct communication harm — not a UX concern.

### 3. The 50-option case is a hard blocker
- Admin-specified option counts up to 50 must be honored (no capping).
- Even if 10 options hit 4 seconds, 50 options would push 20+ seconds on the same hardware. This is not solvable by prompt engineering.

### 4. Fully offline OR fully online — no hybrid
- A hybrid approach (local fast-path + cloud fallback) was considered and explicitly ruled out by product requirements.
- This removes the only architecture that could realistically meet both the latency and offline goals today.

---

## What Remains in the Codebase

The `LocalLlmEngine` implementation and `PocConfig` flags are **preserved but inactive** (engine mode is set to `cloud`). The `llama_cpp_dart` dependency remains in `pubspec.yaml`.

To re-activate for future evaluation:
```dart
// lib/services/llm_engine.dart — PocConfig
static LlmEngineMode llmEngineMode = LlmEngineMode.local;
```

---

## Conditions for Re-Evaluation

Local LLM becomes viable when **at least two** of the following improve:

1. **Hardware:** Apple Silicon NPU (Neural Engine) becomes accessible to third-party runtimes, or next-generation A-series chips push token throughput to 50–100 tokens/second
2. **Model compression:** Sub-2B models with quality parity to current 7B class (speculative decoding, distillation, or architectural advances)
3. **Runtime:** `llama_cpp_dart` or an equivalent gains first-class batch generation and speculative decoding on iOS/Android
4. **Requirements relax:** If the max option count drops to ≤10 and a 6–8 second latency is acceptable in offline scenarios

---

## Recommendation

Revisit in **12–18 months**. Watch for:
- Apple opening ANE (Apple Neural Engine) access to third-party ML runtimes
- `llama.cpp` speculative decoding maturing on mobile
- Sub-2B instruction-tuned models benchmarked specifically for structured JSON output
