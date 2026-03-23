// --- Freestyle Communication JavaScript ---

// --- Global Variables (Similar to gridpage.js) ---
let currentlyScannedButton = null; // Tracks the currently highlighted button
let lastGamepadInputTime = 0; // For gamepad debounce/rate limiting
let isLLMProcessing = false; // Flag to detect if LLM query is running
const clickDebounceDelay = 300; // Debounce for button clicks
let defaultDelay = 3500; // Default auditory scan delay (ms) - Loaded from settings
let scanningInterval; // Holds the interval ID for scanning
let scanMode = 'auto'; // auto | step
let currentScanAdvanceFn = null; // step scanning advance callback for active context
let currentButtonIndex = -1; // Tracks the index for scanning
let scanCycleCount = 0; // Tracks how many complete cycles have been performed
let scanLoopLimit = 0; // 0 = unlimited, 1-10 = limit cycles
let isPausedFromScanLimit = false; // Flag to track if scanning is paused due to scan limit
let gamepadIndex = null; // To store the index of the connected gamepad
let gamepadPollInterval = null; // Interval ID for gamepad polling
let scanningPaused = false; // Global scanning pause flag
let gridColumns = 6; // Default number of grid columns for alphabet grid sizing
let autoClean = false; // Auto Clean setting for automatic cleanup on Speak Display

// --- User Management Variables (Same as gridpage.js) ---
let currentAacUserId = null;
let firebaseIdToken = null;
const AAC_USER_ID_SESSION_KEY = "currentAacUserId";
const FIREBASE_TOKEN_SESSION_KEY = "firebaseIdToken";
const SELECTED_DISPLAY_NAME_SESSION_KEY = "selectedDisplayName";
const SPEECH_HISTORY_LOCAL_STORAGE_KEY = (aacUserId) => `speechHistory_${aacUserId}`;

// --- Audio Variables ---
let personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
let systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';
let currentTtsVoiceName = 'en-US-Neural2-A';
let currentSpeechRate = 180;

// --- Announcement Queue Variables ---
let announcementQueue = [];
let isAnnouncingNow = false;
let audioContextResumeAttempted = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;
let pendingHighlightSpeechTimer = null;
let pendingHighlightSpeechToken = 0;

// --- Freestyle Specific Variables ---
let currentBuildSpaceText = "";
let currentWordOptions = [];
let currentSpellingWord = "";
let currentPredictions = [];
let isSpellingModalOpen = false;
let isChooseWordModalOpen = false;
let currentChooseWordCategory = "";
let currentCategoryWords = [];
let currentScanningContext = "main"; // "main", "spelling-letters", "spelling-predictions", "choose-word-categories", "choose-word-options"

// Navigation context from URL parameters
function getNavigationContext() {
    const params = new URLSearchParams(window.location.search);
    return {
        source_page: params.get('source_page') || null,
        context: params.get('context') || null,
        is_llm_generated: params.get('is_llm_generated') === 'true',
        originating_button: params.get('originating_button') || null
    };
}

// --- Pictogram Support ---
// Pictograms removed as per user request
let enablePictograms = false; // Global setting for pictogram display - Always false for Freestyle

// const PICTOGRAM_MAP = { ... }; // Removed

function getPictogramForText(text) {
    return null;
}
// (Rest of PICTOGRAM_MAP removed)

function getPictogramForText(text) {
    return null;
}

// --- Shared Image Functions (from gridpage.js) ---
function getOptimizedSearchTerm(summary, keywords = null) {
    if (!summary || typeof summary !== 'string') return '';
    
    console.log(`🔧 DEBUG: Processing "${summary}" with keywords:`, keywords);
    
    const questionWords = ['what', 'who', 'where', 'when', 'why', 'how'];
    const words = summary.toLowerCase().trim().split(/\s+/);
    
    // Remove question words from the beginning
    let meaningfulWords = [...words];
    while (meaningfulWords.length > 0 && questionWords.includes(meaningfulWords[0])) {
        meaningfulWords.shift();
    }
    
    // Remove common filler words and clean punctuation
    const fillerWords = ['is', 'are', 'the', 'a', 'an', 'that', 'this', 'it', 'do', 'does', 'did', 'can', 'will', 'would', 'should'];
    meaningfulWords = meaningfulWords
        .filter(word => !fillerWords.includes(word))
        .map(word => word.replace(/[?!.,;:]/g, ''))  // Remove punctuation
        .filter(word => word.length > 0);  // Remove empty strings
    
    // If we have keywords, prioritize them (but skip question words and generic terms)
    if (keywords && Array.isArray(keywords) && keywords.length > 0) {
        // Find the first keyword that isn't a question word, filler word, or generic term
        const questionAndFillerWords = [...questionWords, ...fillerWords, 'question', 'curiosity', 'that', 'this'];
        const genericTerms = ['color', 'thing', 'object', 'item', 'stuff', 'shape', 'size'];
        
        const meaningfulKeyword = keywords.find(keyword => {
            const cleanKeyword = keyword.toLowerCase().trim().replace(/[?!.,;:]/g, '');
            return cleanKeyword.length > 2 && 
                   !questionAndFillerWords.includes(cleanKeyword) &&
                   !genericTerms.includes(cleanKeyword);
        });
        
        if (meaningfulKeyword) {
            const cleanKeyword = meaningfulKeyword.toLowerCase().trim().replace(/[?!.,;:]/g, '');
            console.log(`🔧 DEBUG: Using meaningful keyword: "${cleanKeyword}"`);
            return cleanKeyword;
        }
    }
    
    // Use the most meaningful word from the remaining words
    if (meaningfulWords.length > 0) {
        // For single word inputs that are specific (like colors, objects), prefer the original case
        const originalWordLower = summary.toLowerCase().trim();
        const originalWord = summary.trim(); // Preserve original case
        if (meaningfulWords.includes(originalWordLower) && originalWordLower.length > 2) {
            console.log(`🔧 DEBUG: Using original specific word with preserved case: "${originalWord}"`);
            return originalWord;
        }
        
        // Otherwise, prioritize nouns and verbs (longer words are more likely to be meaningful)
        // Find the corresponding original case word
        const sortedWords = meaningfulWords.sort((a, b) => b.length - a.length);
        const selectedLowerWord = sortedWords[0];
        
        // Try to find the original case version of the selected word
        const originalWords = summary.trim().split(/\s+/);
        const originalCaseWord = originalWords.find(word => 
            word.toLowerCase().replace(/[?!.,;:]/g, '') === selectedLowerWord
        );
        
        const finalWord = originalCaseWord || selectedLowerWord;
        console.log(`🔧 DEBUG: Meaningful words found:`, meaningfulWords, `→ Selected: "${finalWord}"`);
        return finalWord;
    }
    
    // Fallback to original summary if no meaningful words found (preserve case)
    console.log(`🔧 DEBUG: No meaningful words found, using original: "${summary.trim()}"`);
    return summary.trim();
}

/**
 * Simple pluralization helper to generate both singular and plural forms
 * @param {string} word - The word to generate variants for
 * @returns {Array<string>} - Array of word variants (original, singular, plural)
 */
function getWordVariants(word) {
    if (!word || typeof word !== 'string') return [word];
    
    const variants = [word]; // Always include original
    const lowerWord = word.toLowerCase();
    
    // Generate singular form (remove common plural endings)
    if (lowerWord.endsWith('ies') && lowerWord.length > 4) {
        // parties → party, stories → story
        variants.push(word.slice(0, -3) + 'y');
    } else if (lowerWord.endsWith('es') && lowerWord.length > 3) {
        // Only remove 'es' if the word stem suggests it needs 'es' for pluralization
        // boxes → box, dishes → dish, glasses → glass, but NOT jokes → jok
        const stem = lowerWord.slice(0, -2);
        if (stem.endsWith('ch') || stem.endsWith('sh') || stem.endsWith('x') || 
            stem.endsWith('z') || stem.endsWith('s') || stem.endsWith('ss')) {
            variants.push(word.slice(0, -2));
        }
        // For other 'es' endings, treat as regular 's' plural (jokes → joke)
        else {
            variants.push(word.slice(0, -1));
        }
    } else if (lowerWord.endsWith('s') && lowerWord.length > 2 && !lowerWord.endsWith('ss')) {
        // questions → question, foods → food, but not "bass"
        variants.push(word.slice(0, -1));
    }
    
    // Generate plural form (add common plural endings)
    if (!lowerWord.endsWith('s')) {
        if (lowerWord.endsWith('y') && lowerWord.length > 2 && !'aeiou'.includes(lowerWord[lowerWord.length - 2])) {
            // party → parties, story → stories
            variants.push(word.slice(0, -1) + 'ies');
        } else if (lowerWord.endsWith('ch') || lowerWord.endsWith('sh') || lowerWord.endsWith('x') || lowerWord.endsWith('z') || lowerWord.endsWith('s')) {
            // box → boxes, dish → dishes
            variants.push(word + 'es');
        } else {
            // question → questions, food → foods
            variants.push(word + 's');
        }
    }
    
    // Remove duplicates and return
    return [...new Set(variants)];
}

/**
 * Fetches symbol image from the AAC symbol database with retry logic and caching
 * @param {string} text - The button text to find a symbol for
 * @param {Array<string>} keywords - Optional semantic keywords for LLM-generated content  
 * @returns {Promise<string|null>} - Promise that resolves to image URL or null if none found
 */
