/**
 * AAC Symbol Generator JavaScript
 * Specialized tool for generating descriptive word symbols for AAC application
 * Uses existing imagecreator infrastructure with AAC-specific optimizations
 */

let currentStep = 1;
let selectedWords = [];
let generatedSymbols = [];
let selectedSymbols = [];

// Initialize when page loads
function initializeSymbolGenerator() {
    console.log('AAC Symbol Generator initialized');
    updateStepIndicator();
    updateSelectedCount();
    
    // Add event listeners for checkboxes
    document.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
        checkbox.addEventListener('change', updateSelectedCount);
    });
}

// Utility function to get authentication token (using existing auth system)
async function getAuthHeaders() {
    try {
        const token = await window.getAuthToken();
        return {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
        };
    } catch (error) {
        console.error('Error getting auth token:', error);
        throw new Error('Authentication failed');
    }
}

// Update step indicator UI
function updateStepIndicator() {
    for (let i = 1; i <= 4; i++) {
        const step = document.getElementById(`step-${i}`);
        const panel = document.getElementById(`step-${i}-panel`);
        
        if (i < currentStep) {
            step.classList.add('completed');
            step.classList.remove('active');
            if (panel) panel.classList.add('hidden');
        } else if (i === currentStep) {
            step.classList.add('active');
            step.classList.remove('completed');
            if (panel) panel.classList.remove('hidden');
        } else {
            step.classList.remove('active', 'completed');
            if (panel) panel.classList.add('hidden');
        }
    }
}

// Move to specific step
function goToStep(step) {
    currentStep = step;
    updateStepIndicator();
}

// Update selected word count
function updateSelectedCount() {
    const checkboxes = document.querySelectorAll('input[type="checkbox"]:checked');
    const customWords = document.getElementById('custom-words').value
        .split(',')
        .map(w => w.trim())
        .filter(w => w.length > 0);
    
    const totalCount = checkboxes.length + customWords.length;
    document.getElementById('selected-count').textContent = totalCount;
    
    // Update selectedWords array
    selectedWords = [];
    checkboxes.forEach(cb => selectedWords.push(cb.value));
    customWords.forEach(word => selectedWords.push(word));
}

// Proceed to generation configuration
function proceedToGeneration() {
    updateSelectedCount();
    
    if (selectedWords.length === 0) {
        alert('Please select at least one word to generate symbols for.');
        return;
    }
    
    console.log('Selected words for generation:', selectedWords);
    goToStep(2);
}

