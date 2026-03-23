// --- Jokes Page JavaScript ---

let currentAacUserId = null;
let firebaseIdToken = null;
const AAC_USER_ID_SESSION_KEY = "currentAacUserId";
const FIREBASE_TOKEN_SESSION_KEY = "firebaseIdToken";

let scanDelay = 3500;
let LLMOptions = 10;
let ScanningOff = false;
let scanMode = 'auto';
let gridColumns = 10;
let enablePictograms = false;

let currentlyScannedButton = null;
let scanningInterval = null;
let currentButtonIndex = -1;

// Authenticated fetch (same pattern as other pages)
async function authenticatedFetch(url, options = {}) {
    firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);

    if (!firebaseIdToken || !currentAacUserId) {
        console.error("Authentication: Firebase ID Token or AAC User ID not found.");
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error("Authentication required.");
    }

    const headers = {
        'Authorization': `Bearer ${firebaseIdToken}`,
        'X-User-ID': currentAacUserId,
        ...options.headers
    };

    const adminTargetAccountId = sessionStorage.getItem('adminTargetAccountId');
    if (adminTargetAccountId) {
        headers['X-Admin-Target-Account'] = adminTargetAccountId;
    }

    const response = await fetch(url, { ...options, headers });

    if (response.status === 401 || response.status === 403) {
        console.warn(`Authentication failed (${response.status}) for ${url}. Redirecting to login.`);
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error("Authentication failed");
    }

    return response;
}

async function initializeUserContext() {
    firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);

    if (!firebaseIdToken || !currentAacUserId) {
        sessionStorage.clear();
        window.location.href = 'auth.html';
        return false;
    }

    return true;
}

async function loadUserSettings() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (response.ok) {
            const settings = await response.json();

            if (settings && typeof settings.scanDelay === 'number' && !isNaN(settings.scanDelay)) {
                scanDelay = Math.max(100, parseInt(settings.scanDelay));
            } else {
                scanDelay = 3500;
            }

            if (settings && typeof settings.LLMOptions === 'number' && !isNaN(settings.LLMOptions)) {
                LLMOptions = Math.max(1, parseInt(settings.LLMOptions));
            } else {
                LLMOptions = 10;
            }

            if (settings && typeof settings.gridColumns === 'number' && !isNaN(settings.gridColumns)) {
                gridColumns = Math.max(2, Math.min(18, parseInt(settings.gridColumns)));
            } else {
                gridColumns = 10;
            }

            ScanningOff = settings.ScanningOff === true;
            scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
            enablePictograms = settings.enablePictograms === true;

            if (window.updateSightWordSettings) {
                window.updateSightWordSettings(settings);
            }
        }
    } catch (error) {
        console.error('Error loading settings:', error);
        scanDelay = 3500;
        LLMOptions = 10;
        gridColumns = 10;
        ScanningOff = false;
        scanMode = 'auto';
        enablePictograms = false;
    }
}

function updateGridLayout() {
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) return;

    gridContainer.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;

    const baseFontSize = 20;
    const minFontSize = 10;
    const maxFontSize = 28;
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / gridColumns)));

    gridContainer.style.setProperty('--button-font-size', `${fontSize}px`);
}

