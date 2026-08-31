import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint
import '../config/environment_config.dart';
import '../services/user_settings_provider.dart';
import '../services/authenticated_http_client.dart';

class TapInterfaceCategory {
  final String id;
  final String label;
  final String? boardId;
  final String? promptCategory;
  final String? speechText;
  final String? imageUrl;
  final String? customAudioFile;
  final String? backgroundColor;
  final String? textColor;
  final String? llmPrompt;
  final String? wordsPrompt;
  final String? staticOptions;
  final bool isHomeBoard;
  final List<TapBoardButton> boardWordOptions;
  final String? specialPage;
  final bool hidden;
  final String optionType; // 'phrase' or 'word'
  final List<TapInterfaceCategory> children;

  TapInterfaceCategory({
    required this.id,
    required this.label,
    this.boardId,
    this.promptCategory,
    this.speechText,
    this.imageUrl,
    this.customAudioFile,
    this.backgroundColor,
    this.textColor,
    this.llmPrompt,
    this.wordsPrompt,
    this.staticOptions,
    this.isHomeBoard = false,
    this.boardWordOptions = const [],
    this.specialPage,
    this.hidden = false,
    this.optionType = 'phrase', // default to phrase
    this.children = const [],
  });

  static String? _normalizeSpecialPage(dynamic raw) {
    if (raw == null) return null;
    var value = raw.toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('!')) {
      value = value.substring(1);
    }
    final normalized = value
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '-');

    switch (normalized) {
      case 'email':
      case 'email-page':
      case 'emailpage':
      case 'mail':
        return 'email';
      case 'guesswho':
      case 'guess-who':
        return 'guess-who';
      case 'free-style':
      case 'freestyle':
        return 'freestyle';
      default:
        return normalized;
    }
  }

  static bool _parseHidden(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = (raw ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static String? _nullableString(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<TapBoardButton> _parseBoardWordOptions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TapBoardButton.fromJson)
        .toList();
  }

  factory TapInterfaceCategory.fromJson(Map<String, dynamic> json) {
    final normalizedSpecialPage = _normalizeSpecialPage(
      json['special_function'] ?? json['special_page'] ?? json['specialPage'],
    );
    final parsedLabel = (json['label'] ?? '').toString();
    final effectiveLabel = parsedLabel.trim().isNotEmpty
        ? parsedLabel
        : (normalizedSpecialPage == 'email' ? 'Email' : parsedLabel);

    return TapInterfaceCategory(
      id: (json['id'] ?? effectiveLabel).toString(),
      label: effectiveLabel,
      boardId: _nullableString(json['board_id'] ?? json['boardId']),
      promptCategory: json['prompt_category']?.toString(),
      speechText: json['speech_text'],
      imageUrl: json['image_url'],
      customAudioFile: json['custom_audio_file'],
      backgroundColor: json['background_color'],
      textColor: json['text_color'],
      llmPrompt: json['llm_prompt'],
      wordsPrompt: json['words_prompt'],
      staticOptions: json['static_options'],
      isHomeBoard: _parseHidden(json['is_home_board'] ?? json['isHomeBoard']),
      boardWordOptions: _parseBoardWordOptions(
        json['board_word_options'] ?? json['boardWordOptions'],
      ),
      specialPage: normalizedSpecialPage,
      hidden: _parseHidden(
        json['hidden'] ?? json['is_hidden'] ?? json['isHidden'],
      ),
      optionType: json['option_type'] ?? 'phrase',
      children: (json['children'] as List<dynamic>? ?? [])
          .map((child) => TapInterfaceCategory.fromJson(child))
          .toList(),
    );
  }

  bool get hasLLMQuery => llmPrompt != null && llmPrompt!.isNotEmpty;
  bool get hasWordsPrompt => wordsPrompt != null && wordsPrompt!.isNotEmpty;
  bool get hasStaticOptions =>
      staticOptions != null && staticOptions!.isNotEmpty;
  bool get hasBoardWordOptions => boardWordOptions.isNotEmpty;
  bool get hasSpecialPage => specialPage != null && specialPage!.isNotEmpty;
  bool get hasChildren => children.isNotEmpty;
  bool get hasCustomAudioFile =>
      customAudioFile != null && customAudioFile!.isNotEmpty;

  List<String> get staticOptionsList {
    if (!hasStaticOptions) return [];
    return staticOptions!.split(',').map((e) => e.trim()).toList();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'board_id': boardId,
    'prompt_category': promptCategory,
    'speech_text': speechText,
    'image_url': imageUrl,
    'custom_audio_file': customAudioFile,
    'background_color': backgroundColor,
    'text_color': textColor,
    'llm_prompt': llmPrompt,
    'words_prompt': wordsPrompt,
    'static_options': staticOptions,
    'is_home_board': isHomeBoard,
    'board_word_options': boardWordOptions.map((b) => b.toJson()).toList(),
    'special_page': specialPage,
    'hidden': hidden,
    'option_type': optionType,
    'children': children.map((c) => c.toJson()).toList(),
  };
}

class TapBoardButton {
  final String id;
  final String text;
  final String? imageSearchText;
  final int row;
  final int col;
  final String? speechText;
  final String? imageUrl;
  final String? customAudioFile;
  final String? actionType;
  final String afterSelection;
  final String? targetBoardId;
  final bool temporaryNavigation;
  final String? backgroundColor;
  final String? textColor;
  final bool hidden;
  final int? modifierTriggerId;
  final Map<String, dynamic> modifierVariants;
  final String buttonType;   // "static" or "dynamic"
  final String? pastTense;   // past tense variant text
  final String? plural;      // plural variant text
  final int? poolIndex;      // position in the full static pool (for pagination)

  const TapBoardButton({
    required this.id,
    required this.text,
    this.imageSearchText,
    required this.row,
    required this.col,
    this.speechText,
    this.imageUrl,
    this.customAudioFile,
    this.actionType,
    this.afterSelection = 'do_nothing',
    this.targetBoardId,
    this.temporaryNavigation = false,
    this.backgroundColor,
    this.textColor,
    this.hidden = false,
    this.modifierTriggerId,
    this.modifierVariants = const {},
    this.buttonType = 'static',
    this.pastTense,
    this.plural,
    this.poolIndex,
  });

  factory TapBoardButton.fromJson(Map<String, dynamic> json) {
    return TapBoardButton(
      id: (json['id'] ?? 'button_${json['row'] ?? 0}_${json['col'] ?? 0}')
          .toString(),
      text: (json['text'] ?? json['label'] ?? '').toString(),
      imageSearchText: TapInterfaceCategory._nullableString(
        json['image_search_text'] ?? json['imageSearchText'],
      ),
      row: (json['row'] as num?)?.toInt() ?? 0,
      col: (json['col'] as num?)?.toInt() ?? 0,
      speechText: TapInterfaceCategory._nullableString(json['speech_text']),
      imageUrl: TapInterfaceCategory._nullableString(json['image_url']),
      customAudioFile: TapInterfaceCategory._nullableString(
        json['custom_audio_file'],
      ),
      actionType: TapInterfaceCategory._nullableString(json['action_type']),
      afterSelection: (() {
        final v = (json['after_selection'] ?? 'do_nothing').toString();
        // 'use_ai' is only ever a transient backend value that exists before a
        // board is generated; treat it as 'do_nothing' so stale disk-cached
        // values never re-trigger AI board generation.
        return v == 'use_ai' ? 'do_nothing' : v;
      })(),
      targetBoardId: TapInterfaceCategory._nullableString(
        json['target_board_id'] ?? json['targetBoardId'],
      ),
      temporaryNavigation: TapInterfaceCategory._parseHidden(
        json['temporary_navigation'] ?? json['temporaryNavigation'],
      ),
      backgroundColor: TapInterfaceCategory._nullableString(
        json['background_color'],
      ),
      textColor: TapInterfaceCategory._nullableString(json['text_color']),
      hidden: TapInterfaceCategory._parseHidden(
        json['hidden'] ?? json['is_hidden'] ?? json['isHidden'],
      ),
      modifierTriggerId: (json['modifier_trigger_id'] as num?)?.toInt(),
      modifierVariants: (json['modifier_variants'] is Map<String, dynamic>)
          ? json['modifier_variants'] as Map<String, dynamic>
          : const {},
      buttonType: (json['button_type'] ?? 'static').toString(),
      pastTense: TapInterfaceCategory._nullableString(json['past_tense']),
      plural: TapInterfaceCategory._nullableString(json['plural']),
      poolIndex: (json['pool_index'] as num?)?.toInt(),
    );
  }

  TapBoardButton copyWith({
    String? id,
    String? text,
    String? imageSearchText,
    int? row,
    int? col,
    String? speechText,
    String? imageUrl,
    String? customAudioFile,
    String? actionType,
    String? afterSelection,
    String? targetBoardId,
    bool? temporaryNavigation,
    String? backgroundColor,
    String? textColor,
    bool? hidden,
    int? modifierTriggerId,
    Map<String, dynamic>? modifierVariants,
    String? buttonType,
    String? pastTense,
    String? plural,
    int? poolIndex,
  }) {
    return TapBoardButton(
      id: id ?? this.id,
      text: text ?? this.text,
      imageSearchText: imageSearchText ?? this.imageSearchText,
      row: row ?? this.row,
      col: col ?? this.col,
      speechText: speechText ?? this.speechText,
      imageUrl: imageUrl ?? this.imageUrl,
      customAudioFile: customAudioFile ?? this.customAudioFile,
      actionType: actionType ?? this.actionType,
      afterSelection: afterSelection ?? this.afterSelection,
      targetBoardId: targetBoardId ?? this.targetBoardId,
      temporaryNavigation: temporaryNavigation ?? this.temporaryNavigation,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      hidden: hidden ?? this.hidden,
      modifierTriggerId: modifierTriggerId ?? this.modifierTriggerId,
      modifierVariants: modifierVariants ?? this.modifierVariants,
      buttonType: buttonType ?? this.buttonType,
      pastTense: pastTense ?? this.pastTense,
      plural: plural ?? this.plural,
      poolIndex: poolIndex ?? this.poolIndex,
    );
  }

