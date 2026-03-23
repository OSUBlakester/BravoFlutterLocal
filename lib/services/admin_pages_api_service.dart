import 'dart:convert';
import '../models/page_models.dart';
import 'authenticated_http_client.dart';

class AdminPagesApiService {
  final String apiBaseUrl;
  final String userId;

  AdminPagesApiService({required this.apiBaseUrl, required this.userId});

  Future<List<PageModel>> fetchPages() async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '$apiBaseUrl/pages',
        baseHeaders: {
          'X-User-ID': userId,
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => PageModel.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load pages: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error loading pages: $e');
    }
  }

  Future<void> savePage(PageModel page, {String? originalName}) async {
    try {
      final isUpdate = originalName != null && originalName.isNotEmpty;
      final body = page.toJson();
      if (isUpdate) body['originalName'] = originalName;
      
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '$apiBaseUrl/pages',
        baseHeaders: {
          'X-User-ID': userId,
        },
        body: json.encode(body),
        maxRetries: 3,
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to save page: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error saving page: $e');
    }
  }

  Future<void> updatePage(PageModel page, String originalName) async {
    try {
      final body = page.toJson();
      body['originalName'] = originalName;
      
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'PUT',
        '$apiBaseUrl/pages',
        baseHeaders: {
          'X-User-ID': userId,
        },
        body: json.encode(body),
        maxRetries: 3,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to update page: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error updating page: $e');
    }
  }

  Future<void> deletePage(String pageName) async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'DELETE',
        '$apiBaseUrl/pages/$pageName',
        baseHeaders: {
          'X-User-ID': userId,
        },
        maxRetries: 3,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete page: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error deleting page: $e');
    }
  }
}
