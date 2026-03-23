// Admin Pages Interactive Guide System
// Comprehensive guided tours with Smart Help and Multi-media Rich features

// Smart Help AI System - Global class definition
class SmartHelpSystem {
    constructor() {
        this.helpHistory = [];
        this.userContext = {
            currentPage: 'admin_pages',
            skillLevel: 'beginner', // beginner, intermediate, advanced
            commonQuestions: [],
            strugglingWith: []
        };
        this.initialized = false;
    }

    async initialize() {
        if (this.initialized) return;
        this.initialized = true;
        
        // Create smart help UI
        this.createSmartHelpUI();
        this.attachEventListeners();
        this.loadUserPreferences();
    }
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
            const contentEl = document.getElementById('smart-help-content');
            if (contentEl) {
                contentEl.innerHTML = content;
            }
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

        async generateSmartResponse(question) {
            // Simple keyword-based responses for demo
            const lowerQuestion = question.toLowerCase();
            
            if (lowerQuestion.includes('create') && lowerQuestion.includes('page')) {
                return `
                    <div class="text-sm space-y-2">
                        <p><strong>🆕 Creating a New Page:</strong></p>
                        <ol class="text-xs space-y-1">
                            <li>1. Enter a name in "Display Name" field</li>
                            <li>2. Click "Create/Update Page" button</li>
                            <li>3. Your new page appears in the dropdown</li>
                        </ol>
                    </div>
                `;
            }
            
            if (lowerQuestion.includes('ai') && lowerQuestion.includes('button')) {
                return `
                    <div class="text-sm space-y-2">
                        <p><strong>🤖 AI Button Setup:</strong></p>
                        <ol class="text-xs space-y-1">
                            <li>1. Click any empty grid slot</li>
                            <li>2. Add button text (what it shows)</li>
                            <li>3. In "AI Query" field, describe what you want</li>
                        </ol>
                    </div>
                `;
            }
            
            return `
                <div class="text-sm">
                    <p>I understand you're asking about: "${question}"</p>
                    <p class="mt-2 text-xs">Try these common actions or ask me something more specific!</p>
                </div>
            `;
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
                        <button onclick="window.smartHelpInstance.implementRecommendation('emotions')" 
                                style="background: #28a745; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px;">
                            ✅ Add Emotion Buttons
                        </button>
                        <button onclick="window.smartHelpInstance.implementRecommendation('food_categories')" 
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
                'interface_overview': '/static/videos/interface-overview.mp4',
                'create_page_tutorial': '/static/videos/create-page-tutorial.mp4',
                'button_design_tutorial': '/static/videos/button-design-tutorial.mp4',
                'navigation_setup': '/static/videos/navigation-setup.mp4',
                'organization_strategies': '/static/videos/organization-strategies.mp4',
                'advanced_features': '/static/videos/advanced-features.mp4'
            };
            
            this.gifs = {
                'button_design_demo': '/static/images/button-design-demo.gif',
                'category_setup_demo': '/static/images/category-setup-demo.gif'
            };
            
            this.practiceExercises = {
                'navigation': this.createNavigationExercise
            };

