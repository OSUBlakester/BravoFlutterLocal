/**
 * Accent to Bravo Migration - Frontend Logic
 * 
 * Handles file upload, page selection, button display, and migration execution
 */

// Global state
let sessionId = null;
let mtiData = null;
let currentPageData = null;
let selectedButtons = new Set();
let existingBravoPages = [];
let currentTab = 'upload'; // Track current tab

// ===================================
// TAB MANAGEMENT
// ===================================

function showTab(tabName) {
    // Hide all tab content
    document.querySelectorAll('.tab-content').forEach(el => {
        el.classList.remove('active');
    });
    
    // Remove active state from all buttons
    document.querySelectorAll('.tab-button').forEach(el => {
        el.classList.remove('active');
    });
    
    // Show selected tab content
    const tabElement = document.querySelector(`.tab-content[data-tab="${tabName}"]`);
    if (tabElement) {
        tabElement.classList.add('active');
    }
    
    // Activate corresponding tab button
    const tabBtn = document.querySelector(`.tab-button[data-tab="${tabName}"]`);
    if (tabBtn) {
        tabBtn.classList.add('active');
    }
    
    currentTab = tabName;
}

function enableTab(tabName) {
    const tabBtn = document.querySelector(`.tab-button[data-tab="${tabName}"]`);
    if (tabBtn) {
        tabBtn.disabled = false;
    }
}

function disableTab(tabName) {
    const tabBtn = document.querySelector(`.tab-button[data-tab="${tabName}"]`);
    if (tabBtn) {
        tabBtn.disabled = true;
    }
}

// Wait for auth to be ready
document.addEventListener('migrationAuthReady', initializeMigrationTool);

function initializeMigrationTool() {
    console.log('Migration tool initialized');
    setupTabListeners();
    setupEventListeners();
    loadExistingBravoPages();
}

function setupTabListeners() {
    // Add click handlers to tab buttons
    document.querySelectorAll('.tab-button').forEach(btn => {
        btn.addEventListener('click', (e) => {
            if (!btn.disabled) {
                const tabName = btn.getAttribute('data-tab');
                showTab(tabName);
            }
        });
    });
}

// ===================================
// EVENT LISTENERS
// ===================================

function setupEventListeners() {
    // Upload zone
    const uploadZone = document.getElementById('uploadZone');
    const fileInput = document.getElementById('fileInput');
    
    uploadZone.addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', handleFileSelect);
    
    // Drag and drop
    uploadZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadZone.classList.add('dragover');
    });
    
    uploadZone.addEventListener('dragleave', () => {
        uploadZone.classList.remove('dragover');
    });
    
    uploadZone.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadZone.classList.remove('dragover');
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            handleFile(files[0]);
        }
    });

    // Page selection
    document.getElementById('pageSelect').addEventListener('change', handlePageSelect);

    // Button selection controls
    document.getElementById('selectAllBtn').addEventListener('click', selectAllButtons);
    document.getElementById('deselectAllBtn').addEventListener('click', deselectAllButtons);

    // Destination type radio buttons
    document.querySelectorAll('input[name="destinationType"]').forEach(radio => {
        radio.addEventListener('change', handleDestinationTypeChange);
    });

    // Page name inputs
    document.getElementById('newPageName').addEventListener('input', updateMigrationPreview);
    document.getElementById('existingPageSelect').addEventListener('change', updateMigrationPreview);

    // Use source page name button
    const useSourcePageNameBtn = document.getElementById('useSourcePageNameBtn');
    if (useSourcePageNameBtn) {
        useSourcePageNameBtn.addEventListener('click', fillNewPageNameFromSource);
    }

    // Migration execution
    document.getElementById('executeMigrationBtn').addEventListener('click', executeMigration);
    document.getElementById('resetBtn').addEventListener('click', resetMigration);

    // Modal close buttons
    document.getElementById('closeSuccessBtn').addEventListener('click', () => {
        document.getElementById('successModal').classList.add('hidden');
    });
    document.getElementById('closeErrorBtn').addEventListener('click', () => {
        document.getElementById('errorModal').classList.add('hidden');
    });
}

// ===================================
// FILE UPLOAD HANDLING
// ===================================

