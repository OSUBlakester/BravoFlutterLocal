// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

let userInfoTextarea = null;
let saveInfoButton = null;
let infoSaveStatus = null;

let userBirthdateInput = null;

// Mood related elements
let currentMoodSelect = null;
let saveMoodBtn = null;
let clearMoodBtn = null;
let moodSaveStatus = null;
let friendsFamilyTableBody = null;
let addFriendsFamilyRowButton = null;
let saveFriendsFamilyButton = null;
let friendsFamilySaveStatus = null;
let relationshipModal = null;
let manageRelationshipsBtn = null;
let closeModalBtn = null;
let relationshipsList = null;
let newRelationshipInput = null;
let addRelationshipBtn = null;

// Interview related elements
let startInterviewButton = null;
let startFamilyFriendsInterviewButton = null;

// Custom Images related elements
let customImageFile = null;
let customImagePrimaryTag = null;
let uploadCustomImageBtn = null;
let refreshCustomImagesBtn = null;
let customImagesList = null;
let customImagesStatus = null;
let customImageModal = null;
let modalImagePreview = null;
let modalPrimaryTag = null;
let saveCustomImageBtn = null;
let deleteCustomImageBtn = null;
let closeCustomImageModalBtn = null;

// Profile Image related elements
let userName = null;
let profileImageFile = null;
let uploadProfileImageBtn = null;
let removeProfileImageBtn = null;
let currentProfileImageContainer = null;
let currentProfileImage = null;
let profileImageStatus = null;

// --- State Variables ---
let currentUserInfo = '';
let currentUserName = '';
let currentUserBirthdate = null;
let currentMood = '';
let currentProfileImageData = null;
let initialDataLoaded = false;
let currentAiOptionOverrides = null;

function getDefaultAiOptionOverrides() {
    return {
        exclusions: {
            eatingByMouth: false,
            eatingIndependently: false,
            drinkingByMouth: false,
            drinkingIndependently: false,
            walkingIndependently: false,
            toiletingIndependently: false,
            readingIndependently: false,
            foodAllergies: '',
            environmentalAllergies: ''
        },
        inclusions: {
            profanity: false,
            adultTopics: false,
            adultJokes: false,
            religion: false,
            politics: false
        }
    };
}

// Global state
let currentFriendsFamily = { friends_family: [] };
let editingPersonIndex = null;
let editingGroupIndex = null;

let aiOverridesModal = null;
let openAiOverridesModalBtn = null;
let cancelAiOverridesBtn = null;
let saveAiOverridesBtn = null;
let aiOverridesSaveStatus = null;

// Make currentFriendsFamily available globally for interview system
window.currentFriendsFamily = currentFriendsFamily;


// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("user_info_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        userInfoTextarea = document.getElementById('user-info');
        saveInfoButton = document.getElementById('saveInfoButton');
        infoSaveStatus = document.getElementById('info-save-status');

        // User Birthday Element
        userBirthdateInput = document.getElementById('userBirthdate');

        // Mood Elements
        currentMoodSelect = document.getElementById('currentMood');
        saveMoodBtn = document.getElementById('saveMoodBtn');
        clearMoodBtn = document.getElementById('clearMoodBtn');
        moodSaveStatus = document.getElementById('mood-save-status');

        // Friends & Family Elements
        friendsFamilyTableBody = document.getElementById('friendsFamilyTbody');
        addFriendsFamilyRowButton = document.getElementById('addFriendsFamilyRow');
        saveFriendsFamilyButton = document.getElementById('saveFriendsFamilyButton');
        friendsFamilySaveStatus = document.getElementById('friends-family-save-status');
        
        // Modal Elements
        relationshipModal = document.getElementById('relationshipModal');
        manageRelationshipsBtn = document.getElementById('manageRelationshipsBtn');
        closeModalBtn = document.getElementById('closeModalBtn');
        relationshipsList = document.getElementById('relationshipsList');
        newRelationshipInput = document.getElementById('newRelationship');
        addRelationshipBtn = document.getElementById('addRelationshipBtn');
        
        // Interview Elements
        startInterviewButton = document.getElementById('startInterviewButton');
        startFamilyFriendsInterviewButton = document.getElementById('startFamilyFriendsInterviewBtn');

        // Custom Images Elements
        customImageFile = document.getElementById('customImageFile');
        customImagePrimaryTag = document.getElementById('customImagePrimaryTag');
        uploadCustomImageBtn = document.getElementById('uploadCustomImageBtn');
        refreshCustomImagesBtn = document.getElementById('refreshCustomImagesBtn');
        customImagesList = document.getElementById('customImagesList');
        customImagesStatus = document.getElementById('custom-images-status');
        
        // Custom Image Modal Elements
        customImageModal = document.getElementById('customImageModal');
        modalImagePreview = document.getElementById('modalImagePreview');
        modalPrimaryTag = document.getElementById('modalPrimaryTag');
        saveCustomImageBtn = document.getElementById('saveCustomImageBtn');
        deleteCustomImageBtn = document.getElementById('deleteCustomImageBtn');
        closeCustomImageModalBtn = document.getElementById('closeCustomImageModalBtn');
        
        // Profile Image Elements
        userName = document.getElementById('userName');
        profileImageFile = document.getElementById('profileImageFile');
        uploadProfileImageBtn = document.getElementById('uploadProfileImageBtn');
        removeProfileImageBtn = document.getElementById('removeProfileImageBtn');
        currentProfileImageContainer = document.getElementById('currentProfileImageContainer');
        currentProfileImage = document.getElementById('currentProfileImage');
        profileImageStatus = document.getElementById('profile-image-status');

        // AI Option Overrides Elements
        aiOverridesModal = document.getElementById('aiOverridesModal');
        openAiOverridesModalBtn = document.getElementById('openAiOverridesModalBtn');
        cancelAiOverridesBtn = document.getElementById('cancelAiOverridesBtn');
        saveAiOverridesBtn = document.getElementById('saveAiOverridesBtn');
        aiOverridesSaveStatus = document.getElementById('ai-overrides-save-status');

        // Event Listeners - Thread Groups functionality removed

        // Basic check for essential elements
        if (!userInfoTextarea || !saveInfoButton || !infoSaveStatus || !userBirthdateInput || 
            !currentMoodSelect || !saveMoodBtn || !clearMoodBtn || !moodSaveStatus ||
            !friendsFamilyTableBody || !addFriendsFamilyRowButton || !saveFriendsFamilyButton || 
            !friendsFamilySaveStatus || !relationshipModal || !manageRelationshipsBtn || 
            !closeModalBtn || !relationshipsList || !newRelationshipInput || !addRelationshipBtn) {
            console.error("CRITICAL ERROR: One or more essential DOM elements not found.");
            return;
        }

        // Interview button is optional - it may not exist in all setups
        if (!startInterviewButton) {
            console.log("Note: Interview button not found - interview functionality may not be available");
        }

        // Add Event Listeners
        saveInfoButton.addEventListener('click', saveUserInfoAndBirthday);
        saveMoodBtn.addEventListener('click', saveMood);
        clearMoodBtn.addEventListener('click', clearMood);
        addFriendsFamilyRowButton.addEventListener('click', addFriendsFamilyRow);
        saveFriendsFamilyButton.addEventListener('click', saveFriendsFamily);
        manageRelationshipsBtn.addEventListener('click', openRelationshipModal);
        closeModalBtn.addEventListener('click', closeRelationshipModal);
        addRelationshipBtn.addEventListener('click', addRelationship);
        
        // Chat-derived narrative refresh button
        const refreshChatNarrativeBtn = document.getElementById('refreshChatNarrativeBtn');
        if (refreshChatNarrativeBtn) {
            refreshChatNarrativeBtn.addEventListener('click', loadChatDerivedNarrative);
        }
        
        // Interview button event listeners
        if (startInterviewButton) {
            startInterviewButton.addEventListener('click', startInterview);
        }
        
        if (startFamilyFriendsInterviewButton) {
            startFamilyFriendsInterviewButton.addEventListener('click', startFamilyFriendsInterview);
        }

        // Custom Images event listeners
        if (uploadCustomImageBtn) {
            uploadCustomImageBtn.addEventListener('click', uploadCustomImage);
        }
        if (refreshCustomImagesBtn) {
            refreshCustomImagesBtn.addEventListener('click', loadCustomImages);
        }
        if (saveCustomImageBtn) {
            saveCustomImageBtn.addEventListener('click', saveCustomImageChanges);
        }
        if (deleteCustomImageBtn) {
            deleteCustomImageBtn.addEventListener('click', deleteCustomImage);
        }
        if (closeCustomImageModalBtn) {
            closeCustomImageModalBtn.addEventListener('click', closeCustomImageModal);
        }
        
        // Profile Image event listeners
        if (uploadProfileImageBtn) {
            uploadProfileImageBtn.addEventListener('click', uploadProfileImage);
        }
        if (removeProfileImageBtn) {
            removeProfileImageBtn.addEventListener('click', removeProfileImage);
        }

        if (openAiOverridesModalBtn) {
            openAiOverridesModalBtn.addEventListener('click', openAiOverridesModal);
        }
        if (cancelAiOverridesBtn) {
            cancelAiOverridesBtn.addEventListener('click', closeAiOverridesModal);
        }
        if (saveAiOverridesBtn) {
            saveAiOverridesBtn.addEventListener('click', saveAiOverridesOnly);
        }

        if (aiOverridesModal) {
            aiOverridesModal.addEventListener('click', (e) => {
                if (e.target === aiOverridesModal) {
                    closeAiOverridesModal();
                }
            });
        }

        // Close custom image modal when clicking outside
        if (customImageModal) {
            customImageModal.addEventListener('click', (e) => {
                if (e.target === customImageModal) {
                    closeCustomImageModal();
                }
            });
        }

        console.log("Event listeners added successfully");
        console.log("Save Mood Button:", saveMoodBtn);
        console.log("Clear Mood Button:", clearMoodBtn);
        console.log("Current Mood Select:", currentMoodSelect);

        // Close modal when clicking outside
        relationshipModal.addEventListener('click', (e) => {
            if (e.target === relationshipModal) {
                closeRelationshipModal();
            }
        });

        // Load initial data - but only if auth is ready and not already loaded
        if (window.authenticatedFetch && !initialDataLoaded) {
            console.log("Loading initial data from initializePage...");
            await loadInitialData();
        } else {
            console.log("Waiting for authentication before loading data...");
        }
    }
}

// --- Initial Data Loading ---
async function loadInitialData() {
    if (initialDataLoaded) {
        console.log("Initial data already loaded, skipping...");
        return;
    }
    
    console.log("Loading initial data...");
    initialDataLoaded = true;
    
    try {
        await loadUserInfo();
        await loadFriendsFamily();
        await loadMoodOptions();
        await loadCurrentMood();
        await loadCustomImages();
        await loadChatDerivedNarrative();
        console.log("All initial data loaded successfully");
    } catch (error) {
        console.error("Error loading initial data:", error);
        initialDataLoaded = false; // Reset flag so it can be retried
    }
}

// --- Status Display Helper ---
function showStatus(statusElement, message, isError = false, timeout = 3000) {
    if (!statusElement) return;
    statusElement.textContent = message;
    statusElement.className = isError ? 'text-sm text-red-600 ml-4 h-4 inline-block' : 'text-sm text-green-600 ml-4 h-4 inline-block';
    if (timeout > 0) {
        setTimeout(() => {
            statusElement.textContent = '';
        }, timeout);
    }
}

