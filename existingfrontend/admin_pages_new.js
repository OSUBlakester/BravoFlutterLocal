// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

// DOM Elements
let pageForm = null;
let deletePageButton = null;
let selectPage = null;
let buttonGrid = null;
let newPageNameInput = null;
let newPageDisplayNameInput = null;
let createUpdatePageBtn = null;
let revertPageBtn = null;
let saveButtonsBtn = null; 
let helpWizardBtn = null;

// Modal Elements
let buttonEditorModal = null;
let helpWizardModal = null;

let hamburgerBtn = null;
let adminNavDropdown = null;

// --- State Variables ---
let allUserPages = [];
let currentPageData = null;
let initialPageDataString = '';
let currentEditingButton = null; // {row, col} of button being edited
let draggedButton = null;

// --- Constants ---
const GRID_ROWS = 10;
const GRID_COLS = 10;

const DEFAULT_PAGE_BUTTON_STRUCTURE = {
    text: "",
    LLMQuery: "",
    targetPage: "",
    queryType: "options", // Always options now
    speechPhrase: null,
    hidden: false
};

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("admin_pages.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        assignDOMElements();
        
        if (!validateDOMElements()) {
            console.error("CRITICAL ERROR: Essential DOM elements not found.");
            return;
        }

        // Setup Event Listeners
        setupEventListeners();

        // Load initial data
        await loadPages();
    }
}

function assignDOMElements() {
    pageForm = document.getElementById('pageForm');
    deletePageButton = document.getElementById('deletePage');
    selectPage = document.getElementById('selectPage');
    buttonGrid = document.getElementById('buttonGrid');
    newPageNameInput = document.getElementById('newPageName');
    newPageDisplayNameInput = document.getElementById('newPageDisplayName');
    createUpdatePageBtn = document.getElementById('createUpdatePageBtn');
    revertPageBtn = document.getElementById('revertPageBtn');
    saveButtonsBtn = document.getElementById('saveButtonsBtn');
    helpWizardBtn = document.getElementById('helpWizardBtn');
    
    // Modal elements
    buttonEditorModal = document.getElementById('buttonEditorModal');
    helpWizardModal = document.getElementById('helpWizardModal');
    
    hamburgerBtn = document.getElementById('hamburger-btn');
    adminNavDropdown = document.getElementById('admin-nav-dropdown');
}

function validateDOMElements() {
    const required = [
        pageForm, selectPage, buttonGrid, newPageNameInput, 
        newPageDisplayNameInput, createUpdatePageBtn, deletePageButton, 
        revertPageBtn, saveButtonsBtn, helpWizardBtn,
        buttonEditorModal, helpWizardModal, hamburgerBtn, adminNavDropdown
    ];
    
    return required.every(element => element !== null);
}

function setupEventListeners() {
    // Page management
    selectPage.addEventListener('change', handlePageSelected);
    createUpdatePageBtn.addEventListener('click', createUpdatePage);
    deletePageButton.addEventListener('click', deletePage);
    revertPageBtn.addEventListener('click', revertPage);
    
    // Button grid controls
    saveButtonsBtn.addEventListener('click', createUpdatePage);
    helpWizardBtn.addEventListener('click', openHelpWizard);
    
    // Button Editor Modal
    document.getElementById('closeButtonEditor').addEventListener('click', closeButtonEditor);
    document.getElementById('cancelButtonEdit').addEventListener('click', closeButtonEditor);
    document.getElementById('saveButtonEdit').addEventListener('click', saveButtonEdit);
    document.getElementById('clearButtonBtn').addEventListener('click', clearCurrentButton);
    
    // Help Wizard Modal
    document.getElementById('closeHelpWizard').addEventListener('click', closeHelpWizard);
    document.getElementById('wizardCancelBtn').addEventListener('click', closeHelpWizard);
    document.getElementById('wizardNextBtn').addEventListener('click', wizardNext);
    document.getElementById('wizardPrevBtn').addEventListener('click', wizardPrev);
    document.getElementById('wizardAcceptBtn').addEventListener('click', wizardAccept);
    document.getElementById('wizardRejectBtn').addEventListener('click', wizardReject);
    
    // Real-time preview updates in button editor
    ['buttonText', 'speechPhrase', 'targetPage', 'llmQuery', 'buttonHidden'].forEach(id => {
        const element = document.getElementById(id);
        if (element) {
            element.addEventListener('input', updateButtonPreview);
        }
    });
    
    // Hamburger menu
    hamburgerBtn.addEventListener('click', function(event) {
        event.stopPropagation();
        const isExpanded = hamburgerBtn.getAttribute('aria-expanded') === 'true' || false;
        hamburgerBtn.setAttribute('aria-expanded', !isExpanded);
        adminNavDropdown.style.display = isExpanded ? 'none' : 'block';
    });
    
    document.addEventListener('click', function(event) {
        if (adminNavDropdown.style.display === 'block' && 
            !hamburgerBtn.contains(event.target) && 
            !adminNavDropdown.contains(event.target)) {
            adminNavDropdown.style.display = 'none';
            hamburgerBtn.setAttribute('aria-expanded', 'false');
        }
    });
}

