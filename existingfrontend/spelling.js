let firebaseIdToken = null;
let currentAacUserId = null;

let defaultDelay = 3500;
let scanMode = 'auto';
let waitForSwitchToScan = false;
let scanningInterval = null;
let currentlyScannedButton = null;
let currentButtonIndex = -1;
let spellLetterOrder = 'alphabetical';
let LLMOptions = 10;
let currentScanLevel = 'sections';
let activeSectionId = null;
let lettersScanPhase = 'rows'; // rows | items
let activeLetterRowIndex = null;

let currentSpellingWord = "";
let currentBuildSpaceText = "";
let currentPredictions = [];

let announcementQueue = [];
let isAnnouncingNow = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;
let pendingScanPromptTimer = null;
let pendingScanPromptToken = 0;
let lastScanPromptText = '';
let lastScanPromptTime = 0;

const currentWordInput = document.getElementById('current-word');
const alphabetGrid = document.getElementById('alphabet-grid');
const predictionsGrid = document.getElementById('word-predictions');

async function authenticatedFetch(url, options = {}, _isRetry = false) {
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        window.location.href = '/static/auth.html';
        throw new Error('User not authenticated');
    }

    const headers = options.headers || {};
    headers['Authorization'] = `Bearer ${firebaseIdToken}`;
    headers['X-User-ID'] = currentAacUserId;

    const adminTargetAccountId = sessionStorage.getItem('adminTargetAccountId');
    if (adminTargetAccountId) {
        headers['X-Admin-Target-Account'] = adminTargetAccountId;
    }

    options.headers = headers;

    const response = await fetch(url, options);
    if ((response.status === 401 || response.status === 403) && !_isRetry && typeof window.refreshFirebaseToken === 'function') {
        const newToken = await window.refreshFirebaseToken();
        if (newToken) {
            return authenticatedFetch(url, options, true);
        }
    }

    if (response.status === 401 || response.status === 403) {
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed');
    }

    return response;
}

async function loadSettings() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (!response.ok) return;
        const settings = await response.json();
        defaultDelay = settings.scanDelay || 3500;
        scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
        waitForSwitchToScan = settings.waitForSwitchToScan === true;
        spellLetterOrder = typeof settings.spellLetterOrder === 'string' ? settings.spellLetterOrder : 'alphabetical';
        LLMOptions = settings.LLMOptions || 10;
        if (waitForSwitchToScan) {
            window.waitingForInitialSwitch = true;
        }
    } catch (error) {
        console.error('Failed to load settings:', error);
    }
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

async function playAudioToDevice(audioDataBuffer, sampleRate, announcementType) {
    let audioContext = null;
    let source = null;

    try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextClass) {
            throw new Error('Web Audio API not supported');
        }

        const personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
        const systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';

        let targetOutputDeviceId = 'default';
        if (announcementType === 'personal') {
            targetOutputDeviceId = personalSpeakerId;
        } else if (announcementType === 'system') {
            targetOutputDeviceId = systemSpeakerId;
        }

        audioContext = new AudioContextClass();
        if (audioContext.state === 'suspended') {
            await audioContext.resume();
        }

        if (typeof audioContext.setSinkId === 'function' && targetOutputDeviceId && targetOutputDeviceId !== 'default') {
            await audioContext.setSinkId(targetOutputDeviceId);
        }

        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);

        activeAnnouncementAudioContext = audioContext;
        activeAnnouncementAudioSource = source;
        source.start(0);

        await new Promise((resolve) => {
            source.onended = resolve;
        });
    } finally {
        activeAnnouncementAudioSource = null;
        if (activeAnnouncementAudioContext === audioContext) {
            activeAnnouncementAudioContext = null;
        }
        if (audioContext && audioContext.state !== 'closed') {
            await audioContext.close().catch(() => {});
        }
    }
}

function getHomeTarget() {
    const params = new URLSearchParams(window.location.search);
    const from = params.get('from');
    if (from) return from;
    return '/static/gridpage.html?page=home';
}

function updateBuildSpaceInput() {
    const composedText = [currentBuildSpaceText, currentSpellingWord]
        .filter((part) => typeof part === 'string' && part.trim() !== '')
        .join(' ')
        .trim();
    currentWordInput.value = composedText;
}

