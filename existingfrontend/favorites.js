// favorites.js - Complete implementation matching gridpage structure
let currentUser = null;
let userSettings = {};
let currentFavoritesButtons = [];
let announcementQueue = [];
let isProcessingQueue = false;
let speechSynthesis = window.speechSynthesis;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

// Audio context variable for resume functionality
let audioContextResumeAttempted = false;

// Scanning variables (EXACTLY from gridpage.js)
let currentlyScannedButton = null; // Tracks the currently highlighted button
let defaultDelay = 3500; // Default auditory scan delay (ms) - Loaded from settings
let scanningInterval; // Holds the interval ID for scanning
let currentButtonIndex = -1; // Tracks the index for scanning
let scanCycleCount = 0; // Tracks how many complete cycles have been performed
let scanLoopLimit = 0; // 0 = unlimited, 1-10 = limit cycles
let isPausedFromScanLimit = false; // Flag to track if scanning is paused due to scan limit
let ScanningOff = false; // Default scanning state
let scanMode = 'auto'; // auto | step
let gridColumns = 10; // Default number of grid columns for button sizing

// Speech recognition variables (from gridpage.js)
let recognition = null;
let isSettingUpRecognition = false;
let listeningForQuestion = false;
let wakeWordInterjection = "hey";
let wakeWordName = "bravo";

// Authentication variables (matching gridpage.js)
let currentAacUserId = null;
let firebaseIdToken = null;
const AAC_USER_ID_SESSION_KEY = "currentAacUserId";
const FIREBASE_TOKEN_SESSION_KEY = "firebaseIdToken";
const SELECTED_DISPLAY_NAME_SESSION_KEY = "selectedDisplayName";

// DOM elements
let gridContainer;
let speechHistoryElement;
let questionDisplayElement;

// --- Global AudioContext Resume Helper ---
// This function tries to resume the AudioContext on first user gesture.
function tryResumeAudioContext() {
    if (window.AudioContext && !audioContextResumeAttempted) {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') {
            audioContext.resume().then(() => {
                console.log('AudioContext resumed via user gesture.');
            }).catch(e => {
                console.warn('Failed to auto-resume AudioContext on initial gesture:', e);
            });
        }
        audioContextResumeAttempted = true; // Ensure this only runs once per page load
    }
}

// Initialize the page
document.addEventListener('DOMContentLoaded', async function() {
    console.log('DOM loaded, initializing favorites page...');
    
    // Get DOM elements
    gridContainer = document.getElementById('gridContainer');
    speechHistoryElement = document.getElementById('speech-history');
    questionDisplayElement = document.getElementById('question-display');
    
    if (!gridContainer || !speechHistoryElement || !questionDisplayElement) {
        console.error('Required DOM elements not found');
        return;
    }
    
    // Initialize authentication and load data
    const userReady = await initializeUserContext();
    if (!userReady) {
        // Redirection already handled by initializeUserContext
        return;
    }
    
    await loadFavoritesButtons();
    setupEventListeners();
    setupSpeechRecognition();  // Add wake word recognition
    setupKeyboardListener();   // Add keyboard controls
    
    // --- Add AudioContext Resume Listeners (MUST HAVE for playing audio) ---
    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true }); // Keyboard also counts as gesture
    
    console.log('Favorites page initialization complete');
});

// Initialize user context (exactly like gridpage.js)
async function initializeUserContext() {
    console.log('initializeUserContext: Starting initialization...');
    
    // Debug: Check what's actually in session storage
    console.log('Session storage contents:', {
        firebaseIdToken: sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY) ? 'present' : 'missing',
        currentAacUserId: sessionStorage.getItem(AAC_USER_ID_SESSION_KEY),
        allKeys: Object.keys(sessionStorage),
        allValues: Object.keys(sessionStorage).reduce((acc, key) => {
            acc[key] = sessionStorage.getItem(key);
            return acc;
        }, {})
    });
    
    firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);

    console.log('Retrieved values:', {
        firebaseIdToken: firebaseIdToken ? 'present' : 'missing',
        currentAacUserId: currentAacUserId
    });

    if (!firebaseIdToken || !currentAacUserId) {
        console.log("No Firebase ID Token or AAC User ID found in session. Redirecting to auth.html.");
        sessionStorage.clear(); // Clear potentially stale data
        window.location.href = 'auth.html';
        return false; // Indicate not ready
    }
    
    console.log(`User context initialized. AAC User ID: ${currentAacUserId}`);
    
    // Load user settings
    await loadUserSettings();
    
    // Load and update page title with profile name
    await updatePageTitleWithProfile();
    
    // Setup admin toolbar
    setupAdminToolbar();
    
    return true; // Indicate ready
}

