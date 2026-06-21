let freestyleAutoClean = false;
let freestyleBuildSpaceDebounceTimer = null;
let freestyleGamepadIndex = null;
let freestyleGamepadPollHandle = null;
let freestyleLastGamepadInputTime = 0;
const FREESTYLE_GAMEPAD_DEBOUNCE_MS = 300;
const FREESTYLE_UI_TEXT_DEFAULTS = {
    baseTitle: 'Free Style Communication',
    baseTitleShort: 'Free Style',
    exitFreestyle: 'Exit Freestyle',
    buildSpace: 'Build Space',
    buildMessagePlaceholder: 'Build your message here...',
    speakDisplay: 'Speak Display',
    backspace: 'Backspace',
    clearDisplay: 'Clear Display',
    cleanUp: 'Clean Up',
    newRow: 'New Row',
    goBack: 'Go Back',
    somethingElse: 'Something Else',
    somethingElseAz: 'Something Else A-Z',
    suggestedWords: 'Suggested Words',
    tools: 'Tools',
    wordCategories: 'Word Categories',
    spelling: 'Spelling',
    numbers: 'Numbers',
    numbersAdd: 'Add',
    numbersReset: 'Reset to',
    actionSection: 'Action',
    chooseWordSection: 'Choose Word',
    loading: 'Loading...',
    // Audio prompts spoken to the user
    promptDisplayEmpty: 'Display is empty.',
    promptUnableToSpeak: 'Unable to speak display right now.',
    promptStartedNewRow: 'Started new row.',
    promptUnableToStartRow: 'Unable to start a new row right now.',
    promptNoOtherOptions: 'I could not find other word options.',
    promptNoMoreNumbers: 'No more numbers in this range.'
};
let freestyleUiText = { ...FREESTYLE_UI_TEXT_DEFAULTS };

// Load settings once: extracts LLM options, autoClean, AND precomputed translation bundle.
// Page always shows immediately with English defaults; labels swap to translated values
// as soon as settings are available (no blank screen, no live translation API call).
async function loadFreestyleSettings() {
    try {
        const settingsResponse = await authenticatedFetch('/api/settings');
        if (!settingsResponse.ok) {
            return;
        }

        const settings = await settingsResponse.json();

        // Apply LLM / behaviour options
        const freestyleOptions = Number(settings.FreestyleOptions);
        const composeOptions = Number(settings.LLMOptions);
        if (!Number.isNaN(freestyleOptions) && freestyleOptions > 0) {
            LLMOptions = freestyleOptions;
        } else if (!Number.isNaN(composeOptions) && composeOptions > 0) {
            LLMOptions = composeOptions;
        }
        freestyleAutoClean = settings.autoClean === true;

        // Apply precomputed translation bundle if available (populated by admin Translate Pages).
        // If a legacy bundle is missing newer keys, backfill only the missing values with
        // a small one-off translation request so newly added labels do not stay in English.
        const targetLocale = String(settings?.userLanguage || 'en-US').trim() || 'en-US';
        if (targetLocale.toLowerCase() !== 'en-us') {
            const pretranslated = settings?.specialPageTranslations?.freestyle?.[targetLocale];
            const missingKeys = [];

            if (pretranslated && typeof pretranslated === 'object') {
                Object.keys(FREESTYLE_UI_TEXT_DEFAULTS).forEach((key) => {
                    const candidate = String(pretranslated[key] || '').trim();
                    if (candidate) {
                        freestyleUiText[key] = candidate;
                    } else {
                        missingKeys.push(key);
                    }
                });
            } else {
                // No saved bundle yet for this locale. Leave defaults in place rather than
                // blocking first paint with a full-page translation request.
                return;
            }

            if (missingKeys.length > 0) {
                const response = await authenticatedFetch('/api/translate-lines', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        lines: missingKeys.map((key) => FREESTYLE_UI_TEXT_DEFAULTS[key]),
                        source_locale: 'en-US',
                        target_locale: targetLocale
                    })
                });

                if (response.ok) {
                    const payload = await response.json();
                    const translatedLines = Array.isArray(payload.translated_lines) ? payload.translated_lines : [];
                    missingKeys.forEach((key, index) => {
                        const translatedValue = String(translatedLines[index] || '').trim();
                        if (translatedValue) {
                            freestyleUiText[key] = translatedValue;
                        }
                    });
                }
            }
        }
    } catch (error) {
        console.error('Failed to load freestyle settings:', error);
    }
}