function navigateHome() {
    stopAuditoryScanning();
    window.location.href = getHomeTarget();
}

function generateAlphabetGrid() {
    alphabetGrid.innerHTML = '';
    let letters;

    if (spellLetterOrder === 'qwerty') {
        letters = [
            ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
            ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
            ['Z', 'X', 'C', 'V', 'B', 'N', 'M']
        ];
        alphabetGrid.style.gridTemplateColumns = 'repeat(10, 1fr)';
        letters.forEach((row, rowIndex) => {
            row.forEach((letter, colIndex) => {
                const button = document.createElement('button');
                button.className = 'letter-btn spell-button';
                button.textContent = letter;
                button.dataset.letter = letter;
                button.dataset.rowIndex = String(rowIndex);
                button.addEventListener('click', () => handleLetterClick(letter));
                if (rowIndex === 1 && colIndex === 0) {
                    button.style.marginLeft = '5%';
                }
                if (rowIndex === 2 && colIndex === 0) {
                    button.style.gridColumn = '2 / span 1';
                }
                alphabetGrid.appendChild(button);
            });
        });
        appendLettersGoBackOption();
        return;
    }

    if (spellLetterOrder === 'frequency') {
        letters = 'ETAOINSHRDLUCMFWGYPBVKXJZQ'.split('');
    } else {
        letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }

    alphabetGrid.style.gridTemplateColumns = 'repeat(7, 1fr)';
    letters.forEach((letter, index) => {
        const button = document.createElement('button');
        button.className = 'letter-btn spell-button';
        button.textContent = letter;
        button.dataset.letter = letter;
        button.dataset.rowIndex = String(Math.floor(index / 7));
        button.addEventListener('click', () => handleLetterClick(letter));
        alphabetGrid.appendChild(button);
    });

    appendLettersGoBackOption();
}

function appendLettersGoBackOption() {
    const goBackButton = document.createElement('button');
    goBackButton.className = 'letter-btn spell-button';
    goBackButton.textContent = 'Go Back';
    goBackButton.dataset.standardOption = 'true';
    const existingRows = Array.from(alphabetGrid.querySelectorAll('.letter-btn'))
        .map((button) => Number(button.dataset.rowIndex))
        .filter((row) => !Number.isNaN(row));
    const maxRow = existingRows.length ? Math.max(...existingRows) : 0;
    goBackButton.dataset.rowIndex = String(maxRow + 1);
    goBackButton.addEventListener('click', () => {
        restartScanning(120, true);
    });
    alphabetGrid.appendChild(goBackButton);
}

async function handleLetterClick(letter) {
    currentSpellingWord += letter.toLowerCase();
    updateBuildSpaceInput();
    updateLetterAvailability(currentSpellingWord);
    await refreshSuggestedWords();
    restartScanning(250, true);
}

function setBuildSpaceText(text) {
    currentBuildSpaceText = (text || '').trim();
    updateBuildSpaceInput();
}

function appendWordToBuildSpace(word) {
    const cleanWord = (word || '').trim();
    if (!cleanWord) return;
    const nextText = currentBuildSpaceText ? `${currentBuildSpaceText} ${cleanWord}` : cleanWord;
    setBuildSpaceText(nextText);
}

async function getContextualSuggestedWords() {
    try {
        const response = await authenticatedFetch('/api/freestyle/word-options', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                build_space_text: currentBuildSpaceText,
                max_options: Math.max(1, LLMOptions)
            })
        });

        if (!response.ok) {
            currentPredictions = [];
            return;
        }

        const data = await response.json();
        const rawOptions = data.word_options || [];
        currentPredictions = rawOptions
            .map((opt) => (typeof opt === 'object' && opt.text ? opt.text : opt))
            .filter((opt) => typeof opt === 'string' && opt.trim() !== '')
            .slice(0, Math.max(1, LLMOptions));
    } catch (error) {
        console.error('Error getting contextual suggestions:', error);
        currentPredictions = [];
    }
}

async function getWordPredictionsForSpelling() {
    try {
        const response = await authenticatedFetch('/api/freestyle/word-prediction', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                text: currentBuildSpaceText || "",
                spelling_word: currentSpellingWord || "",
                predict_full_words: true
            })
        });

        if (response.ok) {
            const data = await response.json();
            currentPredictions = (data.predictions || []).slice(0, Math.max(1, LLMOptions));
        } else {
            currentPredictions = [];
        }
    } catch (error) {
        console.error('Error getting predictions:', error);
        currentPredictions = [];
    }

    renderWordPredictions();
}

