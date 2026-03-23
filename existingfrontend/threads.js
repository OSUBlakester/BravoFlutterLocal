// --- Global Variables for Threads ---
let currentlyScannedButton = null;
let lastGamepadInputTime = 0;
let isLLMProcessing = false;
const clickDebounceDelay = 300;
let defaultDelay = 3500;
let scanningInterval;
let currentButtonIndex = -1;
let scanCycleCount = 0;
let scanLoopLimit = 0;
let isPausedFromScanLimit = false;
let gamepadIndex = null;
let gamepadPollInterval = null;

// Thread-specific variables
let currentThread = null;
let threadMessages = [];
let wakeWordInterjection = "hey";
let wakeWordName = "bravo";
let LLMOptions = 10;
let ScanningOff = false;
let scanMode = 'auto'; // auto | step
let SummaryOff = false;
let gridColumns = 10;
let waitingForUserAction = false; // New flag to track if we're waiting for user to resume

// Speech recognition variables
let recognition = null;
let isSettingUpRecognition = false;
let listeningForQuestion = false;

// Audio and announcement variables
let announcementQueue = [];
let isAnnouncingNow = false;
let audioContextResumeAttempted = false;
let activeAnnouncementAudioContext = null;
let activeAnnouncementAudioSource = null;

// User management variables
let currentAacUserId = null;
let firebaseIdToken = null;
const AAC_USER_ID_SESSION_KEY = "currentAacUserId";
const FIREBASE_TOKEN_SESSION_KEY = "firebaseIdToken";
const QUESTION_TEXTAREA_ID = 'question-display';
const LISTENING_HIGHLIGHT_CLASS = 'highlight-listening';

// --- Utility Functions ---

function base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}

async function authenticatedFetch(url, options = {}, _isRetry = false) {
    // Re-read token from sessionStorage (may have been refreshed by token-refresh.js)
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        console.error('Missing authentication credentials');
        throw new Error('Authentication required');
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
        console.error('Authentication failed, redirecting to auth page');
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed');
    }
    if (response.status === 401 || response.status === 403) {
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed after token refresh');
    }
    return response;
}

// --- Initialization Functions ---

async function initializeUserContext() {
    const storedAacUserId = sessionStorage.getItem(AAC_USER_ID_SESSION_KEY);
    const storedFirebaseToken = sessionStorage.getItem(FIREBASE_TOKEN_SESSION_KEY);
    
    if (!storedAacUserId || !storedFirebaseToken) {
        console.error('Missing user credentials, redirecting to auth');
        window.location.href = '/static/auth.html';
        return false;
    }
    
    currentAacUserId = storedAacUserId;
    firebaseIdToken = storedFirebaseToken;
    
    // Load settings
    await loadScanSettings();
    
    // Load and update page title with profile name
    await updatePageTitleWithProfile();
    
    return true;
}

// Function to update page title with profile name
async function updatePageTitleWithProfile() {
    console.log('updatePageTitleWithProfile: Starting - currentAacUserId:', currentAacUserId);
    try {
        if (!currentAacUserId) {
            console.warn('updatePageTitleWithProfile: No currentAacUserId available');
            return;
        }
        
        const response = await authenticatedFetch('/api/account/users');
        console.log('updatePageTitleWithProfile: API response status:', response.status);
        
        if (!response.ok) {
            console.warn('updatePageTitleWithProfile: API response not ok:', response.status);
            return;
        }
        
        const profiles = await response.json();
        console.log('updatePageTitleWithProfile: Profiles received:', profiles.length, 'profiles');
        
        const currentProfile = profiles.find(profile => profile.aac_user_id === currentAacUserId);
        console.log('updatePageTitleWithProfile: Current profile found:', currentProfile ? currentProfile.display_name : 'none');
        
        if (currentProfile && currentProfile.display_name) {
            const titleElement = document.getElementById('dynamic-page-title');
            console.log('updatePageTitleWithProfile: Title element found:', !!titleElement);
            
            if (titleElement) {
                const baseTitle = 'Thread Communication';
                const newTitle = `${baseTitle} - ${currentProfile.display_name}`;
                titleElement.textContent = newTitle;
                console.log(`updatePageTitleWithProfile: Updated title to: "${newTitle}"`);
            }
        } else {
            console.warn('updatePageTitleWithProfile: No profile found or no display name for user:', currentAacUserId);
        }
    } catch (error) {
        console.error('Error updating page title with profile:', error);
    }
}

// Function to update thread page title with both thread name and profile name
async function updateThreadPageTitle() {
    console.log('updateThreadPageTitle: Starting');
    try {
        if (!currentAacUserId) {
            console.warn('updateThreadPageTitle: No currentAacUserId available');
            return;
        }
        
        const response = await authenticatedFetch('/api/account/users');
        if (!response.ok) {
            console.warn('updateThreadPageTitle: API response not ok:', response.status);
            return;
        }
        
        const profiles = await response.json();
        const currentProfile = profiles.find(profile => profile.aac_user_id === currentAacUserId);
        
        const titleElement = document.getElementById('dynamic-page-title');
        if (titleElement) {
            let newTitle = '';
            if (currentThread && currentThread.favorite_name) {
                newTitle = `Thread: ${currentThread.favorite_name}`;
            } else {
                newTitle = 'Thread Communication';
            }
            
            if (currentProfile && currentProfile.display_name) {
                newTitle += ` - ${currentProfile.display_name}`;
            }
            
            titleElement.textContent = newTitle;
            console.log(`updateThreadPageTitle: Updated title to: "${newTitle}"`);
        }
    } catch (error) {
        console.error('Error updating thread page title:', error);
    }
}

async function loadScanSettings() {
    try {
        const response = await authenticatedFetch('/api/settings');
        if (response.ok) {
            const settings = await response.json();
            defaultDelay = settings.scanDelay || 3500;
            wakeWordInterjection = (settings.wakeWordInterjection || "hey").toLowerCase();
            wakeWordName = (settings.wakeWordName || "bravo").toLowerCase();
            LLMOptions = settings.LLMOptions || 10;
            ScanningOff = settings.ScanningOff || false;
            scanMode = settings.scanMode === 'step' ? 'step' : 'auto';
            SummaryOff = settings.SummaryOff || false;
            gridColumns = settings.gridColumns || 10;
            scanLoopLimit = settings.scanLoopLimit || 0;
            
            // Update sight word service with new settings
            if (window.updateSightWordSettings) {
                window.updateSightWordSettings(settings);
            }
            
            // Update grid layout
            updateGridLayout();
        }
    } catch (error) {
        console.error('Error loading settings:', error);
    }
}

