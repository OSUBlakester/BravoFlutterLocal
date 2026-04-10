// --- Compose Create Page JavaScript ---
// Purpose-built composition experience: Categories + Word Suggestions + Spelling
// Built on the same architecture as spelling.js

// ============================================================
// Scanning & Page State
// ============================================================

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

let currentSpellingWord = '';
let currentBuildSpaceText = '';
let currentPredictions = [];
let currentCategory = null;
let activeTool = null;
let topLevelCategories = [];
let categoryNavigationStack = [];
let currentNumberRange = null;
let currentNumberPageOffset = 0;
let currentNumberBase = 0;
let lastAnnouncedSpellingWord = '';
let availableCompletedSpellingWord = '';
let spellingPriorityMode = 'none';

let announcementQueue = [];
let isAnnouncingNow = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;
let pendingScanPromptTimer = null;
let pendingScanPromptToken = 0;
let lastScanPromptText = '';
let lastScanPromptTime = 0;
let scanCycleCount = 0;
let scanLoopLimit = 0;
let isPausedFromScanLimit = false;

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
        } catch (error) {
            // no-op
        }
        try {
            activeAnnouncementAudioSource.disconnect();
        } catch (error) {
            // no-op
        }
        activeAnnouncementAudioSource = null;
    }

    if (activeAnnouncementAudioContext && activeAnnouncementAudioContext.state !== 'closed') {
        activeAnnouncementAudioContext.close().catch(() => {});
    }
    activeAnnouncementAudioContext = null;
}

// ============================================================
// Compose Session Keys (same as gridpage.js / spelling.js)
// ============================================================

const COMPOSE_SESSION_STORAGE_KEY = 'bravoComposeSession';
const COMPOSE_PENDING_APPEND_KEY = 'bravoComposePendingAppend';
const SPEECH_HISTORY_LOCAL_STORAGE_KEY = (aacUserId) => `speechHistory_${aacUserId}`;
const NUMBER_RANGE_SIZE = 100;
const NUMBER_PAGE_SIZE = 20;
const NUMBER_TOOL_EXPANSIONS = [1000, 10000, 100000, 1000000];

// ============================================================
// DOM References
// ============================================================

const currentWordInput = document.getElementById('current-word');
const alphabetGrid = document.getElementById('alphabet-grid');
const predictionsGrid = document.getElementById('word-predictions');
const categoryGridEl = document.getElementById('category-grid');
const toolPanelSection = document.getElementById('tool-panel-section');
const categoryPanel = document.getElementById('category-panel');
const lettersPanel = document.getElementById('letters-panel');
const toolPanelTitle = document.getElementById('tool-panel-title');

// ============================================================
// Compose Session Helpers
// ============================================================

function loadComposeSession() {
    try {
        const parsed = JSON.parse(sessionStorage.getItem(COMPOSE_SESSION_STORAGE_KEY) || '{}');
        if (!parsed || typeof parsed !== 'object') {
            return { active: false, documentId: null, title: '', text: '', startedAt: null, sourceFrom: null };
        }
        return {
            active: parsed.active === true,
            documentId: parsed.documentId || null,
            title: parsed.title || '',
            text: typeof parsed.text === 'string' ? parsed.text : '',
            startedAt: parsed.startedAt || null,
            sourceFrom: parsed.sourceFrom || null
        };
    } catch (error) {
        console.warn('Failed to parse compose session in compose_create:', error);
        return { active: false, documentId: null, title: '', text: '', startedAt: null, sourceFrom: null };
    }
}

function saveComposeSession(session) {
    if (!session) return;
    sessionStorage.setItem(COMPOSE_SESSION_STORAGE_KEY, JSON.stringify(session));
}

function syncBuildSpaceToComposeSession() {
    const composedText = getCombinedBuildText().trimEnd();

    const session = loadComposeSession();
    if (session.active) {
        session.text = composedText;
        saveComposeSession(session);
    }
}

// ============================================================
// Authenticated Fetch (mirrors spelling.js / gridpage.js)
// ============================================================

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

// ============================================================
// Settings
// ============================================================

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
        if (typeof settings.scanLoopLimit === 'number' && !Number.isNaN(settings.scanLoopLimit)) {
            scanLoopLimit = Math.max(0, Math.min(10, parseInt(settings.scanLoopLimit, 10)));
        } else {
            scanLoopLimit = 0;
        }
        if (waitForSwitchToScan) {
            window.waitingForInitialSwitch = true;
        }
    } catch (error) {
        console.error('Failed to load settings:', error);
    }
}

// ============================================================
// Audio
// ============================================================

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
        if (!AudioContextClass) throw new Error('Web Audio API not supported');

        const personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
        const systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';
        let targetOutputDeviceId = 'default';
        if (announcementType === 'personal') targetOutputDeviceId = personalSpeakerId;
        else if (announcementType === 'system') targetOutputDeviceId = systemSpeakerId;

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

async function announce(textToAnnounce, announcementType = 'system', recordHistory = true, showSplash = true, useSystemVoice = false) {
    if (!textToAnnounce || !textToAnnounce.trim()) return;

    announcementQueue.push({ textToAnnounce: textToAnnounce.trim(), announcementType, recordHistory, showSplash, useSystemVoice });
    if (isAnnouncingNow) return;

    isAnnouncingNow = true;
    while (announcementQueue.length > 0) {
        const { textToAnnounce: text, announcementType: target, showSplash: shouldShowSplash, useSystemVoice: useSystemVoiceForRequest } = announcementQueue.shift();
        try {
            if (typeof showSplashScreen === 'function' && shouldShowSplash !== false) {
                showSplashScreen(text);
            }
            const response = await authenticatedFetch('/play-audio', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    text,
                    routing_target: target === 'personal' ? 'personal' : 'system',
                    use_system_voice: useSystemVoiceForRequest === true
                })
            });
            if (!response.ok) throw new Error(`Audio synthesis failed: ${response.status}`);
            const jsonResponse = await response.json();
            const audioData = jsonResponse.audio_data;
            if (audioData) {
                const buf = base64ToArrayBuffer(audioData);
                await playAudioToDevice(buf, jsonResponse.sample_rate, target);
            }
        } catch (error) {
            console.error('Error during announce:', error);
        }
    }
    isAnnouncingNow = false;
}

async function speak(textToSpeak) {
    return announce(textToSpeak, 'personal', false, false);
}

async function cleanupTextValue(text) {
    const trimmed = String(text || '').trim();
    if (!trimmed) {
        return '';
    }

    const response = await authenticatedFetch('/api/freestyle/cleanup-text', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text_to_cleanup: trimmed })
    });

    if (!response.ok) {
        const errorText = await response.text().catch(() => 'cleanup failed');
        throw new Error(errorText);
    }

    const data = await response.json();
    return String(data.cleaned_text || trimmed).trim();
}

// ============================================================
// Build Space
// ============================================================

