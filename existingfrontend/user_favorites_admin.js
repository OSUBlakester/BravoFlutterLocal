// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

// DOM elements for tables and save button will be assigned in initializePage
/**
 * Displays a status message to the user.
 * @param {string} message - The message to display.
 * @param {boolean} [isError=false] - Whether the message represents an error.
 */
function showStatus(message, isError = false) {
    const area = document.getElementById('status-message-area');
    if (!area) {
        console.error("Status message area not found!");
        return;
    }
    area.textContent = message;
    area.className = 'status-message'; // Reset classes
    if (message) {
        area.classList.add(isError ? 'status-error' : 'status-success');
    }
}


// --- Core Functions ---

/**
 * Loads the scraping configuration from the backend and populates the tables.
 */
async function loadConfig() {
    showStatus("Loading configuration...", false);
    try {
        const response = await window.authenticatedFetch('/get-user-favorites');
        if (!response.ok) {
            // Attempt to get error detail from response body
            let errorDetail = `HTTP error ${response.status}`;
            try {
                const errorData = await response.json();
                errorDetail = errorData.detail || errorDetail;
            } catch (e) {
                // Ignore if response body is not JSON or empty
            }
            throw new Error(errorDetail);
        }
        const config = await response.json();

        // Clear existing table bodies
        document.getElementById('news-sources-tbody').innerHTML = '';
        document.getElementById('sports-sources-tbody').innerHTML = '';
        document.getElementById('entertainment-sources-tbody').innerHTML = '';

        // Populate tables
        populateTable('news', config.news_sources || []);
        populateTable('sports', config.sports_sources || []);
        populateTable('entertainment', config.entertainment_sources || []);

        showStatus("Configuration loaded.", false);
        // Clear status after a few seconds
        setTimeout(() => showStatus("", false), 3000);

    } catch (error) {
        console.error('Error loading configuration:', error);
        showStatus(`Error loading configuration: ${error.message}`, true);
    }
}

/**
 * Populates a specific category table with source data.
 * @param {string} category - The category name ('news', 'sports', 'entertainment').
 * @param {Array<object>} sources - An array of source objects for the category.
 */
function populateTable(category, sources) {
    const tbody = document.getElementById(`${category}-sources-tbody`);
    if (!tbody) {
        console.error(`Table body not found for category: ${category}`);
        return;
    }
    tbody.innerHTML = ''; // Clear just in case
    sources.forEach(source => {
        const row = createSourceRow(source, category);
        tbody.appendChild(row);
    });
}

/**
 * Creates a table row element for a source configuration.
 * @param {object} [sourceData={}] - The data for the source.
 * @param {string} category - The category the source belongs to.
 * @returns {HTMLTableRowElement} The created table row.
 */
function createSourceRow(sourceData = {}, category) {
    const row = document.createElement('tr');
    // Use sourceData.id if it exists, otherwise leave it empty (will be null on save for new rows)
    row.dataset.id = sourceData.id || '';
    row.dataset.category = category;

    // Define the columns/keys including the new sample_html
    const keys = ['url', 'keywords', 'headline_selector', 'url_selector', 'url_attribute', 'url_prefix', 'sample_html']; // Added sample_html

    keys.forEach(key => {
        const cell = document.createElement('td');
        let inputElement; // Use a more descriptive name

        if (key === 'sample_html') {
            // Use textarea for Sample HTML
            inputElement = document.createElement('textarea');
            inputElement.rows = 3; // Adjust height as needed
            inputElement.placeholder = "Optional: Paste sample <element> here from DevTools for Analyze";
            // Do not pre-fill sample_html from sourceData, it's for input only when analyzing
            inputElement.value = '';
        } else {
            // Use regular input for others
            inputElement = document.createElement('input');
            inputElement.type = (key === 'url') ? 'url' : 'text'; // Use url type for URL field

            // Handle keywords array specifically for display (join with comma+space)
            if (key === 'keywords' && Array.isArray(sourceData[key])) {
                 inputElement.value = sourceData[key].join(', ');
            } else {
                // Assign value from sourceData or default to empty string
                inputElement.value = sourceData[key] || '';
            }
            // Set default for url_attribute if empty
            if (key === 'url_attribute' && !inputElement.value) {
                inputElement.value = 'href'; // Default to 'href'
            }
            // Add placeholder text
             inputElement.placeholder = key.replace('_', ' '); // e.g., "headline selector"
        }

        inputElement.className = `source-input source-${key}-input`; // Add a general class and specific class
        inputElement.setAttribute('aria-label', `${category} ${key}`); // For accessibility
        cell.appendChild(inputElement);
        row.appendChild(cell);
    });

    // Actions Cell
    const actionsCell = document.createElement('td');
    actionsCell.className = 'action-buttons'; // Class for styling

    // Delete Button
    const deleteButton = document.createElement('button');
    deleteButton.textContent = 'Delete';
    deleteButton.className = 'delete-source-btn btn btn-danger btn-sm'; // Add Bootstrap classes
    deleteButton.title = 'Delete this source row';

    // Analyze Button
    const analyzeButton = document.createElement('button');
    analyzeButton.textContent = 'Analyze';
    analyzeButton.className = 'analyze-source-btn btn btn-info btn-sm'; // Add Bootstrap classes
    analyzeButton.title = 'Attempt to auto-detect selectors (uses Sample HTML if provided)'; // Update tooltip

    actionsCell.appendChild(deleteButton);
    actionsCell.appendChild(analyzeButton);
    row.appendChild(actionsCell);

    return row;
}


