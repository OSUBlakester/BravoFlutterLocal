// Audio Admin Interactive Guide System
// Provides comprehensive guided tours for audio configuration and management

document.addEventListener('DOMContentLoaded', function() {
    // Wait for InteractiveGuide to be available
    function initializeGuides() {
        // Register audio admin guides with the InteractiveGuide system
        if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        
        // Audio Configuration Introduction Tour
        InteractiveGuide.registerGuide('audio-intro', {
            title: '🔊 Audio Device Configuration',
            description: 'Learn how to configure personal and system audio outputs for optimal communication experience',
            steps: [
                {
                    target: 'body',
                    title: '🎵 Welcome to Audio Configuration',
                    content: `
                        <div class="guide-welcome">
                            <h3>🔊 Audio Device Admin Center</h3>
                            <p>This interface helps you configure:</p>
                            <ul>
                                <li>� Personal speaker devices for private audio</li>
                                <li>📢 System speakers for public announcements</li>
                                <li>🧪 Audio testing and verification</li>
                                <li>⚙️ Device-specific audio settings</li>
                                <li>🔊 Volume and output quality controls</li>
                            </ul>
                            <div class="tip">
                                <strong>💡 Important:</strong> Test all audio settings to ensure proper communication setup!
                            </div>
                        </div>
                    `,
                    position: 'center'
                },
                {
                    target: '#personalSpeakerSelect',
                    title: '🎧 Personal Speaker Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Set Up Private Audio Output</h4>
                            <p>Personal speakers are used for:</p>
                            <ul>
                                <li>🗣️ <strong>Private conversations:</strong> Personal AI interactions</li>
                                <li>� <strong>Confidential content:</strong> Personal information, reminders</li>
                                <li>🎵 <strong>Individual preferences:</strong> Music, entertainment</li>
                                <li>📞 <strong>Phone calls:</strong> Private communication</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Select a personal audio device from the dropdown
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#testPersonalSpeakerBtn',
                    title: '🧪 Test Personal Audio',
                    content: `
                        <div class="guide-step">
                            <h4>Verify Personal Speaker Setup</h4>
                            <p>Testing ensures:</p>
                            <ul>
                                <li>🔊 <strong>Volume levels:</strong> Appropriate sound level</li>
                                <li>🎯 <strong>Audio clarity:</strong> Clear speech reproduction</li>
                                <li>📍 <strong>Device targeting:</strong> Correct output device</li>
                                <li>⚡ <strong>Response time:</strong> No audio delays</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Click to test your personal speaker selection
                            </div>
                        </div>
                    `,
                    position: 'left'
                },
                {
                    target: '#systemSpeakerSelect',
                    title: '📢 System Speaker Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Set Up Public Audio Output</h4>
                            <p>System speakers are used for:</p>
                            <ul>
                                <li>📢 <strong>Public announcements:</strong> Alerts, notifications</li>
                                <li>👥 <strong>Group interactions:</strong> Shared conversations</li>
                                <li>🚨 <strong>Emergency alerts:</strong> Important warnings</li>
                                <li>🎉 <strong>Celebrations:</strong> Birthday messages, achievements</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Select a system audio device from the dropdown
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#testSystemSpeakerBtn',
                    title: '🧪 Test System Audio',
                    content: `
                        <div class="guide-step">
                            <h4>Verify System Speaker Setup</h4>
                            <p>System testing checks:</p>
                            <ul>
                                <li>📈 <strong>Volume range:</strong> Audible to intended audience</li>
                                <li>🔍 <strong>Audio quality:</strong> Clear for group listening</li>
                                <li>🎯 <strong>Coverage area:</strong> Reaches all listeners</li>
                                <li>🔄 <strong>Reliability:</strong> Consistent performance</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Click to test your system speaker selection
                            </div>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#saveAudioSettingsBtn',
                    title: '💾 Save Audio Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Apply Your Audio Settings</h4>
                            <p>Saving settings will:</p>
                            <ul>
                                <li>✅ <strong>Store preferences:</strong> Remember your device choices</li>
                                <li>🔄 <strong>Apply changes:</strong> Activate new audio routing</li>
                                <li>📱 <strong>Update system:</strong> Configure all connected apps</li>
                                <li>🔐 <strong>User-specific:</strong> Settings unique to this profile</li>
                            </ul>
                            <div class="tip">
                                <strong>Best Practice:</strong> Test both speakers before saving!
                            </div>
                        </div>
                    `,
                    position: 'left'
                }
            ]
        });

        // Audio Testing and Preview Tour
        InteractiveGuide.registerGuide('audio-testing', {
            title: '🔊 Audio Testing & Preview',
            description: 'Learn how to test and preview your audio configurations',
            steps: [
                {
                    target: '#audioPreview, [data-audio="preview"]',
                    title: '🎧 Audio Preview System',
                    content: `
                        <div class="guide-step">
                            <h4>Test Your Audio Settings</h4>
                            <p>Use the preview system to:</p>
                            <ul>
                                <li>🎤 Test voice selection</li>
                                <li>⚡ Verify speed settings</li>
                                <li>🎵 Check pitch adjustments</li>
                                <li>🔊 Confirm volume levels</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Practice:</strong> Click to test current settings
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#testText, [data-audio="test-input"]',
                    title: '📝 Custom Test Text',
                    content: `
                        <div class="guide-step">
                            <h4>Enter Your Test Content</h4>
                            <p>Tips for effective testing:</p>
                            <ul>
                                <li>Use representative text samples</li>
                                <li>Include punctuation and numbers</li>
                                <li>Test with various sentence lengths</li>
                                <li>Try technical terms if applicable</li>
                            </ul>
                            <div class="tip">
                                Save good test phrases for future use!
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#audioOutput, [data-audio="output"]',
                    title: '🔊 Audio Output Options',
                    content: `
                        <div class="guide-step">
                            <h4>Configure Audio Delivery</h4>
                            <p>Choose how audio is played:</p>
                            <ul>
                                <li><strong>Streaming:</strong> Real-time playback</li>
                                <li><strong>Download:</strong> Save audio files</li>
                                <li><strong>Inline:</strong> Embedded player</li>
                            </ul>
                        </div>
                    `,
                    position: 'right'
                }
            ]
        });

        // Advanced Audio Configuration Tour
        InteractiveGuide.registerGuide('audio-advanced', {
            title: '⚙️ Advanced Audio Settings',
            description: 'Master advanced audio configuration options and optimization',
            steps: [
                {
                    target: '#audioFormat, [data-audio="format"]',
                    title: '🎵 Audio Format Selection',
                    content: `
                        <div class="guide-step">
                            <h4>Choose Optimal Audio Format</h4>
                            <p>Format considerations:</p>
                            <ul>
                                <li><strong>MP3:</strong> Universal compatibility, smaller files</li>
                                <li><strong>WAV:</strong> Highest quality, larger files</li>
                                <li><strong>OGG:</strong> Good quality, open standard</li>
                                <li><strong>AAC:</strong> Efficient compression</li>
                            </ul>
                            <div class="tip">
                                Match format to your delivery method and quality needs
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#sampleRate, [data-audio="sample-rate"]',
                    title: '📊 Sample Rate Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Audio Quality Settings</h4>
                            <p>Sample rate affects quality and file size:</p>
                            <ul>
                                <li><strong>22kHz:</strong> Basic quality, smaller files</li>
                                <li><strong>44.1kHz:</strong> CD quality, balanced</li>
                                <li><strong>48kHz:</strong> Professional quality</li>
                            </ul>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#audioEffects, [data-audio="effects"]',
                    title: '✨ Audio Effects & Processing',
                    content: `
                        <div class="guide-step">
                            <h4>Enhance Your Audio</h4>
                            <p>Available audio enhancements:</p>
                            <ul>
                                <li>🎚️ Equalization settings</li>
                                <li>🔊 Volume normalization</li>
                                <li>🎵 Reverb and ambiance</li>
                                <li>🎤 Voice enhancement filters</li>
                            </ul>
                            <div class="warning">
                                <strong>⚠️ Note:</strong> Effects may increase processing time
                            </div>
                        </div>
                    `,
                    position: 'left'
                }
            ]
        });

        // Audio Troubleshooting Tour
        InteractiveGuide.registerGuide('audio-troubleshooting', {
            title: '🔧 Audio Troubleshooting',
            description: 'Solve common audio configuration issues and optimize performance',
            steps: [
                {
                    target: '#audioStatus, [data-audio="status"]',
                    title: '📊 Audio System Status',
                    content: `
                        <div class="guide-step">
                            <h4>Monitor Audio Health</h4>
                            <p>Key status indicators:</p>
                            <ul>
                                <li>🟢 <strong>Green:</strong> System working normally</li>
                                <li>🟡 <strong>Yellow:</strong> Minor issues, check settings</li>
                                <li>🔴 <strong>Red:</strong> Critical error, needs attention</li>
                                <li>⚪ <strong>Gray:</strong> Service unavailable</li>
                            </ul>
                            <div class="tip">
                                Refresh the page if status seems incorrect
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#errorLogs, [data-audio="logs"]',
                    title: '📝 Audio Error Logs',
                    content: `
                        <div class="guide-step">
                            <h4>Diagnose Audio Issues</h4>
                            <p>Common problems and solutions:</p>
                            <ul>
                                <li><strong>No audio output:</strong> Check voice selection</li>
                                <li><strong>Slow generation:</strong> Reduce quality settings</li>
                                <li><strong>Distorted audio:</strong> Adjust pitch/speed</li>
                                <li><strong>Connection errors:</strong> Verify API keys</li>
                            </ul>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#audioReset, [data-audio="reset"]',
                    title: '🔄 Reset Audio Settings',
                    content: `
                        <div class="guide-step">
                            <h4>Restore Default Configuration</h4>
                            <p>When to reset:</p>
                            <ul>
                                <li>Persistent audio issues</li>
                                <li>Corrupted settings</li>
                                <li>Starting fresh configuration</li>
                                <li>Testing baseline performance</li>
                            </ul>
                            <div class="warning">
                                <strong>⚠️ Warning:</strong> This will erase all custom settings
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
                    showAudioGuideMenu();
                });
            }
        }

        // Create guide menu modal (only shown when help button is clicked)
        function showAudioGuideMenu() {
            // Remove existing menu if any
            const existingMenu = document.getElementById('audio-guide-menu');
            if (existingMenu) {
                existingMenu.remove();
            }

            const guideMenu = document.createElement('div');
            guideMenu.id = 'audio-guide-menu';
            guideMenu.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
            guideMenu.innerHTML = `
                <div class="bg-white rounded-lg shadow-lg border p-6 max-w-md w-full mx-4">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="font-bold text-xl text-gray-800">🎵 Audio Admin Guides</h3>
                        <button id="close-audio-guide-menu" class="text-gray-400 hover:text-gray-600 text-2xl">
                            ✕
                        </button>
                    </div>
                    <div class="space-y-3">
                        <button data-guide="audio-intro" 
                                class="audio-guide-menu-btn w-full text-left px-4 py-3 rounded bg-blue-50 hover:bg-blue-100 text-blue-700 transition-colors">
                            📚 Audio Overview
                            <div class="text-sm text-blue-600 mt-1">Learn audio system basics</div>
                        </button>
                        <button data-guide="audio-testing" 
                                class="audio-guide-menu-btn w-full text-left px-4 py-3 rounded bg-green-50 hover:bg-green-100 text-green-700 transition-colors">
                            🔊 Testing & Preview
                            <div class="text-sm text-green-600 mt-1">Test and preview audio settings</div>
                        </button>
                        <button data-guide="audio-advanced" 
                                class="audio-guide-menu-btn w-full text-left px-4 py-3 rounded bg-purple-50 hover:bg-purple-100 text-purple-700 transition-colors">
                            ⚙️ Advanced Settings
                            <div class="text-sm text-purple-600 mt-1">Configure advanced audio options</div>
                        </button>
                        <button data-guide="audio-troubleshooting" 
                                class="audio-guide-menu-btn w-full text-left px-4 py-3 rounded bg-red-50 hover:bg-red-100 text-red-700 transition-colors">
                            🔧 Troubleshooting
                            <div class="text-sm text-red-600 mt-1">Diagnose and fix audio issues</div>
                        </button>
                    </div>
                </div>
            `;
            document.body.appendChild(guideMenu);

            // Add event listeners
            document.getElementById('close-audio-guide-menu').addEventListener('click', function() {
                guideMenu.remove();
            });

            // Close on backdrop click
            guideMenu.addEventListener('click', function(e) {
                if (e.target === guideMenu) {
                    guideMenu.remove();
                }
            });

            // Add guide button listeners
            guideMenu.querySelectorAll('.audio-guide-menu-btn').forEach(btn => {
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
