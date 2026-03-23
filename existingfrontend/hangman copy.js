/**
 * Hangman Game Logic
 * Mode A (I guess): I guess letters by scanning/tapping alphabet.
 *   You pick a word (secret from app), say "ready", tell letter count,
 *   then confirm yes/no for each guessed letter and tap correct positions.
 * Mode B (You guess): I pick a word from LLM-generated options.
 *   You guess letters by voice (wake word → letter).
 *   App auto-checks and reveals letters or adds body parts.
 */

// ===== GAME STATE =====
const gameState = {
    phase: 'category',          // category, mode, wordSelect, setup, playing, gameOver
    selectedCategory: null,
    selectedMode: null,         // 'mode-a' or 'mode-b'
    word: null,                 // The secret word (known in Mode B, unknown in Mode A)
    wordLength: null,           // Number of letters (Mode A: told by you)
    revealedLetters: [],        // Array of booleans per letter position
    guessedLetters: [],         // Letters that have been guessed
    wrongGuesses: 0,            // Count of wrong guesses (max 6)
    maxWrong: 6,
    isLoading: false,
    wordOptions: [],            // LLM-generated word options for Mode B
    currentGuessedLetter: null, // Mode A: the letter just guessed, awaiting yes/no
    processingYesNo: false,
    yesNoRecognitionId: null,
    modeAPhase: null,           // 'waitingReady', 'waitingLetterCount', 'playing', 'waitingYesNo', 'waitingPositions', 'confirmDone'
};

// Screen history for back navigation
const screenHistory = [];

// Scanning state
let scanningInterval = null;
let currentlyScannedButton = null;
let currentButtonIndex = -1;
let defaultDelay = 3500;
let ScanningOff = false;
let wakeWordInterjection = 'hey';
let wakeWordName = 'bravo';
let gridColumns = 6;

// Image matching
let enablePictograms = true;

// Audio announce queue
let announcementQueue = [];
let isAnnouncingNow = false;
let audioContextResumeAttempted = false;

// Speech recognition
let recognition = null;
let isSettingUpRecognition = false;
let waitingForWakeWord = false;
let waitingForGuess = false;
let skipOnendRestart = false;

// ===== INITIALIZATION =====
async function initializeGame() {
    console.log('Initializing Hangman game');
    screenHistory.length = 0;

    // Reset game state
    gameState.phase = 'category';
    gameState.selectedCategory = null;
    gameState.selectedMode = null;
    gameState.word = null;
    gameState.wordLength = null;
    gameState.revealedLetters = [];
    gameState.guessedLetters = [];
    gameState.wrongGuesses = 0;
    gameState.isLoading = false;
    gameState.wordOptions = [];
    gameState.currentGuessedLetter = null;
    gameState.processingYesNo = false;
    gameState.yesNoRecognitionId = null;
    gameState.modeAPhase = null;

    // Stop any lingering recognition/scanning
    stopAuditoryScanning();
    stopWakeWordRecognition();
    hideListeningIndicator();

    // Check auth
    const firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    const currentAacUserId = sessionStorage.getItem('currentAacUserId');
    if (!firebaseIdToken || !currentAacUserId) {
        sessionStorage.clear();
        window.location.href = 'auth.html';
        return;
    }

    await loadSettings();
    await showCategoryScreen();
}

async function loadSettings() {
    try {
        const response = await authenticatedFetch('/api/settings', { method: 'GET' });
        if (!response.ok) return;
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
    } catch (error) {
        console.error('Error loading settings:', error);
    }
}

function getWakeWordPhrase() {
    return `${wakeWordInterjection} ${wakeWordName}`.trim();
}

// ===== CATEGORY SCREEN =====
async function showCategoryScreen() {
    gameState.phase = 'category';
    updatePageContent('category-screen');

    try {
        gameState.isLoading = true;
        const response = await authenticatedFetch('/api/guess-what/categories', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const data = await response.json();
        const categories = data.all_categories;

        const buttons = categories.map(category => ({
            text: category,
            summary: category,
            onClick: () => selectCategory(category)
        }));
        buttons.unshift(createGoBackButton());

        const container = document.querySelector('#category-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
    } catch (error) {
        console.error('Error loading categories:', error);
        gameState.isLoading = false;
    }
}

function selectCategory(category) {
    gameState.selectedCategory = category;
    announceText(`The Category is ${category}.`, false).then(() => showModeScreen());
}

// ===== MODE SCREEN =====
async function showModeScreen() {
    gameState.phase = 'mode';
    updatePageContent('mode-screen');

    const buttons = [
        createGoBackButton(),
        {
            text: 'I guess',
            summary: 'I guess',
            onClick: () => startModeA()
        },
        {
            text: 'You guess',
            summary: 'You guess',
            onClick: () => startModeB()
        }
    ];

    const container = document.querySelector('#mode-screen .gridContainer');
    await displayGridButtons(buttons, container);
}

// ===== MODE A: I guess (you pick word secretly) =====
async function startModeA() {
    gameState.selectedMode = 'mode-a';
    gameState.modeAPhase = 'waitingReady';
    gameState.word = null; // Word is secret — app doesn't know it

    // Announce instructions and wait for "ready"
    announceText(`Think of a ${gameState.selectedCategory}. Say "ready" when you have your word.`, false);
    showListeningIndicator('Listening for: "ready"');
    listenForReady();
}

function listenForReady() {
    waitingForWakeWord = false;
    waitingForGuess = false;
    stopWakeWordRecognition();

    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) return;

    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = 'en-US';

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('[MODE A READY] Heard:', transcript);

        if (gameState.modeAPhase === 'waitingReady' && transcript.includes('ready')) {
            hideListeningIndicator();
            try { recognition.stop(); } catch (e) {}
            recognition = null;
            await handleModeAReady();
        }
    };

    recognition.onerror = () => {};
    recognition.onend = () => {
        if (gameState.modeAPhase === 'waitingReady') {
            setTimeout(() => listenForReady(), 500);
        }
    };

    try { recognition.start(); } catch (e) {}
}

