// --- Global Variables ---
let currentlyScannedButton = null; // Tracks the currently highlighted button
let lastGamepadInputTime = 0; // For gamepad debounce/rate limiting
let querytype = null; // Stores the type of query (e.g., 'question', 'currentevents')
let eventtype = null; // Stores specific event type if needed
let isLLMProcessing = false; // Flag to detect if LLM query is running
const clickDebounceDelay = 300; // Debounce for button clicks (adjust as needed)
let defaultDelay = 3500; // Default auditory scan delay (ms) - Loaded from settings
let currentQuestion = null; // Stores the current question context for LLM
let currentOptions = []; // Stores the current LLM-generated options for Something Else functionality
let scanningInterval; // Holds the interval ID for scanning
const GRID_SWITCH_PROMPT_SHOWN_KEY = 'bravoSwitchPromptShown_grid';
const FOLLOW_UP_CONVERSATION_KEY = 'llm_followUpConversation';
let followUpConversation = {
    originalQuestion: null,
    selectedResponses: []
};

const COMPOSE_SESSION_STORAGE_KEY = 'bravoComposeSession';
const COMPOSE_PENDING_APPEND_KEY = 'bravoComposePendingAppend';
const EMAIL_SESSION_STORAGE_KEY = 'bravoEmailSession';
let composeSession = null;
let emailSession = null;
let composeMenuActionInProgress = false;

function loadEmailSession() {
    try {
        const parsed = JSON.parse(sessionStorage.getItem(EMAIL_SESSION_STORAGE_KEY) || '{}');
        if (!parsed || typeof parsed !== 'object') {
            return {
                active: false,
                mode: 'menu',
                recipientEmail: '',
                recipientName: '',
                sourceFrom: null,
                threadId: '',
                inReplyTo: '',
                references: ''
            };
        }

        return {
            active: parsed.active === true,
            mode: parsed.mode || 'menu',
            recipientEmail: parsed.recipientEmail || '',
            recipientName: parsed.recipientName || '',
            sourceFrom: parsed.sourceFrom || null,
            threadId: parsed.threadId || '',
            inReplyTo: parsed.inReplyTo || '',
            references: parsed.references || ''
        };
    } catch (error) {
        console.warn('Failed to parse email session:', error);
        return {
            active: false,
            mode: 'menu',
            recipientEmail: '',
            recipientName: '',
            sourceFrom: null,
            threadId: '',
            inReplyTo: '',
            references: ''
        };
    }
}

function saveEmailSession() {
    if (!emailSession) return;
    sessionStorage.setItem(EMAIL_SESSION_STORAGE_KEY, JSON.stringify(emailSession));
}

function clearEmailSession() {
    emailSession = {
        active: false,
        mode: 'menu',
        recipientEmail: '',
        recipientName: '',
        sourceFrom: null,
        threadId: '',
        inReplyTo: '',
        references: ''
    };
    sessionStorage.removeItem(EMAIL_SESSION_STORAGE_KEY);
}

function isEmailSessionActive() {
    return Boolean(emailSession && emailSession.active === true);
}

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
        console.warn('Failed to parse compose session:', error);
        return { active: false, documentId: null, title: '', text: '', startedAt: null, sourceFrom: null };
    }
}

function saveComposeSession() {
    if (!composeSession) return;
    sessionStorage.setItem(COMPOSE_SESSION_STORAGE_KEY, JSON.stringify(composeSession));
}

function clearComposeSession() {
    composeSession = { active: false, documentId: null, title: '', text: '', startedAt: null, sourceFrom: null };
    sessionStorage.removeItem(COMPOSE_SESSION_STORAGE_KEY);
    updateSpeechHistoryPanel(); // Restore Speech History label and values
    updateStatusBar(''); // Clear compose status from bar
}

function isComposeSessionActive() {
    return Boolean(composeSession && composeSession.active === true);
}

function appendToComposeText(text) {
    const normalized = String(text || '').replace(/\[PAUSE\]/g, ' ').replace(/\s+/g, ' ').trim();
    if (!normalized || !isComposeSessionActive()) return;

    const existing = String(composeSession.text || '').trim();
    composeSession.text = existing ? `${existing} ${normalized}` : normalized;
    saveComposeSession();
    updateSpeechHistoryPanel(); // Keep Compose box in sync
}

function consumePendingComposeAppends() {
    const raw = localStorage.getItem(COMPOSE_PENDING_APPEND_KEY);
    if (!raw) return;

    let items = [];
    try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
            items = parsed;
        }
    } catch (error) {
        console.warn('Unable to parse pending compose appends:', error);
    }

    if (!items.length || !isComposeSessionActive()) {
        return;
    }

    let didAppend = false;
    items.forEach((item) => {
        const text = String(item || '').trim();
        if (!text) return;
        appendToComposeText(text);
        didAppend = true;
    });

    if (didAppend) {
        localStorage.removeItem(COMPOSE_PENDING_APPEND_KEY);
    }
}

function getComposePromptContext() {
    if (!isComposeSessionActive()) return '';
    const compositionText = String(composeSession.text || '').trim();
    if (!compositionText) return '';
    return `\n\nCREATION CONTEXT:\nThe user is actively creating a letter. Prioritize options that continue or refine this creation:\n"${compositionText}"\nKeep continuity with this creation.`;
}

/**
 * Show or clear the sticky #status-bar at the bottom of the screen.
 * @param {string} message  - Text to display; empty string hides the bar.
 * @param {boolean} isListening - When true, applies the green "listening" style.
 */
function updateStatusBar(message = '', isListening = false) {
    const bar = document.getElementById('status-bar');
    if (!bar) return;
    if (message) {
        bar.textContent = message;
        bar.style.display = 'block';
        bar.classList.toggle('listening', isListening);
    } else {
        bar.textContent = '';
        bar.style.display = 'none';
        bar.classList.remove('listening');
    }
}

/**
 * Switch the Speech History panel between "Speech History" mode and
 * "Create" mode based on whether a compose session is currently active.
 * Safe to call at any time.
 */
function updateSpeechHistoryPanel() {
    const label = document.getElementById('speech-history-label');
    const textarea = document.getElementById('speech-history');
    if (!label || !textarea) return;

    if (isComposeSessionActive()) {
        label.textContent = isEmailSessionActive() ? 'Email:' : 'Create:';
        textarea.value = String(composeSession.text || '');
    } else {
        label.textContent = 'Speech History:';
        const userId = (typeof currentAacUserId !== 'undefined' && currentAacUserId)
            ? currentAacUserId : '__default__';
        const stored = localStorage.getItem(`speechHistory_${userId}`) || '';
        textarea.value = stored;
    }
}

function syncComposeSessionFromStorage() {
    composeSession = loadComposeSession();
    consumePendingComposeAppends();
    updateSpeechHistoryPanel();
}

composeSession = loadComposeSession();
emailSession = loadEmailSession();

// Restore querytype and currentQuestion from localStorage if available
if (localStorage.getItem('llm_currentQueryType')) {
    querytype = localStorage.getItem('llm_currentQueryType');
    console.log('Restored querytype from storage:', querytype);
}
if (localStorage.getItem('llm_currentQuestion')) {
    currentQuestion = localStorage.getItem('llm_currentQuestion');
    console.log('Restored currentQuestion from storage:', currentQuestion);
}
if (localStorage.getItem('llm_currentOptions')) {
    try {
        currentOptions = JSON.parse(localStorage.getItem('llm_currentOptions'));
        console.log('Restored currentOptions from storage:', currentOptions.length, 'options');
    } catch (e) {
        console.warn('Failed to parse currentOptions from storage:', e);
        currentOptions = [];
    }
}
if (localStorage.getItem(FOLLOW_UP_CONVERSATION_KEY)) {
    try {
        const storedConversation = JSON.parse(localStorage.getItem(FOLLOW_UP_CONVERSATION_KEY));
        if (storedConversation && typeof storedConversation === 'object') {
            followUpConversation.originalQuestion = typeof storedConversation.originalQuestion === 'string'
                ? storedConversation.originalQuestion
                : null;
            followUpConversation.selectedResponses = Array.isArray(storedConversation.selectedResponses)
                ? storedConversation.selectedResponses.filter(item => typeof item === 'string' && item.trim() !== '')
                : [];
        }
        console.log('Restored follow-up conversation:', followUpConversation);
    } catch (e) {
        console.warn('Failed to parse follow-up conversation from storage:', e);
        followUpConversation = { originalQuestion: null, selectedResponses: [] };
    }
}
let currentButtonIndex = -1; // Tracks the index for scanning
let scanCycleCount = 0; // Tracks how many complete cycles have been performed
let scanLoopLimit = 0; // 0 = unlimited, 1-10 = limit cycles
let isPausedFromScanLimit = false; // Flag to track if scanning is paused due to scan limit
// --- NEW: Row-Column Scanning Variables ---
let currentScanPattern = 'column'; // 'column' or 'row-column'
let currentRowScanMode = false; // true if currently in row-scan phase
let currentRow = -1; // Current row being scanned (-1 = not in row mode)
let currentButtonInRow = -1; // Current button index within the row
let rowLoopCount = 0; // Tracks row-scan cycles for row-pattern
let columnLoopCount = 0; // Tracks column-scan cycles for row-pattern
let gamepadIndex = null; // To store the index of the connected gamepad
let gamepadPollInterval = null; // Interval ID for gamepad polling
const ANNOUNCE_RELOAD_DELAY = 2000; // Delay in ms after announce before reload (adjust as needed)
// --- NEW: Wake Word Variables ---
let wakeWordInterjection = "hey"; // Default interjection (lowercase)
let wakeWordName = "bravo";       // Default name (lowercase)
let LLMOptions = 10; // Default number of options to generate
let ScanningOff = false; // Default scanning state
let scanMode = 'auto'; // auto | step
let waitForSwitchToScan = false; // Default wait for switch state
let suppressSwitchActivationUntil = 0; // Timestamp guard to prevent immediate button activation after starting scan
let SummaryOff = false; // Default summary state
let gridColumns = 10; // Default number of grid columns for button sizing
const QUESTION_TEXTAREA_ID = 'question-display'; // ID of the question textarea
const LISTENING_HIGHLIGHT_CLASS = 'highlight-listening'; // CSS class for highlighting
let activeOriginatingButtonText = null; // NEW: To store the text of the button that initiated the LLM query
let activeLLMPromptForContext = null; // Store the prompt that generated current LLM buttons

function persistFollowUpConversation() {
    localStorage.setItem(FOLLOW_UP_CONVERSATION_KEY, JSON.stringify(followUpConversation));
}

function resetFollowUpConversation() {
    followUpConversation = {
        originalQuestion: null,
        selectedResponses: []
    };
    localStorage.removeItem(FOLLOW_UP_CONVERSATION_KEY);
}

function initializeFollowUpConversation(questionText) {
    const normalizedQuestion = typeof questionText === 'string' ? questionText.trim() : '';
    if (!normalizedQuestion) {
        resetFollowUpConversation();
        return;
    }

    followUpConversation = {
        originalQuestion: normalizedQuestion,
        selectedResponses: []
    };
    persistFollowUpConversation();
}

function addFollowUpSelection(selectionText) {
    const normalizedSelection = typeof selectionText === 'string' ? selectionText.trim() : '';
    if (!normalizedSelection) return;

    if (!followUpConversation.originalQuestion && currentQuestion) {
        followUpConversation.originalQuestion = currentQuestion;
    }

    followUpConversation.selectedResponses.push(normalizedSelection);
    persistFollowUpConversation();
}

function getConversationContextText() {
    const baseQuestion = followUpConversation.originalQuestion || currentQuestion || '';
    const history = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];

    if (!baseQuestion) return '';

    const historyText = history.length > 0
        ? history.map((response, index) => `${index + 1}. ${response}`).join('\n')
        : 'None yet';

    return `Original question: "${baseQuestion}"\nSelected follow-ups so far:\n${historyText}`;
}

function classifyCommunicationType(text) {
    const normalized = text.toLowerCase().trim();
    
    // Greeting patterns: hello, hi, hey, goodbye, etc.
    if (/^\b(hello|hi|hey|goodbye|bye|good morning|good afternoon|good evening|howdy)\b/.test(normalized)) {
        return 'greeting';
    }
    
    // Question patterns: ends with ? or starts with question words
    if (/\?$/.test(normalized) || /^\b(what|why|how|when|where|who|which|do|does|did|can|could|will|would|should|is|are|am|have|has|had|will)\b/.test(normalized)) {
        return 'question';
    }
    
    // Request patterns: want, need, can you, will you, let's
    if (/\b(want|need|can you|could you|will you|would you|let's|let me|i need|i want|please|can i|could i)\b/.test(normalized)) {
        return 'request';
    }
    
    // Answer patterns: yes, no, yeah, nope, sure, etc.
    if (/^\b(yes|no|yeah|yep|nope|sure|definitely|absolutely|maybe|perhaps|probably)\b|\b(yes|no)$/.test(normalized)) {
        return 'answer';
    }
    
    // Joke/humor patterns: common joke/funny signals
    if (/\b(haha|lol|lmao|funny|joke|made me laugh|that's hilarious|isn't that funny)\b/.test(normalized)) {
        return 'joke';
    }
    
    // Affirmation patterns: positive self-assertions
    if (/\b(i am strong|i can do|i'm amazing|i'm great|i'm capable|i'm confident|proud of)\b/.test(normalized)) {
        return 'affirmation';
    }
    
    // Default: assertion/opinion (statements of fact, feeling, or opinion)
    return 'assertion';
}

function classifyFollowUpGuidance(communicationType) {
    const guidance = {
        greeting: {
            description: 'The user greeted someone. Follow-ups should respond appropriately.',
            patterns: [
                'How are you doing?',
                'Where have you been?',
                'What have you been up to?',
                'Good to see you!',
                'I missed you!',
                'What have you been doing?'
            ]
        },
        assertion: {
            description: 'The user made a statement or shared an opinion. Follow-ups should engage the other person at the same level.',
            patterns: [
                'What do you think about that?',
                'Do you agree?',
                'Have you experienced that too?',
                'Would you like to do that with me?',
                'I like that because...',
                'That reminds me of...'
            ]
        },
        question: {
            description: 'The user asked a question. Follow-ups should provide alternatives, clarifications, or related questions.',
            patterns: [
                'Is it something fun?',
                'Can we find that out together?',
                'Let\'s figure it out',
                'I\'m curious about that too',
                'Do you know?',
                'Should we ask someone?'
            ]
        },
        request: {
            description: 'The user made a request or expressed a want. Follow-ups should expand the idea or get partner input.',
            patterns: [
                'Do you want to go with me?',
                'When can we do that?',
                'What do you think about that?',
                'Can we start planning that?',
                'I hope we can do that soon',
                'Do you want to do that too?'
            ]
        },
        answer: {
            description: 'The user gave an answer (yes/no/maybe). Follow-ups should continue the conversation or explain the answer.',
            patterns: [
                'I don\'t want to do that',
                'Maybe we could try this instead',
                'Here\'s why I think that',
                'Would you do that?',
                'What would you do?',
                'Can we talk about why?'
            ]
        },
        joke: {
            description: 'The user shared humor. Follow-ups should engage with the joke or build on the playfulness.',
            patterns: [
                'Isn\'t that funny?',
                'Do you like jokes like that?',
                'Did that make you laugh?',
                'I love when we laugh together',
                'Tell me another funny one!',
                'You\'re so funny!'
            ]
        },
        affirmation: {
            description: 'The user made a positive self-statement. Follow-ups should reinforce or build on that positivity.',
            patterns: [
                'You\'re amazing!',
                'I\'m proud of you too',
                'You\'re strong too',
                'That\'s awesome!',
                'I believe in you',
                'We\'re both great!'
            ]
        }
    };
    return guidance[communicationType] || guidance.assertion;
}

function getActiveSessionMoodText() {
    let mood = '';

    if (typeof window.getCurrentMood === 'function') {
        try {
            mood = window.getCurrentMood() || '';
        } catch (error) {
            console.warn('Unable to read mood from getCurrentMood():', error);
        }
    }

    if (!mood) {
        mood = sessionStorage.getItem('currentSessionMood') || '';
    }

    const normalizedMood = typeof mood === 'string' ? mood.trim() : '';
    if (!normalizedMood || normalizedMood.toLowerCase() === 'none') {
        return '';
    }

    return `Current user mood for this session: "${normalizedMood}". Keep follow-up options naturally consistent with this mood.`;
}

function isPartnerInterrogativePattern(text) {
    // Detects options that sound like the PARTNER questioning/interviewing the user about their own statement
    // These should NEVER be generated as follow-up options from the user's perspective
    
    if (!text || typeof text !== 'string') return false;
    const normalized = text.toLowerCase().trim();
    
    // DEBUG: Log what we're checking
    console.log(`🔍 Checking option: "${text}"`);
    
    // Get latest user response to check context
    const latestResponse = Array.isArray(followUpConversation.selectedResponses) && followUpConversation.selectedResponses.length > 0
        ? followUpConversation.selectedResponses[followUpConversation.selectedResponses.length - 1]
        : '';
    const latestWasUserAssertion = /^i\b/i.test(latestResponse);
    
    console.log(`   Latest response: "${latestResponse}"`);
    console.log(`   Was user assertion (started with "I"): ${latestWasUserAssertion}`);
    
    // BROAD CATCH-ALL: If user just made a statement about themselves (started with "I"),
    // block ANY option asking them to elaborate on that statement
    if (latestWasUserAssertion) {
        // Block "tell me" phrases entirely after user assertion
        if (/\btell me\b/i.test(normalized)) {
            console.warn('🚫 BLOCKED: "tell me" phrase after user assertion:', text);
            return true;
        }
        
        // Block "what's making you" or "what is making you" 
        if (/what('s| is) making you/i.test(normalized)) {
            console.warn('🚫 BLOCKED: "what\'s making you" after user assertion:', text);
            return true;
        }
        
        // Block "what makes you"
        if (/what makes you/i.test(normalized)) {
            console.warn('🚫 BLOCKED: "what makes you" after user assertion:', text);
            return true;
        }
        
        // Block "share more" / "describe" / "explain"
        if (/^(share more|describe|explain)/i.test(normalized)) {
            console.warn('🚫 BLOCKED: explain/describe pattern after user assertion:', text);
            return true;
        }
    }
    
    // Block therapy/interview patterns regardless of context
    if (/^(why are you|why do you|how does (that|it|this) make you feel|how are you feel)/i.test(normalized)) {
        console.warn('🚫 BLOCKED: therapy/interview pattern:', text);
        return true;
    }
    
    // Block "what kind of ... are you"
    if (/^what kind of .+ are you/i.test(normalized)) {
        console.warn('🚫 BLOCKED: "what kind of ... are you" pattern:', text);
        return true;
    }
    
    // Block "can you tell me"
    if (/^can you tell me/i.test(normalized)) {
        console.warn('🚫 BLOCKED: "can you tell me" pattern:', text);
        return true;
    }
    
    console.log(`   ✅ Option passed filter`);
    return false;
}

function buildFollowUpPrompt(excludedOptionsText = '') {
    const summaryInstruction = SummaryOff
        ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
        : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';

    const conversationContext = getConversationContextText();
    const selectedResponses = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];
    const latestSelectedResponse = selectedResponses.length > 0
        ? selectedResponses[selectedResponses.length - 1]
        : '';
    
    // Classify communication type and get guidance
    const communicationType = latestSelectedResponse
        ? classifyCommunicationType(latestSelectedResponse)
        : 'assertion';
    const typeGuidance = classifyFollowUpGuidance(communicationType);
    
    const moodLine = getActiveSessionMoodText();
    const exclusionLine = excludedOptionsText && excludedOptionsText.trim()
        ? `Avoid repeating these existing options: "${excludedOptionsText}".`
        : '';
    const latestFocusLine = latestSelectedResponse
        ? `Latest selected response (PRIMARY FOCUS): "${latestSelectedResponse}".`
        : '';
    const composePromptContext = getComposePromptContext();
    
    // Build type-specific pattern examples
    const typePatternExamples = typeGuidance.patterns
        .slice(0, 4)
        .map(pattern => `  • ${pattern}`)
        .join('\n');

    return `
AAC COMMUNICATION SYSTEM - GENERATING USER'S NEXT SPEECH OPTIONS

SCENARIO:
An AAC user is having a conversation. They select pre-written options to speak.
The user has ALREADY SPOKEN the following words out loud to their communication partner:
${conversationContext}
Most recently, the user JUST SAID OUT LOUD: "${latestSelectedResponse}"

YOUR TASK:
Generate ${LLMOptions} MORE things the SAME user can SAY, ASK, BUILD, or EXPOUND next to continue THEIR speaking turn.
These are OPTIONS FOR THE USER TO SELECT AND SPEAK (including statements and partner-engagement questions), not responses TO the user.

🚫🚫🚫 CRITICAL ERROR TO AVOID 🚫🚫🚫

The user JUST SAID: "I am over the moon with excitement!"

DO NOT GENERATE: "Tell me more about what makes you feel this way!"
WHY THIS IS WRONG: The user JUST expressed excitement. They don't ask THEMSELVES to tell them more about their own feeling. That would be the PARTNER asking the user a question.

DO NOT GENERATE: "What's making you so excited?"  
WHY THIS IS WRONG: The user doesn't ask themselves what's making them excited. That's the PARTNER questioning the user.

DO NOT GENERATE: "Tell me...", "What makes you...", "What's making you...", "Describe...", "Explain..."
WHY: These are PARTNER phrases asking the user to elaborate. The user doesn't interview themselves.

✅ CORRECT EXAMPLES - Generate options like these:

The user JUST SAID: "I am over the moon with excitement!"
GENERATE: "This is the best day ever!" ✅ (User expounding on their emotion)
GENERATE: "Do you want to celebrate with me?" ✅ (User inviting partner)
GENERATE: "I can't wait to do something fun!" ✅ (User continuing their expression)
GENERATE: "Are you excited too?" ✅ (User engaging partner)
GENERATE: "Something amazing just happened!" ✅ (User adding context)

COMMUNICATION TYPE: ${communicationType.toUpperCase()}
${typeGuidance.description}

PATTERN EXAMPLES FOR ${communicationType.toUpperCase()}:
${typePatternExamples}

RULES FOR GENERATION:
1. The user is SPEAKING, not being interviewed
2. The user is continuing THEIR turn (partner hasn't responded yet)
3. Generate things the user would SAY or ASK to engage the partner, not questions someone would ASK the user
4. Options should BUILD/EXPOUND on their point OR invite partner engagement
5. Keep options short, conversational, and natural
6. NO "Tell me", "What makes you", "Describe", "Explain" after user assertions
7. Include at least 4 partner-engagement QUESTIONS that end with "?" and invite the partner to respond

${moodLine}${exclusionLine}
${composePromptContext}
Return ONLY a JSON list where each item has "option", "summary", and "keywords" keys.
The "option" key should contain the FULL option text.
${summaryInstruction}
The "keywords" key should contain 3-5 words that match available symbols. Use these available descriptive words: good, great, happy, sad, angry, excited, tired, hungry, thirsty, hot, cold, big, small, fast, slow, easy, hard, fun, work, play, eat, drink, sleep, walk, run, read, write, look, listen, talk, help, love, like, want, need, more, less, yes, no, stop, go, come, here, there, up, down, in, out, on, off, open, close, new, old, clean, dirty, quiet, loud, light, dark. Focus on concrete, simple words rather than complex descriptives.
`;
}

function scoreUserVoicePerspective(optionText) {
    if (!optionText || typeof optionText !== 'string') return 0;
    const normalized = optionText.trim().toLowerCase();
    let score = 0;

    // Positive signals: sounds like the AAC user speaking.
    if (/^(i\b|i'm\b|i am\b|i want\b|i need\b|i feel\b|let('|’)s\b|can we\b|could we\b|tell me\b|show me\b)/i.test(optionText)) {
        score += 3;
    }

    if (/^(do you\b|have you\b|can you\b|would you\b|could you\b|what do you think\b|which do you\b|did you\b)/i.test(optionText)) {
        score += 4;
    }

    if (/\bwith me\b/i.test(optionText)) {
        score += 2;
    }

    // Reduce rigid planning-style prompts that feel less conversational in follow-ups.
    if (/^(what should i do\b|which (rides|one|park|option) should i\b)/i.test(optionText)) {
        score -= 3;
    }

    // Negative signals: sounds like the system/partner questioning the AAC user's prior response.
    const addressedToUserPatterns = [
        /\bwhat\s+is\s+it\s+you\s+find\b/i,
        /\bwhat\s+is\s+making\s+you\s+feel\b/i,
        /\bwhat\s+makes\s+you\s+feel\b/i,
        /\bwhy\s+did\s+you\s+choose\b/i,
        /\bwhy\s+are\s+you\s+feeling\b/i,
        /\bwhy\s+do\s+you\s+feel\b/i,
        /\bhow\s+does\s+that\s+make\s+you\s+feel\b/i,
        /\bhow\s+are\s+you\s+feeling\s+about\s+(that|this|your)\b/i,
        /\byour\s+answer\b/i,
        /\byou\s+selected\b/i,
        /\byou\s+chose\b/i
    ];

    for (const pattern of addressedToUserPatterns) {
        if (pattern.test(normalized)) {
            score -= 6;
        }
    }

    return score;
}

function startOrWaitForScanning({ allowPrompt = false, source = 'unknown' } = {}) {
    if (ScanningOff) {
        console.log(`🔇 Scanning is disabled (${source}).`);
        window.waitingForInitialSwitch = false;
        return;
    }

    const hasValidScannedButton = Boolean(
        currentlyScannedButton &&
        currentlyScannedButton.isConnected &&
        currentlyScannedButton.closest('#gridContainer')
    );

    if (currentlyScannedButton && !hasValidScannedButton) {
        console.log(`🧹 Clearing stale scanned button reference (${source}).`);
        currentlyScannedButton = null;
    }

    // If scanning is already active (auto: interval running; step: a button is highlighted),
    // don't disrupt it. This prevents the generateGrid setTimeout from re-entering the
    // "waiting for initial switch" state after the user has already started scanning.
    if (scanningInterval !== null || hasValidScannedButton) {
        console.log(`⏭️ Scanning already active — ignoring startOrWaitForScanning (${source}).`);
        return;
    }

    if (waitForSwitchToScan) {
        window.waitingForInitialSwitch = true;
        console.log(`✋ Waiting for switch press before scanning (${source}).`);

        const hasShownPrompt = sessionStorage.getItem(GRID_SWITCH_PROMPT_SHOWN_KEY) === 'true';
        if (allowPrompt && !hasShownPrompt) {
            sessionStorage.setItem(GRID_SWITCH_PROMPT_SHOWN_KEY, 'true');
            announce("Press switch to begin scanning", "personal", false, false);
        }
        return;
    }

    window.waitingForInitialSwitch = false;
    console.log(`▶️ Starting auditory scanning automatically (${source}).`);
    startAuditoryScanning();
}

function markScanningStartedFromSwitch() {
    suppressSwitchActivationUntil = Date.now() + 600;
}

function shouldSuppressSwitchActivation() {
    return Date.now() < suppressSwitchActivationUntil;
}

