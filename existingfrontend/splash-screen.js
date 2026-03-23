/**
 * Splash Screen Functionality
 * Shows a speech bubble-style overlay with announced text
 */

class SplashScreen {
    constructor() {
        this.splashElement = null;
        this.currentTimeout = null;
        this.settingsLoaded = false;
        this.settings = {
            displaySplash: false,
            displaySplashTime: 3000
        };
        this.init();
    }

    init() {
        // Create splash screen HTML
        this.createSplashElement();
        // Don't load settings immediately - wait for authentication to be ready
    }

    createSplashElement() {
        // Remove existing splash screen if it exists
        const existing = document.getElementById('splash-screen');
        if (existing) {
            existing.remove();
        }

        // Create new splash screen
        const splashHtml = `
            <div id="splash-screen">
                <div class="splash-bubble">
                    <div id="splash-text"></div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', splashHtml);
        this.splashElement = document.getElementById('splash-screen');
    }

    async loadSettings() {
        try {
            // Check if authenticatedFetch is available (should be available on all pages that use splash screen)
            const fetchFunction = window.authenticatedFetch || fetch;
            
            const response = await fetchFunction('/api/settings', {
                method: 'GET',
                credentials: 'include'
            });
            
            if (response.ok) {
                const settings = await response.json();
                this.settings.displaySplash = settings.displaySplash || false;
                this.settings.displaySplashTime = settings.displaySplashTime || 3000;
                this.settingsLoaded = true;
                console.log('Splash screen settings loaded:', this.settings);
            }
        } catch (error) {
            console.error('Failed to load splash screen settings:', error);
            // Use default settings if loading fails
            this.settingsLoaded = true;
        }
    }

    /**
     * Shows the splash screen with the given text
     * @param {string} text - The text to display in the splash screen
     */
    async show(text) {
        // Load settings if not already loaded
        if (!this.settingsLoaded) {
            await this.loadSettings();
        }

        // Don't show if disabled in settings
        if (!this.settings.displaySplash) {
            return;
        }

        // Don't show if no text provided
        if (!text || text.trim() === '') {
            return;
        }

        // Clear any existing timeout
        if (this.currentTimeout) {
            clearTimeout(this.currentTimeout);
            this.currentTimeout = null;
        }

        // Update splash text
        const textElement = document.getElementById('splash-text');
        if (textElement) {
            textElement.textContent = text.trim();
        }

        // Show splash screen with fade-in animation
        if (this.splashElement) {
            this.splashElement.style.display = 'flex'; // Use flex for centering
            this.splashElement.classList.remove('splash-fade-out');
            this.splashElement.classList.add('splash-fade-in');

            // Set timeout to hide splash screen
            this.currentTimeout = setTimeout(() => {
                this.hide();
            }, this.settings.displaySplashTime);
        }
    }

    /**
     * Hides the splash screen with fade-out animation
     */
    hide() {
        if (this.splashElement) {
            this.splashElement.classList.remove('splash-fade-in');
            this.splashElement.classList.add('splash-fade-out');

            // Hide element after animation completes
            setTimeout(() => {
                if (this.splashElement) {
                    this.splashElement.style.display = 'none';
                }
            }, 300);
        }

        // Clear timeout
        if (this.currentTimeout) {
            clearTimeout(this.currentTimeout);
            this.currentTimeout = null;
        }
    }

    /**
     * Updates settings (called when settings are changed)
     * @param {Object} newSettings - Object containing displaySplash and displaySplashTime
     */
    updateSettings(newSettings) {
        if (newSettings.displaySplash !== undefined) {
            this.settings.displaySplash = newSettings.displaySplash;
        }
        if (newSettings.displaySplashTime !== undefined) {
            this.settings.displaySplashTime = newSettings.displaySplashTime;
        }
        console.log('Splash screen settings updated:', this.settings);
    }
}

// Global splash screen instance
let globalSplashScreen = null;

// Initialize splash screen when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    globalSplashScreen = new SplashScreen();
});

/**
 * Global function to show splash screen (used by other scripts)
 * @param {string} text - The text to display
 */
function showSplashScreen(text) {
    if (globalSplashScreen) {
        // Call the async show method but don't wait for it to complete
        // This maintains the existing interface while enabling async loading
        globalSplashScreen.show(text).catch(error => {
            console.error('Error showing splash screen:', error);
        });
    }
}

/**
 * Global function to hide splash screen (used by other scripts)
 */
function hideSplashScreen() {
    if (globalSplashScreen) {
        globalSplashScreen.hide();
    }
}

/**
 * Global function to update splash screen settings (used by admin settings)
 * @param {Object} settings - Object containing displaySplash and displaySplashTime
 */
function updateSplashScreenSettings(settings) {
    if (globalSplashScreen) {
        globalSplashScreen.updateSettings(settings);
    }
}
