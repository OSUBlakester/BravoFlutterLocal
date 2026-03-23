// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

// Volume Slider Handler
function volumeSliderHandler() {
    console.log('Volume slider moved to:', this.value);
    const display = document.getElementById('volumeDisplay');
    if (display) {
        display.textContent = `${this.value}/10`;
        console.log('Volume display updated to:', display.textContent);
    } else {
        console.error('Volume display element not found during slider change');
    }
}

// Setup volume slider function
function setupVolumeSliderNow() {
    console.log('Setting up volume slider...');
    const slider = document.getElementById('applicationVolume');
    const display = document.getElementById('volumeDisplay');
    
    if (slider && display) {
        slider.addEventListener('input', function() {
            display.textContent = `${this.value}/10`;
            console.log('Volume changed to:', this.value);
        });
        console.log('Volume slider setup complete');
        return true;
    } else {
        console.error('Volume slider elements not found');
        return false;
    }
}

// Try setup immediately
setupVolumeSliderNow();

// --- DOM Elements ---
// Settings elements
let scanDelayInput = null; 
const wakeWordInterjectionInput = document.getElementById('wakeWordInterjection');
const wakeWordNameInput = document.getElementById('wakeWordName');
const CountryCodeInput = document.getElementById('CountryCode');
const speechRateInput = document.getElementById('speechRate');
const LLMOptionsInput = document.getElementById('LLMOptions');
const FreestyleOptionsInput = document.getElementById('FreestyleOptions');
const scanLoopLimitInput = document.getElementById('scanLoopLimit');
const scanModeInput = document.getElementById('scanMode');
const ScanningOffInput = document.getElementById('ScanningOff');
const waitForSwitchToScanInput = document.getElementById('waitForSwitchToScan');
// const useTapInterfaceInput = document.getElementById('useTapInterface'); // Removed from UI
const interfaceAuditoryInput = document.getElementById('interfaceAuditory');
const interfaceTapInput = document.getElementById('interfaceTap');
const SummaryOffInput = document.getElementById('SummaryOff');
const enablePictogramsInput = document.getElementById('enablePictograms');
const disableTapPictogramsInput = document.getElementById('disableTapPictograms');
const enableSightWordsInput = document.getElementById('enableSightWords');
const sightWordGradeLevelInput = document.getElementById('sightWordGradeLevel');
const autoCleanInput = document.getElementById('autoClean');
const displaySplashInput = document.getElementById('displaySplash');
const displaySplashTimeInput = document.getElementById('displaySplashTime');
const enableMoodSelectionInput = document.getElementById('enableMoodSelection');
const vocabularyLevelSelect = document.getElementById('vocabularyLevel');
const ttsVoiceSelect = document.getElementById('ttsVoiceSelect');
const testTtsVoiceButton = document.getElementById('testTtsVoiceButton');
const ttsVoiceStatus = document.getElementById('tts-voice-status');
const toolbarPINInput = document.getElementById('toolbarPIN');
const spellLetterOrderSelect = document.getElementById('spellLetterOrder');
// Grid slider elements will be assigned in initializePage when DOM is ready
let gridColumnsSlider = null;
let gridColumnsValue = null;
// Volume slider elements
let applicationVolumeSlider = null;
let volumeDisplay = null;

// Backup volume slider initialization
document.addEventListener('DOMContentLoaded', function() {
    console.log('DOMContentLoaded - Setting up volume slider as backup...');
    const slider = document.getElementById('applicationVolume');
    const display = document.getElementById('volumeDisplay');
    
    if (slider && display) {
        console.log('DOMContentLoaded found volume elements, adding listener...');
        slider.addEventListener('input', function() {
            display.textContent = `${this.value}/10`;
            console.log('DOMContentLoaded listener - Volume updated to:', this.value);
        });
    } else {
        console.error('DOMContentLoaded - Volume elements still not found!');
    }
});

const llmProviderSelect = document.getElementById('llmProvider'); // Updated for provider selection

const saveSettingsButton = document.getElementById('saveSettingsButton');

let settingsStatus = null; // Changed to let


// --- State Variables ---
let currentSettings = {};
let availableVoices = []; // To store loaded voices

// --- Utility Functions ---
function showTemporaryStatus(element, message, isError = false, duration = 3000) {
    if (!element) return;
    element.textContent = message;
    element.style.color = isError ? 'red' : (message.includes('...') ? 'blue' : 'green');
    if (duration > 0) {
        setTimeout(() => {
            if (element.textContent === message) { // Clear only if it's the same message
                element.textContent = '';
            }
        }, duration);
    }
}

