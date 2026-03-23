/**
 * Guess Who Game Logic
 * Mode A: Player 1 selects a person, Player 2 plays against AI with yes/no guesses
 */

// Game state
const gameState = {
    phase: 'category', // category, mode, person, clues, guesses, gameOver, ready, waitingForClue, makingGuess
    selectedCategory: null,
    selectedPerson: null,
    selectedMode: 'mode-a', // mode-a or mode-b
    cluesGiven: [],
    cluesAvailable: [],
    guessesRemaining: 3,
    guessesAttempted: [],
    isLoading: false,
    selectedCluesOptions: [],
    guessOptions: [],
    guessOptionsAll: [], // Mode B: stores all guesses from LLM (for Something Else)
    guessOptionsShown: [], // Mode B: tracks which guesses have been shown
    gameResult: null,
    currentGuess: null, // Mode B: stores the current guess being confirmed
    modeBPhase: null, // Mode B: 'ready', 'waitingForClue', 'listeningForClue', 'makingGuess', 'confirmingGuess'
    processingYesNo: false, // Flag to prevent yes/no handler from processing multiple times
    yesNoRecognitionId: null // Unique ID for current yes/no recognition session to prevent stale handlers
};

// Scanning state (minimal version to match gridpage behavior)
let scanningInterval = null;
let currentlyScannedButton = null;
let currentButtonIndex = -1;
let defaultDelay = 3500;
let ScanningOff = false;
let scanMode = 'auto';
let wakeWordInterjection = 'hey';
let wakeWordName = 'bravo';
let gridColumns = 6;

// Image matching state
let enablePictograms = true; // Can be toggled via settings
let useTapInterface = false; // Whether user is using tap interface

// Audio announce queue (minimal version of gridpage)
let announcementQueue = [];
let isAnnouncingNow = false;
let audioContextResumeAttempted = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

// Speech recognition (wake word + guess)
let recognition = null;
let isSettingUpRecognition = false;
let waitingForWakeWord = false;
let waitingForGuess = false;
let skipOnendRestart = false; // Prevents onend from auto-restarting during controlled transitions

// Initialize the game
async function initializeGame() {
    console.log('Initializing Guess Who game');
    
    // Check if user is authenticated
    const firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    const currentAacUserId = sessionStorage.getItem('currentAacUserId');
    
    if (!firebaseIdToken || !currentAacUserId) {
        console.warn('User not authenticated. Redirecting to auth.html');
        sessionStorage.clear();
        window.location.href = 'auth.html';
        return;
    }
    
    // Load scan and wake word settings
    await loadGuessWhoSettings();

    // Load categories
    await showCategoryScreen();
}

async function loadGuessWhoSettings() {
    try {
        const response = await authenticatedFetch('/api/settings', { method: 'GET' });
        if (!response.ok) {
            return;
        }
        const settings = await response.json();

        if (settings && typeof settings.scanDelay === 'number' && !isNaN(settings.scanDelay)) {
            defaultDelay = Math.max(100, parseInt(settings.scanDelay));
        }

        if (settings && typeof settings.wakeWordInterjection === 'string' && settings.wakeWordInterjection.trim()) {
            wakeWordInterjection = settings.wakeWordInterjection.trim().toLowerCase();
        }
        if (settings && typeof settings.wakeWordName === 'string' && settings.wakeWordName.trim()) {
            wakeWordName = settings.wakeWordName.trim().toLowerCase();
        }

        if (settings && typeof settings.gridColumns === 'number' && !isNaN(settings.gridColumns)) {
            gridColumns = Math.max(2, Math.min(12, parseInt(settings.gridColumns)));
        }

        ScanningOff = settings.ScanningOff === true;
        scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
        useTapInterface = settings.useTapInterface === true;
        
        // Force pictograms on for tap interface users
        if (useTapInterface) {
            enablePictograms = true;
        }
    } catch (error) {
        console.error('Error loading Guess Who settings:', error);
    }
}

function getWakeWordPhrase() {
    return `${wakeWordInterjection} ${wakeWordName}`.trim();
}

/**
 * Fetches symbol image from the AAC symbol database (adapted from gridpage)
 * @param {string} text - The button text to find a symbol for
 * @param {Array<string>} keywords - Optional semantic keywords for LLM-generated content  
 * @returns {Promise<string|null>} - Promise that resolves to image URL or null if none found
 */
async function getSymbolImageForText(text, keywords = null) {
    if (!text || text.trim() === '') {
        return null;
    }
    
    // Check if pictograms/images are enabled
    if (!enablePictograms) {
        console.log(`[IMAGE] Pictograms disabled for "${text}"`);
        return null;
    }
    
    // Check if this text is a sight word - if so, force text-only display (no images)
    if (window.isSightWord && window.isSightWord(text)) {
        console.log(`[IMAGE] Sight word detected: "${text}" - using text-only display`);
        return null;
    }
    
    // Persistent in-memory and sessionStorage cache to avoid repeated requests
    if (!window.symbolImageCache) {
        window.symbolImageCache = new Map();
        
        // Load cache from sessionStorage on first initialization
        try {
            const cachedData = sessionStorage.getItem('symbolImageCache');
            if (cachedData) {
                const parsed = JSON.parse(cachedData);
                Object.entries(parsed).forEach(([key, value]) => {
                    // Only restore if not expired (1 hour TTL)
                    if (value.timestamp > Date.now() - 3600000) {
                        window.symbolImageCache.set(key, value);
                    }
                });
                console.log(`[IMAGE] Restored ${window.symbolImageCache.size} cached symbol images from sessionStorage`);
            }
        } catch (e) {
            console.warn('[IMAGE] Failed to restore symbol image cache:', e);
        }
    }
    
    const cacheKey = `gw_${text.trim().toLowerCase()}`;
    if (window.symbolImageCache.has(cacheKey)) {
        const cached = window.symbolImageCache.get(cacheKey);
        if (cached.timestamp > Date.now() - 3600000) { // Cache for 1 hour
            console.log(`[IMAGE] Cache hit for "${text}": ${cached.imageUrl ? 'found' : 'not found'}`);
            return cached.imageUrl;
        }
    }
    
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
            console.warn(`[IMAGE] Timeout reaching symbol search for: "${text}"`);
            controller.abort();
        }, 10000); // 10 second timeout
        
        // Use unified button-search that searches Firestore collections with keywords support
        let symbolsUrl = `/api/symbols/button-search?q=${encodeURIComponent(text.trim())}&limit=1`;
        if (keywords && keywords.length > 0) {
            symbolsUrl += `&keywords=${encodeURIComponent(JSON.stringify(keywords))}`;
        }
        
        const response = await authenticatedFetch(symbolsUrl, {
            signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        if (!response.ok) {
            console.warn(`[IMAGE] Symbol search failed for "${text}": ${response.status}`);
            return null;
        }
        
        const data = await response.json();
        
        if (data && data.symbols && Array.isArray(data.symbols) && data.symbols.length > 0) {
            const symbolUrl = data.symbols[0].url;
            // Cache the result
            window.symbolImageCache.set(cacheKey, {
                imageUrl: symbolUrl,
                timestamp: Date.now()
            });
            // Persist to sessionStorage for cross-page persistence
            try {
                const cacheObj = Object.fromEntries(window.symbolImageCache);
                sessionStorage.setItem('symbolImageCache', JSON.stringify(cacheObj));
            } catch (e) {
                console.warn('[IMAGE] Failed to persist symbol cache:', e);
            }
            console.log(`[IMAGE] Found image for "${text}": ${symbolUrl}`);
            return symbolUrl;
        } else {
            // Cache null result to avoid repeated failed requests
            window.symbolImageCache.set(cacheKey, {
                imageUrl: null,
                timestamp: Date.now()
            });
            // Persist to sessionStorage
            try {
                const cacheObj = Object.fromEntries(window.symbolImageCache);
                sessionStorage.setItem('symbolImageCache', JSON.stringify(cacheObj));
            } catch (e) {
                console.warn('[IMAGE] Failed to persist symbol cache:', e);
            }
            console.log(`[IMAGE] No image found for "${text}"`);
            return null;
        }
    } catch (error) {
        if (error.name === 'AbortError') {
            console.warn(`[IMAGE] Request aborted for symbol "${text}" - likely due to timeout`);
        } else {
            console.error(`[IMAGE] Error fetching symbol for "${text}":`, error);
        }
        return null;
    }
}