function handleFileSelect(event) {
    const file = event.target.files[0];
    if (file) {
        handleFile(file);
    }
}

async function handleFile(file) {
    if (!file.name.endsWith('.mti')) {
        showError('Please select an MTI file');
        return;
    }

    try {
        // Show progress
        document.getElementById('uploadProgress').classList.remove('hidden');
        updateProgress(20, 'Reading MTI file...');

        // Create form data for file upload
        const formData = new FormData();
        formData.append('file', file);

        updateProgress(40, 'Uploading to server...');

        // Upload MTI file to backend
        const response = await authenticatedFetch('/api/migration/upload-mti', {
            method: 'POST',
            body: formData
            // Don't set Content-Type header - browser will set it with boundary for multipart/form-data
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Upload failed');
        }

        const result = await response.json();
        updateProgress(60, 'Parsing MTI file...');

        // Store session ID
        sessionId = result.session_id;

        updateProgress(80, 'Loading page data...');

        // Fetch full parsed data
        const dataResponse = await authenticatedFetch(`/api/migration/pages/${sessionId}`);
        if (!dataResponse.ok) {
            throw new Error('Failed to fetch parsed page data');
        }

        mtiData = await dataResponse.json();
        updateProgress(100, 'Complete!');

        // Show uploaded file name
        const uploadedFileName = document.getElementById('uploadedFileName');
        const uploadedFileNameText = document.getElementById('uploadedFileNameText');
        if (uploadedFileName && uploadedFileNameText) {
            uploadedFileNameText.textContent = file.name;
            uploadedFileName.classList.remove('hidden');
        }

        // Update UI
        setTimeout(() => {
            document.getElementById('uploadProgress').classList.add('hidden');
            displayMTIData(mtiData);
        }, 500);

    } catch (error) {
        console.error('File upload error:', error);
        showError(`Failed to process MTI file: ${error.message}`);
        document.getElementById('uploadProgress').classList.add('hidden');
    }
}

function readFileAsText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = (e) => resolve(e.target.result);
        reader.onerror = (e) => reject(new Error('Failed to read file'));
        reader.readAsText(file);
    });
}

function updateProgress(percent, text) {
    document.getElementById('progressFill').style.width = `${percent}%`;
    document.getElementById('progressText').textContent = text;
}

// ===================================
// DATA DISPLAY
// ===================================

function displayMTIData(data) {
    // Update statistics
    document.getElementById('sessionStatus').textContent = 'Active';
    document.getElementById('totalPages').textContent = data.total_pages;
    document.getElementById('totalButtons').textContent = data.total_buttons;

    // Populate page dropdown
    populatePageDropdown(data.pages);

    // Enable Pages tab and move to it
    enableTab('pages');
    showTab('pages');
}

function populatePageDropdown(pages) {
    const select = document.getElementById('pageSelect');
    select.innerHTML = '<option value="">-- Select a page --</option>';

    // Convert to array and sort alphabetically
    const pageArray = Object.entries(pages).map(([id, data]) => ({
        id,
        name: data.inferred_name,
        buttonCount: data.button_count
    }));

    pageArray.sort((a, b) => a.name.localeCompare(b.name));

    // Add options
    pageArray.forEach(page => {
        const option = document.createElement('option');
        option.value = page.id;
        option.textContent = `${page.name} [${page.id}] - ${page.buttonCount} buttons`;
        select.appendChild(option);
    });
}

// ===================================
// PAGE & BUTTON SELECTION
// ===================================

function handlePageSelect(event) {
    const pageId = event.target.value;
    
    if (!pageId) {
        disableTab('buttons');
        disableTab('config');
        return;
    }

    currentPageData = mtiData.pages[pageId];
    selectedButtons.clear();
    displayButtons(currentPageData);

    // Enable button selection tab (don't auto-navigate)
    enableTab('buttons');
    updateSelectedCount();
}