/**
 * Adds a new empty source row to the specified category table.
 * @param {string} category - The category to add the row to.
 */
function addSourceRow(category) {
    const tbody = document.getElementById(`${category}-sources-tbody`);
    if (tbody) {
        const newRow = createSourceRow({}, category); // Create row with empty data
        tbody.appendChild(newRow);
        // Optionally scroll to the new row or focus the first input
        newRow.querySelector('.source-url-input')?.focus();
    } else {
        console.error(`Table body not found for category: ${category}`);
        showStatus(`Error: Could not find table for category ${category}.`, true);
    }
}

/**
 * Handles the click event for the delete button on a source row.
 * Removes the row from the table visually.
 * @param {Event} event - The click event object.
 */
function handleDeleteClick(event) {
    const button = event.target;
    const row = button.closest('tr'); // Find the table row
    if (row) {
        row.remove(); // Remove the row from the DOM
        showStatus("Row marked for deletion. Save changes to confirm.", false);
    }
}

/**
 * Gathers data from all tables and sends it to the backend to save.
 */
async function saveConfig() {
    showStatus("Saving configuration...", false);
    const configToSave = {
        news_sources: [],
        sports_sources: [],
        entertainment_sources: []
    };
    const categories = ['news', 'sports', 'entertainment'];
    let hasError = false; // Flag to stop saving if validation fails

    // Iterate through each category table
    categories.forEach(category => {
        // Skip the rest of the categories if an error has already occurred
        if (hasError) return;

        const tbody = document.getElementById(`${category}-sources-tbody`);
        if (!tbody) {
             console.error(`Tbody not found for category: ${category}`);
             // Optionally inform the user, though this shouldn't happen normally
             // showStatus(`Error: Table body for ${category} not found. Skipping save for this category.`, true);
             return; // Skip this category
        }
        const rows = tbody.querySelectorAll('tr');
        const configKey = `${category}_sources`; // e.g., news_sources

        // Iterate through each row in the current table
        rows.forEach((row, index) => {
            // Stop processing rows for this category if an error was found in a previous row
            if (hasError) return;

            const source = {
                // Get existing ID or null for new rows (backend should handle assigning new IDs)
                id: row.dataset.id || null
            };

            // Select input fields within the current row
            const urlInput = row.querySelector('.source-url-input');
            const keywordsInput = row.querySelector('.source-keywords-input');
            const headlineInput = row.querySelector('.source-headline_selector-input');
            const linkInput = row.querySelector('.source-url_selector-input');
            const attributeInput = row.querySelector('.source-url_attribute-input');
            const prefixInput = row.querySelector('.source-url_prefix-input');
            // NOTE: Sample HTML textarea is intentionally NOT read here, it's only used for the 'Analyze' feature.

            // --- Basic Validation ---
            if (!urlInput || !urlInput.value.trim()) {
                showStatus(`Error: URL is required for row ${index + 1} in ${category}.`, true);
                urlInput?.focus(); // Focus the problematic input if it exists
                hasError = true; // Set flag to stop saving process
                return; // Stop processing this row and subsequent rows in this category
            }
            // Add more validation as needed (e.g., check selector formats)

            // --- Assign values to the source object ---
            source.url = urlInput.value.trim();
            // Split keywords string into an array, trim whitespace, remove empty strings
            source.keywords = keywordsInput.value.split(',')
                                         .map(k => k.trim())
                                         .filter(k => k !== ''); // Ensure empty strings are removed
            source.headline_selector = headlineInput.value.trim() || null; // Send null if empty
            source.url_selector = linkInput.value.trim() || null; // Send null if empty
            source.url_attribute = attributeInput.value.trim() || 'href'; // Default to 'href' if empty
            source.url_prefix = prefixInput.value.trim() || null; // Send null if empty

            // Add the processed source object to the correct category array
            configToSave[configKey].push(source);
        });
    });

    // If any validation error occurred, stop before sending to backend
    if (hasError) {
        console.error("Validation errors found. Aborting save.");
        // The error message should already be displayed by the validation check
        return; // Exit the saveConfig function
    }

    // --- Send data to backend ---
    try {
        const response = await window.authenticatedFetch('/update-user-favorites', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(configToSave)
        });

        if (!response.ok) {
             // Attempt to get error detail from response body
            let errorDetail = `Save failed with status ${response.status}`;
            try {
                const errorData = await response.json();
                errorDetail = errorData.detail || errorDetail;
            } catch (e) {
                // Ignore if response body is not JSON or empty
            }
            throw new Error(errorDetail);
        }

        // --- Success ---
        showStatus("Configuration saved successfully!", false);
        // Optionally reload the config to get assigned IDs for new rows,
        // or update row IDs manually based on response if backend sends them back.
        // For simplicity, we'll just show success and clear after a delay.
        setTimeout(() => showStatus("", false), 5000); // Clear status message

    } catch (error) {
        console.error('Error saving configuration:', error);
        showStatus(`Error saving configuration: ${error.message}`, true);
    }
}