  bool get isNavigationButton =>
      (actionType == 'navigate' || afterSelection == 'navigate') &&
      targetBoardId != null &&
      targetBoardId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'image_search_text': imageSearchText,
    'row': row,
    'col': col,
    'speech_text': speechText,
    'image_url': imageUrl,
    'custom_audio_file': customAudioFile,
    'action_type': actionType,
    'after_selection': afterSelection,
    'target_board_id': targetBoardId,
    'temporary_navigation': temporaryNavigation,
    'background_color': backgroundColor,
    'text_color': textColor,
    'hidden': hidden,
    'modifier_trigger_id': modifierTriggerId,
    'modifier_variants': modifierVariants,
    'button_type': buttonType,
    'past_tense': pastTense,
    'plural': plural,
    'pool_index': poolIndex,
  };
}

class TapBoard {
  final String id;
  final String label;
  final String boardType;
  final String? llmPrompt;
  final String? promptCategory;
  final String? promptTopic;
  final String? promptExamples;
  final String? promptExclusions;
  final String? staticOptions;
  final String? speechText;
  final String? imageUrl;
  final String? customAudioFile;
  final String? backgroundColor;
  final String? textColor;
  final int defaultColumns;
  final int maxRows;
  final int? dynamicRows;
  final bool hidden;
  final bool createdDuringMigration;
  final List<TapBoardButton> buttons;