async function handleModeAReady() {
    gameState.modeAPhase = 'waitingLetterCount';

    // Ask for letter count
    await announceText('Great! How many letters are in your word? Say the number.', false);
    showListeningIndicator('Listening for: letter count');
    listenForLetterCount();
}

function listenForLetterCount() {
    // Stop any existing recognition first (including previous countRecognition)
    if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }

    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) return;

    recognition = new SpeechRecognitionAPI();
    recognition.lang = 'en-US';
    recognition.continuous = true;
    recognition.interimResults = false;
    let countHandled = false;

    recognition.onresult = async (event) => {
        // Guard: only process if still waiting for letter count
        if (gameState.modeAPhase !== 'waitingLetterCount' || countHandled) return;

        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('[MODE A LETTER COUNT] Heard:', transcript);

        const count = parseLetterCount(transcript);
        if (count && count > 0 && count <= 30) {
            countHandled = true;
            hideListeningIndicator();
            try { recognition.stop(); } catch (e) {}
            recognition = null;
            gameState.wordLength = count;

            // Set up blank letters (all hidden)
            gameState.revealedLetters = new Array(count).fill(false);
            gameState.guessedLetters = [];
            gameState.wrongGuesses = 0;

            await announceText(`${count} letters. Let's play!`, false);
            gameState.modeAPhase = 'playing';
            showPlayingScreen();
        }
        // If not a valid number, silently keep listening (continuous mode stays open)
    };

    recognition.onerror = (event) => {
        console.log('[MODE A LETTER COUNT] Recognition error:', event.error);
        if (event.error === 'no-speech' || event.error === 'aborted') return;
        if (gameState.modeAPhase === 'waitingLetterCount' && !countHandled) {
            recognition = null;
            setTimeout(() => listenForLetterCount(), 500);
        }
    };

    recognition.onend = () => {
        // Restart if still waiting (browser may stop continuous recognition periodically)
        if (gameState.modeAPhase === 'waitingLetterCount' && !countHandled) {
            console.log('[MODE A LETTER COUNT] Recognition ended, restarting...');
            recognition = null;
            setTimeout(() => listenForLetterCount(), 300);
        }
    };

    try { recognition.start(); } catch (e) {}
}

function parseLetterCount(transcript) {
    // Try to extract a number from the transcript
    const wordToNum = {
        'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
        'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
        'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
        'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
        'twenty one': 21, 'twenty two': 22, 'twenty three': 23, 'twenty four': 24, 'twenty five': 25
    };

    // Check word numbers first
    for (const [word, num] of Object.entries(wordToNum)) {
        if (transcript.includes(word)) return num;
    }

    // Try numeric extraction
    const match = transcript.match(/(\d+)/);
    if (match) return parseInt(match[1]);

    return null;
}

// ===== MODE B: You guess (I pick word from LLM options) =====
async function startModeB() {
    gameState.selectedMode = 'mode-b';
    gameState.phase = 'wordSelect';

    try {
        gameState.isLoading = true;
        await announceText(`Give me a moment to choose a ${gameState.selectedCategory} word.`, false);

        const response = await authenticatedFetch('/api/hangman/generate-words', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                previous_words: []
            })
        });
        const data = await response.json();
        gameState.wordOptions = data.words || data.people || [];

        updatePageContent('word-screen');

        const buttons = gameState.wordOptions.map(word => ({
            text: word,
            summary: word,
            onClick: () => selectWord(word)
        }));
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshWordOptions()
        });
        buttons.unshift(createGoBackButton());

        const container = document.querySelector('#word-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
    } catch (error) {
        console.error('Error generating words:', error);
        gameState.isLoading = false;
    }
}

async function refreshWordOptions() {
    try {
        gameState.isLoading = true;
        const response = await authenticatedFetch('/api/hangman/generate-words', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: gameState.selectedCategory,
                previous_words: gameState.wordOptions || []
            })
        });
        const data = await response.json();
        gameState.wordOptions = data.words || data.people || [];

        const buttons = gameState.wordOptions.map(word => ({
            text: word,
            summary: word,
            onClick: () => selectWord(word)
        }));
        buttons.push({
            text: 'Something Else',
            summary: 'Something Else',
            onClick: () => refreshWordOptions()
        });
        buttons.unshift(createGoBackButton());

        const container = document.querySelector('#word-screen .gridContainer');
        await displayGridButtons(buttons, container);
        gameState.isLoading = false;
    } catch (error) {
        console.error('Error refreshing word options:', error);
        gameState.isLoading = false;
    }
}