// Function to update page title with profile name
async function updatePageTitleWithProfile() {
    try {
        const response = await authenticatedFetch('/api/account/users');
        if (!response.ok) return;
        
        const profiles = await response.json();
        const currentProfile = profiles.find(profile => profile.aac_user_id === currentAacUserId);
        
        if (currentProfile && currentProfile.display_name) {
            const titleElement = document.getElementById('dynamic-page-title');
            if (titleElement) {
                const baseTitle = 'Favorites';
                titleElement.textContent = `${baseTitle} - ${currentProfile.display_name}`;
                console.log(`Updated favorites page title to include profile: ${currentProfile.display_name}`);
            }
        } else {
            // Fallback to just "Favorites" if no profile found
            const titleElement = document.getElementById('dynamic-page-title');
            if (titleElement) {
                titleElement.textContent = 'Favorites';
            }
        }
    } catch (error) {
        console.error('Error updating page title with profile:', error);
        // Fallback to just "Favorites" on error
        const titleElement = document.getElementById('dynamic-page-title');
        if (titleElement) {
            titleElement.textContent = 'Favorites';
        }
    }
}

// Load user settings
async function loadUserSettings() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (response.ok) {
            userSettings = await response.json();
            console.log('User settings loaded:', userSettings);
            
            // Load scanning settings exactly like gridpage.js
            if (userSettings && typeof userSettings.scanDelay === 'number' && !isNaN(userSettings.scanDelay)) {
                defaultDelay = Math.max(100, parseInt(userSettings.scanDelay));
                console.log(`Auditory scan delay loaded: ${defaultDelay}ms`);
            } else {
                defaultDelay = 3500;
            }
            
            // Load grid columns
            if (userSettings && typeof userSettings.gridColumns === 'number' && !isNaN(userSettings.gridColumns)) {
                gridColumns = Math.max(1, parseInt(userSettings.gridColumns));
                console.log(`Grid columns loaded: ${gridColumns}`);
            } else {
                gridColumns = 10;
            }
            
            // Load scanning state
            if (userSettings && typeof userSettings.ScanningOff === 'boolean') {
                ScanningOff = userSettings.ScanningOff;
                console.log(`Scanning state loaded: ScanningOff = ${ScanningOff}`);
            } else {
                ScanningOff = false;
            }

            scanMode = userSettings && userSettings.scanMode === 'step' ? 'step' : 'auto';
            
            // Load scan loop limit
            if (userSettings && typeof userSettings.scanLoopLimit === 'number' && !isNaN(userSettings.scanLoopLimit)) {
                scanLoopLimit = Math.max(0, parseInt(userSettings.scanLoopLimit));
                console.log(`Scan loop limit loaded: ${scanLoopLimit}`);
            } else {
                scanLoopLimit = 0;
            }
            
            // Apply grid columns setting to container
            if (gridContainer) {
                gridContainer.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
                console.log('Grid template columns applied:', gridContainer.style.gridTemplateColumns);
            }
        }
    } catch (error) {
        console.error('Error loading user settings:', error);
        // Use defaults (already set in variable declarations)
        userSettings = { 
            gridColumns: 10, 
            scanDelay: 3500, 
            ScanningOff: false, 
            scanMode: 'auto',
            scanLoopLimit: 0 
        };
    }
}

// Load favorites buttons from backend
async function loadFavoritesButtons() {
    try {
        console.log('Loading favorites buttons...');
        showLoadingIndicator();
        
        const response = await authenticatedFetch('/api/favorites');
        if (!response.ok) {
            throw new Error(`Failed to load favorites: ${response.status}`);
        }
        
        const favoritesData = await response.json();
        console.log('Favorites data loaded:', favoritesData);
        
        currentFavoritesButtons = favoritesData.buttons || [];
        generateGrid();
        
        console.log('Favorites buttons loaded and grid generated');
        
    } catch (error) {
        console.error('Error loading favorites buttons:', error);
        // Show error message
        if (gridContainer) {
            gridContainer.innerHTML = `
                <div style="grid-column: 1 / -1; text-align: center; padding: 20px;">
                    <p>Error loading favorites: ${error.message}</p>
                    <button onclick="loadFavoritesButtons()" style="margin-top: 10px; padding: 10px 20px; background: #FB4F14; color: white; border: none; border-radius: 5px;">
                        Try Again
                    </button>
                </div>
            `;
        }
    } finally {
        hideLoadingIndicator();
    }
}