function getCombinedBuildText() {
    const baseText = String(currentBuildSpaceText || '');
    const spellingWord = String(currentSpellingWord || '').trim();

    if (!spellingWord) {
        return baseText;
    }

    if (!baseText) {
        return spellingWord;
    }

    return /[\s\n]$/.test(baseText) ? `${baseText}${spellingWord}` : `${baseText} ${spellingWord}`;
}

function isStartingNewSentence() {
    const buildText = String(currentBuildSpaceText || '');
    if (currentSpellingWord) {
        return false;
    }
    if (!buildText.trim()) {
        return true;
    }
    return /\n\s*$/.test(buildText);
}

function getSentenceStarterFallbackWords() {
    return ['I', 'It', 'The', 'We', 'Then', 'Also', 'After', 'Next', 'Later', 'They']
        .slice(0, Math.max(1, LLMOptions));
}

function updateBuildSpaceInput() {
    currentWordInput.value = getCombinedBuildText();
}

function setBuildSpaceText(text) {
    currentBuildSpaceText = typeof text === 'string' ? text : '';
    updateBuildSpaceInput();
}

function appendWordToBuildSpace(word) {
    const cleanWord = (word || '').trim();
    if (!cleanWord) return;
    const nextText = currentBuildSpaceText
        ? /[\s\n]$/.test(currentBuildSpaceText)
            ? `${currentBuildSpaceText}${cleanWord}`
            : `${currentBuildSpaceText} ${cleanWord}`
        : cleanWord;
    setBuildSpaceText(nextText);
    syncBuildSpaceToComposeSession();
}

async function clearBuildSpace() {
    currentBuildSpaceText = '';
    currentSpellingWord = '';
    lastAnnouncedSpellingWord = '';
    availableCompletedSpellingWord = '';
    updateBuildSpaceInput();
    renderSpellingActionButtons();
    currentPredictions = [];
    renderWordPredictions();
    updateLetterAvailability('');
    syncBuildSpaceToComposeSession();
    await refreshSuggestedWords();
}

function removeLastWordUnit(text) {
    const value = String(text || '');
    if (!value) {
        return '';
    }

    const trimmedEnd = value.replace(/\s+$/g, '');
    if (!trimmedEnd) {
        return '';
    }

    return trimmedEnd.replace(/\s*\S+$/g, '');
}

async function backspaceCurrentWord() {
    if (currentSpellingWord.length > 0) {
        currentSpellingWord = '';
        lastAnnouncedSpellingWord = '';
        availableCompletedSpellingWord = '';
        updateBuildSpaceInput();
        renderSpellingActionButtons();
        updateLetterAvailability(currentSpellingWord);
        await refreshSuggestedWords();
        if (activeTool === 'spelling') {
            restartScanningInSection('tool-panel', 250);
        } else {
            restartScanning(250, true);
        }
        return;
    }
    if (!currentBuildSpaceText) return;
    const nextText = removeLastWordUnit(currentBuildSpaceText);
    setBuildSpaceText(nextText);
    syncBuildSpaceToComposeSession();
    await refreshSuggestedWords();
    if (activeTool === 'spelling') {
        restartScanningInSection('tool-panel', 250);
    } else {
        restartScanning(250, true);
    }
}

function clearCurrentSpellingWord() {
    currentSpellingWord = '';
    lastAnnouncedSpellingWord = '';
    availableCompletedSpellingWord = '';
    updateBuildSpaceInput();
    renderSpellingActionButtons();
}

