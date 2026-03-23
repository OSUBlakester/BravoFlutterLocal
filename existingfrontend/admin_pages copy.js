// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

// These must be 'let' and initialized to 'null' for proper global scope and assignment later.
let pageForm = null;
let deletePageButton = null;
let selectPage = null;
let buttonGrid = null;
let newPageNameInput = null;
let newPageDisplayNameInput = null;
let createUpdatePageBtn = null;
let revertPageBtn = null;

let hamburgerBtn = null;
let adminNavDropdown = null;

// --- State Variables ---
let allUserPages = []; // Stores ALL pages for the current user loaded from backend
let currentPageData = null; // Stores the currently selected/edited page object
let initialPageDataString = ''; // Used to check for unsaved changes

// --- Constants / Defaults ---
const DEFAULT_PAGE_BUTTON_STRUCTURE = {
    text: "",
    LLMQuery: "",
    targetPage: "",
    queryType: "",
    speechPhrase: null,
    hidden: false
};


// --- Initialization Function ---
/**
 * This function is called when both auth context is ready and DOM is loaded.
 * It assigns DOM elements, sets up event listeners, and loads initial page data.
 */
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("admin_pages.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements (must be done after DOMContentLoaded)
        pageForm = document.getElementById('pageForm'); // Though not directly used for listeners here, good to assign
        deletePageButton = document.getElementById('deletePage');
        selectPage = document.getElementById('selectPage');
        buttonGrid = document.getElementById('buttonGrid');
        newPageNameInput = document.getElementById('newPageName');
        newPageDisplayNameInput = document.getElementById('newPageDisplayName');
        createUpdatePageBtn = document.getElementById('createUpdatePageBtn');
        revertPageBtn = document.getElementById('revertPageBtn');
        hamburgerBtn = document.getElementById('hamburger-btn');
        adminNavDropdown = document.getElementById('admin-nav-dropdown');

        // Check if all essential elements are found
        if (!pageForm || !selectPage || !buttonGrid || !newPageNameInput || !newPageDisplayNameInput || !createUpdatePageBtn || !deletePageButton || !revertPageBtn || !hamburgerBtn || !adminNavDropdown) {
            console.error("CRITICAL ERROR: One or more essential DOM elements not found on admin_pages.html. Page functionality will be limited.");
            return; 
        }

        // Add Event Listeners for page elements
        selectPage.addEventListener('change', handlePageSelected);
        createUpdatePageBtn.addEventListener('click', createUpdatePage);
        deletePageButton.addEventListener('click', deletePage);
        revertPageBtn.addEventListener('click', revertPage);

        // Hamburger Menu Logic
        hamburgerBtn.addEventListener('click', function(event) {
            event.stopPropagation();
            const isExpanded = hamburgerBtn.getAttribute('aria-expanded') === 'true' || false;
            hamburgerBtn.setAttribute('aria-expanded', !isExpanded);
            adminNavDropdown.style.display = isExpanded ? 'none' : 'block';
        });
        document.addEventListener('click', function(event) {
            if (adminNavDropdown.style.display === 'block' && !hamburgerBtn.contains(event.target) && !adminNavDropdown.contains(event.target)) {
                adminNavDropdown.style.display = 'none';
                hamburgerBtn.setAttribute('aria-expanded', 'false');
            }
        });

        console.log("starting page load process...")

        await loadPages(); // Load initial page data
    }
    // Enhanced logging if initialization doesn't proceed
    else if (!isAuthContextReady) {
        console.log("admin_pages.js: initializePage check - Auth context NOT ready yet.");
    }
    else if (!isDomContentLoaded) {
        console.log("admin_pages.js: initializePage check - DOM content NOT loaded yet.");

    }
}

// --- Functions ---

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return; // Prevent multiple executions

    console.log("admin_pages.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage(); // Attempt to initialize if DOM is also ready
}
/**
 * Loads the list of pages from the backend and populates the dropdown.
 */
async function loadPages() {
    try {
        // Ensure window.currentAacUserId is available before fetching
        if (!window.currentAacUserId) {
            console.error("loadPages: window.currentAacUserId is not set. Cannot fetch pages.");
            alert("Critical error: User ID not available for loading pages.");
            return;
        }
        console.log(`Attempting to fetch pages for user: ${window.currentAacUserId}`);
        
        // Use the authenticatedFetch exposed to window by the inline script
        const response = await window.authenticatedFetch('/pages', {
            method: 'GET',
        });
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`HTTP error! status: ${response.status} - ${errorText}`);
        }
        const fetchedPages = await response.json();
        allUserPages = fetchedPages;
        populateSelectPage(allUserPages);
        console.log(`Loaded ${allUserPages.length} pages for user: ${window.currentAacUserId || 'N/A'}`);
        console.log("admin_pages.js: Fetched pages data:", allUserPages);
    } catch (error) {
        console.error('Error loading pages:', error);
        alert(`Failed to load pages: ${error.message}`);
        allUserPages = [];
        populateSelectPage([]);
        clearPageForm();
        renderButtons([]);
    }
}


