// Professional Avatar System using DiceBear API
// Provides high-quality avatars with 30+ professional styles

class DiceBearAvatarSystem {
    constructor() {
        this.baseURL = 'https://api.dicebear.com/9.x';
        this.currentStyle = 'adventurer';
        this.currentSeed = 'DefaultUser';
        this.currentOptions = {
            hairColor: '',
            skinColor: '',
            clothing: '',
            clothingColor: '',
            accessories: '',
            emotion: 'neutral'
        };

        // Define emotional expressions for AAC communication
        this.emotionalExpressions = {
            happy: { mood: 'happy', eyes: 'variant01', mouth: 'variant01' },
            sad: { mood: 'sad', eyes: 'variant02', mouth: 'variant02' },
            excited: { mood: 'excited', eyes: 'variant03', mouth: 'variant03' },
            neutral: { mood: 'neutral', eyes: 'variant04', mouth: 'variant04' },
            surprised: { mood: 'surprised', eyes: 'variant05', mouth: 'variant05' },
            angry: { mood: 'angry', eyes: 'variant06', mouth: 'variant06' },
            confused: { mood: 'confused', eyes: 'variant07', mouth: 'variant07' },
            thinking: { mood: 'thinking', eyes: 'variant08', mouth: 'variant08' }
        };

        // Family member presets
        this.familyPresets = {
            mom: { 
                style: 'adventurer-neutral', 
                seed: 'Mom',
                hairColor: '8d5524',
                skinColor: 'f5deb3',
                clothing: 'casual',
                clothingColor: 'ff69b4'
            },
            dad: { 
                style: 'adventurer', 
                seed: 'Dad',
                hairColor: '3c4043',
                skinColor: 'ddbea9',
                clothing: 'formal',
                clothingColor: '000080'
            },
            grandma: { 
                style: 'personas', 
                seed: 'Grandma',
                hairColor: '696969',
                skinColor: 'f5deb3',
                clothing: 'winter',
                clothingColor: '800080'
            },
            grandpa: { 
                style: 'personas', 
                seed: 'Grandpa',
                hairColor: '696969',
                skinColor: 'cb997e',
                clothing: 'formal',
                clothingColor: '2f4f4f'
            },
            sister: { 
                style: 'adventurer-neutral', 
                seed: 'Sister',
                hairColor: 'eed0a6',
                skinColor: 'f5deb3',
                clothing: 'party',
                clothingColor: 'ffc0cb'
            },
            brother: { 
                style: 'adventurer', 
                seed: 'Brother',
                hairColor: '6c4e37',
                skinColor: 'ddbea9',
                clothing: 'casual',
                clothingColor: '008000'
            }
        };

        this.init();
    }

    init() {
        console.log('Initializing DiceBear Avatar System...');
        this.setupEventListeners();
        this.generateAvatar();
        this.showDebugPanel();
    }