/**
 * Loads available TTS voices from the backend and populates the dropdown.
 */
async function loadVoices() {
    // ttsVoiceSelect will be assigned in initializePage, check there if needed
    // For now, assume it will be available if this function is called from initializePage
    try {
        // Use window.authenticatedFetch if this endpoint requires authentication
        // Assuming /api/tts-voices is public or handled by a different auth mechanism if not using window.authenticatedFetch
        const response = await window.authenticatedFetch('/api/tts-voices'); // Using authenticatedFetch
        if (!response.ok) throw new Error(`Failed to load voices: ${response.statusText}`);
        availableVoices = await response.json();
        
        // Filter to only include US English voices (en-US, en_US, us-en variations)
        const usEnVoices = availableVoices.filter(voice => {
            if (!voice.name) return false;
            const nameLower = voice.name.toLowerCase();
            return nameLower.includes('en-us') || 
                   nameLower.includes('en_us') || 
                   nameLower.includes('us-en') ||
                   nameLower.includes('us_en');
        });
        
        console.log('All available voices:', availableVoices.map(v => v.name));
        console.log('Filtered US English voices:', usEnVoices.map(v => v.name));
        
        ttsVoiceSelect.innerHTML = '<option value="">-- Select a Voice --</option>'; // Default option
        usEnVoices.forEach(voice => {
            const option = document.createElement('option');
            option.value = voice.name;
            option.textContent = `${voice.name} (${voice.ssml_gender.toLowerCase()})`;
            ttsVoiceSelect.appendChild(option);
        });
        
        console.log(`Loaded ${usEnVoices.length} US English voices out of ${availableVoices.length} total voices`);
    } catch (error) {
        console.error('Error loading TTS voices:', error);
        ttsVoiceSelect.innerHTML = '<option value="">Error loading voices</option>';
        showTemporaryStatus(ttsVoiceStatus, `Error loading voices: ${error.message}`, true);
    }
}

// --- Provider selection is now static, no need to load models dynamically ---

// --- Functions ---

/**
 * Loads global settings from the backend.
 */
