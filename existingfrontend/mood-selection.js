/**
 * Mood Selection Functionality
 * Displays a mood selection interface at session start when enabled
 */

// Predefined mood options with emojis and avatar mappings
const MOOD_OPTIONS = [
    { name: 'Happy', emoji: '😊', avatarEmotion: 'happy' },
    { name: 'Sad', emoji: '😢', avatarEmotion: 'sad' },
    { name: 'Excited', emoji: '🤩', avatarEmotion: 'excited' },
    { name: 'Calm', emoji: '😌', avatarEmotion: 'neutral' },
    { name: 'Angry', emoji: '😠', avatarEmotion: 'angry' },
    { name: 'Silly', emoji: '🤪', avatarEmotion: 'laughing' },
    { name: 'Tired', emoji: '😴', avatarEmotion: 'tired' },
    { name: 'Anxious', emoji: '😰', avatarEmotion: 'worried' },
    { name: 'Confused', emoji: '😕', avatarEmotion: 'confused' },
    { name: 'Surprised', emoji: '😲', avatarEmotion: 'surprised' },
    { name: 'Proud', emoji: '😎', avatarEmotion: 'proud' },
    { name: 'Worried', emoji: '😟', avatarEmotion: 'worried' },
    { name: 'Cranky', emoji: '😤', avatarEmotion: 'angry' },
    { name: 'Peaceful', emoji: '🕊️', avatarEmotion: 'neutral' },
    { name: 'Playful', emoji: '😄', avatarEmotion: 'laughing' },
    { name: 'Frustrated', emoji: '😫', avatarEmotion: 'disgusted' },
    { name: 'Curious', emoji: '🤔', avatarEmotion: 'thinking' },
    { name: 'Grateful', emoji: '🙏', avatarEmotion: 'love' },
    { name: 'Lonely', emoji: '😔', avatarEmotion: 'sad' },
    { name: 'Content', emoji: '😊', avatarEmotion: 'happy' }
];

// Export to global scope for use by other scripts
window.MOOD_OPTIONS = MOOD_OPTIONS;

class MoodSelection {
    constructor(settings = null) {
        this.selectedMood = null;
        this.onComplete = null;
        this.moodOverlay = null;
        this.settings = settings; // Store provided settings
        
        // Scanning variables (similar to gridpage.js)
        this.scanningInterval = null;
        this.currentButtonIndex = -1;
        this.currentlyScannedButton = null;
        this.moodButtons = [];
        this.defaultDelay = 3500; // Default scanning delay
        this.isScanning = false;
        this.ScanningOff = false; // Will be loaded from settings
        this.scanMode = 'auto'; // auto | step
        this.activeAnnouncementAudioContext = null;
        this.activeAnnouncementAudioSource = null;
        
        // Gamepad variables
        this.gamepadIndex = null;
        this.gamepadPollInterval = null;
        this.lastGamepadInputTime = 0;
        this.gamepadEnabled = false; // Track if we should handle gamepad input
        
        // Avatar generation variables
        this.baseAvatarConfig = null;
        this.emotionalCombinations = null;
        this.useAvatars = true; // Flag to enable/disable avatar integration
    }

    /**
     * Initialize avatar generation by loading the base avatar configuration
     * This method tries to get the current avatar from the avatar selector or uses defaults
     */
    async initializeAvatarGeneration() {
        try {
            // Try to get base avatar config from avatar selector if available
            if (window.AvatarSelector && window.avatarSelector) {
                this.baseAvatarConfig = { ...window.avatarSelector.currentConfig };
                this.emotionalCombinations = window.avatarSelector.emotionalCombinations;
                console.log('Using avatar selector configuration for mood buttons');
            } else {
                // Try to load avatar config from user data
                const fetchFunction = window.authenticatedFetch || fetch;
                try {
                    const aacUserId = sessionStorage.getItem('aacUserId');
                    const response = await fetchFunction('/api/user-info', {
                        method: 'GET',
                        headers: {
                            'X-User-ID': aacUserId
                        },
                        credentials: 'include'
                    });
                    
                    if (response.ok) {
                        const data = await response.json();
                        if (data.avatarConfig) {
                            this.baseAvatarConfig = data.avatarConfig;
                            console.log('Loaded avatar configuration from user data for mood buttons');
                        }
                    }
                } catch (error) {
                    console.log('Could not load avatar config from user data:', error);
                }
                
                // If no saved config, use defaults
                if (!this.baseAvatarConfig) {
                    this.baseAvatarConfig = {
                        avatarStyle: 'Circle',
                        topType: 'ShortHairShortFlat',
                        accessoriesType: 'Blank',
                        hairColor: 'BrownDark',
                        facialHairType: 'Blank',
                        facialHairColor: 'BrownDark',
                        clotheType: 'BlazerShirt',
                        clotheColor: 'BlueGray',
                        eyeType: 'Default',
                        eyebrowType: 'Default',
                        mouthType: 'Default',
                        skinColor: 'Light'
                    };
                    console.log('Using default avatar configuration for mood buttons');
                }
                
                // Define minimal emotional combinations if avatar selector not available
                this.emotionalCombinations = [
                    { name: 'happy', eyeType: 'Happy', eyebrowType: 'Default', mouthType: 'Smile' },
                    { name: 'sad', eyeType: 'Cry', eyebrowType: 'SadConcerned', mouthType: 'Sad' },
                    { name: 'angry', eyeType: 'Squint', eyebrowType: 'AngryNatural', mouthType: 'Grimace' },
                    { name: 'surprised', eyeType: 'Surprised', eyebrowType: 'RaisedExcited', mouthType: 'Disbelief' },
                    { name: 'excited', eyeType: 'Hearts', eyebrowType: 'RaisedExcited', mouthType: 'Smile' },
                    { name: 'neutral', eyeType: 'Default', eyebrowType: 'Default', mouthType: 'Default' },
                    { name: 'confused', eyeType: 'Dizzy', eyebrowType: 'RaisedExcitedNatural', mouthType: 'Concerned' },
                    { name: 'worried', eyeType: 'Side', eyebrowType: 'SadConcernedNatural', mouthType: 'Concerned' },
                    { name: 'laughing', eyeType: 'Squint', eyebrowType: 'Default', mouthType: 'Tongue' },
                    { name: 'proud', eyeType: 'Default', eyebrowType: 'RaisedExcited', mouthType: 'Smile' },
                    { name: 'tired', eyeType: 'EyeRoll', eyebrowType: 'Default', mouthType: 'Eating' },
                    { name: 'love', eyeType: 'Hearts', eyebrowType: 'Default', mouthType: 'Twinkle' },
                    { name: 'thinking', eyeType: 'Side', eyebrowType: 'FlatNatural', mouthType: 'Default' },
                    { name: 'disgusted', eyeType: 'Side', eyebrowType: 'AngryNatural', mouthType: 'Grimace' }
                ];
            }
        } catch (error) {
            console.warn('Failed to initialize avatar generation, falling back to emojis:', error);
            this.useAvatars = false;
        }
    }

