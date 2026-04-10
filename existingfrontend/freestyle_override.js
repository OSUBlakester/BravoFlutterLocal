let freestyleAutoClean = false;
let freestyleBuildSpaceDebounceTimer = null;
let freestyleGamepadIndex = null;
let freestyleGamepadPollHandle = null;
let freestyleLastGamepadInputTime = 0;
const FREESTYLE_GAMEPAD_DEBOUNCE_MS = 300;

function getFreestyleNavigationContext() {
    const params = new URLSearchParams(window.location.search);
    return {
        sourcePage: params.get('source_page') || null,
        context: params.get('context') || null,
        isLlmGenerated: params.get('is_llm_generated') === 'true',
        originatingButton: params.get('originating_button') || null
    };
}

function showLoadingIndicator(show) {
    const indicator = document.getElementById('loading-indicator');
    if (!indicator) return;
    indicator.style.display = show ? 'flex' : 'none';
}

function recordToSpeechHistory(textToRecord) {
    const normalized = String(textToRecord || '').trim();
    if (!normalized || !currentAacUserId) {
        return;
    }

    try {
        let history = (localStorage.getItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId)) || '')
            .split('\n')
            .filter(Boolean);
        history.unshift(normalized);
        if (history.length > 20) {
            history = history.slice(0, 20);
        }
        localStorage.setItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId), history.join('\n'));
    } catch (error) {
        console.error('Failed to record freestyle speech history:', error);
    }
}

async function updateFreestylePageTitle() {
    try {
        const response = await authenticatedFetch('/api/account/users');
        if (!response.ok) {
            return;
        }

        const profiles = await response.json();
        const currentProfile = profiles.find((profile) => profile.aac_user_id === currentAacUserId);
        const titleElement = document.getElementById('page-title');
        if (!titleElement) {
            return;
        }

        let baseTitle = 'Free Style Communication';
        const navContext = getFreestyleNavigationContext();
        if (navContext.originatingButton && navContext.isLlmGenerated) {
            baseTitle = `Free Style - ${navContext.originatingButton}`;
        } else if (navContext.sourcePage && navContext.sourcePage.toLowerCase() !== 'home') {
            const pageName = navContext.sourcePage
                .replace(/_/g, ' ')
                .replace(/-/g, ' ')
                .replace(/\b\w/g, (char) => char.toUpperCase());
            baseTitle = `Free Style - ${pageName}`;
        }

        titleElement.textContent = currentProfile?.display_name
            ? `${baseTitle} - ${currentProfile.display_name}`
            : baseTitle;
    } catch (error) {
        console.error('Failed to update freestyle page title:', error);
    }
}

async function loadFreestyleSettingsOverrides() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (!response.ok) {
            return;
        }
        const settings = await response.json();
        const freestyleOptions = Number(settings.FreestyleOptions);
        const composeOptions = Number(settings.LLMOptions);
        if (!Number.isNaN(freestyleOptions) && freestyleOptions > 0) {
            LLMOptions = freestyleOptions;
        } else if (!Number.isNaN(composeOptions) && composeOptions > 0) {
            LLMOptions = composeOptions;
        }
        freestyleAutoClean = settings.autoClean === true;
    } catch (error) {
        console.error('Failed to load freestyle override settings:', error);
    }
}

function replaceButtonHandler(buttonId, handler) {
    const existingButton = document.getElementById(buttonId);
    if (!existingButton || !existingButton.parentNode) {
        return null;
    }

    const nextButton = existingButton.cloneNode(true);
    existingButton.parentNode.replaceChild(nextButton, existingButton);
    nextButton.addEventListener('click', handler);
    return nextButton;
}

function setupBuildSpaceManualInput() {
    currentWordInput.removeAttribute('readonly');
    currentWordInput.addEventListener('input', () => {
        currentBuildSpaceText = currentWordInput.value;
        currentSpellingWord = '';
        updateLetterAvailability('');

        if (freestyleBuildSpaceDebounceTimer) {
            clearTimeout(freestyleBuildSpaceDebounceTimer);
        }

        freestyleBuildSpaceDebounceTimer = setTimeout(() => {
            refreshSuggestedWords().catch((error) => {
                console.error('Failed to refresh freestyle suggestions from manual input:', error);
            });
        }, 350);
    });
}

function getFreestyleRequestPayloadBase() {
    const navContext = getFreestyleNavigationContext();
    return {
        context: navContext.context,
        source_page: navContext.sourcePage,
        is_llm_generated: navContext.isLlmGenerated,
        originating_button_text: navContext.originatingButton
    };
}

