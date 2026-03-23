/**
 * Interactive Guide for Help Admin Page
 */

document.addEventListener('DOMContentLoaded', function() {
    function initializeGuides() {
        if (typeof window.InteractiveGuide !== 'undefined' && window.InteractiveGuide.registerGuide) {
            // Register help admin intro guide
            window.InteractiveGuide.registerGuide('help-admin-intro', {
                title: '📚 Welcome to Help Content Management',
                description: 'Learn how to create and manage helpful content for your users',
                steps: [
                    {
                        target: 'body',
                        title: 'Welcome to Help Admin!',
                        content: `
                            <div class="guide-welcome">
                                <h3>🎉 Help Content Management Center</h3>
                                <p>This powerful interface lets you:</p>
                                <ul>
                                    <li>📝 Create interactive help articles</li>
                                    <li>🎨 Design rich content with multimedia</li>
                                    <li>📊 Organize content by categories</li>
                                    <li>👥 Manage user access and permissions</li>
                                    <li>📈 Track content performance</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Pro Tip:</strong> Start with our templates for faster content creation!
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: '.ql-editor, #editor',
                        title: '✏️ Rich Text Editor',
                        content: `
                            <div class="guide-step">
                                <h4>Create Beautiful Content</h4>
                                <p>Use the rich text editor to:</p>
                                <ul>
                                    <li><strong>Format text:</strong> Bold, italic, headers</li>
                                    <li><strong>Add lists:</strong> Bullets and numbered lists</li>
                                    <li><strong>Insert links:</strong> External and internal links</li>
                                    <li><strong>Add images:</strong> Screenshots and diagrams</li>
                                </ul>
                                <div class="practice-mode">
                                    <strong>Try it:</strong> Click here to start writing
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // Create floating guide menu
            createHelpGuideMenu();
        }
    }
    
    // Try to initialize guides with fallback
    if (typeof window.InteractiveGuide !== 'undefined') {
        initializeGuides();
    } else {
        setTimeout(() => {
            if (typeof window.InteractiveGuide !== 'undefined') {
                initializeGuides();
            }
        }, 500);
    }
});

function createHelpGuideMenu() {
    // Create floating guide launcher
    const guideMenu = document.createElement('div');
    guideMenu.id = 'guide-launcher-menu';
    guideMenu.innerHTML = `
        <button id="guide-menu-toggle" class="guide-launcher-btn">
            📚 Help Guides
        </button>
        <div id="guide-menu-content" class="guide-menu-content hidden">
            <h3>📚 Help Admin Guides</h3>
            <button onclick="InteractiveGuide.startGuide('help-admin-intro')" class="guide-menu-item">
                🎉 Getting Started
            </button>
        </div>
    `;

    // Add styles
    const style = document.createElement('style');
    style.textContent = `
        #guide-launcher-menu {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
        }
        
        .guide-launcher-btn {
            background: #3b82f6;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
            transition: all 0.3s ease;
        }
        
        .guide-launcher-btn:hover {
            background: #2563eb;
            transform: translateY(-2px);
            box-shadow: 0 6px 16px rgba(59, 130, 246, 0.4);
        }
        
        .guide-menu-content {
            position: absolute;
            top: 100%;
            right: 0;
            background: white;
            border-radius: 8px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.15);
            padding: 16px;
            min-width: 250px;
            margin-top: 8px;
        }
        
        .guide-menu-content h3 {
            margin: 0 0 12px 0;
            color: #374151;
            font-size: 16px;
        }
        
        .guide-menu-item {
            display: block;
            width: 100%;
            text-align: left;
            background: none;
            border: none;
            padding: 8px 12px;
            margin: 4px 0;
            border-radius: 6px;
            cursor: pointer;
            transition: background-color 0.2s;
            color: #374151;
        }
        
        .guide-menu-item:hover {
            background: #f3f4f6;
        }
        
        .hidden {
            display: none !important;
        }
    `;

    document.head.appendChild(style);
    document.body.appendChild(guideMenu);

    // Toggle menu visibility
    document.getElementById('guide-menu-toggle').addEventListener('click', () => {
        const content = document.getElementById('guide-menu-content');
        content.classList.toggle('hidden');
    });

    // Close menu when clicking outside
    document.addEventListener('click', (e) => {
        const menu = document.getElementById('guide-launcher-menu');
        if (!menu.contains(e.target)) {
            document.getElementById('guide-menu-content').classList.add('hidden');
        }
    });
}
