// Funko Pop Avatar Creator
// Creates custom SVG Funko Pop style avatars

class FunkoAvatarCreator {
    constructor() {
        this.currentConfig = {
            characterName: 'Your Funko',
            characterType: 'human',
            hairStyle: 'short',
            hairColor: 'brown',
            outfitType: 'casual',
            outfitColor: 'blue',
            accessories: []
        };

        this.funkoPalette = {
            // Funko Pop characteristic colors
            skin: {
                light: '#FDBCB4',
                medium: '#E7A47B', 
                tan: '#D4915F',
                dark: '#B87355'
            },
            hair: {
                blonde: '#F4D03F',
                brown: '#8B4513',
                black: '#2C2C2C',
                red: '#CC5500',
                gray: '#A9A9A9',
                pink: '#FF69B4',
                blue: '#4169E1',
                green: '#32CD32'
            },
            outfit: {
                red: '#FF0000',
                blue: '#0066CC',
                green: '#00AA00',
                yellow: '#FFD700',
                purple: '#9932CC',
                pink: '#FF69B4',
                black: '#333333',
                white: '#FFFFFF'
            }
        };

        this.init();
    }

    init() {
        console.log('Initializing Funko Pop Avatar Creator...');
        this.setupEventListeners();
        this.generateFunkoAvatar();
        console.log('Funko Pop Creator ready!');
    }

