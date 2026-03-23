// Simplified DiceBear Avatar System for Testing
// Let's start with a basic working version

class SimpleDiceBearSystem {
    constructor() {
        this.baseURL = 'https://api.dicebear.com/9.x';
        this.currentSeed = 'TestUser';
        this.currentStyle = 'open-peeps'; // Default to actual full-body style
        
        console.log('Initializing Simple DiceBear System...');
        this.init();
    }

    init() {
        this.setupBasicListeners();
        this.loadDefaultAvatar();
        console.log('Simple DiceBear System initialized!');
    }

    setupBasicListeners() {
        console.log('Setting up event listeners...');
        
        // Style selector
        const styleSelect = document.getElementById('avatar-style');
        if (styleSelect) {
            styleSelect.addEventListener('change', (e) => {
                console.log('Style selector changed:', e.target.value);
                this.currentStyle = e.target.value;
                this.loadDefaultAvatar();
            });
            console.log('Style selector listener added');
        } else {
            console.error('Style selector not found!');
        }

        // Seed input
        const seedInput = document.getElementById('avatar-seed');
        if (seedInput) {
            seedInput.addEventListener('input', (e) => {
                console.log('Seed input changed:', e.target.value);
                this.currentSeed = e.target.value || 'TestUser';
                this.loadDefaultAvatar();
            });
            seedInput.value = this.currentSeed;
            console.log('Seed input listener added, value set to:', this.currentSeed);
        } else {
            console.error('Seed input not found!');
        }

        // Add listeners for other controls
        const controls = [
            'hair-style', 'hair-color', 'skin-color', 
            'clothing-style', 'clothing-color', 'accessories'
        ];
        
        controls.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.addEventListener('change', (e) => {
                    console.log(`${id} changed:`, e.target.value);
                    this.loadDefaultAvatar(); // Reload avatar when any control changes
                });
                console.log(`Added listener for ${id}`);
            }
        });

        // Random button
        const randomBtn = document.getElementById('random-avatar-btn');
        if (randomBtn) {
            randomBtn.addEventListener('click', (e) => {
                console.log('Random button clicked');
                this.generateRandomAvatar();
            });
            console.log('Random button listener added');
        } else {
            console.error('Random button not found!');
        }

        // Generate variations button
        const variationsBtn = document.getElementById('save-variations-btn');
        if (variationsBtn) {
            variationsBtn.addEventListener('click', (e) => {
                console.log('Variations button clicked');
                this.generateBasicVariations();
            });
            console.log('Variations button listener added');
        } else {
            console.error('Variations button not found!');
        }
    }

    buildSimpleURL(style = null, seed = null) {
        const useStyle = style || this.currentStyle;
        const useSeed = seed || this.currentSeed;
        
        // Use full-body styles and add parameters for better customization
        let finalStyle = useStyle;
        let params = new URLSearchParams();
        params.append('seed', useSeed);
        
        // Map to full-body styles where possible
        if (useStyle === 'avataaars' || useStyle === 'avataaars-neutral') {
            // Keep avataaars as is (head/bust style)
            finalStyle = useStyle;
        } else if (useStyle === 'adventurer' || useStyle === 'adventurer-neutral') {
            // These are already full-body
            finalStyle = useStyle;
            params.append('backgroundColor', 'transparent');
        } else if (useStyle === 'personas') {
            // Full-body professional style
            finalStyle = 'personas';
            params.append('backgroundColor', 'transparent');
        } else {
            // Default to adventurer for full-body
            finalStyle = 'adventurer';
            params.append('backgroundColor', 'transparent');
        }
        
        const url = `${this.baseURL}/${finalStyle}/svg?${params.toString()}`;
        console.log('Generated URL:', url);
        
        // Update debug info
        const debugUrl = document.getElementById('debug-url');
        if (debugUrl) {
            debugUrl.textContent = url;
        }
        
        return url;
    }

    loadDefaultAvatar() {
        const avatarImg = document.getElementById('current-avatar');
        const styleNameEl = document.getElementById('current-style-name');
        const spinner = document.getElementById('loading-spinner');
        
        if (!avatarImg) {
            console.error('Avatar image element not found!');
            return;
        }

        console.log('Loading avatar...');
        
        // Show loading spinner
        if (spinner) spinner.classList.remove('hidden');
        
        const avatarURL = this.buildSimpleURL();
        
        // Set up error and load handlers
        avatarImg.onload = () => {
            console.log('Avatar loaded successfully!');
            if (spinner) spinner.classList.add('hidden');
            if (styleNameEl) {
                styleNameEl.textContent = `${this.currentStyle} - ${this.currentSeed}`;
            }
        };

        avatarImg.onerror = (error) => {
            console.error('Failed to load avatar:', avatarURL, error);
            if (spinner) spinner.classList.add('hidden');
            
            // Try a fallback style
            if (this.currentStyle !== 'adventurer') {
                console.log('Trying fallback style: adventurer');
                this.currentStyle = 'adventurer';
                document.getElementById('avatar-style').value = 'adventurer';
                this.loadDefaultAvatar();
                return;
            }
            
            // Show error message
            if (styleNameEl) {
                styleNameEl.textContent = 'Error loading avatar - check console';
            }
        };

        // Load the avatar
        console.log('Setting avatar src to:', avatarURL);
        avatarImg.src = avatarURL;
    }

    generateRandomAvatar() {
        // Use actual full-body styles first, then head/bust styles
        const styles = [
            'open-peeps', 'bottts', 'bottts-neutral', 'croodles', 'croodles-neutral', // Full body
            'adventurer', 'adventurer-neutral', 'avataaars', 'avataaars-neutral' // Head/bust
        ];
        const randomSeeds = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Henry'];
        
        this.currentStyle = styles[Math.floor(Math.random() * styles.length)];
        this.currentSeed = randomSeeds[Math.floor(Math.random() * randomSeeds.length)] + Math.floor(Math.random() * 100);
        
        // Update UI
        const styleSelect = document.getElementById('avatar-style');
        const seedInput = document.getElementById('avatar-seed');
        
        if (styleSelect) styleSelect.value = this.currentStyle;
        if (seedInput) seedInput.value = this.currentSeed;
        
        this.loadDefaultAvatar();
        console.log('Generated random avatar:', this.currentStyle, this.currentSeed);
    }

    generateBasicVariations() {
        const variationsBtn = document.getElementById('save-variations-btn');
        const previewSection = document.getElementById('variations-preview');
        const grid = document.getElementById('variations-grid');
        const countSpan = document.getElementById('variations-count');
        
        if (!grid || !previewSection) {
            console.error('Variations UI elements not found');
            return;
        }

        console.log('Generating basic variations...');
        
        // Update button state
        variationsBtn.disabled = true;
        variationsBtn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Generating...';

        // Clear existing grid
        grid.innerHTML = '';

        const variations = [];
        const styles = ['open-peeps', 'bottts', 'croodles', 'adventurer', 'avataaars'];
        const emotions = ['happy', 'sad', 'excited', 'neutral', 'surprised'];
        
        // Create style variations
        styles.forEach(style => {
            const url = this.buildSimpleURL(style, `${this.currentSeed}-${style}`);
            variations.push({
                name: style.replace('-', ' '),
                url: url,
                category: 'style'
            });
        });

        // Create emotion variations (different seeds to simulate emotions)
        emotions.forEach(emotion => {
            const url = this.buildSimpleURL(this.currentStyle, `${emotion}-${this.currentSeed}`);
            variations.push({
                name: emotion,
                url: url,
                category: 'emotion'
            });
        });

        console.log(`Created ${variations.length} variations`);

        // Populate grid
        variations.forEach((variation, index) => {
            const variationDiv = document.createElement('div');
            variationDiv.className = 'text-center bg-gray-50 rounded-lg p-3 hover:shadow-md transition-shadow cursor-pointer border';
            
            const categoryColor = variation.category === 'style' ? 'bg-green-100 text-green-800' : 'bg-yellow-100 text-yellow-800';
            
            variationDiv.innerHTML = `
                <img src="${variation.url}" 
                     alt="${variation.name}" 
                     class="w-20 h-20 mx-auto rounded-lg border-2 border-gray-200 mb-2 hover:border-blue-400 transition-colors"
                     loading="lazy">
                <p class="text-xs font-semibold capitalize text-gray-800 mb-1">${variation.name}</p>
                <span class="inline-block ${categoryColor} text-xs px-2 py-1 rounded-full mb-2">${variation.category}</span>
                <button onclick="window.open('${variation.url}', '_blank')" 
                        class="text-xs text-blue-600 hover:text-blue-800 underline block mx-auto">
                    View Full
                </button>
            `;
            
            // Click to preview
            variationDiv.addEventListener('click', () => {
                document.getElementById('current-avatar').src = variation.url;
                document.getElementById('current-style-name').textContent = variation.name;
            });

            grid.appendChild(variationDiv);
        });

        // Update count and show preview
        countSpan.textContent = `${variations.length} variations`;
        previewSection.classList.remove('hidden');

        // Reset button
        variationsBtn.disabled = false;
        variationsBtn.innerHTML = '<i class="fas fa-save mr-2"></i>Generate All Variations';
        
        console.log('Variations display completed!');
    }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded, initializing Simple DiceBear System...');
    
    // Show debug panel
    const debugPanel = document.getElementById('debug-panel');
    if (debugPanel) {
        debugPanel.classList.remove('hidden');
    }
    
    // Initialize the system
    window.avatarSystem = new SimpleDiceBearSystem();
});