async function getSymbolImageForText(text, keywords = null) {
    if (!text || text.trim() === '') return null;
    
    // Check if pictograms/images are enabled
    if (!enablePictograms) {
        return null;
    }
    
    // Check if this text is a sight word - if so, force text-only display (no images)
    if (window.isSightWord && window.isSightWord(text)) {
        console.log(`🔤 Sight word detected: "${text}" - using text-only display`);
        return null;
    }
    
    // Simple in-memory cache to avoid repeated requests
    if (!window.symbolImageCache) {
        window.symbolImageCache = new Map();
    }
    
    const cacheKey = `v2_${text.trim().toLowerCase()}`; // v2 cache key for tag position prioritization fix
    if (window.symbolImageCache.has(cacheKey)) {
        const cached = window.symbolImageCache.get(cacheKey);
        if (cached.timestamp > Date.now() - 300000) { // Cache for 5 minutes
            return cached.imageUrl;
        }
    }
    
    // Get word variants (original, singular, plural) to try
    const wordVariants = getWordVariants(text.trim());
    console.log(`🔧 DEBUG: Trying word variants for "${text}":`, wordVariants);
    
    const maxRetries = 2;
    let lastError = null;
    
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            // Add a small delay for retries to avoid overwhelming the server
            if (attempt > 1) {
                await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
            }
            
            let bestMatch = null;
            let bestScore = -1;
            let bestSource = '';
            
            // Try each word variant until we find a match
            for (const variant of wordVariants) {
                if (bestMatch) break; // Stop if we found a good match
                
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 seconds for BravoImages priority search
                
                // Use unified button-search that searches both collections with proper prioritization
                const symbolsUrl = `/api/symbols/button-search?q=${encodeURIComponent(variant)}&limit=1`;
                const symbolsUrlWithKeywords = keywords && Array.isArray(keywords) && keywords.length > 0 ? 
                    `${symbolsUrl}&keywords=${encodeURIComponent(JSON.stringify(keywords))}` : symbolsUrl;
                
                // Single unified search call
                const [symbolsResponse] = await Promise.allSettled([
                    fetch(symbolsUrlWithKeywords, { signal: controller.signal })
                ]);
                
                clearTimeout(timeoutId);
                
                // Process unified button-search response (handles both collections with proper prioritization)
                if (symbolsResponse.status === 'fulfilled' && symbolsResponse.value.ok) {
                    try {
                        const symbolsData = await symbolsResponse.value.json();
                        if (symbolsData.symbols && symbolsData.symbols.length > 0) {
                            const symbol = symbolsData.symbols[0];
                            const symbolScore = symbol.match_score || 5;
                            
                            bestMatch = {
                                image_url: symbol.image_url,
                                name: symbol.name || symbol.subconcept || 'Image',
                                match_score: symbolScore,
                                source: symbol.source || 'unified_search'
                            };
                            bestScore = symbolScore;
                            bestSource = symbol.source === 'bravo_images' ? 'BravoImages' : 'Symbols';
                            
                            console.log(`Found ${bestSource} for "${text}" using variant "${variant}": ${symbol.name || symbol.subconcept} (score: ${symbolScore})`);
                            break; // Found a match, stop trying variants
                        }
                    } catch (e) {
                        if (e.name !== 'AbortError') {
                            console.warn('Error parsing unified search response:', e);
                        }
                    }
                }
            }
            
            if (bestMatch) {
                // Cache successful result
                window.symbolImageCache.set(cacheKey, {
                    imageUrl: bestMatch.image_url,
                    timestamp: Date.now()
                });
                
                return bestMatch.image_url;
            } else {
                // Cache null result to avoid repeated requests
                window.symbolImageCache.set(cacheKey, {
                    imageUrl: null,
                    timestamp: Date.now()
                });
                
                // If both searches failed, continue to retry logic
                if (attempt === maxRetries) {
                    console.warn(`No symbols or images found for "${text}" after ${maxRetries} attempts`);
                    return null;
                }
                continue; // Try again
            }
        } catch (error) {
            lastError = error;
            if (error.name === 'AbortError') {
                // Don't retry on timeout - likely server overload
                console.warn(`Symbol search timeout for "${text}" - skipping retries`);
                return null;
            } else {
                console.warn(`Error fetching symbol for "${text}" (attempt ${attempt}/${maxRetries}):`, error.message);
            }
            
            if (attempt === maxRetries) {
                break;
            }
        }
    }
    
    console.warn(`All symbol search attempts failed for "${text}", falling back to pictogram`);
    return null;
}

// --- Initialize on Page Load ---
document.addEventListener('DOMContentLoaded', async () => {
    const userReady = await initializeUserContext();
    if (!userReady) {
        window.location.href = '/static/auth.html';
        return;
    }

    // Initialize the page (loads settings first)
    await initializeFreestylePage();
    
    // Setup input listeners
    setupKeyboardListener();
    setupGamepadListeners();
    
    // Setup audio context resume listeners
    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true });
    
    // Setup PIN modal functionality
    setupPinModal();
    
    // Start scanning after everything is initialized
    startInitialScanning();
});

// --- User Context Initialization (Same as gridpage.js) ---
async function initializeUserContext() {
    firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);

    if (!firebaseIdToken || !currentAacUserId) {
        console.error('User authentication not found. Redirecting to auth page.');
        return false;
    }
    console.log(`User context initialized. AAC User ID: ${currentAacUserId}`);
    
    // Load and update page title with profile name
    await updatePageTitleWithProfile();
    
    return true;
}

// Function to update page title with profile name and source context
async function updatePageTitleWithProfile() {
    try {
        const response = await authenticatedFetch('/api/account/users');
        if (!response.ok) return;
        
        const profiles = await response.json();
        const currentProfile = profiles.find(profile => profile.aac_user_id === currentAacUserId);
        
        if (currentProfile && currentProfile.display_name) {
            const titleElement = document.getElementById('dynamic-page-title');
            if (titleElement) {
                let baseTitle = 'Free Style Communication';
                
                // Add source context to title if available
                const navContext = getNavigationContext();
                if (navContext.originating_button && navContext.is_llm_generated) {
                    // LLM-generated page — show the button text as topic
                    baseTitle = `Free Style - ${navContext.originating_button}`;
                } else if (navContext.source_page && navContext.source_page.toLowerCase() !== 'home') {
                    // Static page — show the page name as topic
                    const pageName = navContext.source_page.replace(/_/g, ' ').replace(/-/g, ' ')
                        .replace(/\b\w/g, c => c.toUpperCase());
                    baseTitle = `Free Style - ${pageName}`;
                }
                
                titleElement.textContent = `${baseTitle} - ${currentProfile.display_name}`;
                console.log(`Updated freestyle page title to include profile: ${currentProfile.display_name}, context: ${baseTitle}`);
            }
        }
    } catch (error) {
        console.error('Error updating page title with profile:', error);
    }
}

// --- Core Fetch Wrapper (Same as gridpage.js) ---
async function authenticatedFetch(url, options = {}, _isRetry = false) {
    // Re-read token from sessionStorage (may have been refreshed by token-refresh.js)
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        throw new Error('User not authenticated');
    }

    const headers = options.headers || {};
    headers['Authorization'] = `Bearer ${firebaseIdToken}`;
    headers['X-User-ID'] = currentAacUserId;
    
    // Check for admin context and add target account header if needed
    const adminTargetAccountId = sessionStorage.getItem('adminTargetAccountId');
    if (adminTargetAccountId) {
        headers['X-Admin-Target-Account'] = adminTargetAccountId;
    }
    
    options.headers = headers;

    const response = await fetch(url, options);
    if ((response.status === 401 || response.status === 403) && !_isRetry) {
        console.warn(`Auth failed (${response.status}) for ${url}. Attempting silent token refresh...`);
        if (typeof window.refreshFirebaseToken === 'function') {
            const newToken = await window.refreshFirebaseToken();
            if (newToken) {
                console.log('[AUTH] Token refreshed, retrying...');
                return authenticatedFetch(url, options, true);
            }
        }
        console.error('Authentication failed. Redirecting to auth page.');
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed');
    }
    if (response.status === 401 || response.status === 403) {
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed after token refresh');
    }
    return response;
}

// --- Settings Loading (Similar to gridpage.js) ---
async function loadScanSettings() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (response.ok) {
            const settings = await response.json();
            defaultDelay = settings.scanDelay || 3500;
            scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
            scanLoopLimit = settings.scanLoopLimit || 0;
            currentTtsVoiceName = settings.selected_tts_voice_name || 'en-US-Neural2-A';
            currentSpeechRate = settings.speech_rate || 180;
            autoClean = settings.autoClean || false; // Load Auto Clean setting
            // enablePictograms = settings.enablePictograms === true; // Load pictograms setting - Disabled for Freestyle
            
            // Update sight word service with new settings
            if (window.updateSightWordSettings) {
                window.updateSightWordSettings(settings);
                console.log('🔤 Updated sight word settings:', settings.sightWordGradeLevel);
            } else {
                console.warn('🔤 Sight word service not available');
            }
            
            // Load gridColumns setting
            if (settings && typeof settings.gridColumns === 'number' && !isNaN(settings.gridColumns)) {
                gridColumns = Math.max(2, Math.min(18, parseInt(settings.gridColumns)));
                console.log(`Grid Columns loaded: ${gridColumns}`);
            } else {
                gridColumns = 6; // Default value for alphabet grid
            }
            
            console.log('Scan settings loaded:', { defaultDelay, scanLoopLimit, gridColumns, autoClean, enablePictograms });
        }
    } catch (error) {
        console.error('Error loading scan settings:', error);
    }
}

// --- Grid Layout Update Function (Similar to gridpage.js) ---
function updateAlphabetGridLayout() {
    const grid = document.getElementById('alphabet-grid');
    if (!grid) return;
    
    // Letters are skinnier so we can fit more columns than the main grid
    // Use ~1.5x the gridColumns since letters only need narrow buttons
    const letterColumns = Math.max(6, Math.min(13, Math.round(gridColumns * 1.3)));
    grid.style.gridTemplateColumns = `repeat(${letterColumns}, 1fr)`;
    
    // Calculate font size matching gridpage formula
    const baseFontSize = 20; // Match gridpage base
    const minFontSize = 10;
    const maxFontSize = 28;
    
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / letterColumns)));
    grid.style.setProperty('--letter-font-size', `${fontSize}px`);
    
    console.log(`Alphabet grid layout updated to ${letterColumns} columns (from gridColumns=${gridColumns}) with ${fontSize}px font size`);
}

// --- Update Word Options Grid Layout ---
function updateWordOptionsGridLayout() {
    const grid = document.getElementById('word-options-grid');
    if (!grid) return;
    
    // Update the CSS grid template columns based on gridColumns setting
    grid.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
    
    // Calculate font size for word options (matching gridpage formula)
    const baseFontSize = 20; // Match gridpage base font size
    const minFontSize = 10;  // Match gridpage minimum
    const maxFontSize = 28;  // Match gridpage maximum
    
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / gridColumns)));
    grid.style.setProperty('--word-option-font-size', `${fontSize}px`);
    
    console.log(`Word options grid layout updated to ${gridColumns} columns with ${fontSize}px font size`);
}

// --- Update Word Predictions Grid Layout ---
function updateWordPredictionsGridLayout() {
    const grid = document.getElementById('word-predictions');
    if (!grid) return;
    
    // Update the CSS grid template columns based on gridColumns setting
    grid.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
    
    // Calculate font size for predictions
    const baseFontSize = 14; // Base font size for predictions
    const minFontSize = 10;  // Minimum font size
    const maxFontSize = 16;  // Maximum font size
    
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (6 / gridColumns)));
    grid.style.setProperty('--prediction-font-size', `${fontSize}px`);
    
    console.log(`Word predictions grid layout updated to ${gridColumns} columns with ${fontSize}px font size`);
}

// --- Initialize Freestyle Page ---
async function initializeFreestylePage() {
    // Load settings first before setting up PIN modal
    await loadScanSettings();
    
    // Setup event listeners for control buttons (only the remaining ones)
    document.getElementById('speak-display-btn').addEventListener('click', speakDisplayText);
    document.getElementById('clear-display-btn').addEventListener('click', clearDisplayText);
    document.getElementById('go-back-btn').addEventListener('click', goBackToGrid);
    
    // Setup build space text area
    const buildSpaceTextarea = document.getElementById('build-space');
    buildSpaceTextarea.addEventListener('input', onBuildSpaceChange);
    
    // Setup spelling modal
    setupSpellingModal();
    
    // Setup choose word modal
    setupChooseWordModal();
    
    // Load initial word options and wait for completion before starting scanning
    await loadWordOptions();
    
    console.log('Freestyle page initialized');
}

// Function to start scanning after page is fully ready
function startInitialScanning() {
    console.log('startInitialScanning called');
    console.log('scanningPaused:', scanningPaused);
    console.log('currentScanningContext:', currentScanningContext);
    
    // Wait a bit longer and ensure buttons exist
    setTimeout(() => {
        const wordButtons = document.querySelectorAll('.word-option-btn');
        const controlButtons = document.querySelectorAll('#speak-display-btn, #go-back-btn, #clear-display-btn');
        console.log(`Found ${wordButtons.length} word buttons and ${controlButtons.length} control buttons`);
        
        if (wordButtons.length === 0) {
            console.warn('No word buttons found, retrying in 1 second...');
            setTimeout(startInitialScanning, 1000);
            return;
        }
        
        scanningPaused = false;
        startScanning();
        console.log('Initial scanning started with buttons available');
    }, 1000); // Increased delay to ensure buttons are rendered
}

