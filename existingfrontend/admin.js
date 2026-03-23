// --- DOM Elements ---
const pageForm = document.getElementById('pageForm');
const deletePageButton = document.getElementById('deletePage');
const selectPage = document.getElementById('selectPage');
const buttonGrid = document.getElementById('buttonGrid');
// Settings elements
const scanDelayInput = document.getElementById('scanDelay');
const wakeWordInterjectionInput = document.getElementById('wakeWordInterjection');
const wakeWordNameInput = document.getElementById('wakeWordName');
const CountryCodeInput = document.getElementById('CountryCode');
const StateCodeInput = document.getElementById('StateCode');
const speechRateInput = document.getElementById('speechRate');
const saveSettingsButton = document.getElementById('saveSettingsButton');
const settingsStatus = document.getElementById('settings-status');


// --- State Variables ---
let currentPageName = null; // Tracks the name of the page currently being edited
let pages = [];
let currentSettings = {};

// --- Functions ---

/**
 * Loads the list of pages from the backend and populates the dropdown.
 */
async function loadPages() {
    try {
        const response = await fetch('/pages');
        if (!response.ok) { throw new Error(`HTTP error! status: ${response.status}`); }
        pages = await response.json();
        populateSelectPage(pages);
    } catch (error) { console.error('Error loading pages:', error); }
}

/**
 * Loads global settings from the backend.
 */
async function loadSettings() {
    settingsStatus.textContent = 'Loading settings...';
    settingsStatus.style.color = 'gray';
    try {
        const response = await fetch('/api/settings');
        if (!response.ok) { const errorText = await response.text(); throw new Error(`HTTP error ${response.status}: ${errorText}`); }
        currentSettings = await response.json();

        if (scanDelayInput) { scanDelayInput.value = currentSettings.scanDelay || ''; }
        if (wakeWordInterjectionInput) { wakeWordInterjectionInput.value = currentSettings.wakeWordInterjection || ''; }
        if (wakeWordNameInput) { wakeWordNameInput.value = currentSettings.wakeWordName || ''; }
        if (CountryCodeInput) { CountryCodeInput.value = currentSettings.CountryCode || ''; }
        if (StateCodeInput) { StateCodeInput.value = currentSettings.StateCode || ''; }
        console.log("speech rate",speechRateInput.value)
        if (speechRateInput) { speechRateInput.value = currentSettings.speech_rate || 180; } // Populate speech rate

         console.log("Settings loaded:", currentSettings);
         settingsStatus.textContent = 'Settings loaded.';
         settingsStatus.style.color = 'green';
         setTimeout(() => { settingsStatus.textContent = ''; }, 3000);

    } catch (error) {
        console.error('Error loading settings:', error);
        settingsStatus.textContent = `Error loading settings: ${error.message}`;
        settingsStatus.style.color = 'red';
    }
}

/**
 * Saves global settings to the backend.
 */
