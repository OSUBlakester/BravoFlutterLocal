import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/environment_config.dart';
import 'services/authenticated_http_client.dart';
import 'services/user_settings_provider.dart';

class EmailPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;

  const EmailPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
  });

  @override
  State<EmailPage> createState() => _EmailPageState();
}

enum _EmailViewMode { home, inbox, compose, composeDraft, messageActions }

class _EmailPageState extends State<EmailPage> {
  bool _isLoading = false;
  String? _statusMessage;
  Map<String, dynamic>? _providerStatus;
  List<Map<String, dynamic>> _inboxItems = [];
  List<Map<String, dynamic>> _contacts = [];
  Map<String, dynamic>? _selectedEmail;
  Map<String, dynamic>? _selectedRecipient;
  List<String> _replyOptions = [];
  final Map<String, int> _recipientUsageEpoch = {};
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  _EmailViewMode _viewMode = _EmailViewMode.home;

  bool get _isConnected => (_providerStatus?['connected'] ?? false) == true;
  String get _recipientUsagePrefsKey => 'email_recency_${widget.aacUserId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecipientUsage();
      _loadProviderStatus();
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _announceEmailContent(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.speak(trimmed);
    } catch (_) {
      SemanticsService.announce(trimmed, Directionality.of(context));
    }
  }

  String? _extractEmailAddress(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }

    final bracketMatch = RegExp(r'<([^>]+)>').firstMatch(value);
    if (bracketMatch != null) {
      final candidate = (bracketMatch.group(1) ?? '').trim();
      if (candidate.contains('@')) {
        return candidate;
      }
    }

    if (value.contains('@')) {
      return value;
    }
    return null;
  }

  Future<void> _startReplyProcess() async {
    final selectedEmail = _selectedEmail;
    if (selectedEmail == null) {
      _showPlannedAction('Select an email first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating reply options...';
    });

    try {
      final subject = (selectedEmail['subject'] ?? '').toString().trim();
      final bodyText = (selectedEmail['body_text'] ?? '').toString().trim();
      final snippet = (selectedEmail['snippet'] ?? '').toString().trim();
      final fromRaw =
          (selectedEmail['sender_email'] ?? selectedEmail['from'] ?? '')
              .toString();
      final fromEmail = _extractEmailAddress(fromRaw) ?? fromRaw;
      final contentForPrompt = bodyText.isNotEmpty ? bodyText : snippet;
      final limit = await _resolveOptionLimit();

      final prompt = '''
Generate $limit short reply options for this email.
Use first-person AAC-friendly responses (concise, practical, polite).
Incoming email from: $fromEmail
Subject: $subject
Email content:
$contentForPrompt
''';

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/generate-options',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'prompt': prompt,
          'count': limit,
        }),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Unable to generate reply options (${response.statusCode}).';
        });
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final options =
          (data['options'] as List<dynamic>? ?? [])
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList();

      final replyRecipient =
          (selectedEmail['sender_email'] ?? _extractEmailAddress(fromRaw) ?? '')
              .toString()
              .trim();
      final replyName =
          (selectedEmail['sender_name'] ?? _extractEmailAddress(fromRaw) ?? '')
              .toString()
              .trim();

      if (replyRecipient.isNotEmpty) {
        _selectedRecipient = {
          'email': replyRecipient,
          'name': replyName,
          'display_name': replyName,
        };
      }

      if (subject.isNotEmpty) {
        _subjectController.text =
            subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject';
      }

      if (options.isNotEmpty) {
        _bodyController.text = options.first;
      }

      setState(() {
        _replyOptions = options;
        _viewMode = _EmailViewMode.composeDraft;
        _isLoading = false;
        _statusMessage = options.isEmpty
            ? 'No reply options generated. You can still compose manually.'
            : 'Reply options generated. Choose one or edit before sending.';
      });

      if (options.isNotEmpty) {
        await _announceEmailContent('Reply options ready. ${options.first}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to generate reply options: $e';
      });
    }
  }

  Future<void> _deleteSelectedEmail() async {
    final selectedEmail = _selectedEmail;
    if (selectedEmail == null) {
      _showPlannedAction('Select an email first.');
      return;
    }
    final messageId = (selectedEmail['id'] ?? '').toString().trim();
    if (messageId.isEmpty) {
      _showPlannedAction('Unable to delete email: missing id.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Deleting email...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/email/messages/${Uri.encodeComponent(messageId)}/delete',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: '{}',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _inboxItems.removeWhere((item) =>
              (item['id'] ?? '').toString().trim() == messageId);
          _selectedEmail = null;
          _viewMode = _EmailViewMode.inbox;
          _isLoading = false;
          _statusMessage = 'Email moved to trash.';
        });
        await _announceEmailContent('Email deleted.');
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to delete email (${response.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to delete email: $e';
      });
    }
  }

  Future<void> _loadRecipientUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recipientUsagePrefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final parsed = json.decode(raw);
      if (parsed is! Map) {
        return;
      }

      _recipientUsageEpoch.clear();
      for (final entry in parsed.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = int.tryParse(entry.value.toString()) ?? 0;
        if (key.isNotEmpty && value > 0) {
          _recipientUsageEpoch[key] = value;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveRecipientUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recipientUsagePrefsKey, json.encode(_recipientUsageEpoch));
    } catch (_) {}
  }

  List<Map<String, dynamic>> _sortContactsByRecency(
    List<Map<String, dynamic>> contacts,
  ) {
    final sorted = List<Map<String, dynamic>>.from(contacts);
    sorted.sort((a, b) {
      final aEmail = (a['email'] ?? '').toString().trim().toLowerCase();
      final bEmail = (b['email'] ?? '').toString().trim().toLowerCase();
      final aUsed = _recipientUsageEpoch[aEmail] ?? 0;
      final bUsed = _recipientUsageEpoch[bEmail] ?? 0;
      if (aUsed != bUsed) {
        return bUsed.compareTo(aUsed);
      }
      final aName =
          (a['display_name'] ?? a['name'] ?? aEmail).toString().toLowerCase();
      final bName =
          (b['display_name'] ?? b['name'] ?? bEmail).toString().toLowerCase();
      return aName.compareTo(bName);
    });
    return sorted;
  }

  Future<void> _selectRecipient(Map<String, dynamic> contact) async {
    final email = (contact['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty) {
      _recipientUsageEpoch[email] = DateTime.now().millisecondsSinceEpoch;
      await _saveRecipientUsage();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = _sortContactsByRecency(_contacts);
      _selectedRecipient = contact;
      final selectedName =
          (contact['display_name'] ?? contact['name'] ?? email).toString();
      _statusMessage =
          'Recipient selected: ${selectedName.isEmpty ? email : selectedName}.';
    });
  }

  Future<void> _sendComposeDraft() async {
    final recipient = (_selectedRecipient?['email'] ?? '').toString().trim();
    if (recipient.isEmpty) {
      _showPlannedAction('Select a recipient first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Sending email...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/email/send',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'to': [recipient],
          'subject': _subjectController.text.trim(),
          'body': _bodyController.text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Email sent successfully.';
          _subjectController.clear();
          _bodyController.clear();
          _viewMode = _EmailViewMode.home;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent successfully.')),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage =
            'Unable to send email (${response.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to send email: $e';
      });
    }
  }

  Future<void> _loadProviderStatus() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading email status...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/email/status',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        // Backend returns {provider_status: {gmail: {...}}}
        // Extract the gmail provider status from the nested structure
        final providerStatusRoot = data['provider_status'] as Map<String, dynamic>?;
        final gmailStatus = providerStatusRoot?['gmail'] as Map<String, dynamic>? ?? {};
        
        setState(() {
          _providerStatus = gmailStatus;
          _statusMessage = _isConnected ? 'Connected to Gmail' : 'Not connected';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load email status (${response.statusCode}).';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load email status: $e';
        _isLoading = false;
      });
    }
  }

  Future<int> _resolveOptionLimit() async {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    if (settingsProvider.settings == null) {
      settingsProvider.idToken = widget.idToken;
      settingsProvider.userId = widget.aacUserId;
      await settingsProvider.fetchSettings();
    }

    return settingsProvider.settings?.llmOptions ?? 10;
  }

  Future<void> _loadInbox() async {
    setState(() {
      _isLoading = true;
      _viewMode = _EmailViewMode.inbox;
      _statusMessage = 'Loading inbox...';
    });

    try {
      final limit = await _resolveOptionLimit();
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/email/inbox?max_results=$limit',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = (data['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final providerStatus =
            (data['provider_status'] as Map<String, dynamic>?) ?? _providerStatus;

        if (!mounted) return;
        setState(() {
          _providerStatus = providerStatus;
          _inboxItems = items;
          _statusMessage = items.isEmpty
              ? 'No inbox messages available yet.'
              : 'Loaded ${items.length} email item(s).';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load inbox (${response.statusCode}).';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load inbox: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _viewMode = _EmailViewMode.compose;
      _statusMessage = 'Loading contacts...';
    });

    try {
      final limit = await _resolveOptionLimit();
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/email/contacts?max_results=$limit',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final contacts = (data['contacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final providerStatus =
            (data['provider_status'] as Map<String, dynamic>?) ?? _providerStatus;

        if (!mounted) return;
        setState(() {
          _providerStatus = providerStatus;
          _contacts = _sortContactsByRecency(contacts);
          _selectedRecipient = null;
          _statusMessage = contacts.isEmpty
              ? 'No provider contacts available yet.'
              : 'Loaded ${contacts.length} contact(s).';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load contacts (${response.statusCode}).';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to load contacts: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _attemptConnect() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking Gmail connection...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/email/connect-url',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'provider': 'gmail'}),
      );

      final body = response.body.isNotEmpty
          ? json.decode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      final message =
          (body['message'] ?? body['detail'] ?? 'Unable to start Gmail connection.')
              .toString();
      final connectUrl = (body['connect_url'] ?? '').toString().trim();
      final canLaunchConnect = connectUrl.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _statusMessage = message;
        _isLoading = false;
      });

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gmail connect failed: $message')),
        );
        return;
      }

      if (canLaunchConnect) {
        final oauthUri = Uri.tryParse(connectUrl);
        if (oauthUri != null) {
          final launched = await launchUrl(
            oauthUri,
            mode: LaunchMode.externalApplication,
          );

          if (launched) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gmail sign-in opened. Return here and tap Refresh Status after granting access.'),
              ),
            );
            return;
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to start Gmail connection: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectEmail(Map<String, dynamic> email) async {
    setState(() {
      _selectedEmail = email;
      _viewMode = _EmailViewMode.messageActions;
      _isLoading = true;
      _statusMessage = 'Loading email content...';
    });

    final messageId = (email['id'] ?? '').toString().trim();
    if (messageId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to load selected email content.';
      });
      return;
    }

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/email/messages/${Uri.encodeComponent(messageId)}',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final detailedMessage =
            (data['message'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final merged = {...email, ...detailedMessage};
        final subject = (merged['subject'] ?? 'Untitled email').toString();
        final snippet = (merged['snippet'] ?? '').toString();
        final bodyText = (merged['body_text'] ?? '').toString();

        setState(() {
          _selectedEmail = merged;
          _isLoading = false;
          _replyOptions = [];
          _statusMessage = 'Loaded message content.';
        });

        final announceText = bodyText.trim().isNotEmpty
            ? 'Email: $subject. ${bodyText.trim()}'
            : (snippet.trim().isNotEmpty
                ? 'Email: $subject. ${snippet.trim()}'
                : 'Email selected: $subject');
        await _announceEmailContent(announceText);
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage =
            'Unable to load message content (${response.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to load message content: $e';
      });
    }
  }

  void _showPlannedAction(String message) {
    setState(() {
      _statusMessage = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildStatusCard() {
    final provider = 'gmail';
    final connectedEmail = (_providerStatus?['email_address'] ?? '').toString();
    final oauthConfigured = (_providerStatus?['scope'] as List?)?.isNotEmpty == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Provider: ${provider.toUpperCase()}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_isConnected ? 'Connected' : 'Not connected'),
            if (connectedEmail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Account: $connectedEmail'),
            ],
            const SizedBox(height: 4),
            Text(oauthConfigured ? 'OAuth configured on server' : 'OAuth not configured on server'),
            if ((_statusMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_statusMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(label, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  Widget _buildDisconnectedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        _buildPrimaryButton(
          label: 'Connect Gmail',
          icon: Icons.link,
          onPressed: _attemptConnect,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Refresh Status',
          icon: Icons.refresh,
          onPressed: _loadProviderStatus,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Go Back',
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildHomeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        _buildPrimaryButton(
          label: 'Read Existing Email',
          icon: Icons.inbox_outlined,
          onPressed: _loadInbox,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Compose New Email',
          icon: Icons.edit_outlined,
          onPressed: _loadContacts,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Refresh Status',
          icon: Icons.refresh,
          onPressed: _loadProviderStatus,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Go Back',
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildInboxView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        if (_inboxItems.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'Inbox subjects will appear here once Gmail is connected.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _inboxItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _inboxItems[index];
                final subject = (item['subject'] ?? 'Untitled email').toString();
                final fromEmail =
                    (item['sender_email'] ?? item['from_email'] ?? '').toString();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(subject),
                    subtitle: fromEmail.isEmpty ? null : Text(fromEmail),
                    onTap: () => _selectEmail(item),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Go Back',
          icon: Icons.arrow_back,
          onPressed: () {
            setState(() {
              _viewMode = _EmailViewMode.home;
              _selectedEmail = null;
              _statusMessage = 'Back to email home.';
            });
          },
        ),
      ],
    );
  }

  Widget _buildComposeView() {
    final selectedEmail = (_selectedRecipient?['email'] ?? '').toString();
    final selectedName = (_selectedRecipient?['name'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compose Shell',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Provider contacts will appear here after Gmail is connected. Later this view will feed recipients into the AAC email compose workflow.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_contacts.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No contacts available yet.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final contactName =
                    (contact['display_name'] ?? contact['name'] ?? 'Unknown')
                        .toString();
                final email = (contact['email'] ?? '').toString();
                final isSelected =
                    selectedEmail.isNotEmpty && selectedEmail == email;

                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(contactName),
                    subtitle: Text(email),
                    trailing:
                        isSelected
                            ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                    onTap: () => _selectRecipient(contact),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Continue with Recipient',
          icon: Icons.arrow_forward,
          onPressed:
              selectedEmail.isEmpty
                  ? null
                  : () {
                    setState(() {
                      _viewMode = _EmailViewMode.composeDraft;
                      _statusMessage =
                          'Composing to ${selectedName.isNotEmpty ? selectedName : selectedEmail}.';
                    });
                  },
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Refresh Contacts',
          icon: Icons.refresh,
          onPressed: _loadContacts,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Go Back',
          icon: Icons.arrow_back,
          onPressed: () {
            setState(() {
              _viewMode = _EmailViewMode.home;
              _statusMessage = 'Back to email home.';
            });
          },
        ),
      ],
    );
  }

  Widget _buildComposeDraftView() {
    final recipient = (_selectedRecipient?['email'] ?? '').toString();
    final recipientName =
        (_selectedRecipient?['display_name'] ?? _selectedRecipient?['name'] ?? '')
            .toString();
    final recipientDisplay =
        recipientName.trim().isEmpty ? recipient : '$recipientName <$recipient>';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Compose Email',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('To: $recipientDisplay'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyController,
                      maxLines: 8,
                      minLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_replyOptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Suggested Replies',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._replyOptions.map(
                        (option) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _bodyController.text = option;
                                _statusMessage = 'Reply option selected.';
                              });
                            },
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(option),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Send Email',
          icon: Icons.send,
          onPressed: recipient.trim().isEmpty ? null : _sendComposeDraft,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Back to Recipients',
          icon: Icons.arrow_back,
          onPressed: () {
            setState(() {
              _viewMode = _EmailViewMode.compose;
              _statusMessage = 'Back to recipients.';
            });
          },
        ),
      ],
    );
  }

  Widget _buildMessageActionsView() {
    final selectedEmail = _selectedEmail;
    final subject = (selectedEmail?['subject'] ?? 'Untitled email').toString();
    final from = (selectedEmail?['from'] ?? '').toString();
    final date = (selectedEmail?['date'] ?? '').toString();
    final bodyText = (selectedEmail?['body_text'] ?? '').toString().trim();
    final snippet = (selectedEmail?['snippet'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selected Email',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(subject, style: const TextStyle(fontSize: 16)),
                  if (from.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('From: $from'),
                  ],
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Date: $date'),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    bodyText.isNotEmpty
                        ? bodyText
                        : (snippet.isNotEmpty ? snippet : 'No message content available.'),
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildPrimaryButton(
          label: 'Reply',
          icon: Icons.reply_outlined,
          onPressed: _startReplyProcess,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Delete',
          icon: Icons.delete_outline,
          onPressed: _deleteSelectedEmail,
        ),
        const SizedBox(height: 12),
        _buildPrimaryButton(
          label: 'Go Back',
          icon: Icons.arrow_back,
          onPressed: () {
            setState(() {
              _viewMode = _EmailViewMode.inbox;
              _selectedEmail = null;
              _statusMessage = 'Back to inbox.';
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: !_isConnected
                    ? _buildDisconnectedView()
                    : switch (_viewMode) {
                        _EmailViewMode.home => _buildHomeView(),
                        _EmailViewMode.inbox => _buildInboxView(),
                        _EmailViewMode.compose => _buildComposeView(),
                        _EmailViewMode.composeDraft => _buildComposeDraftView(),
                        _EmailViewMode.messageActions => _buildMessageActionsView(),
                      },
              ),
            ),
          ),
          if (_isLoading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