/**
 * Populates the page selection dropdown.
 */
function populateSelectPage(pagesData) {
    const currentSelectedPageName = selectPage.value; // Store current value before clearing
    selectPage.innerHTML = '<option value="">-- Select or Create New Page --</option>'; // Always first option

    pagesData.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.displayName || page.name; // Display displayName or name
        selectPage.appendChild(option);
    });

    let pageToSelect = ""; // What we'll try to select initially
    // Try to re-select the previously chosen page (e.g., after a save/delete)
    if (currentSelectedPageName && pagesData.some(p => p.name === currentSelectedPageName)) {
        pageToSelect = currentSelectedPageName;
    } 
    // If 'home' page exists, default to it
    else if (pagesData.some(p => p.name === "home")) {
        pageToSelect = "home"; 
    } 
    // If no 'home' page, but there are other pages, select the first one
    else if (pagesData.length > 0) {
        pageToSelect = pagesData[0].name; 
    }
    // If no pages at all, pageToSelect remains ""

    selectPage.value = pageToSelect; // Set the value in the dropdown

    // Manually trigger handlePageSelected() if a page was selected,
    // as a 'change' event might not fire if the value is programmatically set or doesn't actually change.
    if (pageToSelect) { // Only call if a page should be selected
        handlePageSelected(); 
    } else { // If no page found or selected "Select or Create New Page"
        clearPageForm(); 
        renderButtons([]); 
        currentPageData = null;
    }
}

/**
 * Handles selection of a page from the dropdown.
 */
function handlePageSelected() {
    const selectedPageName = selectPage.value;
    if (selectedPageName === "") {
        clearPageForm();
        renderButtons([]);
        currentPageData = null;
        return;
    }

    // Find the selected page data from the globally loaded 'allUserPages' array
    currentPageData = allUserPages.find(p => p.name === selectedPageName);

    if (currentPageData) {
        newPageNameInput.value = currentPageData.name;
        newPageDisplayNameInput.value = currentPageData.displayName || currentPageData.name;

        // Disable editing name or deleting for the 'home' page
        newPageNameInput.disabled = (currentPageData.name.toLowerCase() === "home");
        deletePageButton.disabled = (currentPageData.name.toLowerCase() === "home");
        createUpdatePageBtn.textContent = "Update Page"; // Change button text

        renderButtons(currentPageData.buttons);
        initialPageDataString = JSON.stringify(currentPageData); // Store initial state for revert
    } else {
        console.error(`Selected page '${selectedPageName}' not found in loaded pages data (allUserPages).`);
        clearPageForm();
        renderButtons([]);
    }
}

/**
 * Clears the page form fields and associated state.
 */
function clearPageForm() {
    newPageNameInput.value = '';
    newPageDisplayNameInput.value = '';
    newPageNameInput.disabled = false; // Enable name input for new pages (default)
    deletePageButton.disabled = true; // Disable delete for new/no selection (default)
    createUpdatePageBtn.textContent = "Create Page"; // Reset button text
    currentPageData = null; // Clear currently edited page data
    initialPageDataString = ''; // Clear initial state
}

/**
 * Renders the buttons for the current page in the grid.
 */