function ensureTerminalPunctuation(text) {
    const trimmed = String(text || '').trim();
    if (!trimmed) {
        return '';
    }
    if (/[.!?]$/.test(trimmed)) {
        return trimmed;
    }

    const normalized = trimmed
        .replace(/["'`]+/g, '')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase();
    const words = normalized.split(' ').filter(Boolean);
    const firstWord = words[0] || '';
    const firstTwoWords = words.slice(0, 2).join(' ');

    const questionStarters = new Set([
        'who', 'what', 'when', 'where', 'why', 'how',
        'do', 'does', 'did', 'can', 'could', 'would', 'will', 'should',
        'is', 'are', 'am', 'was', 'were', 'have', 'has', 'had',
        'may', 'might'
    ]);

    const exclamationStarters = new Set([
        'wow', 'oh', 'oops', 'yay', 'hurray', 'hooray', 'ouch', 'hey'
    ]);

    const multiWordQuestionStarters = new Set([
        'do you', 'did you', 'can you', 'could you', 'would you',
        'will you', 'are you', 'is it', 'is that', 'have you', 'has it'
    ]);

    const multiWordExclamations = new Set([
        'watch out', 'look out'
    ]);

    if (multiWordQuestionStarters.has(firstTwoWords) || questionStarters.has(firstWord)) {
        return `${trimmed}?`;
    }

    if (multiWordExclamations.has(firstTwoWords) || exclamationStarters.has(firstWord)) {
        return `${trimmed}!`;
    }

    return `${trimmed}.`;
}

function exitCreation() {
    stopAuditoryScanning();
    // Commit any in-progress spelling word before exiting
    if (currentSpellingWord) {
        appendWordToBuildSpace(currentSpellingWord);
        currentSpellingWord = '';
    }
    syncBuildSpaceToComposeSession();
    window.location.href = '/static/gridpage.html?compose_finalize=1';
}

async function readCreation() {
    const text = getCombinedBuildText().trim();
    if (!text) {
        await announce('Creation is empty.', 'system', false, true);
        return;
    }
    stopAuditoryScanning();
    await announce(text, 'system', false, true);
    restartScanning(250, true);
}

async function aiEditCreation() {
    const text = getCombinedBuildText().trim();
    if (!text) {
        await announce('Creation is empty.', 'system', false, true);
        return;
    }

    stopAuditoryScanning();
    try {
        const cleaned = await cleanupTextValue(text);
        currentSpellingWord = '';
        setBuildSpaceText(cleaned);
        syncBuildSpaceToComposeSession();
        await refreshSuggestedWords();
        await announce(cleaned || 'Creation is empty.', 'system', false, true);
    } catch (error) {
        console.error('AI edit failed:', error);
        await announce('Unable to AI edit right now.', 'system', false, true);
    }
    restartScanning(250, true);
}

async function newRow() {
    const text = getCombinedBuildText().trimEnd();
    if (!text) {
        await announce('Creation is empty.', 'system', false, true);
        return;
    }

    stopAuditoryScanning();

    try {
        const lines = text.split(/\n/);
        const lastLine = lines.pop() || '';
        const finalizedLine = ensureTerminalPunctuation(lastLine);
        const rebuiltText = lines.length > 0
            ? `${lines.join('\n')}\n${finalizedLine}\n`
            : `${finalizedLine}\n`;

        currentSpellingWord = '';
        setBuildSpaceText(rebuiltText);
        currentCategory = null;
        setActiveCategoryButton('General');
        setActiveTool(null);
        syncBuildSpaceToComposeSession();
        await refreshSuggestedWords();
        await announce('Started new row.', 'system', false, true);
    } catch (error) {
        console.error('New row failed:', error);
        await announce('Unable to start a new row right now.', 'system', false, true);
    }

    restartScanning(250, true);
}

function goBackToSectionScanning() {
    restartScanning(150, true);
}

// ============================================================
// Categories
// ============================================================

// Special-function buttons that are navigation/feature shortcuts, not content categories
const SKIP_SPECIAL_FUNCTIONS = new Set(['spell', 'games', 'goto_home', 'navigate']);
const EXCLUDED_COMPOSE_CATEGORY_LABELS = new Set(['entertainment', 'numbers']);
const NON_NESTED_CATEGORY_LABELS = new Set(['greetings']);

function shouldIncludeCategoryNode(node) {
    if (!node || node.hidden) {
        return false;
    }
    const label = String(node.label || '').trim().toLowerCase();
    if (EXCLUDED_COMPOSE_CATEGORY_LABELS.has(label)) {
        return false;
    }
    const sf = String(node.special_function || '').toLowerCase();
    if (SKIP_SPECIAL_FUNCTIONS.has(sf)) {
        return false;
    }
    return true;
}

function getVisibleCategoryChildren(node) {
    return Array.isArray(node?.children) ? node.children.filter(shouldIncludeCategoryNode) : [];
}

function canDrillIntoCategory(node) {
    const label = String(node?.label || '').trim().toLowerCase();
    if (NON_NESTED_CATEGORY_LABELS.has(label)) {
        return false;
    }
    return getVisibleCategoryChildren(node).length > 0;
}

function getCurrentCategoryNodes() {
    if (!categoryNavigationStack.length) {
        return topLevelCategories;
    }
    return getVisibleCategoryChildren(categoryNavigationStack[categoryNavigationStack.length - 1]);
}

function updateCategoryPanelHeading() {
    if (activeTool === 'numbers') {
        toolPanelTitle.textContent = 'Numbers';
        return;
    }

    if (activeTool !== 'categories') {
        return;
    }
    if (!categoryNavigationStack.length) {
        toolPanelTitle.textContent = 'Word Categories';
        return;
    }
    const pathLabel = categoryNavigationStack.map((node) => node.label).join(' / ');
    toolPanelTitle.textContent = `Word Categories — ${pathLabel}`;
}

function buildNumberRanges(maxNumber) {
    const ranges = [];
    let start = currentNumberBase;
    const finalEnd = currentNumberBase + maxNumber;
    while (start <= finalEnd) {
        const end = Math.min(start === currentNumberBase ? currentNumberBase + NUMBER_RANGE_SIZE : start + (NUMBER_RANGE_SIZE - 1), finalEnd);
        ranges.push({
            start,
            end,
            label: `${start.toLocaleString()}-${end.toLocaleString()}`
        });
        start = end + 1;
    }
    return ranges;
}

function getCurrentNumberPageValues() {
    if (!currentNumberRange) {
        return [];
    }
    const start = currentNumberRange.start + (currentNumberPageOffset * NUMBER_PAGE_SIZE);
    if (start > currentNumberRange.end) {
        return [];
    }
    const end = Math.min(start + NUMBER_PAGE_SIZE - 1, currentNumberRange.end);
    const values = [];
    for (let value = start; value <= end; value++) {
        values.push(String(value));
    }
    return values;
}

function hasMoreNumberPageValues() {
    if (!currentNumberRange) {
        return false;
    }
    return currentNumberRange.start + ((currentNumberPageOffset + 1) * NUMBER_PAGE_SIZE) <= currentNumberRange.end;
}

function renderNumbersToolPanel() {
    categoryGridEl.innerHTML = '';
    updateCategoryPanelHeading();

    buildNumberRanges(1000).forEach((range) => {
        const btn = document.createElement('button');
        btn.className = 'category-btn compose-button';
        btn.textContent = range.label;
        btn.addEventListener('click', async () => {
            currentCategory = null;
            currentNumberRange = range;
            currentNumberPageOffset = 0;
            updateWordsSectionTitle();
            currentPredictions = getCurrentNumberPageValues();
            renderWordPredictions();
            focusWordOptionsScanning(150);
        });
        categoryGridEl.appendChild(btn);
    });

    NUMBER_TOOL_EXPANSIONS.forEach((increment) => {
        const addButton = document.createElement('button');
        addButton.className = 'category-btn compose-button';
        addButton.textContent = `Add ${increment.toLocaleString()}`;
        addButton.addEventListener('click', () => {
            currentNumberBase += increment;
            currentNumberRange = null;
            currentNumberPageOffset = 0;
            renderNumbersToolPanel();
            restartScanningInSection('tool-panel', 150);
        });
        categoryGridEl.appendChild(addButton);
    });

    const resetButton = document.createElement('button');
    resetButton.className = 'category-btn compose-button';
    resetButton.textContent = 'Reset to 0';
    resetButton.addEventListener('click', () => {
        currentNumberBase = 0;
        currentNumberRange = null;
        currentNumberPageOffset = 0;
        renderNumbersToolPanel();
        restartScanningInSection('tool-panel', 150);
    });
    categoryGridEl.appendChild(resetButton);

    const goBackButton = document.createElement('button');
    goBackButton.className = 'category-btn compose-button';
    goBackButton.textContent = 'Go Back';
    goBackButton.addEventListener('click', () => {
        closeActiveTool();
    });
    categoryGridEl.appendChild(goBackButton);
}

function setActiveCategoryButton(label) {
    document.querySelectorAll('.category-btn').forEach((btn) => {
        btn.classList.toggle('active-category', Boolean(label) && btn.dataset.categoryLabel === label);
    });
}

function updateWordsSectionTitle() {
    const wordsTitleEl = document.getElementById('words-section-title');
    if (!wordsTitleEl) return;
    if (currentNumberRange) {
        const pageValues = getCurrentNumberPageValues();
        if (pageValues.length > 0) {
            wordsTitleEl.textContent = `Words — ${pageValues[0]}-${pageValues[pageValues.length - 1]}`;
            return;
        }
        wordsTitleEl.textContent = `Words — ${currentNumberRange.label}`;
        return;
    }
    wordsTitleEl.textContent = currentCategory ? `Words — ${currentCategory.label}` : 'Suggested Words';
}

function setActiveTool(toolName) {
    activeTool = toolName;
    toolPanelSection.hidden = !toolName;
    categoryPanel.hidden = toolName !== 'categories' && toolName !== 'numbers';
    lettersPanel.hidden = toolName !== 'spelling';
    toolPanelTitle.textContent = toolName === 'spelling' ? 'Spelling' : 'Word Categories';

    document.querySelectorAll('.tool-select-btn').forEach((btn) => {
        btn.classList.toggle('active-tool', btn.dataset.tool === toolName);
    });

    if (!toolName) {
        lettersScanPhase = 'rows';
        activeLetterRowIndex = null;
        return;
    }

    if (toolName === 'categories' || toolName === 'numbers') {
        updateCategoryPanelHeading();
    }

    toolPanelSection.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function openTool(toolName) {
    if (toolName === 'categories') {
        renderCurrentCategoryPanel();
    } else if (toolName === 'numbers') {
        renderNumbersToolPanel();
    }
    setActiveTool(toolName);
    restartScanningInSection('tool-panel', 150);
}

function closeActiveTool() {
    setActiveTool(null);
    restartScanning(150, true);
}

function focusWordOptionsScanning(delayMs = 0) {
    stopAuditoryScanning();
    setTimeout(() => {
        if (waitForSwitchToScan && window.waitingForInitialSwitch) {
            return;
        }
        activeSectionId = 'choose-word';
        currentScanLevel = 'items';
        currentButtonIndex = -1;
        startAuditoryScanning();
    }, delayMs);
}

function restartScanningInSection(sectionId, delayMs = 0) {
    stopAuditoryScanning();
    setTimeout(() => {
        if (waitForSwitchToScan && window.waitingForInitialSwitch) {
            return;
        }
        activeSectionId = sectionId;
        currentScanLevel = 'items';
        currentButtonIndex = -1;
        if (sectionId === 'tool-panel' && activeTool === 'spelling') {
            lettersScanPhase = 'rows';
            activeLetterRowIndex = null;
        }
        startAuditoryScanning();
    }, delayMs);
}

function restartSpellingWithActionPriority(delayMs = 0) {
    const actionButton = Array.from(document.querySelectorAll('.letter-btn')).find((button) => button.dataset.chooseWordOption === 'true')
        || Array.from(document.querySelectorAll('.letter-btn')).find((button) => button.dataset.standardOption === 'true');
    const actionRowIndex = actionButton ? Number(actionButton.dataset.rowIndex) : null;

    if (actionRowIndex === null || Number.isNaN(actionRowIndex)) {
        restartScanningInSection('tool-panel', delayMs);
        return;
    }

    stopAuditoryScanning();
    setTimeout(() => {
        if (waitForSwitchToScan && window.waitingForInitialSwitch) return;
        activeSectionId = 'tool-panel';
        currentScanLevel = 'items';
        lettersScanPhase = 'items';
        activeLetterRowIndex = actionRowIndex;
        currentButtonIndex = -1;
        spellingPriorityMode = 'action-options-once';
        startAuditoryScanning();
    }, delayMs);
}

async function loadCategories() {
    try {
        const response = await authenticatedFetch('/api/tap-interface/config');
        if (!response.ok) {
            renderCategoryFallback();
            return;
        }
        const config = await response.json();
        const buttons = Array.isArray(config.buttons) ? config.buttons : [];
        topLevelCategories = buttons.filter(shouldIncludeCategoryNode);
        categoryNavigationStack = [];
        renderCurrentCategoryPanel();
    } catch (error) {
        console.error('Failed to load categories:', error);
        renderCategoryFallback();
    }
}

function renderCategoryFallback() {
    topLevelCategories = [
        { label: 'Greetings', prompt_category: 'greetings', children: [] },
        {
            label: 'Ask',
            prompt_category: 'ask',
            llm_prompt: 'Generate AAC-friendly starters, words, and short phrases for asking questions or making requests. When starting a sentence, strongly prefer natural openings like Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is.',
            children: [
                {
                    label: 'Question',
                    prompt_category: 'questions',
                    llm_prompt: 'Generate question words and short AAC-friendly question phrases for asking about people, things, places, needs, choices, feelings, and preferences',
                    children: []
                },
                {
                    label: 'Request',
                    prompt_category: 'requests',
                    llm_prompt: 'Generate AAC-friendly request starters, request words, and short request phrases for asking for help, objects, actions, comfort, food, drinks, and assistance. When starting a sentence, strongly prefer natural request openings like Can, Could, May, Will, Would, Please, I need, and I want.',
                    children: []
                }
            ]
        },
        {
            label: 'Respond',
            prompt_category: 'respond',
            llm_prompt: 'Generate AAC-friendly response starters, words, and short phrases for responding to a question or request. When starting a sentence, strongly prefer natural response openings like Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now.',
            children: []
        },
        { label: 'People', prompt_category: 'people', children: [] },
        { label: 'Places', prompt_category: 'places', children: [] },
        { label: 'Things', prompt_category: 'things', children: [] },
        { label: 'Actions', prompt_category: 'actions', children: [] },
        { label: 'Describe', prompt_category: 'describe', children: [] },
        { label: 'Animals', prompt_category: 'animals', children: [] }
    ];
    categoryNavigationStack = [];
    renderCurrentCategoryPanel();
}

function renderCurrentCategoryPanel() {
    const categories = getCurrentCategoryNodes();
    const parentNode = categoryNavigationStack.length ? categoryNavigationStack[categoryNavigationStack.length - 1] : null;

    categoryGridEl.innerHTML = '';
    updateCategoryPanelHeading();

    if (!parentNode) {
        const generalButton = document.createElement('button');
        generalButton.className = 'category-btn compose-button';
        generalButton.textContent = 'General';
        generalButton.dataset.categoryLabel = 'General';
        generalButton.addEventListener('click', async () => {
            currentCategory = null;
            setActiveCategoryButton('General');
            updateWordsSectionTitle();
            await refreshSuggestedWords();
            focusWordOptionsScanning(150);
        });
        categoryGridEl.appendChild(generalButton);
    } else {
        const allParentButton = document.createElement('button');
        allParentButton.className = 'category-btn compose-button';
        allParentButton.textContent = `All ${parentNode.label}`;
        allParentButton.dataset.categoryLabel = parentNode.label || '';
        allParentButton.addEventListener('click', async () => {
            await selectCategory(parentNode);
        });
        categoryGridEl.appendChild(allParentButton);
    }

    categories.forEach((cat) => {
        const btn = document.createElement('button');
        btn.className = 'category-btn compose-button';
        btn.textContent = cat.label || cat;
        btn.dataset.categoryLabel = cat.label || cat;
        btn.dataset.promptCategory = cat.prompt_category || (cat.label || cat).toLowerCase();
        btn.addEventListener('click', async () => {
            if (canDrillIntoCategory(cat)) {
                categoryNavigationStack.push(cat);
                renderCurrentCategoryPanel();
                restartScanningInSection('tool-panel', 150);
                return;
            }
            await selectCategory(cat);
        });
        categoryGridEl.appendChild(btn);
    });

    const goBackButton = document.createElement('button');
    goBackButton.className = 'category-btn compose-button';
    goBackButton.textContent = parentNode ? 'Back' : 'Go Back';
    goBackButton.addEventListener('click', () => {
        if (parentNode) {
            categoryNavigationStack.pop();
            renderCurrentCategoryPanel();
            restartScanningInSection('tool-panel', 150);
            return;
        }
        closeActiveTool();
    });
    categoryGridEl.appendChild(goBackButton);

    setActiveCategoryButton(currentCategory ? currentCategory.label : 'General');
}

async function selectCategory(cat) {
    const label = cat.label || String(cat);
    const promptCategory = cat.prompt_category || label.toLowerCase();
    const llmPrompt = String(cat.llm_prompt || '').trim();
    const wordsPrompt = String(cat.words_prompt || '').trim();

    currentCategory = {
        label,
        promptCategory,
        llmPrompt,
        wordsPrompt
    };
    setActiveCategoryButton(label);
    updateWordsSectionTitle();
    document.getElementById('choose-word-section')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

    await loadCategoryWords(currentCategory);
    focusWordOptionsScanning(150);
}

function getContextFreeGeneralPrompt() {
    if (isStartingNewSentence()) {
        return `The user has finished one sentence and is starting a NEW sentence or row.
Generate broadly useful AAC words or short phrases that are appropriate for the BEGINNING of the next sentence.

CRITICAL REQUIREMENTS:
- Treat the existing build space as prior context only, not as a sentence fragment to continue.
- Prioritize sentence starters, discourse starters, pronouns, articles, helper verbs, and common opening phrases.
- Good examples of the kind of options to prefer: "I", "It", "The", "We", "Then", "Also", "After that", "Next", "Later", "They".
- Avoid options that sound like they belong in the middle or end of the previous sentence.
- The new sentence can stay on the same topic, but it must read like the START of a sentence.
- Do not use the user's current location, people present, current activity, personal narrative, or any other live context.
- Keep the suggestions general, everyday, and reusable across settings.
- Avoid proper nouns unless they already appear in the current message.`;
    }

    return `Generate broadly useful AAC words or short phrases that naturally continue the current message being built.
Do not use the user's current location, people present, current activity, personal narrative, or any other live context.
Keep the suggestions general, everyday, and reusable across settings.
Avoid proper nouns unless they already appear in the current message.`;
}

function getContextFreeCategoryPrompt(categoryLabel) {
    if (isStartingNewSentence()) {
        return `The user has finished one sentence and is starting a NEW sentence or row.
Generate AAC-friendly words or short phrases for the category '${categoryLabel}' that are appropriate near the BEGINNING of a new sentence.

CRITICAL REQUIREMENTS:
- Treat the existing build space as prior context only, not as a sentence fragment to continue.
- Prefer category words or short phrases that can sensibly appear at the start of a sentence.
- Keep the new sentence connected to the overall topic, but make the options feel like sentence starters rather than mid-sentence continuations.
- Avoid options that read like they belong after several words have already been spoken in the new sentence.
- Do not use the user's current location, people present, current activity, personal narrative, or any other live context.
- Keep the suggestions category-appropriate, general, and useful across settings.`;
    }

    return `Generate AAC-friendly words or short phrases for the category '${categoryLabel}'.
Use only the current message being built to help decide what could naturally come next.
Do not use the user's current location, people present, current activity, personal narrative, or any other live context.
Keep the suggestions category-appropriate, general, and useful across settings.`;
}

function buildCategorySpecificPrompt(categorySelection) {
    const basePrompt = String(
        categorySelection?.wordsPrompt || categorySelection?.llmPrompt || ''
    ).trim();
    const promptCategory = String(categorySelection?.promptCategory || '').trim().toLowerCase();

    if (!basePrompt) {
        return getContextFreeCategoryPrompt(categorySelection?.label || '');
    }

    let sentenceStartInstruction = isStartingNewSentence()
        ? 'The user is starting a new sentence or row. Prefer options that can sensibly begin the next sentence while staying within the category intent.'
        : 'Use the current build space only to decide what could naturally come next within this category.';

    if (promptCategory === 'ask' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural question and request openings such as Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is. Avoid mid-sentence fragments.';
    }

    if (promptCategory === 'respond' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural response openings such as Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now. Avoid mid-sentence response fragments.';
    }

    if (promptCategory === 'requests' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural request openings and request starters such as Can, Could, May, Will, Would, Please, I need, and I want. Avoid mid-sentence request fragments.';
    }

    return `${basePrompt}

ADDITIONAL COMPOSE REQUIREMENTS:
- ${sentenceStartInstruction}
- Do not use the user's current location, people present, current activity, personal narrative, or any other live context unless the prompt above explicitly requires it.
- Keep the options useful for composition and AAC communication.
- Return words or short phrases only.`;
}

function getCategoryFallbackWords(categorySelection) {
    const promptCategory = String(categorySelection?.promptCategory || '').trim().toLowerCase();

    if (promptCategory === 'ask') {
        if (isStartingNewSentence()) {
            return ['Can', 'Could', 'Please', 'What', 'Where', 'Why', 'How', 'May']
                .slice(0, Math.max(1, LLMOptions));
        }
        return ['can', 'please', 'what', 'where', 'why', 'how', 'need', 'want']
            .slice(0, Math.max(1, LLMOptions));
    }

    if (promptCategory === 'respond') {
        if (isStartingNewSentence()) {
            return ['Yes', 'No', 'Okay', 'Sure', 'Maybe', 'I can', 'Thank you', 'Not right now']
                .slice(0, Math.max(1, LLMOptions));
        }
        return ['yes', 'no', 'okay', 'sure', 'maybe', 'thanks', 'can', 'cannot']
            .slice(0, Math.max(1, LLMOptions));
    }

    if (promptCategory === 'requests') {
        if (isStartingNewSentence()) {
            return ['Can', 'Could', 'May', 'Will', 'Would', 'Please', 'I need', 'I want']
                .slice(0, Math.max(1, LLMOptions));
        }
        return ['please', 'help', 'want', 'need', 'can', 'could', 'more', 'stop']
            .slice(0, Math.max(1, LLMOptions));
    }

    if (promptCategory === 'questions') {
        if (isStartingNewSentence()) {
            return ['Can', 'What', 'Where', 'Who', 'Why', 'How', 'When', 'Do']
                .slice(0, Math.max(1, LLMOptions));
        }
        return ['what', 'where', 'who', 'why', 'how', 'when', 'is', 'do']
            .slice(0, Math.max(1, LLMOptions));
    }

    return [];
}

async function requestCategoryWords(category, customPrompt, fallbackWords = []) {
    return requestCategoryWordsWithExclusions(category, customPrompt, fallbackWords, []);
}

async function requestCategoryWordsWithExclusions(category, customPrompt, fallbackWords = [], excludeWords = []) {
    const buildSpaceContent = getCombinedBuildText().trim();

    try {
        const response = await authenticatedFetch('/api/freestyle/category-words', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category,
                build_space_content: buildSpaceContent,
                exclude_words: excludeWords,
                custom_prompt: customPrompt
            })
        });
        if (!response.ok) {
            currentPredictions = fallbackWords;
            renderWordPredictions();
            return false;
        }
        const data = await response.json();
        const rawWords = data.words || [];
        const nextWords = rawWords
            .map((w) => (typeof w === 'object' && w.text ? w.text : w))
            .filter((w) => typeof w === 'string' && w.trim() !== '')
            .slice(0, Math.max(1, LLMOptions));
        currentPredictions = nextWords.length > 0 ? nextWords : fallbackWords;
        renderWordPredictions();
        return nextWords.length > 0;
    } catch (error) {
        console.error('Error loading category words:', error);
        currentPredictions = fallbackWords;
        renderWordPredictions();
        return false;
    }
}