// Show category selection
async function showCategoryScreen() {
    await loadCategories();
}

async function loadCategories() {
    console.log('loadCategories: Starting');
    gameState.phase = 'category';
    updatePageContent('category-screen');
    console.log('loadCategories: updatePageContent called');
    
    try {
        gameState.isLoading = true;
        const response = await authenticatedFetch('/api/guess-who/categories', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        
        const data = await response.json();
        const categories = data.all_categories;
        console.log('loadCategories: Received categories:', categories);
        
        // Create category buttons
        const buttons = categories.map(category => ({
            text: category,
            summary: category,
            onClick: () => selectCategory(category)
        }));
        
        // Add Home button first
        buttons.unshift(createHomeButton());
        
        console.log('loadCategories: About to display buttons');
        const container = document.querySelector('#category-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
        
    } catch (error) {
        console.error('Error loading categories:', error);
        gameState.isLoading = false;
        alert('Failed to load categories. Please try again.');
    }
}

function selectCategory(category) {
    gameState.selectedCategory = category;
    announceText(`The Category is ${category}.`, false).then(() => showModeScreen());
}

// Show mode selection (Player 1 vs Player 2 selection)
async function showModeScreen() {
    gameState.phase = 'mode';
    updatePageContent('mode-screen');
    
    const buttons = [
        createHomeButton(),
        {
            text: 'I pick',
            summary: 'I pick',
            onClick: () => startModeA()
        },
        {
            text: 'You pick',
            summary: 'You pick',
            onClick: () => startModeB()
        }
    ];
    
    const container = document.querySelector('#mode-screen .gridContainer');
    await displayGridButtons(buttons, container);
}

// Start Mode A: Player 1 selects a person
async function startModeA() {
    gameState.selectedMode = 'mode-a';
    gameState.phase = 'person';
    
    try {
        gameState.isLoading = true;
        await announceText('See if you can guess who I am thinking of. Give me a moment to select someone.', false);
        const response = await authenticatedFetch('/api/guess-who/generate-people', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                previous_people: []
            })
        });
        
        const data = await response.json();
        gameState.peopleOptions = data.people;
        
        // Update page content for person selection
        updatePageContent('person-screen');
        
        // Create person buttons
        const buttons = gameState.peopleOptions.map(person => ({
            text: person,
            summary: person,
            onClick: () => selectPerson(person)
        }));
        
        // Add "Something Else" button to refresh the list
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshPeopleOptions()
        });
        
        // Add Home button first
        buttons.unshift(createHomeButton());
        
        const container = document.querySelector('#person-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
        
    } catch (error) {
        console.error('Error generating people:', error);
        gameState.isLoading = false;
        alert('Failed to generate people. Please try again.');
    }
}

async function refreshPeopleOptions() {
    // Request fresh people (excluding currently shown options)
    try {
        gameState.isLoading = true;
        const response = await authenticatedFetch('/api/guess-who/generate-people', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                previous_people: gameState.peopleOptions || []
            })
        });
        
        const data = await response.json();
        gameState.peopleOptions = data.people;
        
        // Redisplay person selection with new options
        const buttons = gameState.peopleOptions.map(person => ({
            text: person,
            summary: person,
            onClick: () => selectPerson(person)
        }));
        
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshPeopleOptions()
        });
        
        buttons.unshift(createHomeButton());
        
        const container = document.querySelector('#person-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
    } catch (error) {
        console.error('Error refreshing people options:', error);
        gameState.isLoading = false;
    }
}

async function selectPerson(person) {
    gameState.selectedPerson = person;
    
    try {
        gameState.isLoading = true;
        await announceText("I've made my selection. Give me a moment to pick my clues.", false);
        const response = await authenticatedFetch('/api/guess-who/generate-clues', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                selected_person: person,
                previous_clues: []
            })
        });
        
        const data = await response.json();
        gameState.cluesAvailable = data.clues;
        gameState.cluesGiven = [];
        gameState.guessesRemaining = 3;
        gameState.guessesAttempted = [];
        
        // Show clue selection screen
        await showClueScreen();
        gameState.isLoading = false;
        
    } catch (error) {
        console.error('Error generating clues:', error);
        gameState.isLoading = false;
        alert('Failed to generate clues. Please try again.');
    }
}

// ===== MODE B FUNCTIONS =====
// Mode B: Player 1 (app) guesses, Player 2 picks the person

async function startModeB() {
    gameState.selectedMode = 'mode-b';
    gameState.modeBPhase = 'ready';
    gameState.cluesGiven = [];
    gameState.guessesAttempted = [];
    gameState.guessesRemaining = 3;
    gameState.guessOptionsAll = [];
    gameState.guessOptionsShown = [];
    
    // Announce instructions (don't await - let it play while we set up recognition)
    announceText(`Let's see if I can guess a ${gameState.selectedCategory} that you pick! Say "ready" when you have thought of a ${gameState.selectedCategory}.`, false);
    
    // Start listening for "ready" immediately
    listenForReady();
}

function listenForReady() {
    gameState.modeBPhase = 'ready';
    waitingForWakeWord = false;
    waitingForGuess = false;
    
    // Stop any existing recognition first
    stopWakeWordRecognition();
    
    // Set up fresh recognition for ready detection
    showListeningIndicator('Listening for: "ready"');
    setupWakeWordRecognition();
}

async function handleReadyHeard() {
    gameState.modeBPhase = 'waitingForClue';
    hideListeningIndicator();
    
    // Prevent onend handler from auto-restarting during this transition
    skipOnendRestart = true;
    
    // Stop old recognition
    if (recognition) {
        try { recognition.stop(); } catch (e) {}
        recognition = null;
    }
    
    // Announce next instruction (don't await - let it play in background)
    announceText(`Great! Next you need to give me a clue. Say ${getWakeWordPhrase()} when you have thought of a clue.`, false);
    
    // Start listening for wake word immediately (during announcement)
    waitingForWakeWord = true;
    isSettingUpRecognition = false;
    showListeningIndicator(`Listening for: "${getWakeWordPhrase()}"`);
    setupWakeWordRecognition();
    
    // Re-enable onend auto-restart after a short delay
    setTimeout(() => { skipOnendRestart = false; }, 100);
}

async function handleWakeWordForClue() {
    gameState.modeBPhase = 'listeningForClue';
    waitingForWakeWord = false;
    hideListeningIndicator();
    stopWakeWordRecognition();
    
    // Announce and start listening immediately (during announcement)
    announceText('Listening for your clue now.', false);
    showListeningIndicator('Listening for: your clue');
    startClueCapture();
}