// --- Mood Functions ---
async function loadMoodOptions() {
    console.log("Loading mood options...");
    
    // Wait for mood-selection.js to load if needed - with better error handling
    let attempts = 0;
    const maxAttempts = 50; // 5 seconds max wait
    while (!window.MOOD_OPTIONS && attempts < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, 100));
        attempts++;
        console.log(`Waiting for MOOD_OPTIONS... attempt ${attempts}/${maxAttempts}`);
    }
    
    // Use global MOOD_OPTIONS from mood-selection.js, or fallback to local array
    const MOOD_OPTIONS = window.MOOD_OPTIONS || [
        { name: 'Happy', emoji: '😊' },
        { name: 'Sad', emoji: '😢' },
        { name: 'Excited', emoji: '🤩' },
        { name: 'Calm', emoji: '😌' },
        { name: 'Angry', emoji: '😠' },
        { name: 'Silly', emoji: '🤪' },
        { name: 'Tired', emoji: '😴' },
        { name: 'Anxious', emoji: '😰' },
        { name: 'Confused', emoji: '😕' },
        { name: 'Surprised', emoji: '😲' },
        { name: 'Proud', emoji: '😎' },
        { name: 'Worried', emoji: '😟' },
        { name: 'Cranky', emoji: '😤' },
        { name: 'Peaceful', emoji: '🕊️' },
        { name: 'Playful', emoji: '😄' },
        { name: 'Frustrated', emoji: '😫' },
        { name: 'Curious', emoji: '🤔' },
        { name: 'Grateful', emoji: '🙏' },
        { name: 'Lonely', emoji: '😔' },
        { name: 'Content', emoji: '😊' }
    ];
    
    if (!window.MOOD_OPTIONS) {
        console.warn("Using fallback mood options - mood-selection.js may not have loaded properly");
    }
    
    console.log("Using mood options:", MOOD_OPTIONS.length, "options");
    
    // Ensure currentMoodSelect exists
    if (!currentMoodSelect) {
        console.error("currentMoodSelect element not found!");
        return;
    }
    
    // Clear existing options except the first one
    currentMoodSelect.innerHTML = '<option value="">No mood selected</option>';
    
    // Add mood options
    MOOD_OPTIONS.forEach(mood => {
        const option = document.createElement('option');
        option.value = mood.name;
        option.textContent = `${mood.emoji} ${mood.name}`;
        currentMoodSelect.appendChild(option);
    });
    
    console.log("Mood options loaded successfully:", currentMoodSelect.options.length, "total options");
}

async function loadCurrentMood() {
    console.log("Loading current mood...");
    showStatus(moodSaveStatus, "Loading...", false, 0);
    
    try {
        const response = await window.authenticatedFetch('/api/user-info', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (response.ok) {
            const data = await response.json();
            currentMood = data.currentMood || '';
            currentMoodSelect.value = currentMood;
            showStatus(moodSaveStatus, "Loaded", false, 2000);
            console.log("Current mood loaded:", currentMood);
        } else {
            throw new Error(`Failed to load current mood: ${response.status}`);
        }
    } catch (error) {
        console.error("Error loading current mood:", error);
        showStatus(moodSaveStatus, "Failed to load mood", true, 5000);
    }
}

async function saveMood() {
    const selectedMood = currentMoodSelect.value;
    console.log("saveMood() called - Selected mood:", selectedMood);
    console.log("currentMoodSelect element:", currentMoodSelect);
    
    showStatus(moodSaveStatus, "Saving...", false, 0);
    
    try {
        // First get current user info to preserve it
        const getCurrentResponse = await window.authenticatedFetch('/api/user-info', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }
        });
        
        let currentUserInfo = "";
        if (getCurrentResponse.ok) {
            const current = await getCurrentResponse.json();
            currentUserInfo = current.userInfo || "";
            console.log("Retrieved current user info for preservation");
        }
        
        console.log("Sending mood save request:", { userInfo: currentUserInfo, currentMood: selectedMood });
        
        // Save mood along with existing user info
        const response = await window.authenticatedFetch('/api/user-info', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userInfo: currentUserInfo,
                currentMood: selectedMood
            })
        });
        
        if (response.ok) {
            currentMood = selectedMood;
            showStatus(moodSaveStatus, "Mood saved successfully", false, 3000);
            console.log("Mood saved successfully:", selectedMood);
            
            // Update session storage as well
            if (selectedMood) {
                sessionStorage.setItem('currentSessionMood', selectedMood);
            } else {
                sessionStorage.removeItem('currentSessionMood');
            }
        } else {
            throw new Error(`Failed to save mood: ${response.status}`);
        }
    } catch (error) {
        console.error("Error saving mood:", error);
        showStatus(moodSaveStatus, "Failed to save mood", true, 5000);
    }
}

async function clearMood() {
    console.log("clearMood() called");
    console.log("Setting currentMoodSelect.value to empty string");
    currentMoodSelect.value = "";
    await saveMood(); // This will save an empty mood
    sessionStorage.removeItem('currentSessionMood');
    console.log("Mood cleared and session storage updated");
}

// --- User Info Functions ---
async function loadUserInfo() {
    console.log("Loading user info...");
    showStatus(infoSaveStatus, "Loading...", false, 0);
    try {
        // Load user info
        const userInfoResponse = await window.authenticatedFetch('/api/user-info', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!userInfoResponse.ok) {
             const errorText = await userInfoResponse.text();
             throw new Error(`User info fetch failed: ${userInfoResponse.status} ${errorText}`);
        }
        const userInfoData = await userInfoResponse.json();
        currentUserInfo = userInfoData.userInfo || '';
        currentUserName = userInfoData.name || '';
        currentAiOptionOverrides = userInfoData.aiOptionOverrides || getDefaultAiOptionOverrides();
        userInfoTextarea.value = currentUserInfo;
        if (userName) {
            userName.value = currentUserName;
        }
        renderAiOverridesToForm();

        // Load birthdate
        const birthdayResponse = await window.authenticatedFetch('/api/birthdays', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!birthdayResponse.ok) {
             const errorText = await birthdayResponse.text();
             throw new Error(`Birthday fetch failed: ${birthdayResponse.status} ${errorText}`);
        }
        const birthdayData = await birthdayResponse.json();
        currentUserBirthdate = birthdayData.userBirthdate || null;
        if (userBirthdateInput) {
            userBirthdateInput.value = currentUserBirthdate || '';
        }

        // Load profile image
        await loadProfileImage();

        console.log("User info, birthday, and profile image loaded.");
        showStatus(infoSaveStatus, "Loaded.", false, 1500);
        
        // Refresh interview data for the current user
        if (window.refreshInterviewForUser) {
            window.refreshInterviewForUser();
        }

    } catch (error) {
        console.error("Error loading user info:", error);
        showStatus(infoSaveStatus, `Error loading: ${error.message}`, true, 5000);
        currentUserInfo = '';
        currentUserBirthdate = null;
        userInfoTextarea.value = '';
        if (userBirthdateInput) {
            userBirthdateInput.value = '';
        }
    }
}