function handleSpacebarPress() {
    if (window.waitingForInitialSwitch) {
        console.log('Initial switch detected (spacebar) - starting scanning on gridpage');
        window.waitingForInitialSwitch = false;
        markScanningStartedFromSwitch();
        startAuditoryScanning();
        return;
    }

    if (shouldSuppressSwitchActivation()) {
        return;
    }

    if (currentlyScannedButton && !isLLMProcessing && !listeningForQuestion) {
        const buttonToActivate = currentlyScannedButton;
        console.log('Spacebar pressed, activating button:', buttonToActivate.textContent);
        buttonToActivate.click();
        buttonToActivate.classList.add('active');
        setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
        return;
    }

    if (isPausedFromScanLimit) {
        resumeAuditoryScanning();
        return;
    }

    const scanningIsIdle = scanningInterval === null && !currentlyScannedButton;
    if (scanningIsIdle) {
        markScanningStartedFromSwitch();
        startAuditoryScanning();
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

function isJokeQuestion(questionText) {
    if (!questionText) return false;
    const lowered = questionText.toLowerCase();
    return /\b(joke|jokes|funny|pun|dad joke|tell me a joke|make me laugh)\b/.test(lowered);
}

function tokenizeForContext(text) {
    if (!text || typeof text !== 'string') return [];
    const stopWords = new Set([
        'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'to', 'of', 'for', 'in', 'on', 'at', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'it', 'this', 'that', 'i', 'you', 'we', 'they', 'he', 'she',
        'do', 'does', 'did', 'want', 'wants', 'would', 'could', 'should', 'can', 'will', 'today', 'tonight', 'afternoon'
    ]);

    return text
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, ' ')
        .split(/\s+/)
        .map(token => token.trim())
        .filter(token => token.length > 1 && !stopWords.has(token));
}

function scoreOptionContextualFit(optionData, contextTerms, latestResponseTerms) {
    const optionText = typeof optionData.option === 'string' ? optionData.option : '';
    const summaryText = typeof optionData.summary === 'string' ? optionData.summary : '';
    const keywordText = Array.isArray(optionData.keywords) ? optionData.keywords.join(' ') : '';
    const combinedText = `${optionText} ${summaryText} ${keywordText}`;
    const optionTerms = tokenizeForContext(combinedText);
    const optionTermSet = new Set(optionTerms);

    let score = 0;
    for (const term of contextTerms) {
        if (optionTermSet.has(term)) score += 4;
    }
    for (const term of latestResponseTerms) {
        if (optionTermSet.has(term)) score += 6;
    }

    const wordCount = optionText.trim().split(/\s+/).filter(Boolean).length;
    if (wordCount >= 2 && wordCount <= 10) score += 1;
    if (wordCount > 14) score -= 2;

    if (/^i\s+want\s+to\b/i.test(optionText) || /^let('|’)s\b/i.test(optionText) || /^how about\b/i.test(optionText)) {
        score += 1;
    }

    // BOOST: Prioritize partner-engagement questions
    const partnerEngagementPatterns = [/^do you\b/i, /^would you\b/i, /^can you\b/i, /^could you\b/i, /^have you\b/i, /^what do you think\b/i, /^what do you feel\b/i, /^are you\b/i, /^should we\b/i, /^do you want\b/i, /^will you\b/i, /^do you like\b/i, /^what's your\b/i, /^who wants\b/i];
    if (partnerEngagementPatterns.some(pattern => pattern.test(optionText))) score += 8;

    // Prefer single selectable phrase over multi-sentence constructions.
    if ((optionText.match(/[.!?]/g) || []).length > 1) {
        score -= 2;
    }

    return score;
}

function prioritizeContextualOptions(options, contextText, maxCount = LLMOptions) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const contextTerms = tokenizeForContext(contextText || '');
    const latestResponse = Array.isArray(followUpConversation.selectedResponses) && followUpConversation.selectedResponses.length > 0
        ? followUpConversation.selectedResponses[followUpConversation.selectedResponses.length - 1]
        : '';
    const latestResponseTerms = tokenizeForContext(latestResponse);

    const scored = options.map((optionData, index) => ({
        optionData,
        index,
        score: scoreOptionContextualFit(optionData, contextTerms, latestResponseTerms)
    }));

    scored.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return a.index - b.index;
    });

    const selected = scored.slice(0, Math.max(1, maxCount)).map(item => item.optionData);
    console.log('Context prioritization scores:', scored.map(s => ({ idx: s.index, score: s.score, summary: s.optionData?.summary })));
    return selected;
}

function filterOptionsForUserVoicePerspective(options) {
    if (!Array.isArray(options)) return [];

    const selectedResponses = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];
    const latestSelectedResponse = selectedResponses.length > 0
        ? selectedResponses[selectedResponses.length - 1]
        : '';

    const mirroredToUserPatterns = [
        /^\s*what\s+is\s+making\s+you\s+feel\b/i,
        /^\s*what\s+makes\s+you\s+feel\b/i,
        /^\s*why\s+do\s+you\s+feel\b/i,
        /^\s*how\s+does\s+that\s+make\s+you\s+feel\b/i,
        /^\s*why\s+are\s+you\s+so\b/i
    ];

    const latestLooksFirstPerson = /^\s*(i\b|i\'m\b|i am\b|i feel\b|i want\b|i like\b|i love\b)/i.test(latestSelectedResponse || '');

    return options.filter(item => {
        const optionText = typeof item?.option === 'string' ? item.option.trim() : '';
        if (!optionText) return false;

        if (latestLooksFirstPerson && mirroredToUserPatterns.some(pattern => pattern.test(optionText))) {
            return false;
        }

        const perspectiveScore = scoreUserVoicePerspective(optionText);
        // Keep neutral and positive items; remove only strongly "addressed-to-user" phrasing.
        return perspectiveScore > -5;
    });
}

function ensurePartnerPerspectiveMix(options, maxCount = LLMOptions) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const selectedResponses = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];
    const latestSelectedResponse = selectedResponses.length > 0
        ? selectedResponses[selectedResponses.length - 1]
        : '';

    const isAssertion = /^\s*(i\b|i\'m\b|i am\b|i want\b|i like\b|i love\b|i feel\b)/i.test(latestSelectedResponse || '');
    if (!isAssertion) return options.slice(0, Math.max(1, maxCount));

    const partnerDirected = [];
    const otherOptions = [];

    for (const item of options) {
        const text = typeof item?.option === 'string' ? item.option.trim() : '';
        if (/^(do you\b|have you\b|would you\b|could you\b|can you\b|did you\b|what do you think\b)/i.test(text)) {
            partnerDirected.push(item);
        } else {
            otherOptions.push(item);
        }
    }

    const targetPartnerCount = Math.min(3, Math.max(1, Math.floor(Math.max(1, maxCount) / 3)));
    const prioritized = [
        ...partnerDirected.slice(0, targetPartnerCount),
        ...otherOptions,
        ...partnerDirected.slice(targetPartnerCount)
    ];

    return prioritized.slice(0, Math.max(1, maxCount));
}

function isQuestionLikeOption(text) {
    if (!text || typeof text !== 'string') return false;
    const trimmed = text.trim();
    if (!trimmed) return false;
    if (/[?]\s*$/.test(trimmed)) return true;
    return /^(do|does|did|are|is|can|could|would|will|have|has|should|what|which|when|where|why|how|who)\b/i.test(trimmed);
}

function buildPartnerQuestionFallbacks(latestSelectedResponse, neededCount) {
    const communicationType = classifyCommunicationType(latestSelectedResponse || '');
    const templatesByType = {
        assertion: [
            'What do you think about this?',
            'Do you agree with me?',
            'Have you felt this way too?',
            'Can we talk about this?',
            'What would you do in my place?'
        ],
        affirmation: [
            'Do you feel the same way?',
            'Would you agree with that?',
            'What do you think?',
            'Should we do that together?',
            'Do you want to join me?'
        ],
        request: [
            'Can you help me with this?',
            'Would you do this with me?',
            'Do you think this would work?',
            'Should we try this now?',
            'Can we do this together?'
        ],
        answer: [
            'Does that make sense to you?',
            'What do you think about that?',
            'Do you want to know more?',
            'Should I explain more?',
            'Do you agree with that?'
        ],
        joke: [
            'Do you think that is funny?',
            'Want to hear another one?',
            'Did that make you laugh?',
            'Do you have a joke too?',
            'Should I tell one more?'
        ],
        greeting: [
            'How are you doing today?',
            'What are you up to?',
            'Can we chat for a bit?',
            'Are you having a good day?',
            'Do you want to talk?'
        ],
        question: [
            'What do you think about that?',
            'Do you have an idea?',
            'Can we figure this out together?',
            'Would you choose the same?',
            'Should we decide together?'
        ]
    };

    const templates = templatesByType[communicationType] || templatesByType.assertion;
    const selectedTemplates = templates.slice(0, Math.max(0, neededCount));
    return selectedTemplates.map((text) => ({
        option: text,
        summary: text,
        keywords: tokenizeForContext(text).slice(0, 5),
        isLLMGenerated: true,
        originalPrompt: activeLLMPromptForContext,
        originatingButtonText: activeOriginatingButtonText
    }));
}

function prioritizePartnerEngagementQuestions(options, maxCount = LLMOptions, minQuestionCount = 3) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const selectedResponses = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];
    const latestSelectedResponse = selectedResponses.length > 0
        ? selectedResponses[selectedResponses.length - 1]
        : '';

    const questions = [];
    const nonQuestions = [];

    for (const item of options) {
        const text = typeof item?.option === 'string' ? item.option.trim() : '';
        if (!text) continue;
        if (isQuestionLikeOption(text)) {
            questions.push(item);
        } else {
            nonQuestions.push(item);
        }
    }

    const targetQuestions = Math.min(Math.max(1, minQuestionCount), Math.max(1, maxCount));
    let supplementalQuestions = [];
    if (questions.length < targetQuestions) {
        supplementalQuestions = buildPartnerQuestionFallbacks(latestSelectedResponse, targetQuestions - questions.length);
    }

    const merged = [...questions, ...supplementalQuestions, ...nonQuestions];
    const deduped = [];
    const seen = new Set();
    for (const item of merged) {
        const text = typeof item?.option === 'string' ? item.option.trim() : '';
        const normalized = normalizeForComparison(text);
        if (!normalized || seen.has(normalized)) continue;
        seen.add(normalized);
        deduped.push(item);
    }

    const result = deduped.slice(0, Math.max(1, maxCount));
    const resultQuestionCount = result.filter(item => isQuestionLikeOption(item?.option)).length;
    console.log('❓ Partner question prioritization:', {
        inputCount: options.length,
        existingQuestionCount: questions.length,
        supplementalQuestionCount: supplementalQuestions.length,
        outputCount: result.length,
        outputQuestionCount: resultQuestionCount,
        targetQuestions
    });
    return result;
}

function normalizeForComparison(text) {
    if (!text || typeof text !== 'string') return '';
    return text
        .toLowerCase()
        .replace(/["'“”‘’]/g, '')
        .replace(/[^a-z0-9\s]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function enforceAdditiveFollowUpOptions(options, maxCount = LLMOptions) {
    if (!Array.isArray(options) || options.length === 0) {
        console.log('📊 enforceAdditiveFollowUpOptions: Empty/invalid input, returning empty');
        return [];
    }

    const selectedResponses = Array.isArray(followUpConversation.selectedResponses)
        ? followUpConversation.selectedResponses
        : [];
    const latestSelectedResponse = selectedResponses.length > 0
        ? selectedResponses[selectedResponses.length - 1]
        : '';

    console.log('📊 enforceAdditiveFollowUpOptions START:', {
        inputCount: options.length,
        latestSelectedResponse: latestSelectedResponse,
        selectedResponsesCount: selectedResponses.length
    });

    const latestNormalized = normalizeForComparison(latestSelectedResponse);
    if (!latestNormalized) {
        const result = options.slice(0, Math.max(1, maxCount));
        console.log(`📊 enforceAdditiveFollowUpOptions: No latestNormalized, returning ${result.length} options`);
        return result;
    }

    console.log('📊 Latest normalized:', latestNormalized);

    const additive = [];
    for (let i = 0; i < options.length; i++) {
        const item = options[i];
        if (!item || typeof item.option !== 'string') {
            console.log(`  ❌ Option ${i}: Skipped (invalid item structure)`);
            continue;
        }

        const rawOption = item.option.trim();
        if (!rawOption) {
            console.log(`  ❌ Option ${i}: Skipped (empty after trim)`);
            continue;
        }

        let updatedOption = rawOption;
        const normalizedOption = normalizeForComparison(rawOption);

        console.log(`  📌 Option ${i}: "${rawOption.substring(0, 50)}..." normalized: "${normalizedOption.substring(0, 50)}..."`);

        // If option is just a restatement of the previous selection, drop it.
        if (normalizedOption === latestNormalized) {
            console.log(`    🚫 Exact match with latest - DROPPED`);
            continue;
        }

        // If option starts by repeating prior selection, remove that prefix and keep additive tail.
        if (normalizedOption.startsWith(latestNormalized)) {
            console.log(`    ⚠️  Option starts with latest response, attempting to strip prefix...`);
            const escapedLatest = latestSelectedResponse.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const prefixRegex = new RegExp(`^\\s*${escapedLatest}\\s*[!?.:,;\-–—]*\\s*`, 'i');
            updatedOption = updatedOption.replace(prefixRegex, '').trim();

            // Fallback if punctuation/spacing mismatch prevented direct prefix strip.
            if (!updatedOption) {
                console.log(`      Direct regex failed, trying fallback...`);
                const firstBreak = rawOption.search(/[!?.]\s+/);
                if (firstBreak >= 0) {
                    updatedOption = rawOption.slice(firstBreak + 1).trim();
                    console.log(`      Fallback found break at ${firstBreak}, extracted: "${updatedOption.substring(0, 50)}..."`);
                }
            } else {
                console.log(`      Regex stripped prefix, remaining: "${updatedOption.substring(0, 50)}..."`);
            }
        }

        if (!updatedOption) {
            console.log(`    🚫 No updated option remains - DROPPED`);
            continue;
        }

        const updatedNormalized = normalizeForComparison(updatedOption);
        if (!updatedNormalized || updatedNormalized === latestNormalized) {
            console.log(`    🚫 Updated normalized is empty or matches latest - DROPPED`);
            continue;
        }

        console.log(`    ✅ KEEPING option`);
        additive.push({
            ...item,
            option: updatedOption,
            summary: item.summary && typeof item.summary === 'string' ? item.summary : updatedOption
        });
    }

    const result = additive.slice(0, Math.max(1, maxCount));
    console.log(`📊 enforceAdditiveFollowUpOptions END: ${result.length} options kept from ${options.length} input`);
    return result;
}

async function fetchJokeOptions(limit, questionContext) {
    const response = await authenticatedFetch(`/api/jokes/contextual?limit=${limit}`);
    if (!response.ok) {
        throw new Error(`Failed to fetch jokes: ${response.status}`);
    }

    const data = await response.json();
    const jokes = (data && data.jokes) ? data.jokes : [];

    return jokes.map(joke => {
        const jokeText = (joke.text || '').trim();
        return {
            option: addPauseToJokeText(jokeText),
            summary: (joke.summary || 'Joke').trim() || 'Joke',
            keywords: joke.tags ? (Array.isArray(joke.tags) ? joke.tags : [joke.tags]) : ['joke', 'humor'],
            isLLMGenerated: true,
            originalPrompt: questionContext,
            originatingButtonText: activeOriginatingButtonText
        };
    }).filter(option => option.option && option.summary);
}

// --- NEW GLOBAL VARIABLES FOR ANNOUNCEMENT QUEUE & AUDIO CONTEXT FIX ---
let announcementQueue = [];       // Queue for sequential announcements
let isAnnouncingNow = false;      // Flag to prevent concurrent announce playback
let audioContextResumeAttempted = false; // Flag for AudioContext auto-resume helper
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

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

// --- NEW: User Management Variables ---
let currentAacUserId = null; // NEW: To store the currently selected individual AAC user ID
let firebaseIdToken = null; // NEW: To store the Firebase ID Token
const AAC_USER_ID_SESSION_KEY = "currentAacUserId"; // Key for storing selected AAC user ID
const FIREBASE_TOKEN_SESSION_KEY = "firebaseIdToken"; // Key for storing Firebase ID Token
const SELECTED_DISPLAY_NAME_SESSION_KEY = "selectedDisplayName"; // Key for storing display name
const SPEECH_HISTORY_LOCAL_STORAGE_KEY = (aacUserId) => `speechHistory_${aacUserId}`;

// --- Global Audio Settings (Client-Side, as per your attached file) ---
let personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
let systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';


let currentTtsVoiceName = 'en-US-Neural2-A'; // Default voice
let currentSpeechRate = 180;                 // Default words-per-minute

// --- AAC Pictogram Support ---
let enablePictograms = false; // Global setting for pictogram display - Always false for Gridpage
let disableTapPictograms = false; // When true, Tap Interface shows no pictograms/images and no sight word formatting

// Simple mapping of button text to Unicode emoji or icons
// This can be extended with more sophisticated matching or external APIs
// const PICTOGRAM_MAP = { ... }; // Removed
// (Rest of PICTOGRAM_MAP removed)

/**
 * Gets a pictogram for the given text
 * @param {string} text - The button text to find a pictogram for
 * @returns {string|null} - Unicode emoji/symbol or null if none found
 */
function getPictogramForText(text) {
    return null;
}

/**
 * Extracts compound terms and specific phrases that should be preserved
 * @param {string} text - The full text to analyze
 * @returns {string|null} - A compound term if found, null otherwise
 */
function extractCompoundTerm(text) {
    const lowerText = text.toLowerCase();
    
    // Specific patterns to look for (brand names, compound nouns, etc.)
    const compoundPatterns = [
        // Sports teams (prioritize these highly)
        /\b(denver\s+broncos?|dallas\s+cowboys?|green\s+bay\s+packers?|new\s+england\s+patriots?)\b/g,
        /\b(los\s+angeles\s+lakers?|boston\s+celtics?|chicago\s+bulls?|miami\s+heat)\b/g,
        
        // Movie studios and franchises  
        /\b(marvel\s+(?:movie|film|comic)|disney\s+(?:movie|film)|pixar\s+(?:movie|film))\b/g,
        /\b(star\s+wars|harry\s+potter|lord\s+of\s+the\s+rings)\b/g,
        
        // Food types
        /\b(chinese\s+food|italian\s+food|mexican\s+food|fast\s+food|ice\s+cream)\b/g,
        
        // Technology
        /\b(video\s+game|board\s+game|card\s+game)\b/g,
        /\b(social\s+media|text\s+message|phone\s+call)\b/g,
        
        // Activities
        /\b(rock\s+climbing|mountain\s+biking|horse\s+riding)\b/g,
        
        // General two-word nouns (but be selective)
        /\b([a-z]+)\s+(movie|film|game|show|book|music|song|album)\b/g,
        /\b([a-z]+)\s+(team|player|coach|stadium)\b/g,
        /\b([a-z]+)\s+(restaurant|store|shop|place)\b/g
    ];
    
    for (const pattern of compoundPatterns) {
        const matches = lowerText.match(pattern);
        if (matches && matches.length > 0) {
            // Return the first match, cleaned up
            const match = matches[0].trim();
            console.log(`🔧 DEBUG: Found compound term: "${match}"`);
            return match;
        }
    }
    
    return null;
}

/**
 * Intelligently extracts search terms for image matching by prioritizing subjects/objects over action verbs
 * @param {string} summary - The summary text that may start with question words
 * @param {Array<string>} keywords - Array of semantic keywords
 * @returns {string} - Optimized search term for image matching
 */
function getOptimizedSearchTerm(summary, keywords = null) {
    if (!summary || typeof summary !== 'string') return '';
    
    console.log(`🔧 DEBUG: Processing "${summary}" with keywords:`, keywords);
    
    // First, check for compound terms that should be preserved as complete phrases
    const compoundTerm = extractCompoundTerm(summary);
    if (compoundTerm) {
        console.log(`🔧 DEBUG: Using compound term: "${compoundTerm}"`);
        return compoundTerm;
    }
    
    const questionWords = ['what', 'who', 'where', 'when', 'why', 'how'];
    const words = summary.toLowerCase().trim().split(/\s+/);
    
    // Common action verbs that should be deprioritized in favor of objects/subjects
    const commonActionVerbs = [
        'watch', 'see', 'look', 'view', 'observe', 'listen', 'hear', 'play', 'do', 'make', 'get', 'go', 'come',
        'eat', 'drink', 'read', 'write', 'talk', 'speak', 'say', 'tell', 'ask', 'answer', 'call', 'walk',
        'run', 'sit', 'stand', 'work', 'study', 'learn', 'teach', 'help', 'use', 'try', 'want', 'need',
        'like', 'love', 'hate', 'think', 'know', 'understand', 'feel', 'take', 'give', 'put', 'find',
        'buy', 'sell', 'pay', 'spend', 'save', 'open', 'close', 'start', 'stop', 'finish', 'continue'
    ];
    
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
    
    // Enhanced keyword processing - prioritize specific nouns over action verbs
    if (keywords && Array.isArray(keywords) && keywords.length > 0) {
        const questionAndFillerWords = [...questionWords, ...fillerWords, 'question', 'curiosity', 'that', 'this'];
        const genericTerms = ['color', 'thing', 'object', 'item', 'stuff', 'shape', 'size'];
        
        // First, look for specific nouns that aren't action verbs
        const specificNounKeyword = keywords.find(keyword => {
            const cleanKeyword = keyword.toLowerCase().trim().replace(/[?!.,;:]/g, '');
            return cleanKeyword.length > 2 && 
                   !questionAndFillerWords.includes(cleanKeyword) &&
                   !genericTerms.includes(cleanKeyword) &&
                   !commonActionVerbs.includes(cleanKeyword);
        });
        
        if (specificNounKeyword) {
            const cleanKeyword = specificNounKeyword.toLowerCase().trim().replace(/[?!.,;:]/g, '');
            console.log(`🔧 DEBUG: Using specific noun keyword: "${cleanKeyword}"`);
            return cleanKeyword;
        }
        
        // If no specific nouns found, fall back to any meaningful keyword
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
    
    // Enhanced word analysis - prioritize subjects/objects over action verbs
    if (meaningfulWords.length > 0) {
        // For single word inputs that are specific, prefer the original case
        const originalWordLower = summary.toLowerCase().trim();
        const originalWord = summary.trim(); // Preserve original case
        if (meaningfulWords.includes(originalWordLower) && originalWordLower.length > 2) {
            console.log(`🔧 DEBUG: Using original specific word with preserved case: "${originalWord}"`);
            return originalWord;
        }
        
        // Separate words into action verbs vs potential subjects/objects
        const originalWords = summary.trim().split(/\s+/);
        const nonActionWords = [];
        const actionWords = [];
        
        meaningfulWords.forEach(word => {
            if (commonActionVerbs.includes(word)) {
                actionWords.push(word);
            } else {
                nonActionWords.push(word);
            }
        });
        
        // Prioritize non-action words (subjects/objects) - use the longest/most specific one
        if (nonActionWords.length > 0) {
            const sortedNonActionWords = nonActionWords.sort((a, b) => b.length - a.length);
            const selectedWord = sortedNonActionWords[0];
            
            // Find the original case version
            const originalCaseWord = originalWords.find(word => 
                word.toLowerCase().replace(/[?!.,;:]/g, '') === selectedWord
            );
            
            const finalWord = originalCaseWord || selectedWord;
            console.log(`🔧 DEBUG: Using prioritized subject/object: "${finalWord}" (avoided action verbs: ${actionWords})`);
            return finalWord;
        }
        
        // If only action words remain, use the longest one (but log this for debugging)
        const sortedWords = meaningfulWords.sort((a, b) => b.length - a.length);
        const selectedLowerWord = sortedWords[0];
        
        const originalCaseWord = originalWords.find(word => 
            word.toLowerCase().replace(/[?!.,;:]/g, '') === selectedLowerWord
        );
        
        const finalWord = originalCaseWord || selectedLowerWord;
        console.log(`🔧 DEBUG: Only action verbs available, using: "${finalWord}" from ${meaningfulWords}`);
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
 * Fetches symbol image from the AAC symbol database (optimized like tap interface)
 * @param {string} text - The button text to find a symbol for
 * @param {Array<string>} keywords - Optional semantic keywords for LLM-generated content  
 * @returns {Promise<string|null>} - Promise that resolves to image URL or null if none found
 */
async function getSymbolImageForText(text, keywords = null) {
    console.log(`🔍 getSymbolImageForText called for "${text}", enablePictograms: ${enablePictograms}, disableTapPictograms: ${disableTapPictograms}`);
    if (!text || text.trim() === '') {
        console.log(`❌ Empty text provided to getSymbolImageForText`);
        return null;
    }
    
    // If Tap Interface pictograms are disabled, return null (no images at all)
    if (disableTapPictograms) {
        console.log(`❌ Tap Interface pictograms disabled via setting, skipping image for "${text}"`);
        return null;
    }
    
    // Check if pictograms/images are enabled
    if (!enablePictograms) {
        console.log(`❌ Pictograms disabled, skipping image load for "${text}"`);
        return null;
    }
    
    // Check if this text is a sight word - if so, force text-only display (no images)
    if (window.isSightWord && window.isSightWord(text)) {
        console.log(`🔤 Gridpage sight word detected: "${text}" - using text-only display`);
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
                console.log(`✅ Restored ${window.symbolImageCache.size} cached symbol images from sessionStorage`);
            }
        } catch (e) {
            console.warn('Failed to restore symbol image cache:', e);
        }
    }
    
    const cacheKey = `grid_${text.trim().toLowerCase()}`;
    if (window.symbolImageCache.has(cacheKey)) {
        const cached = window.symbolImageCache.get(cacheKey);
        if (cached.timestamp > Date.now() - 3600000) { // Cache for 1 hour (up from 5 min)
            return cached.imageUrl;
        }
    }
    
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
            console.warn(`⏰ Timeout reached for symbol search: "${text}"`);
            controller.abort();
        }, 10000); // 10 second timeout
        
        // Use unified button-search that searches Firestore collections with keywords support (same as tap interface)
        let symbolsUrl = `/api/symbols/button-search?q=${encodeURIComponent(text.trim())}&limit=1`;
        if (keywords && keywords.length > 0) {
            symbolsUrl += `&keywords=${encodeURIComponent(JSON.stringify(keywords))}`;
        }
        
        const response = await authenticatedFetch(symbolsUrl, {
            signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        if (!response.ok) {
            console.warn(`Symbol search failed for "${text}": ${response.status}`);
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
                console.warn('Failed to persist symbol cache:', e);
            }
            console.log(`✅ Found Firestore image for "${text}": ${symbolUrl}`);
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
                console.warn('Failed to persist symbol cache:', e);
            }
            console.log(`❌ No Firestore image found for "${text}"`);
            return null;
        }
    } catch (error) {
        if (error.name === 'AbortError') {
            console.warn(`🚫 Request aborted for symbol "${text}" - likely due to timeout`);
        } else {
            console.error(`Error fetching symbol for "${text}":`, error);
        }
        return null;
    }
}


// --- Utility to convert Base64 to ArrayBuffer (Needed for playing audio) ---
function base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

// --- Core Fetch Wrapper (NEW) ---
// This function will wrap all your fetch calls to automatically add auth headers
async function authenticatedFetch(url, options = {}, _isRetry = false) {
    // Always refresh tokens from session storage (in case they were updated by token-refresh.js)
    firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);
    
    if (!firebaseIdToken || !currentAacUserId) {
        console.error("Authentication: Firebase ID Token or AAC User ID not found.");
        localStorage.setItem('debug_auth_missing', `Missing tokens at ${new Date().toISOString()}: token=${!!firebaseIdToken}, userId=${!!currentAacUserId}`);
        
        // For chat history, don't redirect - just fail gracefully
        if (url.includes('/record_chat_history')) {
            throw new Error("Authentication tokens missing for chat history");
        }
        
        // For other requests, redirect to login
        sessionStorage.clear();
        window.location.href = 'auth.html';
        throw new Error("Authentication required.");
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

    // Make the request
    const response = await fetch(url, options);
    
    // Handle authentication failures — try silent token refresh before giving up
    if ((response.status === 401 || response.status === 403) && !_isRetry) {
        console.warn(`Authentication failed (${response.status}) for ${url}. Attempting silent token refresh...`);
        
        // Try to refresh the token silently via Firebase
        if (typeof window.refreshFirebaseToken === 'function') {
            const newToken = await window.refreshFirebaseToken();
            if (newToken) {
                console.log('[AUTH] Token refreshed successfully, retrying request...');
                // Retry the request with the fresh token (clone options to avoid header mutation issues)
                const retryOptions = { ...options, headers: { ...options.headers } };
                return authenticatedFetch(url, retryOptions, true);
            }
        }
        
        // Token refresh failed — fall back to redirect
        const errorText = await response.text();
        console.warn(`Token refresh failed for ${url}:`, errorText);
        localStorage.setItem('debug_auth_expired', `Auth failed at ${new Date().toISOString()}: ${response.status} - ${errorText}`);
        
        // For chat history, fail gracefully without redirecting
        if (url.includes('/record_chat_history')) {
            throw new Error(`Authentication expired while recording chat history: ${response.status} - ${errorText}`);
        }
        
        // For other critical requests, redirect to login
        sessionStorage.clear();
        alert('Your session has expired. Please log in again.');
        window.location.href = 'auth.html';
        throw new Error("Session expired or invalid.");
    }
    
    // Handle auth failure on retry (refresh already attempted)
    if (response.status === 401 || response.status === 403) {
        const errorText = await response.text();
        localStorage.setItem('debug_auth_expired', `Auth failed after refresh at ${new Date().toISOString()}: ${response.status} - ${errorText}`);
        
        if (url.includes('/record_chat_history')) {
            throw new Error(`Authentication expired while recording chat history: ${response.status} - ${errorText}`);
        }
        
        sessionStorage.clear();
        alert('Your session has expired. Please log in again.');
        window.location.href = 'auth.html';
        throw new Error("Session expired or invalid.");
    }
    
    return response;
}



// --- Settings Loading ---

async function loadScanSettings() {
    try {
        // Use authenticatedFetch instead of direct fetch
        const response = await authenticatedFetch('/api/settings', {
            method: 'GET' // Explicitly define method
        });
       
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`HTTP error loading settings! status: ${response.status} ${errorText}`);
            // On error, we will just use the default values we set in Step 1.
            return;
        }
       
        const settings = await response.json();

        // --- Keep all your existing settings logic ---
        // Load Scan Delay
        if (settings && typeof settings.scanDelay === 'number' && !isNaN(settings.scanDelay)) {
             defaultDelay = Math.max(100, parseInt(settings.scanDelay));
             console.log(`Auditory scan delay loaded: ${defaultDelay}ms`);
        } else {
             defaultDelay = 3500;
        }

        // Load Wake Word parts
        if (settings && typeof settings.wakeWordInterjection === 'string' && settings.wakeWordInterjection.trim()) {
            wakeWordInterjection = settings.wakeWordInterjection.trim().toLowerCase();
        } else {
            wakeWordInterjection = "hey";
        }
        if (settings && typeof settings.wakeWordName === 'string' && settings.wakeWordName.trim()) {
            wakeWordName = settings.wakeWordName.trim().toLowerCase();
        } else {
            wakeWordName = "friend";
        }
        
        // Load LLMOptions
        if (settings && typeof settings.LLMOptions === 'number' && !isNaN(settings.LLMOptions)) {
             LLMOptions = Math.max(1, parseInt(settings.LLMOptions));
        } else {
             LLMOptions = 10;
        }

        // Load Scan Loop Limit
        if (settings && typeof settings.scanLoopLimit === 'number' && !isNaN(settings.scanLoopLimit)) {
             scanLoopLimit = Math.max(0, Math.min(10, parseInt(settings.scanLoopLimit)));
             console.log(`Scan Loop Limit loaded: ${scanLoopLimit} (0 = unlimited)`);
        } else {
             scanLoopLimit = 0; // Default to unlimited
        }

        // Load booleans
        ScanningOff = settings.ScanningOff === true;
        scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
        waitForSwitchToScan = settings.waitForSwitchToScan === true;
        SummaryOff = settings.SummaryOff === true;
        enablePictograms = settings.enablePictograms === true;
        disableTapPictograms = settings.disableTapPictograms === true;
        console.log('🔍 DEBUG enablePictograms loaded from settings:', settings.enablePictograms, '-> final value:', enablePictograms);
        console.log('🔍 DEBUG disableTapPictograms loaded from settings:', settings.disableTapPictograms, '-> final value:', disableTapPictograms);
        
        // Update sight word service with new settings
        if (window.updateSightWordSettings) {
            window.updateSightWordSettings(settings);
        }

        // Load Grid Columns (for standardized button sizing)
        if (settings && typeof settings.gridColumns === 'number' && !isNaN(settings.gridColumns)) {
            gridColumns = Math.max(2, Math.min(18, parseInt(settings.gridColumns)));
            console.log(`Grid Columns loaded: ${gridColumns}`);
        } else {
            gridColumns = 10; // Default value
        }

        // --- ADD THIS NEW LOGIC FOR TTS SETTINGS ---
        // Load Speech Rate
        if (settings && typeof settings.speech_rate === 'number' && !isNaN(settings.speech_rate)) {
            currentSpeechRate = parseInt(settings.speech_rate);
            console.log(`Speech Rate loaded: ${currentSpeechRate} WPM`);
        } else {
            console.warn("Speech Rate setting not found or invalid. Using default:", currentSpeechRate);
            // It will keep its default value of 180
        }

        // Load TTS Voice Name
        if (settings && typeof settings.selected_tts_voice_name === 'string' && settings.selected_tts_voice_name.trim()) {
            currentTtsVoiceName = settings.selected_tts_voice_name;
            console.log(`TTS Voice Name loaded: "${currentTtsVoiceName}"`);
        } else {
            console.warn("TTS Voice Name setting not found or invalid. Using default:", currentTtsVoiceName);
            // It will keep its default value of 'en-US-Neural2-A'
        }
        // --- END OF NEW LOGIC ---

   } catch (error) {
       console.error('Error fetching or parsing scan settings:', error);
       // On any fetch error, the default global variables from Step 1 will be used.
   }
}