// --- Build Space Management ---
function onBuildSpaceChange() {
    const buildSpaceTextarea = document.getElementById('build-space');
    currentBuildSpaceText = buildSpaceTextarea.value;
    
    // Debounced reload of word options when build space changes
    clearTimeout(window.buildSpaceDebounceTimer);
    window.buildSpaceDebounceTimer = setTimeout(() => {
        loadWordOptions();
    }, 1000); // Wait 1 second after user stops typing
}

function addWordToBuildSpace(word) {
    const buildSpaceTextarea = document.getElementById('build-space');
    if (currentBuildSpaceText.trim()) {
        currentBuildSpaceText += ' ' + word;
    } else {
        currentBuildSpaceText = word;
    }
    buildSpaceTextarea.value = currentBuildSpaceText;
    
    // Reload word options with new context
    loadWordOptions();
}

async function speakDisplayText() {
    if (!currentBuildSpaceText.trim()) {
        await announce("Nothing to speak", "system", false);
        return;
    }
    console.log('Auto Clean enabled? ', autoClean);
    // If Auto Clean is enabled, automatically clean up the text first
    if (autoClean) {
        console.log('Auto Clean enabled - cleaning text before speaking');
        await cleanupTextInternal(); // Use internal cleanup to avoid duplicate loading indicators
    }
    
    await announce(currentBuildSpaceText, "system", true);
    
    // Record to speech history (following gridpage.js pattern)
    recordToSpeechHistory(currentBuildSpaceText);
    
    // Pause scanning for the scanning interval duration, then reset to Go Back button
    if (scanningInterval) {
        stopScanning();
        
        setTimeout(() => {
            // Reset to Go Back button and resume scanning
            if (!scanningPaused && currentScanningContext === "main") {
                console.log('Resuming scanning after Speak Display');
                
                // Build the same button list as in startMainScanning() - exactly matching that logic
                let controlButtons = [];
                if (currentBuildSpaceText.trim()) {
                    controlButtons = Array.from(document.querySelectorAll('#speak-display-btn, #go-back-btn, #clear-display-btn'));
                }
                
                const wordButtons = Array.from(document.querySelectorAll('.word-option-btn'));
                const allButtons = [...controlButtons, ...wordButtons];
                
                console.log(`Total buttons found: ${allButtons.length}, Control buttons: ${controlButtons.length}`);
                
                // Find the index of the Go Back button - it should be index 1 (after Speak Display at index 0)
                const goBackIndex = allButtons.findIndex(btn => btn && btn.id === 'go-back-btn');
                console.log(`Go Back button found at index: ${goBackIndex}`);
                
                if (goBackIndex !== -1 && goBackIndex > 0) {
                    // Set to Go Back button index
                    currentButtonIndex = goBackIndex;
                    console.log(`✅ Reset scanning to Go Back button at index ${goBackIndex}`);
                } else {
                    // Fallback to first word button if Go Back not found or is at wrong position
                    currentButtonIndex = Math.max(1, controlButtons.length); // Skip Speak Display button
                    console.log(`⚠️ Go Back button issue, starting with button at index ${currentButtonIndex}`);
                }
                
                startScanning();
            }
        }, 1000); // Use fixed 1 second delay instead of defaultDelay to make it more predictable
    }
}

function clearDisplayText() {
    const buildSpaceTextarea = document.getElementById('build-space');
    currentBuildSpaceText = "";
    buildSpaceTextarea.value = "";
    
    // Reload word options
    loadWordOptions();
}

async function cleanupDisplayText() {
    if (!currentBuildSpaceText.trim()) {
        await announce("Nothing to clean up", "system", false);
        return;
    }
    
    if (isLLMProcessing) {
        await announce("Please wait, processing", "system", false);
        return;
    }
    
    try {
        isLLMProcessing = true;
        showLoadingIndicator(true);
        
        await cleanupTextInternal();
        
        // Announce the change
        await announce("Text cleaned up", "system", false);
    } catch (error) {
        console.error('Error cleaning up text:', error);
        await announce("Cleanup error", "system", false);
    } finally {
        isLLMProcessing = false;
        showLoadingIndicator(false);
    }
}

// Internal cleanup function without loading indicators (for auto-clean)
async function cleanupTextInternal() {
    const response = await authenticatedFetch('/api/freestyle/cleanup-text', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            text_to_cleanup: currentBuildSpaceText
        })
    });
    
    if (response.ok) {
        const data = await response.json();
        const cleanedText = data.cleaned_text || currentBuildSpaceText;
        console.log("Original text:", currentBuildSpaceText);
        console.log("Cleaned text:", cleanedText);
        // Update the build space with cleaned text
        currentBuildSpaceText = cleanedText;
        const buildSpaceTextarea = document.getElementById('build-space');
        buildSpaceTextarea.value = currentBuildSpaceText;
        
        // Reload word options with new context
        loadWordOptions();
    } else {
        console.error('Failed to cleanup text:', response.statusText);
        throw new Error('Cleanup failed');
    }
}

function goBackToGrid() {
    // Navigate back to gridpage.html with the home page
    window.location.href = '/static/gridpage.html?page=home';
}

// --- Word Options Management ---
async function loadWordOptions() {
    if (isLLMProcessing) return;
    
    try {
        isLLMProcessing = true;
        showLoadingIndicator(true);
        
        // Get navigation context for contextual word suggestions
        const navContext = getNavigationContext();
        console.log('DEBUG: Navigation context:', navContext);
        console.log('DEBUG: URL params:', window.location.search);
        
        const requestPayload = {
            build_space_text: currentBuildSpaceText,
            context: navContext.context,
            source_page: navContext.source_page,
            is_llm_generated: navContext.is_llm_generated,
            originating_button_text: navContext.originating_button
        };
        console.log('DEBUG: Freestyle API request payload:', requestPayload);
        
        const response = await authenticatedFetch('/api/freestyle/word-options', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(requestPayload)
        });
        
        if (response.ok) {
            const data = await response.json();
            console.log(`Loaded word options: ${JSON.stringify(data.word_options)}`);
            currentWordOptions = data.word_options || [];
            renderWordOptionsGrid();
        } else {
            console.error('Failed to load word options:', response.statusText);
            // Show fallback options
            currentWordOptions = ["I", "want", "need", "can", "please", "thank you", "help", "yes", "no", "good"];
            renderWordOptionsGrid();
        }
    } catch (error) {
        console.error('Error loading word options:', error);
        currentWordOptions = ["I", "want", "need", "can", "please", "thank you", "help", "yes", "no", "good"];
        renderWordOptionsGrid();
    } finally {
        isLLMProcessing = false;
        showLoadingIndicator(false);
        
        // Restart scanning after new options are loaded and rendered
        if (currentScanningContext === "main" && !scanningInterval && !scanningPaused) {
            setTimeout(() => {
                if (!scanningInterval) { // Double check
                    startScanning();
                }
            }, 500);
        }
    }
}

async function renderWordOptionsGrid() {
    const grid = document.getElementById('word-options-grid');
    grid.innerHTML = '';
    
    // Update grid layout to use current gridColumns setting
    updateWordOptionsGridLayout();
    
    // Create word option buttons with images
    for (let i = 0; i < currentWordOptions.length; i++) {
        const word = currentWordOptions[i];
        const wordData = currentWordOptions[i];
        
        const button = document.createElement('button');
        button.className = 'word-option-btn';
        button.setAttribute('data-index', i);
        button.addEventListener('click', () => handleWordOptionClick(word));
        
        // Get keywords if available (from LLM responses)
        const keywords = (typeof wordData === 'object' && wordData.keywords) ? wordData.keywords : null;
        const displayText = (typeof wordData === 'object' && wordData.text) ? wordData.text : wordData;
        
        // Check for sight words BEFORE optimization (using original text)
        let symbolImageUrl = null;
        if (window.isSightWord && window.isSightWord(displayText)) {
            console.log(`🔤 Main freestyle sight word detected: "${displayText}" - using text-only display`);
            symbolImageUrl = null; // Force text-only for sight words
        } else {
            // Get optimized search term for better image matching
            const optimizedSearchTerm = getOptimizedSearchTerm(displayText, keywords);
            console.log(`🔍 Image search optimization: "${displayText}" → "${optimizedSearchTerm}"`);
            
            // Try to get symbol image first, fall back to pictogram if needed
            symbolImageUrl = await getSymbolImageForText(optimizedSearchTerm, keywords);
        }
        
        if (symbolImageUrl) {
            // Create container with dedicated image area and text footer
            const buttonContent = document.createElement('div');
            buttonContent.style.position = 'relative';
            buttonContent.style.width = '100%';
            buttonContent.style.height = '100%';
            buttonContent.style.display = 'flex';
            buttonContent.style.flexDirection = 'column';
            
            // Image container (takes up most of button height)
            const imageContainer = document.createElement('div');
            imageContainer.style.flex = '1';
            imageContainer.style.width = '100%';
            imageContainer.style.overflow = 'hidden';
            imageContainer.style.borderRadius = '8px 8px 0 0';
            imageContainer.style.display = 'flex';
            imageContainer.style.alignItems = 'center';
            imageContainer.style.justifyContent = 'center';
            
            const imageElement = document.createElement('img');
            imageElement.src = symbolImageUrl;
            imageElement.alt = displayText;
            imageElement.style.width = '100%';
            imageElement.style.height = '100%';
            imageElement.style.objectFit = 'cover';
            imageElement.onerror = () => {
                // If image fails to load, fall back to pictogram
                const pictogram = getPictogramForText(displayText);
                if (pictogram) {
                    const pictogramSpan = document.createElement('span');
                    pictogramSpan.textContent = pictogram;
                    pictogramSpan.style.fontSize = '3em';
                    pictogramSpan.style.lineHeight = '1';
                    pictogramSpan.style.color = '#666';
                    imageContainer.replaceChild(pictogramSpan, imageElement);
                }
            };
            
            // Text footer (matching gridpage)
            const textFooter = document.createElement('div');
            textFooter.style.height = '28px';
            textFooter.style.width = '100%';
            textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
            textFooter.style.color = 'white';
            textFooter.style.display = 'flex';
            textFooter.style.alignItems = 'center';
            textFooter.style.justifyContent = 'center';
            textFooter.style.padding = '2px 4px';
            textFooter.style.margin = '0';
            textFooter.style.borderRadius = '0';
            textFooter.style.position = 'absolute';
            textFooter.style.bottom = '0';
            textFooter.style.left = '0';
            textFooter.style.right = '0';
            
            const textSpan = document.createElement('span');
            textSpan.textContent = displayText;
            textSpan.style.fontSize = '0.7em';
            textSpan.style.fontWeight = 'bold';
            textSpan.style.textAlign = 'center';
            textSpan.style.lineHeight = '1.1';
            textSpan.style.wordWrap = 'break-word';
            textSpan.style.hyphens = 'auto';
            textSpan.style.overflow = 'hidden';
            textSpan.style.display = '-webkit-box';
            textSpan.style.webkitLineClamp = '2';
            textSpan.style.webkitBoxOrient = 'vertical';
            
            imageContainer.appendChild(imageElement);
            textFooter.appendChild(textSpan);
            buttonContent.appendChild(imageContainer);
            buttonContent.appendChild(textFooter);
            button.appendChild(buttonContent);
        } else {
            // Fall back to pictogram if no symbol image found
            const pictogram = getPictogramForText(displayText);
            if (pictogram) {
                const pictogramSpan = document.createElement('span');
                pictogramSpan.textContent = pictogram;
                pictogramSpan.style.fontSize = '3.5em';
                pictogramSpan.style.lineHeight = '1';
                pictogramSpan.style.color = '#666';
                pictogramSpan.style.textAlign = 'center';
                pictogramSpan.style.display = 'block';
                pictogramSpan.style.marginBottom = '5px';
                
                const textSpan = document.createElement('span');
                textSpan.textContent = displayText;
                textSpan.style.fontSize = '0.9em';
                textSpan.style.fontWeight = '500';
                textSpan.style.display = 'block';
                textSpan.style.textAlign = 'center';
                textSpan.style.wordWrap = 'break-word';
                textSpan.style.hyphens = 'auto';
                
                button.appendChild(pictogramSpan);
                button.appendChild(textSpan);
            } else {
                // Pure text fallback - increase text size for sight words
                button.textContent = displayText;
                button.style.fontSize = '1.8em'; // Double the size
                button.style.fontWeight = 'bold';
                button.style.textAlign = 'center';
                button.style.display = 'flex';
                button.style.alignItems = 'center';
                button.style.justifyContent = 'center';
            }
        }
        
        grid.appendChild(button);
    }
    
    // Add Choose Word button (comes first)
    const chooseWordButton = document.createElement('button');
    chooseWordButton.className = 'word-option-btn choose-word-button';
    chooseWordButton.innerHTML = '<i class="fas fa-list"></i> Choose Word';
    chooseWordButton.id = 'choose-word-btn-lower';
    chooseWordButton.addEventListener('click', () => openChooseWordModal());
    grid.appendChild(chooseWordButton);
    
    // Add Spell button (comes second)
    const spellButton = document.createElement('button');
    spellButton.className = 'word-option-btn spell-button';
    spellButton.innerHTML = '<i class="fas fa-keyboard"></i> Spell';
    spellButton.id = 'spell-btn-lower';
    spellButton.addEventListener('click', () => openSpellingModal());
    grid.appendChild(spellButton);
    
    // Add "More Options" button
    const moreButton = document.createElement('button');
    moreButton.className = 'word-option-btn more-options-btn';
    moreButton.textContent = 'More Options';
    moreButton.addEventListener('click', () => loadMoreWordOptions());
    grid.appendChild(moreButton);
    
    console.log(`Rendered ${currentWordOptions.length} word options + Spell + Choose Word + More Options buttons`);
}

