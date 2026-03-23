# Sight Words Integration Guide

## Overview

The Sight Words feature has been integrated into the Bravo AAC application to provide better support for early readers. This feature ensures that Dolch sight words are displayed as text-only buttons (without pictograms) even when the "Enable AAC Pictograms" setting is turned on.

## What are Sight Words?

Sight words are commonly used words that readers should recognize instantly without having to sound them out. The Dolch Sight Word list, developed by Dr. Edward William Dolch in the 1930s-40s, contains 220 "service words" plus 95 high-frequency nouns that comprise 80% of the words found in typical children's books.

## Why Text-Only for Sight Words?

For sight words, displaying only text (without pictograms) is pedagogically beneficial because:
- **Recognition Training**: Users learn to recognize the word by its visual form
- **Reading Development**: Builds automatic word recognition skills
- **Focus Enhancement**: Removes visual distractions from the learning process
- **Educational Standards**: Aligns with sight word teaching best practices

## Grade Level System

The sight words are organized by grade levels with **cumulative inclusion**:

| Grade Level | Words Included | Total Count |
|------------|---------------|-------------|
| Pre-Kindergarten | Pre-K only | 40 words |
| Kindergarten | Pre-K + K | 92 words |
| First Grade | Pre-K + K + 1st | 133 words |
| Second Grade | Pre-K + K + 1st + 2nd | 179 words |
| Third Grade | Pre-K + K + 1st + 2nd + 3rd | 220 words |
| Third Grade + Nouns | All levels + nouns | 315 words |

### Sample Words by Level

**Pre-Kindergarten (40 words):**
- a, and, away, big, blue, can, come, down, find, for, funny, go, help, here, I, in, is, it, jump, little, look, make, me, my, not, one, play, red, run, said, see, the, three, to, two, up, we, where, yellow, you

**Kindergarten (52 additional words):**
- all, am, are, at, ate, be, black, brown, but, came, did, do, eat, four, get, good, have, he, into, like, must, new, no, now, on, our, out, please, pretty, ran, ride, saw, say, she, so, soon, that, there, they, this, too, under, want, was, well, went, what, white, who, will, with, yes

## Admin Configuration

### Setting the Grade Level

1. **Access Admin Settings**: Go to `/static/admin_settings.html`
2. **Find Sight Words Section**: Look for "Sight Words Grade Level" dropdown
3. **Select Appropriate Level**: Choose based on user's reading level
4. **Save Settings**: Click "Save Settings" button

### Default Setting

- **Default Grade Level**: Pre-Kindergarten
- **Default Behavior**: Only Pre-K sight words are text-only
- **Fallback**: If grade level is invalid, defaults to Pre-K

## How It Works

### Decision Logic

When rendering a communication button:

1. **Check if pictograms are enabled** (`enablePictograms = true`)
2. **Check if text is a sight word** using current grade level setting
3. **If sight word**: Force text-only display (no pictogram)
4. **If not sight word**: Use normal pictogram logic

### Matching Algorithm

The system checks if text is a sight word using these rules:

1. **Direct Match**: Exact word match (case-insensitive)
2. **Single Word**: For single words, checks against sight word list
3. **Multi-Word Phrases**: ALL words must be sight words for phrase to be text-only
   - Example: "I go" → text-only (both "I" and "go" are sight words)
   - Example: "I like dinosaurs" → shows pictogram ("dinosaurs" not a sight word)

### Case Sensitivity

The system handles various text formats:
- **Lowercase**: "the", "and", "go"
- **Uppercase**: "THE", "AND", "GO"  
- **Capitalized**: "The", "And", "Go"
- **With spaces**: "  the  ", "and  "

## Technical Implementation

### Files Modified/Added

**Backend (Server-side):**
- `server.py`: Added `sightWordGradeLevel` setting to defaults and model
- `static/dolch_sight_words.json`: Complete Dolch word lists and grade configurations

**Frontend (Client-side):**
- `static/sight-word-service.js`: Core sight word checking service
- `static/gridpage.js`: Updated `getPictogramForText()` to check sight words
- `static/freestyle.js`: Updated `getPictogramForText()` to check sight words
- `static/admin_settings.html`: Added grade level selection UI
- `static/admin_settings.js`: Added grade level setting handling

**HTML Updates:**
- `static/gridpage.html`: Included sight-word-service.js
- `static/freestyle.html`: Included sight-word-service.js
- `static/admin_settings.html`: Included sight-word-service.js

### API Integration

The sight word service automatically:
- Loads user settings from `/api/settings`
- Updates when admin changes grade level
- Synchronizes across all pages that use pictograms