// Generate the grid of favorites buttons
function generateGrid() {
    if (!gridContainer) return;
    
    console.log('Generating grid with', currentFavoritesButtons.length, 'buttons');
    
    // Clear existing content
    gridContainer.innerHTML = '';
    
    // Always add "Go Back" button first (top-left position)
    const backButton = document.createElement('button');
    backButton.textContent = 'Go Back';
    backButton.classList.add('back-button');
    backButton.style.gridRow = '1';
    backButton.style.gridColumn = '1';
    backButton.addEventListener('click', async () => {
        console.log('Go Back button clicked');
        // Navigate back to gridpage (home) without announcement
        window.location.href = '/static/gridpage.html?page=home';
    });
    gridContainer.appendChild(backButton);
    
    if (currentFavoritesButtons.length === 0) {
        // Add message about no favorites, positioned after the Go Back button
        const noFavoritesDiv = document.createElement('div');
        noFavoritesDiv.style.gridColumn = '2 / -1';
        noFavoritesDiv.style.gridRow = '1';
        noFavoritesDiv.style.textAlign = 'center';
        noFavoritesDiv.style.padding = '20px';
        noFavoritesDiv.innerHTML = `
            <div style="text-align: center; padding: 20px;">
                <h3 style="color: #002244; margin-bottom: 20px;">No Favorites Yet</h3>
                <p style="color: #666; margin-bottom: 20px;">
                    You haven't set up any favorite topics yet.<br>
                    Use the Favorites Admin to add your favorite news and topic sources.
                </p>
                <a href="/favorites_admin.html" style="display: inline-block; padding: 12px 24px; background: #FB4F14; color: white; text-decoration: none; border-radius: 8px; font-weight: 500;">
                    Set Up Favorites
                </a>
            </div>
        `;
        gridContainer.appendChild(noFavoritesDiv);
        return;
    }
    
    // Create buttons for each favorite
    console.log('Creating buttons for', currentFavoritesButtons.length, 'favorites');
    
    currentFavoritesButtons.forEach((button, index) => {
        if (button.hidden) {
            console.log('Skipping hidden button:', button.text);
            return; // Skip hidden buttons
        }
        
        const buttonElement = document.createElement('button');
        buttonElement.textContent = button.text;
        buttonElement.classList.add('favorite-button');
        buttonElement.setAttribute('data-index', index);
        
        // Simplified sequential grid positioning after the Go Back button
        const totalButtons = index + 1; // Current button position (1-based)
        
        // Position sequentially, skipping position 1 which is reserved for Go Back
        let gridPosition = totalButtons + 1; // +1 to skip Go Back position
        let row = Math.ceil(gridPosition / gridColumns);
        let col = ((gridPosition - 1) % gridColumns) + 1;
        
        buttonElement.style.gridRow = row.toString();
        buttonElement.style.gridColumn = col.toString();
        
        console.log(`Button "${button.text}" (index ${index}) positioned at grid row ${row}, col ${col} (gridPosition ${gridPosition})`);
        
        // Add click handler
        buttonElement.addEventListener('click', () => handleFavoriteButtonClick(button, index));
        
        gridContainer.appendChild(buttonElement);
    });
    
    console.log('Grid generated successfully with', currentFavoritesButtons.length, 'favorites buttons');
    console.log('Total buttons in grid (including Go Back):', document.querySelectorAll('#gridContainer button').length);
    console.log('ScanningOff:', ScanningOff);
    console.log('defaultDelay:', defaultDelay);
    
    // Delay scanning until after the page is rendered (exactly like gridpage.js)
    setTimeout(() => {
        console.log('Starting scanning from generateGrid setTimeout');
        startAuditoryScanning();
    }, defaultDelay);
}

// Handle favorite button click
async function handleFavoriteButtonClick(button, index) {
    try {
        console.log('Favorite button clicked:', button.text);
        
        // Stop any current scanning
        stopAuditoryScanning();
        
        // Only announce speech phrase if it exists - no other announcements
        if (button.speechPhrase && button.speechPhrase.trim()) {
            console.log('Announcing speech phrase:', button.speechPhrase);
            await announce(button.speechPhrase, "system", true);
        }
        
        // Show loading
        showLoadingIndicator();
        updateQuestionDisplay('Loading favorite topic content...');
        
        // Make API call to get topic content
        const response = await authenticatedFetch('/api/favorites/get-topic-content', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                topic: button.text
            })
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            console.error('Server response error:', errorText);
            throw new Error(`Failed to load content: ${response.status} - ${errorText}`);
        }
        
        const contentData = await response.json();
        console.log('Topic content loaded:', contentData);
        
        // Process the content - server returns {summaries: [], topic: "..."}
        if (contentData.summaries && contentData.summaries.length > 0) {
            await displayTopicContent(contentData.summaries, button.text);
        } else {
            throw new Error(contentData.message || 'No content found for this topic');
        }
        
    } catch (error) {
        console.error('Error handling favorite button click:', error);
        updateQuestionDisplay(`Error: ${error.message}`);
    } finally {
        hideLoadingIndicator();
    }
}