async function loadMoreWordOptions() {
    if (isLLMProcessing) return;
    
    try {
        isLLMProcessing = true;
        showLoadingIndicator(true);
        
        // Include navigation context so refreshed options stay relevant to the source page topic
        const navContext = getNavigationContext();
        
        const response = await authenticatedFetch('/api/freestyle/word-options', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                build_space_text: currentBuildSpaceText,
                request_different_options: true, // Signal to generate different options
                context: navContext.context,
                source_page: navContext.source_page,
                is_llm_generated: navContext.is_llm_generated,
                originating_button_text: navContext.originating_button
            })
        });
        
        if (response.ok) {
            const data = await response.json();
            currentWordOptions = data.word_options || [];
            renderWordOptionsGrid();
        } else {
            console.error('Failed to load more word options:', response.statusText);
        }
    } catch (error) {
        console.error('Error loading more word options:', error);
    } finally {
        isLLMProcessing = false;
        showLoadingIndicator(false);
        
        // Restart scanning after new options are loaded
        if (currentScanningContext === "main" && !scanningInterval && !scanningPaused) {
            setTimeout(() => {
                if (!scanningInterval) { // Double check
                    startScanning();
                }
            }, 500);
        }
    }
}

async function handleWordOptionClick(word) {
    // Extract the display text from word object if needed
    const displayText = (typeof word === 'object' && word.text) ? word.text : word;
    
    // Announce the selected word
    await announce(displayText, "system", true);
    
    // Use display text for build space as well
    addWordToBuildSpace(displayText);
    
    // Stop scanning completely and restart only after word options are reloaded
    if (scanningInterval) {
        stopScanning();
    }
}

// --- Spelling Modal Management ---
function setupSpellingModal() {
    // Setup close modal listeners
    document.getElementById('cancel-spelling-btn').addEventListener('click', closeSpellingModal);
    document.getElementById('spelling-modal').addEventListener('click', (e) => {
        if (e.target.id === 'spelling-modal') {
            closeSpellingModal();
        }
    });
    
    // Setup word control buttons
    document.getElementById('add-word-btn').addEventListener('click', addCurrentWordToBuildSpace);
    document.getElementById('clear-word-btn').addEventListener('click', clearCurrentWord);
    document.getElementById('backspace-btn').addEventListener('click', backspaceCurrentWord);
    
    // Generate alphabet grid
    generateAlphabetGrid();
}


// Add this after the existing spelling modal setup
document.getElementById('current-word').addEventListener('input', async (e) => {
    const currentWord = e.target.value;
    
    // Update letter availability based on current word
    updateLetterAvailability(currentWord);
    
    const fullText = currentBuildSpaceText + ' ' + currentWord;
    if (currentWord.length > 0) {
        await getWordPredictionsForSpelling(fullText);
    } else {
        currentPredictions = [];
        renderWordPredictions();
    }
});

async function getWordPredictionsForSpelling(fullText) {
    if (isLLMProcessing) return;
    
    try {
        isLLMProcessing = true;
        
        // Extract the current word from the full text
        const currentWord = currentSpellingWord || "";
        
        const response = await authenticatedFetch('/api/freestyle/word-prediction', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                text: currentBuildSpaceText || "", // Context from build space
                spelling_word: currentWord, // Current partial word
                predict_full_words: true // Flag to ensure complete words are returned
            })
        });
        
        if (response.ok) {
            const data = await response.json();
            currentPredictions = data.predictions || [];
            renderWordPredictions();
        } else {
            console.error('Failed to get word predictions for spelling:', response.statusText);
            currentPredictions = [];
            renderWordPredictions();
        }
    } catch (error) {
        console.error('Error getting word predictions for spelling:', error);
        currentPredictions = [];
        renderWordPredictions();
    } finally {
        isLLMProcessing = false;
    }
}

function openSpellingModal() {
    isSpellingModalOpen = true;
    document.getElementById('spelling-modal').classList.remove('hidden');
    currentSpellingWord = "";
    document.getElementById('current-word').value = "";
    
    // COMPLETELY stop any current scanning
    stopScanning();
    scanningPaused = true; // Prevent auto-restart
    
    // Initialize smart letter filtering
    updateLetterAvailability("");
    
    // Clear predictions
    currentPredictions = [];
    renderWordPredictions();
    
    // Change context and start spell modal scanning
    currentScanningContext = "spelling-letters";
    
    // Start scanning for the spell modal after a brief delay
    setTimeout(() => {
        scanningPaused = false; // Re-enable scanning for spell modal
        startScanning();
    }, 800);
    
    console.log('Spelling modal opened, main scanning stopped');
}

function closeSpellingModal() {
    isSpellingModalOpen = false;
    document.getElementById('spelling-modal').classList.add('hidden');
    
    // Stop spell modal scanning completely
    stopScanning();
    scanningPaused = true; // Prevent auto-restart
    
    // Change context back to main
    currentScanningContext = "main";
    
    // Restart main scanning after a delay
    setTimeout(() => {
        scanningPaused = false; // Re-enable scanning
        startScanning();
    }, 800);
    
    console.log('Spelling modal closed, returning to main scanning');
}

function generateAlphabetGrid() {
    const grid = document.getElementById('alphabet-grid');
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    
    // Update grid layout to use current gridColumns setting
    updateAlphabetGridLayout();
    
    alphabet.forEach((letter, index) => {
        const button = document.createElement('button');
        button.className = 'letter-btn';
        button.textContent = letter;
        button.setAttribute('data-letter', letter);
        button.setAttribute('data-index', index);
        button.addEventListener('click', () => handleLetterClick(letter));
        grid.appendChild(button);
    });
}

async function handleLetterClick(letter) {
    currentSpellingWord += letter.toLowerCase();
    document.getElementById('current-word').value = currentSpellingWord;
    
    // Update letter availability immediately
    updateLetterAvailability(currentSpellingWord);
    
    // Get word predictions
    await getWordPredictions();
    
    restartScanningForCurrentContext(400);
}

async function getWordPredictions() {
    if (isLLMProcessing) return;
    
    try {
        isLLMProcessing = true;
        
        // Send spelling word and build space separately to ensure full word predictions
        const response = await authenticatedFetch('/api/freestyle/word-prediction', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                text: currentBuildSpaceText || "", // Context from build space
                spelling_word: currentSpellingWord || "", // Current partial word
                predict_full_words: true // Flag to ensure complete words are returned
            })
        });
        
        if (response.ok) {
            const data = await response.json();
            currentPredictions = data.predictions || [];
            renderWordPredictions();
        } else {
            console.error('Failed to get word predictions:', response.statusText);
            currentPredictions = [];
            renderWordPredictions();
        }
    } catch (error) {
        console.error('Error getting word predictions:', error);
        currentPredictions = [];
        renderWordPredictions();
    } finally {
        isLLMProcessing = false;
    }
}

function renderWordPredictions() {
    const grid = document.getElementById('word-predictions');
    grid.innerHTML = '';
    
    // Update grid layout to use current gridColumns setting
    updateWordPredictionsGridLayout();
    
    currentPredictions.forEach((word, index) => {
        const button = document.createElement('button');
        button.className = 'prediction-btn';
        button.textContent = word;
        button.setAttribute('data-index', index);
        button.addEventListener('click', () => handlePredictionClick(word));
        grid.appendChild(button);
    });
}

async function handlePredictionClick(word) {
    // Announce the selected word
    await announce(word, "system", true);
    
    // Immediately add the selected prediction to Build Space and close modal
    currentSpellingWord = word;
    document.getElementById('current-word').value = currentSpellingWord;
    
    // Add word to build space and close modal
    addWordToBuildSpace(currentSpellingWord);
    clearCurrentWord();
    closeSpellingModal();
}

async function addCurrentWordToBuildSpace() {
    if (currentSpellingWord.trim()) {
        // Announce the selected word
        await announce(currentSpellingWord, "system", true);
        
        addWordToBuildSpace(currentSpellingWord);
        clearCurrentWord();
        closeSpellingModal();
    }
}

function clearCurrentWord() {
    currentSpellingWord = "";
    document.getElementById('current-word').value = "";
    
    // Reset letter availability
    updateLetterAvailability("");
    
    currentPredictions = [];
    renderWordPredictions();
    
    restartScanningForCurrentContext(400);
}

function backspaceCurrentWord() {
    if (currentSpellingWord.length > 0) {
        currentSpellingWord = currentSpellingWord.slice(0, -1);
        document.getElementById('current-word').value = currentSpellingWord;
        
        // Update letter availability immediately
        updateLetterAvailability(currentSpellingWord);
        
        getWordPredictions();
        
        restartScanningForCurrentContext(400);
    }
}