function startClueCapture() {
    waitingForGuess = true; // Reuse the guess capture flag for clue capture
    
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error('Speech Recognition API not supported.');
        return;
    }

    let clueRecognitionInstance = new SpeechRecognitionAPI();
    clueRecognitionInstance.lang = 'en-US';
    clueRecognitionInstance.continuous = false;
    clueRecognitionInstance.interimResults = true;
    clueRecognitionInstance.maxAlternatives = 1;

    let finalTranscript = '';
    let hasProcessedResult = false;

    clueRecognitionInstance.onresult = async (event) => {
        if (hasProcessedResult) return;
        let interimTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
            const transcriptPart = event.results[i][0].transcript;
            if (event.results[i].isFinal) { finalTranscript += transcriptPart; } else { interimTranscript += transcriptPart; }
        }

        const isFinishedUtterance = event.results[event.results.length - 1].isFinal;
        if (isFinishedUtterance && finalTranscript.trim()) {
            console.log('[MODE B CLUE] Heard clue:', finalTranscript.trim());
            hasProcessedResult = true;
            waitingForGuess = false;
            try { clueRecognitionInstance.stop(); } catch (e) {}
            await handleClueHeard(finalTranscript.trim());
        }
    };

    clueRecognitionInstance.onerror = () => {
        console.error('[MODE B CLUE] Recognition error');
        waitingForGuess = false;
        try { clueRecognitionInstance.stop(); } catch (e) {}
    };

    clueRecognitionInstance.onend = () => {
        waitingForGuess = false;
    };

    try { 
        clueRecognitionInstance.start();
        console.log('[MODE B CLUE] Started listening for clue');
    } catch (e) {
        console.error('[MODE B CLUE] Error starting recognition:', e);
    }
}

async function handleClueHeard(clueText) {
    waitingForGuess = false;
    hideListeningIndicator();
    stopWakeWordRecognition();
    
    // Add clue to game state
    gameState.cluesGiven.push(clueText);
    
    // Announce the clue back
    await announceText(`Ok. ${clueText}. Give me a moment to make a guess.`, false);
    
    // Generate and show guesses
    await generateAndShowGuesses();
}

async function generateAndShowGuesses() {
    gameState.modeBPhase = 'makingGuess';
    gameState.isLoading = true;
    
    try {
        const response = await authenticatedFetch('/api/guess-who/generate-guesses', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                clues: gameState.cluesGiven,
                previous_guesses: gameState.guessesAttempted
            })
        });
        
        const data = await response.json();
        gameState.guessOptionsAll = data.guesses || [];
        gameState.guessOptionsShown = [];
        
        // Show first set of guesses
        await displayModeBGuessOptions();
        gameState.isLoading = false;
        
    } catch (error) {
        console.error('Error generating guesses:', error);
        gameState.isLoading = false;
        alert('Failed to generate guesses. Please try again.');
    }
}

async function displayModeBGuessOptions() {
    // Determine how many options to show (from settings)
    const settings = await fetch('/api/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(r => r.json()).catch(() => ({ LLMOptions: 5 }));
    
    const llmOptions = settings.LLMOptions || 5;
    
    // Get next batch of guesses that haven't been shown
    const availableGuesses = gameState.guessOptionsAll.filter(g => !gameState.guessOptionsShown.includes(g));
    const guessesToShow = availableGuesses.slice(0, llmOptions);
    
    // Mark these as shown
    gameState.guessOptionsShown.push(...guessesToShow);
    
    // Create buttons
    const buttons = guessesToShow.map(guess => ({
        text: guess,
        summary: guess,
        onClick: () => selectGuess(guess)
    }));
    
    // Add Something Else button if there are more guesses available
    if (availableGuesses.length > llmOptions) {
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshModeBGuesses()
        });
    }
    
    // Add Home button
    buttons.unshift(createHomeButton());
    
    // Update page to show guesses
    updatePageContent('guess-screen');
    document.getElementById('guess-display').textContent = `Make your guess:`;
    document.getElementById('guesses-left-count-2').textContent = gameState.guessesRemaining;
    
    const container = document.querySelector('#guess-screen .gridContainer');
    await displayGridButtons(buttons, container);
    
    // Start listening for guess selection via voice immediately
    listenForModeBGuess();
}

async function refreshModeBGuesses() {
    // Just show the next batch from guessOptionsAll
    await displayModeBGuessOptions();
}

async function selectGuess(guess) {
    gameState.currentGuess = guess;
    gameState.modeBPhase = 'confirmingGuess';
    hideListeningIndicator();
    stopAuditoryScanning();
    
    // Announce the guess and ask for confirmation (don't await - start listening during announcement)
    announceText(`Is it ${guess}? Please say 'yes' or 'no'.`, false);
    
    // Start listening for yes/no immediately
    showListeningIndicator('Listening for: "yes" or "no"');
    listenForYesNo();
}

function listenForYesNo() {
    // Use continuous recognition for yes/no (like 20 Questions)
    gameState.processingYesNo = false; // Reset the flag for a new yes/no session
    if (!recognition) {
        setupYesNoRecognition();
    }
    
    try {
        if (recognition && !recognition.started) {
            recognition.start();
        }
    } catch (e) {
        console.log('[MODE B] Recognition already started or error:', e);
    }
}

function setupYesNoRecognition() {
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error('Speech Recognition API not supported.');
        return;
    }

    // Create a unique ID for this recognition session
    gameState.yesNoRecognitionId = Date.now();
    const sessionId = gameState.yesNoRecognitionId;

    recognition = new SpeechRecognitionAPI();
    recognition.continuous = false;
    recognition.interimResults = false;
    recognition.lang = 'en-US';

    recognition.onresult = async (event) => {
        // Exit early if this is a stale result from a previous recognition session
        if (sessionId !== gameState.yesNoRecognitionId) return;
        // Exit early if we're already processing a yes/no response
        if (gameState.processingYesNo) return;
        
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('[MODE B YES/NO] Heard:', transcript);
        
        if (gameState.modeBPhase === 'confirmingGuess') {
            gameState.processingYesNo = true; // Prevent processing any future results for this turn
            if (transcript.includes('yes')) {
                hideListeningIndicator();
                await handleGuessConfirmation(true);
            } else if (transcript.includes('no')) {
                hideListeningIndicator();
                await handleGuessConfirmation(false);
            } else {
                // Not yes or no, ask again
                gameState.processingYesNo = false; // Reset flag to allow retry
                await announceText("Please say 'yes' or 'no'.", false);
                setTimeout(() => {
                    showListeningIndicator('Listening for: "yes" or "no"');
                    listenForYesNo();
                }, 100);
            }
        }
    };

    recognition.onerror = function (event) {
        console.error('[MODE B YES/NO] Recognition error:', event.error);
        // Retry after error
        setTimeout(() => {
            if (gameState.modeBPhase === 'confirmingGuess') {
                listenForYesNo();
            }
        }, 1500);
    };

    recognition.onend = function () {
        // Auto-restart if still in confirmation phase
        if (gameState.modeBPhase === 'confirmingGuess') {
            setTimeout(() => {
                listenForYesNo();
            }, 1000);
        }
    };
}