// --- Visual Button Grid Functions ---
function renderButtonGrid() {
    if (!currentPageData || !buttonGrid) return;
    
    buttonGrid.innerHTML = '';
    
    for (let row = 0; row < GRID_ROWS; row++) {
        for (let col = 0; col < GRID_COLS; col++) {
            const button = createVisualButton(row, col);
            buttonGrid.appendChild(button);
        }
    }
}

function createVisualButton(row, col) {
    const buttonDiv = document.createElement('div');
    buttonDiv.className = 'visual-button';
    buttonDiv.dataset.row = row;
    buttonDiv.dataset.col = col;
    
    // Find button data for this position
    const buttonData = findButtonAtPosition(row, col);
    
    if (buttonData && buttonData.text) {
        buttonDiv.textContent = buttonData.text;
        buttonDiv.classList.add('has-content');
        
        // Add indicators based on button type
        addButtonIndicators(buttonDiv, buttonData);
        
        // Add visual styling based on content
        if (buttonData.LLMQuery) {
            buttonDiv.classList.add('has-ai');
        }
        if (buttonData.targetPage) {
            buttonDiv.classList.add('has-navigation');
        }
    } else {
        buttonDiv.textContent = 'Undefined';
        buttonDiv.classList.add('undefined');
    }
    
    // Add event listeners
    buttonDiv.addEventListener('click', () => openButtonEditor(row, col));
    
    // Drag and drop
    buttonDiv.draggable = true;
    buttonDiv.addEventListener('dragstart', handleDragStart);
    buttonDiv.addEventListener('dragover', handleDragOver);
    buttonDiv.addEventListener('drop', handleDrop);
    buttonDiv.addEventListener('dragend', handleDragEnd);
    
    return buttonDiv;
}

function addButtonIndicators(buttonDiv, buttonData) {
    if (buttonData.LLMQuery) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-ai';
        indicator.textContent = 'AI';
        indicator.title = 'Has AI Query';
        buttonDiv.appendChild(indicator);
    }
    
    if (buttonData.targetPage) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-nav';
        indicator.textContent = '→';
        indicator.title = 'Navigates to page';
        buttonDiv.appendChild(indicator);
    }
    
    if (buttonData.speechPhrase) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-speech';
        indicator.textContent = '♪';
        indicator.title = 'Has speech phrase';
        buttonDiv.appendChild(indicator);
    }
}

function findButtonAtPosition(row, col) {
    if (!currentPageData || !currentPageData.buttons) return null;
    return currentPageData.buttons.find(btn => btn.row === row && btn.col === col);
}

// --- Drag and Drop Functions ---
function handleDragStart(e) {
    draggedButton = {
        row: parseInt(e.target.dataset.row),
        col: parseInt(e.target.dataset.col)
    };
    e.target.classList.add('dragging');
}

function handleDragOver(e) {
    e.preventDefault();
    e.target.classList.add('drop-target');
}

function handleDrop(e) {
    e.preventDefault();
    e.target.classList.remove('drop-target');
    
    const targetRow = parseInt(e.target.dataset.row);
    const targetCol = parseInt(e.target.dataset.col);
    
    if (draggedButton && (draggedButton.row !== targetRow || draggedButton.col !== targetCol)) {
        swapButtons(draggedButton.row, draggedButton.col, targetRow, targetCol);
        renderButtonGrid(); // Re-render to show changes
    }
}

function handleDragEnd(e) {
    e.target.classList.remove('dragging');
    document.querySelectorAll('.drop-target').forEach(el => {
        el.classList.remove('drop-target');
    });
    draggedButton = null;
}

