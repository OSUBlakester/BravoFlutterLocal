// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

// DOM Elements
let buttonGrid = null;
let buttonEditorModal = null;
let scrapingWizardModal = null;

// State Variables
let favoritesData = { buttons: [] };
let currentEditingButton = null; // {row, col} of button being edited
let draggedButton = null;
let currentScrapingConfig = null;

// Constants
const GRID_ROWS = 10;
const GRID_COLS = 10;

const DEFAULT_SCRAPING_CONFIG = {
    url: "",
    headline_selector: "",
    url_selector: "",
    url_attribute: "href",
    url_prefix: "",
    keywords: []
};

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("favorites_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        assignDOMElements();
        
        if (!validateDOMElements()) {
            console.error("CRITICAL ERROR: Essential DOM elements not found.");
            return;
        }

        // Setup Event Listeners
        setupEventListeners();

        // Load initial data
        await loadFavorites();
        renderGrid();
    }
}

function assignDOMElements() {
    buttonGrid = document.getElementById('buttonGrid');
    buttonEditorModal = document.getElementById('buttonEditorModal');
    scrapingWizardModal = document.getElementById('scrapingWizardModal');
}

function validateDOMElements() {
    const required = [buttonGrid, buttonEditorModal, scrapingWizardModal];
    return required.every(element => element !== null);
}

function setupEventListeners() {
    // Navigation - logout button
    document.getElementById('logout-button').addEventListener('click', async () => {
        if (window.authContext && window.authContext.signOut) {
            await window.authContext.signOut();
            window.location.href = 'auth.html';
        }
    });

    // Switch user button
    document.getElementById('switch-user-button').addEventListener('click', () => {
        window.location.href = 'admin.html';
    });

    // Action buttons
    document.getElementById('saveChangesBtn').addEventListener('click', saveFavorites);
    document.getElementById('clearAllBtn').addEventListener('click', clearAllTopics);

    // Button Editor Modal
    document.getElementById('closeEditorModal').addEventListener('click', closeButtonEditor);
    document.getElementById('cancelEditorBtn').addEventListener('click', closeButtonEditor);
    document.getElementById('buttonEditorForm').addEventListener('submit', saveButtonChanges);
    document.getElementById('deleteButtonBtn').addEventListener('click', deleteButton);
    document.getElementById('configureScrapingBtn').addEventListener('click', openScrapingWizard);

    // Scraping Wizard Modal
    document.getElementById('closeWizardModal').addEventListener('click', closeScrapingWizard);
    document.getElementById('step1NextBtn').addEventListener('click', () => showWizardStep(2));
    document.getElementById('step2BackBtn').addEventListener('click', () => showWizardStep(1));
    document.getElementById('step2NextBtn').addEventListener('click', () => showWizardStep(3));
    document.getElementById('step3BackBtn').addEventListener('click', () => showWizardStep(2));
    document.getElementById('testScrapingBtn').addEventListener('click', testScrapingConfiguration);
    document.getElementById('saveScrapingConfigBtn').addEventListener('click', saveScrapingConfiguration);

    // New simplified wizard
    setupTemplateButtons();
    document.getElementById('smartAnalyzeBtn').addEventListener('click', performSmartAnalysis);
    document.getElementById('testNowBtn').addEventListener('click', testCurrentConfiguration);
    document.getElementById('tryDifferentSiteBtn').addEventListener('click', () => showWizardStep(1));
    
    // Auto-fill URL prefix when base URL changes (kept for backwards compatibility)
    const anyWebsiteUrlInput = document.getElementById('anyWebsiteUrl');
    if (anyWebsiteUrlInput) {
        anyWebsiteUrlInput.addEventListener('input', (e) => {
            const url = e.target.value;
            updateSelectedConfig('manual', url);
        });
    }
}

// --- Data Management ---
async function loadFavorites() {
    try {
        console.log('loadFavorites called');
        showStatus('Loading favorites...', false);
        const response = await window.authenticatedFetch('/api/favorites');
        console.log('API response status:', response.status);
        if (!response.ok) {
            throw new Error(`HTTP error ${response.status}`);
        }
        favoritesData = await response.json();
        console.log('Loaded favoritesData:', favoritesData);
        
        // Ensure buttons array exists
        if (!favoritesData.buttons) {
            favoritesData.buttons = [];
            console.log('Initialized empty buttons array in loaded data');
        }
        
        showStatus('Favorites loaded successfully', false);
        setTimeout(() => showStatus('', false), 3000);
    } catch (error) {
        console.error('Error loading favorites:', error);
        showStatus(`Error loading favorites: ${error.message}`, true);
        favoritesData = { buttons: [] };
        console.log('Using default favoritesData:', favoritesData);
    }
}