    /**
     * Generate avatar URL for a specific mood
     * @param {string} avatarEmotion - The emotion to apply to the avatar
     * @returns {string} The avatar URL
     */
    generateMoodAvatarURL(avatarEmotion) {
        if (!this.useAvatars || !this.baseAvatarConfig || !this.emotionalCombinations) {
            return null;
        }

        try {
            const emotionalOverride = this.emotionalCombinations.find(e => e.name === avatarEmotion);
            if (!emotionalOverride) {
                console.warn(`Emotional combination not found: ${avatarEmotion}`);
                return null;
            }

            const params = new URLSearchParams();
            const config = { ...this.baseAvatarConfig };
            
            // Apply emotional override
            if (emotionalOverride.eyeType) config.eyeType = emotionalOverride.eyeType;
            if (emotionalOverride.eyebrowType) config.eyebrowType = emotionalOverride.eyebrowType;
            if (emotionalOverride.mouthType) config.mouthType = emotionalOverride.mouthType;
            
            for (const [key, value] of Object.entries(config)) {
                if (value) {
                    params.append(key, value);
                }
            }
            
            // Always ensure transparent background
            params.append('background', 'transparent');
            
            return `https://avataaars.io/?${params.toString()}`;
        } catch (error) {
            console.error('Error generating mood avatar URL:', error);
            return null;
        }
    }

    /**
     * Shows the mood selection interface
     * @param {Function} onComplete - Callback function called when mood selection is complete
     */
    async show(onComplete) {
        // Only overwrite onComplete if a new one is provided
        if (onComplete !== undefined) {
            this.onComplete = onComplete;
        }
        
        try {
            // Check if mood selection is enabled in settings
            const isEnabled = await this.isMoodSelectionEnabled();
            if (!isEnabled) {
                console.log('Mood selection is disabled in settings');
                if (this.onComplete) this.onComplete(null);
                return;
            }

            // Check if mood was already set this session
            const existingMood = sessionStorage.getItem('currentSessionMood');
            if (existingMood) {
                console.log('Mood already set for this session:', existingMood);
                // Use setTimeout to ensure onComplete callback is set before calling it
                setTimeout(() => {
                    if (this.onComplete) this.onComplete(existingMood);
                }, 0);
                return;
            }

            // Only show loading overlay if we're actually going to show mood selection
            const loadingOverlay = this.showLoadingOverlay();

            await this.createMoodInterface();
        } catch (error) {
            console.error('Error showing mood selection:', error);
            this.removeLoadingOverlay();
            if (this.onComplete) this.onComplete(null);
        }
    }

    /**
     * Checks if mood selection is enabled in settings
     */
    async isMoodSelectionEnabled() {
        try {
            // Use provided settings if available (from constructor)
            if (this.settings) {
                console.log('Using provided settings for mood selection');
                this.ScanningOff = this.settings.ScanningOff === true;
                this.scanMode = this.settings.scanMode === 'step' ? 'step' : 'auto';
                this.waitForSwitchToScan = this.settings.waitForSwitchToScan === true;
                this.defaultDelay = this.settings.scanDelay || 3500;
                return this.settings.enableMoodSelection === true;
            }
            
            // Otherwise fetch settings
            // Check if authenticatedFetch is available
            const fetchFunction = window.authenticatedFetch || fetch;
            
            const response = await fetchFunction('/api/settings', {
                method: 'GET',
                credentials: 'include'
            });
            
            if (response.ok) {
                const settings = await response.json();
                
                // Load scanning settings
                this.ScanningOff = settings.ScanningOff === true;
                this.scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
                this.waitForSwitchToScan = settings.waitForSwitchToScan === true;
                this.defaultDelay = settings.scanDelay || 3500;
                
                return settings.enableMoodSelection === true;
            }
        } catch (error) {
            console.error('Failed to check mood selection setting:', error);
        }
        return false; // Default to disabled if we can't check
    }

