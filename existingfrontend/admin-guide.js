/**
 * Interactive Guide for Main Admin Page
 * Comprehensive guides for general admin functionality
 */

document.addEventListener('DOMContentLoaded', () => {
    if (typeof InteractiveGuide === 'undefined') {
        console.warn('Interactive Guide system not loaded');
        return;
    }

    setTimeout(() => {
        registerAdminGuides();
    }, 500);
});

function registerAdminGuides() {
    // Main Admin Introduction Guide
    const adminIntroGuide = {
        id: 'admin-intro',
        title: 'Welcome to Bravo AAC Admin Center',
        practiceMode: true,
        steps: [
            {
                target: null,
                title: 'Welcome to the Admin Center! 🎛️',
                icon: '👋',
                content: `
                    <p>This is the central hub for configuring and managing your Bravo AAC application.</p>
                    <p>From here, you can:</p>
                    <ul>
                        <li>Configure global application settings</li>
                        <li>Manage user profiles and data</li>
                        <li>Customize audio and scanning preferences</li>
                        <li>Access specialized admin tools</li>
                    </ul>
                `,
                media: {
                    type: 'image',
                    src: '/static/images/admin-overview.png',
                    alt: 'Admin Center Overview'
                }
            },
            {
                target: 'nav.bg-gray-800',
                title: 'Navigation Bar',
                icon: '🧭',
                content: `
                    <p>The navigation bar provides quick access to key areas:</p>
                    <ul>
                        <li><strong>Admin Nav:</strong> Access all admin pages</li>
                        <li><strong>Home:</strong> Return to the main application</li>
                        <li><strong>Help Admin:</strong> Manage help content (if available)</li>
                    </ul>
                `,
                tips: '<strong>💡 Pro Tip:</strong> Bookmark frequently used admin pages for quick access.'
            },
            {
                target: '.bg-white.p-6.rounded-lg.shadow-lg',
                title: 'Global Settings Panel',
                icon: '⚙️',
                content: `
                    <p>This panel contains the core configuration options that affect the entire application.</p>
                    <p>Settings here apply to all users and all pages of the application.</p>
                `,
                media: {
                    type: 'gif',
                    src: '/static/images/global-settings-demo.gif',
                    alt: 'Configuring global settings'
                }
            },
            {
                target: '#scanDelay',
                title: 'Auditory Scan Speed',
                icon: '🎵',
                content: `
                    <p>This controls how fast the auditory scanning moves between buttons.</p>
                    <ul>
                        <li><strong>Lower values (1000-2000ms):</strong> Faster scanning for experienced users</li>
                        <li><strong>Higher values (3000-5000ms):</strong> Slower scanning for new users or those who need more time</li>
                    </ul>
                `,
                interactive: true,
                interactiveAction: () => {
                    const scanInput = document.getElementById('scanDelay');
                    if (scanInput) {
                        scanInput.value = '3500';
                        scanInput.dispatchEvent(new Event('input'));
                        // Highlight the change
                        scanInput.style.background = '#eff6ff';
                        setTimeout(() => {
                            scanInput.style.background = '';
                        }, 2000);
                    }
                }
            },
            {
                target: 'input[name="wakeWord"]',
                title: 'Wake Word Configuration',
                icon: '🗣️',
                content: `
                    <p>Wake words allow users to activate voice features hands-free.</p>
                    <p>Choose wake words that are:</p>
                    <ul>
                        <li>Easy to pronounce</li>
                        <li>Distinct from common speech</li>
                        <li>Comfortable for the user</li>
                    </ul>
                `,
                tips: '<strong>💡 Tip:</strong> Test wake words in the user\'s environment to ensure they work reliably.'
            }
        ]
    };

    // Button Grid Configuration Guide
    const buttonGridGuide = {
        id: 'admin-button-grid',
        title: 'Configuring the Button Grid',
        practiceMode: true,
        steps: [
            {
                target: null,
                title: 'Understanding the Button Grid',
                icon: '🎯',
                content: `
                    <p>The button grid is the heart of the Bravo AAC interface. Each cell represents a communication button that users interact with.</p>
                    <p>This guide will show you how to configure buttons effectively.</p>
                `
            },
            {
                target: '#buttonGrid',
                title: 'The Button Grid Interface',
                icon: '📱',
                content: `
                    <p>This grid represents the layout users see on their main communication interface.</p>
                    <p>Each cell can be configured with:</p>
                    <ul>
                        <li><strong>Display text:</strong> What the user sees</li>
                        <li><strong>Spoken text:</strong> What the system says aloud</li>
                        <li><strong>Navigation:</strong> Arrow controls for positioning</li>
                    </ul>
                `,
                media: {
                    type: 'video',
                    src: '/static/images/button-grid-tutorial.mp4',
                    autoplay: true,
                    loop: true
                }
            },
            {
                target: '.gridCell:first-child input[placeholder*="display"]',
                title: 'Display Text Configuration',
                icon: '👁️',
                content: `
                    <p>The display text is what users see on the button. Keep it:</p>
                    <ul>
                        <li><strong>Short:</strong> 1-3 words maximum</li>
                        <li><strong>Clear:</strong> Easy to understand</li>
                        <li><strong>Relevant:</strong> Matches the button's purpose</li>
                    </ul>
                `,
                interactive: true,
                interactiveAction: () => {
                    const firstDisplayInput = document.querySelector('.gridCell:first-child input[placeholder*="display"]');
                    if (firstDisplayInput) {
                        firstDisplayInput.value = 'Hello';
                        firstDisplayInput.dispatchEvent(new Event('input'));
                    }
                }
            },
            {
                target: '.gridCell:first-child textarea',
                title: 'Spoken Text Configuration',
                icon: '🔊',
                content: `
                    <p>This is what the text-to-speech system will say when the button is pressed.</p>
                    <p>Spoken text can be:</p>
                    <ul>
                        <li><strong>Same as display:</strong> For simple words</li>
                        <li><strong>More detailed:</strong> Full sentences or phrases</li>
                        <li><strong>Phonetically adjusted:</strong> For better pronunciation</li>
                    </ul>
                `,
                interactive: true,
                interactiveAction: () => {
                    const firstSpokenInput = document.querySelector('.gridCell:first-child textarea');
                    if (firstSpokenInput) {
                        firstSpokenInput.value = 'Hello, how are you today?';
                        firstSpokenInput.dispatchEvent(new Event('input'));
                    }
                }
            },
            {
                target: '.gridCell:first-child .arrowButtons',
                title: 'Position Controls',
                icon: '🎮',
                content: `
                    <p>These arrow buttons control the positioning and organization of your button grid.</p>
                    <p>Use them to:</p>
                    <ul>
                        <li>Rearrange button order</li>
                        <li>Group related buttons together</li>
                        <li>Optimize for user workflow</li>
                    </ul>
                `,
                tips: '<strong>💡 Best Practice:</strong> Place frequently used buttons in easy-to-reach positions.'
            }
        ]
    };

    // Advanced Configuration Guide
    const advancedConfigGuide = {
        id: 'admin-advanced-config',
        title: 'Advanced Configuration Options',
        practiceMode: false,
        steps: [
            {
                target: null,
                title: 'Advanced Configuration Features',
                icon: '🔧',
                content: `
                    <p>Beyond basic settings, the admin panel offers advanced configuration options for power users.</p>
                    <p>These features help you fine-tune the application for specific user needs.</p>
                `
            },
            {
                target: '.text-lg.font-medium.text-gray-700:contains("Auditory Scan Speed")',
                title: 'Accessibility Timing',
                icon: '♿',
                content: `
                    <p>Timing settings are crucial for accessibility:</p>
                    <ul>
                        <li><strong>Motor impairments:</strong> Slower timing (4000-6000ms)</li>
                        <li><strong>Cognitive differences:</strong> Consistent, predictable timing</li>
                        <li><strong>Visual impairments:</strong> Audio cues with appropriate delays</li>
                    </ul>
                    <p>Always test with the actual user to find their optimal settings.</p>
                `
            },
            {
                target: 'form',
                title: 'Configuration Persistence',
                icon: '💾',
                content: `
                    <p>All configuration changes are automatically saved and persist across sessions.</p>
                    <p>Changes take effect:</p>
                    <ul>
                        <li><strong>Immediately:</strong> For current users</li>
                        <li><strong>On next load:</strong> For new sessions</li>
                        <li><strong>Globally:</strong> Across all user accounts</li>
                    </ul>
                `
            },
            {
                target: null,
                title: 'Testing Your Configuration',
                icon: '🧪',
                content: `
                    <h4>Always test configuration changes:</h4>
                    <ul>
                        <li><strong>Test with real users:</strong> Observe how they interact</li>
                        <li><strong>Try different scenarios:</strong> Various communication needs</li>
                        <li><strong>Check accessibility:</strong> Ensure all features work</li>
                        <li><strong>Monitor performance:</strong> Watch for any slowdowns</li>
                    </ul>
                    <p>Regular testing ensures your configuration truly helps users communicate effectively.</p>
                `
            }
        ]
    };

    // Troubleshooting Guide
    const troubleshootingGuide = {
        id: 'admin-troubleshooting',
        title: 'Admin Troubleshooting Guide',
        practiceMode: false,
        steps: [
            {
                target: null,
                title: 'Common Admin Issues & Solutions',
                icon: '🔍',
                content: `
                    <p>This guide covers the most common issues administrators encounter and how to resolve them.</p>
                    <p>We'll walk through systematic troubleshooting approaches.</p>
                `
            },
            {
                target: null,
                title: 'Configuration Not Saving',
                icon: '⚠️',
                content: `
                    <h4>If configuration changes aren't persisting:</h4>
                    <ol>
                        <li><strong>Check browser permissions:</strong> Ensure JavaScript is enabled</li>
                        <li><strong>Clear browser cache:</strong> Force refresh with Ctrl+F5</li>
                        <li><strong>Check network connection:</strong> Ensure stable internet</li>
                        <li><strong>Verify admin permissions:</strong> Confirm you're logged in as admin</li>
                    </ol>
                `
            },
            {
                target: null,
                title: 'Slow Performance Issues',
                icon: '🐌',
                content: `
                    <h4>If the admin interface is running slowly:</h4>
                    <ol>
                        <li><strong>Reduce grid complexity:</strong> Simplify button configurations</li>
                        <li><strong>Optimize images:</strong> Use compressed image formats</li>
                        <li><strong>Check device specs:</strong> Ensure minimum requirements are met</li>
                        <li><strong>Close other applications:</strong> Free up system resources</li>
                    </ol>
                `
            },
            {
                target: null,
                title: 'Audio/Speech Issues',
                icon: '🔇',
                content: `
                    <h4>For text-to-speech problems:</h4>
                    <ol>
                        <li><strong>Check device volume:</strong> Ensure audio is not muted</li>
                        <li><strong>Test browser audio:</strong> Try other audio sources</li>
                        <li><strong>Update browser:</strong> Use latest version</li>
                        <li><strong>Check audio settings:</strong> Visit audio admin page</li>
                    </ol>
                `
            },
            {
                target: null,
                title: 'Getting Additional Help',
                icon: '🆘',
                content: `
                    <h4>When you need more support:</h4>
                    <ul>
                        <li><strong>Documentation:</strong> Check the help admin for guides</li>
                        <li><strong>User Community:</strong> Connect with other administrators</li>
                        <li><strong>Technical Support:</strong> Contact the development team</li>
                        <li><strong>Training Resources:</strong> Access video tutorials</li>
                    </ul>
                `
            }
        ]
    };

    // Register all admin guides
    InteractiveGuide.registerGuide('admin-intro', adminIntroGuide);
    InteractiveGuide.registerGuide('admin-button-grid', buttonGridGuide);
    InteractiveGuide.registerGuide('admin-advanced-config', advancedConfigGuide);
    InteractiveGuide.registerGuide('admin-troubleshooting', troubleshootingGuide);

    // Add guide launcher to admin page
    addAdminGuideLaunchers();
}