async function saveFavorites() {
    try {
        showStatus('Saving favorites...', false);
        const response = await window.authenticatedFetch('/api/favorites', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(favoritesData)
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error ${response.status}`);
        }
        
        showStatus('Favorites saved successfully!', false);
        setTimeout(() => showStatus('', false), 3000);
    } catch (error) {
        console.error('Error saving favorites:', error);
        showStatus(`Error saving favorites: ${error.message}`, true);
    }
}

// --- Grid Management ---
function renderGrid() {
    console.log('renderGrid called');
    console.log('buttonGrid element:', buttonGrid);
    console.log('favoritesData:', favoritesData);
    
    if (!favoritesData || !buttonGrid) {
        console.error('Missing data or grid element:', { favoritesData, buttonGrid });
        return;
    }
    
    // Ensure buttons array exists
    if (!favoritesData.buttons) {
        favoritesData.buttons = [];
        console.log('Initialized empty buttons array');
    }
    
    buttonGrid.innerHTML = '';
    
    console.log(`Rendering grid: ${GRID_ROWS} rows x ${GRID_COLS} cols`);
    
    for (let row = 0; row < GRID_ROWS; row++) {
        for (let col = 0; col < GRID_COLS; col++) {
            const button = createVisualButton(row, col);
            buttonGrid.appendChild(button);
        }
    }
    
    console.log('Grid rendered, total buttons:', buttonGrid.children.length);
}

function createVisualButton(row, col) {
    const buttonDiv = document.createElement('div');
    buttonDiv.className = 'visual-button';
    buttonDiv.dataset.row = row;
    buttonDiv.dataset.col = col;
    
    // Find button data for this position
    const buttonData = findButtonAt(row, col);
    
    if (buttonData && buttonData.text) {
        buttonDiv.textContent = buttonData.text;
        buttonDiv.classList.add('has-content');
        
        // Add indicators based on button configuration
        addButtonIndicators(buttonDiv, buttonData);
        
        // Add visual styling
        if (buttonData.scraping_config && buttonData.scraping_config.url) {
            buttonDiv.classList.add('has-scraping');
        }
    } else {
        buttonDiv.textContent = 'Undefined';
        buttonDiv.classList.add('undefined');
    }
    
    // Add event listeners
    buttonDiv.addEventListener('click', () => editButton(row, col));
    
    // Drag and drop
    buttonDiv.draggable = true;
    buttonDiv.addEventListener('dragstart', (e) => handleDragStart(e, row, col));
    buttonDiv.addEventListener('dragover', handleDragOver);
    buttonDiv.addEventListener('drop', (e) => handleDrop(e, row, col));
    buttonDiv.addEventListener('dragend', handleDragEnd);
    
    return buttonDiv;
}

function addButtonIndicators(buttonDiv, buttonData) {
    if (buttonData.scraping_config && buttonData.scraping_config.url) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-scraping';
        indicator.textContent = '🌐';
        indicator.title = 'Has web scraping configuration';
        buttonDiv.appendChild(indicator);
    }
    
    if (buttonData.speechPhrase) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-speech';
        indicator.textContent = '♪';
        indicator.title = 'Has speech phrase';
        buttonDiv.appendChild(indicator);
    }

    if (buttonData.scraping_config && buttonData.scraping_config.keywords && buttonData.scraping_config.keywords.length > 0) {
        const indicator = document.createElement('div');
        indicator.className = 'button-indicator indicator-keywords';
        indicator.textContent = '🏷️';
        indicator.title = 'Has keyword filtering';
        buttonDiv.appendChild(indicator);
    }
}

function findButtonAt(row, col) {
    if (!favoritesData || !favoritesData.buttons) return null;
    return favoritesData.buttons.find(btn => btn.row === row && btn.col === col);
}

// --- Button Management ---
function editButton(row, col) {
    const buttonData = findButtonAt(row, col);
    
    if (buttonData) {
        // Editing existing button
        currentEditingButton = { row, col, isNew: false };
        currentScrapingConfig = { ...buttonData.scraping_config };
        
        // Populate form
        document.getElementById('buttonText').value = buttonData.text;
        document.getElementById('speechPhrase').value = buttonData.speechPhrase || '';
        updateScrapingConfigStatus();
        
        // Show delete button for existing buttons
        document.getElementById('deleteButtonBtn').style.display = 'inline-block';
        
        showButtonEditor();
    } else {
        // Creating new button - open editor first
        currentEditingButton = { row, col, isNew: true };
        currentScrapingConfig = { ...DEFAULT_SCRAPING_CONFIG };
        
        // Clear form
        document.getElementById('buttonText').value = '';
        document.getElementById('speechPhrase').value = '';
        updateScrapingConfigStatus();
        
        // Hide delete button for new buttons
        document.getElementById('deleteButtonBtn').style.display = 'none';
        
        showButtonEditor();
    }
}

function deleteButton() {
    if (!currentEditingButton || currentEditingButton.isNew) return;
    
    if (confirm('Are you sure you want to delete this topic?')) {
        // Remove from data
        favoritesData.buttons = favoritesData.buttons.filter(btn => 
            !(btn.row === currentEditingButton.row && btn.col === currentEditingButton.col)
        );
        
        closeButtonEditor();
        renderGrid();
        showStatus('Topic deleted', false);
    }
}

function clearAllTopics() {
    if (confirm('Are you sure you want to delete ALL topics? This cannot be undone.')) {
        favoritesData.buttons = [];
        renderGrid();
        showStatus('All topics cleared', false);
    }
}

// --- Drag and Drop ---
function handleDragStart(e, row, col) {
    draggedButton = { row, col };
    e.dataTransfer.effectAllowed = 'move';
}

function handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    e.target.classList.add('drag-over');
}

function handleDragLeave(e) {
    e.target.classList.remove('drag-over');
}

function handleDragEnd(e) {
    e.target.classList.remove('dragging');
    document.querySelectorAll('.drag-over').forEach(el => {
        el.classList.remove('drag-over');
    });
    draggedButton = null;
}

function handleDrop(e, targetRow, targetCol) {
    e.preventDefault();
    e.target.classList.remove('drag-over');
    
    if (!draggedButton) return;
    
    const sourceButton = findButtonAt(draggedButton.row, draggedButton.col);
    const targetButton = findButtonAt(targetRow, targetCol);
    
    if (sourceButton) {
        // Remove source button
        favoritesData.buttons = favoritesData.buttons.filter(btn => 
            !(btn.row === draggedButton.row && btn.col === draggedButton.col)
        );
        
        // If target position has a button, swap positions
        if (targetButton) {
            targetButton.row = draggedButton.row;
            targetButton.col = draggedButton.col;
        }
        
        // Move source button to target position
        sourceButton.row = targetRow;
        sourceButton.col = targetCol;
        
        // Add source button back
        favoritesData.buttons.push(sourceButton);
        
        renderGrid();
        showStatus('Topic moved', false);
    }
    
    draggedButton = null;
}

// --- Modal Management ---
function showButtonEditor() {
    buttonEditorModal.classList.add('show');
}

function closeButtonEditor() {
    buttonEditorModal.classList.remove('show');
    currentEditingButton = null;
}

function openScrapingWizard() {
    // Reset wizard state
    currentScrapingConfig = currentScrapingConfig || { ...DEFAULT_SCRAPING_CONFIG };
    
    // Clear any previous selections in Step 1
    document.getElementById('anyWebsiteUrl').value = '';
    document.getElementById('selectedConfig').innerHTML = 'Choose a popular site above or enter a URL for smart analysis';
    document.getElementById('step1NextBtn').disabled = true;
    
    // Clear Step 2 content
    document.getElementById('summaryContent').innerHTML = 'Configuration will appear here after Step 1';
    document.getElementById('testResultsDisplay').classList.add('hidden');
    document.getElementById('troubleshootingSection').classList.add('hidden');
    document.getElementById('step2NextBtn').disabled = true;
    
    showWizardStep(1);
    scrapingWizardModal.classList.add('show');
}

function closeScrapingWizard() {
    scrapingWizardModal.classList.remove('show');
    hideTestResults();
}

function showWizardStep(stepNumber) {
    // Hide all steps
    document.querySelectorAll('.wizard-step').forEach(step => {
        step.classList.remove('active');
    });
    
    // Show target step
    document.getElementById(`wizardStep${stepNumber}`).classList.add('active');
}

// --- Form Handling ---
function saveButtonChanges(e) {
    e.preventDefault();
    
    const text = document.getElementById('buttonText').value.trim();
    const speechPhrase = document.getElementById('speechPhrase').value.trim();
    
    if (!text) {
        showStatus('Topic name is required', true);
        return;
    }
    
    if (!currentScrapingConfig || !currentScrapingConfig.url) {
        showStatus('Web scraping configuration is required', true);
        return;
    }
    
    const buttonData = {
        row: currentEditingButton.row,
        col: currentEditingButton.col,
        text: text,
        speechPhrase: speechPhrase || null,
        scraping_config: { ...currentScrapingConfig },
        hidden: false
    };
    
    if (currentEditingButton.isNew) {
        // Add new button
        favoritesData.buttons.push(buttonData);
    } else {
        // Update existing button
        const index = favoritesData.buttons.findIndex(btn => 
            btn.row === currentEditingButton.row && btn.col === currentEditingButton.col
        );
        if (index >= 0) {
            favoritesData.buttons[index] = buttonData;
        }
    }
    
    closeButtonEditor();
    renderGrid();
    showStatus('Topic saved', false);
}

// --- Scraping Configuration ---
async function testScrapingConfiguration() {
    const config = getScrapingConfigFromForm();
    
    if (!config.url || !config.headline_selector || !config.url_selector) {
        showStatus('Please fill in all required fields first', true);
        return;
    }
    
    try {
        showTestResults('Testing configuration...', 'info');
        
        const response = await window.authenticatedFetch('/api/favorites/test-scraping', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ scraping_config: config })
        });
        
        const result = await response.json();
        
        if (result.success) {
            let message = `✅ ${result.message}`;
            if (result.sample_articles && result.sample_articles.length > 0) {
                message += '\\n\\nSample articles found:';
                result.sample_articles.slice(0, 3).forEach((article, i) => {
                    message += `\\n${i + 1}. ${article.title}`;
                });
            }
            showTestResults(message, 'success');
        } else {
            showTestResults(`❌ ${result.message}\\n\\nError: ${result.error}`, 'error');
        }
    } catch (error) {
        console.error('Error testing scraping config:', error);
        showTestResults(`❌ Test failed: ${error.message}`, 'error');
    }
}

function saveScrapingConfiguration() {
    const config = getScrapingConfigFromForm();
    
    if (!config.url || !config.headline_selector || !config.url_selector) {
        showStatus('Please fill in all required fields', true);
        return;
    }
    
    currentScrapingConfig = config;
    updateScrapingConfigStatus();
    closeScrapingWizard();
    showStatus('Scraping configuration saved', false);
}

function getScrapingConfigFromForm() {
    // In our simplified approach, we use the currentScrapingConfig that was set by templates or smart analysis
    // Step 3 might still have keywords field, so check for it
    const keywordsElement = document.getElementById('keywords');
    const keywords = keywordsElement ? keywordsElement.value.trim() : '';
    
    if (currentScrapingConfig) {
        // Update keywords if the field exists
        if (keywords) {
            currentScrapingConfig.keywords = keywords.split(',').map(k => k.trim()).filter(k => k);
        }
        return { ...currentScrapingConfig };
    } else {
        // Fallback to default config
        return {
            url: '',
            headline_selector: '',
            url_selector: '',
            url_attribute: 'href',
            url_prefix: '',
            keywords: keywords ? keywords.split(',').map(k => k.trim()).filter(k => k) : []
        };
    }
}

function updateScrapingConfigStatus() {
    const statusEl = document.getElementById('scrapingConfigStatus');
    if (currentScrapingConfig && currentScrapingConfig.url) {
        statusEl.textContent = `✅ Configured for: ${currentScrapingConfig.url}`;
        statusEl.className = 'mt-2 text-sm text-green-600';
    } else {
        statusEl.textContent = '⚠️ Web scraping not configured';
        statusEl.className = 'mt-2 text-sm text-orange-600';
    }
}

// --- Utility Functions ---
function showStatus(message, isError = false) {
    const statusArea = document.getElementById('status-message-area');
    if (!message) {
        statusArea.innerHTML = '';
        return;
    }
    
    const alertClass = isError ? 'bg-red-100 text-red-700 border-red-300' : 'bg-blue-100 text-blue-700 border-blue-300';
    statusArea.innerHTML = `
        <div class="border ${alertClass} px-4 py-3 rounded-lg">
            ${message}
        </div>
    `;
}

function showTestResults(message, type) {
    const resultsEl = document.getElementById('testResults');
    resultsEl.style.display = 'block';
    resultsEl.className = `test-results ${type}`;
    resultsEl.innerHTML = `<pre style="white-space: pre-wrap; margin: 0;">${message}</pre>`;
}

function hideTestResults() {
    document.getElementById('testResults').style.display = 'none';
}

// --- Simplified Template System ---
const SITE_TEMPLATES = {
    cnn: {
        name: 'CNN',
        baseUrl: 'https://www.cnn.com/',
        keywords: ['breaking news', 'politics', 'world'],
        config: {
            url: 'https://www.cnn.com/',
            headline_selector: 'h3.cd__headline a span',
            url_selector: 'h3.cd__headline a',
            url_attribute: 'href',
            url_prefix: 'https://www.cnn.com',
            keywords: ['breaking news', 'politics', 'world']
        }
    },
    bbc: {
        name: 'BBC News',
        baseUrl: 'https://www.bbc.com/news',
        keywords: ['UK', 'world news', 'breaking'],
        config: {
            url: 'https://www.bbc.com/news',
            headline_selector: 'h3[data-testid="card-headline"]',
            url_selector: 'a[data-testid="internal-link"]',
            url_attribute: 'href',
            url_prefix: 'https://www.bbc.com',
            keywords: ['UK', 'world news', 'breaking']
        }
    },
    espn: {
        name: 'ESPN',
        baseUrl: 'https://www.espn.com/',
        keywords: ['NFL', 'NBA', 'MLB', 'sports'],
        config: {
            url: 'https://www.espn.com/',
            headline_selector: 'h1 a, h2 a, h3 a',
            url_selector: 'h1 a, h2 a, h3 a',
            url_attribute: 'href',
            url_prefix: 'https://www.espn.com',
            keywords: ['NFL', 'NBA', 'MLB', 'sports']
        }
    },
    reddit: {
        name: 'Reddit',
        baseUrl: 'https://www.reddit.com/r/',
        keywords: [],
        config: {
            url: 'https://www.reddit.com/r/news/',
            headline_selector: 'h3[slot="title"]',
            url_selector: 'a[slot="full-post-link"]',
            url_attribute: 'href',
            url_prefix: '',
            keywords: []
        }
    }
};

function setupTemplateButtons() {
    const templateButtons = document.querySelectorAll('.site-template-btn');
    templateButtons.forEach(btn => {
        btn.addEventListener('click', () => {
            const siteKey = btn.dataset.site;
            const template = SITE_TEMPLATES[siteKey];
            if (template) {
                currentScrapingConfig = { ...template.config };
                
                // Set default keywords from template
                const keywordsInput = document.getElementById('step1Keywords');
                if (keywordsInput && template.keywords && template.keywords.length > 0) {
                    keywordsInput.value = template.keywords.join(', ');
                    // Update the config with these keywords
                    currentScrapingConfig.keywords = [...template.keywords];
                }
                
                updateSelectedConfig('template', template.name, template.baseUrl);
                enableStep1Next();
            }
        });
    });
}

function updateSelectedConfig(type, name, url = '') {
    const configEl = document.getElementById('selectedConfig');
    if (type === 'template') {
        configEl.innerHTML = `
            <div class="text-green-600">
                <i class="fas fa-check-circle mr-2"></i>
                <strong>${name}</strong> template selected
            </div>
            <div class="text-sm text-gray-600 mt-1">${url}</div>
        `;
    } else if (type === 'manual' && url) {
        configEl.innerHTML = `
            <div class="text-blue-600">
                <i class="fas fa-globe mr-2"></i>
                Ready for smart analysis
            </div>
            <div class="text-sm text-gray-600 mt-1">${url}</div>
        `;
    } else {
        configEl.innerHTML = 'Choose a popular site above or enter a URL for smart analysis';
    }
    
    // Update summary in step 2
    updateStep2Summary(type, name, url);
}

function updateStep2Summary(type, name, url) {
    const summaryEl = document.getElementById('summaryContent');
    if (type === 'template') {
        summaryEl.innerHTML = `
            <div><strong>Source:</strong> ${name} (pre-configured template)</div>
            <div><strong>URL:</strong> ${url}</div>
            <div class="text-green-600 mt-2">
                <i class="fas fa-check-circle mr-1"></i>
                This site is already configured and should work well
            </div>
        `;
    } else if (type === 'smart' && currentScrapingConfig) {
        summaryEl.innerHTML = `
            <div><strong>Source:</strong> Smart Analysis Result</div>
            <div><strong>URL:</strong> ${currentScrapingConfig.url}</div>
            <div class="text-blue-600 mt-2">
                <i class="fas fa-brain mr-1"></i>
                AI has analyzed this site and configured selectors automatically
            </div>
        `;
    } else {
        summaryEl.innerHTML = 'Configuration will appear here after Step 1';
    }
}

function enableStep1Next() {
    document.getElementById('step1NextBtn').disabled = false;
}

async function performSmartAnalysis() {
    const url = document.getElementById('anyWebsiteUrl').value.trim();
    if (!url) {
        showStatus('Please enter a website URL first', true);
        return;
    }
    
    try {
        // Show loading state
        const smartBtn = document.getElementById('smartAnalyzeBtn');
        const originalText = smartBtn.innerHTML;
        smartBtn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>AI is analyzing the website...';
        smartBtn.disabled = true;
        
        // Show analysis status
        showAnalysisStatus('analyzing', 'AI is visiting the website and analyzing its structure...');
        
        // Get sample article URL and keywords if provided
        const sampleArticleUrl = document.getElementById('sampleArticleUrl').value.trim();
        const keywordsInput = document.getElementById('step1Keywords').value.trim();
        const keywords = keywordsInput ? keywordsInput.split(',').map(k => k.trim()).filter(k => k) : [];
        
        // Call smart analysis API
        const response = await window.authenticatedFetch('/api/favorites/smart-analysis', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
                url: url,
                sample_article_url: sampleArticleUrl || null,
                keywords: keywords
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            currentScrapingConfig = result.config;
            // Make sure keywords are included in the config
            if (keywords.length > 0) {
                currentScrapingConfig.keywords = keywords;
            }
            updateSelectedConfig('smart', 'Smart Analysis', url);
            enableStep1Next();
            showAnalysisStatus('success', `✅ Success! Found ${result.articles_found || 'multiple'} articles. Configuration ready for testing.`);
            showStatus('Smart analysis complete! Configuration ready for testing.', false);
        } else {
            // Analysis failed - show helpful error and sample article option
            showAnalysisStatus('error', `❌ ${result.message}`);
            showSampleArticleOption(result.message);
            showStatus(`Smart analysis failed: ${result.message}. Try providing a sample article URL or use a pre-built template.`, true);
        }
    } catch (error) {
        console.error('Error in smart analysis:', error);
        showAnalysisStatus('error', '❌ Network error during analysis. Please check your internet connection.');
        showSampleArticleOption('Network error occurred');
        showStatus('Smart analysis failed due to network error. Try a pre-built template instead.', true);
    } finally {
        // Restore button state
        const smartBtn = document.getElementById('smartAnalyzeBtn');
        smartBtn.innerHTML = '<i class="fas fa-brain mr-2"></i>Smart Analysis - Let AI Figure It Out';
        smartBtn.disabled = false;
    }
}

function showAnalysisStatus(type, message) {
    const statusEl = document.getElementById('analysisStatus');
    const resultsEl = document.getElementById('analysisResults');
    
    statusEl.classList.remove('hidden');
    
    let bgClass = '';
    let textClass = '';
    
    switch (type) {
        case 'analyzing':
            bgClass = 'bg-blue-50 border-blue-200';
            textClass = 'text-blue-800';
            break;
        case 'success':
            bgClass = 'bg-green-50 border-green-200';
            textClass = 'text-green-800';
            break;
        case 'error':
            bgClass = 'bg-red-50 border-red-200';
            textClass = 'text-red-800';
            break;
    }
    
    resultsEl.className = `p-3 rounded-lg text-sm border ${bgClass} ${textClass}`;
    resultsEl.innerHTML = message;
}

function showSampleArticleOption(errorReason) {
    const sampleSection = document.getElementById('sampleArticleSection');
    sampleSection.classList.remove('hidden');
    
    // Update the smart analyze button text to suggest trying with sample
    const smartBtn = document.getElementById('smartAnalyzeBtn');
    smartBtn.innerHTML = '<i class="fas fa-brain mr-2"></i>Try Again with Sample Article URL';
    
    // Add helpful message
    const helpMessage = document.createElement('div');
    helpMessage.className = 'mt-2 p-3 bg-yellow-50 border border-yellow-200 rounded-lg text-sm text-yellow-800';
    helpMessage.innerHTML = `
        <div class="font-medium mb-1">💡 Need Help?</div>
        <div>Providing a sample article URL helps our AI understand the website structure better. 
        Copy the link to any article from this site and paste it above, then try the analysis again.</div>
    `;
    
    // Add help message if it doesn't exist
    const existingHelp = document.getElementById('analysisHelp');
    if (!existingHelp) {
        helpMessage.id = 'analysisHelp';
        document.getElementById('sampleArticleSection').appendChild(helpMessage);
    }
}

async function testCurrentConfiguration() {
    if (!currentScrapingConfig || !currentScrapingConfig.url) {
        showStatus('No configuration to test. Please complete Step 1 first.', true);
        return;
    }
    
    try {
        // Show loading state
        const testBtn = document.getElementById('testNowBtn');
        const originalText = testBtn.innerHTML;
        testBtn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Finding articles...';
        testBtn.disabled = true;
        
        // Test the configuration
        const response = await window.authenticatedFetch('/api/favorites/test-scraping', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ scraping_config: currentScrapingConfig })
        });
        
        const result = await response.json();
        
        // Show results
        const resultsEl = document.getElementById('testResultsDisplay');
        const previewEl = document.getElementById('articlesPreview');
        const troubleEl = document.getElementById('troubleshootingSection');
        
        if (result.success && result.sample_articles && result.sample_articles.length > 0) {
            // Success - show articles
            let html = '';
            result.sample_articles.slice(0, 10).forEach((article, i) => {
                html += `
                    <div class="border-b border-gray-200 py-2 last:border-b-0">
                        <div class="font-medium text-blue-600">${article.title}</div>
                        <div class="text-xs text-gray-500 mt-1">${article.url}</div>
                    </div>
                `;
            });
            if (result.sample_articles.length > 10) {
                html += `<div class="text-sm text-gray-500 text-center py-2">...and ${result.sample_articles.length - 10} more articles</div>`;
            }
            
            previewEl.innerHTML = html;
            resultsEl.classList.remove('hidden');
            troubleEl.classList.add('hidden');
            
            // Enable next step
            document.getElementById('step2NextBtn').disabled = false;
            showStatus(`Great! Found ${result.sample_articles.length} articles.`, false);
            
        } else {
            // Failed - show troubleshooting
            previewEl.innerHTML = `
                <div class="text-red-600 text-center py-4">
                    <i class="fas fa-exclamation-triangle mr-2"></i>
                    No articles found with this configuration
                </div>
            `;
            resultsEl.classList.remove('hidden');
            troubleEl.classList.remove('hidden');
            showStatus('No articles found. See troubleshooting tips below.', true);
        }
        
    } catch (error) {
        console.error('Error testing configuration:', error);
        showStatus('Test failed. Please try a different website.', true);
    } finally {
        // Restore button state
        const testBtn = document.getElementById('testNowBtn');
        testBtn.innerHTML = '<i class="fas fa-play mr-2"></i>Test - Show Me Articles From This Site';
        testBtn.disabled = false;
    }
}

// --- Event Listeners for DOM and Auth ---
document.addEventListener('DOMContentLoaded', () => {
    isDomContentLoaded = true;
    initializePage();
});

document.addEventListener('adminUserContextReady', () => {
    isAuthContextReady = true;
    initializePage();
});

// Fallback: Check if auth context already exists
if (typeof window.adminContextInitializedByInlineScript !== 'undefined' && window.adminContextInitializedByInlineScript) {
    console.log("favorites_admin.js: Auth context already available. Calling initializePage().");
    isAuthContextReady = true;
    initializePage();
}