async function selectWord(word) {
    gameState.word = word.toUpperCase();
    gameState.wordLength = gameState.word.replace(/[^A-Z]/g, '').length;
    gameState.revealedLetters = new Array(gameState.word.length).fill(false);
    // Mark non-letter characters as already revealed (spaces, hyphens, etc.)
    for (let i = 0; i < gameState.word.length; i++) {
        if (!/[A-Z]/.test(gameState.word[i])) {
            gameState.revealedLetters[i] = true;
        }
    }
    gameState.guessedLetters = [];
    gameState.wrongGuesses = 0;

    await announceText(`I picked my word! It has ${gameState.wordLength} letters. Say ${getWakeWordPhrase()} then guess a letter!`, false);
    showPlayingScreen();
    startModeBListening();
}

// ===== PLAYING SCREEN (shared by both modes) =====
function showPlayingScreen() {
    gameState.phase = 'playing';
    updatePageContent('playing-screen');
    renderHangmanSVG();
    renderWordBlanks();
    renderAlphabetGrid();
    updateWrongCount();

    if (gameState.selectedMode === 'mode-a') {
        // Mode A: I scan/tap alphabet
        startAlphabetScanning();
    }
}

function updateWrongCount() {
    const el = document.getElementById('wrong-count');
    if (el) el.textContent = gameState.wrongGuesses;
}

// ===== SVG HANGMAN DRAWING =====
function renderHangmanSVG() {
    const container = document.getElementById('hangman-svg-container');
    if (!container) return;

    // Base structure: gallows (always visible) + 6 body parts (hidden initially)
    container.innerHTML = `
        <svg width="180" height="220" viewBox="0 0 180 220" xmlns="http://www.w3.org/2000/svg">
            <!-- Gallows -->
            <line x1="20" y1="200" x2="160" y2="200" stroke="#1e293b" stroke-width="4" stroke-linecap="round"/>
            <line x1="60" y1="200" x2="60" y2="20" stroke="#1e293b" stroke-width="4" stroke-linecap="round"/>
            <line x1="60" y1="20" x2="120" y2="20" stroke="#1e293b" stroke-width="4" stroke-linecap="round"/>
            <line x1="120" y1="20" x2="120" y2="40" stroke="#1e293b" stroke-width="4" stroke-linecap="round"/>
            
            <!-- Body parts (hidden by default, shown progressively) -->
            <!-- 1: Left leg -->
            <line id="hangman-part-1" x1="120" y1="130" x2="100" y2="170" stroke="#1e293b" stroke-width="3" stroke-linecap="round" style="display:none"/>
            <!-- 2: Right leg -->
            <line id="hangman-part-2" x1="120" y1="130" x2="140" y2="170" stroke="#1e293b" stroke-width="3" stroke-linecap="round" style="display:none"/>
            <!-- 3: Torso -->
            <line id="hangman-part-3" x1="120" y1="80" x2="120" y2="130" stroke="#1e293b" stroke-width="3" stroke-linecap="round" style="display:none"/>
            <!-- 4: Left arm -->
            <line id="hangman-part-4" x1="120" y1="95" x2="95" y2="115" stroke="#1e293b" stroke-width="3" stroke-linecap="round" style="display:none"/>
            <!-- 5: Right arm -->
            <line id="hangman-part-5" x1="120" y1="95" x2="145" y2="115" stroke="#1e293b" stroke-width="3" stroke-linecap="round" style="display:none"/>
            <!-- 6: Head -->
            <circle id="hangman-part-6" cx="120" cy="58" r="18" stroke="#1e293b" stroke-width="3" fill="none" style="display:none"/>
        </svg>
    `;
    updateHangmanDisplay();
}

function updateHangmanDisplay() {
    for (let i = 1; i <= 6; i++) {
        const part = document.getElementById(`hangman-part-${i}`);
        if (part) {
            part.style.display = i <= gameState.wrongGuesses ? 'block' : 'none';
        }
    }
}

// ===== WORD BLANKS =====
function renderWordBlanks() {
    const container = document.getElementById('word-blanks');
    if (!container) return;
    container.innerHTML = '';

    if (gameState.selectedMode === 'mode-a') {
        // Mode A: We only know wordLength, not the actual word
        for (let i = 0; i < (gameState.wordLength || 0); i++) {
            const blank = document.createElement('div');
            blank.className = 'letter-blank';
            blank.id = `blank-${i}`;
            if (gameState.revealedLetters[i] && gameState.revealedLetters[i] !== false) {
                blank.textContent = gameState.revealedLetters[i]; // Store actual letter
                blank.classList.add('revealed');
            }
            container.appendChild(blank);
        }
    } else {
        // Mode B: We know the word
        for (let i = 0; i < gameState.word.length; i++) {
            const char = gameState.word[i];
            if (!/[A-Z]/.test(char)) {
                // Non-letter (space, hyphen, etc.)
                const spacer = document.createElement('div');
                spacer.className = 'letter-blank space-blank';
                if (char === '-') spacer.textContent = '-';
                container.appendChild(spacer);
            } else {
                const blank = document.createElement('div');
                blank.className = 'letter-blank';
                blank.id = `blank-${i}`;
                if (gameState.revealedLetters[i]) {
                    blank.textContent = char;
                    blank.classList.add('revealed');
                }
                container.appendChild(blank);
            }
        }
    }
}