async function saveSettings() {
    const newDelay = scanDelayInput.value;
    const newInterjection = wakeWordInterjectionInput.value.trim();
    const newName = wakeWordNameInput.value.trim();
    const newCountryCode = CountryCodeInput.value.trim();
    const newStateCode = StateCodeInput.value.trim();
    const newSpeechRate = speechRateInput.value; // Get speech rate value

console.log("Saving settings:", { scanDelay: newDelay, wakeWordInterjection: newInterjection, wakeWordName: newName, CountryCode: newCountryCode, StateCode: newStateCode, speechRate: newSpeechRate }); 

    // Validation
    if (!newDelay || isNaN(parseInt(newDelay)) || parseInt(newDelay) < 100) {
         settingsStatus.textContent = 'Invalid delay value. Must be >= 100 ms.';
         settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (!newInterjection) {
        settingsStatus.textContent = 'Wake Word Interjection required.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
     if (!newName) {
        settingsStatus.textContent = 'Wake Word Name required.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (!newCountryCode) {
        settingsStatus.textContent = 'Country Code required.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (!newStateCode) {
        settingsStatus.textContent = 'State Code required.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (!newSpeechRate || isNaN(parseInt(newSpeechRate)) || parseInt(newSpeechRate) < 50 || parseInt(newSpeechRate) > 400) { // Example validation for speech rate
        settingsStatus.textContent = 'Invalid Speech Rate. Must be a number (e.g., 50-400).';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }

    const settingsToSave = {
        scanDelay: parseInt(newDelay),
        wakeWordInterjection: newInterjection,
        wakeWordName: newName,
        CountryCode: newCountryCode,
        StateCode: newStateCode,
        speech_rate: parseInt(newSpeechRate)
    };

    console.log("Saving settings:", settingsToSave);
    settingsStatus.textContent = 'Saving...'; settingsStatus.style.color = 'blue';

    try {
        const response = await fetch('/api/settings', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(settingsToSave)
        });
        if (!response.ok) { const errorText = await response.text(); throw new Error(`Save failed: ${response.status} ${errorText}`); }

        currentSettings = await response.json(); // Update local state with response
        scanDelayInput.value = currentSettings.scanDelay || '';
        wakeWordInterjectionInput.value = currentSettings.wakeWordInterjection || '';
        wakeWordNameInput.value = currentSettings.wakeWordName || '';
        CountryCodeInput.value = currentSettings.CountryCode || '';
        StateCodeInput.value = currentSettings.StateCode || '';
        speechRateInput.value = currentSettings.speech_rate || 180; // Update speech rate

        settingsStatus.textContent = 'Settings saved successfully!'; settingsStatus.style.color = 'green';
        setTimeout(() => { settingsStatus.textContent = ''; }, 3000);

    } catch (error) {
        console.error('Error saving settings:', error);
        settingsStatus.textContent = `Error saving: ${error.message}`; settingsStatus.style.color = 'red';
    }
}


/**
 * Populates the page selection dropdown.
 */
function populateSelectPage(pagesData) {
    const currentVal = selectPage.value;
    selectPage.innerHTML = '<option value="">Select a page</option>';
    const optionNew = document.createElement('option');
    optionNew.value = "--new--";
    optionNew.textContent = "--- Create a New Page ---";
    selectPage.appendChild(optionNew);
    pagesData.sort((a, b) => a.name.localeCompare(b.name));
    pagesData.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.name;
        selectPage.appendChild(option);
    });
     // Restore previous selection if it still exists after reload
     if (pagesData.some(p => p.name === currentVal)) {
         selectPage.value = currentVal;
     } else {
          selectPage.value = ''; // Default to "Select" if previous is gone or invalid
     }
}

/**
 * Loads the selected page data into the form.
 */
function editPage(page) {
    console.log("Loading page data into form:", page.name);
    // *** Set currentPageName HERE when loading an existing page ***
    currentPageName = page.name;
    pageForm.reset(); // Reset form elements to default values
    document.getElementById('pageName').value = page.name;
    // Restore commented-out fields if they exist in your HTML and page data
    // document.getElementById('pageType').value = page.pageType || 'home';
    // document.getElementById('pageDiv').value = page.pageDiv || '';
    // document.getElementById('LLMQuery').value = page.LLMQuery || '';
    // document.getElementById('queryType').value = page.queryType || '';

    generateGrid(); // Regenerate grid structure
    populateGrid(page.buttons || []); // Populate with button data

    selectPage.value = currentPageName; // Ensure dropdown matches loaded page
}

/**
 * Generates the empty 12x12 grid structure in the DOM, including clear buttons.
 */