async function loadSettings() {
    settingsStatus.textContent = 'Loading settings...';
    settingsStatus.style.color = 'gray';
    try {
        // Ensure window.currentAacUserId is available before fetching
        if (!window.currentAacUserId) {
            console.error("loadSettings: window.currentAacUserId is not set. Cannot fetch pages.");
            alert("Critical error: User ID not available for loading pages.");
            return;
        }
        console.log(`Attempting to fetch settings for user: ${window.currentAacUserId}`); // window.currentAacUserId from inline script
        const response = await window.authenticatedFetch('/api/settings'); // Use window.authenticatedFetch

        if (!response.ok) { const errorText = await response.text(); throw new Error(`HTTP error ${response.status}: ${errorText}`); }
        currentSettings = await response.json();

        if (scanDelayInput) { scanDelayInput.value = currentSettings.scanDelay || ''; }
        if (wakeWordInterjectionInput) { wakeWordInterjectionInput.value = currentSettings.wakeWordInterjection || ''; }
        if (wakeWordNameInput) { wakeWordNameInput.value = currentSettings.wakeWordName || ''; }
        if (CountryCodeInput) { CountryCodeInput.value = currentSettings.CountryCode || ''; }
        if (speechRateInput) { speechRateInput.value = currentSettings.speech_rate || 180; } // Populate speech rate
        
        // Initialize volume slider elements
        if (!applicationVolumeSlider) {
            applicationVolumeSlider = document.getElementById('applicationVolume');
            volumeDisplay = document.getElementById('volumeDisplay');
            
            if (applicationVolumeSlider && volumeDisplay) {
                applicationVolumeSlider.addEventListener('input', function() {
                    volumeDisplay.textContent = `${this.value}/10`;
                    console.log('Volume slider updated to:', this.value);
                });
                console.log('Volume slider event listener added');
            }
        }
        
        if (applicationVolumeSlider && volumeDisplay) {
            const volume = currentSettings.applicationVolume !== undefined ? currentSettings.applicationVolume : 8;
            applicationVolumeSlider.value = volume;
            volumeDisplay.textContent = `${volume}/10`;
            console.log('Application volume set to:', volume);
        }
        if (LLMOptionsInput) { LLMOptionsInput.value = currentSettings.LLMOptions || ''; }
        if (FreestyleOptionsInput) { 
            console.log('DEBUG FreestyleOptions - Element found:', !!FreestyleOptionsInput);
            console.log('DEBUG FreestyleOptions - currentSettings.FreestyleOptions:', currentSettings.FreestyleOptions);
            FreestyleOptionsInput.value = currentSettings.FreestyleOptions !== null && currentSettings.FreestyleOptions !== undefined ? currentSettings.FreestyleOptions : ''; 
        }
        if (scanLoopLimitInput) { scanLoopLimitInput.value = currentSettings.scanLoopLimit !== undefined ? currentSettings.scanLoopLimit : 0; }
        if (scanModeInput) { scanModeInput.value = currentSettings.scanMode === 'step' ? 'step' : 'auto'; }
        
        // Handle Interface Mode Radio Buttons
        if (interfaceAuditoryInput && interfaceTapInput) {
            if (currentSettings.useTapInterface) {
                interfaceTapInput.checked = true;
            } else {
                interfaceAuditoryInput.checked = true;
            }
        }

        // if (ScanningOffInput) { ScanningOffInput.checked = currentSettings.ScanningOff || false; } // Removed from UI
        if (SummaryOffInput) { SummaryOffInput.checked = currentSettings.SummaryOff || false; }
        if (autoCleanInput) { autoCleanInput.checked = currentSettings.autoClean || false; }
        if (displaySplashInput) { displaySplashInput.checked = currentSettings.displaySplash || false; }
        if (displaySplashTimeInput) { displaySplashTimeInput.value = currentSettings.displaySplashTime || 3000; }
        if (enableMoodSelectionInput) { enableMoodSelectionInput.checked = currentSettings.enableMoodSelection || false; }
        // if (useTapInterfaceInput) { useTapInterfaceInput.checked = currentSettings.useTapInterface || false; } // Removed from UI
        if (enablePictogramsInput) { enablePictogramsInput.checked = currentSettings.enablePictograms !== false; }
        if (disableTapPictogramsInput) { disableTapPictogramsInput.checked = currentSettings.disableTapPictograms || false; }
        if (ScanningOffInput) { ScanningOffInput.checked = currentSettings.ScanningOff || false; }
        if (waitForSwitchToScanInput) { waitForSwitchToScanInput.checked = currentSettings.waitForSwitchToScan || false; }
        if (enableSightWordsInput) { enableSightWordsInput.checked = currentSettings.enableSightWords !== false; }
        if (sightWordGradeLevelInput) { sightWordGradeLevelInput.value = currentSettings.sightWordGradeLevel || 'pre_k'; }
        if (ttsVoiceSelect && currentSettings.selected_tts_voice_name) {
            ttsVoiceSelect.value = currentSettings.selected_tts_voice_name;
        }
        // Load spellLetterOrder setting
        if (spellLetterOrderSelect) {
            spellLetterOrderSelect.value = currentSettings.spellLetterOrder || 'alphabetical';
        }
        // Load vocabularyLevel setting
        if (vocabularyLevelSelect) {
            vocabularyLevelSelect.value = currentSettings.vocabularyLevel || 'functional';
        }
        // Load gridColumns setting
        if (gridColumnsSlider && currentSettings.gridColumns !== undefined) {
            gridColumnsSlider.value = currentSettings.gridColumns;
            if (gridColumnsValue) gridColumnsValue.textContent = currentSettings.gridColumns;
            console.log(`Loaded gridColumns setting: ${currentSettings.gridColumns}`);
        } else if (gridColumnsSlider) {
            gridColumnsSlider.value = 6; // Default value
            if (gridColumnsValue) gridColumnsValue.textContent = 6;
            console.log("Using default gridColumns value: 6");
        }
         // Load LLM provider setting
        if (llmProviderSelect) {
            // Set to saved value or default to 'gemini'
            const providerValue = currentSettings.llm_provider || 'gemini';
            llmProviderSelect.value = providerValue;
        }

        // Load toolbar PIN (account level)
        await loadToolbarPIN();

         console.log("Settings loaded:", currentSettings);
         showTemporaryStatus(settingsStatus, 'Settings loaded.', false);

    } catch (error) {
        console.error('Error loading settings:', error);
        showTemporaryStatus(settingsStatus, `Error loading settings: ${error.message}`, true, 5000);
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
    const newSpeechRate = speechRateInput.value; // Get speech rate value
    const newApplicationVolume = applicationVolumeSlider ? parseInt(applicationVolumeSlider.value) : 8;
    const newLLMOptions = LLMOptionsInput.value; 
    const newFreestyleOptions = FreestyleOptionsInput.value;
    console.log('DEBUG FreestyleOptions - Save value:', newFreestyleOptions);
    const newScanLoopLimit = scanLoopLimitInput.value;
    const newScanMode = scanModeInput ? scanModeInput.value : 'auto';
    
    // Determine Interface Mode
    let newUseTapInterface = false;

    if (interfaceTapInput && interfaceTapInput.checked) {
        newUseTapInterface = true;
    } else {
        newUseTapInterface = false;
    }

    // const newScanningOff = ScanningOffInput.checked; // Removed from UI
    const newSummaryOff = SummaryOffInput.checked;
    const newAutoClean = autoCleanInput.checked;
    const newDisplaySplash = displaySplashInput.checked;
    const newDisplaySplashTime = displaySplashTimeInput.value ? parseInt(displaySplashTimeInput.value) : 3000;
    const newEnableMoodSelection = enableMoodSelectionInput.checked;
    // const newUseTapInterface = useTapInterfaceInput.checked; // Removed from UI
    const newEnablePictograms = enablePictogramsInput ? enablePictogramsInput.checked : true;
    const newDisableTapPictograms = disableTapPictogramsInput ? disableTapPictogramsInput.checked : false;
    const newScanningOff = ScanningOffInput ? ScanningOffInput.checked : false;
    const newWaitForSwitchToScan = waitForSwitchToScanInput ? waitForSwitchToScanInput.checked : false;
    const newEnableSightWords = enableSightWordsInput.checked;
    const newSightWordGradeLevel = sightWordGradeLevelInput.value;
    const newSelectedTtsVoice = ttsVoiceSelect ? ttsVoiceSelect.value : null;
    const newGridColumns = gridColumnsSlider ? parseInt(gridColumnsSlider.value) : 6;
    const newToolbarPIN = toolbarPINInput ? toolbarPINInput.value.trim() : null;
    const newSpellLetterOrder = spellLetterOrderSelect ? spellLetterOrderSelect.value : 'alphabetical';
    const newVocabularyLevel = vocabularyLevelSelect ? vocabularyLevelSelect.value : 'functional';
    
    console.log(`DEBUG vocabularyLevel - Save value:
        - vocabularyLevelSelect exists: ${!!vocabularyLevelSelect}
        - vocabularyLevelSelect.value: ${vocabularyLevelSelect ? vocabularyLevelSelect.value : 'N/A'}
        - newVocabularyLevel: ${newVocabularyLevel}`);

    console.log(`Save Settings Debug - Spell Letter Order:
        - spellLetterOrderSelect exists: ${!!spellLetterOrderSelect}
        - spellLetterOrderSelect.value: ${spellLetterOrderSelect ? spellLetterOrderSelect.value : 'N/A'}
        - newSpellLetterOrder: ${newSpellLetterOrder}`);
    
    console.log(`Save Settings Debug:
        - gridColumnsSlider exists: ${!!gridColumnsSlider}
        - gridColumnsSlider.value: ${gridColumnsSlider ? gridColumnsSlider.value : 'N/A'}
        - newGridColumns (parsed): ${newGridColumns}`);


    const newLlmProvider = llmProviderSelect ? llmProviderSelect.value : 'gemini';


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
    if (!newSpeechRate || isNaN(parseInt(newSpeechRate)) || parseInt(newSpeechRate) < 50 || parseInt(newSpeechRate) > 400) { // Example validation for speech rate
        settingsStatus.textContent = 'Invalid Speech Rate. Must be a number (e.g., 50-400).';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
     if (!newLLMOptions || isNaN(parseInt(newLLMOptions)) || parseInt(newLLMOptions) < 1 || parseInt(newLLMOptions) > 50) {
        settingsStatus.textContent = 'Invalid LLM Options. Must be a number (e.g., 1-50).';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
     if (newFreestyleOptions !== '' && (isNaN(parseInt(newFreestyleOptions)) || parseInt(newFreestyleOptions) < 1 || parseInt(newFreestyleOptions) > 50)) {
        settingsStatus.textContent = 'Invalid Freestyle Options. Must be a number (e.g., 1-50).';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (newScanLoopLimit !== '' && (isNaN(parseInt(newScanLoopLimit)) || parseInt(newScanLoopLimit) < 0 || parseInt(newScanLoopLimit) > 10)) {
        settingsStatus.textContent = 'Invalid Scan Loop Limit. Must be 0 (unlimited) or 1-10.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (!['auto', 'step'].includes(newScanMode)) {
        settingsStatus.textContent = 'Invalid Scanning Mode. Must be Auto or Step.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    // Validate gridColumns
    if (newGridColumns < 2 || newGridColumns > 18) {
        settingsStatus.textContent = 'Invalid Button Size. Must be between 2 and 18.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    // Validate toolbar PIN
    if (newToolbarPIN && (newToolbarPIN.length < 3 || newToolbarPIN.length > 10)) {
        settingsStatus.textContent = 'Toolbar PIN must be between 3 and 10 characters.';
        settingsStatus.style.color = 'red'; setTimeout(() => { settingsStatus.textContent = ''; }, 4000); return;
    }
    if (ttsVoiceSelect && !newSelectedTtsVoice && availableVoices.length > 0) { // Check if voices loaded but none selected
        showTemporaryStatus(settingsStatus, 'Please select a TTS voice.', true, 4000); return;
    }
    // Provider selection is always valid since it has default values
    // Remove the old LLM model validation

    const settingsToSave = {
        scanDelay: parseInt(newDelay),
        wakeWordInterjection: newInterjection,
        wakeWordName: newName,
        CountryCode: newCountryCode,
        speech_rate: parseInt(newSpeechRate),
        applicationVolume: newApplicationVolume,
        LLMOptions: parseInt(newLLMOptions),
        FreestyleOptions: newFreestyleOptions !== '' ? parseInt(newFreestyleOptions) : null,
        scanLoopLimit: newScanLoopLimit !== '' ? parseInt(newScanLoopLimit) : 0,
        scanMode: newScanMode,
        ScanningOff: newScanningOff,    
        waitForSwitchToScan: newWaitForSwitchToScan,
        SummaryOff: newSummaryOff,
        autoClean: newAutoClean,
        displaySplash: newDisplaySplash,
        displaySplashTime: newDisplaySplashTime,
        enableMoodSelection: newEnableMoodSelection,
        useTapInterface: newUseTapInterface,
        enablePictograms: newEnablePictograms,
        disableTapPictograms: newDisableTapPictograms,
        enableSightWords: newEnableSightWords,
        sightWordGradeLevel: newSightWordGradeLevel,
        selected_tts_voice_name: newSelectedTtsVoice,
        llm_provider: newLlmProvider, // Updated to use provider instead of specific model
        gridColumns: newGridColumns, // Add gridColumns to save payload
        spellLetterOrder: newSpellLetterOrder, // Add spell letter order setting
        vocabularyLevel: newVocabularyLevel // Add vocabulary level setting
    };
    console.log('DEBUG FreestyleOptions - Payload value:', settingsToSave.FreestyleOptions);
    console.log('DEBUG enablePictograms - Payload value:', settingsToSave.enablePictograms);
    console.log('DEBUG spellLetterOrder - Payload value:', settingsToSave.spellLetterOrder);
    console.log('DEBUG vocabularyLevel - Payload value:', settingsToSave.vocabularyLevel);

    console.log("Saving settings:", settingsToSave);
    console.log("FULL PAYLOAD:", JSON.stringify(settingsToSave, null, 2));
    showTemporaryStatus(settingsStatus, 'Saving...', false, 0)

    try {
        // Save user settings
        const response = await window.authenticatedFetch('/api/settings', { // Use window.authenticatedFetch
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(settingsToSave)
        });
        if (!response.ok) { const errorText = await response.text(); throw new Error(`Save failed: ${response.status} ${errorText}`); }

        currentSettings = await response.json(); // Update local state with response
        console.log('DEBUG enablePictograms - Server response value:', currentSettings.enablePictograms);
        console.log('DEBUG vocabularyLevel - Server response value:', currentSettings.vocabularyLevel);
        console.log('DEBUG spellLetterOrder - Server response value:', currentSettings.spellLetterOrder);
        
        if (scanDelayInput) scanDelayInput.value = currentSettings.scanDelay || '';
        if (wakeWordInterjectionInput) wakeWordInterjectionInput.value = currentSettings.wakeWordInterjection || '';
        if (wakeWordNameInput) wakeWordNameInput.value = currentSettings.wakeWordName || '';
        if (CountryCodeInput) CountryCodeInput.value = currentSettings.CountryCode || '';
        if (speechRateInput) speechRateInput.value = currentSettings.speech_rate || 180;
        if (applicationVolumeSlider && volumeDisplay) {
            const volume = currentSettings.applicationVolume !== undefined ? currentSettings.applicationVolume : 8;
            applicationVolumeSlider.value = volume;
            volumeDisplay.textContent = `${volume}/10`;
        }
        if (LLMOptionsInput) LLMOptionsInput.value = currentSettings.LLMOptions || '';
        if (FreestyleOptionsInput) {
            console.log('DEBUG FreestyleOptions - Reload value:', currentSettings.FreestyleOptions);
            FreestyleOptionsInput.value = currentSettings.FreestyleOptions !== null && currentSettings.FreestyleOptions !== undefined ? currentSettings.FreestyleOptions : '';
        }
        if (scanLoopLimitInput) scanLoopLimitInput.value = currentSettings.scanLoopLimit !== undefined ? currentSettings.scanLoopLimit : 0;
        if (scanModeInput) scanModeInput.value = currentSettings.scanMode === 'step' ? 'step' : 'auto';
        if (ScanningOffInput) ScanningOffInput.checked = currentSettings.ScanningOff || false;
        if (waitForSwitchToScanInput) waitForSwitchToScanInput.checked = currentSettings.waitForSwitchToScan || false;
        if (SummaryOffInput) SummaryOffInput.checked = currentSettings.SummaryOff || false;
        if (autoCleanInput) autoCleanInput.checked = currentSettings.autoClean || false;
        if (displaySplashInput) displaySplashInput.checked = currentSettings.displaySplash || false;
        if (displaySplashTimeInput) displaySplashTimeInput.value = currentSettings.displaySplashTime || 3000;
        if (enableMoodSelectionInput) enableMoodSelectionInput.checked = currentSettings.enableMoodSelection || false;
        if (enablePictogramsInput) enablePictogramsInput.checked = currentSettings.enablePictograms !== false;
        if (enableSightWordsInput) enableSightWordsInput.checked = currentSettings.enableSightWords !== false;
        if (sightWordGradeLevelInput) sightWordGradeLevelInput.value = currentSettings.sightWordGradeLevel || 'pre_k';
        if (ttsVoiceSelect) ttsVoiceSelect.value = currentSettings.selected_tts_voice_name || '';
        // Update gridColumns slider after save
        if (gridColumnsSlider && currentSettings.gridColumns !== undefined) {
            gridColumnsSlider.value = currentSettings.gridColumns;
            if (gridColumnsValue) gridColumnsValue.textContent = currentSettings.gridColumns;
        }
        // Update LLM provider select
        if (llmProviderSelect) llmProviderSelect.value = currentSettings.llm_provider || 'gemini';
        // Update spellLetterOrder select
        if (spellLetterOrderSelect) {
            const savedValue = currentSettings.spellLetterOrder || 'alphabetical';
            console.log('DEBUG spellLetterOrder - Setting dropdown to:', savedValue);
            spellLetterOrderSelect.value = savedValue;
            console.log('DEBUG spellLetterOrder - Dropdown now shows:', spellLetterOrderSelect.value);
        }
        // Update vocabularyLevel select
        if (vocabularyLevelSelect) {
            vocabularyLevelSelect.value = currentSettings.vocabularyLevel || 'functional';
        }
        
        // Save toolbar PIN separately (account level)
        if (newToolbarPIN) {
            await saveToolbarPIN(newToolbarPIN);
        }
        
        // Update splash screen settings if the function exists
        if (typeof updateSplashScreenSettings === 'function') {
            updateSplashScreenSettings({
                displaySplash: newDisplaySplash,
                displaySplashTime: newDisplaySplashTime
            });
        }
        
        // Update sight word service settings if the function exists
        if (typeof window.updateSightWordSettings === 'function') {
            window.updateSightWordSettings(currentSettings);
        }
        
        showTemporaryStatus(settingsStatus, 'Settings saved successfully!', false);

    } catch (error) {
        console.error('Error saving settings:', error);
        showTemporaryStatus(settingsStatus, `Error saving: ${error.message}`, true, 5000);
    }
}

/**
 * Tests the currently selected TTS voice.
 */
async function testSelectedVoice() {
    if (!ttsVoiceSelect || !ttsVoiceStatus) return;
    const selectedVoice = ttsVoiceSelect.value;
    if (!selectedVoice) {
        showTemporaryStatus(ttsVoiceStatus, "Please select a voice to test.", true);
        return;
    }
    showTemporaryStatus(ttsVoiceStatus, `Testing voice: ${selectedVoice}...`, false, 0);
    try {
        // Use the /api/test-tts-voice endpoint which is specifically for voice testing
        const response = await window.authenticatedFetch('/api/test-tts-voice', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
                voice_name: selectedVoice, 
                text: "This is a test of the selected voice."
            })
        });
        
        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ detail: response.statusText }));
            throw new Error(errorData.detail || `Test failed: ${response.statusText}`);
        }
        
        const result = await response.json();
        console.log('TTS Test Response:', result); // Debug log
        
        if (result.audio_url) {
            // Backend returns a URL to the audio file - fetch and play it
            console.log('Audio URL received:', result.audio_url);
            
            try {
                // Fetch the audio file from the URL
                const audioResponse = await fetch(result.audio_url);
                if (!audioResponse.ok) {
                    throw new Error(`Failed to fetch audio file: ${audioResponse.status}`);
                }
                
                const audioArrayBuffer = await audioResponse.arrayBuffer();
                console.log('Fetched audio buffer size:', audioArrayBuffer.byteLength);
                
                await playTestAudio(audioArrayBuffer, result.sample_rate || 22050);
                
                showTemporaryStatus(ttsVoiceStatus, "Test voice played successfully!", false);
                
                // Optional: Clean up the temporary file by calling a cleanup endpoint
                // (You could add a cleanup endpoint to the backend if needed)
                
            } catch (audioError) {
                console.error('Error fetching/playing audio from URL:', audioError);
                showTemporaryStatus(ttsVoiceStatus, `Error playing audio: ${audioError.message}`, true, 5000);
            }
            
        } else if (result.audio_data) {
            // Fallback: Handle base64 audio data if provided
            console.log('Audio data received, length:', result.audio_data.length);
            console.log('Sample rate:', result.sample_rate);
            
            const audioData = result.audio_data;
            const sampleRate = result.sample_rate || 22050;
            
            // Convert base64 to ArrayBuffer
            const base64ToArrayBuffer = (base64) => {
                const binaryString = window.atob(base64);
                const len = binaryString.length;
                const bytes = new Uint8Array(len);
                for (let i = 0; i < len; i++) {
                    bytes[i] = binaryString.charCodeAt(i);
                }
                return bytes.buffer;
            };
            
            const audioDataArrayBuffer = base64ToArrayBuffer(audioData);
            console.log('Converted audio buffer size:', audioDataArrayBuffer.byteLength);
            
            await playTestAudio(audioDataArrayBuffer, sampleRate);
            
            showTemporaryStatus(ttsVoiceStatus, "Test voice played successfully!", false);
            
        } else if (result.success && result.message) {
            // Backend says it worked but didn't return audio data or URL
            console.log('Backend response indicates success but no audio_data or audio_url field');
            console.log('Full response:', result);
            showTemporaryStatus(ttsVoiceStatus, result.message + " (No audio data returned)", true);
            
        } else {
            console.log('Unexpected response format:', result);
            showTemporaryStatus(ttsVoiceStatus, "Test completed but unexpected response format.", true);
        }
    } catch (error) {
        console.error('Error testing TTS voice:', error);
        showTemporaryStatus(ttsVoiceStatus, `Error testing voice: ${error.message}`, true, 5000);
    }
}

