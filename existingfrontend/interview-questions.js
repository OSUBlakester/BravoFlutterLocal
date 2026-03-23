// Interview Questions for AAC User Voice & Personality Capture
// This system collects comprehensive information about AAC users to understand their complete personality,
// preferences, challenges, and authentic "voice" so the LLM can generate communication options that 
// truly represent who they are as a person. Focus on capturing their individual character and preferences.

const INTERVIEW_QUESTIONS = {
  // Basic Identity & Personal Information
  identity: [
    {
      id: 'user_name',
      question: 'What is the name of the person using the application?',
      category: 'identity',
      required: true,
      followUp: 'Do they have any nicknames, pet names, or special names that family and friends use?'
    },
    {
      id: 'age_birthday', 
      question: 'When is their birthday?',
      category: 'identity',
      required: true,
      followUp: 'Do they get excited about birthdays? How do they like to celebrate?'
    },
    {
      id: 'living_situation',
      question: 'Where do they live and who do they live with?',
      category: 'identity',
      required: true,
      followUp: 'Who are the most important people in their daily life?'
    }
  ],

  // Personality & Communication Style
  personality: [
    {
      id: 'personality_traits',
      question: 'How would you describe their personality? Are they funny, serious, gentle, energetic, quiet, outgoing?',
      category: 'personality',
      required: true,
      followUp: 'What personality traits do people notice most about them?'
    },
    {
      id: 'communication_style',
      question: 'How do they like to communicate? Are they direct, polite, playful, formal, or casual?',
      category: 'personality',
      required: true,
      followUp: 'Do they have any favorite words, phrases, or ways of expressing themselves?'
    },
    {
      id: 'sense_of_humor',
      question: 'What is their sense of humor like? What makes them laugh or smile?',
      category: 'personality',
      required: false,
      followUp: 'Do they like jokes, silly words, funny faces, or other types of humor?'
    },
    {
      id: 'social_style',
      question: 'Are they more social and outgoing, or quiet and reserved? How do they interact with others?',
      category: 'personality',
      required: true,
      followUp: 'Do they prefer being the center of attention or staying in the background?'
    },
    {
      id: 'emotional_expression',
      question: 'How do they express emotions? How do they show when they\'re happy, sad, excited, or upset?',
      category: 'personality',
      required: true,
      followUp: 'Are there specific ways they like to be comforted or celebrated?'
    }
  ],

  // Interests, Hobbies & Entertainment
  interests: [
    {
      id: 'favorite_activities',
      question: 'What are their favorite activities and hobbies? What do they love to do?',
      category: 'interests',
      required: true,
      followUp: 'Which activities get them most excited? What do they ask to do repeatedly?'
    },
    {
      id: 'entertainment_media',
      question: 'What TV shows, movies, YouTube channels, or videos do they enjoy? Any favorite characters?',
      category: 'interests',
      required: true,
      followUp: 'Do they have favorite lines, songs, or scenes they like to reference or repeat?'
    },
    {
      id: 'music_preferences',
      question: 'What kind of music do they like? Any favorite songs, artists, or genres?',
      category: 'interests',
      required: true,
      followUp: 'Do they sing along, dance, or have favorite lyrics they like to hear?'
    },
    {
      id: 'games_play',
      question: 'What games do they enjoy? Board games, video games, outdoor games, or other types of play?',
      category: 'interests',
      required: false,
      followUp: 'Are they competitive, do they like to win, or do they just enjoy playing?'
    },
    {
      id: 'special_interests',
      question: 'Do they have any special interests or topics they\'re really passionate about?',
      category: 'interests',
      required: false,
      followUp: 'What specific aspects of these interests fascinate them most?'
    },
    {
      id: 'creative_expression',
      question: 'Do they enjoy any creative activities like art, music, building, or crafts?',
      category: 'interests',
      required: false,
      followUp: 'How do they like to be creative? What materials or methods do they prefer?'
    }
  ],

  // Important Relationships & Social Life
  relationships: [
    {
      id: 'pets_animals',
      question: 'Do they have pets or like animals? Any favorite animals or pets they talk about?',
      category: 'relationships',
      required: false,
      followUp: 'How do they interact with animals? Do they have names for favorite pets or stuffed animals?'
    },
    {
      id: 'social_situations',
      question: 'What social situations do they enjoy? Parties, family gatherings, quiet visits, or group activities?',
      category: 'relationships',
      required: false,
      followUp: 'Are there social situations that are challenging or overwhelming for them?'
    },
    {
      id: 'friendship_style',
      question: 'How do they make friends and maintain relationships? What kind of friend are they?',
      category: 'relationships',
      required: false,
      followUp: 'Do they prefer close friendships or many casual friends? How do they show they care?'
    }
  ],

  // Preferences & Dislikes (Food, Sensory, etc.)
  preferences: [
    {
      id: 'food_drinks',
      question: 'What are their favorite foods and drinks? What do they always want and what do they refuse?',
      category: 'preferences',
      required: true,
      followUp: 'Any foods they talk about often, request frequently, or get excited about?'
    },
    {
      id: 'sensory_likes_dislikes',
      question: 'What sensory experiences do they love or hate? Sounds, textures, lights, smells, temperatures?',
      category: 'preferences',
      required: true,
      followUp: 'What sensory things calm them down or get them excited?'
    },
    {
      id: 'clothing_style',
      question: 'Do they have preferences about clothing? Favorite colors, styles, comfort needs, or things they refuse to wear?',
      category: 'preferences',
      required: false,
      followUp: 'Are there textures, fits, or styles that they particularly love or hate?'
    },
    {
      id: 'routine_preferences',
      question: 'Do they like routine and predictability, or do they enjoy surprises and changes?',
      category: 'preferences',
      required: true,
      followUp: 'How do they react to changes in plans or new experiences?'
    },
    {
      id: 'comfort_items',
      question: 'Do they have favorite comfort items, toys, or objects that are important to them?',
      category: 'preferences',
      required: false,
      followUp: 'What items do they like to have with them or talk about often?'
    }
  ],

  // Daily Life & Routines
  daily_life: [
    {
      id: 'typical_day',
      question: 'What does a typical day look like for them? School, work programs, activities, or staying home?',
      category: 'daily_life',
      required: true,
      followUp: 'What are their favorite parts of the day and what parts are most challenging?'
    },
    {
      id: 'favorite_places',
      question: 'What places do they enjoy going to? Stores, parks, restaurants, or other locations?',
      category: 'daily_life',
      required: false,
      followUp: 'Are there places they ask to go or get excited about visiting?'
    },
    {
      id: 'transportation',
      question: 'How do they feel about transportation? Cars, buses, walking, or other ways of getting around?',
      category: 'daily_life',
      required: false,
      followUp: 'Do they have preferences about how they travel or get places?'
    },
    {
      id: 'sleep_rest',
      question: 'What are their sleep and rest patterns? Are they a morning person or night owl?',
      category: 'daily_life',
      required: false,
      followUp: 'When are they most alert and communicative during the day?'
    }
  ],

  // Challenges & Support Needs (All Disabilities & Life Areas)
  challenges: [
    {
      id: 'main_disabilities',
      question: 'What are their main disabilities or challenges? This helps us understand their full support needs.',
      category: 'challenges',
      required: true,
      followUp: 'How do these challenges affect their daily life and what they need help with?'
    },
    {
      id: 'daily_help_needs',
      question: 'What things do they usually need help with? Personal care, mobility, understanding instructions, or other areas?',
      category: 'challenges',
      required: true,
      followUp: 'What are the most common situations where they need support or assistance?'
    },
    {
      id: 'communication_challenges',
      question: 'What are their specific communication challenges? Understanding others, expressing themselves, or both?',
      category: 'challenges',
      required: true,
      followUp: 'How do they currently communicate their wants and needs?'
    },
    {
      id: 'frustration_behaviors',
      question: 'How do they show frustration or distress? What are their warning signs that they\'re struggling?',
      category: 'challenges',
      required: true,
      followUp: 'What helps calm them down or support them when they\'re upset?'
    },
    {
      id: 'learning_challenges',
      question: 'How do they learn best? Do they need extra time, repetition, visual aids, or other learning supports?',
      category: 'challenges',
      required: false,
      followUp: 'What teaching methods work well and what should be avoided?'
    },
    {
      id: 'physical_limitations',
      question: 'Are there any physical limitations that affect what they can do or how they interact with things?',
      category: 'challenges',
      required: false,
      followUp: 'What adaptations or accommodations help them participate more fully?'
    },
    {
      id: 'medical_factors',
      question: 'Are there medical conditions, medications, or health factors that affect their mood, energy, or abilities?',
      category: 'challenges',
      required: false,
      followUp: 'Do these factors change throughout the day or affect their communication?'
    }
  ],

  // Personal Voice & Expression Style
  voice: [
    {
      id: 'catch_phrases',
      question: 'Do they have any favorite words, phrases, or things they like to say? Any catchphrases or expressions that are uniquely theirs?',
      category: 'voice',
      required: true,
      followUp: 'Are there words or phrases they use differently or in their own special way?'
    },
    {
      id: 'communication_goals',
      question: 'What do they most want to communicate about? What topics or messages are most important to them?',
      category: 'voice',
      required: true,
      followUp: 'What would they want to be able to say if they could say anything?'
    },
    {
      id: 'response_style',
      question: 'How do they typically respond to questions or situations? Are they enthusiastic, thoughtful, direct, or hesitant?',
      category: 'voice',
      required: true,
      followUp: 'Do they like to give quick answers or do they need time to think?'
    },
    {
      id: 'conversation_topics',
      question: 'What topics do they love to talk about or hear about? What gets them excited in conversation?',
      category: 'voice',
      required: true,
      followUp: 'Are there topics they avoid or that make them uncomfortable?'
    },
    {
      id: 'expression_methods',
      question: 'How do they currently express themselves? Sounds, gestures, facial expressions, behaviors, or other ways?',
      category: 'voice',
      required: true,
      followUp: 'What are their unique ways of showing excitement, agreement, disagreement, or other feelings?'
    }
  ]
};

