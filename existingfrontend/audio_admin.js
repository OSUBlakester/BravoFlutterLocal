// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;


// DOM Elements - declare with 'let', assign in initializePage
let personalSpeakerSelect = null;
let systemSpeakerSelect = null;
let saveAudioSettingsBtn = null;
let testPersonalSpeakerBtn = null;
let testSystemSpeakerBtn = null;

// Initial loading of saved preferences (from localStorage, these will be used by gridpage.js too)
let personalSpeakerId = localStorage.getItem('bravoPersonalSpeakerId') || 'default';
let systemSpeakerId = localStorage.getItem('bravoSystemSpeakerId') || 'default';

// --- Utility to convert Base64 to ArrayBuffer ---
function base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
}


// --- Core Audio Playback Function (CLIENT-SIDE - Corrected audioContext.setSinkId) ---
async function playAudioToDevice(audioDataBuffer, sampleRate, targetDeviceId) {
    console.log("playAudioToDevice: Starting with targetDeviceId:", targetDeviceId);
    if (!audioDataBuffer) {
        console.error('playAudioToDevice: No audio data buffer provided.');
        throw new Error('No audio data buffer provided.');
    }

    let audioContext;
    let source;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        console.log("playAudioToDevice: AudioContext created. State:", audioContext.state);

        // --- CRITICAL CHANGE: Awaiting setSinkId on AudioContext ---
        // If setSinkId is available AND a specific device is selected (not 'default'),
        // call it and await its completion.
        if (typeof audioContext.setSinkId === 'function' && targetDeviceId && targetDeviceId !== 'default') {
            console.log(`playAudioToDevice: Attempting to call audioContext.setSinkId to device (ID: ${targetDeviceId})`);
            // setSinkId returns a Promise. Await its resolution.
            await audioContext.setSinkId(targetDeviceId); 
            console.log(`playAudioToDevice: audioContext.setSinkId call FINISHED for device ${targetDeviceId}`);

        } else {
            console.warn(`playAudioToDevice: Not performing explicit routing. Reason: typeof audioContext.setSinkId=${typeof audioContext.setSinkId}, targetDeviceId=${targetDeviceId}. Audio will play to browser's default speaker.`);
        }
        // --- END CRITICAL CHANGE ---

        const audioBuffer = await audioContext.decodeAudioData(audioDataBuffer);
        console.log("playAudioToDevice: Audio data decoded. Buffer duration:", audioBuffer.duration);

        source = audioContext.createBufferSource();
        source.buffer = audioBuffer;

        source.connect(audioContext.destination); // Connect to the audioContext.destination

        source.start(0);
        console.log("playAudioToDevice: Audio source started.");

        // Return a promise that resolves when the audio is finished.
        return new Promise((resolve) => {
            source.onended = () => {
                console.log("playAudioToDevice: Audio playback ended.");
                audioContext.close(); // Important to release resources
                resolve();
            };
        }).catch(err => {
            console.error("playAudioToDevice: Error during audio playback promise:", err);
            if (audioContext && audioContext.state !== 'closed') audioContext.close();
            throw err;
        });

    } catch (error) {
        console.error('playAudioToDevice: Fatal Error during setup or playback:', error);
        if (audioContext && audioContext.state !== 'closed') audioContext.close();
        alert(`Error playing audio: ${error.message}. Please check browser console for details.`);
        throw error;
    }
}




// --- Audio Device Management Functions (for setup page) ---
async function populateAudioDeviceSelectors() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
        console.warn('enumerateDevices() not supported.');
        alert('Your browser does not support audio device selection.');
        return;
    }

    // Clear previous options
    personalSpeakerSelect.innerHTML = '<option value="default">Default Speaker</option>';
    systemSpeakerSelect.innerHTML = '<option value="default">Default Speaker</option>';

    try {
        // Request microphone access (even fake) to unlock device labels/permissions
        // This is a browser security requirement for enumerateDevices() to return meaningful labels.
        // A microphone icon will appear in the browser address bar.
        await navigator.mediaDevices.getUserMedia({ audio: true, video: false }); 

        const devices = await navigator.mediaDevices.enumerateDevices();
        const audioOutputDevices = devices.filter(device => device.kind === 'audiooutput');

        audioOutputDevices.forEach(device => {
            // Clone options to put in both dropdowns
            const option1 = document.createElement('option');
            option1.value = device.deviceId;
            option1.textContent = device.label || `Speaker ${device.deviceId.substring(0, 8)}...`;
            personalSpeakerSelect.appendChild(option1);

            const option2 = document.createElement('option');
            option2.value = device.deviceId;
            option2.textContent = device.label || `Speaker ${device.deviceId.substring(0, 8)}...`;
            systemSpeakerSelect.appendChild(option2);
        });

        // Set current selections after populating options
        personalSpeakerSelect.value = personalSpeakerId;
        systemSpeakerSelect.value = systemSpeakerId;

        console.log("Audio devices populated.");

    } catch (err) {
        console.error('Error enumerating audio devices:', err);
        alert('Failed to list audio devices. Ensure microphone access is allowed/prompted for device labels on your device.');
    }
}



// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("audio_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        personalSpeakerSelect = document.getElementById('personalSpeakerSelect');
        systemSpeakerSelect = document.getElementById('systemSpeakerSelect');
        saveAudioSettingsBtn = document.getElementById('saveAudioSettingsBtn');
        testPersonalSpeakerBtn = document.getElementById('testPersonalSpeakerBtn');
        testSystemSpeakerBtn = document.getElementById('testSystemSpeakerBtn');

        // Basic check for essential elements
        if (!personalSpeakerSelect || !systemSpeakerSelect || !saveAudioSettingsBtn || !testPersonalSpeakerBtn || !testSystemSpeakerBtn) {
            console.error("CRITICAL ERROR: One or more essential DOM elements for audio_admin.js not found.");
            return;
        }

        // Add Event Listeners
        saveAudioSettingsBtn.addEventListener('click', saveAudioSettingsHandler); // Renamed handler
        testPersonalSpeakerBtn.addEventListener('click', testPersonalSpeakerHandler); // Renamed handler
        testSystemSpeakerBtn.addEventListener('click', testSystemSpeakerHandler);   // Renamed handler


        await populateAudioDeviceSelectors();
    }
}

// --- DOMContentLoaded Initialization ---
function saveAudioSettingsHandler() {
            personalSpeakerId = personalSpeakerSelect.value;
            systemSpeakerId = systemSpeakerSelect.value;
            localStorage.setItem('bravoPersonalSpeakerId', personalSpeakerId);
            localStorage.setItem('bravoSystemSpeakerId', systemSpeakerId);
            console.log('Audio settings saved to localStorage:', { personalSpeakerId, systemSpeakerId });
            alert('Audio settings saved locally on your browser!');


}

async function testPersonalSpeakerHandler() {
             const testDeviceId = personalSpeakerSelect.value;
             const testDeviceLabel = personalSpeakerSelect.options[personalSpeakerSelect.selectedIndex].text;
             alert(`Testing personal speaker: ${testDeviceLabel}`);
             try {
                const tempText = "Hello. This is a test for your personal speaker.";
                // Use window.authenticatedFetch and ensure window.currentAacUserId is available
                const response = await window.authenticatedFetch(`/play-audio`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }, // X-User-ID added by authenticatedFetch
                    body: JSON.stringify({ text: tempText, routing_target: 'personal' })
                });
                if (!response.ok) throw new Error(`Server error (${response.status}): ${await response.text()}`);
                const data = await response.json();
                const audioDataArrayBuffer = base64ToArrayBuffer(data.audio_data);
                await playAudioToDevice(audioDataArrayBuffer, data.sample_rate, testDeviceId);
                console.log('Personal speaker test complete.');
             } catch (error) {
                 console.error('Personal speaker test failed:', error);
                 alert('Personal speaker test failed. Check console for details.');
             }
}

async function testSystemSpeakerHandler() {
            const testDeviceId = systemSpeakerSelect.value;
            const testDeviceLabel = systemSpeakerSelect.options[systemSpeakerSelect.selectedIndex].text;
            alert(`Testing system speaker: ${testDeviceLabel}`);
            try {
                const tempText = "Hello. This is a test for the system speaker.";
                // Use window.authenticatedFetch
                const response = await window.authenticatedFetch(`/play-audio`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }, // X-User-ID added by authenticatedFetch
                    body: JSON.stringify({ text: tempText, routing_target: 'system' })
                });
                if (!response.ok) throw new Error(`Server error (${response.status}): ${await response.text()}`);
                const data = await response.json();
                const audioDataArrayBuffer = base64ToArrayBuffer(data.audio_data);
                await playAudioToDevice(audioDataArrayBuffer, data.sample_rate, testDeviceId);
                console.log('System speaker test complete.');
            } catch (error) {
                console.error('System speaker test failed:', error);
                alert('System speaker test failed. Check console for details.');
            }
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
        
        // Reset interview system for new user
        if (window.audioInterviewSystem) {
            window.audioInterviewSystem.resetForNewUser();
        }
        
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
        // Reset interview system for logout
        if (window.audioInterviewSystem) {
            window.audioInterviewSystem.resetForNewUser();
        }
        
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
        console.log("audio_admin.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("audio_admin.js: Logout button event listener added");
    }
}

// --- Event Listeners for Initialization ---
document.addEventListener('adminUserContextReady', () => {
    console.log("audio_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("audio_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("audio_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});