async function refreshSuggestedWords() {
    if (currentSpellingWord) {
        await getWordPredictionsForSpelling();
        return;
    }

    await getContextualSuggestedWords();
    renderWordPredictions();
}

function renderWordPredictions() {
    predictionsGrid.innerHTML = '';
    currentPredictions.forEach((word) => {
        const button = document.createElement('button');
        button.className = 'prediction-btn spell-button';
        button.textContent = word;
        button.addEventListener('click', () => handlePredictionClick(word));
        predictionsGrid.appendChild(button);
    });

    const goBackButton = document.createElement('button');
    goBackButton.className = 'prediction-btn spell-button';
    goBackButton.textContent = 'Go Back';
    goBackButton.dataset.standardOption = 'true';
    goBackButton.addEventListener('click', () => {
        restartScanning(120, true);
    });
    predictionsGrid.appendChild(goBackButton);
}

async function handlePredictionClick(word) {
    stopAuditoryScanning();
    await announce(word, 'system', false, true);
    await recordChatHistory('', word);
    appendWordToBuildSpace(word);
    clearCurrentSpellingWord();
    await refreshSuggestedWords();
    restartScanning(300, true);
}

async function speakDisplay() {
    const displayText = [currentBuildSpaceText, currentSpellingWord].filter(Boolean).join(' ').trim();
    if (!displayText) return;
    await announce(displayText, 'system', false, true);
    await recordChatHistory('', displayText);
    if (currentSpellingWord) {
        appendWordToBuildSpace(currentSpellingWord);
        clearCurrentSpellingWord();
        await refreshSuggestedWords();
    }
    restartScanning(300, true);
}

function clearCurrentSpellingWord() {
    currentSpellingWord = '';
    updateBuildSpaceInput();
}

async function clearBuildSpace() {
    currentBuildSpaceText = '';
    currentSpellingWord = '';
    updateBuildSpaceInput();
    currentPredictions = [];
    renderWordPredictions();
    updateLetterAvailability('');
    await refreshSuggestedWords();
}

async function backspaceCurrentWord() {
    if (currentSpellingWord.length > 0) {
        currentSpellingWord = currentSpellingWord.slice(0, -1);
        updateBuildSpaceInput();
        updateLetterAvailability(currentSpellingWord);
        await refreshSuggestedWords();
        restartScanning(250, true);
        return;
    }

    if (!currentBuildSpaceText) return;
    const nextText = currentBuildSpaceText.slice(0, -1).trimEnd();
    setBuildSpaceText(nextText);
    await refreshSuggestedWords();
    restartScanning(250, true);
}

