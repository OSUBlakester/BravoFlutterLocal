import 'dart:convert';

import '../config/environment_config.dart';
import 'authenticated_http_client.dart';

class ComposeDocument {
  final String id;
  final String documentType;
  final String title;
  final String body;
  final String preview;
  final String subject;
  final String updatedAt;
  final String createdAt;
  final String illustrationUrl;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;

  const ComposeDocument({
    required this.id,
    required this.documentType,
    required this.title,
    required this.body,
    required this.preview,
    required this.subject,
    required this.updatedAt,
    required this.createdAt,
    required this.illustrationUrl,
    required this.to,
    required this.cc,
    required this.bcc,
  });

  factory ComposeDocument.fromJson(Map<String, dynamic>? json) {
    final data = json ?? <String, dynamic>{};
    List<String> parseList(dynamic raw) {
      if (raw is List) {
        return raw
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList();
      }
      return const <String>[];
    }

    return ComposeDocument(
      id: (data['id'] ?? '').toString(),
      documentType: (data['document_type'] ?? 'story').toString(),
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      preview: (data['preview'] ?? '').toString(),
      subject: (data['subject'] ?? '').toString(),
      updatedAt: (data['updated_at'] ?? '').toString(),
      createdAt: (data['created_at'] ?? '').toString(),
      illustrationUrl: (data['illustration_url'] ?? '').toString(),
      to: parseList(data['to']),
      cc: parseList(data['cc']),
      bcc: parseList(data['bcc']),
    );
  }
}

class ComposeDocumentService {
  static Map<String, String> _headers(String aacUserId) {
    return {'X-User-ID': aacUserId, 'Content-Type': 'application/json'};
  }

  static Future<List<ComposeDocument>> listDocuments(String aacUserId) async {
    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'GET',
      '${EnvironmentConfig.apiBaseUrl}/api/compose/documents',
      baseHeaders: _headers(aacUserId),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load creations (${response.statusCode})');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception(
        (decoded is Map<String, dynamic> ? decoded['error'] : null)
                ?.toString() ??
            'Failed to load creations',
      );
    }

    final documents = (decoded['documents'] as List?) ?? const [];
    return documents
        .whereType<Map>()
        .map(
          (doc) => ComposeDocument.fromJson(
            doc.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  static Future<ComposeDocument> saveDocument(
    String aacUserId, {
    String? documentId,
    required String documentType,
    required String title,
    required String body,
    List<String> to = const <String>[],
    List<String> cc = const <String>[],
    List<String> bcc = const <String>[],
    String subject = '',
  }) async {
    final isUpdate = (documentId ?? '').trim().isNotEmpty;
    final endpoint = isUpdate
        ? '${EnvironmentConfig.apiBaseUrl}/api/compose/documents/${Uri.encodeComponent(documentId!.trim())}'
        : '${EnvironmentConfig.apiBaseUrl}/api/compose/documents';

    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      isUpdate ? 'PUT' : 'POST',
      endpoint,
      baseHeaders: _headers(aacUserId),
      body: json.encode({
        'document_type': documentType,
        'title': title,
        'body': body,
        'to': to,
        'cc': cc,
        'bcc': bcc,
        'subject': subject,
      }),
      timeoutSeconds: 60,
    );

    if (response.statusCode != 200) {
      final decoded = _tryDecode(response.body);
      throw Exception(
        (decoded['error'] ??
                decoded['detail'] ??
                'Save failed (${response.statusCode})')
            .toString(),
      );
    }

    final decoded = _tryDecode(response.body);
    if (decoded['success'] != true || decoded['document'] is! Map) {
      throw Exception((decoded['error'] ?? 'Save failed').toString());
    }

    return ComposeDocument.fromJson(
      (decoded['document'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  static Future<void> deleteDocument(
    String aacUserId,
    String documentId,
  ) async {
    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'DELETE',
      '${EnvironmentConfig.apiBaseUrl}/api/compose/documents/${Uri.encodeComponent(documentId)}',
      baseHeaders: _headers(aacUserId),
      timeoutSeconds: 45,
    );

    if (response.statusCode != 200) {
      final decoded = _tryDecode(response.body);
      throw Exception(
        (decoded['error'] ??
                decoded['detail'] ??
                'Delete failed (${response.statusCode})')
            .toString(),
      );
    }
  }

  static Future<String> generateTitle(String aacUserId, String body) async {
    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/api/compose/generate-title',
      baseHeaders: _headers(aacUserId),
      body: json.encode({'body': body}),
      timeoutSeconds: 45,
    );

    if (response.statusCode != 200) {
      final decoded = _tryDecode(response.body);
      throw Exception(
        (decoded['error'] ??
                decoded['detail'] ??
                'Title generation failed (${response.statusCode})')
            .toString(),
      );
    }

    final decoded = _tryDecode(response.body);
    final title = (decoded['title'] ?? '').toString().trim();
    if (decoded['success'] != true || title.isEmpty) {
      throw Exception(
        (decoded['error'] ?? 'Title generation failed').toString(),
      );
    }

    return title;
  }

  static Future<String> aiEdit(String aacUserId, String body) async {
    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/api/compose/ai-edit',
      baseHeaders: _headers(aacUserId),
      body: json.encode({'body': body}),
      timeoutSeconds: 90,
    );

    if (response.statusCode != 200) {
      final decoded = _tryDecode(response.body);
      throw Exception(
        (decoded['error'] ??
                decoded['detail'] ??
                'AI edit failed (${response.statusCode})')
            .toString(),
      );
    }

    final decoded = _tryDecode(response.body);
    final edited = (decoded['edited_body'] ?? '').toString().trim();
    if (decoded['success'] != true || edited.isEmpty) {
      throw Exception((decoded['error'] ?? 'AI edit failed').toString());
    }

    return edited;
  }

  static Map<String, dynamic> _tryDecode(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}