// ===== ALPHABET GRID =====
function renderAlphabetGrid() {
    const container = document.getElementById('alphabet-grid');
    if (!container) return;
    container.innerHTML = '';

    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (const letter of letters) {
        const btn = document.createElement('button');
        btn.textContent = letter;
        btn.dataset.letter = letter;

        if (gameState.guessedLetters.includes(letter)) {
            // Already guessed — mark appropriately
            btn.disabled = true;
            if (gameState.selectedMode === 'mode-b') {
                // In Mode B we know if it was correct
                if (gameState.word.includes(letter)) {
                    btn.classList.add('letter-correct');
                } else {
                    btn.classList.add('letter-wrong');
                }
            } else {
                // Mode A: we mark based on stored result
                if (btn.dataset.wasCorrect === 'true') {
                    btn.classList.add('letter-correct');
                } else {
                    btn.classList.add('letter-wrong');
                }
            }
        }

        btn.addEventListener('click', () => handleLetterSelected(letter));
        container.appendChild(btn);
    }
}

function markAlphabetLetter(letter, correct) {
    const container = document.getElementById('alphabet-grid');
    if (!container) return;
    const btns = container.querySelectorAll('button');
    for (const btn of btns) {
        if (btn.dataset.letter === letter) {
            btn.disabled = true;
            btn.dataset.wasCorrect = correct ? 'true' : 'false';
            btn.classList.add(correct ? 'letter-correct' : 'letter-wrong');
            break;
        }
    }
}

// ===== SYSTEM VOICE FOR SCANNING =====
// Uses browser's built-in speechSynthesis (device default/system voice)
// instead of the Cloud TTS personal voice.
function speakScanLabel(text) {
    if (!text || !window.speechSynthesis) return;
    window.speechSynthesis.cancel(); // Stop any in-progress scan speech
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;
    window.speechSynthesis.speak(utterance);
}

function stopScanSpeech() {
    if (window.speechSynthesis) window.speechSynthesis.cancel();
}

// ===== ALPHABET SCANNING (Mode A: I scan alphabet buttons) =====
function startAlphabetScanning() {
    stopAlphabetScanning();
    if (ScanningOff) return;

    const container = document.getElementById('alphabet-grid');
    if (!container) return;
    const buttons = Array.from(container.querySelectorAll('button:not(:disabled)'));
    if (buttons.length === 0) return;

    currentButtonIndex = -1;

    const scanStep = () => {
        if (currentlyScannedButton) currentlyScannedButton.classList.remove('scanning');
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) currentButtonIndex = 0;

        const nextButton = buttons[currentButtonIndex];
        if (!nextButton) return;
        currentlyScannedButton = nextButton;
        nextButton.classList.add('scanning');

        speakScanLabel(nextButton.textContent || '');
    };

    scanStep();
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function stopAlphabetScanning() {
    if (scanningInterval) { clearInterval(scanningInterval); scanningInterval = null; }
    if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); currentlyScannedButton = null; }
    currentButtonIndex = -1;
    stopScanSpeech();
}

// ===== LETTER SELECTION HANDLER =====
async function handleLetterSelected(letter) {
    if (gameState.guessedLetters.includes(letter)) return;
    gameState.guessedLetters.push(letter);
    stopAlphabetScanning();
    stopAuditoryScanning();

    if (gameState.selectedMode === 'mode-a') {
        await handleModeALetterGuess(letter);
    } else {
        await handleModeBLetterGuess(letter);
    }
}

// ===== MODE A: LETTER GUESS FLOW =====
// I select letter → announce → you say yes/no → if yes, you tap positions
async function handleModeALetterGuess(letter) {
    gameState.currentGuessedLetter = letter;
    gameState.modeAPhase = 'waitingYesNo';

    await announceText(`Is the letter ${letter} in your word? Say yes or no.`, false);
    showListeningIndicator('Listening for: "yes" or "no"');
    listenForModeAYesNo();
}

function listenForModeAYesNo() {
    gameState.processingYesNo = false;
    gameState.yesNoRecognitionId = Date.now();
    const sessionId = gameState.yesNoRecognitionId;

    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) return;

    if (recognition) { try { recognition.stop(); } catch(e) {} recognition = null; }

    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = 'en-US';

    recognition.onresult = async (event) => {
        if (sessionId !== gameState.yesNoRecognitionId) return;
        if (gameState.processingYesNo) return;

        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('[MODE A YES/NO] Heard:', transcript);

        if (gameState.modeAPhase === 'waitingYesNo') {
            gameState.processingYesNo = true;
            if (transcript.includes('yes')) {
                hideListeningIndicator();
                try { recognition.stop(); } catch (e) {}
                recognition = null;
                await handleModeALetterCorrect();
            } else if (transcript.includes('no')) {
                hideListeningIndicator();
                try { recognition.stop(); } catch (e) {}
                recognition = null;
                await handleModeALetterWrong();
            } else {
                gameState.processingYesNo = false;
                // Keep listening — continuous mode stays open
            }
        }
    };

    recognition.onerror = (event) => {
        console.log('[MODE A YES/NO] Recognition error:', event.error);
        if (event.error === 'no-speech' || event.error === 'aborted') return;
        setTimeout(() => {
            if (gameState.modeAPhase === 'waitingYesNo' && !gameState.processingYesNo) listenForModeAYesNo();
        }, 1000);
    };

    recognition.onend = () => {
        if (gameState.modeAPhase === 'waitingYesNo' && !gameState.processingYesNo) {
            console.log('[MODE A YES/NO] Recognition ended, restarting...');
            setTimeout(() => listenForModeAYesNo(), 300);
        }
    };

    try { recognition.start(); } catch (e) {}
}

async function handleModeALetterCorrect() {
    const letter = gameState.currentGuessedLetter;
    markAlphabetLetter(letter, true);
    gameState.modeAPhase = 'waitingPositions';

    await announceText(`Great! Tap the blanks where ${letter} goes, then tap Done.`, false);
    enableBlankSelection();
}

