// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;


// DOM Elements - declare with 'let', assign in initializePage
let locationInput = null;
let peopleInput = null;
let activityInput = null;
let saveButton = null;
let dictationButton = null;

// Favorites DOM elements
let favoritesSelect = null;
let loadFavoriteBtn = null;
let openThreadBtn = null;
let addToFavoritesBtn = null;
let manageFavoritesBtn = null;
let manageFavoritesModal = null;
let closeManageFavoritesModal = null;
let addFavoriteModal = null;
let closeAddFavoriteModal = null;
let favoriteName = null;
let cancelAddFavorite = null;
let confirmAddFavorite = null;
let favoritesManagementList = null;

// Schedule DOM elements
let scheduleEnabled = null;
let scheduleFields = null;
let scheduleDaysContainer = null; // Container for checkboxes
let scheduleStartTime = null;
let scheduleEndTime = null;
let editingFavoriteName = null; // To track if we are editing


// Utility function to display status messages
function showStatus(message, isError = false, duration = 3000) {
    // Assuming you'll add a status element to your HTML, e.g., <p id="status-message"></p>
    const statusElement = document.getElementById('status-message'); // Make sure this ID exists in your HTML
    if (statusElement) {
        statusElement.textContent = message;
        statusElement.style.color = isError ? 'red' : 'green';
        if (duration > 0) {
            setTimeout(() => {
                if (statusElement.textContent === message) statusElement.textContent = '';
            }, duration);
        }
    } else { console.log(`Status (${isError ? 'Error' : 'Info'}): ${message}`); }
}

// Function to load current user state
async function loadCurrentUserState() {
    showStatus("Loading current state...", false, 0);
    try {
        // Use the existing GET endpoint from server.py
        const response = await window.authenticatedFetch('/get-user-current'); // No body/headers needed for GET
        if (!response.ok) throw new Error(`Failed to load: ${response.statusText}`);
        const data = await response.json();
        locationInput.value = data.location || '';
        peopleInput.value = data.people || '';
        activityInput.value = data.activity || '';
        
        // Check if there's a loaded favorite and enable thread button if so
        if (data.favorite_name && data.loaded_at && openThreadBtn) {
            openThreadBtn.disabled = false;
            openThreadBtn.setAttribute('data-favorite-name', data.favorite_name);
            console.log(`Thread button enabled for loaded favorite: ${data.favorite_name}`);
        }
        
        showStatus("Current state loaded.", false);
    } catch (error) {
        console.error('Error loading user current state:', error);
        showStatus(`Error loading state: ${error.message}`, true);
    }
}

// Function to load favorites
async function loadFavorites() {
    console.log("loadFavorites() called");
    try {
        console.log("Calling /api/user-current-favorites");
        const response = await window.authenticatedFetch('/api/user-current-favorites');
        console.log("Response received:", response.status, response.statusText);
        if (!response.ok) throw new Error(`Failed to load favorites: ${response.statusText}`);
        const data = await response.json();
        console.log("Favorites data:", data);
        
        // Populate the favorites dropdown
        favoritesSelect.innerHTML = '<option value="">Choose a favorite...</option>';
        data.favorites.forEach(favorite => {
            const option = document.createElement('option');
            option.value = JSON.stringify(favorite);
            option.textContent = favorite.name;
            favoritesSelect.appendChild(option);
        });
        
        console.log("Dropdown populated with", data.favorites.length, "favorites");
        
        // Update load button state
        updateLoadButtonState();
        
    } catch (error) {
        console.error('Error loading favorites:', error);
        showStatus(`Error loading favorites: ${error.message}`, true);
    }
}

// Function to update load button state
function updateLoadButtonState() {
    loadFavoriteBtn.disabled = !favoritesSelect.value;
}

// Function to update open thread button state - only enabled if a favorite was loaded recently
function updateOpenThreadButtonState() {
    // This will be called after loading favorites or checking current state
    // For now, we'll enable it based on the current state having a loaded favorite
    // The real validation will be done server-side
    openThreadBtn.disabled = true; // Default to disabled, will be enabled when we detect a loaded favorite
}

