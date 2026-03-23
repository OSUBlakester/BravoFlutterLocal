import 'dart:convert';
import '../config/environment_config.dart';
import '../services/user_settings_provider.dart';
import 'authenticated_http_client.dart';

class ChatHistoryService {
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;
  ChatHistoryService._internal();

  /// Records chat history to the backend
  /// This is equivalent to the web app's recordChatHistory function
  Future<void> recordChatHistory({
    required String question, 
    required String response,
    required String idToken,
    required String aacUserId,
  }) async {
    try {
      print('🎯 Flutter recordChatHistory called with question: "$question", response: "$response"');
      
      // Skip if both question and response are empty
      if (question.trim().isEmpty && response.trim().isEmpty) {
        print('🎯 Skipping chat history - both question and response are empty');
        return;
      }
      
      print('🎯 Making authenticated fetch call to /record_chat_history...');
      
      final response_http = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/record_chat_history',
        baseHeaders: {
          'X-User-ID': aacUserId,
        },
        body: json.encode({
          'question': question,
          'response': response,
        }),
      );
      
      print('🎯 Response received, status: ${response_http.statusCode}');
      
      if (response_http.statusCode == 200) {
        final responseData = json.decode(response_http.body);
        print('✅ Chat history recorded successfully: $responseData');
      } else {
        final errorText = response_http.body;
        print('❌ Chat history server error: ${response_http.statusCode} - $errorText');
        throw Exception('HTTP error! status: ${response_http.statusCode} - $errorText');
      }
    } catch (error) {
      print('❌ Error recording chat history: $error');
      // Don't rethrow - we don't want chat history errors to break the app
    }
  }

  /// Convenience method that uses UserSettingsProvider for authentication
  Future<void> recordChatHistoryWithProvider({
    required String question, 
    required String response,
    required UserSettingsProvider userSettingsProvider,
  }) async {
    final idToken = userSettingsProvider.idToken;
    final aacUserId = userSettingsProvider.userId;
    
    if (idToken == null || aacUserId == null) {
      print('❌ Cannot record chat history - missing auth token or user ID');
      return;
    }
    
    await recordChatHistory(
      question: question,
      response: response,
      idToken: idToken,
      aacUserId: aacUserId,
    );
  }
}