function updateGridLayout() {
    const gridContainer = document.getElementById('gridContainer');
    if (gridContainer) {
        gridContainer.style.setProperty('--grid-columns', gridColumns);
    }
}

// --- Thread Management Functions ---

async function openThread(favoriteName) {
    console.log(`Opening thread for favorite: ${favoriteName}`);
    document.getElementById('loading-indicator').style.display = 'flex';
    
    try {
        const response = await authenticatedFetch('/api/threads/open', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ favorite_name: favoriteName })
        });
        
        const result = await response.json();
        
        if (!result.success) {
            // If the favorite location hasn't been loaded within 4 hours, announce and return
            if (result.message && result.message.includes("within the last 4 hours")) {
                await announce("Cannot open Thread. Please load a Favorite Location.", "system", false);
                setTimeout(() => {
                    window.history.back();
                }, 3000);
                return;
            }
            
            await announce(result.message, "system", false);
            setTimeout(() => {
                window.history.back();
            }, 3000);
            return;
        }
        
        // Store thread data
        currentThread = result.thread;
        threadMessages = result.all_messages || result.recent_messages || [];  // Use all_messages if available, fallback to recent_messages for backwards compatibility
        
        // Store recent messages separately for LLM context
        const recentMessagesForLLM = result.recent_messages || threadMessages.slice(-5);
        
        // Update page title with favorite name and maintain profile name
        await updateThreadPageTitle();
        
        // Display thread history
        displayThreadHistory();
        
        if (result.is_new) {
            // New thread - generate initial options
            await announce(`Starting new conversation thread for ${currentThread.favorite_name}.`, "system", false);
            await generateInitialThreadOptions();
        } else {
            // Existing thread - announce summary and generate response options
            if (recentMessagesForLLM.length > 0) {
                await announceThreadSummary(recentMessagesForLLM);
            }
            await generateInitialThreadOptions(recentMessagesForLLM);
        }
        
    } catch (error) {
        console.error('Error opening thread:', error);
        await announce('Error opening thread. Returning to previous page.', "system", false);
        setTimeout(() => {
            window.history.back();
        }, 3000);
    } finally {
        document.getElementById('loading-indicator').style.display = 'none';
    }
}

function displayThreadHistory() {
    const messagesContainer = document.getElementById('thread-messages');
    if (!messagesContainer) return;
    
    messagesContainer.innerHTML = '';
    
    if (threadMessages.length === 0) {
        messagesContainer.innerHTML = '<p class="text-gray-500 text-center">No messages yet. Start the conversation!</p>';
        return;
    }
    
    threadMessages.forEach(message => {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${message.sender_type}`;
        
        const bubble = document.createElement('div');
        bubble.className = 'message-bubble';
        bubble.textContent = message.content;
        
        const timeSpan = document.createElement('span');
        timeSpan.className = 'message-time';
        const messageTime = new Date(message.created_at);
        timeSpan.textContent = messageTime.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
        
        if (message.sender_type === 'user') {
            messageDiv.appendChild(timeSpan);
            messageDiv.appendChild(bubble);
        } else {
            messageDiv.appendChild(bubble);
            messageDiv.appendChild(timeSpan);
        }
        
        messagesContainer.appendChild(messageDiv);
    });
    
    // Scroll to bottom with a small delay to ensure DOM rendering is complete
    setTimeout(() => {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        // Also scroll the parent container to ensure visibility
        const parentContainer = document.getElementById('thread-history-container');
        if (parentContainer) {
            parentContainer.scrollTop = parentContainer.scrollHeight;
        }
    }, 50);
}

async function announceThreadSummary(recentMessages = null) {
    // Use provided recent messages or fallback to last 5 from threadMessages
    const messagesToSummarize = recentMessages || threadMessages.slice(-5);
    
    if (messagesToSummarize.length === 0) return;
    
    try {
        // Create prompt for LLM to summarize last few messages
        const messagesText = messagesToSummarize.map(msg => 
            `${msg.sender_type === 'user' ? 'User' : 'Others'}: ${msg.content}`
        ).join('\n');
        
        const prompt = `Here are the last few messages from a conversation thread. Create a brief, conversational summary of where the conversation left off. Keep it to 1-2 sentences:

${messagesText}

Provide only the summary, no extra text.`;

        const response = await getLLMResponse(prompt);
        if (Array.isArray(response) && response.length > 0 && response[0].option) {
            await announce(`Here's where we left off: ${response[0].option}`, "system", false);
        } else if (typeof response === 'string' && response.trim()) {
            await announce(`Here's where we left off: ${response.trim()}`, "system", false);
        }
    } catch (error) {
        console.error('Error generating thread summary:', error);
        // Fallback to simple announcement
        const lastMessage = threadMessages[threadMessages.length - 1];
        if (lastMessage) {
            await announce(`Last message was: ${lastMessage.content}`, "system", false);
        }
    }
}

async function generateInitialThreadOptions(recentMessages = null) {
    console.log('Generating initial thread options');
    document.getElementById('loading-indicator').style.display = 'flex';
    
    try {
        // Build context for LLM
        let contextPrompt;
        if (threadMessages.length === 0) {
            contextPrompt = `The user is starting a new communication thread at ${currentThread.location} with ${currentThread.people} during ${currentThread.activity}. Generate ${LLMOptions} conversation starter options that would be appropriate for this setting.`;
        } else {
            // Use provided recent messages or fallback to last 10 from threadMessages
            const messagesToUse = recentMessages || threadMessages.slice(-10);
            const recentHistory = messagesToUse.map(msg => 
                `${msg.sender_type === 'user' ? 'User' : 'Others'}: ${msg.content}`
            ).join('\n');
            
            contextPrompt = `The user is in an ongoing conversation thread at ${currentThread.location} with ${currentThread.people} during ${currentThread.activity}. Here's the recent conversation history:

${recentHistory}

Generate ${LLMOptions} response options that would be appropriate to continue or restart this conversation.`;
        }
        
        const summaryInstruction = SummaryOff
            ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
            : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
        
        const prompt = `${contextPrompt}
        
Return ONLY a JSON list where each item has "option" and "summary" keys.
${summaryInstruction}
The "option" key should contain the FULL option text.
Example: [{"option": "...", "summary": "..."}]`;

        const response = await getLLMResponse(prompt);
        
        if (Array.isArray(response) && response.length > 0) {
            generateThreadButtons(response);
        } else {
            console.error('Invalid LLM response for initial options');
            await announce('My AI is down. Please notify my Admin.', "system", false);
        }
        
    } catch (error) {
        console.error('Error generating initial options:', error);
        await announce('My AI is down. Please notify my Admin.', "system", false);
    } finally {
        document.getElementById('loading-indicator').style.display = 'none';
    }
}

