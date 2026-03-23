// Family & Friends Interview Questions
// Specialized interview system for collecting information about family members and friends
// to populate the user_info page Friends & Family section

const FAMILY_FRIENDS_INTERVIEW_QUESTIONS = [
  {
    id: 'person_name',
    question: 'What does the person using the application call this person?',
    category: 'basic',
    required: true,
    followUp: 'Do you use their first name, a nickname, or something special like Mom, Dad, etc.?'
  },
  {
    id: 'relationship',
    question: 'What is this person\'s relationship to the person using the application?',
    category: 'basic',
    required: true,
    followUp: 'For example: mother, father, sister, brother, friend, teacher, caregiver, etc.'
  },
  {
    id: 'about_person',
    question: 'Tell me about this person. What do they like or dislike? Do they have any hobbies or interests? What kinds of things do you talk about with them?',
    category: 'details',
    required: true,
    followUp: 'What makes them special? What do you enjoy doing together or talking about?'
  },
  {
    id: 'birthday',
    question: 'When is this person\'s birthday? Just the month and day is fine.',
    category: 'details',
    required: false,
    followUp: 'For example: January 15th, or March 22nd. Say "I don\'t know" if you\'re not sure.'
  }
];

// Configuration for the single-person interview
const FAMILY_FRIENDS_INTERVIEW_CONFIG = {
  title: "Add Person Interview",
  description: "Tell us about one important person in your life and we'll add them to your Friends & Family list.",
  estimatedTime: "2-3 minutes",
  
  // Encouragement prompts
  encouragementPrompts: [
    "Great! Tell me more about them.",
    "That's helpful information!",
    "Perfect, what else can you tell me?",
    "Excellent! One more question.",
    "Thank you for sharing!"
  ]
};

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    FAMILY_FRIENDS_INTERVIEW_QUESTIONS,
    FAMILY_FRIENDS_INTERVIEW_CONFIG
  };
}