async function loadGeneralWords(excludeWords = [], fallbackWordsOverride = null) {
    const fallbackWords = isStartingNewSentence()
        ? getSentenceStarterFallbackWords()
        : ['I', 'want', 'to', 'go', 'more', 'help', 'with', 'and', 'the', 'it']
            .slice(0, Math.max(1, LLMOptions));
    return requestCategoryWordsWithExclusions(
        'general',
        getContextFreeGeneralPrompt(),
        fallbackWordsOverride || fallbackWords,
        excludeWords
    );
}

async function loadCategoryWords(categorySelection, excludeWords = [], fallbackWordsOverride = null) {
    if (!categorySelection) {
        return loadGeneralWords(excludeWords, fallbackWordsOverride);
    }

    const fallbackWords = fallbackWordsOverride || getCategoryFallbackWords(categorySelection);

    return requestCategoryWordsWithExclusions(
        categorySelection.promptCategory,
        buildCategorySpecificPrompt(categorySelection),
        fallbackWords,
        excludeWords
    );
}

// ============================================================
// Word Predictions
// ============================================================

async function getWordPredictionsForSpelling() {
    try {
        const response = await authenticatedFetch('/api/freestyle/word-prediction', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                text: currentBuildSpaceText || '',
                spelling_word: currentSpellingWord || '',
                predict_full_words: true
            })
        });
        if (response.ok) {
            const data = await response.json();
            const predictions = (data.predictions || []).slice(0, Math.max(1, LLMOptions));
            currentPredictions = predictions;
            const normalizedSpellingWord = String(currentSpellingWord || '').trim().toLowerCase();
            if (normalizedSpellingWord) {
                const exactMatch = predictions.find((prediction) => String(prediction || '').trim().toLowerCase() === normalizedSpellingWord);
                renderWordPredictions();
                return exactMatch || null;
            }
        } else {
            currentPredictions = [];
        }
    } catch (error) {
        console.error('Error getting spelling predictions:', error);
        currentPredictions = [];
    }
    renderWordPredictions();
    return null;
}