// --- Speech Recognition Functions ---

function setupSpeechRecognition() {
    if (isSettingUpRecognition || recognition) { 
        console.log('Thread speech recognition already active or being setup, skipping...');
        return; 
    }
    isSettingUpRecognition = true;
    console.log("Setting up Thread keyword speech recognition...");
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) {
        console.error("Speech Recognition API not supported."); 
        isSettingUpRecognition = false; 
        return;
    }
    recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    console.log("Thread Keyword Recognition object created:", recognition);

    recognition.onerror = function (event) {
        console.error("Thread Keyword Speech recognition error:", event.error, event.message);
        if (['no-speech', 'audio-capture', 'network'].includes(event.error) && !listeningForQuestion) { 
            // Only restart if not trying to listen for a question
             console.log("Thread Keyword recognition error, attempting restart...");
             setTimeout(() => {
                 if (!listeningForQuestion && !isSettingUpRecognition) {
                     isSettingUpRecognition = false;
                     recognition = null;
                     setupSpeechRecognition();
                 }
             }, 1000);
        } else { 
            isSettingUpRecognition = false; 
            recognition = null; 
        }
    };

    recognition.onresult = async (event) => {
        const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase().trim();
        console.log('Thread Keyword check - Speech recognized:', transcript);
        if (listeningForQuestion) { 
            console.log("Ignoring thread keyword, currently listening for question."); 
            return; 
        }

        const interjectionToUse = wakeWordInterjection || "hey";
        const nameToUse = wakeWordName || "bravo";
        const phraseWithSpace = `${interjectionToUse} ${nameToUse}`;
        const phraseWithComma = `${interjectionToUse}, ${nameToUse}`;
        const phraseWithCommaNoSpace = `${interjectionToUse},${nameToUse}`;

        console.log(`Thread checking for: "${phraseWithSpace}" OR "${phraseWithComma}" OR "${phraseWithCommaNoSpace}"`);

        if (transcript.includes(phraseWithSpace) || transcript.includes(phraseWithComma) || transcript.includes(phraseWithCommaNoSpace)) {
            console.log(`Thread Keyword detected! ("${transcript}")`);
            stopAuditoryScanning();
            if (recognition) {
                recognition.stop();
                recognition = null;
            }
             isSettingUpRecognition = false;

            // *** HIGHLIGHT QUESTION TEXTAREA ***
            const questionTextarea = document.getElementById(QUESTION_TEXTAREA_ID);
            if (questionTextarea) {
                questionTextarea.classList.add(LISTENING_HIGHLIGHT_CLASS);
                questionTextarea.placeholder = "Listening...";
            }

            const announcement = 'Listening for your question or comment...';
            console.log("Calling announce for thread question prompt...");
            
            // Set up a fallback timer in case announcement hangs
            const fallbackTimer = setTimeout(() => {
                console.warn("Thread wake word: Announcement took too long, proceeding with question recognition");
                setupQuestionRecognition();
            }, 5000); // 5 second fallback
            
            try {
                await announce(announcement, "system", false);
                clearTimeout(fallbackTimer);
                setTimeout(() => setupQuestionRecognition(), 500);
            } catch (announceError) {
                console.error("Thread announcement error:", announceError);
                clearTimeout(fallbackTimer);
                setTimeout(() => setupQuestionRecognition(), 500);
            }
        }
    };

    recognition.onend = () => {
        console.log("Thread Keyword Recognition ended.");
        if (!listeningForQuestion && !isSettingUpRecognition && recognition) {
             console.log("Thread keyword recognition ended unexpectedly, restarting.");
             recognition = null; 
             setTimeout(setupSpeechRecognition, 500);
        } else {
             console.log("Thread keyword recognition ended normally or was already being reset/stopped.");
             isSettingUpRecognition = false;
        }
    };

    try { 
        recognition.start(); 
        console.log("Thread keyword recognition started."); 
        isSettingUpRecognition = false; 
    }
    catch (e) { 
        console.error("Error starting thread keyword recognition:", e); 
        isSettingUpRecognition = false; 
        recognition = null; 
    }
}