    setupEventListeners() {
        // Character name input
        const nameInput = document.getElementById('character-name');
        if (nameInput) {
            nameInput.addEventListener('input', (e) => {
                this.currentConfig.characterName = e.target.value || 'Your Funko';
                this.updateFunkoDisplay();
            });
        }

        // Character type buttons
        document.querySelectorAll('.character-type-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Remove active state from all buttons
                document.querySelectorAll('.character-type-btn').forEach(b => {
                    b.classList.remove('bg-white/30', 'border-yellow-400');
                    b.classList.add('bg-white/10', 'border-white/30');
                });
                
                // Add active state to clicked button
                btn.classList.remove('bg-white/10', 'border-white/30');
                btn.classList.add('bg-white/30', 'border-yellow-400');
                
                this.currentConfig.characterType = btn.getAttribute('data-type');
                this.generateFunkoAvatar();
            });
        });

        // Hair style dropdown
        const hairStyleSelect = document.getElementById('hair-style');
        if (hairStyleSelect) {
            hairStyleSelect.addEventListener('change', (e) => {
                this.currentConfig.hairStyle = e.target.value;
                this.generateFunkoAvatar();
            });
        }

        // Hair color buttons
        document.querySelectorAll('.hair-color-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Remove active state from all hair color buttons
                document.querySelectorAll('.hair-color-btn').forEach(b => {
                    b.classList.remove('ring-4', 'ring-white');
                });
                
                // Add active state to clicked button
                btn.classList.add('ring-4', 'ring-white');
                
                this.currentConfig.hairColor = btn.getAttribute('data-color');
                this.generateFunkoAvatar();
            });
        });

        // Outfit type dropdown
        const outfitTypeSelect = document.getElementById('outfit-type');
        if (outfitTypeSelect) {
            outfitTypeSelect.addEventListener('change', (e) => {
                this.currentConfig.outfitType = e.target.value;
                this.generateFunkoAvatar();
            });
        }

        // Outfit color buttons
        document.querySelectorAll('.outfit-color-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Remove active state from all outfit color buttons
                document.querySelectorAll('.outfit-color-btn').forEach(b => {
                    b.classList.remove('ring-4', 'ring-white');
                });
                
                // Add active state to clicked button
                btn.classList.add('ring-4', 'ring-white');
                
                this.currentConfig.outfitColor = btn.getAttribute('data-color');
                this.generateFunkoAvatar();
            });
        });

        // Accessory buttons
        document.querySelectorAll('.accessory-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const accessory = btn.getAttribute('data-accessory');
                
                if (btn.classList.contains('bg-yellow-400')) {
                    // Remove accessory
                    btn.classList.remove('bg-yellow-400', 'text-gray-900');
                    btn.classList.add('bg-white/10', 'text-white');
                    this.currentConfig.accessories = this.currentConfig.accessories.filter(a => a !== accessory);
                } else {
                    // Add accessory
                    btn.classList.remove('bg-white/10', 'text-white');
                    btn.classList.add('bg-yellow-400', 'text-gray-900');
                    if (!this.currentConfig.accessories.includes(accessory)) {
                        this.currentConfig.accessories.push(accessory);
                    }
                }
                
                this.generateFunkoAvatar();
            });
        });

        // Random Funko button
        const randomBtn = document.getElementById('random-funko-btn');
        if (randomBtn) {
            randomBtn.addEventListener('click', () => {
                this.generateRandomFunko();
            });
        }

        // Generate collection button
        const collectionBtn = document.getElementById('generate-collection-btn');
        if (collectionBtn) {
            collectionBtn.addEventListener('click', () => {
                this.generateFunkoCollection();
            });
        }
    }

    generateFunkoAvatar() {
        const funkoContainer = document.getElementById('custom-funko');
        if (!funkoContainer) return;

        // Show loading state
        const loadingSpinner = document.getElementById('loading-spinner');
        if (loadingSpinner) loadingSpinner.classList.remove('hidden');

        // Generate SVG Funko Pop
        const funkoSVG = this.createFunkoSVG();
        
        // Simulate brief loading time for smooth UX
        setTimeout(() => {
            funkoContainer.innerHTML = funkoSVG;
            this.updateFunkoDisplay();
            if (loadingSpinner) loadingSpinner.classList.add('hidden');
        }, 300);
    }

    createFunkoSVG() {
        const config = this.currentConfig;
        const skinColor = this.funkoPalette.skin.medium;
        const hairColor = this.funkoPalette.hair[config.hairColor] || this.funkoPalette.hair.brown;
        const outfitColor = this.funkoPalette.outfit[config.outfitColor] || this.funkoPalette.outfit.blue;

        return `
            <svg viewBox="0 0 256 320" xmlns="http://www.w3.org/2000/svg" class="w-full h-full">
                <!-- Funko Pop Body Base -->
                <defs>
                    <linearGradient id="bodyGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#f8f9fa;stop-opacity:1" />
                        <stop offset="100%" style="stop-color:#e9ecef;stop-opacity:1" />
                    </linearGradient>
                    <linearGradient id="shadowGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#000000;stop-opacity:0.1" />
                        <stop offset="100%" style="stop-color:#000000;stop-opacity:0.3" />
                    </linearGradient>
                    <filter id="funkoGlow" x="-50%" y="-50%" width="200%" height="200%">
                        <feMorphology operator="dilate" radius="2"/>
                        <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
                        <feMerge> 
                            <feMergeNode in="coloredBlur"/>
                            <feMergeNode in="SourceGraphic"/> 
                        </feMerge>
                    </filter>
                </defs>
                
                <!-- Base Shadow -->
                <ellipse cx="128" cy="310" rx="50" ry="8" fill="url(#shadowGradient)" opacity="0.3"/>
                
                <!-- Body (Funko Pop characteristic rectangular body) -->
                <rect x="80" y="160" width="96" height="120" rx="8" ry="8" fill="${outfitColor}" stroke="#333" stroke-width="2"/>
                <rect x="85" y="165" width="86" height="110" rx="6" ry="6" fill="${outfitColor}" opacity="0.9"/>
                
                ${this.generateOutfitDetails(config.outfitType, outfitColor)}
                
                <!-- Arms -->
                <rect x="60" y="170" width="25" height="60" rx="12" ry="12" fill="${outfitColor}" stroke="#333" stroke-width="2"/>
                <rect x="171" y="170" width="25" height="60" rx="12" ry="12" fill="${outfitColor}" stroke="#333" stroke-width="2"/>
                
                <!-- Hands -->
                <circle cx="72" cy="240" r="12" fill="${skinColor}" stroke="#333" stroke-width="2"/>
                <circle cx="184" cy="240" r="12" fill="${skinColor}" stroke="#333" stroke-width="2"/>
                
                <!-- Legs -->
                <rect x="95" y="275" width="20" height="35" rx="10" ry="10" fill="#333" stroke="#333" stroke-width="2"/>
                <rect x="141" y="275" width="20" height="35" rx="10" ry="10" fill="#333" stroke="#333" stroke-width="2"/>
                
                <!-- Feet -->
                <ellipse cx="105" cy="315" rx="15" ry="8" fill="#000" stroke="#333" stroke-width="2"/>
                <ellipse cx="151" cy="315" rx="15" ry="8" fill="#000" stroke="#333" stroke-width="2"/>
                
                <!-- Head (Oversized Funko Pop head) -->
                <circle cx="128" cy="100" r="60" fill="${skinColor}" stroke="#333" stroke-width="3"/>
                <circle cx="128" cy="95" r="55" fill="${skinColor}" opacity="0.95"/>
                
                ${this.generateHairStyle(config.hairStyle, hairColor)}
                
                <!-- Eyes (Large Funko Pop eyes) -->
                <circle cx="110" cy="85" r="12" fill="#000"/>
                <circle cx="146" cy="85" r="12" fill="#000"/>
                <circle cx="112" cy="82" r="4" fill="#fff"/>
                <circle cx="148" cy="82" r="4" fill="#fff"/>
                
                <!-- Nose -->
                <ellipse cx="128" cy="105" rx="3" ry="2" fill="#dbb5a8"/>
                
                <!-- Mouth -->
                <path d="M 118 118 Q 128 125 138 118" stroke="#333" stroke-width="2" fill="none"/>
                
                ${this.generateAccessories(config.accessories)}
                
                <!-- Funko Pop Shine/Reflection -->
                <ellipse cx="115" cy="70" rx="15" ry="20" fill="#fff" opacity="0.3"/>
                <ellipse cx="105" cy="150" rx="8" ry="12" fill="#fff" opacity="0.2"/>
            </svg>
        `;
    }

    generateHairStyle(hairStyle, hairColor) {
        switch (hairStyle) {
            case 'short':
                return `
                    <path d="M 80 60 Q 128 30 176 60 Q 176 45 128 35 Q 80 45 80 60 Z" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <ellipse cx="128" cy="45" rx="40" ry="15" fill="${hairColor}" opacity="0.8"/>
                `;
            case 'long':
                return `
                    <path d="M 75 55 Q 128 25 181 55 Q 185 70 181 85 L 178 120 Q 170 125 128 125 Q 86 125 78 120 L 75 85 Q 71 70 75 55 Z" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <ellipse cx="128" cy="40" rx="45" ry="18" fill="${hairColor}" opacity="0.9"/>
                `;
            case 'curly':
                return `
                    <circle cx="100" cy="50" r="15" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <circle cx="128" cy="40" r="18" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <circle cx="156" cy="50" r="15" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <circle cx="115" cy="35" r="12" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <circle cx="141" cy="35" r="12" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                `;
            case 'spiky':
                return `
                    <polygon points="128,25 135,45 125,40 130,45 120,40 125,45 115,40 120,45 110,40 115,45 105,40 110,45 100,45 95,40 90,50 85,45 80,55 85,60 128,35" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <polygon points="128,25 135,45 140,40 145,45 150,40 155,45 160,40 165,45 170,40 175,50 180,45 175,55 170,60 128,35" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                `;
            case 'bald':
                return `<!-- No hair -->`; 
            case 'ponytail':
                return `
                    <path d="M 80 60 Q 128 30 176 60 Q 176 45 128 35 Q 80 45 80 60 Z" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <ellipse cx="185" cy="80" rx="8" ry="25" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                `;
            case 'mohawk':
                return `
                    <rect x="125" y="20" width="6" height="40" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <polygon points="128,15 140,30 128,25 116,30" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                    <polygon points="128,20 138,35 128,30 118,35" fill="${hairColor}" stroke="#333" stroke-width="2"/>
                `;
            default:
                return this.generateHairStyle('short', hairColor);
        }
    }

    generateOutfitDetails(outfitType, outfitColor) {
        switch (outfitType) {
            case 'superhero':
                return `
                    <rect x="85" y="165" width="86" height="110" rx="6" ry="6" fill="${outfitColor}"/>
                    <polygon points="128,165 138,185 128,205 118,185" fill="#FFD700" stroke="#333" stroke-width="2"/>
                    <rect x="120" y="190" width="16" height="40" fill="#FFD700"/>
                `;
            case 'business':
                return `
                    <rect x="85" y="165" width="86" height="110" rx="6" ry="6" fill="${outfitColor}"/>
                    <rect x="100" y="170" width="56" height="80" fill="#FFFFFF" stroke="#333" stroke-width="1"/>
                    <rect x="125" y="175" width="6" height="70" fill="#FF0000"/>
                    <circle cx="110" cy="185" r="3" fill="#333"/>
                    <circle cx="110" cy="200" r="3" fill="#333"/>
                    <circle cx="110" cy="215" r="3" fill="#333"/>
                `;
            case 'fantasy':
                return `
                    <rect x="85" y="165" width="86" height="110" rx="6" ry="6" fill="${outfitColor}"/>
                    <polygon points="85,240 100,220 156,220 171,240 171,275 85,275" fill="#8B4513"/>
                    <circle cx="128" cy="200" r="8" fill="#FFD700" stroke="#333" stroke-width="2"/>
                `;
            default:
                return `<rect x="85" y="165" width="86" height="110" rx="6" ry="6" fill="${outfitColor}"/>`;
        }
    }

    generateAccessories(accessories) {
        let accessorySVG = '';
        
        accessories.forEach(accessory => {
            switch (accessory) {
                case 'glasses':
                    accessorySVG += `
                        <circle cx="110" cy="85" r="18" fill="none" stroke="#333" stroke-width="3"/>
                        <circle cx="146" cy="85" r="18" fill="none" stroke="#333" stroke-width="3"/>
                        <line x1="128" y1="85" x2="128" y2="85" stroke="#333" stroke-width="3"/>
                    `;
                    break;
                case 'hat':
                    accessorySVG += `
                        <ellipse cx="128" cy="35" rx="50" ry="15" fill="#333" stroke="#333" stroke-width="2"/>
                        <ellipse cx="128" cy="25" rx="25" ry="20" fill="#333" stroke="#333" stroke-width="2"/>
                    `;
                    break;
                case 'headphones':
                    accessorySVG += `
                        <path d="M 85 70 Q 85 50 128 50 Q 171 50 171 70" stroke="#333" stroke-width="6" fill="none"/>
                        <circle cx="85" cy="75" r="12" fill="#333"/>
                        <circle cx="171" cy="75" r="12" fill="#333"/>
                    `;
                    break;
            }
        });
        
        return accessorySVG;
    }

    updateFunkoDisplay() {
        const nameEl = document.getElementById('funko-name');
        const styleEl = document.getElementById('current-style');
        const characterEl = document.getElementById('current-character');

        if (nameEl) nameEl.textContent = this.currentConfig.characterName;
        if (styleEl) styleEl.textContent = `${this.currentConfig.characterType} - ${this.currentConfig.outfitType}`;
        if (characterEl) characterEl.textContent = `${this.currentConfig.hairStyle} ${this.currentConfig.hairColor} hair`;
    }

    generateRandomFunko() {
        const characterTypes = ['human', 'superhero', 'fantasy', 'robot'];
        const hairStyles = ['short', 'long', 'curly', 'spiky', 'bald', 'ponytail', 'mohawk'];
        const hairColors = ['blonde', 'brown', 'black', 'red', 'gray', 'pink', 'blue', 'green'];
        const outfitTypes = ['casual', 'business', 'superhero', 'fantasy', 'sports', 'formal', 'steampunk'];
        const outfitColors = ['red', 'blue', 'green', 'yellow', 'purple', 'pink', 'black', 'white'];
        const allAccessories = ['glasses', 'hat', 'headphones', 'sword', 'book', 'phone'];

        this.currentConfig.characterType = characterTypes[Math.floor(Math.random() * characterTypes.length)];
        this.currentConfig.hairStyle = hairStyles[Math.floor(Math.random() * hairStyles.length)];
        this.currentConfig.hairColor = hairColors[Math.floor(Math.random() * hairColors.length)];
        this.currentConfig.outfitType = outfitTypes[Math.floor(Math.random() * outfitTypes.length)];
        this.currentConfig.outfitColor = outfitColors[Math.floor(Math.random() * outfitColors.length)];
        
        // Random accessories (0-2 accessories)
        this.currentConfig.accessories = [];
        const numAccessories = Math.floor(Math.random() * 3);
        for (let i = 0; i < numAccessories; i++) {
            const accessory = allAccessories[Math.floor(Math.random() * allAccessories.length)];
            if (!this.currentConfig.accessories.includes(accessory)) {
                this.currentConfig.accessories.push(accessory);
            }
        }

        // Update UI to reflect random choices
        this.updateUIFromConfig();
        this.generateFunkoAvatar();
    }

    updateUIFromConfig() {
        // Update character type buttons
        document.querySelectorAll('.character-type-btn').forEach(btn => {
            btn.classList.remove('bg-white/30', 'border-yellow-400');
            btn.classList.add('bg-white/10', 'border-white/30');
            
            if (btn.getAttribute('data-type') === this.currentConfig.characterType) {
                btn.classList.remove('bg-white/10', 'border-white/30');
                btn.classList.add('bg-white/30', 'border-yellow-400');
            }
        });

        // Update dropdowns
        const hairStyleSelect = document.getElementById('hair-style');
        if (hairStyleSelect) hairStyleSelect.value = this.currentConfig.hairStyle;

        const outfitTypeSelect = document.getElementById('outfit-type');
        if (outfitTypeSelect) outfitTypeSelect.value = this.currentConfig.outfitType;

        // Update color buttons
        document.querySelectorAll('.hair-color-btn').forEach(btn => {
            btn.classList.remove('ring-4', 'ring-white');
            if (btn.getAttribute('data-color') === this.currentConfig.hairColor) {
                btn.classList.add('ring-4', 'ring-white');
            }
        });

        document.querySelectorAll('.outfit-color-btn').forEach(btn => {
            btn.classList.remove('ring-4', 'ring-white');
            if (btn.getAttribute('data-color') === this.currentConfig.outfitColor) {
                btn.classList.add('ring-4', 'ring-white');
            }
        });

        // Update accessory buttons
        document.querySelectorAll('.accessory-btn').forEach(btn => {
            const accessory = btn.getAttribute('data-accessory');
            if (this.currentConfig.accessories.includes(accessory)) {
                btn.classList.remove('bg-white/10', 'text-white');
                btn.classList.add('bg-yellow-400', 'text-gray-900');
            } else {
                btn.classList.remove('bg-yellow-400', 'text-gray-900');
                btn.classList.add('bg-white/10', 'text-white');
            }
        });
    }

    generateFunkoCollection() {
        const collectionBtn = document.getElementById('generate-collection-btn');
        const previewSection = document.getElementById('collection-preview');
        const grid = document.getElementById('collection-grid');
        const countSpan = document.getElementById('collection-count');

        if (!grid || !previewSection) return;

        // Update button state
        collectionBtn.disabled = true;
        collectionBtn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Creating Collection...';

        // Generate multiple Funko variants
        const funkos = [];
        
        // Create emotional variations
        const emotions = ['Happy', 'Sad', 'Excited', 'Surprised', 'Thinking', 'Cool'];
        emotions.forEach(emotion => {
            const config = { ...this.currentConfig };
            config.characterName = `${emotion} ${config.characterName}`;
            funkos.push({ config, category: 'emotion' });
        });

        // Create family variations
        const familyMembers = [
            { name: 'Mom', hairStyle: 'long', outfitType: 'casual', outfitColor: 'pink' },
            { name: 'Dad', hairStyle: 'short', outfitType: 'business', outfitColor: 'blue' },
            { name: 'Sister', hairStyle: 'ponytail', outfitType: 'casual', outfitColor: 'purple' },
            { name: 'Brother', hairStyle: 'spiky', outfitType: 'sports', outfitColor: 'green' },
            { name: 'Grandma', hairStyle: 'short', hairColor: 'gray', outfitType: 'formal', outfitColor: 'black' },
            { name: 'Grandpa', hairStyle: 'bald', outfitType: 'casual', outfitColor: 'brown' }
        ];

        familyMembers.forEach(member => {
            const config = { ...this.currentConfig, ...member };
            config.characterName = member.name;
            funkos.push({ config, category: 'family' });
        });

        // Clear existing grid
        grid.innerHTML = '';

        // Generate and display each Funko
        funkos.forEach((funko, index) => {
            const funkoDiv = document.createElement('div');
            funkoDiv.className = 'bg-white/10 rounded-lg p-4 text-center hover:bg-white/20 transition-all cursor-pointer border border-white/20';
            
            // Create mini Funko SVG
            const oldConfig = { ...this.currentConfig };
            this.currentConfig = funko.config;
            const miniFunkoSVG = this.createFunkoSVG();
            this.currentConfig = oldConfig;

            const categoryColor = funko.category === 'emotion' ? 'bg-yellow-400 text-gray-900' : 'bg-purple-400 text-white';

            funkoDiv.innerHTML = `
                <div class="w-20 h-24 mx-auto mb-3">
                    ${miniFunkoSVG}
                </div>
                <p class="text-white text-sm font-semibold mb-2">${funko.config.characterName}</p>
                <span class="inline-block ${categoryColor} text-xs px-2 py-1 rounded-full">${funko.category}</span>
            `;

            // Click to preview
            funkoDiv.addEventListener('click', () => {
                this.currentConfig = { ...funko.config };
                this.updateUIFromConfig();
                this.generateFunkoAvatar();
            });

            grid.appendChild(funkoDiv);
        });

        // Update count and show section
        countSpan.textContent = `${funkos.length} characters`;
        previewSection.classList.remove('hidden');

        // Reset button
        collectionBtn.disabled = false;
        collectionBtn.innerHTML = '<i class="fas fa-collection mr-2"></i>Create Collection';

        console.log(`Generated ${funkos.length} Funko Pop characters!`);
    }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded, initializing Funko Pop Avatar Creator...');
    window.funkoCreator = new FunkoAvatarCreator();
});