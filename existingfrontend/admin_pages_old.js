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
        generateGrid(); 
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
        generateGrid(); 
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
        generateGrid(); 
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

        generateGrid(); 
        populateGrid(currentPageData.buttons || []); 

        initialPageDataString = JSON.stringify(currentPageData); // Store initial state for revert
    } else {
        console.error(`Selected page '${selectedPageName}' not found in loaded pages data (allUserPages).`);
        clearPageForm();
        generateGrid(); 
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

    generateGrid(); // Ensure grid is cleared/regenerated
}

/**
 * Generates the empty 10x10 grid structure in the DOM, including clear and arrow buttons.
 * (Adapted from old file, changed to 10x10)
 */
function generateGrid() {
    if (!buttonGrid) { console.error("buttonGrid element not found!"); return; }

        buttonGrid.innerHTML = '';
    for (let row = 0; row < 10; row++) { // 10 rows
        for (let col = 0; col < 10; col++) { // 10 columns
            const cell = document.createElement('div');
            cell.classList.add('gridCell');
            cell.dataset.row = row;
            cell.dataset.col = col;

            // Inputs for button properties (using placeholders for identification)
            const labelInput = document.createElement('input'); labelInput.type = 'text'; labelInput.placeholder = 'Label'; labelInput.setAttribute('aria-label', `Label R${row+1}C${col+1}`);
            const speechInput = document.createElement('input'); speechInput.type = 'text'; speechInput.placeholder = 'Speech'; speechInput.setAttribute('aria-label', `Speech R${row+1}C${col+1}`);
            const targetInput = document.createElement('input'); targetInput.type = 'text'; targetInput.placeholder = 'Target'; targetInput.setAttribute('aria-label', `Target R${row+1}C${col+1}`);
            const llmQueryInput = document.createElement('textarea'); llmQueryInput.placeholder = 'LLM Query'; llmQueryInput.setAttribute('aria-label', `LLM Query R${row+1}C${col+1}`);
            const querytypeInput = document.createElement('input'); querytypeInput.type = 'text'; querytypeInput.placeholder = 'Q Type'; querytypeInput.setAttribute('aria-label', `Q Type R${row+1}C${col+1}`);

            cell.appendChild(labelInput);
            cell.appendChild(speechInput);
            cell.appendChild(targetInput);
            cell.appendChild(llmQueryInput);
            cell.appendChild(querytypeInput);

            const hiddenLabel = document.createElement('label');
            hiddenLabel.className = 'flex items-center text-xs mt-1 cursor-pointer text-gray-600';
            const hiddenCheckbox = document.createElement('input');
            hiddenCheckbox.type = 'checkbox';
            hiddenCheckbox.className = 'hidden-checkbox mr-1 h-3 w-3 text-blue-600 border-gray-300 rounded focus:ring-blue-500';
            hiddenLabel.appendChild(hiddenCheckbox);
            hiddenLabel.appendChild(document.createTextNode('Hidden'));
            cell.appendChild(hiddenLabel);

            const clearCellButton = document.createElement('button');
            clearCellButton.type = 'button';
            clearCellButton.textContent = 'X';
            clearCellButton.title = 'Clear Cell';
            clearCellButton.classList.add('clear-cell-btn', 'absolute', 'top-1', 'right-1', 'text-xs', 'bg-red-200', 'hover:bg-red-300', 'p-1', 'rounded'); // Example styling
            clearCellButton.addEventListener('click', (e) => {
                e.preventDefault();
                const parentCell = e.target.closest('.gridCell');
                if (parentCell) {
                    parentCell.querySelectorAll('input[type="text"], textarea').forEach(input => input.value = '');
                    parentCell.querySelector('.hidden-checkbox').checked = false;
                }
            });

            const arrowButtonsContainer = document.createElement('div');
            arrowButtonsContainer.classList.add('arrowButtons'); // From your HTML for styling
            arrowButtonsContainer.appendChild(clearCellButton); // Add clear button to this container

            ['↑', '↓', '←', '→'].forEach((arrow, index) => {
                 const btn = document.createElement('button');
                 btn.type = 'button';
                 btn.textContent = arrow;
                 const offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]][index]; // Up, Down, Left, Right
                 btn.addEventListener('click', (e) => {
                      e.preventDefault();
                      moveButton(row, col, offsets[0], offsets[1]);
                 });
                 arrowButtonsContainer.appendChild(btn);
            });
            cell.appendChild(arrowButtonsContainer);
            buttonGrid.appendChild(cell);
        }
    }
}

/**
 * Populates the generated grid with data from saved buttons.
 * (From old file, compatible with generateGrid)
 */