function setupQuestionRecognition() {
    console.log("Attempting to set up thread question recognition...");
    const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognitionAPI) { 
        console.error("Speech Recognition API not supported."); 
        announce("Sorry, I can't use speech recognition.", "system", false); 
        return; 
    }

    let questionRecognitionInstance = new SpeechRecognitionAPI(); // Use local instance
    questionRecognitionInstance.lang = 'en-US';
    questionRecognitionInstance.continuous = false;
    questionRecognitionInstance.interimResults = true;
    questionRecognitionInstance.maxAlternatives = 1;

    let finalTranscript = ''; 
    let listeningTimeout; 
    let hasProcessedResult = false; 
    let isRestartingKeyword = false;
    const questionTextarea = document.getElementById(QUESTION_TEXTAREA_ID);

    console.log("Thread Question Recognition Config:", { continuous: false, interimResults: true, lang: 'en-US', maxAlternatives: 1 });

    questionRecognitionInstance.onstart = () => {
        console.log("Thread Question Recognition: Listening started...");
        finalTranscript = ''; 
        hasProcessedResult = false;
        if (questionTextarea) {
            questionTextarea.placeholder = "Listening..."; // Ensure placeholder is set
            questionTextarea.value = "";
            questionTextarea.classList.add(LISTENING_HIGHLIGHT_CLASS); // Ensure highlight is on
        }
        listeningForQuestion = true; // Set global state
        clearTimeout(listeningTimeout);
        listeningTimeout = setTimeout(() => {
             if (listeningForQuestion && !finalTranscript && !hasProcessedResult) {
                 console.log("Thread question recognition timeout - no speech detected");
                 announce("Didn't hear anything. Going back to scanning.", "system", false);
                 try { questionRecognitionInstance.stop(); } catch(e) {}
             }
        }, 10000);
    };

    questionRecognitionInstance.onresult = async (event) => {
        console.log("Thread Question onresult."); 
        if (hasProcessedResult) return; 
        clearTimeout(listeningTimeout);
        let interimTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
            const transcriptPart = event.results[i][0].transcript;
            if (event.results[i].isFinal) { 
                finalTranscript += transcriptPart; 
            } else { 
                interimTranscript += transcriptPart; 
            }
        }
        const displayTranscript = finalTranscript || interimTranscript;
        if (questionTextarea) questionTextarea.value = displayTranscript.trim();

        const isFinishedUtterance = event.results[event.results.length - 1].isFinal;

        if (isFinishedUtterance && finalTranscript.trim()) {
            hasProcessedResult = true; 
            console.log("Final Thread Question:", finalTranscript.trim().toLowerCase());
            listeningForQuestion = false; // Set state BEFORE async

            // *** REMOVE HIGHLIGHT & SHOW LOADING ***
            if (questionTextarea) {
                questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS);
                questionTextarea.placeholder = "Question or Comment:";
            }
            document.getElementById('loading-indicator').style.display = 'flex';

            try {
                const questionComment = finalTranscript.trim();
                await announce(`OK, I heard you say: ${questionComment}. Give me a moment to respond.`, "system", false);
                
                // Add incoming message to thread
                await addMessageToThread(questionComment, 'incoming');
                
                // Generate response options based on the question/comment
                await generateResponseOptions(questionComment);
                
            } catch (error) {
                console.error('Error processing thread question:', error); 
                announce("Error processing question.", "system", false);
                isRestartingKeyword = true; 
                setupSpeechRecognition();
            } finally {
                document.getElementById('loading-indicator').style.display = 'none'; // Ensure indicator is hidden
                if (questionTextarea) {
                    questionTextarea.placeholder = "Question or Comment:";
                }
                console.log("Thread LLM processing finished for question.");
            }
        } else if (!isFinishedUtterance) { 
            console.log("Thread waiting for final result..."); 
        }
        else { 
            console.log("Thread final utterance empty."); 
            listeningForQuestion = false; 
            if (questionTextarea) {
                questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS);
                questionTextarea.placeholder = "Question or Comment:";
            }
        }
    };

    questionRecognitionInstance.onerror = (event) => {
        clearTimeout(listeningTimeout); 
        if (hasProcessedResult) return;
        console.error("Thread Question Error:", event.error, event.message);
        let errorMessage = "Speech recognition error."; 
        let attemptRetry = false;
        if (event.error === 'no-speech') {
            errorMessage = "Didn't hear anything. Try again?";
            if (!questionRecognitionInstance.hasRetried) { 
                attemptRetry = true; 
                errorMessage += " Retrying..."; 
                questionRecognitionInstance.hasRetried = true; 
            } // Use instance flag
            else { 
                console.log("Already retried for thread question."); 
                errorMessage = "Still didn't hear anything. Going back to scanning.";
            }
        } else if (event.error === 'not-allowed' || event.error === 'service-not-allowed') { 
            errorMessage = "Mic access denied."; 
        }
        else if (event.error === 'audio-capture') {
            errorMessage = "Microphone issue. Check your microphone.";
        }
        else if (event.error === 'network') {
            errorMessage = "Network issue. Check your connection.";
        }

        if (errorMessage) { announce(errorMessage, "system", false); }
        document.getElementById('loading-indicator').style.display = 'none';
        if (questionTextarea) {
            questionTextarea.placeholder = "Question or Comment:";
            questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); // Remove highlight on error
        }
        listeningForQuestion = false;
        try { questionRecognitionInstance.stop(); } catch(e) {}

        if (attemptRetry) {
            console.log("Attempting thread question retry...");
            setTimeout(() => {
                 try {
                     questionRecognitionInstance.start();
                 }
                 catch (e) {
                     console.error("Thread question retry start error:", e);
                     announce("Couldn't restart listening. Going back to scanning.", "system", false);
                     isRestartingKeyword = true;
                     setupSpeechRecognition();
                     if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                         startAuditoryScanning();
                     }
                 }
            }, 500);
        } else { 
            console.log("Not retrying thread question. Restarting keyword listener.");
            isRestartingKeyword = true;
            setupSpeechRecognition();
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                console.log("Error in thread question rec (not retrying), restarting scanning for existing buttons.");
                startAuditoryScanning();
            }
        }
    };

    questionRecognitionInstance.onend = () => {
        clearTimeout(listeningTimeout); 
        console.log("Thread Question Recognition ended.");
        const wasRetried = questionRecognitionInstance?.hasRetried; 
        const stillListening = listeningForQuestion; // Capture state before reset
        if (listeningForQuestion) { 
            listeningForQuestion = false; 
            console.log("Reset thread listening flag in onend."); 
        }

        if (questionTextarea) {
            questionTextarea.classList.remove(LISTENING_HIGHLIGHT_CLASS); // Ensure highlight is removed
            questionTextarea.placeholder = "Question or Comment:";
        }

        if (stillListening && !hasProcessedResult && !wasRetried) { 
            console.log("Thread ended without result/retry."); 
            announce("Didn't catch that. Going back to scanning.", "system", false); 
        }

        if (!hasProcessedResult && !isRestartingKeyword) {
            console.log("Restarting thread keyword listener from onend.");
            setupSpeechRecognition();
            // If ending without result and falling back to keyword spotting, attempt to restart scanning.
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                console.log("Thread question rec ended (no result), restarting scanning for existing buttons.");
                startAuditoryScanning();
            }
        } else { 
            console.log("Not restarting thread keyword listener from onend (processed, retrying, or handled by error)."); 
        }

        questionRecognitionInstance = null; 
        console.log("Thread Question instance cleaned up.");
    };

    questionRecognitionInstance.onnomatch = () => { 
        console.warn("Thread Question No match."); 
    };
    
    questionRecognitionInstance.onspeechend = () => {
        console.log("Thread Question Speech ended."); 
        clearTimeout(listeningTimeout);
        listeningTimeout = setTimeout(() => {
            if (listeningForQuestion && !hasProcessedResult) {
                console.warn("Thread timeout after speech end.");
                announce("Didn't get a final result. Going back to scanning.", "system", false);
                try { questionRecognitionInstance.stop(); } catch(e) {}
            }
        }, 5000);
    };
    
    questionRecognitionInstance.onsoundend = () => { 
        console.log("Thread Question Sound ended."); 
    };

    setTimeout(() => {
        try { 
            console.log("Calling start() for thread question recognition..."); 
            questionRecognitionInstance.start(); 
        }
        catch (e) { 
            console.error("Thread question start error:", e); 
            announce("Couldn't start listening. Going back to scanning.", "system", false); 
            listeningForQuestion = false; 
            clearTimeout(listeningTimeout); 
            isRestartingKeyword = true; 
            setupSpeechRecognition();
            if (document.querySelectorAll('#gridContainer button:not([style*="display: none"])').length > 0) {
                startAuditoryScanning();
            }
        }
    }, 150);
}