// --- Banner and Page Title Functions (MODIFIED to use selectedDisplayName) ---
function capitalizeFirstLetter(string) {
    if (!string) return "";
    return string.charAt(0).toUpperCase() + string.slice(1).toLowerCase();
}


function setBannerAndPageTitle() {
    // This function will now be called after page data is loaded
    // and the correct page name/displayName is determined.
    const urlParams = new URLSearchParams(window.location.search);
    const pageQueryParam = urlParams.get('page');
    const bannerTitleElement = document.getElementById('dynamic-page-title');
    let displayTitle = "Home"; // Default title, will be overridden

    // Get the base page title first
    const storedBannerTitle = sessionStorage.getItem('dynamicBannerTitle');
    if (pageQueryParam) {
        displayTitle = capitalizeFirstLetter(pageQueryParam);
    } else if (storedBannerTitle) {
        displayTitle = storedBannerTitle;
        sessionStorage.removeItem('dynamicBannerTitle'); // Clear it after use
    }

    // If a specific page is loaded and has a displayName, use that.
    const loadedPageDisplayName = sessionStorage.getItem('currentPageDisplayNameForBanner');
    if (loadedPageDisplayName) {
        displayTitle = loadedPageDisplayName;
    }
    
    // Always add profile name if available (remove any existing profile suffix first)
    const profileDisplayName = sessionStorage.getItem('currentProfileDisplayName');
    if (profileDisplayName) {
        // Remove any existing " - [profile]" suffix to avoid duplication
        displayTitle = displayTitle.replace(/ - .*$/, '');
        displayTitle = `${displayTitle} - ${profileDisplayName}`;
    }
    
    console.log('Setting page title to:', displayTitle); // Debug log
    if (bannerTitleElement) { 
        bannerTitleElement.textContent = displayTitle; 
        console.log('Banner element updated:', bannerTitleElement.textContent); // Debug log
    }
    document.title = displayTitle; // Update browser tab title
}

// --- Helper to get current page information from URL ---
function getCurrentPageInfo() {
    const params = new URLSearchParams(window.location.search);
    const pageNameFromUrl = params.get('page');
    const categoryFromUrl = params.get('category');
    const topicFromUrl = params.get('topic'); // For dynamic topics

    if (pageNameFromUrl) {
        return { name: pageNameFromUrl, type: "static" };
    } else if (categoryFromUrl) {
        // For dynamic pages like current events, the "page name" can be the category.
        return { name: categoryFromUrl, type: "category" };
    } else if (topicFromUrl) {
        return { name: topicFromUrl, type: "dynamic_topic" };
    }
    return { name: "UnknownPage", type: "unknown" }; // Fallback
}



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
    // Update the UI to show the active user ID if you still have that element
    // This part is being removed as user selection is handled by auth.html
    /*
    const activeUserIdElement = document.getElementById('active-user-id-value');
    if (activeUserIdElement) {
        activeUserIdElement.textContent = sessionStorage.getItem(SELECTED_DISPLAY_NAME_SESSION_KEY) || currentAacUserId;
    }*/
    
    // Load and update page title with profile name
    await updatePageTitleWithProfile();
    
    return true; // Indicate ready
}

// Function to update page title with profile name
async function updatePageTitleWithProfile() {
    console.log('updatePageTitleWithProfile: Starting profile name fetch...'); // Debug log
    try {
        const response = await authenticatedFetch('/api/account/users');
        console.log('Profile API response status:', response.status); // Debug log
        
        if (!response.ok) {
            console.warn('Failed to fetch profiles:', response.status);
            return;
        }
        
        const profiles = await response.json();
        console.log('Profiles received:', profiles.length, 'profiles'); // Debug log
        
        const currentProfile = profiles.find(profile => profile.aac_user_id === currentAacUserId);
        console.log('Current profile found:', currentProfile ? currentProfile.display_name : 'none'); // Debug log
        
        if (currentProfile && currentProfile.display_name) {
            // Store the profile name for use in title updates
            sessionStorage.setItem('currentProfileDisplayName', currentProfile.display_name);
            console.log('Stored profile name in session:', currentProfile.display_name); // Debug log
            
            // Update the banner title immediately
            setBannerAndPageTitle();
        } else {
            console.warn('No profile found for current user ID:', currentAacUserId);
        }
    } catch (error) {
        console.error('Error updating page title with profile:', error);
    }
}

// --- Mood Selection Integration ---
async function showMoodSelectionIfNeeded() {
    return new Promise((resolve) => {
        // Check if showMoodSelection function is available
        if (typeof showMoodSelection === 'function') {
            showMoodSelection((selectedMood) => {
                if (selectedMood) {
                    console.log('Mood selected for session:', selectedMood);
                } else {
                    console.log('No mood selected or mood selection skipped');
                }
                resolve();
            });
        } else {
            console.log('Mood selection not available');
            resolve();
        }
    });
}

function getComposeReturnTarget() {
    if (composeSession?.sourceFrom) {
        return composeSession.sourceFrom;
    }
    return 'gridpage.html?page=home';
}

function updateComposeQuestionDisplay(message = '') {
    // Keep hidden textarea in sync (for legacy code that reads it)
    const questionDisplay = document.getElementById('question-display');
    const compositionText = String(composeSession?.text || '').trim();
    const header = message || 'Create Mode';
    if (questionDisplay) questionDisplay.value = compositionText ? `${header}\n\n${compositionText}` : header;
    // Show in status bar instead of the hidden question box
    updateStatusBar(`✏️ ${header}`);
    // Keep the compose panel label/textarea current
    updateSpeechHistoryPanel();
}

function createComposeGridButton(label, clickHandler, index = 0) {
    const button = document.createElement('button');
    button.textContent = label;
    button.classList.add('grid-button');
    const row = Math.floor(index / gridColumns);
    const col = index % gridColumns;
    button.dataset.row = String(row);
    button.dataset.col = String(col);
    button.style.gridRowStart = row + 1;
    button.style.gridColumnStart = col + 1;
    button.addEventListener('click', async () => {
        if (composeMenuActionInProgress) {
            return;
        }
        composeMenuActionInProgress = true;
        stopAuditoryScanning();
        try {
            await clickHandler();
        } finally {
            composeMenuActionInProgress = false;
        }
    });
    return button;
}

async function renderComposeEntryMenu(container, fromUrl) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateComposeQuestionDisplay('Create: Start New or Open Existing');

    const options = [
        {
            label: 'Create New',
            handler: async () => {
                composeSession = {
                    active: true,
                    documentId: null,
                    title: '',
                    text: '',
                    startedAt: new Date().toISOString(),
                    sourceFrom: fromUrl || getComposeReturnTarget()
                };
                saveComposeSession();
                window.location.href = '/static/compose_create.html';
            }
        },
        {
            label: 'Open Existing',
            handler: async () => {
                await renderComposeExistingDocumentsMenu(container, fromUrl);
            }
        },
        {
            label: 'Cancel',
            handler: async () => {
                clearComposeSession();
                window.location.href = fromUrl || 'gridpage.html?page=home';
            }
        }
    ];

    options.forEach((option, index) => {
        container.appendChild(createComposeGridButton(option.label, option.handler, index));
    });

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'compose-entry-menu' }), 50);
}

async function renderComposeExistingDocumentsMenu(container, fromUrl) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateComposeQuestionDisplay('Create: Choose an existing document');

    let docs = [];
    try {
        const response = await authenticatedFetch('/api/compose/documents', { method: 'GET' });
        if (response.ok) {
            const data = await response.json();
            docs = Array.isArray(data.documents) ? data.documents : [];
        }
    } catch (error) {
        console.error('Error loading compose documents:', error);
    }

    const storyLikeDocs = docs.filter((doc) => (doc.document_type || 'story') !== 'email').slice(0, Math.max(6, gridColumns * 2));
    let index = 0;

    if (storyLikeDocs.length === 0) {
        container.appendChild(createComposeGridButton('No Saved Documents', async () => {
            await announce('No saved documents found.', 'system', false);
            await renderComposeEntryMenu(container, fromUrl);
        }, index++));
    } else {
        storyLikeDocs.forEach((doc) => {
            const displayTitle = (doc.title || 'Untitled Creation').trim();
            container.appendChild(createComposeGridButton(displayTitle, async () => {
                composeSession = {
                    active: true,
                    documentId: doc.id,
                    title: displayTitle,
                    text: String(doc.body || ''),
                    startedAt: new Date().toISOString(),
                    sourceFrom: fromUrl || getComposeReturnTarget()
                };
                saveComposeSession();
                window.location.href = '/static/compose_create.html';
            }, index++));
        });
    }

    container.appendChild(createComposeGridButton('Go Back', async () => {
        await renderComposeEntryMenu(container, fromUrl);
    }, index));

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'compose-existing-menu' }), 50);
}

async function saveComposeDocumentAndExit() {
    const compositionText = String(composeSession?.text || '').trim();
    if (!compositionText) {
        await announce('Creation is empty. Add words before saving.', 'system', false);
        return;
    }

    let generatedTitle = 'Untitled Letter';
    try {
        const titleResponse = await authenticatedFetch('/api/compose/generate-title', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ body: compositionText })
        });
        if (titleResponse.ok) {
            const titleData = await titleResponse.json();
            if (titleData.success && titleData.title) {
                generatedTitle = String(titleData.title).trim() || generatedTitle;
            }
        }
    } catch (error) {
        console.warn('Create title generation failed, using fallback title:', error);
    }

    const payload = {
        document_type: 'story',
        title: generatedTitle,
        body: compositionText,
        to: [],
        cc: [],
        bcc: [],
        subject: ''
    };

    const isUpdate = Boolean(composeSession?.documentId);
    const targetUrl = isUpdate
        ? `/api/compose/documents/${composeSession.documentId}`
        : '/api/compose/documents';
    const method = isUpdate ? 'PUT' : 'POST';

    const saveResponse = await authenticatedFetch(targetUrl, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    if (!saveResponse.ok) {
        const errText = await saveResponse.text().catch(() => 'unknown save error');
        throw new Error(`Save failed: ${errText}`);
    }

    clearComposeSession();
    window.location.href = 'gridpage.html?page=home';
}

async function aiEditCompositionInSession() {
    const compositionText = String(composeSession?.text || '').trim();
    if (!compositionText) {
        await announce('Creation is empty. Add words before editing.', 'system', false);
        return;
    }

    const response = await authenticatedFetch('/api/compose/ai-edit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body: compositionText })
    });

    if (!response.ok) {
        const errText = await response.text().catch(() => 'unknown ai edit error');
        throw new Error(`AI edit failed: ${errText}`);
    }

    const data = await response.json();
    if (!data.success || !data.edited_body) {
        throw new Error(data.error || 'AI edit failed');
    }

    composeSession.text = String(data.edited_body || '').trim();
    saveComposeSession();
}

function buildCreationExportFilename() {
    const existingTitle = String(composeSession?.title || '').trim();
    const textPreview = String(composeSession?.text || '').trim().split(/\s+/).slice(0, 6).join(' ');
    const baseName = existingTitle || textPreview || `creation-${new Date().toISOString().slice(0, 10)}`;
    const safeName = baseName
        .replace(/[^a-z0-9]+/gi, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 80);
    return `${safeName || 'creation'}.txt`;
}

async function exportCreationToLocalDrive() {
    const creationText = String(composeSession?.text || '').trim();
    if (!creationText) {
        await announce('Creation is empty. Add words before exporting.', 'system', false);
        return false;
    }

    const filename = buildCreationExportFilename();

    if (window.showSaveFilePicker) {
        try {
            const fileHandle = await window.showSaveFilePicker({
                suggestedName: filename,
                types: [
                    {
                        description: 'Text Files',
                        accept: { 'text/plain': ['.txt'] }
                    }
                ]
            });
            const writable = await fileHandle.createWritable();
            await writable.write(creationText);
            await writable.close();
            return true;
        } catch (error) {
            if (error?.name === 'AbortError') {
                return false;
            }
            console.warn('Save picker export failed, falling back to browser download:', error);
        }
    }

    const blob = new Blob([creationText], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    return true;
}

async function renderComposeFinalizeMenu(container) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateComposeQuestionDisplay('Finalize Creation');

    const options = [
        {
            label: 'Save Creation',
            handler: async () => {
                try {
                    await saveComposeDocumentAndExit();
                } catch (error) {
                    console.error('Error saving composition:', error);
                    await announce('Unable to save creation right now.', 'system', false);
                    await renderComposeFinalizeMenu(container);
                }
            }
        },
        {
            label: 'Discard Creation',
            handler: async () => {
                clearComposeSession();
                window.location.href = 'gridpage.html?page=home';
            }
        },
        {
            label: 'Read Creation',
            handler: async () => {
                const compositionText = String(composeSession?.text || '').trim();
                if (!compositionText) {
                    await announce('Creation is empty.', 'system', false);
                } else {
                    await announce(compositionText, 'system', false);
                }
                await renderComposeFinalizeMenu(container);
            }
        },
        {
            label: 'Export Creation',
            handler: async () => {
                try {
                    const exported = await exportCreationToLocalDrive();
                    if (exported) {
                        await announce('Creation exported to local drive.', 'system', false);
                    }
                } catch (error) {
                    console.error('Error exporting creation:', error);
                    await announce('Unable to export creation right now.', 'system', false);
                }
                await renderComposeFinalizeMenu(container);
            }
        },
        {
            label: 'AI Edit Creation',
            handler: async () => {
                try {
                    await aiEditCompositionInSession();
                    updateComposeQuestionDisplay('AI revised creation');
                    await announce(String(composeSession?.text || ''), 'system', false);
                } catch (error) {
                    console.error('Error during AI edit:', error);
                    await announce('Unable to AI edit creation right now.', 'system', false);
                }
                await renderComposeFinalizeMenu(container);
            }
        },
        {
            label: 'Return to Creation',
            handler: async () => {
                window.location.href = '/static/compose_create.html';
            }
        }
    ];

    options.forEach((option, index) => {
        container.appendChild(createComposeGridButton(option.label, option.handler, index));
    });

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'compose-finalize-menu' }), 50);
}

function getEmailReturnTarget() {
    if (emailSession?.sourceFrom) {
        return emailSession.sourceFrom;
    }
    return 'gridpage.html?page=home';
}

function updateEmailQuestionDisplay(message = '') {
    const questionDisplay = document.getElementById('question-display');
    const draftText = String(composeSession?.text || '').trim();
    const header = message || 'Email';
    if (questionDisplay) {
        questionDisplay.value = draftText ? `${header}\n\n${draftText}` : header;
    }
    updateStatusBar(`📧 ${header}`);
    updateSpeechHistoryPanel();
}

async function startGmailConnectFlow() {
    const response = await authenticatedFetch('/api/email/connect-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: 'gmail' })
    });
    if (!response.ok) {
        const text = await response.text().catch(() => 'Unable to create Gmail connect link');
        throw new Error(text);
    }
    const data = await response.json();
    if (!data?.connect_url) {
        throw new Error('Missing Gmail connect URL');
    }
    window.location.href = data.connect_url;
}

async function renderEmailEntryMenu(container, fromUrl) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateEmailQuestionDisplay('Email: Choose an option');

    const options = [
        {
            label: 'Home',
            handler: async () => {
                clearEmailSession();
                window.location.href = fromUrl || 'gridpage.html?page=home';
            }
        },
        {
            label: 'Create New Email',
            handler: async () => {
                await renderEmailContactsMenu(container, fromUrl);
            }
        },
        {
            label: 'Read Existing Email',
            handler: async () => {
                await renderEmailInboxMenu(container, fromUrl);
            }
        }
    ];

    options.forEach((option, index) => {
        container.appendChild(createComposeGridButton(option.label, option.handler, index));
    });

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-entry-menu' }), 50);
}

async function renderEmailContactsMenu(container, fromUrl, selectedContacts = [], pageToken = null) {
    stopAuditoryScanning();
    container.innerHTML = '';
    const selectionCount = selectedContacts.length;
    const displayTitle = selectionCount > 0
        ? `Email: Add another contact (${selectionCount} selected)`
        : 'Email: Choose a contact';
    updateEmailQuestionDisplay(displayTitle);

    const pageSize = Math.max(4, LLMOptions);
    let contacts = [];
    let nextPageToken = null;
    let loadError = null;
    let usingInboxFallback = false;
    try {
        const contactsUrl = new URL('/api/email/contacts', window.location.origin);
        contactsUrl.searchParams.set('max_results', String(pageSize));
        if (pageToken) contactsUrl.searchParams.set('page_token', pageToken);
        const response = await authenticatedFetch(`${contactsUrl.pathname}${contactsUrl.search}`, { method: 'GET' });
        if (response.ok) {
            const data = await response.json();
            contacts = Array.isArray(data.contacts) ? data.contacts : [];
            nextPageToken = String(data.next_page_token || '').trim() || null;
        } else {
            loadError = `Unable to load contacts (${response.status})`;
        }
    } catch (error) {
        loadError = error.message || 'Unable to load contacts';
    }

    if (loadError || !contacts.length) {
        try {
            const inboxUrl = new URL('/api/email/inbox', window.location.origin);
            inboxUrl.searchParams.set('max_results', String(pageSize));
            if (pageToken) inboxUrl.searchParams.set('page_token', pageToken);
            const inboxResponse = await authenticatedFetch(`${inboxUrl.pathname}${inboxUrl.search}`, { method: 'GET' });
            if (inboxResponse.ok) {
                const inboxData = await inboxResponse.json();
                const messages = Array.isArray(inboxData.messages) ? inboxData.messages : [];
                const dedupe = new Set();
                const fallbackContacts = [];
                messages.forEach((message) => {
                    const senderEmail = String(message?.sender_email || extractEmailAddressFromHeader(message?.from || '') || '').trim();
                    if (!senderEmail) return;
                    const dedupeKey = senderEmail.toLowerCase();
                    if (dedupe.has(dedupeKey)) return;
                    dedupe.add(dedupeKey);
                    fallbackContacts.push({
                        name: String(message?.sender_name || '').trim(),
                        email: senderEmail,
                    });
                });
                if (fallbackContacts.length) {
                    contacts = fallbackContacts;
                    nextPageToken = String(inboxData.next_page_token || '').trim() || null;
                    usingInboxFallback = true;
                    loadError = null;
                }
            }
        } catch (fallbackError) {
            console.warn('Email contacts fallback from inbox failed:', fallbackError);
        }
    }

    if (usingInboxFallback) {
        updateEmailQuestionDisplay(selectionCount > 0
            ? `Email: Add another contact (${selectionCount} selected)`
            : 'Email: Choose a contact (recent senders)');
    }

    let index = 0;
    if (loadError) {
        container.appendChild(createComposeGridButton('Try Again', async () => {
            await renderEmailContactsMenu(container, fromUrl, selectedContacts, null);
        }, index++));
        container.appendChild(createComposeGridButton('Connect Gmail', async () => {
            try {
                await startGmailConnectFlow();
            } catch (error) {
                await announce('Unable to connect Gmail right now.', 'system', false);
                await renderEmailEntryMenu(container, fromUrl);
            }
        }, index++));
    } else if (!contacts.length) {
        container.appendChild(createComposeGridButton('No Contacts Found', async () => {
            await announce('No contacts found.', 'system', false);
            await renderEmailEntryMenu(container, fromUrl);
        }, index++));
    } else {
        // Filter out already-selected contacts to avoid duplicates
        const selectedEmails = new Set(selectedContacts.map(c => c.email.toLowerCase()));
        const availableContacts = contacts.filter(c => {
            const email = String(c?.email || '').trim().toLowerCase();
            return email && !selectedEmails.has(email);
        });

        availableContacts.forEach((contact) => {
            const recipientEmail = String(contact?.email || '').trim();
            const recipientName = String(contact?.name || '').trim();
            const label = recipientName || recipientEmail;
            if (!recipientEmail) return;

            container.appendChild(createComposeGridButton(label, async () => {
                const updatedContacts = [...selectedContacts, { email: recipientEmail, name: recipientName }];
                await renderEmailContactsConfirmMenu(container, fromUrl, updatedContacts);
            }, index++));
        });

        if (nextPageToken) {
            container.appendChild(createComposeGridButton('Show More', async () => {
                await renderEmailContactsMenu(container, fromUrl, selectedContacts, nextPageToken);
            }, index++));
        }
    }

    container.appendChild(createComposeGridButton('Go Back', async () => {
        if (selectedContacts.length > 0) {
            await renderEmailContactsConfirmMenu(container, fromUrl, selectedContacts);
        } else {
            await renderEmailEntryMenu(container, fromUrl);
        }
    }, index));

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-contacts-menu' }), 50);
}

async function renderEmailContactsConfirmMenu(container, fromUrl, selectedContacts) {
    stopAuditoryScanning();
    container.innerHTML = '';
    const names = selectedContacts.map(c => c.name || c.email).join(', ');
    updateEmailQuestionDisplay(`To: ${names}`);

    container.appendChild(createComposeGridButton('Add More Contacts', async () => {
        await renderEmailContactsMenu(container, fromUrl, selectedContacts, null);
    }, 0));

    container.appendChild(createComposeGridButton('Create Email', async () => {
        const primary = selectedContacts[0];
        emailSession = {
            active: true,
            mode: 'compose',
            recipientEmail: selectedContacts.map(c => c.email).join(','),
            recipientName: selectedContacts.map(c => c.name || c.email).join(', '),
            recipients: selectedContacts,
            sourceFrom: fromUrl || getEmailReturnTarget(),
            threadId: '',
            inReplyTo: '',
            references: ''
        };
        saveEmailSession();

        composeSession = {
            active: true,
            documentId: null,
            title: '',
            text: '',
            startedAt: new Date().toISOString(),
            sourceFrom: fromUrl || getEmailReturnTarget()
        };
        saveComposeSession();

        window.location.href = 'gridpage.html?page=home&compose=1&email_compose=1';
    }, 1));

    container.appendChild(createComposeGridButton('Go Back', async () => {
        await renderEmailContactsMenu(container, fromUrl, selectedContacts, null);
    }, 2));

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-contacts-confirm-menu' }), 50);
}

