// Models for Admin Pages & Buttons

class PageButtonModel {
  int row;
  int col;
  String text;
  String? speechPhrase;
  String? llmQuery;
  String? targetPage;
  String? queryType;
  bool hidden;
  String? pictogramUrl; // URL or path to pictogram/image
  bool useCustomPictogram; // Whether to use manually assigned pictogram vs dynamic lookup

  PageButtonModel({
    required this.row,
    required this.col,
    required this.text,
    this.speechPhrase,
    this.llmQuery,
    this.targetPage,
    this.queryType,
    this.hidden = false,
    this.pictogramUrl,
    this.useCustomPictogram = false,
  });

  factory PageButtonModel.fromJson(Map<String, dynamic> json) => PageButtonModel(
        row: json['row'] ?? 0,
        col: json['col'] ?? 0,
        text: json['text'] ?? '',
        speechPhrase: json['speechPhrase'],
        llmQuery: json['LLMQuery'],
        targetPage: json['targetPage'],
        queryType: json['queryType'],
        hidden: json['hidden'] ?? false,
        pictogramUrl: json['pictogramUrl'],
        useCustomPictogram: json['useCustomPictogram'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'row': row,
        'col': col,
        'text': text,
        'speechPhrase': speechPhrase,
        'LLMQuery': llmQuery,
        'targetPage': targetPage,
        'queryType': queryType,
        'hidden': hidden,
        'pictogramUrl': pictogramUrl,
        'useCustomPictogram': useCustomPictogram,
      };
}

class PageModel {
  String name;
  String displayName;
  List<PageButtonModel> buttons;
  // Add more fields as needed

  PageModel({
    required this.name,
    required this.displayName,
    required this.buttons,
  });

  factory PageModel.fromJson(Map<String, dynamic> json) => PageModel(
        name: json['name'] ?? '',
        displayName: json['displayName'] ?? '',
        buttons: (json['buttons'] as List<dynamic>? ?? [])
            .map((b) => PageButtonModel.fromJson(b))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'buttons': buttons.map((b) => b.toJson()).toList(),
      };
}