function generateGrid() {
    buttonGrid.innerHTML = '';
    for (let row = 0; row < 12; row++) {
        for (let col = 0; col < 12; col++) {
            const cell = document.createElement('div');
            cell.classList.add('gridCell');
            cell.dataset.row = row;
            cell.dataset.col = col;

            // Inputs for button properties
            const labelInput = document.createElement('input'); labelInput.type = 'text'; labelInput.placeholder = 'Label'; labelInput.setAttribute('aria-label', `Label R${row+1}C${col+1}`);
            const speechInput = document.createElement('input'); speechInput.type = 'text'; speechInput.placeholder = 'Speech'; speechInput.setAttribute('aria-label', `Speech R${row+1}C${col+1}`);
            const audioFileInput = document.createElement('input'); audioFileInput.type = 'file'; audioFileInput.accept = 'audio/*'; audioFileInput.placeholder = 'MP3 Audio'; audioFileInput.setAttribute('aria-label', `MP3 Audio R${row+1}C${col+1}`); audioFileInput.className = 'audio-file-input text-xs';
            
            // Add upload handler for audio files
            audioFileInput.addEventListener('change', async (e) => {
                const file = e.target.files[0];
                if (file) {
                    try {
                        const formData = new FormData();
                        formData.append('file', file);
                        
                        const response = await fetch('/api/admin/upload-button-audio', {
                            method: 'POST',
                            body: formData
                        });
                        
                        if (response.ok) {
                            const result = await response.json();
                            audioFileInput.dataset.audioUrl = result.audio_url;
                            audioFileInput.style.backgroundColor = '#d1fae5'; // Green background to indicate upload success
                            console.log('Audio uploaded successfully:', result.audio_url);
                        } else {
                            throw new Error('Upload failed');
                        }
                    } catch (error) {
                        console.error('Error uploading audio:', error);
                        audioFileInput.style.backgroundColor = '#fecaca'; // Red background to indicate error
                        alert('Failed to upload audio file. Please try again.');
                    }
                }
            });
            const targetInput = document.createElement('input'); targetInput.type = 'text'; targetInput.placeholder = 'Target'; targetInput.setAttribute('aria-label', `Target R${row+1}C${col+1}`);
            const llmQueryInput = document.createElement('textarea'); llmQueryInput.placeholder = 'LLM Query'; llmQueryInput.setAttribute('aria-label', `LLM Query R${row+1}C${col+1}`);
            const querytypeInput = document.createElement('input'); querytypeInput.type = 'text'; querytypeInput.placeholder = 'Q Type'; querytypeInput.setAttribute('aria-label', `Q Type R${row+1}C${col+1}`);

            cell.appendChild(labelInput);
            cell.appendChild(speechInput);
            cell.appendChild(audioFileInput);
            cell.appendChild(targetInput);
            cell.appendChild(llmQueryInput);
            cell.appendChild(querytypeInput);

            // --- Add Hidden Checkbox ---
            const hiddenLabel = document.createElement('label');
            hiddenLabel.className = 'flex items-center text-xs mt-1 cursor-pointer text-gray-600'; // Added text color
            const hiddenCheckbox = document.createElement('input');
            hiddenCheckbox.type = 'checkbox';
            hiddenCheckbox.className = 'hidden-checkbox mr-1 h-3 w-3 text-blue-600 border-gray-300 rounded focus:ring-blue-500';
            // hiddenCheckbox.checked will be set in populateGrid
            hiddenLabel.appendChild(hiddenCheckbox);
            hiddenLabel.appendChild(document.createTextNode('Hidden'));
            cell.appendChild(hiddenLabel);

            // --- Add Clear Button to Cell ---
            const clearCellButton = document.createElement('button');
            clearCellButton.type = 'button'; // Important: prevent form submission
            clearCellButton.textContent = 'X'; // Simple clear symbol
            clearCellButton.title = 'Clear Cell';
            clearCellButton.classList.add('clear-cell-btn'); // Add class for styling/selection
            clearCellButton.addEventListener('click', (e) => {
                e.preventDefault(); // Prevent form submission
                console.log(`Clearing cell R${row}C${col}`);
                // Find inputs within the specific cell and clear them
                const parentCell = e.target.closest('.gridCell');
                if (parentCell) {
                    parentCell.querySelectorAll('input[type="text"], textarea').forEach(input => {
                        input.value = '';
                    });
                }
            });
            // --- End Clear Button ---


            // Arrow buttons for moving
            const arrowButtons = document.createElement('div');
            arrowButtons.classList.add('arrowButtons');
             // Prepend clear button before arrows
             arrowButtons.appendChild(clearCellButton); // Add clear button here
            ['↑', '↓', '←', '→'].forEach((arrow, index) => {
                 const btn = document.createElement('button');
                 btn.type = 'button';
                 btn.textContent = arrow;
                 const offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]][index];
                 // *** Add e.preventDefault() to arrow listeners ***
                 btn.addEventListener('click', (e) => {
                      e.preventDefault(); // Prevent form submission on arrow click
                      moveButton(row, col, offsets[0], offsets[1]);
                 });
                 arrowButtons.appendChild(btn);
            });
            cell.appendChild(arrowButtons); // Append container with clear + arrows

            buttonGrid.appendChild(cell);
        }
    }
}

/**
 * Populates the generated grid with data from saved buttons.
 */
