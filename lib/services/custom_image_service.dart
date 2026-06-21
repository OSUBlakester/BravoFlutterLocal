import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_image.dart';
import '../config/environment_config.dart';
import 'storage_image_url_service.dart';

class CustomImageService {
  static const String _baseEndpoint = '/api';
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int _maxImageDimension = 800; // 800x800px max
  static const int _compressionQuality = 85;
  static const String _localImagePathPrefix = 'local_custom_image_path_';

  // Cache management
  static Map<String, List<CustomImage>> _imageCache = {};
  static Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  static bool _shouldForceRefresh = true; // Force refresh on first load

  // Request deduplication - prevent multiple simultaneous API calls
  static Map<String, Future<List<CustomImage>>> _ongoingRequests = {};

  static Uri _scopedApiUri(String path, String aacUserId) {
    final base = Uri.parse(
      '${EnvironmentConfig.apiBaseUrl}$_baseEndpoint/$path',
    );
    final query = <String, String>{
      ...base.queryParameters,
      'aac_user_id': aacUserId,
    };
    return base.replace(queryParameters: query);
  }

  /// Clear the images cache to force fresh data from server
  static void clearCache() {
    print(
      '🔄 CustomImageService: Clearing images cache and setting force refresh flag',
    );
    _imageCache.clear();
    _cacheTimestamps.clear();
    _ongoingRequests.clear(); // Clear any ongoing requests
    StorageImageUrlService.clearCache();
    _shouldForceRefresh = true; // Force refresh on next load
  }

  static String _localImagePathKey(String imageId) {
    return '$_localImagePathPrefix$imageId';
  }