function displayButtons(pageData) {
    const container = document.getElementById('buttonList');
    
    // Sort buttons by grid position (row, then column)
    const sortedButtons = [...pageData.buttons].sort((a, b) => {
        if (a.row !== b.row) return a.row - b.row;
        return a.col - b.col;
    });

    container.innerHTML = sortedButtons.map((btn, index) => `
        <div class="button-item" data-index="${index}" id="button-${index}">
            <label class="flex items-start cursor-pointer">
                <input type="checkbox" class="mt-1 mr-3 h-5 w-5 text-blue-600 rounded" 
                       onchange="toggleButtonSelection(${index})">
                <div class="flex-1">
                    <div class="flex items-center gap-2 mb-1">
                        <span class="button-grid-preview">[${btn.row},${btn.col}]</span>
                        <span class="font-semibold text-gray-900">${escapeHtml(btn.name)}</span>
                        ${btn.icon ? `<span class="icon-badge"><i class="fas fa-image mr-1"></i>${escapeHtml(btn.icon)}</span>` : ''}
                    </div>
                    
                    ${btn.speech ? `
                        <div class="speech-indicator text-sm mb-1">
                            <i class="fas fa-volume-up mr-1"></i>
                            Says: "${escapeHtml(btn.speech)}"
                        </div>
                    ` : '<div class="text-sm text-gray-500 italic mb-1">No speech</div>'}
                    
                    ${btn.navigation_target ? `
                        <div class="nav-indicator ${btn.navigation_type === 'TEMPORARY' ? 'temporary' : ''}">
                            <i class="fas fa-${btn.navigation_type === 'TEMPORARY' ? 'undo' : 'arrow-right'} mr-1"></i>
                            Navigate to: ${escapeHtml(mtiData.pages[btn.navigation_target]?.inferred_name || btn.navigation_target)}
                            ${btn.navigation_type === 'TEMPORARY' ? ' (auto-return)' : ''}
                        </div>
                    ` : ''}
                    
                    ${btn.functions ? `
                        <div class="text-xs text-purple-600 mt-1">
                            <i class="fas fa-cog mr-1"></i>${escapeHtml(btn.functions.join(', '))}
                        </div>
                    ` : ''}
                </div>
            </label>
        </div>
    `).join('');
}

function toggleButtonSelection(index) {
    const checkbox = document.querySelector(`#button-${index} input[type="checkbox"]`);
    const item = document.getElementById(`button-${index}`);
    
    if (checkbox.checked) {
        selectedButtons.add(index);
        item.classList.add('selected');
    } else {
        selectedButtons.delete(index);
        item.classList.remove('selected');
    }
    
    updateSelectedCount();
    
    // Enable/disable migration config tab
    if (selectedButtons.size > 0) {
        enableTab('config');
        updateMigrationPreview();
    } else {
        disableTab('config');
    }
}

function selectAllButtons() {
    const checkboxes = document.querySelectorAll('#buttonList input[type="checkbox"]');
    checkboxes.forEach((cb, index) => {
        cb.checked = true;
        selectedButtons.add(index);
        document.getElementById(`button-${index}`).classList.add('selected');
    });
    updateSelectedCount();
    enableTab('config');

    updateMigrationPreview();
}

function deselectAllButtons() {
    const checkboxes = document.querySelectorAll('#buttonList input[type="checkbox"]');
    checkboxes.forEach((cb, index) => {
        cb.checked = false;
        selectedButtons.delete(index);
        document.getElementById(`button-${index}`).classList.remove('selected');
    });
    updateSelectedCount();
    disableTab('config');
}

function updateSelectedCount() {
    document.getElementById('selectedButtons').textContent = selectedButtons.size;
}

// ===================================
// MIGRATION CONFIGURATION
// ===================================

function handleDestinationTypeChange() {
    const destType = document.querySelector('input[name="destinationType"]:checked').value;
    
    if (destType === 'new') {
        document.getElementById('newPageGroup').classList.remove('hidden');
        document.getElementById('existingPageGroup').classList.add('hidden');
    } else {
        document.getElementById('newPageGroup').classList.add('hidden');
        document.getElementById('existingPageGroup').classList.remove('hidden');
    }
    
    updateMigrationPreview();
}

async function loadExistingBravoPages() {
    try {
        const response = await authenticatedFetch('/pages');
        if (response.ok) {
            existingBravoPages = await response.json();
            populateExistingPagesDropdown();
        }
    } catch (error) {
        console.error('Failed to load existing pages:', error);
    }
}

