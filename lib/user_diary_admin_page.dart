import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'config/environment_config.dart';

class UserDiaryAdminPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  const UserDiaryAdminPage({Key? key, required this.idToken, required this.aacUserId}) : super(key: key);

  @override
  State<UserDiaryAdminPage> createState() => _UserDiaryAdminPageState();
}

class _UserDiaryAdminPageState extends State<UserDiaryAdminPage> {
  final TextEditingController dateController = TextEditingController();
  final TextEditingController entryController = TextEditingController();
  String statusMessage = '';
  bool isLoading = false;
  bool isSaving = false;
  List<Map<String, dynamic>> diaryEntries = [];

  @override
  void initState() {
    super.initState();
    
    // Configure soft input mode for admin page (but don't show keyboard yet)
    _configureSoftInputMode();
    
    // Stop wake word listening when this page is shown
    final dynamic gridState = context.findAncestorStateOfType<State<StatefulWidget>>();
    if (gridState != null && gridState.runtimeType.toString() == '_GridPageState') {
      try {
        gridState._wakeWordService?.stopWakeWordListening();
      } catch (_) {}
    }
    fetchDiaryEntries();
  }

  Future<void> fetchDiaryEntries() async {
    setState(() { isLoading = true; });
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/diary-entries'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> entries = json.decode(response.body);
        entries.sort((a, b) => b['date'].compareTo(a['date']));
        setState(() { diaryEntries = List<Map<String, dynamic>>.from(entries); });
      } else {
        setState(() { statusMessage = 'Failed to load entries (${response.statusCode})'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error loading entries: $e'; });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  Future<void> saveDiaryEntry() async {
    final date = dateController.text;
    final entry = entryController.text.trim();
    if (date.isEmpty) {
      setState(() { statusMessage = 'Please select a date.'; });
      return;
    }
    if (entry.isEmpty) {
      setState(() { statusMessage = 'Entry cannot be empty.'; });
      return;
    }
    setState(() { isSaving = true; statusMessage = 'Saving...'; });
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/diary-entry'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({ 'date': date, 'entry': entry }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() { statusMessage = 'Entry saved successfully!'; });
        entryController.clear();
        fetchDiaryEntries();
      } else {
        setState(() { statusMessage = 'Save failed: ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error: $e'; });
    } finally {
      setState(() { isSaving = false; });
    }
  }

  Future<void> deleteDiaryEntry(String entryId) async {
    setState(() { statusMessage = 'Deleting...'; });
    try {
      final response = await http.delete(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/diary-entry/$entryId'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() { statusMessage = 'Entry deleted.'; });
        fetchDiaryEntries();
      } else {
        setState(() { statusMessage = 'Delete failed: ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error: $e'; });
    }
  }

  @override
  void dispose() {
    // Re-disable keyboard when leaving admin page
    _disableKeyboardForMainApp();
    
    dateController.dispose();
    entryController.dispose();
    super.dispose();
  }

  // *** KEYBOARD MANAGEMENT FOR ADMIN PAGES ***
  Future<void> _configureSoftInputMode() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        // Configure window to allow keyboard input
        await platform.invokeMethod('configureSoftInputMode');
        debugPrint('✅ Soft input mode configured for admin page');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to configure soft input mode: $e');
    }
  }

  Future<void> _showKeyboardWhenNeeded() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('showKeyboard');
        debugPrint('✅ Keyboard shown for text field');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to show keyboard: $e');
    }
  }

  Future<void> _disableKeyboardForMainApp() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('disableSoftKeyboard');
        debugPrint('✅ Keyboard disabled for main app');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to disable keyboard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Diary Input')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add/Edit Diary Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: dateController,
              decoration: const InputDecoration(labelText: 'Date', hintText: 'YYYY-MM-DD', border: OutlineInputBorder()),
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  dateController.text = picked.toIso8601String().substring(0, 10);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: entryController,
              maxLines: 6,
              onTap: () {
                // Show keyboard when text field is tapped
                _showKeyboardWhenNeeded();
              },
              decoration: const InputDecoration(
                labelText: 'Entry',
                hintText: 'Enter diary details here...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isSaving ? null : saveDiaryEntry,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Entry'),
                ),
                const SizedBox(width: 16),
                Text(statusMessage, style: TextStyle(color: statusMessage.contains('error') || statusMessage.contains('Error') ? Colors.red : Colors.green)),
              ],
            ),
            const Divider(height: 32),
            const Text('Diary Entries (Most Recent First)', style: TextStyle(fontWeight: FontWeight.bold)),
            isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : diaryEntries.isEmpty
                    ? const Text('No diary entries found.', style: TextStyle(color: Colors.grey))
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: diaryEntries.length,
                        itemBuilder: (context, index) {
                          final entry = diaryEntries[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              title: Text(entry['date'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(entry['entry'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => deleteDiaryEntry(entry['id'].toString()),
                              ),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}
