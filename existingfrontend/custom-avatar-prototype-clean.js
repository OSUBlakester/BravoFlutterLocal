// Custom AAC Avatar System - Professional Quality Full-Body Avatars
// Avataaars-quality SVG generation with full-body support

console.log('Custom Avatar System - Professional version loaded!');

class CustomAvatarSystem {
    constructor() {
        console.log('CustomAvatarSystem constructor called!');
        this.debugElement = document.createElement('div');
        this.debugElement.id = 'debugOutput';
        this.debugElement.style.cssText = 'position: fixed; top: 10px; right: 10px; background: black; color: white; padding: 10px; font-family: monospace; font-size: 12px; z-index: 9999; max-width: 300px; max-height: 200px; overflow: auto;';
        document.body.appendChild(this.debugElement);
        this.debug('CustomAvatarSystem constructor called!');
        
        this.currentConfig = {
            skinTone: 'light',
            hairStyle: 'short',
            hairColor: 'brown',
            gender: 'neutral',
            clothing: 'casual',
            textOverlay: ''
        };

        this.skinTones = {
            light: '#FDBCB4',
            medium: '#E8B982',
            tan: '#D08B5B',
            dark: '#A0522D'
        };

        this.hairColors = {
            brown: '#8B4513',
            black: '#2F1B14',
            blonde: '#FAD5A5',
            red: '#CD853F',
            gray: '#808080'
        };

        this.init();
    }

    debug(message) {
        console.log(message);
        if (this.debugElement) {
            this.debugElement.innerHTML += message + '<br>';
            this.debugElement.scrollTop = this.debugElement.scrollHeight;
        }
    }

    init() {
        this.debug('Initializing avatar system...');
        this.setupEventListeners();
        this.debug('Avatar system initialized!');
    }

    setupEventListeners() {
        // Form inputs for real-time updates
        const formElements = ['skinTone', 'hairStyle', 'hairColor', 'gender', 'clothing'];
        formElements.forEach(elementId => {
            const element = document.getElementById(elementId);
            if (element) {
                element.addEventListener('change', (e) => {
                    this.currentConfig[elementId] = e.target.value;
                    this.generateAvatar();
                });
            }
        });

        const textOverlay = document.getElementById('textOverlay');
        if (textOverlay) {
            textOverlay.addEventListener('input', (e) => {
                this.currentConfig.textOverlay = e.target.value;
                this.generateAvatar();
            });
        }

        // Buttons
        this.debug('Setting up button event listeners...');
        const generateBtn = document.getElementById('generateBtn');
        const randomBtn = document.getElementById('randomBtn');
        const generateVariationsBtn = document.getElementById('generateVariationsBtn');
        
        this.debug('generateBtn found: ' + (generateBtn ? 'yes' : 'no'));
        this.debug('randomBtn found: ' + (randomBtn ? 'yes' : 'no'));
        this.debug('generateVariationsBtn found: ' + (generateVariationsBtn ? 'yes' : 'no'));
        
        document.getElementById('generateBtn')?.addEventListener('click', () => this.generateAvatar());
        document.getElementById('randomBtn')?.addEventListener('click', () => this.generateRandom());
        document.getElementById('generateVariationsBtn')?.addEventListener('click', () => this.generateAACVariations());
        
        // Test event listener
        document.getElementById('generateBtn')?.addEventListener('click', () => {
            console.log('Generate button clicked! (test listener)');
            this.debug('Generate button clicked! (test listener)');
        });
    }

    generateAvatar(config = null) {
        this.debug('generateAvatar called with config: ' + JSON.stringify(config));
        const selectedConfig = config || this.getSelectedConfig();
        this.debug('selectedConfig: ' + JSON.stringify(selectedConfig));
        
        try {
            this.debug('Creating SVG...');
            const svgHTML = this.createAvatarSVG(selectedConfig);
            this.debug('SVG created, length: ' + svgHTML.length);
            
            const avatarDisplay = document.getElementById('avatarDisplay');
            this.debug('avatarDisplay element: ' + (avatarDisplay ? 'found' : 'not found'));
            
            if (avatarDisplay) {
                // Add some styling to make sure the SVG is visible
                avatarDisplay.style.cssText = 'width: 100%; height: 400px; border: 1px solid red; background: white;';
                
                this.debug('Setting innerHTML...');
                avatarDisplay.innerHTML = svgHTML;
                this.debug('Avatar display updated');
                
                // Debug: show what's actually in the div
                this.debug('avatarDisplay.innerHTML length: ' + avatarDisplay.innerHTML.length);
                this.debug('First 200 chars: ' + avatarDisplay.innerHTML.substring(0, 200));
            } else {
                this.debug('ERROR: avatarDisplay element not found!');
            }
        } catch (error) {
            this.debug('ERROR: ' + error.message);
        }
    }

