import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'config/environment_config.dart';
import 'services/user_settings_provider.dart';

class NumbersScanPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final Future<void> Function(
    String text, {
    String routing,
    int? speechRate,
    bool showSpeechBubble,
  })
  announceFunction;
  final Future<void> Function(String text)? scanPromptFunction;

  const NumbersScanPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.announceFunction,
    this.scanPromptFunction,
  });

  @override
  State<NumbersScanPage> createState() => _NumbersScanPageState();
}

class _NumbersScanPageState extends State<NumbersScanPage> {
  static const int _numberRowsVisible = 6;
  static const int _rowsVisible = _numberRowsVisible + 2;
  static const int _homeRowIndex = 0;
  static const int _firstNumberRowIndex = 1;
  static const int _showMoreRowIndex = _rowsVisible - 1;

  final FocusNode _focusNode = FocusNode();
  int _lastSwitchActivationMs = 0;

  int _startNumber = 0;
  int _scanDelayMs = 3500;
  bool _waitForSwitchToScan = false;
  bool _waitingForInitialSwitch = false;
  String _scanMode = 'auto';

  Timer? _scanTimer;
  Timer? _pendingPromptTimer;
  Timer? _speechBubbleTimer;
  bool _isAutoTickRunning = false;
  int _promptToken = 0;
  String _lastPromptText = '';
  DateTime _lastPromptAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _scanPhase = 'rows'; // rows | items
  int _currentRowScanCursor = -1;
  int _currentRowIndex = -1;
  int _currentItemIndex = -1;

  bool _isAnnouncingPrompt = false;
  String? _queuedPromptText;
  bool _showSpeechBubble = false;
  String _speechBubbleText = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _pendingPromptTimer?.cancel();
    _speechBubbleTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _showSpeechBubbleOverlay(String text) {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;

    if (settings?.displaySplash != true) {
      return;
    }

    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
    }