// Function to load selected favorite and automatically save
async function loadSelectedFavorite() {
    console.log("loadSelectedFavorite() called");
    const selectedValue = favoritesSelect.value;
    console.log("Selected value:", selectedValue);
    if (!selectedValue) return;
    
    try {
        const favorite = JSON.parse(selectedValue);
        console.log("Parsed favorite:", favorite);
        
        // Update the form fields
        locationInput.value = favorite.location || '';
        peopleInput.value = favorite.people || '';
        activityInput.value = favorite.activity || '';
        
        // Automatically save the loaded data to the database
        const loadTimestamp = new Date().toISOString(); // Use same timestamp for both loaded_at and saved_at
        const saveData = {
            location: favorite.location || '',
            people: favorite.people || '',
            activity: favorite.activity || '',
            loaded_at: loadTimestamp,  // Timestamp when favorite is loaded
            favorite_name: favorite.name,  // Include the favorite name for tracking
            saved_at: loadTimestamp  // Use same timestamp to indicate this save is part of loading, not manual
        };
        
        const response = await window.authenticatedFetch('/user_current', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(saveData)
        });
        
        if (response.ok) {
            showStatus(`Loaded and saved favorite: ${favorite.name}`, false);
            // Enable the Open Thread button since we just loaded a favorite
            openThreadBtn.disabled = false;
            // Store the loaded favorite name for the thread functionality
            openThreadBtn.setAttribute('data-favorite-name', favorite.name);
        } else {
            showStatus(`Loaded favorite: ${favorite.name} (but failed to auto-save)`, true);
        }
        
    } catch (error) {
        console.error('Error loading favorite:', error);
        showStatus('Error loading selected favorite', true);
    }
}

// Function to open thread for the loaded favorite
async function openThreadForLoadedFavorite() {
    console.log("openThreadForLoadedFavorite() called");
    
    const favoriteName = openThreadBtn.getAttribute('data-favorite-name');
    if (!favoriteName) {
        showStatus('No favorite loaded. Please load a favorite first.', true);
        return;
    }
    
    try {
        // Navigate to the threads page with the favorite name as a parameter
        const encodedFavoriteName = encodeURIComponent(favoriteName);
        window.location.href = `/static/threads.html?favorite=${encodedFavoriteName}`;
    } catch (error) {
        console.error('Error opening thread:', error);
        showStatus('Error opening thread for favorite', true);
    }
}

// Function to show add favorite modal
function showAddFavoriteModal() {
    console.log("showAddFavoriteModal() called");
    editingFavoriteName = null; // Reset editing state
    
    // Update preview with current values
    document.getElementById('favoritePreviewLocation').textContent = `Location: ${locationInput.value || '(empty)'}`;
    document.getElementById('favoritePreviewPeople').textContent = `People: ${peopleInput.value || '(empty)'}`;
    document.getElementById('favoritePreviewActivity').textContent = `Activity: ${activityInput.value || '(empty)'}`;
    
    // Clear the name input
    favoriteName.value = '';
    
    // Reset schedule fields
    scheduleEnabled.checked = false;
    scheduleFields.classList.add('opacity-50', 'pointer-events-none');
    // Uncheck all days
    const checkboxes = scheduleDaysContainer.querySelectorAll('input[type="checkbox"]');
    checkboxes.forEach(cb => cb.checked = false);
    
    scheduleStartTime.value = '';
    scheduleEndTime.value = '';
    
    // Update modal title and button text
    document.querySelector('#addFavoriteModal h3').textContent = 'Add to Favorites';
    confirmAddFavorite.textContent = 'Save Favorite';

    // Show modal
    addFavoriteModal.classList.remove('hidden');
    favoriteName.focus();
}