    getSelectedConfig() {
        const config = {
            skinTone: document.getElementById('skinTone')?.value || 'light',
            hairStyle: document.getElementById('hairStyle')?.value || 'short',
            hairColor: document.getElementById('hairColor')?.value || 'brown',
            gender: document.getElementById('gender')?.value || 'neutral',
            clothing: document.getElementById('clothing')?.value || 'casual',
            textOverlay: document.getElementById('textOverlay')?.value || ''
        };
        
        this.debug('getSelectedConfig returning: ' + JSON.stringify(config));
        return config;
    }

    createAvatarSVG(config) {
        const skinColor = this.skinTones[config.skinTone];
        const hairColor = this.hairColors[config.hairColor];
        
        return `
            <svg viewBox="0 0 280 400" xmlns="http://www.w3.org/2000/svg" style="width: 100%; height: 400px;">
                <defs>
                    <!-- Professional gradients for depth -->
                    <linearGradient id="skinGradient" x1="30%" y1="0%" x2="70%" y2="100%">
                        <stop offset="0%" stop-color="${this.lightenColor(skinColor, 0.15)}" />
                        <stop offset="50%" stop-color="${skinColor}" />
                        <stop offset="100%" stop-color="${this.darkenColor(skinColor, 0.1)}" />
                    </linearGradient>
                    <linearGradient id="hairGradient" x1="30%" y1="0%" x2="70%" y2="100%">
                        <stop offset="0%" stop-color="${this.lightenColor(hairColor, 0.2)}" />
                        <stop offset="100%" stop-color="${this.darkenColor(hairColor, 0.1)}" />
                    </linearGradient>
                    <filter id="softShadow" x="-20%" y="-20%" width="140%" height="140%">
                        <feDropShadow dx="2" dy="3" stdDeviation="3" flood-opacity="0.2" flood-color="#000000" />
                    </filter>
                    <radialGradient id="faceShading" cx="50%" cy="40%" r="60%">
                        <stop offset="0%" stop-color="${this.lightenColor(skinColor, 0.1)}" />
                        <stop offset="100%" stop-color="${skinColor}" />
                    </radialGradient>
                </defs>
                
                <!-- Professional Full Body -->
                ${this.generateProfessionalFullBody(config, skinColor)}
                
                <!-- Professional Head with proper proportions -->
                ${this.generateProfessionalHead(config, skinColor)}
                
                <!-- Professional Hair -->
                ${this.generateProfessionalHair(config, hairColor)}
                
                <!-- Professional Face Features -->
                ${this.generateProfessionalFace(config)}
                
                <!-- Professional Clothing -->
                ${this.generateProfessionalClothing(config)}
                
                <!-- Text overlay if present -->
                ${config.textOverlay ? this.generateTextOverlay(config.textOverlay) : ''}
            </svg>
        `;
    }

    lightenColor(color, amount) {
        const hex = color.replace('#', '');
        const r = Math.min(255, parseInt(hex.substr(0, 2), 16) + Math.round(255 * amount));
        const g = Math.min(255, parseInt(hex.substr(2, 2), 16) + Math.round(255 * amount));
        const b = Math.min(255, parseInt(hex.substr(4, 2), 16) + Math.round(255 * amount));
        return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }

    darkenColor(color, amount) {
        const hex = color.replace('#', '');
        const r = Math.max(0, parseInt(hex.substr(0, 2), 16) - Math.round(255 * amount));
        const g = Math.max(0, parseInt(hex.substr(2, 2), 16) - Math.round(255 * amount));
        const b = Math.max(0, parseInt(hex.substr(4, 2), 16) - Math.round(255 * amount));
        return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }

    generateProfessionalFullBody(config, skinColor) {
        const ismasculine = config.gender === 'masculine';
        const isfeminine = config.gender === 'feminine';
        
        // Body dimensions based on gender
        const shoulderWidth = ismasculine ? 85 : isfeminine ? 75 : 80;
        const waistWidth = ismasculine ? 75 : isfeminine ? 65 : 70;
        const hipWidth = ismasculine ? 75 : isfeminine ? 85 : 80;
        
        return `
            <g id="fullBody" filter="url(#softShadow)">
                <!-- Torso with professional curves -->
                <path d="M${140 - shoulderWidth/2},150 
                         Q${140 - shoulderWidth/2},140 ${140 - shoulderWidth/4},140
                         Q140,135 ${140 + shoulderWidth/4},140
                         Q${140 + shoulderWidth/2},140 ${140 + shoulderWidth/2},150
                         L${140 + waistWidth/2},200
                         Q${140 + waistWidth/2},210 ${140 + hipWidth/2},220
                         L${140 + hipWidth/2},260
                         Q${140 + hipWidth/2},270 ${140 + hipWidth/4},270
                         L${140 - hipWidth/4},270
                         Q${140 - hipWidth/2},270 ${140 - hipWidth/2},260
                         L${140 - hipWidth/2},220
                         Q${140 - waistWidth/2},210 ${140 - waistWidth/2},200
                         Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
                
                <!-- Arms with natural curves -->
                <path d="M${140 - shoulderWidth/2 + 5},155
                         Q${140 - shoulderWidth/2 - 15},160 ${140 - shoulderWidth/2 - 20},180
                         Q${140 - shoulderWidth/2 - 25},200 ${140 - shoulderWidth/2 - 20},220
                         L${140 - shoulderWidth/2 - 15},235
                         Q${140 - shoulderWidth/2 - 10},240 ${140 - shoulderWidth/2 - 5},235
                         L${140 - shoulderWidth/2},220
                         Q${140 - shoulderWidth/2 + 5},200 ${140 - shoulderWidth/2 + 10},180
                         Q${140 - shoulderWidth/2 + 5},160 ${140 - shoulderWidth/2 + 5},155
                         Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
                
                <path d="M${140 + shoulderWidth/2 - 5},155
                         Q${140 + shoulderWidth/2 + 15},160 ${140 + shoulderWidth/2 + 20},180
                         Q${140 + shoulderWidth/2 + 25},200 ${140 + shoulderWidth/2 + 20},220
                         L${140 + shoulderWidth/2 + 15},235
                         Q${140 + shoulderWidth/2 + 10},240 ${140 + shoulderWidth/2 + 5},235
                         L${140 + shoulderWidth/2},220
                         Q${140 + shoulderWidth/2 - 5},200 ${140 + shoulderWidth/2 - 10},180
                         Q${140 + shoulderWidth/2 - 5},160 ${140 + shoulderWidth/2 - 5},155
                         Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
                
                <!-- Hands -->
                <circle cx="${140 - shoulderWidth/2 - 17}" cy="235" r="8" 
                        fill="url(#skinGradient)" 
                        stroke="rgba(0,0,0,0.1)" 
                        stroke-width="0.5"/>
                <circle cx="${140 + shoulderWidth/2 + 17}" cy="235" r="8" 
                        fill="url(#skinGradient)" 
                        stroke="rgba(0,0,0,0.1)" 
                        stroke-width="0.5"/>
                
                <!-- Legs with natural proportions -->
                <path d="M${140 - hipWidth/4},270
                         Q${140 - hipWidth/4 - 5},280 ${140 - hipWidth/4 - 8},320
                         Q${140 - hipWidth/4 - 10},360 ${140 - hipWidth/4 - 8},380
                         L${140 - hipWidth/4 + 2},385
                         Q${140 - hipWidth/4 + 8},385 ${140 - hipWidth/4 + 8},380
                         Q${140 - hipWidth/4 + 10},360 ${140 - hipWidth/4 + 8},320
                         Q${140 - hipWidth/4 + 5},280 ${140 - hipWidth/4},270
                         Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
                
                <path d="M${140 + hipWidth/4},270
                         Q${140 + hipWidth/4 + 5},280 ${140 + hipWidth/4 + 8},320
                         Q${140 + hipWidth/4 + 10},360 ${140 + hipWidth/4 + 8},380
                         L${140 + hipWidth/4 - 2},385
                         Q${140 + hipWidth/4 - 8},385 ${140 + hipWidth/4 - 8},380
                         Q${140 + hipWidth/4 - 10},360 ${140 + hipWidth/4 - 8},320
                         Q${140 + hipWidth/4 - 5},280 ${140 + hipWidth/4},270
                         Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
                
                <!-- Feet -->
                <ellipse cx="${140 - hipWidth/4}" cy="388" rx="12" ry="6" 
                         fill="url(#skinGradient)" 
                         stroke="rgba(0,0,0,0.1)" 
                         stroke-width="0.5"/>
                <ellipse cx="${140 + hipWidth/4}" cy="388" rx="12" ry="6" 
                         fill="url(#skinGradient)" 
                         stroke="rgba(0,0,0,0.1)" 
                         stroke-width="0.5"/>
            </g>
        `;
    }

