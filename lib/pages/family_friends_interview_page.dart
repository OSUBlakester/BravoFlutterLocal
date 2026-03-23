import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/family_friends_interview_service.dart';

class FamilyFriendsInterviewPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final Function(ExtractedPerson)? onPersonAdded;
  const FamilyFriendsInterviewPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.onPersonAdded,
  });

  @override
  State<FamilyFriendsInterviewPage> createState() => _FamilyFriendsInterviewPageState();
}

class _FamilyFriendsInterviewPageState extends State<FamilyFriendsInterviewPage> {
  late FamilyFriendsInterviewService _service;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize interview service (it will handle wake word service management)
    _service = FamilyFriendsInterviewService();
    _service.setAuthenticationDetails(widget.idToken, widget.aacUserId);
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _service.initializeSpeech();
    setState(() {
      _isInitialized = true;
    });
    
    // Auto-start the interview
    if (_isInitialized) {
      await _service.startInterview();
    }
  }

  @override
  void dispose() {
    // Service will handle wake word re-enabling in its own dispose method
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _service,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: _isInitialized ? _buildInterviewContent() : _buildLoadingScreen(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Initializing Family & Friends Interview...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
    return Consumer<FamilyFriendsInterviewService>(
      builder: (context, service, child) {
        return Column(
          children: [
            _buildHeader(service),
            _buildProgressSection(service),
            if (service.extractedPerson != null) 
              _buildResultsSection(service)
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    children: [
                      _buildQuestionSection(service),
                      const SizedBox(height: 8),
                      _buildRecognitionSection(service),
                      const SizedBox(height: 8),
                      _buildControlButtons(service),
                    ],
                  ),
                ),
              ),
            _buildBottomActions(service),
          ],
        );
      },
    );
  }

  Widget _buildHeader(FamilyFriendsInterviewService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.people, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Person Interview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tell us about someone important',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(FamilyFriendsInterviewService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Only show question counter during active interview
              if (service.isActive && service.currentQuestionIndex < service.totalQuestions)
                Text(
                  'Question ${service.currentQuestionIndex + 1} of ${service.totalQuestions}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                )
              else if (!service.isActive)
                const Text(
                  'Interview Complete',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              const Spacer(), // Push status to the right
              Text(
                _getStatusText(service.statusType),
                style: TextStyle(
                  fontSize: 14,
                  color: _getStatusColor(service.statusType),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: service.progress,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
          ),
          if (service.status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              service.status,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionSection(FamilyFriendsInterviewService service) {
    final questionText = service.getCurrentQuestionText();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: Colors.blue[600], size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Question',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (questionText.isNotEmpty)
              Text(
                questionText,
                style: const TextStyle(fontSize: 14, height: 1.3),
              )
            else
              const Text(
                'Preparing your question...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognitionSection(FamilyFriendsInterviewService service) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  service.isListening ? Icons.mic : Icons.mic_none,
                  color: service.isListening ? Colors.red : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  service.isListening ? 'Listening...' : 'Your Response',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: service.isListening ? Colors.red[300]! : Colors.grey[300]!,
                ),
              ),
              child: Text(
                service.currentRecognizedText.isEmpty
                    ? (service.isListening ? 'Listening for your response...' : 'Waiting for question...')
                    : service.currentRecognizedText,
                style: TextStyle(
                  fontSize: 13,
                  color: service.currentRecognizedText.isEmpty ? Colors.grey[600] : Colors.black87,
                  fontStyle: service.currentRecognizedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons(FamilyFriendsInterviewService service) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        // Always show confirm/retry buttons if there's recognized text
        if (service.currentRecognizedText.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: service.isConfirming ? () => service.confirmResponse() : null,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(80, 32),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => service.retryResponse(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try Again', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(80, 32),
            ),
          ),
        ],
        if (service.isActive) ...[
          OutlinedButton.icon(
            onPressed: () => service.skipQuestion(),
            icon: const Icon(Icons.skip_next, size: 16),
            label: const Text('Skip', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(60, 32),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => service.togglePauseResume(),
            icon: Icon(service.isPaused ? Icons.play_arrow : Icons.pause, size: 16),
            label: Text(
              service.isPaused ? 'Resume' : 'Pause',
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: service.isPaused ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(70, 32),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultsSection(FamilyFriendsInterviewService service) {
    final person = service.extractedPerson!;
    
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600], size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      'Person Information Collected',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPersonDetail('Name', person.name),
                _buildPersonDetail('Relationship', person.relationship),
                if (person.about.isNotEmpty) 
                  _buildPersonDetail('About', person.about),
                if (person.birthday.isNotEmpty) 
                  _buildPersonDetail('Birthday', person.birthday),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : 'Not provided',
            style: TextStyle(
              fontSize: 14,
              color: value.isNotEmpty ? Colors.black87 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(FamilyFriendsInterviewService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (service.extractedPerson != null) ...[
            ElevatedButton.icon(
              onPressed: () {
                widget.onPersonAdded?.call(service.extractedPerson!);
                // Show success message instead of immediately closing dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${service.extractedPerson!.name} has been added to Friends & Family!'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
                // Close the dialog after a brief delay
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    Navigator.of(context).pop(service.extractedPerson!);
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Person'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
              ),
            ),
          ] else if (service.isActive) ...[
            ElevatedButton.icon(
              onPressed: () => service.stopInterview(),
              icon: const Icon(Icons.stop),
              label: const Text('Stop Interview'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusText(String statusType) {
    switch (statusType) {
      case 'listening':
        return 'Listening';
      case 'success':
        return 'Success';
      case 'error':
        return 'Error';
      case 'warning':
        return 'Attention';
      default:
        return 'Ready';
    }
  }

  Color _getStatusColor(String statusType) {
    switch (statusType) {
      case 'listening':
        return Colors.red[600]!;
      case 'success':
        return Colors.green[600]!;
      case 'error':
        return Colors.red[600]!;
      case 'warning':
        return Colors.orange[600]!;
      default:
        return Colors.blue[600]!;
    }
  }
}