function swapButtons(fromRow, fromCol, toRow, toCol) {
    if (!currentPageData || !currentPageData.buttons) return;
    
    const fromButton = currentPageData.buttons.find(btn => btn.row === fromRow && btn.col === fromCol);
    const toButton = currentPageData.buttons.find(btn => btn.row === toRow && btn.col === toCol);
    
    // Remove both buttons from array
    currentPageData.buttons = currentPageData.buttons.filter(btn => 
        !(btn.row === fromRow && btn.col === fromCol) && 
        !(btn.row === toRow && btn.col === toCol)
    );
    
    // Add them back with swapped positions
    if (fromButton) {
        fromButton.row = toRow;
        fromButton.col = toCol;
        currentPageData.buttons.push(fromButton);
    }
    
    if (toButton) {
        toButton.row = fromRow;
        toButton.col = fromCol;
        currentPageData.buttons.push(toButton);
    }
}

// --- Button Editor Functions ---
function openButtonEditor(row, col) {
    currentEditingButton = { row, col };
    const buttonData = findButtonAtPosition(row, col) || { ...DEFAULT_PAGE_BUTTON_STRUCTURE };
    
    // Populate form
    document.getElementById('buttonText').value = buttonData.text || '';
    document.getElementById('speechPhrase').value = buttonData.speechPhrase || '';
    document.getElementById('llmQuery').value = buttonData.LLMQuery || '';
    document.getElementById('buttonHidden').checked = buttonData.hidden || false;
    
    // Populate target page dropdown
    populateTargetPageDropdown();
    document.getElementById('targetPage').value = buttonData.targetPage || '';
    
    // Update position info
    document.getElementById('positionInfo').textContent = `Row ${row + 1}, Column ${col + 1}`;
    
    // Update preview
    updateButtonPreview();
    
    // Show modal
    buttonEditorModal.classList.remove('hidden');
}

function closeButtonEditor() {
    buttonEditorModal.classList.add('hidden');
    currentEditingButton = null;
}

function saveButtonEdit() {
    if (!currentEditingButton) return;
    
    const buttonData = {
        row: currentEditingButton.row,
        col: currentEditingButton.col,
        text: document.getElementById('buttonText').value.trim(),
        speechPhrase: document.getElementById('speechPhrase').value.trim() || null,
        targetPage: document.getElementById('targetPage').value.trim(),
        LLMQuery: document.getElementById('llmQuery').value.trim(),
        queryType: "options", // Always options
        hidden: document.getElementById('buttonHidden').checked
    };
    
    // Remove existing button at this position
    if (!currentPageData.buttons) currentPageData.buttons = [];
    currentPageData.buttons = currentPageData.buttons.filter(btn => 
        !(btn.row === currentEditingButton.row && btn.col === currentEditingButton.col)
    );
    
    // Add new button if it has content
    if (buttonData.text || buttonData.LLMQuery || buttonData.targetPage) {
        currentPageData.buttons.push(buttonData);
    }
    
    // Re-render grid and close modal
    renderButtonGrid();
    closeButtonEditor();
}

function clearCurrentButton() {
    if (!currentEditingButton) return;
    
    // Remove button from data
    if (currentPageData && currentPageData.buttons) {
        currentPageData.buttons = currentPageData.buttons.filter(btn => 
            !(btn.row === currentEditingButton.row && btn.col === currentEditingButton.col)
        );
    }
    
    // Re-render and close
    renderButtonGrid();
    closeButtonEditor();
}

function updateButtonPreview() {
    const preview = document.getElementById('buttonPreview');
    const configSummary = document.getElementById('configSummary');
    
    const text = document.getElementById('buttonText').value.trim();
    const speechPhrase = document.getElementById('speechPhrase').value.trim();
    const targetPage = document.getElementById('targetPage').value.trim();
    const llmQuery = document.getElementById('llmQuery').value.trim();
    const hidden = document.getElementById('buttonHidden').checked;
    
    // Update preview button
    if (text) {
        preview.innerHTML = `<div class="visual-button has-content">${text}</div>`;
    } else {
        preview.innerHTML = `<div class="visual-button undefined">Undefined</div>`;
    }
    
    // Update configuration summary
    let buttonType = 'Empty';
    let action = 'No action';
    
    if (text) {
        if (llmQuery && targetPage) {
            buttonType = 'AI + Navigation';
            action = `Generate AI options, then navigate to "${targetPage}"`;
        } else if (llmQuery) {
            buttonType = 'AI Generation';
            action = 'Generate options using AI';
        } else if (targetPage) {
            buttonType = 'Navigation';
            action = `Navigate to "${targetPage}"`;
        } else {
            buttonType = 'Simple Button';
            action = speechPhrase ? `Say "${speechPhrase}"` : 'Display button text';
        }
    }
    
    document.getElementById('buttonTypeInfo').textContent = buttonType;
    document.getElementById('actionInfo').textContent = action;
}

