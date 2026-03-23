/*
 * Sight Word Service - Dolch Sight Words Integration
 * Handles checking if text should be displayed as text-only (no pictograms)
 * based on Dolch sight word lists and user settings.
 */

class SightWordService {
    constructor() {
        this.dolchWords = null;
        this.currentGradeLevel = 'pre_k';
        this.isInitialized = false;
        this.sightWordSet = new Set();
        this.init();
    }

    async init() {
        try {
            await this.loadDolchWords();
            await this.loadUserSettings();
            this.isInitialized = true;
            console.log('Sight Word Service initialized with grade level:', this.currentGradeLevel);
        } catch (error) {
            console.error('Failed to initialize Sight Word Service:', error);
        }
    }

    async loadDolchWords() {
        try {
            const response = await fetch('/static/dolch_sight_words.json');
            if (!response.ok) {
                throw new Error(`Failed to load Dolch words: ${response.status}`);
            }
            this.dolchWords = await response.json();
        } catch (error) {
            console.error('Error loading Dolch sight words:', error);
            // Fallback to minimal word set
            this.dolchWords = {
                dolch_sight_words: {
                    pre_k: ["a", "and", "the", "to", "I", "you", "it", "in", "is", "go"]
                },
                grade_levels: {
                    pre_k: { includes: ["pre_k"] }
                }
            };
        }
    }

    async loadUserSettings() {
        try {
            const fetchFunction = window.authenticatedFetch || fetch;
            const response = await fetchFunction('/api/settings', {
                method: 'GET',
                credentials: 'include'
            });
            
            if (response.ok) {
                const settings = await response.json();
                this.updateGradeLevel(settings.sightWordGradeLevel || 'pre_k');
            }
        } catch (error) {
            console.error('Failed to load sight word settings:', error);
            this.updateGradeLevel('pre_k'); // Default fallback
        }
    }

    updateGradeLevel(gradeLevel) {
        if (!this.dolchWords || !this.dolchWords.grade_levels[gradeLevel]) {
            console.warn('Invalid grade level:', gradeLevel, 'falling back to pre_k');
            gradeLevel = 'pre_k';
        }

        this.currentGradeLevel = gradeLevel;
        this.buildSightWordSet();
        console.log(`Sight word grade level updated to: ${gradeLevel}, total words: ${this.sightWordSet.size}`);
    }

    buildSightWordSet() {
        this.sightWordSet.clear();
        
        if (!this.dolchWords) return;

        const gradeConfig = this.dolchWords.grade_levels[this.currentGradeLevel];
        if (!gradeConfig) return;

        // Add all words from included grade levels
        for (const level of gradeConfig.includes) {
            const wordsArray = this.dolchWords.dolch_sight_words[level];
            if (wordsArray) {
                wordsArray.forEach(word => {
                    // Store normalized versions for matching
                    this.sightWordSet.add(word.toLowerCase());
                    this.sightWordSet.add(word.toUpperCase());
                    this.sightWordSet.add(word.charAt(0).toUpperCase() + word.slice(1).toLowerCase());
                });
            }
        }
    }

    /**
     * Check if a text string is a sight word and should be displayed text-only
     * @param {string} text - The button text to check
     * @returns {boolean} - True if text should be text-only (no pictograms)
     */
    isSightWord(text) {
        if (!this.isInitialized || !text) return false;

        // Normalize the text for checking
        const normalizedText = text.trim();
        
        // Direct match check
        if (this.sightWordSet.has(normalizedText)) {
            return true;
        }

        // Check if it's a single word that matches
        const words = normalizedText.split(/\s+/);
        if (words.length === 1) {
            return this.sightWordSet.has(words[0]);
        }

        // For multi-word phrases, check if ALL words are sight words
        // This ensures that phrases like "I go" are treated as sight words
        // if both "I" and "go" are in the sight word list
        const allWordsSightWords = words.every(word => {
            const cleanWord = word.replace(/[^\w]/g, '').trim(); // Remove punctuation
            return cleanWord && this.sightWordSet.has(cleanWord);
        });

        return allWordsSightWords;
    }

    /**
     * Update settings when user changes sight word grade level
     * @param {Object} settings - Settings object containing sightWordGradeLevel
     */
    updateSettings(settings) {
        if (settings.sightWordGradeLevel !== undefined) {
            this.updateGradeLevel(settings.sightWordGradeLevel);
        }
    }

    /**
     * Get current grade level info
     * @returns {Object} - Grade level information
     */
    getCurrentGradeLevelInfo() {
        if (!this.dolchWords || !this.dolchWords.grade_levels[this.currentGradeLevel]) {
            return { display_name: 'Pre-Kindergarten', word_count: 0 };
        }

        const config = this.dolchWords.grade_levels[this.currentGradeLevel];
        return {
            display_name: config.display_name,
            word_count: this.sightWordSet.size / 3, // Divide by 3 since we store 3 versions of each word
            includes: config.includes
        };
    }

    /**
     * Get all sight words for current grade level (for debugging/testing)
     * @returns {Array} - Array of sight words
     */
    getAllSightWords() {
        const uniqueWords = new Set();
        if (!this.dolchWords) return [];

        const gradeConfig = this.dolchWords.grade_levels[this.currentGradeLevel];
        if (!gradeConfig) return [];

        for (const level of gradeConfig.includes) {
            const wordsArray = this.dolchWords.dolch_sight_words[level];
            if (wordsArray) {
                wordsArray.forEach(word => uniqueWords.add(word.toLowerCase()));
            }
        }

        return Array.from(uniqueWords).sort();
    }
}

// Create global instance
const globalSightWordService = new SightWordService();

// Global functions for easy access
window.isSightWord = function(text) {
    return globalSightWordService.isSightWord(text);
};

window.updateSightWordSettings = function(settings) {
    globalSightWordService.updateSettings(settings);
};

window.getSightWordInfo = function() {
    return globalSightWordService.getCurrentGradeLevelInfo();
};

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { SightWordService, globalSightWordService };
}