    /**
     * Pre-fetch all mood images in batch to avoid timeout issues
     * @param {Function} progressCallback - Optional callback to report progress (current, total)
     */
    async prefetchMoodImages(progressCallback = null) {
        // Check enablePictograms - try window.enablePictograms first, fallback to checking settings
        let pictogramsEnabled = false;
        if (typeof window.enablePictograms !== 'undefined') {
            pictogramsEnabled = window.enablePictograms;
            console.log('📷 Using window.enablePictograms:', pictogramsEnabled);
        } else {
            // Load from settings if not available yet
            try {
                const fetchFunction = window.authenticatedFetch || fetch;
                const aacUserId = sessionStorage.getItem('aacUserId');
                const response = await fetchFunction('/api/settings', {
                    method: 'GET',
                    headers: {
                        'X-User-ID': aacUserId
                    },
                    credentials: 'include'
                });
                if (response.ok) {
                    const settings = await response.json();
                    pictogramsEnabled = settings.enablePictograms === true;
                    console.log('📷 Loaded enablePictograms from settings:', pictogramsEnabled);
                }
            } catch (error) {
                console.warn('Failed to load enablePictograms setting:', error);
            }
        }
        
        if (!pictogramsEnabled) {
            console.log('Pictograms disabled, skipping mood image prefetch');
            return new Map(); // Return empty map
        }
        
        const imageMap = new Map();
        const moodNames = MOOD_OPTIONS.map(m => m.name);
        
        console.log('🎨 Pre-fetching mood images in batch...');
        
        let completed = 0;
        
        // Fetch images in parallel but with staggered timing to avoid overwhelming backend
        const promises = moodNames.map((name, index) => {
            return new Promise(resolve => {
                // Stagger requests by 50ms each (1 second total for all 20 moods)
                setTimeout(async () => {
                    try {
                        if (typeof getSymbolImageForText === 'function') {
                            const imageUrl = await getSymbolImageForText(name);
                            if (imageUrl) {
                                imageMap.set(name, imageUrl);
                                console.log(`✅ Pre-fetched image for mood: ${name}`);
                            } else {
                                console.log(`❌ No image found for mood: ${name}`);
                            }
                        }
                    } catch (error) {
                        console.warn(`Error pre-fetching mood image for ${name}:`, error);
                    }
                    completed++;
                    if (progressCallback) {
                        progressCallback(completed, moodNames.length);
                    }
                    resolve();
                }, index * 50); // 50ms stagger
            });
        });
        
        await Promise.all(promises);
        console.log(`🎨 Pre-fetch complete: ${imageMap.size}/${moodNames.length} mood images loaded`);
        
        return imageMap;
    }
    
    /**
     * Shows a loading overlay during mood image prefetch
     */
    showLoadingOverlay() {
        // Ensure document.body is ready
        if (!document.body) {
            console.warn('Document body not ready, deferring overlay creation');
            // Wait for DOM to be ready
            if (document.readyState === 'loading') {
                return new Promise(resolve => {
                    document.addEventListener('DOMContentLoaded', () => {
                        resolve(this.showLoadingOverlay());
                    });
                });
            }
            return null;
        }
        
        // Note: Loading overlay now defined in auth.html
        // Just return reference to it if it exists
        return document.getElementById('mood-loading-overlay');
    }
    
    /**
     * Updates loading progress
     */
    updateLoadingProgress(current, total) {
        const progressEl = document.getElementById('mood-loading-progress');
        if (progressEl) {
            const percent = Math.round((current / total) * 100);
            progressEl.textContent = `${percent}%`;
        }
    }
    
    /**
     * Removes loading overlay
     */
    removeLoadingOverlay() {
        const overlay = document.getElementById('mood-loading-overlay');
        if (overlay) {
            overlay.remove();
        }
    }