function populateTargetPageDropdown() {
    const select = document.getElementById('targetPage');
    select.innerHTML = '<option value="">No page navigation</option>';
    
    allUserPages.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.displayName || page.name;
        select.appendChild(option);
    });
}



// --- Help Wizard Functions ---
let wizardStep = 1;
let wizardData = {};

function openHelpWizard() {
    wizardStep = 1;
    wizardData = {};
    
    // Populate wizard page dropdown
    const wizardTargetPage = document.getElementById('wizardTargetPage');
    wizardTargetPage.innerHTML = '<option value="">No, stay on current page</option>';
    allUserPages.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.displayName || page.name;
        wizardTargetPage.appendChild(option);
    });
    
    showWizardStep(1);
    helpWizardModal.classList.remove('hidden');
}

function closeHelpWizard() {
    helpWizardModal.classList.add('hidden');
    wizardStep = 1;
    wizardData = {};
}

function wizardNext() {
    // Collect current step data
    switch (wizardStep) {
        case 1:
            wizardData.name = document.getElementById('wizardButtonName').value.trim();
            if (!wizardData.name) {
                alert('Please enter a button name.');
                return;
            }
            break;
        case 2:
            wizardData.speechPhrase = document.getElementById('wizardSpeechPhrase').value.trim();
            break;
        case 3:
            wizardData.targetPage = document.getElementById('wizardTargetPage').value.trim();
            break;
        case 4:
            wizardData.aiDescription = document.getElementById('wizardAiDescription').value.trim();
            break;
    }
    
    wizardStep++;
    
    if (wizardStep > 4) {
        // Show preview
        showWizardPreview();
    } else {
        showWizardStep(wizardStep);
    }
}

function wizardPrev() {
    wizardStep--;
    if (wizardStep < 1) wizardStep = 1;
    showWizardStep(wizardStep);
}

function showWizardStep(step) {
    // Hide all steps
    document.querySelectorAll('.wizard-step').forEach(el => el.classList.add('hidden'));
    
    // Show current step
    document.getElementById(`wizardStep${step}`).classList.remove('hidden');
    
    // Update navigation buttons
    document.getElementById('wizardPrevBtn').classList.toggle('hidden', step === 1);
    document.getElementById('wizardNextBtn').classList.remove('hidden');
    document.getElementById('wizardAcceptBtn').classList.add('hidden');
    document.getElementById('wizardRejectBtn').classList.add('hidden');
}

function showWizardPreview() {
    // Hide all steps and show preview
    document.querySelectorAll('.wizard-step').forEach(el => el.classList.add('hidden'));
    document.getElementById('wizardPreview').classList.remove('hidden');
    
    // Generate LLM query from AI description
    if (wizardData.aiDescription) {
        wizardData.llmQuery = `Generate #LLMOptions ${wizardData.aiDescription}. Each option should be a clear, actionable choice for the user.`;
    }
    
    // Update preview
    const preview = document.getElementById('wizardButtonPreview');
    preview.innerHTML = `<div class="visual-button has-content">${wizardData.name}</div>`;
    
    // Update configuration preview
    const configPreview = document.getElementById('wizardConfigPreview');
    configPreview.innerHTML = `
        <div><strong>Button Name:</strong> ${wizardData.name}</div>
        ${wizardData.speechPhrase ? `<div><strong>Speech:</strong> "${wizardData.speechPhrase}"</div>` : ''}
        ${wizardData.targetPage ? `<div><strong>Navigation:</strong> Go to "${wizardData.targetPage}"</div>` : ''}
        ${wizardData.llmQuery ? `<div><strong>AI Query:</strong> ${wizardData.llmQuery}</div>` : ''}
    `;
    
    // Update navigation buttons
    document.getElementById('wizardNextBtn').classList.add('hidden');
    document.getElementById('wizardAcceptBtn').classList.remove('hidden');
    document.getElementById('wizardRejectBtn').classList.remove('hidden');
}

function wizardAccept() {
    // Find empty spot for new button
    const emptySpot = findEmptyGridSpot();
    if (!emptySpot) {
        alert('No empty spots available in the grid. Please clear a button first.');
        return;
    }
    
    // Create button data
    const buttonData = {
        row: emptySpot.row,
        col: emptySpot.col,
        text: wizardData.name,
        speechPhrase: wizardData.speechPhrase || null,
        targetPage: wizardData.targetPage || "",
        LLMQuery: wizardData.llmQuery || "",
        queryType: "options",
        hidden: false
    };
    
    // Add to current page
    if (!currentPageData.buttons) currentPageData.buttons = [];
    currentPageData.buttons.push(buttonData);
    
    // Re-render and close
    renderButtonGrid();
    closeHelpWizard();
}

