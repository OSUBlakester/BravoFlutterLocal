// Favorites Admin Interactive Guide System
// Comprehensive guided tours for managing user favorites and preferences

document.addEventListener('DOMContentLoaded', function() {
    // Wait for InteractiveGuide to be available
    function initializeGuides() {
        // Register favorites admin guides with the InteractiveGuide system
        if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        
        // Favorites Management Overview Tour
        InteractiveGuide.registerGuide('favorites-overview', {
            title: '⭐ Event Sources & Topic Management',
            description: 'Learn to manage favorite topics and configure web scraping for current events and news',
            steps: [
                {
                    target: 'body',
                    title: '⭐ Welcome to Event Sources Administration',
                    content: `
                        <div class="guide-welcome">
                            <h3>📰 Event Sources & Topic Management</h3>
                            <p>This interface helps you manage:</p>
                            <ul>
                                <li>⭐ Favorite topics and conversation subjects</li>
                                <li>🌐 Web scraping configuration for current events</li>
                                <li>📰 News sources and content feeds</li>
                                <li>� Personalized content filtering</li>
                                <li>🔄 Automatic content updates and refreshing</li>
                                <li>� Topic popularity and engagement tracking</li>
                            </ul>
                            <div class="tip">
                                <strong>💡 Key Point:</strong> Well-configured topics keep conversations fresh and relevant!
                            </div>
                        </div>
                    `,
                    position: 'center'
                },
                {
                    target: '#buttonGrid',
                    title: '🗂️ Topic Grid Management',
                    content: `
                        <div class="guide-step">
                            <h4>Organize Your Favorite Topics</h4>
                            <p>The topic grid displays:</p>
                            <ul>
                                <li>🎯 <strong>Current topics:</strong> Configured favorite subjects</li>
                                <li>📰 <strong>News sources:</strong> Connected web scraping feeds</li>
                                <li>🔄 <strong>Update status:</strong> Last refresh times</li>
                                <li>⚙️ <strong>Configuration:</strong> Edit topic settings</li>
                                <li>➕ <strong>Add new:</strong> Create additional topics</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Click on any empty cell to add a new topic
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#buttonText',
                    title: '📝 Topic Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Configure Topic Details</h4>
                            <p>For each topic, set up:</p>
                            <ul>
                                <li>🏷️ <strong>Topic Name:</strong> Clear, descriptive title (e.g., "Denver Broncos")</li>
                                <li>🗣️ <strong>Speech Phrase:</strong> What to say before reading content</li>
                                <li>🌐 <strong>Web Sources:</strong> News sites and content feeds</li>
                                <li>🔍 <strong>Keywords:</strong> Filter relevant content</li>
                                <li>⏰ <strong>Update frequency:</strong> How often to refresh</li>
                            </ul>
                            <div class="tip">
                                Choose topics that match the user's interests and communication needs
                            </div>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#configureScrapingBtn',
                    title: '🌐 Web Scraping Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Set Up Automatic Content Feeds</h4>
                            <p>Web scraping enables:</p>
                            <ul>
                                <li>📰 <strong>Current news:</strong> Latest articles and updates</li>
                                <li>🏈 <strong>Sports scores:</strong> Game results and schedules</li>
                                <li>🎬 <strong>Entertainment:</strong> Movie reviews, celebrity news</li>
                                <li>🌤️ <strong>Weather updates:</strong> Local conditions and forecasts</li>
                                <li>📈 <strong>Stock prices:</strong> Financial information</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Click to open the web scraping wizard
                            </div>
                        </div>
                    `,
                    position: 'left'
                },
                {
                    target: '#anyWebsiteUrl',
                    title: '� Custom News Sources',
                    content: `
                        <div class="guide-step">
                            <h4>Add Any Website as a Source</h4>
                            <p>You can scrape content from:</p>
                            <ul>
                                <li>� <strong>News websites:</strong> CNN, BBC, local news</li>
                                <li>🏈 <strong>Sports sites:</strong> ESPN, team websites</li>
                                <li>� <strong>Industry blogs:</strong> Specialized content</li>
                                <li>🎭 <strong>Entertainment:</strong> Celebrity, movies, music</li>
                                <li>�️ <strong>Government:</strong> Official announcements</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Paste any news section URL to configure scraping
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '.site-template-btn',
                    title: '⚡ Quick Setup Templates',
                    content: `
                        <div class="guide-step">
                            <h4>Use Pre-configured News Sources</h4>
                            <p>Popular templates include:</p>
                            <ul>
                                <li>📺 <strong>CNN:</strong> Breaking news and politics</li>
                                <li>🌍 <strong>BBC News:</strong> International coverage</li>
                                <li>🏈 <strong>ESPN:</strong> Sports news and scores</li>
                                <li>💬 <strong>Reddit:</strong> Community discussions</li>
                            </ul>
                            <div class="tip">
                                Templates automatically configure keywords and scraping settings
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                }
            ]
        });

        // Favorites Analytics Tour
        InteractiveGuide.registerGuide('favorites-analytics', {
            title: '📊 Favorites Analytics',
            description: 'Understand user preferences through favorites data analysis',
            steps: [
                {
                    target: '#analyticsPanel, [data-favorites="analytics"]',
                    title: '📈 Favorites Analytics Dashboard',
                    content: `
                        <div class="guide-step">
                            <h4>Analyze User Preferences</h4>
                            <p>Key metrics to track:</p>
                            <ul>
                                <li>📊 <strong>Total favorites:</strong> Overall engagement level</li>
                                <li>🔥 <strong>Trending content:</strong> What's popular now</li>
                                <li>👥 <strong>User segments:</strong> Preference groups</li>
                                <li>📅 <strong>Time patterns:</strong> When users favorite</li>
                                <li>🎯 <strong>Category breakdown:</strong> Content preferences</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Explore:</strong> Click to view analytics dashboard
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#trendingChart, [data-favorites="trending"]',
                    title: '🔥 Trending Favorites',
                    content: `
                        <div class="guide-step">
                            <h4>Identify Popular Content</h4>
                            <p>Trending indicators:</p>
                            <ul>
                                <li>📈 <strong>Rising favorites:</strong> Rapidly growing content</li>
                                <li>⏰ <strong>Time-based trends:</strong> Seasonal patterns</li>
                                <li>👥 <strong>User demographics:</strong> Who's favoriting what</li>
                                <li>🎯 <strong>Content correlation:</strong> Related favorites</li>
                            </ul>
                            <div class="tip">
                                Use trending data to curate featured content
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#userInsights, [data-favorites="insights"]',
                    title: '🧠 User Preference Insights',
                    content: `
                        <div class="guide-step">
                            <h4>Understand User Behavior</h4>
                            <p>Behavioral insights:</p>
                            <ul>
                                <li>🎨 <strong>Content preferences:</strong> Types, themes, styles</li>
                                <li>⏱️ <strong>Usage patterns:</strong> Peak favoriting times</li>
                                <li>🔄 <strong>Engagement cycles:</strong> How often users favorite</li>
                                <li>📱 <strong>Device preferences:</strong> Mobile vs desktop usage</li>
                            </ul>
                        </div>
                    `,
                    position: 'left'
                }
            ]
        });

        // Recommendation System Tour
        InteractiveGuide.registerGuide('favorites-recommendations', {
            title: '🎯 Smart Recommendations',
            description: 'Create and manage intelligent content recommendation systems',
            steps: [
                {
                    target: '#recommendationEngine, [data-favorites="recommendations"]',
                    title: '🤖 Recommendation Engine',
                    content: `
                        <div class="guide-step">
                            <h4>Personalized Content Suggestions</h4>
                            <p>Recommendation algorithms:</p>
                            <ul>
                                <li>👥 <strong>Collaborative filtering:</strong> Based on similar users</li>
                                <li>🏷️ <strong>Content-based:</strong> Similar to user's favorites</li>
                                <li>🔗 <strong>Hybrid approach:</strong> Combined algorithms</li>
                                <li>🧠 <strong>Machine learning:</strong> Adaptive recommendations</li>
                                <li>📊 <strong>Popularity-based:</strong> Trending content</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Configure:</strong> Set up recommendation parameters
                            </div>
                        </div>
                    `,
                    position: 'center'
                },
                {
                    target: '#recommendationRules, [data-favorites="rules"]',
                    title: '⚙️ Recommendation Rules',
                    content: `
                        <div class="guide-step">
                            <h4>Customize Recommendation Logic</h4>
                            <p>Configurable rules:</p>
                            <ul>
                                <li>🎯 <strong>Similarity thresholds:</strong> How similar is similar enough</li>
                                <li>📅 <strong>Recency weights:</strong> Favor recent favorites</li>
                                <li>🏷️ <strong>Category preferences:</strong> Content type priorities</li>
                                <li>👥 <strong>User segments:</strong> Demographic-based rules</li>
                                <li>🚫 <strong>Exclusion filters:</strong> Content to avoid recommending</li>
                            </ul>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#recommendationTesting, [data-favorites="testing"]',
                    title: '🧪 A/B Testing Recommendations',
                    content: `
                        <div class="guide-step">
                            <h4>Test Recommendation Effectiveness</h4>
                            <p>Testing strategies:</p>
                            <ul>
                                <li>🔄 <strong>Algorithm comparison:</strong> Test different approaches</li>
                                <li>👥 <strong>User group testing:</strong> Segment-based experiments</li>
                                <li>📊 <strong>Performance metrics:</strong> Click-through rates, conversions</li>
                                <li>⏱️ <strong>Long-term tracking:</strong> User satisfaction over time</li>
                            </ul>
                            <div class="tip">
                                Continuously optimize based on user feedback
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                }
            ]
        });

        // Favorites Organization Tour
        InteractiveGuide.registerGuide('favorites-organization', {
            title: '🗂️ Favorites Organization',
            description: 'Organize, categorize, and structure favorites for better user experience',
            steps: [
                {
                    target: '#categoryManager, [data-favorites="categories"]',
                    title: '🏷️ Category Management',
                    content: `
                        <div class="guide-step">
                            <h4>Organize Content Categories</h4>
                            <p>Category features:</p>
                            <ul>
                                <li>📁 <strong>Hierarchical structure:</strong> Parent and sub-categories</li>
                                <li>🎨 <strong>Visual customization:</strong> Icons, colors, themes</li>
                                <li>🏷️ <strong>Tag system:</strong> Multi-category content</li>
                                <li>🔄 <strong>Auto-categorization:</strong> AI-powered sorting</li>
                                <li>👥 <strong>User-created categories:</strong> Personal organization</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Create a new category
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#bulkActions, [data-favorites="bulk"]',
                    title: '⚡ Bulk Operations',
                    content: `
                        <div class="guide-step">
                            <h4>Manage Multiple Favorites</h4>
                            <p>Available bulk actions:</p>
                            <ul>
                                <li>🏷️ <strong>Bulk categorization:</strong> Assign categories to multiple items</li>
                                <li>🗑️ <strong>Bulk deletion:</strong> Remove multiple favorites</li>
                                <li>📤 <strong>Bulk export:</strong> Download favorite collections</li>
                                <li>🔄 <strong>Bulk migration:</strong> Move between categories</li>
                                <li>⭐ <strong>Bulk rating:</strong> Update ratings efficiently</li>
                            </ul>
                        </div>
                    `,
                    position: 'left'
                },
                {
                    target: '#favoritesBackup, [data-favorites="backup"]',
                    title: '💾 Favorites Backup',
                    content: `
                        <div class="guide-step">
                            <h4>Protect User Favorites</h4>
                            <p>Backup strategies:</p>
                            <ul>
                                <li>🔄 <strong>Automatic backups:</strong> Regular system backups</li>
                                <li>📤 <strong>User exports:</strong> Personal backup downloads</li>
                                <li>☁️ <strong>Cloud sync:</strong> Cross-device synchronization</li>
                                <li>📅 <strong>Versioning:</strong> Historical backup snapshots</li>
                            </ul>
                            <div class="warning">
                                <strong>⚠️ Important:</strong> Regular backups prevent data loss
                            </div>
                        </div>
                    `,
                    position: 'right'
                }
            ]
        });

        // Connect help button to guide system
        function setupHelpButton() {
            const helpButton = document.getElementById('help-icon');
            if (helpButton) {
                helpButton.addEventListener('click', function() {
                    showFavoritesGuideMenu();
                });
            }
        }

        // Create guide menu modal (only shown when help button is clicked)
        function showFavoritesGuideMenu() {
            // Remove existing menu if any
            const existingMenu = document.getElementById('favorites-guide-menu');
            if (existingMenu) {
                existingMenu.remove();
            }

            const guideMenu = document.createElement('div');
            guideMenu.id = 'favorites-guide-menu';
            guideMenu.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
            guideMenu.innerHTML = `
                <div class="bg-white rounded-lg shadow-lg border p-6 max-w-md w-full mx-4">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="font-bold text-xl text-gray-800">⭐ Favorites Admin Guides</h3>
                        <button id="close-favorites-guide-menu" class="text-gray-400 hover:text-gray-600 text-2xl">
                            ✕
                        </button>
                    </div>
                    <div class="space-y-3">
                        <button data-guide="favorites-overview" 
                                class="favorites-guide-menu-btn w-full text-left px-4 py-3 rounded bg-blue-50 hover:bg-blue-100 text-blue-700 transition-colors">
                            📚 Favorites Overview
                            <div class="text-sm text-blue-600 mt-1">Learn favorites management basics</div>
                        </button>
                        <button data-guide="favorites-analytics" 
                                class="favorites-guide-menu-btn w-full text-left px-4 py-3 rounded bg-green-50 hover:bg-green-100 text-green-700 transition-colors">
                            📊 Analytics & Insights
                            <div class="text-sm text-green-600 mt-1">Analyze user preferences and trends</div>
                        </button>
                        <button data-guide="favorites-recommendations" 
                                class="favorites-guide-menu-btn w-full text-left px-4 py-3 rounded bg-purple-50 hover:bg-purple-100 text-purple-700 transition-colors">
                            🎯 Smart Recommendations
                            <div class="text-sm text-purple-600 mt-1">Configure intelligent content suggestions</div>
                        </button>
                        <button data-guide="favorites-organization" 
                                class="favorites-guide-menu-btn w-full text-left px-4 py-3 rounded bg-orange-50 hover:bg-orange-100 text-orange-700 transition-colors">
                            🗂️ Organization & Backup
                            <div class="text-sm text-orange-600 mt-1">Organize and backup favorites data</div>
                        </button>
                    </div>
                </div>
            `;
            document.body.appendChild(guideMenu);

            // Add event listeners
            document.getElementById('close-favorites-guide-menu').addEventListener('click', function() {
                guideMenu.remove();
            });

            // Close on backdrop click
            guideMenu.addEventListener('click', function(e) {
                if (e.target === guideMenu) {
                    guideMenu.remove();
                }
            });

            // Add guide button listeners
            guideMenu.querySelectorAll('.favorites-guide-menu-btn').forEach(btn => {
                btn.addEventListener('click', function() {
                    const guideId = this.getAttribute('data-guide');
                    guideMenu.remove();
                    InteractiveGuide.startGuide(guideId);
                });
            });
        }

        // Setup help button connection
        setTimeout(setupHelpButton, 1000);
        }
    }
    
    // Try to initialize guides, with fallback
    if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        initializeGuides();
    } else {
        // Wait a bit for InteractiveGuide to load
        setTimeout(() => {
            if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
                initializeGuides();
            }
        }, 500);
    }
});
