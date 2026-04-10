import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ComposeSessionData {
  final bool active;
  final String documentType;
  final String? documentId;
  final String title;
  final String text;
  final String? startedAt;
  final String? sourceFrom;

  const ComposeSessionData({
    required this.active,
    required this.documentType,
    this.documentId,
    required this.title,
    required this.text,
    this.startedAt,
    this.sourceFrom,
  });

  const ComposeSessionData.inactive()
    : active = false,
      documentType = 'story',
      documentId = null,
      title = '',
      text = '',
      startedAt = null,
      sourceFrom = null;

  ComposeSessionData copyWith({
    bool? active,
    String? documentType,
    String? documentId,
    bool clearDocumentId = false,
    String? title,
    String? text,
    String? startedAt,
    bool clearStartedAt = false,
    String? sourceFrom,
    bool clearSourceFrom = false,
  }) {
    return ComposeSessionData(
      active: active ?? this.active,
      documentType: documentType ?? this.documentType,
      documentId: clearDocumentId ? null : (documentId ?? this.documentId),
      title: title ?? this.title,
      text: text ?? this.text,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      sourceFrom: clearSourceFrom ? null : (sourceFrom ?? this.sourceFrom),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'active': active,
      'document_type': documentType,
      'document_id': documentId,
      'title': title,
      'text': text,
      'started_at': startedAt,
      'source_from': sourceFrom,
    };
  }

  static ComposeSessionData fromJson(Map<String, dynamic>? json) {
    final data = json ?? <String, dynamic>{};
    final rawType = (data['document_type'] ?? 'story').toString().trim();
    return ComposeSessionData(
      active: data['active'] == true,
      documentType: rawType.isEmpty ? 'story' : rawType,
      documentId: (data['document_id'] ?? '').toString().trim().isEmpty
          ? null
          : (data['document_id'] ?? '').toString().trim(),
      title: (data['title'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      startedAt: (data['started_at'] ?? '').toString().trim().isEmpty
          ? null
          : (data['started_at'] ?? '').toString().trim(),
      sourceFrom: (data['source_from'] ?? '').toString().trim().isEmpty
          ? null
          : (data['source_from'] ?? '').toString().trim(),
    );
  }
}

class ComposeSessionService {
  static String _keyForUser(String aacUserId) =>
      'compose_session_${aacUserId.trim()}';

  static String _docsKeyForUser(String aacUserId) =>
      'compose_docs_${aacUserId.trim()}';

  static Future<ComposeSessionData> load(String aacUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForUser(aacUserId));
    if (raw == null || raw.trim().isEmpty) {
      return const ComposeSessionData.inactive();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return ComposeSessionData.fromJson(decoded);
      }
      if (decoded is Map) {
        return ComposeSessionData.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
      return const ComposeSessionData.inactive();
    } catch (_) {
      return const ComposeSessionData.inactive();
    }
  }

  static Future<void> save(
    String aacUserId,
    ComposeSessionData session,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForUser(aacUserId), json.encode(session.toJson()));
  }

  static Future<void> clear(String aacUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUser(aacUserId));
  }

  static Future<List<Map<String, dynamic>>> loadLocalDocuments(
    String aacUserId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_docsKeyForUser(aacUserId));
    if (raw == null || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      final docs = decoded
          .whereType<Map>()
          .map(
            (doc) => doc.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();

      docs.sort((a, b) {
        final aUpdated = (a['updated_at'] ?? '').toString();
        final bUpdated = (b['updated_at'] ?? '').toString();
        return bUpdated.compareTo(aUpdated);
      });
      return docs;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<String> upsertLocalDocument(
    String aacUserId, {
    String? documentId,
    required String documentType,
    required String title,
    required String body,
  }) async {
    final docs = await loadLocalDocuments(aacUserId);
    final now = DateTime.now().toUtc().toIso8601String();
    final effectiveId =
        (documentId ?? '').trim().isNotEmpty
        ? documentId!.trim()
        : 'local_${DateTime.now().millisecondsSinceEpoch}';

    final existingIndex = docs.indexWhere(
      (doc) => (doc['id'] ?? '').toString().trim() == effectiveId,
    );

    final updatedDoc = <String, dynamic>{
      'id': effectiveId,
      'document_type': documentType,
      'title': title,
      'body': body,
      'updated_at': now,
      'is_local_fallback': true,
    };

    if (existingIndex >= 0) {
      final existingCreatedAt =
          (docs[existingIndex]['created_at'] ?? '').toString().trim();
      updatedDoc['created_at'] = existingCreatedAt.isEmpty
          ? now
          : existingCreatedAt;
      docs[existingIndex] = updatedDoc;
    } else {
      updatedDoc['created_at'] = now;
      docs.add(updatedDoc);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_docsKeyForUser(aacUserId), json.encode(docs));
    return effectiveId;
  }

  static Future<bool> deleteLocalDocument(
    String aacUserId,
    String documentId,
  ) async {
    final effectiveId = documentId.trim();
    if (effectiveId.isEmpty) {
      return false;
    }

    final docs = await loadLocalDocuments(aacUserId);
    final originalLength = docs.length;
    docs.removeWhere(
      (doc) => (doc['id'] ?? '').toString().trim() == effectiveId,
    );

    if (docs.length == originalLength) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_docsKeyForUser(aacUserId), json.encode(docs));
    return true;
  }
}
