import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tap_navigation_models.dart';

class TapInterfaceApiService {
  final String apiBaseUrl;
  final String idToken;
  final String userId;

  TapInterfaceApiService({
    required this.apiBaseUrl,
    required this.idToken,
    required this.userId,
  });

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
    'X-User-ID': userId,
  };

  // Load tap interface configuration
  Future<TapNavigationConfig?> loadConfiguration() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/tap-interface/config');
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('API Response: $jsonData');
        final config = TapNavigationConfig.fromJson(jsonData);
        print('Parsed config: ${config.toJson()}');
        return config;
      } else {
        print('Failed to load tap interface config: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error loading tap interface config: $e');
      return null;
    }
  }

  // Save tap interface configuration
  Future<bool> saveConfiguration(TapNavigationConfig config) async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/tap-interface/config');
      final response = await http.post(
        url,
        headers: _headers,
        body: json.encode(config.toJson()),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to save tap interface config: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error saving tap interface config: $e');
      return false;
    }
  }
}