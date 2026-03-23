// Enhanced Avatar Selector JavaScript - Using DiceBear API with Multiple Styles

class EnhancedAvatarSelector {
    constructor() {
        this.currentConfig = {
            style: 'open-peeps', // Default to more expressive style
            seed: 'user123',
            mood: 'happy',
            backgroundColor: 'transparent',
            flip: false
        };

        // Enhanced emotional combinations with DiceBear mood support
        this.emotionalCombinations = [
            // Basic Emotions (supported by most DiceBear styles)
            { name: 'happy', mood: 'happy', category: 'emotion' },
            { name: 'sad', mood: 'sad', category: 'emotion' },
            { name: 'angry', mood: 'angry', category: 'emotion' },
            { name: 'surprised', mood: 'surprised', category: 'emotion' },
            { name: 'neutral', mood: 'neutral', category: 'emotion' },
            { name: 'excited', mood: 'excited', category: 'emotion' },
            
            // Extended Emotions
            { name: 'worried', mood: 'sad', category: 'emotion' },
            { name: 'laughing', mood: 'happy', category: 'emotion' },
            { name: 'confused', mood: 'surprised', category: 'emotion' },
            { name: 'calm', mood: 'neutral', category: 'emotion' },
            { name: 'tired', mood: 'sad', category: 'emotion' },
            { name: 'proud', mood: 'happy', category: 'emotion' },

            // AAC Essential Responses
            { name: 'yes', mood: 'happy', textOverlay: '✓', category: 'aac' },
            { name: 'no', mood: 'angry', textOverlay: '✗', category: 'aac' },
            { name: 'help', mood: 'surprised', textOverlay: '!', category: 'aac' },
            { name: 'stop', mood: 'angry', textOverlay: '🛑', category: 'aac' },
            { name: 'please', mood: 'neutral', textOverlay: '🙏', category: 'aac' },
            { name: 'thank_you', mood: 'happy', textOverlay: '♥', category: 'aac' },
            { name: 'more', mood: 'excited', textOverlay: '+', category: 'aac' },
            { name: 'finished', mood: 'happy', textOverlay: '✓', category: 'aac' },

            // Family Members (inherit skin tone, not accessories)
            { name: 'mom', mood: 'happy', category: 'family', ageModifier: 'adult', genderHint: 'female' },
            { name: 'dad', mood: 'neutral', category: 'family', ageModifier: 'adult', genderHint: 'male' },
            { name: 'grandma', mood: 'happy', category: 'family', ageModifier: 'elderly', genderHint: 'female' },
            { name: 'grandpa', mood: 'neutral', category: 'family', ageModifier: 'elderly', genderHint: 'male' },
            { name: 'sister', mood: 'happy', category: 'family', ageModifier: 'young', genderHint: 'female' },
            { name: 'brother', mood: 'neutral', category: 'family', ageModifier: 'young', genderHint: 'male' },
            { name: 'baby', mood: 'happy', category: 'family', ageModifier: 'baby', genderHint: 'neutral' },
            { name: 'friend', mood: 'happy', category: 'family', ageModifier: 'peer', genderHint: 'neutral' }
        ];

        // DiceBear styles with their capabilities
        this.avatarStyles = {
            'avataaars': {
                name: 'Avataaars (Classic)',
                baseUrl: 'https://avataaars.io/',
                supportsMood: false,
                description: 'Classic cartoon-style avatars'
            },
            'open-peeps': {
                name: 'Open Peeps (Expressive)',
                baseUrl: 'https://api.dicebear.com/9.x/open-peeps/svg',
                supportsMood: true,
                description: 'Highly expressive hand-drawn style'
            },
            'lorelei': {
                name: 'Lorelei (Artistic)',
                baseUrl: 'https://api.dicebear.com/9.x/lorelei/svg',
                supportsMood: true,
                description: 'Artistic portraits with emotions'
            },
            'adventurer': {
                name: 'Adventurer (Detailed)',
                baseUrl: 'https://api.dicebear.com/9.x/adventurer/svg',
                supportsMood: true,
                description: 'Detailed character portraits'
            },
            'big-smile': {
                name: 'Big Smile (Fun)',
                baseUrl: 'https://api.dicebear.com/9.x/big-smile/svg',
                supportsMood: true,
                description: 'Fun and colorful expressions'
            }
        };

        this.init();
    }