function populateExistingPagesDropdown() {
    const select = document.getElementById('existingPageSelect');
    select.innerHTML = '<option value="">-- Select a page --</option>';
    
    existingBravoPages.forEach(page => {
        const option = document.createElement('option');
        option.value = page.name;
        option.textContent = page.displayName || page.name;
        select.appendChild(option);
    });
}

function updateMigrationPreview() {
    const destType = document.querySelector('input[name="destinationType"]:checked').value;
    const sortedButtons = [...currentPageData.buttons].sort((a, b) => {
        if (a.row !== b.row) return a.row - b.row;
        return a.col - b.col;
    });
    const selectedButtonsList = Array.from(selectedButtons).map(i => sortedButtons[i]);
    
    let previewHTML = '';
    
    if (destType === 'new') {
        const pageName = document.getElementById('newPageName').value || '(unnamed)';
        previewHTML = `
            <strong>Action:</strong> Create new Bravo page<br>
            <strong>Page Name:</strong> ${escapeHtml(pageName)}<br>
            <strong>Buttons to migrate:</strong> ${selectedButtons.size}<br><br>
            <strong>Selected buttons:</strong><br>
            ${selectedButtonsList.map(btn => `• ${escapeHtml(btn.name)} [${btn.row},${btn.col}]`).join('<br>')}
        `;
    } else {
        const existingPage = document.getElementById('existingPageSelect').value || '(not selected)';
        previewHTML = `
            <strong>Action:</strong> Add to existing Bravo page<br>
            <strong>Target Page:</strong> ${escapeHtml(existingPage)}<br>
            <strong>Buttons to add:</strong> ${selectedButtons.size}<br><br>
            <strong>Selected buttons:</strong><br>
            ${selectedButtonsList.map(btn => `• ${escapeHtml(btn.name)} [${btn.row},${btn.col}]`).join('<br>')}
        `;
    }
    
    document.getElementById('previewContent').innerHTML = previewHTML;
}

function fillNewPageNameFromSource() {
    if (!currentPageData) {
        showError('Please select a source page first');
        return;
    }

    const sourceName = (currentPageData.inferred_name || currentPageData.page_id || '').toString().trim();
    if (!sourceName) {
        showError('Source page name is not available');
        return;
    }

    const input = document.getElementById('newPageName');
    input.value = sourceName;
    input.dispatchEvent(new Event('input'));
    input.focus();
}

// ===================================
// MIGRATION EXECUTION
// ===================================

async function executeMigration() {
    const destType = document.querySelector('input[name="destinationType"]:checked').value;
    let destPageName;
    
    if (destType === 'new') {
        destPageName = document.getElementById('newPageName').value.trim();
        if (!destPageName) {
            showError('Please enter a page name');
            return;
        }
    } else {
        destPageName = document.getElementById('existingPageSelect').value;
        if (!destPageName) {
            showError('Please select a target page');
            return;
        }
    }
    
    if (selectedButtons.size === 0) {
        showError('Please select at least one button');
        return;
    }

    try {
        // Disable button
        const btn = document.getElementById('executeMigrationBtn');
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Migrating...';

        const response = await authenticatedFetch('/api/migration/import-buttons', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                session_id: sessionId,
                accent_page_id: currentPageData.page_id,
                selected_button_indices: Array.from(selectedButtons),
                destination_type: destType,
                destination_page_name: destPageName,
                create_navigation_pages: false
            })
        });

        if (!response.ok) {
            const error = await response.json();
            const errorMsg = error.detail || 'Migration failed';
            
            // Special handling for session not found
            if (errorMsg.includes('session not found') || errorMsg.includes('expired')) {
                throw new Error('Migration session expired. Please re-upload your MTI file to start a new session.');
            }
            
            throw new Error(errorMsg);
        }

        const result = await response.json();
        
        // Check for conflicts that need user resolution
        if (result.requires_confirmation) {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-check mr-2"></i>Execute Migration';
            await handleMigrationConflicts(result);
            return;
        }
        
        // Show success
        showSuccess(result);
        
        // Reset for next migration
        setTimeout(() => {
            resetForNextMigration();
        }, 2000);

    } catch (error) {
        console.error('Migration error:', error);
        showError(`Migration failed: ${error.message}`);
    } finally {
        const btn = document.getElementById('executeMigrationBtn');
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-rocket mr-2"></i>Execute Migration';
    }
}

