class InterviewQuestions {
  static const Map<String, dynamic> comprehensiveQuestions = {
    // Configuration for User Voice & Personality Interview
    'INTERVIEW_CONFIG': {
      // Minimum required questions for comprehensive personality and voice profile
      'minimumRequired': 15,
      
      // Questions per session to avoid fatigue
      'questionsPerSession': 5,
      
      // Time between questions (in seconds)
      'questionInterval': 4,
      
      // Categories to prioritize for complete user voice profile
      'priorityCategories': ['identity', 'personality', 'preferences', 'voice', 'history', 'values'],
      
      // Maximum length for a single answer
      'maxAnswerLength': 2000,
      
      // Prompts for encouraging detailed responses about the person
      'encouragementPrompts': [
        "Can you tell me more about that?",
        "That's helpful - can you give me some specific examples?",
        "What else would help me understand their personality?",
        "Are there other details that show what makes them unique?",
        "Can you describe how they express this or show this trait?"
      ],
      
      // Prompts for skipping questions
      'skipPrompts': [
        "That's okay - we can move on to learn about other aspects of who they are.",
        "No problem - let's continue with other questions about their personality.",
        "We can skip this one - there are many ways to capture their voice and preferences.",
        "That's fine - let's explore other parts of their character and interests."
      ]
    },
    
    // Basic Identity & Personal Information
    'identity': [
      {
        'id': 'user_name',
        'question': 'What is the name of the person using the application?',
        'category': 'identity',
        'required': true,
        'followUp': 'Do they have any nicknames, pet names, or special names that family and friends use?'
      },
      {
        'id': 'age_birthday', 
        'question': 'When is their birthday?',
        'category': 'identity',
        'required': true,
        'followUp': 'Do they get excited about birthdays? How do they like to celebrate?'
      },
      {
        'id': 'living_situation',
        'question': 'Where do they live and who do they live with?',
        'category': 'identity',
        'required': true,
        'followUp': 'Who are the most important people in their daily life?'
      }
    ],
    // Personality & Communication Style
    'personality': [
      {
        'id': 'personality_traits',
        'question': 'How would you describe their personality? Are they funny, serious, gentle, energetic, quiet, outgoing?',
        'category': 'personality',
        'required': true,
        'followUp': 'What personality traits do people notice most about them?'
      },
      {
        'id': 'communication_style',
        'question': 'How do they like to communicate? Are they direct, polite, playful, formal, or casual?',
        'category': 'personality',
        'required': true,
        'followUp': 'Do they have any favorite words, phrases, or ways of expressing themselves?'
      },
      {
        'id': 'sense_of_humor',
        'question': 'What is their sense of humor like? What makes them laugh or smile?',
        'category': 'personality',
        'required': false,
        'followUp': 'Do they like jokes, silly words, funny faces, or other types of humor?'
      },
      {
        'id': 'social_style',
        'question': 'Are they more social and outgoing, or quiet and reserved? How do they interact with others?',
        'category': 'personality',
        'required': true,
        'followUp': 'Do they prefer being the center of attention or staying in the background?'
      },
      {
        'id': 'emotional_expression',
        'question': 'How do they express emotions? How do they show when they\'re happy, sad, excited, or upset?',
        'category': 'personality',
        'required': true,
        'followUp': 'Are there specific ways they like to be comforted or celebrated?'
      }
    ],
    // Interests, Hobbies & Entertainment
    'interests': [
      {
        'id': 'favorite_activities',
        'question': 'What are their favorite activities and hobbies? What do they love to do?',
        'category': 'interests',
        'required': true,
        'followUp': 'Which activities get them most excited? What do they ask to do repeatedly?'
      },
      {
        'id': 'entertainment_media',
        'question': 'What books, TV shows, movies, YouTube channels, or videos do they enjoy? Any favorite characters?',
        'category': 'interests',
        'required': true,
        'followUp': 'Do they have favorite lines, songs, or scenes they like to reference or repeat?'
      },
      {
        'id': 'music_preferences',
        'question': 'What kind of music do they like? Any favorite songs, artists, or genres?',
        'category': 'interests',
        'required': true,
        'followUp': 'Do they sing along, dance, or have favorite lyrics they like to hear?'
      },
      {
        'id': 'games_play',
        'question': 'What games do they enjoy? Board games, video games, outdoor games, or other types of play?',
        'category': 'interests',
        'required': false,
        'followUp': 'Are they competitive, do they like to win, or do they just enjoy playing?'
      },
      {
        'id': 'learning_topics',
        'question': 'What subjects or topics do they find interesting to learn about or discuss?',
        'category': 'interests',
        'required': false,
        'followUp': 'Do they have any special interests or expertise in particular areas?'
      },
      {
        'id': 'creative_expression',
        'question': 'Do they enjoy creative activities like art, crafts, building, or making things?',
        'category': 'interests',
        'required': false,
        'followUp': 'What types of creative projects do they like most?'
      }
    ],
    // Important Relationships & Social Life
    'relationships': [
      {
        'id': 'pets_animals',
        'question': 'Do they have pets or like animals? Any favorite animals or pets they talk about?',
        'category': 'relationships',
        'required': false,
        'followUp': 'How do they interact with animals? Do they have names for favorite pets or stuffed animals?'
      },
      {
        'id': 'social_situations',
        'question': 'What social situations do they enjoy? Parties, family gatherings, quiet visits, or group activities?',
        'category': 'relationships',
        'required': false,
        'followUp': 'Are there social situations that are challenging or overwhelming for them?'
      },
      {
        'id': 'friendship_style',
        'question': 'How do they make friends and maintain relationships? What kind of friend are they?',
        'category': 'relationships',
        'required': false,
        'followUp': 'Do they prefer close friendships or many casual friends? How do they show they care?'
      }
    ],
    // Preferences & Dislikes (Food, Sensory, etc.)
    'preferences': [
      {
        'id': 'food_drinks',
        'question': 'What are their favorite foods and drinks? What do they always want and what do they refuse?',
        'category': 'preferences',
        'required': true,
        'followUp': 'Any foods they talk about often, request frequently, or get excited about?'
      },
      {
        'id': 'sensory_likes_dislikes',
        'question': 'What sensory experiences do they love or hate? Sounds, textures, lights, smells, temperatures?',
        'category': 'preferences',
        'required': true,
        'followUp': 'What sensory things calm them down or get them excited?'
      },
      {
        'id': 'clothing_style',
        'question': 'Do they have preferences about clothing? Favorite colors, styles, comfort needs, or things they refuse to wear?',
        'category': 'preferences',
        'required': false,
        'followUp': 'Are there textures, fits, or styles that they particularly love or hate?'
      },
      {
        'id': 'routine_preferences',
        'question': 'Do they like routine and predictability, or do they enjoy surprises and changes?',
        'category': 'preferences',
        'required': true,
        'followUp': 'How do they react to changes in plans or new experiences?'
      },
      {
        'id': 'comfort_items',
        'question': 'Do they have favorite comfort items, toys, or objects that are important to them?',
        'category': 'preferences',
        'required': false,
        'followUp': 'What items do they like to have with them or talk about often?'
      }
    ],
    // Daily Life & Routines
    'daily_life': [
      {
        'id': 'typical_day',
        'question': 'What does a typical day look like for them? School, work programs, activities, or staying home?',
        'category': 'daily_life',
        'required': true,
        'followUp': 'What are their favorite parts of the day and what parts are most challenging?'
      },
      {
        'id': 'favorite_places',
        'question': 'What places do they enjoy going to? Stores, parks, restaurants, or other locations?',
        'category': 'daily_life',
        'required': false,
        'followUp': 'Are there places they ask to go or get excited about visiting?'
      },
      {
        'id': 'transportation',
        'question': 'How do they feel about transportation? Cars, buses, walking, or other ways of getting around?',
        'category': 'daily_life',
        'required': false,
        'followUp': 'Do they have preferences about how they travel or get places?'
      },
      {
        'id': 'sleep_rest',
        'question': 'What are their sleep and rest patterns? Are they a morning person or night owl?',
        'category': 'daily_life',
        'required': false,
        'followUp': 'When are they most alert and communicative during the day?'
      }
    ],
    // Personal History & Life Story
    'history': [
      {
        'id': 'life_story',
        'question': 'What are some important events or experiences in their life? School memories, achievements, places they\'ve lived, or experiences that shaped who they are?',
        'category': 'history',
        'required': true,
        'followUp': 'Are there specific memories or accomplishments they\'re proud of or like to talk about?'
      },
      {
        'id': 'school_work_history',
        'question': 'Tell me about their school experiences, jobs, or programs they\'ve been part of. What did they enjoy most?',
        'category': 'history',
        'required': false,
        'followUp': 'Are there teachers, coworkers, or experiences from these places that were meaningful to them?'
      },
      {
        'id': 'family_traditions',
        'question': 'What family traditions, cultural background, or special celebrations are part of their life?',
        'category': 'history',
        'required': false,
        'followUp': 'How do they participate in or feel about these traditions and celebrations?'
      },
      {
        'id': 'travel_places',
        'question': 'What places have they visited or lived that were special to them? Any trips or locations they remember fondly?',
        'category': 'history',
        'required': false,
        'followUp': 'What did they love about these places? Do they want to visit again or talk about them often?'
      }
    ],
    // Dreams, Goals & Future Hopes
    'dreams': [
      {
        'id': 'future_goals',
        'question': 'What do they want to do, see, or accomplish in the future? Any dreams or goals they talk about?',
        'category': 'dreams',
        'required': true,
        'followUp': 'What steps are they taking or what would help them work toward these goals?'
      },
      {
        'id': 'people_to_meet',
        'question': 'Are there people they want to meet, reconnect with, or spend more time with?',
        'category': 'dreams',
        'required': false,
        'followUp': 'What would they want to say or do with these people?'
      },
      {
        'id': 'places_to_visit',
        'question': 'Where do they want to go or what do they want to see? Any dream destinations or experiences?',
        'category': 'dreams',
        'required': false,
        'followUp': 'What draws them to these places? What would they want to do there?'
      },
      {
        'id': 'skills_to_learn',
        'question': 'What new skills do they want to learn or what abilities do they want to develop?',
        'category': 'dreams',
        'required': false,
        'followUp': 'Why are these skills important to them? How would learning them change their life?'
      }
    ],
    // Values, Opinions & What Matters Most
    'values': [
      {
        'id': 'core_values',
        'question': 'What matters most to them in life? Family, fairness, fun, helping others, independence, or other values?',
        'category': 'values',
        'required': true,
        'followUp': 'How do they show these values in their daily life or relationships?'
      },
      {'id': 'role_models',
        'question': 'Do they have role models or people they look up to? What qualities do they admire in these people?',
        'category': 'values',
        'required': false,
        'followUp': 'How do these role models influence their behavior or choices?'
      },
      {
        'id': 'strong_opinions',
        'question': 'What are they passionate about? Any strong likes, dislikes, or opinions about how things should be?',
        'category': 'values',
        'required': true,
        'followUp': 'Do they like to advocate for these beliefs or share their opinions with others?'
      },
      {
        'id': 'pride_disappointment',
        'question': 'What makes them feel proud, happy, or satisfied? What disappoints or upsets them about the world?',
        'category': 'values',
        'required': false,
        'followUp': 'How do they express these feelings? Do they want to take action about things that matter to them?'
      },
      {'id': 'personal_beliefs',
        'question': 'Do they have personal, spiritual, or religious beliefs that are important to them?',
        'category': 'values',
        'required': false,
        'followUp': 'How do these beliefs influence their daily life and decisions?'
      }
    ],
    // Favorite Memories & Stories
    'memories': [
      {
        'id': 'favorite_memories',
        'question': 'What are some of their favorite memories? Happy times, funny moments, or special experiences they like to remember?',
        'category': 'memories',
        'required': true,
        'followUp': 'Do they like to talk about these memories or share these stories with others?'
      },
      {
        'id': 'funny_stories',
        'question': 'Do they have funny stories, embarrassing moments, or silly things that happened that they enjoy sharing?',
        'category': 'memories',
        'required': false,
        'followUp': 'How do they tell these stories? Do they like to make people laugh with their experiences?'
      },
      {
        'id': 'meaningful_experiences',
        'question': 'What experiences or moments changed them or taught them something important about themselves?',
        'category': 'memories',
        'required': false,
        'followUp': 'How do these experiences influence how they see themselves or the world now?'
      },
      {
        'id': 'nostalgic_things',
        'question': 'What from their past do they miss or feel nostalgic about? Old friends, places, activities, or times in their life?',
        'category': 'memories',
        'required': false,
        'followUp': 'What made those times special? Do they try to recreate those experiences or feelings now?'
      }
    ],
    // Support Context & Disability Information
    'support_needs': [
      {
        'id': 'developmental_disabilities',
        'question': 'Do they have developmental disabilities or conditions that affect learning, understanding, or processing information?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'How do these conditions affect their communication needs and daily activities?'
      },
      {
        'id': 'physical_disabilities',
        'question': 'Do they have physical disabilities or mobility challenges? Any limitations with movement, coordination, or physical abilities?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'How do these physical challenges affect their participation in activities or communication methods?'
      },
      {
        'id': 'medical_conditions',
        'question': 'What medical conditions or health issues do they have that affect their daily life or communication?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'Are there specific medical needs or treatments that impact their activities or preferences?'
      },
      {
        'id': 'feeding_nutrition',
        'question': 'How do they eat and drink? Do they eat regular food, require special diets, use feeding tubes, or have other nutrition needs?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'Are there feeding challenges, special equipment, or dietary restrictions that are important to know?'
      },
      {
        'id': 'allergies_safety',
        'question': 'Do they have any food allergies, medication allergies, or other safety concerns that are critical to communicate?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'What are the signs of allergic reactions and what emergency information should always be available?'
      },
      {
        'id': 'sensory_processing',
        'question': 'Do they have sensory processing differences, autism, or conditions that affect how they experience sounds, lights, touch, or other sensations?',
        'category': 'support_needs',
        'required': false,
        'followUp': 'What sensory accommodations help them feel comfortable and communicate better?'
      },
      {
        'id': 'behavioral_emotional',
        'question': 'Do they have emotional regulation challenges, behavioral conditions, or mental health needs that affect communication?',
        'category': 'support_needs',
        'required': false,
        'followUp': 'What strategies help them feel calm and ready to communicate? What should be avoided?'
      },
      {
        'id': 'medications',
        'question': 'What medications do they take and do any affect their alertness, behavior, or communication abilities?',
        'category': 'support_needs',
        'required': false,
        'followUp': 'Are there times of day when medications affect how they feel or communicate?'
      },
      {
        'id': 'emergency_medical',
        'question': 'What emergency medical information is critical for caregivers to know? Seizure protocols, emergency contacts, or urgent medical needs?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'What emergency situations might require immediate communication and what information needs to be shared quickly?'
      },
      {
        'id': 'daily_care_needs',
        'question': 'What daily care or assistance do they need? Help with personal care, mobility, eating, or other activities?',
        'category': 'support_needs',
        'required': false,
        'followUp': 'How do they communicate their needs for help or indicate when they need assistance?'
      },
      {
        'id': 'cognitive_abilities',
        'question': 'What are their cognitive strengths and challenges? How well do they understand complex information, follow instructions, or make decisions?',
        'category': 'support_needs',
        'required': true,
        'followUp': 'What communication approaches work best given their cognitive abilities and processing style?'
      }
    ],
    // Personal Voice & Expression Style
    'voice': [
      {
        'id': 'catch_phrases',
        'question': 'Do they have any favorite words, phrases, or things they like to say? Any catchphrases or expressions that are uniquely theirs?',
        'category': 'voice',
        'required': true,
        'followUp': 'Are there words or phrases they use differently or in their own special way?'
      },
      {
        'id': 'communication_goals',
        'question': 'What do they most want to communicate about? What topics or messages are most important to them?',
        'category': 'voice',
        'required': true,
        'followUp': 'What would they want to be able to say if they could say anything?'
      },
      {
        'id': 'response_style',
        'question': 'How do they typically respond to questions or situations? Are they enthusiastic, thoughtful, direct, or hesitant?',
        'category': 'voice',
        'required': true,
        'followUp': 'Do they like to give quick answers or do they need time to think?'
      },
      {
        'id': 'conversation_topics',
        'question': 'What topics do they love to talk about or hear about? What gets them excited in conversation?',
        'category': 'voice',
        'required': true,
        'followUp': 'Are there topics they avoid or that make them uncomfortable?'
      },
      {
        'id': 'expression_methods',
        'question': 'How do they currently express themselves? Sounds, gestures, facial expressions, behaviors, or other ways?',
        'category': 'voice',
        'required': true,
        'followUp': 'What are their unique ways of showing excitement, agreement, disagreement, or other feelings?'
      }
    ]
  };