function wizardReject() {
    wizardStep = 4; // Go back to AI description step
    showWizardStep(4);
}

function findEmptyGridSpot() {
    for (let row = 0; row < GRID_ROWS; row++) {
        for (let col = 0; col < GRID_COLS; col++) {
            if (!findButtonAtPosition(row, col)) {
                return { row, col };
            }
        }
    }
    return null;
}

// --- Page Management Functions (keeping existing logic) ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    isAuthContextReady = true;
    console.log("admin_pages.js: Auth context is ready. Stored flag.");
    initializePage();
}

function handlePageSelected() {
    const selectedPageName = selectPage.value;
    if (!selectedPageName) return;
    
    currentPageData = allUserPages.find(page => page.name === selectedPageName);
    if (currentPageData) {
        newPageNameInput.value = currentPageData.name;
        newPageDisplayNameInput.value = currentPageData.displayName || currentPageData.name;
        initialPageDataString = JSON.stringify(currentPageData);
        renderButtonGrid();
    }
}

async function loadPages() {
    try {
        console.log("Loading pages from backend...");
        const response = await window.authenticatedFetch('/pages');
        if (!response.ok) throw new Error(`Failed to load pages: ${response.statusText}`);
        
        allUserPages = await response.json();
        populatePageSelect();
        
        if (allUserPages.length > 0) {
            selectPage.value = allUserPages[0].name;
            handlePageSelected();
        }
    } catch (error) {
        console.error('Error loading pages:', error);
        alert('Failed to load pages. Please refresh the page.');
    }
}

function populatePageSelect() {
    selectPage.innerHTML = '';
    allUserPages.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.displayName || page.name;
        selectPage.appendChild(option);
    });
}

async function createUpdatePage() {
    const pageName = newPageNameInput.value.trim();
    const displayName = newPageDisplayNameInput.value.trim();
    
    if (!pageName || !displayName) {
        alert('Please enter both page name and display name.');
        return;
    }
    
    const pageData = {
        name: pageName.toLowerCase(),
        displayName: displayName,
        buttons: currentPageData ? currentPageData.buttons : []
    };
    
    try {
        const isUpdate = allUserPages.some(page => page.name === pageData.name);
        
        if (isUpdate) {
            pageData.originalName = pageData.name;
            const response = await window.authenticatedFetch('/pages', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(pageData)
            });
            
            if (!response.ok) throw new Error(`Failed to update page: ${response.statusText}`);
        } else {
            const response = await window.authenticatedFetch('/pages', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(pageData)
            });
            
            if (!response.ok) throw new Error(`Failed to create page: ${response.statusText}`);
        }
        
        await loadPages();
        alert(isUpdate ? 'Page updated successfully!' : 'Page created successfully!');
        
    } catch (error) {
        console.error('Error saving page:', error);
        alert('Failed to save page. Please try again.');
    }
}

async function deletePage() {
    const pageName = newPageNameInput.value.trim();
    if (!pageName) {
        alert('No page selected to delete.');
        return;
    }
    
    if (pageName === 'home') {
        alert('The home page cannot be deleted.');
        return;
    }
    
    if (!confirm(`Are you sure you want to delete the page "${pageName}"? This action cannot be undone.`)) {
        return;
    }
    
    try {
        const response = await window.authenticatedFetch(`/pages/${pageName}`, {
            method: 'DELETE'
        });
        
        if (!response.ok) throw new Error(`Failed to delete page: ${response.statusText}`);
        
        await loadPages();
        alert('Page deleted successfully!');
        
    } catch (error) {
        console.error('Error deleting page:', error);
        alert('Failed to delete page. Please try again.');
    }
}

function revertPage() {
    if (initialPageDataString) {
        currentPageData = JSON.parse(initialPageDataString);
        renderButtonGrid();
        alert('Changes reverted.');
    }
}

// --- Event Listeners for DOM and Auth ---
document.addEventListener('DOMContentLoaded', function() {
    console.log("admin_pages.js: DOM content loaded. Stored flag.");
    isDomContentLoaded = true;
    initializePage();
});

document.addEventListener('adminUserContextReady', function() {
    console.log("admin_pages.js: Received adminUserContextReady event. Calling authContextIsReady().");
    authContextIsReady();
});

// Fallback: Check if auth context already exists
if (typeof window.adminContextInitializedByInlineScript !== 'undefined' && window.adminContextInitializedByInlineScript) {
    console.log("admin_pages.js: Auth context already available. Calling authContextIsReady().");
    authContextIsReady();
}
