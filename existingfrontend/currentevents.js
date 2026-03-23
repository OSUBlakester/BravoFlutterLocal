// Global state
let favoritesData = null;
let currentOptions = [];

// Initialize page when auth context is ready
let isAuthContextReady = false;
let isDomContentLoaded = false;

document.addEventListener('DOMContentLoaded', () => {
    isDomContentLoaded = true;
    initializePage();
});

window.addEventListener('authContextReady', () => {
    isAuthContextReady = true;
    initializePage();
});

async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        await loadFavoriteTopics();
        setupHomeButton();
    }
}

async function loadFavoriteTopics() {
    try {
        const response = await window.authenticatedFetch('/api/favorites');
        if (response.ok) {
            favoritesData = await response.json();
            renderTopicButtons();
        } else {
            console.error('Failed to load favorites');
        }
    } catch (error) {
        console.error('Error loading favorites:', error);
    }
}

function renderTopicButtons() {
    const container = document.getElementById('currentEventsButtons');
    
    // Clear existing topic buttons (keep home button)
    const homeButton = document.getElementById('homeButton');
    container.innerHTML = '';
    container.appendChild(homeButton);
    
    // Add favorite topic buttons
    if (favoritesData && favoritesData.buttons) {
        favoritesData.buttons
            .filter(btn => !btn.hidden)
            .sort((a, b) => a.row * 10 + a.col - (b.row * 10 + b.col)) // Sort by grid position
            .forEach(button => {
                const topicBtn = document.createElement('button');
                topicBtn.textContent = button.text;
                topicBtn.id = `topic-${button.row}-${button.col}`;
                topicBtn.addEventListener('click', () => {
                    getTopicContent(button.text, button.speechPhrase);
                });
                container.appendChild(topicBtn);
            });
    }
}

function setupHomeButton() {
    document.getElementById('homeButton').addEventListener('click', () => {
        window.location.href = 'gridpage.html';
    });
}

async function getTopicContent(topicText, speechPhrase) {
    try {
        // Show loading
        const gridContainer = document.getElementById('gridContainer');
        gridContainer.innerHTML = '<div>Loading content for ' + topicText + '...</div>';
        
        // Optionally speak the speech phrase
        if (speechPhrase) {
            try {
                await speak(speechPhrase, "system");
            } catch (error) {
                console.error("Error speaking phrase:", error);
            }
        }
        
        const response = await window.authenticatedFetch('/api/favorites/get-topic-content', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ topic: topicText })
        });
        
        if (response.ok) {
            const data = await response.json();
            generateLlmButtons(data.summaries || []);
        } else {
            const errorData = await response.json();
            gridContainer.innerHTML = '<div>Error loading content: ' + (errorData.detail || 'Unknown error') + '</div>';
        }
    } catch (error) {
        console.error('Error getting topic content:', error);
        const gridContainer = document.getElementById('gridContainer');
        gridContainer.innerHTML = '<div>Error loading content: ' + error.message + '</div>';
    }
}

function generateLlmButtons(options) {
    const gridContainer = document.getElementById('gridContainer');
    gridContainer.innerHTML = '';
    currentOptions = options;

    if (!options || options.length === 0) {
        gridContainer.innerHTML = '<div>No content available for this topic.</div>';
        return;
    }

    options.forEach(option => {
        const button = document.createElement('button');
        button.textContent = option;
        button.classList.add('llm-button');
        button.addEventListener('click', () => {
            console.log("Button clicked:", option);
            console.log("speaking llm option");
            speak(option, "system")
                .then(() => {
                    console.log("speak callback triggered");
                    window.location.reload(true);

                    document.addEventListener('DOMContentLoaded', function() {
                        console.log("DOMContentLoaded triggered, starting scanning");
                    });
                })
                .catch(error => {
                    console.error("speak error", error);
                });
        });
        gridContainer.appendChild(button);
    });
}

async function speak(text, audioType = "system") {
    console.log("Speaking:", text); // Debugging log
    
    // Show splash screen if enabled
    if (typeof showSplashScreen === 'function') {
        showSplashScreen(text);
    }
    
    return new Promise((resolve, reject) => {
        fetch('/play-audio', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text, audioType }),
        })
        .then(response => {
            if (!response.ok) {
                reject(new Error('Failed to play audio'));
            } else {
                resolve();
            }
        })
        .catch(error => {
            console.error('Error playing audio:', error);
            reject(error);
        });
    });
}