function addAdminGuideLaunchers() {
    // Create guide launcher for admin page
    const guideLauncher = document.createElement('div');
    guideLauncher.id = 'admin-guide-launcher';
    guideLauncher.innerHTML = `
        <button id="admin-guide-toggle" class="admin-guide-toggle">
            📚 Admin Guides
        </button>
        <div id="admin-guide-content" class="admin-guide-content hidden">
            <h3>Admin Center Guides</h3>
            <div class="guide-grid">
                <button onclick="InteractiveGuide.startGuide('admin-intro')" class="admin-guide-card">
                    <div class="guide-icon">🎛️</div>
                    <div class="guide-info">
                        <h4>Admin Introduction</h4>
                        <p>Get started with the admin center</p>
                    </div>
                </button>
                <button onclick="InteractiveGuide.startGuide('admin-button-grid')" class="admin-guide-card">
                    <div class="guide-icon">📱</div>
                    <div class="guide-info">
                        <h4>Button Grid Setup</h4>
                        <p>Configure communication buttons</p>
                    </div>
                </button>
                <button onclick="InteractiveGuide.startGuide('admin-advanced-config')" class="admin-guide-card">
                    <div class="guide-icon">🔧</div>
                    <div class="guide-info">
                        <h4>Advanced Configuration</h4>
                        <p>Fine-tune advanced settings</p>
                    </div>
                </button>
                <button onclick="InteractiveGuide.startGuide('admin-troubleshooting')" class="admin-guide-card">
                    <div class="guide-icon">🔍</div>
                    <div class="guide-info">
                        <h4>Troubleshooting</h4>
                        <p>Solve common issues</p>
                    </div>
                </button>
            </div>
        </div>
    `;

    // Add styles
    const style = document.createElement('style');
    style.textContent = `
        #admin-guide-launcher {
            position: fixed;
            top: 100px;
            right: 20px;
            z-index: 1000;
        }

        .admin-guide-toggle {
            background: linear-gradient(135deg, #10b981, #047857);
            color: white;
            border: none;
            padding: 12px 20px;
            border-radius: 25px;
            font-weight: bold;
            cursor: pointer;
            box-shadow: 0 10px 30px rgba(16, 185, 129, 0.3);
            transition: all 0.3s ease;
            font-size: 14px;
        }

        .admin-guide-toggle:hover {
            transform: translateY(-2px);
            box-shadow: 0 15px 40px rgba(16, 185, 129, 0.4);
        }

        .admin-guide-content {
            position: absolute;
            top: 60px;
            right: 0;
            background: white;
            border-radius: 16px;
            box-shadow: 0 25px 50px rgba(0, 0, 0, 0.2);
            padding: 25px;
            min-width: 350px;
            border: 1px solid #e5e7eb;
        }

        .admin-guide-content h3 {
            margin: 0 0 20px 0;
            color: #1f2937;
            font-size: 18px;
            font-weight: bold;
            text-align: center;
        }

        .guide-grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 12px;
        }

        .admin-guide-card {
            display: flex;
            align-items: center;
            background: #f9fafb;
            border: 2px solid #e5e7eb;
            border-radius: 12px;
            padding: 15px;
            cursor: pointer;
            transition: all 0.3s ease;
            text-align: left;
            width: 100%;
        }

        .admin-guide-card:hover {
            background: #eff6ff;
            border-color: #3b82f6;
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(59, 130, 246, 0.15);
        }

        .guide-icon {
            font-size: 24px;
            margin-right: 15px;
            width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: white;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }

        .guide-info h4 {
            margin: 0 0 5px 0;
            font-weight: 600;
            color: #1f2937;
            font-size: 14px;
        }

        .guide-info p {
            margin: 0;
            color: #6b7280;
            font-size: 12px;
            line-height: 1.4;
        }

        .hidden {
            display: none !important;
        }

        @media (max-width: 768px) {
            #admin-guide-launcher {
                position: fixed;
                bottom: 20px;
                right: 20px;
                top: auto;
            }
            
            .admin-guide-content {
                position: fixed;
                bottom: 80px;
                right: 20px;
                left: 20px;
                width: auto;
                min-width: auto;
            }
        }
    `;

    document.head.appendChild(style);
    document.body.appendChild(guideLauncher);

    // Toggle functionality
    document.getElementById('admin-guide-toggle').addEventListener('click', () => {
        const content = document.getElementById('admin-guide-content');
        content.classList.toggle('hidden');
    });

    // Close when clicking outside
    document.addEventListener('click', (e) => {
        const launcher = document.getElementById('admin-guide-launcher');
        if (!launcher.contains(e.target)) {
            document.getElementById('admin-guide-content').classList.add('hidden');
        }
    });
}
