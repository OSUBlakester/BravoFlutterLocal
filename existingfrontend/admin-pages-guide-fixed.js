/**
 * Smart Help System - Globally accessible version
 * Provides intelligent contextual assistance for admin interfaces
 */
class SmartHelpSystem {
    constructor() {
        this.isInitialized = false;
        this.currentContext = null;
        this.helpDatabase = this.initializeHelpDatabase();
        console.log('SmartHelpSystem constructor called');
    }
    
    initialize() {
        if (this.isInitialized) return;
        console.log('SmartHelpSystem initializing...');
        this.isInitialized = true;
        console.log('SmartHelpSystem initialized successfully');
    }
    
    initializeHelpDatabase() {
        return {
            'admin-pages': {
                overview: 'Manage your application pages and button configurations',
                quickActions: [
                    'Create new page',
                    'Edit existing page',
                    'Configure button grid',
                    'Set up navigation'
                ],
                commonTasks: {
                    'create-page': 'Select "Create New Page" from dropdown, enter display name, and configure buttons',
                    'edit-buttons': 'Click on any grid button to open the button editor',
                    'navigation': 'Use the target page dropdown to set up page navigation'
                }
            }
        };
    }
    
    getContextualHelp(context) {
        const help = this.helpDatabase[context] || this.helpDatabase['admin-pages'];
        this.showHelpModal('Contextual Help', help.description || help);
        return help;
    }
    
    getAdvancedTips() {
        const tips = [
            '🎯 Use dynamic buttons with AI queries for personalized responses',
            '🔗 Set up page navigation chains for complex communication flows',
            '🎨 Organize buttons by frequency of use for better accessibility',
            '⚡ Test your pages with different user scenarios',
            '📱 Consider mobile-friendly button sizing and spacing'
        ];
        this.showHelpModal('Advanced Tips', `
            <div style="text-align: left;">
                <h4>🚀 Advanced Admin Tips</h4>
                <ul style="margin: 15px 0; padding-left: 20px;">
                    ${tips.map(tip => `<li style="margin: 8px 0;">${tip}</li>`).join('')}
                </ul>
            </div>
        `);
    }
    
    getPersonalizedRecommendations() {
        this.showHelpModal('Personalized Recommendations', `
            <div style="text-align: left;">
                <h4>📊 Your Customization Recommendations</h4>
                <div style="background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 10px 0;">
                    <strong>✅ Quick Wins:</strong>
                    <ul style="margin: 10px 0; padding-left: 20px;">
                        <li>Create dedicated pages for frequently used phrases</li>
                        <li>Set up navigation shortcuts between related pages</li>
                        <li>Use AI-powered dynamic buttons for flexible responses</li>
                    </ul>
                </div>
                <div style="background: #fff3cd; padding: 15px; border-radius: 8px; margin: 10px 0;">
                    <strong>🔧 Optimization Tips:</strong>
                    <ul style="margin: 10px 0; padding-left: 20px;">
                        <li>Group similar concepts on the same page</li>
                        <li>Use clear, descriptive button labels</li>
                        <li>Test page flows with actual users</li>
                    </ul>
                </div>
            </div>
        `);
    }
    
    showHelpModal(title, content) {
        // Create modal overlay
        const overlay = document.createElement('div');
        overlay.style.cssText = `
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.5); z-index: 10000; display: flex;
            align-items: center; justify-content: center;
        `;
        
        // Create modal content
        const modal = document.createElement('div');
        modal.style.cssText = `
            background: white; padding: 30px; border-radius: 12px;
            max-width: 600px; max-height: 80vh; overflow-y: auto;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        `;
        
        modal.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                <h3 style="margin: 0; color: #2c3e50;">${title}</h3>
                <button onclick="this.closest('.help-modal-overlay').remove()" 
                        style="background: none; border: none; font-size: 24px; cursor: pointer; color: #7f8c8d;">×</button>
            </div>
            <div>${content}</div>
        `;
        
        overlay.className = 'help-modal-overlay';
        overlay.appendChild(modal);
        document.body.appendChild(overlay);
        
        // Close on overlay click
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                overlay.remove();
            }
        });
    }
    
    generateSmartSuggestions(currentAction) {
        const suggestions = [
            'Start by creating a new page or selecting an existing one',
            'Use the button grid to configure interactive elements',
            'Set up AI queries for dynamic button behavior',
            'Test your configuration before saving'
        ];
        return suggestions;
    }
}

/**
 * Multimedia Help System - Globally accessible version
 * Provides rich media support for help content
 */
class MultimediaHelpSystem {
    constructor() {
        this.isInitialized = false;
        this.mediaCache = new Map();
        this.supportedFormats = ['image', 'video', 'audio', 'interactive'];
        console.log('MultimediaHelpSystem constructor called');
    }
    
    initialize() {
        if (this.isInitialized) return;
        console.log('MultimediaHelpSystem initializing...');
        this.isInitialized = true;
        console.log('MultimediaHelpSystem initialized successfully');
    }
    
    createInteractiveDemo(stepId, config) {
        const demo = document.createElement('div');
        demo.className = 'interactive-demo';
        demo.innerHTML = `
            <div class="demo-content">
                <h4>${config.title}</h4>
                <p>${config.description}</p>
                <div class="demo-actions">
                    ${config.actions.map(action => `
                        <button class="demo-action-btn" data-action="${action.id}">
                            ${action.label}
                        </button>
                    `).join('')}
                </div>
            </div>
        `;
        return demo;
    }
    
    highlightElement(selector, message) {
        const element = document.querySelector(selector);
        if (!element) return null;
        
        const highlight = document.createElement('div');
        highlight.className = 'help-highlight';
        highlight.style.cssText = `
            position: absolute;
            pointer-events: none;
            border: 2px solid #3b82f6;
            border-radius: 4px;
            background: rgba(59, 130, 246, 0.1);
            z-index: 9999;
        `;
        
        const rect = element.getBoundingClientRect();
        highlight.style.left = (rect.left + window.scrollX - 2) + 'px';
        highlight.style.top = (rect.top + window.scrollY - 2) + 'px';
        highlight.style.width = (rect.width + 4) + 'px';
        highlight.style.height = (rect.height + 4) + 'px';
        
        document.body.appendChild(highlight);
        
        if (message) {
            const tooltip = document.createElement('div');
            tooltip.className = 'help-tooltip';
            tooltip.textContent = message;
            tooltip.style.cssText = `
                position: absolute;
                background: #1f2937;
                color: white;
                padding: 8px 12px;
                border-radius: 6px;
                font-size: 14px;
                z-index: 10000;
                max-width: 250px;
            `;
            tooltip.style.left = (rect.left + window.scrollX) + 'px';
            tooltip.style.top = (rect.top + window.scrollY - 40) + 'px';
            document.body.appendChild(tooltip);
            
            setTimeout(() => {
                tooltip.remove();
            }, 3000);
        }
        
        return highlight;
    }
    
    removeHighlights() {
        document.querySelectorAll('.help-highlight').forEach(el => el.remove());
        document.querySelectorAll('.help-tooltip').forEach(el => el.remove());
    }
}

// Make classes globally available immediately
window.SmartHelpSystem = SmartHelpSystem;
window.MultimediaHelpSystem = MultimediaHelpSystem;

console.log('Admin pages guide classes loaded and made globally available');
console.log('SmartHelpSystem available:', typeof SmartHelpSystem);
console.log('MultimediaHelpSystem available:', typeof MultimediaHelpSystem);