function buildFreestyleCategoryPrompt(categorySelection) {
    const basePrompt = String(
        categorySelection?.wordsPrompt || categorySelection?.llmPrompt || ''
    ).trim();
    const promptCategory = String(categorySelection?.promptCategory || '').trim().toLowerCase();

    if (!basePrompt) {
        return getContextFreeCategoryPrompt(categorySelection?.label || '');
    }

    let sentenceStartInstruction = isStartingNewSentence()
        ? 'The user is starting a new sentence or row. Prefer options that can sensibly begin the next sentence while staying within the category intent.'
        : 'Use the current build space to decide what could naturally come next within this category.';

    if (promptCategory === 'ask' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural question and request openings such as Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is.';
    }

    if (promptCategory === 'respond' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural response openings such as Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now.';
    }

    if (promptCategory === 'requests' && isStartingNewSentence()) {
        sentenceStartInstruction = 'The user is starting a new sentence or row. Prefer natural request openings and request starters such as Can, Could, May, Will, Would, Please, I need, and I want.';
    }

    return `${basePrompt}

ADDITIONAL FREESTYLE REQUIREMENTS:
- ${sentenceStartInstruction}
- Use current communication context when relevant, including current location, people present, activity, and the page or button the user came from.
- Keep the options useful for current AAC communication.
- Return words or short phrases only.`;
}

async function requestFreestyleGeneralWords(requestDifferentOptions = false) {
    const payload = {
        ...getFreestyleRequestPayloadBase(),
        build_space_text: getCombinedBuildText().trim(),
        single_words_only: true,
        request_different_options: requestDifferentOptions,
        max_options: Math.max(1, LLMOptions)
    };

    try {
        const response = await authenticatedFetch('/api/freestyle/word-options', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            throw new Error(`General freestyle request failed: ${response.status}`);
        }

        const data = await response.json();
        const options = Array.isArray(data.word_options) ? data.word_options : [];
        const nextWords = options
            .map((item) => (typeof item === 'object' && item?.text ? item.text : item))
            .filter((item) => typeof item === 'string' && item.trim() !== '')
            .slice(0, Math.max(1, LLMOptions));

        const fallbackWords = isStartingNewSentence()
            ? getSentenceStarterFallbackWords()
            : ['I', 'want', 'need', 'can', 'please', 'help', 'yes', 'no']
                .slice(0, Math.max(1, LLMOptions));

        currentPredictions = nextWords.length > 0 ? nextWords : fallbackWords;
        renderWordPredictions();
        return nextWords.length > 0;
    } catch (error) {
        console.error('Failed to load freestyle general words with context:', error);
        const fallbackWords = isStartingNewSentence()
            ? getSentenceStarterFallbackWords()
            : ['I', 'want', 'need', 'can', 'please', 'help', 'yes', 'no']
                .slice(0, Math.max(1, LLMOptions));
        currentPredictions = fallbackWords;
        renderWordPredictions();
        return false;
    }
}

requestCategoryWordsWithExclusions = async function(category, customPrompt, fallbackWords = [], excludeWords = []) {
    const payload = {
        ...getFreestyleRequestPayloadBase(),
        category,
        build_space_content: getCombinedBuildText().trim(),
        exclude_words: excludeWords,
        custom_prompt: customPrompt
    };

    try {
        const response = await authenticatedFetch('/api/freestyle/category-words', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            currentPredictions = fallbackWords;
            renderWordPredictions();
            return false;
        }

        const data = await response.json();
        const rawWords = Array.isArray(data.words) ? data.words : [];
        const nextWords = rawWords
            .map((item) => (typeof item === 'object' && item?.text ? item.text : item))
            .filter((item) => typeof item === 'string' && item.trim() !== '')
            .slice(0, Math.max(1, LLMOptions));

        currentPredictions = nextWords.length > 0 ? nextWords : fallbackWords;
        renderWordPredictions();
        return nextWords.length > 0;
    } catch (error) {
        console.error('Failed to load freestyle category words with context:', error);
        currentPredictions = fallbackWords;
        renderWordPredictions();
        return false;
    }
};

buildCategorySpecificPrompt = buildFreestyleCategoryPrompt;

loadGeneralWords = async function(excludeWords = [], fallbackWordsOverride = null) {
    const didLoadWords = await requestFreestyleGeneralWords(Boolean(excludeWords?.length));
    if (!didLoadWords && fallbackWordsOverride) {
        currentPredictions = fallbackWordsOverride;
        renderWordPredictions();
    }
    return didLoadWords;
};

async function speakDisplayFromFreestyle() {
    const currentText = getCombinedBuildText().trim();
    if (!currentText) {
        await announce('Display is empty.', 'system', false, true);
        return;
    }

    stopAuditoryScanning();

    try {
        let textToSpeak = currentText;
        if (freestyleAutoClean) {
            textToSpeak = await cleanupTextValue(currentText);
            currentSpellingWord = '';
            setBuildSpaceText(textToSpeak);
            await refreshSuggestedWords();
        }

        await announce(textToSpeak, 'system', false, true);
        recordToSpeechHistory(textToSpeak);
    } catch (error) {
        console.error('Failed to speak freestyle display:', error);
        await announce('Unable to speak display right now.', 'system', false, true);
    }

    restartScanning(250, true);
}

function goBackFromFreestyle() {
    stopAuditoryScanning();
    window.location.href = '/static/gridpage.html?page=home';
}