  static Future<void> _clearLocalImageCopy(String imageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localPath = prefs.getString(_localImagePathKey(imageId));
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await prefs.remove(_localImagePathKey(imageId));
    } catch (e) {
      print('⚠️ CustomImageService: Failed to clear local image copy: $e');
    }
  }

  /// Upload a new custom image
  static Future<CustomImage?> uploadImage({
    required File imageFile,
    required String primaryTag,
    required String idToken,
    required String aacUserId,
  }) async {
    try {
      print('🔄 CustomImageService: Starting upload for "$primaryTag"');

      // Validate and compress image
      final compressedImage = await _validateAndCompressImage(imageFile);
      if (compressedImage == null) {
        throw Exception('Failed to process image file');
      }

      // Prepare the multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}$_baseEndpoint/upload_custom_image',
        ),
      );

      // Add headers (without Content-Type for multipart)
      request.headers.addAll({
        'Authorization': 'Bearer $idToken',
        'X-User-ID': aacUserId,
      });

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          compressedImage.bytes,
          filename: compressedImage.filename,
          contentType: MediaType('image', 'webp'),
        ),
      );

      // Add form fields
      final uploadRequest = CustomImageUploadRequest(primaryTag: primaryTag);

      uploadRequest.toFormData().forEach((key, value) {
        request.fields[key] = value;
      });
      // Explicitly include profile scope so backend can isolate per-profile data.
      request.fields['aac_user_id'] = aacUserId;

      print('📤 CustomImageService: Sending upload request...');

      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print(
        '📥 CustomImageService: Upload response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(responseBody);

        if (jsonResponse['success'] == true &&
            jsonResponse['image_data'] != null) {
          final customImage = CustomImage.fromJson(jsonResponse['image_data']);
          final resolvedUrl = await StorageImageUrlService.resolveImageUrl(
            storagePath: customImage.storagePath,
            fallbackUrl: customImage.imageUrl,
          );
          print('✅ CustomImageService: Upload successful - ${customImage.id}');
          return resolvedUrl != null
              ? customImage.copyWith(imageUrl: resolvedUrl)
              : customImage;
        } else {
          throw Exception(
            'Upload failed: ${jsonResponse['message'] ?? 'Unknown error'}',
          );
        }
      } else {
        final errorData = json.decode(responseBody);
        throw Exception(
          'Upload failed: ${errorData['detail'] ?? 'Server error'}',
        );
      }
    } catch (e) {
      print('❌ CustomImageService: Upload error: $e');
      rethrow;
    }
  }

  /// Get all custom images for the current user
  static Future<List<CustomImage>> getCustomImages({
    required String idToken,
    required String aacUserId,
    bool forceRefresh = false,
    bool shouldLogMissing = true,
  }) async {
    try {
      final cacheKey = '${aacUserId}_images';
      final now = DateTime.now();

      // Auto-enable force refresh if flag is set (first load after cache clear)
      final shouldForceRefresh = forceRefresh || _shouldForceRefresh;

      // Check cache if not forcing refresh
      if (!shouldForceRefresh && _imageCache.containsKey(cacheKey)) {
        final cacheTime = _cacheTimestamps[cacheKey];
        if (cacheTime != null &&
            now.difference(cacheTime) < _cacheValidDuration) {
          print(
            '📋 CustomImageService: Returning cached images for $aacUserId (${_imageCache[cacheKey]!.length} images)',
          );
          return _imageCache[cacheKey]!;
        }
      }

      // Check if there's already an ongoing request for this user
      if (_ongoingRequests.containsKey(cacheKey)) {
        print(
          '⏳ CustomImageService: Request already in progress for $aacUserId, waiting...',
        );
        return await _ongoingRequests[cacheKey]!;
      }

      print(
        '🚀 CustomImageService: Starting new fetch for $aacUserId (forceRefresh: $shouldForceRefresh)',
      );

      // Create and store the future to prevent duplicate requests
      final requestFuture = _fetchImagesFromServer(
        idToken,
        aacUserId,
        cacheKey,
        now,
      );
      _ongoingRequests[cacheKey] = requestFuture;

      try {
        final result = await requestFuture;
        return result;
      } finally {
        // Always clean up the ongoing request
        _ongoingRequests.remove(cacheKey);
      }
    } catch (e) {
      print('❌ CustomImageService: Fetch error: $e');
      rethrow;
    }
  }

  /// Internal method to actually fetch images from the server
  static Future<List<CustomImage>> _fetchImagesFromServer(
    String idToken,
    String aacUserId,
    String cacheKey,
    DateTime now,
  ) async {
    final response = await http.get(
      _scopedApiUri('get_custom_images', aacUserId),
      headers: {
        'Authorization': 'Bearer $idToken',
        'X-User-ID': aacUserId,
        'Content-Type': 'application/json',
      },
    );

    final responseData = json.decode(response.body);

    if (response.statusCode == 200) {
      if (responseData['success'] == true && responseData['images'] != null) {
        final List<dynamic> imagesJson = responseData['images'];
        final images = <CustomImage>[];
        for (final jsonImage in imagesJson) {
          final imageAacUserId = jsonImage is Map<String, dynamic>
              ? (jsonImage['aac_user_id'] ?? jsonImage['aacUserId'])
                    ?.toString()
                    .trim()
              : null;

          // Defense-in-depth: if backend returns account-wide records,
          // keep only the active profile's custom images.
          if (imageAacUserId != null &&
              imageAacUserId.isNotEmpty &&
              imageAacUserId != aacUserId) {
            continue;
          }

          final image = CustomImage.fromJson(jsonImage);
          if (image.aacUserId.isNotEmpty && image.aacUserId != aacUserId) {
            continue;
          }
          if (image.isProfileImage) {
            continue;
          }
          final resolvedUrl = await StorageImageUrlService.resolveImageUrl(
            storagePath: image.storagePath,
            fallbackUrl: image.imageUrl,
          );
          images.add(
            resolvedUrl != null ? image.copyWith(imageUrl: resolvedUrl) : image,
          );
        }

        // Cache the results
        _imageCache[cacheKey] = images;
        _cacheTimestamps[cacheKey] = now;

        // Clear force refresh flag after successful fetch
        _shouldForceRefresh = false;

        print(
          '✅ CustomImageService: Fetched ${images.length} custom images and cached them',
        );
        return images;
      } else {
        throw Exception(
          'Failed to fetch custom images: ${responseData['message'] ?? 'Unknown error'}',
        );
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  /// Update custom image metadata
  static Future<CustomImage?> updateImage({
    required String imageId,
    String? primaryTag,
    required String idToken,
    required String aacUserId,
  }) async {
    try {
      print('🔄 CustomImageService: Updating image $imageId');

      final updateRequest = CustomImageUpdateRequest(
        id: imageId,
        primaryTag: primaryTag,
      );

      final response = await http.put(
        _scopedApiUri('update_custom_image', aacUserId),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          ...updateRequest.toJson(),
          'aac_user_id': aacUserId,
        }),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        if (responseData['success'] == true &&
            responseData['image_data'] != null) {
          final customImage = CustomImage.fromJson(responseData['image_data']);
          final resolvedUrl = await StorageImageUrlService.resolveImageUrl(
            storagePath: customImage.storagePath,
            fallbackUrl: customImage.imageUrl,
          );
          print('✅ CustomImageService: Update successful - ${customImage.id}');
          return resolvedUrl != null
              ? customImage.copyWith(imageUrl: resolvedUrl)
              : customImage;
        } else {
          throw Exception(
            'Update failed: ${responseData['message'] ?? 'Unknown error'}',
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ CustomImageService: Update error: $e');
      rethrow;
    }
  }

  /// Delete custom image (soft delete)
  static Future<bool> deleteImage({
    required String imageId,
    required String idToken,
    required String aacUserId,
  }) async {
    try {
      print('🔄 CustomImageService: Deleting image $imageId');

      // Try the primary custom image delete endpoint first
      var response = await http.delete(
        _scopedApiUri('delete_custom_image/$imageId', aacUserId),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
      );

      // If we get a 404, try the imagecreator delete endpoint as fallback
      if (response.statusCode == 404) {
        print(
          '🔄 CustomImageService: Primary endpoint returned 404, trying imagecreator endpoint...',
        );
        response = await http.delete(
          _scopedApiUri('imagecreator/images/$imageId', aacUserId),
          headers: {
            'Authorization': 'Bearer $idToken',
            'X-User-ID': aacUserId,
            'Content-Type': 'application/json',
          },
        );
      }

      if (response.statusCode == 200) {
        // Try to parse JSON response, but handle plain success responses too
        try {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true ||
              responseData.containsKey('id')) {
            print('✅ CustomImageService: Delete successful - $imageId');
            // Clear cache to force refresh on next fetch
            await _clearLocalImageCopy(imageId);
            clearCache();
            return true;
          } else {
            throw Exception(
              'Delete failed: ${responseData['message'] ?? 'Unknown error'}',
            );
          }
        } catch (jsonError) {
          // Handle non-JSON success responses
          if (response.body.isEmpty ||
              response.body.toLowerCase().contains('success')) {
            print(
              '✅ CustomImageService: Delete successful (non-JSON response) - $imageId',
            );
            // Clear cache to force refresh on next fetch
            await _clearLocalImageCopy(imageId);
            clearCache();
            return true;
          } else {
            throw Exception('Unexpected response format: ${response.body}');
          }
        }
      } else if (response.statusCode == 404) {
        throw Exception(
          'Image not found (404). The image may have already been deleted.',
        );
      } else {
        String errorMessage;
        try {
          final errorData = json.decode(response.body);
          errorMessage =
              errorData['detail'] ??
              errorData['message'] ??
              'Server error: ${response.statusCode}';
        } catch (e) {
          errorMessage =
              'Server error: ${response.statusCode} - ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('❌ CustomImageService: Delete error: $e');
      rethrow;
    }
  }

  /// Find custom images matching a search query
  static Future<List<CustomImage>> searchImages({
    required String query,
    required String idToken,
    required String aacUserId,
  }) async {
    try {
      final allImages = await getCustomImages(
        idToken: idToken,
        aacUserId: aacUserId,
      );

      if (query.isEmpty) return allImages;

      return allImages.where((image) => image.matchesQuery(query)).toList();
    } catch (e) {
      print('❌ CustomImageService: Search error: $e');
      rethrow;
    }
  }

  /// Find the best matching custom image for a concept/subconcept
  /// Handles intelligent parsing of button text to find matches
  static Future<CustomImage?> findBestMatch({
    required String concept,
    required String idToken,
    required String aacUserId,
    String? subconcept,
    bool shouldLogMissing = true,
  }) async {
    try {
      final allImages = await getCustomImages(
        idToken: idToken,
        aacUserId: aacUserId,
        shouldLogMissing: shouldLogMissing,
      );

      if (allImages.isEmpty) {
        print(
          '📭 CustomImageService: No custom images available for matching "$concept"',
        );
        return null;
      }

      final usableImages = allImages
          .where((image) => !image.isProfileImage)
          .toList();
      if (usableImages.isEmpty) {
        print(
          '📭 CustomImageService: Only profile images were returned; ignoring them for matching',
        );
        return null;
      }

      // Debug for potential false positive matches
      if (concept.length == 1 || concept.toLowerCase() == "please") {
        print(
          '🔍 CustomImageService: Checking "$concept" against ${usableImages.length} custom images',
        );
        for (final image in usableImages) {
          bool matches = image.matchesQuery(concept);
          if (matches) {
            // Check if it's a legitimate tag match vs a false positive
            bool hasExactTagMatch = image.tags.any(
              (tag) => tag.toLowerCase() == concept.toLowerCase(),
            );
            if (hasExactTagMatch) {
              print(
                '✅ LEGITIMATE MATCH: "$concept" has exact tag match in "${image.concept}" tags=${image.tags}',
              );
            } else {
              print(
                '🚨 FALSE POSITIVE: "$concept" matched "${image.concept}" without exact tag match, tags=${image.tags}',
              );
            }
          }
        }
      }

      // Strategy 1: Direct exact match with concept/subconcept
      if (subconcept != null && subconcept.isNotEmpty) {
        final exactMatch = usableImages
            .where(
              (image) =>
                  image.concept.toLowerCase() == concept.toLowerCase() &&
                  image.subconcept.toLowerCase() == subconcept.toLowerCase(),
            )
            .firstOrNull;

        if (exactMatch != null) {
          print(
            '✅ CustomImageService: Exact match found: ${exactMatch.concept}/${exactMatch.subconcept}',
          );
          return exactMatch;
        }
      }

      // Strategy 2: Try parsing the concept as a potential concept/subconcept combination
      final words = concept.toLowerCase().split(RegExp(r'[\s_-]+'));
      if (words.length >= 2) {
        // Try different combinations for multi-word concepts
        for (int i = 1; i < words.length; i++) {
          final candidateConcept = words.sublist(0, i).join(' ');
          final candidateSubconcept = words.sublist(i).join(' ');

          final combinationMatch = usableImages
              .where(
                (image) =>
                    image.concept.toLowerCase() == candidateConcept &&
                    image.subconcept.toLowerCase() == candidateSubconcept,
              )
              .firstOrNull;

          if (combinationMatch != null) {
            print(
              '✅ CustomImageService: Combination match found: ${combinationMatch.concept}/${combinationMatch.subconcept}',
            );
            return combinationMatch;
          }
        }
      }

      // Strategy 3: Concept-only match
      final conceptMatch = usableImages
          .where(
            (image) => image.concept.toLowerCase() == concept.toLowerCase(),
          )
          .firstOrNull;

      if (conceptMatch != null) {
        print(
          '✅ CustomImageService: Concept match found: ${conceptMatch.concept}',
        );
        return conceptMatch;
      }

      // Strategy 4: Tag-based exact matching (HIGH PRIORITY - more precise for names and specific terms)
      final conceptLower = concept.toLowerCase();
      final tagExactMatch = usableImages
          .where(
            (image) =>
                image.tags.any((tag) => tag.toLowerCase() == conceptLower),
          )
          .firstOrNull;

      if (tagExactMatch != null) {
        print(
          '✅ CustomImageService: Tag exact match found: "${tagExactMatch.concept}/${tagExactMatch.subconcept}" with matching tag: "$concept"',
        );
        return tagExactMatch;
      }

      // Strategy 5: Partial concept match (LOWER PRIORITY - concept contains or is contained by image concept)
      final partialConceptMatch = usableImages.where((image) {
        final imageConcept = image.concept.toLowerCase();
        final searchConcept = concept.toLowerCase();
        return imageConcept.contains(searchConcept) ||
            searchConcept.contains(imageConcept);
      }).firstOrNull;

      if (partialConceptMatch != null) {
        print(
          '✅ CustomImageService: Partial concept match found: ${partialConceptMatch.concept}',
        );
        return partialConceptMatch;
      }

      // Strategy 6: Subconcept exact matching
      if (subconcept != null && subconcept.isNotEmpty) {
        final subconceptLower = subconcept.toLowerCase();
        final subconceptExactMatch = usableImages
            .where((image) => image.subconcept.toLowerCase() == subconceptLower)
            .firstOrNull;

        if (subconceptExactMatch != null) {
          print(
            '✅ CustomImageService: Subconcept exact match found: "${subconceptExactMatch.concept}/${subconceptExactMatch.subconcept}"',
          );
          return subconceptExactMatch;
        }
      }

      // Strategy 7: Full text search across concept, subconcept, and tags (only for longer queries)
      if (concept.length > 2) {
        // Only use fuzzy search for longer terms
        final searchQuery = subconcept != null && subconcept.isNotEmpty
            ? '$concept $subconcept'
            : concept;

        print(
          '🔍 CustomImageService: Searching with query: "$searchQuery" (length > 2)',
        );

        // Debug: Show all images and their searchable text
        for (final image in usableImages) {
          print(
            '🔍 Image ${image.id}: "${image.searchableText}" (concept: "${image.concept}", tags: ${image.tags})',
          );
        }

        final searchResults = usableImages
            .where((image) => image.matchesQuery(searchQuery))
            .toList();

        if (searchResults.isNotEmpty) {
          final matchedImage = searchResults.first;
          print(
            '✅ CustomImageService: Text search match found: "${matchedImage.concept}/${matchedImage.subconcept}" with tags: ${matchedImage.tags}',
          );
          return matchedImage;
        }
      } else {
        print(
          '🔍 CustomImageService: Skipping fuzzy search for short query: "$concept" (length <= 2)',
        );
      }

      print('❌ CustomImageService: No match found for "$concept"');
      return null;
    } catch (e) {
      print('❌ CustomImageService: FindBestMatch error: $e');
      return null;
    }
  }

  /// Validate and compress image file
  static Future<_CompressedImageResult?> _validateAndCompressImage(
    File imageFile,
  ) async {
    try {
      // Check file size
      final fileSize = await imageFile.length();
      if (fileSize > _maxFileSizeBytes) {
        throw Exception(
          'File size too large. Maximum allowed: ${(_maxFileSizeBytes / (1024 * 1024)).round()}MB',
        );
      }

      // Check file extension - support common mobile formats including HEIC from iOS
      final extension = path.extension(imageFile.path).toLowerCase();
      if (![
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
        '.heif',
      ].contains(extension)) {
        throw Exception(
          'Unsupported file format. Please use JPG, PNG, WebP, or HEIC',
        );
      }

      print('🔄 CustomImageService: Compressing image...');

      // Compress the image
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        imageFile.absolute.path,
        minWidth: _maxImageDimension,
        minHeight: _maxImageDimension,
        quality: _compressionQuality,
        format: CompressFormat.webp, // Convert to WebP for better compression
      );

      if (compressedBytes == null) {
        throw Exception('Failed to compress image');
      }

      final originalSize = fileSize;
      final compressedSize = compressedBytes.length;
      final compressionRatio =
          ((originalSize - compressedSize) / originalSize * 100).round();

      print(
        '✅ CustomImageService: Compression complete - ${compressionRatio}% reduction (${(originalSize / 1024).round()}KB → ${(compressedSize / 1024).round()}KB)',
      );

      // Generate filename with WebP extension
      final baseName = path.basenameWithoutExtension(imageFile.path);
      final compressedFilename = '$baseName.webp';

      return _CompressedImageResult(
        bytes: compressedBytes,
        filename: compressedFilename,
      );
    } catch (e) {
      print('❌ CustomImageService: Compression error: $e');
      return null;
    }
  }
}

class _CompressedImageResult {
  final Uint8List bytes;
  final String filename;

  const _CompressedImageResult({required this.bytes, required this.filename});
}

// Extension to add firstOrNull method if not available
extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