// --- Choose Word Modal Grid Layout (match gridpage sizing) ---
function updateModalGridLayout() {
    // Apply same grid columns and font size as main word-options grid
    const categoryGrid = document.getElementById('category-grid');
    const wordOptionsGrid = document.getElementById('category-word-options-grid');
    
    const baseFontSize = 20;
    const minFontSize = 10;
    const maxFontSize = 28;
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / gridColumns)));
    
    [categoryGrid, wordOptionsGrid].forEach(grid => {
        if (grid) {
            grid.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
            grid.style.setProperty('--word-option-font-size', `${fontSize}px`);
        }
    });
    
    console.log(`Modal grid layout updated to ${gridColumns} columns with ${fontSize}px font size`);
}

// --- Choose Word Modal Management ---
function setupChooseWordModal() {
    // Setup event listeners
    document.getElementById('cancel-choose-word-btn').addEventListener('click', closeChooseWordModal);
    document.getElementById('back-to-categories-btn').addEventListener('click', showCategorySelection);
    document.getElementById('something-else-words-btn').addEventListener('click', generateDifferentWords);
    document.getElementById('go-back-from-words-btn').addEventListener('click', closeChooseWordModal);
    
    // Handle modal background click
    document.getElementById('choose-word-modal').addEventListener('click', (e) => {
        if (e.target.id === 'choose-word-modal') {
            closeChooseWordModal();
        }
    });
}

function openChooseWordModal() {
    console.log('Opening Choose Word modal');
    
    // Set modal state
    isChooseWordModalOpen = true;
    currentScanningContext = "choose-word-categories";
    
    // Reset modal state
    currentChooseWordCategory = "";
    currentCategoryWords = [];
    
    // Show modal
    document.getElementById('choose-word-modal').classList.remove('hidden');
    
    // Apply gridpage-matching layout to modal grids
    updateModalGridLayout();
    
    // Show category selection
    showCategorySelection();
    
    restartScanningForCurrentContext(300);
}

function closeChooseWordModal() {
    console.log('Closing Choose Word modal');
    
    // Set modal state
    isChooseWordModalOpen = false;
    currentScanningContext = "main";
    
    // Reset state
    currentChooseWordCategory = "";
    currentCategoryWords = [];
    
    // Hide modal
    document.getElementById('choose-word-modal').classList.add('hidden');
    
    restartScanningForCurrentContext(300);
}

function showCategorySelection() {
    console.log('Showing category selection');
    
    // Update scanning context
    currentScanningContext = "choose-word-categories";
    
    // Show category section, hide word options section
    document.getElementById('category-section').classList.remove('hidden');
    document.getElementById('word-options-section').classList.add('hidden');
    
    // Generate category buttons
    generateCategoryButtons();
    
    restartScanningForCurrentContext(300);
}

function generateCategoryButtons() {
    const categoryGrid = document.getElementById('category-grid');
    
    // Define categories with additional suggestions
    const categories = [
        { name: "People", icon: "fas fa-users" },
        { name: "Places", icon: "fas fa-map-marker-alt" },
        { name: "Animals", icon: "fas fa-paw" },
        { name: "Insects", icon: "fas fa-bug" },
        { name: "Reptiles", icon: "fas fa-dragon" },
        { name: "Fish", icon: "fas fa-fish" },
        { name: "Birds", icon: "fas fa-dove" },
        { name: "Wild Animals", icon: "fas fa-paw" },
        { name: "Around the House", icon: "fas fa-home" },
        { name: "In the Room", icon: "fas fa-couch" },
        { name: "General things", icon: "fas fa-cube" },
        { name: "Actions", icon: "fas fa-running" },
        { name: "Feelings & Emotions", icon: "fas fa-heart" },
        { name: "Questions & Comments", icon: "fas fa-question-circle" },
        { name: "Times and Dates", icon: "fas fa-calendar" },
        { name: "Activities & Hobbies", icon: "fas fa-gamepad" },
        { name: "Medical & Health", icon: "fas fa-heartbeat" },
        { name: "Food & Drinks", icon: "fas fa-utensils" },
        { name: "Colors & Descriptions", icon: "fas fa-palette" },
        { name: "Numbers & Quantities", icon: "fas fa-calculator" },
        { name: "School & Learning", icon: "fas fa-graduation-cap" },
        { name: "Transportation", icon: "fas fa-car" },
        { name: "Weather", icon: "fas fa-cloud-sun" },
        { name: "Technology", icon: "fas fa-laptop" },
        { name: "Sports & Games", icon: "fas fa-trophy" }
    ];
    
    // Clear existing categories
    categoryGrid.innerHTML = '';
    
    // Create category buttons (text only, no icons, for better fit)
    categories.forEach((category, index) => {
        const button = document.createElement('button');
        button.className = 'freestyle-modal-btn category-btn';
        button.textContent = category.name;
        button.addEventListener('click', () => selectCategory(category.name));
        categoryGrid.appendChild(button);
    });
}

async function selectCategory(categoryName) {
    console.log('Selected category:', categoryName);
    
    // Set current category
    currentChooseWordCategory = categoryName;
    
    // Update title
    document.getElementById('selected-category-title').textContent = `${categoryName}:`;
    
    // Show word options section, hide category section
    document.getElementById('category-section').classList.add('hidden');
    document.getElementById('word-options-section').classList.remove('hidden');
    
    // Update scanning context
    currentScanningContext = "choose-word-options";
    
    // Generate words for the category
    await generateCategoryWords(categoryName);
}

async function generateCategoryWords(categoryName, excludeWords = []) {
    if (isLLMProcessing) return;
    
    try {
        isLLMProcessing = true;
        showLoadingIndicator();
        
        // Get current build space content for context
        const buildSpaceContent = document.getElementById('build-space').value.trim();
        
        // Prepare the request
        const requestData = {
            category: categoryName,
            build_space_content: buildSpaceContent,
            exclude_words: excludeWords
        };
        
        console.log('Generating category words:', requestData);
        
        const response = await authenticatedFetch('/api/freestyle/category-words', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(requestData)
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const data = await response.json();
        console.log('Category words response:', data);
        
        if (data.words && Array.isArray(data.words)) {
            currentCategoryWords = data.words;
            displayCategoryWords();
        } else {
            console.error('Invalid category words response format');
            announceText('Error generating word options. Please try again.');
        }
        
    } catch (error) {
        console.error('Error generating category words:', error);
        announceText('Error generating word options. Please try again.');
    } finally {
        isLLMProcessing = false;
        showLoadingIndicator(false);
    }
}

async function displayCategoryWords() {
    const wordOptionsGrid = document.getElementById('category-word-options-grid');
    
    // Clear existing words
    wordOptionsGrid.innerHTML = '';
    
    // Apply gridpage-matching layout
    updateModalGridLayout();
    
    // Add word buttons with images
    for (let i = 0; i < currentCategoryWords.length; i++) {
        const word = currentCategoryWords[i];
        const wordData = currentCategoryWords[i];
        
        const button = document.createElement('button');
        button.className = 'freestyle-modal-btn word-option-btn';
        button.addEventListener('click', () => selectCategoryWord(word));
        
        // Get keywords if available (from LLM responses)
        const keywords = (typeof wordData === 'object' && wordData.keywords) ? wordData.keywords : null;
        const displayText = (typeof wordData === 'object' && wordData.text) ? wordData.text : wordData;
        
        // Get optimized search term for better image matching
        const optimizedSearchTerm = getOptimizedSearchTerm(displayText, keywords);
        console.log(`🔍 Choose Word image search optimization: "${displayText}" → "${optimizedSearchTerm}"`);
        
        // Try to get symbol image first, fall back to pictogram if needed
        let symbolImageUrl = await getSymbolImageForText(optimizedSearchTerm, keywords);
        
        if (symbolImageUrl) {
            // Create container with dedicated image area and text footer
            const buttonContent = document.createElement('div');
            buttonContent.style.position = 'relative';
            buttonContent.style.width = '100%';
            buttonContent.style.height = '100%';
            buttonContent.style.display = 'flex';
            buttonContent.style.flexDirection = 'column';
            
            // Image container (takes up most of button height)
            const imageContainer = document.createElement('div');
            imageContainer.style.flex = '1';
            imageContainer.style.width = '100%';
            imageContainer.style.overflow = 'hidden';
            imageContainer.style.borderRadius = '8px 8px 0 0';
            imageContainer.style.display = 'flex';
            imageContainer.style.alignItems = 'center';
            imageContainer.style.justifyContent = 'center';
            
            const imageElement = document.createElement('img');
            imageElement.src = symbolImageUrl;
            imageElement.alt = displayText;
            imageElement.style.width = '100%';
            imageElement.style.height = '100%';
            imageElement.style.objectFit = 'cover';
            imageElement.onerror = () => {
                // If image fails to load, fall back to pictogram
                const pictogram = getPictogramForText(displayText);
                if (pictogram) {
                    const pictogramSpan = document.createElement('span');
                    pictogramSpan.textContent = pictogram;
                    pictogramSpan.style.fontSize = '3em';
                    pictogramSpan.style.lineHeight = '1';
                    pictogramSpan.style.color = '#666';
                    imageContainer.replaceChild(pictogramSpan, imageElement);
                }
            };
            
            // Text footer (matching gridpage)
            const textFooter = document.createElement('div');
            textFooter.style.height = '28px';
            textFooter.style.width = '100%';
            textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
            textFooter.style.color = 'white';
            textFooter.style.display = 'flex';
            textFooter.style.alignItems = 'center';
            textFooter.style.justifyContent = 'center';
            textFooter.style.padding = '2px 4px';
            textFooter.style.margin = '0';
            textFooter.style.borderRadius = '0';
            textFooter.style.position = 'absolute';
            textFooter.style.bottom = '0';
            textFooter.style.left = '0';
            textFooter.style.right = '0';
            
            const textSpan = document.createElement('span');
            textSpan.textContent = displayText;
            textSpan.style.fontSize = '0.7em';
            textSpan.style.fontWeight = 'bold';
            textSpan.style.textAlign = 'center';
            textSpan.style.lineHeight = '1.1';
            textSpan.style.wordWrap = 'break-word';
            textSpan.style.hyphens = 'auto';
            textSpan.style.overflow = 'hidden';
            textSpan.style.display = '-webkit-box';
            textSpan.style.webkitLineClamp = '2';
            textSpan.style.webkitBoxOrient = 'vertical';
            
            imageContainer.appendChild(imageElement);
            textFooter.appendChild(textSpan);
            buttonContent.appendChild(imageContainer);
            buttonContent.appendChild(textFooter);
            button.appendChild(buttonContent);
        } else {
            // Fall back to pictogram if no symbol image found
            const pictogram = getPictogramForText(displayText);
            if (pictogram) {
                const pictogramSpan = document.createElement('span');
                pictogramSpan.textContent = pictogram;
                pictogramSpan.style.fontSize = '3.5em';
                pictogramSpan.style.lineHeight = '1';
                pictogramSpan.style.color = '#666';
                pictogramSpan.style.textAlign = 'center';
                pictogramSpan.style.display = 'block';
                pictogramSpan.style.marginBottom = '5px';
                
                const textSpan = document.createElement('span');
                textSpan.textContent = displayText;
                textSpan.style.fontSize = '0.9em';
                textSpan.style.fontWeight = '500';
                textSpan.style.display = 'block';
                textSpan.style.textAlign = 'center';
                textSpan.style.wordWrap = 'break-word';
                textSpan.style.hyphens = 'auto';
                
                button.appendChild(pictogramSpan);
                button.appendChild(textSpan);
            } else {
                // Pure text fallback
                button.textContent = displayText;
            }
        }
        
        wordOptionsGrid.appendChild(button);
    }
    
    restartScanningForCurrentContext(300);
}

async function generateDifferentWords() {
    console.log('Generating different words for category:', currentChooseWordCategory);
    
    // Extract display text strings from current words to exclude them
    const excludeWords = currentCategoryWords.map(w => 
        (typeof w === 'object' && w.text) ? w.text : String(w)
    );
    console.log('Excluding words:', excludeWords);
    
    // Generate new words excluding current ones
    await generateCategoryWords(currentChooseWordCategory, excludeWords);
}

async function selectCategoryWord(word) {
    console.log('Selected word:', word);
    
    // Extract the display text from word object if needed
    const displayText = (typeof word === 'object' && word.text) ? word.text : word;
    
    // Announce the selected word
    await announce(displayText, "system", true);
    
    // Add word to build space
    addWordToBuildSpace(displayText);
    
    // Close modal
    closeChooseWordModal();
    
    // Follow same flow as freestyle options - speak display
    setTimeout(() => {
        speakDisplayText();
    }, 500);
}

// --- Speech History Management (Following gridpage.js pattern) ---
function recordToSpeechHistory(textToRecord) {
    if (!currentAacUserId || !textToRecord.trim()) {
        return;
    }
    
    try {
        // Get existing history from localStorage
        let history = (localStorage.getItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId)) || '').split('\n').filter(Boolean);
        
        // Add new text to the beginning of the array
        history.unshift(textToRecord.trim());
        
        // Limit to 20 entries (same as gridpage.js)
        if (history.length > 20) { 
            history = history.slice(0, 20); 
        }
        
        // Save back to localStorage
        localStorage.setItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId), history.join('\n'));
        
        console.log('Speech history recorded:', textToRecord);
    } catch (error) {
        console.error('Error recording speech history:', error);
    }
}

