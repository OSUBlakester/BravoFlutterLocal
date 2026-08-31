import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// Status for each word in a custom phrase
enum WordSearchStatus { found, foundWithModifier, notFound }

class WordSearchResult {
  final WordSearchStatus status;
  final String? foundAs;
  const WordSearchResult(this.status, {this.foundAs});
}

class ShowMeDialog extends StatefulWidget {
  final Future<Map<String, WordSearchResult>> Function(String phrase) onValidatePhrase;

  const ShowMeDialog({super.key, required this.onValidatePhrase});

  @override
  State<ShowMeDialog> createState() => _ShowMeDialogState();
}

class _ShowMeDialogState extends State<ShowMeDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedPhrase; // For level tabs

  // Custom tab state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _transcribedText = '';
  bool _isValidating = false;
  Map<String, WordSearchResult>? _validationResults;

  static const _level1 = [
    'I am happy',
    'Want to play',
    'You are funny',
    'Hello everyone',
    'Where is my toy',
  ];
  static const _level2 = [
    'Want more music',
    "I don't dance",
    'Stop that dog',
    'I am cold',
    'More juice please',
  ];
  static const _level3 = [
    'I need a break',
    'Yes I want that tablet',
    'No I don\'t want that medicine',
    'Happy to see you friend',
    'Do you like my shirt',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available) return;
    setState(() {
      _isListening = true;
      _transcribedText = '';
      _validationResults = null;
    });
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() => _transcribedText = result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _validatePhrase() async {
    if (_transcribedText.trim().isEmpty) return;
    setState(() => _isValidating = true);
    final results = await widget.onValidatePhrase(_transcribedText);
    if (mounted) {
      setState(() {
        _validationResults = results;
        _isValidating = false;
      });
    }
  }

  Widget _buildLevelTab(List<String> phrases) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final phrase in phrases)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() => _selectedPhrase = phrase),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedPhrase == phrase
                        ? Colors.amber[700]!
                        : Colors.grey[300]!,
                    width: _selectedPhrase == phrase ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _selectedPhrase == phrase
                      ? Colors.amber[50]
                      : Colors.white,
                ),
                child: Text(
                  phrase,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: _selectedPhrase == phrase
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _selectedPhrase != null && _tabController.index != 3
              ? () => Navigator.of(context).pop(_selectedPhrase)
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Go'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTab() {
    final hasText = _transcribedText.trim().isNotEmpty;
    final anyFound = _validationResults?.values.any(
          (r) => r.status != WordSearchStatus.notFound,
        ) ??
        false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tap the microphone and speak a phrase.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: Text(
                  _transcribedText.isEmpty ? 'Your phrase will appear here...' : _transcribedText,
                  style: TextStyle(
                    fontSize: 18,
                    color: _transcribedText.isEmpty ? Colors.grey[400] : Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 28,
              backgroundColor: _isListening ? Colors.red : Colors.amber[700],
              child: IconButton(
                icon: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
                onPressed: _isListening ? _stopListening : _startListening,
                tooltip: _isListening ? 'Stop' : 'Start dictation',
              ),
            ),
          ],
        ),
        if (hasText) ...[
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isValidating ? null : _validatePhrase,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: _isValidating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirm words'),
          ),
        ],
        if (_validationResults != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Word check:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          for (final entry in _validationResults!.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    entry.value.status == WordSearchStatus.notFound
                        ? Icons.cancel
                        : entry.value.status == WordSearchStatus.foundWithModifier
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle,
                    color: entry.value.status == WordSearchStatus.notFound
                        ? Colors.red
                        : entry.value.status == WordSearchStatus.foundWithModifier
                            ? Colors.orange
                            : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (entry.value.status == WordSearchStatus.foundWithModifier &&
                      entry.value.foundAs != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(via "${entry.value.foundAs}" + modifier)',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                  if (entry.value.status == WordSearchStatus.notFound) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'not found on boards',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: anyFound ? () => Navigator.of(context).pop(_transcribedText) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Go'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        height: 560,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.amber[700],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Show Me',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              onTap: (_) => setState(() {
                _selectedPhrase = null; // Clear selection when switching tabs
              }),
              labelColor: Colors.amber[800],
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.amber[700],
              tabs: const [
                Tab(text: 'Level 1'),
                Tab(text: 'Level 2'),
                Tab(text: 'Level 3'),
                Tab(text: 'Custom'),
              ],
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLevelTab(_level1),
                  _buildLevelTab(_level2),
                  _buildLevelTab(_level3),
                  _buildCustomTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