function applyFreestyleLocalization() {
    const setText = (id, value) => {
        const element = document.getElementById(id);
        if (element) {
            element.textContent = value;
        }
    };

    setText('exit-creation-btn', freestyleUiText.exitFreestyle);
    setText('read-creation-btn', freestyleUiText.speakDisplay);
    setText('backspace-btn', freestyleUiText.backspace);
    setText('clear-word-btn', freestyleUiText.clearDisplay);
    setText('ai-edit-btn', freestyleUiText.cleanUp);
    setText('new-row-btn', freestyleUiText.newRow);
    setText('action-go-back-btn', freestyleUiText.goBack);
    setText('words-section-title', freestyleUiText.suggestedWords);
    setText('tool-panel-title', freestyleUiText.wordCategories);
    setText('categories-tool-btn', freestyleUiText.wordCategories);
    setText('spelling-tool-btn', freestyleUiText.spelling);
    setText('numbers-tool-btn', freestyleUiText.numbers);

    const buildSpaceTitle = document.querySelector('#action-section .section-title');
    if (buildSpaceTitle) {
        buildSpaceTitle.textContent = freestyleUiText.buildSpace;
    }

    const toolsTitle = document.querySelector('#tool-toggle-section .section-title');
    if (toolsTitle) {
        toolsTitle.textContent = freestyleUiText.tools;
    }

    const buildSpaceInput = document.getElementById('current-word');
    if (buildSpaceInput) {
        buildSpaceInput.placeholder = freestyleUiText.buildMessagePlaceholder;
    }

    const loadingText = document.querySelector('#loading-indicator p');
    if (loadingText) {
        loadingText.textContent = freestyleUiText.loading;
    }

    // Compose runtime creates some standard labels dynamically; provide localized
    // values through body dataset so compose_create.js can render them in locale.
    document.body.dataset.composeGoBack = freestyleUiText.goBack;
    document.body.dataset.composeSuggestedWords = freestyleUiText.suggestedWords;
    document.body.dataset.composeSomethingElse = freestyleUiText.somethingElse;
    document.body.dataset.composeSomethingElseAz = freestyleUiText.somethingElseAz;
    document.body.dataset.numbersAdd = freestyleUiText.numbersAdd;
    document.body.dataset.numbersReset = freestyleUiText.numbersReset;

    // If prediction buttons were already rendered before localization completed,
    // update them in place now.
    document.querySelectorAll('#word-predictions [data-standard-option-type]').forEach((button) => {
        const optionType = String(button.dataset.standardOptionType || '').trim();
        if (optionType === 'go-back') {
            button.textContent = freestyleUiText.goBack;
        } else if (optionType === 'something-else') {
            button.textContent = freestyleUiText.somethingElse;
        } else if (optionType === 'something-else-az') {
            button.textContent = freestyleUiText.somethingElseAz;
        }
    });

    // Keep title in sync if compose logic already set it.
    if (typeof updateWordsSectionTitle === 'function') {
        updateWordsSectionTitle();
    }

    // Section-level scan prompts are spoken by compose_create.js.
    // Set explicit localized labels so scanning does not fall back to hardcoded English.
    const actionSection = document.getElementById('action-section');
    if (actionSection) {
        actionSection.dataset.scanLabel = String(
            freestyleUiText.actionSection || freestyleUiText.buildSpace || 'Action'
        );
    }

    const chooseWordSection = document.getElementById('choose-word-section');
    if (chooseWordSection) {
        chooseWordSection.dataset.scanLabel = String(
            freestyleUiText.chooseWordSection || freestyleUiText.suggestedWords || 'Choose Word'
        );
    }

    const toolToggleSection = document.getElementById('tool-toggle-section');
    if (toolToggleSection) {
        toolToggleSection.dataset.scanLabel = String(
            freestyleUiText.tools || 'Tools'
        );
    }
}

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

        let baseTitle = freestyleUiText.baseTitle;
        const navContext = getFreestyleNavigationContext();
        if (navContext.originatingButton && navContext.isLlmGenerated) {
            baseTitle = `${freestyleUiText.baseTitleShort} - ${navContext.originatingButton}`;
        } else if (navContext.sourcePage && navContext.sourcePage.toLowerCase() !== 'home') {
            const pageName = navContext.sourcePage
                .replace(/_/g, ' ')
                .replace(/-/g, ' ')
                .replace(/\b\w/g, (char) => char.toUpperCase());
            baseTitle = `${freestyleUiText.baseTitleShort} - ${pageName}`;
        }

        titleElement.textContent = currentProfile?.display_name
            ? `${baseTitle} - ${currentProfile.display_name}`
            : baseTitle;
    } catch (error) {
        console.error('Failed to update freestyle page title:', error);
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

function freestyleStartsWithLetterFilter(word, selectedLetter) {
    const trimmedWord = String(word || '').trim();
    if (!trimmedWord || !selectedLetter) return false;
    const normalizedStart = trimmedWord.replace(/^[^a-zA-Z]+/, '');
    return normalizedStart.toLowerCase().startsWith(String(selectedLetter).toLowerCase());
}

async function requestFreestyleGeneralWords(requestDifferentOptions = false, requestOptions = {}) {
    const startsWithLetter = String(requestOptions?.startsWithLetter || '').trim();
    const requestedOptionCount = startsWithLetter
        ? Math.min(50, Math.max(24, Math.max(1, LLMOptions) * 4))
        : Math.max(1, LLMOptions);
    const payload = {
        ...getFreestyleRequestPayloadBase(),
        build_space_text: getCombinedBuildText().trim(),
        single_words_only: true,
        request_different_options: requestDifferentOptions,
        max_options: requestedOptionCount
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
        const parsedWords = options
            .map((item) => (typeof item === 'object' && item?.text ? item.text : item))
            .filter((item) => typeof item === 'string' && item.trim() !== '')
            .slice(0, requestedOptionCount);

        const nextWords = startsWithLetter
            ? parsedWords.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter)).slice(0, Math.max(1, LLMOptions))
            : parsedWords.slice(0, Math.max(1, LLMOptions));

        const fallbackWords = isStartingNewSentence()
            ? getSentenceStarterFallbackWords()
            : ['I', 'want', 'need', 'can', 'please', 'help', 'yes', 'no']
                .slice(0, Math.max(1, LLMOptions));

        const filteredFallbackWords = startsWithLetter
            ? fallbackWords.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter))
            : fallbackWords;

        currentPredictions = nextWords.length > 0 ? nextWords : filteredFallbackWords;
        renderWordPredictions();
        return nextWords.length > 0;
    } catch (error) {
        console.error('Failed to load freestyle general words with context:', error);
        const fallbackWords = isStartingNewSentence()
            ? getSentenceStarterFallbackWords()
            : ['I', 'want', 'need', 'can', 'please', 'help', 'yes', 'no']
                .slice(0, Math.max(1, LLMOptions));
        const filteredFallbackWords = startsWithLetter
            ? fallbackWords.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter))
            : fallbackWords;
        currentPredictions = filteredFallbackWords;
        renderWordPredictions();
        return false;
    }
}