// --- Chat-Derived Narrative Loading ---
async function loadChatDerivedNarrative() {
    console.log("Loading chat-derived narrative...");
    const loadingEl = document.getElementById('chat-narrative-loading');
    const contentSections = [
        'chat-narrative-text-section',
        'chat-facts-section',
        'chat-questions-section',
        'chat-greetings-section'
    ];
    
    try {
        // Show loading
        loadingEl.style.display = 'block';
        contentSections.forEach(id => {
            const el = document.getElementById(id);
            if (el) el.classList.add('hidden');
        });
        
        const response = await window.authenticatedFetch('/api/chat-derived-narrative', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (!response.ok) {
            throw new Error(`Failed to load: ${response.status}`);
        }
        
        const data = await response.json();
        
        // Hide loading
        loadingEl.style.display = 'none';
        
        // Display narrative text
        const narrativeTextEl = document.getElementById('chat-narrative-text');
        if (narrativeTextEl) {
            narrativeTextEl.value = data.narrative_text || '';
            if (data.narrative_text) {
                document.getElementById('chat-narrative-text-section').classList.remove('hidden');
            }
        }
        
        // Display extracted facts
        if (data.extracted_facts && data.extracted_facts.length > 0) {
            document.getElementById('chat-facts-section').classList.remove('hidden');
            document.getElementById('facts-count').textContent = data.extracted_facts.length;
            
            const factsList = document.getElementById('chat-facts-list');
            factsList.innerHTML = data.extracted_facts.map(fact => `
                <div class="bg-white border border-gray-200 rounded px-3 py-2">
                    <div class="text-sm text-gray-800">${fact.fact}</div>
                    <div class="text-xs text-gray-500 mt-1">
                        <span class="inline-flex items-center px-2 py-0.5 rounded-full bg-${fact.category === 'preference' ? 'purple' : 'blue'}-100 text-${fact.category === 'preference' ? 'purple' : 'blue'}-800">
                            ${fact.category}
                        </span>
                        <span class="ml-2">Confidence: ${fact.confidence}</span>
                        ${fact.mention_count > 1 ? `<span class="ml-2">(mentioned ${fact.mention_count}x)</span>` : ''}
                    </div>
                </div>
            `).join('');
        }
        
        // Display answered questions
        const questions = data.answered_questions || {};
        const questionKeys = Object.keys(questions);
        if (questionKeys.length > 0) {
            document.getElementById('chat-questions-section').classList.remove('hidden');
            document.getElementById('questions-count').textContent = questionKeys.length;
            
            const questionsList = document.getElementById('chat-questions-list');
            questionsList.innerHTML = questionKeys.map(key => `
                <div class="bg-white border border-gray-200 rounded px-2 py-1">
                    <span class="font-medium text-gray-700">${key}:</span>
                    <span class="text-gray-600">${questions[key]}</span>
                </div>
            `).join('');
        }
        
        // Display recent greetings
        if (data.recent_greetings && data.recent_greetings.length > 0) {
            document.getElementById('chat-greetings-section').classList.remove('hidden');
            
            const greetingsList = document.getElementById('chat-greetings-list');
            greetingsList.innerHTML = data.recent_greetings.map(greeting => `
                <span class="px-3 py-1 bg-purple-100 text-purple-700 rounded-full text-sm">
                    ${greeting}
                </span>
            `).join('');
        }
        
        // Update metadata
        const updatedDate = data.last_updated ? new Date(data.last_updated).toLocaleString() : 'Never';
        document.getElementById('chat-narrative-updated').textContent = updatedDate;
        document.getElementById('chat-narrative-message-count').textContent = data.source_message_count || 0;
        
        console.log("Chat-derived narrative loaded successfully");
        
    } catch (error) {
        console.error("Error loading chat-derived narrative:", error);
        loadingEl.textContent = 'Error loading narrative';
        loadingEl.style.color = '#ef4444';
    }
}
async function saveUserInfoAndBirthday() {
    console.log("Saving user info and birthday...");
    showStatus(infoSaveStatus, "Saving...", false, 0);

    const userInfo = userInfoTextarea.value;
    const userNameValue = userName ? userName.value : '';
    const userBday = userBirthdateInput ? userBirthdateInput.value : null;

    if (userBday && !/^\d{4}-\d{2}-\d{2}$/.test(userBday)) {
         showStatus(infoSaveStatus, "User Birthdate must be in YYYY-MM-DD format or empty.", true, 5000);
         userBirthdateInput.focus();
         return;
    }

    try {
        // Save user info
        const userInfoResponse = await window.authenticatedFetch('/api/user-info', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify({ 
                userInfo: userInfo,
                name: userNameValue,
                aiOptionOverrides: collectAiOverridesFromForm()
            })
        });
        if (!userInfoResponse.ok) {
             const errorText = await userInfoResponse.text();
             throw new Error(`User info save failed: ${userInfoResponse.status} ${errorText}`);
        }

        // Save birthday
        const birthdayResponse = await window.authenticatedFetch('/api/birthdays', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify({ 
                userBirthdate: userBday || null,
                friendsFamily: [] // Keep existing friends/family data
            })
        });
        if (!birthdayResponse.ok) {
             const errorText = await birthdayResponse.text();
             throw new Error(`Birthday save failed: ${birthdayResponse.status} ${errorText}`);
        }

        currentUserInfo = userInfo;
        currentUserName = userNameValue;
        currentUserBirthdate = userBday;
        console.log("User info, name, and birthday saved successfully.");
        showStatus(infoSaveStatus, "Saved successfully!", false);

    } catch (error) {
        console.error("Error saving user info and birthday:", error);
        showStatus(infoSaveStatus, `Error saving: ${error.message}`, true, 5000);
    }
}