async function handleGuessConfirmation(isCorrect) {
    // Immediately invalidate any stale yes/no results
    gameState.yesNoRecognitionId = null;
    
    // Reset recognition state flags
    waitingForWakeWord = false;
    waitingForGuess = false;
    isSettingUpRecognition = false;
    
    // Stop any existing recognition immediately
    stopWakeWordRecognition();
    if (recognition) {
        try {
            recognition.stop();
        } catch (e) {}
        recognition = null;
    }
    
    if (isCorrect) {
        // Player 1 (app) wins!
        gameState.gameResult = {
            won: true,
            guess: gameState.currentGuess,
            cluesUsed: gameState.cluesGiven.length,
            guessesUsed: 4 - gameState.guessesRemaining,
            guessesTotal: 3
        };
        
        await announceText('I win! Great game!', false);
        endGame();
    } else {
        // Incorrect guess
        gameState.guessesAttempted.push(gameState.currentGuess);
        gameState.guessesRemaining--;
        
        if (gameState.guessesRemaining <= 0) {
            // Player 2 wins! App ran out of guesses
            gameState.gameResult = {
                won: false,
                actualPerson: 'Unknown', // We don't know who Player 2 picked
                cluesGiven: gameState.cluesGiven,
                guessesUsed: 3,
                guessesTotal: 3
            };
            
            await announceText('Darn! You win! Great game!', false);
            endGame();
        } else {
            // More guesses remaining, ask for another clue (don't await - start listening during announcement)
            announceText(`That's not it. Say ${getWakeWordPhrase()} when you have another clue.`, false);
            
            // Reset to waiting for clue phase with proper recognition cleanup
            gameState.modeBPhase = 'waitingForClue';
            waitingForWakeWord = true;
            
            // Start listening immediately
            try {
                showListeningIndicator(`Listening for: "${getWakeWordPhrase()}"`);
                setupWakeWordRecognition();
            } catch (e) {
                console.error('[MODE B] Error restarting recognition:', e);
            }
        }
    }
}

// ===== END MODE B FUNCTIONS =====

async function showClueScreen() {
    gameState.phase = 'clues';
    updatePageContent('clue-screen');
    
    // Update target name and stats
    document.getElementById('clue-target-name').textContent = gameState.selectedPerson;
    document.getElementById('clues-given-count').textContent = gameState.cluesGiven.length;
    document.getElementById('guesses-left-count').textContent = gameState.guessesRemaining;
    
    if (gameState.cluesGiven.length >= 3) {
        if (gameState.guessesRemaining <= 0) {
            endGame();
        }
        return;
    } else {
        // Filter out previously selected clues by their full text value
        const selectedClueTexts = gameState.cluesGiven;
        const availableClues = gameState.cluesAvailable.filter(clueObj => {
            // Extract the text from clue object or string
            const clueText = (typeof clueObj === 'string') ? clueObj : (clueObj.text || clueObj.full || '');
            // Check if this clue has been selected
            return !selectedClueTexts.includes(clueText);
        });
        
        console.log('[CLUE SCREEN] Available clues:', availableClues.length, 'from', gameState.cluesAvailable.length);
        
        if (availableClues.length === 0) {
            // Need more clues
            try {
                const response = await authenticatedFetch('/api/guess-who/generate-clues', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        category: gameState.selectedCategory,
                        selected_person: gameState.selectedPerson,
                        previous_clues: gameState.cluesGiven
                    })
                });
                
                const data = await response.json();
                gameState.cluesAvailable = data.clues;
            } catch (error) {
                console.error('Error generating more clues:', error);
            }
        }
        
        // Create buttons from available clues
        const buttons = availableClues.map(clueObj => {
            // Handle both string and object clue formats
            let clueText = '';
            let clueSummary = '';
            
            if (typeof clueObj === 'string') {
                // Old format: just a string
                clueText = clueObj;
                clueSummary = clueObj.length > 50 ? clueObj.substring(0, 47) + '...' : clueObj;
            } else if (typeof clueObj === 'object' && clueObj !== null) {
                // New format: object with text and summary
                clueText = String(clueObj.text || clueObj.full || '').trim();
                clueSummary = String(clueObj.summary || clueText || '').trim();
                
                // If still empty, use the entire object as fallback
                if (!clueText) {
                    clueText = JSON.stringify(clueObj);
                    clueSummary = clueText;
                }
            } else {
                clueText = String(clueObj || '').trim();
                clueSummary = clueText;
            }
            
            console.log('[GUESS_WHO CLUE]', { type: typeof clueObj, clueText, clueSummary });
            
            return {
                text: clueText,
                summary: clueSummary,
                onClick: () => selectClue(clueText)
            };
        });
        
        // Add "Something Else" button before Home button
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshClueOptions()
        });
        
        buttons.unshift(createHomeButton());
        const container = document.querySelector('#clue-screen .gridContainer');
        await displayGridButtons(buttons, container);
    }
}

async function refreshClueOptions() {
    // Request fresh clues (telling LLM to exclude already selected and shown clues)
    try {
        const allShownClues = gameState.cluesGiven.concat(
            gameState.cluesAvailable.map(c => c.text || c)
        );
        
        const response = await authenticatedFetch('/api/guess-who/generate-clues', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                selected_person: gameState.selectedPerson,
                previous_clues: allShownClues
            })
        });
        
        const data = await response.json();
        gameState.cluesAvailable = data.clues;
        await showClueScreen();
    } catch (error) {
        console.error('Error refreshing clue options:', error);
    }
}

function selectClue(clueText) {
    gameState.cluesGiven.push(clueText);

    const clueIndex = gameState.cluesGiven.length;
    stopAuditoryScanning();
    announceText(`Clue ${clueIndex}: ${clueText}`, false)
        .then(() => announceText(`Say ${getWakeWordPhrase()} when you are ready to guess.`, false))
        .then(() => startWakeWordListener());
}

async function startWakeWordListener() {
    waitingForWakeWord = true;
    stopAuditoryScanning();
    setupWakeWordRecognition();
}

function setupWakeWordRecognition() {
    // Only set up if not already in progress and we don't have an active recognition
    // Use a small delay to ensure any pending stop() calls complete
    if (isSettingUpRecognition) {
        console.log('[RECOGNITION SETUP] Already setting up, skipping');
        return;
    }
    
    // If recognition device exists, try to stop it first
    if (recognition) {
        console.log('[RECOGNITION SETUP] Stopping existing recognition');
        try {
            recognition.stop();
        } catch (e) {}
        recognition = null;
    }
    
    isSettingUpRecognition = true;

    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error('Speech Recognition API not supported.');
        isSettingUpRecognition = false;
        return;
    }

    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;

    recognition.onerror = function () {
        if (!waitingForWakeWord) {
            return;
        }
        recognition = null;
        isSettingUpRecognition = false;
    };

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        const interjectionToUse = wakeWordInterjection || 'hey';
        const nameToUse = wakeWordName || 'bravo';
        const phraseWithSpace = `${interjectionToUse} ${nameToUse}`;
        const phraseWithComma = `${interjectionToUse}, ${nameToUse}`;
        const phraseWithCommaNoSpace = `${interjectionToUse},${nameToUse}`;
        
        console.log('[RECOGNITION] Heard:', transcript, 'Mode:', gameState.selectedMode, 'Phase:', gameState.modeBPhase);

        // Mode B: Handle "ready" detection
        if (gameState.selectedMode === 'mode-b' && gameState.modeBPhase === 'ready') {
            if (transcript.includes('ready')) {
                // Set flag to false BEFORE stopping so onend handler doesn't restart
                waitingForWakeWord = false;
                if (recognition) {
                    try { recognition.stop(); } catch (e) {}
                    recognition = null;
                }
                isSettingUpRecognition = false;
                await handleReadyHeard();
                return;
            }
        }

        // Wake word detection for Mode A (guess) and Mode B (clue)
        if (transcript.includes(phraseWithSpace) || transcript.includes(phraseWithComma) || transcript.includes(phraseWithCommaNoSpace)) {
            waitingForWakeWord = false;
            if (recognition) {
                try { recognition.stop(); } catch (e) {}
                recognition = null;
            }
            isSettingUpRecognition = false;
            
            // Mode B: Handle wake word for clue
            if (gameState.selectedMode === 'mode-b' && gameState.modeBPhase === 'waitingForClue') {
                await handleWakeWordForClue();
            } else {
                // Mode A: Handle wake word for guess
                await announceText('Listening for your guess', false);
                startGuessRecognition();
            }
        }
    };

    recognition.onend = () => {
        // Don't auto-restart if we're in a controlled transition
        if (skipOnendRestart) {
            recognition = null;
            isSettingUpRecognition = false;
            console.log('[RECOGNITION ONEND] Skipping auto-restart (controlled transition)');
            return;
        }
        
        // Only auto-restart if we're still waiting and not already setting up new recognition
        if (waitingForWakeWord && !isSettingUpRecognition) {
            recognition = null;
            isSettingUpRecognition = false;
            setTimeout(setupWakeWordRecognition, 500);
        } else {
            recognition = null;
            isSettingUpRecognition = false;
        }
    };

    try {
        recognition.start();
        isSettingUpRecognition = false;
    } catch (e) {
        recognition = null;
        isSettingUpRecognition = false;
    }
}