// Generate symbols using AAC-optimized prompts
async function generateSymbols() {
    const btn = document.getElementById('generate-symbols-btn');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Generating...';
    btn.disabled = true;
    
    try {
        const style = document.getElementById('symbol-style').value;
        const variations = parseInt(document.getElementById('variations-count').value);
        const styleNotes = document.getElementById('style-notes').value;
        
        // Create AAC-specific generation prompts
        const symbolRequests = selectedWords.map(word => ({
            word: word,
            prompt: createAACSymbolPrompt(word, style, styleNotes),
            category: categorizeWord(word),
            tags: generateWordTags(word)
        }));
        
        const headers = await getAuthHeaders();
        
        // Use existing image generation endpoint with simple string array format
        const response = await fetch('/api/imagecreator/generate-images', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                concept: "AAC Descriptive Symbols",
                subconcepts: selectedWords, // Send simple string array, not complex objects
                style: `AAC Symbol - ${style} - ${styleNotes}`
            })
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            console.error('API Error Response:', errorText);
            try {
                const error = JSON.parse(errorText);
                throw new Error(error.detail || 'Failed to generate symbols');
            } catch {
                throw new Error(`Server error: ${response.status} - ${errorText}`);
            }
        }
        
        const data = await response.json();
        console.log('API Response:', data); // Debug log
        console.log('API Response images:', data.images); // Debug log
        
        // Transform the response to include AAC metadata for each generated symbol
        generatedSymbols = (data.images || []).map((image, index) => {
            console.log('Processing image:', image); // Debug log
            console.log('Image URL from API:', image.image_url); // Debug log
            const processedSymbol = {
                ...image,
                word: selectedWords[index % selectedWords.length], // Map back to original words
                category: categorizeWord(selectedWords[index % selectedWords.length]),
                tags: generateWordTags(selectedWords[index % selectedWords.length]),
                concept: selectedWords[index % selectedWords.length], // Set concept to the word
                subconcept: selectedWords[index % selectedWords.length] // Set subconcept to the word
            };
            console.log('Processed symbol:', processedSymbol); // Debug log
            return processedSymbol;
        });
        
        console.log('Generated symbols:', generatedSymbols); // Debug log
        
        // Display generated symbols
        displayGeneratedSymbols();
        goToStep(3);
        
    } catch (error) {
        console.error('Error generating symbols:', error);
        console.error('Full error details:', error.message);
        alert('Error generating symbols: ' + error.message);
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

// Create AAC-specific prompts for each word
function createAACSymbolPrompt(word, style, styleNotes) {
    const basePrompt = `Create a clear, simple AAC communication symbol for the word "${word}".`;
    
    const stylePrompts = {
        'picom-style': 'Match the PiCom Global Symbols style: simple line art, minimal colors, high contrast, universally recognizable.',
        'minimalist': 'Minimalist design with clean lines, simple shapes, limited color palette.',
        'friendly': 'Friendly and colorful design suitable for all ages, warm and inviting.',
        'high-contrast': 'High contrast black and white design for maximum accessibility and readability.'
    };
    
    const wordSpecificGuidance = getWordSpecificGuidance(word);
    
    return `${basePrompt} ${stylePrompts[style]} ${wordSpecificGuidance} ${styleNotes} 
    Requirements: transparent background, 512x512 pixels, suitable for AAC communication device.`;
}

// Get word-specific visual guidance
function getWordSpecificGuidance(word) {
    const positiveWords = ['fantastic', 'awesome', 'amazing', 'incredible', 'wonderful', 'brilliant', 'excellent', 'outstanding'];
    const emotionalWords = ['ecstatic', 'delighted', 'thrilled', 'overjoyed', 'content', 'serene'];
    const activityWords = ['energetic', 'dynamic', 'vibrant', 'creative', 'artistic', 'confident'];
    
    if (positiveWords.includes(word)) {
        return 'Use bright, uplifting imagery like stars, sunshine, or upward arrows to convey positivity.';
    } else if (emotionalWords.includes(word)) {
        return 'Focus on facial expressions or emotional symbols that clearly convey the feeling.';
    } else if (activityWords.includes(word)) {
        return 'Use dynamic shapes or movement indicators to show action and energy.';
    }
    
    return 'Create a clear, universally understandable symbol that represents the concept.';
}

// Categorize words for database organization
function categorizeWord(word) {
    const positiveWords = ['fantastic', 'awesome', 'amazing', 'incredible', 'wonderful', 'brilliant', 'excellent', 'outstanding'];
    const emotionalWords = ['ecstatic', 'delighted', 'thrilled', 'overjoyed', 'content', 'serene'];
    const activityWords = ['energetic', 'dynamic', 'vibrant', 'creative', 'artistic', 'confident'];
    
    if (positiveWords.includes(word)) return 'descriptors';
    if (emotionalWords.includes(word)) return 'emotions';
    if (activityWords.includes(word)) return 'activities';
    
    return 'descriptors'; // default
}

// Generate searchable tags for each word
function generateWordTags(word) {
    const baseTags = [word];
    
    // Add synonyms and related terms
    const tagMappings = {
        'fantastic': ['great', 'wonderful', 'amazing', 'positive', 'good'],
        'awesome': ['amazing', 'great', 'incredible', 'positive', 'good'],
        'amazing': ['incredible', 'wonderful', 'fantastic', 'great', 'positive'],
        'incredible': ['amazing', 'unbelievable', 'fantastic', 'wonderful'],
        'wonderful': ['great', 'fantastic', 'lovely', 'nice', 'positive'],
        'brilliant': ['smart', 'clever', 'bright', 'excellent', 'great'],
        'excellent': ['great', 'outstanding', 'perfect', 'good', 'superior'],
        'outstanding': ['excellent', 'exceptional', 'remarkable', 'great'],
        'ecstatic': ['very happy', 'overjoyed', 'elated', 'thrilled'],
        'delighted': ['pleased', 'happy', 'glad', 'joyful'],
        'thrilled': ['excited', 'elated', 'overjoyed', 'happy'],
        'overjoyed': ['ecstatic', 'elated', 'very happy', 'thrilled'],
        'content': ['satisfied', 'peaceful', 'happy', 'calm'],
        'serene': ['peaceful', 'calm', 'tranquil', 'quiet'],
        'energetic': ['active', 'lively', 'dynamic', 'vigorous'],
        'dynamic': ['active', 'energetic', 'powerful', 'forceful'],
        'vibrant': ['lively', 'energetic', 'bright', 'colorful'],
        'creative': ['artistic', 'imaginative', 'inventive', 'original'],
        'artistic': ['creative', 'aesthetic', 'beautiful', 'expressive'],
        'confident': ['sure', 'certain', 'self-assured', 'bold']
    };
    
    if (tagMappings[word]) {
        baseTags.push(...tagMappings[word]);
    }
    
    return baseTags;
}

// Display generated symbols for review
function displayGeneratedSymbols() {
    const container = document.getElementById('generated-symbols-container');
    container.innerHTML = '';
    
    console.log('Displaying symbols:', generatedSymbols); // Debug log
    
    generatedSymbols.forEach((symbol, index) => {
        console.log(`Symbol ${index}:`, symbol); // Debug log
        console.log(`Image URL for ${symbol.word}:`, symbol.image_url); // Debug log
        
        const card = document.createElement('div');
        card.className = 'symbol-card cursor-pointer';
        card.onclick = () => toggleSymbolSelection(index);

        card.innerHTML = `
            <div class="relative">
                <img src="${symbol.image_url || 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iI2VlZSIvPjx0ZXh0IHg9IjUwIiB5PSI1MCIgZm9udC1mYW1pbHk9IkFyaWFsIiBmb250LXNpemU9IjE0IiBmaWxsPSIjOTk5IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBkb21pbmFudC1iYXNlbGluZT0ibWlkZGxlIj5ObyBJbWFnZTwvdGV4dD48L3N2Zz4='}" alt="${symbol.word}" class="w-full h-40 object-contain bg-white" onload="console.log('Image loaded successfully:', this.src); this.style.border='3px solid green'; console.log('Image dimensions:', this.naturalWidth, 'x', this.naturalHeight);" onerror="console.error('Failed to load image:', this.src, 'Error details:', event); this.style.border='3px solid red';" crossorigin="anonymous">
                <div class="absolute top-2 right-2">
                    <input type="checkbox" class="w-4 h-4" ${selectedSymbols.includes(index) ? 'checked' : ''}>
                </div>
                <div class="absolute bottom-2 left-2 bg-black bg-opacity-75 text-white text-xs px-2 py-1 rounded">
                    IMG: ${index + 1}
                </div>
            </div>
            <div class="p-3">
                <h3 class="font-semibold text-sm">${symbol.word || symbol.concept || 'Symbol'}</h3>
                <p class="text-xs text-gray-600 mt-1">${symbol.subconcept || 'Generated symbol'}</p>
                <div class="mt-2">
                    ${(symbol.tags || []).slice(0, 3).map(tag => `<span class="word-tag">${tag}</span>`).join('')}
                </div>
                <div class="mt-1 text-xs text-gray-400">
                    URL: ${symbol.image_url ? 'Present' : 'Missing'}
                </div>
            </div>
        `;

        container.appendChild(card);
    });    // Auto-select all symbols initially
    selectedSymbols = generatedSymbols.map((_, index) => index);
    updateSymbolSelectionUI();
}

// Toggle symbol selection
function toggleSymbolSelection(index) {
    if (selectedSymbols.includes(index)) {
        selectedSymbols = selectedSymbols.filter(i => i !== index);
    } else {
        selectedSymbols.push(index);
    }
    updateSymbolSelectionUI();
}

// Update symbol selection UI
function updateSymbolSelectionUI() {
    const cards = document.querySelectorAll('.symbol-card');
    cards.forEach((card, index) => {
        const checkbox = card.querySelector('input[type="checkbox"]');
        if (selectedSymbols.includes(index)) {
            card.classList.add('selected');
            checkbox.checked = true;
        } else {
            card.classList.remove('selected');
            checkbox.checked = false;
        }
    });
}

// Proceed to import selected symbols
function proceedToImport() {
    if (selectedSymbols.length === 0) {
        alert('Please select at least one symbol to import.');
        return;
    }
    
    goToStep(4);
    importSymbolsToAAC();
}

// Import selected symbols to AAC database
async function importSymbolsToAAC() {
    const progressBar = document.getElementById('import-progress-bar');
    const statusText = document.getElementById('import-status');
    const resultsDiv = document.getElementById('import-results');
    
    try {
        statusText.textContent = 'Preparing symbols for import...';
        progressBar.style.width = '10%';
        
        const symbolsToImport = selectedSymbols.map(index => {
            const symbol = generatedSymbols[index];
            return {
                name: symbol.concept || symbol.subconcept || `symbol_${index}`,
                description: `AAC symbol for ${symbol.concept || symbol.subconcept}`,
                tags: symbol.tags || [],
                categories: [symbol.category || 'descriptors'],
                image_url: symbol.image_url,
                source: 'gemini_generated',
                search_weight: 2,
                age_groups: ['all'],
                difficulty_level: 'simple'
            };
        });
        
        statusText.textContent = 'Converting to AAC database format...';
        progressBar.style.width = '30%';
        
        // Use the new AAC symbol import endpoint
        const headers = await getAuthHeaders();
        const response = await fetch('/api/symbols/import-aac-generated', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                symbols: symbolsToImport,
                batch_size: 10
            })
        });
        
        statusText.textContent = 'Importing to database...';
        progressBar.style.width = '70%';
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to import symbols');
        }
        
        const result = await response.json();
        
        statusText.textContent = 'Import complete!';
        progressBar.style.width = '100%';
        
        // Show results
        setTimeout(() => {
            document.getElementById('imported-count').textContent = result.imported_count || symbolsToImport.length;
            resultsDiv.classList.remove('hidden');
            document.getElementById('import-progress').classList.add('hidden');
        }, 1000);
        
    } catch (error) {
        console.error('Error importing symbols:', error);
        statusText.textContent = `Import failed: ${error.message}`;
        progressBar.style.width = '0%';
        alert('Error importing symbols: ' + error.message);
    }
}

// Start over
function startOver() {
    currentStep = 1;
    selectedWords = [];
    generatedSymbols = [];
    selectedSymbols = [];
    
    // Reset form
    document.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = false);
    document.getElementById('custom-words').value = '';
    
    // Reset UI
    updateStepIndicator();
    updateSelectedCount();
    
    // Hide results
    document.getElementById('import-results').classList.add('hidden');
    document.getElementById('import-progress').classList.remove('hidden');
    document.getElementById('import-progress-bar').style.width = '0%';
    document.getElementById('import-status').textContent = 'Ready to import...';
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', initializeSymbolGenerator);