async function refreshSuggestedWords() {
    if (currentSpellingWord) {
        return getWordPredictionsForSpelling();
    }
    if (currentNumberRange) {
        currentPredictions = getCurrentNumberPageValues();
        renderWordPredictions();
        return null;
    }
    if (currentCategory) {
        await loadCategoryWords(currentCategory);
        return null;
    }
    await loadGeneralWords();
    return null;
}

async function loadSomethingElseOptions() {
    if (currentSpellingWord) {
        await announce('Something Else is not available while spelling.', 'system', false, true);
        restartScanning(250, false);
        return;
    }

    if (currentNumberRange) {
        stopAuditoryScanning();
        if (hasMoreNumberPageValues()) {
            currentNumberPageOffset += 1;
            currentPredictions = getCurrentNumberPageValues();
            updateWordsSectionTitle();
            renderWordPredictions();
        } else {
            await announce('No more numbers in this range.', 'system', false, true);
        }
        focusWordOptionsScanning(150);
        return;
    }

    const existingOptions = currentPredictions
        .map((word) => String(word || '').trim())
        .filter(Boolean);

    stopAuditoryScanning();

    let didLoadNewWords = false;
    if (currentCategory) {
        didLoadNewWords = await loadCategoryWords(currentCategory, existingOptions, existingOptions);
    } else {
        didLoadNewWords = await loadGeneralWords(existingOptions, existingOptions);
    }

    if (!didLoadNewWords) {
        await announce('I could not find other word options.', 'system', false, true);
    }

    focusWordOptionsScanning(150);
}