function renderAiOverridesToForm() {
    const overrides = currentAiOptionOverrides || getDefaultAiOptionOverrides();
    const exclusions = overrides.exclusions || {};
    const inclusions = overrides.inclusions || {};

    const checkboxMap = {
        ovr_excl_eatingByMouth: exclusions.eatingByMouth,
        ovr_excl_eatingIndependently: exclusions.eatingIndependently,
        ovr_excl_drinkingByMouth: exclusions.drinkingByMouth,
        ovr_excl_drinkingIndependently: exclusions.drinkingIndependently,
        ovr_excl_walkingIndependently: exclusions.walkingIndependently,
        ovr_excl_toiletingIndependently: exclusions.toiletingIndependently,
        ovr_excl_readingIndependently: exclusions.readingIndependently,
        ovr_inc_profanity: inclusions.profanity,
        ovr_inc_adultTopics: inclusions.adultTopics,
        ovr_inc_adultJokes: inclusions.adultJokes,
        ovr_inc_religion: inclusions.religion,
        ovr_inc_politics: inclusions.politics
    };

    Object.entries(checkboxMap).forEach(([id, value]) => {
        const element = document.getElementById(id);
        if (element) element.checked = value === true;
    });

    const foodAllergiesInput = document.getElementById('ovr_excl_foodAllergies');
    const environmentalAllergiesInput = document.getElementById('ovr_excl_environmentalAllergies');
    if (foodAllergiesInput) foodAllergiesInput.value = exclusions.foodAllergies || '';
    if (environmentalAllergiesInput) environmentalAllergiesInput.value = exclusions.environmentalAllergies || '';
}

function collectAiOverridesFromForm() {
    return {
        exclusions: {
            eatingByMouth: !!document.getElementById('ovr_excl_eatingByMouth')?.checked,
            eatingIndependently: !!document.getElementById('ovr_excl_eatingIndependently')?.checked,
            drinkingByMouth: !!document.getElementById('ovr_excl_drinkingByMouth')?.checked,
            drinkingIndependently: !!document.getElementById('ovr_excl_drinkingIndependently')?.checked,
            walkingIndependently: !!document.getElementById('ovr_excl_walkingIndependently')?.checked,
            toiletingIndependently: !!document.getElementById('ovr_excl_toiletingIndependently')?.checked,
            readingIndependently: !!document.getElementById('ovr_excl_readingIndependently')?.checked,
            foodAllergies: (document.getElementById('ovr_excl_foodAllergies')?.value || '').trim(),
            environmentalAllergies: (document.getElementById('ovr_excl_environmentalAllergies')?.value || '').trim()
        },
        inclusions: {
            profanity: !!document.getElementById('ovr_inc_profanity')?.checked,
            adultTopics: !!document.getElementById('ovr_inc_adultTopics')?.checked,
            adultJokes: !!document.getElementById('ovr_inc_adultJokes')?.checked,
            religion: !!document.getElementById('ovr_inc_religion')?.checked,
            politics: !!document.getElementById('ovr_inc_politics')?.checked
        }
    };
}

function openAiOverridesModal() {
    if (!aiOverridesModal) return;
    if (!currentAiOptionOverrides) {
        currentAiOptionOverrides = getDefaultAiOptionOverrides();
    }
    renderAiOverridesToForm();
    if (aiOverridesSaveStatus) aiOverridesSaveStatus.textContent = '';
    aiOverridesModal.classList.remove('hidden');
}

function closeAiOverridesModal() {
    if (!aiOverridesModal) return;
    aiOverridesModal.classList.add('hidden');
}