// Function to save favorite
async function saveFavorite() {
    const name = favoriteName.value.trim();
    if (!name) {
        showStatus('Please enter a name for the favorite', true);
        return;
    }
    
    // Construct the favorite object
    const favoriteData = {
        name: name,
        location: locationInput.value || '',
        people: peopleInput.value || '',
        activity: activityInput.value || ''
    };

    // Add schedule if enabled
    if (scheduleEnabled.checked) {
        if (!scheduleStartTime.value || !scheduleEndTime.value) {
            showStatus('Please enter start and end times for the schedule', true);
            return;
        }
        
        // Collect selected days
        const selectedDays = [];
        const checkboxes = scheduleDaysContainer.querySelectorAll('input[type="checkbox"]:checked');
        checkboxes.forEach(cb => selectedDays.push(cb.value));
        
        if (selectedDays.length === 0) {
            showStatus('Please select at least one day for the schedule', true);
            return;
        }

        favoriteData.schedule = {
            enabled: true,
            days_of_week: selectedDays,
            start_time: scheduleStartTime.value,
            end_time: scheduleEndTime.value
        };
    } else {
        favoriteData.schedule = null;
    }
    
    try {
        let response;
        if (editingFavoriteName) {
            // We are editing an existing favorite
            // Use the manage endpoint with 'edit' action
            // Note: For edit, we might want to preserve the location/people/activity if the user didn't change them
            // But here we are taking the current values from the inputs (which might be from the loaded favorite or current state)
            // Wait, if we are editing, we should probably have populated the inputs with the favorite's data first.
            // Let's assume editFavorite does that.
            
            // However, the current UI design for "Add Favorite" takes the *current* state values.
            // If we reuse this modal for editing, we should probably allow editing the location/people/activity too, 
            // or at least keep the existing ones if we don't want to overwrite them with current state.
            // But the modal shows "Current Values". 
            
            // If we are in "Edit" mode, we should probably NOT use the current state values for the preview, 
            // but rather the values from the favorite being edited.
            // But the modal structure is "Current Values: ...". 
            
            // Let's stick to the plan: "Add/Edit Favorite". 
            // If editing, we are updating the favorite with the *current* form values (name, schedule) 
            // AND potentially the location/people/activity.
            
            // Actually, `editFavorite` in the previous implementation used `prompt` to ask for new values.
            // If we use this modal, we are effectively saying "Update this favorite with these settings".
            // But the "Current Values" section is read-only text based on `locationInput`, etc.
            
            // If I want to allow editing the schedule of an existing favorite WITHOUT changing its location/people/activity to the current state,
            // I would need to populate `locationInput` etc. with the favorite's data when opening the modal.
            // That's what `loadSelectedFavorite` does.
            
            // So, `editFavorite` should:
            // 1. Load the favorite data into the main form inputs (location, people, activity).
            // 2. Open the modal with the favorite's name and schedule.
            
            response = await window.authenticatedFetch('/api/user-current-favorites/manage', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    action: 'edit',
                    old_name: editingFavoriteName,
                    favorite: favoriteData
                })
            });
        } else {
            // Creating a new favorite
            response = await window.authenticatedFetch('/api/user-current-favorites', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(favoriteData)
            });
        }
        
        const result = await response.json();
        if (result.success) {
            showStatus(result.message, false);
            addFavoriteModal.classList.add('hidden');
            await showManageFavoritesModal(); // Refresh the management list if it was open
            await loadFavorites(); // Refresh the dropdown
        } else {
            showStatus(result.message, true);
        }
    } catch (error) {
        console.error('Error saving favorite:', error);
        showStatus('Error saving favorite', true);
    }
}

let currentFavoritesList = []; // Store loaded favorites for editing