// Display topic content as buttons
async function displayTopicContent(articles, topicName) {
    try {
        console.log('Displaying topic content for:', topicName);
        
        // Clear current grid
        gridContainer.innerHTML = '';
        
        // Add back button first
        const backButton = document.createElement('button');
        backButton.textContent = 'Go Back';
        backButton.classList.add('back-button');
        backButton.style.gridColumn = '1';
        backButton.style.gridRow = '1';
        backButton.addEventListener('click', async () => {
            // Go back to favorites without announcement
            await loadFavoritesButtons();
        });
        gridContainer.appendChild(backButton);
        
        // Create buttons for each summary
        articles.forEach((summary, index) => {
            const buttonElement = document.createElement('button');
            buttonElement.textContent = summary.summary; // Short phrase for button text
            buttonElement.classList.add('article-button');
            buttonElement.setAttribute('data-option', summary.option || ''); // Full conversation starter
            
            // Calculate grid position properly
            const gridColumns = userSettings.gridColumns || 10;
            let row = Math.floor(index / gridColumns) + 1;
            let col = (index % gridColumns) + 2; // Start from column 2
            
            // If we go beyond the grid width, wrap to next row starting at column 1
            if (col > gridColumns) {
                row++;
                col = 1;
            }
            
            buttonElement.style.gridColumn = col.toString();
            buttonElement.style.gridRow = row.toString();
            
            // Add click handler
            buttonElement.addEventListener('click', () => handleSummarySelection(summary));
            
            gridContainer.appendChild(buttonElement);
        });
        
        // Update display without announcement
        updateQuestionDisplay(`${topicName}: ${articles.length} summaries found`);
        
        // Start scanning for article buttons
        setTimeout(() => {
            if (!ScanningOff) {
                startAuditoryScanning();
            }
        }, 500);
        
        console.log('Topic content displayed successfully');
        
    } catch (error) {
        console.error('Error displaying topic content:', error);
        updateQuestionDisplay(`Error: ${error.message}`);
    }
}

// Handle summary selection
async function handleSummarySelection(summary) {
    try {
        console.log('Summary selected:', summary.summary);
        
        // Announce the full conversation starter using the announce function
        await announce(summary.option, "system", true);
        
        // Navigate back to favorites page after announcement completes
        setTimeout(async () => {
            await loadFavoritesButtons();
        }, 1000); // Shorter delay since announce already waits for completion
        
    } catch (error) {
        console.error('Error handling summary selection:', error);
    }
}

// Authenticated fetch function
// Authenticated fetch function (matching gridpage.js pattern)
async function authenticatedFetch(url, options = {}, _isRetry = false) {
    // Re-read token from sessionStorage (may have been refreshed by token-refresh.js)
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        throw new Error('No authentication token or user ID');
    }
    
    const headers = {
        'Authorization': `Bearer ${firebaseIdToken}`,
        'X-User-ID': currentAacUserId,
        'Content-Type': 'application/json',
        ...options.headers
    };
    
    // Check for admin context and add target account header if needed
    const adminTargetAccountId = sessionStorage.getItem('adminTargetAccountId');
    if (adminTargetAccountId) {
        headers['X-Admin-Target-Account'] = adminTargetAccountId;
    }
    
    const response = await fetch(url, {
        ...options,
        headers
    });

    if ((response.status === 401 || response.status === 403) && !_isRetry) {
        console.warn(`Auth failed (${response.status}) for ${url}. Attempting silent token refresh...`);
        if (typeof window.refreshFirebaseToken === 'function') {
            const newToken = await window.refreshFirebaseToken();
            if (newToken) {
                console.log('[AUTH] Token refreshed, retrying...');
                return authenticatedFetch(url, options, true);
            }
        }
        window.location.href = 'auth.html';
        throw new Error('Authentication failed');
    }
    if (response.status === 401 || response.status === 403) {
        window.location.href = 'auth.html';
        throw new Error('Authentication failed after token refresh');
    }
    return response;
}

// Speech and announcement functions
function addToSpeechHistory(text) {
    try {
        // Clean [PAUSE] markers from text before adding to history
        const cleanText = text.replace(/\[PAUSE\]/g, ' ').trim();
        const speechHistory = document.getElementById('speech-history');
        if (speechHistory && currentAacUserId) {
            const storageKey = `speechHistory_${currentAacUserId}`;
            let history = (localStorage.getItem(storageKey) || '').split('\n').filter(Boolean);
            history.unshift(cleanText); // Add to top
            if (history.length > 20) { 
                history = history.slice(0, 20); // Keep only last 20 entries
            }
            speechHistory.value = history.join('\n');
            localStorage.setItem(storageKey, speechHistory.value);
        }
    } catch (error) {
        console.error('Error adding to speech history:', error);
    }
}

function updateQuestionDisplay(text) {
    if (!questionDisplayElement) return;
    questionDisplayElement.value = text;
}