// --- Auditory Scanning (Similar to gridpage.js but adapted for freestyle) ---
function startScanning() {
    if (scanningPaused) {
        console.log('Scanning is paused, not starting');
        return;
    }
    
    if (scanningInterval) {
        stopScanning();
    }
    
    scanCycleCount = 0;
    isPausedFromScanLimit = false;
    currentScanAdvanceFn = null;
    
    if (currentScanningContext === "main") {
        startMainScanning();
    } else if (currentScanningContext === "spelling-letters") {
        startSpellingLettersScanning();
    } else if (currentScanningContext === "spelling-predictions") {
        startSpellingPredictionsScanning();
    } else if (currentScanningContext === "choose-word-categories") {
        startChooseWordCategoriesScanning();
    } else if (currentScanningContext === "choose-word-options") {
        startChooseWordOptionsScanning();
    }
}

function startMainScanning() {
    console.log('Starting main scanning');
    
    // Context-aware scanning: control buttons first, then word options
    // Skip Speak Display, Go Back, and Clear Display buttons if Build Space is empty
    let controlButtons = [];
    if (currentBuildSpaceText.trim()) {
        controlButtons = Array.from(document.querySelectorAll('#speak-display-btn, #go-back-btn, #clear-display-btn'));
    }
    
    const wordButtons = Array.from(document.querySelectorAll('.word-option-btn'));
    const allButtons = [...controlButtons, ...wordButtons];
    
    if (allButtons.length === 0) {
        console.log('No buttons found for main scanning');
        return;
    }
    
    console.log(`Found ${allButtons.length} buttons for main scanning (Build space ${currentBuildSpaceText.trim() ? 'has content' : 'is empty'})`);
    currentButtonIndex = 0;
    
    const scanNext = async () => {
        // Remove highlight from previous button
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning-highlight');
        }
        
        // Check scan limit
        if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            stopScanning();
            isPausedFromScanLimit = true;
            return;
        }
        
        // Get current button
        const button = allButtons[currentButtonIndex];
        if (button) {
            currentlyScannedButton = button;
            speakAndHighlight(button);
        }
        
        // Move to next button
        currentButtonIndex++;
        if (currentButtonIndex >= allButtons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
    };
    
    scanNext(); // Start immediately
    currentScanAdvanceFn = scanNext;
    if (scanMode !== 'step') {
        scanningInterval = setInterval(scanNext, defaultDelay);
    }
}

function startSpellingLettersScanning() {
    console.log('Starting spell letters scanning');
    
    const scanNext = async () => {
        // Get fresh button lists each time to account for disabled letters and current word content
        // Skip Add Word, Clear, and Backspace buttons if Current Word is empty
        let controlButtonSelectors = '#cancel-spelling-btn';
        if (currentSpellingWord.trim()) {
            controlButtonSelectors = '#add-word-btn, #clear-word-btn, #backspace-btn, #cancel-spelling-btn';
        }
        
        const controlButtons = document.querySelectorAll(controlButtonSelectors);
        const predictionButtons = document.querySelectorAll('.prediction-btn');
        const letterButtons = document.querySelectorAll('.letter-btn:not(.disabled-letter):not([disabled])'); // Skip disabled letters
        const allButtons = [...controlButtons, ...predictionButtons, ...letterButtons];
        
        if (allButtons.length === 0) {
            console.log('No available buttons for spell scanning');
            return;
        }
        
        // Remove highlight from previous button
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning-highlight');
        }
        
        // Check scan limit
        if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            stopScanning();
            isPausedFromScanLimit = true;
            return;
        }
        
        // Reset index if we've gone beyond the updated list
        if (currentButtonIndex >= allButtons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
        
        // Get current button
        const button = allButtons[currentButtonIndex];
        if (button && !button.disabled && !button.classList.contains('disabled-letter')) {
            currentlyScannedButton = button;
            speakAndHighlight(button);
        }
        
        // Move to next button
        currentButtonIndex++;
        if (currentButtonIndex >= allButtons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
    };
    
    currentButtonIndex = 0;
    scanNext(); // Start immediately
    currentScanAdvanceFn = scanNext;
    if (scanMode !== 'step') {
        scanningInterval = setInterval(scanNext, defaultDelay);
    }
}

function startSpellingPredictionsScanning() {
    const buttons = document.querySelectorAll('.prediction-btn');
    if (buttons.length === 0) return;
    
    currentButtonIndex = 0;
    
    const scanNext = () => {
        // Remove highlight from previous button
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning-highlight');
        }
        
        // Check scan limit
        if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            stopScanning();
            isPausedFromScanLimit = true;
            return;
        }
        
        // Get current button
        const button = buttons[currentButtonIndex];
        if (button) {
            currentlyScannedButton = button;
            speakAndHighlight(button);
        }
        
        // Move to next button
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
    };
    
    scanNext(); // Start immediately
    currentScanAdvanceFn = scanNext;
    if (scanMode !== 'step') {
        scanningInterval = setInterval(scanNext, defaultDelay);
    }
}

function startChooseWordCategoriesScanning() {
    // Only scan buttons within the choose word modal
    const modal = document.getElementById('choose-word-modal');
    const categoryButtons = modal.querySelectorAll('.category-btn');
    const controlButtons = modal.querySelectorAll('#cancel-choose-word-btn');
    const allButtons = [...categoryButtons, ...controlButtons];
    if (allButtons.length === 0) return;
    const buttons = allButtons;
    
    currentButtonIndex = 0;
    
    const scanNext = () => {
        // Remove highlight from previous button
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning-highlight');
        }
        
        // Check scan limit
        if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            stopScanning();
            isPausedFromScanLimit = true;
            return;
        }
        
        // Get current button
        const button = buttons[currentButtonIndex];
        if (button) {
            currentlyScannedButton = button;
            speakAndHighlight(button);
        }
        
        // Move to next button
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
    };
    
    scanNext(); // Start immediately
    currentScanAdvanceFn = scanNext;
    if (scanMode !== 'step') {
        scanningInterval = setInterval(scanNext, defaultDelay);
    }
}

function startChooseWordOptionsScanning() {
    // Only scan buttons within the choose word modal
    const modal = document.getElementById('choose-word-modal');
    const wordButtons = modal.querySelectorAll('.word-option-btn');
    const controlButtons = modal.querySelectorAll('#back-to-categories-btn, #something-else-words-btn, #go-back-from-words-btn');
    const allButtons = [...wordButtons, ...controlButtons];
    if (allButtons.length === 0) return;
    const buttons = allButtons;
    
    currentButtonIndex = 0;
    
    const scanNext = () => {
        // Remove highlight from previous button
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning-highlight');
        }
        
        // Check scan limit
        if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            stopScanning();
            isPausedFromScanLimit = true;
            return;
        }
        
        // Get current button
        const button = buttons[currentButtonIndex];
        if (button) {
            currentlyScannedButton = button;
            speakAndHighlight(button);
        }
        
        // Move to next button
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
        }
    };
    
    scanNext(); // Start immediately
    currentScanAdvanceFn = scanNext;
    if (scanMode !== 'step') {
        scanningInterval = setInterval(scanNext, defaultDelay);
    }
}

function stopScanning() {
    if (scanningInterval) {
        clearInterval(scanningInterval);
        scanningInterval = null;
        console.log('Scanning stopped');
    }

    pendingHighlightSpeechToken += 1;
    if (pendingHighlightSpeechTimer) {
        clearTimeout(pendingHighlightSpeechTimer);
        pendingHighlightSpeechTimer = null;
    }
    interruptScanningAnnouncementPlayback();
    
    // Remove highlight from current button
    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning-highlight');
        currentlyScannedButton = null;
    }
    currentScanAdvanceFn = null;
    
    currentButtonIndex = -1;
    // Note: No need to cancel speech here as backend TTS handles its own queue
}

function speakAndHighlight(button) {
    // Remove scanning class from all buttons
    document.querySelectorAll('.scanning-highlight').forEach(btn => {
        btn.classList.remove('scanning-highlight');
    });
    
    button.classList.add('scanning-highlight');

    pendingHighlightSpeechToken += 1;
    const speechToken = pendingHighlightSpeechToken;
    if (pendingHighlightSpeechTimer) {
        clearTimeout(pendingHighlightSpeechTimer);
        pendingHighlightSpeechTimer = null;
    }

    interruptScanningAnnouncementPlayback();

    const textToSpeak = getButtonScanLabel(button);
    if (!textToSpeak) {
        return;
    }

    pendingHighlightSpeechTimer = setTimeout(() => {
        pendingHighlightSpeechTimer = null;
        if (speechToken !== pendingHighlightSpeechToken || currentlyScannedButton !== button) {
            return;
        }
        announce(textToSpeak, 'system', false).catch((error) => {
            console.error('Freestyle scanning announce error:', error);
        });
    }, 500);
}

function getButtonScanLabel(button) {
    if (!button) return '';

    const ariaLabel = (button.getAttribute('aria-label') || '').trim();
    if (ariaLabel) return ariaLabel;

    const dataLetter = (button.getAttribute('data-letter') || '').trim();
    if (dataLetter) return dataLetter;

    return (button.innerText || button.textContent || '').replace(/\s+/g, ' ').trim();
}

function restartScanningForCurrentContext(delay = 300) {
    stopScanning();
    setTimeout(() => {
        if (!scanningPaused) {
            startScanning();
        }
    }, delay);
}

function resumeScanning() {
    if (isPausedFromScanLimit) {
        scanCycleCount = 0;
        isPausedFromScanLimit = false;
        startScanning();
    }
}