function renderButtons(buttonsData) {
    if (!buttonGrid) { console.error("buttonGrid element not found!"); return; }
    buttonGrid.innerHTML = ''; // Clear existing buttons before rendering new ones

    // Create 100 cells for the grid (10 rows of 10 cols)
    for (let i = 0; i < 100; i++) {
        const cell = document.createElement('div');
        cell.className = 'gridCell'; // Apply base cell styles (from CSS)
        cell.dataset.rowIndex = Math.floor(i / 10);
        cell.dataset.colIndex = i % 10;
        // cell.dataset.originalIndex = i; // Not strictly needed for logic, can keep or remove

        // Display row/col index at the top of each cell
        const buttonIndexSpan = document.createElement('span');
        buttonIndexSpan.textContent = `(${cell.dataset.rowIndex}, ${cell.dataset.colIndex})`;
        buttonIndexSpan.className = 'text-xs text-gray-500 mb-1';
        cell.appendChild(buttonIndexSpan);

        // Find existing button data for this specific cell (if any)
        let buttonData = buttonsData.find(btn => 
            parseInt(btn.row) === parseInt(cell.dataset.rowIndex) && parseInt(btn.col) === parseInt(cell.dataset.colIndex)
        );

        // If no button data for this cell, use a default empty structure for inputs
        if (!buttonData) {
            buttonData = { 
                ...DEFAULT_PAGE_BUTTON_STRUCTURE, // Use default structure for empty fields
                row: parseInt(cell.dataset.rowIndex), 
                col: parseInt(cell.dataset.colIndex) 
            };
        }

        // Create and append input fields for button properties
        const textInput = document.createElement('input');
        textInput.type = 'text';
        textInput.placeholder = 'Button Text (display)';
        textInput.value = buttonData.text || ''; // Pre-fill
        textInput.dataset.field = 'text'; // Data attribute to identify field
        cell.appendChild(textInput);

        const speechInput = document.createElement('input');
        speechInput.type = 'text';
        speechInput.placeholder = 'Speech Phrase (optional)';
        speechInput.value = buttonData.speechPhrase || '';
        speechInput.dataset.field = 'speechPhrase';
        cell.appendChild(speechInput);

        const llmQueryInput = document.createElement('textarea');
        llmQueryInput.placeholder = 'LLM Query (optional)';
        llmQueryInput.value = buttonData.LLMQuery || '';
        llmQueryInput.dataset.field = 'LLMQuery';
        llmQueryInput.rows = 2; // Default rows for textarea
        cell.appendChild(llmQueryInput);

        const targetPageInput = document.createElement('input');
        targetPageInput.type = 'text';
        targetPageInput.placeholder = 'Target Page (navigation)';
        targetPageInput.value = buttonData.targetPage || '';
        targetPageInput.dataset.field = 'targetPage';
        cell.appendChild(targetPageInput);

        const queryTypeInput = document.createElement('input');
        queryTypeInput.type = 'text';
        queryTypeInput.placeholder = 'Query Type (e.g., options)';
        queryTypeInput.value = buttonData.queryType || '';
        queryTypeInput.dataset.field = 'queryType';
        cell.appendChild(queryTypeInput);

        // Hidden checkbox
        const hiddenCheckboxContainer = document.createElement('div');
        hiddenCheckboxContainer.className = 'flex items-center justify-center mt-2';
        const hiddenCheckbox = document.createElement('input');
        hiddenCheckbox.type = 'checkbox';
        hiddenCheckbox.id = `hidden-${i}`; // Unique ID for label
        hiddenCheckbox.checked = buttonData.hidden === true; // Ensure boolean comparison
        hiddenCheckbox.dataset.field = 'hidden';
        hiddenCheckboxContainer.appendChild(hiddenCheckbox);
        const hiddenLabel = document.createElement('label');
        hiddenLabel.htmlFor = `hidden-${i}`; // Link label to checkbox
        hiddenLabel.textContent = 'Hidden';
        hiddenLabel.className = 'ml-2 text-sm text-gray-700 cursor-pointer'; // Add cursor for UX
        hiddenCheckboxContainer.appendChild(hiddenLabel);
        cell.appendChild(hiddenCheckboxContainer);

        // Add the cell to the button grid container
        buttonGrid.appendChild(cell);
    }
}

/**
 * Gathers button data from the grid's input fields.
 */
function getButtonsDataFromGrid() {
    const buttons = [];
    // Iterate through each 'gridCell' element
    document.querySelectorAll('#buttonGrid .gridCell').forEach(cell => {
        const row = parseInt(cell.dataset.rowIndex);
        const col = parseInt(cell.dataset.colIndex);

        // Get values from input elements within the current cell
        const text = cell.querySelector('[data-field="text"]').value.trim();
        const speechPhrase = cell.querySelector('[data-field="speechPhrase"]').value.trim(); // .trim() is good
        const llmQuery = cell.querySelector('[data-field="LLMQuery"]').value.trim();
        const targetPage = cell.querySelector('[data-field="targetPage"]').value.trim();
        const queryType = cell.querySelector('[data-field="queryType"]').value.trim();
        const hidden = cell.querySelector('[data-field="hidden"]').checked; // Boolean from checkbox

        // Only include buttons that have text content OR are explicitly marked as hidden.
        // This allows saving empty but hidden cells if desired.
        if (text || hidden) {
            buttons.push({
                row: row,
                col: col,
                text: text,
                // Use null for empty strings instead of empty strings, matches backend Pydantic Optional[str]
                speechPhrase: speechPhrase || null, 
                LLMQuery: llmQuery || null,
                targetPage: targetPage || null,
                queryType: queryType || null,
                hidden: hidden // Boolean value
            });
        }
    });
    return buttons;
}


/**
 * Handles creation or update of a page.
 * Determines whether to POST (create) or PUT (update) based on currentPageData state.
 */