async function saveAiOverridesOnly() {
    const overridesToSave = collectAiOverridesFromForm();
    currentAiOptionOverrides = overridesToSave;

    if (aiOverridesSaveStatus) {
        aiOverridesSaveStatus.textContent = 'Saving...';
        aiOverridesSaveStatus.className = 'text-sm text-blue-600';
    }

    try {
        const response = await window.authenticatedFetch('/api/user-info', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userInfo: userInfoTextarea?.value || currentUserInfo || '',
                name: userName?.value || currentUserName || '',
                aiOptionOverrides: overridesToSave
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Save failed: ${response.status} ${errorText}`);
        }

        if (aiOverridesSaveStatus) {
            aiOverridesSaveStatus.textContent = 'Overrides saved.';
            aiOverridesSaveStatus.className = 'text-sm text-green-600';
        }
        setTimeout(() => {
            closeAiOverridesModal();
        }, 500);
    } catch (error) {
        console.error('Error saving AI overrides:', error);
        if (aiOverridesSaveStatus) {
            aiOverridesSaveStatus.textContent = `Error: ${error.message}`;
            aiOverridesSaveStatus.className = 'text-sm text-red-600';
        }
    }
}

// --- Modal Functions ---
function openRelationshipModal() {
    relationshipModal.classList.remove('hidden');
    renderRelationshipsList();
}

function closeRelationshipModal() {
    relationshipModal.classList.add('hidden');
}

// --- Friends & Family Functions ---
function renderRelationshipsList() {
    if (!relationshipsList) return;
    relationshipsList.innerHTML = '';

    currentFriendsFamily.available_relationships.forEach((relationship, index) => {
        const item = document.createElement('div');
        item.className = 'flex items-center justify-between p-2 bg-gray-50 rounded border';
        item.innerHTML = `
            <span class="text-sm">${relationship}</span>
            <button type="button" class="text-red-600 hover:text-red-800" onclick="removeRelationship(${index})">
                <i class="fas fa-times"></i>
            </button>
        `;
        relationshipsList.appendChild(item);
    });
}

function renderFriendsFamilyTable() {
    if (!friendsFamilyTableBody) return;
    friendsFamilyTableBody.innerHTML = '';

    const friendsFamilyList = Array.isArray(currentFriendsFamily.friends_family) ? currentFriendsFamily.friends_family : [];

    friendsFamilyList.forEach((person, index) => {
        const row = document.createElement('tr');
        row.dataset.index = index;

        // Name Cell
        const nameCell = document.createElement('td');
        nameCell.className = 'px-4 py-2';
        const nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.value = person.name || '';
        nameInput.placeholder = 'Name';
        nameInput.className = 'border px-2 py-1 w-full text-sm';
        nameInput.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].name = e.target.value.trim();
        });
        nameCell.appendChild(nameInput);

        // Relationship Cell
        const relationshipCell = document.createElement('td');
        relationshipCell.className = 'px-4 py-2';
        const relationshipSelect = document.createElement('select');
        relationshipSelect.className = 'border px-2 py-1 w-full text-sm relationship-select';
        
        // Add default option
        const defaultOption = document.createElement('option');
        defaultOption.value = '';
        defaultOption.textContent = 'Select...';
        relationshipSelect.appendChild(defaultOption);

        // Add relationship options
        currentFriendsFamily.available_relationships.forEach(rel => {
            const option = document.createElement('option');
            option.value = rel;
            option.textContent = rel;
            if (person.relationship === rel) option.selected = true;
            relationshipSelect.appendChild(option);
        });

        relationshipSelect.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].relationship = e.target.value;
        });
        relationshipCell.appendChild(relationshipSelect);

        // About Cell
        const aboutCell = document.createElement('td');
        aboutCell.className = 'px-4 py-2';
        const aboutTextarea = document.createElement('textarea');
        aboutTextarea.value = person.about || '';
        aboutTextarea.placeholder = 'Background, interests, etc.';
        aboutTextarea.className = 'border px-2 py-1 w-full text-sm resize-none';
        aboutTextarea.rows = 2;
        aboutTextarea.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].about = e.target.value.trim();
        });
        aboutCell.appendChild(aboutTextarea);

        // Birthday Cell
        const birthdayCell = document.createElement('td');
        birthdayCell.className = 'px-4 py-2';
        const birthdayInput = document.createElement('input');
        birthdayInput.type = 'text';
        birthdayInput.value = person.birthday || '';
        birthdayInput.placeholder = 'MM-DD';
        birthdayInput.pattern = '\\d{2}-\\d{2}';
        birthdayInput.maxLength = 5;
        birthdayInput.className = 'border px-2 py-1 w-full text-sm';
        birthdayInput.addEventListener('change', (e) => {
            const value = e.target.value;
            if (value === '' || /^\d{2}-\d{2}$/.test(value)) {
                if (value !== '') {
                    const [month, day] = value.split('-').map(Number);
                    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
                        currentFriendsFamily.friends_family[index].birthday = value;
                    } else {
                        alert('Invalid month or day (MM-DD).');
                        e.target.value = currentFriendsFamily.friends_family[index].birthday || '';
                    }
                } else {
                    currentFriendsFamily.friends_family[index].birthday = '';
                }
            } else {
                alert('Please use MM-DD format (e.g., 05-21)');
                e.target.value = currentFriendsFamily.friends_family[index].birthday || '';
            }
        });
        birthdayCell.appendChild(birthdayInput);

        // Action Cell
        const actionCell = document.createElement('td');
        actionCell.className = 'px-4 py-2';
        const deleteButton = document.createElement('button');
        deleteButton.innerHTML = '<i class="fas fa-trash mr-1"></i>Delete';
        deleteButton.type = 'button';
        deleteButton.className = 'button-danger px-2 py-1 text-xs';
        deleteButton.onclick = () => {
            currentFriendsFamily.friends_family.splice(index, 1);
            renderFriendsFamilyTable();
        };
        actionCell.appendChild(deleteButton);

        row.appendChild(nameCell);
        row.appendChild(relationshipCell);
        row.appendChild(aboutCell);
        row.appendChild(birthdayCell);
        row.appendChild(actionCell);
        friendsFamilyTableBody.appendChild(row);
    });
}

function addFriendsFamilyRow() {
    if (!Array.isArray(currentFriendsFamily.friends_family)) {
        currentFriendsFamily.friends_family = [];
    }
    currentFriendsFamily.friends_family.push({ 
        name: '', 
        relationship: '', 
        about: '', 
        birthday: '' 
    });
    renderFriendsFamilyTable();
    
    // Focus the name input of the new row
    const newRowInput = friendsFamilyTableBody.querySelector(`tr[data-index="${currentFriendsFamily.friends_family.length - 1}"] input[placeholder="Name"]`);
    if (newRowInput) newRowInput.focus();
}

async function loadFriendsFamily() {
    console.log("Loading friends & family...");
    showStatus(friendsFamilySaveStatus, "Loading...", false, 0);
    try {
        const response = await window.authenticatedFetch('/api/friends-family', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Friends & family fetch failed: ${response.status} ${errorText}`);
        }
        const data = await response.json();
        currentFriendsFamily = {
            friends_family: Array.isArray(data.friends_family) ? data.friends_family : [],
            available_relationships: Array.isArray(data.available_relationships) ? data.available_relationships : []
        };
        
        // Update window reference for interview system
        window.currentFriendsFamily = currentFriendsFamily;

        renderRelationshipsList();
        renderFriendsFamilyTable();
        console.log("Friends & family loaded:", currentFriendsFamily);
        showStatus(friendsFamilySaveStatus, "Loaded.", false, 1500);

    } catch (error) {
        console.error("Error loading friends & family:", error);
        showStatus(friendsFamilySaveStatus, `Error loading: ${error.message}`, true, 5000);
        currentFriendsFamily = { friends_family: [], available_relationships: [] };
        // Update window reference for interview system
        window.currentFriendsFamily = currentFriendsFamily;
        renderRelationshipsList();
        renderFriendsFamilyTable();
    }
}

async function saveFriendsFamily() {
    console.log("Saving friends & family...");
    showStatus(friendsFamilySaveStatus, "Saving...", false, 0);

    // Filter out incomplete entries - only name is required
    const validEntries = currentFriendsFamily.friends_family.filter(person => 
        person.name && person.name.trim() !== ''
    );

    const dataToSave = {
        friends_family: validEntries,
        available_relationships: currentFriendsFamily.available_relationships
    };

    try {
        const response = await window.authenticatedFetch('/api/friends-family', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(dataToSave)
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Save failed: ${response.status} ${errorText}`);
        }
        const serverResponse = await response.json();
        console.log("Server returned after save:", serverResponse);
        currentFriendsFamily = serverResponse;
        renderFriendsFamilyTable();

        console.log("Friends & family saved successfully.");
        showStatus(friendsFamilySaveStatus, "Saved successfully!", false);

    } catch (error) {
        console.error("Error saving friends & family:", error);
        showStatus(friendsFamilySaveStatus, `Error saving: ${error.message}`, true, 5000);
    }
}

async function addRelationship() {
    const newRelationship = newRelationshipInput.value.trim();
    if (!newRelationship) {
        alert('Please enter a relationship type.');
        return;
    }

    if (currentFriendsFamily.available_relationships.includes(newRelationship)) {
        alert('This relationship type already exists.');
        return;
    }

    try {
        const response = await window.authenticatedFetch('/api/manage-relationships', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'add',
                relationship: newRelationship
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Add relationship failed: ${response.status} ${errorText}`);
        }

        const data = await response.json();
        currentFriendsFamily.available_relationships = data.available_relationships;
        // Update window reference for interview system
        window.currentFriendsFamily = currentFriendsFamily;
        newRelationshipInput.value = '';
        renderRelationshipsList();
        renderFriendsFamilyTable(); // Re-render to update dropdowns

    } catch (error) {
        console.error("Error adding relationship:", error);
        alert(`Error adding relationship: ${error.message}`);
    }
}