function populateGrid(buttons) {
    if (!Array.isArray(buttons)) {
        console.warn("populateGrid received non-array for buttons:", buttons);
        buttons = []; // Default to empty array if invalid data
    }
    if (!buttonGrid) { // Add a guard for buttonGrid itself
        console.error("populateGrid: buttonGrid element not found! Cannot populate grid.");
        return;
    }
    
    // Ensure grid is visually clean before populating
    const allCells = buttonGrid.querySelectorAll('.gridCell');
    allCells.forEach(cell => {
        cell.querySelectorAll('input[type="text"], textarea').forEach(input => input.value = '');
        const hiddenCheckbox = cell.querySelector('.hidden-checkbox');
        if (hiddenCheckbox) hiddenCheckbox.checked = false;
    });

    const successfullyPlacedButtonsIndices = new Set(); // To track which buttons from the input array are placed by index

    // First pass: Place buttons with valid and unique row/col
    buttons.forEach((button, index) => {
        if (button.row != null && button.col != null &&
            typeof button.row === 'number' && !isNaN(button.row) &&
            typeof button.col === 'number' && !isNaN(button.col) &&
            button.row >= 0 && button.row < 10 && button.col >= 0 && button.col < 10) {

            const cellSelector = `.gridCell[data-row="${button.row}"][data-col="${button.col}"]`;
            const cell = buttonGrid.querySelector(cellSelector);

            if (cell) {
                const labelInput = cell.querySelector('input[placeholder="Label"]');
                if (labelInput && labelInput.value === '') { // Cell is visually empty
                    populateCellWithButtonData(cell, button);
                    successfullyPlacedButtonsIndices.add(index);
                } else {
                    console.warn(`populateGrid: Cell ${button.row},${button.col} already occupied. Button data:`, JSON.stringify(button));
                }
            } else {
                // This case should ideally not happen if generateGrid works correctly.
                console.warn(`populateGrid: Cell DOM element not found for valid row/col: ${button.row},${button.col}. Button data:`, JSON.stringify(button));
            }
        }
    });

    // Second pass: Place buttons that were not placed (due to null/invalid/duplicate row/col)
    buttons.forEach((button, index) => {
        if (successfullyPlacedButtonsIndices.has(index)) {
            return; // Skip if already placed
        }

        console.warn(`populateGrid: Button (index ${index}) has invalid/null/duplicate row/col or target cell was occupied. Attempting to place in next available empty cell. Data:`, JSON.stringify(button));
        
        let placedInFallback = false;
        for (let r = 0; r < 10; r++) {
            for (let c = 0; c < 10; c++) {
                const cellSelector = `.gridCell[data-row="${r}"][data-col="${c}"]`;
                const cell = buttonGrid.querySelector(cellSelector);
                if (cell) {
                    const labelInput = cell.querySelector('input[placeholder="Label"]');
                    const hiddenCheckbox = cell.querySelector('.hidden-checkbox');
                    if (labelInput && labelInput.value === '' && hiddenCheckbox && !hiddenCheckbox.checked) { // Check if cell is visually empty
                        populateCellWithButtonData(cell, button);
                        console.log(`Placed button "${button.text}" (originally invalid/null/duplicate pos) into visually empty cell ${r},${c}`);
                        placedInFallback = true;
                        break; 
                    }
                }
            }
            if (placedInFallback) break;
        }

        if (!placedInFallback) {
            console.warn(`Could not find an empty cell to place button "${button.text}" (index ${index}). Grid might be full.`);
        }

    });
}

/**
 * Moves button data between adjacent grid cells.
 * (From old file, adapted for 10x10 grid and new input identification)
 */
function moveButton(row, col, rowOffset, colOffset) {
    const newRow = row + rowOffset;
    const newCol = col + colOffset;

    if (newRow >= 0 && newRow < 10 && newCol >= 0 && newCol < 10) { 
        const cell = document.createElement('div');
        const currentCell = buttonGrid.querySelector(`.gridCell[data-row="${row}"][data-col="${col}"]`);
        const targetCell = buttonGrid.querySelector(`.gridCell[data-row="${newRow}"][data-col="${newCol}"]`);

        if (currentCell && targetCell) {
            const fieldsToSwap = [
                'input[placeholder="Label"]', 
                'input[placeholder="Speech"]', 
                'input[placeholder="Target"]', 
                'textarea[placeholder="LLM Query"]', 
                'input[placeholder="Q Type"]',
                '.hidden-checkbox' // For the checkbox state
            ];
            fieldsToSwap.forEach(selector => {
                const currentField = currentCell.querySelector(selector);
                const targetField = targetCell.querySelector(selector);
                if (currentField && targetField) {
                    const tempValue = (selector === '.hidden-checkbox') ? currentField.checked : currentField.value;
                    if (selector === '.hidden-checkbox') {
                        currentField.checked = targetField.checked;
                        targetField.checked = tempValue;
                    } else {
                        currentField.value = targetField.value;
                        targetField.value = tempValue;
                    }
                }
            });
        }
    }
}