async function createUpdatePage() {
    const pageName = newPageNameInput.value.trim(); // Get page name from input
    const displayName = newPageDisplayNameInput.value.trim(); // Get display name from input

    if (!pageName) {
        alert("Page Name cannot be empty.");
        newPageNameInput.focus(); // Focus on the problematic input
        return;
    }

    const currentButtons = getButtonsDataFromGrid(); // Gather buttons from the grid

    const pagePayload = { // Construct the data payload for the API
        name: pageName,
        displayName: displayName || pageName, // Use display name if provided, else page name
        buttons: currentButtons // Array of button objects
    };

    let response;
    try {
        // Determine if updating an existing page or creating a new one
        // An update occurs if currentPageData exists AND its name matches the input name
        if (currentPageData && currentPageData.name === pageName) {
            console.log(`Attempting to UPDATE page "${pageName}" for user ${window.currentAacUserId}.`);
            pagePayload.originalName = currentPageData.name;
            response = await authenticatedFetch('/pages', { // Use authenticatedFetch
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' }, // Only Content-Type needed here
                body: JSON.stringify(pagePayload)
            });
        } else {
            console.log(`Attempting to CREATE new page "${pageName}" for user ${window.currentAacUserId}.`);
            if (allUserPages.some(p => p.name === pageName)) { /* ... */ }
            response = await authenticatedFetch('/pages', { // Use authenticatedFetch
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(pagePayload)
            });
        }

        if (!response.ok) { // Check for HTTP errors (4xx, 5xx)
            const errorData = await response.json().catch(() => ({})); // Try to parse JSON error, fallback to empty object
            throw new Error(errorData.detail || `Server responded with status: ${response.status}`);
        }

        alert('Page saved successfully!');
        await loadPages(); // Reload pages list to update dropdown and available pages after save
        selectPage.value = pageName; // Re-select the saved page in the dropdown
        selectPage.dispatchEvent(new Event('change')); // Manually trigger change to load its buttons/update form

    } catch (error) {
        console.error('Error saving page:', error);
        alert(`Error saving page: ${error.message}`);
    }
}


/**
 * Handles page deletion.
 */
async function deletePage() {
    // Prevent deletion if no page is selected or if it's the 'home' page
    if (!currentPageData || currentPageData.name.toLowerCase() === "home") { // Use .toLowerCase() for robustness
        alert("Cannot delete the 'home' page or no page is currently selected.");
        return;
    }

    if (!confirm(`Are you sure you want to delete the page "${currentPageData.displayName || currentPageData.name}"? This action cannot be undone.`)) {
        return; // If user cancels
    }

    try {
        console.log(`Attempting to DELETE page "${currentPageData.name}" for user ${currentUserId}.`);
        const response = await authenticatedFetch(`/pages/${encodeURIComponent(currentPageData.name)}`, { // Use authenticatedFetch
            method: 'DELETE',
            // No headers needed here, authenticatedFetch adds them
        });

        if (!response.ok) { // Check for HTTP errors
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.detail || `Server responded with status: ${response.status}`);
        }

        alert('Page deleted successfully!');
        clearPageForm(); // Clear the form and grid
        renderButtons([]); // Ensure grid is visually cleared
        await loadPages(); // Reload all pages to update state and dropdown

        // After deletion, attempt to select 'home' page if it exists, otherwise clear selection.
        if (allUserPages.some(p => p.name === "home")) {
            selectPage.value = "home";
            selectPage.dispatchEvent(new Event('change')); // Trigger change to display home's buttons
        } else {
            selectPage.value = ""; // No home, no other pages, clear selection
            selectPage.dispatchEvent(new Event('change')); // Trigger to clear form/grid
        }
    } catch (error) {
        console.error('Error deleting page:', error);
        alert(`Error deleting page: ${error.message}`);
    }
}

/**
 * Reverts changes in the button grid to the state when the page was last loaded or saved.
 */
function revertPage() {
    // Only revert if we have a current page and its initial state was stored
    if (currentPageData && initialPageDataString) {
        const parsedInitialData = JSON.parse(initialPageDataString);
        // Re-render the buttons based on the stored initial state
        renderButtons(parsedInitialData.buttons || []); 
        alert('Changes reverted to last saved state.');
    } else {
        alert('No pending changes to revert for the current page.');
    }
}

// --- Event Listeners for Initialization --
// 1. Listen for the custom event dispatched by the inline script
document.addEventListener('adminUserContextReady', () => {
    cconsole.log("admin_pages.js: 'adminUserContextReady' event received by listener.");
    authContextIsReady();
});

// 2. Check for the global flag immediately.
// This handles the race condition where the inline script's event fires
// before this deferred script's listener is attached.
if (window.adminContextInitializedByInlineScript === true) {
    console.log("admin_pages.js: Global flag 'adminContextInitializedByInlineScript' was already true on script load.");
    authContextIsReady();
}

// 3. Listen for DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
    console.log("admin_pages.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage(); // Attempt to initialize the page
});