    final duration = settings?.displaySplashtime ?? 3000;
    _speechBubbleTimer = Timer(Duration(milliseconds: duration), () {
      _hideSpeechBubbleOverlay();
    });
  }

  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showSpeechBubble = false;
      _speechBubbleText = '';
    });
  }

  Future<void> _announceWithLocalSpeechBubble(
    String text, {
    String routing = 'system',
    int? speechRate,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    _showSpeechBubbleOverlay(cleaned);
    await widget.announceFunction(
      cleaned,
      routing: routing,
      speechRate: speechRate,
      showSpeechBubble: false,
    );
  }

  Future<void> _loadSettings() async {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;

    setState(() {
      _scanDelayMs = settings?.scanDelay ?? 3500;
      _scanMode = (settings?.scanMode == 'step') ? 'step' : 'auto';
      _waitForSwitchToScan = settings?.waitForSwitchToScan == true;
      _waitingForInitialSwitch = _waitForSwitchToScan;
    });

    if (!_waitingForInitialSwitch) {
      _resetToRowsAndRestart(delayMs: 0);
    }
  }

  int _rowStartValue(int rowIndex) {
    final numberRowIndex = rowIndex - _firstNumberRowIndex;
    return _startNumber + (numberRowIndex * 10);
  }

  String _rowPromptText(int rowIndex) {
    if (rowIndex == _homeRowIndex) {
      return 'Home';
    }
    if (rowIndex == _showMoreRowIndex) {
      return 'Show More Options';
    }

    final start = _rowStartValue(rowIndex);
    final fmt = NumberFormat('#,##0');
    return '${fmt.format(start)} to ${fmt.format(start + 9)}';
  }

  List<_NumberItem> _buttonsForRow(int rowIndex) {
    final items = <_NumberItem>[];

    if (rowIndex == _homeRowIndex) {
      items.add(
        _NumberItem(
          key: 'home',
          label: 'Home',
          action: _NumberAction.home,
          rowIndex: rowIndex,
          colIndex: 0,
        ),
      );
      return items;
    }

    if (rowIndex == _showMoreRowIndex) {
      const advanceOptions = [
        ('Next\n50', 50),
        ('Add\n100', 100),
        ('Add\n1,000', 1000),
        ('Add\n10,000', 10000),
        ('Add\n100,000', 100000),
        ('Add\n1,000,000', 1000000),
      ];
      for (var i = 0; i < advanceOptions.length; i++) {
        final (label, amount) = advanceOptions[i];
        items.add(
          _NumberItem(
            key: 'advance_$amount',
            label: label,
            action: _NumberAction.advance,
            payload: '$amount',
            rowIndex: rowIndex,
            colIndex: i,
          ),
        );
      }
      return items;
    }

    final start = _rowStartValue(rowIndex);

    for (int value = start; value <= start + 9; value++) {
      items.add(
        _NumberItem(
          key: 'num_$value',
          label: NumberFormat('#,##0').format(value),
          action: _NumberAction.number,
          payload: '$value',
          rowIndex: rowIndex,
          colIndex: value - start,
        ),
      );
    }

    return items;
  }

  List<int> _rowTargets() {
    return List<int>.generate(_rowsVisible, (index) => index);
  }

  void _clearPendingPrompt() {
    _pendingPromptTimer?.cancel();
    _pendingPromptTimer = null;
    _promptToken += 1;
  }

  Future<void> _announcePrompt(String text) async {
    final cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.isEmpty) return;

    if (_isAnnouncingPrompt) {
      _queuedPromptText = cleaned;
      return;
    }

    final now = DateTime.now();
    if (cleaned == _lastPromptText &&
        now.difference(_lastPromptAt).inMilliseconds < 700) {
      return;
    }

    _isAnnouncingPrompt = true;
    try {
      if (widget.scanPromptFunction != null) {
        await widget.scanPromptFunction!(cleaned);
      } else {
        await widget.announceFunction(
          cleaned,
          routing: 'personal',
          showSpeechBubble: false,
        );
      }
      _lastPromptText = cleaned;
      _lastPromptAt = DateTime.now();
    } catch (_) {
      // Non-critical for scanning flow.
    } finally {
      _isAnnouncingPrompt = false;

      final queued = _queuedPromptText;
      _queuedPromptText = null;
      if (queued != null && queued.trim().isNotEmpty) {
        Future.microtask(() => _announcePrompt(queued));
      }
    }
  }

  Future<void> _schedulePromptForCurrentTarget() async {
    String prompt = '';

    if (_scanPhase == 'rows') {
      final rows = _rowTargets();
      if (_currentRowScanCursor < 0 || _currentRowScanCursor >= rows.length) {
        return;
      }
      prompt = _rowPromptText(rows[_currentRowScanCursor]);
    } else {
      final rowItems = _buttonsForRow(_currentRowIndex);
      if (_currentItemIndex < 0 || _currentItemIndex >= rowItems.length) {
        return;
      }
      prompt = rowItems[_currentItemIndex].label;
    }

    if (prompt.isEmpty) return;

    _clearPendingPrompt();
    final token = _promptToken;
    if (!mounted || token != _promptToken) return;
    _pendingPromptTimer = null;
    await _announcePrompt(prompt);
  }

  Future<void> _advanceScan() async {
    if (!mounted) return;
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_scanPhase == 'rows') {
      final rows = _rowTargets();
      if (rows.isEmpty) return;
      setState(() {
        _currentRowScanCursor = (_currentRowScanCursor + 1) % rows.length;
      });
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    final rowItems = _buttonsForRow(_currentRowIndex);
    if (rowItems.isEmpty) {
      setState(() {
        _scanPhase = 'rows';
        _currentItemIndex = -1;
      });
      _advanceScanSync();
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    setState(() {
      _currentItemIndex = (_currentItemIndex + 1) % rowItems.length;
    });
    unawaited(_schedulePromptForCurrentTarget());
  }

  void _advanceScanSync() {
    if (!mounted) return;
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_scanPhase == 'rows') {
      final rows = _rowTargets();
      if (rows.isEmpty) return;
      setState(() {
        _currentRowScanCursor = (_currentRowScanCursor + 1) % rows.length;
      });
      return;
    }

    final rowItems = _buttonsForRow(_currentRowIndex);
    if (rowItems.isEmpty) {
      setState(() {
        _scanPhase = 'rows';
        _currentItemIndex = -1;
      });
      _advanceScanSync();
      return;
    }

    setState(() {
      _currentItemIndex = (_currentItemIndex + 1) % rowItems.length;
    });
  }

  void _startAutoScanTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(Duration(milliseconds: _scanDelayMs), (_) {
      if (!mounted || _scanMode != 'auto' || _isAutoTickRunning) return;
      _isAutoTickRunning = true;
      unawaited(() async {
        try {
          await _advanceScan();
        } finally {
          _isAutoTickRunning = false;
        }
      }());
    });
  }

  void _startScanning() {
    if (!mounted) return;
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_scanMode == 'step') {
      if ((_scanPhase == 'rows' && _currentRowScanCursor == -1) ||
          (_scanPhase == 'items' && _currentItemIndex == -1)) {
        _advanceScanSync();
        unawaited(_schedulePromptForCurrentTarget());
      }
      return;
    }

    _scanTimer?.cancel();
    _advanceScanSync();
    unawaited(_schedulePromptForCurrentTarget());
    _startAutoScanTimer();
  }

  void _stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isAutoTickRunning = false;
    _clearPendingPrompt();
  }

  void _resetToRowsAndRestart({int delayMs = 0}) {
    _stopScanning();
    setState(() {
      _scanPhase = 'rows';
      _currentRowScanCursor = -1;
      _currentRowIndex = -1;
      _currentItemIndex = -1;
    });

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_waitForSwitchToScan && _waitingForInitialSwitch) return;
      if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
      _startScanning();
    });
  }

  Future<void> _recordChatHistory(String responseText) async {
    try {
      await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/record_chat_history'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'question': '', 'response': responseText}),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _handleNumberSelection(String value) async {
    _stopScanning();
    await _announceWithLocalSpeechBubble(value, routing: 'system');
    await _recordChatHistory(value);
    _resetToRowsAndRestart(delayMs: 180);
  }

  void _handleSpace() {
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_waitForSwitchToScan && _waitingForInitialSwitch) {
      setState(() {
        _waitingForInitialSwitch = false;
      });
      _startScanning();
      return;
    }

    final hasTarget =
        (_scanPhase == 'rows' && _currentRowScanCursor >= 0) ||
        (_scanPhase == 'items' && _currentItemIndex >= 0);

    if (!hasTarget) {
      _startScanning();
      return;
    }

    _clearPendingPrompt();

    if (_scanPhase == 'rows') {
      final selectedRow = _rowTargets()[_currentRowScanCursor];

      if (selectedRow == _homeRowIndex) {
        _stopScanning();
        Navigator.of(context).pop();
        return;
      }

      setState(() {
        _currentRowIndex = selectedRow;
        _scanPhase = 'items';
        _currentItemIndex = -1;
      });
      if (_scanMode == 'auto') {
        _advanceScanSync();
        unawaited(_schedulePromptForCurrentTarget());
        _startAutoScanTimer();
      } else {
        _advanceScanSync();
        unawaited(_schedulePromptForCurrentTarget());
      }
      return;
    }

    final rowItems = _buttonsForRow(_currentRowIndex);
    if (_currentItemIndex < 0 || _currentItemIndex >= rowItems.length) {
      return;
    }

    final selected = rowItems[_currentItemIndex];
    switch (selected.action) {
      case _NumberAction.number:
        _handleNumberSelection(selected.payload ?? selected.label);
      case _NumberAction.advance:
        final amount = int.tryParse(selected.payload ?? '0') ?? 0;
        setState(() {
          _startNumber += amount;
        });
        _resetToRowsAndRestart(delayMs: 140);
      case _NumberAction.showMore:
        _resetToRowsAndRestart(delayMs: 140);
      case _NumberAction.home:
        _stopScanning();
        Navigator.of(context).pop();
    }
  }

  void _handleRawKey(RawKeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent == false) {
      return;
    }

    final isSwitchKey =
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey.keyLabel == ' ';

    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        _scanMode == 'step') {
      _advanceScanSync();
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    if (isSwitchKey && event is RawKeyDownEvent) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSwitchActivationMs < 180) {
        return;
      }
      _lastSwitchActivationMs = now;
      _handleSpace();
    }
  }

  bool _isRowHighlighted(int rowIndex) {
    return _scanPhase == 'rows' &&
        _currentRowScanCursor >= 0 &&
        _rowTargets()[_currentRowScanCursor] == rowIndex;
  }

  bool _isItemHighlighted(int rowIndex, int colIndex) {
    if (_scanPhase != 'items' || rowIndex != _currentRowIndex) return false;
    final rowItems = _buttonsForRow(rowIndex);
    if (_currentItemIndex < 0 || _currentItemIndex >= rowItems.length)
      return false;
    final selected = rowItems[_currentItemIndex];
    return selected.rowIndex == rowIndex && selected.colIndex == colIndex;
  }

  /// Renders button text that scales down to fit without splitting words,
  /// Renders button text scaled to fit both axes using Flutter's FittedBox.
  Widget _buildButtonText(String label) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        textAlign: TextAlign.center,
        textScaleFactor: 1.0,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGridStyleHeader({
    required Color headerBackgroundColor,
    required Color headerTextColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: headerBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Numbers',
                      style: TextStyle(
                        color: headerTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'v1.0.2+18',
                      style: TextStyle(
                        color: headerTextColor.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: true,
    );
    final userSettings = settingsProvider.settings;
    final Color headerTextColor = userSettings != null
        ? Color(userSettings.lightColorValue)
        : Colors.white;
    final Color headerBackgroundColor = userSettings != null
        ? Color(userSettings.darkColorValue)
        : Colors.black;

    return Scaffold(
      body: RawKeyboardListener(
        autofocus: true,
        focusNode: _focusNode,
        onKey: _handleRawKey,
        child: Stack(
          children: [
            Column(
              children: [
                _buildGridStyleHeader(
                  headerBackgroundColor: headerBackgroundColor,
                  headerTextColor: headerTextColor,
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: _rowsVisible,
                    itemBuilder: (context, rowIndex) {
                      final items = _buttonsForRow(rowIndex);
                      final rowHighlighted = _isRowHighlighted(rowIndex);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: rowHighlighted
                              ? Colors.orange.withValues(alpha: 0.16)
                              : Colors.transparent,
                          border: Border.all(
                            color: rowHighlighted
                                ? Colors.orange
                                : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: items.map((item) {
                              final highlighted = _isItemHighlighted(
                                item.rowIndex,
                                item.colIndex,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: item.action == _NumberAction.number
                                      ? 99.0
                                      : item.action == _NumberAction.advance
                                          ? 172.0
                                          : 138.0,
                                  height: 58,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      switch (item.action) {
                                        case _NumberAction.number:
                                          _handleNumberSelection(
                                            item.payload ?? item.label,
                                          );
                                        case _NumberAction.advance:
                                          final amt = int.tryParse(
                                                item.payload ?? '0',
                                              ) ??
                                              0;
                                          setState(() {
                                            _startNumber += amt;
                                          });
                                          _resetToRowsAndRestart(delayMs: 140);
                                        case _NumberAction.showMore:
                                          _resetToRowsAndRestart(delayMs: 140);
                                        case _NumberAction.home:
                                          _stopScanning();
                                          Navigator.of(context).pop();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: highlighted
                                          ? Colors.orange
                                          : Colors.blue.shade50,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: highlighted
                                              ? Colors.deepOrange
                                              : Colors.blue.shade200,
                                        ),
                                      ),
                                    ),
                                    child: _buildButtonText(item.label),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_showSpeechBubble)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(60),
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.grey[400]!,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            offset: const Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/whitespeechbubble.jpg',
                            width: 90,
                            height: 90,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(45),
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 45,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 30),
                          Flexible(
                            child: Text(
                              _speechBubbleText,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _NumberAction { home, number, showMore, advance }

class _NumberItem {
  final String key;
  final String label;
  final _NumberAction action;
  final String? payload;
  final int rowIndex;
  final int colIndex;

  const _NumberItem({
    required this.key,
    required this.label,
    required this.action,
    required this.rowIndex,
    required this.colIndex,
    this.payload,
  });
}