async function renderEmailInboxMenu(container, fromUrl, pageToken = null) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateEmailQuestionDisplay('Email: Read existing messages');

    let messages = [];
    let nextPageToken = null;
    let loadError = null;
    try {
        const inboxUrl = new URL('/api/email/inbox', window.location.origin);
        inboxUrl.searchParams.set('max_results', '20');
        if (pageToken) {
            inboxUrl.searchParams.set('page_token', pageToken);
        }

        const response = await authenticatedFetch(`${inboxUrl.pathname}${inboxUrl.search}`, { method: 'GET' });
        if (response.ok) {
            const data = await response.json();
            messages = Array.isArray(data.messages) ? data.messages : [];
            nextPageToken = String(data.next_page_token || '').trim() || null;
        } else {
            loadError = `Unable to load inbox (${response.status})`;
        }
    } catch (error) {
        loadError = error.message || 'Unable to load inbox';
    }

    let index = 0;
    if (loadError || !messages.length) {
        container.appendChild(createComposeGridButton(loadError ? 'Inbox Unavailable' : 'No Inbox Messages', async () => {
            await announce(loadError || 'No inbox messages available.', 'system', false);
            await renderEmailEntryMenu(container, fromUrl);
        }, index++));
    } else {
        messages.slice(0, Math.max(8, gridColumns * 3)).forEach((message) => {
            const messageId = String(message?.id || '').trim();
            if (!messageId) return;
            const subject = String(message.subject || '(No subject)').trim();
            const label = subject;

            container.appendChild(createComposeGridButton(label.slice(0, 64), async () => {
                stopAuditoryScanning();
                try {
                    const detailResponse = await authenticatedFetch(`/api/email/messages/${encodeURIComponent(messageId)}`, { method: 'GET' });
                    if (!detailResponse.ok) {
                        await announce('Unable to load that email.', 'system', false);
                        await renderEmailInboxMenu(container, fromUrl, pageToken);
                        return;
                    }
                    const detail = await detailResponse.json();
                    const msg = detail?.message || {};
                    const body = String(msg.body_text || msg.snippet || '').trim();
                    const readText = body || 'No message body available.';
                    await announce(readText, 'system', false, false);
                    await renderEmailReadActionsMenu(container, fromUrl, messageId, msg);
                    return;
                } catch (error) {
                    await announce('Unable to read that email right now.', 'system', false);
                }
                await renderEmailInboxMenu(container, fromUrl, pageToken);
            }, index++));
        });
    }

    if (nextPageToken) {
        container.appendChild(createComposeGridButton('Show More', async () => {
            await renderEmailInboxMenu(container, fromUrl, nextPageToken);
        }, index++));
    }

    container.appendChild(createComposeGridButton('Go Back', async () => {
        await renderEmailEntryMenu(container, fromUrl);
    }, index));

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-inbox-menu' }), 50);
}

function extractEmailAddressFromHeader(headerValue) {
    const raw = String(headerValue || '').trim();
    if (!raw) return '';

    const bracketMatch = raw.match(/<([^>]+)>/);
    if (bracketMatch && bracketMatch[1]) {
        return bracketMatch[1].trim();
    }

    const plainMatch = raw.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
    return plainMatch ? plainMatch[0].trim() : '';
}

async function startReplyToEmail(fromUrl, messageId, messageData) {
    const recipientEmail = extractEmailAddressFromHeader(messageData.from || '');
    if (!recipientEmail) {
        await announce('Unable to determine sender email for reply.', 'system', false);
        return;
    }

    emailSession = {
        active: true,
        mode: 'reply',
        recipientEmail,
        recipientName: String(messageData.from || '').trim(),
        sourceFrom: fromUrl || getEmailReturnTarget(),
        threadId: String(messageData.thread_id || '').trim(),
        inReplyTo: String(messageData.message_id_header || '').trim(),
        references: String(messageData.references || '').trim()
    };
    saveEmailSession();

    composeSession = {
        active: true,
        documentId: null,
        title: String(messageData.subject || '').trim(),
        text: '',
        startedAt: new Date().toISOString(),
        sourceFrom: fromUrl || getEmailReturnTarget()
    };
    saveComposeSession();

    window.location.href = 'gridpage.html?page=home&compose=1&email_compose=1';
}

async function renderEmailReadActionsMenu(container, fromUrl, messageId, messageData) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateEmailQuestionDisplay('Email: Choose an action');

    container.appendChild(createComposeGridButton('Reply to Email', async () => {
        await startReplyToEmail(fromUrl, messageId, messageData);
    }, 0));

    container.appendChild(createComposeGridButton('Go Back', async () => {
        await renderEmailInboxMenu(container, fromUrl);
    }, 1));

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-read-actions-menu' }), 50);
}

async function sendCurrentEmailFromSession() {
    if (!isEmailSessionActive()) {
        throw new Error('Email session is not active');
    }

    const bodyText = String(composeSession?.text || '').trim();
    if (!bodyText) {
        throw new Error('Email body is empty');
    }

    // Support both array (multi-recipient) and legacy single-string recipient
    let toAddresses = [];
    if (Array.isArray(emailSession.recipients) && emailSession.recipients.length > 0) {
        toAddresses = emailSession.recipients.map(r => String(r.email || '').trim()).filter(Boolean);
    } else {
        const recipientEmail = String(emailSession.recipientEmail || '').trim();
        if (recipientEmail) {
            toAddresses = recipientEmail.split(',').map(e => e.trim()).filter(Boolean);
        }
    }
    if (!toAddresses.length) {
        throw new Error('No recipient selected');
    }

    let subject = 'Message';
    try {
        const titleResponse = await authenticatedFetch('/api/compose/generate-title', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ body: bodyText })
        });
        if (titleResponse.ok) {
            const titleData = await titleResponse.json();
            if (titleData?.success && titleData?.title) {
                subject = String(titleData.title).trim() || subject;
            }
        }
    } catch (error) {
        console.warn('Email subject generation failed, using fallback subject:', error);
    }

    const sendResponse = await authenticatedFetch('/api/email/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            to: toAddresses,
            cc: [],
            bcc: [],
            subject,
            body: bodyText,
            thread_id: String(emailSession.threadId || '').trim(),
            in_reply_to: String(emailSession.inReplyTo || '').trim(),
            references: String(emailSession.references || '').trim()
        })
    });

    if (!sendResponse.ok) {
        const errText = await sendResponse.text().catch(() => 'send failed');
        throw new Error(errText);
    }
}

async function renderEmailFinalizeMenu(container, fromUrl) {
    stopAuditoryScanning();
    container.innerHTML = '';
    updateEmailQuestionDisplay('Email: Finalize draft');

    const options = [
        {
            label: 'Read email',
            handler: async () => {
                const bodyText = String(composeSession?.text || '').trim();
                await speakLocally(bodyText || 'Email is empty.');
                await renderEmailFinalizeMenu(container, fromUrl);
            }
        },
        {
            label: 'Edit email',
            handler: async () => {
                window.location.href = 'gridpage.html?page=home&compose=1&email_compose=1';
            }
        },
        {
            label: 'Send email',
            handler: async () => {
                try {
                    await sendCurrentEmailFromSession();
                    clearComposeSession();
                    clearEmailSession();
                    await announce('Email sent successfully.', 'system', false);
                    window.location.href = `gridpage.html?email_menu=1&from=${encodeURIComponent(fromUrl || getEmailReturnTarget())}`;
                } catch (error) {
                    await announce('Unable to send email right now.', 'system', false);
                    await renderEmailFinalizeMenu(container, fromUrl);
                }
            }
        },
        {
            label: 'Discard Email',
            handler: async () => {
                clearComposeSession();
                clearEmailSession();
                window.location.href = 'gridpage.html?page=home';
            }
        }
    ];

    options.forEach((option, index) => {
        container.appendChild(createComposeGridButton(option.label, option.handler, index));
    });

    setTimeout(() => startOrWaitForScanning({ allowPrompt: true, source: 'email-finalize-menu' }), 50);
}

function addQuitComposeButton(container) {
    if (!isComposeSessionActive()) return;
    if (container.querySelector('#compose-quit-button')) return;

    const currentCount = container.querySelectorAll('button').length;
    const isEmailDraft = isEmailSessionActive();
    const quitButton = createComposeGridButton(isEmailDraft ? 'Exit Email' : 'Exit Creation', () => {
        window.location.href = isEmailDraft ? 'gridpage.html?email_finalize=1' : 'gridpage.html?compose_finalize=1';
    }, currentCount);
    quitButton.id = 'compose-quit-button';
    container.appendChild(quitButton);
    updateComposeQuestionDisplay(isEmailDraft ? 'Email in progress' : 'Creation in progress');
}



// --- User Management Functions ---
// Called to load the current user state, including UI updates and refreshing local data

// The user-id-selector, set-user-id-button, and create-user-button related UI and functions
// are removed as user selection is handled by auth.html and user_select.html.
// currentAacUserId from sessionStorage is the source of truth.


// --- DOMContentLoaded Initialization ---
document.addEventListener('DOMContentLoaded', async () => {
    // Debug viewer for persistent localStorage messages
    if (window.location.search.includes('debug=1')) {
        console.log('🔍 DEBUG MODE ENABLED - localStorage debug messages:');
        console.log('LLM Selection:', localStorage.getItem('debug_llm_selection'));
        console.log('LLM Success:', localStorage.getItem('debug_llm_success'));
        console.log('LLM Error:', localStorage.getItem('debug_llm_error'));
        console.log('Auth State:', localStorage.getItem('debug_auth_state'));
        console.log('Server Error:', localStorage.getItem('debug_server_error'));
        console.log('Fetch Error:', localStorage.getItem('debug_fetch_error'));
    }

    const userReady = await initializeUserContext();
    if (!userReady) {
        // Redirection already handled by initializeUserContext
        return;
    }

    // Parallelize independent async operations for faster load
    const [scanSettingsResult, pagesResponse] = await Promise.all([
        loadScanSettings(),
        authenticatedFetch('/pages', { method: 'GET' })
    ]);
    console.log('✅ Core initialization complete (parallelized)');
    
    // 3. Initialize grid layout with loaded gridColumns setting
    updateGridLayout();

    const params = new URLSearchParams(window.location.search);
    const isComposeEntryView = params.get('compose_entry') === '1';
    const isComposeFinalizeView = params.get('compose_finalize') === '1';
    const isEmailEntryView = params.get('email_menu') === '1';
    const isEmailFinalizeView = params.get('email_finalize') === '1';
    const isEmailComposeView = params.get('email_compose') === '1';
    const composeResumeFlag = params.get('compose') === '1';
    const isComposeFlowView = isComposeEntryView || isComposeFinalizeView || isEmailEntryView || isEmailFinalizeView || isEmailComposeView;

    // Remove the user-id-selector related UI elements if they exist
    document.getElementById('user-id-selector')?.closest('div')?.remove();

    // 4. Show mood selection if enabled and not already set for this session
    // Lazy load non-critical features - don't block page render
    Promise.all([
        isComposeFlowView ? Promise.resolve() : showMoodSelectionIfNeeded(),
        window.avatarSelector?.initializeAfterAuth?.()
    ]).catch(err => console.warn('Non-critical feature init failed:', err));

    const gridContainer = document.getElementById('gridContainer');
    let pageName = params.get('page');

    if (!pageName) {
        pageName = "home";
    }

    // Set banner title based on selected user's display name or page name
    setBannerAndPageTitle();

    try {
        if (!pagesResponse.ok) {
            const errorText = await pagesResponse.text();
            throw new Error(`Failed to load pages: ${pagesResponse.status} - ${errorText}`);
        }
        const userPages = await pagesResponse.json();

        let pageToDisplay = userPages.find(p => p.name === pageName);

        // Load scan pattern from page metadata
        currentScanPattern = pageToDisplay?.scan_pattern || 'column';
        console.log(`Loaded scan pattern for page '${pageName}': ${currentScanPattern}`);

        if (!pageToDisplay) {
            console.warn(`Requested page '${pageName}' not found.`);
            const homePage = userPages.find(p => p.name === "home");
            if (homePage) {
                pageToDisplay = homePage; // Corrected variable name
                pageName = "home"; // Update pageName to reflect the fallback
                currentScanPattern = pageToDisplay?.scan_pattern || 'column'; // Load scan pattern for fallback page
                console.warn(`Defaulting to 'home' page.`);
            } else if (userPages.length > 0) {
                pageToDisplay = userPages[0];
                pageName = pageToDisplay.name; // Update pageName
                currentScanPattern = pageToDisplay?.scan_pattern || 'column'; // Load scan pattern for fallback page
                console.warn(`No 'home' page. Defaulting to first available page: '${pageName}'.`);
            } else {
                console.error(`No pages found for current user. Cannot display any content.`);
                gridContainer.innerHTML = `<p class="col-span-full text-center text-red-500">Error: No pages found.</p>`;
                return;
            }
        }

         // CRITICAL FIX: Move this line to AFTER pageToDisplay is defined and validated
        // Update banner and title with the actual page being displayed
        // Ensure pageToDisplay is not null/undefined before accessing properties
        sessionStorage.setItem('currentPageDisplayNameForBanner', pageToDisplay.displayName || capitalizeFirstLetter(pageToDisplay.name));
        setBannerAndPageTitle(); // Call again to set the correct title

        if (isComposeEntryView) {
            const fromUrl = params.get('from') || getComposeReturnTarget();
            await renderComposeEntryMenu(gridContainer, fromUrl);
        } else if (isComposeFinalizeView) {
            if (!isComposeSessionActive()) {
                window.location.href = 'gridpage.html?page=home';
                return;
            }
            await renderComposeFinalizeMenu(gridContainer);
        } else if (isEmailEntryView) {
            const fromUrl = params.get('from') || getEmailReturnTarget();
            await renderEmailEntryMenu(gridContainer, fromUrl);
        } else if (isEmailFinalizeView) {
            const fromUrl = params.get('from') || getEmailReturnTarget();
            if (!isComposeSessionActive() || !isEmailSessionActive()) {
                window.location.href = `gridpage.html?email_menu=1&from=${encodeURIComponent(fromUrl)}`;
                return;
            }
            await renderEmailFinalizeMenu(gridContainer, fromUrl);
        } else {
            if (composeResumeFlag && isEmailComposeView && !isComposeSessionActive()) {
                composeSession = {
                    active: true,
                    documentId: null,
                    title: '',
                    text: '',
                    startedAt: new Date().toISOString(),
                    sourceFrom: params.get('from') || getComposeReturnTarget()
                };
                saveComposeSession();
            }

            if (!isEmailComposeView && isComposeSessionActive() && !isEmailSessionActive()) {
                clearComposeSession();
            }

            await generateGrid(pageToDisplay, gridContainer);
            if (isComposeSessionActive()) {
                addQuitComposeButton(gridContainer);
                updateSpeechHistoryPanel(); // Switch label to "Compose" and show composition text
            }
        }

        const jokesParam = params.get('jokes');
        if (jokesParam) {
            document.getElementById('loading-indicator').style.display = 'flex';
            try {
                currentQuestion = 'tell me a joke';
                activeLLMPromptForContext = currentQuestion;
                activeOriginatingButtonText = 'Special Jokes';
                querytype = 'jokes';

                sessionStorage.setItem('currentPageDisplayNameForBanner', 'Jokes');
                setBannerAndPageTitle();

                const questionDisplay = document.getElementById('question-display');
                if (questionDisplay) {
                    questionDisplay.value = 'Tell me a joke';
                }

                const jokeOptions = await fetchJokeOptions(LLMOptions, currentQuestion);
                if (jokeOptions.length > 0) {
                    await generateLlmButtons(jokeOptions);
                } else {
                    console.warn('No jokes returned for special jokes navigation.');
                    announce('I could not find any jokes right now.', 'system', false);
                }
            } catch (error) {
                console.error('Error loading jokes for special navigation:', error);
                announce('Error loading jokes.', 'system', false);
            } finally {
                document.getElementById('loading-indicator').style.display = 'none';
            }
        }

        const guessWhoParam = params.get('guess_who');
        if (guessWhoParam) {
            // Redirect to Guess Who game page (session tokens preserved in sessionStorage)
            window.location.href = 'guess_who.html';
        }

        const optionsParam = params.get('options');
        if (optionsParam) {
            const options = decodeURIComponent(optionsParam).split('\n')
                .map((option) => option.replace(/^\d+\.\s*|\\|['"]+|^\(+\d\s*/g, '').replace('1. ', '').trim())
                .filter(Boolean);
            if (options.length > 0) {
                const optionsObjects = options.map(optText => ({ summary: optText, option: optText, keywords: [] }));
                console.log("Generating LLM buttons from URL params:", optionsObjects);
                await generateLlmButtons(optionsObjects);
            } else {
                console.warn("Options parameter found but resulted in empty options array.");
            }
        }
    } catch (error) {
        console.error('Error loading page data:', error);
        gridContainer.innerHTML = `<p class="col-span-full text-center text-red-500">Error loading page data: ${error.message}.</p>`;
    }


    // --- Setup Input Listeners ---
    setupKeyboardListener(); // Ensure called
    setupGamepadListeners(); // Ensure called

    // --- Setup Speech Recognition ---
    if (!isComposeFlowView && !isComposeSessionActive()) {
        setupSpeechRecognition();
    }

    // --- Add AudioContext Resume Listeners (MUST HAVE for playing audio) ---
    document.body.addEventListener('mousedown', tryResumeAudioContext, { once: true });
    document.body.addEventListener('touchstart', tryResumeAudioContext, { once: true });
    document.body.addEventListener('keydown', tryResumeAudioContext, { once: true }); // Keyboard also counts as gesture

    // --- Setup Clear History Button ---
    const clearButton = document.getElementById('clear-history');
    const speechHistory = document.getElementById('speech-history');
    if (clearButton && speechHistory) {
        clearButton.addEventListener('click', () => {
            speechHistory.value = '';
            localStorage.removeItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId));
        });
    } else {
        console.error("Could not find clear-history button or speech-history textarea.");
    }
    // Initial load of user-specific speech history
    if (speechHistory) {
        const storedHistory = localStorage.getItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId));
        if (storedHistory) { speechHistory.value = storedHistory; }
    }
    // If a compose session is already active (e.g. returning to compose grid), switch the panel
    updateSpeechHistoryPanel();
    window.addEventListener('pageshow', syncComposeSessionFromStorage);
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') {
            syncComposeSessionFromStorage();
        }
    });
    window.addEventListener('focus', syncComposeSessionFromStorage);
    
    // --- NEW: Add event listeners for the admin toolbar buttons ---
    const switchUserButton = document.getElementById('switch-user-button');
    const logoutButton = document.getElementById('logout-button');

    function handleSwitchUser() {
        console.log("Switching user profile. Clearing session and redirecting to auth page for profile selection.");
        // Only set flag to prevent auto-proceed with default user - keep user authenticated
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        console.log('Set bravoSkipDefaultUser flag for profile selection');
        sessionStorage.clear();
        
        // Small delay to ensure localStorage is written before navigation
        setTimeout(() => {
            window.location.href = 'auth.html';
        }, 100);
    }

    function handleLogout() {
        console.log("Logging out. Clearing session and redirecting to auth page for login.");
        // Set both flags to prevent automatic re-login and auto-profile selection
        localStorage.setItem('bravoIntentionalLogout', 'true');
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        console.log('Set bravoIntentionalLogout and bravoSkipDefaultUser flags');
        sessionStorage.clear();
        
        // Small delay to ensure localStorage is written before navigation
        setTimeout(() => {
            window.location.href = 'auth.html';
        }, 100);
    }

    if (switchUserButton) {
        switchUserButton.addEventListener('click', handleSwitchUser);
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
    }

    // Avatar manager button removed

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
            pinModal.style.display = 'block';
            if (pinInput) {
                pinInput.value = '';
                pinInput.focus();
            }
            if (pinError) {
                pinError.style.display = 'none';
            }
        }
    }

    // Function to hide PIN modal
    function hidePinModal() {
        if (pinModal) {
            pinModal.style.display = 'none';
        }
        if (pinInput) {
            pinInput.value = '';
        }
        if (pinError) {
            pinError.style.display = 'none';
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
            adminIcons.style.display = 'flex';
        }
        if (lockButton) {
            lockButton.style.display = 'none';
        }
        hidePinModal();
    }

    // Function to lock admin toolbar
    function lockToolbar() {
        if (adminIcons) {
            adminIcons.style.display = 'none';
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
                        pinError.style.display = 'block';
                    }
                    if (pinInput) {
                        pinInput.value = '';
                        pinInput.focus();
                    }
                }
            } else {
                if (pinError) {
                    pinError.textContent = 'PIN must be 3-10 characters.';
                    pinError.style.display = 'block';
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
        if (e.key === 'Escape' && pinModal && pinModal.style.display === 'block') {
            hidePinModal();
        }
    });

    // Initialize toolbar state on page load
    lockToolbar();
});

// --- Debounce Function ---
function debounce(func, delay) {
    let timeoutId;
    return function(...args) {
        const context = this;
        clearTimeout(timeoutId);
        timeoutId = setTimeout(() => {
            func.apply(context, args);
        }, delay);
    };
}

// --- Grid Layout Update Function ---
function updateGridLayout() {
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) return;
    
    // Update the CSS grid template columns based on gridColumns setting
    gridContainer.style.gridTemplateColumns = `repeat(${gridColumns}, 1fr)`;
    
    // Calculate font size based on number of columns
    // Fewer columns (larger buttons) = larger font size
    // More columns (smaller buttons) = smaller font size
    const baseFontSize = 20; // Base font size in pixels
    const minFontSize = 10;  // Minimum font size
    const maxFontSize = 28;  // Maximum font size
    
    // Calculate font size: inversely proportional to number of columns
    // Formula: baseFontSize * (baseFactor / gridColumns) where baseFactor is calibrated for good results
    const fontSize = Math.max(minFontSize, Math.min(maxFontSize, baseFontSize * (8 / gridColumns)));
    
    // Set the CSS custom property for button font size
    gridContainer.style.setProperty('--button-font-size', `${fontSize}px`);
    
    console.log(`Grid layout updated to ${gridColumns} columns with ${fontSize}px font size`);
}

// --- Grid Generation ---
async function generateGrid(page, container) {
    stopAuditoryScanning();
    window.waitingForInitialSwitch = false;
    isPausedFromScanLimit = false;
    currentRowScanMode = false;
    currentRow = -1;

    container.innerHTML = '';
    updateGridLayout();

    const buttonsArray = Array.isArray(page.buttons) ? page.buttons : [];
    // 1. Filter out hidden buttons and those without text
    const visibleButtons = buttonsArray.filter(buttonData => {
        if (!(buttonData && buttonData.text && buttonData.text.trim() !== '' && buttonData.hidden !== true)) {
            return false;
        }

        if (isComposeSessionActive()) {
            const target = String(buttonData.targetPage || '').trim().toLowerCase();
            if (target === '!games' || target === '!compose' || target === '!composition') {
                return false;
            }
        }

        return true;
    });
    if (visibleButtons.length === 0) {
        container.innerHTML = `<p class="col-span-full text-center text-gray-500">No buttons configured.</p>`;
        return;
    }

    // 2. Sort by row, then col (undefineds go last)
    const sortedButtons = visibleButtons.slice().sort((a, b) => {
        const rowA = Number.isInteger(a.row) ? a.row : 9999;
        const rowB = Number.isInteger(b.row) ? b.row : 9999;
        if (rowA !== rowB) return rowA - rowB;
        const colA = Number.isInteger(a.col) ? a.col : 9999;
        const colB = Number.isInteger(b.col) ? b.col : 9999;
        return colA - colB;
    });

    // 3. Lay out buttons row by row, filling each row up to gridColumns
    // Use throttled loading to prevent server overwhelm
    const buttonPromises = sortedButtons.map(async (buttonData, idx) => {
        const currentRow = Math.floor(idx / gridColumns);
        const currentCol = idx % gridColumns;
        
        const button = document.createElement('button');
        
        // When disableTapPictograms is on: ALL buttons are plain text-only
        // No images, no sight word formatting, no assigned images — just text
        if (disableTapPictograms) {
            console.log(`[DISABLE TAP PICTOGRAMS] Plain text button for: "${buttonData.text}"`);
            button.textContent = buttonData.text;
        // Check if this is a sight word - if so, render as text-only with special formatting
        } else if (window.isSightWord && window.isSightWord(buttonData.text)) {
            console.log('[SIGHT WORD] Rendering text-only button for:', buttonData.text);
            button.textContent = buttonData.text;
            button.classList.add('sight-word-button');
            // Apply inline styles for sight words (bigger, bolder, red text)
            button.style.fontSize = '2.2em';
            button.style.fontWeight = '900';
            button.style.color = '#dc2626';
        } else {
            // Check for manually assigned image first, then search if not found
            let symbolImageUrl = buttonData.assigned_image_url || null;
            
            if (!symbolImageUrl) {
                // Try to get symbol image through search, fall back to pictogram if needed
                symbolImageUrl = await getSymbolImageForText(buttonData.text);
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
            imageElement.alt = buttonData.text;
            imageElement.style.width = '100%';
            imageElement.style.height = '100%';
            imageElement.style.objectFit = 'cover'; // Match LLM buttons - fills container
            imageElement.onerror = () => {
                console.warn(`Failed to load image for "${buttonData.text}" - using text-only display`);
                // No emoji fallback - just hide the broken image
                imageElement.style.display = 'none';
            };
            
            // Text footer (overlays bottom of image)
            const textFooter = document.createElement('div');
            textFooter.style.minHeight = '14px';
            textFooter.style.width = '100%';
            textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
            textFooter.style.color = 'white';
            textFooter.style.display = 'flex';
            textFooter.style.alignItems = 'center';
            textFooter.style.justifyContent = 'center';
            textFooter.style.padding = '0 3px';
            textFooter.style.margin = '0';
            textFooter.style.borderRadius = '0';
            textFooter.style.boxSizing = 'border-box';
            textFooter.style.position = 'absolute';
            textFooter.style.bottom = '0';
            textFooter.style.left = '0';
            textFooter.style.right = '0';
            
            const textSpan = document.createElement('span');
            textSpan.textContent = buttonData.text;
            textSpan.style.fontSize = '0.45em';
            textSpan.style.fontWeight = 'bold';
            textSpan.style.textAlign = 'center';
            textSpan.style.lineHeight = '0.95';
            textSpan.style.wordWrap = 'break-word';
            textSpan.style.hyphens = 'auto';
            textSpan.style.overflow = 'hidden';
            textSpan.style.display = '-webkit-box';
            textSpan.style.webkitLineClamp = '1';
            textSpan.style.webkitBoxOrient = 'vertical';
            
            imageContainer.appendChild(imageElement);
            textFooter.appendChild(textSpan);
            buttonContent.appendChild(imageContainer);
            buttonContent.appendChild(textFooter);
            button.appendChild(buttonContent);
        } else {
            // No image found - use text-only display (no emoji fallback)
            button.textContent = buttonData.text;
            }
        }
        
        button.dataset.llmQuery = buttonData.LLMQuery || '';
        button.dataset.targetPage = buttonData.targetPage || '';
        button.dataset.speechPhrase = buttonData.speechPhrase || '';
        button.dataset.queryType = buttonData.queryType || '';
        button.dataset.row = currentRow;
        button.dataset.col = currentCol;
        button.classList.add('grid-button'); // Add class for CSS styling (preserves sight-word-button if already set)
        button.style.gridRowStart = currentRow + 1;
        button.style.gridColumnStart = currentCol + 1;
        
        // Only apply these inline styles for non-sight-word buttons (they would override CSS class)
        if (!button.classList.contains('sight-word-button')) {
            button.style.padding = '0'; // Remove all padding
            button.style.margin = '0'; // Remove all margin
            button.style.border = 'none'; // Remove border
            button.style.position = 'relative'; // Allow for absolute positioning of text overlay
            button.style.overflow = 'hidden'; // Ensure images don't overflow button boundaries
        }
        
        button.addEventListener('click', debounce(() => handleButtonClick(buttonData), clickDebounceDelay));
        
        return button;
    });
    
    // Wait for all buttons to be created and append them to container
    const buttons = await Promise.all(buttonPromises);
    
    // Use DocumentFragment for batch DOM append (much faster than individual appends)
    const fragment = document.createDocumentFragment();
    buttons.forEach(button => fragment.appendChild(button));
    container.appendChild(fragment);

    // Delay scanning until after the page is rendered
    setTimeout(() => {
        console.log('🔍 GRIDPAGE SCANNING INIT DEBUG:');
        console.log('  ScanningOff:', ScanningOff);
        console.log('  waitForSwitchToScan:', waitForSwitchToScan);
        startOrWaitForScanning({ allowPrompt: true, source: 'generateGrid' });
    }, defaultDelay);
}

