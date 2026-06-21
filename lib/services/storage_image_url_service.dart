import 'package:firebase_storage/firebase_storage.dart';
import '../config/environment_config.dart';

class StorageImageUrlService {
  static final Map<String, String> _storagePathUrlCache = {};

  static bool _isHttpUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim().toLowerCase();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  static String? _normalizeFallbackUrl(String? fallbackUrl) {
    if (fallbackUrl == null) return null;
    final raw = fallbackUrl.trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    if (_isHttpUrl(raw)) return raw;

    if (raw.startsWith('//')) {
      return 'https:$raw';
    }

    if (raw.startsWith('storage.googleapis.com/')) {
      return 'https://$raw';
    }

    if (raw.startsWith('/')) {
      return '${EnvironmentConfig.apiBaseUrl}$raw';
    }

    if (raw.startsWith('gs://')) {
      final remainder = raw.substring(5);
      final slash = remainder.indexOf('/');
      if (slash > 0) {
        final bucket = remainder.substring(0, slash);
        final objectPath = remainder.substring(slash + 1);
        return 'https://storage.googleapis.com/$bucket/$objectPath';
      }
    }

    return raw;
  }

  static Future<String?> resolveImageUrl({
    String? storagePath,
    String? fallbackUrl,
    String? bucketName,
  }) async {
    final normalizedFallback = _normalizeFallbackUrl(fallbackUrl);
    final path = storagePath?.trim();
    if (path == null || path.isEmpty) {
      return normalizedFallback;
    }

    final cached = _storagePathUrlCache[path];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final resolvedBucket = (bucketName != null && bucketName.isNotEmpty)
          ? bucketName
          : '${EnvironmentConfig.projectId}-aac-images';
      final downloadUrl = await FirebaseStorage.instanceFor(bucket: resolvedBucket)
          .ref(path)
          .getDownloadURL();
      _storagePathUrlCache[path] = downloadUrl;
      return downloadUrl;
    } catch (_) {
      // Fall back to backend-provided URL if Firebase Storage URL resolution fails.
      return normalizedFallback;
    }
  }

  static void clearCache() {
    _storagePathUrlCache.clear();
  }
}