class TapNavigationButton {
  String id;
  String label;
  String? speechText;
  String? imageUrl;
  String? customAudioFile;
  String backgroundColor;
  String textColor;
  String? llmPrompt;
  String? wordsPrompt;
  String? staticOptions;
  String? specialPage;
  bool hidden;
  List<TapNavigationButton> children;

  TapNavigationButton({
    required this.id,
    required this.label,
    this.speechText,
    this.imageUrl,
    this.customAudioFile,
    this.backgroundColor = '#FFFFFF',
    this.textColor = '#000000',
    this.llmPrompt,
    this.wordsPrompt,
    this.staticOptions,
    this.specialPage,
    this.hidden = false,
    List<TapNavigationButton>? children,
  }) : children = children ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'speech_text': speechText,
      'image_url': imageUrl,
      'custom_audio_file': customAudioFile,
      'background_color': backgroundColor,
      'text_color': textColor,
      'llm_prompt': llmPrompt,
      'words_prompt': wordsPrompt,
      'static_options': staticOptions,
      'special_function': specialPage,
      'hidden': hidden,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }

  factory TapNavigationButton.fromJson(Map<String, dynamic> json) {
    return TapNavigationButton(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      speechText: json['speech_text'],
      imageUrl: json['image_url'],
      customAudioFile: json['custom_audio_file'],
      backgroundColor: json['background_color'] ?? '#FFFFFF',
      textColor: json['text_color'] ?? '#000000',
      llmPrompt: json['llm_prompt'],
      wordsPrompt: json['words_prompt'],
      staticOptions: json['static_options'],
      specialPage: json['special_function'] ?? json['special_page'],
      hidden: json['hidden'] ?? false,
      children: (json['children'] as List<dynamic>?)
          ?.map((child) => TapNavigationButton.fromJson(child as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  TapNavigationButton copyWith({
    String? id,
    String? label,
    String? speechText,
    String? imageUrl,
    String? customAudioFile,
    String? backgroundColor,
    String? textColor,
    String? llmPrompt,
    String? wordsPrompt,
    String? staticOptions,
    String? specialPage,
    bool? hidden,
    List<TapNavigationButton>? children,
  }) {
    return TapNavigationButton(
      id: id ?? this.id,
      label: label ?? this.label,
      speechText: speechText ?? this.speechText,
      imageUrl: imageUrl ?? this.imageUrl,
      customAudioFile: customAudioFile ?? this.customAudioFile,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      llmPrompt: llmPrompt ?? this.llmPrompt,
      wordsPrompt: wordsPrompt ?? this.wordsPrompt,
      staticOptions: staticOptions ?? this.staticOptions,
      specialPage: specialPage ?? this.specialPage,
      hidden: hidden ?? this.hidden,
      children: children ?? List<TapNavigationButton>.from(this.children),
    );
  }

  // Helper getters
  bool get hasLLMPrompt => llmPrompt != null && llmPrompt!.isNotEmpty;
  bool get hasWordsPrompt => wordsPrompt != null && wordsPrompt!.isNotEmpty;
  bool get hasStaticOptions => staticOptions != null && staticOptions!.isNotEmpty;
  bool get hasSpecialPage => specialPage != null && specialPage!.isNotEmpty;
  bool get hasChildren => children.isNotEmpty;
  bool get hasCustomAudioFile => customAudioFile != null && customAudioFile!.isNotEmpty;
  
  List<String> get staticOptionsList {
    if (!hasStaticOptions) return [];
    return staticOptions!.split(',').map((e) => e.trim()).toList();
  }
}

class TapNavigationConfig {
  String id;
  String name;
  String? description;
  bool isActive;
  String createdAt;
  String updatedAt;
  List<TapNavigationButton> buttons;

  TapNavigationConfig({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    List<TapNavigationButton>? buttons,
  }) : buttons = buttons ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'buttons': buttons.map((button) => button.toJson()).toList(),
    };
  }

  factory TapNavigationConfig.fromJson(Map<String, dynamic> json) {
    return TapNavigationConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at'] ?? DateTime.now().toIso8601String(),
      buttons: (json['buttons'] as List<dynamic>?)
          ?.map((button) => TapNavigationButton.fromJson(button as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

// Path helper for navigation
class ButtonPath {
  final List<int> indices;

  ButtonPath(this.indices);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonPath &&
          runtimeType == other.runtimeType &&
          _listEquals(indices, other.indices);

  @override
  int get hashCode => indices.hashCode;

  @override
  String toString() => 'ButtonPath(${indices.join(',')})';

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}