    init() {
        console.log('DOM loaded, initializing Enhanced Avatar Selector...');
        this.setupEventListeners();
        this.updateAvatar();
        console.log('Enhanced Avatar Selector initialized!');
    }

    setupEventListeners() {
        // Style selection
        const styleSelect = document.getElementById('avatar-style');
        if (styleSelect) {
            styleSelect.addEventListener('change', (e) => {
                this.currentConfig.style = e.target.value;
                this.updateAvatar();
            });
        }

        // Seed input
        const seedInput = document.getElementById('avatar-seed');
        if (seedInput) {
            seedInput.addEventListener('input', (e) => {
                this.currentConfig.seed = e.target.value || 'user123';
                this.updateAvatar();
            });
        }

        // Background color
        const bgSelect = document.getElementById('background-color');
        if (bgSelect) {
            bgSelect.addEventListener('change', (e) => {
                this.currentConfig.backgroundColor = e.target.value;
                this.updateAvatar();
            });
        }

        // Emotion buttons
        const emotionBtns = document.querySelectorAll('.emotion-btn');
        emotionBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Remove active state from all buttons
                emotionBtns.forEach(b => b.classList.remove('ring-2', 'ring-blue-500'));
                // Add active state to clicked button
                btn.classList.add('ring-2', 'ring-blue-500');
                
                this.currentConfig.mood = e.target.dataset.mood;
                this.updateAvatar();
            });
        });

        // Generate variations button
        const generateBtn = document.getElementById('generate-variations');
        if (generateBtn) {
            generateBtn.addEventListener('click', () => this.generateAllVariations());
        }

        // Generate random button
        const randomBtn = document.getElementById('generate-random');
        if (randomBtn) {
            randomBtn.addEventListener('click', () => this.generateRandomAvatar());
        }

        // Save avatar button
        const saveBtn = document.getElementById('save-avatar');
        if (saveBtn) {
            saveBtn.addEventListener('click', () => this.saveAvatar());
        }
    }

    generateAvatarURL(config = null, familyMemberConfig = null) {
        const finalConfig = { ...this.currentConfig, ...(config || {}) };
        const style = this.avatarStyles[finalConfig.style];
        
        if (!style) return '';

        // For family members, create a variation of the main avatar
        if (familyMemberConfig) {
            // Use a different seed to create variation but maintain consistency
            finalConfig.seed = `${finalConfig.seed}-${familyMemberConfig.name}`;
            
            // Family members don't inherit mood unless specified
            if (!familyMemberConfig.mood) {
                finalConfig.mood = 'neutral';
            }
        }

        if (finalConfig.style === 'avataaars') {
            // Use original avataaars logic for backwards compatibility
            return this.generateAvataaarsURL(config);
        } else {
            // Use DiceBear API
            const params = new URLSearchParams();
            params.append('seed', finalConfig.seed);
            
            if (style.supportsMood && finalConfig.mood) {
                params.append('mood', finalConfig.mood);
            }
            
            if (finalConfig.backgroundColor && finalConfig.backgroundColor !== 'transparent') {
                params.append('backgroundColor', finalConfig.backgroundColor);
            }
            
            // Add some randomization for family members
            if (familyMemberConfig) {
                if (familyMemberConfig.genderHint && familyMemberConfig.genderHint !== 'neutral') {
                    // DiceBear will generate appropriate variations based on seed
                }
                if (familyMemberConfig.ageModifier) {
                    // Some styles support age-related parameters
                }
            }
            
            return `${style.baseUrl}?${params.toString()}`;
        }
    }

    generateAvataaarsURL(emotionalOverride = null) {
        // Fallback for Avataaars style - simplified version
        const seed = this.currentConfig.seed;
        return `https://avataaars.io/?seed=${encodeURIComponent(seed)}`;
    }

    updateAvatar() {
        const avatarImg = document.getElementById('avatar-image');
        const loadingSpinner = document.getElementById('loading-spinner');
        
        if (!avatarImg) return;

        if (loadingSpinner) loadingSpinner.style.display = 'flex';
        avatarImg.style.display = 'none';

        const url = this.generateAvatarURL();
        
        avatarImg.onload = () => {
            if (loadingSpinner) loadingSpinner.style.display = 'none';
            avatarImg.style.display = 'block';
            
            const saveBtn = document.getElementById('save-avatar');
            if (saveBtn) saveBtn.style.display = 'inline-block';
        };
        
        avatarImg.onerror = () => {
            if (loadingSpinner) loadingSpinner.style.display = 'none';
            console.error('Failed to load avatar:', url);
        };
        
        avatarImg.src = url;
    }

    generateRandomAvatar() {
        // Generate random configurations
        const styles = Object.keys(this.avatarStyles);
        const moods = ['happy', 'sad', 'angry', 'surprised', 'neutral', 'excited'];
        const backgrounds = ['transparent', 'solid', 'gradientLinear'];
        
        this.currentConfig.style = styles[Math.floor(Math.random() * styles.length)];
        this.currentConfig.mood = moods[Math.floor(Math.random() * moods.length)];
        this.currentConfig.backgroundColor = backgrounds[Math.floor(Math.random() * backgrounds.length)];
        this.currentConfig.seed = 'user' + Math.floor(Math.random() * 1000);
        
        // Update UI elements
        const styleSelect = document.getElementById('avatar-style');
        if (styleSelect) styleSelect.value = this.currentConfig.style;
        
        const seedInput = document.getElementById('avatar-seed');
        if (seedInput) seedInput.value = this.currentConfig.seed;
        
        const bgSelect = document.getElementById('background-color');
        if (bgSelect) bgSelect.value = this.currentConfig.backgroundColor;
        
        // Update emotion buttons
        const emotionBtns = document.querySelectorAll('.emotion-btn');
        emotionBtns.forEach(btn => {
            btn.classList.remove('ring-2', 'ring-blue-500');
            if (btn.dataset.mood === this.currentConfig.mood) {
                btn.classList.add('ring-2', 'ring-blue-500');
            }
        });
        
        this.updateAvatar();
    }

    generateAllVariations() {
        const variations = [];
        
        // Generate all emotional and AAC variations
        this.emotionalCombinations.forEach(emotion => {
            const config = {
                mood: emotion.mood
            };
            
            let url;
            if (emotion.category === 'family') {
                url = this.generateAvatarURL(config, emotion);
            } else {
                url = this.generateAvatarURL(config);
            }
            
            variations.push({
                emotion: emotion.name,
                url: url,
                category: emotion.category,
                textOverlay: emotion.textOverlay
            });
        });
        
        this.displayVariations(variations);
    }

    displayVariations(variations) {
        const container = document.getElementById('variations-container');
        const countElement = document.getElementById('variations-count');
        const grid = document.getElementById('variations-grid');
        
        if (!container || !grid) return;
        
        container.style.display = 'block';
        if (countElement) countElement.textContent = variations.length;
        
        grid.innerHTML = '';
        
        variations.forEach((variation, index) => {
            const variationDiv = document.createElement('div');
            variationDiv.className = 'text-center bg-white rounded-lg p-3 shadow-sm hover:shadow-md transition-shadow cursor-pointer border';
            
            const isFamily = variation.category === 'family';
            const isAAC = variation.category === 'aac';
            const isEmotion = variation.category === 'emotion';
            
            let categoryBadge = '';
            let categoryColor = 'bg-gray-100 text-gray-800';
            
            if (isAAC) {
                categoryBadge = 'AAC Response';
                categoryColor = 'bg-green-100 text-green-800';
            } else if (isFamily) {
                categoryBadge = 'Family Member';
                categoryColor = 'bg-purple-100 text-purple-800';
            } else if (isEmotion) {
                categoryBadge = 'Emotion';
                categoryColor = 'bg-blue-100 text-blue-800';
            }
            
            // Create composite image for family members
            let imageHTML = '';
            if (isFamily) {
                const mainAvatarUrl = this.generateAvatarURL();
                imageHTML = `
                <div class="relative flex items-end justify-center mb-2">
                    <img src="${variation.url}" 
                         alt="${variation.emotion}" 
                         class="w-20 h-20 rounded-full border-2 border-gray-200 hover:border-purple-400 transition-colors"
                         onclick="this.classList.toggle('scale-110'); this.style.zIndex = this.style.zIndex ? '' : '10';">
                    <img src="${mainAvatarUrl}" 
                         alt="Main Avatar" 
                         class="w-12 h-12 rounded-full border-2 border-blue-300 ml-1 opacity-80"
                         title="Main Avatar (You)">
                    ${variation.textOverlay ? `<div class="absolute -bottom-1 -right-1 bg-purple-600 text-white text-sm font-bold rounded-full w-6 h-6 flex items-center justify-center shadow-lg">${variation.textOverlay}</div>` : ''}
                </div>`;
            } else {
                imageHTML = `
                <div class="relative mb-2">
                    <img src="${variation.url}" 
                         alt="${variation.emotion}" 
                         class="w-24 h-24 mx-auto rounded-full border-2 border-gray-200 hover:border-blue-400 transition-colors"
                         onclick="this.classList.toggle('scale-110'); this.style.zIndex = this.style.zIndex ? '' : '10';">
                    ${variation.textOverlay ? `<div class="absolute -bottom-1 -right-1 bg-blue-600 text-white text-sm font-bold rounded-full w-6 h-6 flex items-center justify-center shadow-lg">${variation.textOverlay}</div>` : ''}
                </div>`;
            }
            
            variationDiv.innerHTML = `
                ${imageHTML}
                <p class="text-sm font-semibold capitalize text-gray-800">${variation.emotion.replace('_', ' ')}</p>
                <span class="inline-block ${categoryColor} text-xs px-2 py-1 rounded-full mt-1">${categoryBadge}</span>
                <button onclick="window.open('${variation.url}', '_blank')" 
                        class="mt-2 text-xs text-blue-600 hover:text-blue-800 underline block w-full">
                    View Full Size
                </button>
            `;
            
            grid.appendChild(variationDiv);
        });
        
        // Add download all functionality
        const downloadBtn = document.getElementById('download-all-btn');
        if (downloadBtn) {
            downloadBtn.onclick = () => this.downloadAllVariations(variations);
        }
    }

    async downloadAllVariations(variations) {
        // Simple implementation - open each in new tab
        // In a real app, you'd want to zip them or provide a better download mechanism
        for (let i = 0; i < variations.length; i++) {
            const variation = variations[i];
            setTimeout(() => {
                const link = document.createElement('a');
                link.href = variation.url;
                link.download = `avatar-${variation.emotion}.svg`;
                link.target = '_blank';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
            }, i * 100); // Stagger downloads
        }
    }

    saveAvatar() {
        const url = this.generateAvatarURL();
        const link = document.createElement('a');
        link.href = url;
        link.download = `avatar-${this.currentConfig.seed}-${this.currentConfig.mood}.svg`;
        link.target = '_blank';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
}

// Initialize the Enhanced Avatar Selector when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new EnhancedAvatarSelector();
});