async function addMessageToThread(content, senderType) {
    if (!currentThread) return;
    
    try {
        const requestBody = {
            content: content,
            sender_type: senderType
        };
        
        const response = await authenticatedFetch(`/api/threads/${currentThread.thread_id}/messages`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(requestBody)
        });
        
        if (response.ok) {
            const result = await response.json();
            if (result.success) {
                threadMessages.push(result.message);
                displayThreadHistory();
            }
        } else {
            console.error(`[THREAD_MESSAGE] Server responded with error:`, response.status, await response.text());
        }
    } catch (error) {
        console.error('Error adding message to thread:', error);
    }
}

async function generateResponseOptions(questionComment) {
    console.log('Generating response options for:', questionComment);
    
    try {
        // Build context including thread history and current question
        const recentHistory = threadMessages.slice(-10).map(msg => 
            `${msg.sender_type === 'user' ? 'User' : 'Others'}: ${msg.content}`
        ).join('\n');
        
        const contextPrompt = `The user is in a conversation thread at ${currentThread.location} with ${currentThread.people} during ${currentThread.activity}.

Recent conversation history:
${recentHistory}

Someone just asked or commented: "${questionComment}"

Generate ${LLMOptions} appropriate response options for the AAC user. The options should include:
- Direct responses to the question/comment
- Follow-up questions to keep the conversation going
- Related comments that could lead to more discussion
- Ways to share relevant personal experiences or thoughts

Focus on creating engaging options that encourage continued communication and social interaction.`;
        
        const summaryInstruction = SummaryOff
            ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
            : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
        
        const prompt = `${contextPrompt}
        
Return ONLY a JSON list where each item has "option" and "summary" keys.
${summaryInstruction}
The "option" key should contain the FULL response text.
Example: [{"option": "...", "summary": "..."}]`;

        const response = await getLLMResponse(prompt);
        
        if (Array.isArray(response) && response.length > 0) {
            generateThreadButtons(response);
        } else {
            console.error('Invalid LLM response for thread options');
            await announce('My AI is down. Please notify my Admin.', "system", false);
        }
        
    } catch (error) {
        console.error('Error generating response options:', error);
        await announce('My AI is down. Please notify my Admin.', "system", false);
    }
}

// --- LLM Integration ---

async function getLLMResponse(prompt) {
    console.log("Sending LLM Request for thread (Prompt length):", prompt.length);
    try {
        const response = await authenticatedFetch('/llm', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: prompt }),
        });

        if (!response.ok) {
            throw new Error(`LLM request failed: ${response.status}`);
        }

        const parsedJson = await response.json();
        console.log("Thread LLM Response Received:", parsedJson);

        if (!Array.isArray(parsedJson)) {
            console.error("Expected array from LLM, got:", typeof parsedJson);
            return [];
        }

        const transformedData = parsedJson.map(item => {
            if (typeof item === 'object' && item !== null && 
                typeof item.option === 'string' && typeof item.summary === 'string') {
                return {
                    option: item.option.trim(),
                    summary: item.summary.trim(),
                    isLLMGenerated: true,
                    originalPrompt: prompt
                };
            }
            return null;
        }).filter(Boolean);

        console.log("Thread transformed data:", transformedData);
        return transformedData;

    } catch (error) {
        console.error("Error in thread LLM response:", error);
        return [];
    }
}

// --- Button Generation ---

function generateThreadButtons(options) {
    document.getElementById('loading-indicator').style.display = 'none';
    isLLMProcessing = false;
    stopAuditoryScanning();
    
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) {
        console.error("gridContainer not found!");
        return;
    }
    
    gridContainer.innerHTML = '';
    updateGridLayout();
    
    let isAnnouncing = false;
    console.log("Generating thread buttons for options:", options);

    // Generate buttons for LLM options
    options.forEach(optionData => {
        if (!optionData || typeof optionData.summary !== 'string' || typeof optionData.option !== 'string') {
            console.warn("Skipping invalid thread option data:", optionData);
            return;
        }
        
        const button = document.createElement('button');
        button.textContent = optionData.summary;
        button.dataset.option = optionData.option;
        
        button.addEventListener('click', async () => {
            if (isAnnouncing) return;
            isAnnouncing = true;
            stopAuditoryScanning();
            
            console.log("Thread button clicked:", optionData.option);
            
            try {
                // Announce the selected response
                await announce(optionData.option, "system");
                
                // Add user message to thread
                await addMessageToThread(optionData.option, 'user');
                
                // Clear question display
                const questionDisplay = document.getElementById('question-display');
                if (questionDisplay) {
                    questionDisplay.value = '';
                }
                
                // Clear all LLM-generated options and show only standard buttons
                clearLLMOptionsAndShowStandardButtons();
                
                // Set flag to indicate we're waiting for user action
                waitingForUserAction = true;
                
                // Pause scanning - user needs to manually resume with switch
                console.log('User selected an option. Scanning paused until manual resume.');
                try {
                    await announce("Scanning paused. Use your switch to resume scanning.", "system", false);
                } catch (e) { 
                    console.error("Speech synthesis error:", e); 
                }
                
            } catch (error) {
                console.error("Error during thread response:", error);
                startAuditoryScanning();
            } finally {
                isAnnouncing = false;
            }
        });
        
        gridContainer.appendChild(button);
    });

    // Add standard thread buttons for normal thread operation
    addEssentialThreadButtons(gridContainer);
    
    // Start auditory scanning and speech recognition
    if (gridContainer.childElementCount > 0) {
        console.log("Starting auditory scanning and speech recognition for thread buttons");
        startAuditoryScanning();
        // Restart speech recognition for wake word detection
        setTimeout(() => {
            setupSpeechRecognition();
        }, 1000);
    }
}

// --- Clear LLM options and show only standard buttons ---
function clearLLMOptionsAndShowStandardButtons() {
    const gridContainer = document.getElementById('gridContainer');
    if (!gridContainer) {
        console.error("gridContainer not found!");
        return;
    }
    
    // Clear all current buttons
    gridContainer.innerHTML = '';
    updateGridLayout();
    
    console.log("Cleared LLM options, showing only essential thread buttons");
    
    // Add only essential buttons when pausing after user communication
    addEssentialThreadButtons(gridContainer);
}