    /**
     * Creates the mood selection interface
     */
    async createMoodInterface() {
        try {
            // Initialize avatar generation
            await this.initializeAvatarGeneration();
            
            console.log('🎨 Starting mood image prefetch...');
            
            // Pre-fetch mood images to avoid timeouts during display
            const moodImageMap = await this.prefetchMoodImages((current, total) => {
                console.log(`📊 Progress: ${current}/${total}`);
                this.updateLoadingProgress(current, total);
            });
            
            console.log('✅ Mood image prefetch complete');
            
            // Remove loading overlay
            this.removeLoadingOverlay();
            
            // Remove existing overlay if it exists
            this.removeMoodInterface();

            // Create overlay
            this.moodOverlay = document.createElement('div');
            this.moodOverlay.className = 'mood-selection-overlay';
            this.moodOverlay.id = 'mood-selection-overlay';

            // Create container
            const container = document.createElement('div');
            container.className = 'mood-selection-container';

            // Create title
            const title = document.createElement('h2');
            title.className = 'mood-selection-title';
            title.textContent = 'How are you feeling today?';

            // Create subtitle
            const subtitle = document.createElement('p');
            subtitle.className = 'mood-selection-subtitle';
            subtitle.textContent = 'Select your current mood to help personalize your experience';

            // Create mood grid
            const moodGrid = document.createElement('div');
            moodGrid.className = 'mood-grid';

        // Add mood buttons with pre-fetched images
        for (const mood of MOOD_OPTIONS) {
            const button = document.createElement('button');
            button.className = 'mood-button';
            button.setAttribute('data-mood', mood.name);
            
            // Create image container
            const imageContainer = document.createElement('div');
            imageContainer.className = 'mood-image-container';
            
            // Check if we have a pre-fetched image for this mood
            const imageUrl = moodImageMap.get(mood.name);
            
            if (imageUrl) {
                // Use pre-fetched image
                const imageElement = document.createElement('img');
                imageElement.className = 'mood-image';
                imageElement.src = imageUrl;
                imageElement.alt = mood.name;
                
                // Fallback to emoji on image load error
                imageElement.onerror = () => {
                    console.warn(`Failed to load pre-fetched image for ${mood.name} - falling back to emoji`);
                    imageContainer.innerHTML = '';
                    const emojiSpan = document.createElement('span');
                    emojiSpan.className = 'mood-emoji';
                    emojiSpan.textContent = mood.emoji;
                    imageContainer.appendChild(emojiSpan);
                };
                
                imageContainer.appendChild(imageElement);
            } else {
                // No image available (either pictograms disabled, not found, or error) - use emoji
                const emojiSpan = document.createElement('span');
                emojiSpan.className = 'mood-emoji';
                emojiSpan.textContent = mood.emoji;
                imageContainer.appendChild(emojiSpan);
            }
            
            const name = document.createElement('div');
            name.className = 'mood-name';
            name.textContent = mood.name;
            
            button.appendChild(imageContainer);
            button.appendChild(name);
            
            button.addEventListener('click', () => this.selectMood(mood.name, button));
            moodGrid.appendChild(button);
        }

        // Create action buttons (only Skip button now)
        const actions = document.createElement('div');
        actions.className = 'mood-actions';

        const skipButton = document.createElement('button');
        skipButton.className = 'mood-action-button mood-skip-button';
        skipButton.textContent = 'Skip';
        skipButton.addEventListener('click', () => this.skipMoodSelection());

        actions.appendChild(skipButton);

        // Assemble the interface - Skip button at top
        container.appendChild(title);
        container.appendChild(actions); // Skip button after title
        container.appendChild(subtitle);
        container.appendChild(moodGrid);
        this.moodOverlay.appendChild(container);

        // Add to page
        document.body.appendChild(this.moodOverlay);

        // Store references to buttons for scanning - Skip button first
        this.moodButtons = [skipButton, ...moodGrid.querySelectorAll('.mood-button')];

        // Focus the modal container to capture keyboard events
        container.setAttribute('tabindex', '-1');
        
        // Add keydown event directly to the container to ensure we catch spacebar
        container.addEventListener('keydown', (event) => this.handleKeyPress(event));
        
        container.focus();

        // Setup gamepad support
        this.setupGamepadSupport();

        // Start scanning if enabled
        if (!this.ScanningOff) {
            // Check if we should wait for switch press before starting (only on first visit to this page)
            const scanningHasStarted = sessionStorage.getItem('bravoScanningStarted_mood') === 'true';
            
            if (this.waitForSwitchToScan && !scanningHasStarted) {
                console.log('Waiting for switch press to begin scanning...');
                this.waitingForInitialSwitch = true;
                // Play prompt in personal speaker
                this.speakText("Press switch to begin scanning", false, false); // personal speaker, not announcement
            } else {
                console.log('Starting mood selection scanning...');
                this.startScanning();
            }
        } else {
            // Focus first mood button for accessibility when scanning is off
            const firstButton = moodGrid.querySelector('.mood-button');
            if (firstButton) {
                firstButton.focus();
            }
        }
        } catch (error) {
            console.error('Error creating mood interface:', error);
            this.removeLoadingOverlay();
            // Call completion callback with null on error
            if (this.onComplete) {
                this.onComplete(null);
            }
        }
    }

    /**
     * Handles mood selection
     * @param {string} moodName - The selected mood name
     * @param {HTMLElement} buttonElement - The clicked button element
     */
    selectMood(moodName, buttonElement) {
        console.log('Mood selected:', moodName);
        
        // Stop scanning when mood is selected
        this.stopScanning();
        
        // Remove previous selection
        const previousSelected = this.moodOverlay.querySelector('.mood-button.selected');
        if (previousSelected) {
            previousSelected.classList.remove('selected');
        }

        // Add selection to clicked button
        buttonElement.classList.add('selected');
        this.selectedMood = moodName;

        // Show brief confirmation then proceed automatically
        setTimeout(() => {
            this.completeMoodSelection();
        }, 500); // Brief delay to show selection feedback
    }

    /**
     * Completes the mood selection process
     */
    async completeMoodSelection() {
        if (!this.selectedMood) {
            console.warn('No mood selected');
            return;
        }

        try {
            // Save mood to session storage
            sessionStorage.setItem('currentSessionMood', this.selectedMood);

            // Save mood to user info (optional - persists across sessions)
            await this.saveMoodToSettings(this.selectedMood);

            console.log('Mood selection completed:', this.selectedMood);
            
            // Remove interface
            this.removeMoodInterface();

            // Call completion callback
            console.log('DEBUG: onComplete callback exists?', !!this.onComplete);
            if (this.onComplete) {
                console.log('DEBUG: Calling onComplete with mood:', this.selectedMood);
                this.onComplete(this.selectedMood);
            } else {
                console.warn('DEBUG: No onComplete callback set!');
            }
        } catch (error) {
            console.error('Error completing mood selection:', error);
            // Continue anyway with session storage
            this.removeMoodInterface();
            if (this.onComplete) {
                this.onComplete(this.selectedMood);
            }
        }
    }