    generateProfessionalHead(config, skinColor) {
        return `
            <g id="head">
                <!-- Professional head shape with subtle shadows -->
                <ellipse cx="140" cy="90" rx="50" ry="55" 
                         fill="url(#faceShading)" 
                         stroke="rgba(0,0,0,0.08)" 
                         stroke-width="0.5"
                         filter="url(#softShadow)"/>
                
                <!-- Neck -->
                <path d="M125,135 Q140,140 155,135 L155,150 Q140,155 125,150 Z" 
                      fill="url(#skinGradient)" 
                      stroke="rgba(0,0,0,0.05)" 
                      stroke-width="0.5"/>
            </g>
        `;
    }

    generateProfessionalHair(config, hairColor) {
        const hairStyles = {
            'short': `
                <path d="M90,70 Q95,45 140,40 Q185,45 190,70 Q190,85 185,95 Q175,100 165,95 Q155,90 140,90 Q125,90 115,95 Q105,100 95,95 Q90,85 90,70 Z" 
                      fill="url(#hairGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
            `,
            'medium': `
                <path d="M85,65 Q90,35 140,30 Q190,35 195,65 Q195,90 190,105 Q185,120 175,125 Q165,115 155,110 Q145,105 140,105 Q135,105 125,110 Q115,115 105,125 Q95,120 90,105 Q85,90 85,65 Z" 
                      fill="url(#hairGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
            `,
            'long': `
                <path d="M80,60 Q85,25 140,20 Q195,25 200,60 Q200,95 195,125 Q190,155 185,170 Q175,175 165,170 Q155,165 145,160 Q140,158 140,160 Q135,158 135,160 Q125,165 115,170 Q105,175 95,170 Q90,155 85,125 Q80,95 80,60 Z" 
                      fill="url(#hairGradient)" 
                      stroke="rgba(0,0,0,0.1)" 
                      stroke-width="0.5"/>
            `,
            'curly': `
                <g>
                    <circle cx="110" cy="55" r="18" fill="url(#hairGradient)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                    <circle cx="140" cy="45" r="22" fill="url(#hairGradient)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                    <circle cx="170" cy="55" r="18" fill="url(#hairGradient)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                    <circle cx="100" cy="80" r="15" fill="url(#hairGradient)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                    <circle cx="180" cy="80" r="15" fill="url(#hairGradient)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                </g>
            `
        };
        
        return `
            <g id="hair">
                ${hairStyles[config.hairStyle] || hairStyles['short']}
            </g>
        `;
    }

    generateProfessionalFace(config) {
        return `
            <g id="face">
                <!-- Eyes with depth -->
                <ellipse cx="120" cy="80" rx="8" ry="6" fill="white" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>
                <ellipse cx="160" cy="80" rx="8" ry="6" fill="white" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>
                <circle cx="122" cy="80" r="4" fill="#2C3E50"/>
                <circle cx="158" cy="80" r="4" fill="#2C3E50"/>
                <circle cx="123" cy="79" r="1.5" fill="white"/>
                <circle cx="159" cy="79" r="1.5" fill="white"/>
                
                <!-- Eyebrows -->
                <path d="M112,70 Q120,68 128,70" fill="none" stroke="rgba(0,0,0,0.6)" stroke-width="2" stroke-linecap="round"/>
                <path d="M152,70 Q160,68 168,70" fill="none" stroke="rgba(0,0,0,0.6)" stroke-width="2" stroke-linecap="round"/>
                
                <!-- Nose with subtle shading -->
                <path d="M140,85 Q142,95 140,100 Q138,95 140,85" fill="rgba(0,0,0,0.1)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>
                
                <!-- Professional mouth -->
                <path d="M128,110 Q140,118 152,110" fill="none" stroke="rgba(220,100,100,0.8)" stroke-width="2.5" stroke-linecap="round"/>
                <path d="M130,112 Q140,116 150,112" fill="rgba(220,100,100,0.3)"/>
            </g>
        `;
    }

