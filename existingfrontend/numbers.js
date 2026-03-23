let firebaseIdToken = null;
let currentAacUserId = null;

let defaultDelay = 3500;
let scanMode = 'auto';
let waitForSwitchToScan = false;

let scanningInterval = null;
let currentScanPhase = 'rows'; // rows | items
let currentRowIndex = -1;
let currentRowScanCursor = -1;
let currentItemIndex = -1;
let currentlyScannedElement = null;

let announcementQueue = [];
let isAnnouncingNow = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

let pendingScanPromptTimer = null;
let pendingScanPromptToken = 0;
let lastScanPromptText = '';
let lastScanPromptTime = 0;

let pageOffset = 0;
const ROWS_VISIBLE = 9;

const numbersGrid = document.getElementById('numbers-grid');

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
        if (waitForSwitchToScan) {
            window.waitingForInitialSwitch = true;
        }
    } catch (error) {
        console.error('Failed to load settings:', error);
    }
}

function getHomeTarget() {
    const params = new URLSearchParams(window.location.search);
    const from = params.get('from');
    if (from) return from;
    return '/static/gridpage.html?page=home';
}

function navigateHome() {
    stopAuditoryScanning();
    window.location.href = getHomeTarget();
}

function getRowRangeForIndex(rowIndex) {
    const start = (pageOffset * ROWS_VISIBLE * 10) + (rowIndex * 10);
    return { start, end: start + 9 };
}

function createButton({ label, rowIndex, colIndex, cssClass, clickHandler }) {
    const button = document.createElement('button');
    button.className = `number-btn scan-item ${cssClass || ''}`.trim();
    button.textContent = label;
    button.dataset.rowIndex = String(rowIndex);
    button.dataset.colIndex = String(colIndex);
    button.addEventListener('click', clickHandler);
    return button;
}

function renderNumbersGrid() {
    numbersGrid.innerHTML = '';

    for (let rowIndex = 0; rowIndex < ROWS_VISIBLE; rowIndex++) {
        const { start } = getRowRangeForIndex(rowIndex);

        if (rowIndex === 0) {
            numbersGrid.appendChild(createButton({
                label: 'Home',
                rowIndex,
                colIndex: 0,
                cssClass: 'home-btn',
                clickHandler: navigateHome
            }));
            for (let n = 0; n <= 9; n++) {
                const value = start + n;
                numbersGrid.appendChild(createButton({
                    label: String(value),
                    rowIndex,
                    colIndex: n + 1,
                    clickHandler: () => handleNumberSelection(String(value))
                }));
            }
            continue;
        }

        for (let n = 0; n < 10; n++) {
            const value = start + n;
            numbersGrid.appendChild(createButton({
                label: String(value),
                rowIndex,
                colIndex: n,
                clickHandler: () => handleNumberSelection(String(value))
            }));
        }

        if (rowIndex === ROWS_VISIBLE - 1) {
            numbersGrid.appendChild(createButton({
                label: 'Show More',
                rowIndex,
                colIndex: 10,
                cssClass: 'show-more-btn',
                clickHandler: () => {
                    pageOffset += 1;
                    renderNumbersGrid();
                    resetToRowsAndRestart(140);
                }
            }));
        } else {
            const spacer = document.createElement('div');
            spacer.className = 'number-spacer';
            spacer.setAttribute('aria-hidden', 'true');
            numbersGrid.appendChild(spacer);
        }
    }
}

async function handleNumberSelection(value) {
    stopAuditoryScanning();
    await announce(value, 'system', false, true);
    await recordChatHistory('', value);
    resetToRowsAndRestart(180);
}

function getRowTargets() {
    const rowIndexes = new Set(
        Array.from(document.querySelectorAll('.scan-item'))
            .map((button) => Number(button.dataset.rowIndex))
            .filter((v) => !Number.isNaN(v))
    );

    return Array.from(rowIndexes)
        .sort((a, b) => a - b)
        .map((rowIndex) => ({ type: 'row-target', rowIndex }));
}

function getButtonsForRow(rowIndex) {
    return Array.from(document.querySelectorAll('.scan-item'))
        .filter((button) => Number(button.dataset.rowIndex) === rowIndex)
        .sort((a, b) => Number(a.dataset.colIndex) - Number(b.dataset.colIndex));
}

function clearScanHighlight() {
    if (!currentlyScannedElement) return;

    if (currentlyScannedElement.type === 'row-target') {
        getButtonsForRow(currentlyScannedElement.rowIndex).forEach((button) => button.classList.remove('scanned'));
    } else if (currentlyScannedElement.classList) {
        currentlyScannedElement.classList.remove('scanned');
    }

    currentlyScannedElement = null;
}