/**
 * Handles the click event for the analyze button. Sends URL, keywords,
 * and optional sample HTML to the backend for analysis and populates
 * suggested selectors. Optionally triggers a save.
 * @param {Event} event - The click event.
 */
async function handleAnalyzeClick(event) {
    const analyzeButton = event.target;
    const row = analyzeButton.closest('tr');
    if (!row) return; // Should not happen if button is in a row

    // Get input elements from the current row
    const urlInput = row.querySelector('.source-url-input');
    const keywordsInput = row.querySelector('.source-keywords-input');
    const headlineInput = row.querySelector('.source-headline_selector-input');
    const linkInput = row.querySelector('.source-url_selector-input');
    const prefixInput = row.querySelector('.source-url_prefix-input');
    const sampleHtmlInput = row.querySelector('.source-sample_html-input'); // Get the textarea

    // Get values, trim whitespace
    const urlValue = urlInput.value.trim();
    const keywordsValue = keywordsInput.value.trim();
    const sampleHtmlValue = sampleHtmlInput.value.trim(); // Get the sample HTML

    // Validate URL presence
    if (!urlValue) {
        showStatus("Please enter a URL before analyzing.", true);
        urlInput.focus();
        return; // Stop if no URL
    }

    // --- UI Update: Indicate Loading ---
    const originalButtonText = analyzeButton.textContent;
    analyzeButton.textContent = 'Analyzing...';
    analyzeButton.disabled = true; // Disable button during processing
    showStatus(`Analyzing ${urlValue}...`, false);

    try {
        // Prepare keywords list
        const keywordsList = keywordsValue.split(',')
                                   .map(k => k.trim())
                                   .filter(k => k !== ''); // Remove empty keywords

        // Prepare request body
        const requestBody = {
            url: urlValue,
            keywords: keywordsList
            // sample_html is added conditionally below
        };
        // Add sample_html to request only if it has content
        if (sampleHtmlValue) {
            requestBody.sample_html = sampleHtmlValue;
        }

        // --- Call Backend API ---
        const response = await window.authenticatedFetch('/api/analyze-url', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(requestBody) // Send the prepared body
        });

        // Check for network or server errors
        if (!response.ok) {
            let errorDetail = `Analysis failed with status ${response.status}`;
             try {
                const errorData = await response.json();
                errorDetail = errorData.detail || errorDetail;
            } catch (e) { /* Ignore non-JSON errors */ }
            throw new Error(errorDetail);
        }

        // Parse the JSON response containing suggestions
        const suggestions = await response.json();
        console.log("Received suggestions:", suggestions); // Log for debugging

        // --- Apply Suggestions ---
        let changed = false; // Flag to track if any input value was changed
        // Apply headline selector suggestion if provided and different from current value
        if (suggestions.headline_selector && headlineInput.value !== suggestions.headline_selector) {
            headlineInput.value = suggestions.headline_selector;
            changed = true;
        }
        // Apply URL selector suggestion if provided and different
        if (suggestions.url_selector && linkInput.value !== suggestions.url_selector) {
            linkInput.value = suggestions.url_selector;
            changed = true;
        }
        // Apply URL prefix suggestion if provided and different
        if (suggestions.url_prefix && prefixInput.value !== suggestions.url_prefix) {
            prefixInput.value = suggestions.url_prefix;
            changed = true;
        }

        // --- Auto-Save or Show Status ---
        if (changed) {
            showStatus(`Analysis complete for ${urlValue}. Applied suggestions. Saving...`, false);
            // Automatically save the entire configuration after applying changes
            await saveConfig(); // Await saveConfig to complete
            // Note: saveConfig will show its own success/error message, potentially overwriting this one.
        } else {
             // Inform user if no new suggestions were applied
             showStatus(`Analysis complete for ${urlValue}. No new suggestions applied or suggestions matched existing values.`, false);
             setTimeout(() => showStatus("", false), 5000); // Clear status after delay
        }

    } catch (error) {
        // Catch errors from fetch or processing
        console.error("Error during URL analysis:", error);
        showStatus(`Error analyzing URL: ${error.message}`, true);
    } finally {
        // --- UI Cleanup: Restore Button ---
        // This block runs regardless of success or error
        analyzeButton.textContent = originalButtonText;
        analyzeButton.disabled = false; // Re-enable button
    }
}