    generateProfessionalClothing(config) {
        const clothingStyles = {
            'casual': `
                <path d="M${140-40},150 Q${140-45},145 ${140-30},145 Q140,140 ${140+30},145 Q${140+45},145 ${140+40},150 
                         L${140+35},200 Q${140+35},210 ${140+30},220 L${140+25},260 Q${140+25},270 ${140+20},270
                         L${140-20},270 Q${140-25},270 ${140-25},260 L${140-30},220 Q${140-35},210 ${140-35},200 Z" 
                      fill="#4A90E2" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
            `,
            'formal': `
                <path d="M${140-42},150 Q${140-47},145 ${140-32},145 Q140,140 ${140+32},145 Q${140+47},145 ${140+42},150 
                         L${140+37},200 Q${140+37},210 ${140+32},220 L${140+27},260 Q${140+27},270 ${140+22},270
                         L${140-22},270 Q${140-27},270 ${140-27},260 L${140-32},220 Q${140-37},210 ${140-37},200 Z" 
                      fill="#2C3E50" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
                <!-- Tie -->
                <path d="M140,150 L140,200 Q142,210 140,220 Q138,210 140,150 Z" fill="#E74C3C"/>
            `,
            'sports': `
                <path d="M${140-38},150 Q${140-43},145 ${140-28},145 Q140,140 ${140+28},145 Q${140+43},145 ${140+38},150 
                         L${140+33},200 Q${140+33},210 ${140+28},220 L${140+23},260 Q${140+23},270 ${140+18},270
                         L${140-18},270 Q${140-23},270 ${140-23},260 L${140-28},220 Q${140-33},210 ${140-33},200 Z" 
                      fill="#27AE60" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
            `,
            'dress': `
                <path d="M${140-40},150 Q${140-45},145 ${140-30},145 Q140,140 ${140+30},145 Q${140+45},145 ${140+40},150 
                         L${140+45},200 Q${140+50},220 ${140+55},240 Q${140+60},260 ${140+55},270
                         L${140-55},270 Q${140-60},260 ${140-55},240 Q${140-50},220 ${140-45},200 Z" 
                      fill="#E91E63" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>
            `
        };
        
        return `
            <g id="clothing">
                ${clothingStyles[config.clothing] || clothingStyles['casual']}
            </g>
        `;
    }

    generateTextOverlay(text) {
        return `
            <g id="textOverlay">
                <rect x="90" y="300" width="100" height="30" rx="15" 
                      fill="rgba(255,255,255,0.9)" 
                      stroke="rgba(0,0,0,0.2)" 
                      stroke-width="1"/>
                <text x="140" y="320" text-anchor="middle" 
                      font-family="Arial, sans-serif" 
                      font-size="16" 
                      font-weight="bold" 
                      fill="#2C3E50">${text}</text>
            </g>
        `;
    }

    generateRandom() {
        const skinTones = Object.keys(this.skinTones);
        const hairStyles = ['short', 'medium', 'long', 'curly'];
        const hairColors = Object.keys(this.hairColors);
        const genders = ['neutral', 'masculine', 'feminine'];
        const clothingTypes = ['casual', 'formal', 'sports', 'dress'];
        
        const randomConfig = {
            skinTone: skinTones[Math.floor(Math.random() * skinTones.length)],
            hairStyle: hairStyles[Math.floor(Math.random() * hairStyles.length)],
            hairColor: hairColors[Math.floor(Math.random() * hairColors.length)],
            gender: genders[Math.floor(Math.random() * genders.length)],
            clothing: clothingTypes[Math.floor(Math.random() * clothingTypes.length)],
            textOverlay: ''
        };
        
        this.generateAvatar(randomConfig);
        this.updateFormFields(randomConfig);
    }
    
    updateFormFields(config) {
        Object.keys(config).forEach(key => {
            const element = document.getElementById(key);
            if (element) {
                element.value = config[key];
            }
        });
    }

    generateAACVariations() {
        alert('AAC Variations feature coming soon! This will generate emotional expressions, body part highlights, and action poses.');
    }
}

// Initialize the system when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM Content Loaded - initializing CustomAvatarSystem');
    const avatarSystem = new CustomAvatarSystem();
    console.log('CustomAvatarSystem initialized:', avatarSystem);
});