/**
 * Gathers button data from the grid's input fields.
 */
function getButtonsDataFromGrid() {
    const buttons = [];
    // Iterate through each 'gridCell' element
    buttonGrid.querySelectorAll('.gridCell').forEach(cell => { 
        const row = parseInt(cell.dataset.row); 
        const col = parseInt(cell.dataset.col); 

        // Get values from input elements within the current cell
        const text = cell.querySelector('input[placeholder="Label"]').value.trim();
        const speechPhrase = cell.querySelector('input[placeholder="Speech"]').value.trim();
        const llmQuery = cell.querySelector('textarea[placeholder="LLM Query"]').value.trim();
        const targetPage = cell.querySelector('input[placeholder="Target"]').value.trim();
        const queryType = cell.querySelector('input[placeholder="Q Type"]').value.trim();
        const hidden = cell.querySelector('.hidden-checkbox').checked;

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

// Helper function to populate a cell with button data
function populateCellWithButtonData(cellElement, buttonData) {
    cellElement.querySelector('input[placeholder="Label"]').value = buttonData.text || '';
    cellElement.querySelector('input[placeholder="Speech"]').value = buttonData.speechPhrase || '';
    cellElement.querySelector('input[placeholder="Target"]').value = buttonData.targetPage || '';
    cellElement.querySelector('textarea[placeholder="LLM Query"]').value = buttonData.LLMQuery || '';
    cellElement.querySelector('input[placeholder="Q Type"]').value = buttonData.queryType || '';
    const hiddenCheckbox = cellElement.querySelector('.hidden-checkbox');
    if (hiddenCheckbox) {
        hiddenCheckbox.checked = buttonData.hidden || false;
    }
}

/**
 * Handles creation or update of a page.
 * Determines whether to POST (create) or PUT (update) based on currentPageData state.
 */
async function createUpdatePage() {
    const newPageNameValue = newPageNameInput.value.trim().toLowerCase(); // Always work with lowercase for logic
    const displayName = newPageDisplayNameInput.value.trim();

    if (!newPageNameValue) {
        alert("Page Name cannot be empty.");
        newPageNameInput.focus(); // Focus on the problematic input
        return;
    }

    const currentButtons = getButtonsDataFromGrid(); // Gather buttons from the grid

    const pagePayload = { // Construct the data payload for the API
        name: newPageNameValue, // Save with lowercase name
        displayName: displayName || newPageNameValue, 
        buttons: currentButtons // Array of button objects
    };

    let response;
    try {
        // Determine if updating an existing page or creating a new one
        // An update occurs if currentPageData exists AND its name matches the input name
        if (currentPageData && currentPageData.name === newPageNameValue) {
            // This condition might be too strict if casing changed.
            // A better check for "update" is simply if currentPageData exists.
            // The backend will handle if it's a rename or just content update.
            console.log(`Attempting to UPDATE page. Original loaded name: "${currentPageData.name}", New input name: "${newPageNameValue}"`);
            pagePayload.originalName = currentPageData.name.toLowerCase(); // Always send the loaded page's name (as lowercase) as originalName
            response = await authenticatedFetch('/pages', { // Use authenticatedFetch
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' }, // Only Content-Type needed here
                body: JSON.stringify(pagePayload)
            });
        } else {
            console.log(`Attempting to CREATE new page "${newPageNameValue}" for user ${window.currentAacUserId}.`);
            // Check if a page with this (now lowercased) name already exists
            if (allUserPages.some(p => p.name === newPageNameValue)) { 
                alert(`A page named "${newPageNameValue}" already exists. Please choose a different name or select the existing page to update.`);
                return;
            }            response = await authenticatedFetch('/pages', { 
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
        selectPage.value = newPageNameValue; // Re-select the saved/created page (which is lowercase)
        // Manually trigger the change handler to reload the form with the new/updated page data
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
        console.log(`Attempting to DELETE page "${currentPageData.name}" for user ${window.currentAacUserId}.`);
        const response = await authenticatedFetch(`/pages/${encodeURIComponent(currentPageData.name)}`, { // Use authenticatedFetch
            method: 'DELETE',
            // No headers needed here, authenticatedFetch adds them
        });

        if (!response.ok) { // Check for HTTP errors
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.detail || `Server responded with status: ${response.status}`);
        }

        alert('Page deleted successfully!');
        clearPageForm(); 
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
        // Regenerate grid and populate with initial data
        generateGrid();
        populateGrid(parsedInitialData.buttons || []);
        alert('Changes reverted to last saved state.');
    } else {
        alert('No pending changes to revert for the current page.');
    }
}

// --- Event Listeners for Initialization --
// 1. Listen for the custom event dispatched by the inline script
document.addEventListener('adminUserContextReady', () => {
    console.log("admin_pages.js: 'adminUserContextReady' event received by listener.");
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