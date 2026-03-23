// Avatar Selector JavaScript - Enhanced with AAC support and family members

class AvatarSelector {
    constructor() {
        this.currentConfig = {
            avatarStyle: 'Circle',
            topType: 'ShortHairShortFlat',
            accessoriesType: 'Blank',
            hairColor: 'BrownDark',
            facialHairType: 'Blank',
            facialHairColor: 'BrownDark',
            clotheType: 'BlazerShirt',
            clotheColor: 'BlueGray',
            eyeType: 'Default',
            eyebrowType: 'Default',
            mouthType: 'Default',
            skinColor: 'Light'
        };

        // Enhanced emotional combinations with more emotions and family members
        this.emotionalCombinations = [
            // PHASE 1: Core Emotions (8 variations) - Enhanced
            { name: 'happy', eyeType: 'Happy', eyebrowType: 'Default', mouthType: 'Smile' },
            { name: 'sad', eyeType: 'Cry', eyebrowType: 'SadConcerned', mouthType: 'Sad' },
            { name: 'angry', eyeType: 'Squint', eyebrowType: 'AngryNatural', mouthType: 'Grimace' },
            { name: 'surprised', eyeType: 'Surprised', eyebrowType: 'RaisedExcited', mouthType: 'Disbelief' },
            { name: 'wink', eyeType: 'Wink', eyebrowType: 'Default', mouthType: 'Twinkle' },
            { name: 'sleepy', eyeType: 'Dizzy', eyebrowType: 'Default', mouthType: 'Eating' },
            { name: 'excited', eyeType: 'Hearts', eyebrowType: 'RaisedExcited', mouthType: 'Smile' },
            { name: 'neutral', eyeType: 'Default', eyebrowType: 'Default', mouthType: 'Default' },

            // PHASE 1B: Extended Emotions (15 variations) - More nuanced
            { name: 'confused', eyeType: 'Dizzy', eyebrowType: 'RaisedExcitedNatural', mouthType: 'Concerned' },
            { name: 'worried', eyeType: 'Side', eyebrowType: 'SadConcernedNatural', mouthType: 'Concerned' },
            { name: 'laughing', eyeType: 'Squint', eyebrowType: 'Default', mouthType: 'Tongue' },
            { name: 'crying', eyeType: 'Cry', eyebrowType: 'SadConcerned', mouthType: 'Sad' },
            { name: 'skeptical', eyeType: 'Side', eyebrowType: 'UpDown', mouthType: 'Serious' },
            { name: 'embarrassed', eyeType: 'Side', eyebrowType: 'Default', mouthType: 'Concerned' },
            { name: 'proud', eyeType: 'Default', eyebrowType: 'RaisedExcited', mouthType: 'Smile' },
            { name: 'tired', eyeType: 'EyeRoll', eyebrowType: 'Default', mouthType: 'Eating' },
            { name: 'love', eyeType: 'Hearts', eyebrowType: 'Default', mouthType: 'Twinkle' },
            { name: 'scared', eyeType: 'Surprised', eyebrowType: 'FlatNatural', mouthType: 'ScreamOpen' },
            { name: 'disgusted', eyeType: 'Side', eyebrowType: 'AngryNatural', mouthType: 'Grimace' },
            { name: 'thinking', eyeType: 'Side', eyebrowType: 'FlatNatural', mouthType: 'Default' },
            { name: 'contemplating', eyeType: 'Side', eyebrowType: 'FlatNatural', mouthType: 'Default' },
            { name: 'serious', eyeType: 'Default', eyebrowType: 'Default', mouthType: 'Serious' },
            { name: 'determined', eyeType: 'Default', eyebrowType: 'AngryNatural', mouthType: 'Serious' },
            { name: 'focused', eyeType: 'Squint', eyebrowType: 'Default', mouthType: 'Serious' },
            { name: 'disbelief', eyeType: 'EyeRoll', eyebrowType: 'UpDown', mouthType: 'Disbelief' },
            { name: 'amazed', eyeType: 'Surprised', eyebrowType: 'RaisedExcited', mouthType: 'Twinkle' },

            // PHASE 2: Simple Responses (Essential for AAC) - Enhanced
            { name: 'yes', eyeType: 'Happy', eyebrowType: 'RaisedExcited', mouthType: 'Smile', textOverlay: '✓' },
            { name: 'no', eyeType: 'Default', eyebrowType: 'Angry', mouthType: 'Serious', textOverlay: '✗' },
            { name: 'maybe', eyeType: 'Side', eyebrowType: 'UpDown', mouthType: 'Concerned', textOverlay: '?' },
            { name: 'i_dont_know', eyeType: 'Dizzy', eyebrowType: 'UpDown', mouthType: 'Concerned', textOverlay: '?' },
            { name: 'stop', eyeType: 'Default', eyebrowType: 'Angry', mouthType: 'Serious', textOverlay: '🛑' },
            { name: 'go', eyeType: 'Happy', eyebrowType: 'Default', mouthType: 'Smile', textOverlay: '→' },
            { name: 'help', eyeType: 'Surprised', eyebrowType: 'RaisedExcited', mouthType: 'ScreamOpen', textOverlay: '!' },
            { name: 'please', eyeType: 'Default', eyebrowType: 'RaisedExcited', mouthType: 'Default', textOverlay: '🙏' },
            { name: 'thank_you', eyeType: 'Happy', eyebrowType: 'Default', mouthType: 'Smile', textOverlay: '♥' },
            { name: 'more', eyeType: 'Default', eyebrowType: 'RaisedExcited', mouthType: 'Default', textOverlay: '+' },
            { name: 'finished', eyeType: 'Happy', eyebrowType: 'Default', mouthType: 'Smile', textOverlay: '✓' },
            { name: 'wait', eyeType: 'Default', eyebrowType: 'Default', mouthType: 'Serious', textOverlay: '⏸' },

            // PHASE 3A: Family Members (9 variations)
            { 
                name: 'mom', 
                topType: 'LongHairStraight', 
                clotheType: 'BlazerSweater', 
                clotheColor: 'PastelBlue',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Smile' 
            },
            { 
                name: 'dad', 
                topType: 'ShortHairShortFlat', 
                clotheType: 'BlazerShirt', 
                clotheColor: 'Gray02',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },
            { 
                name: 'grandma', 
                topType: 'LongHairBob', 
                hairColor: 'SilverGray', 
                clotheType: 'CollarSweater', 
                clotheColor: 'Heather',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Smile' 
            },
            { 
                name: 'grandpa', 
                topType: 'ShortHairShortFlat', 
                hairColor: 'SilverGray', 
                clotheType: 'BlazerShirt', 
                clotheColor: 'Gray01',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },
            { 
                name: 'sister', 
                topType: 'LongHairCurly', 
                clotheType: 'ShirtCrewNeck', 
                clotheColor: 'Pink',
                eyeType: 'Happy', 
                eyebrowType: 'Default', 
                mouthType: 'Smile' 
            },
            { 
                name: 'brother', 
                topType: 'ShortHairShortWaved', 
                clotheType: 'Hoodie', 
                clotheColor: 'Blue02',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },
            { 
                name: 'baby', 
                topType: 'ShortHairShortFlat', 
                clotheType: 'Overall', 
                clotheColor: 'PastelYellow',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },
            { 
                name: 'teenager', 
                topType: 'LongHairShavedSides', 
                clotheType: 'GraphicShirt', 
                clotheColor: 'Red',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },
            { 
                name: 'adult', 
                topType: 'ShortHairTheCaesar', 
                clotheType: 'BlazerShirt', 
                clotheColor: 'Gray02',
                eyeType: 'Default', 
                eyebrowType: 'Default', 
                mouthType: 'Default' 
            },

            // PHASE 3B: Family Groups (1 new composite option)
            { 
                name: 'family_parents', 
                isComposite: true,
                description: 'You with both parents',
                members: ['main', 'mom', 'dad']
            }
        ];

        this.init();
    }