// --- Button Click Handling ---
async function handleButtonClick(buttonData) {
    // --- DEBUG TIMING ---
    const debugTimes = {};
    debugTimes.start = performance.now();

    // Check if scanning was paused from scan limit and resume it
    if (isPausedFromScanLimit) {
        await resumeAuditoryScanning();
        debugTimes.resumeScan = performance.now();
        console.log('[DEBUG] handleButtonClick: resumeAuditoryScanning only, total:', (debugTimes.resumeScan - debugTimes.start).toFixed(2), 'ms');
        return; // Don't process the button click, just resume scanning
    }

    // NEW: Check if we're in row-phase scanning and handle row selection
    if (currentRowScanMode && currentRow >= 0) {
        console.log(`Row phase: User selected row ${currentRow}, switching to column-phase scanning...`);
        stopAuditoryScanning();
        startColumnPhaseForRow(currentRow);
        return; // Return early, don't execute button action
    }

    // IMMEDIATELY stop scanning when any button is clicked
    stopAuditoryScanning();
    debugTimes.stopScan = performance.now();

    const clickTimestamp = new Date().toISOString();
    const pageInfo = getCurrentPageInfo();
    debugTimes.pageInfo = performance.now();

    let localQueryType = buttonData.queryType || '';
    const llmQuery = buttonData.LLMQuery || buttonData.llmQuery || '';  // Check both capital and lowercase
    const targetPage = buttonData.targetPage || '';
    const navigationType = buttonData.navigationType || '';
    const speechPhrase = buttonData.speechPhrase || '';
    const customAudioFile = buttonData.customAudioFile || null;

    // If we have an LLMQuery but no queryType, default to "options"
    if (llmQuery && !localQueryType) {
        localQueryType = 'options';
        console.log('🔧 Auto-set queryType to "options" for button with LLMQuery');
    }

    console.log('🎯 GRIDPAGE Button clicked:', { 
        text: buttonData.text || buttonData.option, 
        queryType: localQueryType, 
        llmQuery: llmQuery ? 'present' : 'none',
        llmQueryActual: llmQuery,  // Show actual value for debugging
        speechPhrase: speechPhrase ? speechPhrase : 'none',
        isLLMGenerated: buttonData.isLLMGenerated 
    });

    const buttonLabel = buttonData.option || buttonData.text || '';
    const buttonSummary = buttonData.summary || buttonLabel;

    let contextForLog;
    if (buttonData.isLLMGenerated) {
        console.log('🎯 GRIDPAGE ENTERING LLM CHAT HISTORY PATH for:', buttonLabel);
        contextForLog = buttonData.originalPrompt;
        // Record chat history for LLM-generated selection (await to ensure completion before page refresh)
        localStorage.setItem('debug_llm_selection', `Attempting to record: "${buttonLabel}" at ${new Date().toISOString()}`);
        console.log('🎯 GRIDPAGE Recording LLM-generated selection:', buttonLabel);
        try {
            // Refresh authentication context before recording
            firebaseIdToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
            currentAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);
            
            console.log('🔐 GRIDPAGE Auth tokens before chat history:', { 
                tokenPresent: !!firebaseIdToken, 
                userIdPresent: !!currentAacUserId 
            });
            
            if (!firebaseIdToken || !currentAacUserId) {
                throw new Error('Authentication tokens missing when recording LLM selection');
            }
            
            console.log('🎯 GRIDPAGE Calling recordChatHistory for LLM selection...');
            await recordChatHistory("", buttonLabel);
            localStorage.setItem('debug_llm_success', `Successfully recorded: "${buttonLabel}" at ${new Date().toISOString()}`);
            console.log('✅ GRIDPAGE LLM chat history recorded before page action');
        } catch (error) {
            localStorage.setItem('debug_llm_error', `Error recording "${buttonLabel}": ${error.message} at ${new Date().toISOString()}`);
            console.error('❌ Failed to record chat history for LLM selection:', error);
        }
    } else if (llmQuery) {
        console.log('🎯 GRIDPAGE NOT LLM generated, checking other paths. llmQuery present:', !!llmQuery);
        contextForLog = llmQuery;
    } else {
        activeOriginatingButtonText = null;
        contextForLog = pageInfo.name;
    }
    debugTimes.preLog = performance.now();

    // --- Log Button Click for Audit (FIRE-AND-FORGET, non-blocking) ---
    const logData = {
        timestamp: clickTimestamp,
        page_name: pageInfo.name,
        page_context_prompt: contextForLog,
        button_text: buttonLabel,
        button_summary: buttonSummary,
        is_llm_generated: buttonData.isLLMGenerated || false,
        originating_button_text: buttonData.isLLMGenerated ? buttonData.originatingButtonText : null
    };
    (async () => {
        try {
            const t0 = performance.now();
            console.log("[ASYNC] Sending button click log:", logData);
            const response = await authenticatedFetch('/api/audit/log-button-click', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(logData)
            });
            const t1 = performance.now();
            if (!response.ok) console.error("[ASYNC] Failed to log button click:", response.status, await response.text());
            else console.log("[ASYNC] Button click logged successfully:", logData, `[DEBUG] logButtonClick took ${(t1-t0).toFixed(2)} ms`);
        } catch (error) {
            console.error("[ASYNC] Error sending button click log:", error);
        }
    })();
    debugTimes.logClick = performance.now();

    // --- STEP 3: Execute the main logic (the slow part) ---
    try {
        debugTimes.preMain = performance.now();
        console.log('🔍 STEP 3: Checking llmQuery:', llmQuery ? 'YES' : 'NO', 'Value:', llmQuery);
        if (llmQuery) {
            console.log('✅ ENTERING LLM QUERY BRANCH');
            const t0 = performance.now();
            // Case 1: Button triggers an LLM query.
            if (speechPhrase) {
                console.log('🎤 Has speech phrase, announcing:', speechPhrase);
                const tAnnounce0 = performance.now();
                await announce(speechPhrase, "system", false); // Announce while speech bubble is clear.
                const tAnnounce1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: announce(speechPhrase) took ${(tAnnounce1-tAnnounce0).toFixed(2)} ms`);
                
                // Record chat history for user speech selection
                console.log('🎯 GRIDPAGE Recording speech selection:', speechPhrase);
                recordChatHistory("", speechPhrase).catch(error => {
                    console.error('Failed to record chat history for gridpage speech:', error);
                });
            }
            
            // Play custom MP3 audio file if assigned
            if (customAudioFile) {
                const tAudio0 = performance.now();
                await playCustomButtonAudio(customAudioFile);
                const tAudio1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: playCustomButtonAudio took ${(tAudio1-tAudio0).toFixed(2)} ms`);
            }
            
            // Show loading indicator AFTER the speech announcement is complete
            document.getElementById('loading-indicator').style.display = 'flex';

            if (buttonLabel) {
                sessionStorage.setItem('dynamicBannerTitle', buttonLabel);
                setBannerAndPageTitle();
            }

            isLLMProcessing = true;
            querytype = localQueryType;
            if (localQueryType) { // Only save if we have a valid queryType
                localStorage.setItem('llm_currentQueryType', localQueryType);
                console.log('Saved querytype to localStorage:', localQueryType);
            }
            activeOriginatingButtonText = buttonLabel;
            activeLLMPromptForContext = llmQuery;
            initializeFollowUpConversation(llmQuery);

            // Note: #LLMOptions replacement now handled on server side
            currentQuestion = llmQuery;
            if (llmQuery) { // Only save if we have a valid question
                localStorage.setItem('llm_currentQuestion', llmQuery);
                console.log('Saved currentQuestion to localStorage:', llmQuery);
            }
            sessionStorage.setItem('currentQuestion', llmQuery);

            const summaryInstruction = SummaryOff ?
                'The "summary" key should contain the exact same FULL text as the "option" key.' :
                'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';

            const promptForLLM = `"${llmQuery}". Format as a JSON list... ${summaryInstruction} ...${getComposePromptContext()}`;
            const tLLM0 = performance.now();
            const options = await getLLMResponse(promptForLLM);
            const tLLM1 = performance.now();
            console.log(`[DEBUG] handleButtonClick: getLLMResponse took ${(tLLM1-tLLM0).toFixed(2)} ms`);
            
            // LLM options generated - no chat history recorded here
            
            const tGen0 = performance.now();
            await generateLlmButtons(options); // This function will restart scanning.
            const tGen1 = performance.now();
            console.log(`[DEBUG] handleButtonClick: generateLlmButtons took ${(tGen1-tGen0).toFixed(2)} ms`);
            debugTimes.llmBranch = performance.now();

        } else if (localQueryType === "currentevents") {
            // Case 2: Button navigates to current events.
            if (buttonLabel) {
                sessionStorage.setItem('dynamicBannerTitle', buttonLabel);
                setBannerAndPageTitle();
                activeLLMPromptForContext = `User is viewing current events for category: ${buttonData.text.toLowerCase()}`;
                activeOriginatingButtonText = buttonLabel;
            }
            isLLMProcessing = true; 
            querytype = localQueryType; 
            eventtype = buttonData.text.toLowerCase();
            const tEvents0 = performance.now();
            await getCurrentEvents(eventtype); // This function handles its own spinner hiding.
            const tEvents1 = performance.now();
            console.log(`[DEBUG] handleButtonClick: getCurrentEvents took ${(tEvents1-tEvents0).toFixed(2)} ms`);
            debugTimes.currentEventsBranch = performance.now();

        } else if (localQueryType === "thread") {
            // Case 2.5: Button opens thread automatically using current favorite if available
            console.log('Thread button clicked - checking for loaded favorite');
            activeOriginatingButtonText = null;
            
            try {
                // Get current user state to check for loaded favorite
                const currentStateResponse = await fetch('/get-user-current', {
                    method: 'GET',
                    headers: await getAuthHeaders()
                });
                
                if (currentStateResponse.ok) {
                    const currentState = await currentStateResponse.json();
                    console.log('Current state for thread detection:', currentState);
                    
                    // Check if there's a currently loaded favorite
                    if (currentState.favorite_name && currentState.loaded_at) {
                        // Navigate directly to thread with the loaded favorite
                        console.log(`Opening thread for loaded favorite: ${currentState.favorite_name}`);
                        await announce(`Opening thread for ${currentState.favorite_name}.`, "system", false);
                        setTimeout(() => {
                            window.location.href = `/static/threads.html`;
                        }, 1000); // Small delay to let announcement play
                        document.getElementById('loading-indicator').style.display = 'none';
                        return;
                    } else {
                        console.log('No loaded favorite found. Current state:', {
                            favorite_name: currentState.favorite_name,
                            loaded_at: currentState.loaded_at
                        });
                    }
                }
                
                // No loaded favorite, use the existing thread opening logic
                console.log('No loaded favorite found, using standard thread opening');
                await handleOpenThreadCommand();
                
            } catch (error) {
                console.error('Error handling thread button:', error);
                await announce('Error opening thread. Please try again.', "system", false);
                document.getElementById('loading-indicator').style.display = 'none';
                startAuditoryScanning();
            }
            
            debugTimes.threadBranch = performance.now();

        } else if (navigationType === 'GO-BACK-PAGE') {
            // Case 3a: GO-BACK-PAGE navigation (return to previous page in history)
            activeOriginatingButtonText = null;
            
            if (speechPhrase) {
                const tAnnounce0 = performance.now();
                await announce(speechPhrase, "system", false);
                const tAnnounce1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: announce(speechPhrase) (go-back) took ${(tAnnounce1-tAnnounce0).toFixed(2)} ms`);
                
                // Record chat history for user speech selection
                console.log('🎯 GRIDPAGE Recording go-back speech:', speechPhrase);
                recordChatHistory("", speechPhrase).catch(error => {
                    console.error('Failed to record chat history for go-back speech:', error);
                });
            }
            
            // Play custom MP3 audio file if assigned
            if (customAudioFile) {
                const tAudio0 = performance.now();
                await playCustomButtonAudio(customAudioFile);
                const tAudio1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: playCustomButtonAudio (go-back) took ${(tAudio1-tAudio0).toFixed(2)} ms`);
            }
            
            // Navigate back in browser history
            console.log('⬅️ GO-BACK-PAGE: Navigating to previous page');
            window.history.back();
            return;
            
        } else if (targetPage) {
            // Case 3b: Button is a navigation link (special or normal)
            activeOriginatingButtonText = null;
            
            // Check if we should return to a TEMPORARY navigation source instead
            const tempNavReturn = sessionStorage.getItem('tempNavReturnPage');
            if (tempNavReturn) {
                console.log('🔄 TEMPORARY navigation: Returning to original page:', tempNavReturn);
                sessionStorage.removeItem('tempNavReturnPage');
                
                if (speechPhrase) {
                    const tAnnounce0 = performance.now();
                    await announce(speechPhrase, "system", false);
                    const tAnnounce1 = performance.now();
                    console.log(`[DEBUG] handleButtonClick: announce(speechPhrase) (temp nav return) took ${(tAnnounce1-tAnnounce0).toFixed(2)} ms`);
                    
                    // Record chat history for user speech selection
                    console.log('🎯 GRIDPAGE Recording temp nav return speech:', speechPhrase);
                    recordChatHistory("", speechPhrase).catch(error => {
                        console.error('Failed to record chat history for temp nav return:', error);
                    });
                }
                
                // Play custom MP3 audio file if assigned
                if (customAudioFile) {
                    const tAudio0 = performance.now();
                    await playCustomButtonAudio(customAudioFile);
                    const tAudio1 = performance.now();
                    console.log(`[DEBUG] handleButtonClick: playCustomButtonAudio (temp nav return) took ${(tAudio1-tAudio0).toFixed(2)} ms`);
                }
                
                // Return to original page (ignore this button's targetPage)
                window.location.href = `gridpage.html?page=${tempNavReturn}`;
                return;
            }
            
            if (speechPhrase) {
                const tAnnounce0 = performance.now();
                await announce(speechPhrase, "system", false);
                const tAnnounce1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: announce(speechPhrase) (nav) took ${(tAnnounce1-tAnnounce0).toFixed(2)} ms`);
                
                // Record chat history for user speech selection
                console.log('🎯 GRIDPAGE Recording navigation speech:', speechPhrase);
                recordChatHistory("", speechPhrase).catch(error => {
                    console.error('Failed to record chat history for gridpage navigation speech:', error);
                });
            }
            
            // Play custom MP3 audio file if assigned
            if (customAudioFile) {
                const tAudio0 = performance.now();
                await playCustomButtonAudio(customAudioFile);
                const tAudio1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: playCustomButtonAudio (nav) took ${(tAudio1-tAudio0).toFixed(2)} ms`);
            }
            
            // If this is TEMPORARY navigation, store current page for return
            if (navigationType === 'TEMPORARY') {
                const currentPageName = pageInfo?.name;
                if (currentPageName && currentPageName !== 'UnknownPage') {
                    console.log('🔄 TEMPORARY navigation: Storing return page:', currentPageName);
                    sessionStorage.setItem('tempNavReturnPage', currentPageName);
                }
            }
            
            // Navigate immediately (no delay)
            if (typeof targetPage === 'string' && targetPage.startsWith('!')) {
                // Special page: navigate directly to the corresponding HTML
                const specialPage = targetPage.substring(1).toLowerCase();
                
                // For favorites page, pass current location as 'from' parameter
                if (specialPage === 'favorites') {
                    const currentUrl = window.location.href;
                    window.location.href = `${specialPage}.html?from=${encodeURIComponent(currentUrl)}`;
                } else if (specialPage === 'jokes') {
                    const params = new URLSearchParams();
                    params.set('jokes', '1');
                    window.location.href = `gridpage.html?${params.toString()}`;
                } else if (specialPage === 'guess-who' || specialPage === 'guesswho') {
                    const params = new URLSearchParams();
                    params.set('guess_who', '1');
                    window.location.href = `gridpage.html?${params.toString()}`;
                } else if (specialPage === 'mood' || specialPage === 'mood-selection') {
                    if (typeof clearCurrentMood === 'function') {
                        clearCurrentMood();
                    } else {
                        sessionStorage.removeItem('currentSessionMood');
                    }

                    if (typeof showMoodSelection === 'function') {
                        showMoodSelection((selectedMood) => {
                            if (selectedMood) {
                                console.log('Mood updated from gridpage button:', selectedMood);
                            } else {
                                console.log('Mood selection dismissed or unavailable from gridpage button.');
                            }
                            startAuditoryScanning();
                        });
                    } else {
                        console.warn('showMoodSelection is unavailable; falling back to mood.html');
                        window.location.href = 'mood.html';
                    }
                    return;
                } else if (specialPage === 'spelling' || specialPage === 'spell') {
                    const params = new URLSearchParams();
                    params.set('from', window.location.href);
                    window.location.href = `spelling.html?${params.toString()}`;
                } else if (specialPage === 'numbers' || specialPage === 'number') {
                    const params = new URLSearchParams();
                    params.set('from', window.location.href);
                    window.location.href = `numbers.html?${params.toString()}`;
                } else if (specialPage === 'email' || specialPage === 'emails') {
                    const params = new URLSearchParams();
                    params.set('from', window.location.href);
                    params.set('email_menu', '1');
                    window.location.href = `gridpage.html?${params.toString()}`;
                } else if (specialPage === 'compose' || specialPage === 'composition') {
                    const params = new URLSearchParams();
                    params.set('from', window.location.href);
                    params.set('compose_entry', '1');
                    window.location.href = `gridpage.html?${params.toString()}`;
                } else if (specialPage === 'freestyle') {
                    // For freestyle page, pass context information for contextual word suggestions
                    console.log('DEBUG: Before freestyle navigation - activeLLMPromptForContext:', activeLLMPromptForContext);
                    console.log('DEBUG: Before freestyle navigation - activeOriginatingButtonText:', activeOriginatingButtonText);
                    console.log('DEBUG: Before freestyle navigation - pageInfo:', pageInfo);
                    
                    const params = new URLSearchParams();
                    
                    // Pass current page name as source context
                    if (pageInfo?.name && pageInfo.name !== 'UnknownPage') {
                        params.set('source_page', pageInfo.name);
                    }
                    
                    // Pass LLM context if available (indicates LLM-generated page)
                    if (activeLLMPromptForContext) {
                        params.set('context', activeLLMPromptForContext);
                        params.set('is_llm_generated', 'true');
                    }
                    
                    // Pass originating button text if available
                    if (activeOriginatingButtonText) {
                        params.set('originating_button', activeOriginatingButtonText);
                    }

                    if (isComposeSessionActive()) {
                        params.set('compose', '1');
                    }
                    
                    console.log('DEBUG: Freestyle navigation params:', params.toString());
                    const queryString = params.toString();
                    window.location.href = queryString ? `${specialPage}.html?${queryString}` : `${specialPage}.html`;
                } else {
                    window.location.href = `${specialPage}.html`;
                }
            } else {
                // Normal page: use gridpage.html?page=targetPage
                window.location.href = `gridpage.html?page=${targetPage}`;
            }
            debugTimes.targetPageBranch = performance.now();

        } else if (speechPhrase || customAudioFile) {
            // Case 4: Button just speaks a phrase or plays audio.
            activeOriginatingButtonText = null;
            
            // Check if we should return to a TEMPORARY navigation source
            const tempNavReturn = sessionStorage.getItem('tempNavReturnPage');
            if (tempNavReturn) {
                console.log('🔄 TEMPORARY navigation: Returning to original page after speech:', tempNavReturn);
                sessionStorage.removeItem('tempNavReturnPage');
                
                if (speechPhrase) {
                    await announce(speechPhrase, "system", false);
                    // Record chat history for user speech selection
                    console.log('🎯 GRIDPAGE Recording temp nav speech before return:', speechPhrase);
                    recordChatHistory("", speechPhrase).catch(error => {
                        console.error('Failed to record chat history for temp nav speech:', error);
                    });
                }
                
                // Play custom MP3 audio file if assigned
                if (customAudioFile) {
                    await playCustomButtonAudio(customAudioFile);
                }
                
                // Return to original page
                window.location.href = `gridpage.html?page=${tempNavReturn}`;
                return;
            }
            
            if (speechPhrase) {
                const tAnnounce0 = performance.now();
                await announce(speechPhrase, "system", false);
                const tAnnounce1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: announce(speechPhrase) (speak only) took ${(tAnnounce1-tAnnounce0).toFixed(2)} ms`);
                
                // Record chat history for user speech selection
                console.log('🎯 GRIDPAGE Recording speak-only:', speechPhrase);
                recordChatHistory("", speechPhrase).catch(error => {
                    console.error('Failed to record chat history for gridpage speak-only:', error);
                });
            }
            
            // Play custom MP3 audio file if assigned
            if (customAudioFile) {
                const tAudio0 = performance.now();
                await playCustomButtonAudio(customAudioFile);
                const tAudio1 = performance.now();
                console.log(`[DEBUG] handleButtonClick: playCustomButtonAudio (speak only) took ${(tAudio1-tAudio0).toFixed(2)} ms`);
            }
            // CRITICAL: Hide spinner and restart scanning for simple speak actions.
            document.getElementById('loading-indicator').style.display = 'none';
            startAuditoryScanning();
            debugTimes.speakOnlyBranch = performance.now();

        } else {
            // Case 5: Button with no action, hide spinner and restart scanning.
            console.warn("Button clicked with no action defined:", buttonData);
            document.getElementById('loading-indicator').style.display = 'none';
            startAuditoryScanning();
            debugTimes.noActionBranch = performance.now();
        }
    } catch (error) {
        debugTimes.error = performance.now();
        console.error("Error in handleButtonClick main logic:", error);
        announce("Sorry, an error occurred.", "system", false);
        document.getElementById('loading-indicator').style.display = 'none';
        startAuditoryScanning(); // Restart scanning on error
    } finally {
        // This finally block now mostly ensures the processing flag is reset.
        // Spinner management is handled within each specific logic path.
        if (isLLMProcessing) {
             isLLMProcessing = false;
        }
        debugTimes.finally = performance.now();
        // --- SUMMARY LOG ---
        const steps = Object.keys(debugTimes);
        let last = debugTimes.start;
        for (const step of steps) {
            if (step !== 'start') {
                console.log(`[DEBUG] handleButtonClick: ${step} took ${(debugTimes[step] - last).toFixed(2)} ms`);
                last = debugTimes[step];
            }
        }
        console.log(`[DEBUG] handleButtonClick: TOTAL ${(debugTimes.finally - debugTimes.start).toFixed(2)} ms`);
    }
}

// --- Chat History with fallback to local storage ---
async function recordChatHistory(question, response) {
    console.log('🎯 GRIDPAGE recordChatHistory called with:', { question, response });
    
    // Check authentication state before making request
    const tokenPresent = !!sessionStorage.getItem('firebaseIdToken');
    const userIdPresent = !!sessionStorage.getItem('currentAacUserId');
    console.log('🔐 Auth check - Token present:', tokenPresent, 'UserID present:', userIdPresent);
    localStorage.setItem('debug_auth_state', `Token: ${tokenPresent}, UserID: ${userIdPresent} at ${new Date().toISOString()}`);
    
    try {
        const recorded = await authenticatedFetch('/record_chat_history', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, // authenticatedFetch adds Auth and X-User-ID
            body: JSON.stringify({ question, response })
        });
        if (!recorded.ok) {
            const errorText = await recorded.text();
            console.error('❌ Chat history server error:', recorded.status, errorText);
            localStorage.setItem('debug_server_error', `${recorded.status}: ${errorText} at ${new Date().toISOString()}`);
            throw new Error(`HTTP error! status: ${recorded.status} - ${errorText}`);
        }
        const responseData = await recorded.json();
        console.log('✅ GRIDPAGE Chat history recorded successfully:', responseData);
        localStorage.setItem('debug_chat_success', `Recorded "${response}" at ${new Date().toISOString()}`);
    } catch (error) {
        console.error('❌ GRIDPAGE Error recording chat history:', error);
        localStorage.setItem('debug_fetch_error', `${error.message} at ${new Date().toISOString()}`);
        
        // Fallback: Store in local storage for later sync
        if (error.message.includes('Authentication') || error.message.includes('expired')) {
            const pendingEntry = {
                question: question || "",
                response: response || "",
                timestamp: new Date().toISOString(),
                id: `pending_${Date.now()}`
            };
            
            const pending = JSON.parse(localStorage.getItem('pending_chat_history') || '[]');
            pending.push(pendingEntry);
            localStorage.setItem('pending_chat_history', JSON.stringify(pending));
            console.log('💾 Stored chat history locally for later sync:', pendingEntry);
            localStorage.setItem('debug_local_store', `Stored locally: "${response}" at ${new Date().toISOString()}`);
        }
    }
}


// --- Current Events ---
async function getCurrentEvents(eventType) {
    console.log(`Workspaceing current events for type: ${eventType}`);
    document.getElementById('loading-indicator').style.display = 'flex';
    
    try { // Outer try block - KEEP THIS ONE
        // REMOVE THE INNER `try {` LINE HERE
        const response = await authenticatedFetch('/get-current-events', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, // authenticatedFetch adds Auth and X-User-ID
            body: JSON.stringify({ eventType }),
        });

        // Check if the HTTP request itself was successful (e.g., status 200 OK)
        if (!response.ok) {
            let errorDetails = `HTTP error! status: ${response.status}`;
            try {
                const errorText = await response.text();
                errorDetails += `, Body: ${errorText}`;
            } catch (e) {
                // Ignore error reading body if it fails
            }
            console.error("Fetch request failed:", errorDetails);
            throw new Error(errorDetails);
        }

        const optionsData = await response.json();

        console.log("Successfully received and parsed data:", optionsData);

        if (Array.isArray(optionsData)) {
            await generateLlmButtons(optionsData);
        } else {
            console.error("Error: Data received from server is not an array.", optionsData);
            isLLMProcessing = false; // Reset flag on error
        }

    } catch (error) { // Outer catch block - KEEP THIS ONE
        console.error('Error in getCurrentEvents function:', error);
        isLLMProcessing = false; // Reset flag on error
    } finally { // Outer finally block - KEEP THIS ONE
        document.getElementById('loading-indicator').style.display = 'none'; 
    }
}

// --- LLM Interaction ---
async function getLLMResponse(prompt) {
    console.log("Sending LLM Request (Prompt length):", prompt.length);
    try {
        function prepareJsonString(str) { /* ... */ }

        // When a compose session is active, tell the server to suppress location context
        // and focus the LLM on composition continuation instead.
        const requestBody = { prompt };
        if (isComposeSessionActive()) {
            requestBody.compose_mode = true;
            requestBody.compose_body = String(composeSession.text || '').trim();
        }

        const response = await authenticatedFetch('/llm', { // Use authenticatedFetch
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, // authenticatedFetch adds Auth and X-User-ID
            body: JSON.stringify(requestBody),
        });

        if (!response.ok) {
            const eT = await response.text();
            throw new Error(`LLM HTTP error! status: ${response.status} ${eT}`);
        }

        const parsedJson = await response.json();
        console.log("LLM Response Received (Raw Parsed):", parsedJson);

        if (!Array.isArray(parsedJson)) {
            console.error("LLM response was not an array:", parsedJson);
            return [];
        }

        // --- THIS IS THE NEW, INTELLIGENT TRANSFORMATION LOGIC ---
        const transformedData = parsedJson.map(item => {
            if (!item || typeof item !== 'object') {
                return null; // Ignore invalid items in the array
            }

            const summary = item.summary;
            const keywords = item.keywords; // Preserve keywords field
            let option = null;

            // Find the key that is NOT 'summary' or 'keywords' and use its value as the 'option'
            const otherKeys = Object.keys(item).filter(key => key !== 'summary' && key !== 'keywords');
            if (otherKeys.length > 0) {
                option = item[otherKeys[0]]; // Take the value of the first other key
            }

            // If we found a summary and an option, create a standardized object
            if (summary != null && option != null) {
                return {
                    option: String(option), // Ensure they are strings
                    summary: String(summary),
                    keywords: keywords, // Include keywords if present
                    isLLMGenerated: true,
                    originalPrompt: activeLLMPromptForContext,
                    originatingButtonText: activeOriginatingButtonText
                };
            }

            return null; // Return null if the object is not in the expected format
        }).filter(Boolean); // The .filter(Boolean) removes any null entries

        console.log("Transformed and Validated Data:", transformedData);
        
        if (transformedData.length !== parsedJson.length) {
            console.warn(`Filtered out ${parsedJson.length - transformedData.length} malformed items from the LLM response.`);
        }
        
        return transformedData;

    } catch (error) {
        console.error("Error fetching or processing LLM Response:", error);
        const loadingIndicator = document.getElementById('loading-indicator');
        if (loadingIndicator) {
            loadingIndicator.style.display = 'none';
        }
        return [];
    }
}

// --- Speech Recognition (Keyword and Question) ---
let recognition = null;
let isSettingUpRecognition = false;
let listeningForQuestion = false; // This flag is crucial

function setupSpeechRecognition() {
    if (isSettingUpRecognition || recognition) { return; }
    isSettingUpRecognition = true;
    console.log("Setting up Keyword speech recognition...");
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error("Speech Recognition API not supported."); isSettingUpRecognition = false; return;
    }
    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    console.log("Keyword Recognition object created:", recognition);

    recognition.onerror = function (event) {
        console.error("Keyword Speech recognition error:", event.error, event.message);
        if (['no-speech', 'audio-capture', 'network'].includes(event.error) && !listeningForQuestion) { // Only restart if not trying to listen for a question
             console.log("Keyword recognition error, attempting restart...");
             setTimeout(() => { recognition = null; isSettingUpRecognition = false; setupSpeechRecognition(); }, 1000);
        } else { isSettingUpRecognition = false; recognition = null; }
    };

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('Keyword check - Speech recognized:', transcript);
        if (listeningForQuestion) { console.log("Ignoring keyword, currently listening for question."); return; }

        const interjectionToUse = wakeWordInterjection || "hey";
        const nameToUse = wakeWordName || "bravo";
        const phraseWithSpace = `${interjectionToUse} ${nameToUse}`;
        const phraseWithComma = `${interjectionToUse}, ${nameToUse}`;
        const phraseWithCommaNoSpace = `${interjectionToUse},${nameToUse}`;

        console.log(`Checking for: "${phraseWithSpace}" OR "${phraseWithComma}" OR "${phraseWithCommaNoSpace}"`);

        // Check for "Open Thread" command
        if ((transcript.includes(phraseWithSpace) || transcript.includes(phraseWithComma) || transcript.includes(phraseWithCommaNoSpace)) && 
            transcript.includes("open thread")) {
            console.log(`Thread opening command detected! ("${transcript}")`);
            stopAuditoryScanning();
            if (recognition) {
                try { recognition.stop(); } catch(e) { console.warn("Error stopping keyword recognition:", e); }
                recognition.onresult = null; recognition.onerror = null; recognition.onend = null; recognition = null;
            }
            isSettingUpRecognition = false;
            
            // Handle thread opening
            await handleOpenThreadCommand();
            return;
        }

        if (transcript.includes(phraseWithSpace) || transcript.includes(phraseWithComma) || transcript.includes(phraseWithCommaNoSpace)) {
            console.log(`Keyword detected! ("${transcript}")`);
            stopAuditoryScanning();
            if (recognition) {
                console.log("Stopping keyword recognition...");
                try { recognition.stop(); } catch(e) { console.warn("Error stopping keyword recognition:", e); }
                recognition.onresult = null; recognition.onerror = null; recognition.onend = null; recognition = null;
                console.log("Stopped and cleared keyword recognition instance.");
            }
             isSettingUpRecognition = false;

            // *** HIGHLIGHT QUESTION TEXTAREA ***
            const questionTextarea = document.getElementById(QUESTION_TEXTAREA_ID);
            if (questionTextarea) {
                questionTextarea.classList.add(LISTENING_HIGHLIGHT_CLASS);
                questionTextarea.placeholder = "Listening for your question..."; // Update placeholder
            }
            updateStatusBar('🎤 Listening for your question...', true);

            const announcement = "I'm listening.";
            console.log("Calling announce for question prompt...");
            try {
                await announce(announcement, "system", false);
                console.log("Announce finished. Setting up question recognition.");
                setupQuestionRecognition(); // This will set listeningForQuestion = true
            } catch (announceError) {
                 console.error("Error during announcement:", announceError);
                 if (questionTextarea) questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); // Remove highlight on error
                 setupSpeechRecognition(); // Restart keyword spotting
            }
        }
    };

    recognition.onend = () => {
        console.log("Keyword Recognition ended.");
        if (!listeningForQuestion && !isSettingUpRecognition && recognition) {
             console.log("Keyword recognition ended unexpectedly, restarting.");
             recognition = null; setTimeout(setupSpeechRecognition, 500);
        } else {
             console.log("Keyword recognition ended normally or was already being reset/stopped.");
             isSettingUpRecognition = false;
        }
    };

    try { recognition.start(); console.log("Keyword recognition started."); isSettingUpRecognition = false; }
    catch (e) { console.error("Error starting keyword recognition:", e); isSettingUpRecognition = false; recognition = null; }
}

function setupQuestionRecognition() {
    console.log("Attempting to set up question recognition...");
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) { console.error("Speech Recognition API not supported."); announce("Sorry, I can't use speech recognition.", "system", false); return; }

    let questionRecognitionInstance = new SpeechRecognitionAPI(); // Use local instance
    questionRecognitionInstance.lang = 'en-US';
    questionRecognitionInstance.continuous = false;
    questionRecognitionInstance.interimResults = true;
    questionRecognitionInstance.maxAlternatives = 1;

    let finalTranscript = ''; let listeningTimeout; let hasProcessedResult = false; let isRestartingKeyword = false;
    const questionTextarea = document.getElementById(QUESTION_TEXTAREA_ID);

    console.log("Question Recognition Config:", { continuous: false, interimResults: true, lang: 'en-US', maxAlternatives: 1 });

    questionRecognitionInstance.onstart = () => {
        console.log("Question Recognition: Listening started...");
        finalTranscript = ''; hasProcessedResult = false;
        if (questionTextarea) {
            questionTextarea.placeholder = "Listening..."; // Ensure placeholder is set
            questionTextarea.value = "";
            questionTextarea.classList.add(LISTENING_HIGHLIGHT_CLASS); // Ensure highlight is on
        }
        updateStatusBar('🎤 Listening...', true);
        listeningForQuestion = true; // Set global state
        clearTimeout(listeningTimeout);
        listeningTimeout = setTimeout(() => {
             if (listeningForQuestion && !finalTranscript && !hasProcessedResult) {
                 console.log("Question Timeout: No speech detected."); announce("I didn't hear anything. Try again?", "system", false);
                 try { questionRecognitionInstance.stop(); } catch(e){}
             }
        }, 10000);
    };

    questionRecognitionInstance.onresult = async (event) => {
        console.log("Question onresult."); if (hasProcessedResult) return; clearTimeout(listeningTimeout);
        let interimTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
            const transcriptPart = event.results[i][0].transcript;
            if (event.results[i].isFinal) { finalTranscript += transcriptPart; } else { interimTranscript += transcriptPart; }
        }
        const displayTranscript = finalTranscript || interimTranscript;
        if (questionTextarea) questionTextarea.value = displayTranscript.trim();
        if (displayTranscript.trim()) updateStatusBar(displayTranscript.trim());

        const isFinishedUtterance = event.results[event.results.length - 1].isFinal;

        if (isFinishedUtterance && finalTranscript.trim()) {
            hasProcessedResult = true; console.log("Final Question:", finalTranscript.trim().toLowerCase());
            listeningForQuestion = false; // Set state BEFORE async

            // *** REMOVE HIGHLIGHT & SHOW LOADING ***
            if (questionTextarea) questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS);
            document.getElementById('loading-indicator').style.display = 'flex';

            try {
                announce("Okay, processing: " + finalTranscript.trim() + ". Give me a moment.", "system", false);
                updateStatusBar('Processing: ' + finalTranscript.trim() + '...');
                currentQuestion = finalTranscript.trim().toLowerCase();
                initializeFollowUpConversation(currentQuestion);

                const summaryInstruction = SummaryOff
                ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
                : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
                activeLLMPromptForContext = currentQuestion; // Set context to just the user's question
                activeOriginatingButtonText = "Voice Input"; // Mark as voice-initiated

                if (isJokeQuestion(currentQuestion)) {
                    querytype = "jokes";
                    const jokeOptions = await fetchJokeOptions(LLMOptions, currentQuestion);
                    if (jokeOptions.length > 0) {
                        await generateLlmButtons(jokeOptions);
                    } else {
                        console.warn("No jokes returned for joke request.");
                        announce("I couldn't find any jokes right now.", "system", false);
                        isRestartingKeyword = true;
                        setupSpeechRecognition();
                    }
                    return;
                }

                const promptForLLM = `
                    Provide up to "${LLMOptions}" short, single-phrase options related to: "${currentQuestion}".
                    Do not include any introductory or concluding text.
                    Each option should be a short, selectable next-step phrase for AAC use.
                    Prefer concrete activity choices, clarifying choices, or preference choices.
                    Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.
                    The "option" key should contain the FULL option text.
                    ${summaryInstruction}
                    The "keywords" key should contain 3-5 words that match available symbols. Use these available descriptive words: good, great, happy, sad, angry, excited, tired, hungry, thirsty, hot, cold, big, small, fast, slow, easy, hard, fun, work, play, eat, drink, sleep, walk, run, read, write, look, listen, talk, help, love, like, want, need, more, less, yes, no, stop, go, come, here, there, up, down, in, out, on, off, open, close, new, old, clean, dirty, quiet, loud, light, dark. Focus on concrete, simple words rather than complex descriptives.
                    Example: [{"option": "What a fantastic day!", "summary": "Fantastic day", "keywords": ["good", "happy", "great", "day", "fun"]}]
                    ${getComposePromptContext()}
                `;
                document.getElementById('loading-indicator').style.display = 'flex';
                const options = await getLLMResponse(promptForLLM);
                const prioritizedOptions = prioritizeContextualOptions(options, currentQuestion, LLMOptions);
                if (Array.isArray(prioritizedOptions) && (prioritizedOptions.length === 0 || prioritizedOptions.every(o => typeof o === 'object' && o !== null && 'option' in o && 'summary' in o))) {
                    querytype = "question"; await generateLlmButtons(prioritizedOptions);
                } else {
                    console.error("LLM response invalid:", prioritizedOptions); announce("Unexpected response.", "system", false);
                    isRestartingKeyword = true; setupSpeechRecognition();
                }
            } catch (error) {
                console.error('Error processing question:', error); announce("Error processing question.", "system", false);
                isRestartingKeyword = true; setupSpeechRecognition();
            } finally {
                //document.getElementById('loading-indicator').style.display = 'none';
                document.getElementById('loading-indicator').style.display = 'none'; // Ensure indicator is hidden
                if (questionTextarea) questionTextarea.placeholder = "Ask a question...";
                updateStatusBar(''); // Clear status bar after question is processed
                console.log("LLM processing finished for question.");
            }
        } else if (!isFinishedUtterance) { console.log("Waiting for final result..."); }
        else { console.log("Final utterance empty."); listeningForQuestion = false; if (questionTextarea) questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); updateStatusBar(''); }
    };

    questionRecognitionInstance.onerror = (event) => {
        clearTimeout(listeningTimeout); if (hasProcessedResult) return;
        console.error("Question Error:", event.error, event.message);
        let errorMessage = "Speech recognition error."; let attemptRetry = false;
        if (event.error === 'no-speech') {
            errorMessage = "Didn't hear anything. Try again?";
            if (!questionRecognitionInstance.hasRetried) { attemptRetry = true; errorMessage += " Retrying..."; questionRecognitionInstance.hasRetried = true; } // Use instance flag
            else { console.log("Already retried."); }
        } else if (event.error === 'not-allowed' || event.error === 'service-not-allowed') { errorMessage = "Mic access denied."; }
        else if (event.error === 'audio-capture') { errorMessage = "Mic problem."; }
        else if (event.error === 'network') { errorMessage = "Network error."; }
        else if (event.error === 'aborted') { errorMessage = ""; }

        if (errorMessage) { announce(errorMessage, "system", false); }
        document.getElementById('loading-indicator').style.display = 'none';
        if (questionTextarea) {
            questionTextarea.placeholder = "Ask a question...";
            questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); // Remove highlight on error
        }
        updateStatusBar(''); // Clear status bar on error
        listeningForQuestion = false;
        try { questionRecognitionInstance.stop(); } catch(e) {}

        if (attemptRetry) {
            console.log("Attempting retry...");
            setTimeout(() => {
                 try { finalTranscript = ''; listeningForQuestion = true; hasProcessedResult = false; questionRecognitionInstance.start(); }
                 catch (e) { console.error("Retry start error:", e); announce("Retry failed.", "system", false); listeningForQuestion = false; isRestartingKeyword = true; setupSpeechRecognition(); }
            }, 500);
        } else { 
            console.log("Not retrying. Restarting keyword listener.");
            isRestartingKeyword = true;
            setupSpeechRecognition();
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                console.log("Error in question rec (not retrying), restarting scanning for existing buttons.");
                startAuditoryScanning();
            }
        }
    };

    questionRecognitionInstance.onend = () => {
        clearTimeout(listeningTimeout); console.log("Question Recognition ended.");
        const wasRetried = questionRecognitionInstance?.hasRetried; const stillListening = listeningForQuestion; // Capture state before reset
        if (listeningForQuestion) { listeningForQuestion = false; console.log("Reset listening flag in onend."); }

        if (questionTextarea) {
            questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); // Ensure highlight is removed
            questionTextarea.placeholder = "Ask a question...";
        }
        updateStatusBar(''); // Clear status bar when recognition ends

        if (stillListening && !hasProcessedResult && !wasRetried) { console.log("Ended without result/retry."); announce("Didn't catch that. Try again?", "system", false); }

        if (!hasProcessedResult && !isRestartingKeyword) {
            console.log("Restarting keyword listener from onend.");
            setupSpeechRecognition();
            // If ending without result and falling back to keyword spotting, attempt to restart scanning.
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                console.log("Question rec ended (no result), restarting scanning for existing buttons.");
                startAuditoryScanning();
            }
        } else { console.log("Not restarting keyword listener from onend (processed, retrying, or handled by error)."); }

        questionRecognitionInstance = null; console.log("Question instance cleaned up.");
    };

    questionRecognitionInstance.onnomatch = () => { console.warn("Question No match."); };
    questionRecognitionInstance.onspeechend = () => {
        console.log("Question Speech ended."); clearTimeout(listeningTimeout);
        listeningTimeout = setTimeout(() => {
            if (listeningForQuestion && !hasProcessedResult) {
                console.warn("Timeout after speech end."); announce("Didn't get a final result.", "system", false);
                try { questionRecognitionInstance.stop(); } catch(e){}
            }
        }, 5000);
    };
    questionRecognitionInstance.onsoundend = () => { console.log("Question Sound ended."); };

    setTimeout(() => {
        try { console.log("Calling start() for question recognition..."); questionRecognitionInstance.start(); }
        catch (e) { console.error("Start error:", e); announce("Couldn't start listening.", "system", false); listeningForQuestion = false; clearTimeout(listeningTimeout); isRestartingKeyword = true; setupSpeechRecognition(); }
    }, 150);
}

// --- Thread Opening Function ---
async function handleOpenThreadCommand() {
    console.log('Handling open thread command');
    
    try {
        // First, get the list of available favorites
        const response = await authenticatedFetch('/api/user-current-favorites');
        if (!response.ok) {
            throw new Error(`Failed to load favorites: ${response.statusText}`);
        }
        
        const data = await response.json();
        const favorites = data.favorites || [];
        
        if (favorites.length === 0) {
            await announce('No favorite locations found. Please set up a favorite location first.', "system", false);
            // Restart keyword recognition
            setTimeout(() => {
                setupSpeechRecognition();
                if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                    startAuditoryScanning();
                }
            }, 1000);
            return;
        }
        
        if (favorites.length === 1) {
            // Only one favorite, open thread for it directly
            const favorite = favorites[0];
            await announce(`Opening thread for ${favorite.name}.`, "system", false);
            setTimeout(() => {
                window.location.href = `/static/threads.html?favorite=${encodeURIComponent(favorite.name)}`;
            }, 1500);
        } else {
            // Multiple favorites, let user choose
            await announce(`Which location would you like to open a thread for?`, "system", false);
            
            // Generate buttons for favorite selection
            const favoriteOptions = favorites.map(fav => ({
                option: `Open thread for ${fav.name}`,
                summary: fav.name,
                isLLMGenerated: false,
                favoriteData: fav
            }));
            
            // Generate buttons for favorite selection
            generateFavoriteSelectionButtons(favoriteOptions);
        }
        
    } catch (error) {
        console.error('Error handling open thread command:', error);
        await announce('Error opening thread. Please try again.', "system", false);
        // Restart keyword recognition
        setTimeout(() => {
            setupSpeechRecognition();
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                startAuditoryScanning();
            }
        }, 1000);
    }
}

// --- Generate Favorite Selection Buttons ---
function generateFavoriteSelectionButtons(favoriteOptions) {
    stopAuditoryScanning();
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) {
        console.error("gridContainer not found!");
        return;
    }
    
    gridContainer.innerHTML = '';
    updateGridLayout();
    
    let isAnnouncing = false;
    console.log("Generating favorite selection buttons for thread opening:", favoriteOptions);

    // Generate buttons for each favorite
    favoriteOptions.forEach(optionData => {
        const button = document.createElement('button');
        button.textContent = optionData.summary;
        button.dataset.option = optionData.option;
        
        button.addEventListener('click', async () => {
            if (isAnnouncing) return;
            isAnnouncing = true;
            stopAuditoryScanning();
            
            console.log("Favorite selection button clicked:", optionData.favoriteData.name);
            
            try {
                await announce(`Opening thread for ${optionData.favoriteData.name}.`, "system", false);
                setTimeout(() => {
                    window.location.href = `/static/threads.html?favorite=${encodeURIComponent(optionData.favoriteData.name)}`;
                }, 1500);
            } catch (error) {
                console.error("Error opening thread for favorite:", error);
                await announce('Error opening thread.', "system", false);
            } finally {
                isAnnouncing = false;
            }
        });
        
        gridContainer.appendChild(button);
    });

    // Add Cancel button
    const cancelButton = document.createElement('button');
    cancelButton.textContent = 'Cancel';
    cancelButton.addEventListener('click', async () => {
        stopAuditoryScanning();
        await announce('Thread opening cancelled.', "system", false);
        setTimeout(() => {
            window.location.reload(true);
        }, 1500);
    });
    gridContainer.appendChild(cancelButton);
    
    // Start auditory scanning
    if (gridContainer.childElementCount > 0) {
        console.log("Starting auditory scanning for favorite selection");
        startAuditoryScanning();
    }
}


// --- Custom Button Audio Playback Function ---
async function playCustomButtonAudio(audioUrl) {
    try {
        console.log(`[AUDIO] Playing custom button audio: ${audioUrl}`);
        
        // Create audio element
        const audio = new Audio(audioUrl);
        
        // Wait for the audio to load and play
        return new Promise((resolve, reject) => {
            audio.addEventListener('loadeddata', () => {
                console.log('[AUDIO] Custom audio loaded, starting playback');
            });
            
            audio.addEventListener('ended', () => {
                console.log('[AUDIO] Custom audio playback completed');
                resolve();
            });
            
            audio.addEventListener('error', (e) => {
                console.error('[AUDIO] Error playing custom audio:', e);
                resolve(); // Don't reject, just continue silently
            });
            
            // Start playback
            audio.play().catch(error => {
                console.error('[AUDIO] Failed to play custom audio:', error);
                resolve(); // Continue silently on error
            });
        });
        
    } catch (error) {
        console.error('[AUDIO] Error in playCustomButtonAudio:', error);
        // Don't throw error, just continue silently
    }
}

// --- Core Audio Playback Function (Centralized audio processing) ---
// This function is called by `processAnnouncementQueue` to play synthesized audio.
async function playAudioToDevice(audioDataBuffer, sampleRate, announcementType) { // announcementType needed to determine target speaker
    console.log(`playAudioToDevice: Starting playback for type "${announcementType}"`);

    // Get speaker IDs directly here, as this is the actual playback point.
    const personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
    const systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';
    
    let targetOutputDeviceId;
    if (announcementType === 'personal') {
        targetOutputDeviceId = personalSpeakerId;
    } else if (announcementType === 'system') {
        targetOutputDeviceId = systemSpeakerId;
    } else {
        targetOutputDeviceId = 'default';
    }
    console.log(`playAudioToDevice: Final targetOutputDeviceId: "${targetOutputDeviceId}"`);

    if (!audioDataBuffer) {
        console.error('playAudioToDevice: No audio data buffer provided.');
        throw new Error('No audio data buffer provided.');
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        if (audioContext.state === 'suspended') {
            console.log("playAudioToDevice: AudioContext is suspended, attempting to resume.");
            // We resume here; the tryResumeAudioContext() will provide the gesture.
            audioContext.resume().catch(err => {
                console.warn("playAudioToDevice: .resume() failed, probably no user gesture yet:", err);
            });
        }

        if (typeof audioContext.setSinkId === 'function' && targetOutputDeviceId && targetOutputDeviceId !== 'default') {
            console.log(`playAudioToDevice: Attempting to call audioContext.setSinkId to device (ID: ${targetOutputDeviceId})`);
            await audioContext.setSinkId(targetOutputDeviceId);
            console.log(`playAudioToDevice: setSinkId call FINISHED for device ${targetOutputDeviceId}`);
        } else {
            console.warn(`playAudioToDevice: Not performing explicit routing. Audio will play to browser's default speaker.`);
        }

        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        console.log("playAudioToDevice: Audio data decoded. Buffer duration:", audioBuffer.duration);

        source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        activeAnnouncementAudioContext = audioContext;
        activeAnnouncementAudioSource = source;
        source.start(0);
        console.log("playAudioToDevice: Audio source started.");

        return new Promise((resolve) => {
            source.onended = () => {
                console.log("playAudioToDevice: Audio playback ended.");
                activeAnnouncementAudioSource = null;
                if (activeAnnouncementAudioContext === audioContext) {
                    activeAnnouncementAudioContext = null;
                }
                audioContext.close(); // Important to release resources
                resolve();
            };
        }).catch(err => {
            console.error("playAudioToDevice: Error during audio playback promise:", err);
            if (audioContext && audioContext.state !== 'closed') audioContext.close();
            if (activeAnnouncementAudioContext === audioContext) {
                activeAnnouncementAudioContext = null;
                activeAnnouncementAudioSource = null;
            }
            throw err;
        });

    } catch (error) {
        console.error('playAudioToDevice: Fatal Error during setup or playback:', error);
        if (audioContext && audioContext.state !== 'closed') audioContext.close();
        if (activeAnnouncementAudioContext === audioContext) {
            activeAnnouncementAudioContext = null;
            activeAnnouncementAudioSource = null;
        }
        throw error;
    }
}