function resetForNextMigration() {
    // Keep session active but reset selections for next migration
    selectedButtons.clear();
    
    // Reload Bravo pages dropdown to include newly created pages
    loadExistingBravoPages();
    
    // Reset migration config inputs
    disableTab('config');
    document.getElementById('newPageName').value = '';
    
    // Keep page selection visible so user can select another page
    // Keep button grid visible with current page
    
    // Update counts
    updateSelectedCount();
}

function resetMigration() {
    if (confirm('Start over? This will clear your current session.')) {
        sessionId = null;
        mtiData = null;
        currentPageData = null;
        selectedButtons.clear();
        
        document.getElementById('sessionStatus').textContent = 'Not Started';
        document.getElementById('totalPages').textContent = '0';
        document.getElementById('totalButtons').textContent = '0';
        document.getElementById('selectedButtons').textContent = '0';
        
        // Reset tabs
        disableTab('pages');
        disableTab('buttons');
        disableTab('config');
        showTab('upload');

        const uploadedFileName = document.getElementById('uploadedFileName');
        const uploadedFileNameText = document.getElementById('uploadedFileNameText');
        if (uploadedFileName && uploadedFileNameText) {
            uploadedFileNameText.textContent = '';
            uploadedFileName.classList.add('hidden');
        }
        
        document.getElementById('fileInput').value = '';
    }
}

// ===================================
// UTILITY FUNCTIONS
// ===================================

async function authenticatedFetch(url, options = {}) {
    const token = window.userAuthToken;
    
    if (!token) {
        throw new Error('Not authenticated');
    }
    
    const headers = {
        ...options.headers,
        'Authorization': `Bearer ${token}`
    };
    
    return fetch(url, { ...options, headers });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function showSuccess(result) {
    const message = `
        <p class="mb-2"><strong>${result.buttons_imported}</strong> buttons successfully migrated to page:</p>
        <p class="font-semibold text-lg">"${result.destination_page}"</p>
    `;
    
    document.getElementById('successMessage').innerHTML = message;
    document.getElementById('successModal').classList.remove('hidden');
}

// ===================================
// CONFLICT RESOLUTION
// ===================================

async function handleMigrationConflicts(conflictData) {
    const { conflicts, navigation_conflicts } = conflictData;
    
    // Handle page/button conflicts
    if (conflicts && conflicts.length > 0) {
        for (const conflict of conflicts) {
            if (conflict.type === 'page_exists') {
                if (conflict.is_home) {
                    showError('Cannot replace the Home page. Please choose a different page name or add to existing page.');
                    return;
                }
                
                const action = await showPageConflictDialog(conflict.page_name);
                if (action === 'cancel') {
                    return;
                }
                // Handle rename or replace based on action
                // TODO: Implement rename/replace logic
            } else if (conflict.type === 'button_exists') {
                const action = await showButtonConflictDialog(conflict.button_name, conflict.position);
                if (action === 'cancel') {
                    return;
                } else if (action === 'rename') {
                    const newName = await promptForNewName('button', conflict.button_name);
                    if (!newName) {
                        return; // User cancelled the rename
                    }
                    conflict.resolution = 'rename';
                    conflict.new_name = newName;
                } else if (action === 'replace') {
                    conflict.resolution = 'replace';
                }
            }
        }
    }
    
    // Handle navigation conflicts
    if (navigation_conflicts && navigation_conflicts.length > 0) {
        for (const navConflict of navigation_conflicts) {
            const action = await showNavigationConflictDialog(navConflict);
            if (action === 'cancel') {
                return;
            } else if (action === 'create') {
                navConflict.resolution = 'create_page';
            } else if (action === 'select') {
                const newTarget = await promptForPageSelection(navConflict.button_name);
                if (!newTarget) {
                    return; // User cancelled
                }
                navConflict.resolution = 'change_navigation';
                navConflict.new_target = newTarget;
            }
        }
    }
    
    // Re-execute migration with conflict resolutions
    await executeMigrationWithResolutions(conflictData, conflicts, navigation_conflicts);
}

function showPageConflictDialog(pageName) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white rounded-lg p-6 max-w-md shadow-xl">
                <h3 class="text-xl font-bold mb-4 text-red-600">
                    <i class="fas fa-exclamation-triangle mr-2"></i>Page Already Exists
                </h3>
                <p class="mb-6">A page named "<strong>${pageName}</strong>" already exists. What would you like to do?</p>
                <div class="flex flex-col gap-3">
                    <button class="conflict-action-btn bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" data-action="rename">
                        <i class="fas fa-edit mr-2"></i>Use a Different Name
                    </button>
                    <button class="conflict-action-btn bg-orange-600 text-white px-4 py-2 rounded hover:bg-orange-700" data-action="replace">
                        <i class="fas fa-sync mr-2"></i>Replace Existing Page
                    </button>
                    <button class="conflict-action-btn bg-gray-400 text-white px-4 py-2 rounded hover:bg-gray-500" data-action="cancel">
                        <i class="fas fa-times mr-2"></i>Cancel Migration
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        
        modal.querySelectorAll('.conflict-action-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const action = btn.dataset.action;
                document.body.removeChild(modal);
                resolve(action);
            });
        });
    });
}