function getValidLetters(currentWord) {
    if (!currentWord || currentWord.length === 0) {
        return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }

    const lastChar = currentWord.slice(-1).toUpperCase();
    const lastTwoChars = currentWord.slice(-2).toUpperCase();

    const likelyAfter = {
        'A': ['B', 'C', 'D', 'F', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W', 'Y'],
        'B': ['A', 'E', 'I', 'L', 'O', 'R', 'U', 'Y'],
        'C': ['A', 'E', 'H', 'I', 'L', 'O', 'R', 'U'],
        'D': ['A', 'E', 'I', 'O', 'R', 'U', 'Y'],
        'E': ['A', 'D', 'L', 'M', 'N', 'R', 'S', 'T', 'V', 'W', 'X'],
        'F': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
        'G': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
        'H': ['A', 'E', 'I', 'O', 'U', 'Y'],
        'I': ['C', 'D', 'F', 'G', 'L', 'M', 'N', 'R', 'S', 'T'],
        'J': ['A', 'E', 'O', 'U'],
        'K': ['A', 'E', 'I', 'N'],
        'L': ['A', 'E', 'I', 'O', 'U', 'Y'],
        'M': ['A', 'E', 'I', 'O', 'U', 'Y'],
        'N': ['A', 'C', 'D', 'E', 'G', 'I', 'K', 'O', 'S', 'T', 'U', 'Y', 'Z'],
        'O': ['B', 'C', 'D', 'F', 'G', 'K', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W'],
        'P': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
        'Q': ['U'],
        'R': ['A', 'E', 'I', 'O', 'U', 'Y'],
        'S': ['A', 'C', 'E', 'H', 'I', 'K', 'L', 'M', 'N', 'O', 'P', 'T', 'U', 'W'],
        'T': ['A', 'E', 'H', 'I', 'O', 'R', 'U', 'W'],
        'U': ['B', 'C', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T'],
        'V': ['A', 'E', 'I', 'O'],
        'W': ['A', 'E', 'H', 'I', 'O'],
        'X': ['A', 'E', 'I'],
        'Y': ['A', 'E', 'O', 'U'],
        'Z': ['A', 'E', 'I', 'O']
    };

    const likelyAfterTwoLetters = {
        'TH': ['A', 'E', 'I', 'O', 'R'],
        'CH': ['A', 'E', 'I', 'O', 'U'],
        'SH': ['A', 'E', 'I', 'O', 'U'],
        'WH': ['A', 'E', 'I', 'O', 'U'],
        'PH': ['A', 'E', 'I', 'O', 'U'],
        'ST': ['A', 'E', 'I', 'O', 'R', 'U'],
        'SP': ['A', 'E', 'I', 'O', 'R'],
        'SC': ['A', 'E', 'I', 'O', 'R'],
        'FL': ['A', 'E', 'I', 'O', 'U'],
        'BL': ['A', 'E', 'I', 'O', 'U'],
        'CL': ['A', 'E', 'I', 'O', 'U'],
        'GL': ['A', 'E', 'I', 'O', 'U'],
        'PL': ['A', 'E', 'I', 'O', 'U'],
        'BR': ['A', 'E', 'I', 'O', 'U'],
        'CR': ['A', 'E', 'I', 'O', 'U'],
        'DR': ['A', 'E', 'I', 'O', 'U'],
        'FR': ['A', 'E', 'I', 'O', 'U'],
        'GR': ['A', 'E', 'I', 'O', 'U'],
        'PR': ['A', 'E', 'I', 'O', 'U'],
        'TR': ['A', 'E', 'I', 'O', 'U'],
        'ON': ['A', 'C', 'D', 'E', 'G', 'K', 'S', 'T', 'Y', 'Z'],
        'RO': ['A', 'B', 'C', 'D', 'E', 'G', 'L', 'M', 'N', 'O', 'P', 'S', 'T', 'U', 'W'],
        'RN': ['A', 'E', 'I', 'O']
    };

    if (currentWord.length >= 4) {
        return 'ABCDEFGHIKLMNOPRSTUVWYZ'.split('');
    }
    if (currentWord.length >= 2 && likelyAfterTwoLetters[lastTwoChars]) {
        return likelyAfterTwoLetters[lastTwoChars];
    }
    if (likelyAfter[lastChar]) {
        return likelyAfter[lastChar];
    }
    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
}

function updateLetterAvailability(currentWord) {
    const validLetters = getValidLetters(currentWord);
    const letterButtons = document.querySelectorAll('.letter-btn');
    letterButtons.forEach((button) => {
        if (button.dataset.standardOption === 'true') {
            button.classList.remove('disabled-letter');
            button.disabled = false;
            return;
        }
        const letter = button.textContent.toUpperCase();
        if (validLetters.includes(letter)) {
            button.classList.remove('disabled-letter');
            button.disabled = false;
        } else {
            button.classList.add('disabled-letter');
            button.disabled = true;
        }
    });
}

function getVisibleEnabledButtons(selector) {
    return Array.from(document.querySelectorAll(selector)).filter((button) => {
        return button.offsetParent !== null && !button.disabled;
    });
}

function getSectionButtonsInOrder() {
    const orderedIds = ['action-section', 'choose-word-section', 'letters-section'];
    return orderedIds
        .map((id) => document.getElementById(id))
        .filter((section) => section && section.offsetParent !== null);
}

function getActionButtonsInOrder() {
    const orderedIds = ['speak-display-btn', 'backspace-btn', 'clear-word-btn', 'home-btn'];
    return orderedIds
        .map((id) => document.getElementById(id))
        .filter((button) => button && button.offsetParent !== null && !button.disabled);
}

function getItemsForSection(sectionId) {
    if (sectionId === 'action') {
        return getActionButtonsInOrder();
    }
    if (sectionId === 'choose-word') {
        return getVisibleEnabledButtons('.prediction-btn');
    }
    if (sectionId === 'letters') {
        if (lettersScanPhase === 'rows') {
            const rowSet = new Set(
                getVisibleEnabledButtons('.letter-btn')
                    .map((button) => Number(button.dataset.rowIndex))
                    .filter((row) => !Number.isNaN(row))
            );
            return Array.from(rowSet)
                .sort((a, b) => a - b)
                .map((rowIndex) => ({ type: 'letter-row', rowIndex }));
        }

        const rowButtons = getVisibleEnabledButtons('.letter-btn').filter((button) => {
            return Number(button.dataset.rowIndex) === activeLetterRowIndex;
        });
        return rowButtons;
    }
    return [];
}

function clearScanHighlight() {
    if (currentlyScannedButton && currentlyScannedButton.type === 'letter-row') {
        const rowButtons = getVisibleEnabledButtons('.letter-btn').filter((button) => {
            return Number(button.dataset.rowIndex) === currentlyScannedButton.rowIndex;
        });
        rowButtons.forEach((button) => button.classList.remove('scanned'));
        currentlyScannedButton = null;
        return;
    }

    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanned');
    }
    currentlyScannedButton = null;
}

function getScanPromptTextForElement(element) {
    if (!element) return '';

    if (element.type === 'letter-row') {
        return `Row ${element.rowIndex + 1}`;
    }

    if (element.classList.contains('scan-section')) {
        const sectionId = element.dataset.sectionId;
        if (sectionId === 'action') return 'Action';
        if (sectionId === 'choose-word') return 'Choose word';
        if (sectionId === 'letters') return 'Letters';
    }

    const directText = (element.textContent || '').replace(/\s+/g, ' ').trim();
    if (directText) return directText;

    const heading = element.querySelector('.section-title');
    return heading ? heading.textContent.trim() : '';
}

function clearPendingScanPrompt() {
    if (pendingScanPromptTimer) {
        clearTimeout(pendingScanPromptTimer);
        pendingScanPromptTimer = null;
    }
    pendingScanPromptToken += 1;
}

async function announceScanPrompt(promptText) {
    const text = (promptText || '').trim();
    if (!text) return;

    const now = Date.now();
    if (text === lastScanPromptText && now - lastScanPromptTime < 700) {
        return;
    }

    try {
        await announce(text, 'personal', false, false);
        lastScanPromptText = text;
        lastScanPromptTime = Date.now();
    } catch (error) {
        console.error('Error announcing scan prompt:', error);
    }
}

function scheduleScanPromptForElement(element) {
    const promptText = getScanPromptTextForElement(element);
    if (!promptText) return;

    clearPendingScanPrompt();
    const token = pendingScanPromptToken;
    pendingScanPromptTimer = setTimeout(() => {
        if (token !== pendingScanPromptToken) return;
        pendingScanPromptTimer = null;
        announceScanPrompt(promptText);
    }, 120);
}

function enterSectionScan(sectionId) {
    activeSectionId = sectionId;
    currentScanLevel = 'items';
    if (sectionId === 'letters') {
        lettersScanPhase = 'rows';
        activeLetterRowIndex = null;
    }
    stopAuditoryScanning();
    startAuditoryScanning();
}

function returnToSectionScan() {
    activeSectionId = null;
    currentScanLevel = 'sections';
    lettersScanPhase = 'rows';
    activeLetterRowIndex = null;
}

function advanceScan() {
    let buttons = [];

    if (currentScanLevel === 'sections') {
        buttons = getSectionButtonsInOrder();
    } else {
        buttons = getItemsForSection(activeSectionId);
        if (!buttons.length) {
            returnToSectionScan();
            buttons = getSectionButtonsInOrder();
        }
    }

    if (!buttons.length) {
        clearScanHighlight();
        currentButtonIndex = -1;
        return;
    }

    clearScanHighlight();
    currentButtonIndex = (currentButtonIndex + 1) % buttons.length;
    currentlyScannedButton = buttons[currentButtonIndex];
    if (currentlyScannedButton.type === 'letter-row') {
        const rowButtons = getVisibleEnabledButtons('.letter-btn').filter((button) => {
            return Number(button.dataset.rowIndex) === currentlyScannedButton.rowIndex;
        });
        rowButtons.forEach((button) => button.classList.add('scanned'));
    } else {
        currentlyScannedButton.classList.add('scanned');
    }
    scheduleScanPromptForElement(currentlyScannedButton);
}

function startAuditoryScanning() {
    if (scanningInterval) return;
    if (scanMode === 'step') {
        if (!currentlyScannedButton) {
            currentButtonIndex = -1;
            advanceScan();
        }
        return;
    }

    currentButtonIndex = -1;
    advanceScan();
    scanningInterval = setInterval(advanceScan, defaultDelay);
}

function stopAuditoryScanning() {
    clearPendingScanPrompt();
    if (scanningInterval) {
        clearInterval(scanningInterval);
        scanningInterval = null;
    }
    clearScanHighlight();
    currentButtonIndex = -1;
}

function restartScanning(delayMs = 0, resetToSections = false) {
    stopAuditoryScanning();
    setTimeout(() => {
        if (waitForSwitchToScan && window.waitingForInitialSwitch) {
            return;
        }
        if (resetToSections) {
            returnToSectionScan();
        }
        startAuditoryScanning();
    }, delayMs);
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

function handleSpacebarPress() {
    if (waitForSwitchToScan && window.waitingForInitialSwitch) {
        window.waitingForInitialSwitch = false;
        startAuditoryScanning();
        return;
    }

    if (!currentlyScannedButton) {
        startAuditoryScanning();
        return;
    }

    clearPendingScanPrompt();

    if (currentlyScannedButton.type === 'letter-row') {
        lettersScanPhase = 'items';
        activeLetterRowIndex = currentlyScannedButton.rowIndex;
        stopAuditoryScanning();
        startAuditoryScanning();
        return;
    }

    currentlyScannedButton.click();
}

function bindKeyboardScanning() {
    document.addEventListener('keydown', (event) => {
        if (event.repeat) return;
        if (event.code === 'Space') {
            event.preventDefault();
            handleSpacebarPress();
        }
        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            advanceScan();
        }
    });
}

async function announce(textToAnnounce, announcementType = 'system', recordHistory = true, showSplash = true) {
    if (!textToAnnounce || !textToAnnounce.trim()) {
        return;
    }

    announcementQueue.push({
        textToAnnounce: textToAnnounce.trim(),
        announcementType,
        recordHistory,
        showSplash
    });
    if (isAnnouncingNow) {
        return;
    }

    isAnnouncingNow = true;
    while (announcementQueue.length > 0) {
        const { textToAnnounce: text, announcementType: target, recordHistory: shouldRecordHistory } = announcementQueue.shift();
        try {
            const response = await authenticatedFetch('/play-audio', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ text, routing_target: target === 'personal' ? 'personal' : 'system' })
            });

            if (!response.ok) {
                throw new Error(`Failed to synthesize audio: ${response.status}`);
            }

            const jsonResponse = await response.json();
            const audioData = jsonResponse.audio_data;
            if (audioData) {
                const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
                await playAudioToDevice(audioDataArrayBuffer, jsonResponse.sample_rate, target);
            }

            if (shouldRecordHistory) {
                await recordChatHistory('', text);
            }
        } catch (error) {
            console.error('Error during announce:', error);
        }
    }
    isAnnouncingNow = false;
}

function setupEventListeners() {
    document.getElementById('speak-display-btn').addEventListener('click', speakDisplay);
    document.getElementById('clear-word-btn').addEventListener('click', async () => {
        await clearBuildSpace();
        restartScanning(150, true);
    });
    document.getElementById('backspace-btn').addEventListener('click', backspaceCurrentWord);
    document.getElementById('home-btn').addEventListener('click', navigateHome);

    const sections = document.querySelectorAll('.scan-section');
    sections.forEach((section) => {
        section.addEventListener('click', (event) => {
            if (event.target !== section) return;
            const sectionId = section.dataset.sectionId;
            if (!sectionId) return;
            enterSectionScan(sectionId);
        });
    });
}

async function initialize() {
    await loadSettings();
    setupEventListeners();
    generateAlphabetGrid();
    updateLetterAvailability('');
    setBuildSpaceText('');
    await refreshSuggestedWords();
    returnToSectionScan();
    bindKeyboardScanning();

    if (!waitForSwitchToScan) {
        startAuditoryScanning();
    }
}

initialize();