// --- Add essential buttons for post-communication pause ---
function addEssentialThreadButtons(gridContainer) {
    // Free Style button
    const freeStyleButton = document.createElement('button');
    freeStyleButton.textContent = 'Free Style';
    freeStyleButton.addEventListener('click', () => {
        stopAuditoryScanning();
        resumeScanningAfterUserAction(); // Resume scanning since button was clicked
        console.log("Thread Free Style button clicked");
        // Navigate to freestyle page with thread context
        const threadParam = encodeURIComponent(JSON.stringify({
            thread_id: currentThread?.thread_id,
            return_url: window.location.href
        }));
        window.location.href = `/static/freestyle.html?thread=${threadParam}`;
    });
    gridContainer.appendChild(freeStyleButton);

    // New Topic button
    const newTopicButton = document.createElement('button');
    newTopicButton.textContent = 'New Topic';
    newTopicButton.addEventListener('click', async () => {
        stopAuditoryScanning();
        resumeScanningAfterUserAction(); // Resume scanning since button was clicked
        console.log("New Topic button clicked");
        
        document.getElementById('loading-indicator').style.display = 'flex';
        
        try {
            // Build context from current thread and recent history
            let contextInfo = '';
            if (currentThread) {
                contextInfo = `The user is currently in a conversation thread at "${currentThread.location}" with "${currentThread.people}" during "${currentThread.activity}".`;
                
                // Add recent conversation history for context
                if (threadMessages.length > 0) {
                    const recentHistory = threadMessages.slice(-5).map(msg => 
                        `${msg.sender_type === 'user' ? 'User' : 'Others'}: ${msg.content}`
                    ).join('\n');
                    contextInfo += `\n\nRecent conversation history:\n${recentHistory}\n\n`;
                }
            }
            
            // Create a prompt for new topic suggestions with RAG context
            const basePrompt = `${contextInfo}The user wants to start a new conversation topic that would be relevant and engaging for this specific social setting. Generate ${LLMOptions} conversation starter options that:

- Are appropriate for the current location "${currentThread?.location || 'current setting'}" and activity "${currentThread?.activity || 'current activity'}"
- Would work well when talking with "${currentThread?.people || 'the people present'}"
- Take into account the recent conversation flow and build naturally from it
- Encourage sharing and deeper discussion
- Include options that could lead to learning more about the people present
- Suggest topics that are contextually relevant to the setting and activity
- Provide ways to share relevant personal experiences that others can relate to
- Offer conversation starters that could reveal common interests or experiences

Focus on creating options that feel natural for this specific social context and encourage authentic connection and engagement between everyone present.`;

            const summaryInstruction = SummaryOff ?
                'The "summary" key should contain the exact same FULL text as the "option" key.' :
                'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';

            const newTopicPrompt = `"${basePrompt}". Format as a JSON list with each item having "option" and "summary" keys. ${summaryInstruction}`;

            console.log('Enhanced New Topic prompt with context:', newTopicPrompt);
            console.log('Current thread context:', currentThread);
            console.log('Recent message count for context:', threadMessages.length);
            console.log('Sending enhanced new topic request to LLM...');

            const options = await getLLMResponse(newTopicPrompt);
            console.log('New Topic options received:', options);
            console.log('Number of options:', options.length);
            
            if (options && options.length > 0) {
                // Transform the options to include context about being new topic starters
                const newTopicOptions = options.map(option => ({
                    ...option,
                    isLLMGenerated: true,
                    originatingButtonText: 'New Topic'
                }));
                
                console.log('Transformed new topic options:', newTopicOptions);
                generateThreadButtons(newTopicOptions);
                await announce('Here are some new topic ideas to explore.', "system", false);
            } else {
                console.error('No options returned from LLM');
                await announce('Sorry, I couldn\'t generate new topic options. Please try again.', "system", false);
                startAuditoryScanning();
            }
        } catch (error) {
            console.error('Error generating new topic options:', error);
            await announce('Sorry, I had trouble generating new topic ideas. Please try again.', "system", false);
            startAuditoryScanning();
        } finally {
            document.getElementById('loading-indicator').style.display = 'none';
        }
    });
    gridContainer.appendChild(newTopicButton);

    // Exit Thread button
    const exitThreadButton = document.createElement('button');
    exitThreadButton.textContent = 'Exit Thread';
    exitThreadButton.addEventListener('click', () => {
        stopAuditoryScanning();
        resumeScanningAfterUserAction(); // Resume scanning since button was clicked
        console.log("Thread Exit button clicked");
        window.history.back();
    });
    gridContainer.appendChild(exitThreadButton);
}

// --- Helper function to resume scanning after user action ---
function resumeScanningAfterUserAction() {
    if (waitingForUserAction) {
        console.log("Resuming scanning after user action");
        waitingForUserAction = false;
        // Small delay to ensure UI is updated before starting scan
        setTimeout(() => {
            const buttons = document.querySelectorAll('#gridContainer button:not([style*="display: none"])');
            if (buttons.length > 0) {
                startAuditoryScanning();
            }
        }, 100);
    }
}

// --- Audio Functions ---