/**
 * Plays test audio for TTS voice testing
 */
async function playTestAudio(audioDataBuffer, sampleRate) {
    if (!audioDataBuffer) {
        throw new Error('No audio data buffer provided.');
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        
        // Handle suspended AudioContext (required for Chrome's autoplay policy)
        if (audioContext.state === 'suspended') {
            console.log('AudioContext is suspended, attempting to resume...');
            try {
                await audioContext.resume();
                console.log('AudioContext resumed successfully');
            } catch (resumeError) {
                console.warn("AudioContext resume failed:", resumeError);
                // Continue anyway - sometimes audio still works
            }
        }

        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        source.start(0);

        return new Promise((resolve, reject) => {
            source.onended = () => {
                if (audioContext && audioContext.state !== 'closed') {
                    audioContext.close();
                }
                resolve();
            };
            
            source.onerror = (error) => {
                if (audioContext && audioContext.state !== 'closed') {
                    audioContext.close();
                }
                reject(error);
            };
        });

    } catch (error) {
        console.error('Error playing test audio:', error);
        if (audioContext && audioContext.state !== 'closed') {
            try {
                audioContext.close();
            } catch (closeError) {
                console.warn('Error closing AudioContext:', closeError);
            }
        }
        throw error;
    }
}

/**
 * Loads the toolbar PIN from account settings.
 */