    init() {
        console.log('DOM loaded, initializing Avatar Selector...');
        this.setupAvatarPreview();
        this.setupDropdownListeners();
        this.setupEventListeners();
        this.updateAvatar();
    }

    setupAvatarPreview() {
        // Avatar preview is handled by HTML structure
    }

    setupDropdownListeners() {
        // These would be set up if we had dropdowns in the HTML
    }

    setupEventListeners() {
        const generateBtn = document.getElementById('generate-all-btn');
        if (generateBtn) {
            generateBtn.addEventListener('click', () => this.generateAllVariations());
        }

        const saveAvatarBtn = document.getElementById('save-avatar');
        if (saveAvatarBtn) {
            saveAvatarBtn.addEventListener('click', () => this.saveAvatar());
        }
    }

    generateAvataaarsURL(emotionalOverride = null) {
        const params = new URLSearchParams();
        const config = { ...this.currentConfig };
        
        // Apply emotional override if provided
        if (emotionalOverride) {
            // For family members, only inherit basic characteristics, not accessories
            const isFamilyMember = emotionalOverride.topType || emotionalOverride.clotheType;
            
            if (isFamilyMember) {
                // Family members inherit skin tone but NOT accessories, facial hair, or hats
                config.skinColor = this.currentConfig.skinColor; // Keep main avatar's skin tone
                config.accessoriesType = 'Blank'; // Remove accessories for family members
                config.facialHairType = 'Blank'; // Remove facial hair for all family members (including Grandma!)
                
                // Apply family member specific attributes
                if (emotionalOverride.topType) config.topType = emotionalOverride.topType;
                if (emotionalOverride.hairColor) config.hairColor = emotionalOverride.hairColor;
                if (emotionalOverride.clotheType) config.clotheType = emotionalOverride.clotheType;
                if (emotionalOverride.clotheColor) config.clotheColor = emotionalOverride.clotheColor;
            }
            
            // Always apply facial expressions (for both emotions and family members)
            config.eyeType = emotionalOverride.eyeType;
            config.eyebrowType = emotionalOverride.eyebrowType;
            config.mouthType = emotionalOverride.mouthType;
        }
        
        for (const [key, value] of Object.entries(config)) {
            if (value) {
                params.append(key, value);
            }
        }
        // Always ensure transparent background for all avatars
        params.append('background', 'transparent');
        return `https://avataaars.io/?${params.toString()}`;
    }