function showButtonConflictDialog(buttonName, position) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white rounded-lg p-6 max-w-md shadow-xl">
                <h3 class="text-xl font-bold mb-4 text-orange-600">
                    <i class="fas fa-exclamation-triangle mr-2"></i>Button Position Conflict
                </h3>
                <p class="mb-6">A button already exists at position <strong>${position}</strong>. The button "<strong>${buttonName}</strong>" cannot be placed there. What would you like to do?</p>
                <div class="flex flex-col gap-3">
                    <button class="conflict-action-btn bg-orange-600 text-white px-4 py-2 rounded hover:bg-orange-700" data-action="replace">
                        <i class="fas fa-sync mr-2"></i>Replace Existing Button
                    </button>
                    <button class="conflict-action-btn bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" data-action="rename">
                        <i class="fas fa-edit mr-2"></i>Rename New Button
                    </button>
                    <button class="conflict-action-btn bg-gray-400 text-white px-4 py-2 rounded hover:bg-gray-500" data-action="cancel">
                        <i class="fas fa-times mr-2"></i>Cancel Migration
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        
        modal.querySelectorAll('.conflict-action-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const action = btn.dataset.action;
                document.body.removeChild(modal);
                resolve(action);
            });
        });
    });
}

function showNavigationConflictDialog(navConflict) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white rounded-lg p-6 max-w-md shadow-xl">
                <h3 class="text-xl font-bold mb-4 text-yellow-600">
                    <i class="fas fa-question-circle mr-2"></i>Navigation Target Missing
                </h3>
                <p class="mb-6">Button "<strong>${navConflict.button_name}</strong>" navigates to page "<strong>${navConflict.navigation_target_name}</strong>", which doesn't exist yet. What would you like to do?</p>
                <div class="flex flex-col gap-3">
                    <button class="conflict-action-btn bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700" data-action="create">
                        <i class="fas fa-plus mr-2"></i>Create New Page "${navConflict.navigation_target_name}"
                    </button>
                    <button class="conflict-action-btn bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" data-action="select">
                        <i class="fas fa-hand-pointer mr-2"></i>Select Different Navigation
                    </button>
                    <button class="conflict-action-btn bg-gray-400 text-white px-4 py-2 rounded hover:bg-gray-500" data-action="cancel">
                        <i class="fas fa-times mr-2"></i>Cancel Migration
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        
        modal.querySelectorAll('.conflict-action-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const action = btn.dataset.action;
                document.body.removeChild(modal);
                resolve(action);
            });
        });
    });
}