## Testing

### Test Interface

Access the test interface at: `/static/sight-word-test.html`

**Features:**
- Test individual words
- Run comprehensive test suite
- Change grade levels dynamically
- View all current sight words
- See real-time results

### Manual Testing

1. **Enable Pictograms**: Go to admin settings, enable AAC pictograms
2. **Set Grade Level**: Choose a specific sight word grade level
3. **Test Sight Words**: Navigate to communication pages
4. **Verify Behavior**: 
   - Sight words show text-only
   - Non-sight words show pictograms
   - Mixed phrases behave correctly

### Test Cases

```javascript
// These should be text-only (sight words)
"the", "I", "go", "and", "you", "is"
"I go", "the big red", "you and me"

// These should show pictograms (not sight words)
"elephant", "computer", "dinosaur"
"I like dinosaurs", "the elephant"
```

## User Impact

### For Administrators

**Benefits:**
- **Educational Alignment**: Supports proper sight word instruction
- **Flexible Control**: Adjust grade level as user progresses
- **Easy Management**: Simple dropdown selection

**Considerations:**
- Choose appropriate grade level for user
- Update grade level as reading skills improve
- Monitor effectiveness with user

### For AAC Users

**Benefits:**
- **Better Learning**: Sight words display optimally for recognition
- **Consistent Experience**: Non-sight words still have visual support
- **Progressive Development**: Grade level can advance with skills

**User Experience:**
- Transparent to user (automatic behavior)
- Seamless integration with existing pictogram system
- No additional complexity in interface

## Configuration Examples

### Scenario 1: Beginning Reader
```json
{
  "enablePictograms": true,
  "sightWordGradeLevel": "pre_k"
}
```
**Result**: Only 40 most basic sight words are text-only

### Scenario 2: Intermediate Reader  
```json
{
  "enablePictograms": true,
  "sightWordGradeLevel": "first_grade"
}
```
**Result**: 133 cumulative sight words are text-only

### Scenario 3: Advanced Reader
```json
{
  "enablePictograms": true,
  "sightWordGradeLevel": "third_grade_with_nouns"
}
```
**Result**: All 315 Dolch words are text-only

### Scenario 4: Pictograms Disabled
```json
{
  "enablePictograms": false,
  "sightWordGradeLevel": "kindergarten"
}
```
**Result**: All buttons are text-only (sight word setting has no effect)

## Troubleshooting

### Common Issues

**Sight Words Showing Pictograms:**
- Verify `enablePictograms` is true
- Check grade level setting includes the word
- Clear browser cache and reload
- Check browser console for JavaScript errors

**Grade Level Not Changing:**
- Ensure settings are saved successfully
- Check that sight-word-service.js is loaded
- Verify no JavaScript errors in console
- Try refreshing the page after settings change

**Test Interface Not Working:**
- Confirm file at `/static/sight-word-test.html`
- Check that `/static/dolch_sight_words.json` is accessible
- Verify sight-word-service.js is loading correctly

### Debug Information

**Browser Console Commands:**
```javascript
// Check if service is loaded
console.log(window.isSightWord);

// Test a specific word
window.isSightWord("the");

// Get current grade level info
window.getSightWordInfo();

// Get all sight words for current level
window.globalSightWordService.getAllSightWords();
```

**Network Tab:**
- Verify `/static/dolch_sight_words.json` loads successfully
- Check `/api/settings` returns sight word grade level

## Future Enhancements

### Potential Improvements

1. **Custom Word Lists**: Allow admins to add/remove specific words
2. **Progress Tracking**: Monitor which sight words user struggles with
3. **Automatic Advancement**: Progress grade level based on performance
4. **Multi-Language Support**: Add sight word lists for other languages
5. **Visual Indicators**: Show when words are being treated as sight words
6. **Analytics**: Track sight word recognition patterns

### Integration Opportunities

1. **Assessment Tools**: Integration with reading assessment systems
2. **Learning Management**: Connect to educational progress tracking
3. **Parent Dashboard**: Show sight word progress to parents/caregivers
4. **Therapist Tools**: Provide sight word usage reports for therapy sessions

## Support and Maintenance

### Monitoring

- Check browser console for sight word service errors
- Monitor settings API for grade level updates
- Verify Dolch words file accessibility

### Updates

- Grade level changes take effect immediately
- New deployments preserve user settings
- Dolch word list is static (based on educational standard)

### Backup and Recovery

- Sight word settings stored in user settings
- Dolch words file included in deployment
- Default fallback to Pre-K level if issues occur