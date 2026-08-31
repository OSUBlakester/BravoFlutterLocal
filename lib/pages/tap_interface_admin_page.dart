import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../services/user_settings_provider.dart';

enum _AdminSection { boardBuilder, boardsMenu, migration }

class TapInterfaceAdminPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;

  const TapInterfaceAdminPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
  });

  @override
  State<TapInterfaceAdminPage> createState() => _TapInterfaceAdminPageState();
}

class _TapInterfaceAdminPageState extends State<TapInterfaceAdminPage> {
  // Grid dimensions derived from user settings at runtime — see _gridRows/_gridCols getters
  static const int _boardRows = 7; // fallback/max capacity
  static const int _boardCols = 12;
  static const List<MapEntry<String, String>> _backgroundColorOptions = [
    MapEntry('#FFFFFF', 'White'),
    MapEntry('#F3F4F6', 'Light Gray'),
    MapEntry('#FEF3C7', 'Soft Yellow'),
    MapEntry('#FDE68A', 'Warm Yellow'),
    MapEntry('#E0F2FE', 'Light Blue'),
    MapEntry('#DBEAFE', 'Soft Blue'),
    MapEntry('#DCFCE7', 'Light Green'),
    MapEntry('#FCE7F3', 'Light Pink'),
  ];

  _AdminSection _activeSection = _AdminSection.boardBuilder;

  String _apiBaseUrl = '';
  bool _loading = false;
  String? _error;
  String? _boardDataWarning;

  // ---------- Shared board data ----------
  List<Map<String, dynamic>> _boards = [];
  Map<String, dynamic> _boardSettings = <String, dynamic>{};

  // ---------- Board Builder state ----------
  String? _selectedBoardId;
  Map<String, dynamic>? _currentBoard;
  bool _showMigrationBoardsOnly = false;
  int? _moveSourceIndex;
  int _adminGridPage = 0;

  final TextEditingController _boardLabelController = TextEditingController();
  final TextEditingController _llmPromptController = TextEditingController();
  final TextEditingController _promptTopicController = TextEditingController();
  final TextEditingController _promptExamplesController = TextEditingController();
  final TextEditingController _promptExclusionsController = TextEditingController();
  String _boardType = 'ai';
  bool _setAsHomeBoard = false;

  // ---------- Boards Menu state ----------
  List<Map<String, dynamic>> _boardsMenuTree = [];
  List<Map<String, dynamic>> _boardsMenuOriginalTree = [];
  List<int>? _selectedMenuPath;

  final TextEditingController _menuLabelController = TextEditingController();
  final TextEditingController _menuSpeechController = TextEditingController();
  final TextEditingController _menuImageController = TextEditingController();
  final TextEditingController _menuAudioController = TextEditingController();
  final TextEditingController _menuBackgroundController = TextEditingController(text: '#FFFFFF');
  final TextEditingController _menuTextColorController = TextEditingController(text: '#000000');
  String? _menuBoardTarget;
  bool _menuHidden = false;

