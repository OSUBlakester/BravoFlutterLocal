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
  });

  factory CustomImage.fromJson(Map<String, dynamic> json) {
    return CustomImage(
      id: json['id'] as String,
      concept: json['concept'] as String,
      subconcept: json['subconcept'] as String,
      tags: List<String>.from(json['tags'] ?? []),
      imageUrl: json['image_url'] as String,
      originalFilename: json['original_filename'] as String,
      storagePath: json['storage_path'] as String,
      accountId: json['account_id'] as String,
      aacUserId: json['aac_user_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      active: json['active'] as bool? ?? true,
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

  /// Returns a formatted search string for filtering
  String get searchableText {
    return '$concept $subconcept ${tags.join(' ')}'.toLowerCase();
  }

  /// Checks if this image matches the given search query
  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    
    final lowerQuery = query.toLowerCase().trim();
    final searchText = searchableText.trim();
    
    // Debug logging for problematic single character queries
    if (lowerQuery.length == 1 && (lowerQuery == 'i' || searchText.contains('lily'))) {
      print('🚨 MATCHQUERY DEBUG: Query="$lowerQuery", SearchText="$searchText"');
      print('   Concept: "$concept", Subconcept: "$subconcept", Tags: $tags');
    }
    
    // For single character queries, be more strict to avoid false positives
    if (lowerQuery.length == 1) {
      // Split searchable text into words and check for exact word matches
      final words = searchText.split(RegExp(r'\s+'));
      final result = words.any((word) => word == lowerQuery);
      
      // Debug single character matches
      if (lowerQuery == 'i' || searchText.contains('lily')) {
        print('   Words: $words');
        print('   SingleCharMatch Result: $result');
      }
      
      return result;
    }
    
    // For multi-character queries, use fuzzy matching with word boundaries
    if (lowerQuery.length <= 3) {
      // For short queries (2-3 chars), look for word starts or exact words
      final words = searchText.split(RegExp(r'\s+'));
      return words.any((word) => 
        word == lowerQuery ||  // exact match
        word.startsWith(lowerQuery)  // word starts with query
      );
    }
    
    // For longer queries, use the original contains logic
    return searchText.contains(lowerQuery);
  }
}

class CustomImageUploadRequest {
  final String description;

  const CustomImageUploadRequest({
    required this.description,
  });

  // Parse description into concept, subconcept, and tags
  String get concept {
    final parts = description.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : '';
  }

  String get subconcept {
    final parts = description.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : '';
  }

  List<String> get tags {
    final parts = description.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.length > 1 ? parts.sublist(1) : [parts.isNotEmpty ? parts.first : ''];
  }

  Map<String, String> toFormData() {
    return {
      'concept': concept,
      'subconcept': subconcept,
      'tags': tags.join(','),
    };
  }

  @override
  String toString() {
    return 'CustomImageUploadRequest(concept: $concept, subconcept: $subconcept, tags: $tags)';
  }
}

class CustomImageUpdateRequest {
  final String id;
  final String? description;

  const CustomImageUpdateRequest({
    required this.id,
    this.description,
  });

  // Parse description into concept, subconcept, and tags when needed
  String? get concept {
    if (description == null) return null;
    final parts = description!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : null;
  }

  String? get subconcept {
    if (description == null) return null;
    final parts = description!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : null;
  }

  List<String>? get tags {
    if (description == null) return null;
    final parts = description!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.length > 1 ? parts.sublist(1) : [parts.isNotEmpty ? parts.first : ''];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {'id': id};
    if (concept != null) data['concept'] = concept;
    if (subconcept != null) data['subconcept'] = subconcept;
    if (tags != null) data['tags'] = tags;
    return data;
  }

  @override
  String toString() {
    return 'CustomImageUpdateRequest(id: $id, description: $description)';
  }
}