import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class TapInterfaceAdminApiService {
  final String apiBaseUrl;
  final String idToken;
  final String userId;

  TapInterfaceAdminApiService({
    required this.apiBaseUrl,
    required this.idToken,
    required this.userId,
  });

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
        'X-User-ID': userId,
      };

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $idToken',
        'X-User-ID': userId,
      };

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<Map<String, dynamic>> getTapBoards() async {
    final response = await http.get(_uri('/api/tap-interface/boards'), headers: _jsonHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to load boards: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> createBoard(Map<String, dynamic> payload) async {
    final response = await http.post(
      _uri('/api/tap-interface/boards'),
      headers: _jsonHeaders,
      body: json.encode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create board: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> updateBoard(String boardId, Map<String, dynamic> payload) async {
    final response = await http.put(
      _uri('/api/tap-interface/boards/${Uri.encodeComponent(boardId)}'),
      headers: _jsonHeaders,
      body: json.encode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update board: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<void> deleteBoard(String boardId) async {
    final response = await http.delete(
      _uri('/api/tap-interface/boards/${Uri.encodeComponent(boardId)}'),
      headers: _authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete board: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getBoardsMenu() async {
    final response = await http.get(_uri('/api/tap-interface/boards-menu'), headers: _jsonHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to load boards menu: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<void> saveBoardsMenu(List<Map<String, dynamic>> menu) async {
    final response = await http.post(
      _uri('/api/tap-interface/boards-menu'),
      headers: _jsonHeaders,
      body: json.encode({'boards_menu': menu}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save boards menu: ${response.statusCode} ${response.body}');
    }
  }

  Future<String> uploadButtonAudio(Uint8List bytes, String fileName) async {
    final request = http.MultipartRequest('POST', _uri('/api/admin/upload-button-audio'));
    request.headers.addAll(_authHeaders);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

    final streamedResponse = await request.send();
    final body = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode != 200) {
      throw Exception('Audio upload failed: ${streamedResponse.statusCode} $body');
    }

    final parsed = (json.decode(body) as Map).cast<String, dynamic>();
    if (parsed['success'] == true && parsed['audio_url'] != null) {
      return parsed['audio_url'].toString();
    }
    throw Exception('Audio upload did not return a URL');
  }

  Future<Map<String, dynamic>> uploadTouchChatArchive(Uint8List bytes, String fileName) async {
    final request = http.MultipartRequest('POST', _uri('/api/touchchat-migration/upload-ce'));
    request.headers.addAll(_authHeaders);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

    final streamedResponse = await request.send();
    final body = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      throw Exception('TouchChat upload failed: ${streamedResponse.statusCode} $body');
    }
    return (json.decode(body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> getTouchChatBoards(String sessionId) async {
    final response = await http.get(
      _uri('/api/touchchat-migration/boards/${Uri.encodeComponent(sessionId)}'),
      headers: _jsonHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load TouchChat boards: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> importTouchChatBoard(Map<String, dynamic> payload) async {
    final response = await http.post(
      _uri('/api/touchchat-migration/import-board'),
      headers: _jsonHeaders,
      body: json.encode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TouchChat import failed: ${response.statusCode} ${response.body}');
    }
    return (json.decode(response.body) as Map).cast<String, dynamic>();
  }

  Future<void> deleteTouchChatSession(String sessionId) async {
    final response = await http.delete(
      _uri('/api/touchchat-migration/session/${Uri.encodeComponent(sessionId)}'),
      headers: _authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to reset TouchChat migration session: ${response.statusCode} ${response.body}');
    }
  }
}