async function getSymbolImageForText(text, keywords = null) {
    if (!text || text.trim() === '') {
        return null;
    }

    if (!enablePictograms) {
        return null;
    }

    if (window.isSightWord && window.isSightWord(text)) {
        return null;
    }

    if (!window.symbolImageCache) {
        window.symbolImageCache = new Map();

        try {
            const cachedData = sessionStorage.getItem('symbolImageCache');
            if (cachedData) {
                const parsed = JSON.parse(cachedData);
                Object.entries(parsed).forEach(([key, value]) => {
                    if (value.timestamp > Date.now() - 3600000) {
                        window.symbolImageCache.set(key, value);
                    }
                });
            }
        } catch (e) {
            console.warn('Failed to restore symbol image cache:', e);
        }
    }

    const cacheKey = `jokes_${text.trim().toLowerCase()}_${keywords ? JSON.stringify(keywords) : 'none'}`;
    if (window.symbolImageCache.has(cacheKey)) {
        const cached = window.symbolImageCache.get(cacheKey);
        if (cached.timestamp > Date.now() - 3600000) {
            return cached.imageUrl;
        }
    }

    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        let symbolsUrl = `/api/symbols/button-search?q=${encodeURIComponent(text.trim())}&limit=1`;
        if (keywords && Array.isArray(keywords) && keywords.length > 0) {
            symbolsUrl += `&keywords=${encodeURIComponent(JSON.stringify(keywords))}`;
        }

        const response = await authenticatedFetch(symbolsUrl, { signal: controller.signal });

        clearTimeout(timeoutId);

        if (!response.ok) {
            return null;
        }

        const data = await response.json();
        if (data && data.symbols && Array.isArray(data.symbols) && data.symbols.length > 0) {
            const symbolUrl = data.symbols[0].url;
            window.symbolImageCache.set(cacheKey, {
                imageUrl: symbolUrl,
                timestamp: Date.now()
            });

            try {
                const cacheObj = Object.fromEntries(window.symbolImageCache);
                sessionStorage.setItem('symbolImageCache', JSON.stringify(cacheObj));
            } catch (e) {
                console.warn('Failed to persist symbol cache:', e);
            }

            return symbolUrl;
        }

        window.symbolImageCache.set(cacheKey, {
            imageUrl: null,
            timestamp: Date.now()
        });

        try {
            const cacheObj = Object.fromEntries(window.symbolImageCache);
            sessionStorage.setItem('symbolImageCache', JSON.stringify(cacheObj));
        } catch (e) {
            console.warn('Failed to persist symbol cache:', e);
        }

        return null;
    } catch (error) {
        return null;
    }
}

async function loadJokes() {
    const statusText = document.getElementById('statusText');
    stopAuditoryScanning();

    if (statusText) {
        statusText.textContent = 'Loading jokes...';
    }

    try {
        const response = await authenticatedFetch(`/api/jokes/contextual?limit=${LLMOptions}`);
        if (!response.ok) {
            throw new Error(`Failed to fetch jokes: ${response.status}`);
        }

        const data = await response.json();
        const jokes = (data && data.jokes) ? data.jokes : [];

        await renderJokes(jokes);

        if (statusText) {
            statusText.textContent = jokes.length ? `Showing ${jokes.length} jokes` : 'No jokes available';
        }

        if (!ScanningOff) {
            startAuditoryScanning();
        }
    } catch (error) {
        console.error('Error loading jokes:', error);
        if (statusText) {
            statusText.textContent = 'Failed to load jokes';
        }
    }
}

function addPauseToJokeText(text) {
    if (!text) return '';
    if (text.includes('[PAUSE]')) return text;

    const questionIndex = text.indexOf('?');
    if (questionIndex !== -1 && questionIndex < text.length - 1) {
        return `${text.slice(0, questionIndex + 1)} [PAUSE] ${text.slice(questionIndex + 1).trim()}`;
    }

    if (text.includes(' - ')) {
        return text.replace(' - ', ' [PAUSE] ');
    }

    if (text.includes(' — ')) {
        return text.replace(' — ', ' [PAUSE] ');
    }

    if (text.includes(': ')) {
        return text.replace(': ', ': [PAUSE] ');
    }

    return text;
}

