// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

let dateInput = null;
let entryInput = null;
let saveButton = null;
let dictationButton = null; 
let diaryEntriesDiv = null;
let saveStatus = null;

let recognition; 
let isDictating = false; 

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("user_diary_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        dateInput = document.getElementById('date');
        entryInput = document.getElementById('entry');
        saveButton = document.getElementById('saveButton');
        dictationButton = document.getElementById('dictationButton'); 
        diaryEntriesDiv = document.getElementById('diaryEntries');
        saveStatus = document.getElementById('save-status');
        

        // Basic check for essential elements
        if (!dateInput || !entryInput || !saveButton || !dictationButton || !diaryEntriesDiv || !saveStatus) {
            console.error("CRITICAL ERROR: One or more essential DOM elements for audio_admin.js not found.");
            return;
        }

        // Add Event Listeners
        saveButton.addEventListener('click', SaveDiaryHandler);
        dictationButton.addEventListener('click', dictationButtonHandler); 

        // Initial Data Load
        await loadDiaryEntries();
    }
}


// --- DOMContentLoaded Initialization ---
// Function to display status messages
function showStatus(element, message, isError = false, duration = 3000) {
    if (!element) return;
    element.textContent = message;
    element.style.color = isError ? 'red' : 'green';
    if (duration > 0) {
        setTimeout(() => {
            if (element.textContent === message) { element.textContent = ''; }
        }, duration);
    }
}

// --- Save Entry ---
async function SaveDiaryHandler() {
    const date = dateInput.value;
    const entry = entryInput.value.trim(); // Trim entry

    if (!date) {
        showStatus(saveStatus, "Please select a date.", true);
        dateInput.focus();
        return;
    }
    if (!entry) {
        showStatus(saveStatus, "Entry cannot be empty.", true);
        entryInput.focus();
        return;
    }

    showStatus(saveStatus, "Saving...", false, 0);
    console.log(`Saving entry for date: ${date}`);

    try {
        const response = await window.authenticatedFetch('/api/diary-entry', { // New endpoint
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify({ date, entry }) // Send as JSON object
        });

        if (response.ok) {
            console.log('Diary entry saved successfully.');
            entryInput.value = ''; // Clear entry input after successful save
            // dateInput.value = ''; // Optionally clear date input
            showStatus(saveStatus, "Entry saved successfully!", false);
            loadDiaryEntries(); // Reload entries to show the new/updated one and sorting
        } else {
            const errorText = await response.text();
            console.error('Failed to save diary entry:', response.status, errorText);
            showStatus(saveStatus, `Save failed: ${errorText || response.statusText}`, true);
        }
    } catch (error) {
        console.error('Error saving diary entry:', error);
        showStatus(saveStatus, `Error: ${error.message}`, true);
    }
};

// --- Delete Entry ---
async function deleteEntry(entryId) {
    if (!entryId) {
            console.error("Cannot delete entry without ID.");
            return;
    }
    if (!confirm("Are you sure you want to delete this diary entry?")) {
        return;
    }
    console.log(`Attempting to delete entry with ID: ${entryId}`);
    showStatus(saveStatus, "Deleting...", false, 0);

    try {
        const response = await window.authenticatedFetch(`/api/diary-entry/${entryId}`, { // New endpoint with ID
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' }, 
        });

        if (response.ok) {
            console.log('Diary entry deleted successfully.');
            showStatus(saveStatus, "Entry deleted.", false);
            loadDiaryEntries(); // Refresh the list
        } else {
            const errorText = await response.text();
            console.error('Failed to delete diary entry:', response.status, errorText);
            showStatus(saveStatus, `Delete failed: ${errorText || response.statusText}`, true);
        }
    } catch (error) {
        console.error('Error deleting diary entry:', error);
        showStatus(saveStatus, `Error: ${error.message}`, true);
    }
}


function dictationButtonHandler() { 
    if (!isDictating) {
        startDictation();
    } else {
        stopDictation();
    }
}