function startGuessRecognition() {
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error('Speech Recognition API not supported.');
        return;
    }

    let guessRecognitionInstance = new SpeechRecognitionAPI();
    guessRecognitionInstance.lang = 'en-US';
    guessRecognitionInstance.continuous = false;
    guessRecognitionInstance.interimResults = true;
    guessRecognitionInstance.maxAlternatives = 1;

    let finalTranscript = '';
    let hasProcessedResult = false;
    waitingForGuess = true;

    guessRecognitionInstance.onresult = async (event) => {
        if (hasProcessedResult) return;
        let interimTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
            const transcriptPart = event.results[i][0].transcript;
            if (event.results[i].isFinal) { finalTranscript += transcriptPart; } else { interimTranscript += transcriptPart; }
        }

        const isFinishedUtterance = event.results[event.results.length - 1].isFinal;
        if (isFinishedUtterance && finalTranscript.trim()) {
            hasProcessedResult = true;
            waitingForGuess = false;
            try { guessRecognitionInstance.stop(); } catch (e) {}
            
            // Mode B: Handle clue capture
            if (gameState.selectedMode === 'mode-b' && gameState.modeBPhase === 'listeningForClue') {
                await handleClueHeard(finalTranscript.trim());
            } else {
                // Mode A: Handle guess capture
                await handleGuessHeard(finalTranscript.trim());
            }
        }
    };

    guessRecognitionInstance.onerror = () => {
        waitingForGuess = false;
        try { guessRecognitionInstance.stop(); } catch (e) {}
    };

    guessRecognitionInstance.onend = () => {
        waitingForGuess = false;
    };

    try { guessRecognitionInstance.start(); } catch (e) {}
}

function stopWakeWordRecognition() {
    waitingForWakeWord = false;
    waitingForGuess = false;
    
    if (recognition) {
        try {
            recognition.stop();
        } catch (e) {
            console.log('[STOP RECOGNITION] Error or already stopped:', e);
        }
        recognition = null;
    }
    isSettingUpRecognition = false;
}

function listenForModeBGuess() {
    if (gameState.selectedMode !== 'mode-b') return;
    
    // Set up voice recognition for guess selection by voice
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) return;

    let guessRecognition = new SpeechRecognitionAPI();
    guessRecognition.lang = 'en-US';
    guessRecognition.continuous = true;
    guessRecognition.interimResults = true;
    guessRecognition.maxAlternatives = 1;

    guessRecognition.onresult = (event) => {
        let interimTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
            const transcriptPart = event.results[i][0].transcript.toLowerCase();
            if (event.results[i].isFinal) {
                // Check if transcript matches any of the visible guesses
                const buttons = document.querySelectorAll('#guess-screen .gridContainer button');
                for (let btn of buttons) {
                    const buttonText = btn.textContent.toLowerCase().trim();
                    // Simple word matching
                    const transcriptWords = transcriptPart.split(/\s+/);
                    const buttonWords = buttonText.split(/\s+/);
                    
                    // Check if most words match
                    let matchCount = 0;
                    for (let word of buttonWords) {
                        if (word.length > 2 && transcriptPart.includes(word)) {
                            matchCount++;
                        }
                    }
                    
                    if (matchCount > 0 && matchCount >= buttonWords.length / 2) {
                        console.log('[MODE B GUESS] Selected guess by voice:', buttonText);
                        hideListeningIndicator();
                        try { guessRecognition.stop(); } catch (e) {}
                        // Trigger the button click
                        btn.click();
                        return;
                    }
                }
            } else {
                interimTranscript += transcriptPart;
            }
        }
    };

    guessRecognition.onerror = (event) => {
        if (event.error !== 'no-speech') {
            console.error('[MODE B GUESS] Recognition error:', event.error);
        }
    };

    guessRecognition.onend = () => {
        // Recognition ended, optionally restart if still in guess-screen
        if (gameState.phase === 'guesses' && gameState.selectedMode === 'mode-b') {
            setTimeout(() => {
                listenForModeBGuess();
            }, 500);
        }
    };

    try {
        guessRecognition.start();
        console.log('[MODE B GUESS] Started listening for guess selection');
    } catch (e) {
        console.error('[MODE B GUESS] Error starting recognition:', e);
    }
}

function showListeningIndicator(message) {
    const indicator = document.getElementById('listening-status');
    if (indicator) {
        indicator.textContent = message;
        indicator.classList.add('active');
    }
}

function hideListeningIndicator() {
    const indicator = document.getElementById('listening-status');
    if (indicator) {
        indicator.classList.remove('active');
    }
}

async function handleGuessHeard(guessText) {
    gameState.guessesAttempted.push(guessText);
    gameState.guessesRemaining -= 1;

    // Announce that the guess was heard
    await announceText(`Ok. I hear your guess ${guessText}. Give me a moment to respond.`, false);

    await showGuessResponseScreen(guessText);
}

async function showGuessResponseScreen(guessText) {
    gameState.phase = 'guesses';
    updatePageContent('guess-screen');
    document.getElementById('guess-display').textContent = `Player 2 guessed: ${guessText}`;
    document.getElementById('guesses-left-count-2').textContent = Math.max(0, gameState.guessesRemaining);

    const responseOptions = await generateGuessResponseOptions(guessText);
    const buttons = responseOptions.map(option => ({
        text: option.text,
        summary: option.summary,
        onClick: () => handleGuessResponse(option)
    }));

    buttons.unshift(createHomeButton());
    const container = document.querySelector('#guess-screen .gridContainer');
    await displayGridButtons(buttons, container);
}