function enableBlankSelection() {
    // Make unrevealed word blanks tappable for position selection
    const blanksContainer = document.getElementById('word-blanks');
    if (!blanksContainer) return;

    for (let i = 0; i < gameState.wordLength; i++) {
        const blank = document.getElementById(`blank-${i}`);
        if (!blank) continue;

        if (gameState.revealedLetters[i] && gameState.revealedLetters[i] !== false) {
            // Already revealed — not selectable
            continue;
        }

        blank.classList.add('selectable');
        // Remove old listeners by replacing the node
        const newBlank = blank.cloneNode(true);
        blank.parentNode.replaceChild(newBlank, blank);
        newBlank.addEventListener('click', () => {
            if (newBlank.classList.contains('selected')) {
                newBlank.classList.remove('selected');
                newBlank.textContent = '';
            } else {
                newBlank.classList.add('selected');
                newBlank.textContent = gameState.currentGuessedLetter;
            }
        });
    }

    // Show the Done button
    const doneBtn = document.getElementById('position-done-btn');
    if (doneBtn) {
        doneBtn.style.display = 'block';
        doneBtn.onclick = () => confirmPositions();
    }
}

async function confirmPositions() {
    stopAlphabetScanning();

    // Collect selected blanks
    const blanksContainer = document.getElementById('word-blanks');
    if (!blanksContainer) return;

    const selectedBlanks = blanksContainer.querySelectorAll('.letter-blank.selected');
    const letter = gameState.currentGuessedLetter;
    let positionsRevealed = 0;

    selectedBlanks.forEach(blank => {
        // Extract position from id "blank-N"
        const idMatch = blank.id && blank.id.match(/^blank-(\d+)$/);
        if (idMatch) {
            const pos = parseInt(idMatch[1]);
            gameState.revealedLetters[pos] = letter;
            positionsRevealed++;
        }
    });

    // Hide the Done button
    const doneBtn = document.getElementById('position-done-btn');
    if (doneBtn) doneBtn.style.display = 'none';

    if (positionsRevealed === 0) {
        await announceText(`You need to tap at least one blank. Try again.`, false);
        enableBlankSelection();
        return;
    }

    // Update display
    renderWordBlanks();
    updateHangmanDisplay();

    // Check win
    if (checkModeAWin()) {
        const word = gameState.revealedLetters.join('');
        await announceText(`I win! The word is ${word}!`, false);
        endGame(true);
        return;
    }

    // Continue playing
    gameState.modeAPhase = 'playing';
    await announceText('Got it. Keep guessing!', false);
    startAlphabetScanning();
}

function checkModeAWin() {
    // Win if all positions are revealed
    for (let i = 0; i < gameState.wordLength; i++) {
        if (!gameState.revealedLetters[i] || gameState.revealedLetters[i] === false) {
            return false;
        }
    }
    return true;
}

async function handleModeALetterWrong() {
    const letter = gameState.currentGuessedLetter;
    markAlphabetLetter(letter, false);
    gameState.wrongGuesses++;
    updateHangmanDisplay();
    updateWrongCount();

    if (gameState.wrongGuesses >= gameState.maxWrong) {
        await announceText('Oh no! I\'m out of guesses. You win!', false);
        endGame(false);
        return;
    }

    const remaining = gameState.maxWrong - gameState.wrongGuesses;
    await announceText(`Nope! ${remaining} wrong ${remaining === 1 ? 'guess' : 'guesses'} left.`, false);
    gameState.modeAPhase = 'playing';
    startAlphabetScanning();
}

// ===== MODE B: You guess via voice =====
function startModeBListening() {
    waitingForWakeWord = true;
    showListeningIndicator(`Listening for: "${getWakeWordPhrase()}"`);
    setupWakeWordRecognition();
}

function setupWakeWordRecognition() {
    if (isSettingUpRecognition) return;
    if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }
    isSettingUpRecognition = true;

    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) { isSettingUpRecognition = false; return; }

    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = 'en-US';

    recognition.onerror = (event) => {
        console.log('[MODE B WAKE] Recognition error:', event.error);
        if (!waitingForWakeWord) return;
        if (event.error === 'no-speech' || event.error === 'aborted') return;
        recognition = null;
        isSettingUpRecognition = false;
    };

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        const interjection = wakeWordInterjection || 'hey';
        const name = wakeWordName || 'bravo';
        const phrases = [`${interjection} ${name}`, `${interjection}, ${name}`, `${interjection},${name}`];

        console.log('[MODE B WAKE] Heard:', transcript);

        if (phrases.some(p => transcript.includes(p))) {
            waitingForWakeWord = false;
            hideListeningIndicator();
            if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }
            isSettingUpRecognition = false;

            await announceText('What letter?', false);
            showListeningIndicator('Listening for: a letter');
            startLetterCapture();
        }
    };

    recognition.onend = () => {
        if (skipOnendRestart) {
            recognition = null;
            isSettingUpRecognition = false;
            return;
        }
        if (waitingForWakeWord && !isSettingUpRecognition) {
            recognition = null;
            isSettingUpRecognition = false;
            setTimeout(setupWakeWordRecognition, 500);
        } else {
            recognition = null;
            isSettingUpRecognition = false;
        }
    };

    try { recognition.start(); isSettingUpRecognition = false; } catch (e) { recognition = null; isSettingUpRecognition = false; }
}