// Function to show manage favorites modal
async function showManageFavoritesModal() {
    console.log("showManageFavoritesModal() called");
    try {
        const response = await window.authenticatedFetch('/api/user-current-favorites');
        if (!response.ok) throw new Error(`Failed to load favorites: ${response.statusText}`);
        const data = await response.json();
        console.log("Management modal favorites data:", data);
        
        currentFavoritesList = data.favorites; // Store for access in editFavorite
        
        // Populate the management list
        favoritesManagementList.innerHTML = '';
        
        if (data.favorites.length === 0) {
            favoritesManagementList.innerHTML = '<p class="text-gray-500 text-center py-4">No favorites saved yet.</p>';
        } else {
            data.favorites.forEach(favorite => {
                // Format schedule string for display
                let scheduleInfo = '<span class="text-gray-400 italic">No schedule</span>';
                if (favorite.schedule && favorite.schedule.enabled) {
                    // Handle both old single day and new multiple days format for backward compatibility
                    let daysDisplay = '';
                    if (favorite.schedule.days_of_week && Array.isArray(favorite.schedule.days_of_week)) {
                        daysDisplay = favorite.schedule.days_of_week.map(d => d.substring(0, 3)).join(', ');
                    } else if (favorite.schedule.day_of_week) {
                        daysDisplay = favorite.schedule.day_of_week;
                    }
                    
                    scheduleInfo = `<span class="text-green-600"><i class="fas fa-clock mr-1"></i>${daysDisplay} ${favorite.schedule.start_time} - ${favorite.schedule.end_time}</span>`;
                }

                const favoriteDiv = document.createElement('div');
                favoriteDiv.className = 'border border-gray-200 rounded-lg p-4';
                favoriteDiv.innerHTML = `
                    <div class="flex justify-between items-start">
                        <div class="flex-1">
                            <h4 class="font-medium text-gray-800 mb-1">${favorite.name}</h4>
                            <div class="text-sm mb-2">${scheduleInfo}</div>
                            <p class="text-sm text-gray-600">Location: ${favorite.location || '(empty)'}</p>
                            <p class="text-sm text-gray-600">People: ${favorite.people || '(empty)'}</p>
                            <p class="text-sm text-gray-600">Activity: ${favorite.activity || '(empty)'}</p>
                        </div>
                        <div class="flex gap-2 ml-4">
                            <button onclick="editFavorite('${favorite.name.replace(/'/g, "\\'")}')" class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-sm">
                                Edit
                            </button>
                            <button onclick="deleteFavorite('${favorite.name.replace(/'/g, "\\'")}')" class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded text-sm">
                                Delete
                            </button>
                        </div>
                    </div>
                `;
                favoritesManagementList.appendChild(favoriteDiv);
            });
        }
        
        manageFavoritesModal.classList.remove('hidden');
        console.log("Management modal shown");
    } catch (error) {
        console.error('Error loading favorites for management:', error);
        showStatus('Error loading favorites', true);
    }
}

// Function to edit favorite
async function editFavorite(favoriteName) {
    const favorite = currentFavoritesList.find(f => f.name === favoriteName);
    if (!favorite) {
        showStatus('Favorite not found', true);
        return;
    }

    editingFavoriteName = favoriteName; // Set editing state

    // Populate the main form inputs temporarily for the preview
    // Note: This doesn't change the actual saved state on the server, just the inputs on the page
    // which are used for the "Current Values" preview in the modal.
    // Ideally, we should have separate inputs in the modal for editing these values, 
    // but reusing the "Add" modal structure implies we use the page inputs.
    locationInput.value = favorite.location || '';
    peopleInput.value = favorite.people || '';
    activityInput.value = favorite.activity || '';

    // Update preview with these values
    document.getElementById('favoritePreviewLocation').textContent = `Location: ${locationInput.value || '(empty)'}`;
    document.getElementById('favoritePreviewPeople').textContent = `People: ${peopleInput.value || '(empty)'}`;
    document.getElementById('favoritePreviewActivity').textContent = `Activity: ${activityInput.value || '(empty)'}`;

    // Populate name
    document.getElementById('favoriteName').value = favorite.name;

    // Populate schedule
    if (favorite.schedule && favorite.schedule.enabled) {
        scheduleEnabled.checked = true;
        scheduleFields.classList.remove('opacity-50', 'pointer-events-none');
        
        // Reset checkboxes first
        const checkboxes = scheduleDaysContainer.querySelectorAll('input[type="checkbox"]');
        checkboxes.forEach(cb => cb.checked = false);
        
        // Check appropriate boxes
        if (favorite.schedule.days_of_week && Array.isArray(favorite.schedule.days_of_week)) {
            favorite.schedule.days_of_week.forEach(day => {
                const cb = scheduleDaysContainer.querySelector(`input[value="${day}"]`);
                if (cb) cb.checked = true;
            });
        } else if (favorite.schedule.day_of_week) {
            // Backward compatibility
            const cb = scheduleDaysContainer.querySelector(`input[value="${favorite.schedule.day_of_week}"]`);
            if (cb) cb.checked = true;
        }
        
        scheduleStartTime.value = favorite.schedule.start_time;
        scheduleEndTime.value = favorite.schedule.end_time;
    } else {
        scheduleEnabled.checked = false;
        scheduleFields.classList.add('opacity-50', 'pointer-events-none');
        // Uncheck all
        const checkboxes = scheduleDaysContainer.querySelectorAll('input[type="checkbox"]');
        checkboxes.forEach(cb => cb.checked = false);
        
        scheduleStartTime.value = '';
        scheduleEndTime.value = '';
    }

    // Update modal title and button text
    document.querySelector('#addFavoriteModal h3').textContent = 'Edit Favorite';
    confirmAddFavorite.textContent = 'Update Favorite';

    // Show modal (and hide management modal temporarily if needed, but they can stack)
    // Stacking might be confusing if not handled well with z-index, but let's try.
    // Or we can close the management modal.
    manageFavoritesModal.classList.add('hidden');
    addFavoriteModal.classList.remove('hidden');
    document.getElementById('favoriteName').focus();
}

