/**
 * Comprehensive Interactive Guide for Admin Pages
 * Combines structured tour, Smart Help AI, and multimedia content
 */

class AdminPagesComprehensiveGuide {
    constructor() {
        this.currentStep = 0;
        this.isActive = false;
        this.smartHelp = null; // Will be initialized later
        this.multimedia = null; // Will be initialized later
        this.overlay = null;
        this.guidePanel = null;
        this.userProgress = this.loadProgress();
        
        // Initialize the guide system when dependencies are ready
        this.initializeWhenReady();
    }

    initializeWhenReady() {
        // Wait for SmartHelpSystem and MultimediaHelpSystem to be available
        let retryCount = 0;
        const maxRetries = 100; // 10 seconds max wait time
        
        const checkDependencies = () => {
            console.log(`Checking dependencies, attempt ${retryCount + 1}`);
            
            if (typeof SmartHelpSystem !== 'undefined' && typeof MultimediaHelpSystem !== 'undefined') {
                console.log('Dependencies found, initializing comprehensive guide...');
                try {
                    this.smartHelp = new SmartHelpSystem();
                    this.multimedia = new MultimediaHelpSystem();
                    this.initializeGuide();
                    console.log('Comprehensive guide initialized successfully');
                } catch (error) {
                    console.error('Error initializing comprehensive guide:', error);
                }
            } else {
                retryCount++;
                if (retryCount < maxRetries) {
                    console.log(`Dependencies not ready (SmartHelpSystem: ${typeof SmartHelpSystem}, MultimediaHelpSystem: ${typeof MultimediaHelpSystem}), retrying...`);
                    setTimeout(checkDependencies, 100);
                } else {
                    console.error('Failed to initialize comprehensive guide after maximum retries');
                }
            }
        };
        
        // Start checking immediately, but also wait for DOMContentLoaded if needed
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', checkDependencies);
        } else {
            checkDependencies();
        }
    }

    initializeGuide() {
        console.log('Initializing comprehensive guide...');
        
        // Note: Using existing help button instead of creating new one
        // this.createHelpButton();
        
        // Create guide overlay and panel
        this.createGuideOverlay();
        this.createGuidePanel();
        
        // Initialize Smart Help and Multimedia systems
        this.smartHelp.initialize();
        this.multimedia.initialize();
        
        // Add event listeners
        this.addEventListeners();
        
        console.log('Comprehensive guide initialization complete');
    }

    createHelpButton() {
        // Using existing help button in admin_pages.html instead of creating new one
        return;
        
        /* Original button creation code commented out
        const helpButton = document.createElement('button');
        helpButton.id = 'comprehensive-help-btn';
        helpButton.innerHTML = '🎯 Comprehensive Guide';
        helpButton.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 10000;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 20px;
            border-radius: 25px;
            cursor: pointer;
            font-size: 14px;
            font-weight: bold;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
            transition: all 0.3s ease;
        `;
        
        helpButton.addEventListener('mouseenter', () => {
            helpButton.style.transform = 'translateY(-2px)';
            helpButton.style.boxShadow = '0 6px 20px rgba(102, 126, 234, 0.6)';
        });
        
        helpButton.addEventListener('mouseleave', () => {
            helpButton.style.transform = 'translateY(0)';
            helpButton.style.boxShadow = '0 4px 15px rgba(102, 126, 234, 0.4)';
        });
        
        helpButton.addEventListener('click', () => this.startComprehensiveGuide());
        
        document.body.appendChild(helpButton);
        */
    }

    createGuideOverlay() {
        this.overlay = document.createElement('div');
        this.overlay.id = 'comprehensive-guide-overlay';
        this.overlay.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.7);
            z-index: 15000;
            display: none;
            backdrop-filter: blur(3px);
        `;
        document.body.appendChild(this.overlay);
    }

    createGuidePanel() {
        this.guidePanel = document.createElement('div');
        this.guidePanel.id = 'comprehensive-guide-panel';
        this.guidePanel.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 90%;
            max-width: 800px;
            max-height: 90vh;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
            z-index: 15001;
            display: none;
            overflow: hidden;
        `;
        
        this.guidePanel.innerHTML = `
            <div id="guide-header" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; text-align: center;">
                <h2 style="margin: 0; font-size: 24px;">Admin Pages - Comprehensive Guide</h2>
                <p style="margin: 10px 0 0 0; opacity: 0.9;">Master page and button management with guided tours and AI assistance</p>
            </div>
            
            <div id="guide-content" style="padding: 30px; overflow-y: auto; max-height: 60vh;">
                <!-- Dynamic content will be loaded here -->
            </div>
            
            <div id="guide-footer" style="background: #f8f9fa; padding: 20px; display: flex; justify-content: space-between; align-items: center; border-top: 1px solid #e9ecef;">
                <div id="guide-progress" style="display: flex; align-items: center;">
                    <div id="progress-bar" style="width: 200px; height: 8px; background: #e9ecef; border-radius: 4px; margin-right: 15px;">
                        <div id="progress-fill" style="height: 100%; background: linear-gradient(90deg, #667eea, #764ba2); border-radius: 4px; width: 0%; transition: width 0.3s ease;"></div>
                    </div>
                    <span id="progress-text" style="font-size: 14px; color: #6c757d;">Step 0 of 0</span>
                </div>
                
                <div id="guide-controls" style="display: flex; gap: 10px;">
                    <button id="guide-prev" style="background: #6c757d; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">Previous</button>
                    <button id="guide-next" style="background: #667eea; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">Next</button>
                    <button id="guide-close" style="background: #dc3545; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">Close</button>
                </div>
            </div>
        `;
        
        document.body.appendChild(this.guidePanel);
    }

    getGuideSteps() {
        return [
            {
                title: "Welcome to Admin Pages",
                type: "overview",
                content: `
                    <div style="text-align: center; margin-bottom: 30px;">
                        <div style="font-size: 48px; margin-bottom: 20px;">🎯</div>
                        <h3>Master Page and Button Management</h3>
                        <p style="font-size: 16px; color: #6c757d; line-height: 1.6;">
                            This comprehensive guide will walk you through every aspect of managing pages and buttons 
                            in your AAC system. You'll learn to create, edit, organize, and optimize your communication 
                            interface with confidence.
                        </p>
                    </div>
                    
                    <div style="background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 20px 0;">
                        <h4 style="color: #495057; margin-top: 0;">What You'll Learn:</h4>
                        <ul style="color: #6c757d; line-height: 1.8;">
                            <li><strong>Page Management:</strong> Create, edit, and organize communication pages</li>
                            <li><strong>Button Configuration:</strong> Design effective communication buttons</li>
                            <li><strong>Navigation Setup:</strong> Build intuitive page-to-page navigation</li>
                            <li><strong>Content Organization:</strong> Structure your AAC system for maximum usability</li>
                            <li><strong>Advanced Features:</strong> Utilize smart suggestions and AI assistance</li>
                        </ul>
                    </div>
                    
                    <div style="background: linear-gradient(135deg, #667eea20, #764ba220); padding: 20px; border-radius: 10px; border-left: 4px solid #667eea;">
                        <h4 style="color: #495057; margin-top: 0;">🤖 AI-Powered Assistance</h4>
                        <p style="color: #6c757d; margin-bottom: 0;">
                            Throughout this guide, you can access Smart Help AI for contextual assistance, 
                            personalized suggestions, and instant answers to your questions.
                        </p>
                    </div>
                `,
                smartHelpContext: "admin_pages_overview",
                videos: []
            },
            {
                title: "Understanding the Interface",
                type: "interface_tour",
                target: "body",
                content: `
                    <h3>📱 Admin Pages Interface Overview</h3>
                    <p>Let's explore the main components of the admin pages interface:</p>
                    
                    <div style="margin: 20px 0;">
                        <div style="background: #e3f2fd; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>🗂️ Page Management Section</strong><br>
                            <span style="color: #666;">Create, edit, and organize your communication pages</span>
                        </div>
                        <div style="background: #f3e5f5; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>🔘 Button Management Section</strong><br>
                            <span style="color: #666;">Design and configure individual communication buttons</span>
                        </div>
                        <div style="background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>🔄 Navigation Tools</strong><br>
                            <span style="color: #666;">Set up page-to-page navigation and workflows</span>
                        </div>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.multimedia.showVideo('interface_overview')" 
                                style="background: #ff4757; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold;">
                            📹 Watch Interface Overview Video
                        </button>
                    </div>
                `,
                smartHelpContext: "interface_overview",
                videos: ["interface_overview"]
            },
            {
                title: "Creating Your First Page",
                type: "hands_on",
                target: ".create-page-btn, [data-action='create-page']",
                content: `
                    <h3>📄 Creating Communication Pages</h3>
                    <p>Pages are the foundation of your AAC system. Let's create your first page step by step.</p>
                    
                    <div style="background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #ffc107;">
                        <strong>💡 Pro Tip:</strong> Start with simple, frequently-used communication topics before creating complex pages.
                    </div>
                    
                    <h4>Step-by-Step Process:</h4>
                    <ol style="line-height: 1.8;">
                        <li>Click the "Create New Page" button (highlighted below)</li>
                        <li>Choose a descriptive page name</li>
                        <li><strong>Note:</strong> Page names can be changed later if needed</li>
                        <li><strong>After creation:</strong> A blank grid will be available for adding buttons</li>
                        <li><strong>Remember to save:</strong> Click the save button after making changes</li>
                    </ol>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.multimedia.showVideo('create_page_tutorial')" 
                                style="background: #ff4757; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            📹 Watch Page Creation Tutorial
                        </button>
                        <button onclick="guideInstance.smartHelp.getContextualHelp('creating_pages')" 
                                style="background: #2f3542; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            🤖 Get Smart Help
                        </button>
                    </div>
                `,
                smartHelpContext: "creating_pages",
                videos: ["create_page_tutorial"],
                highlightTarget: ".create-page-btn, [data-action='create-page'], button[onclick*='createPage'], .add-page-button"
            },
            {
                title: "Button Design Guide",
                type: "hands_on", 
                target: ".create-button-btn, [data-action='create-button']",
                content: `
                    <h3>🔘 Complete Button Design Guide</h3>
                    <p>Buttons are the core communication elements of your AAC system. Master button design to create effective communication tools.</p>
                    
                    <div style="background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #28a745;">
                        <strong>� Button Functions:</strong>
                        <ul style="margin: 10px 0;">
                            <li><strong>Navigation Buttons:</strong> Move to another page</li>
                            <li><strong>Communication Buttons:</strong> Express thoughts, needs, or ideas</li>
                        </ul>
                    </div>
                    
                    <h4>📝 Communication Button Types:</h4>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin: 15px 0;">
                        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; border: 2px solid #007bff;">
                            <strong>🔒 Static Buttons</strong>
                            <p style="font-size: 14px; margin: 10px 0;">Always say the same predefined message</p>
                            <ul style="font-size: 13px;">
                                <li>Consistent output</li>
                                <li>Reliable communication</li>
                                <li>Perfect for routine phrases</li>
                            </ul>
                        </div>
                        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; border: 2px solid #ff6b6b;">
                            <strong>🤖 Dynamic Buttons</strong>
                            <p style="font-size: 14px; margin: 10px 0;">Use AI to generate contextual responses</p>
                            <ul style="font-size: 13px;">
                                <li>Adaptive communication</li>
                                <li>Context-aware responses</li>
                                <li>Flexible interaction</li>
                            </ul>
                        </div>
                    </div>
                    
                    <h4>🛠️ Button Creation Methods:</h4>
                    <div style="margin: 15px 0;">
                        <div style="background: #fff3cd; padding: 12px; border-radius: 6px; margin: 8px 0;">
                            <strong>✋ Manual Creation:</strong> Design each button individually with full customization control
                        </div>
                        <div style="background: #d1ecf1; padding: 12px; border-radius: 6px; margin: 8px 0;">
                            <strong>🪄 Wizard Creation:</strong> Use guided setup for quick, standardized button creation
                        </div>
                    </div>
                    
                    <h4>🎛️ Button Properties Guide:</h4>
                    <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;">
                        <strong>Essential Properties:</strong>
                        <ul style="margin: 10px 0; line-height: 1.6;">
                            <li><strong>Label Text:</strong> The text displayed on the button</li>
                            <li><strong>Speech Output:</strong> What the device will say when pressed</li>
                            <li><strong>Target Page:</strong> Which page to navigate to (if navigation button)</li>
                            <li><strong>AI Query:</strong> Dynamic content generation prompt (if dynamic button)</li>
                            <li><strong>Hidden:</strong> Checkbox to hide the button from the user interface</li>
                        </ul>
                    </div>
                    
                    <h4>🎨 System Colors & Indicators:</h4>
                    <p style="margin: 10px 0; font-size: 14px;">The system automatically assigns colors and indicators based on button function:</p>
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin: 15px 0;">
                        <div style="background: linear-gradient(135deg, #ddd6fe 0%, #e0e7ff 100%); border: 2px solid #7c3aed; padding: 15px; border-radius: 8px;">
                            <strong>🤖 AI Buttons (Purple)</strong><br>
                            <small>Contains AI Query for dynamic responses</small><br>
                            <div style="margin-top: 8px; background: #7c3aed; color: white; width: 16px; height: 16px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-size: 10px;">AI</div>
                            <small style="margin-left: 8px;">Purple indicator with "AI"</small>
                        </div>
                        <div style="background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%); border: 2px solid #d97706; padding: 15px; border-radius: 8px;">
                            <strong>🧭 Navigation Buttons (Orange)</strong><br>
                            <small>Links to another page</small><br>
                            <div style="margin-top: 8px; background: #d97706; color: white; width: 16px; height: 16px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-size: 10px;">→</div>
                            <small style="margin-left: 8px;">Orange indicator with arrow</small>
                        </div>
                        <div style="background: linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%); border: 2px solid #059669; padding: 15px; border-radius: 8px;">
                            <strong>�️ Speech Buttons (Green)</strong><br>
                            <small>Has custom speech phrase</small><br>
                            <div style="margin-top: 8px; background: #059669; color: white; width: 16px; height: 16px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-size: 10px;">♪</div>
                            <small style="margin-left: 8px;">Green indicator with music note</small>
                        </div>
                        <div style="background: #f3f4f6; border: 2px solid #9ca3af; padding: 15px; border-radius: 8px; opacity: 0.7;">
                            <strong>🫥 Hidden Buttons (Faded)</strong><br>
                            <small>Not visible to users, admin-only</small><br>
                            <small style="margin-top: 8px; color: #6b7280;">Appears faded with reduced opacity</small>
                        </div>
                    </div>
                    
                    <div style="background: #ffe6e6; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #ff4757;">
                        <strong>🎯 Drag & Drop Arrangement:</strong>
                        <p style="margin: 10px 0; font-size: 14px;">Buttons can be dragged and dropped to change their arrangement on the grid. Organize frequently used buttons in easily accessible positions.</p>
                    </div>
                    
                    <div style="background: #ff6b6b; color: white; padding: 15px; border-radius: 8px; margin: 15px 0; text-align: center;">
                        <strong>💾 IMPORTANT: Always click the SAVE button after making any changes!</strong>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.multimedia.showVideo('button_design_tutorial')" 
                                style="background: #ff4757; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            📹 Watch Button Design Tutorial
                        </button>
                        <button onclick="guideInstance.smartHelp.getContextualHelp('button_design')" 
                                style="background: #2f3542; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            🤖 Get Smart Help
                        </button>
                    </div>
                `,
                smartHelpContext: "button_design",
                videos: ["button_design_tutorial"],
                highlightTarget: ".create-button-btn, [data-action='create-button'], button[onclick*='createButton'], .add-button"
            },
            {
                title: "Setting Up Navigation",
                type: "hands_on",
                target: ".navigation-settings, [data-section='navigation']",
                content: `
                    <h3>🧭 Page Navigation Configuration</h3>
                    <p>Effective navigation helps users move smoothly between different communication contexts.</p>
                    
                    <div style="background: #d4edda; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #28a745;">
                        <strong>🗺️ Navigation Best Practices:</strong>
                        <ul style="margin: 10px 0;">
                            <li>Create logical page hierarchies</li>
                            <li>Provide easy "back" and "home" options</li>
                            <li>Use consistent navigation patterns</li>
                            <li>Test navigation with actual users</li>
                        </ul>
                    </div>
                    
                    <h4>Navigation Types:</h4>
                    <div style="margin: 15px 0;">
                        <div style="background: #fff; border: 1px solid #dee2e6; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>📂 Category Navigation</strong><br>
                            <span style="color: #666; font-size: 14px;">Organize pages by communication topics (food, activities, feelings, etc.)</span>
                        </div>
                        <div style="background: #fff; border: 1px solid #dee2e6; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>🔄 Contextual Navigation</strong><br>
                            <span style="color: #666; font-size: 14px;">Link related pages based on conversation flow</span>
                        </div>
                        <div style="background: #fff; border: 1px solid #dee2e6; padding: 15px; border-radius: 8px; margin: 10px 0;">
                            <strong>⭐ Quick Access</strong><br>
                            <span style="color: #666; font-size: 14px;">Create shortcuts to frequently used pages</span>
                        </div>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.multimedia.showVideo('navigation_setup')" 
                                style="background: #ff4757; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            📹 Navigation Setup Tutorial
                        </button>
                        <button onclick="guideInstance.startPracticeExercise('navigation')" 
                                style="background: #00d2d3; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            🎯 Practice Exercise
                        </button>
                    </div>
                `,
                smartHelpContext: "navigation_setup",
                videos: ["navigation_setup"],
                practiceExercise: "navigation",
                highlightTarget: ".navigation-settings, [data-section='navigation'], .nav-config"
            },
            {
                title: "Organization and Categories",
                type: "organizational",
                content: `
                    <h3>📋 Content Organization Strategies</h3>
                    <p>Proper organization makes your AAC system more efficient and user-friendly.</p>
                    
                    <div style="background: #f8d7da; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #dc3545;">
                        <strong>⚠️ Common Organization Mistakes:</strong>
                        <ul style="margin: 10px 0;">
                            <li>Too many buttons on one page</li>
                            <li>Inconsistent categorization</li>
                            <li>Poor visual hierarchy</li>
                            <li>Missing search functionality</li>
                        </ul>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.multimedia.showVideo('organization_strategies')" 
                                style="background: #ff4757; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            📹 Organization Strategies
                        </button>
                        <button onclick="guideInstance.multimedia.showGif('category_setup_demo')" 
                                style="background: #5f27cd; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            🎞️ Category Setup Demo
                        </button>
                    </div>
                `,
                smartHelpContext: "content_organization",
                videos: ["organization_strategies"],
                gifs: ["category_setup_demo"]
            },
            {
                title: "Completion & Next Steps",
                type: "completion",
                content: `
                    <div style="text-align: center; margin-bottom: 30px;">
                        <div style="font-size: 48px; margin-bottom: 20px;">🎉</div>
                        <h3>Congratulations! You've Mastered Admin Pages</h3>
                        <p style="font-size: 16px; color: #6c757d; line-height: 1.6;">
                            You now have the knowledge and tools to create effective AAC communication systems.
                        </p>
                    </div>
                    
                    <div style="background: linear-gradient(135deg, #667eea20, #764ba220); padding: 25px; border-radius: 15px; margin: 20px 0;">
                        <h4 style="color: #495057; margin-top: 0;">📚 What You've Learned:</h4>
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                            <div>
                                <ul style="color: #6c757d; line-height: 1.8;">
                                    <li>✅ Page creation and management</li>
                                    <li>✅ Button design principles</li>
                                    <li>✅ Navigation configuration</li>
                                </ul>
                            </div>
                            <div>
                                <ul style="color: #6c757d; line-height: 1.8;">
                                    <li>✅ Content organization strategies</li>
                                    <li>✅ System navigation setup</li>
                                    <li>✅ AI-powered assistance tools</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                    
                    <div style="background: #d1ecf1; padding: 20px; border-radius: 10px; margin: 20px 0; border-left: 4px solid #17a2b8;">
                        <h4 style="color: #495057; margin-top: 0;">🚀 Next Steps:</h4>
                        <ol style="color: #6c757d; line-height: 1.8;">
                            <li>Start creating your first communication pages</li>
                            <li>Test your configurations with users</li>
                            <li>Use Smart Help for ongoing assistance</li>
                            <li>Explore other admin tools and settings</li>
                        </ol>
                    </div>
                    
                    <div style="text-align: center; margin: 20px 0;">
                        <button onclick="guideInstance.smartHelp.getPersonalizedRecommendations()" 
                                style="background: #2f3542; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            🤖 Get Personalized Recommendations
                        </button>
                        <button onclick="guideInstance.downloadGuideReference()" 
                                style="background: #28a745; color: white; border: none; padding: 12px 24px; border-radius: 25px; cursor: pointer; font-weight: bold; margin: 5px;">
                            📄 Download Reference Guide
                        </button>
                    </div>
                    
                    <div style="text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #e9ecef;">
                        <p style="color: #6c757d; font-size: 14px;">
                            Need help? Smart Help AI is always available by clicking the 🤖 button or asking questions in any admin section.
                        </p>
                    </div>
                `,
                smartHelpContext: "completion_next_steps"
            }
        ];
    }

    startComprehensiveGuide() {
        // Check if the guide is fully initialized
        if (!this.smartHelp || !this.multimedia) {
            console.warn('Guide system not fully initialized yet, please try again in a moment');
            return;
        }
        
        this.currentStep = 0;
        this.isActive = true;
        this.overlay.style.display = 'block';
        this.guidePanel.style.display = 'block';
        this.showCurrentStep();
        this.saveProgress();
        
        // Initialize Smart Help context
        this.smartHelp.setContext('comprehensive_guide_started');
    }

    showCurrentStep() {
        const steps = this.getGuideSteps();
        const step = steps[this.currentStep];
        
        if (!step) return;
        
        // Update content
        const contentEl = document.getElementById('guide-content');
        contentEl.innerHTML = step.content;
        
        // Update progress
        const progressFill = document.getElementById('progress-fill');
        const progressText = document.getElementById('progress-text');
        const progress = ((this.currentStep + 1) / steps.length) * 100;
        
        progressFill.style.width = `${progress}%`;
        progressText.textContent = `Step ${this.currentStep + 1} of ${steps.length}`;
        
        // Update controls
        const prevBtn = document.getElementById('guide-prev');
        const nextBtn = document.getElementById('guide-next');
        
        prevBtn.disabled = this.currentStep === 0;
        nextBtn.textContent = this.currentStep === steps.length - 1 ? 'Complete' : 'Next';
        
        // Highlight target if specified
        this.clearHighlights();
        if (step.highlightTarget) {
            this.highlightElement(step.highlightTarget);
        }
        
        // Set Smart Help context
        if (step.smartHelpContext) {
            this.smartHelp.setContext(step.smartHelpContext);
        }
        
        // Auto-scroll to top of content
        contentEl.scrollTop = 0;
        
        this.saveProgress();
    }

    highlightElement(selector) {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
            if (el) {
                el.style.outline = '3px solid #667eea';
                el.style.outlineOffset = '4px';
                el.style.borderRadius = '8px';
                el.style.position = 'relative';
                el.style.zIndex = '14999';
                
                // Add pulsing animation
                const pulse = document.createElement('div');
                pulse.className = 'guide-pulse-animation';
                pulse.style.cssText = `
                    position: absolute;
                    top: -10px;
                    left: -10px;
                    right: -10px;
                    bottom: -10px;
                    border: 2px solid #667eea;
                    border-radius: 12px;
                    animation: guidePulse 2s infinite;
                    pointer-events: none;
                    z-index: 14998;
                `;
                
                el.style.position = 'relative';
                el.appendChild(pulse);
            }
        });
        
        // Add CSS animation if not exists
        if (!document.getElementById('guide-pulse-styles')) {
            const styles = document.createElement('style');
            styles.id = 'guide-pulse-styles';
            styles.textContent = `
                @keyframes guidePulse {
                    0% { opacity: 1; transform: scale(1); }
                    50% { opacity: 0.5; transform: scale(1.05); }
                    100% { opacity: 1; transform: scale(1); }
                }
            `;
            document.head.appendChild(styles);
        }
    }

    clearHighlights() {
        // Remove outlines
        document.querySelectorAll('[style*="outline"]').forEach(el => {
            el.style.outline = '';
            el.style.outlineOffset = '';
        });
        
        // Remove pulse animations
        document.querySelectorAll('.guide-pulse-animation').forEach(el => {
            el.remove();
        });
    }

    addEventListeners() {
        // Navigation controls
        document.getElementById('guide-prev').addEventListener('click', () => {
            if (this.currentStep > 0) {
                this.currentStep--;
                this.showCurrentStep();
            }
        });
        
        document.getElementById('guide-next').addEventListener('click', () => {
            const steps = this.getGuideSteps();
            if (this.currentStep < steps.length - 1) {
                this.currentStep++;
                this.showCurrentStep();
            } else {
                this.completeGuide();
            }
        });
        
        document.getElementById('guide-close').addEventListener('click', () => {
            this.closeGuide();
        });
        
        // Close on overlay click
        this.overlay.addEventListener('click', (e) => {
            if (e.target === this.overlay) {
                this.closeGuide();
            }
        });
        
        // Keyboard navigation
        document.addEventListener('keydown', (e) => {
            if (!this.isActive) return;
            
            if (e.key === 'Escape') {
                this.closeGuide();
            } else if (e.key === 'ArrowLeft' && this.currentStep > 0) {
                this.currentStep--;
                this.showCurrentStep();
            } else if (e.key === 'ArrowRight') {
                const steps = this.getGuideSteps();
                if (this.currentStep < steps.length - 1) {
                    this.currentStep++;
                    this.showCurrentStep();
                } else {
                    this.completeGuide();
                }
            }
        });
    }

    closeGuide() {
        this.isActive = false;
        this.overlay.style.display = 'none';
        this.guidePanel.style.display = 'none';
        this.clearHighlights();
        this.saveProgress();
    }

    completeGuide() {
        this.userProgress.completed = true;
        this.userProgress.completedAt = new Date().toISOString();
        this.saveProgress();
        
        // Show completion celebration
        this.smartHelp.celebrateCompletion();
        
        // Close after a moment
        setTimeout(() => {
            this.closeGuide();
        }, 2000);
    }

    startPracticeExercise(type) {
        this.multimedia.startPracticeExercise(type);
    }

    downloadGuideReference() {
        // Create downloadable reference guide
        const referenceContent = this.generateReferenceGuide();
        const blob = new Blob([referenceContent], { type: 'text/html' });
        const url = URL.createObjectURL(blob);
        
        const a = document.createElement('a');
        a.href = url;
        a.download = 'admin-pages-reference-guide.html';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    generateReferenceGuide() {
        return `
            <!DOCTYPE html>
            <html>
            <head>
                <title>Admin Pages Reference Guide</title>
                <style>
                    body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
                    h1, h2, h3 { color: #667eea; }
                    .tip { background: #f8f9fa; padding: 15px; border-left: 4px solid #667eea; margin: 15px 0; }
                    .warning { background: #fff3cd; border-left: 4px solid #ffc107; }
                    .success { background: #d4edda; border-left: 4px solid #28a745; }
                </style>
            </head>
            <body>
                <h1>🎯 Admin Pages Reference Guide</h1>
                <p>Quick reference for managing pages and buttons in your AAC system.</p>
                
                <h2>📄 Page Management</h2>
                <div class="tip">
                    <strong>Creating Pages:</strong> Always start with a clear purpose and organize by communication topics.
                </div>
                
                <h2>🔘 Button Design</h2>
                <div class="tip">
                    <strong>Design Principles:</strong> Use clear icons, readable text, and appropriate colors for maximum usability.
                </div>
                
                <h2>🧭 Navigation Setup</h2>
                <div class="tip">
                    <strong>Best Practice:</strong> Create logical hierarchies and provide easy back/home navigation options.
                </div>
                
                <h2>🤖 Smart Help</h2>
                <div class="success">
                    Smart Help AI is always available for contextual assistance and personalized recommendations.
                </div>
                
                <p><em>Generated on ${new Date().toLocaleDateString()}</em></p>
            </body>
            </html>
        `;
    }

    saveProgress() {
        const progress = {
            currentStep: this.currentStep,
            completed: this.userProgress.completed || false,
            lastAccessed: new Date().toISOString(),
            completedAt: this.userProgress.completedAt || null
        };
        localStorage.setItem('adminPagesGuideProgress', JSON.stringify(progress));
    }

    loadProgress() {
        const saved = localStorage.getItem('adminPagesGuideProgress');
        return saved ? JSON.parse(saved) : { currentStep: 0, completed: false };
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    window.guideInstance = new AdminPagesComprehensiveGuide();
});

// Export for global access
window.AdminPagesComprehensiveGuide = AdminPagesComprehensiveGuide;
