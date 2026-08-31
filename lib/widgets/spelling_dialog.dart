import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../config/environment_config.dart';
import '../tap_interface_page.dart'; // For TapInterfaceButton
import '../services/user_settings_provider.dart';

class SpellingDialog extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String currentContext; // For prediction context
  final Function(String) onWordSelected;

  const SpellingDialog({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.currentContext,
    required this.onWordSelected,
  });

  @override
  State<SpellingDialog> createState() => _SpellingDialogState();
}

class _SpellingDialogState extends State<SpellingDialog> {
  final TextEditingController _spellingWordController = TextEditingController();
  List<String> _currentPredictions = [];
  List<String> _validLetters = [];
  bool _isLoading = false;
  String _currentSpellingWord = "";

  @override
  void initState() {
    super.initState();
    _validLetters = _getAllLetters();
    _getWordPredictions();
  }

  @override
  void dispose() {
    _spellingWordController.dispose();
    super.dispose();
  }

  List<String> _getAllLetters() {
    // Get letter order from user settings
    final settings = Provider.of<UserSettingsProvider>(context, listen: false).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';
    
    if (letterOrder == 'qwerty') {
      // QWERTY keyboard layout - flatten the rows
      return ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P',
              'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L',
              'Z', 'X', 'C', 'V', 'B', 'N', 'M'];
    } else if (letterOrder == 'frequency') {
      // Frequency-based order: ETAOIN SHRDLU CMFWGY P BVKX JZQ
      return 'ETAOINSHRDLUCMFWGYPBVKXJZQ'.split('');
    } else {
      // Alphabetical (default)
      return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }
  }

  List<String> _getValidLetters(String currentWord) {
    // Always return all letters to prevent blocking valid words
    // The previous logic was too restrictive and blocked valid combinations (e.g. "to" -> "u" for "touchdown")
    return _getAllLetters();
  }

  void _handleLetterClick(String letter) {
    setState(() {
      _currentSpellingWord += letter.toLowerCase();
      _spellingWordController.text = _currentSpellingWord;
      _validLetters = _getValidLetters(_currentSpellingWord);
    });
    
    _getWordPredictions();
  }

  void _backspaceCurrentWord() {
    if (_currentSpellingWord.isNotEmpty) {
      setState(() {
        _currentSpellingWord = _currentSpellingWord.substring(0, _currentSpellingWord.length - 1);
        _spellingWordController.text = _currentSpellingWord;
        _validLetters = _getValidLetters(_currentSpellingWord);
      });
      _getWordPredictions();
    }
  }

  void _addCurrentWordToBuildSpace() {
    if (_currentSpellingWord.trim().isNotEmpty) {
      widget.onWordSelected(_currentSpellingWord);
    }
  }

  Future<void> _getWordPredictions() async {
    // Don't fetch if word is empty
    if (_currentSpellingWord.isEmpty) {
      setState(() {
        _currentPredictions = [];
      });
      return;
    }

    // Allow concurrent requests, but only update if it's the latest one
    // This prevents race conditions where an old request overwrites a new one
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final url = '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-prediction';
      final headers = {
        'Authorization': 'Bearer ${widget.idToken}',
        'X-User-ID': widget.aacUserId,
        'Content-Type': 'application/json',
      };
      final body = json.encode({
        'text': widget.currentContext, // Context from build space
        'spelling_word': _currentSpellingWord, // Current partial word being spelled
        'predict_full_words': true, // Flag to ensure complete words are returned
      });
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );
      
      debugPrint('SpellingDialog: API Response (${response.statusCode}): ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<String> predictions = List<String>.from(data['predictions'] ?? []);
        
        // Convert completions to full words
        if (_currentSpellingWord.trim().isNotEmpty) {
          predictions = predictions.map((prediction) {
            String currentWord = _currentSpellingWord.toLowerCase();
            String predictionLower = prediction.toLowerCase();
            
            // If the prediction already starts with the current word (case-insensitive), use it as is
            if (predictionLower.startsWith(currentWord)) {
              return prediction;
            } 
            // If the prediction is just the suffix, append it to the current word
            else {
              // Check if it's a suffix by seeing if the prediction is shorter than the current word
              // or if it doesn't look like a full word on its own
              return _currentSpellingWord + prediction;
            }
          }).toList();
        }
        
        // Deduplicate predictions
        predictions = predictions.toSet().toList();
        
        if (mounted) {
          setState(() {
            _currentPredictions = predictions;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentPredictions = [];
          });
        }
      }
    } catch (e) {
      debugPrint('SpellingDialog: Error getting word predictions: $e');
      if (mounted) {
        setState(() {
          _currentPredictions = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SafeArea(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            // Header + word display in one compact row
            Row(
              children: [
                const Text('Spell Word', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      _currentSpellingWord.isEmpty ? 'Start typing...' : _currentSpellingWord,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _currentSpellingWord.isEmpty ? Colors.grey : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_currentSpellingWord.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.backspace, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _backspaceCurrentWord,
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _addCurrentWordToBuildSpace,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Predictions Row
            SizedBox(
              height: 40,
              width: double.infinity,
              child: _isLoading
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : _currentPredictions.isEmpty
                  ? Center(
                      child: Text(
                        _currentSpellingWord.isEmpty ? 'Start typing for predictions' : 'No predictions found',
                        style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      scrollDirection: Axis.horizontal,
                      itemCount: _currentPredictions.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        return ActionChip(
                          label: Text(_currentPredictions[index], style: const TextStyle(fontSize: 14)),
                          onPressed: () => widget.onWordSelected(_currentPredictions[index]),
                          backgroundColor: Colors.blue[50],
                          side: BorderSide(color: Colors.blue[200]!),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            
            // Keyboard
            Expanded(
              child: Consumer<UserSettingsProvider>(
                builder: (context, provider, child) {
                  final letterOrder = provider.settings?.spellLetterOrder ?? 'alphabetical';
                  final letters = _getAllLetters();
                  
                  // QWERTY layout needs special handling with 10 columns for top row
                  if (letterOrder == 'qwerty') {
                    return GridView.count(
                      crossAxisCount: 10,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: letters.map((letter) {
                        final isValid = _validLetters.contains(letter);
                        return Opacity(
                          opacity: isValid ? 1.0 : 0.3,
                          child: TapInterfaceButton(
                            label: letter,
                            onPressed: isValid ? () => _handleLetterClick(letter) : () {},
                            backgroundColor: isValid ? Colors.blue[100]! : Colors.grey[200]!,
                            foregroundColor: Colors.black,
                            borderColor: Colors.blue[300]!,
                            fontSize: 20,
                            enablePictograms: false,
                          ),
                        );
                      }).toList(),
                    );
                  }
                  
                  // Alphabetical and frequency use standard 9-column grid
                  return GridView.count(
                    crossAxisCount: 9,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: letters.map((letter) {
                      final isValid = _validLetters.contains(letter);
                      return Opacity(
                        opacity: isValid ? 1.0 : 0.3,
                        child: TapInterfaceButton(
                          label: letter,
                          onPressed: isValid ? () => _handleLetterClick(letter) : () {},
                          backgroundColor: isValid ? Colors.blue[100]! : Colors.grey[200]!,
                          foregroundColor: Colors.black,
                          borderColor: Colors.blue[300]!,
                          fontSize: 20,
                          enablePictograms: false,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