// Announcement functions
async function announce(textToAnnounce, announcementType = "system", recordHistory = true) {
    console.log(`ANNOUNCE: "${textToAnnounce.substring(0, 30)}..." (Type: ${announcementType})`);
    
    // Stop scanning during announcement
    const wasScanningActive = scanningInterval !== null;
    if (wasScanningActive) {
        stopAuditoryScanning();
    }
    
    try {
        // Use the server's text-to-speech API like gridpage does
        const response = await authenticatedFetch(`/play-audio`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: textToAnnounce, routing_target: announcementType }),
        });

        if (!response.ok) {
            throw new Error(`Failed to synthesize audio: ${response.status}`);
        }

        const jsonResponse = await response.json();
        const audioData = jsonResponse.audio_data;
        const sampleRate = jsonResponse.sample_rate;

        if (!audioData) {
            throw new Error("No audio data received from server.");
        }

        // Convert base64 to ArrayBuffer
        const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
        await playAudioToDevice(audioDataArrayBuffer, sampleRate, announcementType);

        // Record to speech history if requested
        if (recordHistory) {
            addToSpeechHistory(textToAnnounce);
        }

    } catch (error) {
        console.error('Error during announcement:', error);
        // Fallback to browser speech synthesis
        try {
            const utterance = new SpeechSynthesisUtterance(textToAnnounce);
            window.speechSynthesis.cancel();
            window.speechSynthesis.speak(utterance);
            
            // Wait for speech to complete
            await new Promise((resolve) => {
                utterance.onend = resolve;
                utterance.onerror = resolve;
            });
            
            if (recordHistory) {
                addToSpeechHistory(textToAnnounce);
            }
        } catch (fallbackError) {
            console.error('Fallback speech synthesis also failed:', fallbackError);
        }
    } finally {
        // Restart scanning after announcement if it was active before
        if (wasScanningActive && !ScanningOff) {
            setTimeout(() => {
                const buttons = document.querySelectorAll('#gridContainer button:not([style*="display: none"])');
                if (buttons.length > 0) {
                    startAuditoryScanning();
                }
            }, 500);
        }
    }
}

// Helper function to convert base64 to ArrayBuffer
function base64ToArrayBuffer(base64) {
    const binaryString = window.atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

// Helper function to play audio
async function playAudioToDevice(audioDataBuffer, sampleRate, announcementType) {
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
        activeAnnouncementAudioContext = audioContext;
        activeAnnouncementAudioSource = source;
        source.start(0);

        return new Promise((resolve) => {
            source.onended = () => {
                activeAnnouncementAudioSource = null;
                if (activeAnnouncementAudioContext === audioContext) {
                    activeAnnouncementAudioContext = null;
                }
                audioContext.close();
                resolve();
            };
        });

    } catch (error) {
        console.error('Error during audio playback:', error);
        if (audioContext && audioContext.state !== 'closed') audioContext.close();
        if (activeAnnouncementAudioContext === audioContext) {
            activeAnnouncementAudioContext = null;
            activeAnnouncementAudioSource = null;
        }
        throw error;
    }
}

function interruptScanningAnnouncementPlayback() {
    announcementQueue = [];
    isProcessingQueue = false;

    if (speechSynthesis) {
        speechSynthesis.cancel();
    }

    if (activeAnnouncementAudioSource) {
        try {
            activeAnnouncementAudioSource.onended = null;
            activeAnnouncementAudioSource.stop(0);
        } catch (e) {
            // no-op
        }
        try {
            activeAnnouncementAudioSource.disconnect();
        } catch (e) {
            // no-op
        }
        activeAnnouncementAudioSource = null;
    }

    if (activeAnnouncementAudioContext && activeAnnouncementAudioContext.state !== 'closed') {
        activeAnnouncementAudioContext.close().catch(() => {});
    }
    activeAnnouncementAudioContext = null;
}

async function queueAnnouncement(text) {
    if (!text) return;
    
    announcementQueue.push(text);
    if (!isProcessingQueue) {
        await processAnnouncementQueue();
    }
}

async function processAnnouncementQueue() {
    if (isProcessingQueue || announcementQueue.length === 0) return;
    
    isProcessingQueue = true;
    
    while (announcementQueue.length > 0) {
        const text = announcementQueue.shift();
        await announceText(text);
    }
    
    isProcessingQueue = false;
}

async function announceText(text) {
    if (!text || !speechSynthesis) return;
    
    return new Promise((resolve) => {
        // Cancel any ongoing speech
        speechSynthesis.cancel();
        
        const utterance = new SpeechSynthesisUtterance(text);
        
        // Configure voice settings
        utterance.rate = (userSettings.speech_rate || 180) / 180; // Convert WPM to rate
        utterance.pitch = 1;
        utterance.volume = 1;
        
        // Try to use the selected voice
        const voices = speechSynthesis.getVoices();
        const selectedVoice = voices.find(voice => 
            voice.name === userSettings.selected_tts_voice_name
        );
        if (selectedVoice) {
            utterance.voice = selectedVoice;
        }
        
        utterance.onend = () => resolve();
        utterance.onerror = () => resolve();
        
        speechSynthesis.speak(utterance);
    });
}