    /**
     * Skips the mood selection
     */
    skipMoodSelection() {
        console.log('Mood selection skipped');
        
        // Set session storage to indicate mood was skipped
        sessionStorage.setItem('currentSessionMood', 'none');
        
        // Remove interface
        this.removeMoodInterface();

        // Call completion callback with null
        if (this.onComplete) {
            this.onComplete(null);
        }
    }

    /**
     * Saves the selected mood to user info
     * @param {string} mood - The selected mood
     */
    async saveMoodToSettings(mood) {
        try {
            const aacUserId = sessionStorage.getItem('currentAacUserId') || sessionStorage.getItem('aacUserId');
            const firebaseToken = sessionStorage.getItem('firebaseIdToken');
            
            console.log('🔐 AUTH DEBUG - aacUserId:', aacUserId);
            console.log('🔐 AUTH DEBUG - firebaseToken exists:', !!firebaseToken);
            console.log('🔐 AUTH DEBUG - firebaseToken length:', firebaseToken ? firebaseToken.length : 0);
            
            if (!firebaseToken || !aacUserId) {
                console.warn('⚠️ Missing auth credentials. Firebase token:', !!firebaseToken, 'aacUserId:', !!aacUserId);
                console.warn('⚠️ Mood will be saved to sessionStorage only.');
                // Still save to sessionStorage for use during this session
                sessionStorage.setItem('currentSessionMood', mood);
                return;
            }
            
            const headers = {
                'Authorization': `Bearer ${firebaseToken}`,
                'X-User-ID': aacUserId,
                'Content-Type': 'application/json'
            };
            
            // First get current user state to preserve it
            const getCurrentResponse = await fetch('/get-user-current', {
                method: 'GET',
                headers: headers,
                credentials: 'include'
            });
            
            let currentLocation = "";
            let currentPeople = "";
            let currentActivity = "";
            
            if (getCurrentResponse.ok) {
                const current = await getCurrentResponse.json();
                currentLocation = current.location || "";
                currentPeople = current.people || "";
                currentActivity = current.activity || "";
            }
            
            // Save mood along with existing current state
            const response = await fetch('/user_current', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({
                    location: currentLocation,
                    people: currentPeople,
                    activity: currentActivity,
                    mood: mood
                }),
                credentials: 'include'
            });

            if (!response.ok) {
                console.warn('Failed to save mood to current state:', response.statusText);
            } else {
                console.log('✅ Mood saved successfully:', mood);
            }
        } catch (error) {
            console.warn('Error saving mood to current state:', error);
        }
    }

    /**
     * Start scanning through mood options and Skip button
     */
    startScanning() {
        if (this.ScanningOff || this.scanningInterval) {
            return;
        }

        // Speak initial prompt
        this.speakText("How are you feeling today?");

        this.currentButtonIndex = 0;
        this.isScanning = true;

        if (this.scanMode === 'step') {
            this.scanStep();
            return;
        }
        
        // Delay first scan step to allow initial prompt to finish
        setTimeout(() => {
            this.scanStep();
        }, 2000);
    }

    /**
     * Stop scanning
     */
    stopScanning() {
        if (this.scanningInterval) {
            clearTimeout(this.scanningInterval);
            this.scanningInterval = null;
        }
        
        // Remove highlight from currently scanned button
        if (this.currentlyScannedButton) {
            this.currentlyScannedButton.classList.remove('scan-highlight', 'scanning');
            this.currentlyScannedButton.style.border = '';
            this.currentlyScannedButton = null;
        }
        
        // Also remove highlights from all buttons as backup
        this.moodButtons.forEach(button => {
            button.classList.remove('scan-highlight', 'scanning');
            button.style.border = '';
        });
        
        this.isScanning = false;
    }

    /**
     * Scanning step - highlights current button and speaks it
     */
    scanStep() {
        if (this.ScanningOff || !this.moodButtons || this.moodButtons.length === 0) {
            return;
        }

        // Clear previous highlights and remove from currently scanned button
        if (this.currentlyScannedButton) {
            this.currentlyScannedButton.classList.remove('scan-highlight', 'scanning');
            this.currentlyScannedButton.style.border = '';
        }

        // Highlight current button
        this.currentlyScannedButton = this.moodButtons[this.currentButtonIndex];
        if (this.currentlyScannedButton) {
            this.currentlyScannedButton.classList.add('scan-highlight', 'scanning');
            this.currentlyScannedButton.style.border = '3px solid #007bff';
            
            console.log('Scanning mood button:', this.currentButtonIndex, this.currentlyScannedButton.textContent || this.currentlyScannedButton.getAttribute('data-mood'));
            
            // Speak the button text
            this.speakAndHighlight(this.currentlyScannedButton);
        }

        // Move to next button
        this.currentButtonIndex = (this.currentButtonIndex + 1) % this.moodButtons.length;

        // Schedule next scan step only in auto mode
        if (this.scanMode !== 'step') {
            this.scanningInterval = setTimeout(() => {
                this.scanStep();
            }, this.defaultDelay);
        }
    }

    /**
     * Helper function to convert Base64 to ArrayBuffer
     */
    base64ToArrayBuffer(base64) {
        const binaryString = window.atob(base64);
        const len = binaryString.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        return bytes.buffer;
    }

    /**
     * Backend TTS announce function for mood selection
     */
    async announce(textToAnnounce, announcementType = "system", recordHistory = false) {
        try {
            const fetchFunction = window.authenticatedFetch || fetch;
            const response = await fetchFunction('/play-audio', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text: textToAnnounce, routing_target: announcementType }),
            });

            if (!response.ok) {
                const errorBody = await response.json().catch(() => response.text());
                throw new Error(`Failed to synthesize audio: ${response.status} - ${JSON.stringify(errorBody)}`);
            }

            const jsonResponse = await response.json();
            const audioData = jsonResponse.audio_data;
            const sampleRate = jsonResponse.sample_rate || 22050;

            if (audioData) {
                const audioDataArrayBuffer = this.base64ToArrayBuffer(audioData);
                await this.playAudioToDevice(audioDataArrayBuffer, sampleRate, announcementType);
            }
        } catch (error) {
            console.error('Mood selection TTS error:', error);
            // Fallback to browser speech synthesis if backend fails
            this.fallbackToSpeechSynthesis(textToAnnounce);
        }
    }

    /**
     * Play audio using Web Audio API
     */
    async playAudioToDevice(audioDataBuffer, sampleRate, announcementType) {
        let audioContext;
        let source;

        try {
            audioContext = new (window.AudioContext || window.webkitAudioContext)();
            
            if (audioContext.state === 'suspended') {
                await audioContext.resume();
            }

            const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
            source = audioContext.createBufferSource();
            source.buffer = audioBuffer;
            source.connect(audioContext.destination);
            this.activeAnnouncementAudioContext = audioContext;
            this.activeAnnouncementAudioSource = source;
            source.start(0);

            return new Promise((resolve) => {
                source.onended = () => {
                    this.activeAnnouncementAudioSource = null;
                    if (this.activeAnnouncementAudioContext === audioContext) {
                        this.activeAnnouncementAudioContext = null;
                    }
                    if (audioContext && audioContext.state !== 'closed') {
                        audioContext.close();
                    }
                    resolve();
                };
            });
        } catch (error) {
            console.error('Audio playback error in mood selection:', error);
            if (audioContext && audioContext.state !== 'closed') {
                audioContext.close();
            }
            if (this.activeAnnouncementAudioContext === audioContext) {
                this.activeAnnouncementAudioContext = null;
                this.activeAnnouncementAudioSource = null;
            }
            throw error;
        }
    }

    interruptScanningAnnouncementPlayback() {
        if (window.speechSynthesis) {
            window.speechSynthesis.cancel();
        }

        if (this.activeAnnouncementAudioSource) {
            try {
                this.activeAnnouncementAudioSource.onended = null;
                this.activeAnnouncementAudioSource.stop(0);
            } catch (e) {
                // no-op
            }
            try {
                this.activeAnnouncementAudioSource.disconnect();
            } catch (e) {
                // no-op
            }
            this.activeAnnouncementAudioSource = null;
        }

        if (this.activeAnnouncementAudioContext && this.activeAnnouncementAudioContext.state !== 'closed') {
            this.activeAnnouncementAudioContext.close().catch(() => {});
        }
        this.activeAnnouncementAudioContext = null;
    }

    /**
     * Fallback to browser speech synthesis
     */
    fallbackToSpeechSynthesis(text) {
        if ('speechSynthesis' in window && text) {
            window.speechSynthesis.cancel();
            const utterance = new SpeechSynthesisUtterance(text);
            utterance.rate = 0.8;
            utterance.pitch = 1;
            utterance.volume = 0.8;
            window.speechSynthesis.speak(utterance);
        }
    }

    /**
     * Speak button text for auditory feedback
     */
    async speakAndHighlight(button) {
        if (!button) return;

        let textToSpeak;
        if (button.classList.contains('mood-button')) {
            const moodName = button.getAttribute('data-mood');
            textToSpeak = moodName; // Just say the mood name without "Mood:" prefix
        } else if (button.classList.contains('mood-skip-button')) {
            textToSpeak = 'Skip mood selection';
        } else {
            textToSpeak = button.textContent || button.innerText;
        }

        // Use backend TTS instead of browser speech synthesis
        try {
            await this.announce(textToSpeak, "system", false);
        } catch (error) {
            console.error('Error using backend TTS for mood scanning:', error);
        }

        console.log('Scanning:', textToSpeak);
    }

    /**
     * Speak text using backend TTS
     */
    async speakText(text) {
        console.log('Speaking:', text);
        try {
            await this.announce(text, "system", false);
        } catch (error) {
            console.error('Error using backend TTS:', error);
            // Fallback to browser speech synthesis
            this.fallbackToSpeechSynthesis(text);
        }
    }

    /**
     * Setup gamepad listeners for mood selection
     */
    setupGamepadSupport() {
        console.log('Setting up gamepad support for mood selection');
        this.gamepadEnabled = true;
        
        // Check for already connected gamepads
        const gamepads = navigator.getGamepads();
        for (let i = 0; i < gamepads.length; i++) {
            if (gamepads[i]) {
                console.log("Found connected gamepad for mood selection:", i, gamepads[i].id);
                if (this.gamepadIndex === null) {
                    this.gamepadIndex = i;
                    this.startGamepadPolling();
                }
                break;
            }
        }
        
        // If no gamepad is found, that's okay - user can still use keyboard/touch
        if (this.gamepadIndex === null) {
            console.log('No gamepad detected for mood selection, keyboard/touch input will work');
        }
    }

    /**
     * Start gamepad polling for mood selection
     */
    startGamepadPolling() {
        if (this.gamepadPollInterval !== null || !this.gamepadEnabled) return;
        console.log("Starting mood selection gamepad polling for index:", this.gamepadIndex);
        let lastButtonState = false;

        const pollGamepads = () => {
            // Stop polling if mood selection is no longer active
            if (!this.moodOverlay || !this.gamepadEnabled) {
                this.stopGamepadPolling();
                return;
            }
            
            if (this.gamepadIndex === null) {
                this.stopGamepadPolling();
                return;
            }
            
            const gp = navigator.getGamepads()[this.gamepadIndex];
            if (!gp) {
                this.gamepadPollInterval = requestAnimationFrame(pollGamepads);
                return;
            }

            const currentButtonState = gp.buttons[0] && gp.buttons[0].pressed;
            if (currentButtonState && !lastButtonState) {
                const now = Date.now();
                if (now - this.lastGamepadInputTime > 300) { // Rate limit
                    this.handleGamepadInput();
                    this.lastGamepadInputTime = now;
                } else {
                    console.log("Mood selection gamepad press ignored (rate limit).");
                }
            }
            
            lastButtonState = currentButtonState;
            this.gamepadPollInterval = requestAnimationFrame(pollGamepads);
        };
        
        this.gamepadPollInterval = requestAnimationFrame(pollGamepads);
    }

    /**
     * Stop gamepad polling for mood selection
     */
    stopGamepadPolling() {
        if (this.gamepadPollInterval !== null) {
            cancelAnimationFrame(this.gamepadPollInterval);
            this.gamepadPollInterval = null;
            console.log("Stopped mood selection gamepad polling.");
        }
    }

    /**
     * Handle gamepad input for mood selection
     */
    handleGamepadInput() {
        console.log('Gamepad input detected in mood selection, ScanningOff:', this.ScanningOff, 'currentlyScannedButton:', this.currentlyScannedButton);

        // If waiting for initial switch press, start scanning now
        if (this.waitingForInitialSwitch) {
            console.log('Initial switch press detected - starting scanning on mood page');
            this.waitingForInitialSwitch = false;
            sessionStorage.setItem('bravoScanningStarted_mood', 'true');
            this.startScanning();
            return;
        }

        if (this.ScanningOff) {
            // Manual selection mode - activate focused button
            const focusedButton = document.activeElement;
            console.log('Manual mode - focused button:', focusedButton);
            
            if (focusedButton && focusedButton.classList.contains('mood-button')) {
                const moodName = focusedButton.getAttribute('data-mood');
                this.selectMood(moodName, focusedButton);
            } else if (focusedButton && focusedButton.classList.contains('mood-skip-button')) {
                this.skipMoodSelection();
            } else {
                // If no specific button is focused, focus the first mood button
                const firstButton = this.moodOverlay.querySelector('.mood-button');
                if (firstButton) {
                    firstButton.focus();
                }
            }
        } else {
            // Scanning mode - select current highlighted button
            if (this.currentlyScannedButton) {
                const buttonToActivate = this.currentlyScannedButton;
                console.log("Mood selection: Gamepad pressed, activating button:", buttonToActivate.textContent || buttonToActivate.getAttribute('data-mood'));
                
                // Add visual feedback
                buttonToActivate.classList.add('active');
                setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
                
                // Activate the button
                buttonToActivate.click();
            } else {
                console.log('No currently scanned button available in mood selection');
            }
        }
    }

    /**
     * Handle keyboard navigation and scanning controls
     */
    handleKeyPress(event) {
        // Only handle events when mood selection is active
        if (!this.moodOverlay || this.moodOverlay.style.display === 'none') {
            return;
        }

        console.log('Mood selection keypress:', event.code, 'target:', event.target);

        // Prevent all default behaviors for space, enter, and arrows when modal is active
        if (['Space', 'Tab', 'Enter', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Escape'].includes(event.code)) {
            event.preventDefault();
            event.stopPropagation();
            event.stopImmediatePropagation();
        }

        switch (event.code) {
            case 'Tab':
                if (this.scanMode === 'step') {
                    this.interruptScanningAnnouncementPlayback();
                    if (this.waitingForInitialSwitch) {
                        this.waitingForInitialSwitch = false;
                        sessionStorage.setItem('bravoScanningStarted_mood', 'true');
                        this.startScanning();
                    } else if (!this.ScanningOff) {
                        if (!this.currentlyScannedButton) {
                            this.startScanning();
                        } else {
                            this.scanStep();
                        }
                    }
                }
                break;

            case 'Space':
                console.log('Space pressed in mood selection, ScanningOff:', this.ScanningOff, 'currentlyScannedButton:', this.currentlyScannedButton);

                // If waiting for initial switch press, start scanning now
                if (this.waitingForInitialSwitch) {
                    console.log('Initial spacebar press detected - starting scanning on mood page');
                    this.waitingForInitialSwitch = false;
                    sessionStorage.setItem('bravoScanningStarted_mood', 'true');
                    this.startScanning();
                    event.preventDefault();
                    return;
                }

                if (this.ScanningOff) {
                    // Manual selection mode
                    const focusedButton = document.activeElement;
                    console.log('Manual mode - focused button:', focusedButton);
                    if (focusedButton && focusedButton.classList.contains('mood-button')) {
                        const moodName = focusedButton.getAttribute('data-mood');
                        this.selectMood(moodName, focusedButton);
                    } else if (focusedButton && focusedButton.classList.contains('mood-skip-button')) {
                        this.skipMoodSelection();
                    } else {
                        // If no specific button is focused, focus the first mood button
                        const firstButton = this.moodOverlay.querySelector('.mood-button');
                        if (firstButton) {
                            firstButton.focus();
                        }
                    }
                } else {
                    // Scanning mode - select current highlighted button
                    if (this.currentlyScannedButton) {
                        const buttonToActivate = this.currentlyScannedButton;
                        console.log("Mood selection: Spacebar pressed, activating button:", buttonToActivate.textContent || buttonToActivate.getAttribute('data-mood'));
                        buttonToActivate.click();
                        buttonToActivate.classList.add('active');
                        setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
                    } else {
                        console.log('No currently scanned button available');
                    }
                }
                break;

            case 'Enter':
                // Same logic as Space for Enter key
                if (this.ScanningOff) {
                    const focusedButton = document.activeElement;
                    if (focusedButton && focusedButton.classList.contains('mood-button')) {
                        const moodName = focusedButton.getAttribute('data-mood');
                        this.selectMood(moodName, focusedButton);
                    } else if (focusedButton && focusedButton.classList.contains('mood-skip-button')) {
                        this.skipMoodSelection();
                    }
                } else {
                    if (this.currentlyScannedButton) {
                        this.currentlyScannedButton.click();
                    }
                }
                break;

            case 'Escape':
                this.skipMoodSelection();
                break;

            case 'ArrowRight':
            case 'ArrowDown':
                if (this.ScanningOff) {
                    this.navigateButtons(1);
                }
                break;

            case 'ArrowLeft':
            case 'ArrowUp':
                if (this.ScanningOff) {
                    this.navigateButtons(-1);
                }
                break;
        }
    }

    /**
     * Navigate between buttons manually (when scanning is off)
     */
    navigateButtons(direction) {
        const currentFocused = document.activeElement;
        const currentIndex = this.moodButtons.indexOf(currentFocused);
        
        if (currentIndex >= 0) {
            const nextIndex = (currentIndex + direction + this.moodButtons.length) % this.moodButtons.length;
            this.moodButtons[nextIndex].focus();
        } else {
            // Focus first button if none focused
            this.moodButtons[0].focus();
        }
    }
    removeMoodInterface() {
        // Stop scanning
        this.stopScanning();
        
        // Stop gamepad polling and disable gamepad support
        this.gamepadEnabled = false;
        this.stopGamepadPolling();
        this.gamepadIndex = null;
        
        // Remove interface (this will automatically remove the container event listener)
        if (this.moodOverlay) {
            this.moodOverlay.remove();
            this.moodOverlay = null;
        }
        
        // Clear button references
        this.moodButtons = [];
        this.currentButtonIndex = 0;
    }

    /**
     * Gets the current session mood
     * @returns {string|null} The current mood or null if none set
     */
    static getCurrentMood() {
        const mood = sessionStorage.getItem('currentSessionMood');
        return mood === 'none' ? null : mood;
    }

    /**
     * Clears the current session mood (useful for testing or admin reset)
     */
    static clearCurrentMood() {
        sessionStorage.removeItem('currentSessionMood');
    }
}

