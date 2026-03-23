class FamilyFriendsInterviewQuestions {
  // Family & Friends Interview Questions
  // Specialized interview system for collecting information about family members and friends
  // to populate the user_info page Friends & Family section
  
  static const List<Map<String, dynamic>> questions = [
    {
      'id': 'person_name',
      'question': 'What does the user call this person? (Their name or nickname)',
      'category': 'basic',
      'required': true,
      'followUp': 'Do you use their first name, a nickname, or something special like Mom, Dad, etc.?'
    },
    {
      'id': 'relationship',
      'question': 'What is this person\'s relationship?',
      'category': 'basic',
      'required': true,
      'followUp': 'For example: mother, father, sister, brother, friend, teacher, caregiver, etc.'
    },
    {
      'id': 'about_person',
      'question': 'Tell me about this person. What do they like or dislike? Do they have any hobbies or interests? What kinds of things do you talk about with them?',
      'category': 'details',
      'required': true,
      'followUp': 'What makes them special? What do you enjoy doing together or talking about?'
    },
    {
      'id': 'birthday',
      'question': 'When is this person\'s birthday? Just the month and day is fine.',
      'category': 'details',
      'required': false,
      'followUp': 'For example: January 15th, or March 22nd. Say "I don\'t know" if you\'re not sure.'
    }
  ];

  // Configuration for the single-person interview
  static const Map<String, dynamic> config = {
    'title': "Add Person Interview",
    'description': "Tell us about one important person in your life and we'll add them to your Friends & Family list.",
    'estimatedTime': "2-3 minutes",
    
    // Encouragement prompts
    'encouragementPrompts': [
      "Great! Tell me more about them.",
      "That's helpful information!",
      "Perfect, what else can you tell me?",
      "Excellent! One more question.",
      "Thank you for sharing!"
    ]
  };

  /// Get all questions
  static List<Map<String, dynamic>> getAllQuestions() {
    return questions.map((q) => Map<String, dynamic>.from(q)).toList();
  }

  /// Get required questions only
  static List<Map<String, dynamic>> getRequiredQuestions() {
    return questions
        .where((q) => q['required'] == true)
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
  }

  /// Get configuration
  static Map<String, dynamic> getConfig() {
    return Map<String, dynamic>.from(config);
  }

  /// Get questions by category
  static List<Map<String, dynamic>> getQuestionsByCategory(String category) {
    return questions
        .where((q) => q['category'] == category)
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
  }

  /// Get encouragement prompts
  static List<String> getEncouragementPrompts() {
    return List<String>.from(config['encouragementPrompts'] ?? []);
  }
}