// --- Input Handling (Same as gridpage.js) ---
function setupKeyboardListener() {
    document.addEventListener('keydown', (event) => {
        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            pendingHighlightSpeechToken += 1;
            if (pendingHighlightSpeechTimer) {
                clearTimeout(pendingHighlightSpeechTimer);
                pendingHighlightSpeechTimer = null;
            }
            interruptScanningAnnouncementPlayback();
            if (isPausedFromScanLimit) {
                resumeScanning();
            } else if (currentScanAdvanceFn) {
                currentScanAdvanceFn();
            } else {
                startScanning();
            }
            return;
        }

        if (event.code === 'Space') {
            event.preventDefault();
            handleSpacebarPress();
        }
    });
}

function handleSpacebarPress() {
    if (currentlyScannedButton) {
        // Simulate click on the currently scanned button
        currentlyScannedButton.click();
    } else if (!scanningInterval && !isPausedFromScanLimit) {
        // Start scanning if not active
        startScanning();
    } else if (isPausedFromScanLimit) {
        // Resume scanning if paused
        resumeScanning();
    }
}

function setupGamepadListeners() {
    window.addEventListener('gamepadconnected', (e) => {
        console.log('Gamepad connected:', e.gamepad);
        gamepadIndex = e.gamepad.index;
        startGamepadPolling();
    });

    window.addEventListener('gamepaddisconnected', (e) => {
        console.log('Gamepad disconnected:', e.gamepad);
        if (gamepadIndex === e.gamepad.index) {
            gamepadIndex = null;
            stopGamepadPolling();
        }
    });
}

function startGamepadPolling() {
    if (gamepadPollInterval) return;
    
    const pollGamepad = () => {
        if (gamepadIndex === null) return;
        
        const gamepad = navigator.getGamepads()[gamepadIndex];
        if (gamepad) {
            const currentTime = Date.now();
            if (currentTime - lastGamepadInputTime > clickDebounceDelay) {
                if (gamepad.buttons[0] && gamepad.buttons[0].pressed) {
                    lastGamepadInputTime = currentTime;
                    handleSpacebarPress();
                }
            }
        }
        
        gamepadPollInterval = requestAnimationFrame(pollGamepad);
    };
    
    gamepadPollInterval = requestAnimationFrame(pollGamepad);
}

function stopGamepadPolling() {
    if (gamepadPollInterval) {
        cancelAnimationFrame(gamepadPollInterval);
        gamepadPollInterval = null;
    }
}

// --- Audio Functions (Similar to gridpage.js) ---
function base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

async function playAudioToDevice(audioDataBuffer, sampleRate, announcementType) {
    try {
        if (!window.AudioContext && !window.webkitAudioContext) {
            console.error('Web Audio API not supported');
            return;
        }

        const AudioContext = window.AudioContext || window.webkitAudioContext;
        const audioContext = new AudioContext();

        if (audioContext.state === 'suspended') {
            await audioContext.resume();
        }

        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        activeAnnouncementAudioContext = audioContext;
        activeAnnouncementAudioSource = source;
        source.start();

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
        console.error('Error playing audio:', error);
        activeAnnouncementAudioContext = null;
        activeAnnouncementAudioSource = null;
    }
}

function interruptScanningAnnouncementPlayback() {
    announcementQueue = [];
    isAnnouncingNow = false;

    if (window.speechSynthesis) {
        window.speechSynthesis.cancel();
    }

    if (activeAnnouncementAudioSource) {
        try {
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

async function processAnnouncementQueue() {
    if (isAnnouncingNow || announcementQueue.length === 0) {
        return;
    }

    isAnnouncingNow = true;

    while (announcementQueue.length > 0) {
        const announcement = announcementQueue.shift();
        const { textToAnnounce, announcementType, recordHistory } = announcement;

        // Show splash screen if enabled
        if (typeof showSplashScreen === 'function') {
            showSplashScreen(textToAnnounce);
        }

        try {
            const routingTarget = announcementType === "personal" ? "personal" : "system";
            
            const response = await authenticatedFetch('/play-audio', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    text: textToAnnounce,
                    routing_target: routingTarget
                })
            });

            if (response.ok) {
                const data = await response.json();
                if (data.audio_data) {
                    const audioBuffer = base64ToArrayBuffer(data.audio_data);
                    await playAudioToDevice(audioBuffer, data.sample_rate || 24000, announcementType);
                }
            } else {
                console.error('TTS request failed:', response.statusText);
            }

            if (recordHistory && announcementType === "personal") {
                // Clean [PAUSE] markers from text before recording to history
                const cleanText = textToAnnounce.replace(/\[PAUSE\]/g, ' ').trim();
                await recordChatHistory(cleanText, null);
            }

        } catch (error) {
            console.error('Error in announcement processing:', error);
        }
    }

    isAnnouncingNow = false;
}

async function announce(textToAnnounce, announcementType = "system", recordHistory = true) {
    if (!textToAnnounce || textToAnnounce.trim() === "") {
        return;
    }

    announcementQueue.push({
        textToAnnounce: textToAnnounce.trim(),
        announcementType,
        recordHistory
    });

    processAnnouncementQueue();
}

async function recordChatHistory(question, response) {
    try {
        await authenticatedFetch('/record_chat_history', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                question: question || "",
                response: response || ""
            })
        });
    } catch (error) {
        console.error('Failed to record chat history:', error);
    }
}

function tryResumeAudioContext() {
    if (audioContextResumeAttempted) return;
    audioContextResumeAttempted = true;
    
    if (window.AudioContext || window.webkitAudioContext) {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        const tempContext = new AudioContext();
        if (tempContext.state === 'suspended') {
            tempContext.resume().then(() => {
                tempContext.close();
                console.log('AudioContext resumed successfully');
            }).catch(err => {
                console.error('Failed to resume AudioContext:', err);
            });
        } else {
            tempContext.close();
        }
    }
}

// --- Loading Indicator ---
function showLoadingIndicator(show) {
    const indicator = document.getElementById('loading-indicator');
    if (show) {
        indicator.style.display = 'flex';
    } else {
        indicator.style.display = 'none';
    }
}

// --- PIN Modal Setup (Same as gridpage.js) ---
function setupPinModal() {
    // --- PIN Protection for Admin Toolbar ---
    const lockButton = document.getElementById('lock-icon');
    const adminIcons = document.getElementById('admin-icons');
    const pinModal = document.getElementById('pin-modal');
    const pinInput = document.getElementById('pin-input');
    const pinSubmitButton = document.getElementById('pin-submit');
    const pinCancelButton = document.getElementById('pin-cancel');
    const pinError = document.getElementById('pin-error');

    // Function to show PIN modal
    function showPinModal() {
        if (pinModal) {
            pinModal.classList.remove('hidden');
            if (pinInput) {
                pinInput.value = '';
                pinInput.focus();
            }
            if (pinError) {
                pinError.classList.add('hidden');
            }
        }
    }

    // Function to hide PIN modal
    function hidePinModal() {
        if (pinModal) {
            pinModal.classList.add('hidden');
        }
        if (pinInput) {
            pinInput.value = '';
        }
        if (pinError) {
            pinError.classList.add('hidden');
        }
    }

    // Function to validate PIN with backend
    async function validatePin(pin) {
        try {
            const response = await authenticatedFetch('/api/account/toolbar-pin', {
                method: 'GET'
            });
            
            if (response.ok) {
                const data = await response.json();
                return data.pin === pin;
            }
        } catch (error) {
            console.error('Error validating PIN:', error);
        }
        return false;
    }

    // Function to unlock admin toolbar
    function unlockToolbar() {
        if (adminIcons) {
            adminIcons.classList.remove('hidden');
        }
        if (lockButton) {
            lockButton.style.display = 'none';
        }
        hidePinModal();
    }

    // Function to lock admin toolbar
    function lockToolbar() {
        if (adminIcons) {
            adminIcons.classList.add('hidden');
        }
        if (lockButton) {
            lockButton.style.display = 'block';
        }
    }

    // Event listener for lock button
    if (lockButton) {
        lockButton.addEventListener('click', showPinModal);
    }

    // Event listener for lock toolbar button (locks the toolbar back)
    const lockToolbarButton = document.getElementById('lock-toolbar-button');
    if (lockToolbarButton) {
        lockToolbarButton.addEventListener('click', lockToolbar);
    }

    // Event listener for back to grid admin button
    const backToGridAdmin = document.getElementById('back-to-grid-admin');
    if (backToGridAdmin) {
        backToGridAdmin.addEventListener('click', () => {
            window.location.href = '/static/gridpage.html?page=home';
        });
    }

    // Event listener for switch user button
    const switchUserButton = document.getElementById('switch-user-button');
    if (switchUserButton) {
        switchUserButton.addEventListener('click', () => {
            console.log("Switching user profile. Clearing session and redirecting to auth page for profile selection.");
            // Only set flag to prevent auto-proceed with default user - keep user authenticated
            localStorage.setItem('bravoSkipDefaultUser', 'true');
            console.log('Set bravoSkipDefaultUser flag for profile selection');
            sessionStorage.clear();
            
            // Small delay to ensure localStorage is written before navigation
            setTimeout(() => {
                window.location.href = '/static/auth.html';
            }, 100);
        });
    }

    // Event listener for logout button
    const logoutButton = document.getElementById('logout-button');
    if (logoutButton) {
        logoutButton.addEventListener('click', () => {
            console.log("Logging out. Clearing session and redirecting to auth page for login.");
            // Set both flags to prevent automatic re-login and auto-profile selection
            localStorage.setItem('bravoIntentionalLogout', 'true');
            localStorage.setItem('bravoSkipDefaultUser', 'true');
            console.log('Set bravoIntentionalLogout and bravoSkipDefaultUser flags');
            sessionStorage.clear();
            
            // Small delay to ensure localStorage is written before navigation
            setTimeout(() => {
                window.location.href = '/static/auth.html';
            }, 100);
        });
    }

    // Event listener for PIN submit
    if (pinSubmitButton) {
        pinSubmitButton.addEventListener('click', async () => {
            const pin = pinInput.value;
            if (pin.length >= 3 && pin.length <= 10) {
                const isValid = await validatePin(pin);
                if (isValid) {
                    unlockToolbar();
                } else {
                    if (pinError) {
                        pinError.textContent = 'Invalid PIN. Please try again.';
                        pinError.classList.remove('hidden');
                    }
                    if (pinInput) {
                        pinInput.value = '';
                        pinInput.focus();
                    }
                }
            } else {
                if (pinError) {
                    pinError.textContent = 'PIN must be 3-10 characters.';
                    pinError.classList.remove('hidden');
                }
            }
        });
    }

    // Event listener for PIN cancel
    if (pinCancelButton) {
        pinCancelButton.addEventListener('click', hidePinModal);
    }

    // Event listener for Enter key in PIN input
    if (pinInput) {
        pinInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                if (pinSubmitButton) {
                    pinSubmitButton.click();
                }
            }
        });
    }

    // Event listener for Escape key to close modal
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && pinModal && !pinModal.classList.contains('hidden')) {
            hidePinModal();
        }
    });

    // Initialize toolbar state on page load
    lockToolbar();
}

