# Local LLM POC Setup Guide

On-device LLM inference using [`llama_cpp_dart`](https://github.com/netdur/llama_cpp_dart) 0.9.x.  
The engine runs a GGUF model directly on the iPad/Android device — no network required after setup.

---

## How It Works

```
PocConfig.llmEngineMode = LlmEngineMode.local
    ↓
LlmEngineFactory.getEngine() → LocalLlmEngine
    ↓
LlamaEngine (worker isolate, off main thread)
    ↓
GGUF model on-device (Metal GPU on iPad)
    ↓
http.Response with same JSON format as cloud engine
```

The `LocalLlmEngine` is a drop-in replacement for `CloudLlmEngine`.  
All response parsing, retry logic, and call sites in `main.dart` are unchanged.

---

## Step 1 — Download the Native Binary

The Dart package ships no native code — you must download the prebuilt binary from GitHub Releases.

**iOS (xcframework):**

1. Go to: https://github.com/netdur/llama_cpp_dart/releases/latest
2. Download `llama.xcframework.zip`
3. Unzip it → you get `llama.xcframework/`

**Android (AAR):**

1. Go to: https://github.com/netdur/llama_cpp_dart/releases/latest
2. Download `llama-cpp-dart.aar` (CPU version) or `llama-cpp-dart-hexagon.aar` (Snapdragon NPU)

---

## Step 2 — Add Native Binary to Project

### iOS

1. Open the project in Xcode:
   ```
   open ios/Runner.xcworkspace
   ```
2. In the **Project Navigator**, select the `Runner` project (top item).
3. Select the **Runner** target → **General** tab → scroll to **Frameworks, Libraries, and Embedded Content**.
4. Click **+** → **Add Other…** → **Add Files…**
5. Navigate to and select `llama.xcframework`.
6. Set the embed option to **Embed & Sign**.
7. Close Xcode.

### Android

1. Create the libs directory if it doesn't exist:
   ```bash
   mkdir -p android/app/libs
   ```
2. Copy the AAR:
   ```bash
   cp /path/to/llama-cpp-dart.aar android/app/libs/
   ```
3. Open `android/app/build.gradle.kts` and add inside the `dependencies` block:
   ```kotlin
   implementation(files("libs/llama-cpp-dart.aar"))
   ```

---

## Step 3 — Choose and Download a GGUF Model

Recommended models for iPad (balance of speed and quality):

| Model | Size | Notes |
|-------|------|-------|
| `Phi-3.5-mini-instruct-Q4_K_M.gguf` | ~2.2 GB | Best quality for AAC use case |
| `Phi-3-mini-4k-instruct-q4.gguf` | ~2.2 GB | Slightly smaller context |
| `Qwen2.5-1.5B-Instruct-Q4_K_M.gguf` | ~1.0 GB | Faster, smaller |
| `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` | ~0.4 GB | Fastest (for quick first test) |

Download from [Hugging Face](https://huggingface.co) — search the model name + `GGUF`.

**Quick download example (Qwen 0.5B for fast first test):**
```bash
# Install huggingface_hub CLI if needed
pip install huggingface_hub

huggingface-cli download Qwen/Qwen2.5-0.5B-Instruct-GGUF \
  qwen2.5-0.5b-instruct-q4_k_m.gguf \
  --local-dir ~/Downloads/models/
```

---

## Step 4 — Copy Model to Device

### iOS (via Xcode File Sharing)

1. Connect iPad via USB.
2. Open Xcode → **Window** → **Devices and Simulators**.
3. Select your iPad → scroll down to **Installed Apps** → select **Bravo AAC**.
4. Click the **+** button under the app's Documents section.
5. Navigate to your downloaded `.gguf` file and add it.

The model will be placed in the app's Documents directory.  
Path will be: `/var/mobile/Containers/Data/Application/<UUID>/Documents/<filename>.gguf`

### Android (via adb)

```bash
adb push ~/Downloads/models/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  /sdcard/Android/data/com.yourapp/files/
```

---

## Step 5 — Configure the App

In `lib/services/llm_engine.dart`, update `PocConfig`:

```dart
class PocConfig {
  // Switch engine to local:
  static LlmEngineMode llmEngineMode = LlmEngineMode.local;

  // Set model filename (resolved against app Documents dir automatically):
  static String localModelFilename = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';

  // Or set full absolute path (overrides filename auto-resolution):
  // static String localModelPath = '/full/path/to/model.gguf';

  // GPU layers — 99 = all layers on iPad Metal GPU (fastest):
  static int localModelGpuLayers = 99;
}
```

---

## Step 6 — Run and Test

```bash
# Run on connected iPad
flutter run -d <iPad-device-id>

# Or run in release mode (faster inference):
flutter run --release -d <iPad-device-id>
```

When an LLM button is tapped for the first time, you'll see in the debug console:
```
🤖 LLM ENGINE: local (llama_cpp_dart on-device)
🤖 LocalLlmEngine: loading model from /path/to/model.gguf …
🤖 LocalLlmEngine: model ready
🤖 LocalLlmEngine raw output: [{"option": "..."}]
```

Model load takes 2–10 seconds depending on model size. Subsequent queries are fast since the model stays warm in memory.

---

## Switching Back to Cloud

```dart
// In lib/services/llm_engine.dart:
static LlmEngineMode llmEngineMode = LlmEngineMode.cloud;
```

Hot-restart the app. No other changes needed.

---

## Troubleshooting

**`LlamaEngine` fails to spawn / `libllama` not found**  
→ Confirm the xcframework was added to Xcode with "Embed & Sign" (iOS) or AAR is in `android/app/libs/` with Gradle dependency (Android).

**Model file not found error in debug log**  
→ Confirm the `.gguf` file name in `PocConfig.localModelFilename` exactly matches the file transferred to the device (case-sensitive).

**First query returns `[]` (empty options)**  
→ Check debug log for `🤖 LocalLlmEngine error:` lines. Usually a model path or library linking issue.

**Inference is slow (>30s per query)**  
→ Ensure `PocConfig.localModelGpuLayers = 99` (Metal GPU acceleration). If running debug build, switch to `--release`.

**Build fails after adding package**  
→ Run `flutter pub get` then `cd ios && pod install && cd ..` to pick up the new Dart dependency.

---

## Performance Expectations (iPad)

| Model | Load Time | Query Time (release) | Quality |
|-------|-----------|---------------------|---------|
| Qwen2.5-0.5B Q4 | ~2s | ~3–8s | Basic |
| Qwen2.5-1.5B Q4 | ~4s | ~8–15s | Good |
| Phi-3.5-mini Q4 | ~8s | ~15–30s | Best |

Times are approximate on iPad Air M1. Metal GPU acceleration required for these numbers.