requestCategoryWordsWithExclusions = async function(category, customPrompt, fallbackWords = [], excludeWords = [], requestOptions = {}) {
    const startsWithLetter = String(requestOptions?.startsWithLetter || '').trim();
    const requestedOptionCount = startsWithLetter
        ? Math.min(50, Math.max(24, Math.max(1, LLMOptions) * 4))
        : Math.max(1, LLMOptions);
    const basePrompt = String(customPrompt || '').trim();
    const promptWithLetterConstraint = startsWithLetter
        ? `${basePrompt}\n\nSTARTING LETTER REQUIREMENT:\n- Every option text must begin with '${startsWithLetter}' (case-insensitive).\n- Do not return options that start with any other letter.`
        : basePrompt;
    const filteredFallbackWords = startsWithLetter
        ? fallbackWords.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter))
        : fallbackWords;

    const payload = {
        ...getFreestyleRequestPayloadBase(),
        category,
        max_options: requestedOptionCount,
        build_space_content: getCombinedBuildText().trim(),
        exclude_words: excludeWords,
        custom_prompt: promptWithLetterConstraint
    };

    try {
        const response = await authenticatedFetch('/api/freestyle/category-words', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            currentPredictions = filteredFallbackWords;
            renderWordPredictions();
            return false;
        }

        const data = await response.json();
        const rawWords = Array.isArray(data.words) ? data.words : [];
        const parsedWords = rawWords
            .map((item) => (typeof item === 'object' && item?.text ? item.text : item))
            .filter((item) => typeof item === 'string' && item.trim() !== '')
            .slice(0, requestedOptionCount);

        const nextWords = startsWithLetter
            ? parsedWords.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter)).slice(0, Math.max(1, LLMOptions))
            : parsedWords.slice(0, Math.max(1, LLMOptions));

        currentPredictions = nextWords.length > 0 ? nextWords : filteredFallbackWords;
        renderWordPredictions();
        return nextWords.length > 0;
    } catch (error) {
        console.error('Failed to load freestyle category words with context:', error);
        currentPredictions = filteredFallbackWords;
        renderWordPredictions();
        return false;
    }
};