// Auditory scanning functions (from gridpage.js)
// --- Auditory Scanning (EXACTLY from gridpage.js) ---
function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) { console.log("Auditory scanning is off."); return; }
    if (scanMode === 'step') {
        currentButtonIndex = -1;
        scanCycleCount = 0;
        isPausedFromScanLimit = false;
        advanceScanningStep();
        return;
    }
    console.log("Starting auditory scanning...");
    const buttons = Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
    if (buttons.length === 0) { console.log("No visible buttons found."); currentlyScannedButton = null; return; }
    
    // Reset cycle tracking when starting fresh
    currentButtonIndex = -1;
    scanCycleCount = 0;
    isPausedFromScanLimit = false;

    const scanStep = async () => {
        if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); }
        currentButtonIndex++;
        
        // Check if we've completed a full cycle
        if (currentButtonIndex >= buttons.length) { 
            currentButtonIndex = 0; 
            scanCycleCount++;
            
            // Check scan loop limit
            if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
                console.log(`Scan loop limit reached (${scanLoopLimit} cycles). Pausing scanning.`);
                isPausedFromScanLimit = true;
                stopAuditoryScanning();
                
                // Announce that scanning is paused
                try {
                    await announce("Scanning paused", "system", false);
                } catch (e) { 
                    console.error("Speech synthesis error:", e); 
                }
                
                // Set focus and highlight on the first button so user can restart scanning
                if (buttons.length > 0) {
                    currentButtonIndex = 0;
                    buttons[0].focus();
                    // Add visual highlight to show focus is on first button
                    currentlyScannedButton = buttons[0];
                    currentlyScannedButton.classList.add('scanning');
                    console.log("Focus and highlight set on first button for restart capability");
                }
                
                return;
            }
        }
        
        if (buttons[currentButtonIndex]) {
            currentlyScannedButton = buttons[currentButtonIndex];
            speakAndHighlight(currentlyScannedButton);
        } else { console.warn("Button not found at index:", currentButtonIndex); currentButtonIndex = -1; }
    };
    console.log(`Scan delay set to: ${defaultDelay}ms`);
    scanStep(); // Perform first scan immediately
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function advanceScanningStep() {
    if (ScanningOff || scanMode !== 'step') {
        return;
    }
    const buttons = Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
    if (buttons.length === 0) {
        currentlyScannedButton = null;
        return;
    }

    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning');
    }
    currentButtonIndex = (currentButtonIndex + 1) % buttons.length;
    currentlyScannedButton = buttons[currentButtonIndex];
    speakAndHighlight(currentlyScannedButton);
}

async function speakAndHighlight(button) {
    document.querySelectorAll('#gridContainer button.scanning').forEach(btn => { btn.classList.remove('scanning'); });
    button.classList.add('scanning');
    try {
        const textToSpeak = button.textContent;
        await announce(textToSpeak, "system", false);
    } catch (e) { console.error("Speech synthesis error:", e); }
}

function stopAuditoryScanning() {
    console.log("Stopping auditory scanning.");
    clearInterval(scanningInterval); scanningInterval = null;
    if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); currentlyScannedButton = null; }
    currentButtonIndex = -1; window.speechSynthesis.cancel();
}

// Function to resume scanning from first option with cycle reset
async function resumeAuditoryScanning() {
    if (!isPausedFromScanLimit) {
        console.log("Scanning was not paused from scan limit, starting normally");
        startAuditoryScanning();
        return;
    }
    
    console.log("Resuming scanning from first option with cycle reset...");
    isPausedFromScanLimit = false;
    scanCycleCount = 0; // Reset cycle count
    currentButtonIndex = -1; // Reset to start from first option
    
    // Announce that scanning is resumed
    try {
        await announce("Scanning resumed", "system", false);
    } catch (e) { 
        console.error("Speech synthesis error:", e); 
    }
    
    startAuditoryScanning();
}

function selectCurrentScannedButton() {
    if (!currentlyScannedButton) {
        console.log("No button currently being scanned");
        return;
    }
    
    // Capture the button reference before stopping scanning (which sets it to null)
    const buttonToActivate = currentlyScannedButton;
    console.log("Selecting currently scanned button:", buttonToActivate.textContent);
    stopAuditoryScanning();
    buttonToActivate.click();
}

// Loading indicator functions
function showLoadingIndicator() {
    const loadingIndicator = document.getElementById('loading-indicator');
    if (loadingIndicator) {
        loadingIndicator.style.display = 'flex';
    }
}