async function renderJokes(jokes) {
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) return;

    gridContainer.innerHTML = '';
    updateGridLayout();

    const buttonDataList = [
        { text: 'Home', kind: 'home' },
        ...jokes.map(joke => ({
            text: (joke.summary || 'Joke').trim() || 'Joke',
            jokeText: (joke.text || '').trim(),
            keywords: joke.tags ? (Array.isArray(joke.tags) ? joke.tags : [joke.tags]) : ['joke', 'humor']
        })),
        { text: 'Something Else', kind: 'refresh' }
    ];

    // PERFORMANCE: Prefetch all symbol images in parallel before creating buttons
    const symbolImagePromises = buttonDataList.map(buttonData => 
        (window.isSightWord && window.isSightWord(buttonData.text)) 
            ? Promise.resolve(null) 
            : getSymbolImageForText(buttonData.text, buttonData.keywords)
    );
    const symbolImages = await Promise.all(symbolImagePromises);

    const buttonPromises = buttonDataList.map(async (buttonData, idx) => {
        const currentRow = Math.floor(idx / gridColumns);
        const currentCol = idx % gridColumns;

        const button = document.createElement('button');

        if (window.isSightWord && window.isSightWord(buttonData.text)) {
            button.textContent = buttonData.text;
            button.classList.add('sight-word-button');
            button.style.fontSize = '2.2em';
            button.style.fontWeight = '900';
            button.style.color = '#dc2626';
        } else {
            // Use pre-fetched symbol image
            const symbolImageUrl = symbolImages[idx];

            if (symbolImageUrl) {
                const buttonContent = document.createElement('div');
                buttonContent.style.position = 'relative';
                buttonContent.style.width = '100%';
                buttonContent.style.height = '100%';
                buttonContent.style.display = 'flex';
                buttonContent.style.flexDirection = 'column';

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
                imageElement.alt = buttonData.text;
                imageElement.style.width = '100%';
                imageElement.style.height = '100%';
                imageElement.style.objectFit = 'cover';
                imageElement.onerror = () => {
                    imageElement.style.display = 'none';
                };

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
                textSpan.textContent = buttonData.text;
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
                button.textContent = buttonData.text;
            }
        }

        button.dataset.scanLabel = buttonData.text;
        button.dataset.row = currentRow;
        button.dataset.col = currentCol;
        button.classList.add('grid-button');
        button.style.gridRowStart = currentRow + 1;
        button.style.gridColumnStart = currentCol + 1;

        if (!button.classList.contains('sight-word-button')) {
            button.style.padding = '0';
            button.style.margin = '0';
            button.style.border = 'none';
            button.style.position = 'relative';
            button.style.overflow = 'hidden';
        }

        if (buttonData.kind === 'home') {
            button.addEventListener('click', () => {
                stopAuditoryScanning();
                goHome();
            });
        } else if (buttonData.kind === 'refresh') {
            button.addEventListener('click', () => {
                stopAuditoryScanning();
                loadJokes();
            });
        } else {
            button.addEventListener('click', async () => {
                stopAuditoryScanning();
                if (buttonData.jokeText) {
                    const pausedText = addPauseToJokeText(buttonData.jokeText);
                    await announce(pausedText, 'system', true);
                }
                goHome();
            });
        }

        return button;
    });

    const buttons = await Promise.all(buttonPromises);
    const fragment = document.createDocumentFragment();
    buttons.forEach(button => fragment.appendChild(button));
    gridContainer.appendChild(fragment);
}

function getVisibleButtons() {
    return Array.from(document.querySelectorAll('#gridContainer button'));
}

function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) return;

    if (scanMode === 'step') {
        currentButtonIndex = -1;
        advanceJokesScanningStep();
        return;
    }

    const buttons = getVisibleButtons();
    if (buttons.length === 0) return;

    currentButtonIndex = -1;

    const scanStep = async () => {
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning');
        }

        currentButtonIndex = (currentButtonIndex + 1) % buttons.length;
        currentlyScannedButton = buttons[currentButtonIndex];

        if (currentlyScannedButton) {
            currentlyScannedButton.classList.add('scanning');
            const label = (currentlyScannedButton.dataset.scanLabel || currentlyScannedButton.textContent || '').trim();
            if (label) {
                try {
                    await announce(label, 'system', false);
                } catch (e) {
                    console.error('Scanning announce error:', e);
                }
            }
        }
    };

    scanStep();
    scanningInterval = setInterval(scanStep, scanDelay);
}