function renderWordPredictions() {
    predictionsGrid.classList.toggle('numbers-mode', Boolean(currentNumberRange));
    predictionsGrid.innerHTML = '';
    currentPredictions.forEach((word) => {
        const button = document.createElement('button');
        button.className = 'prediction-btn compose-button';
        button.textContent = word;
        button.addEventListener('click', () => handlePredictionClick(word));
        predictionsGrid.appendChild(button);
    });

    if (!currentSpellingWord) {
        const somethingElseButton = document.createElement('button');
        somethingElseButton.className = 'prediction-btn compose-button';
        somethingElseButton.textContent = 'Something Else';
        somethingElseButton.dataset.standardOption = 'true';
        somethingElseButton.addEventListener('click', async () => {
            await loadSomethingElseOptions();
        });
        predictionsGrid.appendChild(somethingElseButton);
    }

    const goBackButton = document.createElement('button');
    goBackButton.className = 'prediction-btn compose-button';
    goBackButton.textContent = 'Go Back';
    goBackButton.dataset.standardOption = 'true';
    goBackButton.addEventListener('click', () => {
        restartScanning(120, true);
    });
    predictionsGrid.appendChild(goBackButton);

    const totalButtons = predictionsGrid.querySelectorAll('.prediction-btn').length;
    const wordGridColumns = Math.max(4, Math.ceil(totalButtons / 2));
    predictionsGrid.style.setProperty('--word-grid-columns', String(wordGridColumns));
    predictionsGrid.classList.toggle('compact-grid', wordGridColumns >= 7);
    predictionsGrid.classList.toggle('ultra-compact-grid', wordGridColumns >= 8);
}

async function handlePredictionClick(word) {
    stopAuditoryScanning();
    await announce(word, 'system', false, true);
    appendWordToBuildSpace(word);
    clearCurrentSpellingWord();
    updateLetterAvailability('');

    // A selected category acts as a temporary prompt for the next choice.
    // Once a word is chosen, return to general continuation suggestions
    // based on the full current Build Space.
    currentCategory = null;
    currentNumberRange = null;
    currentNumberPageOffset = 0;
    setActiveCategoryButton('General');
    updateWordsSectionTitle();

    await refreshSuggestedWords();
    focusWordOptionsScanning(300);
}

// ============================================================
// Alphabet Grid
// ============================================================

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
                button.className = 'letter-btn compose-button';
                button.textContent = letter;
                button.dataset.letter = letter;
                button.dataset.rowIndex = String(rowIndex);
                button.addEventListener('click', () => handleLetterClick(letter));
                if (rowIndex === 1 && colIndex === 0) button.style.marginLeft = '5%';
                if (rowIndex === 2 && colIndex === 0) button.style.gridColumn = '2 / span 1';
                alphabetGrid.appendChild(button);
            });
        });
        renderSpellingActionButtons();
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
        button.className = 'letter-btn compose-button';
        button.textContent = letter;
        button.dataset.letter = letter;
        button.dataset.rowIndex = String(Math.floor(index / 7));
        button.addEventListener('click', () => handleLetterClick(letter));
        alphabetGrid.appendChild(button);
    });

    renderSpellingActionButtons();
}