// Function to delete favorite
async function deleteFavorite(favoriteName) {
    if (!confirm(`Are you sure you want to delete the favorite "${favoriteName}"?`)) return;
    
    try {
        const response = await window.authenticatedFetch('/api/user-current-favorites/manage', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'delete',
                old_name: favoriteName
            })
        });
        
        const result = await response.json();
        if (result.success) {
            showStatus(result.message, false);
            await showManageFavoritesModal(); // Refresh the modal
            await loadFavorites(); // Refresh the dropdown
        } else {
            showStatus(result.message, true);
        }
    } catch (error) {
        console.error('Error deleting favorite:', error);
        showStatus('Error deleting favorite', true);
    }
}

// Make functions available globally for onclick handlers
window.editFavorite = editFavorite;
window.deleteFavorite = deleteFavorite;



let recognition;
let isDictating = false;


// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("admin_current_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        locationInput = document.getElementById('location');
        peopleInput = document.getElementById('people');
        activityInput = document.getElementById('activity');
        saveButton = document.getElementById('saveButton');
        dictationButton = document.getElementById('dictationButton');
        
        // Favorites DOM elements
        favoritesSelect = document.getElementById('favoritesSelect');
        loadFavoriteBtn = document.getElementById('loadFavoriteBtn');
        openThreadBtn = document.getElementById('openThreadBtn');
        addToFavoritesBtn = document.getElementById('addToFavoritesBtn');
        manageFavoritesBtn = document.getElementById('manageFavoritesBtn');
        manageFavoritesModal = document.getElementById('manageFavoritesModal');
        closeManageFavoritesModal = document.getElementById('closeManageFavoritesModal');
        addFavoriteModal = document.getElementById('addFavoriteModal');
        closeAddFavoriteModal = document.getElementById('closeAddFavoriteModal');
        favoriteName = document.getElementById('favoriteName');
        cancelAddFavorite = document.getElementById('cancelAddFavorite');
        confirmAddFavorite = document.getElementById('confirmAddFavorite');
        favoritesManagementList = document.getElementById('favoritesManagementList');

        // Schedule DOM elements
        scheduleEnabled = document.getElementById('scheduleEnabled');
        scheduleFields = document.getElementById('scheduleFields');
        scheduleDaysContainer = document.getElementById('scheduleDaysContainer');
        scheduleStartTime = document.getElementById('scheduleStartTime');
        scheduleEndTime = document.getElementById('scheduleEndTime');

        // Basic check for essential elements
        if (!locationInput || !peopleInput || !activityInput || !saveButton || !dictationButton || !favoritesSelect || !loadFavoriteBtn || !openThreadBtn || !addToFavoritesBtn || !manageFavoritesBtn) {
            console.error("CRITICAL ERROR: One or more essential DOM elements for user_current_admin.js not found.");
            return;
        }

        // Add Event Listeners
        if (saveButton) saveButton.addEventListener('click', saveCurrentUserState);
        if (dictationButton) dictationButton.addEventListener('click', dictationButtonHandler);
        
        // Favorites event listeners
        if (favoritesSelect) favoritesSelect.addEventListener('change', updateLoadButtonState);
        if (loadFavoriteBtn) {
            loadFavoriteBtn.addEventListener('click', loadSelectedFavorite);
            console.log("Load favorite button event listener added");
        }
        if (openThreadBtn) {
            openThreadBtn.addEventListener('click', openThreadForLoadedFavorite);
            console.log("Open thread button event listener added");
        }
        if (addToFavoritesBtn) {
            addToFavoritesBtn.addEventListener('click', showAddFavoriteModal);
            console.log("Add to favorites button event listener added");
        }
        if (manageFavoritesBtn) {
            manageFavoritesBtn.addEventListener('click', showManageFavoritesModal);
            console.log("Manage favorites button event listener added");
        }
        
        // Modal event listeners
        if (closeManageFavoritesModal) closeManageFavoritesModal.addEventListener('click', () => manageFavoritesModal.classList.add('hidden'));
        if (closeAddFavoriteModal) closeAddFavoriteModal.addEventListener('click', () => addFavoriteModal.classList.add('hidden'));
        if (cancelAddFavorite) cancelAddFavorite.addEventListener('click', () => addFavoriteModal.classList.add('hidden'));
        if (confirmAddFavorite) confirmAddFavorite.addEventListener('click', saveFavorite);
        
        // Schedule checkbox listener
        if (scheduleEnabled) {
            scheduleEnabled.addEventListener('change', () => {
                if (scheduleEnabled.checked) {
                    scheduleFields.classList.remove('opacity-50', 'pointer-events-none');
                } else {
                    scheduleFields.classList.add('opacity-50', 'pointer-events-none');
                }
            });
        }

        // Close modals when clicking outside
        manageFavoritesModal.addEventListener('click', (e) => {
            if (e.target === manageFavoritesModal) {
                manageFavoritesModal.classList.add('hidden');
            }
        });
        addFavoriteModal.addEventListener('click', (e) => {
            if (e.target === addFavoriteModal) {
                addFavoriteModal.classList.add('hidden');
            }
        });


        // Initial data loading
        await loadCurrentUserState();
        console.log("About to call loadFavorites()");
        await loadFavorites();
        console.log("loadFavorites() completed");
    }
}


