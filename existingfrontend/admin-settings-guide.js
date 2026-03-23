// Admin Settings Interactive Guide System
// Comprehensive guided tours for global configuration management

document.addEventListener('DOMContentLoaded', function() {
    // Wait for InteractiveGuide to be available
    function initializeGuides() {
        // Register admin settings guides with InteractiveGuide system
        if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        
            // User Settings Overview Tour
            InteractiveGuide.registerGuide('settings-overview', {
                title: '⚙️ User Settings Management',
                description: 'Learn how to configure your personal AAC settings and preferences',
                steps: [
                    {
                        target: 'body',
                        title: '🎛️ Welcome to User Settings',
                        content: `
                            <div class="guide-welcome">
                                <h3>⚙️ Personal Configuration Center</h3>
                                <p>This admin panel controls your personal settings and preferences:</p>
                                <ul>
                                    <li>🔒 Security configurations for your account</li>
                                    <li>🤖 AI behavior and response customization</li>
                                    <li>🔊 Audio and speech settings</li>
                                    <li>📱 Display and interface preferences</li>
                                    <li>🔍 Auditory scanning features</li>
                                </ul>
                                <div class="tip">
                                    <strong>💡 Note:</strong> Changes here affect only your profile. Adjust settings to match your preferences.
                                </div>
                            </div>
                        `,
                        position: 'center'
                    },
                    {
                        target: 'div.bg-white:nth-of-type(1)',
                        title: '🔒 Security Settings',
                        content: `
                            <div class="guide-step">
                                <h4>Protect Administrative Access</h4>
                                <p>Configure security measures to protect your settings:</p>
                                <ul>
                                    <li>🔐 <strong>Admin PIN:</strong> Required to access admin functions</li>
                                    <li>📱 Use 4-10 digits for optimal security</li>
                                    <li>🔄 Change PIN regularly for best security</li>
                                    <li>💾 Remember to save after setting PIN</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Setting Security:</strong>
                                    <ol>
                                        <li>Enter a 4-10 digit PIN in the toolbar PIN field</li>
                                        <li><strong>⭐ Scroll down and click "Save Settings"</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: 'div.bg-white:nth-of-type(2)',
                        title: '🤖 AI Settings Configuration',
                        content: `
                            <div class="guide-step">
                                <h4>Customize AI Behavior</h4>
                                <p>Control how the AI assistant responds and behaves:</p>
                                <ul>
                                    <li>🗣️ <strong>Wake Word:</strong> Set activation phrase (e.g., "Hey Bravo")</li>
                                    <li>🎯 <strong>Response Options:</strong> Number of choices AI provides</li>
                                    <li>🎭 <strong>Mood Selection:</strong> Enable personalized responses</li>
                                    <li>🖼️ <strong>Pictograms:</strong> Show AAC symbols on buttons</li>
                                    <li>🌍 <strong>Location:</strong> Set country for local information</li>
                                    <li>⚡ <strong>Provider:</strong> Choose between Gemini or ChatGPT</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Key AI Settings:</strong>
                                    <ol>
                                        <li>Set wake word interjection and name</li>
                                        <li>Adjust number of AI options (1-50)</li>
                                        <li>Enable/disable features with checkboxes</li>
                                        <li><strong>⭐ Save changes when complete</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'right'
                    },
                    {
                        target: 'div.bg-white:nth-of-type(3)',
                        title: '🔊 Audio Settings',
                        content: `
                            <div class="guide-step">
                                <h4>Configure Speech and Voice</h4>
                                <p>Optimize audio output for your preferences:</p>
                                <ul>
                                    <li>⚡ <strong>Speech Rate:</strong> Words per minute (100-300 WPM)</li>
                                    <li>🎤 <strong>Voice Selection:</strong> Choose from available TTS voices</li>
                                    <li>🔊 <strong>Test Feature:</strong> Preview voice settings</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Audio Configuration:</strong>
                                    <ol>
                                        <li>Set speech rate (recommended: 150-200 WPM)</li>
                                        <li>Select preferred TTS voice from dropdown</li>
                                        <li>Click "Test Voice" to preview</li>
                                        <li><strong>⭐ Save settings to apply changes</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'left'
                    },
                    {
                        target: 'div.bg-white:nth-of-type(4)',
                        title: '📱 Display Settings',
                        content: `
                            <div class="guide-step">
                                <h4>Customize Interface Layout</h4>
                                <p>Adjust visual settings for optimal usability:</p>
                                <ul>
                                    <li>📏 <strong>Button Size:</strong> Control with slider (2-18 columns)</li>
                                    <li>👀 <strong>Larger Buttons:</strong> Fewer columns = bigger buttons</li>
                                    <li>🔤 <strong>Smaller Buttons:</strong> More columns = smaller buttons</li>
                                    <li>⚖️ <strong>Balance:</strong> More buttons vs easier targeting</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Setting Button Size:</strong>
                                    <ol>
                                        <li>Use the slider to adjust column count</li>
                                        <li>2 columns = largest buttons (easiest to tap)</li>
                                        <li>18 columns = smallest buttons (more on screen)</li>
                                        <li><strong>⭐ Save to apply the new layout</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'top'
                    },
                    {
                        target: 'div.bg-white:nth-of-type(5)',
                        title: '🔍 Auditory Scanning Settings',
                        content: `
                            <div class="guide-step">
                                <h4>Switch Navigation Features</h4>
                                <p>Configure scanning for switch-based navigation:</p>
                                <ul>
                                    <li>⏱️ <strong>Scan Speed:</strong> Time between button highlights (ms)</li>
                                    <li>🔄 <strong>Loop Limit:</strong> Number of scanning cycles (0 = unlimited)</li>
                                    <li>⏹️ <strong>Toggle Off:</strong> Disable scanning if not needed</li>
                                    <li>🎯 <strong>Navigation:</strong> Enables switch-based button selection</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Scanning Configuration:</strong>
                                    <ol>
                                        <li>Set scan delay (recommended: 2000-4000ms for beginners)</li>
                                        <li>Choose loop limit (0 for continuous, 1-3 for limited cycles)</li>
                                        <li>Check "Turn off" to disable scanning completely</li>
                                        <li><strong>⭐ Save settings to apply scanning preferences</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#saveSettingsButton',
                        title: '💾 Save Settings',
                        content: `
                            <div class="guide-step">
                                <h4>Apply All Configuration Changes</h4>
                                <p>Important final step for all settings:</p>
                                <ul>
                                    <li>💾 <strong>Save Required:</strong> Changes don't apply until saved</li>
                                    <li>✅ <strong>Confirmation:</strong> Look for success message</li>
                                    <li>🔄 <strong>Test Changes:</strong> Verify settings work as expected</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Critical Save Step:</strong>
                                    <ol>
                                        <li>Review all your setting changes</li>
                                        <li><strong>⭐ Click "Save Settings" button</strong></li>
                                        <li>Wait for confirmation message</li>
                                        <li>Test settings in main app interface</li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'top'
                    }
                ]
            });

            // Security Configuration Tour
            InteractiveGuide.registerGuide('security-setup', {
                title: '🔒 Security Configuration',
                description: 'Set up security measures to protect your administrative functions',
                steps: [
                    {
                        target: '#toolbarPIN',
                        title: '🔐 Admin PIN Setup',
                        content: `
                            <div class="guide-step">
                                <h4>Secure Your Admin Access</h4>
                                <p>The admin PIN protects configuration settings:</p>
                                <ul>
                                    <li>🔢 Use 4-10 digits for the PIN</li>
                                    <li>🔐 Required to access admin toolbar</li>
                                    <li>💡 Choose memorable but secure numbers</li>
                                    <li>🔄 Change periodically for security</li>
                                </ul>
                                <div class="security-tips">
                                    <strong>🛡️ Security Best Practices:</strong>
                                    <ul>
                                        <li>Avoid obvious patterns (1234, 0000)</li>
                                        <li>Don't use birthdays or easily guessed numbers</li>
                                        <li>Store PIN securely and don't share</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // AI Configuration Tour
            InteractiveGuide.registerGuide('ai-setup', {
                title: '🤖 AI Configuration',
                description: 'Configure AI behavior and response settings for optimal performance',
                steps: [
                    {
                        target: '#wakeWordInterjection',
                        title: '🗣️ Wake Word Configuration',
                        content: `
                            <div class="guide-step">
                                <h4>Set Voice Activation Phrase</h4>
                                <p>Configure how to activate voice commands:</p>
                                <ul>
                                    <li>💬 <strong>Interjection:</strong> Opening word (Hey, Hi, Hello)</li>
                                    <li>🏷️ <strong>Name:</strong> Assistant name (Bravo, Assistant)</li>
                                    <li>🎯 <strong>Example:</strong> "Hey Bravo" or "Hello Assistant"</li>
                                    <li>🔊 <strong>Natural Speech:</strong> Use familiar, easy phrases</li>
                                </ul>
                                <div class="wake-word-examples">
                                    <strong>💡 Popular Wake Words:</strong>
                                    <ul>
                                        <li>"Hey Bravo" - Default and recommended</li>
                                        <li>"Hello Assistant" - Formal alternative</li>
                                        <li>"Hi Helper" - Simple and friendly</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#LLMOptions',
                        title: '🎯 AI Response Options',
                        content: `
                            <div class="guide-step">
                                <h4>Control Response Choices</h4>
                                <p>Set how many options the AI provides:</p>
                                <ul>
                                    <li>🔢 <strong>Range:</strong> 1-50 response options</li>
                                    <li>⚡ <strong>Few Options (3-8):</strong> Faster selection, simpler choices</li>
                                    <li>🌟 <strong>Many Options (10-20):</strong> More variety, detailed responses</li>
                                    <li>⚖️ <strong>Balance:</strong> Consider user cognitive load</li>
                                </ul>
                                <div class="recommendation">
                                    <strong>📋 Recommendations by User Type:</strong>
                                    <ul>
                                        <li><strong>Beginners:</strong> 3-5 options</li>
                                        <li><strong>Regular Users:</strong> 8-12 options</li>
                                        <li><strong>Advanced Users:</strong> 15+ options</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'right'
                    },
                    {
                        target: '#llmProvider',
                        title: '⚡ AI Provider Selection',
                        content: `
                            <div class="guide-step">
                                <h4>Choose Your AI Engine</h4>
                                <p>Select between available AI providers:</p>
                                <ul>
                                    <li>🟦 <strong>Google Gemini:</strong> Fast, efficient, great for AAC</li>
                                    <li>🟢 <strong>OpenAI ChatGPT:</strong> Conversational, detailed responses</li>
                                    <li>🔧 <strong>System Config:</strong> Models managed by administrator</li>
                                    <li>🎯 <strong>Performance:</strong> Both provide excellent results</li>
                                </ul>
                                <div class="provider-comparison">
                                    <strong>🔍 Quick Comparison:</strong>
                                    <ul>
                                        <li><strong>Gemini:</strong> Faster responses, lower latency</li>
                                        <li><strong>ChatGPT:</strong> More conversational tone</li>
                                        <li>Both support AAC communication needs effectively</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'left'
                    }
                ]
            });

            // Audio Configuration Tour
            InteractiveGuide.registerGuide('audio-setup', {
                title: '🔊 Audio Configuration',
                description: 'Set up speech rate and voice settings for optimal audio output',
                steps: [
                    {
                        target: '#speechRate',
                        title: '⚡ Speech Rate Setting',
                        content: `
                            <div class="guide-step">
                                <h4>Optimize Speaking Speed</h4>
                                <p>Configure words per minute for announcements:</p>
                                <ul>
                                    <li>🐌 <strong>Slow (100-150 WPM):</strong> Better for comprehension</li>
                                    <li>⚡ <strong>Normal (150-200 WPM):</strong> Natural speech pace</li>
                                    <li>🚀 <strong>Fast (200-300 WPM):</strong> Quick communication</li>
                                    <li>👂 <strong>User Needs:</strong> Adjust for hearing/processing</li>
                                </ul>
                                <div class="speech-guidelines">
                                    <strong>📋 Recommended Rates:</strong>
                                    <ul>
                                        <li><strong>Slower pace:</strong> 120-150 WPM</li>
                                        <li><strong>General use:</strong> 160-180 WPM</li>
                                        <li><strong>Faster pace:</strong> 200+ WPM</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    },
                    {
                        target: '#ttsVoiceSelect',
                        title: '🎤 Voice Selection',
                        content: `
                            <div class="guide-step">
                                <h4>Choose Text-to-Speech Voice</h4>
                                <p>Select the best voice for your profile:</p>
                                <ul>
                                    <li>👥 <strong>Voice Options:</strong> Male, female, different accents</li>
                                    <li>🔊 <strong>Test Feature:</strong> Preview voices before choosing</li>
                                    <li>🌍 <strong>Language:</strong> Voices match system language</li>
                                    <li>👂 <strong>Clarity:</strong> Choose clear, easy-to-understand voices</li>
                                </ul>
                                <div class="voice-tips">
                                    <strong>🎯 Voice Selection Tips:</strong>
                                    <ul>
                                        <li>Test with actual content you will hear</li>
                                        <li>Consider user preferences and familiarity</li>
                                        <li>Some voices work better for specific content types</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'right'
                    }
                ]
            });

            // Display Configuration Tour
            InteractiveGuide.registerGuide('display-setup', {
                title: '📱 Display Configuration',
                description: 'Customize interface layout and button sizing for optimal usability',
                steps: [
                    {
                        target: '#gridColumnsSlider',
                        title: '📏 Button Size Control',
                        content: `
                            <div class="guide-step">
                                <h4>Optimize Button Layout</h4>
                                <p>Balance button size with screen space:</p>
                                <ul>
                                    <li>👈 <strong>Fewer Columns (2-6):</strong> Larger, easier-to-tap buttons</li>
                                    <li>👉 <strong>More Columns (10-18):</strong> More buttons visible at once</li>
                                    <li>⚖️ <strong>Balance:</strong> Consider button size vs quantity trade-off</li>
                                    <li>� <strong>Screen Size:</strong> Adjust based on device dimensions</li>
                                </ul>
                                <div class="layout-recommendations">
                                    <strong>📋 General Recommendations:</strong>
                                    <ul>
                                        <li><strong>Beginners:</strong> 2-4 columns (large, easy buttons)</li>
                                        <li><strong>Regular users:</strong> 6-8 columns (balanced approach)</li>
                                        <li><strong>Advanced users:</strong> 8-12 columns (more options)</li>
                                        <li><strong>Large screens:</strong> 8-14 columns (utilize screen space)</li>
                                    </ul>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // Auditory Scanning Configuration Tour
            InteractiveGuide.registerGuide('scanning-setup', {
                title: '🔍 Auditory Scanning Settings',
                description: 'Configure scanning features for switch-based navigation',
                steps: [
                    {
                        target: 'div.bg-white:nth-of-type(5)',
                        title: '🔍 Auditory Scanning Configuration',
                        content: `
                            <div class="guide-step">
                                <h4>Switch Navigation Features</h4>
                                <p>Configure scanning for switch-based navigation:</p>
                                <ul>
                                    <li>⏱️ <strong>Scan Speed:</strong> Time between button highlights (milliseconds)</li>
                                    <li>🔄 <strong>Loop Limit:</strong> Number of scanning cycles (0 = unlimited)</li>
                                    <li>⏹️ <strong>Toggle Off:</strong> Disable scanning if not needed</li>
                                    <li>🎯 <strong>Navigation:</strong> Enables switch-based button selection</li>
                                </ul>
                                <div class="action-steps">
                                    <strong>Scanning Configuration:</strong>
                                    <ol>
                                        <li>Set scan delay (recommended: 2000-4000ms for beginners)</li>
                                        <li>Choose loop limit (0 for continuous, 1-3 for limited cycles)</li>
                                        <li>Check "Turn off" to disable scanning completely</li>
                                        <li><strong>⭐ Save settings to apply scanning preferences</strong></li>
                                    </ol>
                                </div>
                            </div>
                        `,
                        position: 'bottom'
                    }
                ]
            });

            // Setup help button functionality
            setupHelpButton();
            
        } else {
            // Retry after a short delay if InteractiveGuide is not ready
            setTimeout(initializeGuides, 100);
        }
    }

    // Initialize when DOM is ready
    initializeGuides();

    function setupHelpButton() {
        const helpButton = document.getElementById('help-icon');
        if (helpButton) {
            helpButton.addEventListener('click', function() {
                // Launch the main settings overview guide
                if (typeof InteractiveGuide !== 'undefined') {
                    InteractiveGuide.startGuide('settings-overview');
                }
            });
        }
    }

    // Auto-initialize when InteractiveGuide becomes available
    if (typeof InteractiveGuide !== 'undefined') {
        initializeGuides();
    }
});