function startLetterCapture() {
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) return;

    let letterRecognition = new SpeechRecognitionAPI();
    letterRecognition.lang = 'en-US';
    letterRecognition.continuous = true;
    letterRecognition.interimResults = false;
    letterRecognition.maxAlternatives = 3;
    let letterResultHandled = false;

    letterRecognition.onresult = async (event) => {
        if (letterResultHandled) return;
        letterResultHandled = true;
        hideListeningIndicator();

        // Try all alternatives to find a letter
        const lastResult = event.results[event.results.length - 1];
        let detectedLetter = null;
        for (let i = 0; i < lastResult.length; i++) {
            const transcript = lastResult[i].transcript.toUpperCase().trim();
            console.log('[MODE B LETTER] Alternative', i, ':', transcript);

            // Try single character
            if (transcript.length === 1 && /[A-Z]/.test(transcript)) {
                detectedLetter = transcript;
                break;
            }

            // Try NATO/common speech patterns: "the letter B", "B as in boy", etc.
            const letterMatch = transcript.match(/\b([A-Z])\b/);
            if (letterMatch) {
                detectedLetter = letterMatch[1];
                break;
            }
        }

        try { letterRecognition.stop(); } catch (e) {}

        if (detectedLetter) {
            if (gameState.guessedLetters.includes(detectedLetter)) {
                await announceText(`You already guessed ${detectedLetter}. Try another letter. Say ${getWakeWordPhrase()} first.`, false);
                startModeBListening();
            } else {
                await handleLetterSelected(detectedLetter);
            }
        } else {
            await announceText("I didn't catch a letter. Say " + getWakeWordPhrase() + " and try again.", false);
            startModeBListening();
        }
    };

    letterRecognition.onerror = (event) => {
        console.log('[MODE B LETTER] Recognition error:', event.error);
        if (event.error === 'no-speech' || event.error === 'aborted') return;
        hideListeningIndicator();
        startModeBListening();
    };

    letterRecognition.onend = () => {
        // If recognition ended without a result (e.g. browser timeout), restart listening
        if (!letterResultHandled && gameState.phase === 'playing' && gameState.selectedMode === 'mode-b') {
            console.log('[MODE B LETTER] Recognition ended without result, restarting wake word listener...');
            hideListeningIndicator();
            startModeBListening();
        }
    };

    try { letterRecognition.start(); } catch (e) {}
}

async function handleModeBLetterGuess(letter) {
    // App knows the word — auto-check
    if (gameState.word.includes(letter)) {
        // Correct!
        markAlphabetLetter(letter, true);
        // Reveal all matching positions
        for (let i = 0; i < gameState.word.length; i++) {
            if (gameState.word[i] === letter) {
                gameState.revealedLetters[i] = true;
            }
        }
        renderWordBlanks();

        // Check win
        if (gameState.revealedLetters.every(r => r)) {
            const wordDisplay = gameState.word;
            await announceText(`Yes! ${letter} is in the word! The word is ${wordDisplay}. You win!`, false);
            endGame(true);
            return;
        }

        const count = gameState.word.split('').filter(c => c === letter).length;
        await announceText(`Yes! ${letter} appears ${count} ${count === 1 ? 'time' : 'times'}!`, false);
        startModeBListening();
    } else {
        // Wrong!
        markAlphabetLetter(letter, false);
        gameState.wrongGuesses++;
        updateHangmanDisplay();
        updateWrongCount();

        if (gameState.wrongGuesses >= gameState.maxWrong) {
            await announceText(`No, ${letter} is not in the word. The word was ${gameState.word}. Game over!`, false);
            endGame(false);
            return;
        }

        const remaining = gameState.maxWrong - gameState.wrongGuesses;
        await announceText(`No, ${letter} is not in the word. ${remaining} wrong ${remaining === 1 ? 'guess' : 'guesses'} left.`, false);
        startModeBListening();
    }
}

// ===== GAME OVER =====
function endGame(playerWon) {
    gameState.phase = 'gameOver';
    hideListeningIndicator();
    stopWakeWordRecognition();
    stopAlphabetScanning();
    stopAuditoryScanning();

    if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }
    isSettingUpRecognition = false;

    updatePageContent('game-over-screen');

    const msgEl = document.getElementById('game-over-message');
    const detailsEl = document.getElementById('game-over-details');

    if (gameState.selectedMode === 'mode-a') {
        // Mode A: I was guessing
        if (playerWon) {
            const word = gameState.revealedLetters.join('');
            msgEl.textContent = `🎉 I figured it out! The word is "${word}"`;
            detailsEl.textContent = `I made ${gameState.wrongGuesses} wrong guess${gameState.wrongGuesses !== 1 ? 'es' : ''}.`;
        } else {
            msgEl.textContent = `💀 Game Over! The hangman is complete.`;
            detailsEl.textContent = `Better luck next time! I used all ${gameState.maxWrong} wrong guesses.`;
        }
    } else {
        // Mode B: You were guessing
        if (playerWon) {
            msgEl.textContent = `🎉 You got it! The word was "${gameState.word}"`;
            detailsEl.textContent = `${gameState.wrongGuesses} wrong guess${gameState.wrongGuesses !== 1 ? 'es' : ''} out of ${gameState.maxWrong} allowed.`;
        } else {
            msgEl.textContent = `💀 Game Over! The word was "${gameState.word}"`;
            detailsEl.textContent = `You used all ${gameState.maxWrong} wrong guesses.`;
        }
    }

    const buttons = [
        { text: 'Play Again', summary: 'Play Again', onClick: () => initializeGame() },
        { text: 'Go Back', summary: 'Go Back', onClick: () => goBackToPreviousStep() }
    ];
    const container = document.querySelector('#game-over-screen .gridContainer');
    displayGridButtons(buttons, container).catch(err => console.error('Error displaying game over buttons:', err));
}