    updateAvatar() {
        const avatarImg = document.getElementById('avatar-image');
        const loadingSpinner = document.getElementById('loading-spinner');
        const saveBtn = document.getElementById('save-avatar');
        
        if (!avatarImg) return;

        if (loadingSpinner) loadingSpinner.style.display = 'flex';
        avatarImg.style.display = 'none';
        if (saveBtn) saveBtn.style.display = 'none';

        const avatarUrl = this.generateAvataaarsURL();
        
        avatarImg.src = avatarUrl;
        avatarImg.onload = () => {
            if (loadingSpinner) loadingSpinner.style.display = 'none';
            avatarImg.style.display = 'block';
            if (saveBtn) saveBtn.style.display = 'inline-block';
        };
        avatarImg.onerror = () => {
            if (loadingSpinner) loadingSpinner.style.display = 'none';
            console.error('Failed to load avatar');
        };
    }

    generateRandomAvatar() {
        // This could be implemented if needed
    }

    updateUI() {
        // Update UI elements if we had form controls
    }

    saveAvatar() {
        // Generate all variations and display them
        this.generateAllVariations();
        console.log('Avatar saved - generating complete AAC set automatically');
    }

    generateAllVariations() {
        const variations = [];

        this.emotionalCombinations.forEach(emotionalOverride => {
            const isFamily = emotionalOverride.topType || emotionalOverride.clotheType;
            const isComposite = emotionalOverride.isComposite;
            
            if (isComposite) {
                // Handle composite family images
                const mainAvatarUrl = this.generateAvataaarsURL();
                const momConfig = this.emotionalCombinations.find(e => e.name === 'mom');
                const dadConfig = this.emotionalCombinations.find(e => e.name === 'dad');
                
                variations.push({
                    emotion: emotionalOverride.name,
                    url: mainAvatarUrl, // For now, use main avatar - could be enhanced to create composite
                    category: 'family',
                    description: emotionalOverride.description,
                    isComposite: true,
                    textOverlay: emotionalOverride.textOverlay
                });
            } else {
                const avatarUrl = this.generateAvataaarsURL(emotionalOverride);
                let category = 'emotion';
                
                if (isFamily) {
                    category = 'family';
                } else if (emotionalOverride.textOverlay) {
                    category = 'aac';
                }
                
                variations.push({
                    emotion: emotionalOverride.name,
                    url: avatarUrl,
                    category: category,
                    textOverlay: emotionalOverride.textOverlay
                });
            }
        });
        
        this.displayVariations(variations);
    }