function promptForNewName(type, currentName) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white rounded-lg p-6 max-w-md shadow-xl">
                <h3 class="text-xl font-bold mb-4">
                    <i class="fas fa-edit mr-2"></i>Rename ${type === 'button' ? 'Button' : 'Page'}
                </h3>
                <p class="mb-4">Current name: <strong>${currentName}</strong></p>
                <input type="text" id="newNameInput" class="w-full border rounded px-3 py-2 mb-4" placeholder="Enter new name" value="${currentName}">
                <div class="flex gap-3 justify-end">
                    <button class="bg-gray-400 text-white px-4 py-2 rounded hover:bg-gray-500" id="cancelRename">
                        Cancel
                    </button>
                    <button class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" id="confirmRename">
                        <i class="fas fa-check mr-2"></i>Confirm
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        
        const input = document.getElementById('newNameInput');
        input.focus();
        input.select();
        
        document.getElementById('cancelRename').addEventListener('click', () => {
            document.body.removeChild(modal);
            resolve(null);
        });
        
        const confirmRename = () => {
            const newName = input.value.trim();
            if (newName) {
                document.body.removeChild(modal);
                resolve(newName);
            }
        };
        
        document.getElementById('confirmRename').addEventListener('click', confirmRename);
        input.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') confirmRename();
        });
    });
}

async function promptForPageSelection(buttonName) {
    // Get list of existing pages
    const response = await window.parent.authenticatedFetch('/pages');
    const pages = await response.json();
    
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        
        const pageOptions = pages.map(p => `<option value="${p.name}">${p.name}</option>`).join('');
        
        modal.innerHTML = `
            <div class="bg-white rounded-lg p-6 max-w-md shadow-xl">
                <h3 class="text-xl font-bold mb-4">
                    <i class="fas fa-hand-pointer mr-2"></i>Select Navigation Target
                </h3>
                <p class="mb-4">Select where button "<strong>${buttonName}</strong>" should navigate to:</p>
                <select id="pageSelect" class="w-full border rounded px-3 py-2 mb-4">
                    <option value="">-- Select a page --</option>
                    ${pageOptions}
                </select>
                <div class="flex gap-3 justify-end">
                    <button class="bg-gray-400 text-white px-4 py-2 rounded hover:bg-gray-500" id="cancelSelect">
                        Cancel
                    </button>
                    <button class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" id="confirmSelect">
                        <i class="fas fa-check mr-2"></i>Confirm
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        
        document.getElementById('cancelSelect').addEventListener('click', () => {
            document.body.removeChild(modal);
            resolve(null);
        });
        
        document.getElementById('confirmSelect').addEventListener('click', () => {
            const selected = document.getElementById('pageSelect').value;
            if (selected) {
                document.body.removeChild(modal);
                resolve(selected);
            }
        });
    });
}

async function executeMigrationWithResolutions(conflictData, conflicts, navigation_conflicts) {
    const btn = document.getElementById('executeMigrationBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Executing...';
    
    try {
        const response = await window.parent.authenticatedFetch('/api/migration/import-buttons', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                session_id: conflictData.session_id,
                accent_page_id: conflictData.accent_page_id,
                selected_button_indices: conflictData.selected_button_indices,
                destination_type: conflictData.destination_type,
                destination_page_name: conflictData.destination_page_name,
                create_navigation_pages: false,
                conflict_resolutions: {
                    conflicts: conflicts,
                    navigation_conflicts: navigation_conflicts
                }
            })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Migration failed');
        }

        const result = await response.json();
        
        // Show success with details
        showSuccess(result);
        
        // Reset for next migration
        setTimeout(() => {
            resetForNextMigration();
        }, 2000);

    } catch (error) {
        console.error('Migration error:', error);
        showError(`Migration failed: ${error.message}`);
    } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-rocket mr-2"></i>Execute Migration';
    }
}


function showError(message) {
    document.getElementById('errorMessage').textContent = message;
    document.getElementById('errorModal').classList.remove('hidden');
}

function showInfo(message) {
    const infoDiv = document.createElement('div');
    infoDiv.className = 'fixed top-4 right-4 bg-blue-100 border-l-4 border-blue-500 text-blue-700 p-4 rounded shadow-lg z-50';
    infoDiv.innerHTML = `
        <div class="flex items-center">
            <i class="fas fa-info-circle mr-2"></i>
            <span>${message}</span>
        </div>
    `;
    document.body.appendChild(infoDiv);
    
    setTimeout(() => {
        infoDiv.remove();
    }, 5000);
}

console.log('Accent Migration script loaded');