async function loadToolbarPIN() {
    try {
        const response = await window.authenticatedFetch('/api/account/toolbar-pin');
        if (!response.ok) throw new Error(`Failed to load toolbar PIN: ${response.statusText}`);
        const data = await response.json();
        if (toolbarPINInput) {
            toolbarPINInput.value = data.toolbarPIN || '1234';
        }
        console.log("Toolbar PIN loaded from account settings");
    } catch (error) {
        console.error('Error loading toolbar PIN:', error);
        if (toolbarPINInput) {
            toolbarPINInput.value = '1234'; // Default fallback
        }
        showTemporaryStatus(settingsStatus, `Error loading toolbar PIN: ${error.message}`, true, 3000);
    }
}

/**
 * Saves the toolbar PIN to account settings.
 */
async function saveToolbarPIN(newPIN) {
    try {
        const response = await window.authenticatedFetch('/api/account/toolbar-pin', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ toolbarPIN: newPIN })
        });
        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.detail || `Failed to save toolbar PIN: ${response.statusText}`);
        }
        
        // Update the PIN immediately in the gridpage if it's open in another tab
        // This allows for immediate integration without restart
        if (window.opener && window.opener.updateToolbarPIN) {
            window.opener.updateToolbarPIN(newPIN);
        }
        
        console.log("Toolbar PIN saved successfully");
        return true;
    } catch (error) {
        console.error('Error saving toolbar PIN:', error);
        throw error;
    }
}

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("admin_settings.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        scanDelayInput = document.getElementById('scanDelay');
        gridColumnsSlider = document.getElementById('gridColumnsSlider');
        gridColumnsValue = document.getElementById('gridColumnsValue');
        // The following are already assigned globally as const, no need to re-assign:
        // wakeWordInterjectionInput, wakeWordNameInput, CountryCodeInput, speechRateInput,
        // LLMOptionsInput, ScanningOffInput, SummaryOffInput, ttsVoiceSelect,
        // testTtsVoiceButton, ttsVoiceStatus, llmProviderSelect, saveSettingsButton.

        settingsStatus = document.getElementById('settings-status'); // This was 'let', so assign it.

        // Basic check for essential elements
        if (!saveSettingsButton || !settingsStatus) {
            console.error("CRITICAL ERROR: One or more essential DOM elements for admin_settings.js not found.");
            return;
        }

        // Debug: Check if slider elements were found
        console.log("Slider elements found:", {
            gridColumnsSlider: !!gridColumnsSlider,
            gridColumnsValue: !!gridColumnsValue
        });

        if (gridColumnsSlider) {
            console.log("gridColumnsSlider details:", {
                id: gridColumnsSlider.id,
                value: gridColumnsSlider.value,
                min: gridColumnsSlider.min,
                max: gridColumnsSlider.max
            });
        }

        if (gridColumnsValue) {
            console.log("gridColumnsValue details:", {
                id: gridColumnsValue.id,
                textContent: gridColumnsValue.textContent,
                innerHTML: gridColumnsValue.innerHTML
            });
        }

        // Add Event Listeners
        if (saveSettingsButton) saveSettingsButton.addEventListener('click', saveSettings);
        if (testTtsVoiceButton) testTtsVoiceButton.addEventListener('click', testSelectedVoice);
        
        // Mood-related event listeners
        // Grid columns slider event listener
        if (gridColumnsSlider && gridColumnsValue) {
            // Update value display when slider moves
            const updateSliderValue = function() {
                gridColumnsValue.textContent = gridColumnsSlider.value;
                console.log(`Grid columns slider updated to: ${gridColumnsSlider.value}`);
            };
            
            gridColumnsSlider.addEventListener('input', updateSliderValue);
            gridColumnsSlider.addEventListener('change', updateSliderValue);
            
            // Set initial value
            updateSliderValue();
            console.log("Grid columns slider event listeners added successfully");
        } else {
            console.error("Grid columns slider elements not found:", {
                gridColumnsSlider: !!gridColumnsSlider,
                gridColumnsValue: !!gridColumnsValue
            });
        }


        // Initial data loading
        if (ttsVoiceSelect) await loadVoices();
        // Static provider selection - no need to populate dropdown
        await loadSettings();
        await loadToolbarPIN(); // Load the toolbar PIN on page initialization
    }
}

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("admin_settings.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}


// --- Event Listeners ---
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
        console.log("admin_settings.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("admin_settings.js: Logout button event listener added");
    }
}

// Listener for when the authentication context is ready
document.addEventListener('adminUserContextReady', () => {
    console.log("admin_settings.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("admin_settings.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("admin_settings.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});