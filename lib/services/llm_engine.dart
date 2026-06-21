import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/environment_config.dart';
import 'authenticated_http_client.dart';

String _buildClientRequestId() {
  final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
  final hash = (micros ^ micros.hashCode).toUnsigned(32).toRadixString(16);
  return 'flutter-$micros-$hash';
}

String _buildClientPlatformStamp() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

// ---------------------------------------------------------------------------
// POC feature flags — not user-visible; changed by developers only.
// ---------------------------------------------------------------------------

/// Selects which LLM engine the app uses at runtime.
///
/// Default is [cloud]. Flip to [local] or [hybrid] for evaluation; both
/// fall back to [CloudLlmEngine] until the local engine is implemented.
enum LlmEngineMode { cloud, local, hybrid }

/// Compile-time / runtime POC configuration knobs.
///
/// Keep this class separate from user-facing settings so that none of the
/// feature-flag wiring ever touches [UserSettingsProvider] or the admin UI.
class PocConfig {
  PocConfig._(); // prevent instantiation

  /// Controls which LLM engine is used.
  /// Set to [LlmEngineMode.local] to test on-device inference via llama_cpp_dart.
  /// Switch back to [LlmEngineMode.cloud] to restore production behaviour.
  static LlmEngineMode llmEngineMode = LlmEngineMode.cloud;

  /// Full path to the GGUF model file on the device.
  ///
  /// If empty at runtime, [LocalLlmEngine] will attempt to resolve
  /// [localModelFilename] inside the app's Documents directory.
  ///
  /// Examples:
  ///   iOS:     '/var/mobile/Containers/Data/Application/.../Documents/phi-3.5-mini-Q4.gguf'
  ///   Android: '/data/user/0/com.package/files/phi-3.5-mini-Q4.gguf'
  static String localModelPath = '';

  /// Filename of the GGUF model to look for in the app Documents directory
  /// when [localModelPath] is empty.
  static String localModelFilename = 'Qwen2.5-3B-Instruct-Q4_K_M.gguf';

  /// Optional HTTPS URL used to auto-download the model when it is missing.
  ///
  /// Leave empty to disable auto-download.
  /// Example: 'https://example.com/models/phi-3.5-mini-instruct-q4.gguf'
  static String localModelDownloadUrl = 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf';

  /// Number of transformer layers to offload to the GPU.
  /// iOS Metal: 99 = all layers on GPU (fastest on iPad A-series).
  /// Android CPU AAR: set to 0 (no GPU acceleration).
  static int localModelGpuLayers = 99;

  /// Context window size in tokens.
  /// Smaller context lowers memory pressure and improves decode latency on mobile.
  static int localModelContextSize = 1024;

  /// Max number of new tokens to generate per response.
  /// This is a floor; runtime raises it for larger requested option counts.
  static int localModelMaxTokens = 256;
}

// ---------------------------------------------------------------------------
// Engine interface
// ---------------------------------------------------------------------------

/// Common interface for all LLM engines.
///
/// The engine owns only the *transport layer* — it receives an already-built
/// request body map and returns a raw [http.Response].  All response parsing,
/// error handling, and retry logic at the call sites remain unchanged.
abstract class LlmEngine {
  /// Sends [body] (the map produced by `_buildLlmRequestBody`) to the LLM
  /// backend and returns the raw HTTP response.
  Future<http.Response> query({
    required Map<String, dynamic> body,
    required String userId,
    int timeoutSeconds = 30,
  });
}

// ---------------------------------------------------------------------------
// Cloud engine (current production path)
// ---------------------------------------------------------------------------

/// Forwards every request to the cloud `/llm` endpoint, exactly as the
/// in-line `AuthenticatedHttpClient` calls did before this abstraction was
/// introduced.  No behaviour change.
class CloudLlmEngine implements LlmEngine {
  @override
  Future<http.Response> query({
    required Map<String, dynamic> body,
    required String userId,
    int timeoutSeconds = 30,
  }) {
    final clientRequestId = _buildClientRequestId();
    final clientPlatform = _buildClientPlatformStamp();
    final stampedBody = {
      ...body,
      'clientRequestId': clientRequestId,
      'clientPlatform': clientPlatform,
      'clientRequestTimestamp': DateTime.now().toUtc().toIso8601String(),
    };

    debugPrint(
      '🤖 LLM Stamp: requestId=$clientRequestId platform=$clientPlatform',
    );

    return AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/llm',
      baseHeaders: {
        'X-User-ID': userId,
        'Content-Type': 'application/json',
        'X-Client-Request-ID': clientRequestId,
        'X-Client-Platform': clientPlatform,
      },
      body: json.encode(stampedBody),
      timeoutSeconds: timeoutSeconds,
    );
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// Returns the [LlmEngine] that matches [PocConfig.llmEngineMode].
class LlmEngineFactory {
  LlmEngineFactory._(); // prevent instantiation

  static LlmEngine getEngine() {
    switch (PocConfig.llmEngineMode) {
      case LlmEngineMode.cloud:
        return CloudLlmEngine();
      case LlmEngineMode.local:
        debugPrint('🤖 LLM ENGINE: local (llama_cpp_dart on-device)');
        return LocalLlmEngine();
      case LlmEngineMode.hybrid: // not yet implemented — falls back to cloud
        return CloudLlmEngine();
    }
  }
}

// ---------------------------------------------------------------------------
// Local (on-device) engine — DISABLED (no-go decision May 2026)
// ---------------------------------------------------------------------------
//
// POC evaluation found on-device inference is 5× too slow (15 s vs 4 s target)
// on iPad A16 with a 3B Q4 model at full Metal GPU acceleration.
// See LOCAL_LLM_POC_FINDINGS.md for full details.
//
// To re-enable when hardware/software catches up:
//   1. Add `llama_cpp_dart: <version>` back to pubspec.yaml
//   2. Restore the full LocalLlmEngine implementation from git history (poc/local-llm-eval branch)
//   3. Set PocConfig.llmEngineMode = LlmEngineMode.local
class LocalLlmEngine implements LlmEngine {
  @override
  Future<http.Response> query({
    required Map<String, dynamic> body,
    required String userId,
    int timeoutSeconds = 30,
  }) async {
    throw UnsupportedError(
      'LocalLlmEngine is disabled. '
      'Set PocConfig.llmEngineMode = LlmEngineMode.cloud or restore the implementation from the poc/local-llm-eval branch.',
    );
  }
}