function populateGrid(buttons) {
    buttons.forEach(button => {
        const cell = buttonGrid.querySelector(`.gridCell[data-row="${button.row}"][data-col="${button.col}"]`);
        if (cell) {
            cell.querySelector('input[placeholder="Label"]').value = button.text || '';
            cell.querySelector('input[placeholder="Speech"]').value = button.speechPhrase || '';
            const audioFileInput = cell.querySelector('.audio-file-input');
            if (audioFileInput && button.customAudioFile) {
                audioFileInput.dataset.audioUrl = button.customAudioFile;
                audioFileInput.style.backgroundColor = '#d1fae5'; // Green to indicate audio file assigned
                audioFileInput.title = 'Audio file assigned: ' + button.customAudioFile;
            }
            cell.querySelector('input[placeholder="Target"]').value = button.targetPage || '';
            cell.querySelector('textarea[placeholder="LLM Query"]').value = button.LLMQuery || '';
            cell.querySelector('input[placeholder="Q Type"]').value = button.queryType || '';
            // Set the hidden checkbox state
            const hiddenCheckbox = cell.querySelector('.hidden-checkbox');
            if (hiddenCheckbox) {
                hiddenCheckbox.checked = button.hidden || false;
            }
        } else { console.warn(`Cell not found for button at row ${button.row}, col ${button.col}`); }
    });
}

/**
 * Moves button data between adjacent grid cells.
 */
function moveButton(row, col, rowOffset, colOffset) {
    const newRow = row + rowOffset;
    const newCol = col + colOffset;

    if (newRow >= 0 && newRow < 12 && newCol >= 0 && newCol < 12) {
        const cell = buttonGrid.querySelector(`.gridCell[data-row="${row}"][data-col="${col}"]`);
        const newCell = buttonGrid.querySelector(`.gridCell[data-row="${newRow}"][data-col="${newCol}"]`);

        if (cell && newCell) {
            const inputs = ['input[placeholder="Label"]', 'input[placeholder="Speech"]', 'input[placeholder="Target"]', 'textarea[placeholder="LLM Query"]', 'input[placeholder="Q Type"]'];
            const tempValues = {};
            inputs.forEach(selector => { tempValues[selector] = cell.querySelector(selector).value; });
            inputs.forEach(selector => { cell.querySelector(selector).value = newCell.querySelector(selector).value; });
            inputs.forEach(selector => { newCell.querySelector(selector).value = tempValues[selector]; });
        }
    }
}


/**
 * Saves the current page configuration (details and button grid) to the backend.
 */
