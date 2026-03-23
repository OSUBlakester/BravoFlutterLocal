// Mood selection constants matching web app
class MoodOptions {
  static const String noMoodSelected = 'No Mood Selected';
  
  static const List<Map<String, String>> moodOptions = [
    {'name': 'Happy', 'emoji': '😊'},
    {'name': 'Sad', 'emoji': '😢'},
    {'name': 'Excited', 'emoji': '🤩'},
    {'name': 'Calm', 'emoji': '😌'},
    {'name': 'Angry', 'emoji': '😠'},
    {'name': 'Silly', 'emoji': '🤪'},
    {'name': 'Tired', 'emoji': '😴'},
    {'name': 'Bored', 'emoji': '😐'},
    {'name': 'Anxious', 'emoji': '😰'},
    {'name': 'Confused', 'emoji': '😕'},
    {'name': 'Surprised', 'emoji': '😲'},
    {'name': 'Proud', 'emoji': '😎'},
    {'name': 'Worried', 'emoji': '😟'},
    {'name': 'Cranky', 'emoji': '😤'},
    {'name': 'Peaceful', 'emoji': '🕊️'},
    {'name': 'Playful', 'emoji': '😄'},
    {'name': 'Frustrated', 'emoji': '😫'},
    {'name': 'Curious', 'emoji': '🤔'},
    {'name': 'Grateful', 'emoji': '🙏'},
    {'name': 'Lonely', 'emoji': '😔'},
    {'name': 'Content', 'emoji': '😊'},
  ];
  
  static List<String> get allMoodNames {
    return [noMoodSelected, ...moodOptions.map((mood) => mood['name']!)];
  }
  
  static String getMoodWithEmoji(String moodName) {
    if (moodName == noMoodSelected) return noMoodSelected;
    
    final mood = moodOptions.firstWhere(
      (mood) => mood['name'] == moodName,
      orElse: () => {'name': moodName, 'emoji': ''},
    );
    
    return '${mood['emoji']} ${mood['name']}';
  }
  
  static String getEmojiForMood(String moodName) {
    if (moodName == noMoodSelected) return '';
    
    final mood = moodOptions.firstWhere(
      (mood) => mood['name'] == moodName,
      orElse: () => {'name': moodName, 'emoji': ''},
    );
    
    return mood['emoji'] ?? '';
  }
}