// --- DOMContentLoaded Initialization ---
async function saveCurrentUserState() { 
        console.log("location input value", locationInput.value);
        console.log("people input value", peopleInput.value);
        console.log("activity input value", activityInput.value);
        const location = locationInput.value;
        const people = peopleInput.value;
        const activity = activityInput.value;

        console.log('Data sent to backend:', { location, people, activity }); // Add this line
        showStatus("Saving...", false, 0);

        try {
            // Use the existing POST endpoint from server.py
            const response = await window.authenticatedFetch('/user_current', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }, // X-User-ID added by authenticatedFetch
                body: JSON.stringify({ location, people, activity })
            });

            if (response.ok) {
                console.log('User current updated successfully.');
                showStatus("Current state saved successfully!", false);
            } else {
                console.error('Failed to update user current:', response.statusText);
                showStatus(`Save failed: ${response.statusText}`, true);
            }
        } catch (error) {
            console.error('Error updating user current:', error);
            showStatus(`Error saving: ${error.message}`, true);
        }
}


function dictationButtonHandler() { 
    if (!isDictating) {
        startDictation();
    } else {
        stopDictation();
    }
}

async function startDictation() {
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
        console.log("transcript", transcript);
    
        const locationMatch = transcript.match(/location\s+(.+?)\s*people/i);
        const peopleMatch = transcript.match(/people\s+(.+?)\s*activity/i);
        const activityMatch = transcript.match(/activity\s+(.+)/i);
    
        if (locationMatch && locationMatch[1]) {
            locationInput.value = locationMatch[1].trim();
            console.log("location input updated", locationInput.value);
        }
    
        if (peopleMatch && peopleMatch[1]) {
            peopleInput.value = peopleMatch[1].trim();
            console.log("people input updated", peopleInput.value);
        }
    
        if (activityMatch && activityMatch[1]) {
            activityInput.value = activityMatch[1].trim();
            console.log("activity input updated", activityInput.value);
        }
    };

    recognition.onerror = function(event) {
        console.error('Dictation error:', event); // Log the entire event object
        stopDictation();
    };

    recognition.onend = function() {
        console.log('Dictation ended.');
        setTimeout(function() {
            if (isDictating) {
                console.log("restarting dictation");
                recognition.start();
            } else {
                stopDictation();
            }
        }, 100); // 100 milliseconds delay
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


// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("admin_current_admin.js: Authentication context is now marked as ready.");
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
        console.log("user_current_admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("user_current_admin.js: Logout button event listener added");
    }
}

// --- Event Listeners ---
// Listener for when the authentication context is ready
document.addEventListener('adminUserContextReady', () => {
    console.log("admin_current_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("admin_current_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("admin_current_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});