function getSpellingActionRowIndex() {
    const existingRows = Array.from(alphabetGrid.querySelectorAll('.letter-btn'))
        .filter((button) => button.dataset.standardOption !== 'true')
        .map((button) => Number(button.dataset.rowIndex))
        .filter((row) => !Number.isNaN(row));
    const maxRow = existingRows.length ? Math.max(...existingRows) : 0;
    return maxRow + 1;
}

function renderSpellingActionButtons() {
    Array.from(alphabetGrid.querySelectorAll('.letter-btn'))
        .filter((button) => button.dataset.standardOption === 'true')
        .forEach((button) => button.remove());

    const actionRowIndex = getSpellingActionRowIndex();

    if (availableCompletedSpellingWord) {
        const chooseWordButton = document.createElement('button');
        chooseWordButton.className = 'letter-btn compose-button';
        chooseWordButton.textContent = 'Choose Word';
        chooseWordButton.dataset.standardOption = 'true';
        chooseWordButton.dataset.chooseWordOption = 'true';
        chooseWordButton.dataset.rowIndex = String(actionRowIndex);
        chooseWordButton.addEventListener('click', () => {
            chooseCurrentSpellingWord().catch((error) => {
                console.error('Failed to choose completed spelling word:', error);
            });
        });
        alphabetGrid.appendChild(chooseWordButton);
    }

    const goBackButton = document.createElement('button');
    goBackButton.className = 'letter-btn compose-button';
    goBackButton.textContent = 'Go Back';
    goBackButton.dataset.standardOption = 'true';
    goBackButton.dataset.rowIndex = String(actionRowIndex);
    goBackButton.addEventListener('click', () => {
        closeActiveTool();
    });
    alphabetGrid.appendChild(goBackButton);
}

async function chooseCurrentSpellingWord() {
    const chosenWord = String(availableCompletedSpellingWord || currentSpellingWord || '').trim();
    if (!chosenWord) {
        restartScanningInSection('tool-panel', 150);
        return;
    }

    stopAuditoryScanning();
    await announce(chosenWord, 'system', false, true);

    const nextText = currentBuildSpaceText
        ? /[\s\n]$/.test(currentBuildSpaceText)
            ? `${currentBuildSpaceText}${chosenWord} `
            : `${currentBuildSpaceText} ${chosenWord} `
        : `${chosenWord} `;

    currentSpellingWord = '';
    lastAnnouncedSpellingWord = '';
    availableCompletedSpellingWord = '';
    setBuildSpaceText(nextText);
    syncBuildSpaceToComposeSession();
    renderSpellingActionButtons();
    updateLetterAvailability('');
    await refreshSuggestedWords();
    restartScanning(250, true);
}

async function handleLetterClick(letter) {
    currentSpellingWord += letter.toLowerCase();
    updateBuildSpaceInput();
    updateLetterAvailability(currentSpellingWord);
    const completedWord = await refreshSuggestedWords();
    if (completedWord) {
        const normalizedCompletedWord = String(completedWord || '').trim().toLowerCase();
        availableCompletedSpellingWord = String(completedWord || '').trim();
        renderSpellingActionButtons();
        if (normalizedCompletedWord && normalizedCompletedWord !== lastAnnouncedSpellingWord) {
            lastAnnouncedSpellingWord = normalizedCompletedWord;
            stopAuditoryScanning();
            await announce(completedWord, 'system', false, true);
            restartSpellingWithActionPriority(250);
            return;
        }
    } else {
        lastAnnouncedSpellingWord = '';
        availableCompletedSpellingWord = '';
        renderSpellingActionButtons();
    }
    restartScanningInSection('tool-panel', 250);
}

// ============================================================
// Letter Availability
// ============================================================

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

    if (currentWord.length >= 4) return 'ABCDEFGHIKLMNOPRSTUVWYZ'.split('');
    if (currentWord.length >= 2 && likelyAfterTwoLetters[lastTwoChars]) return likelyAfterTwoLetters[lastTwoChars];
    if (likelyAfter[lastChar]) return likelyAfter[lastChar];
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

// ============================================================
// Scanning (4 sections: action, tool-toggle, choose-word, tool-panel)
// ============================================================

function getVisibleEnabledButtons(selector) {
    return Array.from(document.querySelectorAll(selector)).filter((button) => {
        return button.offsetParent !== null && !button.disabled;
    });
}

function getSectionButtonsInOrder() {
    const orderedIds = ['action-section', 'choose-word-section', 'tool-toggle-section', 'tool-panel-section'];
    return orderedIds
        .map((id) => document.getElementById(id))
        .filter((section) => section && section.offsetParent !== null);
}

function getActionButtonsInOrder() {
    const orderedIds = ['read-creation-btn', 'exit-creation-btn', 'backspace-btn', 'clear-word-btn', 'ai-edit-btn', 'new-row-btn', 'action-go-back-btn'];
    return orderedIds
        .map((id) => document.getElementById(id))
        .filter((button) => button && button.offsetParent !== null && !button.disabled);
}

function getToolToggleButtonsInOrder() {
    const orderedIds = ['categories-tool-btn', 'spelling-tool-btn', 'numbers-tool-btn'];
    return orderedIds
        .map((id) => document.getElementById(id))
        .filter((button) => button && button.offsetParent !== null && !button.disabled);
}