async function removeRelationship(index) {
    const relationship = currentFriendsFamily.available_relationships[index];
    if (!relationship) return;

    if (!confirm(`Remove "${relationship}" from available relationships?`)) return;

    try {
        const response = await window.authenticatedFetch('/api/manage-relationships', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'remove',
                relationship: relationship
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Remove relationship failed: ${response.status} ${errorText}`);
        }

        const data = await response.json();
        currentFriendsFamily.available_relationships = data.available_relationships;
        // Update window reference for interview system
        window.currentFriendsFamily = currentFriendsFamily;
        renderRelationshipsList();
        renderFriendsFamilyTable(); // Re-render to update dropdowns

    } catch (error) {
        console.error("Error removing relationship:", error);
        alert(`Error removing relationship: ${error.message}`);
    }
}

// --- Interview Functions ---
function startInterview() {
    console.log("Starting comprehensive user interview...");
    
    // Check if the AudioInterviewSystem is available
    if (typeof AudioInterviewSystem === 'undefined') {
        console.error("AudioInterviewSystem not available");
        alert("Interview system is not available. Please refresh the page and try again.");
        return;
    }
    
    // Initialize and start the interview system
    try {
        // Use existing interview system instance or create one
        const interviewSystem = window.audioInterviewSystem || window.interviewSystem;
        if (!interviewSystem) {
            window.interviewSystem = new AudioInterviewSystem();
        }
        
        // Open the interview modal using the correct method name
        const systemToUse = window.audioInterviewSystem || window.interviewSystem;
        systemToUse.openInterviewModal();
        
    } catch (error) {
        console.error("Error starting interview:", error);
        alert("There was an error starting the interview. Please try again.");
    }
}

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("user_info_admin.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}

// --- Admin Toolbar Button Handlers ---
function setupAdminToolbarButtons() {
    const switchUserButton = document.getElementById('switch-user-button');
    const logoutButton = document.getElementById('logout-button');

    function handleSwitchUser() {
        console.log("Switching user profile. Clearing session and redirecting to auth page for profile selection.");
        
        // Reset interview system for new user
        if (window.audioInterviewSystem) {
            window.audioInterviewSystem.resetForNewUser();
        }
        
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
        
        // Reset interview system for logout
        if (window.audioInterviewSystem) {
            window.audioInterviewSystem.resetForNewUser();
        }
        
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
        console.log("user_info_admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("user_info_admin.js: Logout button event listener added");
    }
}

// --- Event Listeners ---
document.addEventListener('adminUserContextReady', () => {
    console.log("user_info_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("user_info_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

// --- Custom Images Functions ---
async function uploadCustomImage() {
    console.log("Uploading custom image...");
    
    if (!customImageFile.files[0]) {
        showStatus(customImagesStatus, "Please select an image file", true, 3000);
        return;
    }
    
    if (!customImagePrimaryTag.value.trim()) {
        showStatus(customImagesStatus, "Please enter a primary tag", true, 3000);
        return;
    }
    
    try {
        showStatus(customImagesStatus, "Uploading...", false, 0);
        
        const formData = new FormData();
        formData.append('image', customImageFile.files[0]);
        formData.append('concept', 'custom'); // Simple concept for custom images
        formData.append('subconcept', customImagePrimaryTag.value.trim());
        formData.append('tags', ''); // No additional tags in simplified version
        
        const response = await window.authenticatedFetch('/api/upload_custom_image', {
            method: 'POST',
            body: formData
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Upload failed: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log("Upload successful:", result);
        
        // Clear form
        customImageFile.value = '';
        customImagePrimaryTag.value = '';
        
        showStatus(customImagesStatus, "Image uploaded successfully!", false, 3000);
        
        // Reload images list
        await loadCustomImages();
        
    } catch (error) {
        console.error("Error uploading image:", error);
        showStatus(customImagesStatus, `Upload failed: ${error.message}`, true, 5000);
    }
}

async function loadCustomImages() {
    console.log("Loading custom images...");
    
    try {
        const response = await window.authenticatedFetch('/api/get_custom_images', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Failed to load images: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log("Custom images loaded:", result);
        
        displayCustomImages(result.images || []);
        
    } catch (error) {
        console.error("Error loading custom images:", error);
        showStatus(customImagesStatus, `Failed to load images: ${error.message}`, true, 3000);
    }
}

function displayCustomImages(images) {
    if (!customImagesList) return;
    
    if (images.length === 0) {
        customImagesList.innerHTML = `
            <div class="text-center text-gray-500 col-span-full">
                <i class="fas fa-images text-4xl mb-2"></i>
                <p>No custom images uploaded yet</p>
            </div>
        `;
        return;
    }
    
    customImagesList.innerHTML = images.map(image => `
        <div class="relative group cursor-pointer" onclick="editCustomImage('${image.id}', '${image.image_url}', '${image.subconcept}')">
            <img src="${image.image_url}" alt="${image.subconcept}" class="w-full h-24 object-cover rounded border hover:shadow-lg transition-shadow">
            <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-30 rounded flex items-center justify-center transition-all">
                <i class="fas fa-edit text-white opacity-0 group-hover:opacity-100 transition-opacity"></i>
            </div>
            <p class="text-xs text-center mt-1 truncate">${image.subconcept}</p>
        </div>
    `).join('');
}

function editCustomImage(imageId, imageUrl, primaryTag) {
    if (!customImageModal) return;
    
    // Store current image id for saving/deleting
    customImageModal.dataset.imageId = imageId;
    
    // Set modal content
    modalImagePreview.src = imageUrl;
    modalPrimaryTag.value = primaryTag;
    
    // Show modal
    customImageModal.classList.remove('hidden');
}

async function saveCustomImageChanges() {
    console.log("Saving custom image changes...");
    
    const imageId = customImageModal.dataset.imageId;
    const primaryTag = modalPrimaryTag.value.trim();
    
    if (!primaryTag) {
        alert("Please enter a primary tag");
        return;
    }
    
    try {
        const response = await window.authenticatedFetch('/api/update_custom_image', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                image_id: imageId,
                concept: 'custom',
                subconcept: primaryTag,
                tags: []
            })
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Update failed: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log("Image updated successfully:", result);
        
        // Close modal and refresh
        closeCustomImageModal();
        await loadCustomImages();
        
        showStatus(customImagesStatus, "Image updated successfully!", false, 3000);
        
    } catch (error) {
        console.error("Error updating image:", error);
        alert(`Failed to update image: ${error.message}`);
    }
}

async function deleteCustomImage() {
    const imageId = customImageModal.dataset.imageId;
    
    if (!confirm("Are you sure you want to delete this image? This action cannot be undone.")) {
        return;
    }
    
    console.log("Deleting custom image...");
    
    try {
        const response = await window.authenticatedFetch(`/api/delete_custom_image/${imageId}`, {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Delete failed: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log("Image deleted successfully:", result);
        
        // Close modal and refresh
        closeCustomImageModal();
        await loadCustomImages();
        
        showStatus(customImagesStatus, "Image deleted successfully!", false, 3000);
        
    } catch (error) {
        console.error("Error deleting image:", error);
        alert(`Failed to delete image: ${error.message}`);
    }
}

function closeCustomImageModal() {
    if (customImageModal) {
        customImageModal.classList.add('hidden');
        customImageModal.dataset.imageId = '';
        modalImagePreview.src = '';
        modalPrimaryTag.value = '';
    }
}

// --- Profile Image Functions ---
async function loadProfileImage() {
    console.log("Loading profile image...");
    
    try {
        const response = await window.authenticatedFetch('/api/get_profile_image', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (response.ok) {
            const result = await response.json();
            currentProfileImageData = result.profile_image;
            
            if (currentProfileImageData && currentProfileImageData.image_url) {
                // Show current profile image
                if (currentProfileImage && currentProfileImageContainer) {
                    currentProfileImage.src = currentProfileImageData.image_url;
                    currentProfileImageContainer.style.display = 'block';
                }
                console.log("Profile image loaded:", currentProfileImageData.image_url);
            } else {
                // No profile image set
                if (currentProfileImageContainer) {
                    currentProfileImageContainer.style.display = 'none';
                }
                currentProfileImageData = null;
                console.log("No profile image set");
            }
        } else if (response.status === 404) {
            // No profile image found - this is normal
            if (currentProfileImageContainer) {
                currentProfileImageContainer.style.display = 'none';
            }
            currentProfileImageData = null;
        } else {
            const errorText = await response.text();
            console.error("Error loading profile image:", response.status, errorText);
        }
        
    } catch (error) {
        console.error("Error loading profile image:", error);
    }
}

async function uploadProfileImage() {
    console.log("Uploading profile image...");
    
    if (!profileImageFile || !profileImageFile.files[0]) {
        showStatus(profileImageStatus, "Please select an image file", true, 3000);
        return;
    }
    
    if (!userName || !userName.value.trim()) {
        alert('Please enter a user name and click "Save User Name, Info & Birthday" before uploading a profile picture.\n\nThe name must be saved first so the profile picture can be properly tagged.');
        showStatus(profileImageStatus, "Please save a user name first", true, 5000);
        return;
    }
    
    try {
        showStatus(profileImageStatus, "Uploading...", false, 0);
        
        const formData = new FormData();
        formData.append('image', profileImageFile.files[0]);
        
        const response = await window.authenticatedFetch('/api/upload_user_profile_image', {
            method: 'POST',
            body: formData
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            // Check for the server-side "name not set" error
            if (response.status === 400 && errorText.includes('name')) {
                alert('Please set a user name and click "Save User Name, Info & Birthday" before uploading a profile picture.\n\nThe name must be saved to the server first.');
                showStatus(profileImageStatus, "Please save a user name first", true, 5000);
                return;
            }
            throw new Error(`Upload failed: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log("Profile image upload successful:", result);
        
        // Clear form
        profileImageFile.value = '';
        
        showStatus(profileImageStatus, "Profile image uploaded successfully!", false, 3000);
        
        // Reload profile image
        await loadProfileImage();
        
    } catch (error) {
        console.error("Error uploading profile image:", error);
        showStatus(profileImageStatus, `Upload failed: ${error.message}`, true, 5000);
    }
}

async function removeProfileImage() {
    console.log("Removing profile image...");
    
    if (!currentProfileImageData) {
        showStatus(profileImageStatus, "No profile image to remove", true, 3000);
        return;
    }
    
    try {
        showStatus(profileImageStatus, "Removing...", false, 0);
        
        const response = await window.authenticatedFetch('/api/remove_profile_image', {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Remove failed: ${response.status} ${errorText}`);
        }
        
        console.log("Profile image removed successfully");
        
        showStatus(profileImageStatus, "Profile image removed successfully!", false, 3000);
        
        // Hide current image display
        if (currentProfileImageContainer) {
            currentProfileImageContainer.style.display = 'none';
        }
        currentProfileImageData = null;
        
    } catch (error) {
        console.error("Error removing profile image:", error);
        showStatus(profileImageStatus, `Remove failed: ${error.message}`, true, 5000);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("user_info_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});

// Listen for authentication context ready event
document.addEventListener('adminUserContextReady', async () => {
    console.log("user_info_admin.js: Authentication context ready.");
    isAuthContextReady = true;
    
    // Load data now that auth is ready
    if (isDomContentLoaded && window.authenticatedFetch && !initialDataLoaded) {
        console.log("Loading user data after auth ready...");
        await loadInitialData();
    }
});