function hideLoadingIndicator() {
    const loadingIndicator = document.getElementById('loading-indicator');
    if (loadingIndicator) {
        loadingIndicator.style.display = 'none';
    }
}

// Admin toolbar setup (from gridpage)
function setupAdminToolbar() {
    const lockIcon = document.getElementById('lock-icon');
    const adminIcons = document.getElementById('admin-icons');
    const lockToolbarButton = document.getElementById('lock-toolbar-button');
    const pinModal = document.getElementById('pin-modal');
    const pinInput = document.getElementById('pin-input');
    const pinSubmit = document.getElementById('pin-submit');
    const pinCancel = document.getElementById('pin-cancel');
    const pinError = document.getElementById('pin-error');
    
    if (lockIcon) {
        lockIcon.addEventListener('click', () => {
            if (pinModal) {
                pinModal.classList.remove('hidden');
                if (pinInput) pinInput.focus();
            }
        });
    }
    
    if (pinSubmit) {
        pinSubmit.addEventListener('click', () => {
            const enteredPin = pinInput ? pinInput.value : '';
            const correctPin = userSettings.toolbarPIN || '1234';
            
            if (enteredPin === correctPin) {
                if (adminIcons) adminIcons.classList.remove('hidden');
                if (pinModal) pinModal.classList.add('hidden');
                if (pinInput) pinInput.value = '';
                if (pinError) pinError.classList.add('hidden');
            } else {
                if (pinError) pinError.classList.remove('hidden');
            }
        });
    }
    
    if (pinCancel) {
        pinCancel.addEventListener('click', () => {
            if (pinModal) pinModal.classList.add('hidden');
            if (pinInput) pinInput.value = '';
            if (pinError) pinError.classList.add('hidden');
        });
    }
    
    if (lockToolbarButton) {
        lockToolbarButton.addEventListener('click', () => {
            if (adminIcons) adminIcons.classList.add('hidden');
        });
    }
}

// Event listeners setup
function setupEventListeners() {
    // Clear history button
    const clearButton = document.getElementById('clear-history');
    if (clearButton) {
        clearButton.addEventListener('click', () => {
            if (speechHistoryElement) {
                speechHistoryElement.value = '';
            }
        });
    }
    
    // Keyboard shortcuts for scanning (from gridpage.js)
    document.addEventListener('keydown', (event) => {
        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            interruptScanningAnnouncementPlayback();
            if (isPausedFromScanLimit) {
                resumeAuditoryScanning();
            } else if (currentlyScannedButton) {
                advanceScanningStep();
            } else {
                startAuditoryScanning();
            }
            return;
        }

        switch(event.code) {
            case 'Space':
                event.preventDefault();
                if (isPausedFromScanLimit) {
                    resumeAuditoryScanning();
                } else if (currentlyScannedButton) {
                    selectCurrentScannedButton();
                } else {
                    startAuditoryScanning();
                }
                break;
            case 'Escape':
                event.preventDefault();
                stopAuditoryScanning();
                break;
            case 'Enter':
                event.preventDefault();
                if (currentlyScannedButton) {
                    selectCurrentScannedButton();
                }
                break;
            case 'KeyS':
                if (event.ctrlKey || event.metaKey) {
                    event.preventDefault();
                    if (isPausedFromScanLimit) {
                        resumeAuditoryScanning();
                    } else {
                        startAuditoryScanning();
                    }
                }
                break;
        }
    });
    
    // Help modal functionality
    setupHelpModal();
    
    // Focus management - ensure scanning works when page loads
    window.addEventListener('load', () => {
        // Give focus to the document body so keyboard events work
        document.body.focus();
    });
}

// Help modal setup
function setupHelpModal() {
    const helpIcon = document.getElementById('help-icon');
    const helpModal = document.getElementById('help-modal');
    const helpModalClose = document.getElementById('help-modal-close');
    
    if (helpIcon && helpModal) {
        helpIcon.addEventListener('click', () => {
            helpModal.classList.remove('hidden');
            loadHelpContent();
        });
    }
    
    if (helpModalClose && helpModal) {
        helpModalClose.addEventListener('click', () => {
            helpModal.classList.add('hidden');
        });
    }
}

async function loadHelpContent() {
    const helpContent = document.getElementById('help-modal-content');
    if (!helpContent) return;
    
    try {
        const response = await fetch('/static/web_scraping_help_page.html');
        if (response.ok) {
            const html = await response.text();
            helpContent.innerHTML = html;
        } else {
            helpContent.innerHTML = '<p>Help content could not be loaded.</p>';
        }
    } catch (error) {
        console.error('Error loading help content:', error);
        helpContent.innerHTML = '<p>Error loading help content.</p>';
    }
}