// --- Announcement Queue Processor ---
// This function manages playing announcements from the queue sequentially.
async function processAnnouncementQueue() {
    if (isAnnouncingNow || announcementQueue.length === 0) {
        return; // Already playing or nothing to play.
    }

    isAnnouncingNow = true;
    const announcement = announcementQueue.shift();
    const { textToAnnounce, announcementType, recordHistory, showSplash, useSystemVoice, resolve, reject, historyText } = announcement;

    console.log(`ANNOUNCE QUEUE: Playing "${textToAnnounce.substring(0, 30)}..." (Type: ${announcementType})`);

    // Show splash screen if enabled and requested
    if (typeof showSplashScreen === 'function' && showSplash !== false) {
        showSplashScreen(textToAnnounce);
    }

    try {
        // Fetch audio data from your server using authenticatedFetch
        const response = await authenticatedFetch(`/play-audio`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, // authenticatedFetch adds Auth and X-User-ID
            body: JSON.stringify({
                text: textToAnnounce,
                routing_target: announcementType,
                use_system_voice: useSystemVoice === true
            }),
        });

        if (!response.ok) {
            const errorBody = await response.json().catch(() => response.text());
            throw new Error(`Failed to synthesize audio: ${response.status} - ${JSON.stringify(errorBody)}`);
        }

        const jsonResponse = await response.json();
        const audioData = jsonResponse.audio_data;
        const sampleRate = jsonResponse.sample_rate;

        if (!audioData) {
            throw new Error("No audio data received from server.");
        }

        const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
        await playAudioToDevice(audioDataArrayBuffer, sampleRate, announcementType);

        if (recordHistory) {
            const textForHistory = historyText || textToAnnounce.replace(/\[PAUSE\]/g, ' ').trim();
            if (isComposeSessionActive()) {
                appendToComposeText(textForHistory);
            } else {
                const speechHistory = document.getElementById('speech-history');
                if (speechHistory) {
                    let history = (localStorage.getItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId)) || '').split('\n').filter(Boolean);
                    history.unshift(textForHistory);
                    if (history.length > 20) { history = history.slice(0, 20); }
                    speechHistory.value = history.join('\n');
                    localStorage.setItem(SPEECH_HISTORY_LOCAL_STORAGE_KEY(currentAacUserId), speechHistory.value);
                } else {
                    console.warn("Speech history textarea not found for recording.");
                }
            }
        }
        
        resolve(); 

    } catch (error) {
        console.error('ANNOUNCE QUEUE: Error during announcement playback:', error);
        reject(error);
    } finally {
        isAnnouncingNow = false;
        if (announcementQueue.length > 0) {
            processAnnouncementQueue();
        }
    }
}


// --- Announce Function (MODIFIED to use the queue) ---
// This function will now queue up messages for sequential playback.
async function announce(textToAnnounce, announcementType = "system", recordHistory = true, showSplash = true, useSystemVoice = false) {
    console.log(`ANNOUNCE: QUEUING "${textToAnnounce.substring(0, 30)}..." (Type: ${announcementType})`);
    
    // Special handling for RANDOM choice - detect {RANDOM:option1|option2|option3} pattern
    // Trim the input first to handle any whitespace issues
    const trimmedText = textToAnnounce.trim();
    const randomPattern = /^\{RANDOM:(.+)\}$/;
    const randomMatch = trimmedText.match(randomPattern);
    
    if (randomMatch) {
        // Extract options and split by pipe delimiter
        const options = randomMatch[1].split('|').map(opt => opt.trim()).filter(opt => opt.length > 0);
        
        if (options.length > 0) {
            // Randomly select one option
            const selectedOption = options[Math.floor(Math.random() * options.length)];
            console.log(`RANDOM CHOICE: Selected "${selectedOption}" from ${options.length} options`);
            console.log(`RANDOM CHOICE DEBUG: Original length=${textToAnnounce.length}, Trimmed length=${trimmedText.length}`);
            
            // Replace textToAnnounce with the selected option
            textToAnnounce = selectedOption;
        } else {
            console.warn('RANDOM CHOICE: No valid options found, using original text');
        }
    } else if (trimmedText.startsWith('{RANDOM:')) {
        // Pattern didn't match but it looks like it should be RANDOM - log for debugging
        console.warn('RANDOM CHOICE: Pattern detected but regex failed to match');
        console.warn('RANDOM CHOICE DEBUG: Text =', JSON.stringify(textToAnnounce));
        console.warn('RANDOM CHOICE DEBUG: Trimmed =', JSON.stringify(trimmedText));
    }
    
    // Special handling for [PAUSE] markers - split and announce each segment separately
    if (textToAnnounce.includes('[PAUSE]')) {
        const parts = textToAnnounce.split('[PAUSE]').map(p => p.trim()).filter(p => p.length > 0);
        
        if (parts.length > 1) {
            console.log(`PAUSE DETECTED: Split into ${parts.length} segments`);
            
            // Announce all parts except the last with pauses between them
            for (let i = 0; i < parts.length - 1; i++) {
                await new Promise((resolve, reject) => {
                    announcementQueue.push({
                        textToAnnounce: parts[i],
                        announcementType,
                        recordHistory: false, // Don't record the split parts
                        showSplash: showSplash,
                        useSystemVoice,
                        resolve,
                        reject
                    });
                    processAnnouncementQueue();
                });
                
                // Add 1.5-second pause between segments
                await new Promise(resolve => setTimeout(resolve, 1500));
            }
            
            // Announce the last part and record the FULL clean text to history
            const cleanText = textToAnnounce.replace(/\[PAUSE\]/g, ' ').trim();
            const lastPart = parts[parts.length - 1];
            
            return new Promise((resolve, reject) => {
                // Override textToAnnounce for history recording while playing the last part
                const lastAnnouncement = {
                    textToAnnounce: lastPart,
                    announcementType,
                    recordHistory: recordHistory,
                    showSplash: showSplash,
                    useSystemVoice,
                    resolve,
                    reject,
                    historyText: cleanText // Add custom property for clean history text
                };
                announcementQueue.push(lastAnnouncement);
                processAnnouncementQueue();
            });
        }
    }
    
    // Special handling for jokes - detect if text contains a question followed by an answer
    const jokePattern = /^(.+\?)\s*(.+[!.])$/;
    const jokeMatch = textToAnnounce.match(jokePattern);
    
    if (jokeMatch) {
        const question = jokeMatch[1].trim();
        const punchline = jokeMatch[2].trim();
        
        console.log(`JOKE DETECTED: Question="${question}" Punchline="${punchline}"`);
        
        // Announce the question first
        await new Promise((resolve, reject) => {
            announcementQueue.push({
                textToAnnounce: question,
                announcementType,
                recordHistory: false, // Don't record the split parts
                showSplash: showSplash,
                useSystemVoice,
                resolve,
                reject
            });
            processAnnouncementQueue();
        });
        
        // Add a 1-second pause
        await new Promise(resolve => setTimeout(resolve, 1500));
        
        // Then announce the punchline
        return new Promise((resolve, reject) => {
            announcementQueue.push({
                textToAnnounce: punchline,
                announcementType,
                recordHistory, // Record the full joke in history if requested
                showSplash: showSplash,
                useSystemVoice,
                resolve,
                reject
            });
            processAnnouncementQueue();
        });
    }
    
    // Regular announcement for non-jokes
    return new Promise((resolve, reject) => {
        announcementQueue.push({
            textToAnnounce,
            announcementType,
            recordHistory,
            showSplash,
            useSystemVoice,
            resolve, // Store the resolve function of this promise
            reject   // Store the reject function of this promise
        });

        // Trigger the queue processing. It will only start playing if not already playing.
        processAnnouncementQueue();
    });
}