            this.initializeMultimedia();
        }

        initializeMultimedia() {
            this.createMultimediaModal();
        }

        createMultimediaModal() {
            const modalHTML = `
                <div id="multimedia-modal" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 30000; align-items: center; justify-content: center;">
                    <div style="background: white; border-radius: 15px; max-width: 90%; max-height: 90%; overflow: hidden;">
                        <div style="background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 20px; display: flex; justify-content: space-between; align-items: center;">
                            <h3 style="margin: 0;">📹 Multimedia Help Center</h3>
                            <button id="close-multimedia-modal" style="background: none; border: none; color: white; font-size: 24px; cursor: pointer;">×</button>
                        </div>
                        <div id="multimedia-content" style="padding: 30px; min-height: 400px;">
                            <!-- Dynamic content -->
                        </div>
                    </div>
                </div>
            `;
            
            document.body.insertAdjacentHTML('beforeend', modalHTML);
            this.attachMultimediaListeners();
        }

        attachMultimediaListeners() {
            const closeBtn = document.getElementById('close-multimedia-modal');
            if (closeBtn) {
                closeBtn.addEventListener('click', () => this.hideMultimediaModal());
            }

            const modal = document.getElementById('multimedia-modal');
            if (modal) {
                modal.addEventListener('click', (e) => {
                    if (e.target === modal) {
                        this.hideMultimediaModal();
                    }
                });
            }
        }

        showVideo(videoKey) {
            const videoUrl = this.videos[videoKey];
            if (!videoUrl) {
                this.showVideoPlaceholder(videoKey);
                return;
            }

            const content = `
                <div style="text-align: center;">
                    <h4>📹 ${this.getVideoTitle(videoKey)}</h4>
                    <video controls style="width: 100%; max-width: 640px; border-radius: 10px;">
                        <source src="${videoUrl}" type="video/mp4">
                        Your browser does not support the video tag.
                    </video>
                    <p style="margin-top: 15px; color: #6c757d;">
                        This video tutorial will guide you through the process step by step.
                    </p>
                </div>
            `;

            this.updateMultimediaContent(content);
            this.showMultimediaModal();
        }

        showVideoPlaceholder(videoKey) {
            const content = `
                <div style="text-align: center; padding: 40px;">
                    <div style="font-size: 64px; margin-bottom: 20px;">🎬</div>
                    <h4>${this.getVideoTitle(videoKey)}</h4>
                    <div style="background: #f8f9fa; padding: 30px; border-radius: 10px; margin: 20px 0;">
                        <p style="color: #6c757d; margin-bottom: 15px;">
                            This video tutorial is being prepared and will be available soon!
                        </p>
                        <p style="color: #495057; font-weight: bold;">
                            In the meantime, here's what this video will cover:
                        </p>
                        <ul style="text-align: left; color: #6c757d; margin: 15px 0;">
                            ${this.getVideoDescription(videoKey)}
                        </ul>
                    </div>
                    <button onclick="window.multimediaInstance.hideMultimediaModal()" 
                            style="background: #667eea; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold;">
                        Got it! 📚
                    </button>
                </div>
            `;

            this.updateMultimediaContent(content);
            this.showMultimediaModal();
        }

        showGif(gifKey) {
            const gifUrl = this.gifs[gifKey];
            if (!gifUrl) {
                this.showGifPlaceholder(gifKey);
                return;
            }

            const content = `
                <div style="text-align: center;">
                    <h4>🎞️ ${this.getGifTitle(gifKey)}</h4>
                    <img src="${gifUrl}" alt="${this.getGifTitle(gifKey)}" style="max-width: 100%; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.1);">
                    <p style="margin-top: 15px; color: #6c757d;">
                        This quick demonstration shows the process in action.
                    </p>
                </div>
            `;

            this.updateMultimediaContent(content);
            this.showMultimediaModal();
        }

        showGifPlaceholder(gifKey) {
            const content = `
                <div style="text-align: center; padding: 40px;">
                    <div style="font-size: 64px; margin-bottom: 20px;">🎞️</div>
                    <h4>${this.getGifTitle(gifKey)}</h4>
                    <div style="background: #f8f9fa; padding: 30px; border-radius: 10px; margin: 20px 0;">
                        <p style="color: #6c757d; margin-bottom: 15px;">
                            This animated demonstration is being created and will be available soon!
                        </p>
                        <p style="color: #495057; font-weight: bold;">
                            This demo will show:
                        </p>
                        <ul style="text-align: left; color: #6c757d; margin: 15px 0;">
                            ${this.getGifDescription(gifKey)}
                        </ul>
                    </div>
                    <button onclick="window.multimediaInstance.hideMultimediaModal()" 
                            style="background: #5f27cd; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold;">
                        Understood! ✨
                    </button>
                </div>
            `;

            this.updateMultimediaContent(content);
            this.showMultimediaModal();
        }

        startPracticeExercise(exerciseKey) {
            if (this.practiceExercises[exerciseKey]) {
                const exercise = this.practiceExercises[exerciseKey].call(this);
                this.updateMultimediaContent(exercise);
                this.showMultimediaModal();
            }
        }

        createNavigationExercise() {
            return `
                <div style="text-align: center; padding: 20px;">
                    <h4>🎯 Navigation Practice Exercise</h4>
                    <div style="background: #e3f2fd; padding: 20px; border-radius: 10px; margin: 20px 0;">
                        <h5 style="margin-top: 0;">Interactive Practice Scenario:</h5>
                        <p style="text-align: left; color: #495057;">
                            You're setting up an AAC system for a user who needs to communicate about daily activities. 
                            Practice creating a logical navigation flow:
                        </p>
                        <div style="background: white; padding: 15px; border-radius: 8px; margin: 15px 0; text-align: left;">
                            <strong>🏠 Main Page</strong> → Should contain:<br>
                            • Basic greetings<br>
                            • Navigation to activity categories<br>
                            • Emergency/help buttons<br><br>
                            
                            <strong>🍽️ Meals Page</strong> → Should link to:<br>
                            • Breakfast options<br>
                            • Lunch options<br>
                            • Dinner options<br>
                            • Back to main page<br><br>
                            
                            <strong>🎮 Activities Page</strong> → Should include:<br>
                            • Indoor activities<br>
                            • Outdoor activities<br>
                            • Social activities<br>
                            • Back to main page
                        </div>
                    </div>
                    <div style="display: flex; gap: 10px; justify-content: center; margin-top: 20px;">
                        <button onclick="window.multimediaInstance.hideMultimediaModal()" 
                                style="background: #28a745; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold;">
                            🚀 Start Practice
                        </button>
                        <button onclick="window.multimediaInstance.hideMultimediaModal()" 
                                style="background: #6c757d; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer;">
                            Maybe Later
                        </button>
                    </div>
                </div>
            `;
        }

        getVideoTitle(key) {
            const titles = {
                'interface_overview': 'Admin Interface Overview',
                'create_page_tutorial': 'Creating Your First Page',
                'button_design_tutorial': 'Button Design Masterclass',
                'navigation_setup': 'Navigation Setup Guide',
                'organization_strategies': 'Content Organization Strategies',
                'advanced_features': 'Advanced Features Tutorial'
            };
            return titles[key] || 'Tutorial Video';
        }

        getVideoDescription(key) {
            const descriptions = {
                'interface_overview': '<li>Main interface components</li><li>Navigation between sections</li><li>Key controls and buttons</li><li>Settings and preferences</li>',
                'create_page_tutorial': '<li>Step-by-step page creation</li><li>Naming conventions</li><li>Page organization</li><li>Best practices</li>',
                'button_design_tutorial': '<li>Visual design principles</li><li>Accessibility considerations</li><li>Color and contrast</li><li>Testing your designs</li>',
                'navigation_setup': '<li>Creating page hierarchies</li><li>Navigation button placement</li><li>User flow optimization</li><li>Testing navigation paths</li>',
                'organization_strategies': '<li>Category-based organization</li><li>Frequency-based layouts</li><li>User-centered design</li><li>Maintenance strategies</li>',
                'advanced_features': '<li>AI button configuration</li><li>Custom behaviors</li><li>Analytics and optimization</li><li>Troubleshooting tips</li>'
            };
            return descriptions[key] || '<li>Comprehensive tutorial content</li>';
        }

        getGifTitle(key) {
            const titles = {
                'button_design_demo': 'Button Design in Action',
                'category_setup_demo': 'Category Setup Demo'
            };
            return titles[key] || 'Quick Demo';
        }

        getGifDescription(key) {
            const descriptions = {
                'button_design_demo': '<li>Real-time button creation</li><li>Design tool usage</li><li>Preview and testing</li>',
                'category_setup_demo': '<li>Category creation workflow</li><li>Organization methods</li><li>Best practice examples</li>'
            };
            return descriptions[key] || '<li>Step-by-step demonstration</li>';
        }

        showMultimediaModal() {
            const modal = document.getElementById('multimedia-modal');
            if (modal) {
                modal.style.display = 'flex';
            }
        }

        hideMultimediaModal() {
            const modal = document.getElementById('multimedia-modal');
            if (modal) {
                modal.style.display = 'none';
            }
        }

        updateMultimediaContent(content) {
            const contentEl = document.getElementById('multimedia-content');
            if (contentEl) {
                contentEl.innerHTML = content;
            }
        }
    }

    // Initialize systems
    const smartHelp = new SmartHelpSystem();
    const multimedia = new MultimediaHelpSystem();

    // Make available globally for comprehensive guide
    window.smartHelpInstance = smartHelp;
    window.multimediaInstance = multimedia;

    // Create enhanced help button that uses both systems
    const enhancedHelpButton = document.createElement('button');
    enhancedHelpButton.innerHTML = '🤖 Smart Help';
    enhancedHelpButton.style.cssText = `
        position: fixed;
        bottom: 20px;
        right: 20px;
        z-index: 10000;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border: none;
        padding: 15px 25px;
        border-radius: 30px;
        cursor: pointer;
        font-size: 16px;
        font-weight: bold;
        box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        transition: all 0.3s ease;
    `;
    
    enhancedHelpButton.addEventListener('mouseenter', () => {
        enhancedHelpButton.style.transform = 'translateY(-3px)';
        enhancedHelpButton.style.boxShadow = '0 6px 20px rgba(102, 126, 234, 0.6)';
    });
    
    enhancedHelpButton.addEventListener('mouseleave', () => {
        enhancedHelpButton.style.transform = 'translateY(0)';
        enhancedHelpButton.style.boxShadow = '0 4px 15px rgba(102, 126, 234, 0.4)';
    });
    
    enhancedHelpButton.addEventListener('click', () => {
        smartHelp.showSmartHelp();
    });
    
    document.body.appendChild(enhancedHelpButton);
});