    setupEventListeners() {
        // Style selection
        const styleSelect = document.getElementById('avatar-style');
        if (styleSelect) {
            styleSelect.addEventListener('change', (e) => {
                this.currentStyle = e.target.value;
                this.generateAvatar();
            });
        }

        // Seed input
        const seedInput = document.getElementById('avatar-seed');
        if (seedInput) {
            seedInput.addEventListener('input', (e) => {
                this.currentSeed = e.target.value || 'DefaultUser';
                this.generateAvatar();
            });
            // Initialize with default value
            seedInput.value = this.currentSeed;
        }

        // Customization options
        const optionElements = [
            'hair-style', 'hair-color', 'skin-color', 
            'clothing-style', 'clothing-color', 'accessories'
        ];
        
        optionElements.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.addEventListener('change', (e) => {
                    const optionKey = id.replace('-', '');
                    this.currentOptions[optionKey] = e.target.value;
                    this.generateAvatar();
                });
            }
        });

        // Emotional expression buttons
        const emotionBtns = document.querySelectorAll('.emotion-btn');
        emotionBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Remove active state from all buttons
                emotionBtns.forEach(b => b.classList.remove('bg-blue-100', 'border-blue-300'));
                
                // Add active state to clicked button
                btn.classList.add('bg-blue-100', 'border-blue-300');
                
                const emotion = btn.getAttribute('data-emotion');
                this.currentOptions.emotion = emotion;
                this.generateAvatar();
            });
        });

        // Random avatar button
        const randomBtn = document.getElementById('random-avatar-btn');
        if (randomBtn) {
            randomBtn.addEventListener('click', () => this.generateRandomAvatar());
        }

        // Save variations button
        const saveBtn = document.getElementById('save-variations-btn');
        if (saveBtn) {
            saveBtn.addEventListener('click', () => this.generateAllVariations());
        }

        // Debug panel toggle
        const debugToggle = document.getElementById('toggle-debug');
        if (debugToggle) {
            debugToggle.addEventListener('click', () => {
                document.getElementById('debug-panel').classList.add('hidden');
            });
        }
    }

    buildAvatarURL(style = null, seed = null, options = {}) {
        const selectedStyle = style || this.currentStyle;
        const selectedSeed = seed || this.currentSeed;
        const mergedOptions = { ...this.currentOptions, ...options };
        
        const params = new URLSearchParams();
        params.append('seed', selectedSeed);
        
        // Add style-specific parameters
        this.addStyleSpecificParams(params, selectedStyle, mergedOptions);
        
        const url = `${this.baseURL}/${selectedStyle}/svg?${params.toString()}`;
        
        // Update debug info
        this.updateDebugInfo(url);
        
        return url;
    }

    addStyleSpecificParams(params, style, options) {
        // Common parameters for most styles
        if (options.skincolor && options.skincolor !== '') {
            params.append('skinColor', options.skincolor);
        }
        
        if (options.haircolor && options.haircolor !== '') {
            params.append('hairColor', options.haircolor);
        }
        
        if (options.clothingcolor && options.clothingcolor !== '') {
            params.append('clothingColor', options.clothingcolor);
        }

        // Style-specific parameters
        switch (style) {
            case 'adventurer':
            case 'adventurer-neutral':
                this.addAdventurerParams(params, options);
                break;
            case 'avataaars':
            case 'avataaars-neutral':
                this.addAvataaarsParams(params, options);
                break;
            case 'personas':
                this.addPersonasParams(params, options);
                break;
            case 'notionists':
            case 'notionists-neutral':
                this.addNotionistsParams(params, options);
                break;
        }

        // Apply emotional expressions
        this.applyEmotionalExpression(params, options.emotion || 'neutral', style);
    }

    addAdventurerParams(params, options) {
        // Adventurer-specific parameters
        if (options.hairstyle) params.append('hair', options.hairstyle);
        if (options.clothingstyle) params.append('clothing', options.clothingstyle);
        if (options.accessories) params.append('accessories', options.accessories);
    }

    addAvataaarsParams(params, options) {
        // Avataaars-specific parameters (similar to your existing system)
        if (options.hairstyle) params.append('topType', options.hairstyle);
        if (options.clothingstyle) params.append('clotheType', options.clothingstyle);
        if (options.accessories) params.append('accessoriesType', options.accessories);
    }

    addPersonasParams(params, options) {
        // Personas-specific parameters
        if (options.hairstyle) params.append('hair', options.hairstyle);
        if (options.clothingstyle) params.append('clothes', options.clothingstyle);
    }

    addNotionistsParams(params, options) {
        // Notionists-specific parameters
        if (options.hairstyle) params.append('hair', options.hairstyle);
        if (options.accessories) params.append('glasses', options.accessories);
    }

    applyEmotionalExpression(params, emotion, style) {
        const expression = this.emotionalExpressions[emotion];
        if (!expression) return;

        // Apply expression based on style capabilities
        switch (style) {
            case 'adventurer':
            case 'adventurer-neutral':
                if (expression.eyes) params.append('eyes', expression.eyes);
                if (expression.mouth) params.append('mouth', expression.mouth);
                break;
            case 'avataaars':
            case 'avataaars-neutral':
                if (expression.eyes) params.append('eyeType', expression.eyes);
                if (expression.mouth) params.append('mouthType', expression.mouth);
                break;
            case 'personas':
                if (expression.mood) params.append('mood', expression.mood);
                break;
        }
    }

    generateAvatar() {
        const avatarImg = document.getElementById('current-avatar');
        const styleNameEl = document.getElementById('current-style-name');
        const spinner = document.getElementById('loading-spinner');
        
        if (!avatarImg) return;

        // Show loading spinner
        if (spinner) spinner.classList.remove('hidden');
        
        const avatarURL = this.buildAvatarURL();
        
        avatarImg.onload = () => {
            if (spinner) spinner.classList.add('hidden');
            if (styleNameEl) {
                const styleName = this.currentStyle.replace('-', ' ').replace(/\b\w/g, l => l.toUpperCase());
                styleNameEl.textContent = `${styleName} - ${this.currentSeed}`;
            }
        };

        avatarImg.onerror = () => {
            if (spinner) spinner.classList.add('hidden');
            console.error('Failed to load avatar:', avatarURL);
            // Fallback to a simpler style
            if (this.currentStyle !== 'adventurer') {
                this.currentStyle = 'adventurer';
                this.generateAvatar();
            }
        };

        avatarImg.src = avatarURL;
    }

    generateRandomAvatar() {
        // Randomize all settings
        const styles = [
            'adventurer', 'adventurer-neutral', 'avataaars', 'avataaars-neutral',
            'personas', 'notionists', 'notionists-neutral', 'lorelei', 'lorelei-neutral'
        ];
        
        const hairColors = ['0e0e0e', '3c4043', '6c4e37', 'b38867', 'eed0a6', 'd4af37', 'cc9966', '8b4513', '696969'];
        const skinColors = ['f5deb3', 'ddbea9', 'cb997e', 'a0695f', '8d5524', '6f4e37', '3c1810'];
        const clothingColors = ['000000', 'ffffff', 'ff0000', '0000ff', '008000', 'ffff00', 'ffa500', '800080', 'ffc0cb'];
        const emotions = Object.keys(this.emotionalExpressions);

        // Randomize style
        this.currentStyle = styles[Math.floor(Math.random() * styles.length)];
        document.getElementById('avatar-style').value = this.currentStyle;

        // Randomize seed
        this.currentSeed = 'User' + Math.floor(Math.random() * 1000);
        document.getElementById('avatar-seed').value = this.currentSeed;

        // Randomize options
        this.currentOptions.haircolor = hairColors[Math.floor(Math.random() * hairColors.length)];
        this.currentOptions.skincolor = skinColors[Math.floor(Math.random() * skinColors.length)];
        this.currentOptions.clothingcolor = clothingColors[Math.floor(Math.random() * clothingColors.length)];
        this.currentOptions.emotion = emotions[Math.floor(Math.random() * emotions.length)];

        // Update UI
        this.updateUIFromOptions();
        this.generateAvatar();
    }

    updateUIFromOptions() {
        if (this.currentOptions.haircolor) {
            const hairSelect = document.getElementById('hair-color');
            if (hairSelect) hairSelect.value = this.currentOptions.haircolor;
        }
        if (this.currentOptions.skincolor) {
            const skinSelect = document.getElementById('skin-color');
            if (skinSelect) skinSelect.value = this.currentOptions.skincolor;
        }
        if (this.currentOptions.clothingcolor) {
            const clothingSelect = document.getElementById('clothing-color');
            if (clothingSelect) clothingSelect.value = this.currentOptions.clothingcolor;
        }

        // Update emotion button state
        const emotionBtns = document.querySelectorAll('.emotion-btn');
        emotionBtns.forEach(btn => {
            if (btn.getAttribute('data-emotion') === this.currentOptions.emotion) {
                btn.classList.add('bg-blue-100', 'border-blue-300');
            } else {
                btn.classList.remove('bg-blue-100', 'border-blue-300');
            }
        });
    }

    async generateAllVariations() {
        const saveBtn = document.getElementById('save-variations-btn');
        const previewSection = document.getElementById('variations-preview');
        const grid = document.getElementById('variations-grid');
        const countSpan = document.getElementById('variations-count');
        
        if (!saveBtn || !previewSection || !grid) return;

        // Update button state
        saveBtn.disabled = true;
        saveBtn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Generating Variations...';

        try {
            const variations = [];

            // Generate emotional variations
            for (const [emotion, expression] of Object.entries(this.emotionalExpressions)) {
                const avatarURL = this.buildAvatarURL(null, null, { emotion });
                variations.push({
                    name: emotion,
                    url: avatarURL,
                    category: 'emotion',
                    seed: `${this.currentSeed}-${emotion}`
                });
            }

            // Generate family member variations
            for (const [member, preset] of Object.entries(this.familyPresets)) {
                const avatarURL = this.buildAvatarURL(preset.style, preset.seed, preset);
                variations.push({
                    name: member,
                    url: avatarURL,
                    category: 'family',
                    seed: preset.seed
                });
            }

            // Generate style variations
            const styles = ['adventurer', 'adventurer-neutral', 'avataaars', 'personas', 'notionists'];
            for (const style of styles) {
                const avatarURL = this.buildAvatarURL(style, `${this.currentSeed}-${style}`, {});
                variations.push({
                    name: style.replace('-', ' '),
                    url: avatarURL,
                    category: 'style',
                    seed: `${this.currentSeed}-${style}`
                });
            }

            // Clear existing grid
            grid.innerHTML = '';

            // Populate grid
            variations.forEach((variation, index) => {
                const variationDiv = document.createElement('div');
                variationDiv.className = 'text-center bg-gray-50 rounded-lg p-3 hover:shadow-md transition-shadow cursor-pointer border';
                
                let categoryBadge = '';
                let badgeColor = 'bg-blue-100 text-blue-800';
                
                switch (variation.category) {
                    case 'emotion':
                        badgeColor = 'bg-yellow-100 text-yellow-800';
                        categoryBadge = 'Emotion';
                        break;
                    case 'family':
                        badgeColor = 'bg-purple-100 text-purple-800';
                        categoryBadge = 'Family';
                        break;
                    case 'style':
                        badgeColor = 'bg-green-100 text-green-800';
                        categoryBadge = 'Style';
                        break;
                }

                variationDiv.innerHTML = `
                    <img src="${variation.url}" 
                         alt="${variation.name}" 
                         class="w-20 h-20 mx-auto rounded-lg border-2 border-gray-200 mb-2 hover:border-blue-400 transition-colors">
                    <p class="text-xs font-semibold capitalize text-gray-800 mb-1">${variation.name.replace('_', ' ')}</p>
                    <span class="inline-block ${badgeColor} text-xs px-2 py-1 rounded-full mb-2">${categoryBadge}</span>
                    <button onclick="window.open('${variation.url}', '_blank')" 
                            class="text-xs text-blue-600 hover:text-blue-800 underline block mx-auto">
                        View Full
                    </button>
                `;
                
                // Add click to preview
                variationDiv.addEventListener('click', () => {
                    document.getElementById('current-avatar').src = variation.url;
                    document.getElementById('current-style-name').textContent = `${variation.name} - ${variation.seed}`;
                });

                grid.appendChild(variationDiv);
            });

            // Update count and show preview
            countSpan.textContent = `${variations.length} variations`;
            previewSection.classList.remove('hidden');

            console.log(`Generated ${variations.length} professional avatar variations`);

        } catch (error) {
            console.error('Error generating variations:', error);
            alert('Error generating avatar variations. Please try again.');
        } finally {
            saveBtn.disabled = false;
            saveBtn.innerHTML = '<i class="fas fa-save mr-2"></i>Generate All Variations';
        }
    }

    showDebugPanel() {
        const debugPanel = document.getElementById('debug-panel');
        if (debugPanel) {
            debugPanel.classList.remove('hidden');
        }
    }

    updateDebugInfo(url) {
        const debugUrl = document.getElementById('debug-url');
        if (debugUrl) {
            debugUrl.textContent = url;
        }
    }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded, initializing DiceBear Avatar System...');
    window.avatarSystem = new DiceBearAvatarSystem();
});