async function speakLocally(textToSpeak) {
    const safeText = String(textToSpeak || '').trim();
    if (!safeText) return;
    await announce(safeText, 'system', false, false);
}

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




// --- Row-Column Scanning Helper Functions ---
function getVisibleRowIndices() {
    const buttons = Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
    if (buttons.length === 0) return [];
    
    const rowSet = new Set();
    buttons.forEach(btn => {
        const row = parseInt(btn.dataset.row, 10);
        if (!isNaN(row)) rowSet.add(row);
    });
    
    return Array.from(rowSet).sort((a, b) => a - b);
}

function getButtonsInRow(rowIndex) {
    return Array.from(document.querySelectorAll(`#gridContainer button[data-row="${rowIndex}"]:not([style*="display: none"])`))
        .sort((a, b) => {
            const colA = parseInt(a.dataset.col, 10);
            const colB = parseInt(b.dataset.col, 10);
            return colA - colB;
        });
}

function getVisibleButtons() {
    return Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
}


// --- Auditory Scanning ---
function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) { console.log("Auditory scanning is off."); return; }
    if (scanMode === 'step') {
        startStepColumnScanning();
        return;
    }
    console.log("Starting auditory scanning...", `Pattern: ${currentScanPattern}`);
    
    // Check which scanning pattern to use
    if (currentScanPattern === 'row-column') {
        startRowPhaseScanning();
    } else {
        startColumnPhaseScanning();
    }
}

function startStepColumnScanning() {
    console.log("Starting STEP scanning (column mode)...");
    const buttons = getVisibleButtons();
    if (buttons.length === 0) {
        currentlyScannedButton = null;
        return;
    }

    currentRowScanMode = false;
    currentButtonIndex = -1;
    scanCycleCount = 0;
    isPausedFromScanLimit = false;
    advanceStepColumnScan();
}

function advanceStepColumnScan() {
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
        speakAndHighlight(currentlyScannedButton);
    }
}

function startRowPhaseScanning() {
    console.log("Starting ROW-PHASE scanning...");
    const rowIndices = getVisibleRowIndices();
    if (rowIndices.length === 0) { 
        console.log("No rows found for row-phase scanning."); 
        currentlyScannedButton = null;
        return;
    }
    
    currentRowScanMode = true;
    currentRow = -1;
    rowLoopCount = 0;
    isPausedFromScanLimit = false;

    const scanStep = async () => {
        // Remove previous highlight (if it was on a button from the previous row)
        if (currentlyScannedButton) { 
            currentlyScannedButton.classList.remove('scanning');
            // Also remove row highlights from all buttons
            document.querySelectorAll('#gridContainer button.scanning-row').forEach(btn => {
                btn.classList.remove('scanning-row');
            });
        }
        
        currentRow++;
        
        // Check if we've completed a full cycle through all rows
        if (currentRow >= rowIndices.length) {
            currentRow = 0;
            rowLoopCount++;
            
            // Check scan loop limit
            if (scanLoopLimit > 0 && rowLoopCount >= scanLoopLimit) {
                console.log(`Row scan loop limit reached (${scanLoopLimit} cycles). Pausing scanning.`);
                isPausedFromScanLimit = true;
                stopAuditoryScanning();
                
                try {
                    await announce("Scanning paused", "system", false, false, true);
                } catch (e) { 
                    console.error("Speech synthesis error:", e); 
                }
                
                // Highlight first button for restart capability
                const firstRowButtons = getButtonsInRow(rowIndices[0]);
                if (firstRowButtons.length > 0) {
                    currentlyScannedButton = firstRowButtons[0];
                    firstRowButtons.forEach(btn => btn.classList.add('scanning-row'));
                    currentRow = 0;
                }
                return;
            }
        }
        
        const rowIndex = rowIndices[currentRow];
        const buttonsInRow = getButtonsInRow(rowIndex);
        
        if (buttonsInRow.length > 0) {
            // Highlight all buttons in this row
            buttonsInRow.forEach(btn => btn.classList.add('scanning-row'));
            // Set currentlyScannedButton to the first button in the row (for switch handling)
            currentlyScannedButton = buttonsInRow[0];
            
            // Announce the row
            try {
                const rowNumber = currentRow + 1;
                await announce(`Row ${rowNumber}`, "system", false, false, true);
            } catch (e) { 
                console.error("Speech synthesis error:", e); 
            }
        } else {
            console.warn("No buttons found in row:", rowIndex);
        }
    };
    
    console.log(`Scan delay set to: ${defaultDelay}ms`);
    scanStep(); // Perform first scan immediately
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function startColumnPhaseScanning() {
    console.log("Starting COLUMN-PHASE scanning...");
    const buttons = getVisibleButtons();
    if (buttons.length === 0) { 
        console.log("No visible buttons found."); 
        currentlyScannedButton = null; 
        return; 
    }
    
    currentRowScanMode = false;
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
                console.log(`Column scan loop limit reached (${scanLoopLimit} cycles). Pausing scanning.`);
                isPausedFromScanLimit = true;
                stopAuditoryScanning();
                
                try {
                    await announce("Scanning paused", "system", false, false, true);
                } catch (e) { 
                    console.error("Speech synthesis error:", e); 
                }
                
                // Set focus on first button for restart capability
                if (buttons.length > 0) {
                    currentButtonIndex = 0;
                    buttons[0].focus();
                    currentlyScannedButton = buttons[0];
                    currentlyScannedButton.classList.add('scanning');
                }
                return;
            }
        }
        
        if (buttons[currentButtonIndex]) {
            currentlyScannedButton = buttons[currentButtonIndex];
            speakAndHighlight(currentlyScannedButton);
        } else { 
            console.warn("Button not found at index:", currentButtonIndex); 
            currentButtonIndex = -1; 
        }
    };
    
    console.log(`Scan delay set to: ${defaultDelay}ms`);
    scanStep(); // Perform first scan immediately
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function startColumnPhaseForRow(rowIndex) {
    console.log(`Starting COLUMN-PHASE for row ${rowIndex}...`);
    // Stop any existing scanning interval (row phase) before switching modes
    stopAuditoryScanning();
    const buttonsInRow = getButtonsInRow(rowIndex);
    
    if (buttonsInRow.length === 0) {
        console.log("No buttons found in row, resuming row scanning.");
        startRowPhaseScanning();
        return;
    }
    
    // Clear row highlighting
    document.querySelectorAll('#gridContainer button.scanning-row').forEach(btn => {
        btn.classList.remove('scanning-row');
    });
    
    currentRowScanMode = false;
    currentRow = rowIndex;
    currentButtonInRow = -1;
    columnLoopCount = 0;
    isPausedFromScanLimit = false;

    const scanStep = async () => {
        if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); }
        currentButtonInRow++;
        
        // Check if we've completed a full cycle through buttons in this row
        if (currentButtonInRow >= buttonsInRow.length) {
            currentButtonInRow = 0;
            columnLoopCount++;
            
            // Check scan loop limit
            if (scanLoopLimit > 0 && columnLoopCount >= scanLoopLimit) {
                console.log(`Column scan loop limit reached (${scanLoopLimit} cycles). Pausing scanning.`);
                isPausedFromScanLimit = true;
                stopAuditoryScanning();
                
                try {
                    await announce("Scanning paused", "system", false, false, true);
                } catch (e) { 
                    console.error("Speech synthesis error:", e); 
                }
                
                // Highlight first button in row for restart
                if (buttonsInRow.length > 0) {
                    currentButtonInRow = 0;
                    buttonsInRow[0].focus();
                    currentlyScannedButton = buttonsInRow[0];
                    currentlyScannedButton.classList.add('scanning');
                }
                return;
            }
        }
        
        if (buttonsInRow[currentButtonInRow]) {
            currentlyScannedButton = buttonsInRow[currentButtonInRow];
            speakAndHighlight(currentlyScannedButton);
        } else {
            console.warn("Button not found at index:", currentButtonInRow);
            currentButtonInRow = -1;
        }
    };
    
    console.log(`Scan delay set to: ${defaultDelay}ms`);
    scanStep(); // Perform first scan immediately
    scanningInterval = setInterval(scanStep, defaultDelay);
}

async function speakAndHighlight(button) {
    document.querySelectorAll('#gridContainer button.scanning').forEach(btn => { btn.classList.remove('scanning'); });
    button.classList.add('scanning');
    try {
        const textToSpeak = button.textContent;
        // Use backend TTS instead of browser speech synthesis
        await announce(textToSpeak, "system", false, false, true);
    } catch (e) { console.error("Speech synthesis error:", e); }
}

function stopAuditoryScanning() {
    console.log("Stopping auditory scanning.");
    clearInterval(scanningInterval); scanningInterval = null;
    if (currentlyScannedButton) { currentlyScannedButton.classList.remove('scanning'); currentlyScannedButton = null; }
    document.querySelectorAll('#gridContainer button.scanning-row').forEach(btn => {
        btn.classList.remove('scanning-row');
    });
    currentButtonIndex = -1;
    // Note: No need to cancel speech here as backend TTS handles its own queue
}

// Function to resume scanning from first option with cycle reset
async function resumeAuditoryScanning() {
    if (!isPausedFromScanLimit) {
        console.log("Scanning was not paused from scan limit, starting normally");
        startAuditoryScanning();
        return;
    }
    
    console.log("Resuming scanning with cycle reset...");
    isPausedFromScanLimit = false;
    
    // Reset appropriate counters based on current mode
    if (currentRowScanMode) {
        rowLoopCount = 0;
        currentRow = -1;
    } else {
        scanCycleCount = 0;
        currentButtonIndex = -1;
    }
    
    // Announce that scanning is resumed using the proper audio system
    try {
        await announce("Scanning resumed", "system", false, false, true);
    } catch (e) { 
        console.error("Speech synthesis error:", e); 
    }
    
    // Start scanning after brief delay to allow announcement
    setTimeout(() => {
        startAuditoryScanning();
    }, 1500);
}

async function createHomeButton() {
    const homeButton = document.createElement('button');
    homeButton.className = '';

    const homeImageUrl = await getSymbolImageForText('Home', ['home', 'house', 'main', 'start']);
    if (homeImageUrl) {
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
        imageElement.src = homeImageUrl;
        imageElement.alt = 'Home';
        imageElement.style.width = '100%';
        imageElement.style.height = '100%';
        imageElement.style.objectFit = 'cover';
        imageElement.onerror = () => {
            homeButton.textContent = 'Home';
        };

        const textFooter = document.createElement('div');
        textFooter.style.minHeight = '14px';
        textFooter.style.width = '100%';
        textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
        textFooter.style.color = 'white';
        textFooter.style.display = 'flex';
        textFooter.style.alignItems = 'center';
        textFooter.style.justifyContent = 'center';
        textFooter.style.padding = '0 3px';
        textFooter.style.boxSizing = 'border-box';
        textFooter.style.position = 'absolute';
        textFooter.style.bottom = '0';
        textFooter.style.left = '0';
        textFooter.style.right = '0';

        const textSpan = document.createElement('span');
        textSpan.textContent = 'Home';
        textSpan.style.fontSize = '0.45em';
        textSpan.style.fontWeight = 'bold';
        textSpan.style.textAlign = 'center';
        textSpan.style.lineHeight = '0.95';

        imageContainer.appendChild(imageElement);
        textFooter.appendChild(textSpan);
        buttonContent.appendChild(imageContainer);
        buttonContent.appendChild(textFooter);
        homeButton.appendChild(buttonContent);
    } else {
        homeButton.textContent = 'Home';
    }

    homeButton.addEventListener('click', () => {
        activeOriginatingButtonText = null;
        activeLLMPromptForContext = null;
        resetFollowUpConversation();
        localStorage.removeItem('llm_currentQueryType');
        localStorage.removeItem('llm_currentQuestion');
        localStorage.removeItem('llm_currentOptions');
        window.location.href = 'gridpage.html?page=home';
    });

    return homeButton;
}

// --- LLM Button Generation ---
async function generateLlmButtons(options) {
    document.getElementById('loading-indicator').style.display = 'none';
    isLLMProcessing = false; // Reset processing flag since LLM results are ready
    options = Array.isArray(options) ? options : [];
    stopAuditoryScanning();
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) { console.error("gridContainer not found!"); return; }
    gridContainer.innerHTML = '';
    
    // Update grid layout to use current gridColumns setting
    updateGridLayout();
    
    currentOptions = options;
    localStorage.setItem('llm_currentOptions', JSON.stringify(options));
    let isAnnouncing = false;
    console.log("Generating buttons for options:", options);

     // --- Define Tailwind classes ---
     const baseButtonClasses = [ 'grid-button-base', 'w-full', 'h-auto', 'text-white', 'font-semibold', 'text-sm', 'sm:text-base', 'p-3', 'rounded-lg', 'shadow-md', 'border-2', 'transition', 'duration-150', 'ease-in-out', 'transform', 'hover:-translate-y-0.5', 'flex', 'items-center', 'justify-center', 'text-center', 'cursor-pointer', 'focus:outline-none', 'focus:ring-2', 'focus:ring-offset-2', 'mb-3' ];
     const llmButtonColors = [ 'bg-teal-600', 'border-teal-800', 'hover:bg-teal-700', 'hover:border-teal-900', 'focus:ring-teal-500' ];
     const specialButtonColors = [ 'bg-gray-600', 'border-gray-800', 'hover:bg-gray-700', 'hover:border-gray-900', 'focus:ring-gray-500' ];
     const askAgainButtonColors = [ 'bg-yellow-500', 'border-yellow-700', 'hover:bg-yellow-600', 'hover:border-yellow-800', 'text-black', 'focus:ring-yellow-400' ];
     const goBackButtonColors = [ 'bg-gray-200', 'border-gray-400', 'hover:bg-gray-300', 'hover:border-gray-500', 'text-black', 'focus:ring-gray-300' ];

    // Build buttons immediately (text first), then hydrate images asynchronously.
    const validButtons = [];
    options.forEach((optionData) => {
        if (!optionData || typeof optionData.summary !== 'string' || typeof optionData.option !== 'string') {
            console.warn("Skipping invalid option data:", optionData);
            return;
        }

        const button = document.createElement('button');
        button.textContent = optionData.summary;
        button.dataset.option = optionData.option;
        button.dataset.speechPhrase = optionData.option;
        button.className = '';
        button.style.padding = '0';
        button.style.margin = '0';
        button.style.border = 'none';
        button.style.position = 'relative';
        button.style.overflow = 'hidden';

        validButtons.push({ button, optionData });
    });

    console.log(`🧩 generateLlmButtons: Prepared ${validButtons.length} immediate buttons`);
    const fragment = document.createDocumentFragment();

    if (querytype === 'jokes') {
        const homeButton = await createHomeButton();
        fragment.appendChild(homeButton);
    }

    if (querytype !== 'jokes') {
        const homeButton = await createHomeButton();
        gridContainer.appendChild(homeButton);
    }
    
    // Add event listeners and append buttons
    validButtons.forEach(({ button, optionData }) => {
        // Pass the full optionData object, which now includes isLLMGenerated and originalPrompt
        button.addEventListener('click', debounce(async () => {
            if (isAnnouncing) { console.log("Announcement in progress..."); return; }
            isAnnouncing = true;
            stopAuditoryScanning(); // Stop scanning when an option is chosen
            console.log("LLM Button Click. Announcing:", optionData.option); // Log the full option text

            // --- Log LLM Button Click for Audit ---
            const clickTimestamp = new Date().toISOString();
            const pageInfo = getCurrentPageInfo();
            const logData = {
                timestamp: clickTimestamp,
                page_name: pageInfo.name,
                page_context_prompt: optionData.originalPrompt, // From tagged optionData
                button_text: optionData.option,
                button_summary: optionData.summary,
                is_llm_generated: optionData.isLLMGenerated, // Should be true
                originating_button_text: optionData.originatingButtonText // NEW: Add originating button text
            };
            console.log("Logging LLM button click data:", logData);
            try {
                console.log('🔄 About to send audit log...');
                const auditResponse = await authenticatedFetch('/api/audit/log-button-click', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(logData)
                });
                console.log('📊 Audit response received:', auditResponse.ok);
                if (!auditResponse.ok) console.error("Failed to log LLM button click:", auditResponse.status, await auditResponse.text());
                else console.log("LLM button click logged successfully:", logData);
            } catch (auditError) {
                console.error("Error sending LLM button click log:", auditError);
            }
            console.log('✅ Audit logging complete');
            // --- End Audit Logging ---
            
            // --- Record Chat History for LLM Selection ---
            const isWakeWordQuestion = currentQuestion && currentQuestion.trim();
            console.log('🎯 GRIDPAGE Recording LLM selection (in LLM click handler):', optionData.option);
            console.log('🎯 GRIDPAGE Wake word question context:', { currentQuestion, isWakeWordQuestion });
            localStorage.setItem('debug_wake_word', `Question: "${currentQuestion}", Option: "${optionData.option}" at ${new Date().toISOString()}`);
            
            console.log('💬 Recording chat history (non-blocking)...');
            // Fire and forget - don't wait for chat history recording
            const questionToRecord = isWakeWordQuestion ? currentQuestion : "";
            recordChatHistory(questionToRecord, optionData.option).then(() => {
                localStorage.setItem('debug_wake_success', `Recorded Q:"${questionToRecord}" A:"${optionData.option}" at ${new Date().toISOString()}`);
                console.log('✅ GRIDPAGE LLM chat history recorded successfully');
            }).catch(chatError => {
                localStorage.setItem('debug_wake_error', `Error: ${chatError.message} at ${new Date().toISOString()}`);
                console.error('❌ Failed to record LLM chat history:', chatError);
            });
            // --- End Chat History Recording ---
            
            console.log('🔊 About to announce option...');
            try {
                // Announce the selected option (using the full option text for clarity)
                await announce(optionData.option, "system", true); // Use optionData.option directly
                console.log("✅ Announcement finished for:", button.dataset.option);

                if (querytype === 'jokes') {
                    window.location.href = 'gridpage.html?page=home';
                } else {
                    addFollowUpSelection(optionData.option);

                    const excludedOptionsText = currentOptions
                        .map(opt => opt.option)
                        .filter(text => typeof text === 'string' && text.trim() !== '')
                        .join('; ');

                    const followUpPrompt = buildFollowUpPrompt(excludedOptionsText);
                    activeLLMPromptForContext = getConversationContextText();
                    querytype = 'question';

                    document.getElementById('loading-indicator').style.display = 'flex';
                    const followUpOptions = await getLLMResponse(followUpPrompt);
                    document.getElementById('loading-indicator').style.display = 'none';
                    
                    console.log(`📥 Received ${Array.isArray(followUpOptions) ? followUpOptions.length : 0} options from LLM`);
                    
                    // FILTER 1: Remove partner-interrogative patterns
                    const filteredForUserPerspective = Array.isArray(followUpOptions)
                        ? followUpOptions.filter(optionObj => {
                            const optionText = typeof optionObj === 'object' ? optionObj.option : optionObj;
                            const isInterrogative = isPartnerInterrogativePattern(optionText);
                            if (isInterrogative) {
                                console.warn('🚫 Filtered out partner-interrogative pattern:', optionText);
                            }
                            return !isInterrogative;
                        })
                        : followUpOptions;
                    
                    console.log(`✅ After interrogative filter: ${Array.isArray(filteredForUserPerspective) ? filteredForUserPerspective.length : 0} options remain`);
                    
                    const prioritizedFollowUpOptions = prioritizeContextualOptions(
                        filteredForUserPerspective,
                        getConversationContextText(),
                        LLMOptions
                    );
                    const additiveFollowUpOptions = enforceAdditiveFollowUpOptions(prioritizedFollowUpOptions, LLMOptions);
                    const partnerQuestionPrioritizedOptions = prioritizePartnerEngagementQuestions(additiveFollowUpOptions, LLMOptions, 4);

                    if (Array.isArray(partnerQuestionPrioritizedOptions) && partnerQuestionPrioritizedOptions.length > 0) {
                        await generateLlmButtons(partnerQuestionPrioritizedOptions);
                    } else {
                        console.warn('No follow-up options returned after selection.');
                        announce("Sorry, I couldn't find follow-up options right now.", "system", false);
                        startAuditoryScanning();
                    }
                }

            } catch (error) {
                 console.error("❌ Error during announcement or reload:", error);
                 document.getElementById('loading-indicator').style.display = 'none';
                 // Optionally restart scanning here if announce fails
                 startAuditoryScanning();
            } finally {
                isAnnouncing = false; // Reset flag  
            }
        }, clickDebounceDelay)); // Apply debounce
        fragment.appendChild(button);
    });

    // Hydrate images after buttons are already visible to avoid blank states.
    validButtons.forEach(({ button, optionData }, idx) => {
        (async () => {
            try {
                await new Promise(resolve => setTimeout(resolve, idx * 200));
                const optimizedSearchTerm = getOptimizedSearchTerm(optionData.summary, optionData.keywords);
                console.log(`🔍 Image search optimization: "${optionData.summary}" → "${optimizedSearchTerm}"`);

                const symbolImageUrl = await getSymbolImageForText(optimizedSearchTerm, optionData.keywords);
                if (!symbolImageUrl || !button.isConnected) {
                    if (!symbolImageUrl) {
                        console.warn(`🚨 LLM Option: No image found for "${optimizedSearchTerm}" (original: "${optionData.summary}")`);
                    }
                    return;
                }

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
                imageElement.alt = optionData.summary;
                imageElement.style.width = '100%';
                imageElement.style.height = '100%';
                imageElement.style.objectFit = 'cover';
                imageElement.onerror = () => {
                    console.warn(`Failed to load image for "${optionData.summary}" - keeping text-only display`);
                };

                const textFooter = document.createElement('div');
                textFooter.style.minHeight = '14px';
                textFooter.style.width = '100%';
                textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
                textFooter.style.color = 'white';
                textFooter.style.display = 'flex';
                textFooter.style.alignItems = 'center';
                textFooter.style.justifyContent = 'center';
                textFooter.style.padding = '0 3px';
                textFooter.style.margin = '0';
                textFooter.style.borderRadius = '0';
                textFooter.style.boxSizing = 'border-box';
                textFooter.style.position = 'absolute';
                textFooter.style.bottom = '0';
                textFooter.style.left = '0';
                textFooter.style.right = '0';

                const textSpan = document.createElement('span');
                textSpan.textContent = optionData.summary;
                textSpan.style.fontSize = '0.45em';
                textSpan.style.fontWeight = 'bold';
                textSpan.style.textAlign = 'center';
                textSpan.style.lineHeight = '0.95';
                textSpan.style.wordWrap = 'break-word';
                textSpan.style.hyphens = 'auto';
                textSpan.style.overflow = 'hidden';
                textSpan.style.display = '-webkit-box';
                textSpan.style.webkitLineClamp = '1';
                textSpan.style.webkitBoxOrient = 'vertical';

                imageContainer.appendChild(imageElement);
                textFooter.appendChild(textSpan);
                buttonContent.appendChild(imageContainer);
                buttonContent.appendChild(textFooter);

                button.innerHTML = '';
                button.appendChild(buttonContent);
            } catch (error) {
                console.warn(`LLM button image hydration failed for "${optionData.summary}":`, error);
            }
        })();
    });
    gridContainer.appendChild(fragment);

    // --- Generate Special Buttons ---
    // (Ensure these also have the base class and appropriate color classes)
    const somethingElseButton = document.createElement('button');
    // Remove Tailwind classes to allow CSS speech bubble styling to take precedence
    somethingElseButton.className = '';
    
    // Apply image matching to Something Else button
    const somethingElseImageUrl = await getSymbolImageForText('Something Else', ['refresh', 'more', 'other']);
    if (somethingElseImageUrl) {
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
        imageElement.src = somethingElseImageUrl;
        imageElement.alt = 'Something Else';
        imageElement.style.width = '100%';
        imageElement.style.height = '100%';
        imageElement.style.objectFit = 'cover';
        imageElement.onerror = () => {
            somethingElseButton.textContent = 'Something Else';
        };
        
        const textFooter = document.createElement('div');
        textFooter.style.minHeight = '14px';
        textFooter.style.width = '100%';
        textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
        textFooter.style.color = 'white';
        textFooter.style.display = 'flex';
        textFooter.style.alignItems = 'center';
        textFooter.style.justifyContent = 'center';
        textFooter.style.padding = '0 3px';
        textFooter.style.boxSizing = 'border-box';
        textFooter.style.position = 'absolute';
        textFooter.style.bottom = '0';
        textFooter.style.left = '0';
        textFooter.style.right = '0';
        
        const textSpan = document.createElement('span');
        textSpan.textContent = 'Something Else';
        textSpan.style.fontSize = '0.45em';
        textSpan.style.fontWeight = 'bold';
        textSpan.style.textAlign = 'center';
        textSpan.style.lineHeight = '0.95';
        
        imageContainer.appendChild(imageElement);
        textFooter.appendChild(textSpan);
        buttonContent.appendChild(imageContainer);
        buttonContent.appendChild(textFooter);
        somethingElseButton.appendChild(buttonContent);
    } else {
        somethingElseButton.textContent = 'Something Else';
    }
    somethingElseButton.addEventListener('click', async () => {
        stopAuditoryScanning(); // Stop scanning before fetching new options
        console.log("Something Else button clicked. Query Type:", querytype, "Current Question context:", currentQuestion);

       try { // Wrap main logic
            // --- Logic based on query type ---
            if (querytype === "currentevents") {
                // For "Something Else" in current events, the activeOriginatingButtonText
                // should still be the category button that initiated it.
                console.log("Getting next set of current events for type:", eventtype);
                await getCurrentEvents(eventtype); // This calls generateLlmButtons, which starts scanning
            } else if (querytype === "jokes") {
                document.getElementById('loading-indicator').style.display = 'flex';
                const jokeOptions = await fetchJokeOptions(LLMOptions, currentQuestion);
                if (jokeOptions.length > 0) {
                    await generateLlmButtons(jokeOptions);
                } else {
                    console.warn("No jokes returned for refresh.");
                    announce("Sorry, I couldn't find any other jokes.", "system", false);
                }
            } else if (querytype === "question" || querytype === "options") {
                document.getElementById('loading-indicator').style.display = 'flex';
                try {
                    const excludedOptionsText = currentOptions
                        .map(opt => opt.option)
                        .filter(text => typeof text === 'string' && text.trim() !== '')
                        .join("; ");
                    console.log("Excluding options:", excludedOptionsText);

                    activeLLMPromptForContext = getConversationContextText() || currentQuestion;
                    const prompt = buildFollowUpPrompt(excludedOptionsText);
                    console.log("Sending prompt for 'Something Else' options:", prompt);

                    const response = await getLLMResponse(prompt); // Expects an array
                    
                    console.log(`📥 Received ${Array.isArray(response) ? response.length : 0} options from LLM (Something Else)`);
                    
                    // FILTER 1: Remove partner-interrogative patterns
                    const filteredResponse = Array.isArray(response)
                        ? response.filter(optionObj => {
                            const optionText = typeof optionObj === 'object' ? optionObj.option : optionObj;
                            const isInterrogative = isPartnerInterrogativePattern(optionText);
                            if (isInterrogative) {
                                console.warn('🚫 Filtered out partner-interrogative pattern:', optionText);
                            }
                            return !isInterrogative;
                        })
                        : response;
                    
                    console.log(`✅ After interrogative filter: ${Array.isArray(filteredResponse) ? filteredResponse.length : 0} options remain (Something Else)`);
                    
                    const prioritizedResponse = prioritizeContextualOptions(
                        filteredResponse,
                        getConversationContextText() || currentQuestion,
                        LLMOptions
                    );
                    const additiveResponse = enforceAdditiveFollowUpOptions(prioritizedResponse, LLMOptions);
                    const partnerQuestionPrioritizedResponse = prioritizePartnerEngagementQuestions(additiveResponse, LLMOptions, 4);

                    if (Array.isArray(partnerQuestionPrioritizedResponse)) {
                        if (partnerQuestionPrioritizedResponse.length > 0) {
                            await generateLlmButtons(partnerQuestionPrioritizedResponse); // This will restart scanning
                        } else {
                            console.warn("LLM did not return any new options after exclusion (array response).");
                            announce("Sorry, I couldn't find any other options for that.", "system", false);
                        }
                    } else if (typeof prioritizedResponse === 'string' && prioritizedResponse.trim() !== '') { // Fallback for older string response
                        console.warn("Received string response from getLLMResponse for 'Something Else', expected array. Processing as string.");
                        const newOptions = prioritizedResponse.split("\n").map(option => option.replace(/^\s*\d+[\.\)]?\s*|\s*\*+\s*|["']/g, '').trim()).filter(option => option !== "");
                        if (newOptions.length > 0) {
                            const newOptionsObjects = newOptions.map(optText => ({ summary: optText, option: optText, keywords: [] }));
                            await generateLlmButtons(newOptionsObjects); // This will restart scanning
                        } else {
                            console.warn("LLM did not return any new options after exclusion (string response).");
                            announce("Sorry, I couldn't find any other options for that.", "system", false);
                        }
                    } else {
                        console.error("Unexpected or empty response type from getLLMResponse for 'Something Else':", prioritizedResponse);
                        announce("Sorry, I received an unexpected response for more options.", "system", false);
                    }
                    } catch (error) {
                    console.error('Error getting new LLM options for "Something Else":', error);
                    announce("Sorry, an error occurred while getting more options.", "system", false);
                } finally {
                    document.getElementById('loading-indicator').style.display = 'none';
                }
                } else {
                console.warn("Something Else clicked with unknown querytype:", querytype);
                announce("Sorry, I'm not sure what to do for 'Something Else' here.", "system", false);
            }
            } finally {
            // This 'finally' ensures that scanning is attempted to be restarted
            // if it wasn't already started by generateLlmButtons (e.g., due to error or no new options).
            if (!scanningInterval) { // Check if scanning is not already active
                console.log("Attempting to restart scanning in 'Something Else' finally block.");
                // Restore activeLLMPromptForContext if needed for scanning, though it's usually for the next LLM call
                // activeLLMPromptForContext = currentQuestion; // Or a specific "something else" context
                startAuditoryScanning();
            }
        }
    });


    
    gridContainer.appendChild(somethingElseButton);

    // Add Free Style button
    const freeStyleButton = document.createElement('button');
    freeStyleButton.id = 'freeStyleButton';
    // Remove Tailwind classes to allow CSS speech bubble styling to take precedence
    freeStyleButton.className = '';
    
    // Apply image matching to Free Style button
    const freeStyleImageUrl = await getSymbolImageForText('Free Style', ['freestyle', 'spell', 'keyboard', 'type']);
    if (freeStyleImageUrl) {
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
        imageElement.src = freeStyleImageUrl;
        imageElement.alt = 'Free Style';
        imageElement.style.width = '100%';
        imageElement.style.height = '100%';
        imageElement.style.objectFit = 'cover';
        imageElement.onerror = () => {
            freeStyleButton.textContent = 'Free Style';
        };
        
        const textFooter = document.createElement('div');
        textFooter.style.minHeight = '14px';
        textFooter.style.width = '100%';
        textFooter.style.backgroundColor = 'rgba(0, 0, 0, 0.9)';
        textFooter.style.color = 'white';
        textFooter.style.display = 'flex';
        textFooter.style.alignItems = 'center';
        textFooter.style.justifyContent = 'center';
        textFooter.style.padding = '0 3px';
        textFooter.style.boxSizing = 'border-box';
        textFooter.style.position = 'absolute';
        textFooter.style.bottom = '0';
        textFooter.style.left = '0';
        textFooter.style.right = '0';
        
        const textSpan = document.createElement('span');
        textSpan.textContent = 'Free Style';
        textSpan.style.fontSize = '0.45em';
        textSpan.style.fontWeight = 'bold';
        textSpan.style.textAlign = 'center';
        textSpan.style.lineHeight = '0.95';
        
        imageContainer.appendChild(imageElement);
        textFooter.appendChild(textSpan);
        buttonContent.appendChild(imageContainer);
        buttonContent.appendChild(textFooter);
        freeStyleButton.appendChild(buttonContent);
    } else {
        freeStyleButton.textContent = 'Free Style';
    }
    freeStyleButton.addEventListener('click', () => {
        stopAuditoryScanning();
        console.log('DEBUG: LLM-generated Free Style clicked - preserving context');
        console.log('DEBUG: activeLLMPromptForContext:', activeLLMPromptForContext);
        console.log('DEBUG: activeOriginatingButtonText:', activeOriginatingButtonText);
        
        // Build URL parameters for context-aware freestyle
        const params = new URLSearchParams();
        
        // Pass current page name as source context
        const pageInfo = getCurrentPageInfo();
        if (pageInfo?.name && pageInfo.name !== 'UnknownPage') {
            params.set('source_page', pageInfo.name);
        }
        
        // Pass LLM context if available (indicates LLM-generated page)
        if (activeLLMPromptForContext) {
            params.set('context', activeLLMPromptForContext);
            params.set('is_llm_generated', 'true');
        }

        if (isComposeSessionActive()) {
            params.set('compose', '1');
        }
        
        // Pass originating button text if available
        if (activeOriginatingButtonText) {
            params.set('originating_button', activeOriginatingButtonText);
        }
        
        console.log('DEBUG: LLM-generated freestyle navigation params:', params.toString());
        const queryString = params.toString();
        // Navigate to freestyle.html with context
        window.location.href = queryString ? `freestyle.html?${queryString}` : 'freestyle.html';
    });
    gridContainer.appendChild(freeStyleButton);

    if (querytype === "question") {
        const askAgainButton = document.createElement('button');
        askAgainButton.textContent = 'Please ask me again';
        askAgainButton.id = 'askAgainButton';
        // Remove Tailwind classes to allow CSS speech bubble styling to take precedence
        askAgainButton.className = '';
        askAgainButton.addEventListener('click', () => {
            stopAuditoryScanning();
            activeOriginatingButtonText = null; // Reset, as a new question will be asked
            activeLLMPromptForContext = null;
            resetFollowUpConversation();
            announce('Okay, please ask your question again after the tone.', "system", false)
                .then(() => { activeLLMPromptForContext = "User chose to ask question again."; })
                .then(() => {
                    // Reset state and start question recognition again
                    listeningForQuestion = false; // Ensure state allows starting new recognition
                    // No need to stop recognition instance here, setupQuestionRecognition creates a new one
                    setTimeout(() => {
                        setupQuestionRecognition(); // Start listening for the question
                    }, 100); // Short delay after announcement
                })
                .catch(err => {
                    console.error("Error announcing 'ask again':", err);
                    // If announce fails, revert to keyword spotting and scan existing buttons
                    setupSpeechRecognition();
                    activeLLMPromptForContext = null; // Clear context
                    if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                        startAuditoryScanning();
                    }
                });
        });
        gridContainer.appendChild(askAgainButton);
    }


    // --- Start Auditory Scanning ---
    if (gridContainer.childElementCount > 0) {
         console.log("Starting auditory scanning for generated LLM/special buttons.");
         setupSpeechRecognition();
            startOrWaitForScanning({ allowPrompt: false, source: 'generateLlmButtons' });
    } else { console.log("No buttons generated, not starting scanning."); }
}

