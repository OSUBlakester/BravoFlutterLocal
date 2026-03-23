import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_interview_service.dart';

class AudioInterviewPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;

  const AudioInterviewPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
  });

  @override
  State<AudioInterviewPage> createState() => _AudioInterviewPageState();
}

class _AudioInterviewPageState extends State<AudioInterviewPage> {
  late AudioInterviewService _interviewService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _interviewService = AudioInterviewService();
    _interviewService.setAuthenticationDetails(widget.idToken, widget.aacUserId);
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _interviewService.initializeSpeech();
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _interviewService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _interviewService,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Audio Interview System'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isInitialized ? _buildInterviewContent() : _buildLoadingScreen(),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Initializing Audio Interview System...',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Setting up speech recognition and text-to-speech',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildInterviewContent() {
    return Consumer<AudioInterviewService>(
      builder: (context, service, child) {
        return Column(
          children: [
            _buildProgressSection(service),
            _buildStatusSection(service),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildQuestionSection(service),
                    const SizedBox(height: 12),
                    _buildVoiceRecognitionSection(service),
                    const SizedBox(height: 12),
                    _buildControlButtons(service),
                    if (service.interviewData.responses.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildResponsesPreview(service),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomActionBar(service),
          ],
        );
      },
    );
  }

  Widget _buildProgressSection(AudioInterviewService service) {
    // Get current question category for display
    final currentQuestion = service.currentQuestionIndex < service.totalQuestions 
        ? service.getCurrentQuestion() 
        : null;
    final categoryName = currentQuestion?.type ?? '';
    final displayCategory = _getCategoryDisplayName(categoryName);
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question ${service.currentQuestionIndex + 1} of ${service.totalQuestions}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (displayCategory.isNotEmpty)
                      Text(
                        'Category: $displayCategory',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${(service.progress * 100).toInt()}% Complete',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: service.progress,
            backgroundColor: Colors.blue[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ],
      ),
    );
  }

  String _getCategoryDisplayName(String category) {
    switch (category.toLowerCase()) {
      case 'identity':
        return 'Identity & Basic Info';
      case 'personality':
        return 'Personality & Traits';
      case 'interests':
        return 'Interests & Hobbies';
      case 'relationships':
        return 'Relationships & Social';
      case 'preferences':
        return 'Preferences & Likes';
      case 'daily_life':
        return 'Daily Life & Routine';
      case 'challenges':
        return 'Challenges & Support';
      case 'voice':
        return 'Communication Goals';
      default:
        return category;
    }
  }

  Widget _buildStatusSection(AudioInterviewService service) {
    Color statusColor;
    IconData statusIcon;
    String statusText = service.status;

    // Override status if speaking
    if (service.isSpeaking) {
      statusColor = Colors.purple;
      statusIcon = Icons.volume_up;
      statusText = 'Speaking question... Please wait';
    } else {
      switch (service.statusType) {
        case 'success':
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          break;
        case 'error':
          statusColor = Colors.red;
          statusIcon = Icons.error;
          break;
        case 'warning':
          statusColor = Colors.orange;
          statusIcon = Icons.warning;
          break;
        case 'listening':
          statusColor = Colors.blue;
          statusIcon = Icons.mic;
          break;
        default:
          statusColor = Colors.grey;
          statusIcon = Icons.info;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: statusColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (service.statusType == 'listening' || service.isSpeaking)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionSection(AudioInterviewService service) {
    final questionText = service.getCurrentQuestionText();
    
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Current Question',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (questionText.isNotEmpty)
              Text(
                questionText,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.4,
                ),
              )
            else
              const Text(
                'Ready to start the interview? Click "Start Interview" below!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRecognitionSection(AudioInterviewService service) {
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  service.isListening ? Icons.mic : Icons.mic_none,
                  color: service.isListening ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  service.isListening ? 'Listening...' : 'Voice Recognition',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: service.isListening ? Colors.red[50] : Colors.grey[100],
                border: Border.all(
                  color: service.isListening ? Colors.red[200]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                service.currentRecognizedText.isNotEmpty
                    ? service.currentRecognizedText
                    : service.isListening
                        ? 'Listening for your response...'
                        : 'Your response will appear here',
                style: TextStyle(
                  fontSize: 16,
                  color: service.currentRecognizedText.isNotEmpty
                      ? Colors.black87
                      : Colors.grey[600],
                  fontStyle: service.currentRecognizedText.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
            if (service.currentRecognizedText.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => service.confirmCurrentResponse(),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm Response'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => service.retryCurrentQuestion(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons(AudioInterviewService service) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Interview Controls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!service.isActive)
                  ElevatedButton.icon(
                    onPressed: () => service.startInterview(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Interview'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (service.isActive) ...[
                  ElevatedButton.icon(
                    onPressed: () => service.togglePauseResume(),
                    icon: Icon(service.isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(service.isPaused ? 'Resume' : 'Pause'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: service.isPaused ? Colors.green : Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => service.skipCurrentQuestion(),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip Question'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => service.retryCurrentQuestion(),
                    icon: const Icon(Icons.replay),
                    label: const Text('Repeat Question'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () => _showRestartDialog(service),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart Interview'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsesPreview(AudioInterviewService service) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Interview Progress',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${service.interviewData.responses.length} responses',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (service.interviewData.responses.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _showInterviewSummary(service),
                        icon: const Icon(Icons.summarize, size: 16),
                        label: const Text('Summary', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: service.interviewData.responses.isEmpty
                ? const Center(
                    child: Text(
                      'No responses yet. Start the interview to begin collecting information.',
                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: service.interviewData.responses.length,
                    itemBuilder: (context, index) {
                      final response = service.interviewData.responses[index];
                      return ListTile(
                        dense: true,
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: _getCategoryColor(response.type).withOpacity(0.2),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _getCategoryColor(response.type),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(response.type).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getCategoryDisplayName(response.type),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _getCategoryColor(response.type),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              response.question,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          response.answer,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInterviewSummary(AudioInterviewService service) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Interview Summary by Category',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildCategorizedResponses(service),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategorizedResponses(AudioInterviewService service) {
    // Group responses by category
    final responsesByCategory = <String, List<InterviewResponse>>{};
    for (final response in service.interviewData.responses) {
      final category = response.type;
      if (!responsesByCategory.containsKey(category)) {
        responsesByCategory[category] = [];
      }
      responsesByCategory[category]!.add(response);
    }

    final categories = responsesByCategory.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final responses = responsesByCategory[category]!;
        final displayName = _getCategoryDisplayName(category);
        final categoryColor = _getCategoryColor(category);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ExpansionTile(
            title: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${responses.length}',
                    style: TextStyle(
                      color: categoryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            children: responses.map((response) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      response.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      response.answer,
                      style: const TextStyle(
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'identity':
        return Colors.purple;
      case 'personality':
        return Colors.orange;
      case 'interests':
        return Colors.green;
      case 'relationships':
        return Colors.pink;
      case 'preferences':
        return Colors.teal;
      case 'daily_life':
        return Colors.indigo;
      case 'challenges':
        return Colors.red;
      case 'voice':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildBottomActionBar(AudioInterviewService service) {
    final canGenerate = service.interviewData.responses.isNotEmpty && !service.isActive;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canGenerate ? () => _generateProfile(service) : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate User Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog(AudioInterviewService service) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Restart Interview'),
          content: const Text(
            'Are you sure you want to restart the interview? This will clear all current responses.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                service.restartInterview();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Restart', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateProfile(AudioInterviewService service) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating user profile...'),
                SizedBox(height: 8),
                Text(
                  'This may take a moment as we process your interview responses.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );

      final result = await service.generateAndProcessNarrative();
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        // Show success dialog and return results
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Profile Generated!'),
                ],
              ),
              content: const Text(
                'Your user profile has been successfully generated from the interview responses. '
                'You can now review and edit it in the User Information page.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(result); // Return to previous page with results
                  },
                  child: const Text('View Profile'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Generation Failed'),
                ],
              ),
              content: Text(
                'Failed to generate user profile: $e\n\n'
                'Please try again or enter the information manually.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    }
  }
}