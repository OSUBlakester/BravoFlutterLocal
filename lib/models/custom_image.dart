class CustomImage {
  final String id;
  final String concept;
  final String subconcept;
  final List<String> tags;
  final String imageUrl;
  final String originalFilename;
  final String storagePath;
  final String accountId;
  final String aacUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool active;
  final bool isProfileImage;

  const CustomImage({
    required this.id,
    required this.concept,
    required this.subconcept,
    required this.tags,
    required this.imageUrl,
    required this.originalFilename,
    required this.storagePath,
    required this.accountId,
    required this.aacUserId,
    required this.createdAt,
    required this.updatedAt,
    required this.active,
    this.isProfileImage = false,
  });

  factory CustomImage.fromJson(Map<String, dynamic> json) {
    return CustomImage(
      id: (json['id'] ?? '').toString(),
      concept: (json['concept'] ?? '').toString(),
      subconcept: (json['subconcept'] ?? '').toString(),
      tags: () {
        final result = <String>[];
        
        // Add subconcept parts to tags list
        final sub = (json['subconcept'] ?? '').toString();
        if (sub.contains(',') || sub.contains('/')) {
          result.addAll(
            sub.split(RegExp(r'[,/]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty),
          );
        } else {
          final trimmed = sub.trim();
          if (trimmed.isNotEmpty) {
            result.add(trimmed);
          }
        }

        // Add regular tags
        final rawTags = json['tags'];
        if (rawTags is List) {
          for (final item in rawTags) {
            final str = item?.toString() ?? '';
            if (str.contains(',') || str.contains('/')) {
              result.addAll(
                str.split(RegExp(r'[,/]+'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            } else {
              final trimmed = str.trim();
              if (trimmed.isNotEmpty) {
                result.add(trimmed);
              }
            }
          }
        } else if (rawTags != null) {
          final str = rawTags.toString();
          result.addAll(
            str.split(RegExp(r'[,/]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty),
          );
        }
        return result.toSet().toList(); // Deduplicate tags
      }(),
      imageUrl: (json['image_url'] ?? json['imageUrl'] ?? '').toString(),
      originalFilename: (json['original_filename'] ?? json['originalFilename'] ?? '').toString(),
      storagePath: (json['storage_path'] ?? json['storagePath'] ?? '').toString(),
      accountId: (json['account_id'] ?? json['accountId'] ?? '').toString(),
      aacUserId: (json['aac_user_id'] ?? json['aacUserId'] ?? '').toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      active: json['active'] as bool? ?? true,
      isProfileImage: json['is_profile_image'] as bool? ?? json['isProfileImage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'concept': concept,
      'subconcept': subconcept,
      'tags': tags,
      'image_url': imageUrl,
      'original_filename': originalFilename,
      'storage_path': storagePath,
      'account_id': accountId,
      'aac_user_id': aacUserId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'active': active,
      'is_profile_image': isProfileImage,
    };
  }

  CustomImage copyWith({
    String? id,
    String? concept,
    String? subconcept,
    List<String>? tags,
    String? imageUrl,
    String? originalFilename,
    String? storagePath,
    String? accountId,
    String? aacUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? active,
    bool? isProfileImage,
  }) {
    return CustomImage(
      id: id ?? this.id,
      concept: concept ?? this.concept,
      subconcept: subconcept ?? this.subconcept,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
      originalFilename: originalFilename ?? this.originalFilename,
      storagePath: storagePath ?? this.storagePath,
      accountId: accountId ?? this.accountId,
      aacUserId: aacUserId ?? this.aacUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      active: active ?? this.active,
      isProfileImage: isProfileImage ?? this.isProfileImage,
    );
  }

  @override
  String toString() {
    return 'CustomImage(id: $id, concept: $concept, subconcept: $subconcept, tags: $tags)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomImage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  String get searchableText {
    return '$concept $subconcept ${tags.join(' ')}'.toLowerCase();
  }

  bool matchesQuery(String query) {
    if (query.isEmpty) return true;

    final lowerQuery = query.toLowerCase().trim();
    final searchText = searchableText.trim();

    if (lowerQuery.length == 1 && (lowerQuery == 'i' || searchText.contains('lily'))) {
      print('🚨 MATCHQUERY DEBUG: Query="$lowerQuery", SearchText="$searchText"');
      print('   Concept: "$concept", Subconcept: "$subconcept", Tags: $tags');
    }

    if (lowerQuery.length == 1) {
      final words = searchText.split(RegExp(r'\s+'));
      final result = words.any((word) => word == lowerQuery);

      if (lowerQuery == 'i' || searchText.contains('lily')) {
        print('   Words: $words');
        print('   SingleCharMatch Result: $result');
      }

      return result;
    }

    if (lowerQuery.length <= 3) {
      final words = searchText.split(RegExp(r'\s+'));
      return words.any((word) =>
          word == lowerQuery || word.startsWith(lowerQuery));
    }

    return searchText.contains(lowerQuery);
  }
}

class CustomImageUploadRequest {
  final String primaryTag;

  const CustomImageUploadRequest({
    required this.primaryTag,
  });

  Map<String, String> toFormData() {
    return {
      'concept': 'custom',
      'subconcept': primaryTag,
      'tags': '',
    };
  }

  @override
  String toString() {
    return 'CustomImageUploadRequest(primaryTag: $primaryTag)';
  }
}

class CustomImageUpdateRequest {
  final String id;
  final String? primaryTag;

  const CustomImageUpdateRequest({
    required this.id,
    this.primaryTag,
  });

  Map<String, dynamic> toJson() {
    return {
      'image_id': id,
      'concept': 'custom',
      'subconcept': primaryTag ?? '',
      'tags': [],
    };
  }

  @override
  String toString() {
    return 'CustomImageUpdateRequest(id: $id, primaryTag: $primaryTag)';
  }
}