// --- Input Handling --- ADDED/VERIFIED ---

/**
 * Sets up the keyboard listener for the Spacebar.
 */
function setupKeyboardListener() {
    document.addEventListener('keydown', (event) => {
        if (event.repeat) return; // Ignore key-repeat events (held key fires multiple keydown)
        const isSpaceKey = event.code === 'Space' || event.key === ' ' || event.key === 'Spacebar';

        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            interruptScanningAnnouncementPlayback();

            if (window.waitingForInitialSwitch) {
                console.log('Initial switch detected (tab) - starting scanning on gridpage');
                window.waitingForInitialSwitch = false;
                markScanningStartedFromSwitch();
                startAuditoryScanning();
                return;
            }

            if (shouldSuppressSwitchActivation()) return;

            if (!isLLMProcessing && !listeningForQuestion) {
                if (!currentlyScannedButton) {
                    startAuditoryScanning();
                } else {
                    advanceStepColumnScan();
                }
            }
            return;
        }

        if (isSpaceKey) {
            event.preventDefault();
            handleSpacebarPress();
        }
    });
    console.log("Keyboard listener (Spacebar) set up.");
}

/**
 * Sets up listeners for gamepad connection/disconnection and starts polling.
 */
function setupGamepadListeners() {
    window.addEventListener("gamepadconnected", (event) => {
        console.log("Gamepad connected:", event.gamepad.index, event.gamepad.id);
        if (gamepadIndex === null) { gamepadIndex = event.gamepad.index; startGamepadPolling(); }
    });
    window.addEventListener("gamepaddisconnected", (event) => {
        console.log("Gamepad disconnected:", event.gamepad.index, event.gamepad.id);
        if (gamepadIndex === event.gamepad.index) { gamepadIndex = null; stopGamepadPolling(); }
    });
    console.log("Gamepad connection listeners set up.");
     const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
     for (let i = 0; i < gamepads.length; i++) {
         if (gamepads[i]) {
             console.log("Gamepad already connected at index:", i);
             if (gamepadIndex === null) { gamepadIndex = i; startGamepadPolling(); }
             break;
         }
     }
}

/**
 * Starts the gamepad polling loop using requestAnimationFrame.
 */
function startGamepadPolling() {
    if (gamepadPollInterval !== null) return;
    console.log("Starting gamepad polling for index:", gamepadIndex);
    let lastButtonState = false;

    function pollGamepads() {
        if (gamepadIndex === null) { stopGamepadPolling(); return; }
        const gp = navigator.getGamepads()[gamepadIndex];
        if (!gp) { gamepadPollInterval = requestAnimationFrame(pollGamepads); return; } // Keep polling if gp not ready

        const currentButtonState = gp.buttons[0] && gp.buttons[0].pressed;
        if (currentButtonState && !lastButtonState) {
             const now = Date.now();
             if (now - lastGamepadInputTime > 300) { // Rate limit
                // Check if we're waiting for initial switch press
                if (window.waitingForInitialSwitch) {
                    console.log('Initial switch detected (gamepad) - starting scanning on gridpage');
                    window.waitingForInitialSwitch = false;
                    markScanningStartedFromSwitch();
                    startAuditoryScanning();
                    lastGamepadInputTime = now;
                    lastButtonState = currentButtonState;
                    gamepadPollInterval = requestAnimationFrame(pollGamepads);
                    return;
                }

                if (shouldSuppressSwitchActivation()) {
                    lastButtonState = currentButtonState;
                    gamepadPollInterval = requestAnimationFrame(pollGamepads);
                    return;
                }
                
                // Normal scanning behavior
                if (!isLLMProcessing && !listeningForQuestion && currentlyScannedButton) {
                    const buttonToActivate = currentlyScannedButton; // Capture the button reference
                    console.log("Gamepad button 0 pressed, activating button:", buttonToActivate.textContent);
                    buttonToActivate.click();
                    buttonToActivate.classList.add('active');
                    // Use the captured reference in the timeout
                    setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
                    lastGamepadInputTime = now;
                } else { console.log("Gamepad press ignored (state)."); }
             } else { console.log("Gamepad press ignored (rate limit)."); }
        }
        lastButtonState = currentButtonState;
        gamepadPollInterval = requestAnimationFrame(pollGamepads); // Continue polling
    }
    gamepadPollInterval = requestAnimationFrame(pollGamepads); // Start the loop
}

/**
 * Stops the gamepad polling loop.
 */
function stopGamepadPolling() {
    if (gamepadPollInterval !== null) {
        cancelAnimationFrame(gamepadPollInterval);
        gamepadPollInterval = null;
        console.log("Stopped gamepad polling.");
    }
}

// --- Avatar Manager Modal ---
async function showAvatarManager() {
    // Create avatar manager modal
    const modal = document.createElement('div');
    modal.id = 'avatar-manager-modal';
    modal.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(0, 0, 0, 0.8);
        display: flex;
        justify-content: center;
        align-items: center;
        z-index: 10000;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    `;

    const container = document.createElement('div');
    container.style.cssText = `
        background-color: white;
        border-radius: 16px;
        padding: 1.5rem;
        max-width: 95vw;
        max-height: 95vh;
        overflow-y: auto;
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.3);
        width: 90vw;
    `;

    container.innerHTML = `
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem; border-bottom: 2px solid #e2e8f0; padding-bottom: 1rem;">
            <h2 style="font-size: 1.8rem; font-weight: 600; color: #2d3748; margin: 0;">
                🧑‍💻 Avatar & Mood Settings
            </h2>
            <button id="close-avatar-manager" style="background: #e2e8f0; color: #2d3748; border: none; padding: 0.5rem 1rem; border-radius: 8px; cursor: pointer; font-size: 1rem; font-weight: 500;">
                ✕ Close
            </button>
        </div>
        
        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 2rem; height: calc(90vh - 150px);">
            <!-- Left Panel: Preview and Actions -->
            <div style="display: flex; flex-direction: column; gap: 1rem;">
                <div style="background: #f7fafc; padding: 1.5rem; border-radius: 12px; border: 2px solid #e2e8f0; text-align: center;">
                    <h3 style="margin-top: 0; color: #2d3748; font-size: 1.2rem;">Avatar Preview</h3>
                    <div id="current-avatar-preview" style="display: flex; justify-content: center; margin: 1rem 0;">
                        <div style="color: #4a5568;">Loading...</div>
                    </div>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; margin-top: 1rem;">
                        <button id="random-avatar" style="background: #805ad5; color: white; border: none; padding: 0.75rem; border-radius: 8px; cursor: pointer; font-size: 0.9rem; font-weight: 500;">
                            🎲 Random
                        </button>
                        <button id="reset-avatar" style="background: #e53e3e; color: white; border: none; padding: 0.75rem; border-radius: 8px; cursor: pointer; font-size: 0.9rem; font-weight: 500;">
                            � Reset
                        </button>
                    </div>
                </div>
                
                <div style="display: flex; flex-direction: column; gap: 0.5rem;">
                    <button id="save-current-avatar" style="background: #38a169; color: white; border: none; padding: 0.75rem 1rem; border-radius: 8px; cursor: pointer; font-size: 1rem; font-weight: 500;">
                        � Save Avatar
                    </button>
                </div>
            </div>
            
            <!-- Right Panel: Avatar Customization -->
            <div style="overflow-y: auto; padding-right: 0.5rem;">
                <div id="avatar-customization-container">
                    <!-- Avatar customization controls will be loaded here -->
                </div>
            </div>
        </div>
    `;

    modal.appendChild(container);
    document.body.appendChild(modal);

    // Initialize avatar selector and set up customization
    const avatarSelector = window.avatarSelector || new AvatarSelector();
    window.modalAvatarSelector = avatarSelector;

    // Load user's saved avatar configuration first
    await avatarSelector.loadAvatarConfig();

    // Set up the full avatar customization interface after loading config
    setupAvatarCustomization();

    // Random avatar button
    document.getElementById('random-avatar').addEventListener('click', () => {
        // Generate random config
        const options = {
            topType: ['NoHair', 'ShortHairShortFlat', 'ShortHairShortRound', 'ShortHairSides', 'LongHairBob', 'LongHairStraight', 'LongHairCurly', 'ShortHairTheCaesar', 'LongHairBun'],
            accessoriesType: ['Blank', 'Sunglasses', 'Prescription01', 'Round', 'Wayfarers'],
            hairColor: ['Black', 'BrownDark', 'Brown', 'Blonde', 'Red', 'Auburn'],
            facialHairType: ['Blank', 'BeardLight', 'BeardMedium', 'MoustacheFancy'],
            facialHairColor: ['Black', 'BrownDark', 'Brown', 'Auburn', 'Blonde', 'Red'],
            clotheType: ['BlazerShirt', 'Hoodie', 'ShirtCrewNeck', 'GraphicShirt', 'CollarSweater', 'BlazerSweater'],
            clotheColor: ['Black', 'Blue01', 'Blue02', 'Blue03', 'Gray01', 'Gray02', 'Red', 'White'],
            skinColor: ['Light', 'Tanned', 'Brown', 'DarkBrown', 'Pale']
        };
        
        const randomConfig = {};
        Object.keys(options).forEach(category => {
            const categoryOptions = options[category];
            randomConfig[category] = categoryOptions[Math.floor(Math.random() * categoryOptions.length)];
        });
        randomConfig.avatarStyle = 'Circle';
        
        avatarSelector.currentConfig = randomConfig;
        setupAvatarCustomization(); // Refresh the UI with new config
    });

    // Reset avatar button
    document.getElementById('reset-avatar').addEventListener('click', () => {
        avatarSelector.currentConfig = {
            avatarStyle: 'Circle',
            topType: 'ShortHairShortFlat',
            accessoriesType: 'Blank',
            hairColor: 'BrownDark',
            facialHairType: 'Blank',
            facialHairColor: 'BrownDark',
            clotheType: 'BlazerShirt',
            clotheColor: 'BlueGray',
            skinColor: 'Light'
        };
        setupAvatarCustomization(); // Refresh the UI with default config
    });

    // Save avatar button
    document.getElementById('save-current-avatar').addEventListener('click', async () => {
        try {
            const saved = await avatarSelector.saveAvatarConfig();
            if (saved) {
                // Show success message
                const button = document.getElementById('save-current-avatar');
                const originalText = button.innerHTML;
                button.innerHTML = '✅ Saved!';
                button.style.background = '#38a169';
                setTimeout(() => {
                    button.innerHTML = originalText;
                    button.style.background = '#38a169';
                }, 2000);
            } else {
                alert('Failed to save avatar. Please try again.');
            }
        } catch (error) {
            console.error('Error saving avatar:', error);
            alert('Error saving avatar. Please try again.');
        }
    });

    function setupAvatarCustomization() {
        const container = document.getElementById('avatar-customization-container');
        if (!container) return;

        // Get current avatar config or default
        let currentConfig = avatarSelector.currentConfig || {
            avatarStyle: 'Circle',
            topType: 'ShortHairShortFlat',
            accessoriesType: 'Blank',
            hairColor: 'BrownDark',
            facialHairType: 'Blank',
            facialHairColor: 'BrownDark',
            clotheType: 'BlazerShirt',
            clotheColor: 'BlueGray',
            skinColor: 'Light'
        };
        
        console.log('Setting up avatar customization with config:', currentConfig);

        // Create dropdown-based customization interface like avatar-selector.html
        container.innerHTML = `
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
                <!-- Hair Style -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Hair Style</label>
                    <select id="modal-topType" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="NoHair">No Hair</option>
                        <option value="Eyepatch">Eyepatch</option>
                        <option value="Hat">Hat</option>
                        <option value="Hijab">Hijab</option>
                        <option value="Turban">Turban</option>
                        <option value="WinterHat1">Winter Hat 1</option>
                        <option value="WinterHat2">Winter Hat 2</option>
                        <option value="WinterHat3">Winter Hat 3</option>
                        <option value="WinterHat4">Winter Hat 4</option>
                        <option value="LongHairBigHair">Long Hair Big Hair</option>
                        <option value="LongHairBob">Long Hair Bob</option>
                        <option value="LongHairBun">Long Hair Bun</option>
                        <option value="LongHairCurly">Long Hair Curly</option>
                        <option value="LongHairCurvy">Long Hair Curvy</option>
                        <option value="LongHairDreads">Long Hair Dreads</option>
                        <option value="LongHairFrida">Long Hair Frida</option>
                        <option value="LongHairFro">Long Hair Fro</option>
                        <option value="LongHairFroBand">Long Hair Fro Band</option>
                        <option value="LongHairNotTooLong">Long Hair Not Too Long</option>
                        <option value="LongHairShavedSides">Long Hair Shaved Sides</option>
                        <option value="LongHairMiaWallace">Long Hair Mia Wallace</option>
                        <option value="LongHairStraight">Long Hair Straight</option>
                        <option value="LongHairStraight2">Long Hair Straight 2</option>
                        <option value="LongHairStraightStrand">Long Hair Straight Strand</option>
                        <option value="ShortHairDreads01">Short Hair Dreads 01</option>
                        <option value="ShortHairDreads02">Short Hair Dreads 02</option>
                        <option value="ShortHairFrizzle">Short Hair Frizzle</option>
                        <option value="ShortHairShaggyMullet">Short Hair Shaggy Mullet</option>
                        <option value="ShortHairShortCurly">Short Hair Short Curly</option>
                        <option value="ShortHairShortFlat">Short Hair Short Flat</option>
                        <option value="ShortHairShortRound">Short Hair Short Round</option>
                        <option value="ShortHairShortWaved">Short Hair Short Waved</option>
                        <option value="ShortHairSides">Short Hair Sides</option>
                        <option value="ShortHairTheCaesar">Short Hair The Caesar</option>
                        <option value="ShortHairTheCaesarSidePart">Short Hair The Caesar Side Part</option>
                    </select>
                </div>

                <!-- Hair Color -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Hair Color</label>
                    <select id="modal-hairColor" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Auburn">Auburn</option>
                        <option value="Black">Black</option>
                        <option value="Blonde">Blonde</option>
                        <option value="BlondeGolden">Blonde Golden</option>
                        <option value="Brown">Brown</option>
                        <option value="BrownDark">Brown Dark</option>
                        <option value="PastelPink">Pastel Pink</option>
                        <option value="Platinum">Platinum</option>
                        <option value="Red">Red</option>
                        <option value="SilverGray">Silver Gray</option>
                    </select>
                </div>

                <!-- Facial Hair -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Facial Hair</label>
                    <select id="modal-facialHairType" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Blank">None</option>
                        <option value="BeardMedium">Beard Medium</option>
                        <option value="BeardLight">Beard Light</option>
                        <option value="BeardMajestic">Beard Majestic</option>
                        <option value="MoustacheFancy">Moustache Fancy</option>
                        <option value="MoustacheMagnum">Moustache Magnum</option>
                    </select>
                </div>

                <!-- Facial Hair Color -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Facial Hair Color</label>
                    <select id="modal-facialHairColor" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Auburn">Auburn</option>
                        <option value="Black">Black</option>
                        <option value="Blonde">Blonde</option>
                        <option value="BlondeGolden">Blonde Golden</option>
                        <option value="Brown">Brown</option>
                        <option value="BrownDark">Brown Dark</option>
                        <option value="Platinum">Platinum</option>
                        <option value="Red">Red</option>
                    </select>
                </div>

                <!-- Accessories -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Accessories</label>
                    <select id="modal-accessoriesType" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Blank">None</option>
                        <option value="Kurt">Kurt</option>
                        <option value="Prescription01">Glasses Prescription 01</option>
                        <option value="Prescription02">Glasses Prescription 02</option>
                        <option value="Round">Glasses Round</option>
                        <option value="Sunglasses">Sunglasses</option>
                        <option value="Wayfarers">Wayfarers</option>
                    </select>
                </div>

                <!-- Clothing -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Clothing</label>
                    <select id="modal-clotheType" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="BlazerShirt">Blazer Shirt</option>
                        <option value="BlazerSweater">Blazer Sweater</option>
                        <option value="CollarSweater">Collar Sweater</option>
                        <option value="GraphicShirt">Graphic Shirt</option>
                        <option value="Hoodie">Hoodie</option>
                        <option value="Overall">Overall</option>
                        <option value="ShirtCrewNeck">Shirt Crew Neck</option>
                        <option value="ShirtScoopNeck">Shirt Scoop Neck</option>
                        <option value="ShirtVNeck">Shirt V Neck</option>
                    </select>
                </div>

                <!-- Clothing Color -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Clothing Color</label>
                    <select id="modal-clotheColor" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Black">Black</option>
                        <option value="Blue01">Blue 01</option>
                        <option value="Blue02">Blue 02</option>
                        <option value="Blue03">Blue 03</option>
                        <option value="Gray01">Gray 01</option>
                        <option value="Gray02">Gray 02</option>
                        <option value="Heather">Heather</option>
                        <option value="PastelBlue">Pastel Blue</option>
                        <option value="PastelGreen">Pastel Green</option>
                        <option value="PastelOrange">Pastel Orange</option>
                        <option value="PastelRed">Pastel Red</option>
                        <option value="PastelYellow">Pastel Yellow</option>
                        <option value="Pink">Pink</option>
                        <option value="Red">Red</option>
                        <option value="White">White</option>
                    </select>
                </div>

                <!-- Skin Color -->
                <div>
                    <label style="display: block; font-size: 0.9rem; font-weight: 500; color: #374151; margin-bottom: 0.5rem;">Skin Color</label>
                    <select id="modal-skinColor" style="width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; background: white; color: #374151;">
                        <option value="Tanned">Tanned</option>
                        <option value="Yellow">Yellow</option>
                        <option value="Pale">Pale</option>
                        <option value="Light">Light</option>
                        <option value="Brown">Brown</option>
                        <option value="DarkBrown">Dark Brown</option>
                        <option value="Black">Black</option>
                    </select>
                </div>
            </div>
        `;

        // Set current values in dropdowns
        Object.keys(currentConfig).forEach(key => {
            const select = document.getElementById(`modal-${key}`);
            if (select && currentConfig[key]) {
                select.value = currentConfig[key];
            }
        });

        // Add event listeners to dropdowns
        ['topType', 'hairColor', 'facialHairType', 'facialHairColor', 'accessoriesType', 'clotheType', 'clotheColor', 'skinColor'].forEach(configKey => {
            const select = document.getElementById(`modal-${configKey}`);
            if (select) {
                select.addEventListener('change', (e) => {
                    console.log(`Changed ${configKey} to ${e.target.value}`);
                    currentConfig[configKey] = e.target.value;
                    avatarSelector.currentConfig = currentConfig;
                    console.log('Updated avatarSelector.currentConfig:', avatarSelector.currentConfig);
                    updateAvatarPreview();
                });
            }
        });

        // Update initial preview
        updateAvatarPreview();
    }

    document.getElementById('close-avatar-manager').addEventListener('click', () => {
        modal.remove();
        delete window.modalAvatarSelector;
    });

    // Click outside modal to close
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.remove();
            delete window.modalAvatarSelector;
        }
    });

    function updateAvatarPreview() {
        const previewDiv = document.getElementById('current-avatar-preview');
        if (previewDiv && avatarSelector) {
            const config = avatarSelector.currentConfig;
            const params = new URLSearchParams();
            
            Object.keys(config).forEach(key => {
                if (config[key]) {
                    params.append(key, config[key]);
                }
            });
            
            const avatarUrl = 'https://avataaars.io/?' + params.toString();
            previewDiv.innerHTML = `<img src="${avatarUrl}" alt="Current Avatar" style="width: 120px; height: 120px; border-radius: 50%; border: 3px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.1);">`;
        }
    }
}


// --- Utility Functions ---
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

// Add event listener to stop scanning/polling on page unload
window.addEventListener('beforeunload', () => {
    stopAuditoryScanning();
    stopGamepadPolling();
});