// --- Event Listeners Initialization ---

function setupEventListeners() {
    // Save All button
    const saveButton = document.getElementById('save-all-button');
    if (saveButton) {
        saveButton.addEventListener('click', saveConfig);
    } else {
        console.error("Save All button not found!");
    }


    // Use event delegation on the body for dynamically added buttons
    document.body.addEventListener('click', (event) => {
        // Handle "Add Source" button clicks
        if (event.target && event.target.classList.contains('add-source-btn')) {
            const category = event.target.dataset.category;
            if (category) {
                addSourceRow(category);
            } else {
                console.warn("Add source button clicked without category data.");
            }
        }
        // Handle "Delete" button clicks
        else if (event.target && event.target.classList.contains('delete-source-btn')) {
             handleDeleteClick(event);
         }
        // Handle "Analyze" button clicks
         else if (event.target && event.target.classList.contains('analyze-source-btn')) {
            handleAnalyzeClick(event); // Call the analysis handler
        }
    });

}

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("user_favorites_admin.js: Auth context and DOM ready. Initializing page.");


        // Basic check for essential elements
        if (!document.getElementById('status-message-area') || !document.getElementById('save-all-button')) {
            console.error("CRITICAL ERROR: One or more essential DOM elements for user_favorites_admin.js not found.");
            return;
        }


        setupEventListeners(); // Setup other event listeners
        await loadConfig();    // Load initial config
    }
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
        console.log("user_favorites_admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("user_favorites_admin.js: Logout button event listener added");
    }
}

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("user_favorites_admin.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}

// --- Standard Event Listeners for Initialization ---
document.addEventListener('adminUserContextReady', authContextIsReady);
if (window.adminContextInitializedByInlineScript === true) authContextIsReady();
document.addEventListener('DOMContentLoaded', () => { 
    isDomContentLoaded = true; 
    initializePage(); 
    setupAdminToolbarButtons(); // Add toolbar button functionality
});