  // ---------- Migration state ----------
  String? _migrationSessionId;
  Map<String, dynamic>? _touchChatData;
  String? _selectedSourceBoardId;
  Set<int> _selectedButtonIndices = <int>{};
  bool _importFullCascade = false;
  String _destinationType = 'new';
  String _mergeMode = 'update';
  final TextEditingController _newDestinationNameController = TextEditingController();
  String? _existingDestinationBoardId;
  bool _migrationBusy = false;
  String _migrationStatus = 'Ready to upload a TouchChat .ce file.';
  List<Map<String, dynamic>> _pendingMissingTargets = [];
  final Map<String, String> _pendingTargetMode = <String, String>{};
  final Map<String, String> _pendingTargetCreateName = <String, String>{};
  final Map<String, String> _pendingTargetExistingBoard = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      _apiBaseUrl = userSettings.apiBaseUrl;
      _loadBoards();
      _loadBoardsMenu();
    });
  }

  @override
  void dispose() {
    _boardLabelController.dispose();
    _llmPromptController.dispose();
    _promptTopicController.dispose();
    _promptExamplesController.dispose();
    _promptExclusionsController.dispose();
    _menuLabelController.dispose();
    _menuSpeechController.dispose();
    _menuImageController.dispose();
    _menuAudioController.dispose();
    _menuBackgroundController.dispose();
    _menuTextColorController.dispose();

    _newDestinationNameController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.idToken}',
        'X-User-ID': widget.aacUserId,
      };

  // Grid dimensions derived from user profile settings — matching tap_interface_page.dart conventions:
  //   tapWordsRows = TOTAL word rows (static + dynamic)
  //   tapDynamicRows = how many of those are AI-generated (bottom rows)
  //   static rows = tapWordsRows - tapDynamicRows
  UserSettings? get _userSettings =>
      Provider.of<UserSettingsProvider>(context, listen: false).settings;

  int get _gridRows => _userSettings?.tapWordsRows ?? _boardRows;
  int get _gridCols => _userSettings?.gridColumns ?? _boardCols;

  // Profile-level dynamic rows — this is what the tap interface actually uses for rendering.
  // The board's own dynamic_rows field is a server-side override; the visualization always
  // reflects the profile setting so the admin matches what users see.
  int get _profileDynamicRows => _userSettings?.tapDynamicRows ?? 0;

  String _normalizeHex(String value, {required String fallback}) {
    final trimmed = value.trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return fallback;
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed ?? fallback;
  }

  String _asString(dynamic value, {String fallback = ''}) {
    final text = (value ?? '').toString();
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> _extractBoardsPayload(Map<String, dynamic> payload) {
    final topLevelBoards = payload['boards'];
    if (topLevelBoards is List<dynamic>) {
      return topLevelBoards.whereType<Map<String, dynamic>>().toList();
    }

    final boardsConfig = payload['boards_config'];
    if (boardsConfig is Map<String, dynamic>) {
      final nestedBoards = boardsConfig['boards'];
      if (nestedBoards is List<dynamic>) {
        return nestedBoards.whereType<Map<String, dynamic>>().toList();
      }
    }

    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _extractBoardSettingsPayload(Map<String, dynamic> payload) {
    final topLevelSettings = payload['board_settings'];
    if (topLevelSettings is Map<String, dynamic>) {
      return topLevelSettings;
    }

    final boardsConfig = payload['boards_config'];
    if (boardsConfig is Map<String, dynamic>) {
      final nestedSettings = boardsConfig['board_settings'];
      if (nestedSettings is Map<String, dynamic>) {
        return nestedSettings;
      }
    }

    final menuConfig = payload['menu_config'];
    if (menuConfig is Map<String, dynamic>) {
      final fallbackSettings = menuConfig['board_settings'];
      if (fallbackSettings is Map<String, dynamic>) {
        return fallbackSettings;
      }
    }

    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _extractBoardsMenuPayload(Map<String, dynamic> payload) {
    final topLevelMenu = payload['boards_menu'];
    if (topLevelMenu is List<dynamic>) {
      return topLevelMenu.whereType<Map<String, dynamic>>().toList();
    }

    final menuConfig = payload['menu_config'];
    if (menuConfig is Map<String, dynamic>) {
      final nestedMenu = menuConfig['boards_menu'];
      if (nestedMenu is List<dynamic>) {
        return nestedMenu.whereType<Map<String, dynamic>>().toList();
      }
    }

    return <Map<String, dynamic>>[];
  }

  int _boardCompletenessScore(Map<String, dynamic> board) {
    final buttons = (board['buttons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .length;
    var score = 0;
    if (_asString(board['id']).trim().isNotEmpty) score += 100;
    if (_asString(board['label']).trim().isNotEmpty) score += 20;
    if (_asString(board['board_type']).trim().isNotEmpty) score += 10;
    if (_asString(board['llm_prompt']).trim().isNotEmpty) score += 5;
    score += buttons;
    return score;
  }

  ({List<Map<String, dynamic>> boards, String? warning}) _normalizeLoadedBoards(
    List<Map<String, dynamic>> loadedBoards,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    var duplicateIdCount = 0;
    var missingIdCount = 0;

    for (final board in loadedBoards) {
      final cloned = _deepCloneMap(board);
      final id = _asString(cloned['id']).trim();
      if (id.isEmpty) {
        missingIdCount += 1;
        continue;
      }

      final existing = byId[id];
      if (existing == null) {
        byId[id] = cloned;
        continue;
      }

      duplicateIdCount += 1;
      final existingScore = _boardCompletenessScore(existing);
      final candidateScore = _boardCompletenessScore(cloned);
      if (candidateScore > existingScore) {
        byId[id] = cloned;
      }
    }

    final boards = byId.values.toList()
      ..sort((a, b) {
        final labelA = _asString(a['label'], fallback: _asString(a['id'])).toLowerCase();
        final labelB = _asString(b['label'], fallback: _asString(b['id'])).toLowerCase();
        final labelCompare = labelA.compareTo(labelB);
        if (labelCompare != 0) return labelCompare;
        return _asString(a['id']).compareTo(_asString(b['id']));
      });

    final labelCounts = <String, int>{};
    for (final board in boards) {
      final normalizedLabel = _asString(board['label'], fallback: _asString(board['id']))
          .trim()
          .toLowerCase();
      if (normalizedLabel.isEmpty) continue;
      labelCounts[normalizedLabel] = (labelCounts[normalizedLabel] ?? 0) + 1;
    }
    final duplicateLabelGroups = labelCounts.values.where((count) => count > 1).length;

    final warningParts = <String>[];
    if (duplicateIdCount > 0) {
      warningParts.add('collapsed $duplicateIdCount duplicate board id entr${duplicateIdCount == 1 ? 'y' : 'ies'}');
    }
    if (missingIdCount > 0) {
      warningParts.add('ignored $missingIdCount board entr${missingIdCount == 1 ? 'y' : 'ies'} without id');
    }
    if (duplicateLabelGroups > 0) {
      warningParts.add('$duplicateLabelGroups duplicate board label group${duplicateLabelGroups == 1 ? '' : 's'} detected');
    }

    final warning = warningParts.isEmpty ? null : 'Board data warning: ${warningParts.join('; ')}.';
    return (boards: boards, warning: warning);
  }

  List<DropdownMenuItem<String>> _buildBackgroundColorItems(String selectedColor) {
    final selected = _normalizeHex(selectedColor, fallback: '#FFFFFF');
    final items = _backgroundColorOptions
        .map(
          (opt) => DropdownMenuItem<String>(
            value: opt.key,
            child: Text('${opt.value} (${opt.key})'),
          ),
        )
        .toList();

    if (!_backgroundColorOptions.any((opt) => opt.key == selected)) {
      items.insert(
        0,
        DropdownMenuItem<String>(
          value: selected,
          child: Text('Custom ($selected)'),
        ),
      );
    }

    return items;
  }

  Future<void> _loadBoards() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/tap-interface/boards'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load boards (${response.statusCode})');
      }

      final payload = json.decode(response.body) as Map<String, dynamic>;
      final loadedBoards = _extractBoardsPayload(payload);
      final normalized = _normalizeLoadedBoards(loadedBoards);

      setState(() {
        _boards = normalized.boards;
        _boardDataWarning = normalized.warning;
        _boardSettings = _extractBoardSettingsPayload(payload);

        if (_selectedBoardId == null && _boards.isNotEmpty) {
          final firstEditable = _boards.firstWhere(
            (b) => !_isBoardReadOnly(b),
            orElse: () => _boards.first,
          );
          _selectedBoardId = _asString(firstEditable['id']);
          _bindBoardFromSelection();
        } else if (_selectedBoardId != null) {
          final stillExists = _boards.any((b) => _asString(b['id']) == _selectedBoardId);
          if (stillExists) {
            _bindBoardFromSelection();
          } else {
            _selectedBoardId = null;
            _currentBoard = null;
            _adminGridPage = 0;
          }
        }

        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadBoardsMenu() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/tap-interface/boards-menu'),
        headers: _headers,
      );

      if (response.statusCode != 200) return;

      final payload = json.decode(response.body) as Map<String, dynamic>;
      final loadedMenu = _extractBoardsMenuPayload(payload);
      final loadedBoards = _extractBoardsPayload(payload);
      final normalizedBoards = _normalizeLoadedBoards(loadedBoards);

      setState(() {
        _boardsMenuTree = loadedMenu
            .map((item) => _deepCloneMap(item))
            .toList();
        _boardsMenuOriginalTree = _boardsMenuTree.map(_deepCloneMap).toList();

        if (normalizedBoards.boards.isNotEmpty) {
          _boards = normalizedBoards.boards;
          _boardDataWarning = normalizedBoards.warning;
        }

        final settings = _extractBoardSettingsPayload(payload);
        if (settings.isNotEmpty) {
          _boardSettings = settings;
        }
      });
    } catch (_) {}
  }

  bool _isBoardReadOnly(Map<String, dynamic>? board) {
    return false;
  }

  List<Map<String, dynamic>> get _editableBoards {
    // Filter out non-configurable special-function boards (spell, games, numbers)
    var filtered = _boards.where((b) {
      final specialFn = _asString(b['special_function']).toLowerCase();
      final id = _asString(b['id']).toLowerCase();
      final lbl = _asString(b['label']).toLowerCase();
      if (specialFn == 'spell' || specialFn == 'games' || specialFn == 'numbers') return false;
      if (id.contains('spell') || id.contains('games') || id.contains('numbers')) return false;
      if (lbl == 'spell' || lbl == 'games' || lbl == 'numbers') return false;
      return true;
    }).toList();

    if (_showMigrationBoardsOnly) {
      filtered = filtered.where((b) {
        final createdDuringMigration = _isTruthy(b['created_during_migration']);
        final buttons = (b['buttons'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
        return createdDuringMigration && buttons.isEmpty;
      }).toList();
    }

    // Sort alphabetically by label
    filtered.sort((a, b) =>
        _asString(a['label']).toLowerCase().compareTo(_asString(b['label']).toLowerCase()));
    return filtered;
  }

  void _bindBoardFromSelection() {
    if (_selectedBoardId == null) return;
    final board = _boards.firstWhere(
      (b) => _asString(b['id']) == _selectedBoardId,
      orElse: () => <String, dynamic>{},
    );
    if (board.isEmpty) return;

    _currentBoard = _deepCloneMap(board);
    _adminGridPage = 0;
    _boardLabelController.text = _asString(_currentBoard!['label']);
    _boardType = _asString(_currentBoard!['board_type'], fallback: 'ai').toLowerCase();
    if (_boardType != 'ai' && _boardType != 'static' && _boardType != 'system') {
      _boardType = 'ai';
    }

    _llmPromptController.text = _asString(_currentBoard!['llm_prompt']);
    _promptTopicController.text = _asString(_currentBoard!['prompt_topic']);
    _promptExamplesController.text = _asString(_currentBoard!['prompt_examples']);
    _promptExclusionsController.text = _asString(_currentBoard!['prompt_exclusions']);
    _setAsHomeBoard = _selectedBoardId == _asString(_boardSettings['home_board_id']);
  }

  Map<String, dynamic> _deepCloneMap(Map<String, dynamic> input) {
    return json.decode(json.encode(input)) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _currentBoardButtons() {
    if (_currentBoard == null) return <Map<String, dynamic>>[];
    return (_currentBoard!['buttons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Map<String, dynamic>? _findButtonAt(int row, int col) {
    for (final btn in _currentBoardButtons()) {
      if (_asInt(btn['row'], fallback: -1) == row && _asInt(btn['col'], fallback: -1) == col) {
        return btn;
      }
    }
    return null;
  }

  /// Buttons sorted by pool order (pool_index if set, else row * _boardCols + col).
  /// Mirrors the sort the tap interface uses for its "More Options" pagination.
  List<Map<String, dynamic>> _sortedPoolButtons() {
    final buttons = _currentBoardButtons()
        .where((b) => _asString(b['label']).isNotEmpty)
        .toList();
    final hasPools = buttons.any((b) => b['pool_index'] != null);
    if (hasPools) {
      buttons.sort((a, b) {
        final ai = a['pool_index'] != null
            ? _asInt(a['pool_index'], fallback: 0)
            : _asInt(a['row'], fallback: 0) * _boardCols + _asInt(a['col'], fallback: 0);
        final bi = b['pool_index'] != null
            ? _asInt(b['pool_index'], fallback: 0)
            : _asInt(b['row'], fallback: 0) * _boardCols + _asInt(b['col'], fallback: 0);
        return ai.compareTo(bi);
      });
    } else {
      buttons.sort((a, b) {
        final ai = _asInt(a['row'], fallback: 0) * _boardCols + _asInt(a['col'], fallback: 0);
        final bi = _asInt(b['row'], fallback: 0) * _boardCols + _asInt(b['col'], fallback: 0);
        return ai.compareTo(bi);
      });
    }
    return buttons;
  }

  void _setButtonAt(int row, int col, Map<String, dynamic> buttonData) {
    final buttons = _currentBoardButtons();
    buttons.removeWhere((btn) =>
        _asInt(btn['row'], fallback: -1) == row && _asInt(btn['col'], fallback: -1) == col);
    buttons.add(buttonData);
    _currentBoard!['buttons'] = buttons;
  }

  void _clearButtonAt(int row, int col) {
    final buttons = _currentBoardButtons();
    buttons.removeWhere((btn) =>
        _asInt(btn['row'], fallback: -1) == row && _asInt(btn['col'], fallback: -1) == col);
    _currentBoard!['buttons'] = buttons;
  }

  Future<String?> _uploadAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      withData: true,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
    );

    if (result == null || result.files.isEmpty || result.files.first.bytes == null) {
      return null;
    }

    final picked = result.files.first;
    final bytes = picked.bytes!;
    final name = picked.name;

    if (bytes.length > 10 * 1024 * 1024) {
      _showSnackBar('Audio file must be under 10MB.', isError: true);
      return null;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBaseUrl/api/admin/upload-button-audio'),
    );

    request.headers['Authorization'] = 'Bearer ${widget.idToken}';
    request.headers['X-User-ID'] = widget.aacUserId;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));

    final streamed = await request.send();
    final responseText = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (${streamed.statusCode})');
    }

    final payload = json.decode(responseText) as Map<String, dynamic>;
    if (!_isTruthy(payload['success']) || _asString(payload['audio_url']).isEmpty) {
      throw Exception('Upload failed: no URL returned');
    }

    return _asString(payload['audio_url']);
  }

  Future<void> _saveCurrentBoard() async {
    if (_currentBoard == null) return;
    if (_isBoardReadOnly(_currentBoard)) {
      _showSnackBar('This board is read-only.', isError: true);
      return;
    }

    final boardLabel = _boardLabelController.text.trim();
    if (boardLabel.isEmpty) {
      _showSnackBar('Board label is required.', isError: true);
      return;
    }

    final boardId = _asString(_currentBoard!['id']);
    final normalizedLabel = boardLabel.toLowerCase();
    final labelConflict = _boards.any((b) {
      final otherId = _asString(b['id']);
      if (otherId == boardId) return false;
      return _asString(b['label']).trim().toLowerCase() == normalizedLabel;
    });
    if (labelConflict) {
      _showSnackBar('Board label must be unique. Rename this board before saving.', isError: true);
      return;
    }

    setState(() {
      _loading = true;
    });

    final payload = <String, dynamic>{
      'label': boardLabel,
      'board_type': _boardType,
      'owner_scope': _asString(_currentBoard!['owner_scope'], fallback: 'user'),
      'hidden': _isTruthy(_currentBoard!['hidden']),
      'llm_prompt': _boardType == 'ai' ? _nullIfEmpty(_llmPromptController.text) : null,
      'prompt_category': null,
      'prompt_topic': _boardType == 'ai' ? _nullIfEmpty(_promptTopicController.text) : null,
      'prompt_examples': _boardType == 'ai' ? _nullIfEmpty(_promptExamplesController.text) : null,
      'prompt_exclusions': _boardType == 'ai' ? _nullIfEmpty(_promptExclusionsController.text) : null,
      'dynamic_rows': _currentBoard?['dynamic_rows'],
      'static_options': _currentBoard!['static_options'],
      'special_function': _currentBoard!['special_function'],
      'default_columns': _asInt(_currentBoard!['default_columns'], fallback: _boardCols),
      'max_rows': _asInt(_currentBoard!['max_rows'], fallback: _boardRows),
      'is_customized': true,
      'buttons': _boardType == 'ai' ? <Map<String, dynamic>>[] : _currentBoardButtons(),
      'set_as_home': _setAsHomeBoard,
      'created_during_migration': _isTruthy(_currentBoard!['created_during_migration']) && _currentBoardButtons().isEmpty,
    };

    try {
      late final http.Response response;
      if (boardId.isEmpty) {
        response = await http.post(
          Uri.parse('$_apiBaseUrl/api/tap-interface/boards'),
          headers: _headers,
          body: json.encode(payload),
        );
      } else {
        response = await http.put(
          Uri.parse('$_apiBaseUrl/api/tap-interface/boards/${Uri.encodeComponent(boardId)}'),
          headers: _headers,
          body: json.encode(payload),
        );
      }

      if (response.statusCode != 200) {
        throw Exception('Save failed (${response.statusCode})');
      }

      final responsePayload = json.decode(response.body) as Map<String, dynamic>;
      final savedBoard = responsePayload['board'] as Map<String, dynamic>?;
      final savedId = _asString(savedBoard?['id']);

      await _loadBoards();
      if (savedId.isNotEmpty) {
        setState(() {
          _selectedBoardId = savedId;
          _bindBoardFromSelection();
        });
      }

      _showSnackBar('Board saved successfully.', isError: false);
    } catch (e) {
      _showSnackBar('Failed to save board: $e', isError: true);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteCurrentBoard() async {
    if (_currentBoard == null) return;
    if (_isBoardReadOnly(_currentBoard)) {
      _showSnackBar('This board is read-only.', isError: true);
      return;
    }

    final boardId = _asString(_currentBoard!['id']);
    if (boardId.isEmpty) {
      setState(() {
        _currentBoard = null;
        _adminGridPage = 0;
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Board'),
        content: Text('Delete board "${_asString(_currentBoard!['label'])}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _loading = true;
    });

    try {
      final response = await http.delete(
        Uri.parse('$_apiBaseUrl/api/tap-interface/boards/${Uri.encodeComponent(boardId)}'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Delete failed (${response.statusCode})');
      }

      setState(() {
        _currentBoard = null;
        _selectedBoardId = null;
        _adminGridPage = 0;
      });

      await _loadBoards();
      _showSnackBar('Board deleted.', isError: false);
    } catch (e) {
      _showSnackBar('Failed to delete board: $e', isError: true);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _createNewBoardDraft() async {
    setState(() {
      _adminGridPage = 0;
      _currentBoard = {
        'id': '',
        'label': 'New Board',
        'board_type': 'static',
        'source': 'custom',
        'owner_scope': 'user',
        'hidden': false,
        'llm_prompt': null,
        'prompt_topic': null,
        'prompt_examples': null,
        'prompt_exclusions': null,
        'dynamic_rows': null,
        'static_options': null,
        'special_function': null,
        'default_columns': _boardCols,
        'max_rows': _boardRows,
        'buttons': <Map<String, dynamic>>[],
      };
      _selectedBoardId = null;
      _bindBoardFromSelectionDraft();
    });
  }

  void _bindBoardFromSelectionDraft() {
    if (_currentBoard == null) return;
    _boardLabelController.text = _asString(_currentBoard!['label']);
    _boardType = _asString(_currentBoard!['board_type'], fallback: 'static');
    _llmPromptController.text = _asString(_currentBoard!['llm_prompt']);
    _promptTopicController.text = _asString(_currentBoard!['prompt_topic']);
    _promptExamplesController.text = _asString(_currentBoard!['prompt_examples']);
    _promptExclusionsController.text = _asString(_currentBoard!['prompt_exclusions']);
    _setAsHomeBoard = false;
  }

  Future<void> _openButtonEditor(int row, int col) async {
    if (_currentBoard == null) return;
    if (_isBoardReadOnly(_currentBoard) || _boardType == 'ai') return;

    final existing = _findButtonAt(row, col);
    final labelController = TextEditingController(text: _asString(existing?['label']));
    final speechController = TextEditingController(text: _asString(existing?['speech_text']));
    final pastTenseController = TextEditingController(text: _asString(existing?['past_tense']));
    final pluralController = TextEditingController(text: _asString(existing?['plural']));
    final imageController = TextEditingController(text: _asString(existing?['image_url']));
    final customAudioController = TextEditingController(text: _asString(existing?['custom_audio_file']));
    final buttonLlmPromptController = TextEditingController(text: _asString(existing?['llm_prompt']));
    final poolIndexController = TextEditingController(
      text: existing?['pool_index'] != null ? _asString(existing!['pool_index']) : '',
    );
    String selectedBackgroundColor = _normalizeHex(_asString(existing?['background_color']), fallback: '#FFFFFF');
    String buttonType = _asString(existing?['button_type'], fallback: 'static');
    if (buttonType != 'static' && buttonType != 'dynamic') buttonType = 'static';

    String afterSelection = _asString(existing?['after_selection'], fallback: 'do_nothing');
    if (afterSelection.isEmpty) afterSelection = 'do_nothing';
    String? targetBoardId = _nullIfEmpty(_asString(existing?['target_board_id']));
    bool temporaryNavigation = _isTruthy(existing?['temporary_navigation']);
    bool hidden = _isTruthy(existing?['hidden']);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Button [$row,$col]'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: buttonType,
                        items: const [
                          DropdownMenuItem(value: 'static', child: Text('Static (fixed content)')),
                          DropdownMenuItem(value: 'dynamic', child: Text('Dynamic (AI-generated)')),
                        ],
                        onChanged: (v) {
                          setDialogState(() {
                            buttonType = v ?? 'static';
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Button Type'),
                      ),
                      const SizedBox(height: 8),
                      if (buttonType == 'dynamic') ...[
                        TextField(
                          controller: buttonLlmPromptController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'AI Prompt',
                            hintText: 'Describe what AI should generate for this button',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (buttonType == 'static') ...[
                        TextField(
                          controller: labelController,
                          decoration: const InputDecoration(labelText: 'Button Label'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: speechController,
                          decoration: const InputDecoration(
                            labelText: 'Announcement (spoken aloud on selection)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: pastTenseController,
                                decoration: const InputDecoration(
                                  labelText: 'Past Tense (optional)',
                                  hintText: 'e.g. wanted',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: pluralController,
                                decoration: const InputDecoration(
                                  labelText: 'Plural (optional)',
                                  hintText: 'e.g. friends',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: imageController,
                        decoration: const InputDecoration(labelText: 'Image URL'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: customAudioController,
                              decoration: const InputDecoration(labelText: 'Custom Audio URL'),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                final uploaded = await _uploadAudioFile();
                                if (uploaded != null && mounted) {
                                  setDialogState(() {
                                    customAudioController.text = uploaded;
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  _showSnackBar('Audio upload failed: $e', isError: true);
                                }
                              }
                            },
                            child: const Text('Upload'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: afterSelection,
                        items: const [
                          DropdownMenuItem(value: 'do_nothing', child: Text('Do nothing')),
                          DropdownMenuItem(value: 'navigate', child: Text('Navigate to board')),
                          DropdownMenuItem(value: 'navigate_home', child: Text('Navigate to home board')),
                          DropdownMenuItem(value: 'use_ai', child: Text('Use AI')),
                        ],
                        onChanged: (v) {
                          setDialogState(() {
                            afterSelection = v ?? 'do_nothing';
                            if (afterSelection != 'navigate') {
                              targetBoardId = null;
                              temporaryNavigation = false;
                            }
                          });
                        },
                        decoration: const InputDecoration(labelText: 'After Selection'),
                      ),
                      const SizedBox(height: 8),
                      if (afterSelection == 'navigate')
                        DropdownButtonFormField<String>(
                          value: targetBoardId,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('No target board'),
                            ),
                            ..._boards.map((b) {
                              final id = _asString(b['id']);
                              final label = _asString(b['label'], fallback: id);
                              return DropdownMenuItem(value: id, child: Text('$label [$id]'));
                            }),
                          ],
                          onChanged: (v) {
                            setDialogState(() {
                              targetBoardId = v;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Target Board'),
                        ),
                      if (afterSelection == 'navigate')
                        CheckboxListTile(
                          value: temporaryNavigation,
                          onChanged: (v) {
                            setDialogState(() {
                              temporaryNavigation = v ?? false;
                            });
                          },
                          title: const Text('Temporary navigation (return after one selection)'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedBackgroundColor,
                        items: _buildBackgroundColorItems(selectedBackgroundColor),
                        onChanged: (v) {
                          setDialogState(() {
                            selectedBackgroundColor = _normalizeHex(v ?? '#FFFFFF', fallback: '#FFFFFF');
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Background Color'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: poolIndexController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pool Order (optional)',
                          hintText: 'Controls pagination order in static pool',
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: hidden,
                        onChanged: (v) {
                          setDialogState(() {
                            hidden = v ?? false;
                          });
                        },
                        title: const Text('Hidden'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, <String, dynamic>{'clear': true});
                  },
                  child: const Text('Clear Button'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final isDynamic = buttonType == 'dynamic';
                    final label = labelController.text.trim();
                    if (!isDynamic && label.isEmpty) {
                      Navigator.pop(context, <String, dynamic>{'clear': true});
                      return;
                    }
                    if (isDynamic && buttonLlmPromptController.text.trim().isEmpty) {
                      return; // require prompt for dynamic buttons
                    }
                    Navigator.pop(context, <String, dynamic>{
                      'id': _asString(existing?['id'], fallback: isDynamic
                          ? 'btn_pool_${DateTime.now().millisecondsSinceEpoch}_$row$col'
                          : 'btn_${row}_${col}_${DateTime.now().millisecondsSinceEpoch}'),
                      'button_type': buttonType,
                      'llm_prompt': isDynamic ? _nullIfEmpty(buttonLlmPromptController.text) : null,
                      'label': isDynamic ? '' : label,
                      'row': row,
                      'col': col,
                      'speech_text': isDynamic ? null : _nullIfEmpty(speechController.text),
                      'past_tense': isDynamic ? null : _nullIfEmpty(pastTenseController.text),
                      'plural': isDynamic ? null : _nullIfEmpty(pluralController.text),
                      'image_url': _nullIfEmpty(imageController.text),
                      'custom_audio_file': _nullIfEmpty(customAudioController.text),
                      'action_type': afterSelection == 'navigate' || afterSelection == 'navigate_home'
                          ? 'navigate'
                          : 'announce',
                      'after_selection': afterSelection,
                      'target_board_id': afterSelection == 'navigate' ? targetBoardId : null,
                      'temporary_navigation': afterSelection == 'navigate' ? temporaryNavigation : false,
                      'background_color': selectedBackgroundColor,
                      'text_color': _normalizeHex(_asString(existing?['text_color']), fallback: '#000000'),
                      'hidden': hidden,
                      'pool_index': int.tryParse(poolIndexController.text.trim()),
                      'modifier_trigger_id': existing?['modifier_trigger_id'],
                      'modifier_variants': existing?['modifier_variants'] ?? <String, dynamic>{},
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    labelController.dispose();
    speechController.dispose();
    pastTenseController.dispose();
    pluralController.dispose();
    imageController.dispose();
    customAudioController.dispose();
    buttonLlmPromptController.dispose();
    poolIndexController.dispose();

    if (result == null) return;

    setState(() {
      if (_isTruthy(result['clear'])) {
        _clearButtonAt(row, col);
      } else {
        _setButtonAt(row, col, result);
      }
    });
  }

  void _swapButtonsByIndex(int sourceIndex, int targetIndex) {
    final sourceRow = sourceIndex ~/ _boardCols;
    final sourceCol = sourceIndex % _boardCols;
    final targetRow = targetIndex ~/ _boardCols;
    final targetCol = targetIndex % _boardCols;

    final sourceButton = _findButtonAt(sourceRow, sourceCol);
    final targetButton = _findButtonAt(targetRow, targetCol);

    if (sourceButton == null && targetButton == null) return;

    setState(() {
      _clearButtonAt(sourceRow, sourceCol);
      _clearButtonAt(targetRow, targetCol);

      if (sourceButton != null) {
        final moved = _deepCloneMap(sourceButton);
        moved['row'] = targetRow;
        moved['col'] = targetCol;
        _setButtonAt(targetRow, targetCol, moved);
      }
      if (targetButton != null) {
        final moved = _deepCloneMap(targetButton);
        moved['row'] = sourceRow;
        moved['col'] = sourceCol;
        _setButtonAt(sourceRow, sourceCol, moved);
      }
    });
  }

  // ---------- Boards menu helpers ----------
  Map<String, dynamic>? _getMenuNodeAtPath(List<int> path) {
    List<Map<String, dynamic>> currentList = _boardsMenuTree;
    Map<String, dynamic>? node;

    for (var i = 0; i < path.length; i++) {
      final idx = path[i];
      if (idx < 0 || idx >= currentList.length) return null;
      node = currentList[idx];
      if (i < path.length - 1) {
        currentList = (node['children'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    }
    return node;
  }

  List<Map<String, dynamic>>? _getMenuSiblingList(List<int> path) {
    if (path.isEmpty) return null;
    if (path.length == 1) return _boardsMenuTree;

    final parentPath = path.sublist(0, path.length - 1);
    final parent = _getMenuNodeAtPath(parentPath);
    if (parent == null) return null;

    parent['children'] ??= <Map<String, dynamic>>[];
    return parent['children'] as List<Map<String, dynamic>>;
  }

  void _selectMenuNode(List<int> path) {
    final node = _getMenuNodeAtPath(path);
    if (node == null) return;

    setState(() {
      _selectedMenuPath = List<int>.from(path);
      _menuLabelController.text = _asString(node['label']);
      _menuBoardTarget = _nullIfEmpty(_asString(node['board_id']));
      _menuSpeechController.text = _asString(node['speech_text']);
      _menuImageController.text = _asString(node['image_url']);
      _menuAudioController.text = _asString(node['custom_audio_file']);
      _menuBackgroundController.text = _normalizeHex(_asString(node['background_color']), fallback: '#FFFFFF');
      _menuTextColorController.text = _normalizeHex(_asString(node['text_color']), fallback: '#000000');
      _menuHidden = _isTruthy(node['hidden']);
    });
  }

  void _applyMenuFormToSelectedNode() {
    if (_selectedMenuPath == null) return;
    final node = _getMenuNodeAtPath(_selectedMenuPath!);
    if (node == null) return;

    node['label'] = _menuLabelController.text.trim().isEmpty ? 'Untitled Menu Item' : _menuLabelController.text.trim();
    node['board_id'] = _menuBoardTarget;
    node['speech_text'] = _nullIfEmpty(_menuSpeechController.text);
    node['image_url'] = _nullIfEmpty(_menuImageController.text);
    node['custom_audio_file'] = _nullIfEmpty(_menuAudioController.text);
    node['background_color'] = _normalizeHex(_menuBackgroundController.text, fallback: '#FFFFFF');
    node['text_color'] = _normalizeHex(_asString(node['text_color']), fallback: '#000000');
    node['hidden'] = _menuHidden;
  }

  void _addRootMenuNode() {
    final newNode = <String, dynamic>{
      'id': 'menu_custom_${DateTime.now().millisecondsSinceEpoch}',
      'label': 'New Menu Item',
      'board_id': null,
      'source': 'custom',
      'source_button_id': null,
      'sort_order': _boardsMenuTree.length,
      'hidden': false,
      'image_url': null,
      'speech_text': null,
      'custom_audio_file': null,
      'background_color': '#FFFFFF',
      'text_color': '#000000',
      'children': <Map<String, dynamic>>[],
    };

    setState(() {
      _boardsMenuTree.add(newNode);
      _selectMenuNode([_boardsMenuTree.length - 1]);
    });
  }

  void _addChildMenuNode() {
    if (_selectedMenuPath == null) return;
    final parent = _getMenuNodeAtPath(_selectedMenuPath!);
    if (parent == null) return;

    final children = (parent['children'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final child = <String, dynamic>{
      'id': 'menu_custom_${DateTime.now().millisecondsSinceEpoch}',
      'label': 'New Child Item',
      'board_id': null,
      'source': 'custom',
      'source_button_id': null,
      'sort_order': children.length,
      'hidden': false,
      'image_url': null,
      'speech_text': null,
      'custom_audio_file': null,
      'background_color': '#FFFFFF',
      'text_color': '#000000',
      'children': <Map<String, dynamic>>[],
    };

    children.add(child);
    parent['children'] = children;

    setState(() {
      _selectMenuNode([..._selectedMenuPath!, children.length - 1]);
    });
  }

  void _deleteSelectedMenuNode() {
    if (_selectedMenuPath == null) return;
    final path = List<int>.from(_selectedMenuPath!);
    final siblings = _getMenuSiblingList(path);
    if (siblings == null) return;

    final idx = path.last;
    if (idx < 0 || idx >= siblings.length) return;

    setState(() {
      siblings.removeAt(idx);
      if (path.length == 1) {
        _boardsMenuTree = List<Map<String, dynamic>>.from(siblings);
      }
      _selectedMenuPath = null;
      _menuLabelController.clear();
      _menuSpeechController.clear();
      _menuImageController.clear();
      _menuAudioController.clear();
      _menuBackgroundController.text = '#FFFFFF';
      _menuTextColorController.text = '#000000';
      _menuBoardTarget = null;
      _menuHidden = false;
    });
  }

  List<Map<String, dynamic>> _serializeMenuTree(List<Map<String, dynamic>> items) {
    final serialized = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      serialized.add({
        'id': _asString(item['id'], fallback: 'menu_custom_${DateTime.now().millisecondsSinceEpoch}_$i'),
        'label': _asString(item['label'], fallback: 'Menu Item ${i + 1}'),
        'board_id': _nullIfEmpty(_asString(item['board_id'])),
        'source': _asString(item['source'], fallback: 'custom'),
        'source_button_id': item['source_button_id'],
        'sort_order': i,
        'hidden': _isTruthy(item['hidden']),
        'image_url': _nullIfEmpty(_asString(item['image_url'])),
        'speech_text': _nullIfEmpty(_asString(item['speech_text'])),
        'custom_audio_file': _nullIfEmpty(_asString(item['custom_audio_file'])),
        'background_color': _normalizeHex(_asString(item['background_color']), fallback: '#FFFFFF'),
        'text_color': _normalizeHex(_asString(item['text_color']), fallback: '#000000'),
        'children': _serializeMenuTree(
          (item['children'] as List<dynamic>? ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList(),
        ),
      });
    }
    return serialized;
  }

  Future<void> _saveBoardsMenu() async {
    _applyMenuFormToSelectedNode();

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/tap-interface/boards-menu'),
        headers: _headers,
        body: json.encode({'boards_menu': _serializeMenuTree(_boardsMenuTree)}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to save boards menu (${response.statusCode})');
      }

      _boardsMenuOriginalTree = _boardsMenuTree.map(_deepCloneMap).toList();
      _showSnackBar('Boards menu saved.', isError: false);
    } catch (e) {
      _showSnackBar('Boards menu save failed: $e', isError: true);
    }
  }

  void _cancelBoardsMenuChanges() {
    setState(() {
      _boardsMenuTree = _boardsMenuOriginalTree.map(_deepCloneMap).toList();
      _selectedMenuPath = null;
      _menuLabelController.clear();
      _menuSpeechController.clear();
      _menuImageController.clear();
      _menuAudioController.clear();
      _menuBackgroundController.text = '#FFFFFF';
      _menuTextColorController.text = '#000000';
      _menuBoardTarget = null;
      _menuHidden = false;
    });
  }

  // ---------- Migration helpers ----------
  Future<void> _pickAndUploadTouchChatFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: true,
        allowedExtensions: ['ce', 'zip'],
      );

      if (result == null || result.files.isEmpty || result.files.first.bytes == null) {
        return;
      }

      final picked = result.files.first;
      final lower = picked.name.toLowerCase();
      if (!(lower.endsWith('.ce') || lower.endsWith('.zip') || lower.endsWith('.ce.zip'))) {
        _setMigrationStatus('Please select a TouchChat .ce file.');
        return;
      }

      _setMigrationStatus('Uploading and analyzing TouchChat export...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/api/touchchat-migration/upload-ce'),
      );

      request.headers['Authorization'] = 'Bearer ${widget.idToken}';
      request.headers['X-User-ID'] = widget.aacUserId;
      request.files.add(http.MultipartFile.fromBytes('file', picked.bytes!, filename: picked.name));

      final uploaded = await request.send();
      final uploadText = await uploaded.stream.bytesToString();

      if (uploaded.statusCode != 200) {
        throw Exception('Upload failed (${uploaded.statusCode})');
      }

      final uploadPayload = json.decode(uploadText) as Map<String, dynamic>;
      final sessionId = _asString(uploadPayload['session_id']);
      if (sessionId.isEmpty) {
        throw Exception('Upload succeeded but no session ID was returned.');
      }

      final boardsResponse = await http.get(
        Uri.parse('$_apiBaseUrl/api/touchchat-migration/boards/$sessionId'),
        headers: _headers,
      );

      if (boardsResponse.statusCode != 200) {
        throw Exception('Failed to load TouchChat boards (${boardsResponse.statusCode})');
      }

      final boardsPayload = json.decode(boardsResponse.body) as Map<String, dynamic>;

      setState(() {
        _migrationSessionId = sessionId;
        _touchChatData = boardsPayload;
        _selectedSourceBoardId = null;
        _selectedButtonIndices.clear();
        _pendingMissingTargets = [];
        _pendingTargetMode.clear();
        _pendingTargetCreateName.clear();
        _pendingTargetExistingBoard.clear();
      });

      _setMigrationStatus('TouchChat file analyzed. Select a source board.');
    } catch (e) {
      _setMigrationStatus('Upload failed: $e');
    }
  }

  Map<String, dynamic>? _selectedSourceBoard() {
    final boards = (_touchChatData?['boards'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (_selectedSourceBoardId == null) return null;
    final board = boards[_selectedSourceBoardId!];
    if (board is Map<String, dynamic>) return board;
    return null;
  }

  Future<void> _executeMigrationImport() async {
    if (_migrationBusy) return;
    if (_migrationSessionId == null || _selectedSourceBoardId == null) {
      _setMigrationStatus('Upload a file and choose a source board first.');
      return;
    }

    if (!_importFullCascade && _selectedButtonIndices.isEmpty) {
      _setMigrationStatus('Select at least one button to import.');
      return;
    }

    final destinationName = _newDestinationNameController.text.trim();
    if (_destinationType == 'new' && destinationName.isEmpty) {
      _setMigrationStatus('Enter a destination board name.');
      return;
    }
    if (_destinationType == 'existing' && (_existingDestinationBoardId ?? '').isEmpty) {
      _setMigrationStatus('Select an existing destination board.');
      return;
    }

    if (_destinationType == 'new') {
      final normalizedDestination = destinationName.toLowerCase().trim();
      final existing = _boards.where((b) {
        final label = _asString(b['label']).toLowerCase().trim();
        return label == normalizedDestination;
      }).toList();

      if (existing.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Naming Conflict'),
            content: Text(
              'A board named "$destinationName" already exists. Do you want to continue anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        );

        if (proceed != true) {
          _setMigrationStatus('Migration canceled. Rename destination board or choose existing.');
          return;
        }
      }
    }

    final navigationResolutions = <String, dynamic>{};
    for (final target in _pendingMissingTargets) {
      final rid = _asString(target['target_page_rid']);
      if (rid.isEmpty) continue;

      final mode = _pendingTargetMode[rid] ?? 'create';
      if (mode == 'create') {
        navigationResolutions[rid] = {
          'action': 'create',
          'board_name': (_pendingTargetCreateName[rid] ?? _asString(target['target_page_name'])).trim(),
        };
      } else {
        navigationResolutions[rid] = {
          'action': 'existing',
          'board_id': _pendingTargetExistingBoard[rid] ?? '',
        };
      }
    }

    for (final target in _pendingMissingTargets) {
      final rid = _asString(target['target_page_rid']);
      if (rid.isEmpty) continue;
      final mode = _pendingTargetMode[rid] ?? 'create';
      if (mode == 'existing' && (_pendingTargetExistingBoard[rid] ?? '').trim().isEmpty) {
        _setMigrationStatus('Pick an existing board for all missing navigation targets.');
        return;
      }
      if (mode == 'create' && (_pendingTargetCreateName[rid] ?? '').trim().isEmpty) {
        _setMigrationStatus('Enter a name for each new navigation target board.');
        return;
      }
    }

    final payload = <String, dynamic>{
      'session_id': _migrationSessionId,
      'source_board_id': _selectedSourceBoardId,
      'selected_button_indices': _selectedButtonIndices.where((idx) => idx >= 0).toList()..sort(),
      'destination_type': _destinationType,
      'destination_board_id': _destinationType == 'existing' ? _existingDestinationBoardId : null,
      'destination_board_name': _destinationType == 'new' ? destinationName : null,
      'merge_mode': _mergeMode,
      'navigation_resolutions': navigationResolutions,
      'import_full_cascade': _importFullCascade,
    };

    setState(() {
      _migrationBusy = true;
    });
    _setMigrationStatus('Importing TouchChat data...');

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/touchchat-migration/import-board'),
        headers: _headers,
        body: json.encode(payload),
      );

      if (response.statusCode != 200) {
        throw Exception('Import failed (${response.statusCode})');
      }

      final result = json.decode(response.body) as Map<String, dynamic>;

      if (_isTruthy(result['requires_confirmation'])) {
        final targets = (result['missing_navigation_targets'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
        final available = (result['available_destination_boards'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();

        setState(() {
          _pendingMissingTargets = targets;
          for (final target in targets) {
            final rid = _asString(target['target_page_rid']);
            if (rid.isEmpty) continue;
            _pendingTargetMode[rid] = 'create';
            _pendingTargetCreateName[rid] = _asString(target['target_page_name'], fallback: 'New Board');
            _pendingTargetExistingBoard[rid] = available.isNotEmpty ? _asString(available.first['id']) : '';
          }
        });

        _setMigrationStatus('Resolve missing navigation targets and run import again.');
      } else {
        final importedCount = _asInt(result['buttons_imported'], fallback: 0);
        final targetLabel = _asString(result['target_board_label']);
        _setMigrationStatus('Migration complete: $importedCount buttons imported to $targetLabel.');

        await _loadBoards();

        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Migration Complete'),
              content: Text('Imported $importedCount buttons into $targetLabel.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            ),
          );
        }

        setState(() {
          _pendingMissingTargets = [];
        });
      }
    } catch (e) {
      _setMigrationStatus('Import failed: $e');
    } finally {
      setState(() {
        _migrationBusy = false;
      });
    }
  }

  Future<void> _resetMigrationSession() async {
    if (_migrationSessionId != null) {
      try {
        await http.delete(
          Uri.parse('$_apiBaseUrl/api/touchchat-migration/session/${_migrationSessionId!}'),
          headers: {
            'Authorization': 'Bearer ${widget.idToken}',
            'X-User-ID': widget.aacUserId,
          },
        );
      } catch (_) {}
    }

    setState(() {
      _migrationSessionId = null;
      _touchChatData = null;
      _selectedSourceBoardId = null;
      _selectedButtonIndices.clear();
      _importFullCascade = false;
      _destinationType = 'new';
      _mergeMode = 'update';
      _existingDestinationBoardId = null;
      _newDestinationNameController.clear();
      _pendingMissingTargets = [];
      _pendingTargetMode.clear();
      _pendingTargetCreateName.clear();
      _pendingTargetExistingBoard.clear();
    });

    _setMigrationStatus('Ready to upload a TouchChat .ce file.');
  }

  void _setMigrationStatus(String message) {
    setState(() {
      _migrationStatus = message;
    });
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap Interface Admin'),
        backgroundColor: const Color(0xFF002244),
        foregroundColor: const Color(0xFFFB4F14),
      ),
      body: _loading && _boards.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildSectionHeader(),
                    Expanded(
                      child: switch (_activeSection) {
                        _AdminSection.boardBuilder => _buildBoardBuilderSection(),
                        _AdminSection.boardsMenu => _buildBoardsMenuSection(),
                        _AdminSection.migration => _buildMigrationSection(),
                      },
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadBoards,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Container(
      width: double.infinity,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildSectionButton(_AdminSection.boardBuilder, 'Board Builder', Icons.grid_view),
          _buildSectionButton(_AdminSection.boardsMenu, 'Boards Menu', Icons.account_tree),
          _buildSectionButton(_AdminSection.migration, 'TouchChat Migration', Icons.file_upload),
        ],
      ),
    );
  }

  Widget _buildSectionButton(_AdminSection section, String label, IconData icon) {
    final selected = _activeSection == section;
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _activeSection = section;
        });
      },
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF002244) : Colors.white,
        foregroundColor: selected ? const Color(0xFFFB4F14) : Colors.black87,
        side: BorderSide(color: selected ? const Color(0xFF002244) : Colors.grey.shade300),
      ),
    );
  }

  Widget _buildLegendChip(String label, Color borderColor, Color bgColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _buildBoardBuilderSection() {
    final migrationIncompleteCount = _boards.where((b) {
      final created = _isTruthy(b['created_during_migration']);
      final buttons = (b['buttons'] as List<dynamic>? ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList();
      return created && buttons.isEmpty && !_isBoardReadOnly(b);
    }).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 360,
                        child: DropdownButtonFormField<String>(
                          value: _selectedBoardId,
                          decoration: const InputDecoration(
                            labelText: 'Select Board',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _editableBoards
                              .map((b) {
                                final id = _asString(b['id']);
                                final label = _asString(b['label'], fallback: id);
                                final homeBoardId = _asString(_boardSettings['home_board_id']);
                                final tags = <String>[];
                                if (id == homeBoardId) tags.add('home');
                                final createdDuringMigration = _isTruthy(b['created_during_migration']);
                                final buttons = (b['buttons'] as List<dynamic>? ?? <dynamic>[])
                                    .whereType<Map<String, dynamic>>()
                                    .toList();
                                if (createdDuringMigration && buttons.isEmpty) tags.add('needs config');
                                if (_isBoardReadOnly(b)) tags.add('read-only');
                                final tagStr = tags.isEmpty ? '' : ' [${tags.join(', ')}]';
                                return DropdownMenuItem(
                                  value: id,
                                  child: Text('$label$tagStr'),
                                );
                              })
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedBoardId = value;
                              _bindBoardFromSelection();
                              _moveSourceIndex = null;
                            });
                          },
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _createNewBoardDraft,
                        icon: const Icon(Icons.add),
                        label: const Text('Create New Board'),
                      ),
                      OutlinedButton(
                        onPressed: migrationIncompleteCount > 0
                            ? () {
                                setState(() {
                                  _showMigrationBoardsOnly = !_showMigrationBoardsOnly;
                                  if (_selectedBoardId != null &&
                                      !_editableBoards.any((b) => _asString(b['id']) == _selectedBoardId)) {
                                    _selectedBoardId = null;
                                    _currentBoard = null;
                                    _adminGridPage = 0;
                                  }
                                });
                              }
                            : null,
                        child: Text(_showMigrationBoardsOnly ? 'Show All Boards' : 'Show Migration Boards'),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _setAsHomeBoard,
                            onChanged: (_currentBoard == null || _isBoardReadOnly(_currentBoard))
                                ? null
                                : (value) {
                                    setState(() {
                                      _setAsHomeBoard = value ?? false;
                                    });
                                  },
                          ),
                          const Text('Set as Home Board'),
                        ],
                      ),
                    ],
                  ),
                  if (_isBoardReadOnly(_currentBoard)) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'This board is read-only because it is a standard legacy/system board.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ],
                  if (_moveSourceIndex != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Move mode active: tap target cell to swap, or tap the same source cell again to cancel.',
                      style: TextStyle(color: Colors.blue.shade700),
                    ),
                  ],
                  if (_boardDataWarning != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _boardDataWarning!,
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_currentBoard != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Board Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _boardLabelController,
                            decoration: const InputDecoration(
                              labelText: 'Display Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            enabled: !_isBoardReadOnly(_currentBoard),
                          ),
                        ),
                      ],
                    ),
                    if (_boardType == 'ai') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _llmPromptController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'LLM Prompt',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_isBoardReadOnly(_currentBoard),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _promptTopicController,
                              decoration: const InputDecoration(
                                labelText: 'Prompt Topic',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              enabled: !_isBoardReadOnly(_currentBoard),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: TextField(
                              controller: _promptExamplesController,
                              decoration: const InputDecoration(
                                labelText: 'Prompt Examples (comma-separated)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              enabled: !_isBoardReadOnly(_currentBoard),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: TextField(
                              controller: _promptExclusionsController,
                              decoration: const InputDecoration(
                                labelText: 'Prompt Exclusions (comma-separated)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              enabled: !_isBoardReadOnly(_currentBoard),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (_currentBoard == null || _isBoardReadOnly(_currentBoard) || _loading)
                              ? null
                              : _saveCurrentBoard,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Board'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_currentBoard == null || _isBoardReadOnly(_currentBoard) || _loading)
                              ? null
                              : _deleteCurrentBoard,
                          icon: const Icon(Icons.delete),
                          label: const Text('Delete Board'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_currentBoard == null || _isBoardReadOnly(_currentBoard) || _boardType == 'ai')
                              ? null
                              : () async {
                                  final generated = await _openAiBulkDialog();
                                  if (generated != null) {
                                    setState(() {
                                      _applyAiBulkButtons(generated);
                                    });
                                  }
                                },
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('AI Build Options'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_currentBoard == null || _isBoardReadOnly(_currentBoard) || _loading)
                              ? null
                              : _openConfigureDynamicRowsDialog,
                          icon: const Icon(Icons.tune),
                          label: const Text('Configure Dynamic Rows'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0D9488),
                            side: const BorderSide(color: Color(0xFF0D9488)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_boardType != 'ai')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Board Buttons', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Tap cell to edit. Long-press to start move/swap mode.'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          _buildLegendChip('AI/LLM button', const Color(0xFF7C3AED), const Color(0xFFEDE9FE)),
                          _buildLegendChip('Dynamic AI row', const Color(0xFF0D9488), const Color(0xFFF0FDFA)),
                          _buildLegendChip('Navigate', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                          _buildLegendChip('Speech', const Color(0xFF059669), const Color(0xFFD1FAE5)),
                          _buildLegendChip('Empty', Colors.grey.shade400, Colors.grey.shade50),
                          _buildLegendChip('Beyond profile rows', Colors.grey.shade300, Colors.grey.shade100),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final gridCols = _gridCols;
                          final profileRows = _gridRows;
                          final boardDynRaw = _currentBoard?['dynamic_rows'];
                          final dynRows = boardDynRaw != null
                              ? _asInt(boardDynRaw, fallback: _profileDynamicRows)
                              : _profileDynamicRows;
                          final staticRows = (profileRows - dynRows).clamp(0, profileRows);
                          final slotsPerPage = staticRows * gridCols;
                          final sortedPool = _sortedPoolButtons();
                          final totalPages = (slotsPerPage > 0 && sortedPool.isNotEmpty)
                              ? ((sortedPool.length + slotsPerPage - 1) ~/ slotsPerPage)
                              : 1;
                          final page = _adminGridPage.clamp(0, totalPages - 1);
                          const cellSize = 68.0;
                          final totalHeight = _boardRows * cellSize + (_boardRows - 1) * 4;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Page ${page + 1} of $totalPages',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: page > 0
                                        ? () => setState(() => _adminGridPage = page - 1)
                                        : null,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(36, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('← Prev'),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    onPressed: page < totalPages - 1
                                        ? () => setState(() => _adminGridPage = page + 1)
                                        : null,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(36, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('Next →'),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '(${sortedPool.length} buttons, $slotsPerPage/page)',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: totalHeight,
                                child: GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _boardRows * gridCols,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: gridCols,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 4,
                                    mainAxisExtent: 68.0,
                                  ),
                                  itemBuilder: (context, index) {
                                    final row = index ~/ gridCols;
                                    final col = index % gridCols;

                                    final isStaticRow = row < staticRows;
                                    final isDynamicSlot = row >= staticRows && row < profileRows;
                                    final isOutOfRange = row >= profileRows;

                                    if (isDynamicSlot) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0FDFA),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF0D9488), width: 1.5),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Center(
                                          child: Text(
                                            '✦ Dynamic\nAI Row',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: Color(0xFF0F766E),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      );
                                    }

                                    if (isOutOfRange) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                      );
                                    }

                                    // Static row: look up button by sorted pool position
                                    final poolPos = isStaticRow
                                        ? page * slotsPerPage + row * gridCols + col
                                        : -1;
                                    final button = (isStaticRow && poolPos < sortedPool.length)
                                        ? sortedPool[poolPos]
                                        : null;
                                    final hasContent = button != null && _asString(button['label']).isNotEmpty;
                                    final label = hasContent ? _asString(button['label']) : '';
                                    final btnRow = button != null
                                        ? _asInt(button['row'], fallback: poolPos ~/ _boardCols)
                                        : (poolPos >= 0 ? poolPos ~/ _boardCols : row);
                                    final btnCol = button != null
                                        ? _asInt(button['col'], fallback: poolPos % _boardCols)
                                        : (poolPos >= 0 ? poolPos % _boardCols : col);

                                    final isSourceMove = _moveSourceIndex == index;
                                    final isMoveActive = _moveSourceIndex != null;

                                    final afterSel = _asString(button?['after_selection']);
                                    final actionType = _asString(button?['action_type']);
                                    final customAudioUrl = _asString(button?['custom_audio_file']);
                                    final tempNavValue = button?['temporary_navigation'];
                                    final isNavHome = hasContent && afterSel == 'navigate_home';
                                    final isNav = hasContent && !isNavHome &&
                                        (afterSel == 'navigate' || actionType == 'navigate');
                                    final isAi = hasContent && afterSel == 'use_ai';
                                    final hasAudio = hasContent && customAudioUrl.isNotEmpty;
                                    final isTempNav = hasContent && _isTruthy(tempNavValue);
                                    final isSpeech = hasContent && !isNav && !isNavHome && !isAi;

                                    final Color bgColor;
                                    final Color borderColor;
                                    final Color fgColor;
                                    if (isSourceMove) {
                                      bgColor = Colors.orange.shade100;
                                      borderColor = Colors.orange;
                                      fgColor = Colors.black;
                                    } else if (isAi) {
                                      bgColor = const Color(0xFFEDE9FE);
                                      borderColor = const Color(0xFF7C3AED);
                                      fgColor = const Color(0xFF4C1D95);
                                    } else if (isNav || isNavHome) {
                                      bgColor = const Color(0xFFFEF3C7);
                                      borderColor = const Color(0xFFD97706);
                                      fgColor = const Color(0xFF78350F);
                                    } else if (isSpeech) {
                                      bgColor = const Color(0xFFD1FAE5);
                                      borderColor = const Color(0xFF059669);
                                      fgColor = Colors.black;
                                    } else {
                                      bgColor = Colors.grey.shade50;
                                      borderColor = Colors.grey.shade300;
                                      fgColor = Colors.grey.shade400;
                                    }

                                    return InkWell(
                                      onTap: () async {
                                        if (_isBoardReadOnly(_currentBoard)) return;
                                        if (_moveSourceIndex != null) {
                                          if (_moveSourceIndex == index) {
                                            setState(() => _moveSourceIndex = null);
                                            return;
                                          }
                                          _swapButtonsByIndex(_moveSourceIndex!, index);
                                          setState(() => _moveSourceIndex = null);
                                          return;
                                        }
                                        await _openButtonEditor(btnRow, btnCol);
                                      },
                                      onLongPress: () {
                                        if (_isBoardReadOnly(_currentBoard)) return;
                                        setState(() {
                                          _moveSourceIndex = isSourceMove ? null : index;
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isMoveActive && !isSourceMove
                                              ? bgColor.withValues(alpha: 0.8)
                                              : bgColor,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: borderColor, width: isSourceMove ? 2 : 1),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: Stack(
                                          children: [
                                            Center(
                                              child: Text(
                                                label.isEmpty ? '' : label,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: fgColor,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isNavHome)
                                              const Positioned(top: 1, right: 1,
                                                child: Text('⌂', style: TextStyle(fontSize: 10, color: Color(0xFFD97706))))
                                            else if (isTempNav)
                                              const Positioned(top: 1, right: 1,
                                                child: Text('↩', style: TextStyle(fontSize: 10, color: Color(0xFFD97706))))
                                            else if (isNav)
                                              const Positioned(top: 1, right: 1,
                                                child: Text('→', style: TextStyle(fontSize: 10, color: Color(0xFFD97706))))
                                            else if (isAi)
                                              const Positioned(top: 1, right: 1,
                                                child: Text('✦', style: TextStyle(fontSize: 10, color: Color(0xFF7C3AED)))),
                                            if (hasAudio)
                                              const Positioned(bottom: 1, right: 1,
                                                child: Text('♪', style: TextStyle(fontSize: 9, color: Colors.blue))),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openConfigureDynamicRowsDialog() async {
    if (_currentBoard == null) return;

    final promptController = TextEditingController(text: _asString(_currentBoard!['llm_prompt']));
    final examplesController = TextEditingController(text: _asString(_currentBoard!['prompt_examples']));
    final exclusionsController = TextEditingController(text: _asString(_currentBoard!['prompt_exclusions']));
    final rowCountController = TextEditingController();

    // Seed row count from board's explicit value, else profile default
    final boardDynRaw = _currentBoard?['dynamic_rows'];
    final currentDynRows = boardDynRaw != null
        ? _asInt(boardDynRaw, fallback: _profileDynamicRows)
        : _profileDynamicRows;
    rowCountController.text = currentDynRows.toString();

    int step = 1;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Configure Dynamic Rows'),
          content: SizedBox(
            width: 460,
            child: step == 1
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Step 1 of 2',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade600)),
                      const SizedBox(height: 4),
                      const Text('AI Prompt for Dynamic Rows',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text(
                          'Specify what kind of words or phrases the AI should generate for the dynamic rows at the bottom of this board.',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: promptController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. Generate action words and phrases for common activities...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: examplesController,
                              decoration: const InputDecoration(
                                labelText: 'Examples (comma-separated)',
                                hintText: 'e.g. Hello, Goodbye, Thank you',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: exclusionsController,
                              decoration: const InputDecoration(
                                labelText: 'Exclusions (comma-separated)',
                                hintText: 'e.g. words to avoid',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Step 2 of 2',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade600)),
                      const SizedBox(height: 4),
                      const Text('Number of Dynamic Rows',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          'Set the number of dynamic rows (0 to $_boardRows). Enter 0 to disable dynamic rows.',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: rowCountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 1',
                          border: const OutlineInputBorder(),
                          suffixText: 'max $_boardRows',
                        ),
                      ),
                    ],
                  ),
          ),
          actions: step == 1
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => setDialogState(() => step = 2),
                    child: const Text('Next →'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => setDialogState(() => step = 1),
                    child: const Text('← Back'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final val = int.tryParse(rowCountController.text.trim());
                      if (val == null || val < 0 || val > _boardRows) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Enter a number between 0 and $_boardRows'),
                        ));
                        return;
                      }
                      Navigator.pop(dialogContext, {
                        'dynamic_rows': val,
                        'llm_prompt': promptController.text.trim().isEmpty
                            ? null
                            : promptController.text.trim(),
                        'prompt_examples': examplesController.text.trim().isEmpty
                            ? null
                            : examplesController.text.trim(),
                        'prompt_exclusions': exclusionsController.text.trim().isEmpty
                            ? null
                            : exclusionsController.text.trim(),
                        'old_dynamic_rows': currentDynRows,
                      });
                    },
                    child: const Text('Apply & Save'),
                  ),
                ],
        ),
      ),
    );

    promptController.dispose();
    examplesController.dispose();
    exclusionsController.dispose();
    rowCountController.dispose();

    if (result == null || !mounted) return;

    final newVal = result['dynamic_rows'] as int;
    final oldVal = result['old_dynamic_rows'] as int;

    setState(() {
      _currentBoard!['dynamic_rows'] = newVal;
      _currentBoard!['llm_prompt'] = result['llm_prompt'];
      _currentBoard!['prompt_examples'] = result['prompt_examples'];
      _currentBoard!['prompt_exclusions'] = result['prompt_exclusions'];
    });

    // Keep board details controllers in sync
    _llmPromptController.text = _asString(_currentBoard!['llm_prompt']);
    _promptExamplesController.text = _asString(_currentBoard!['prompt_examples']);
    _promptExclusionsController.text = _asString(_currentBoard!['prompt_exclusions']);

    // If reducing dynamic rows, offer to fill vacated rows with static pool words
    bool fillStatic = false;
    if (newVal < oldVal && mounted) {
      fillStatic = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Fill Vacated Rows?'),
              content: const Text(
                  'You reduced the number of dynamic rows. Fill the newly available static rows with default vocabulary from the static pool?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No, leave blank'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yes, fill them'),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (fillStatic && mounted) {
      await _fillVacatedStaticRows(oldVal, newVal);
    }

    if (!mounted) return;
    await _saveCurrentBoard();

    // Sync profile's tapDynamicRows so the tap interface reflects the change.
    // updateSettings notifies listeners (grid rebuilds) and saves to the server.
    if (mounted) {
      await Provider.of<UserSettingsProvider>(context, listen: false)
          .updateSettings((s) => s.tapDynamicRows = newVal);
      setState(() {}); // ensure admin grid re-reads the updated value
    }
  }

  Future<void> _fillVacatedStaticRows(int oldDynRows, int newDynRows) async {
    if (_currentBoard == null) return;
    try {
      final label = Uri.encodeComponent(_asString(_currentBoard!['label']));
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/tap-interface/static-pool?label=$label'),
        headers: _headers,
      );
      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final pool = (data['pool'] as List<dynamic>? ?? [])
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (pool.isEmpty) return;

      final buttons = (_currentBoard!['buttons'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final existingLabels = buttons
          .map((b) => _asString(b['label']).toLowerCase())
          .where((l) => l.isNotEmpty)
          .toSet();

      final gridCols = _gridCols;
      int poolIdx = 0;
      final newButtons = List<Map<String, dynamic>>.from(buttons);

      for (int r = _boardRows - oldDynRows; r < _boardRows - newDynRows; r++) {
        for (int c = 0; c < gridCols; c++) {
          final hasBtn = newButtons.any(
              (b) => _asInt(b['row'], fallback: -1) == r && _asInt(b['col'], fallback: -1) == c);
          if (!hasBtn) {
            String? word;
            while (poolIdx < pool.length) {
              final candidate = pool[poolIdx++];
              if (!existingLabels.contains(candidate.toLowerCase())) {
                word = candidate;
                existingLabels.add(candidate.toLowerCase());
                break;
              }
            }
            if (word != null) {
              newButtons.add({
                'id': 'btn_${r}_${c}_${DateTime.now().millisecondsSinceEpoch}',
                'label': word,
                'row': r,
                'col': c,
                'speech_text': word,
                'after_selection': 'do_nothing',
                'action_type': 'announce',
                'target_board_id': null,
                'temporary_navigation': false,
                'custom_audio_file': null,
                'background_color': '#FFFFFF',
                'text_color': '#000000',
                'hidden': false,
              });
            }
          }
        }
      }

      setState(() {
        _currentBoard!['buttons'] = newButtons;
      });
    } catch (e) {
      debugPrint('_fillVacatedStaticRows: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _openAiBulkDialog() async {
    final promptController = TextEditingController();
    final totalController = TextEditingController(text: '24');
    final perRowController = TextEditingController(text: '12');
    String afterSelection = 'do_nothing';
    String? targetBoard;
    final bgController = TextEditingController(text: '#FFFFFF');
    List<String> previewOptions = [];
    bool previewBusy = false;

    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runPreview() async {
              final prompt = promptController.text.trim();
              final total = int.tryParse(totalController.text) ?? 24;
              if (prompt.isEmpty || total <= 0) {
                return;
              }

              setDialogState(() {
                previewBusy = true;
              });

              try {
                final response = await http.post(
                  Uri.parse('$_apiBaseUrl/llm'),
                  headers: _headers,
                  body: json.encode({
                    'count': total,
                    'prompt':
                        'Generate exactly $total UNIQUE board button labels for AAC communication: $prompt. Return JSON array of objects with an option field.',
                    'response_format': 'json',
                  }),
                );

                if (response.statusCode != 200) {
                  throw Exception('Preview failed (${response.statusCode})');
                }

                final payload = json.decode(response.body);
                final normalized = <String>[];
                final seen = <String>{};

                List<dynamic> source;
                if (payload is List<dynamic>) {
                  source = payload;
                } else if (payload is Map<String, dynamic>) {
                  source = (payload['options'] as List<dynamic>?) ??
                      (payload['data'] as List<dynamic>?) ??
                      (payload['response'] as List<dynamic>?) ??
                      <dynamic>[];
                } else {
                  source = <dynamic>[];
                }

                for (final item in source) {
                  final text = item is String
                      ? item.trim()
                    : item is Map<String, dynamic> && _asString(item['option']).trim().isNotEmpty
                      ? _asString(item['option']).trim()
                      : item is Map<String, dynamic>
                        ? _asString(item['text']).trim()
                        : '';
                  if (text.isEmpty) continue;
                  final key = text.toLowerCase();
                  if (seen.contains(key)) continue;
                  seen.add(key);
                  normalized.add(text);
                }

                setDialogState(() {
                  previewOptions = normalized.take(total).toList();
                });
              } catch (_) {
                setDialogState(() {
                  previewOptions = [];
                });
              } finally {
                setDialogState(() {
                  previewBusy = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('AI Build Board Options'),
              content: SizedBox(
                width: 680,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: promptController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Prompt',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: totalController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Total Options',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: perRowController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Options Per Row',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: afterSelection,
                        items: const [
                          DropdownMenuItem(value: 'do_nothing', child: Text('Do nothing')),
                          DropdownMenuItem(value: 'use_ai', child: Text('Use AI')),
                          DropdownMenuItem(value: 'navigate', child: Text('Navigate')),
                        ],
                        onChanged: (v) {
                          setDialogState(() {
                            afterSelection = v ?? 'do_nothing';
                            if (afterSelection != 'navigate') targetBoard = null;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Default After Selection',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (afterSelection == 'navigate')
                        DropdownButtonFormField<String>(
                          value: targetBoard,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('No target board'),
                            ),
                            ..._boards.map((b) {
                              final id = _asString(b['id']);
                              final label = _asString(b['label'], fallback: id);
                              return DropdownMenuItem<String>(value: id, child: Text(label));
                            }),
                          ],
                          onChanged: (v) {
                            setDialogState(() {
                              targetBoard = v;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Target Board',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bgController,
                        decoration: const InputDecoration(
                          labelText: 'Background Color (#RRGGBB)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: previewBusy ? null : runPreview,
                              child: previewBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Preview'),
                            ),
                            Text('${previewOptions.length} options'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ListView.builder(
                          itemCount: previewOptions.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            title: Text(previewOptions[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: previewOptions.isEmpty
                      ? null
                      : () {
                          final perRow = (int.tryParse(perRowController.text) ?? 12).clamp(1, _boardCols);
                          final generated = <Map<String, dynamic>>[];
                          for (var i = 0; i < previewOptions.length; i++) {
                            final row = i ~/ perRow;
                            final col = i % perRow;
                            if (row >= _boardRows) break;
                            generated.add({
                              'id': 'btn_ai_${DateTime.now().millisecondsSinceEpoch}_$i',
                              'label': previewOptions[i],
                              'row': row,
                              'col': col,
                              'speech_text': previewOptions[i],
                              'after_selection': afterSelection,
                              'action_type': afterSelection == 'navigate' ? 'navigate' : 'announce',
                              'target_board_id': afterSelection == 'navigate' ? targetBoard : null,
                              'temporary_navigation': false,
                              'custom_audio_file': null,
                              'special_function': null,
                              'image_url': null,
                              'background_color': _normalizeHex(bgController.text, fallback: '#FFFFFF'),
                              'text_color': '#000000',
                              'hidden': false,
                            });
                          }
                          Navigator.pop(context, generated);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    promptController.dispose();
    totalController.dispose();
    perRowController.dispose();
    bgController.dispose();

    return result;
  }

  void _applyAiBulkButtons(List<Map<String, dynamic>> generated) {
    if (_currentBoard == null) return;

    // Replace by default for parity with current web dialog defaults unless user manually edits afterwards.
    _currentBoard!['buttons'] = generated;
  }

  Widget _buildBoardsMenuSection() {
    return Row(
      children: [
        SizedBox(
          width: 380,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Menu Structure'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addRootMenuNode,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _boardsMenuTree.isEmpty
                      ? const Center(child: Text('No menu items. Add one to begin.'))
                      : ListView(
                          padding: const EdgeInsets.all(8),
                          children: _buildMenuTreeWidgets(_boardsMenuTree, const <int>[], 0),
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: _selectedMenuPath == null
                ? const Center(
                    child: Text('Select a menu item to edit.'),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Edit Menu Item', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _menuLabelController,
                            decoration: const InputDecoration(
                              labelText: 'Menu Label',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _applyMenuFormToSelectedNode(),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _menuBoardTarget,
                            decoration: const InputDecoration(
                              labelText: 'Board Target',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(value: null, child: Text('None / Category only')),
                              ..._boards
                                  .map((b) {
                                    final id = _asString(b['id']);
                                    final label = _asString(b['label'], fallback: id);
                                    return DropdownMenuItem<String>(value: id, child: Text(label));
                                  }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _menuBoardTarget = value;
                                _applyMenuFormToSelectedNode();
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _menuSpeechController,
                            decoration: const InputDecoration(
                              labelText: 'Speech Text',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _applyMenuFormToSelectedNode(),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _menuImageController,
                            decoration: const InputDecoration(
                              labelText: 'Image URL',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _applyMenuFormToSelectedNode(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _menuAudioController,
                                  readOnly: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Custom Audio URL',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    final uploaded = await _uploadAudioFile();
                                    if (uploaded != null) {
                                      setState(() {
                                        _menuAudioController.text = uploaded;
                                        _applyMenuFormToSelectedNode();
                                      });
                                    }
                                  } catch (e) {
                                    _showSnackBar('Audio upload failed: $e', isError: true);
                                  }
                                },
                                child: const Text('Upload'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _normalizeHex(_menuBackgroundController.text, fallback: '#FFFFFF'),
                            decoration: const InputDecoration(
                              labelText: 'Background Color',
                              border: OutlineInputBorder(),
                            ),
                            items: _buildBackgroundColorItems(_menuBackgroundController.text),
                            onChanged: (value) {
                              setState(() {
                                _menuBackgroundController.text = _normalizeHex(value ?? '#FFFFFF', fallback: '#FFFFFF');
                                _applyMenuFormToSelectedNode();
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _menuHidden,
                            onChanged: (v) {
                              setState(() {
                                _menuHidden = v ?? false;
                                _applyMenuFormToSelectedNode();
                              });
                            },
                            title: const Text('Hidden'),
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _addChildMenuNode,
                                icon: const Icon(Icons.subdirectory_arrow_right),
                                label: const Text('Add Child'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _deleteSelectedMenuNode,
                                icon: const Icon(Icons.delete),
                                label: const Text('Delete Item'),
                              ),
                              ElevatedButton.icon(
                                onPressed: _saveBoardsMenu,
                                icon: const Icon(Icons.save),
                                label: const Text('Save Changes'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _cancelBoardsMenuChanges,
                                icon: const Icon(Icons.cancel),
                                label: const Text('Cancel Changes'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMenuTreeWidgets(List<Map<String, dynamic>> nodes, List<int> parentPath, int depth) {
    final widgets = <Widget>[];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final path = [...parentPath, i];
      final selected = _selectedMenuPath != null && _listEquals(_selectedMenuPath!, path);
      final children = (node['children'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () {
              _applyMenuFormToSelectedNode();
              _selectMenuNode(path);
            },
            child: Container(
              padding: EdgeInsets.fromLTRB(8 + (depth * 18), 8, 8, 8),
              decoration: BoxDecoration(
                color: selected ? Colors.green.shade50 : Colors.white,
                border: Border.all(color: selected ? Colors.green : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(children.isEmpty ? Icons.insert_drive_file : Icons.folder, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _asString(node['label'], fallback: '(unlabeled)'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_isTruthy(node['hidden']))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('HIDDEN', style: TextStyle(fontSize: 10, color: Colors.amber.shade900)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      if (children.isNotEmpty) {
        widgets.addAll(_buildMenuTreeWidgets(children, path, depth + 1));
      }
    }

    return widgets;
  }

  Widget _buildMigrationSection() {
    final sourceBoards = ((_touchChatData?['boards'] as Map<String, dynamic>?) ?? <String, dynamic>{});
    final sourceBoardEntries = sourceBoards.entries
        .where((entry) => entry.value is Map<String, dynamic>)
        .map((entry) => MapEntry(entry.key, entry.value as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => _asString(a.value['name']).compareTo(_asString(b.value['name'])));

    final selectedBoard = _selectedSourceBoard();
    final sourceButtons = (selectedBoard?['buttons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TouchChat Migration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(_migrationStatus),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _migrationBusy ? null : _pickAndUploadTouchChatFile,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Upload .ce File'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _migrationBusy ? null : _resetMigrationSession,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset Migration'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedSourceBoardId,
                    decoration: const InputDecoration(
                      labelText: 'Source TouchChat Board',
                      border: OutlineInputBorder(),
                    ),
                    items: sourceBoardEntries.map((entry) {
                      final board = entry.value;
                      final name = _asString(board['name'], fallback: entry.key);
                      final count = _asInt(board['button_count'], fallback: 0);
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Text('$name ($count buttons)'),
                      );
                    }).toList(),
                    onChanged: (_migrationSessionId == null || _migrationBusy)
                        ? null
                        : (value) {
                            setState(() {
                              _selectedSourceBoardId = value;
                              _selectedButtonIndices.clear();
                              _pendingMissingTargets = [];

                              if (value != null && sourceBoards[value] is Map<String, dynamic>) {
                                final board = sourceBoards[value] as Map<String, dynamic>;

                                if (_importFullCascade) {
                                  final nextButtons = (board['buttons'] as List<dynamic>? ?? <dynamic>[])
                                      .whereType<Map<String, dynamic>>()
                                      .toList();
                                  _selectedButtonIndices = nextButtons
                                      .map((btn) => _asInt(btn['index'], fallback: -1))
                                      .where((idx) => idx >= 0)
                                      .toSet();
                                }

                                final sourceName = _asString(board['name'], fallback: value);
                                if (_destinationType == 'new') {
                                  _newDestinationNameController.text = sourceName;
                                }
                              }
                            });
                          },
                  ),
                  if (selectedBoard != null) ...[
                    const SizedBox(height: 8),
                    Text('Grid ${_asInt(selectedBoard['layout_cols'], fallback: 0)} x ${_asInt(selectedBoard['layout_rows'], fallback: 0)}'),
                  ],
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _importFullCascade,
                    onChanged: _migrationBusy
                        ? null
                        : (v) {
                            setState(() {
                              _importFullCascade = v ?? false;
                              if (_importFullCascade) {
                                _selectedButtonIndices = sourceButtons
                                    .map((btn) => _asInt(btn['index'], fallback: -1))
                                    .where((idx) => idx >= 0)
                                    .toSet();
                              }
                            });
                          },
                    title: const Text('Import full cascade (linked boards recursively)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: selectedBoard == null
                            ? null
                            : () {
                                setState(() {
                                  _selectedButtonIndices = sourceButtons
                                      .map((btn) => _asInt(btn['index'], fallback: -1))
                                      .where((idx) => idx >= 0)
                                      .toSet();
                                });
                              },
                        child: const Text('Select All'),
                      ),
                      OutlinedButton(
                        onPressed: selectedBoard == null
                            ? null
                            : () {
                                setState(() {
                                  _selectedButtonIndices.clear();
                                });
                              },
                        child: const Text('Clear All'),
                      ),
                      Text('${_selectedButtonIndices.length} selected'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (selectedBoard != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Buttons', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: ListView.builder(
                        itemCount: sourceButtons.length,
                        itemBuilder: (_, i) {
                          final btn = sourceButtons[i];
                          final idx = _asInt(btn['index'], fallback: -1);
                          final checked = _selectedButtonIndices.contains(idx);
                          final navName = _asString(btn['navigation_target_page_name']);

                          return CheckboxListTile(
                            value: checked,
                            onChanged: (_migrationBusy || idx < 0)
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedButtonIndices.add(idx);
                                      } else {
                                        _selectedButtonIndices.remove(idx);
                                      }
                                      _pendingMissingTargets = [];
                                    });
                                  },
                            title: Text('[${_asInt(btn['row'], fallback: 0)},${_asInt(btn['col'], fallback: 0)}] ${_asString(btn['label'])}'),
                            subtitle: Text(
                              navName.isEmpty
                                  ? 'Speech: ${_asString(btn['speech_text'], fallback: _asString(btn['label']))}'
                                  : 'Speech: ${_asString(btn['speech_text'], fallback: _asString(btn['label']))}  |  Navigate: $navName',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Execute Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'new',
                          groupValue: _destinationType,
                          onChanged: _migrationBusy
                              ? null
                              : (v) {
                                  setState(() {
                                    _destinationType = v ?? 'new';
                                  });
                                },
                          title: const Text('Create New Board'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'existing',
                          groupValue: _destinationType,
                          onChanged: _migrationBusy
                              ? null
                              : (v) {
                                  setState(() {
                                    _destinationType = v ?? 'existing';
                                  });
                                },
                          title: const Text('Use Existing Board'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_destinationType == 'new')
                    TextField(
                      controller: _newDestinationNameController,
                      decoration: const InputDecoration(
                        labelText: 'New Destination Board Name',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_migrationBusy,
                    ),
                  if (_destinationType == 'existing')
                    DropdownButtonFormField<String>(
                      value: _existingDestinationBoardId,
                      decoration: const InputDecoration(
                        labelText: 'Existing Destination Board',
                        border: OutlineInputBorder(),
                      ),
                      items: _boards
                          .where((b) => !_isBoardReadOnly(b))
                          .map((b) {
                            final id = _asString(b['id']);
                            final label = _asString(b['label'], fallback: id);
                            return DropdownMenuItem(value: id, child: Text(label));
                          })
                          .toList(),
                      onChanged: _migrationBusy
                          ? null
                          : (value) {
                              setState(() {
                                _existingDestinationBoardId = value;
                              });
                            },
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _mergeMode,
                    decoration: const InputDecoration(
                      labelText: 'Merge Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'update',
                        child: Text('Update by grid position (default)'),
                      ),
                      DropdownMenuItem(
                        value: 'replace',
                        child: Text('Replace destination board buttons'),
                      ),
                    ],
                    onChanged: _migrationBusy
                        ? null
                        : (value) {
                            setState(() {
                              _mergeMode = value ?? 'update';
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  if (_pendingMissingTargets.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber.shade300),
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resolve Missing Navigation Targets',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ..._pendingMissingTargets.map((target) {
                            final rid = _asString(target['target_page_rid']);
                            final mode = _pendingTargetMode[rid] ?? 'create';
                            final defaultName = _asString(target['target_page_name'], fallback: 'New Board');

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(defaultName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: mode,
                                          items: const [
                                            DropdownMenuItem(value: 'create', child: Text('Create new board')),
                                            DropdownMenuItem(value: 'existing', child: Text('Map to existing board')),
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              _pendingTargetMode[rid] = value ?? 'create';
                                            });
                                          },
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: mode == 'create'
                                            ? TextFormField(
                                                initialValue: _pendingTargetCreateName[rid] ?? defaultName,
                                                onChanged: (value) {
                                                  _pendingTargetCreateName[rid] = value;
                                                },
                                                decoration: const InputDecoration(
                                                  labelText: 'New board name',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              )
                                            : DropdownButtonFormField<String>(
                                                value: (_pendingTargetExistingBoard[rid] ?? '').isEmpty
                                                    ? null
                                                    : _pendingTargetExistingBoard[rid],
                                                items: _boards
                                                    .where((b) => !_isBoardReadOnly(b))
                                                    .map((b) {
                                                      final id = _asString(b['id']);
                                                      final label = _asString(b['label'], fallback: id);
                                                      return DropdownMenuItem(value: id, child: Text(label));
                                                    })
                                                    .toList(),
                                                onChanged: (value) {
                                                  setState(() {
                                                    _pendingTargetExistingBoard[rid] = value ?? '';
                                                  });
                                                },
                                                decoration: const InputDecoration(
                                                  labelText: 'Existing board',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ElevatedButton.icon(
                    onPressed: _migrationBusy ? null : _executeMigrationImport,
                    icon: _migrationBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Execute Migration'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