function advanceJokesScanningStep() {
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
    currentlyScannedButton = buttons[currentButtonIndex];

    if (currentlyScannedButton) {
        currentlyScannedButton.classList.add('scanning');
        const label = (currentlyScannedButton.dataset.scanLabel || currentlyScannedButton.textContent || '').trim();
        if (label) {
            announce(label, 'system', false).catch((e) => console.error('Scanning announce error:', e));
        }
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
}

function goHome() {
    window.location.href = 'gridpage.html?page=home';
}

// Announcement queue and processing (same pattern as gridpage)
let announcementQueue = [];
let isAnnouncingNow = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

function base64ToArrayBuffer(base64) {
    const binaryString = window.atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

async function playAudioToDevice(audioDataBuffer) {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
    const source = audioContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(audioContext.destination);
    activeAnnouncementAudioContext = audioContext;
    activeAnnouncementAudioSource = source;

    return new Promise((resolve, reject) => {
        source.onended = () => {
            activeAnnouncementAudioSource = null;
            if (activeAnnouncementAudioContext === audioContext) {
                activeAnnouncementAudioContext = null;
            }
            if (audioContext && audioContext.state !== 'closed') {
                audioContext.close().catch(() => {});
            }
            resolve();
        };
        source.onerror = reject;
        source.start(0);
    });
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
    const { textToAnnounce, announcementType, resolve, reject, showSplash } = announcementQueue.shift();

    if (showSplash && typeof showSplashScreen === 'function') {
        showSplashScreen(textToAnnounce);
    }

    try {
        const response = await authenticatedFetch('/play-audio', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: textToAnnounce, routing_target: announcementType })
        });

        if (!response.ok) {
            const errorBody = await response.json().catch(() => response.text());
            throw new Error(`Failed to synthesize audio: ${response.status} - ${JSON.stringify(errorBody)}`);
        }

        const jsonResponse = await response.json();
        const audioData = jsonResponse.audio_data;

        if (!audioData) {
            throw new Error('No audio data received from server.');
        }

        const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
        await playAudioToDevice(audioDataArrayBuffer);

        resolve();
    } catch (error) {
        console.error('Error in announcement:', error);
        reject(error);
    } finally {
        isAnnouncingNow = false;
        processAnnouncementQueue();
    }
}

async function announce(textToAnnounce, announcementType = 'system', showSplash = true) {
    if (textToAnnounce.includes('[PAUSE]')) {
        const parts = textToAnnounce.split('[PAUSE]').map(p => p.trim()).filter(p => p.length > 0);

        if (parts.length > 1) {
            for (let i = 0; i < parts.length - 1; i++) {
                await new Promise((resolve, reject) => {
                    announcementQueue.push({
                        textToAnnounce: parts[i],
                        announcementType,
                        showSplash,
                        resolve,
                        reject
                    });
                    processAnnouncementQueue();
                });

                await new Promise(resolve => setTimeout(resolve, 1500));
            }

            const lastPart = parts[parts.length - 1];
            return new Promise((resolve, reject) => {
                announcementQueue.push({
                    textToAnnounce: lastPart,
                    announcementType,
                    showSplash,
                    resolve,
                    reject
                });
                processAnnouncementQueue();
            });
        }
    }

    return new Promise((resolve, reject) => {
        announcementQueue.push({
            textToAnnounce,
            announcementType,
            showSplash,
            resolve,
            reject
        });

        processAnnouncementQueue();
    });
}

// Initialize page
window.addEventListener('DOMContentLoaded', async () => {
    // Add CSS for scanning highlight (if not already present)
    if (!document.getElementById('scanning-styles')) {
        const styleSheet = document.createElement("style");
        styleSheet.id = 'scanning-styles';
        styleSheet.textContent = `
            .scanning { /* Highlight style for individual buttons */
                box-shadow: 0 0 10px 4px #FB4F14 !important; /* Orange glow, !important to override base button shadow */
                outline: none !important; /* Prevent default browser focus outline, !important for specificity */
            }
            .scanning-row { /* Highlight style for entire row during row-phase scanning */
                box-shadow: 0 0 8px 3px #FFA500 !important; /* Slightly different orange glow for row highlight */
                outline: none !important;
            }
            .active { /* Optional style for click feedback */
                 transform: scale(0.95);
                 opacity: 0.8;
            }
            .grid-button-base { /* Ensure base class exists for JS */ }
        `;
        document.head.appendChild(styleSheet);
    }

    const userReady = await initializeUserContext();
    if (!userReady) {
        return;
    }

    await loadUserSettings();
    await loadJokes();

    if (typeof hideSplashScreen === 'function') {
        hideSplashScreen();
    }
});

// Spacebar selects current scanned button
document.addEventListener('keydown', (event) => {
    if (event.code === 'Tab' && scanMode === 'step') {
        event.preventDefault();
        interruptScanningAnnouncementPlayback();
        if (currentlyScannedButton) {
            advanceJokesScanningStep();
        } else {
            startAuditoryScanning();
        }
        return;
    }

    if (event.code === 'Space' && currentlyScannedButton) {
        event.preventDefault();
        currentlyScannedButton.click();
    }
});