buildCategorySpecificPrompt = buildFreestyleCategoryPrompt;

loadGeneralWords = async function(excludeWords = [], fallbackWordsOverride = null, requestOptions = {}) {
    const startsWithLetter = String(requestOptions?.startsWithLetter || '').trim();
    const didLoadWords = await requestFreestyleGeneralWords(Boolean(excludeWords?.length), requestOptions);
    if (!didLoadWords && fallbackWordsOverride) {
        currentPredictions = startsWithLetter
            ? fallbackWordsOverride.filter((item) => freestyleStartsWithLetterFilter(item, startsWithLetter))
            : fallbackWordsOverride;
        renderWordPredictions();
    }
    return didLoadWords;
};

async function speakDisplayFromFreestyle() {
    const currentText = getCombinedBuildText().trim();
    if (!currentText) {
        if (typeof announcePartnerFacingOutput === 'function') {
            await announcePartnerFacingOutput(freestyleUiText.promptDisplayEmpty, false, true);
        } else {
            await announce(freestyleUiText.promptDisplayEmpty, 'system', false, true);
        }
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

        if (typeof announcePartnerFacingOutput === 'function') {
            await announcePartnerFacingOutput(textToSpeak, false, true);
        } else {
            await announce(textToSpeak, 'system', false, true);
        }
        recordToSpeechHistory(textToSpeak);
    } catch (error) {
        console.error('Failed to speak freestyle display:', error);
        if (typeof announcePartnerFacingOutput === 'function') {
            await announcePartnerFacingOutput(freestyleUiText.promptUnableToSpeak, false, true);
        } else {
            await announce(freestyleUiText.promptUnableToSpeak, 'system', false, true);
        }
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
    try {
        // Load settings (LLM options + precomputed translation bundle) in one fetch,
        // then apply labels before revealing localized text.
        await loadFreestyleSettings();
        applyFreestyleLocalization();
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
    } finally {
        document.body.classList.remove('freestyle-localization-pending');
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initializeFreestyleOverrides().catch((error) => {
        console.error('Failed to initialize freestyle overrides:', error);
    });
});