async function generateGuessResponseOptions(guessText) {
    // Determine if the guess is correct by checking if it contains the selected person's name
    const selectedPersonLower = gameState.selectedPerson.toLowerCase();
    const guessLower = guessText.toLowerCase();
    const isGuessCorrect = guessLower.includes(selectedPersonLower) || selectedPersonLower.includes(guessLower.split(' ')[0]);
    
    let prompt;
    if (isGuessCorrect) {
        // If guess is correct, generate only positive confirmation responses
        prompt = `You are helping a person using an AAC device in a Guess Who game. Player 2 just guessed correctly!\n\nSelected person: "${gameState.selectedPerson}"\nCategory: "${gameState.selectedCategory}"\nPlayer 2 guess: "${guessText}"\n\nThe guess IS CORRECT - Player 2 guessed the right person!\n\nGenerate 6 short positive confirmation responses that affirm the correct guess. All responses must indicate the guess was correct.\n\nReturn ONLY a JSON array of objects with:\n- text: full response (must confirm the guess is CORRECT)\n- summary: 3-5 word label\n- is_correct: true (ALWAYS true for all 6 options)\n\nExample:\n[\n  {"text": "Yes! That's right!", "summary": "Yes correct", "is_correct": true},\n  {"text": "Correct! You got it!", "summary": "Correct", "is_correct": true}\n]\n`;
    } else {
        // If guess is incorrect, generate only negative response options
        prompt = `You are helping a person using an AAC device in a Guess Who game. Player 2 just guessed incorrectly.\n\nSelected person: "${gameState.selectedPerson}"\nCategory: "${gameState.selectedCategory}"\nClues given: ${gameState.cluesGiven.map((clue, idx) => `Clue ${idx + 1}: ${clue}`).join(' | ')}\nPlayer 2 guess: "${guessText}"\n\nThe guess is INCORRECT - Player 2 guessed someone else!\n\nGenerate 6 short negative rejection responses that tell Player 2 their guess is wrong. NEVER confirm the guess is correct. Do NOT reveal who the actual person is. All responses must indicate the guess was WRONG.\n\nReturn ONLY a JSON array of objects with:\n- text: full response (must say the guess is WRONG, no mentions of who it actually is)\n- summary: 3-5 word label\n- is_correct: false (ALWAYS false for all 6 options)\n\nExample:\n[\n  {"text": "No, that's not it.", "summary": "No, wrong", "is_correct": false},\n  {"text": "Not quite. Try again.", "summary": "Not quite", "is_correct": false}\n]\n`;
    }

    try {
        const response = await authenticatedFetch('/llm', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt })
        });

        if (!response.ok) {
            throw new Error(`LLM error: ${response.status}`);
        }

        const data = await response.json();
        if (!Array.isArray(data)) {
            return [];
        }

        return data.map(item => {
            const textValue = item.text || item.option || item.response || item.answer || '';
            const summaryValue = item.summary || textValue;
            return {
                text: String(textValue),
                summary: String(summaryValue).split(' ').slice(0, 5).join(' '),
                // Enforce correctness: if guess is correct, all should be true; if wrong, all should be false
                is_correct: isGuessCorrect
            };
        }).filter(item => item.text);
    } catch (error) {
        console.error('Error generating response options:', error);
        return [];
    }
}

async function handleGuessResponse(option) {
    await announceText(option.text, true);

    if (option.is_correct) {
        gameState.gameResult = {
            won: true,
            guess: option.text,
            guessesUsed: 3 - Math.max(0, gameState.guessesRemaining),
            guessesTotal: 3
        };
        endGame();
        return;
    }

    if (gameState.guessesRemaining <= 0) {
        gameState.gameResult = {
            won: false,
            actualPerson: gameState.selectedPerson,
            guessesAttempted: gameState.guessesAttempted,
            guessesTotal: 3
        };
        endGame();
        return;
    }

    showClueScreen();
}

function endGame() {
    console.log('[GUESS_WHO END GAME] Ending game, stopping all recognition');
    gameState.phase = 'gameOver';
    
    // Stop all recognition immediately
    hideListeningIndicator();
    stopWakeWordRecognition();
    gameState.yesNoRecognitionId = null;
    gameState.modeBPhase = null;
    if (recognition) {
        try {
            recognition.stop();
        } catch (e) {}
        recognition = null;
    }
    isSettingUpRecognition = false;
    
    updatePageContent('game-over-screen');
    
    if (gameState.selectedMode === 'mode-a') {
        // Mode A: Player 2 is guessing
        if (gameState.gameResult.won) {
            document.getElementById('game-over-message').textContent = 
                `🎉 Correct! Player 2 guessed "${gameState.gameResult.guess}"`;
            document.getElementById('game-over-details').textContent = 
                `They used ${gameState.gameResult.guessesUsed} out of ${gameState.gameResult.guessesTotal} guesses.`;
        } else {
            document.getElementById('game-over-message').textContent = 
                `Game Over! Player 2 didn't guess it.`;
            document.getElementById('game-over-details').textContent = 
                `The person was: ${gameState.gameResult.actualPerson}`;
        }
    } else {
        // Mode B: Player 1 (app) is guessing
        if (gameState.gameResult.won) {
            document.getElementById('game-over-message').textContent = 
                `🎉 I win! I guessed "${gameState.gameResult.guess}"`;
            document.getElementById('game-over-details').textContent = 
                `I used ${gameState.gameResult.guessesUsed} out of ${gameState.gameResult.guessesTotal} guesses and ${gameState.gameResult.cluesUsed} clues.`;
        } else {
            document.getElementById('game-over-message').textContent = 
                `You win! I couldn't guess it.`;
            document.getElementById('game-over-details').textContent = 
                `I used all ${gameState.gameResult.guessesTotal} guesses. The clues were: ${gameState.gameResult.cluesGiven.join(', ')}`;
        }
    }
    
    const buttons = [
        {
            text: 'Play Again',
            summary: 'Play Again',
            onClick: () => initializeGame()
        },
        {
            text: 'Home',
            summary: 'Home',
            onClick: () => window.location.href = useTapInterface ? '/static/tap_interface.html' : '/gridpage.html'
        }
    ];
    
    const container = document.querySelector('#game-over-screen .gridContainer');
    // Note: endGame doesn't await displayGridButtons since it's called from a synchronous context
    // The buttons will display asynchronously
    displayGridButtons(buttons, container).catch(error => {
        console.error('[GAME OVER] Error displaying buttons:', error);
    });
}

// Helper functions
function createHomeButton() {
    return {
        text: 'Home',
        summary: 'Home',
        onClick: () => {
            window.location.href = useTapInterface ? '/static/tap_interface.html' : '/gridpage.html';
        }
    };
}

function updatePageContent(screenId, customSubtitle = null) {
    stopAuditoryScanning();
    // Hide all screens
    document.querySelectorAll('[id$="-screen"]').forEach(screen => {
        screen.classList.remove('visible-screen');
        screen.classList.add('hidden-screen');
    });
    
    // Show selected screen
    document.getElementById(screenId).classList.remove('hidden-screen');
    document.getElementById(screenId).classList.add('visible-screen');
    
    // Update banner if needed
    if (customSubtitle) {
        const subtitleEl = document.querySelector('.page-subtitle');
        if (subtitleEl) {
            subtitleEl.textContent = customSubtitle;
        }
    }
}

async function displayGridButtons(buttons, containerElement = null) {
    stopAuditoryScanning();
    // Find the gridContainer - use provided element or search for it
    let container = containerElement;
    
    if (!container) {
        const visibleScreen = document.querySelector('.visible-screen');
        container = visibleScreen ? visibleScreen.querySelector('.gridContainer') : document.querySelector('.gridContainer');
    }
    
    if (!container) {
        console.error('Could not find gridContainer element');
        return;
    }
    
    console.log('displayGridButtons: Found container, adding', buttons.length, 'buttons');
    container.innerHTML = '';
    
    container.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
    updateGridFontSize(container);
    
    // Fetch images for buttons that don't have one yet
    const buttonPromises = buttons.map(async (buttonConfig) => {
        // If button already has an imageUrl, use it
        if (buttonConfig.imageUrl) {
            return buttonConfig;
        }
        
        // Try to fetch image for button text (prioritize full text over summary)
        const textToMatch = buttonConfig.text || buttonConfig.summary || '';
        if (textToMatch.trim()) {
            try {
                const imageUrl = await getSymbolImageForText(textToMatch);
                if (imageUrl) {
                    buttonConfig.imageUrl = imageUrl;
                    console.log(`[BUTTON IMAGE] Added image for "${textToMatch}"`);
                }
            } catch (error) {
                console.warn(`[BUTTON IMAGE] Failed to fetch image for "${textToMatch}":`, error);
            }
        }
        
        return buttonConfig;
    });
    
    // Wait for all images to be fetched
    const enhancedButtons = await Promise.all(buttonPromises);
    
    // Create and add buttons
    enhancedButtons.forEach(buttonConfig => {
        const button = createButton(buttonConfig);
        container.appendChild(button);
    });

    if (enhancedButtons.length > 0) {
        startAuditoryScanning();
    }
}