function highlightElement(target) {
    if (target.type === 'row-target') {
        getButtonsForRow(target.rowIndex).forEach((button) => button.classList.add('scanned'));
        return;
    }
    target.classList.add('scanned');
}

function getPromptForScanTarget(target) {
    if (!target) return '';
    if (target.type === 'row-target') {
        const { start, end } = getRowRangeForIndex(target.rowIndex);
        return `${start} to ${end}`;
    }
    return (target.textContent || '').trim();
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

function scheduleScanPromptForTarget(target) {
    const promptText = getPromptForScanTarget(target);
    if (!promptText) return;

    clearPendingScanPrompt();
    const token = pendingScanPromptToken;
    pendingScanPromptTimer = setTimeout(() => {
        if (token !== pendingScanPromptToken) return;
        pendingScanPromptTimer = null;
        announceScanPrompt(promptText);
    }, 120);
}

function advanceScan() {
    let targets;
    if (currentScanPhase === 'rows') {
        targets = getRowTargets();
        if (!targets.length) {
            clearScanHighlight();
            currentRowIndex = -1;
            currentRowScanCursor = -1;
            return;
        }

        clearScanHighlight();
        currentRowScanCursor = (currentRowScanCursor + 1) % targets.length;
        currentlyScannedElement = targets[currentRowScanCursor];
        highlightElement(currentlyScannedElement);
        scheduleScanPromptForTarget(currentlyScannedElement);
        return;
    }

    const rowButtons = getButtonsForRow(currentRowIndex);
    if (!rowButtons.length) {
        currentScanPhase = 'rows';
        currentItemIndex = -1;
        advanceScan();
        return;
    }

    clearScanHighlight();
    currentItemIndex = (currentItemIndex + 1) % rowButtons.length;
    currentlyScannedElement = rowButtons[currentItemIndex];
    highlightElement(currentlyScannedElement);
    scheduleScanPromptForTarget(currentlyScannedElement);
}

function startAuditoryScanning() {
    if (scanningInterval) return;

    if (scanMode === 'step') {
        if (!currentlyScannedElement) {
            if (currentScanPhase === 'rows') {
                currentRowIndex = -1;
                currentRowScanCursor = -1;
            }
            currentItemIndex = -1;
            advanceScan();
        }
        return;
    }

    if (currentScanPhase === 'rows') {
        currentRowIndex = -1;
        currentRowScanCursor = -1;
    }
    currentItemIndex = -1;
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
}

function resetToRowsAndRestart(delayMs = 0) {
    stopAuditoryScanning();
    currentScanPhase = 'rows';
    currentRowIndex = -1;
    currentRowScanCursor = -1;
    currentItemIndex = -1;

    setTimeout(() => {
        if (waitForSwitchToScan && window.waitingForInitialSwitch) {
            return;
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

    if (!currentlyScannedElement) {
        startAuditoryScanning();
        return;
    }

    clearPendingScanPrompt();
    if (currentScanPhase === 'rows') {
        currentRowIndex = currentlyScannedElement.rowIndex;
        currentScanPhase = 'items';
        currentItemIndex = -1;
        stopAuditoryScanning();
        startAuditoryScanning();
        return;
    }

    currentlyScannedElement.click();
}

function bindKeyboardScanning() {
    document.addEventListener('keydown', (event) => {
        if (event.repeat) return;

        if (event.code === 'Space') {
            event.preventDefault();
            handleSpacebarPress();
            return;
        }

        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            advanceScan();
        }
    });
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
    const personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
    const systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';

    let targetOutputDeviceId = 'default';
    if (announcementType === 'personal') {
        targetOutputDeviceId = personalSpeakerId;
    } else if (announcementType === 'system') {
        targetOutputDeviceId = systemSpeakerId;
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') {
            audioContext.resume().catch(() => {});
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
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    text,
                    routing_target: target === 'personal' ? 'personal' : 'system'
                })
            });

            if (!response.ok) {
                throw new Error(`Failed to synthesize audio: ${response.status}`);
            }

            const jsonResponse = await response.json();
            if (jsonResponse.audio_data) {
                const audioDataArrayBuffer = base64ToArrayBuffer(jsonResponse.audio_data);
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

async function initialize() {
    await loadSettings();
    renderNumbersGrid();
    bindKeyboardScanning();
    if (!waitForSwitchToScan) {
        resetToRowsAndRestart(0);
    }
}

initialize();