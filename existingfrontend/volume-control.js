/**
 * Volume Control Module
 * Handles setting application volume based on user settings
 */

// Global variable to store the current application volume setting
let applicationVolumeLevel = 8; // Default to 8/10 (80%)

/**
 * Load application volume from user settings
 * @param {Object} settings - User settings object
 */
function loadApplicationVolumeFromSettings(settings) {
    if (settings && typeof settings.applicationVolume === 'number') {
        applicationVolumeLevel = Math.max(0, Math.min(10, settings.applicationVolume));
        console.log(`Application volume loaded from settings: ${applicationVolumeLevel}/10`);
    } else {
        console.log(`Using default application volume: ${applicationVolumeLevel}/10`);
    }
}

/**
 * Set the system audio volume to the configured application level
 * Note: This is a web API limitation - browsers don't allow direct volume control
 * This function prepares for future implementation or hybrid app integration
 */
function setApplicationVolume() {
    try {
        // Convert 0-10 scale to 0-1 scale for audio APIs
        const volumeLevel = applicationVolumeLevel / 10;
        
        console.log(`Setting application volume to ${applicationVolumeLevel}/10 (${Math.round(volumeLevel * 100)}%)`);
        
        // For web browsers, we can't directly control system volume
        // But we can prepare the value for use with audio elements
        if (window.speechSynthesis) {
            // Set speech synthesis volume if available
            const utteranceSettings = {
                volume: volumeLevel
            };
            
            // Store for use in speech synthesis calls
            window.applicationVolumeLevel = volumeLevel;
            console.log('Speech synthesis volume level set:', volumeLevel);
        }
        
        // Set audio element volumes throughout the app
        const audioElements = document.querySelectorAll('audio');
        audioElements.forEach(audio => {
            audio.volume = volumeLevel;
            console.log('Audio element volume set to:', volumeLevel);
        });
        
        // Dispatch custom event for other parts of the app to listen to
        window.dispatchEvent(new CustomEvent('applicationVolumeChanged', {
            detail: { volumeLevel: applicationVolumeLevel, normalizedVolume: volumeLevel }
        }));
        
        return true;
    } catch (error) {
        console.error('Error setting application volume:', error);
        return false;
    }
}

/**
 * Initialize application volume on page load
 * Should be called after settings are loaded
 */
function initializeApplicationVolume(settings = null) {
    if (settings) {
        loadApplicationVolumeFromSettings(settings);
    }
    setApplicationVolume();
}

/**
 * Update application volume and apply immediately
 * @param {number} newLevel - Volume level from 0-10
 */
function updateApplicationVolume(newLevel) {
    if (typeof newLevel === 'number' && newLevel >= 0 && newLevel <= 10) {
        applicationVolumeLevel = newLevel;
        setApplicationVolume();
        return true;
    } else {
        console.error('Invalid volume level. Must be between 0 and 10.');
        return false;
    }
}

/**
 * Get current application volume level
 * @returns {number} Volume level from 0-10
 */
function getCurrentApplicationVolume() {
    return applicationVolumeLevel;
}

/**
 * Get normalized volume level (0-1) for use with audio APIs
 * @returns {number} Volume level from 0-1
 */
function getNormalizedApplicationVolume() {
    return applicationVolumeLevel / 10;
}

// Export functions for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        loadApplicationVolumeFromSettings,
        setApplicationVolume,
        initializeApplicationVolume,
        updateApplicationVolume,
        getCurrentApplicationVolume,
        getNormalizedApplicationVolume
    };
}