function startDictation() {
    recognition = new (window.webkitSpeechRecognition || window.SpeechRecognition)();
    recognition.continuous = true;
    recognition.lang = 'en-US';

    recognition.onstart = function() {
        console.log('Dictation started.');
        dictationButton.textContent = 'Stop Dictation';
        isDictating = true;
    };

    recognition.onresult = function(event) {
        const transcript = event.results[event.results.length - 1][0].transcript;
        entryInput.value += transcript + ' ';
    };

    recognition.onerror = function(event) {
        console.error('Dictation error:', event.error);
        stopDictation();
    };

    recognition.onend = function() {
        console.log('Dictation ended.');
        stopDictation();
    };

    recognition.start();
}

function stopDictation() {
    if (recognition) {
        recognition.stop();
        recognition = null;
    }
    dictationButton.textContent = 'Start Dictation';
    isDictating = false;
}

// --- Load and Display Entries ---
async function loadDiaryEntries() {
    const loadingPara = document.getElementById('loading-entries');
    if (loadingPara) loadingPara.textContent = 'Loading entries...';
    console.log("Loading diary entries...");
    try {
        const response = await window.authenticatedFetch('/api/diary-entries',
            {
                headers: { 'Content-Type': 'application/json' },
            }

        ); // New endpoint

        if (response.ok) {
            const entries = await response.json(); // Expecting JSON array
            // Ensure it's an array before proceeding
            if (Array.isArray(entries)) {
                // Sort entries by date, most recent first
                entries.sort((a, b) => new Date(b.date) - new Date(a.date));
                displayDiaryEntries(entries);
            } else {
                    console.error("Received diary data is not an array:", entries);
                    displayDiaryEntries([]); // Display empty
            }
        } else {
            console.error('Failed to load diary entries:', response.statusText);
            if (loadingPara) loadingPara.textContent = 'Failed to load entries.';
        }
    } catch (error) {
        console.error('Error loading diary entries:', error);
        if (loadingPara) loadingPara.textContent = 'Error loading entries.';
    }
}

function displayDiaryEntries(entries) {
    if (!diaryEntriesDiv) return;
    // Clear previous entries, keeping the title
    diaryEntriesDiv.innerHTML = '<h2>Diary Entries (Most Recent First)</h2>';

    if (entries.length === 0) {
        diaryEntriesDiv.innerHTML += '<p class="text-gray-500">No diary entries found.</p>';
        return;
    }

    entries.forEach(entry => {
        // Validate entry structure
        if (!entry || typeof entry.date !== 'string' || typeof entry.entry !== 'string' || !entry.id) {
            console.warn("Skipping invalid entry object:", entry);
            return; // Skip malformed entries
        }

        const entryDiv = document.createElement('div');
        entryDiv.className = 'diary-entry'; // Apply Tailwind styles via class

        const contentDiv = document.createElement('div');
        contentDiv.className = 'diary-entry-content';
        contentDiv.innerHTML = `<strong>Date:</strong> ${entry.date}<br><strong>Entry:</strong><p>${entry.entry}</p>`; // Use paragraph for entry

        const deleteButton = document.createElement('button');
        deleteButton.innerHTML = '<i class="fas fa-trash-alt"></i>';
        deleteButton.title = 'Delete Entry';
        deleteButton.className = 'button-danger diary-entry-delete-btn'; // Apply Tailwind styles via class
        deleteButton.onclick = () => deleteEntry(entry.id); // Call delete function with entry ID

        entryDiv.appendChild(contentDiv);
        entryDiv.appendChild(deleteButton);
        diaryEntriesDiv.appendChild(entryDiv);
    });
}

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("audio_admin.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}

// --- Admin Toolbar Button Handlers ---
function setupAdminToolbarButtons() {
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
        console.log("user_diary_admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("user_diary_admin.js: Logout button event listener added");
    }
}

// --- Event Listeners ---
// Listener for when the authentication context is ready
document.addEventListener('adminUserContextReady', () => {
    console.log("user_diary_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("user_diary_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("user_diary_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});