async function savePage(event) {
    event.preventDefault();

    const pageNameInput = document.getElementById('pageName');
    const newPageName = pageNameInput.value.trim();

    if (!newPageName) { alert("Page Name is required."); pageNameInput.focus(); return; }

    // *** Check currentPageName state before deciding method ***
    console.log("Saving page. Current page name state:", currentPageName);
    // Determine if we are updating an existing page or creating a new one
    const isUpdating = !!currentPageName && currentPageName !== "--new--";
    const method = isUpdating ? 'PUT' : 'POST';
    const url = '/pages';

    // *** CRITICAL FIX: Ensure originalName is sent ONLY for PUT requests ***
    if (method === 'PUT' && !currentPageName) {
         alert("Error: Cannot update page. Original page name is missing. Please re-select the page from the dropdown.");
         return; // Prevent sending invalid update request
    }

    // Prevent creating a duplicate page name
    const isCreatingNew = (method === 'POST');
    if (isCreatingNew && pages.some(p => p.name === newPageName)) {
         alert(`A page named "${newPageName}" already exists. Please choose a different name.`);
         pageNameInput.focus(); return;
    }

    // Prepare page data from form
    const pageData = {
        name: newPageName,
        // Include other page details if they exist in your HTML form
        // pageType: document.getElementById('pageType')?.value || 'home', // Example with fallback
        // pageDiv: document.getElementById('pageDiv')?.value.trim() || '',
        // LLMQuery: document.getElementById('LLMQuery')?.value.trim() || '',
        // queryType: document.getElementById('queryType')?.value.trim() || '',
        buttons: []
    };

    // Collect button data from the grid
    buttonGrid.querySelectorAll('.gridCell').forEach(cell => {
        const text = cell.querySelector('input[placeholder="Label"]').value.trim();
        if (text) { // Only save if Label has text
            const audioFileInput = cell.querySelector('.audio-file-input');
            pageData.buttons.push({
                row: parseInt(cell.dataset.row), col: parseInt(cell.dataset.col), text: text,
                speechPhrase: cell.querySelector('input[placeholder="Speech"]').value.trim(),
                customAudioFile: audioFileInput ? audioFileInput.dataset.audioUrl || null : null,
                targetPage: cell.querySelector('input[placeholder="Target"]').value.trim(),
                LLMQuery: cell.querySelector('textarea[placeholder="LLM Query"]').value.trim(),
                queryType: cell.querySelector('input[placeholder="Q Type"]').value.trim(),
                hidden: cell.querySelector('.hidden-checkbox').checked
            });
        }
    });

    // Construct request body - Ensure originalName is included for PUT
    const body = isUpdating ? { ...pageData, originalName: currentPageName } : pageData;

    console.log(`Attempting to ${method} page:`, body);

    try {
        const response = await fetch(url, { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        if (!response.ok) { const errorText = await response.text(); throw new Error(`Save failed: ${response.status} ${errorText}`); }

        console.log(`Page ${isUpdating ? 'updated' : 'created'} successfully.`);
        const savedPageName = newPageName; // Store the name that was saved/created
        await loadPages(); // Reload page list (this updates the global 'pages' array)

        // Reselect the saved/updated page in the dropdown
        selectPage.value = savedPageName;

        // ** CRITICAL FIX: Update currentPageName if the name was changed during an update **
        // This ensures subsequent saves of the renamed page work correctly
        currentPageName = savedPageName;

        // Reload the form with the potentially updated data
        // No need to call editPage again, data is already in form, just ensure state matches
        // const updatedPage = pages.find(p => p.name === savedPageName);
        // if (updatedPage) {
        //      console.log("Page data updated in form (if name changed).");
        // } else {
        //      console.error("Saved page not found after reloading list. Clearing form.");
        //      clearForm();
        // }
        alert(`Page "${savedPageName}" saved successfully!`);

    } catch (error) {
        console.error('Error saving page:', error);
        alert(`Error saving page: ${error.message}`);
    }
}

/**
 * Deletes the currently selected page after confirmation.
 */
async function deletePage() {
     // *** Ensure currentPageName is valid before attempting delete ***
    if (currentPageName && currentPageName !== "--new--") {
        if (!confirm(`Are you sure you want to delete the page "${currentPageName}"? This cannot be undone.`)) { return; }
        console.log(`Attempting to delete page: ${currentPageName}`);
        try {
            // Send name in the body for DELETE request
            const response = await fetch('/pages', { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: currentPageName }) });
            if (!response.ok) { const errorText = await response.text(); throw new Error(`Delete failed: ${response.status} ${errorText}`); }
            console.log(`Page "${currentPageName}" deleted successfully.`);
            await loadPages(); // Reload page list
            clearForm(); // Clear form and set dropdown to "--new--"
            alert(`Page "${currentPageName}" deleted.`);
        } catch (error) { console.error('Error deleting page:', error); alert(`Error deleting page: ${error.message}`); }
    } else { alert("No page selected to delete, or 'Create New Page' is selected."); }
}

/**
 * Clears the form fields and resets the grid.
 */
function clearForm() {
    console.log("Clearing form and resetting currentPageName.");
    currentPageName = null; // *** Reset current page tracking ***
    pageForm.reset();
    // Restore commented-out fields if they exist
    // document.getElementById('pageType').value = 'home';
    selectPage.value = "--new--"; // Set dropdown to "Create New" explicitly
    generateGrid(); // Clear the grid display
}

// --- Event Listeners ---

// Handle page selection change
selectPage.addEventListener('change', () => {
    const selectedPageName = selectPage.value;
    if (selectedPageName === "--new--") {
        clearForm(); // This now correctly sets currentPageName to null
    } else if (selectedPageName) {
        const page = pages.find(p => p.name === selectedPageName);
        if (page) {
            editPage(page); // This sets currentPageName to the selected page name
        } else {
             console.error(`Selected page "${selectedPageName}" not found in loaded data.`);
             clearForm();
        }
    } else {
        clearForm(); // Also clear if "Select a page" is chosen
    }
});

// Handle form submission (Save Page)
pageForm.addEventListener('submit', savePage);

// Handle Delete Page button click
deletePageButton.addEventListener('click', deletePage);

// Handle Save Settings button click
if (saveSettingsButton) {
    saveSettingsButton.addEventListener('click', saveSettings);
} else { console.error("Save Settings button not found!"); }

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
        console.log("admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("admin.js: Logout button event listener added");
    }
}

// --- Initial Load ---
document.addEventListener('DOMContentLoaded', () => {
    console.log("Admin page loaded.");
    generateGrid(); // Generate grid structure on initial load
    loadPages();    // Load page list into dropdown
    loadSettings(); // Load global settings
    setupAdminToolbarButtons(); // Add toolbar button functionality
});