  /// Get all questions as a flat list for the interview service
  static List<Map<String, dynamic>> getAllQuestions() {
    List<Map<String, dynamic>> allQuestions = [];
    
    comprehensiveQuestions.forEach((categoryKey, categoryData) {
      if (categoryKey == 'INTERVIEW_CONFIG') return;
      
      if (categoryData is List) {
        for (var question in categoryData) {
          allQuestions.add(Map<String, dynamic>.from(question));
        }
      }
    });
    
    return allQuestions;
  }

  /// Get questions by category
  static List<Map<String, dynamic>> getQuestionsByCategory(String category) {
    if (!comprehensiveQuestions.containsKey(category) || 
        comprehensiveQuestions[category] is! List) {
      return [];
    }
    
    return (comprehensiveQuestions[category] as List)
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
  }

  /// Get configuration settings
  static Map<String, dynamic> getConfig() {
    return Map<String, dynamic>.from(
      comprehensiveQuestions['INTERVIEW_CONFIG'] ?? {}
    );
  }

  /// Get required questions only
  static List<Map<String, dynamic>> getRequiredQuestions() {
    return getAllQuestions()
        .where((question) => question['required'] == true)
        .toList();
  }

  /// Get questions with follow-ups
  static List<Map<String, dynamic>> getQuestionsWithFollowUps() {
    return getAllQuestions()
        .where((question) => question['followUp'] != null && question['followUp'].toString().isNotEmpty)
        .toList();
  }
}