function setupPinModal() {
    const lockButton = document.getElementById('lock-icon');
    const adminIcons = document.getElementById('admin-icons');
    const pinModal = document.getElementById('pin-modal');
    const pinInput = document.getElementById('pin-input');
    const pinSubmitButton = document.getElementById('pin-submit');
    const pinCancelButton = document.getElementById('pin-cancel');
    const pinError = document.getElementById('pin-error');

    function showPinModal() {
        pinModal?.classList.remove('hidden');
        if (pinInput) {
            pinInput.value = '';
            pinInput.focus();
        }
        pinError?.classList.add('hidden');
    }

    function hidePinModal() {
        pinModal?.classList.add('hidden');
        if (pinInput) {
            pinInput.value = '';
        }
        pinError?.classList.add('hidden');
    }

    async function validatePin(pin) {
        try {
            const response = await authenticatedFetch('/api/account/toolbar-pin', { method: 'GET' });
            if (!response.ok) {
                return false;
            }
            const data = await response.json();
            return data.pin === pin;
        } catch (error) {
            console.error('Failed to validate toolbar PIN:', error);
            return false;
        }
    }

    function unlockToolbar() {
        adminIcons?.classList.remove('hidden');
        if (lockButton) {
            lockButton.style.display = 'none';
        }
        hidePinModal();
    }

    function lockToolbar() {
        adminIcons?.classList.add('hidden');
        if (lockButton) {
            lockButton.style.display = 'block';
        }
    }

    lockButton?.addEventListener('click', showPinModal);
    document.getElementById('lock-toolbar-button')?.addEventListener('click', lockToolbar);
    document.getElementById('back-to-grid-admin')?.addEventListener('click', () => {
        window.location.href = '/static/gridpage.html?page=home';
    });
    document.getElementById('switch-user-button')?.addEventListener('click', () => {
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        sessionStorage.clear();
        setTimeout(() => {
            window.location.href = '/static/auth.html';
        }, 100);
    });
    document.getElementById('logout-button')?.addEventListener('click', () => {
        localStorage.setItem('bravoIntentionalLogout', 'true');
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        sessionStorage.clear();
        setTimeout(() => {
            window.location.href = '/static/auth.html';
        }, 100);
    });
    pinCancelButton?.addEventListener('click', hidePinModal);
    pinModal?.addEventListener('click', (event) => {
        if (event.target === pinModal) {
            hidePinModal();
        }
    });
    pinInput?.addEventListener('keydown', async (event) => {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        pinSubmitButton?.click();
    });

    pinSubmitButton?.addEventListener('click', async () => {
        const pin = pinInput?.value || '';
        if (pin.length < 3 || pin.length > 10) {
            pinError?.classList.remove('hidden');
            return;
        }

        const isValid = await validatePin(pin);
        if (isValid) {
            unlockToolbar();
            return;
        }

        pinError?.classList.remove('hidden');
        if (pinInput) {
            pinInput.select();
        }
    });
}

function setupFreestyleGamepadListeners() {
    window.addEventListener('gamepadconnected', (event) => {
        freestyleGamepadIndex = event.gamepad.index;
        if (!freestyleGamepadPollHandle) {
            pollFreestyleGamepad();
        }
    });

    window.addEventListener('gamepaddisconnected', (event) => {
        if (freestyleGamepadIndex === event.gamepad.index) {
            freestyleGamepadIndex = null;
        }
        if (freestyleGamepadIndex === null && freestyleGamepadPollHandle) {
            cancelAnimationFrame(freestyleGamepadPollHandle);
            freestyleGamepadPollHandle = null;
        }
    });
}

function pollFreestyleGamepad() {
    if (freestyleGamepadIndex === null) {
        freestyleGamepadPollHandle = null;
        return;
    }

    const gamepad = navigator.getGamepads()[freestyleGamepadIndex];
    if (gamepad?.buttons?.[0]?.pressed) {
        const now = Date.now();
        if (now - freestyleLastGamepadInputTime > FREESTYLE_GAMEPAD_DEBOUNCE_MS) {
            freestyleLastGamepadInputTime = now;
            handleSpacebarPress();
        }
    }

    freestyleGamepadPollHandle = requestAnimationFrame(pollFreestyleGamepad);
}

function tryResumeAudioContext() {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) {
        return;
    }

    const tempContext = new AudioContextClass();
    if (tempContext.state === 'suspended') {
        tempContext.resume().finally(() => tempContext.close().catch(() => {}));
        return;
    }

    tempContext.close().catch(() => {});
}

async function initializeFreestyleOverrides() {
    await loadFreestyleSettingsOverrides();
    await updateFreestylePageTitle();

    setupBuildSpaceManualInput();
    setupPinModal();
    setupFreestyleGamepadListeners();

    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true });

    replaceButtonHandler('exit-creation-btn', goBackFromFreestyle);
    replaceButtonHandler('read-creation-btn', speakDisplayFromFreestyle);

    await refreshSuggestedWords();
}

window.addEventListener('load', () => {
    initializeFreestyleOverrides().catch((error) => {
        console.error('Failed to initialize freestyle overrides:', error);
    });
});