// Global instance
let globalMoodSelection = null;

// Initialize when script loads or when DOM is ready
function initializeMoodSelection() {
    if (!globalMoodSelection) {
        globalMoodSelection = new MoodSelection();
        console.log('Global mood selection initialized');
    }
}

// Initialize immediately if DOM is already loaded, otherwise wait for DOMContentLoaded
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeMoodSelection);
} else {
    // DOM is already ready
    initializeMoodSelection();
}

/**
 * Global function to show mood selection (used by other scripts)
 * @param {Function} onComplete - Callback function when mood selection is complete
 */
function showMoodSelection(onComplete) {
    if (globalMoodSelection) {
        globalMoodSelection.show(onComplete);
    } else {
        console.log('Mood selection not yet initialized, waiting...');
        // Wait for initialization with a timeout
        let attempts = 0;
        const maxAttempts = 50; // 5 seconds max wait
        const checkInterval = setInterval(() => {
            attempts++;
            if (globalMoodSelection) {
                clearInterval(checkInterval);
                console.log('Mood selection now available, showing...');
                globalMoodSelection.show(onComplete);
            } else if (attempts >= maxAttempts) {
                clearInterval(checkInterval);
                console.warn('Mood selection initialization timed out');
                if (onComplete) onComplete(null);
            }
        }, 100);
    }
}

/**
 * Global function to get current mood (used by other scripts)
 * @returns {string|null} The current mood or null if none set
 */
function getCurrentMood() {
    return MoodSelection.getCurrentMood();
}

/**
 * Global function to clear current mood (used by admin scripts)
 */
function clearCurrentMood() {
    MoodSelection.clearCurrentMood();
}

// Export for use in other modules
window.MoodSelection = MoodSelection;
window.showMoodSelection = showMoodSelection;
window.getCurrentMood = getCurrentMood;
window.clearCurrentMood = clearCurrentMood;