// --- Smart Letter Filtering ---
function getValidLetters(currentWord) {
    console.log(`DEBUG: getValidLetters called with: "${currentWord}"`);
    
    if (!currentWord || currentWord.length === 0) {
        console.log(`DEBUG: Empty word, returning all letters`);
        return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }
    
    const lastChar = currentWord.slice(-1).toUpperCase();
    const lastTwoChars = currentWord.slice(-2).toUpperCase();
    const wordSoFar = currentWord.toUpperCase();
    
    console.log(`DEBUG: Last char: "${lastChar}", Last two chars: "${lastTwoChars}", Word so far: "${wordSoFar}"`);
    
    // Define likely letter combinations based on common English patterns
    const likelyAfter = {
        // Single letters - what commonly follows each letter
        'A': ['B', 'C', 'D', 'F', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W', 'Y'],
        'B': ['A', 'E', 'I', 'L', 'O', 'R', 'U', 'Y'], // BA, BE, BI, BL, BO, BR, BU, BY
        'C': ['A', 'E', 'H', 'I', 'L', 'O', 'R', 'U'], // CA, CE, CH, CI, CL, CO, CR, CU
        'D': ['A', 'E', 'I', 'O', 'R', 'U', 'Y'], // DA, DE, DI, DO, DR, DU, DY
        'E': ['A', 'D', 'L', 'M', 'N', 'R', 'S', 'T', 'V', 'W', 'X'], // EA, ED, EL, EM, EN, ER, ES, ET, EV, EW, EX
        'F': ['A', 'E', 'I', 'L', 'O', 'R', 'U'], // FA, FE, FI, FL, FO, FR, FU
        'G': ['A', 'E', 'I', 'L', 'O', 'R', 'U'], // GA, GE, GI, GL, GO, GR, GU
        'H': ['A', 'E', 'I', 'O', 'U', 'Y'], // HA, HE, HI, HO, HU, HY
        'I': ['C', 'D', 'F', 'G', 'L', 'M', 'N', 'R', 'S', 'T'], // IC, ID, IF, IG, IL, IM, IN, IR, IS, IT
        'J': ['A', 'E', 'O', 'U'], // JA, JE, JO, JU
        'K': ['A', 'E', 'I', 'N'], // KA, KE, KI, KN
        'L': ['A', 'E', 'I', 'O', 'U', 'Y'], // LA, LE, LI, LO, LU, LY
        'M': ['A', 'E', 'I', 'O', 'U', 'Y'], // MA, ME, MI, MO, MU, MY
        'N': ['A', 'C', 'D', 'E', 'G', 'I', 'K', 'O', 'S', 'T', 'U', 'Y', 'Z'], // NA, NC, ND, NE, NG, NI, NK, NO, NS, NT, NU, NY, NZ
        'O': ['B', 'C', 'D', 'F', 'G', 'K', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W'], // OB, OC, OD, OF, OG, OK, OL, OM, ON, OP, OR, OS, OT, OV, OW
        'P': ['A', 'E', 'I', 'L', 'O', 'R', 'U'], // PA, PE, PI, PL, PO, PR, PU
        'Q': ['U'], // QU (almost always)
        'R': ['A', 'E', 'I', 'O', 'U', 'Y'], // RA, RE, RI, RO, RU, RY
        'S': ['A', 'C', 'E', 'H', 'I', 'K', 'L', 'M', 'N', 'O', 'P', 'T', 'U', 'W'], // SA, SC, SE, SH, SI, SK, SL, SM, SN, SO, SP, ST, SU, SW
        'T': ['A', 'E', 'H', 'I', 'O', 'R', 'U', 'W'], // TA, TE, TH, TI, TO, TR, TU, TW
        'U': ['B', 'C', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T'], // UB, UC, UG, UL, UM, UN, UP, UR, US, UT
        'V': ['A', 'E', 'I', 'O'], // VA, VE, VI, VO
        'W': ['A', 'E', 'H', 'I', 'O'], // WA, WE, WH, WI, WO
        'X': ['A', 'E', 'I'], // XA, XE, XI (rare)
        'Y': ['A', 'E', 'O', 'U'], // YA, YE, YO, YU
        'Z': ['A', 'E', 'I', 'O'] // ZA, ZE, ZI, ZO
    };
    
    // Two-letter patterns - what commonly follows specific two-letter combinations
    const likelyAfterTwoLetters = {
        'TH': ['A', 'E', 'I', 'O', 'R'], // THE, THI, THO, THR
        'CH': ['A', 'E', 'I', 'O', 'U'], // CHA, CHE, CHI, CHO, CHU
        'SH': ['A', 'E', 'I', 'O', 'U'], // SHA, SHE, SHI, SHO, SHU
        'WH': ['A', 'E', 'I', 'O', 'U'], // WHA, WHE, WHI, WHO, WHU
        'PH': ['A', 'E', 'I', 'O', 'U'], // PHA, PHE, PHI, PHO, PHU
        'ST': ['A', 'E', 'I', 'O', 'R', 'U'], // STA, STE, STI, STO, STR, STU
        'SP': ['A', 'E', 'I', 'O', 'R'], // SPA, SPE, SPI, SPO, SPR
        'SC': ['A', 'E', 'I', 'O', 'R'], // SCA, SCE, SCI, SCO, SCR
        'FL': ['A', 'E', 'I', 'O', 'U'], // FLA, FLE, FLI, FLO, FLU
        'BL': ['A', 'E', 'I', 'O', 'U'], // BLA, BLE, BLI, BLO, BLU
        'CL': ['A', 'E', 'I', 'O', 'U'], // CLA, CLE, CLI, CLO, CLU
        'GL': ['A', 'E', 'I', 'O', 'U'], // GLA, GLE, GLI, GLO, GLU
        'PL': ['A', 'E', 'I', 'O', 'U'], // PLA, PLE, PLI, PLO, PLU
        'BR': ['A', 'E', 'I', 'O', 'U'], // BRA, BRE, BRI, BRO, BRU
        'CR': ['A', 'E', 'I', 'O', 'U'], // CRA, CRE, CRI, CRO, CRU
        'DR': ['A', 'E', 'I', 'O', 'U'], // DRA, DRE, DRI, DRO, DRU
        'FR': ['A', 'E', 'I', 'O', 'U'], // FRA, FRE, FRI, FRO, FRU
        'GR': ['A', 'E', 'I', 'O', 'U'], // GRA, GRE, GRI, GRO, GRU
        'PR': ['A', 'E', 'I', 'O', 'U'], // PRA, PRE, PRI, PRO, PRU
        'TR': ['A', 'E', 'I', 'O', 'U'], // TRA, TRE, TRI, TRO, TRU
        'ON': ['A', 'C', 'D', 'E', 'G', 'K', 'S', 'T', 'Y', 'Z'], // ONA, ONC, OND, ONE, ONG, ONK, ONS, ONT, ONY, ONZ - for words like "bronze", "bronco"
        'RO': ['A', 'B', 'C', 'D', 'E', 'G', 'L', 'M', 'N', 'O', 'P', 'S', 'T', 'U', 'W'], // Common RO combinations
        'RN': ['A', 'E', 'I', 'O'], // RNA, RNE, RNI, RNO - for words ending in -orn, -urn
    };
    
    let validLetters = [];
    
    // For longer words (4+ letters), be more permissive to allow complex combinations
    if (currentWord.length >= 4) {
        // For longer words, use a combination approach:
        // 1. Check for specific three/four letter patterns
        const lastThreeChars = currentWord.slice(-3).toUpperCase();
        const lastFourChars = currentWord.slice(-4).toUpperCase();
        
        // Specific patterns for common word endings/structures
        const longerPatterns = {
            'RON': ['C', 'G', 'T', 'Y', 'Z'], // bronco, strong, front, sony, bronze
            'ION': ['A', 'E', 'S'], // iona, ione, ions
            'ING': ['A', 'E', 'L', 'S', 'T'], // inga, inge, ingl, ings, ingt
            'ING': ['E', 'L', 'S'], // inge, ingl, ings
            'URN': ['A', 'E', 'I', 'S'], // urna, urne, urni, urns
            'ORN': ['E', 'I', 'S'], // orne, orni, orns
        };
        
        if (longerPatterns[lastThreeChars]) {
            validLetters = longerPatterns[lastThreeChars];
            console.log(`DEBUG: Using three-letter pattern "${lastThreeChars}": ${validLetters.length} letters`);
        }
        // If no specific pattern found for longer words, be more permissive
        else {
            // Use two-letter pattern if available, but expand it
            if (likelyAfterTwoLetters[lastTwoChars]) {
                validLetters = likelyAfterTwoLetters[lastTwoChars];
                // Add common consonants for longer words
                const additionalConsonants = ['C', 'D', 'G', 'K', 'S', 'T', 'W', 'Y', 'Z'];
                additionalConsonants.forEach(letter => {
                    if (!validLetters.includes(letter)) {
                        validLetters.push(letter);
                    }
                });
                console.log(`DEBUG: Using expanded two-letter pattern "${lastTwoChars}": ${validLetters.length} letters`);
            }
            // Fall back to single letter with expansion
            else if (likelyAfter[lastChar]) {
                validLetters = likelyAfter[lastChar];
                // For longer words, add more consonants that commonly appear
                const extraConsonants = ['C', 'D', 'G', 'K', 'S', 'T', 'W', 'Z'];
                extraConsonants.forEach(letter => {
                    if (!validLetters.includes(letter)) {
                        validLetters.push(letter);
                    }
                });
                console.log(`DEBUG: Using expanded single letter pattern "${lastChar}": ${validLetters.length} letters`);
            }
            // Ultimate fallback for long words - allow most common letters
            else {
                validLetters = 'ABCDEFGHIKLMNOPRSTUVWYZ'.split(''); // Exclude less common J, Q, X
                console.log(`DEBUG: Using permissive pattern for long word: ${validLetters.length} letters`);
            }
        }
    }
    // For shorter words (2-3 letters), use existing logic but be slightly more permissive
    else if (currentWord.length >= 2 && likelyAfterTwoLetters[lastTwoChars]) {
        validLetters = likelyAfterTwoLetters[lastTwoChars];
        console.log(`DEBUG: Using two-letter pattern "${lastTwoChars}": ${validLetters.length} letters`);
    }
    // Otherwise use single letter pattern
    else if (likelyAfter[lastChar]) {
        validLetters = likelyAfter[lastChar];
        console.log(`DEBUG: Using single letter pattern "${lastChar}": ${validLetters.length} letters`);
    }
    // Fallback to all letters if no pattern found
    else {
        validLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
        console.log(`DEBUG: No pattern found, allowing all letters: ${validLetters.length} letters`);
    }
    
    console.log(`DEBUG: Final valid letters for "${currentWord}":`, validLetters);
    return validLetters;
}

function updateLetterAvailability(currentWord) {
    const validLetters = getValidLetters(currentWord);
    const letterButtons = document.querySelectorAll('.letter-btn');
    
    console.log(`DEBUG: updateLetterAvailability called with word: "${currentWord}"`);
    console.log(`DEBUG: Valid letters calculated:`, validLetters);
    console.log(`DEBUG: Found ${letterButtons.length} letter buttons`);
    
    letterButtons.forEach(button => {
        const letter = button.textContent.toUpperCase();
        if (validLetters.includes(letter)) {
            button.classList.remove('disabled-letter');
            button.disabled = false;
            console.log(`DEBUG: Enabled letter: ${letter}`);
        } else {
            button.classList.add('disabled-letter');
            button.disabled = true;
            console.log(`DEBUG: Disabled letter: ${letter}`);
        }
    });
    
    console.log(`DEBUG: After update, disabled buttons:`, 
        document.querySelectorAll('.letter-btn.disabled-letter').length);
}

// --- Cleanup on page unload ---
window.addEventListener('beforeunload', () => {
    stopScanning();
    stopGamepadPolling();
});
