// Admin Pages Interactive Guide System
// Comprehensive guided tours with Smart Help and Multi-media Rich features

document.addEventListener('DOMContentLoaded', function() {
    
    // Smart Help AI System
    class SmartHelpSystem {
        constructor() {
            this.helpHistory = [];
            this.userContext = {
                currentPage: 'admin_pages',
                skillLevel: 'beginner', // beginner, intermediate, advanced
                commonQuestions: [],
                strugglingWith: []
            };
            this.initializeSmartHelp();
        }

        async initializeSmartHelp() {
            // Create smart help UI
            this.createSmartHelpUI();
            this.attachEventListeners();
            this.loadUserPreferences();
        }

        createSmartHelpUI() {
            // Smart Help floating assistant
            const smartHelpHTML = `
                <div id="smart-help-assistant" class="fixed bottom-4 right-4 z-50 hidden">
                    <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-4 rounded-2xl shadow-2xl max-w-sm">
                        <div class="flex items-center justify-between mb-2">
                            <div class="flex items-center">
                                <div class="w-8 h-8 bg-white bg-opacity-20 rounded-full flex items-center justify-center mr-2">
                                    🤖
                                </div>
                                <span class="font-semibold">Smart Help</span>
                            </div>
                            <button id="close-smart-help" class="text-white hover:text-gray-200">
                                <i class="fas fa-times"></i>
                            </button>
                        </div>
                        <div id="smart-help-content">
                            <p class="text-sm mb-3">I can help you with page and button management! What would you like to know?</p>
                            <div class="space-y-2">
                                <button class="smart-help-suggestion w-full text-left text-xs bg-white bg-opacity-20 p-2 rounded hover:bg-opacity-30" data-question="How do I create a new page?">
                                    🆕 How do I create a new page?
                                </button>
                                <button class="smart-help-suggestion w-full text-left text-xs bg-white bg-opacity-20 p-2 rounded hover:bg-opacity-30" data-question="How do I set up AI buttons?">
                                    🤖 How do I set up AI buttons?
                                </button>
                                <button class="smart-help-suggestion w-full text-left text-xs bg-white bg-opacity-20 p-2 rounded hover:bg-opacity-30" data-question="How do I rearrange buttons?">
                                    🤏 How do I rearrange buttons?
                                </button>
                            </div>
                        </div>
                        <div class="mt-3 flex space-x-2">
                            <input type="text" id="smart-help-input" placeholder="Ask me anything..." class="flex-1 text-xs p-2 rounded text-gray-800">
                            <button id="smart-help-send" class="bg-white bg-opacity-20 p-2 rounded hover:bg-opacity-30">
                                <i class="fas fa-paper-plane text-xs"></i>
                            </button>
                        </div>
                    </div>
                </div>
            `;

            document.body.insertAdjacentHTML('beforeend', smartHelpHTML);
        }

        attachEventListeners() {
            // Smart help suggestions
            document.addEventListener('click', (e) => {
                if (e.target.classList.contains('smart-help-suggestion')) {
                    const question = e.target.dataset.question;
                    this.handleSmartHelpQuestion(question);
                }
            });

            // Smart help input
            const smartHelpInput = document.getElementById('smart-help-input');
            const smartHelpSend = document.getElementById('smart-help-send');
            
            if (smartHelpInput && smartHelpSend) {
                smartHelpSend.addEventListener('click', () => {
                    const question = smartHelpInput.value.trim();
                    if (question) {
                        this.handleSmartHelpQuestion(question);
                        smartHelpInput.value = '';
                    }
                });

                smartHelpInput.addEventListener('keypress', (e) => {
                    if (e.key === 'Enter') {
                        smartHelpSend.click();
                    }
                });
            }

            // Close smart help
            const closeButton = document.getElementById('close-smart-help');
            if (closeButton) {
                closeButton.addEventListener('click', () => {
                    this.hideSmartHelp();
                });
            }

            // Auto-trigger smart help based on user behavior
            this.setupBehaviorTriggers();
        }

        setupBehaviorTriggers() {
            // Show smart help if user seems stuck
            let inactivityTimer;
            let clickCount = 0;

            document.addEventListener('click', () => {
                clickCount++;
                clearTimeout(inactivityTimer);
                
                // If user clicks same area multiple times, they might be confused
                if (clickCount > 5) {
                    setTimeout(() => {
                        this.showSmartHelp();
                        this.updateSmartHelpContent("I noticed you're clicking around a lot. Can I help you find what you're looking for?");
                    }, 1000);
                    clickCount = 0;
                }

                // Reset click count after 10 seconds
                setTimeout(() => { clickCount = 0; }, 10000);
            });

            // Show help after period of inactivity
            const resetInactivityTimer = () => {
                clearTimeout(inactivityTimer);
                inactivityTimer = setTimeout(() => {
                    this.showSmartHelp();
                    this.updateSmartHelpContent("Need help getting started? I can guide you through creating your first page or button!");
                }, 30000); // 30 seconds of inactivity
            };

            document.addEventListener('mousemove', resetInactivityTimer);
            document.addEventListener('keypress', resetInactivityTimer);
            resetInactivityTimer();
        }

        async handleSmartHelpQuestion(question) {
            this.helpHistory.push(question);
            
            // Show loading state
            this.updateSmartHelpContent(`
                <div class="text-sm">
                    <div class="animate-pulse">🤔 Let me think about that...</div>
                </div>
            `);

            try {
                // Generate contextual response based on current page state
                const response = await this.generateSmartResponse(question);
                this.updateSmartHelpContent(response);
            } catch (error) {
                console.error('Smart help error:', error);
                this.updateSmartHelpContent(`
                    <div class="text-sm">
                        <p class="text-yellow-200">I'm having trouble right now, but here are some quick tips:</p>
                        <ul class="mt-2 space-y-1 text-xs">
                            <li>• Use the Button Wizard for guided button creation</li>
                            <li>• Click the grid to edit buttons directly</li>
                            <li>• Drag buttons to rearrange them</li>
                            <li>• Check the tutorials in the main help section</li>
                        </ul>
                    </div>
                `);
            }
        }

        async generateSmartResponse(question) {
            // Analyze current page context
            const context = this.analyzeCurrentContext();
            
            // Generate smart response based on question and context
            const responses = {
                'how do i create a new page': `
                    <div class="text-sm space-y-2">
                        <p><strong>🆕 Creating a New Page:</strong></p>
                        <ol class="text-xs space-y-1">
                            <li>1. Enter a name in "Display Name" field</li>
                            <li>2. Click "Create/Update Page" button</li>
                            <li>3. Your new page appears in the dropdown</li>
                        </ol>
                        ${context.hasEmptyPageName ? '<p class="text-yellow-200">💡 I see the name field is empty - try entering something like "Breakfast" or "Activities"</p>' : ''}
                        <button class="smart-help-action text-xs bg-white bg-opacity-20 p-1 rounded" data-action="highlight-page-creation">Show me where</button>
                    </div>
                `,
                'how do i set up ai buttons': `
                    <div class="text-sm space-y-2">
                        <p><strong>🤖 AI Button Setup:</strong></p>
                        <ol class="text-xs space-y-1">
                            <li>1. Click any empty grid slot</li>
                            <li>2. Add button text (what it shows)</li>
                            <li>3. In "AI Query" field, describe what you want</li>
                            <li>4. Save the button</li>
                        </ol>
                        <div class="bg-white bg-opacity-20 p-2 rounded text-xs">
                            <strong>Example AI Query:</strong><br>
                            "Generate 3 polite ways to ask for help"
                        </div>
                        <button class="smart-help-action text-xs bg-white bg-opacity-20 p-1 rounded" data-action="demo-ai-button">Show me a demo</button>
                    </div>
                `,
                'how do i rearrange buttons': `
                    <div class="text-sm space-y-2">
                        <p><strong>🤏 Drag & Drop Guide:</strong></p>
                        <ol class="text-xs space-y-1">
                            <li>1. Click and hold any button</li>
                            <li>2. Drag to the new position</li>
                            <li>3. Drop when you see the red highlight</li>
                            <li>4. Click "Save Button Changes"</li>
                        </ol>
                        ${context.hasButtons ? '<button class="smart-help-action text-xs bg-white bg-opacity-20 p-1 rounded" data-action="demo-drag-drop">Show me how</button>' : '<p class="text-yellow-200">💡 You need some buttons first - try creating one!</p>'}
                    </div>
                `
            };

            // Find best matching response
            const questionLower = question.toLowerCase();
            for (const [key, response] of Object.entries(responses)) {
                if (questionLower.includes(key.replace(/[^\w\s]/g, ''))) {
                    return response;
                }
            }

            // Fallback: generate contextual help
            return this.generateContextualHelp(question, context);
        }

        generateContextualHelp(question, context) {
            let help = `<div class="text-sm space-y-2">`;
            
            if (question.toLowerCase().includes('button')) {
                help += `
                    <p><strong>🎛️ Button Help:</strong></p>
                    <ul class="text-xs space-y-1">
                        <li>• Click grid slots to create/edit buttons</li>
                        <li>• Use the Button Wizard for step-by-step guidance</li>
                        <li>• Drag buttons to rearrange them</li>
                        <li>• Add AI queries for dynamic content</li>
                    </ul>
                `;
            } else if (question.toLowerCase().includes('page')) {
                help += `
                    <p><strong>📄 Page Help:</strong></p>
                    <ul class="text-xs space-y-1">
                        <li>• Select pages from the dropdown</li>
                        <li>• Create new pages with descriptive names</li>
                        <li>• Each page has its own 10x10 button grid</li>
                        <li>• Delete unused pages to keep things organized</li>
                    </ul>
                `;
            } else {
                help += `
                    <p><strong>🤔 Not sure what you mean, but here are common tasks:</strong></p>
                    <ul class="text-xs space-y-1">
                        <li>• Creating pages and buttons</li>
                        <li>• Setting up AI-powered content</li>
                        <li>• Arranging your button layout</li>
                        <li>• Configuring speech and navigation</li>
                    </ul>
                `;
            }

            help += `</div>`;
            return help;
        }

        analyzeCurrentContext() {
            const pageNameField = document.getElementById('newPageDisplayName');
            const buttonGrid = document.getElementById('buttonGrid');
            const pageSelect = document.getElementById('selectPage');

            return {
                hasEmptyPageName: pageNameField && !pageNameField.value.trim(),
                hasButtons: buttonGrid && buttonGrid.querySelectorAll('.visual-button.has-content').length > 0,
                currentPage: pageSelect ? pageSelect.value : null,
                isNewUser: !localStorage.getItem('userHasCreatedButton')
            };
        }

        showSmartHelp() {
            const assistant = document.getElementById('smart-help-assistant');
            if (assistant) {
                assistant.classList.remove('hidden');
            }
        }

        hideSmartHelp() {
            const assistant = document.getElementById('smart-help-assistant');
            if (assistant) {
                assistant.classList.add('hidden');
            }
        }

        updateSmartHelpContent(content) {
            const contentDiv = document.getElementById('smart-help-content');
            if (contentDiv) {
                contentDiv.innerHTML = content;
                
                // Attach action listeners
                contentDiv.querySelectorAll('.smart-help-action').forEach(button => {
                    button.addEventListener('click', (e) => {
                        const action = e.target.dataset.action;
                        this.executeSmartAction(action);
                    });
                });
            }
        }

        executeSmartAction(action) {
            switch (action) {
                case 'highlight-page-creation':
                    this.highlightElement('#newPageDisplayName', 'This is where you enter your page name');
                    setTimeout(() => {
                        this.highlightElement('#createUpdatePageBtn', 'Then click here to create the page');
                    }, 2000);
                    break;
                    
                case 'demo-ai-button':
                    this.demonstrateAIButton();
                    break;
                    
                case 'demo-drag-drop':
                    this.demonstrateDragDrop();
                    break;
            }
        }

        highlightElement(selector, message) {
            const element = document.querySelector(selector);
            if (element) {
                element.style.boxShadow = '0 0 20px 5px rgba(59, 130, 246, 0.5)';
                element.style.border = '3px solid #3b82f6';
                
                // Show tooltip
                const tooltip = document.createElement('div');
                tooltip.className = 'absolute bg-blue-600 text-white p-2 rounded text-sm z-50';
                tooltip.textContent = message;
                tooltip.style.top = element.offsetTop - 40 + 'px';
                tooltip.style.left = element.offsetLeft + 'px';
                document.body.appendChild(tooltip);
                
                setTimeout(() => {
                    element.style.boxShadow = '';
                    element.style.border = '';
                    if (tooltip.parentNode) {
                        tooltip.parentNode.removeChild(tooltip);
                    }
                }, 3000);
            }
        }

        demonstrateAIButton() {
            // Auto-fill example AI button
            const buttonText = document.getElementById('buttonText');
            const aiQuery = document.getElementById('llmQuery');
            
            if (buttonText && aiQuery) {
                buttonText.value = 'Help Ideas';
                aiQuery.value = 'Generate 3 polite ways to ask for assistance';
                
                this.updateSmartHelpContent(`
                    <div class="text-sm">
                        <p class="text-green-200">✨ I've filled in an example AI button for you!</p>
                        <p class="text-xs mt-2">This creates a button that generates different help requests each time it's pressed.</p>
                    </div>
                `);
            }
        }

        demonstrateDragDrop() {
            const buttons = document.querySelectorAll('.visual-button.has-content');
            if (buttons.length >= 2) {
                // Highlight first two buttons to show drag concept
                buttons[0].style.backgroundColor = '#fef3c7';
                buttons[1].style.backgroundColor = '#dcfce7';
                
                this.updateSmartHelpContent(`
                    <div class="text-sm">
                        <p class="text-green-200">🤏 See the highlighted buttons?</p>
                        <p class="text-xs mt-2">Click and drag the yellow one to swap places with the green one!</p>
                    </div>
                `);
                
                setTimeout(() => {
                    buttons[0].style.backgroundColor = '';
                    buttons[1].style.backgroundColor = '';
                }, 5000);
            }
        }

        loadUserPreferences() {
            // Load user's help preferences and skill level
            const savedLevel = localStorage.getItem('userSkillLevel');
            if (savedLevel) {
                this.userContext.skillLevel = savedLevel;
            }
        }

        // Enhanced methods for comprehensive guide integration
        setContext(context) {
            this.currentContext = context;
            this.updateBehaviorTriggers();
        }

        getContextualHelp(topic) {
            const helpContent = this.getHelpContent(topic);
            this.showSmartHelpDialog(helpContent);
        }

        getAdvancedTips() {
            const tips = this.generateAdvancedTips();
            this.showSmartHelpDialog(tips);
        }

        getPersonalizedRecommendations() {
            const recommendations = this.generatePersonalizedRecommendations();
            this.showSmartHelpDialog(recommendations);
        }

        celebrateCompletion() {
            this.showSuccessMessage('🎉 Congratulations! You\'ve completed the comprehensive guide!');
        }

        getHelpContent(topic) {
            const helpTopics = {
                creating_pages: {
                    title: "Creating Effective Pages",
                    content: `
                        <h4>🚀 Smart Tips for Page Creation:</h4>
                        <ul>
                            <li><strong>Start Simple:</strong> Begin with basic communication needs</li>
                            <li><strong>User-Centered:</strong> Consider your user's motor and cognitive abilities</li>
                            <li><strong>Visual Hierarchy:</strong> Use clear visual organization</li>
                            <li><strong>Test Early:</strong> Get user feedback during development</li>
                        </ul>
                        <div style="background: #e3f2fd; padding: 15px; border-radius: 8px; margin: 15px 0;">
                            <strong>💡 AI Suggestion:</strong> Based on common usage patterns, consider creating pages for:
                            Greetings, Basic Needs, Emotions, and Activities first.
                        </div>
                    `
                },
                button_design: {
                    title: "Button Design Best Practices",
                    content: `
                        <h4>🎨 Smart Design Principles:</h4>
                        <ul>
                            <li><strong>Size Matters:</strong> Ensure buttons are large enough for motor abilities</li>
                            <li><strong>Contrast:</strong> Use high contrast colors for visibility</li>
                            <li><strong>Consistency:</strong> Maintain consistent design patterns</li>
                            <li><strong>Feedback:</strong> Provide clear visual/audio feedback</li>
                        </ul>
                        <div style="background: #f3e5f5; padding: 15px; border-radius: 8px; margin: 15px 0;">
                            <strong>🤖 AI Insight:</strong> Users typically perform better with 6-12 buttons per page. 
                            Consider grouping related concepts together.
                        </div>
                    `
                },
                navigation_setup: {
                    title: "Navigation Configuration",
                    content: `
                        <h4>🧭 Smart Navigation Strategy:</h4>
                        <ul>
                            <li><strong>Breadcrumbs:</strong> Show users where they are</li>
                            <li><strong>Consistent Back Button:</strong> Always provide easy return paths</li>
                            <li><strong>Home Access:</strong> Quick access to main page</li>
                            <li><strong>Logical Flow:</strong> Design intuitive conversation paths</li>
                        </ul>
                        <div style="background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 15px 0;">
                            <strong>📊 Usage Data:</strong> Most successful AAC systems have 2-3 levels maximum 
                            in their navigation hierarchy.
                        </div>
                    `
                }
            };

            return helpTopics[topic] || {
                title: "Smart Help Available",
                content: "<p>I'm here to help! Ask me anything about page and button management.</p>"
            };
        }

        generateAdvancedTips() {
            return {
                title: "🚀 Advanced AAC Management Tips",
                content: `
                    <h4>Expert-Level Strategies:</h4>
                    <div style="background: linear-gradient(135deg, #667eea20, #764ba220); padding: 20px; border-radius: 10px; margin: 15px 0;">
                        <h5>🔍 Analytics-Driven Optimization:</h5>
                        <ul>
                            <li>Monitor button usage patterns to identify frequently used items</li>
                            <li>Move popular buttons to easier access positions</li>
                            <li>Remove or reorganize rarely used content</li>
                        </ul>
                    </div>
                    
                    <div style="background: linear-gradient(135deg, #ff9a9e20, #fecfef20); padding: 20px; border-radius: 10px; margin: 15px 0;">
                        <h5>⚡ Performance Optimization:</h5>
                        <ul>
                            <li>Use compressed images for faster loading</li>
                            <li>Implement progressive disclosure for complex pages</li>
                            <li>Cache frequently accessed content</li>
                        </ul>
                    </div>
                    
                    <div style="background: linear-gradient(135deg, #a8edea20, #fed6e320); padding: 20px; border-radius: 10px; margin: 15px 0;">
                        <h5>🎯 User Experience Enhancement:</h5>
                        <ul>
                            <li>Implement predictive text and smart suggestions</li>
                            <li>Create context-aware page recommendations</li>
                            <li>Use machine learning to adapt to user preferences</li>
                        </ul>
                    </div>
                `
            };
        }

        generatePersonalizedRecommendations() {
            // This would typically analyze user data, but for demo purposes:
            return {
                title: "🎯 Your Personalized Recommendations",
                content: `
                    <div style="background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 15px 0;">
                        <h4 style="margin-top: 0;">Based on your usage patterns:</h4>
                        
                        <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #28a745;">
                            <strong>📈 High Priority:</strong> Consider adding more emotion-related buttons - 
                            users often need to express feelings but this category seems underutilized.
                        </div>
                        
                        <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #ffc107;">
                            <strong>⚡ Quick Win:</strong> Your food category is popular but could benefit from 
                            subcategories (drinks, snacks, meals) for easier navigation.
                        </div>
                        
                        <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #17a2b8;">
                            <strong>🎯 Optimization:</strong> Consider moving your most-used buttons to the top-left 
                            position for easier access with the dominant hand.
                        </div>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.smartHelp.implementRecommendation('emotions')" 
                                style="background: #28a745; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px;">
                            ✅ Add Emotion Buttons
                        </button>
                        <button onclick="guideInstance.smartHelp.implementRecommendation('food_categories')" 
                                style="background: #ffc107; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px;">
                            📁 Organize Food Category
                        </button>
                    </div>
                `
            };
        }

        implementRecommendation(type) {
            switch(type) {
                case 'emotions':
                    this.showSuccessMessage('🎯 Great choice! Emotion buttons are essential for effective communication.');
                    break;
                case 'food_categories':
                    this.showSuccessMessage('📁 Excellent! Organized categories improve navigation speed.');
                    break;
                default:
                    this.showSuccessMessage('✅ Recommendation noted! Implementing smart suggestions...');
            }
        }

        showSmartHelpDialog(helpData) {
            // Create and show help dialog
            const dialog = document.createElement('div');
            dialog.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                width: 90%;
                max-width: 600px;
                background: white;
                border-radius: 15px;
                box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
                z-index: 20000;
                padding: 0;
                overflow: hidden;
            `;
            
            dialog.innerHTML = `
                <div style="background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 20px; text-align: center;">
                    <h3 style="margin: 0;">${helpData.title}</h3>
                </div>
                <div style="padding: 30px; max-height: 60vh; overflow-y: auto;">
                    ${helpData.content}
                </div>
                <div style="background: #f8f9fa; padding: 15px; text-align: right; border-top: 1px solid #e9ecef;">
                    <button onclick="this.parentElement.parentElement.remove()" 
                            style="background: #667eea; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">
                        Got it!
                    </button>
                </div>
            `;
            
            // Create backdrop
            const backdrop = document.createElement('div');
            backdrop.style.cssText = `
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                z-index: 19999;
            `;
            
            backdrop.addEventListener('click', () => {
                backdrop.remove();
                dialog.remove();
            });
            
            document.body.appendChild(backdrop);
            document.body.appendChild(dialog);
        }

        showSuccessMessage(message) {
            const successDiv = document.createElement('div');
            successDiv.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                background: linear-gradient(135deg, #28a745, #20c997);
                color: white;
                padding: 15px 25px;
                border-radius: 25px;
                z-index: 25000;
                font-weight: bold;
                box-shadow: 0 4px 15px rgba(40, 167, 69, 0.3);
                transform: translateX(100%);
                transition: transform 0.3s ease;
            `;
            successDiv.textContent = message;
            
            document.body.appendChild(successDiv);
            
            // Animate in
            setTimeout(() => successDiv.style.transform = 'translateX(0)', 100);
            
            // Remove after 3 seconds
            setTimeout(() => {
                successDiv.style.transform = 'translateX(100%)';
                setTimeout(() => successDiv.remove(), 300);
            }, 3000);
        }
    }

    // Multi-media Rich Content System
    class MultimediaHelpSystem {
        constructor() {
            this.videos = {
                'creating-pages': '/static/videos/creating-pages-demo.mp4',
                'button-setup': '/static/videos/button-setup-demo.mp4',
                'drag-drop': '/static/videos/drag-drop-demo.mp4',
                'ai-configuration': '/static/videos/ai-buttons-demo.mp4'
            };
            
            this.gifs = {
                'quick-button-create': '/static/images/quick-button-create.gif',
                'drag-drop-demo': '/static/images/drag-drop-demo.gif',
                'wizard-walkthrough': '/static/images/wizard-walkthrough.gif'
            };
            
            this.initializeMultimedia();
        }

        initializeMultimedia() {
            this.createMultimediaModal();
            this.setupVideoTriggers();
        }

        createMultimediaModal() {
            const modalHTML = `
                <div id="multimedia-help-modal" class="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50 hidden">
                    <div class="bg-white rounded-2xl shadow-2xl w-[90vw] h-[90vh] max-w-4xl flex flex-col">
                        <div class="flex justify-between items-center p-6 border-b">
                            <h2 class="text-2xl font-bold text-gray-800">📺 Video Tutorials</h2>
                            <button id="close-multimedia-modal" class="text-gray-500 hover:text-red-500 text-3xl">&times;</button>
                        </div>
                        <div class="flex-1 p-6">
                            <div id="multimedia-content" class="h-full">
                                <!-- Content will be loaded here -->
                            </div>
                        </div>
                        <div class="p-6 border-t bg-gray-50 rounded-b-2xl">
                            <div class="flex space-x-2">
                                <button class="multimedia-tab px-4 py-2 bg-blue-600 text-white rounded" data-tab="videos">📺 Videos</button>
                                <button class="multimedia-tab px-4 py-2 bg-gray-300 text-gray-700 rounded" data-tab="gifs">🎬 Quick Demos</button>
                                <button class="multimedia-tab px-4 py-2 bg-gray-300 text-gray-700 rounded" data-tab="interactive">🎮 Interactive</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;

            document.body.insertAdjacentHTML('beforeend', modalHTML);
            this.attachMultimediaListeners();
        }

        attachMultimediaListeners() {
            // Close modal
            document.getElementById('close-multimedia-modal').addEventListener('click', () => {
                this.hideMultimediaModal();
            });

            // Tab switching
            document.querySelectorAll('.multimedia-tab').forEach(tab => {
                tab.addEventListener('click', (e) => {
                    const tabType = e.target.dataset.tab;
                    this.switchMultimediaTab(tabType);
                    
                    // Update active tab styling
                    document.querySelectorAll('.multimedia-tab').forEach(t => {
                        t.className = 'multimedia-tab px-4 py-2 bg-gray-300 text-gray-700 rounded';
                    });
                    e.target.className = 'multimedia-tab px-4 py-2 bg-blue-600 text-white rounded';
                });
            });
        }

        setupVideoTriggers() {
            // Add video help buttons to existing guide steps
            document.addEventListener('click', (e) => {
                if (e.target.classList.contains('show-video-help')) {
                    const videoType = e.target.dataset.video;
                    this.showVideoHelp(videoType);
                }
            });
        }

        showMultimediaModal() {
            const modal = document.getElementById('multimedia-help-modal');
            if (modal) {
                modal.classList.remove('hidden');
                this.switchMultimediaTab('videos'); // Default to videos tab
            }
        }

        hideMultimediaModal() {
            const modal = document.getElementById('multimedia-help-modal');
            if (modal) {
                modal.classList.add('hidden');
            }
        }

        switchMultimediaTab(tabType) {
            const content = document.getElementById('multimedia-content');
            
            switch (tabType) {
                case 'videos':
                    content.innerHTML = this.generateVideoContent();
                    break;
                case 'gifs':
                    content.innerHTML = this.generateGifContent();
                    break;
                case 'interactive':
                    content.innerHTML = this.generateInteractiveContent();
                    break;
            }
        }

        generateVideoContent() {
            return `
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6 h-full">
                    <div class="video-item">
                        <h3 class="text-lg font-semibold mb-3">🆕 Creating Your First Page</h3>
                        <div class="video-placeholder bg-gray-200 rounded-lg h-48 flex items-center justify-center mb-3">
                            <div class="text-center">
                                <div class="text-4xl mb-2">🎬</div>
                                <p class="text-sm text-gray-600">3-minute tutorial on<br>page creation basics</p>
                                <button class="mt-2 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700" onclick="this.parentElement.innerHTML='<video controls class=w-full><source src=/static/videos/creating-pages-demo.mp4 type=video/mp4>Video not available</video>'">▶ Watch Now</button>
                            </div>
                        </div>
                        <p class="text-sm text-gray-600">Learn the fundamentals of creating and organizing communication pages.</p>
                    </div>
                    
                    <div class="video-item">
                        <h3 class="text-lg font-semibold mb-3">🎛️ Button Configuration Mastery</h3>
                        <div class="video-placeholder bg-gray-200 rounded-lg h-48 flex items-center justify-center mb-3">
                            <div class="text-center">
                                <div class="text-4xl mb-2">🎬</div>
                                <p class="text-sm text-gray-600">5-minute deep dive into<br>button setup options</p>
                                <button class="mt-2 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700" onclick="this.parentElement.innerHTML='<video controls class=w-full><source src=/static/videos/button-setup-demo.mp4 type=video/mp4>Video not available</video>'">▶ Watch Now</button>
                            </div>
                        </div>
                        <p class="text-sm text-gray-600">Master speech, navigation, and AI button configurations.</p>
                    </div>
                    
                    <div class="video-item">
                        <h3 class="text-lg font-semibold mb-3">🤏 Drag & Drop Layout Design</h3>
                        <div class="video-placeholder bg-gray-200 rounded-lg h-48 flex items-center justify-center mb-3">
                            <div class="text-center">
                                <div class="text-4xl mb-2">🎬</div>
                                <p class="text-sm text-gray-600">2-minute tutorial on<br>organizing your grid</p>
                                <button class="mt-2 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700" onclick="this.parentElement.innerHTML='<video controls class=w-full><source src=/static/videos/drag-drop-demo.mp4 type=video/mp4>Video not available</video>'">▶ Watch Now</button>
                            </div>
                        </div>
                        <p class="text-sm text-gray-600">Learn efficient techniques for arranging your button layout.</p>
                    </div>
                    
                    <div class="video-item">
                        <h3 class="text-lg font-semibold mb-3">🤖 AI-Powered Button Creation</h3>
                        <div class="video-placeholder bg-gray-200 rounded-lg h-48 flex items-center justify-center mb-3">
                            <div class="text-center">
                                <div class="text-4xl mb-2">🎬</div>
                                <p class="text-sm text-gray-600">4-minute guide to<br>intelligent buttons</p>
                                <button class="mt-2 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700" onclick="this.parentElement.innerHTML='<video controls class=w-full><source src=/static/videos/ai-configuration-demo.mp4 type=video/mp4>Video not available</video>'">▶ Watch Now</button>
                            </div>
                        </div>
                        <p class="text-sm text-gray-600">Create dynamic, context-aware communication with AI assistance.</p>
                    </div>
                </div>
            `;
        }

        generateGifContent() {
            return `
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4 h-full">
                    <div class="gif-item text-center">
                        <h4 class="font-semibold mb-2">⚡ Quick Button Creation</h4>
                        <div class="gif-placeholder bg-gradient-to-br from-blue-100 to-blue-200 rounded-lg h-32 flex items-center justify-center mb-2">
                            <div class="text-center">
                                <div class="text-2xl mb-1">🎬</div>
                                <button class="text-xs px-2 py-1 bg-blue-600 text-white rounded" onclick="this.parentElement.innerHTML='<img src=/static/images/quick-button-create.gif class=w-full h-32 object-cover rounded-lg>'">Load GIF</button>
                            </div>
                        </div>
                        <p class="text-xs text-gray-600">30-second button creation process</p>
                    </div>
                    
                    <div class="gif-item text-center">
                        <h4 class="font-semibold mb-2">🤏 Drag & Drop Demo</h4>
                        <div class="gif-placeholder bg-gradient-to-br from-green-100 to-green-200 rounded-lg h-32 flex items-center justify-center mb-2">
                            <div class="text-center">
                                <div class="text-2xl mb-1">🎬</div>
                                <button class="text-xs px-2 py-1 bg-green-600 text-white rounded" onclick="this.parentElement.innerHTML='<img src=/static/images/drag-drop-demo.gif class=w-full h-32 object-cover rounded-lg>'">Load GIF</button>
                            </div>
                        </div>
                        <p class="text-xs text-gray-600">See drag and drop in action</p>
                    </div>
                    
                    <div class="gif-item text-center">
                        <h4 class="font-semibold mb-2">🧙‍♂️ Wizard Walkthrough</h4>
                        <div class="gif-placeholder bg-gradient-to-br from-purple-100 to-purple-200 rounded-lg h-32 flex items-center justify-center mb-2">
                            <div class="text-center">
                                <div class="text-2xl mb-1">🎬</div>
                                <button class="text-xs px-2 py-1 bg-purple-600 text-white rounded" onclick="this.parentElement.innerHTML='<img src=/static/images/wizard-walkthrough.gif class=w-full h-32 object-cover rounded-lg>'">Load GIF</button>
                            </div>
                        </div>
                        <p class="text-xs text-gray-600">Complete wizard process</p>
                    </div>
                </div>
                
                <div class="mt-6 p-4 bg-gray-50 rounded-lg">
                    <h4 class="font-semibold mb-2">💡 Pro Tips</h4>
                    <ul class="text-sm space-y-1">
                        <li>• Right-click any button for quick actions</li>
                        <li>• Use Ctrl+Z to undo button moves</li>
                        <li>• Hold Shift while dragging to copy buttons</li>
                        <li>• Double-click empty slots for instant wizard</li>
                    </ul>
                </div>
            `;
        }

        generateInteractiveContent() {
            return `
                <div class="h-full flex flex-col">
                    <h3 class="text-xl font-semibold mb-4">🎮 Interactive Practice Mode</h3>
                    
                    <div class="flex-1 space-y-4">
                        <div class="practice-exercise bg-blue-50 p-4 rounded-lg">
                            <h4 class="font-semibold text-blue-800 mb-2">Exercise 1: Create a Greeting Button</h4>
                            <p class="text-sm text-blue-700 mb-3">Practice creating a simple "Hello" button with speech output.</p>
                            <button class="start-exercise px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700" data-exercise="greeting-button">
                                🚀 Start Practice
                            </button>
                        </div>
                        
                        <div class="practice-exercise bg-green-50 p-4 rounded-lg">
                            <h4 class="font-semibold text-green-800 mb-2">Exercise 2: Set Up AI Button</h4>
                            <p class="text-sm text-green-700 mb-3">Learn to create an AI-powered button that generates meal suggestions.</p>
                            <button class="start-exercise px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700" data-exercise="ai-button">
                                🤖 Start Practice
                            </button>
                        </div>
                        
                        <div class="practice-exercise bg-purple-50 p-4 rounded-lg">
                            <h4 class="font-semibold text-purple-800 mb-2">Exercise 3: Design a Page Layout</h4>
                            <p class="text-sm text-purple-700 mb-3">Practice organizing buttons for a "Morning Routine" page.</p>
                            <button class="start-exercise px-4 py-2 bg-purple-600 text-white rounded hover:bg-purple-700" data-exercise="page-layout">
                                🎨 Start Practice
                            </button>
                        </div>
                    </div>
                    
                    <div class="mt-4 p-3 bg-yellow-50 rounded-lg">
                        <div class="flex items-center">
                            <div class="text-yellow-600 mr-2">🏆</div>
                            <div>
                                <span class="font-semibold text-yellow-800">Practice Progress:</span>
                                <span class="text-yellow-700 ml-2" id="practice-progress">0/3 exercises completed</span>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        showVideoHelp(videoType) {
            this.showMultimediaModal();
            // Auto-play specific video if available
            // Implementation would depend on video management system
        }
    }

    // Initialize enhanced help systems
    let smartHelp, multimediaHelp;

    // Wait for InteractiveGuide to be available
    function initializeGuides() {
        // Register admin pages guides with InteractiveGuide system
        if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        
            // Pages Overview Tour
            InteractiveGuide.registerGuide('pages-overview', {
                title: '📄 Page & Button Management',
                description: 'Learn how to create and manage AAC communication pages and button layouts',
                steps: [
                    {
                        target: 'body',
                        title: '🎯 Welcome to Page Management',
                        content: `
                            <div class="guide-welcome">
                                <h3>📄 Page & Button Administration Center</h3>
                                <p>This powerful interface lets you design your AAC communication system:</p>
                                <ul>
                                    <li>📋 Create and organize communication pages</li>
                                    <li>🎛️ Design 10x10 button grids for each page</li>
                                    <li>🔧 Configure button actions and behaviors</li>
                                    <li>🤖 Set up AI-powered content generation</li>
                                    <li>🔄 Arrange buttons with drag & drop</li>
                                </ul>
                                <div class="multimedia-options mt-4 space-y-2">
                                    <button class="show-video-help w-full text-left text-sm bg-blue-100 p-2 rounded hover:bg-blue-200" data-video="overview">
                                        📺 Watch 2-minute overview video
                                    </button>
                                    <button class="ask-smart-help w-full text-left text-sm bg-purple-100 p-2 rounded hover:bg-purple-200" data-question="How do I get started with page management?">
                                        🤖 Ask Smart Help: "How do I get started?"
                                    </button>
                                </div>
                                <div class="tip">
                                    <strong>💡 Best Practice:</strong> Start with a few essential pages, then expand your communication system as needed.
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '#selectPage',
                        title: '📋 Page Selection',
                        content: `
                            <div class="guide-step">
                                <h4>Choose Your Communication Page</h4>
                                <p>Select which page to work with from your existing pages:</p>
                                <ul>
                                    <li>🏠 <strong>Home:</strong> Main landing page</li>
                                    <li>🍽️ <strong>Food pages:</strong> Meals and dining</li>
                                    <li>👥 <strong>Social pages:</strong> Conversations and interactions</li>
                                    <li>🎯 <strong>Custom pages:</strong> Your specialized topics</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Tip:</strong> Each page can hold up to 100 buttons in a 10x10 grid layout.
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#pageForm',
                        title: '📝 Page Management',
                        content: `
                            <div class="guide-step">
                                <h4>Create and Edit Pages</h4>
                                <p>Manage your communication pages with these tools:</p>
                                <ul>
                                    <li>➕ <strong>Create:</strong> Add new themed pages</li>
                                    <li>✏️ <strong>Update:</strong> Modify page names and settings</li>
                                    <li>🗑️ <strong>Delete:</strong> Remove unused pages</li>
                                    <li>↩️ <strong>Revert:</strong> Undo unsaved changes</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Naming:</strong> Use clear, descriptive names like "Morning Routine" or "Dinner Conversation"
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#buttonGrid',
                        title: '🎛️ Interactive Button Grid',
                        content: `
                            <div class="guide-step">
                                <h4>Design Your Communication Layout</h4>
                                <p>This 10x10 grid represents your page's button layout:</p>
                                <ul>
                                    <li>🖱️ <strong>Click:</strong> Edit any button's configuration</li>
                                    <li>🤏 <strong>Drag:</strong> Rearrange buttons by dragging</li>
                                    <li>🎨 <strong>Visual cues:</strong> Colors show button types</li>
                                    <li>💾 <strong>Auto-save:</strong> Changes save automatically</li>
                                </ul>
                                <div class="multimedia-options mt-4 space-y-2">
                                    <button class="show-video-help w-full text-left text-sm bg-blue-100 p-2 rounded hover:bg-blue-200" data-video="grid-interaction">
                                        📺 Watch grid interaction demo
                                    </button>
                                    <button class="show-gif-demo w-full text-left text-sm bg-green-100 p-2 rounded hover:bg-green-200" data-gif="drag-drop">
                                        🎬 See drag & drop in action
                                    </button>
                                </div>
                                <div class="legend">
                                    <h5>Button Color Legend:</h5>
                                    <ul>
                                        <li>🟢 <strong>Green:</strong> Regular speech buttons</li>
                                        <li>🟣 <strong>Purple:</strong> AI-powered buttons</li>
                                        <li>🟡 <strong>Yellow:</strong> Navigation buttons</li>
                                        <li>⚪ <strong>Dashed:</strong> Empty slots</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'top'
                    },
                    {
                        target: '#helpWizardBtn',
                        title: '🧙‍♂️ New Button Wizard',
                        content: `
                            <div class="guide-step">
                                <h4>Guided Button Creation</h4>
                                <p>The Button Wizard helps you create perfect buttons step by step:</p>
                                <ul>
                                    <li>📝 <strong>Step 1:</strong> Choose button text</li>
                                    <li>🗣️ <strong>Step 2:</strong> Set speech phrase</li>
                                    <li>🔄 <strong>Step 3:</strong> Configure page navigation</li>
                                    <li>🤖 <strong>Step 4:</strong> Add AI capabilities</li>
                                    <li>👁️ <strong>Preview:</strong> See your button before saving</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Perfect for beginners:</strong> The wizard ensures you don't miss any important settings!
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // Button Configuration Tour
            InteractiveGuide.registerGuide('button-setup', {
                title: '🎛️ Button Configuration',
                description: 'Master the art of creating powerful communication buttons',
                steps: [
                    {
                        target: 'body',
                        title: '🎛️ Button Configuration Mastery',
                        content: `
                            <div class="guide-welcome">
                                <h3>🎛️ Advanced Button Setup</h3>
                                <p>Learn to create sophisticated communication buttons:</p>
                                <ul>
                                    <li>💬 <strong>Speech buttons:</strong> Simple text-to-speech</li>
                                    <li>🔄 <strong>Navigation buttons:</strong> Move between pages</li>
                                    <li>🤖 <strong>AI buttons:</strong> Dynamic content generation</li>
                                    <li>🎭 <strong>Combo buttons:</strong> Multiple actions in sequence</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Pro Tip:</strong> Start simple, then add complexity as you become comfortable with the system.
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '#buttonGrid .visual-button:first-child',
                        title: '🖱️ Selecting Buttons',
                        content: `
                            <div class="guide-step">
                                <h4>Click Any Button to Edit</h4>
                                <p>The button editor opens when you click any grid position:</p>
                                <ul>
                                    <li>🎯 <strong>Empty slots:</strong> Create new buttons</li>
                                    <li>✏️ <strong>Existing buttons:</strong> Modify configuration</li>
                                    <li>🗑️ <strong>Clear buttons:</strong> Remove unwanted buttons</li>
                                    <li>📋 <strong>Copy settings:</strong> Duplicate successful configurations</li>
                                </ul>
                                <div class="tip">
                                    <strong>🖱️ Try it:</strong> Click this button to see the editor in action!
                                </div>
                            </div>
                        `,
                        position: 'right'
                    },
                    {
                        target: '#buttonText',
                        title: '📝 Button Text',
                        content: `
                            <div class="guide-step">
                                <h4>The Button's Display Text</h4>
                                <p>This text appears on the button and serves as its label:</p>
                                <ul>
                                    <li>📏 <strong>Keep it short:</strong> 1-3 words work best</li>
                                    <li>🎯 <strong>Be clear:</strong> Users should understand instantly</li>
                                    <li>🖼️ <strong>Visual space:</strong> Longer text may wrap or shrink</li>
                                    <li>🔤 <strong>Examples:</strong> "Hello", "More Food", "I need help"</li>
                                </ul>
                                <div class="tip">
                                    <strong>✨ Best Practice:</strong> Use action words and clear nouns for maximum clarity.
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#speechPhrase',
                        title: '🗣️ Speech Configuration',
                        content: `
                            <div class="guide-step">
                                <h4>What the Button Says</h4>
                                <p>Configure the spoken output when this button is pressed:</p>
                                <ul>
                                    <li>🔊 <strong>Primary speech:</strong> Main message to communicate</li>
                                    <li>🎭 <strong>Different from label:</strong> Can be longer than button text</li>
                                    <li>🌟 <strong>Natural language:</strong> Full sentences work great</li>
                                    <li>🔗 <strong>Combination:</strong> Works with other actions</li>
                                </ul>
                                <div class="examples">
                                    <h5>Examples:</h5>
                                    <ul>
                                        <li>Button: "Water" → Speech: "I would like some water please"</li>
                                        <li>Button: "Help" → Speech: "Can someone help me?"</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#targetPage',
                        title: '🔄 Page Navigation',
                        content: `
                            <div class="guide-step">
                                <h4>Navigate Between Pages</h4>
                                <p>Make buttons that move users to different communication pages:</p>
                                <ul>
                                    <li>🏠 <strong>Home button:</strong> Return to main page</li>
                                    <li>📂 <strong>Category pages:</strong> Food, activities, people</li>
                                    <li>🎯 <strong>Specific topics:</strong> Detailed conversation areas</li>
                                    <li>🔙 <strong>Back navigation:</strong> Return to previous page</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Navigation Strategy:</strong> Every page should have a way to get home and to related topics.
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#llmQuery',
                        title: '🤖 AI-Powered Buttons',
                        content: `
                            <div class="guide-step">
                                <h4>Dynamic Content Generation</h4>
                                <p>Create buttons that generate fresh content using AI:</p>
                                <ul>
                                    <li>🌟 <strong>Dynamic responses:</strong> Different answers each time</li>
                                    <li>🎯 <strong>Context-aware:</strong> Responses fit the situation</li>
                                    <li>📊 <strong>Multiple options:</strong> System uses #LLMOptions setting</li>
                                    <li>🧠 <strong>Smart prompts:</strong> Describe what you want naturally</li>
                                </ul>
                                <div class="examples">
                                    <h5>AI Query Examples:</h5>
                                    <ul>
                                        <li>"Suggest 3 healthy breakfast options"</li>
                                        <li>"Generate conversation starters for meeting new people"</li>
                                        <li>"Create polite ways to ask for help"</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#buttonPreview',
                        title: '👁️ Live Preview',
                        content: `
                            <div class="guide-step">
                                <h4>See Your Button Before Saving</h4>
                                <p>The preview shows exactly how your button will appear:</p>
                                <ul>
                                    <li>🎨 <strong>Visual style:</strong> Colors and borders</li>
                                    <li>📝 <strong>Text display:</strong> How text fits and wraps</li>
                                    <li>🔍 <strong>Type indicators:</strong> Icons for special functions</li>
                                    <li>⚡ <strong>Real-time:</strong> Updates as you type</li>
                                </ul>
                                <div class="tip">
                                    <strong>👀 Visual Check:</strong> Make sure the button looks clear and professional before saving!
                                </div>
                            </div>
                        `,
                        position: 'left'
                    }
                ]
            });

            // Drag and Drop Tour
            InteractiveGuide.registerGuide('grid-management', {
                title: '🤏 Grid Management',
                description: 'Learn to organize your button layout with drag and drop',
                steps: [
                    {
                        target: 'body',
                        title: '🤏 Grid Layout Mastery',
                        content: `
                            <div class="guide-welcome">
                                <h3>🎛️ Advanced Grid Management</h3>
                                <p>Organize your communication interface for maximum effectiveness:</p>
                                <ul>
                                    <li>🤏 <strong>Drag & Drop:</strong> Rearrange buttons intuitively</li>
                                    <li>📐 <strong>Strategic layout:</strong> Position frequently used buttons prominently</li>
                                    <li>🎨 <strong>Visual organization:</strong> Group related concepts</li>
                                    <li>♿ <strong>Accessibility:</strong> Consider reach and motor skills</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Layout Strategy:</strong> Place the most important buttons in easy-to-reach positions.
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '#buttonGrid',
                        title: '🤏 Drag and Drop Basics',
                        content: `
                            <div class="guide-step">
                                <h4>Rearrange Your Button Layout</h4>
                                <p>Moving buttons is simple and intuitive:</p>
                                <ul>
                                    <li>🖱️ <strong>Click and hold:</strong> Start dragging any button</li>
                                    <li>👁️ <strong>Visual feedback:</strong> Button tilts and becomes transparent</li>
                                    <li>🎯 <strong>Drop zones:</strong> Valid positions highlight in red</li>
                                    <li>✅ <strong>Release:</strong> Drop the button in its new position</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Pro Tip:</strong> You can move buttons to empty slots or swap positions with existing buttons!
                                </div>
                            </div>
                        `,
                        position: 'top'
                    },
                    {
                        target: '#saveButtonsBtn',
                        title: '💾 Saving Your Layout',
                        content: `
                            <div class="guide-step">
                                <h4>Preserve Your Perfect Layout</h4>
                                <p>Don't lose your hard work - save your button arrangements:</p>
                                <ul>
                                    <li>💾 <strong>Manual save:</strong> Click this button to save changes</li>
                                    <li>⚡ <strong>Auto-save:</strong> Some changes save automatically</li>
                                    <li>🔄 <strong>Sync status:</strong> Visual indicators show save state</li>
                                    <li>📱 <strong>Cross-device:</strong> Layouts sync across all devices</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Best Practice:</strong> Save frequently, especially after major layout changes!
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // AI Setup Tour
            InteractiveGuide.registerGuide('ai-setup', {
                title: '🤖 AI Button Setup',
                description: 'Create intelligent buttons that generate dynamic content',
                steps: [
                    {
                        target: 'body',
                        title: '🤖 AI-Powered Communication',
                        content: `
                            <div class="guide-welcome">
                                <h3>🤖 Intelligent Button Creation</h3>
                                <p>Harness AI to create dynamic, context-aware communication:</p>
                                <ul>
                                    <li>🧠 <strong>Smart generation:</strong> AI creates relevant responses</li>
                                    <li>🎯 <strong>Context awareness:</strong> Responses fit the situation</li>
                                    <li>🔄 <strong>Fresh content:</strong> Different options each time</li>
                                    <li>📊 <strong>Multiple choices:</strong> Generate several options to choose from</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Power Tip:</strong> AI buttons are perfect for situations that need variety and creativity!
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '#llmQuery',
                        title: '🧠 Writing AI Prompts',
                        content: `
                            <div class="guide-step">
                                <h4>Describe What You Want</h4>
                                <p>Write clear, natural descriptions of what the AI should generate:</p>
                                <ul>
                                    <li>🎯 <strong>Be specific:</strong> "Suggest healthy lunch options" vs "food ideas"</li>
                                    <li>📊 <strong>Set quantity:</strong> "3 ways to..." or "several options for..."</li>
                                    <li>🎭 <strong>Add context:</strong> "for a business meeting" or "for a child"</li>
                                    <li>🔤 <strong>Use examples:</strong> "like pizza, salad, or sandwiches"</li>
                                </ul>
                                <div class="examples">
                                    <h5>Great AI Prompts:</h5>
                                    <ul>
                                        <li>"Generate 3 polite ways to decline an invitation"</li>
                                        <li>"Suggest conversation topics for meeting neighbors"</li>
                                        <li>"Create responses for thanking healthcare workers"</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#configSummary',
                        title: '📊 Understanding AI Settings',
                        content: `
                            <div class="guide-step">
                                <h4>How AI Buttons Work</h4>
                                <p>The system uses your global settings to control AI behavior:</p>
                                <ul>
                                    <li>🔢 <strong>#LLMOptions:</strong> Controls how many choices to generate</li>
                                    <li>🎯 <strong>Context aware:</strong> AI knows what page and button this is</li>
                                    <li>🔄 <strong>Dynamic content:</strong> Fresh responses every time</li>
                                    <li>⚡ <strong>Smart caching:</strong> Fast responses for common requests</li>
                                </ul>
                                <div class="tip">
                                    <strong>⚙️ Settings Tip:</strong> Adjust #LLMOptions in Global Settings to control how many AI choices you get!
                                </div>
                            </div>
                        `,
                        position: 'left'
                    }
                ]
            });

            // Wizard Tour
            InteractiveGuide.registerGuide('wizard-walkthrough', {
                title: '🧙‍♂️ Button Wizard',
                description: 'Step-by-step guided button creation for beginners',
                steps: [
                    {
                        target: 'body',
                        title: '🧙‍♂️ The Button Creation Wizard',
                        content: `
                            <div class="guide-welcome">
                                <h3>🧙‍♂️ Guided Button Creation</h3>
                                <p>Perfect for beginners - the wizard guides you through every step:</p>
                                <ul>
                                    <li>📝 <strong>Step-by-step:</strong> No overwhelming options</li>
                                    <li>💡 <strong>Helpful hints:</strong> Tips for each decision</li>
                                    <li>👁️ <strong>Live preview:</strong> See results as you build</li>
                                    <li>🎯 <strong>Best practices:</strong> Built-in recommendations</li>
                                </ul>
                                <div class="tip">
                                    <strong>🌟 Perfect for:</strong> First-time users, complex buttons, or when you want guidance!
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '#helpWizardBtn',
                        title: '🚀 Starting the Wizard',
                        content: `
                            <div class="guide-step">
                                <h4>Launch the Guided Experience</h4>
                                <p>Click this button to start the step-by-step button creation process:</p>
                                <ul>
                                    <li>🎯 <strong>Clear steps:</strong> One decision at a time</li>
                                    <li>↩️ <strong>Go back:</strong> Change previous decisions anytime</li>
                                    <li>👁️ <strong>Preview mode:</strong> See your button before finalizing</li>
                                    <li>✅ <strong>Accept/Reject:</strong> Final approval before saving</li>
                                </ul>
                                <div class="tip">
                                    <strong>🧙‍♂️ Wizard Magic:</strong> Even experienced users love the wizard for complex buttons!
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#wizardButtonName',
                        title: '📝 Step 1: Button Name',
                        content: `
                            <div class="guide-step">
                                <h4>What Should the Button Say?</h4>
                                <p>The wizard's first step focuses on the button's display text:</p>
                                <ul>
                                    <li>🎯 <strong>Primary purpose:</strong> What's the main message?</li>
                                    <li>📏 <strong>Length matters:</strong> Shorter text displays better</li>
                                    <li>👁️ <strong>Visual appeal:</strong> Clear, readable text</li>
                                    <li>🎭 <strong>User-friendly:</strong> Language that makes sense to users</li>
                                </ul>
                                <div class="examples">
                                    <h5>Good Button Names:</h5>
                                    <ul>
                                        <li>"Good Morning" (friendly greeting)</li>
                                        <li>"I'm Hungry" (clear need)</li>
                                        <li>"More Please" (polite request)</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#wizardSpeechPhrase',
                        title: '🗣️ Step 2: Speech Output',
                        content: `
                            <div class="guide-step">
                                <h4>What Should It Say Aloud?</h4>
                                <p>Configure the spoken message when the button is pressed:</p>
                                <ul>
                                    <li>🔊 <strong>Spoken version:</strong> Can be longer than button text</li>
                                    <li>🎭 <strong>Natural speech:</strong> Full sentences work great</li>
                                    <li>📢 <strong>Clear communication:</strong> Express the full intent</li>
                                    <li>🎯 <strong>Context appropriate:</strong> Match the situation</li>
                                </ul>
                                <div class="examples">
                                    <h5>Button vs Speech Examples:</h5>
                                    <ul>
                                        <li>Button: "Water" → Speech: "I would like some water, please"</li>
                                        <li>Button: "Bathroom" → Speech: "I need to use the restroom"</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#wizardTargetPage',
                        title: '🔄 Step 3: Page Navigation',
                        content: `
                            <div class="guide-step">
                                <h4>Should It Go Somewhere?</h4>
                                <p>Decide if pressing this button should navigate to another page:</p>
                                <ul>
                                    <li>🏠 <strong>Stay put:</strong> Just speak and remain on current page</li>
                                    <li>📂 <strong>Category jump:</strong> Move to a related topic page</li>
                                    <li>🎯 <strong>Specific page:</strong> Navigate to a particular area</li>
                                    <li>🔄 <strong>Smart flow:</strong> Create logical conversation paths</li>
                                </ul>
                                <div class="tip">
                                    <strong>🎯 Navigation Strategy:</strong> Navigation buttons help users explore topics in depth!
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#wizardAiDescription',
                        title: '🤖 Step 4: AI Enhancement',
                        content: `
                            <div class="guide-step">
                                <h4>Add Intelligence?</h4>
                                <p>The final step lets you add AI-powered dynamic content:</p>
                                <ul>
                                    <li>🧠 <strong>Smart generation:</strong> AI creates relevant options</li>
                                    <li>🔄 <strong>Always fresh:</strong> Different content each time</li>
                                    <li>📊 <strong>Multiple choices:</strong> Several options to pick from</li>
                                    <li>🎯 <strong>Context aware:</strong> AI knows the situation</li>
                                </ul>
                                <div class="examples">
                                    <h5>AI Enhancement Ideas:</h5>
                                    <ul>
                                        <li>"Generate conversation starters for new people"</li>
                                        <li>"Suggest activities for a rainy day"</li>
                                        <li>"Create polite ways to end a conversation"</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#wizardButtonPreview',
                        title: '👁️ Final Preview',
                        content: `
                            <div class="guide-step">
                                <h4>See Your Creation</h4>
                                <p>The wizard shows you exactly what you've created:</p>
                                <ul>
                                    <li>🎨 <strong>Visual preview:</strong> How the button will look</li>
                                    <li>📋 <strong>Configuration summary:</strong> All settings at a glance</li>
                                    <li>✅ <strong>Accept/Reject:</strong> Final approval before saving</li>
                                    <li>🔄 <strong>Easy changes:</strong> Go back to modify anything</li>
                                </ul>
                                <div class="tip">
                                    <strong>✨ Quality Check:</strong> Make sure everything looks perfect before accepting!
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            console.log('Admin Pages interactive guides registered successfully');
            
            // Initialize Smart Help and Multimedia systems
            smartHelp = new SmartHelpSystem();
            multimediaHelp = new MultimediaHelpSystem();
            
            // Add enhanced event handlers
            setupEnhancedHelpHandlers();
            
        } else {
            // Retry after a short delay if InteractiveGuide isn't ready yet
            setTimeout(initializeGuides, 100);
        }
    }

    // Enhanced help event handlers
    function setupEnhancedHelpHandlers() {
        // Smart Help integration
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('ask-smart-help')) {
                const question = e.target.dataset.question;
                if (smartHelp) {
                    smartHelp.showSmartHelp();
                    smartHelp.handleSmartHelpQuestion(question);
                }
            }
            
            if (e.target.classList.contains('show-video-help')) {
                const videoType = e.target.dataset.video;
                if (multimediaHelp) {
                    multimediaHelp.showVideoHelp(videoType);
                }
            }
            
            if (e.target.classList.contains('show-gif-demo')) {
                const gifType = e.target.dataset.gif;
                if (multimediaHelp) {
                    multimediaHelp.showMultimediaModal();
                    multimediaHelp.switchMultimediaTab('gifs');
                }
            }
            
            if (e.target.classList.contains('start-exercise')) {
                const exerciseType = e.target.dataset.exercise;
                startPracticeExercise(exerciseType);
            }
        });

        // Auto-show smart help for new users
        if (!localStorage.getItem('hasSeenAdminPagesHelp')) {
            setTimeout(() => {
                if (smartHelp) {
                    smartHelp.showSmartHelp();
                    localStorage.setItem('hasSeenAdminPagesHelp', 'true');
                }
            }, 3000);
        }
    }

    // Practice exercise system
    function startPracticeExercise(exerciseType) {
        const exercises = {
            'greeting-button': () => {
                // Highlight button grid
                smartHelp.highlightElement('#buttonGrid .visual-button:first-child', 'Click here to start creating your greeting button');
                
                // Pre-fill helpful values after click
                setTimeout(() => {
                    const buttonText = document.getElementById('buttonText');
                    const speechPhrase = document.getElementById('speechPhrase');
                    if (buttonText && speechPhrase) {
                        buttonText.value = 'Hello';
                        speechPhrase.value = 'Hello! How are you today?';
                        smartHelp.updateSmartHelpContent(`
                            <div class="text-sm">
                                <p class="text-green-200">✨ Perfect! I've filled in some example text.</p>
                                <p class="text-xs mt-2">Now click "Save Button" to complete the exercise.</p>
                            </div>
                        `);
                    }
                }, 1000);
            },
            
            'ai-button': () => {
                smartHelp.highlightElement('#buttonGrid .visual-button:nth-child(2)', 'Click here to create an AI-powered button');
                
                setTimeout(() => {
                    const buttonText = document.getElementById('buttonText');
                    const llmQuery = document.getElementById('llmQuery');
                    if (buttonText && llmQuery) {
                        buttonText.value = 'Meal Ideas';
                        llmQuery.value = 'Suggest 3 healthy meal options for lunch';
                        smartHelp.updateSmartHelpContent(`
                            <div class="text-sm">
                                <p class="text-green-200">🤖 Excellent! This button will generate different meal suggestions each time.</p>
                                <p class="text-xs mt-2">Save this button to complete the AI exercise.</p>
                            </div>
                        `);
                    }
                }, 1000);
            },
            
            'page-layout': () => {
                multimediaHelp.showMultimediaModal();
                multimediaHelp.switchMultimediaTab('interactive');
                smartHelp.updateSmartHelpContent(`
                    <div class="text-sm">
                        <p class="text-blue-200">🎨 Layout exercise started!</p>
                        <p class="text-xs mt-2">Follow the interactive tutorial in the multimedia window.</p>
                    </div>
                `);
            }
        };

        if (exercises[exerciseType]) {
            exercises[exerciseType]();
        }
    }

    // Initialize guides when the page loads
    initializeGuides();

    // Set up help button integration
    const helpButton = document.getElementById('help-icon');
    if (helpButton) {
        helpButton.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            
            // Show enhanced help menu
            if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.showGuideMenu) {
                InteractiveGuide.showGuideMenu();
            } else if (multimediaHelp) {
                // Fallback to multimedia help if interactive guide isn't available
                multimediaHelp.showMultimediaModal();
            }
        });

        // Add context menu for advanced help options
        helpButton.addEventListener('contextmenu', function(e) {
            e.preventDefault();
            showAdvancedHelpMenu(e.clientX, e.clientY);
        });
    }

    // Advanced help context menu
    function showAdvancedHelpMenu(x, y) {
        const menu = document.createElement('div');
        menu.className = 'fixed bg-white shadow-lg rounded-lg p-2 z-50 border';
        menu.style.left = x + 'px';
        menu.style.top = y + 'px';
        menu.innerHTML = `
            <div class="space-y-1">
                <button class="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 rounded" onclick="smartHelp.showSmartHelp()">🤖 Smart Help Assistant</button>
                <button class="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 rounded" onclick="multimediaHelp.showMultimediaModal()">📺 Video Tutorials</button>
                <button class="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 rounded" onclick="InteractiveGuide.showGuideMenu()">📋 Step-by-Step Guides</button>
                <hr class="my-1">
                <button class="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 rounded text-red-600" onclick="localStorage.clear(); location.reload()">🔄 Reset All Help Data</button>
            </div>
        `;
        
        document.body.appendChild(menu);
        
        // Remove menu when clicking elsewhere
        setTimeout(() => {
            document.addEventListener('click', function removeMenu() {
                if (menu.parentNode) {
                    menu.parentNode.removeChild(menu);
                }
                document.removeEventListener('click', removeMenu);
            });
        }, 100);
    // Enhanced methods for comprehensive guide integration
    setContext(context) {
        this.currentContext = context;
        this.updateBehaviorTriggers();
    }

    getContextualHelp(topic) {
        const helpContent = this.getHelpContent(topic);
        this.showSmartHelpDialog(helpContent);
    }

    getAdvancedTips() {
        const tips = this.generateAdvancedTips();
        this.showSmartHelpDialog(tips);
    }

    getPersonalizedRecommendations() {
        const recommendations = this.generatePersonalizedRecommendations();
        this.showSmartHelpDialog(recommendations);
    }

    celebrateCompletion() {
        this.showSuccessMessage('🎉 Congratulations! You\'ve completed the comprehensive guide!');
    }

    getHelpContent(topic) {
        const helpTopics = {
            creating_pages: {
                title: "Creating Effective Pages",
                content: `
                    <h4>🚀 Smart Tips for Page Creation:</h4>
                    <ul>
                        <li><strong>Start Simple:</strong> Begin with basic communication needs</li>
                        <li><strong>User-Centered:</strong> Consider your user's motor and cognitive abilities</li>
                        <li><strong>Visual Hierarchy:</strong> Use clear visual organization</li>
                        <li><strong>Test Early:</strong> Get user feedback during development</li>
                    </ul>
                    <div style="background: #e3f2fd; padding: 15px; border-radius: 8px; margin: 15px 0;">
                        <strong>💡 AI Suggestion:</strong> Based on common usage patterns, consider creating pages for:
                        Greetings, Basic Needs, Emotions, and Activities first.
                    </div>
                `
            },
            button_design: {
                title: "Button Design Best Practices",
                content: `
                    <h4>🎨 Smart Design Principles:</h4>
                    <ul>
                        <li><strong>Size Matters:</strong> Ensure buttons are large enough for motor abilities</li>
                        <li><strong>Contrast:</strong> Use high contrast colors for visibility</li>
                        <li><strong>Consistency:</strong> Maintain consistent design patterns</li>
                        <li><strong>Feedback:</strong> Provide clear visual/audio feedback</li>
                    </ul>
                    <div style="background: #f3e5f5; padding: 15px; border-radius: 8px; margin: 15px 0;">
                        <strong>🤖 AI Insight:</strong> Users typically perform better with 6-12 buttons per page. 
                        Consider grouping related concepts together.
                    </div>
                `
            },
            navigation_setup: {
                title: "Navigation Configuration",
                content: `
                    <h4>🧭 Smart Navigation Strategy:</h4>
                    <ul>
                        <li><strong>Breadcrumbs:</strong> Show users where they are</li>
                        <li><strong>Consistent Back Button:</strong> Always provide easy return paths</li>
                        <li><strong>Home Access:</strong> Quick access to main page</li>
                        <li><strong>Logical Flow:</strong> Design intuitive conversation paths</li>
                    </ul>
                    <div style="background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 15px 0;">
                        <strong>📊 Usage Data:</strong> Most successful AAC systems have 2-3 levels maximum 
                        in their navigation hierarchy.
                    </div>
                `
            }
        };

        return helpTopics[topic] || {
            title: "Smart Help Available",
            content: "<p>I'm here to help! Ask me anything about page and button management.</p>"
        };
    }

    generateAdvancedTips() {
        return {
            title: "🚀 Advanced AAC Management Tips",
            content: `
                <h4>Expert-Level Strategies:</h4>
                <div style="background: linear-gradient(135deg, #667eea20, #764ba220); padding: 20px; border-radius: 10px; margin: 15px 0;">
                    <h5>🔍 Analytics-Driven Optimization:</h5>
                    <ul>
                        <li>Monitor button usage patterns to identify frequently used items</li>
                        <li>Move popular buttons to easier access positions</li>
                        <li>Remove or reorganize rarely used content</li>
                    </ul>
                </div>
                
                <div style="background: linear-gradient(135deg, #ff9a9e20, #fecfef20); padding: 20px; border-radius: 10px; margin: 15px 0;">
                    <h5>⚡ Performance Optimization:</h5>
                    <ul>
                        <li>Use compressed images for faster loading</li>
                        <li>Implement progressive disclosure for complex pages</li>
                        <li>Cache frequently accessed content</li>
                    </ul>
                </div>
                
                <div style="background: linear-gradient(135deg, #a8edea20, #fed6e320); padding: 20px; border-radius: 10px; margin: 15px 0;">
                    <h5>🎯 User Experience Enhancement:</h5>
                    <ul>
                        <li>Implement predictive text and smart suggestions</li>
                        <li>Create context-aware page recommendations</li>
                        <li>Use machine learning to adapt to user preferences</li>
                    </ul>
                </div>
            `
        };
    }

    generatePersonalizedRecommendations() {
        // This would typically analyze user data, but for demo purposes:
        return {
            title: "🎯 Your Personalized Recommendations",
            content: `
                <div style="background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 15px 0;">
                    <h4 style="margin-top: 0;">Based on your usage patterns:</h4>
                    
                    <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #28a745;">
                        <strong>📈 High Priority:</strong> Consider adding more emotion-related buttons - 
                        users often need to express feelings but this category seems underutilized.
                    </div>
                    
                    <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #ffc107;">
                        <strong>⚡ Quick Win:</strong> Your food category is popular but could benefit from 
                        subcategories (drinks, snacks, meals) for easier navigation.
                    </div>
                    
                    <div style="background: white; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #17a2b8;">
                        <strong>🎯 Optimization:</strong> Consider moving your most-used buttons to the top-left 
                        position for easier access with the dominant hand.
                    </div>
                </div>
                
                <div style="text-align: center; margin: 20px 0;">
                    <button onclick="guideInstance.smartHelp.implementRecommendation('emotions')" 
                            style="background: #28a745; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px;">
                        ✅ Add Emotion Buttons
                    </button>
                    <button onclick="guideInstance.smartHelp.implementRecommendation('food_categories')" 
                            style="background: #ffc107; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px;">
                        📁 Organize Food Category
                    </button>
                </div>
            `
        };
    }

    implementRecommendation(type) {
        switch(type) {
            case 'emotions':
                this.showSuccessMessage('🎯 Great choice! Emotion buttons are essential for effective communication.');
                break;
            case 'food_categories':
                this.showSuccessMessage('📁 Excellent! Organized categories improve navigation speed.');
                break;
            default:
                this.showSuccessMessage('✅ Recommendation noted! Implementing smart suggestions...');
        }
    }

    showSmartHelpDialog(helpData) {
        // Create and show help dialog
        const dialog = document.createElement('div');
        dialog.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 90%;
            max-width: 600px;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
            z-index: 20000;
            padding: 0;
            overflow: hidden;
        `;
        
        dialog.innerHTML = `
            <div style="background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 20px; text-align: center;">
                <h3 style="margin: 0;">${helpData.title}</h3>
            </div>
            <div style="padding: 30px; max-height: 60vh; overflow-y: auto;">
                ${helpData.content}
            </div>
            <div style="background: #f8f9fa; padding: 15px; text-align: right; border-top: 1px solid #e9ecef;">
                <button onclick="this.parentElement.parentElement.remove()" 
                        style="background: #667eea; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">
                    Got it!
                </button>
            </div>
        `;
        
        // Create backdrop
        const backdrop = document.createElement('div');
        backdrop.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            z-index: 19999;
        `;
        
        backdrop.addEventListener('click', () => {
            backdrop.remove();
            dialog.remove();
        });
        
        document.body.appendChild(backdrop);
        document.body.appendChild(dialog);
    }

    showSuccessMessage(message) {
        const successDiv = document.createElement('div');
        successDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            padding: 15px 25px;
            border-radius: 25px;
            z-index: 25000;
            font-weight: bold;
            box-shadow: 0 4px 15px rgba(40, 167, 69, 0.3);
            transform: translateX(100%);
            transition: transform 0.3s ease;
        `;
        successDiv.textContent = message;
        
        document.body.appendChild(successDiv);
        
        // Animate in
        setTimeout(() => successDiv.style.transform = 'translateX(0)', 100);
        
        // Remove after 3 seconds
        setTimeout(() => {
            successDiv.style.transform = 'translateX(100%)';
            setTimeout(() => successDiv.remove(), 300);
        }, 3000);
    });
