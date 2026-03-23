/**
 * Modular Avatar Creator - Professional Quality Component System
 * Inspired by Vue Color Avatar and Multiavatar architectures
 * Optimized for AAC communication with emotional variations
 */

class ModularAvatarCreator {
    constructor() {
        this.currentAvatar = {
            face: { shape: 'oval', skinTone: '#fdd8b5' },
            hair: { style: 'short', color: '#8B4513' },
            eyes: { style: 'normal', color: '#654321' },
            nose: { style: 'medium' },
            mouth: { style: 'neutral', emotion: 'neutral' },
            glasses: { style: 'none' },
            accessories: { style: 'none' },
            clothing: { style: 'casual', color: '#4A90E2' }
        };
        
        this.components = this.initializeComponents();
        this.emotions = this.initializeEmotions();
        this.init();
    }

    initializeComponents() {
        return {
            faceShapes: {
                oval: {
                    name: 'Oval',
                    svg: '<ellipse cx="150" cy="130" rx="75" ry="85" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                },
                round: {
                    name: 'Round',
                    svg: '<circle cx="150" cy="130" r="80" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                },
                square: {
                    name: 'Square',
                    svg: '<rect x="75" y="50" width="150" height="160" rx="15" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                },
                heart: {
                    name: 'Heart',
                    svg: '<path d="M150 45 C120 45, 75 70, 75 130 C75 180, 120 210, 150 210 C180 210, 225 180, 225 130 C225 70, 180 45, 150 45 Z" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                },
                diamond: {
                    name: 'Diamond',
                    svg: '<path d="M150 45 L200 130 L150 215 L100 130 Z" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                },
                long: {
                    name: 'Long',
                    svg: '<ellipse cx="150" cy="130" rx="65" ry="95" fill="$skinTone" stroke="#d4a574" stroke-width="2"/>'
                }
            },
            
            skinTones: [
                '#fdd8b5', '#f5c6a0', '#e4a76f', '#d08b5b', 
                '#ba8660', '#a67c52', '#8b6f47', '#654321',
                '#f8d7da', '#f4c2a1', '#e8b88a', '#d49c6c'
            ],
            
            hairStyles: {
                short: {
                    name: 'Short',
                    svg: '<path d="M80 80 Q150 40, 220 80 Q210 60, 150 50 Q90 60, 80 80" fill="$hairColor"/>'
                },
                long: {
                    name: 'Long',
                    svg: '<path d="M70 70 Q150 30, 230 70 Q230 100, 220 130 Q200 150, 180 140 Q150 120, 120 140 Q100 150, 80 130 Q70 100, 70 70" fill="$hairColor"/>'
                },
                curly: {
                    name: 'Curly',
                    svg: '<g fill="$hairColor"><circle cx="90" cy="75" r="15"/><circle cx="110" cy="65" r="12"/><circle cx="130" cy="60" r="14"/><circle cx="150" cy="55" r="16"/><circle cx="170" cy="60" r="14"/><circle cx="190" cy="65" r="12"/><circle cx="210" cy="75" r="15"/></g>'
                },
                wavy: {
                    name: 'Wavy',
                    svg: '<path d="M75 75 Q100 55, 125 65 Q150 45, 175 65 Q200 55, 225 75 Q220 90, 200 95 Q150 80, 100 95 Q80 90, 75 75" fill="$hairColor"/>'
                },
                pixie: {
                    name: 'Pixie',
                    svg: '<path d="M85 85 Q150 45, 215 85 Q200 70, 150 65 Q100 70, 85 85" fill="$hairColor"/>'
                },
                ponytail: {
                    name: 'Ponytail',
                    svg: '<g fill="$hairColor"><path d="M80 80 Q150 40, 220 80 Q210 60, 150 50 Q90 60, 80 80"/><ellipse cx="200" cy="85" rx="8" ry="25" transform="rotate(45 200 85)"/></g>'
                },
                bald: {
                    name: 'Bald',
                    svg: '<path d="M85 100 Q150 85, 215 100" stroke="$hairColor" stroke-width="2" fill="none"/>'
                },
                afro: {
                    name: 'Afro',
                    svg: '<circle cx="150" cy="90" r="45" fill="$hairColor"/>'
                }
            },
            
            hairColors: [
                '#8B4513', '#D2691E', '#CD853F', '#F4A460',
                '#FFD700', '#FF6347', '#DC143C', '#800080',
                '#000000', '#2F4F4F', '#556B2F', '#8B0000'
            ],
            
            eyeStyles: {
                normal: {
                    name: 'Normal',
                    svg: '<g><ellipse cx="125" cy="110" rx="12" ry="8" fill="white" stroke="#333" stroke-width="1"/><ellipse cx="175" cy="110" rx="12" ry="8" fill="white" stroke="#333" stroke-width="1"/><circle cx="125" cy="110" r="5" fill="$eyeColor"/><circle cx="175" cy="110" r="5" fill="$eyeColor"/><circle cx="127" cy="108" r="2" fill="white"/><circle cx="177" cy="108" r="2" fill="white"/></g>'
                },
                large: {
                    name: 'Large',
                    svg: '<g><ellipse cx="125" cy="110" rx="15" ry="12" fill="white" stroke="#333" stroke-width="1"/><ellipse cx="175" cy="110" rx="15" ry="12" fill="white" stroke="#333" stroke-width="1"/><circle cx="125" cy="110" r="7" fill="$eyeColor"/><circle cx="175" cy="110" r="7" fill="$eyeColor"/><circle cx="127" cy="108" r="2" fill="white"/><circle cx="177" cy="108" r="2" fill="white"/></g>'
                },
                small: {
                    name: 'Small',
                    svg: '<g><ellipse cx="125" cy="110" rx="8" ry="6" fill="white" stroke="#333" stroke-width="1"/><ellipse cx="175" cy="110" rx="8" ry="6" fill="white" stroke="#333" stroke-width="1"/><circle cx="125" cy="110" r="3" fill="$eyeColor"/><circle cx="175" cy="110" r="3" fill="$eyeColor"/><circle cx="126" cy="109" r="1" fill="white"/><circle cx="176" cy="109" r="1" fill="white"/></g>'
                },
                almond: {
                    name: 'Almond',
                    svg: '<g><path d="M115 110 Q125 105, 135 110 Q125 115, 115 110" fill="white" stroke="#333" stroke-width="1"/><path d="M165 110 Q175 105, 185 110 Q175 115, 165 110" fill="white" stroke="#333" stroke-width="1"/><circle cx="125" cy="110" r="4" fill="$eyeColor"/><circle cx="175" cy="110" r="4" fill="$eyeColor"/></g>'
                },
                sleepy: {
                    name: 'Sleepy',
                    svg: '<g><path d="M115 112 Q125 108, 135 112" stroke="#333" stroke-width="2" fill="none"/><path d="M165 112 Q175 108, 185 112" stroke="#333" stroke-width="2" fill="none"/></g>'
                },
                winking: {
                    name: 'Winking',
                    svg: '<g><ellipse cx="125" cy="110" rx="12" ry="8" fill="white" stroke="#333" stroke-width="1"/><path d="M165 108 Q175 106, 185 108" stroke="#333" stroke-width="2" fill="none"/><circle cx="125" cy="110" r="5" fill="$eyeColor"/><circle cx="127" cy="108" r="2" fill="white"/></g>'
                }
            },
            
            eyeColors: [
                '#654321', '#8B4513', '#4169E1', '#228B22',
                '#800080', '#FF6347', '#DAA520', '#2F4F4F'
            ],
            
            noseStyles: {
                small: {
                    name: 'Small',
                    svg: '<ellipse cx="150" cy="125" rx="3" ry="6" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                },
                medium: {
                    name: 'Medium',
                    svg: '<ellipse cx="150" cy="125" rx="5" ry="8" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                },
                large: {
                    name: 'Large',
                    svg: '<ellipse cx="150" cy="125" rx="7" ry="12" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                },
                button: {
                    name: 'Button',
                    svg: '<circle cx="150" cy="125" r="4" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                },
                pointed: {
                    name: 'Pointed',
                    svg: '<path d="M150 115 L155 130 L145 130 Z" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                },
                wide: {
                    name: 'Wide',
                    svg: '<ellipse cx="150" cy="125" rx="8" ry="6" fill="#e4a76f" stroke="#d4a574" stroke-width="0.5"/>'
                }
            },
            
            mouthStyles: {
                neutral: {
                    name: 'Neutral',
                    emotions: {
                        neutral: '<path d="M135 145 Q150 145, 165 145" stroke="#333" stroke-width="2" fill="none"/>',
                        happy: '<path d="M135 145 Q150 155, 165 145" stroke="#333" stroke-width="2" fill="none"/>',
                        sad: '<path d="M135 155 Q150 145, 165 155" stroke="#333" stroke-width="2" fill="none"/>',
                        surprised: '<ellipse cx="150" cy="150" rx="8" ry="12" fill="#FF6B6B" stroke="#333" stroke-width="2"/>',
                        angry: '<path d="M135 150 Q150 140, 165 150" stroke="#333" stroke-width="3" fill="none"/>',
                        laughing: '<path d="M130 145 Q150 165, 170 145" stroke="#333" stroke-width="2" fill="none"/><path d="M140 155 Q150 160, 160 155" stroke="#333" stroke-width="1" fill="none"/>'
                    }
                },
                full: {
                    name: 'Full',
                    emotions: {
                        neutral: '<ellipse cx="150" cy="150" rx="15" ry="8" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        happy: '<path d="M135 145 Q150 160, 165 145" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        sad: '<path d="M135 155 Q150 140, 165 155" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        surprised: '<ellipse cx="150" cy="150" rx="12" ry="18" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        angry: '<path d="M135 155 Q150 140, 165 155" fill="#FF6B6B" stroke="#333" stroke-width="2"/>',
                        laughing: '<path d="M130 145 Q150 170, 170 145" fill="#FF6B6B" stroke="#333" stroke-width="1"/>'
                    }
                },
                small: {
                    name: 'Small',
                    emotions: {
                        neutral: '<circle cx="150" cy="150" r="6" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        happy: '<path d="M145 148 Q150 153, 155 148" stroke="#333" stroke-width="2" fill="none"/>',
                        sad: '<path d="M145 152 Q150 147, 155 152" stroke="#333" stroke-width="2" fill="none"/>',
                        surprised: '<ellipse cx="150" cy="150" rx="6" ry="10" fill="#FF6B6B" stroke="#333" stroke-width="1"/>',
                        angry: '<path d="M145 152 Q150 145, 155 152" stroke="#333" stroke-width="2" fill="none"/>',
                        laughing: '<path d="M140 148 Q150 158, 160 148" stroke="#333" stroke-width="2" fill="none"/>'
                    }
                }
            },
            
            glassesStyles: {
                none: {
                    name: 'None',
                    svg: ''
                },
                round: {
                    name: 'Round',
                    svg: '<g fill="none" stroke="#333" stroke-width="2"><circle cx="125" cy="110" r="18"/><circle cx="175" cy="110" r="18"/><path d="M143 110 L157 110"/><path d="M107 110 L100 115"/><path d="M193 110 L200 115"/></g>'
                },
                square: {
                    name: 'Square',
                    svg: '<g fill="none" stroke="#333" stroke-width="2"><rect x="107" y="92" width="36" height="36" rx="4"/><rect x="157" y="92" width="36" height="36" rx="4"/><path d="M143 110 L157 110"/><path d="M107 110 L100 115"/><path d="M193 110 L200 115"/></g>'
                },
                sunglasses: {
                    name: 'Sunglasses',
                    svg: '<g><circle cx="125" cy="110" r="18" fill="#333" stroke="#333" stroke-width="2"/><circle cx="175" cy="110" r="18" fill="#333" stroke="#333" stroke-width="2"/><path d="M143 110 L157 110" stroke="#333" stroke-width="2"/><path d="M107 110 L100 115" stroke="#333" stroke-width="2"/><path d="M193 110 L200 115" stroke="#333" stroke-width="2"/></g>'
                },
                reading: {
                    name: 'Reading',
                    svg: '<g fill="rgba(255,255,255,0.8)" stroke="#333" stroke-width="1"><rect x="107" y="92" width="36" height="36" rx="18"/><rect x="157" y="92" width="36" height="36" rx="18"/><path d="M143 110 L157 110" stroke="#333" stroke-width="2"/><path d="M107 110 L100 115" stroke="#333" stroke-width="2"/><path d="M193 110 L200 115" stroke="#333" stroke-width="2"/></g>'
                }
            },
            
            accessoryStyles: {
                none: {
                    name: 'None',
                    svg: ''
                },
                hat: {
                    name: 'Hat',
                    svg: '<g fill="#4A90E2"><ellipse cx="150" cy="65" rx="60" ry="8"/><ellipse cx="150" cy="55" rx="40" ry="15"/></g>'
                },
                headband: {
                    name: 'Headband',
                    svg: '<ellipse cx="150" cy="75" rx="65" ry="6" fill="#FF6B6B"/>'
                },
                bow: {
                    name: 'Bow',
                    svg: '<g fill="#FF69B4"><path d="M120 75 Q130 65, 140 75 Q130 85, 120 75"/><path d="M160 75 Q170 65, 180 75 Q170 85, 160 75"/><rect x="138" y="70" width="24" height="10" rx="2"/></g>'
                },
                earrings: {
                    name: 'Earrings',
                    svg: '<g><circle cx="100" cy="125" r="4" fill="#FFD700"/><circle cx="200" cy="125" r="4" fill="#FFD700"/></g>'
                },
                bandana: {
                    name: 'Bandana',
                    svg: '<path d="M80 70 Q150 40, 220 70 Q210 50, 150 45 Q90 50, 80 70" fill="#DC143C"/>'
                }
            },
            
            clothingStyles: {
                casual: {
                    name: 'Casual',
                    svg: '<path d="M80 200 Q80 190, 90 190 L210 190 Q220 190, 220 200 L220 270 Q220 280, 210 280 L90 280 Q80 280, 80 270 Z" fill="$clothingColor" stroke="#333" stroke-width="1"/>'
                },
                formal: {
                    name: 'Formal',
                    svg: '<g><path d="M80 200 Q80 190, 90 190 L210 190 Q220 190, 220 200 L220 270 Q220 280, 210 280 L90 280 Q80 280, 80 270 Z" fill="#333"/><path d="M90 200 L150 200 L210 200 L210 210 L90 210 Z" fill="white"/><circle cx="120" cy="225" r="3" fill="white"/><circle cx="150" cy="225" r="3" fill="white"/><circle cx="180" cy="225" r="3" fill="white"/></g>'
                },
                tshirt: {
                    name: 'T-Shirt',
                    svg: '<path d="M90 200 Q90 190, 100 190 L200 190 Q210 190, 210 200 L210 270 Q210 280, 200 280 L100 280 Q90 280, 90 270 Z" fill="$clothingColor" stroke="#333" stroke-width="1"/>'
                },
                hoodie: {
                    name: 'Hoodie',
                    svg: '<g><path d="M80 200 Q80 190, 90 190 L210 190 Q220 190, 220 200 L220 270 Q220 280, 210 280 L90 280 Q80 280, 80 270 Z" fill="$clothingColor" stroke="#333" stroke-width="1"/><path d="M100 190 Q150 170, 200 190" stroke="#333" stroke-width="2" fill="none"/></g>'
                },
                dress: {
                    name: 'Dress',
                    svg: '<path d="M100 200 Q100 190, 110 190 L190 190 Q200 190, 200 200 L220 270 Q220 280, 210 280 L90 280 Q80 280, 80 270 Z" fill="$clothingColor" stroke="#333" stroke-width="1"/>'
                }
            },
            
            clothingColors: [
                '#4A90E2', '#50C878', '#FF6B6B', '#FFD93D',
                '#9B59B6', '#E67E22', '#1ABC9C', '#34495E',
                '#E74C3C', '#3498DB', '#2ECC71', '#F39C12'
            ]
        };
    }

    initializeEmotions() {
        return {
            neutral: { name: '😐 Neutral', color: '#95A5A6' },
            happy: { name: '😊 Happy', color: '#F39C12' },
            sad: { name: '😢 Sad', color: '#3498DB' },
            surprised: { name: '😲 Surprised', color: '#E74C3C' },
            angry: { name: '😠 Angry', color: '#E74C3C' },
            laughing: { name: '😂 Laughing', color: '#27AE60' }
        };
    }

    init() {
        this.populateComponentGrids();
        this.setupEventListeners();
        this.renderAvatar();
    }

    populateComponentGrids() {
        // Face shapes
        this.populateGrid('face-shape-grid', this.components.faceShapes, 'face', 'shape');
        
        // Skin tones
        this.populateColorPalette('skin-tone-palette', this.components.skinTones, 'face', 'skinTone');
        
        // Hair styles
        this.populateGrid('hair-style-grid', this.components.hairStyles, 'hair', 'style');
        
        // Hair colors
        this.populateColorPalette('hair-color-palette', this.components.hairColors, 'hair', 'color');
        
        // Eyes
        this.populateGrid('eyes-grid', this.components.eyeStyles, 'eyes', 'style');
        
        // Nose
        this.populateGrid('nose-grid', this.components.noseStyles, 'nose', 'style');
        
        // Mouth
        this.populateGrid('mouth-grid', this.components.mouthStyles, 'mouth', 'style');
        
        // Glasses
        this.populateGrid('glasses-grid', this.components.glassesStyles, 'glasses', 'style');
        
        // Accessories
        this.populateGrid('accessories-grid', this.components.accessoryStyles, 'accessories', 'style');
        
        // Clothing
        this.populateGrid('clothing-grid', this.components.clothingStyles, 'clothing', 'style');
        
        // Emotions
        this.populateEmotions();
    }

    populateGrid(gridId, components, category, property) {
        const grid = document.getElementById(gridId);
        if (!grid) return;
        
        Object.keys(components).forEach(key => {
            const component = components[key];
            const item = document.createElement('div');
            item.className = 'component-item';
            item.dataset.category = category;
            item.dataset.property = property;
            item.dataset.value = key;
            
            // Add visual representation (simplified icon or preview)
            item.innerHTML = `
                <div class="text-center">
                    <div class="text-2xl mb-1">${this.getComponentIcon(category, key)}</div>
                    <div class="text-xs text-gray-600">${component.name}</div>
                </div>
            `;
            
            if (this.currentAvatar[category][property] === key) {
                item.classList.add('selected');
            }
            
            item.addEventListener('click', () => this.selectComponent(category, property, key));
            grid.appendChild(item);
        });
    }

    populateColorPalette(paletteId, colors, category, property) {
        const palette = document.getElementById(paletteId);
        if (!palette) return;
        
        colors.forEach(color => {
            const colorOption = document.createElement('div');
            colorOption.className = 'color-option';
            colorOption.style.backgroundColor = color;
            colorOption.dataset.category = category;
            colorOption.dataset.property = property;
            colorOption.dataset.value = color;
            
            if (this.currentAvatar[category][property] === color) {
                colorOption.classList.add('selected');
            }
            
            colorOption.addEventListener('click', () => this.selectComponent(category, property, color));
            palette.appendChild(colorOption);
        });
    }

    populateEmotions() {
        const panel = document.querySelector('.mood-selector');
        if (!panel) return;
        
        Object.keys(this.emotions).forEach(emotion => {
            const emotionData = this.emotions[emotion];
            const option = document.createElement('div');
            option.className = 'mood-option';
            option.dataset.emotion = emotion;
            option.innerHTML = emotionData.name;
            
            if (this.currentAvatar.mouth.emotion === emotion) {
                option.classList.add('selected');
            }
            
            option.addEventListener('click', () => this.selectEmotion(emotion));
            panel.appendChild(option);
        });
    }

    selectComponent(category, property, value) {
        // Update current avatar
        this.currentAvatar[category][property] = value;
        
        // Update UI selections
        document.querySelectorAll(`[data-category="${category}"][data-property="${property}"]`).forEach(item => {
            item.classList.toggle('selected', item.dataset.value === value);
        });
        
        // Re-render avatar
        this.renderAvatar();
    }

    selectEmotion(emotion) {
        this.currentAvatar.mouth.emotion = emotion;
        
        // Update UI selections
        document.querySelectorAll('.mood-option').forEach(item => {
            item.classList.toggle('selected', item.dataset.emotion === emotion);
        });
        
        this.renderAvatar();
    }

    renderAvatar() {
        const svg = document.getElementById('avatar-svg');
        if (!svg) return;
        
        // Clear previous content
        svg.innerHTML = '';
        
        // Add background
        const background = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        background.setAttribute('width', '100%');
        background.setAttribute('height', '100%');
        background.setAttribute('fill', '#f8fafc');
        background.setAttribute('rx', '20');
        svg.appendChild(background);
        
        // Render components in layer order
        const layers = [
            { component: 'face', layer: 1 },
            { component: 'hair', layer: 2 },
            { component: 'eyes', layer: 3 },
            { component: 'nose', layer: 4 },
            { component: 'mouth', layer: 5 },
            { component: 'glasses', layer: 6 },
            { component: 'accessories', layer: 7 },
            { component: 'clothing', layer: 0 }
        ];
        
        layers.sort((a, b) => a.layer - b.layer).forEach(({ component }) => {
            this.renderComponent(svg, component);
        });
    }

    renderComponent(svg, componentType) {
        const componentData = this.currentAvatar[componentType];
        let componentSVG = '';
        
        switch(componentType) {
            case 'face':
                const faceShape = this.components.faceShapes[componentData.shape];
                componentSVG = faceShape.svg.replace('$skinTone', componentData.skinTone);
                break;
                
            case 'hair':
                if (componentData.style !== 'bald') {
                    const hairStyle = this.components.hairStyles[componentData.style];
                    componentSVG = hairStyle.svg.replace('$hairColor', componentData.color);
                }
                break;
                
            case 'eyes':
                const eyeStyle = this.components.eyeStyles[componentData.style];
                componentSVG = eyeStyle.svg.replace(/\$eyeColor/g, this.components.eyeColors[0]);
                break;
                
            case 'nose':
                const noseStyle = this.components.noseStyles[componentData.style];
                componentSVG = noseStyle.svg;
                break;
                
            case 'mouth':
                const mouthStyle = this.components.mouthStyles[componentData.style];
                const emotion = componentData.emotion || 'neutral';
                componentSVG = mouthStyle.emotions[emotion] || mouthStyle.emotions.neutral;
                break;
                
            case 'glasses':
                if (componentData.style !== 'none') {
                    const glassesStyle = this.components.glassesStyles[componentData.style];
                    componentSVG = glassesStyle.svg;
                }
                break;
                
            case 'accessories':
                if (componentData.style !== 'none') {
                    const accessoryStyle = this.components.accessoryStyles[componentData.style];
                    componentSVG = accessoryStyle.svg;
                }
                break;
                
            case 'clothing':
                const clothingStyle = this.components.clothingStyles[componentData.style];
                componentSVG = clothingStyle.svg.replace('$clothingColor', componentData.color);
                break;
        }
        
        if (componentSVG) {
            const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            group.innerHTML = componentSVG;
            svg.appendChild(group);
        }
    }

    getComponentIcon(category, key) {
        const icons = {
            face: { oval: '⭕', round: '🔵', square: '⬜', heart: '💝', diamond: '💎', long: '📏' },
            hair: { short: '✂️', long: '💇‍♀️', curly: '🌀', wavy: '〰️', pixie: '🧚', ponytail: '🎯', bald: '🥚', afro: '☁️' },
            eyes: { normal: '👁️', large: '🔍', small: '🔸', almond: '🥜', sleepy: '😴', winking: '😉' },
            nose: { small: '🔹', medium: '🔶', large: '🔸', button: '🔘', pointed: '📐', wide: '↔️' },
            mouth: { neutral: '😐', full: '👄', small: '🤐' },
            glasses: { none: '❌', round: '🤓', square: '📐', sunglasses: '🕶️', reading: '📖' },
            accessories: { none: '❌', hat: '🎩', headband: '🎀', bow: '🎀', earrings: '💍', bandana: '🏴‍☠️' },
            clothing: { casual: '👕', formal: '🤵', tshirt: '👔', hoodie: '🧥', dress: '👗' }
        };
        
        return icons[category]?.[key] || '❔';
    }

    setupEventListeners() {
        // Randomize button
        document.getElementById('randomize-btn')?.addEventListener('click', () => {
            this.randomizeAvatar();
        });
        
        // Save button
        document.getElementById('save-btn')?.addEventListener('click', () => {
            this.saveAvatar();
        });
        
        // Emotions button
        document.getElementById('emotions-btn')?.addEventListener('click', () => {
            this.toggleEmotionPanel();
        });
        
        // Close modal
        document.getElementById('close-modal')?.addEventListener('click', () => {
            this.closeModal();
        });
    }

    randomizeAvatar() {
        // Randomize each component
        Object.keys(this.components.faceShapes).forEach((shape, index) => {
            if (Math.random() < 0.2) { // 20% chance to change each component
                const shapes = Object.keys(this.components.faceShapes);
                this.selectComponent('face', 'shape', shapes[Math.floor(Math.random() * shapes.length)]);
            }
        });
        
        // Random skin tone
        const skinTones = this.components.skinTones;
        this.selectComponent('face', 'skinTone', skinTones[Math.floor(Math.random() * skinTones.length)]);
        
        // Random hair
        const hairStyles = Object.keys(this.components.hairStyles);
        this.selectComponent('hair', 'style', hairStyles[Math.floor(Math.random() * hairStyles.length)]);
        
        const hairColors = this.components.hairColors;
        this.selectComponent('hair', 'color', hairColors[Math.floor(Math.random() * hairColors.length)]);
        
        // Random features
        const eyeStyles = Object.keys(this.components.eyeStyles);
        this.selectComponent('eyes', 'style', eyeStyles[Math.floor(Math.random() * eyeStyles.length)]);
        
        const noseStyles = Object.keys(this.components.noseStyles);
        this.selectComponent('nose', 'style', noseStyles[Math.floor(Math.random() * noseStyles.length)]);
        
        const mouthStyles = Object.keys(this.components.mouthStyles);
        this.selectComponent('mouth', 'style', mouthStyles[Math.floor(Math.random() * mouthStyles.length)]);
        
        // Random emotion
        const emotions = Object.keys(this.emotions);
        this.selectEmotion(emotions[Math.floor(Math.random() * emotions.length)]);
        
        // Random accessories (with higher chance of 'none')
        if (Math.random() > 0.6) {
            const glassesStyles = Object.keys(this.components.glassesStyles);
            this.selectComponent('glasses', 'style', glassesStyles[Math.floor(Math.random() * glassesStyles.length)]);
        }
        
        if (Math.random() > 0.7) {
            const accessoryStyles = Object.keys(this.components.accessoryStyles);
            this.selectComponent('accessories', 'style', accessoryStyles[Math.floor(Math.random() * accessoryStyles.length)]);
        }
        
        // Random clothing
        const clothingStyles = Object.keys(this.components.clothingStyles);
        this.selectComponent('clothing', 'style', clothingStyles[Math.floor(Math.random() * clothingStyles.length)]);
        
        const clothingColors = this.components.clothingColors;
        this.selectComponent('clothing', 'color', clothingColors[Math.floor(Math.random() * clothingColors.length)]);
    }

    toggleEmotionPanel() {
        const panel = document.getElementById('emotion-panel');
        if (panel) {
            panel.style.display = panel.style.display === 'none' ? 'block' : 'none';
        }
    }

    saveAvatar() {
        const svg = document.getElementById('avatar-svg');
        if (!svg) return;
        
        // Create canvas and convert SVG to image
        const svgData = new XMLSerializer().serializeToString(svg);
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        const img = new Image();
        
        canvas.width = 300;
        canvas.height = 300;
        
        const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
        const url = URL.createObjectURL(svgBlob);
        
        img.onload = function() {
            ctx.drawImage(img, 0, 0);
            
            // Download as PNG
            const link = document.createElement('a');
            link.download = `avatar-${Date.now()}.png`;
            link.href = canvas.toDataURL();
            link.click();
            
            URL.revokeObjectURL(url);
        };
        
        img.src = url;
    }

    closeModal() {
        const modal = document.getElementById('collections-modal');
        if (modal) {
            modal.style.display = 'none';
        }
    }
}

// Initialize the avatar creator when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new ModularAvatarCreator();
});