async function playAudioToDevice(audioDataBuffer, sampleRate, announcementType) {
    console.log(`Thread playAudioToDevice: Starting playback for type "${announcementType}"`);

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

    if (!audioDataBuffer) {
        console.error('Thread playAudioToDevice: No audio data buffer provided.');
        throw new Error('No audio data buffer provided.');
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        
        // Handle suspended AudioContext (required for Chrome's autoplay policy)
        if (audioContext.state === 'suspended') {
            console.log('Thread AudioContext is suspended, attempting to resume...');
            try {
                await audioContext.resume();
                console.log('Thread AudioContext resumed successfully');
            } catch (resumeError) {
                console.warn("Thread playAudioToDevice: AudioContext resume failed:", resumeError);
                // If AudioContext can't resume, fall back to silent completion
                console.log('Thread playAudioToDevice: Falling back to silent mode due to AudioContext restrictions');
                if (audioContext && audioContext.state !== 'closed') {
                    try {
                        audioContext.close();
                    } catch (closeError) {
                        console.warn('Thread playAudioToDevice: Error closing failed AudioContext:', closeError);
                    }
                }
                return; // Complete silently instead of throwing an error
            }
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

        return new Promise((resolve) => {
            source.onended = () => {
                if (audioContext && audioContext.state !== 'closed') {
                    audioContext.close();
                }
                activeAnnouncementAudioSource = null;
                if (activeAnnouncementAudioContext === audioContext) {
                    activeAnnouncementAudioContext = null;
                }
                resolve();
            };
            
            // Add a timeout fallback in case onended doesn't fire
            setTimeout(() => {
                console.log('Thread playAudioToDevice: Timeout reached, forcing completion');
                if (audioContext && audioContext.state !== 'closed') {
                    try {
                        audioContext.close();
                    } catch (closeError) {
                        console.warn('Thread playAudioToDevice: Error closing AudioContext on timeout:', closeError);
                    }
                }
                if (activeAnnouncementAudioContext === audioContext) {
                    activeAnnouncementAudioContext = null;
                    activeAnnouncementAudioSource = null;
                }
                resolve();
            }, 10000); // 10 second timeout
        });

    } catch (error) {
        console.error('Thread playAudioToDevice: Error:', error);
        if (audioContext && audioContext.state !== 'closed') {
            try {
                audioContext.close();
            } catch (closeError) {
                console.warn('Thread playAudioToDevice: Error closing AudioContext:', closeError);
            }
        }
        if (activeAnnouncementAudioContext === audioContext) {
            activeAnnouncementAudioContext = null;
            activeAnnouncementAudioSource = null;
        }
        // Don't throw error, just complete silently to prevent lockup
        console.log('Thread playAudioToDevice: Completing silently due to audio error');
        return;
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
    const { textToAnnounce, announcementType, recordHistory, resolve, reject } = announcementQueue.shift();

    console.log(`Thread ANNOUNCE QUEUE: Playing "${textToAnnounce.substring(0, 30)}..." (Type: ${announcementType})`);

    // Show splash screen only for personal announcements, not system announcements
    if (typeof showSplashScreen === 'function' && announcementType === 'personal') {
        showSplashScreen(textToAnnounce);
    }

    // Add a timeout to prevent hanging
    const timeoutPromise = new Promise((timeoutResolve) => {
        setTimeout(() => {
            console.warn('Thread ANNOUNCE QUEUE: Timeout reached, forcing completion');
            timeoutResolve();
        }, 15000); // 15 second timeout
    });

    try {
        const response = await authenticatedFetch(`/play-audio`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: textToAnnounce, routing_target: announcementType }),
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
        
        // Race between audio playback and timeout
        await Promise.race([
            playAudioToDevice(audioDataArrayBuffer, sampleRate, announcementType),
            timeoutPromise
        ]);

        resolve();

    } catch (error) {
        console.error('Thread ANNOUNCE QUEUE: Error:', error);
        // Always resolve instead of reject to prevent hanging
        console.log('Thread ANNOUNCE QUEUE: Resolving despite error to prevent lockup');
        resolve();
    } finally {
        isAnnouncingNow = false;
        if (announcementQueue.length > 0) {
            processAnnouncementQueue();
        }
    }
}

async function announce(textToAnnounce, announcementType = "system", recordHistory = true) {
    console.log(`Thread ANNOUNCE: QUEUING "${textToAnnounce.substring(0, 30)}..." (Type: ${announcementType})`);
    
    return new Promise((resolve, reject) => {
        announcementQueue.push({
            textToAnnounce,
            announcementType,
            recordHistory,
            resolve,
            reject
        });

        processAnnouncementQueue();
    });
}

// --- Auditory Scanning Functions ---

function startAuditoryScanning() {
    stopAuditoryScanning();
    if (ScanningOff) {
        console.log("Thread auditory scanning is off.");
        return;
    }
    if (scanMode === 'step') {
        currentButtonIndex = -1;
        scanCycleCount = 0;
        isPausedFromScanLimit = false;
        advanceThreadScanningStep();
        return;
    }
    console.log("Starting thread auditory scanning...");
    
    const buttons = Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
    if (buttons.length === 0) {
        console.log("No visible thread buttons found.");
        currentlyScannedButton = null;
        return;
    }
    
    currentButtonIndex = -1;
    scanCycleCount = 0;
    isPausedFromScanLimit = false;

    const scanStep = async () => {
        if (currentlyScannedButton) {
            currentlyScannedButton.classList.remove('scanning');
        }
        currentButtonIndex++;
        
        if (currentButtonIndex >= buttons.length) {
            currentButtonIndex = 0;
            scanCycleCount++;
            
            if (scanLoopLimit > 0 && scanCycleCount >= scanLoopLimit) {
                console.log(`Thread scan loop limit reached (${scanLoopLimit} cycles). Pausing scanning.`);
                isPausedFromScanLimit = true;
                stopAuditoryScanning();
                
                try {
                    await announce("Scanning paused. Use your switch to resume scanning.", "system", false);
                } catch (e) {
                    console.error("Speech synthesis error:", e);
                }
                
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
            console.log(`Thread scanning button ${currentButtonIndex}:`, buttons[currentButtonIndex].textContent);
            currentlyScannedButton = buttons[currentButtonIndex];
            speakAndHighlight(currentlyScannedButton);
        } else {
            console.warn("Thread: Button not found at index:", currentButtonIndex);
        }
    };
    
    console.log("Thread: Starting scan step with", buttons.length, "buttons, delay:", defaultDelay);
    scanStep();
    scanningInterval = setInterval(scanStep, defaultDelay);
}

function advanceThreadScanningStep() {
    if (ScanningOff || scanMode !== 'step') {
        return;
    }

    const buttons = Array.from(document.querySelectorAll('#gridContainer button:not([style*="display: none"])'));
    if (buttons.length === 0) {
        currentlyScannedButton = null;
        return;
    }

    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning');
    }

    currentButtonIndex = (currentButtonIndex + 1) % buttons.length;
    currentlyScannedButton = buttons[currentButtonIndex];
    speakAndHighlight(currentlyScannedButton);
}

async function speakAndHighlight(button) {
    console.log("Thread speakAndHighlight called for button:", button.textContent);
    
    document.querySelectorAll('#gridContainer button.scanning').forEach(btn => {
        btn.classList.remove('scanning');
    });
    button.classList.add('scanning');
    
    try {
        const textToSpeak = button.textContent;
        console.log("Thread attempting to speak:", textToSpeak);
        // Use backend TTS instead of browser speech synthesis
        await announce(textToSpeak, "system", false);
        console.log("Thread announce() called successfully");
    } catch (e) {
        console.error("Thread speech synthesis error:", e);
    }
}

function stopAuditoryScanning() {
    console.log("Stopping thread auditory scanning.");
    clearInterval(scanningInterval);
    scanningInterval = null;
    if (currentlyScannedButton) {
        currentlyScannedButton.classList.remove('scanning');
        currentlyScannedButton = null;
    }
    currentButtonIndex = -1;
    // Note: No need to cancel speech here as backend TTS handles its own queue
}

// --- Input Handling ---

function setupKeyboardListener() {
    document.addEventListener('keydown', (event) => {
        if (event.code === 'Tab' && scanMode === 'step') {
            event.preventDefault();
            interruptScanningAnnouncementPlayback();

            if (isPausedFromScanLimit) {
                resumeAuditoryScanning();
                return;
            }

            if (waitingForUserAction) {
                waitingForUserAction = false;
                startAuditoryScanning();
                return;
            }

            if (!isLLMProcessing && !listeningForQuestion) {
                if (!currentlyScannedButton) {
                    startAuditoryScanning();
                } else {
                    advanceThreadScanningStep();
                }
            }
            return;
        }

        if (event.code === 'Space') {
            event.preventDefault();
            
            // Check if scanning was paused from scan limit and resume it
            if (isPausedFromScanLimit) {
                console.log("Thread spacebar pressed, resuming scanning from scan limit pause");
                resumeAuditoryScanning();
                return;
            }
            
            // If we're waiting for user action, resume scanning
            if (waitingForUserAction) {
                console.log("Thread spacebar pressed, resuming scanning");
                waitingForUserAction = false;
                startAuditoryScanning();
                return;
            }
            
            // Normal spacebar functionality - match gridpage.js exactly
            if (!isLLMProcessing && !listeningForQuestion && currentlyScannedButton) {
                const buttonToActivate = currentlyScannedButton; // Capture the button reference
                console.log("Thread spacebar pressed, activating button:", buttonToActivate.textContent);
                buttonToActivate.click();
                buttonToActivate.classList.add('active');
                // Use the captured reference in the timeout as well
                setTimeout(() => buttonToActivate?.classList.remove('active'), 150);
            }
        }
    });
    console.log("Thread keyboard listener (Spacebar) set up.");
}

function setupGamepadListeners() {
    window.addEventListener("gamepadconnected", (event) => {
        console.log("Thread gamepad connected:", event.gamepad.index);
        if (gamepadIndex === null) {
            gamepadIndex = event.gamepad.index;
            startGamepadPolling();
        }
    });
    
    window.addEventListener("gamepaddisconnected", (event) => {
        console.log("Thread gamepad disconnected:", event.gamepad.index);
        if (gamepadIndex === event.gamepad.index) {
            gamepadIndex = null;
            stopGamepadPolling();
        }
    });
    
    const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (let i = 0; i < gamepads.length; i++) {
        if (gamepads[i]) {
            console.log("Thread gamepad already connected at index:", i);
            if (gamepadIndex === null) {
                gamepadIndex = i;
                startGamepadPolling();
            }
            break;
        }
    }
}

function startGamepadPolling() {
    if (gamepadPollInterval !== null) return;
    console.log("Starting thread gamepad polling for index:", gamepadIndex);
    let lastButtonState = false;

    function pollGamepads() {
        if (gamepadIndex === null) {
            stopGamepadPolling();
            return;
        }
        const gp = navigator.getGamepads()[gamepadIndex];
        if (!gp) {
            gamepadPollInterval = requestAnimationFrame(pollGamepads);
            return;
        }

        const currentButtonState = gp.buttons[0] && gp.buttons[0].pressed;
        if (currentButtonState && !lastButtonState) {
            const now = Date.now();
            if (now - lastGamepadInputTime > 300) {
                if (!isLLMProcessing && !listeningForQuestion && currentlyScannedButton) {
                    console.log("Thread gamepad button pressed, activating:", currentlyScannedButton.textContent);
                    currentlyScannedButton.click();
                    currentlyScannedButton.classList.add('active');
                    setTimeout(() => currentlyScannedButton?.classList.remove('active'), 150);
                    lastGamepadInputTime = now;
                }
            }
        }
        lastButtonState = currentButtonState;
        gamepadPollInterval = requestAnimationFrame(pollGamepads);
    }
    gamepadPollInterval = requestAnimationFrame(pollGamepads);
}

function stopGamepadPolling() {
    if (gamepadPollInterval !== null) {
        cancelAnimationFrame(gamepadPollInterval);
        gamepadPollInterval = null;
        console.log("Stopped thread gamepad polling.");
    }
}

// --- Admin Toolbar Functionality (copied from gridpage.js) ---

function setupAdminFunctionality() {
    // Add event listeners for the admin toolbar buttons
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

    // PIN Protection for Admin Toolbar
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
}

document.addEventListener('DOMContentLoaded', async () => {
    console.log('Thread page DOMContentLoaded');
    
    // Setup admin functionality
    setupAdminFunctionality();
    
    // Initialize user context
    const userInitialized = await initializeUserContext();
    if (!userInitialized) return;
    
    // Setup input listeners
    setupKeyboardListener();
    setupGamepadListeners();
    
    // Get thread information from current user state instead of URL parameters
    let favoriteName = null;
    try {
        const response = await authenticatedFetch('/get-user-current');
        if (response.ok) {
            const currentState = await response.json();
            console.log('Retrieved current user state:', currentState);
            
            if (currentState.favorite_name && currentState.loaded_at) {
                favoriteName = currentState.favorite_name;
                console.log(`Using loaded favorite from current state: ${favoriteName}`);
            } else {
                console.log('No loaded favorite found in current state');
            }
        }
    } catch (error) {
        console.error('Error retrieving current user state:', error);
    }
    
    if (favoriteName) {
        // Wait for user interaction to initialize audio context
        const initializeAudioAfterInteraction = () => {
            // This will be called after the first user interaction
            document.removeEventListener('click', initializeAudioAfterInteraction);
            document.removeEventListener('keydown', initializeAudioAfterInteraction);
            console.log('User interaction detected, initializing audio context');
        };
        
        document.addEventListener('click', initializeAudioAfterInteraction, { once: true });
        document.addEventListener('keydown', initializeAudioAfterInteraction, { once: true });
        
        // Open thread for the specified favorite
        await openThread(favoriteName);
    } else {
        // No favorite specified - this shouldn't happen normally
        console.error('No favorite name specified for thread');
        await announce('No thread specified. Returning to previous page.', "system", false);
        setTimeout(() => {
            window.history.back();
        }, 3000);
        return;
    }
    
    // Setup speech recognition after a small delay
    setTimeout(() => {
        console.log('Initializing speech recognition with settings:', {
            wakeWordInterjection,
            wakeWordName,
            ScanningOff,
            LLMOptions
        });
        setupSpeechRecognition();
    }, 1000);
    
    console.log('Thread page initialization complete');
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    stopAuditoryScanning();
    stopGamepadPolling();
    if (recognition) {
        recognition.stop();
        recognition = null;
    }
});

// Add scanning styles
if (!document.getElementById('scanning-styles')) {
    const styleSheet = document.createElement("style");
    styleSheet.id = 'scanning-styles';
    styleSheet.textContent = `
        .scanning {
            box-shadow: 0 0 10px 4px #FB4F14 !important;
            outline: none !important;
        }
        .active {
            transform: scale(0.95);
            opacity: 0.8;
        }
        .grid-button-base { }
    `;
    document.head.appendChild(styleSheet);
}