// ===== SHARED UI FUNCTIONS =====

function updatePageContent(screenId, customSubtitle = null, options = {}) {
    stopAuditoryScanning();
    stopAlphabetScanning();
    const { skipHistory = false } = options;
    document.querySelectorAll('[id$="-screen"]').forEach(screen => {
        screen.classList.remove('visible-screen');
        screen.classList.add('hidden-screen');
    });
    document.getElementById(screenId).classList.remove('hidden-screen');
    document.getElementById(screenId).classList.add('visible-screen');

    if (!skipHistory) {
        if (screenHistory[screenHistory.length - 1] !== screenId) {
            screenHistory.push(screenId);
        }
    }
}

function goBackToPreviousStep() {
    stopAuditoryScanning();
    stopAlphabetScanning();
    stopWakeWordRecognition();
    hideListeningIndicator();
    waitingForWakeWord = false;
    waitingForGuess = false;
    skipOnendRestart = true;

    if (screenHistory.length > 1) {
        screenHistory.pop();
        const previousScreen = screenHistory[screenHistory.length - 1];
        updatePageContent(previousScreen, null, { skipHistory: true });
        return;
    }
    window.location.href = '/games.html';
}

function createGoBackButton() {
    return {
        text: 'Go Back',
        summary: 'Go Back',
        onClick: () => goBackToPreviousStep()
    };
}

async function displayGridButtons(buttons, containerElement = null) {
    stopAuditoryScanning();
    let container = containerElement;
    if (!container) {
        const visibleScreen = document.querySelector('.visible-screen');
        container = visibleScreen ? visibleScreen.querySelector('.gridContainer') : document.querySelector('.gridContainer');
    }
    if (!container) return;

    container.innerHTML = '';
    container.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
    updateGridFontSize(container);

    // Fetch images for buttons
    const buttonPromises = buttons.map(async (buttonConfig) => {
        if (buttonConfig.imageUrl) return buttonConfig;
        const textToMatch = buttonConfig.text || buttonConfig.summary || '';
        if (textToMatch.trim()) {
            try {
                const imageUrl = await getSymbolImageForText(textToMatch);
                if (imageUrl) buttonConfig.imageUrl = imageUrl;
            } catch (e) {}
        }
        return buttonConfig;
    });
    const enhanced = await Promise.all(buttonPromises);

    enhanced.forEach(config => {
        const button = createButton(config);
        container.appendChild(button);
    });

    if (enhanced.length > 0) {
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

function createButton(config) {
    const button = document.createElement('button');
    const displayText = String(config.summary || config.text || '').trim();
    const fullText = String(config.text || config.summary || '').trim();

    if (config.imageUrl) {
        const buttonContent = document.createElement('div');
        buttonContent.style.cssText = 'position:relative;width:100%;height:100%;display:flex;flex-direction:column;';

        const imageContainer = document.createElement('div');
        imageContainer.style.cssText = 'flex:1;width:100%;overflow:hidden;border-radius:8px 8px 0 0;display:flex;align-items:center;justify-content:center;';

        const img = document.createElement('img');
        img.src = config.imageUrl;
        img.alt = fullText;
        img.style.cssText = 'width:100%;height:100%;object-fit:cover;';
        img.onerror = () => { img.style.display = 'none'; };

        const textFooter = document.createElement('div');
        textFooter.style.cssText = 'height:28px;width:100%;background-color:rgba(0,0,0,0.9);color:white;display:flex;align-items:center;justify-content:center;padding:2px 4px;position:absolute;bottom:0;left:0;right:0;';

        const span = document.createElement('span');
        span.textContent = displayText;
        span.style.cssText = 'font-size:0.7em;font-weight:bold;text-align:center;line-height:1.1;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;';

        imageContainer.appendChild(img);
        textFooter.appendChild(span);
        buttonContent.appendChild(imageContainer);
        buttonContent.appendChild(textFooter);
        button.appendChild(buttonContent);

        button.style.cssText = 'padding:0;margin:0;border:none;position:relative;overflow:hidden;';
    } else {
        button.textContent = displayText;
    }

    button.addEventListener('click', (e) => {
        e.preventDefault();
        stopAuditoryScanning();
        stopAlphabetScanning();
        if (config.onClick) config.onClick();
    });

    return button;
}

function getVisibleButtons() {
    const visibleScreen = document.querySelector('.visible-screen');
    const container = visibleScreen ? visibleScreen.querySelector('.gridContainer') : document.querySelector('.gridContainer');
    if (!container) return [];
    return Array.from(container.querySelectorAll('button:not([style*="display: none"])'));
}

function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) return;
    const buttons = getVisibleButtons();
    if (buttons.length === 0) return;
    currentButtonIndex = -1;

    const scanStep = () => {
        if (currentlyScannedButton) currentlyScannedButton.classList.remove('scanning');
        currentButtonIndex++;
        if (currentButtonIndex >= buttons.length) currentButtonIndex = 0;
        const nextButton = buttons[currentButtonIndex];
        if (!nextButton) return;
        currentlyScannedButton = nextButton;
        nextButton.classList.add('scanning');
        speakScanLabel(nextButton.textContent || '');
    };

    scanStep();
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function stopAuditoryScanning() {
    if (scanningInterval) { clearInterval(scanningInterval); scanningInterval = null; }
    if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); currentlyScannedButton = null; }
    currentButtonIndex = -1;
    stopScanSpeech();
}