  const TapBoard({
    required this.id,
    required this.label,
    required this.boardType,
    this.llmPrompt,
    this.promptCategory,
    this.promptTopic,
    this.promptExamples,
    this.promptExclusions,
    this.staticOptions,
    this.speechText,
    this.imageUrl,
    this.customAudioFile,
    this.backgroundColor,
    this.textColor,
    this.defaultColumns = 12,
    this.maxRows = 7,
    this.dynamicRows,
    this.hidden = false,
    this.createdDuringMigration = false,
    this.buttons = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'board_type': boardType,
    'llm_prompt': llmPrompt,
    'prompt_category': promptCategory,
    'prompt_topic': promptTopic,
    'prompt_examples': promptExamples,
    'prompt_exclusions': promptExclusions,
    'static_options': staticOptions,
    'speech_text': speechText,
    'image_url': imageUrl,
    'custom_audio_file': customAudioFile,
    'background_color': backgroundColor,
    'text_color': textColor,
    'default_columns': defaultColumns,
    'max_rows': maxRows,
    'dynamic_rows': dynamicRows,
    'hidden': hidden,
    'created_during_migration': createdDuringMigration,
    'buttons': buttons.map((b) => b.toJson()).toList(),
  };

  factory TapBoard.fromJson(Map<String, dynamic> json) {
    return TapBoard(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      boardType: (json['board_type'] ?? 'ai').toString(),
      llmPrompt: TapInterfaceCategory._nullableString(json['llm_prompt']),
      promptCategory: TapInterfaceCategory._nullableString(
        json['prompt_category'],
      ),
      promptTopic: TapInterfaceCategory._nullableString(json['prompt_topic']),
      promptExamples: TapInterfaceCategory._nullableString(
        json['prompt_examples'],
      ),
      promptExclusions: TapInterfaceCategory._nullableString(
        json['prompt_exclusions'],
      ),
      staticOptions: TapInterfaceCategory._nullableString(
        json['static_options'],
      ),
      speechText: TapInterfaceCategory._nullableString(json['speech_text']),
      imageUrl: TapInterfaceCategory._nullableString(json['image_url']),
      customAudioFile: TapInterfaceCategory._nullableString(
        json['custom_audio_file'],
      ),
      backgroundColor: TapInterfaceCategory._nullableString(
        json['background_color'],
      ),
      textColor: TapInterfaceCategory._nullableString(json['text_color']),
      defaultColumns: (json['default_columns'] as num?)?.toInt() ?? 12,
      maxRows: (json['max_rows'] as num?)?.toInt() ?? 7,
      dynamicRows: (json['dynamic_rows'] as num?)?.toInt(),
      hidden: TapInterfaceCategory._parseHidden(
        json['hidden'] ?? json['is_hidden'] ?? json['isHidden'],
      ),
      createdDuringMigration: TapInterfaceCategory._parseHidden(
        json['created_during_migration'],
      ),
      buttons: (json['buttons'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TapBoardButton.fromJson)
          .toList(),
    );
  }
}

class TapBoardSettings {
  final String? homeBoardId;

  const TapBoardSettings({this.homeBoardId});

  Map<String, dynamic> toJson() => {
    'home_board_id': homeBoardId,
  };

  factory TapBoardSettings.fromJson(Map<String, dynamic> json) {
    return TapBoardSettings(
      homeBoardId: TapInterfaceCategory._nullableString(
        json['home_board_id'] ?? json['homeBoardId'],
      ),
    );
  }
}

class TapBoardsResponse {
  final List<TapBoard> boards;
  final TapBoardSettings boardSettings;

  const TapBoardsResponse({required this.boards, required this.boardSettings});

  static List<dynamic> _extractBoardsList(Map<String, dynamic> json) {
    final topLevel = json['boards'];
    if (topLevel is List<dynamic>) return topLevel;

    final boardsConfig = json['boards_config'];
    if (boardsConfig is Map<String, dynamic>) {
      final nestedBoards = boardsConfig['boards'];
      if (nestedBoards is List<dynamic>) return nestedBoards;
    }

    return const <dynamic>[];
  }

  static Map<String, dynamic> _extractBoardSettings(Map<String, dynamic> json) {
    final topLevel = json['board_settings'];
    if (topLevel is Map<String, dynamic>) return topLevel;

    final boardsConfig = json['boards_config'];
    if (boardsConfig is Map<String, dynamic>) {
      final nestedSettings = boardsConfig['board_settings'];
      if (nestedSettings is Map<String, dynamic>) return nestedSettings;
    }

    final menuConfig = json['menu_config'];
    if (menuConfig is Map<String, dynamic>) {
      final fallbackSettings = menuConfig['board_settings'];
      if (fallbackSettings is Map<String, dynamic>) return fallbackSettings;
    }

    return const <String, dynamic>{};
  }

  Map<String, dynamic> toJson() => {
    'boards': boards.map((b) => b.toJson()).toList(),
    'board_settings': boardSettings.toJson(),
  };

  factory TapBoardsResponse.fromJson(Map<String, dynamic> json) {
    return TapBoardsResponse(
      boards: _extractBoardsList(json)
          .whereType<Map<String, dynamic>>()
          .map(TapBoard.fromJson)
          .toList(),
      boardSettings: TapBoardSettings.fromJson(_extractBoardSettings(json)),
    );
  }
}

class TapInterfaceConfig {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final String createdAt;
  final String updatedAt;
  final List<TapInterfaceCategory> buttons;

  TapInterfaceConfig({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.buttons,
  });

  factory TapInterfaceConfig.fromJson(Map<String, dynamic> json) {
    return TapInterfaceConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      buttons: (json['buttons'] as List<dynamic>? ?? [])
          .map((button) => TapInterfaceCategory.fromJson(button))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'is_active': isActive,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'buttons': buttons.map((b) => b.toJson()).toList(),
  };
}

class TapInterfaceService {
  final UserSettingsProvider userSettingsProvider;

  // Backup endpoint used only when production primary host is slow/unavailable.
  static const String _prodApiBackupUrl =
      'https://bravo-aac-api-222892987413.us-central1.run.app';
  // A/B toggle: when false, rely on backend locale handling only.
  static const bool _clientWordTranslationFallbackEnabled = false;
  static const int _maxWordTranslationCacheEntries = 1500;
  final Map<String, String> _wordTranslationCache = <String, String>{};

  TapInterfaceService({required this.userSettingsProvider});

  List<String> _tapApiCandidates(String path) {
    final primary = '${EnvironmentConfig.apiBaseUrl}$path';
    if (EnvironmentConfig.currentEnvironment != Environment.prod) {
      return [primary];
    }

    final backup = '$_prodApiBackupUrl$path';
    if (primary == backup) {
      return [primary];
    }

    return [primary, backup];
  }

  String _translationCacheKey(String locale, String text) {
    return '${locale.toLowerCase()}::${text.toLowerCase()}';
  }

  void _rememberWordTranslation(String locale, String source, String translated) {
    final sourceKey = _translationCacheKey(locale, source);
    _wordTranslationCache[sourceKey] = translated;

    // Keep memory bounded; Map preserves insertion order.
    while (_wordTranslationCache.length > _maxWordTranslationCacheEntries) {
      _wordTranslationCache.remove(_wordTranslationCache.keys.first);
    }
  }

  bool _isNonEnglishLocale(String locale) {
    return !locale.toLowerCase().startsWith('en');
  }

  String _languageNameFromLocale(String locale) {
    final normalized = locale.toLowerCase();
    if (normalized.startsWith('es')) return 'Spanish';
    if (normalized.startsWith('fr')) return 'French';
    if (normalized.startsWith('pt')) return 'Portuguese';
    if (normalized.startsWith('de')) return 'German';
    if (normalized.startsWith('it')) return 'Italian';
    if (normalized.startsWith('zh')) return 'Chinese';
    if (normalized.startsWith('ja')) return 'Japanese';
    if (normalized.startsWith('ko')) return 'Korean';
    if (normalized.startsWith('ar')) return 'Arabic';
    if (normalized.startsWith('ru')) return 'Russian';
    return locale;
  }

  String _buildTapLanguageDirective(String locale) {
    if (!_isNonEnglishLocale(locale)) return '';
    final languageName = _languageNameFromLocale(locale);
    return '\nCRITICAL: Generate ALL content entirely in $languageName (locale: $locale). Do NOT use English.\n';
  }

  List<Map<String, String>> _phraseFallbackOptionsForLocale(String locale) {
    final normalized = locale.toLowerCase();
    if (normalized.startsWith('es')) {
      return const [
        {'summary': 'Intenta de nuevo', 'fullText': 'Intenta de nuevo'},
        {'summary': 'Algo mas', 'fullText': 'Algo mas'},
        {'summary': 'Regresar', 'fullText': 'Regresar'},
      ];
    }

    return const [
      {'summary': 'Try again', 'fullText': 'Try again'},
      {'summary': 'Something else', 'fullText': 'Something else'},
      {'summary': 'Go back', 'fullText': 'Go back'},
    ];
  }

  bool _looksLikeEnglishLeak(List<String> options, String locale) {
    if (!_isNonEnglishLocale(locale) || options.isEmpty) return false;

    const englishHints = {
      'want',
      'need',
      'like',
      'more',
      'please',
      'yes',
      'no',
      'okay',
      'ok',
      'stop',
      'again',
      'good',
      'bad',
      'happy',
      'sad',
      'tired',
      'this',
      'that',
      'there',
      'now',
      'later',
      'with',
      'my',
      'to',
      'the',
      'for',
      'and',
      'eat',
      'drink',
      'sleep',
      'everyone',
      'grandmother',
    };

    var englishLikeLines = 0;
    for (final option in options) {
      final tokens = option
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty) continue;

      final englishTokenHits =
          tokens.where((t) => englishHints.contains(t)).length;
      final ratio = englishTokenHits / tokens.length;
      if (ratio >= 0.6 || englishTokenHits >= 2) {
        englishLikeLines++;
      }
    }

    final threshold = options.length >= 12 ? 5 : 3;
    return englishLikeLines >= threshold;
  }

  bool _shouldAttemptWordTranslation(List<String> words, String userLanguage) {
    return _isNonEnglishLocale(userLanguage) && words.isNotEmpty;
  }

  Future<List<String>> _translateWordListIfNeeded(
    List<String> words,
    String userLanguage,
  ) async {
    if (!_clientWordTranslationFallbackEnabled) {
      return words;
    }

    if (!_shouldAttemptWordTranslation(words, userLanguage)) {
      return words;
    }

    try {
      final locale = userLanguage.toLowerCase();
      final result = List<String>.filled(words.length, '');
      final uncachedWordIndexes = <String, List<int>>{};

      for (var i = 0; i < words.length; i++) {
        final source = _normalizeOptionText(words[i]);
        if (source.isEmpty) {
          result[i] = words[i];
          continue;
        }

        final cached = _wordTranslationCache[_translationCacheKey(locale, source)];
        if (cached != null && cached.trim().isNotEmpty) {
          result[i] = cached;
        } else {
          result[i] = source;
          uncachedWordIndexes.putIfAbsent(source, () => <int>[]).add(i);
        }
      }

      if (uncachedWordIndexes.isEmpty) {
        debugPrint(
          '[TapInterfaceService] Translation cache hit for ${words.length} words ($userLanguage).',
        );
        return result;
      }

      debugPrint(
        '[TapInterfaceService] Applying translation fallback for non-English locale ($userLanguage): ${uncachedWordIndexes.length} uncached unique words.',
      );

      final uncachedWords = uncachedWordIndexes.keys.toList();

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/translate-lines',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'lines': uncachedWords,
          'source_locale': 'en-US',
          'target_locale': userLanguage,
        }),
        timeoutSeconds: 20,
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[TapInterfaceService] Word translation fallback failed with status ${response.statusCode}. Keeping original words.',
        );
        return result;
      }

      final data = json.decode(response.body);
      final translatedLines = data['translated_lines'];
      if (translatedLines is! List) {
        debugPrint(
          '[TapInterfaceService] Word translation fallback returned invalid payload. Keeping original words.',
        );
        return result;
      }

      if (translatedLines.isEmpty) {
        debugPrint(
          '[TapInterfaceService] Word translation fallback returned empty result. Keeping original words.',
        );
        return result;
      }

      final translated = translatedLines
          .map((line) => _normalizeOptionText(line?.toString() ?? ''))
          .toList();

      final translatedCount = translated.length < uncachedWords.length
          ? translated.length
          : uncachedWords.length;
      for (var i = 0; i < translatedCount; i++) {
        final source = uncachedWords[i];
        final localized = translated[i].trim().isNotEmpty ? translated[i] : source;
        _rememberWordTranslation(locale, source, localized);
        for (final idx in uncachedWordIndexes[source] ?? const <int>[]) {
          result[idx] = localized;
        }
      }

      final comparableCount = words.length < result.length
          ? words.length
          : result.length;
      var unchangedCount = 0;
      for (var i = 0; i < comparableCount; i++) {
        final original = _normalizeOptionText(words[i]).toLowerCase().trim();
        final localized = _normalizeOptionText(result[i]).toLowerCase().trim();
        if (original.isNotEmpty && original == localized) {
          unchangedCount++;
        }
      }
      if (_isNonEnglishLocale(userLanguage) && unchangedCount >= 3) {
        debugPrint(
          '[TapInterfaceService] Translation fallback returned mostly unchanged text for $userLanguage ($unchangedCount/$comparableCount). Backend may already be returning source-language words or translation endpoint may be bypassing locale conversion.',
        );
      }

      debugPrint(
        '[TapInterfaceService] Word translation fallback applied. First 10 translated: ${result.take(10).toList()}',
      );
      return result;
    } catch (e) {
      debugPrint(
        '[TapInterfaceService] Word translation fallback exception: $e. Keeping original words.',
      );
      return words;
    }
  }

  Future<List<String>> localizeWordListForUserLocale({
    required List<String> words,
    String? localeOverride,
  }) async {
    final targetLocale =
        localeOverride ?? userSettingsProvider.settings?.userLanguage ?? 'en-US';
    return _translateWordListIfNeeded(words, targetLocale);
  }

  Future<List<Map<String, dynamic>>> _localizeWordResultTextsIfNeeded(
    List<Map<String, dynamic>> results,
    String userLanguage,
  ) async {
    if (!_isNonEnglishLocale(userLanguage) || results.isEmpty) {
      return results;
    }

    final texts = results
        .map((r) => (r['text']?.toString() ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (texts.isEmpty) return results;

    final localizedTexts = await _translateWordListIfNeeded(texts, userLanguage);
    if (localizedTexts.isEmpty) {
      return results;
    }

    final localizedResults = <Map<String, dynamic>>[];
    for (var i = 0; i < results.length; i++) {
      final updated = Map<String, dynamic>.from(results[i]);
      if (i < localizedTexts.length && localizedTexts[i].trim().isNotEmpty) {
        updated['text'] = localizedTexts[i];
      }
      localizedResults.add(updated);
    }

    return localizedResults;
  }

  Future<TapInterfaceConfig?> fetchTapInterfaceConfig() async {
    for (final url in _tapApiCandidates('/api/tap-interface/config')) {
      try {
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'GET',
          url,
          baseHeaders: {
            'X-User-ID': userSettingsProvider.userId ?? '',
            'Content-Type': 'application/json',
          },
          maxRetries: 0,
          timeoutSeconds: 60,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          debugPrint('[TapInterfaceService] Loaded tap config from $url');
          return TapInterfaceConfig.fromJson(data);
        }

        debugPrint(
          '[TapInterfaceService] tap config fetch failed from $url: status=${response.statusCode}',
        );
      } catch (e) {
        debugPrint('[TapInterfaceService] tap config fetch error from $url: $e');
      }
    }

    return null;
  }

  Future<TapBoardsResponse?> fetchTapBoards() async {
    for (final url in _tapApiCandidates('/api/tap-interface/boards')) {
      try {
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'GET',
          url,
          baseHeaders: {
            'X-User-ID': userSettingsProvider.userId ?? '',
            'Content-Type': 'application/json',
          },
          maxRetries: 0,
          timeoutSeconds: 60,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('[TapInterfaceService] Loaded tap boards from $url');
          return TapBoardsResponse.fromJson(data);
        }

        debugPrint(
          '[TapInterfaceService] tap boards fetch failed from $url: status=${response.statusCode}',
        );
      } catch (e) {
        debugPrint('[TapInterfaceService] tap boards fetch error from $url: $e');
      }
    }

    return null;
  }

  Future<List<Map<String, String>>> generateLLMPhraseOptions({
    required String context,
    int maxOptions = 6,
    bool requestDifferentOptions = false,
    List<String> excludeOptions = const [],
    String? currentMood,
  }) async {
    final userLanguage = userSettingsProvider.settings?.userLanguage ?? 'en-US';
    try {
      // Use the same prompt format and endpoint as main.dart
      final summaryInstruction =
          'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';

      String excludeText = '';
      if (requestDifferentOptions && excludeOptions.isNotEmpty) {
        excludeText =
            '\nDo NOT include these options I already have: ${excludeOptions.join(', ')}\n';
      }

      String moodContext = '';
      if (currentMood != null &&
          currentMood.isNotEmpty &&
          currentMood != 'No Mood Selected') {
        moodContext =
            '\nThe user is currently feeling: $currentMood. Ensure the options reflect this mood.\n';
      }

      final languageInstruction = _buildTapLanguageDirective(userLanguage);

      final promptForLLM =
          'Generate exactly $maxOptions short, single-phrase options that directly answer or respond to: "$context".\n'
          'IMPORTANT: Provide exactly $maxOptions options, no more, no less. Each option must be relevant to the context provided.\n'
          'ONLY provide options that directly relate to the context: "$context"\n'
          '${requestDifferentOptions ? 'Generate DIFFERENT options than what I already have.\n' : ''}'
          '$excludeText'
          '$moodContext'
          '$languageInstruction'
          'Do not include any introductory or concluding text.\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\n'
          'Do NOT use bullet points or dashes.\n'
          'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\n'
          '$summaryInstruction\n'
          'The "keywords" key should be a list of 1-3 simple, concrete English nouns or verbs that represent the core concepts in the phrase and can be used to find matching images. ALWAYS in English, even if the option/summary is in another language. Focus on visual, concrete concepts (like "food", "happy", "play", "home") rather than abstract words.\n'
          'Example: [{"option": "I want to go outside", "summary": "Go outside", "keywords": ["outside", "play"]}, {"option": "¿Puedo tomar agua por favor?", "summary": "Agua por favor", "keywords": ["water", "drink"]}]';

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'prompt': promptForLLM,
          'user_language': userLanguage,
          'target_locale': userLanguage,
        }),
        timeoutSeconds: 30,
      );

      print('LLM Phrase API Response: ${response.statusCode}');
      print(
        'LLM Phrase API Response Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
      );

      if (response.statusCode == 200) {
        var responseBody = response.body;

        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print('LLM Phrase API: Detected markdown code fence, stripping...');
          responseBody = responseBody
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
        }

        final dynamic decodedData = json.decode(responseBody);

        // Handle both direct list and wrapped in options key
        final List<dynamic> data = decodedData is List
            ? decodedData
            : (decodedData is Map && decodedData['options'] != null)
            ? decodedData['options']
            : [];

        print('LLM Phrase API Decoded ${data.length} items');

        final options = <Map<String, String>>[];

        for (var i = 0; i < data.length; i++) {
          var item = data[i];

          // If item is a string, try to parse it as JSON
          if (item is String) {
            final trimmed = item.trim();

            // Skip markdown artifacts
            if (trimmed.startsWith('```') ||
                trimmed == 'json' ||
                trimmed.isEmpty) {
              continue;
            }

            if (trimmed.startsWith('{')) {
              try {
                String cleaned = trimmed.endsWith(',')
                    ? trimmed.substring(0, trimmed.length - 1)
                    : trimmed;
                item = json.decode(cleaned);
              } catch (e) {
                print('LLM Phrase API: Failed to parse string as JSON: $e');
                continue;
              }
            } else {
              continue; // Skip non-JSON strings
            }
          }

          if (item is Map) {
            // Extract keywords from LLM response
            final keywords = item['keywords'];
            final keywordsString = keywords is List
                ? keywords.join('|')
                : (keywords?.toString() ?? '');

            final optionText =
                item['option']?.toString() ?? item['text']?.toString() ?? '';
            final summaryText = item['summary']?.toString() ?? optionText;

            // Skip invalid entries
            if (optionText.isEmpty ||
                optionText.startsWith('{') ||
                optionText.startsWith('```')) {
              continue;
            }

            options.add({
              'summary': summaryText,
              'fullText': optionText,
              'keywords': keywordsString,
            });
          }
        }

        print(
          'LLM Phrase API Extracted Options with Keywords (${options.length}): ${options.take(5).map((o) => o['fullText']).toList()}',
        );
        return options;
      }

      print('Failed to generate LLM phrase options: ${response.statusCode}');
      return _phraseFallbackOptionsForLocale(userLanguage);
    } catch (e) {
      print('Error in generateLLMPhraseOptions: $e');
      return _phraseFallbackOptionsForLocale(userLanguage);
    }
  }

  // Keep the old method for backward compatibility
  Future<List<String>> generateLLMOptions({
    required String llmPrompt,
    required String categoryLabel,
    int maxOptions = 20,
  }) async {
    try {
      final phraseOptions = await generateLLMPhraseOptions(
        context: categoryLabel,
        maxOptions: maxOptions,
      );
      return phraseOptions.map((option) => option['fullText'] ?? '').toList();
    } catch (e) {
      print('Error in generateLLMOptions wrapper: $e');
      return [];
    }
  }

  Future<List<String>> generateCategoryWords({
    required String category,
    String buildSpaceContent = '',
    List<String> excludeWords = const [],
    int maxOptions = 27,
    bool requestDifferentOptions = false,
    String? currentMood,
    String? customPrompt,
  }) async {
    final userLanguage = userSettingsProvider.settings?.userLanguage ?? 'en-US';
    try {
      print('🎯 TapInterfaceService - generateCategoryWords called with:');
      print('   category: "$category"');
      print(
        '   MOOD CHECK: category contains "feeling"? ${category.contains('feeling')}',
      );
      print('   buildSpaceContent: "$buildSpaceContent"');
      print('   excludeWords: $excludeWords');
      print('   maxOptions: $maxOptions');
      print('   currentMood: $currentMood');

      // Extract mood from category if present, or use passed mood
      String? extractedMood = currentMood;
      if (extractedMood == null && category.contains('feeling')) {
        // Extract mood from "feeling X" pattern
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(category);
        extractedMood = moodMatch?.group(1);
      }

      print('   Final mood for category: $extractedMood');

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words',
        baseHeaders: {
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'category': category,
          'build_space_content': buildSpaceContent,
          'exclude_words': excludeWords,
          'request_different_options': requestDifferentOptions,
          'current_mood': extractedMood,
          'user_language': userLanguage,
          'target_locale': userLanguage,
          'max_options': maxOptions,
          if (customPrompt != null && customPrompt.isNotEmpty)
            'custom_prompt': customPrompt,
        }),
      );

      print('Category Words API Response: ${response.statusCode}');
      print('Category Words API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Category Words API Parsed Data: $data');

        final rawWords = data['words'] ?? [];
        print('Category Words API Raw Words: $rawWords');

        final words = rawWords
            .map<String>((word) {
              String raw;
              if (word is String) {
                raw = word;
              } else if (word is Map<String, dynamic>) {
                raw =
                    word['text']?.toString() ??
                    word['word']?.toString() ??
                    word.toString();
              } else {
                raw = word.toString();
              }
              return _normalizeOptionText(raw);
            })
            .where((text) {
              final trimmedText = text.trim();
              return trimmedText.isNotEmpty &&
                  trimmedText.length > 0 &&
                  !trimmedText.contains('here are') &&
                  trimmedText.length <= 50;
            })
            .toList();

        print('Category Words API Final Words: $words');

        final localizedWords = await _translateWordListIfNeeded(
          words,
          userLanguage,
        );

        // CRITICAL FIX: Apply client-side exclusion filtering since API exclusions aren't working properly
        if (requestDifferentOptions && excludeWords.isNotEmpty) {
          print(
            '🔧 Applying CLIENT-SIDE exclusion filtering for category words...',
          );
          print('   Original API words count: ${localizedWords.length}');
          print(
            '   Excluding words: ${excludeWords.take(5).toList()}${excludeWords.length > 5 ? '...' : ''}',
          );

          // Create case-insensitive exclusion set for better matching
          final excludeSet = excludeWords
              .map((e) => e.toLowerCase().trim())
              .toSet();

          // Filter out excluded words
          final filteredWords = localizedWords.where((word) {
            final wordLower = word.toLowerCase().trim();
            final shouldExclude = excludeSet.contains(wordLower);
            if (shouldExclude) {
              print(
                '   🚫 Excluding: "$word" (matches excluded "${excludeWords.firstWhere((e) => e.toLowerCase().trim() == wordLower, orElse: () => wordLower)}")',
              );
            }
            return !shouldExclude;
          }).toList();

          print(
            '   After client-side exclusion: ${filteredWords.length} words',
          );
          print(
            '   First 10 after exclusion: ${filteredWords.take(10).toList()}',
          );

          // If we have too few words after exclusion, supplement with category-appropriate alternatives
          if (filteredWords.length < maxOptions ~/ 2) {
            print(
              '   ⚡ Too few words after exclusion (${filteredWords.length}), adding category alternatives...',
            );

            // Generate category-specific alternatives based on the category
            List<String> categoryAlternatives = [];
            final categoryLower = category.toLowerCase();

            // Check for vacation/travel related
            if (categoryLower.contains('vacation') ||
                categoryLower.contains('travel') ||
                categoryLower.contains('destination') ||
                categoryLower.contains('holiday')) {
              categoryAlternatives = [
                'Hawaii',
                'Florida',
                'California',
                'Colorado',
                'Texas',
                'New York',
                'Alaska',
                'Arizona',
                'beach',
                'mountains',
                'forest',
                'lake',
                'ocean',
                'island',
                'resort',
                'hotel',
                'cabin',
                'campground',
                'cruise',
                'Disney',
                'theme park',
                'zoo',
                'aquarium',
                'museum',
                'city',
                'country',
                'Europe',
                'Mexico',
                'Canada',
              ];
            }
            // Check for places/locations
            else if (categoryLower.contains('place') ||
                categoryLower.contains('location') ||
                categoryLower.contains('where') ||
                categoryLower.contains('go')) {
              categoryAlternatives = [
                'home',
                'park',
                'school',
                'store',
                'restaurant',
                'library',
                'playground',
                'pool',
                'gym',
                'mall',
                'theater',
                'hospital',
                'church',
                'downtown',
                'neighborhood',
                'garden',
                'beach',
                'mountains',
                'lake',
                'river',
                'forest',
              ];
            }
            // Food related
            else if (categoryLower.contains('food') ||
                categoryLower.contains('meal') ||
                categoryLower.contains('eat') ||
                categoryLower.contains('snack')) {
              categoryAlternatives = [
                'pizza',
                'burger',
                'sandwich',
                'salad',
                'pasta',
                'chicken',
                'fish',
                'steak',
                'soup',
                'fruit',
                'vegetables',
                'dessert',
                'ice cream',
                'cake',
                'cookies',
                'chips',
                'popcorn',
                'yogurt',
                'cheese',
                'bread',
              ];
            } else if (categoryLower.contains('feeling') ||
                categoryLower.contains('emotion')) {
              categoryAlternatives = [
                'excited',
                'thrilled',
                'peaceful',
                'curious',
                'hopeful',
                'determined',
                'inspired',
                'grateful',
              ];
            } else if (categoryLower.contains('action') ||
                categoryLower.contains('activity') ||
                categoryLower.contains('game')) {
              categoryAlternatives = [
                'explore',
                'create',
                'discover',
                'adventure',
                'journey',
                'wander',
                'climb',
                'swim',
              ];
            } else if (categoryLower.contains('people') ||
                categoryLower.contains('family') ||
                categoryLower.contains('who')) {
              categoryAlternatives = [
                'neighbor',
                'teammate',
                'companion',
                'mentor',
                'helper',
                'visitor',
                'guest',
                'host',
              ];
            } else if (categoryLower.contains('places')) {
              categoryAlternatives = [
                'adventure',
                'journey',
                'destination',
                'hideaway',
                'sanctuary',
                'playground',
                'workshop',
                'studio',
              ];
            } else {
              categoryAlternatives = [
                'awesome',
                'amazing',
                'wonderful',
                'fantastic',
                'brilliant',
                'creative',
                'special',
                'unique',
              ];
            }

            // Add category alternatives that aren't already excluded
            for (String alternative in categoryAlternatives) {
              if (!excludeSet.contains(alternative.toLowerCase()) &&
                  !filteredWords
                      .map((e) => e.toLowerCase())
                      .contains(alternative.toLowerCase()) &&
                  filteredWords.length < maxOptions) {
                filteredWords.add(alternative);
                print('   ✨ Added category alternative: "$alternative"');
              }
            }

            print(
              '   Final count with category alternatives: ${filteredWords.length}',
            );
          }

          return filteredWords;
        }

        return localizedWords;
      }

      print('Failed to generate category words: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating category words: $e');
      return [];
    }
  }

  /// Returns words with their English keywords for image matching.
  /// The backend sends {words: [{text: "word", keywords: ["english", "keywords"]}]}.
  /// This method preserves those keywords so image search works for non-English words.
  Future<List<Map<String, dynamic>>> generateCategoryWordsWithKeywords({
    required String category,
    String buildSpaceContent = '',
    List<String> excludeWords = const [],
    int maxOptions = 27,
    bool requestDifferentOptions = false,
    String? currentMood,
    String? customPrompt,
  }) async {
    final userLanguage = userSettingsProvider.settings?.userLanguage ?? 'en-US';
    try {
      String? extractedMood = currentMood;
      if (extractedMood == null && category.contains('feeling')) {
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(category);
        extractedMood = moodMatch?.group(1);
      }

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words',
        baseHeaders: {
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'category': category,
          'build_space_content': buildSpaceContent,
          'exclude_words': excludeWords,
          'request_different_options': requestDifferentOptions,
          'current_mood': extractedMood,
          'user_language': userLanguage,
          'target_locale': userLanguage,
          'max_options': maxOptions,
          if (customPrompt != null && customPrompt.isNotEmpty)
            'custom_prompt': customPrompt,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawWords = data['words'] ?? [];

        final results = <Map<String, dynamic>>[];
        final seen = <String>{};

        for (final word in rawWords) {
          String text;
          List<String> keywords = [];

          if (word is String) {
            text = _normalizeOptionText(word);
          } else if (word is Map<String, dynamic>) {
            text = _normalizeOptionText(
              word['text']?.toString() ?? word['word']?.toString() ?? '',
            );
            final kws = word['keywords'];
            if (kws is List) {
              keywords = kws
                  .map((k) => k.toString().trim())
                  .where((k) => k.isNotEmpty)
                  .toList();
            }
          } else {
            text = _normalizeOptionText(word.toString());
          }

          if (text.isEmpty || text.length > 50 || text.contains('here are'))
            continue;
          final key = text.toLowerCase();
          if (seen.contains(key)) continue;
          seen.add(key);

          results.add({'text': text, 'keywords': keywords});
        }

        print(
          'Category Words (with keywords): ${results.length} results, first 3: ${results.take(3).map((r) => "${r['text']}→${r['keywords']}").toList()}',
        );

        final localizedTexts = await _translateWordListIfNeeded(
          results.map((r) => r['text']?.toString() ?? '').toList(),
          userLanguage,
        );

        final localizedResults = <Map<String, dynamic>>[];
        for (var i = 0; i < results.length && i < localizedTexts.length; i++) {
          localizedResults.add({
            'text': localizedTexts[i],
            'keywords': results[i]['keywords'] ?? <String>[],
          });
        }

        return localizedResults.take(maxOptions).toList();
      }

      print(
        'Failed to generate category words with keywords: ${response.statusCode}',
      );
      return [];
    } catch (e) {
      print('Error in generateCategoryWordsWithKeywords: $e');
      return [];
    }
  }

  Future<List<String>> generateFreestyleOptions({
    required String context,
    String buildSpaceText = '',
    bool singleWordsOnly = true,
    int maxOptions = 15,
    bool requestDifferentOptions = false,
    List<String> excludeOptions = const [],
    String? currentMood,
    bool didLocaleRetry = false,
  }) async {
    final userLanguage = userSettingsProvider.settings?.userLanguage ?? 'en-US';
    debugPrint('🔧🔧🔧 FREESTYLE OPTIONS SERVICE CALLED 🔧🔧🔧');
    try {
      debugPrint(
        '🔧 TapInterfaceService - generateFreestyleOptions called with:',
      );
      debugPrint('   buildSpaceText: "$buildSpaceText"');
      debugPrint('   context: "$context"');
      debugPrint('   singleWordsOnly: $singleWordsOnly');
      print('   requestDifferentOptions: $requestDifferentOptions');
      print('   excludeOptions: $excludeOptions');
      print('   excludeOptions length: ${excludeOptions.length}');
      print('   currentMood: $currentMood');

      // Extract mood from context if present, or use passed mood
      String? extractedMood = currentMood;
      if (extractedMood == null && context.contains('feeling')) {
        // Extract mood from "feeling X" pattern
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(context);
        extractedMood = moodMatch?.group(1);
      }

      // If we have a mood but no specific context, add it to context for general requests
      String effectiveContext = context;
      if (extractedMood != null &&
          extractedMood.isNotEmpty &&
          !context.contains('feeling')) {
        effectiveContext = '$context when feeling $extractedMood';
      }

      if (_isNonEnglishLocale(userLanguage)) {
        final localeDirective = _buildTapLanguageDirective(userLanguage).trim();
        if (localeDirective.isNotEmpty) {
          effectiveContext = '$effectiveContext\n$localeDirective';
        }
      }

      print('   Final mood: $extractedMood');
      print(
        '   Sending to API - source_page: "${effectiveContext.contains('feeling') ? 'Mood-Aware Words' : effectiveContext}", context: "$effectiveContext"',
      );
      print('   Full request body will include exclude_words: $excludeOptions');

      // Use the same endpoint and format as the working freestyle.js
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'build_space_text': buildSpaceText,
          'context': effectiveContext,
          'source_page': effectiveContext.contains('feeling')
              ? 'Mood-Aware Words'
              : effectiveContext,
          'is_llm_generated': false,
          'single_words_only': singleWordsOnly,
          'originating_button_text': null,
          'request_different_options': requestDifferentOptions,
          'exclude_words': excludeOptions,
          'current_mood': extractedMood,
          'max_options': maxOptions,
          'user_language':
              userSettingsProvider.settings?.userLanguage ?? 'en-US',
          'target_locale':
              userSettingsProvider.settings?.userLanguage ?? 'en-US',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      debugPrint('Freestyle API Response: ${response.statusCode}');

      // Log full response for debugging
      if (response.statusCode != 200) {
        debugPrint('❌ Freestyle API Error: Status ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }

      if (response.body.isEmpty) {
        debugPrint('❌ Freestyle API: Empty response body');
        return [];
      }

      debugPrint(
        'Freestyle API Response Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
      );

      if (response.statusCode == 200) {
        var responseBody = response.body;

        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print('Freestyle API: Detected markdown code fence, stripping...');
          responseBody = responseBody
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
        }

        final data = json.decode(responseBody);
        print('✅ Freestyle API Parsed Data Type: ${data.runtimeType}');
        print('✅ Full parsed data structure: $data');

        // Use the exact same response parsing as freestyle_page.dart
        // API sometimes returns word_options as a JSON-encoded string instead of
        // a parsed list. Normalise to a List<dynamic> before processing.
        List<dynamic> rawOptions = [];
        if (data is Map) {
          final rawField = data['word_options'];
          if (rawField is List) {
            rawOptions = rawField;
          } else if (rawField is String && rawField.isNotEmpty) {
            try {
              final decoded = json.decode(rawField);
              if (decoded is List) rawOptions = decoded;
            } catch (_) { /* leave rawOptions empty */ }
          }
        }
        debugPrint('✅ Freestyle API Raw Options length: ${rawOptions.length}');

        final options = <String>[];

        if (rawOptions.isNotEmpty) {
          for (var i = 0; i < rawOptions.length; i++) {
            final option = rawOptions[i];
            String raw = '';

            if (option is String) {
              final trimmed = option.trim();

              // Skip markdown artifacts
              if (trimmed.startsWith('```') ||
                  trimmed == 'json' ||
                  trimmed.isEmpty) {
                continue;
              }

              // Check if it's JSON-encoded string
              if (trimmed.startsWith('{')) {
                try {
                  String cleaned = trimmed.endsWith(',')
                      ? trimmed.substring(0, trimmed.length - 1)
                      : trimmed;
                  final parsed = json.decode(cleaned);
                  if (parsed is Map) {
                    raw =
                        parsed['option']?.toString() ??
                        parsed['text']?.toString() ??
                        parsed['word']?.toString() ??
                        trimmed;
                  } else {
                    raw = trimmed;
                  }
                } catch (e) {
                  raw = trimmed;
                }
              } else {
                raw = trimmed;
              }
            } else if (option is Map<String, dynamic>) {
              // Prefer named text fields; if all are null, skip this item
              // rather than calling option.toString() which gives {text: Bye, keywords: [...]}
              final extracted =
                  option['option']?.toString() ??
                  option['text']?.toString() ??
                  option['word']?.toString();
              if (extracted == null) continue;
              raw = extracted;
            } else {
              raw = option.toString();
            }

            final normalized = _normalizeOptionText(raw);
            final trimmedText = normalized.trim();

            // Filter out invalid options — covers multiple JSON/metadata leak formats:
            //   '":"'           → text":"Bye","keywords":["hello"]  (quoted keys)
            //   'keywords'      → text: Bye, keywords: [hello]      (unquoted keys)
            //   ': ['           → key: [value, ...]                 (list value)
            //   starts with '{' → full JSON object
            //   starts with '[' → JSON array (e.g. ["demo","presentation"])
            if (trimmedText.isNotEmpty &&
                trimmedText.length <= 50 &&
                !trimmedText.contains('here are') &&
                !trimmedText.startsWith('{') &&
                !trimmedText.startsWith('[') &&
                !trimmedText.contains('":"') &&
                !trimmedText.toLowerCase().contains('keywords') &&
                !trimmedText.contains(': [') &&
                !trimmedText.startsWith('```') &&
                trimmedText != 'json') {
              options.add(normalized);
            }
          }
        }

        print(
          'Freestyle API Final Options (${options.length}): ${options.take(10).toList()}',
        );

        if (options.isEmpty) {
          print('⚠️  WARNING: Freestyle API returned empty options list!');
          print('   Context: "$context"');
          print('   BuildSpace: "$buildSpaceText"');
          return [];
        }

        // CRITICAL FIX: Apply client-side exclusion filtering since API exclusions aren't working properly
        if (requestDifferentOptions && excludeOptions.isNotEmpty) {
          print('🔧 Applying CLIENT-SIDE exclusion filtering...');
          print('   Original API options count: ${options.length}');
          print(
            '   Excluding options: ${excludeOptions.take(5).toList()}${excludeOptions.length > 5 ? '...' : ''}',
          );

          // Create case-insensitive exclusion set for better matching
          final excludeSet = excludeOptions
              .map((e) => e.toLowerCase().trim())
              .toSet();

          // Filter out excluded options
          final filteredOptions = options.where((option) {
            final optionLower = option.toLowerCase().trim();
            final shouldExclude = excludeSet.contains(optionLower);
            if (shouldExclude) {
              print(
                '   🚫 Excluding: "$option" (matches excluded "${excludeOptions.firstWhere((e) => e.toLowerCase().trim() == optionLower, orElse: () => optionLower)}")',
              );
            }
            return !shouldExclude;
          }).toList();

          print(
            '   After client-side exclusion: ${filteredOptions.length} options',
          );
          print(
            '   First 10 after exclusion: ${filteredOptions.take(10).toList()}',
          );

          // If we have too few options after exclusion, supplement with context-appropriate alternatives
          if (filteredOptions.length < maxOptions ~/ 2) {
            print(
              '   ⚡ Too few options after exclusion (${filteredOptions.length}), adding context alternatives...',
            );

            List<String> contextAlternatives = [];
            final contextLower = context.toLowerCase();

            // Check for vacation/travel related
            if (contextLower.contains('vacation') ||
                contextLower.contains('travel') ||
                contextLower.contains('destination') ||
                contextLower.contains('holiday')) {
              contextAlternatives = [
                'Hawaii',
                'Florida',
                'California',
                'Colorado',
                'Texas',
                'beach',
                'mountains',
                'forest',
                'lake',
                'ocean',
                'island',
                'resort',
                'Disney',
                'cruise',
                'camping',
                'hiking',
                'swimming',
                'sightseeing',
              ];
            }
            // Check for places/locations
            else if (contextLower.contains('place') ||
                contextLower.contains('location') ||
                contextLower.contains('where')) {
              contextAlternatives = [
                'home',
                'park',
                'school',
                'store',
                'restaurant',
                'library',
                'playground',
                'pool',
                'gym',
                'mall',
                'theater',
                'downtown',
                'beach',
                'mountains',
              ];
            }
            // Food related
            else if (contextLower.contains('food') ||
                contextLower.contains('meal') ||
                contextLower.contains('eat')) {
              contextAlternatives = [
                'pizza',
                'burger',
                'sandwich',
                'salad',
                'pasta',
                'chicken',
                'fish',
                'fruit',
                'vegetables',
                'dessert',
                'ice cream',
                'cookies',
              ];
            }
            // Default creative alternatives
            else {
              contextAlternatives = [
                'awesome',
                'amazing',
                'wonderful',
                'fantastic',
                'brilliant',
                'excellent',
                'perfect',
                'great',
                'create',
                'build',
                'make',
                'design',
                'craft',
                'construct',
                'form',
                'shape',
                'adventure',
                'journey',
                'explore',
                'discover',
                'travel',
                'wander',
                'roam',
                'quest',
                'music',
                'art',
                'color',
                'paint',
                'draw',
                'sing',
                'dance',
                'rhythm',
                'family',
                'friend',
                'together',
                'share',
                'care',
                'love',
                'support',
                'connect',
                'outside',
                'nature',
                'sky',
                'sun',
                'moon',
                'stars',
                'tree',
                'flower',
                'learn',
                'teach',
                'understand',
                'explain',
                'question',
                'answer',
                'wonder',
                'imagine',
                'kind',
                'gentle',
                'brave',
                'strong',
                'smart',
                'clever',
                'wise',
                'thoughtful',
              ];
            }

            // Add context alternatives that aren't already excluded
            for (String creative in contextAlternatives) {
              if (!excludeSet.contains(creative.toLowerCase()) &&
                  !filteredOptions
                      .map((e) => e.toLowerCase())
                      .contains(creative.toLowerCase()) &&
                  filteredOptions.length < maxOptions) {
                filteredOptions.add(creative);
                print('   ✨ Added creative alternative: "$creative"');
              }
            }

            print(
              '   Final count with creative alternatives: ${filteredOptions.length}',
            );
          }

            final translatedOrOriginal = await _translateWordListIfNeeded(
              filteredOptions,
              userLanguage,
            );
            if (!didLocaleRetry &&
                _looksLikeEnglishLeak(translatedOrOriginal, userLanguage)) {
              debugPrint(
                '[TapInterfaceService] Detected likely English leak for $userLanguage. Retrying word-options with stricter locale context.',
              );
              final simplifiedBuildSpace =
                  buildSpaceText.split(RegExp(r'\s+')).length > 1
                  ? ''
                  : buildSpaceText;
              return generateFreestyleOptions(
                context:
                    '$context\nRespond only in ${_languageNameFromLocale(userLanguage)} (locale: $userLanguage).',
                buildSpaceText: simplifiedBuildSpace,
                singleWordsOnly: singleWordsOnly,
                maxOptions: maxOptions,
                requestDifferentOptions: requestDifferentOptions,
                excludeOptions: excludeOptions,
                currentMood: currentMood,
                didLocaleRetry: true,
              );
            }
            return translatedOrOriginal;
        }

        final translatedOrOriginal = await _translateWordListIfNeeded(
          options,
          userLanguage,
        );
        if (!didLocaleRetry &&
            _looksLikeEnglishLeak(translatedOrOriginal, userLanguage)) {
          debugPrint(
            '[TapInterfaceService] Detected likely English leak for $userLanguage. Retrying word-options with stricter locale context.',
          );
          final simplifiedBuildSpace =
              buildSpaceText.split(RegExp(r'\s+')).length > 1
              ? ''
              : buildSpaceText;
          return generateFreestyleOptions(
            context:
                '$context\nRespond only in ${_languageNameFromLocale(userLanguage)} (locale: $userLanguage).',
            buildSpaceText: simplifiedBuildSpace,
            singleWordsOnly: singleWordsOnly,
            maxOptions: maxOptions,
            requestDifferentOptions: requestDifferentOptions,
            excludeOptions: excludeOptions,
            currentMood: currentMood,
            didLocaleRetry: true,
          );
        }
        return translatedOrOriginal;
      }

      debugPrint(
        '❌ Failed to generate freestyle options: ${response.statusCode}',
      );
      debugPrint('   Response body: ${response.body}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ ERROR in generateFreestyleOptions: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Freestyle options with English keyword hints for image matching.
  /// Returns [{text, keywords}] — same contract as generateCategoryWordsWithKeywords.
  /// Keywords may be empty [] if the backend doesn't include them for a given word.
  Future<List<Map<String, dynamic>>> generateFreestyleOptionsWithKeywords({
    required String context,
    String buildSpaceText = '',
    bool singleWordsOnly = true,
    int maxOptions = 15,
    bool requestDifferentOptions = false,
    List<String> excludeOptions = const [],
    String? currentMood,
  }) async {
    final userLanguage = userSettingsProvider.settings?.userLanguage ?? 'en-US';
    try {
      String? extractedMood = currentMood;
      if (extractedMood == null && context.contains('feeling')) {
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(context);
        extractedMood = moodMatch?.group(1);
      }

      String effectiveContext = context;
      if (extractedMood != null &&
          extractedMood.isNotEmpty &&
          !context.contains('feeling')) {
        effectiveContext = '$context when feeling $extractedMood';
      }

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'build_space_text': buildSpaceText,
          'context': effectiveContext,
          'source_page': effectiveContext,
          'is_llm_generated': false,
          'single_words_only': singleWordsOnly,
          'originating_button_text': null,
          'request_different_options': requestDifferentOptions,
          'exclude_words': excludeOptions,
          'current_mood': extractedMood,
          'max_options': maxOptions,
          'user_language': userLanguage,
          'target_locale': userLanguage,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode == 200) {
        var responseBody = response.body;
        if (responseBody.contains('```json')) {
          responseBody = responseBody
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
        }

        final data = json.decode(responseBody);
        final rawOptions = data['word_options'] ?? [];
        final results = <Map<String, dynamic>>[];
        final seen = <String>{};

        if (rawOptions is List) {
          for (final option in rawOptions) {
            String text = '';
            List<String> keywords = [];

            if (option is Map<String, dynamic>) {
              text = _normalizeOptionText(
                option['option']?.toString() ??
                    option['text']?.toString() ??
                    option['word']?.toString() ??
                    '',
              );
              final kws = option['keywords'];
              if (kws is List) {
                keywords = kws
                    .map((k) => k.toString().trim())
                    .where((k) => k.isNotEmpty)
                    .toList();
              }
            } else if (option is String) {
              final trimmed = option.trim();
              if (trimmed.startsWith('{')) {
                try {
                  final parsed = json.decode(
                    trimmed.endsWith(',')
                        ? trimmed.substring(0, trimmed.length - 1)
                        : trimmed,
                  );
                  if (parsed is Map<String, dynamic>) {
                    text = _normalizeOptionText(
                      parsed['option']?.toString() ??
                          parsed['text']?.toString() ??
                          parsed['word']?.toString() ??
                          trimmed,
                    );
                    final kws = parsed['keywords'];
                    if (kws is List) {
                      keywords = kws
                          .map((k) => k.toString().trim())
                          .where((k) => k.isNotEmpty)
                          .toList();
                    }
                  }
                } catch (_) {
                  text = _normalizeOptionText(trimmed);
                }
              } else {
                text = _normalizeOptionText(trimmed);
              }
            } else {
              text = _normalizeOptionText(option.toString());
            }

            if (text.isEmpty || text.length > 50 || text.contains('here are'))
              continue;
            final key = text.toLowerCase();
            if (seen.contains(key)) continue;
            seen.add(key);
            results.add({'text': text, 'keywords': keywords});
          }
        }

        final localizedResults = await _localizeWordResultTextsIfNeeded(
          results,
          userLanguage,
        );
        return localizedResults.take(maxOptions).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error in generateFreestyleOptionsWithKeywords: $e');
      return [];
    }
  }

  /// Generate options using the simple /api/generate-options endpoint (like the web app)
  /// This is better for answering specific questions than the freestyle endpoint
  Future<List<String>> generateDirectOptions({
    required String prompt,
    int maxOptions = 18,
  }) async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/generate-options',
        baseHeaders: {
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': prompt, 'count': maxOptions}),
      );

      print('Direct Options API Response: ${response.statusCode}');
      print('Direct Options API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        var responseBody = response.body;

        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print(
            'Direct Options API: Detected markdown code fence, stripping...',
          );
          responseBody = responseBody
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          print(
            'Direct Options API: After stripping fences: ${responseBody.substring(0, responseBody.length > 200 ? 200 : responseBody.length)}',
          );
        }

        final data = json.decode(responseBody);
        print('Direct Options API Decoded Data Type: ${data.runtimeType}');

        List<dynamic> rawOptions = [];

        // Handle different response formats
        if (data is Map && data['options'] != null) {
          rawOptions = data['options'] as List<dynamic>;
        } else if (data is List) {
          rawOptions = data;
        }

        print('Direct Options API Raw Options Count: ${rawOptions.length}');

        final List<String> options = [];
        for (var i = 0; i < rawOptions.length; i++) {
          final option = rawOptions[i];

          if (option is String) {
            final trimmed = option.trim();

            // Skip empty strings, commas, brackets, markdown artifacts
            if (trimmed.isEmpty ||
                trimmed == ',' ||
                trimmed == '[' ||
                trimmed == ']' ||
                trimmed.startsWith('```') ||
                trimmed == 'json') {
              continue;
            }

            // Check if it's a JSON-encoded string like "{\"option\": \"text\"}"
            if (trimmed.startsWith('{')) {
              try {
                // Remove trailing comma if present
                String cleaned = trimmed;
                if (cleaned.endsWith(',')) {
                  cleaned = cleaned.substring(0, cleaned.length - 1);
                }

                final parsed = json.decode(cleaned);

                // Extract the actual text from the parsed object
                if (parsed is Map) {
                  final text =
                      parsed['option']?.toString().trim() ??
                      parsed['text']?.toString().trim() ??
                      parsed['word']?.toString().trim() ??
                      trimmed;
                  if (text.isNotEmpty &&
                      !text.startsWith('{') &&
                      !text.startsWith('```')) {
                    options.add(text);
                  }
                } else {
                  if (!trimmed.startsWith('```')) {
                    options.add(trimmed);
                  }
                }
              } catch (e) {
                print('Direct Options API Failed to parse as JSON: $e');
                // If parsing fails and it's not markdown, use the string as-is
                if (!trimmed.startsWith('```')) {
                  options.add(trimmed);
                }
              }
            } else {
              // Not JSON, use as-is (but skip markdown)
              if (!trimmed.startsWith('```')) {
                options.add(trimmed);
              }
            }
          } else if (option is Map) {
            // Already a parsed object, extract the text field
            final text =
                option['option']?.toString().trim() ??
                option['text']?.toString().trim() ??
                option['word']?.toString().trim() ??
                option.toString().trim();
            if (text.isNotEmpty &&
                !text.startsWith('{') &&
                !text.startsWith('```')) {
              options.add(text);
            }
          } else {
            // Other type, convert to string
            final text = option.toString().trim();
            if (text.isNotEmpty && !text.startsWith('```')) {
              options.add(text);
            }
          }
        }

        final filteredOptions = options
            .where(
              (option) =>
                  option.isNotEmpty &&
                  !option.startsWith('{') &&
                  !option.contains('option":') &&
                  !option.startsWith('```') &&
                  option != 'json',
            )
            .toList();

        // Normalize to single-word options only (Words section expects single tokens)
        final cleanedOptions = filteredOptions
            .map(_normalizeSingleWordOption)
            .where((option) => option.isNotEmpty)
            .toList();

        print(
          'Direct Options API Final Extracted Options (${cleanedOptions.length}): ${cleanedOptions.take(10).toList()}',
        );
        return cleanedOptions;
      }

      print('Failed to generate direct options: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating direct options: $e');
      return [];
    }
  }

  /// Generate word options for text completion using a custom prompt
  /// This method is used when a category has a wordsPrompt defined
  Future<List<Map<String, dynamic>>> generateCustomWordOptions({
    required String prompt,
    int maxOptions = 30,
  }) async {
    try {
      final userLanguage =
          userSettingsProvider.settings?.userLanguage ?? 'en-US';
      print('🎯 TapInterfaceService - generateCustomWordOptions called with:');
      print('   prompt: "$prompt"');
      print('   maxOptions: $maxOptions');

      // Note: Mood context support can be added later if needed
      String moodContext = '';

      print('Using custom words prompt for text completion');

      // Create intelligent prompt based on the type of starter word
      String intelligentPrompt = _createIntelligentPrompt(
        prompt,
        maxOptions,
        moodContext,
      );
      final languageInstruction = _buildTapLanguageDirective(userLanguage);
      if (languageInstruction.isNotEmpty) {
        intelligentPrompt =
            '$intelligentPrompt\n$languageInstruction\nIMPORTANT: Keep "keywords" in English for image matching, but keep "option" and "summary" in locale $userLanguage.';
      }

      // Use the /llm endpoint like the web app does
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({'prompt': intelligentPrompt}),
        timeoutSeconds: 30,
      );

      print('Custom Words LLM Response: ${response.statusCode}');
      print('Custom Words LLM Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Custom Words LLM Parsed Data: $data');

        // Convert LLM response format to words format with keywords preserved
        final words = <Map<String, dynamic>>[];
        if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic> && item['option'] != null) {
              final optionText = item['option'].toString().trim();
              if (optionText.isNotEmpty &&
                  !optionText.toLowerCase().contains('here are') &&
                  optionText != prompt &&
                  optionText.length <= 50) {
                // Remove the original prompt from the beginning if it exists
                String cleanedOption = _removePromptFromOption(
                  optionText,
                  prompt,
                );
                final normalizedText = _normalizeOptionText(cleanedOption);

                // Extract keywords from the LLM response, prioritizing nouns for image matching
                List<String> keywords = [];
                if (item['keywords'] != null) {
                  if (item['keywords'] is List) {
                    keywords = (item['keywords'] as List)
                        .map((k) => k.toString())
                        .toList();
                  } else if (item['keywords'] is String) {
                    keywords = [item['keywords'].toString()];
                  }
                }

                // If no keywords provided, extract potential nouns from the text as fallback
                if (keywords.isEmpty) {
                  keywords = _extractImageKeywords(normalizedText);
                  print(
                    'Generated fallback keywords for "$normalizedText": $keywords',
                  );
                }

                words.add({
                  'text': normalizedText,
                  'summary': item['summary']?.toString() ?? normalizedText,
                  'keywords': keywords,
                });
              }
            }
          }
        }

        final localizedWords = await _localizeWordResultTextsIfNeeded(
          words,
          userLanguage,
        );

        print(
          'Custom Words LLM Final Words: ${localizedWords.length} items with keywords',
        );
        return localizedWords;
      }

      print('Failed to generate custom word options: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating custom word options: $e');
      return [];
    }
  }

  /// Create an intelligent prompt based on the starter word type
  String _createIntelligentPrompt(
    String prompt,
    int maxOptions,
    String moodContext,
  ) {
    final promptLower = prompt.toLowerCase().trim();

    // Question words that should generate meaningful question continuations
    if (promptLower == 'who') {
      return 'Generate $maxOptions different ways to complete the question "Who..." with logical, meaningful continuations$moodContext. Examples: "is at the door", "called me", "wants to play", "is my teacher", "lives here". Each option should complete the question "Who..." to make a sensible question someone might ask. For keywords, focus on NOUNS and PEOPLE (like "teacher", "friend", "mom", "doctor") that would be good for image matching, not action words. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'what') {
      return 'Generate $maxOptions different ways to complete the question "What..." with logical, meaningful continuations$moodContext. Examples: "time is it", "are we eating", "is that sound", "happened today", "should I do". Each option should complete the question "What..." to make a sensible question someone might ask. For keywords, focus on NOUNS and OBJECTS (like "food", "sound", "time", "activity") that would be good for image matching, not action words. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'where') {
      return 'Generate $maxOptions different ways to complete the question "Where..." with logical, meaningful continuations$moodContext. Examples: "is Mom", "are we going", "did I put my keys", "is the bathroom", "should we meet". Each option should complete the question "Where..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'when') {
      return 'Generate $maxOptions different ways to complete the question "When..." with logical, meaningful continuations$moodContext. Examples: "are we leaving", "is dinner ready", "do I need to be there", "will you be back", "did this happen". Each option should complete the question "When..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'why') {
      return 'Generate $maxOptions different ways to complete the question "Why..." with logical, meaningful continuations$moodContext. Examples: "are you sad", "is this happening", "can\'t I go", "did you do that", "is it so loud". Each option should complete the question "Why..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'how') {
      return 'Generate $maxOptions different ways to complete the question "How..." with logical, meaningful continuations$moodContext. Examples: "are you feeling", "do I do this", "long will it take", "did you know", "much does it cost". Each option should complete the question "How..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'can' || promptLower == 'could') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "I help you", "we go outside", "you show me", "I have a snack", "we play together". Each option should complete the question to make a sensible request or question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'should' || promptLower == 'would') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "I call Mom", "we go home", "you like this", "I wear a jacket", "we have lunch". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'do' ||
        promptLower == 'does' ||
        promptLower == 'did') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "you want to play", "this work", "I miss anything", "you need help", "we have time". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'is' ||
        promptLower == 'are' ||
        promptLower == 'was' ||
        promptLower == 'were') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "Mom coming home", "you feeling better", "that the doorbell", "we going soon", "dinner ready". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else {
      // For non-question starters, use the original approach
      return 'Complete this sentence starter: "$prompt" with $maxOptions different continuations$moodContext. Each option should be the continuation part that comes AFTER "$prompt". Allow proper nouns, place names, and multi-word phrases (1-4 words each). Examples: if prompt is "I want to go to", generate options like "the park", "Broncos stadium", "my room". For keywords, focus on MAIN NOUNS and SUBJECTS (like "park", "stadium", "room", "burger", "salad") that represent the primary object or place, not adjectives like "big" or "light". Return as a JSON array with "option", "summary", and "keywords" keys.';
    }
  }

  /// Extract meaningful keywords for image matching, prioritizing nouns over adjectives
  List<String> _extractImageKeywords(String text) {
    // Common adjectives that should not be primary image keywords
    final adjectives = {
      'big',
      'small',
      'large',
      'little',
      'tiny',
      'huge',
      'giant',
      'mini',
      'light',
      'dark',
      'bright',
      'dim',
      'heavy',
      'soft',
      'hard',
      'rough',
      'smooth',
      'hot',
      'cold',
      'warm',
      'cool',
      'freezing',
      'burning',
      'icy',
      'fast',
      'slow',
      'quick',
      'rapid',
      'speedy',
      'sluggish',
      'old',
      'new',
      'young',
      'ancient',
      'modern',
      'fresh',
      'stale',
      'good',
      'bad',
      'great',
      'terrible',
      'awful',
      'amazing',
      'wonderful',
      'beautiful',
      'ugly',
      'pretty',
      'handsome',
      'cute',
      'adorable',
      'loud',
      'quiet',
      'noisy',
      'silent',
      'peaceful',
      'clean',
      'dirty',
      'messy',
      'tidy',
      'neat',
      'happy',
      'sad',
      'angry',
      'excited',
      'calm',
      'nervous',
      'red',
      'blue',
      'green',
      'yellow',
      'purple',
      'orange',
      'pink',
      'brown',
      'black',
      'white',
      'gray',
      'grey',
      'round',
      'square',
      'long',
      'short',
      'wide',
      'narrow',
      'thick',
      'thin',
      'wet',
      'dry',
      'damp',
      'moist',
      'soggy',
      'empty',
      'full',
      'half',
      'complete',
      'incomplete',
      'open',
      'closed',
      'broken',
      'fixed',
      'damaged',
      'cheap',
      'expensive',
      'free',
      'costly',
      'easy',
      'difficult',
      'simple',
      'complex',
      'safe',
      'dangerous',
      'risky',
      'secure',
      'funny',
      'serious',
      'silly',
      'smart',
      'clever',
      'stupid',
      'rich',
      'poor',
      'wealthy',
      'broke',
      'healthy',
      'sick',
      'ill',
      'well',
      'busy',
      'lazy',
      'active',
      'tired',
      'energetic',
    };

    // Common nouns that make good image keywords
    final goodNouns = {
      'burger',
      'salad',
      'pizza',
      'sandwich',
      'soup',
      'pasta',
      'chicken',
      'fish',
      'beef',
      'vegetables',
      'park',
      'beach',
      'stadium',
      'school',
      'hospital',
      'store',
      'restaurant',
      'library',
      'theater',
      'car',
      'bus',
      'train',
      'plane',
      'bike',
      'boat',
      'truck',
      'motorcycle',
      'dog',
      'cat',
      'bird',
      'horse',
      'elephant',
      'lion',
      'bear',
      'rabbit',
      'animal',
      'book',
      'phone',
      'computer',
      'table',
      'chair',
      'bed',
      'house',
      'door',
      'window',
      'ball',
      'game',
      'toy',
      'music',
      'movie',
      'picture',
      'photo',
      'water',
      'milk',
      'juice',
      'coffee',
      'tea',
      'soda',
      'shirt',
      'pants',
      'shoes',
      'hat',
      'jacket',
      'dress',
      'socks',
      'apple',
      'banana',
      'orange',
      'grape',
      'strawberry',
      'cookie',
      'cake',
      'bread',
      'friend',
      'family',
      'mom',
      'dad',
      'child',
      'baby',
      'person',
      'people',
      'money',
      'job',
      'work',
      'office',
      'meeting',
      'party',
      'celebration',
    };

    // Split text into words and clean them
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    List<String> keywords = [];

    // First pass: Find known good nouns
    for (final word in words) {
      if (goodNouns.contains(word)) {
        keywords.add(word);
      }
    }

    // Second pass: Add other words that aren't adjectives (potential nouns)
    for (final word in words) {
      if (!adjectives.contains(word) &&
          !goodNouns.contains(word) &&
          word.length > 2 && // Skip very short words
          !keywords.contains(word)) {
        keywords.add(word);
      }
    }

    // If we still don't have keywords, take the longest non-adjective words
    if (keywords.isEmpty) {
      final nonAdjectives =
          words
              .where((word) => !adjectives.contains(word) && word.length > 2)
              .toList()
            ..sort(
              (a, b) => b.length.compareTo(a.length),
            ); // Sort by length descending

      keywords.addAll(nonAdjectives.take(3)); // Take up to 3 longest words
    }

    // Limit to reasonable number of keywords
    return keywords.take(5).toList();
  }

  /// Remove the original prompt from the option text to get just the completion part
  String _removePromptFromOption(String optionText, String originalPrompt) {
    final optionLower = optionText.toLowerCase().trim();
    final promptLower = originalPrompt.toLowerCase().trim();

    // If the option starts with the prompt, remove it
    if (optionLower.startsWith(promptLower)) {
      String remainder = optionText.substring(originalPrompt.length).trim();
      // If there's remaining text after removing the prompt, return it
      if (remainder.isNotEmpty) {
        return remainder;
      }
    }

    // If the option doesn't start with prompt or has no remainder, return as-is
    return optionText;
  }

  /// Normalize option text by removing numbered prefixes and cleaning up formatting
  String _normalizeOptionText(String raw) {
    var text = raw.trim();
    // Remove surrounding quotes if accidentally included
    if (text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1).trim();
    }
    // Strip common numbered prefixes: "1.", "1)", "1 -", "1:"
    text = text.replaceFirst(RegExp(r'^\s*\d+\s*[\.\)\-:]\s*'), '');
    // Also strip leading bullets like "- " or "• "
    text = text.replaceFirst(RegExp(r'^[\-•]\s*'), '');
    return text.trim();
  }

  /// Normalize direct word options to a single token and drop phrase-like outputs
  String _normalizeSingleWordOption(String raw) {
    var text = _normalizeOptionText(raw);

    // Remove common LLM artifacts like "summary" or "option" prefixes
    text = text.replaceFirst(
      RegExp(r'^(summary|option|options)\b[:\-]?\s*', caseSensitive: false),
      '',
    );

    // Collapse punctuation into spaces
    text = text
        .replaceAll(RegExp(r"[^\p{L}\p{N}\-']+", unicode: true), ' ')
        .trim();

    if (text.isEmpty) return '';

    // Keep only single-word options for the Words section
    if (text.contains(RegExp(r'\s+'))) {
      return '';
    }

    // Guard against stray artifacts
    if (text.toLowerCase() == 'summary' || text.toLowerCase() == 'option') {
      return '';
    }

    return text;
  }

  /// Calls /api/tap-interface/boards/{boardId}/assign-all-images to re-assign
  /// images for every button on an existing board using the server's current
  /// key-term stripping and negation-guarding logic.  Returns a map of
  /// button id → image_url for every button that got an image; returns null
  /// on any failure so the caller can gracefully degrade.
  Future<Map<String, String?>?> assignAllImages(String boardId) async {
    if (boardId.isEmpty) return null;
    try {
      debugPrint('[TapService] 🖼️ assignAllImages for board "$boardId"');
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/boards/$boardId/assign-all-images',
        baseHeaders: {
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({'board_id': boardId}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('[TapService] ❌ assignAllImages HTTP ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Response may come as:
      //   { "buttons": [{id, image_url}, ...] }
      // or wrapped in a "board":
      //   { "board": { "buttons": [...] } }
      List<dynamic>? buttonsList;
      if (data['buttons'] is List) {
        buttonsList = data['buttons'] as List;
      } else if (data['board'] is Map) {
        final board = data['board'] as Map<String, dynamic>;
        if (board['buttons'] is List) buttonsList = board['buttons'] as List;
      }

      if (buttonsList == null) {
        debugPrint('[TapService] ❌ assignAllImages: unexpected response shape');
        return null;
      }

      final result = <String, String?>{};
      for (final raw in buttonsList) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id']?.toString();
        final url = raw['image_url']?.toString();
        if (id != null) result[id] = (url != null && url.isNotEmpty) ? url : null;
      }
      debugPrint('[TapService] ✅ assignAllImages: got images for ${result.length} buttons');
      return result;
    } catch (e) {
      debugPrint('[TapService] ❌ assignAllImages error: $e');
      return null;
    }
  }

  /// Calls /api/tap-interface/bravo-build to generate a complete board with
  /// up to 30 buttons that have images already assigned and are saved to
  /// Firestore.  Returns the new board on success or null on failure.
  Future<TapBoard?> callBravoBuild({
    required String buttonLabel,
    String? sourceBoardId,
    String? buttonId,
    String? context,
  }) async {
    try {
      debugPrint(
        '[TapService] 🏗️ callBravoBuild label="$buttonLabel" source=$sourceBoardId',
      );
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/bravo-build',
        baseHeaders: {
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'button_label': buttonLabel,
          if (sourceBoardId != null && sourceBoardId.isNotEmpty)
            'source_board_id': sourceBoardId,
          if (buttonId != null && buttonId.isNotEmpty) 'button_id': buttonId,
          if (context != null && context.isNotEmpty) 'context': context,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          '[TapService] ❌ bravo-build HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 300))}',
        );
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        debugPrint('[TapService] ❌ bravo-build returned success=false');
        return null;
      }

      final boardJson = data['board'] as Map<String, dynamic>?;
      if (boardJson == null) {
        debugPrint('[TapService] ❌ bravo-build response missing "board" key');
        return null;
      }

      final board = TapBoard.fromJson(boardJson);
      debugPrint(
        '[TapService] ✅ bravo-build returned board "${board.label}" with ${board.buttons.length} buttons',
      );
      return board;
    } catch (e) {
      debugPrint('[TapService] ❌ callBravoBuild error: $e');
      return null;
    }
  }
}