// Add to speech history
function addToSpeechHistory(text) {
    if (!speechHistoryElement) return;
    
    // Clean [PAUSE] markers from text before adding to history
    const cleanText = text.replace(/\[PAUSE\]/g, ' ').trim();
    const history = speechHistoryElement.value.split('\n').filter(Boolean);
    history.unshift(cleanText);
    if (history.length > 20) {
        history.splice(20);
    }
    speechHistoryElement.value = history.join('\n');
    
    // Save to localStorage if user context available
    if (currentAacUserId) {
        const storageKey = `speechHistory_${currentAacUserId}`;
        localStorage.setItem(storageKey, speechHistoryElement.value);
    }
}

// Speech Recognition Setup (from gridpage.js)
function setupSpeechRecognition() {
    if (isSettingUpRecognition || recognition) { return; }
    isSettingUpRecognition = true;
    console.log("Setting up keyword speech recognition...");
    
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error("Speech Recognition API not supported."); 
        isSettingUpRecognition = false; 
        return;
    }
    
    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    console.log("Keyword Recognition object created:", recognition);

    recognition.onerror = function (event) {
        console.error("Keyword Speech recognition error:", event.error, event.message);
        if (['no-speech', 'audio-capture', 'network'].includes(event.error) && !listeningForQuestion) {
             console.log("Keyword recognition error, attempting restart...");
             setTimeout(() => {
                 if (!listeningForQuestion) {
                     recognition = null;
                     isSettingUpRecognition = false;
                     setupSpeechRecognition();
                 }
             }, 1000);
        } else { 
            isSettingUpRecognition = false; 
            recognition = null; 
        }
    };

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('Keyword check - Speech recognized:', transcript);
        if (listeningForQuestion) { 
            console.log("Ignoring keyword, currently listening for question."); 
            return; 
        }

        const phraseWithSpace = `${wakeWordInterjection} ${wakeWordName}`;
        const phraseWithComma = `${wakeWordInterjection}, ${wakeWordName}`;
        const phraseWithCommaNoSpace = `${wakeWordInterjection},${wakeWordName}`;

        console.log(`Checking for: "${phraseWithSpace}" OR "${phraseWithComma}" OR "${phraseWithCommaNoSpace}"`);

        if (transcript.includes(phraseWithSpace) || transcript.includes(phraseWithComma) || transcript.includes(phraseWithCommaNoSpace)) {
            console.log(`Wake word detected! ("${transcript}")`);
            stopAuditoryScanning();
            if (recognition) {
                recognition.stop();
                recognition = null;
            }
            isSettingUpRecognition = false;

            const announcement = 'Listening for your question...';
            console.log("Calling announce for question prompt...");
            try {
                await announce(announcement, "system", false);
                setupQuestionRecognition();
            } catch (announceError) {
                console.error("Error during announcement:", announceError);
                setupSpeechRecognition(); // Restart keyword spotting
            }
        }
    };

    recognition.onend = () => {
        console.log("Keyword Recognition ended.");
        if (!listeningForQuestion && !isSettingUpRecognition && recognition) {
             console.log("Keyword recognition ended unexpectedly, restarting.");
             recognition = null; 
             setTimeout(setupSpeechRecognition, 500);
        } else {
             console.log("Keyword recognition ended normally or was already being reset/stopped.");
             isSettingUpRecognition = false;
        }
    };

    try { 
        recognition.start(); 
        console.log("Keyword recognition started."); 
        isSettingUpRecognition = false; 
    }
    catch (e) { 
        console.error("Error starting keyword recognition:", e); 
        isSettingUpRecognition = false; 
        recognition = null; 
    }
}

function setupQuestionRecognition() {
    console.log("Question recognition not implemented for favorites page");
    // For now, just restart keyword recognition
    setTimeout(() => {
        setupSpeechRecognition();
        if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
            startAuditoryScanning();
        }
    }, 1000);
}

// Keyboard listener setup
function setupKeyboardListener() {
    document.addEventListener('keydown', (event) => {
        if (event.code === 'Tab' && scanMode === 'step' && !listeningForQuestion) {
            event.preventDefault();
            interruptScanningAnnouncementPlayback();
            if (currentlyScannedButton) {
                advanceScanningStep();
            } else {
                startAuditoryScanning();
            }
            return;
        }

        if (event.code === 'Space' && !listeningForQuestion && currentlyScannedButton) {
            event.preventDefault();
            const buttonToActivate = currentlyScannedButton; // Capture the button reference
            console.log("Spacebar pressed, activating button:", buttonToActivate.textContent);
            buttonToActivate.click();
            buttonToActivate.classList.add('active');
            // Use the captured reference in the timeout as well
            setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
        }
    });
    console.log("Keyboard listener (Spacebar) set up.");
}

// Export functions for debugging
window.favoritesPage = {
    loadFavoritesButtons,
    startAuditoryScanning,
    stopAuditoryScanning,
    currentUser,
    userSettings,
    currentFavoritesButtons
};