function updateGridFontSize(container) {
    const baseFontSize = 20;
    const minFontSize = 10;
    const maxFontSize = 28;
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / gridColumns)));
    container.style.setProperty('--button-font-size', `${fontSize}px`);
}

function getVisibleButtons() {
    const visibleScreen = document.querySelector('.visible-screen');
    const container = visibleScreen ? visibleScreen.querySelector('.gridContainer') : document.querySelector('.gridContainer');
    if (!container) return [];
    return Array.from(container.querySelectorAll('button:not([style*="display: none"])'));
}

function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) { return; }

    if (scanMode === 'step') {
        currentButtonIndex = -1;
        advanceGuessWhoScanningStep();
        return;
    }

    const buttons = getVisibleButtons();
    if (buttons.length === 0) { return; }

    currentButtonIndex = -1;
    const scanStep = async () => {
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning');
        }
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) {
            currentButtonIndex = 0;
        }

        const nextButton = buttons[currentButtonIndex];
        if (!nextButton) { return; }
        currentlyScannedButton = nextButton;
        nextButton.classList.add('scanning');

        const textToSpeak = nextButton.textContent || '';
        // Use Prompt/Speak for scanning (simpler, no splash screen, no queue)
        if (typeof Prompt === 'function') {
            try {
                Prompt(textToSpeak, false, false);
            } catch (e) {
                console.error('Scanning Prompt error:', e);
            }
        } else {
            // Fallback: simple announce without splash screen
            try {
                await announce(textToSpeak, 'system', false, false);
            } catch (e) {
                console.error('Scanning announce error:', e);
            }
        }
    };

    scanStep();
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function advanceGuessWhoScanningStep() {
    if (ScanningOff || scanMode !== 'step') {
        return;
    }

    const buttons = getVisibleButtons();
    if (buttons.length === 0) {
        currentlyScannedButton = null;
        return;
    }

    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning');
    }

    currentButtonIndex = (currentButtonIndex + 1) % buttons.length;
    const nextButton = buttons[currentButtonIndex];
    if (!nextButton) {
        return;
    }
    currentlyScannedButton = nextButton;
    nextButton.classList.add('scanning');

    const textToSpeak = nextButton.textContent || '';
    if (typeof Prompt === 'function') {
        try {
            Prompt(textToSpeak, false, false);
        } catch (e) {
            console.error('Scanning Prompt error:', e);
        }
    } else {
        announce(textToSpeak, 'system', false, false).catch((e) => {
            console.error('Scanning announce error:', e);
        });
    }
}

function stopAuditoryScanning() {
    if (scanningInterval) {
        clearInterval(scanningInterval);
        scanningInterval = null;
    }
    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning');
        currentlyScannedButton = null;
    }
    currentButtonIndex = -1;
}

function createButton(config) {
    const button = document.createElement('button');
    // For display on the button: prioritize summary (for clues/responses), fall back to text
    const displayText = String(config.summary || config.text || '').trim();
    // For images and metadata: use full text first
    const fullText = String(config.text || config.summary || '').trim();
    
    // If an image URL is provided, create image + text footer layout (exactly like gridpage)
    if (config.imageUrl) {
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
        imageElement.src = config.imageUrl;
        imageElement.alt = fullText;
        imageElement.style.width = '100%';
        imageElement.style.height = '100%';
        imageElement.style.objectFit = 'cover'; // Fills container like gridpage
        imageElement.onerror = () => {
            console.warn(`[IMAGE] Failed to load image for "${displayText}"`);
            // Hide the broken image
            imageElement.style.display = 'none';
        };
        
        // Text footer (overlays bottom of image) - shows full text like gridpage
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
        // Image footer shows full text (like gridpage), but button display shows summary
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
        
        // Apply gridpage's button styling when image is present
        button.style.padding = '0';
        button.style.margin = '0';
        button.style.border = 'none';
        button.style.position = 'relative';
        button.style.overflow = 'hidden';
    } else {
        // Text-only button (no image available or disabled) - matches gridpage
        button.textContent = displayText;
    }
    
    // Add click handler
    button.addEventListener('click', (event) => {
        event.preventDefault();
        // Stop scanning immediately before handling button click
        stopAuditoryScanning();
        // Don't announce button text here - let the onClick handler decide what to announce
        if (config.onClick) {
            config.onClick();
        }
    });
    
    return button;
}

function announceText(text, recordHistory = false) {
    return announce(text, 'system', recordHistory, true);
}

function base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

async function playAudioToDevice(audioDataBuffer, sampleRate) {
    if (!audioDataBuffer) {
        return;
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') {
            audioContext.resume().catch(() => {});
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
        console.error('Audio playback error:', error);
        if (audioContext && audioContext.state !== 'closed') {
            audioContext.close();
        }
        if (activeAnnouncementAudioContext === audioContext) {
            activeAnnouncementAudioContext = null;
            activeAnnouncementAudioSource = null;
        }
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

async function processAnnouncementQueue() {
    if (isAnnouncingNow || announcementQueue.length === 0) {
        return;
    }
    isAnnouncingNow = true;
    const announcement = announcementQueue.shift();
    const { textToAnnounce, resolve, reject, showSplash } = announcement;

    console.log(`[GUESS_WHO] Processing announcement: "${textToAnnounce.substring(0, 40)}..." showSplash=${showSplash}`);

    // Show splash screen if enabled and requested
    if (typeof showSplashScreen === 'function' && showSplash !== false) {
        console.log('[GUESS_WHO] Calling showSplashScreen');
        showSplashScreen(textToAnnounce);
    } else {
        console.log(`[GUESS_WHO] showSplashScreen not available. Type: ${typeof showSplashScreen}, showSplash: ${showSplash}`);
    }

    try {
        const response = await authenticatedFetch('/play-audio', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: textToAnnounce, routing_target: 'system' })
        });

        if (!response.ok) {
            const errorBody = await response.text();
            throw new Error(`Failed to synthesize audio: ${response.status} - ${errorBody}`);
        }

        const jsonResponse = await response.json();
        const audioData = jsonResponse.audio_data;
        const sampleRate = jsonResponse.sample_rate;

        if (!audioData) {
            throw new Error('No audio data received from server.');
        }

        const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
        await playAudioToDevice(audioDataArrayBuffer, sampleRate);

        resolve();
    } catch (error) {
        console.error('Announce error:', error);
        reject(error);
    } finally {
        isAnnouncingNow = false;
        if (announcementQueue.length > 0) {
            processAnnouncementQueue();
        }
    }
}

async function announce(textToAnnounce, announcementType = 'system', recordHistory = false, showSplash = false) {
    const trimmedText = String(textToAnnounce || '').trim();
    if (!trimmedText) {
        return Promise.resolve();
    }

    return new Promise((resolve, reject) => {
        announcementQueue.push({ textToAnnounce: trimmedText, resolve, reject, showSplash });
        processAnnouncementQueue();
    });
}