    displayVariations(variations) {
        let container = document.getElementById('variations-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'variations-container';
            container.className = 'mt-8 bg-white rounded-lg shadow-lg p-6';
            document.querySelector('.max-w-4xl').appendChild(container);
        }
        
        container.innerHTML = `
            <div class="flex justify-between items-center mb-6">
                <h2 class="text-2xl font-bold text-gray-900">
                    <span id="variations-count">${variations.length}</span> Avatar Variations Generated
                </h2>
                <button id="download-all-btn" class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg transition-colors">
                    <i class="fas fa-download mr-2"></i>Download All
                </button>
            </div>
            <div id="variations-grid" class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                <!-- Generated variations will appear here -->
            </div>
        `;
        
        const grid = document.getElementById('variations-grid');
        
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
            if (isFamily && !variation.isComposite) {
                const mainAvatarUrl = this.generateAvataaarsURL();
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
            } else if (variation.isComposite) {
                // Special handling for composite family images
                const mainAvatarUrl = this.generateAvataaarsURL();
                const momConfig = this.emotionalCombinations.find(e => e.name === 'mom');
                const dadConfig = this.emotionalCombinations.find(e => e.name === 'dad');
                const momUrl = this.generateAvataaarsURL(momConfig);
                const dadUrl = this.generateAvataaarsURL(dadConfig);
                
                imageHTML = `
                <div class="relative flex items-end justify-center mb-2">
                    <img src="${mainAvatarUrl}" 
                         alt="You" 
                         class="w-16 h-16 rounded-full border-2 border-blue-300"
                         title="You">
                    <img src="${momUrl}" 
                         alt="Mom" 
                         class="w-14 h-14 rounded-full border-2 border-pink-300 -ml-2"
                         title="Mom">
                    <img src="${dadUrl}" 
                         alt="Dad" 
                         class="w-14 h-14 rounded-full border-2 border-blue-400 -ml-2"
                         title="Dad">
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
        
        container.style.display = 'block';
    }

    async downloadAllVariations(variations) {
        // Download all variations with a small delay between each
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
            }, i * 100); // Stagger downloads by 100ms
        }
    }

    showVariationsPreview(variations) {
        // Create a dedicated preview section if it doesn't exist
        let previewSection = document.getElementById('variations-preview');
        if (!previewSection) {
            previewSection = document.createElement('div');
            previewSection.id = 'variations-preview';
            previewSection.className = 'mt-6 p-4 bg-gray-50 rounded-lg border';
            previewSection.innerHTML = `
                <h3 class="font-medium text-gray-800 mb-3">Quick Preview</h3>
                <div id="preview-grid" class="grid grid-cols-8 gap-2"></div>
            `;
            document.querySelector('.bg-white.rounded-lg.shadow-lg.p-8').appendChild(previewSection);
        }
        
        const previewGrid = document.getElementById('preview-grid');
        previewGrid.innerHTML = '';
        
        variations.slice(0, 16).forEach(variation => {
            const previewImg = document.createElement('img');
            previewImg.src = variation.url;
            previewImg.alt = variation.emotion;
            previewImg.className = 'w-12 h-12 rounded-lg border hover:border-blue-400 transition-colors cursor-pointer';
            previewImg.title = variation.emotion.replace('_', ' ');
            previewGrid.appendChild(previewImg);
        });
    }

    downloadAllVariations(variations) {
        // Simple download implementation
        variations.forEach((variation, index) => {
            setTimeout(() => {
                const link = document.createElement('a');
                link.href = variation.url;
                link.download = `avatar-${variation.emotion}.png`;
                link.click();
            }, index * 200);
        });
    }
}

// Initialize Avatar Selector when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new AvatarSelector();
});