// ===== LISTENING INDICATOR =====
function showListeningIndicator(message) {
    const indicator = document.getElementById('listening-status');
    if (indicator) { indicator.textContent = message; indicator.classList.add('active'); }
}

function hideListeningIndicator() {
    const indicator = document.getElementById('listening-status');
    if (indicator) indicator.classList.remove('active');
}

// ===== STOP WAKE WORD =====
function stopWakeWordRecognition() {
    waitingForWakeWord = false;
    waitingForGuess = false;
    if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }
    isSettingUpRecognition = false;
}

// ===== ANNOUNCE / TTS =====
function announceText(text, recordHistory = false) {
    return announce(text, 'system', recordHistory, true);
}

async function announce(textToAnnounce, announcementType = 'system', recordHistory = false, showSplash = false) {
    const trimmedText = String(textToAnnounce || '').trim();
    if (!trimmedText) return Promise.resolve();
    return new Promise((resolve, reject) => {
        announcementQueue.push({ textToAnnounce: trimmedText, resolve, reject, showSplash });
        processAnnouncementQueue();
    });
}

async function processAnnouncementQueue() {
    if (isAnnouncingNow || announcementQueue.length === 0) return;
    isAnnouncingNow = true;
    const announcement = announcementQueue.shift();
    const { textToAnnounce, resolve, reject, showSplash } = announcement;

    if (typeof showSplashScreen === 'function' && showSplash !== false) {
        showSplashScreen(textToAnnounce);
    }

    try {
        const response = await authenticatedFetch('/play-audio', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: textToAnnounce, routing_target: 'system' })
        });
        if (!response.ok) throw new Error(`Audio synthesis failed: ${response.status}`);
        const jsonResponse = await response.json();
        const audioData = jsonResponse.audio_data;
        if (!audioData) throw new Error('No audio data received');
        const buffer = base64ToArrayBuffer(audioData);
        await playAudioToDevice(buffer, jsonResponse.sample_rate);
        resolve();
    } catch (error) {
        console.error('Announce error:', error);
        reject(error);
    } finally {
        isAnnouncingNow = false;
        if (announcementQueue.length > 0) processAnnouncementQueue();
    }
}

function base64ToArrayBuffer(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
}

async function playAudioToDevice(audioDataBuffer, sampleRate) {
    if (!audioDataBuffer) return;
    let audioContext;
    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') audioContext.resume().catch(() => {});
        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        source.start(0);
        return new Promise(resolve => { source.onended = () => { audioContext.close(); resolve(); }; });
    } catch (error) {
        console.error('Audio playback error:', error);
        if (audioContext && audioContext.state !== 'closed') audioContext.close();
    }
}

function tryResumeAudioContext() {
    if (window.AudioContext && !audioContextResumeAttempted) {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        if (ctx.state === 'suspended') ctx.resume().catch(() => {});
        audioContextResumeAttempted = true;
    }
}

// ===== AUTH FETCH =====
async function authenticatedFetch(url, options = {}) {
    const firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    const currentAacUserId = sessionStorage.getItem('currentAacUserId');
    if (!firebaseIdToken || !currentAacUserId) {
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error('Authentication required.');
    }
    const headers = options.headers || {};
    headers['Authorization'] = `Bearer ${firebaseIdToken}`;
    headers['X-User-ID'] = currentAacUserId;
    const response = await fetch(url, { ...options, headers });
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    return response;
}

// ===== SYMBOL IMAGE LOOKUP =====
async function getSymbolImageForText(text) {
    if (!text || text.trim() === '') return null;
    if (!enablePictograms) return null;

    if (!window.symbolImageCache) {
        window.symbolImageCache = new Map();
        try {
            const cachedData = sessionStorage.getItem('symbolImageCache');
            if (cachedData) {
                const parsed = JSON.parse(cachedData);
                Object.entries(parsed).forEach(([key, value]) => {
                    if (value.timestamp > Date.now() - 3600000) window.symbolImageCache.set(key, value);
                });
            }
        } catch (e) {}
    }

    const cacheKey = `hm_${text.trim().toLowerCase()}`;
    if (window.symbolImageCache.has(cacheKey)) {
        const cached = window.symbolImageCache.get(cacheKey);
        if (cached.timestamp > Date.now() - 3600000) return cached.imageUrl;
    }

    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);
        const symbolsUrl = `/api/symbols/button-search?q=${encodeURIComponent(text.trim())}&limit=1`;
        const response = await authenticatedFetch(symbolsUrl, { signal: controller.signal });
        clearTimeout(timeoutId);
        if (!response.ok) return null;
        const data = await response.json();
        const url = (data?.symbols?.[0]?.url) || null;

        window.symbolImageCache.set(cacheKey, { imageUrl: url, timestamp: Date.now() });
        try {
            const cacheObj = Object.fromEntries(window.symbolImageCache);
            sessionStorage.setItem('symbolImageCache', JSON.stringify(cacheObj));
        } catch (e) {}
        return url;
    } catch (error) {
        return null;
    }
}

// ===== DOM READY =====
document.addEventListener('DOMContentLoaded', () => {
    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true });
    initializeGame();
});