// Configuration for User Voice & Personality Interview
const INTERVIEW_CONFIG = {
  // Minimum required questions for comprehensive personality and voice profile
  minimumRequired: 15,
  
  // Questions per session to avoid fatigue
  questionsPerSession: 5,
  
  // Time between questions (in seconds)
  questionInterval: 4,
  
  // Categories to prioritize for complete user voice profile
  priorityCategories: ['identity', 'personality', 'preferences', 'voice', 'challenges'],
  
  // Maximum length for a single answer
  maxAnswerLength: 2000,
  
  // Prompts for encouraging detailed responses about the person
  encouragementPrompts: [
    "Can you tell me more about that?",
    "That's helpful - can you give me some specific examples?",
    "What else would help me understand their personality?",
    "Are there other details that show what makes them unique?",
    "Can you describe how they express this or show this trait?"
  ],
  
  // Prompts for skipping questions
  skipPrompts: [
    "That's okay - we can move on to learn about other aspects of who they are.",
    "No problem - let's continue with other questions about their personality.",
    "We can skip this one - there are many ways to capture their voice and preferences.",
    "That's fine - let's explore other parts of their character and interests."
  ],
  
  // Key areas for capturing authentic user voice
  voiceCapture: {
    // Essential personality dimensions
    personalityAreas: [
      'humor_style',
      'social_energy',
      'emotional_expression',
      'communication_style',
      'interaction_preferences'
    ],
    
    // Important preference categories
    preferenceAreas: [
      'sensory_preferences',
      'food_and_drink',
      'entertainment_choices',
      'routine_vs_variety',
      'comfort_items'
    ],
    
    // Communication voice elements
    voiceElements: [
      'favorite_expressions',
      'response_patterns',
      'conversation_topics',
      'communication_goals',
      'expression_methods'
    ],
    
    // Life context areas
    contextAreas: [
      'daily_routines',
      'support_needs',
      'challenge_areas',
      'relationship_style',
      'interests_and_passions'
    ]
  }
};

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { INTERVIEW_QUESTIONS, INTERVIEW_CONFIG };
} else if (typeof window !== 'undefined') {
  window.INTERVIEW_QUESTIONS = INTERVIEW_QUESTIONS;
  window.INTERVIEW_CONFIG = INTERVIEW_CONFIG;
}