function tryResumeAudioContext() {
    if (window.AudioContext && !audioContextResumeAttempted) {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') {
            audioContext.resume().catch(() => {});
        }
        audioContextResumeAttempted = true;
    }
}

// Fetch helper (similar to gridpage)
async function authenticatedFetch(url, options = {}, _isRetry = false) {
    const firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    const currentAacUserId = sessionStorage.getItem('currentAacUserId');
    
    if (!firebaseIdToken || !currentAacUserId) {
        console.error('Authentication: Firebase ID Token or AAC User ID not found.');
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error('Authentication required.');
    }
    
    const headers = options.headers || {};
    headers['Authorization'] = `Bearer ${firebaseIdToken}`;
    headers['X-User-ID'] = currentAacUserId;
    
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
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error('Authentication failed');
    }
    
    if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    return response;
}

// Start the game when page loads
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded, initializing game');
    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true });
    initializeGame();
    setupCustomCategoriesUI();
});

// ===== CUSTOM CATEGORIES MANAGEMENT =====

function setupCustomCategoriesUI() {
    const lockButton = document.getElementById('lock-icon');
    const pinModal = document.getElementById('pin-modal');
    const pinInput = document.getElementById('pin-input');
    const pinSubmitButton = document.getElementById('pin-submit');
    const pinCancelButton = document.getElementById('pin-cancel');
    const pinError = document.getElementById('pin-error');
    
    const customCategoriesModal = document.getElementById('custom-categories-modal');
    const closeCategoriesModal = document.getElementById('close-categories-modal');
    const cancelCategoriesButton = document.getElementById('cancel-categories-button');
    const saveCategoriesButton = document.getElementById('save-categories-button');
    const resetToDefaultsButton = document.getElementById('reset-to-defaults-button');
    const categoriesInput = document.getElementById('categories-input');
    const categoriesPreview = document.getElementById('categories-preview');
    const categoryCount = document.getElementById('category-count');
    
    // PIN Modal Functions
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
    
    function showCustomCategoriesModal() {
        hidePinModal();
        if (customCategoriesModal) {
            customCategoriesModal.classList.remove('hidden');
            loadCurrentCategories();
        }
    }
    
    function hideCustomCategoriesModal() {
        if (customCategoriesModal) {
            customCategoriesModal.classList.add('hidden');
        }
    }
    
    async function loadCurrentCategories() {
        try {
            const response = await authenticatedFetch('/api/guess-who/categories', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            
            if (response.ok) {
                const data = await response.json();
                // Use custom_categories if available, otherwise use default_categories
                const categories = (data.custom_categories && data.custom_categories.length > 0) 
                    ? data.custom_categories 
                    : data.default_categories;
                
                // Populate textarea with current categories (one per line)
                categoriesInput.value = categories.join('\n');
                updatePreview();
            }
        } catch (error) {
            console.error('Error loading categories:', error);
        }
    }
    
    function parseCategories(text) {
        // Split by newlines only (one category per line)
        const lines = text.split('\n');
        const categories = [];
        
        lines.forEach(line => {
            const trimmed = line.trim();
            if (trimmed.length > 0) {
                categories.push(trimmed);
            }
        });
        
        // Remove duplicates (case-insensitive)
        const unique = [];
        const seen = new Set();
        categories.forEach(cat => {
            const lower = cat.toLowerCase();
            if (!seen.has(lower)) {
                seen.add(lower);
                unique.push(cat);
            }
        });
        
        return unique;
    }
    
    function updatePreview() {
        const text = categoriesInput.value;
        const categories = parseCategories(text);
        
        if (categoryCount) {
            categoryCount.textContent = categories.length;
        }
        
        if (categoriesPreview) {
            if (categories.length === 0) {
                categoriesPreview.innerHTML = '<p class=\"text-gray-400 text-sm italic\">No categories entered yet...</p>';
            } else {
                categoriesPreview.innerHTML = categories.map((cat, index) => 
                    `<span class=\"inline-block bg-blue-100 text-blue-800 px-3 py-1 rounded-full text-sm mr-2 mb-2\">
                        ${index + 1}. ${escapeHtml(cat)}
                    </span>`
                ).join('');
            }
        }
    }
    
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    async function saveCustomCategories() {
        const text = categoriesInput.value;
        const categories = parseCategories(text);
        
        if (categories.length === 0) {
            alert('Please enter at least one category.');
            return;
        }
        
        try {
            const response = await authenticatedFetch('/api/guess-who/custom-categories', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ categories })
            });
            
            if (response.ok) {
                alert(`Successfully saved ${categories.length} custom categories!`);
                hideCustomCategoriesModal();
                
                // Reload the game if we're on category selection screen
                if (gameState.phase === 'category') {
                    await loadCategories();
                }
            } else {
                alert('Failed to save categories. Please try again.');
            }
        } catch (error) {
            console.error('Error saving categories:', error);
            alert('Failed to save categories. Please try again.');
        }
    }
    
    async function resetToDefaults() {
        if (!confirm('Are you sure you want to reset to default categories? This will remove all custom categories.')) {
            return;
        }
        
        try {
            const response = await authenticatedFetch('/api/guess-who/custom-categories', {
                method: 'DELETE'
            });
            
            if (response.ok) {
                alert('Successfully reset to default categories!');
                hideCustomCategoriesModal();
                
                // Reload the game if we're on category selection screen
                if (gameState.phase === 'category') {
                    await loadCategories();
                }
            } else {
                alert('Failed to reset categories. Please try again.');
            }
        } catch (error) {
            console.error('Error resetting categories:', error);
            alert('Failed to reset categories. Please try again.');
        }
    }
    
    // Event Listeners
    if (lockButton) {
        lockButton.addEventListener('click', showPinModal);
    }
    
    if (pinSubmitButton) {
        pinSubmitButton.addEventListener('click', async () => {
            const pin = pinInput.value;
            if (pin.length >= 3 && pin.length <= 10) {
                const isValid = await validatePin(pin);
                if (isValid) {
                    showCustomCategoriesModal();
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
    
    if (pinCancelButton) {
        pinCancelButton.addEventListener('click', hidePinModal);
    }
    
    if (pinInput) {
        pinInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                pinSubmitButton.click();
            }
        });
    }
    
    if (closeCategoriesModal) {
        closeCategoriesModal.addEventListener('click', hideCustomCategoriesModal);
    }
    
    if (cancelCategoriesButton) {
        cancelCategoriesButton.addEventListener('click', hideCustomCategoriesModal);
    }
    
    if (saveCategoriesButton) {
        saveCategoriesButton.addEventListener('click', saveCustomCategories);
    }
    
    if (resetToDefaultsButton) {
        resetToDefaultsButton.addEventListener('click', resetToDefaults);
    }
    
    if (categoriesInput) {
        categoriesInput.addEventListener('input', updatePreview);
    }
    
    // Close modal on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.code === 'Tab' && scanMode === 'step') {
            e.preventDefault();
            interruptScanningAnnouncementPlayback();
            if (currentlyScannedButton) {
                advanceGuessWhoScanningStep();
            } else {
                startAuditoryScanning();
            }
            return;
        }

        if (e.code === 'Space' && currentlyScannedButton) {
            e.preventDefault();
            currentlyScannedButton.click();
            return;
        }

        if (e.key === 'Escape') {
            if (customCategoriesModal && !customCategoriesModal.classList.contains('hidden')) {
                hideCustomCategoriesModal();
            } else if (pinModal && !pinModal.classList.contains('hidden')) {
                hidePinModal();
            }
        }
    });
}