function getItemsForSection(sectionId) {
    if (sectionId === 'action') {
        return getActionButtonsInOrder();
    }
    if (sectionId === 'tool-toggle') {
        return getToolToggleButtonsInOrder();
    }
    if (sectionId === 'choose-word') {
        return getVisibleEnabledButtons('.prediction-btn');
    }
    if (sectionId === 'tool-panel' && (activeTool === 'categories' || activeTool === 'numbers')) {
        return getVisibleEnabledButtons('.category-btn');
    }
    if (sectionId === 'tool-panel' && activeTool === 'spelling') {
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
        return getVisibleEnabledButtons('.letter-btn').filter((button) => {
            return Number(button.dataset.rowIndex) === activeLetterRowIndex;
        });
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

    if (element.classList && element.classList.contains('scan-section')) {
        const sectionId = element.dataset.sectionId;
        if (sectionId === 'action') return 'Actions';
        if (sectionId === 'tool-toggle') return 'Tools';
        if (sectionId === 'choose-word') return 'Choose word';
        if (sectionId === 'tool-panel') {
            if (activeTool === 'spelling') return 'Spelling';
            if (activeTool === 'numbers') return 'Numbers';
            return 'Word Categories';
        }
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
    if (text === lastScanPromptText && now - lastScanPromptTime < 700) return;

    try {
        await announce(text, 'system', false, false, true);
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
    if (sectionId === 'tool-panel' && activeTool === 'spelling') {
        lettersScanPhase = 'rows';
        activeLetterRowIndex = null;
    }
    scanCycleCount = 0;
    isPausedFromScanLimit = false;
    stopAuditoryScanning();
    startAuditoryScanning();
}

function returnToSectionScan() {
    activeSectionId = null;
    currentScanLevel = 'sections';
    lettersScanPhase = 'rows';
    activeLetterRowIndex = null;
    scanCycleCount = 0;
}

function advanceScan() {
    let buttons = [];

    if (activeSectionId === 'tool-panel' && activeTool === 'spelling' && spellingPriorityMode === 'return-to-rows') {
        lettersScanPhase = 'rows';
        activeLetterRowIndex = null;
        currentButtonIndex = -1;
        spellingPriorityMode = 'none';
    }

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

    const nextIndex = currentButtonIndex + 1;
    if (nextIndex >= buttons.length) {
        scanCycleCount += 1;
        if (scanMode !== 'step' && scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
            isPausedFromScanLimit = true;
            stopAuditoryScanning();
            currentButtonIndex = 0;
            currentlyScannedButton = buttons[0];
            if (currentlyScannedButton.type === 'letter-row') {
                const rowButtons = getVisibleEnabledButtons('.letter-btn').filter((button) => {
                    return Number(button.dataset.rowIndex) === currentlyScannedButton.rowIndex;
                });
                rowButtons.forEach((button) => button.classList.add('scanned'));
            } else {
                currentlyScannedButton.classList.add('scanned');
            }
            announce('Scanning paused', 'system', false, false, true).catch((error) => {
                console.error('Error announcing scan pause:', error);
            });
            return;
        }
    }

    clearScanHighlight();
    currentButtonIndex = nextIndex % buttons.length;
    currentlyScannedButton = buttons[currentButtonIndex];

    if (currentlyScannedButton.type === 'letter-row') {
        const rowButtons = getVisibleEnabledButtons('.letter-btn').filter((button) => {
            return Number(button.dataset.rowIndex) === currentlyScannedButton.rowIndex;
        });
        rowButtons.forEach((button) => button.classList.add('scanned'));
    } else {
        currentlyScannedButton.classList.add('scanned');
    }

    if (activeSectionId === 'tool-panel' && activeTool === 'spelling' && spellingPriorityMode === 'action-options-once') {
        spellingPriorityMode = 'return-to-rows';
    }

    scheduleScanPromptForElement(currentlyScannedButton);
}

function startAuditoryScanning() {
    if (scanningInterval) return;
    if (scanMode === 'step') {
        if (!currentlyScannedButton) {
            currentButtonIndex = -1;
            scanCycleCount = 0;
            isPausedFromScanLimit = false;
            advanceScan();
        }
        return;
    }
    currentButtonIndex = -1;
    scanCycleCount = 0;
    isPausedFromScanLimit = false;
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
        if (waitForSwitchToScan && window.waitingForInitialSwitch) return;
        if (resetToSections) returnToSectionScan();
        startAuditoryScanning();
    }, delayMs);
}

async function resumeAuditoryScanning() {
    if (!isPausedFromScanLimit) {
        startAuditoryScanning();
        return;
    }

    isPausedFromScanLimit = false;
    scanCycleCount = 0;
    if (currentScanLevel === 'sections') {
        currentButtonIndex = -1;
    } else if (activeSectionId === 'tool-panel' && activeTool === 'spelling') {
        currentButtonIndex = -1;
        if (lettersScanPhase === 'rows') {
            activeLetterRowIndex = null;
        }
    } else {
        currentButtonIndex = -1;
    }

    try {
        await announce('Scanning resumed', 'system', false, false, true);
    } catch (error) {
        console.error('Error announcing scan resume:', error);
    }

    setTimeout(() => {
        startAuditoryScanning();
    }, 1500);
}

function handleSpacebarPress() {
    if (waitForSwitchToScan && window.waitingForInitialSwitch) {
        window.waitingForInitialSwitch = false;
        startAuditoryScanning();
        return;
    }
    if (isPausedFromScanLimit) {
        resumeAuditoryScanning().catch((error) => {
            console.error('Error resuming scan:', error);
        });
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
            interruptScanningAnnouncementPlayback();
            advanceScan();
        }
    });
}

// ============================================================
// Event Listeners
// ============================================================

function setupEventListeners() {
    document.getElementById('exit-creation-btn').addEventListener('click', exitCreation);
    document.getElementById('read-creation-btn').addEventListener('click', readCreation);

    document.getElementById('backspace-btn').addEventListener('click', backspaceCurrentWord);

    document.getElementById('clear-word-btn').addEventListener('click', async () => {
        await clearBuildSpace();
        restartScanning(150, true);
    });

    document.getElementById('ai-edit-btn').addEventListener('click', aiEditCreation);
    document.getElementById('new-row-btn').addEventListener('click', newRow);
    document.getElementById('action-go-back-btn').addEventListener('click', goBackToSectionScanning);
    document.getElementById('categories-tool-btn').dataset.tool = 'categories';
    document.getElementById('numbers-tool-btn').dataset.tool = 'numbers';
    document.getElementById('spelling-tool-btn').dataset.tool = 'spelling';
    document.getElementById('categories-tool-btn').addEventListener('click', () => openTool('categories'));
    document.getElementById('numbers-tool-btn').addEventListener('click', () => openTool('numbers'));
    document.getElementById('spelling-tool-btn').addEventListener('click', () => openTool('spelling'));

    // Clicking the section background enters section-level scanning
    document.querySelectorAll('.scan-section').forEach((section) => {
        section.addEventListener('click', (event) => {
            if (event.target !== section) return;
            const sectionId = section.dataset.sectionId;
            if (!sectionId) return;
            enterSectionScan(sectionId);
        });
    });
}

// ============================================================
// Initialize
// ============================================================

async function initialize() {
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        window.location.href = '/static/auth.html';
        return;
    }

    await loadSettings();
    setupEventListeners();

    // Load existing compose draft into the build space
    const session = loadComposeSession();
    if (session.active && session.text) {
        setBuildSpaceText(session.text);
    }

    // Update banner title with user's display name
    try {
        const profilesResponse = await authenticatedFetch('/api/account/users');
        if (profilesResponse.ok) {
            const profiles = await profilesResponse.json();
            const profile = profiles.find((p) => p.aac_user_id === currentAacUserId);
            if (profile && profile.display_name) {
                const titleEl = document.getElementById('page-title');
                if (titleEl) titleEl.textContent = `Create — ${profile.display_name}`;
            }
        }
    } catch (e) {
        // Non-critical — page title update failure is ignored
    }

    generateAlphabetGrid();
    updateLetterAvailability('');

    // Load categories and initial word suggestions in parallel
    await Promise.all([
        loadCategories(),
        refreshSuggestedWords()
    ]);

    updateWordsSectionTitle();

    returnToSectionScan();
    bindKeyboardScanning();

    if (!waitForSwitchToScan) {
        startAuditoryScanning();
    }
}

document.addEventListener('DOMContentLoaded', initialize);
