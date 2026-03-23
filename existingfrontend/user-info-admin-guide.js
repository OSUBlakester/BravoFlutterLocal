// User Information Admin Interactive Guide System
// Comprehensive guided tours for user management and profile administration

document.addEventListener('DOMContentLoaded', function() {
    // Wait for InteractiveGuide to be available
    function initializeGuides() {
        // Register user admin guides with the InteractiveGuide system
        if (typeof InteractiveGuide !== 'undefined' && InteractiveGuide.registerGuide) {
        
                // User Management Overview Tour
        InteractiveGuide.registerGuide('user-overview', {
            title: '� User Information Management',
            description: 'Learn how to manage user profiles, personal information, and relationships effectively',
            steps: [
                {
                    target: 'body',
                    title: '👋 Welcome to User Information Management',
                    content: `
                        <div class="guide-welcome">
                            <h3>� User Information & Relationships</h3>
                            <p>This admin panel helps you manage:</p>
                            <ul>
                                <li>🎭 Current mood settings for personalized AI responses</li>
                                <li>� General user information and interests</li>
                                <li>🎂 Birthday tracking and reminders</li>
                                <li>👨‍👩‍👧‍👦 Friends & family relationships</li>
                                <li>🏷️ Custom relationship types</li>
                            </ul>
                            <div class="tip">
                                <strong>💡 Key Point:</strong> All information helps personalize the AI assistant's responses and enables meaningful conversations.
                            </div>
                        </div>
                    `,
                    position: 'center'
                },
                {
                    target: '.bg-blue-50',
                    title: '🎭 Setting Current Mood',
                    content: `
                        <div class="guide-step">
                            <h4>Personalize AI Responses with Mood</h4>
                            <p>The current mood setting affects how the AI assistant interacts:</p>
                            <ul>
                                <li><strong>Happy:</strong> Upbeat, enthusiastic responses</li>
                                <li><strong>Calm:</strong> Gentle, soothing interactions</li>
                                <li><strong>Excited:</strong> High-energy, animated conversations</li>
                                <li><strong>Thoughtful:</strong> More reflective, deeper discussions</li>
                            </ul>
                            <div class="action-steps">
                                <strong>Next Steps:</strong>
                                <ol>
                                    <li>Choose a mood from the dropdown menu</li>
                                    <li><strong>⭐ Don't forget to click "Save Mood" button!</strong></li>
                                </ol>
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#user-info-form',
                    title: '� User Information & Interests',
                    content: `
                        <div class="guide-step">
                            <h4>Build a Complete User Profile</h4>
                            <p>Include important details about the user:</p>
                            <ul>
                                <li>🏠 Personal background and living situation</li>
                                <li>🎯 Hobbies, interests, and favorite activities</li>
                                <li>🏥 Important medical or accessibility needs</li>
                                <li>📚 Preferred topics of conversation</li>
                                <li>🚫 Topics to avoid or handle sensitively</li>
                            </ul>
                            <div class="action-steps">
                                <strong>To Save Changes:</strong>
                                <ol>
                                    <li>Add or edit information in the text area</li>
                                    <li><strong>⭐ Scroll down and click "Save User Info" button</strong></li>
                                </ol>
                            </div>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#userBirthdate',
                    title: '🎂 Birthday Management',
                    content: `
                        <div class="guide-step">
                            <h4>Track Important Dates</h4>
                            <p>Setting the user's birthday enables:</p>
                            <ul>
                                <li>🎉 Automatic birthday reminders and celebrations</li>
                                <li>📅 Age-appropriate conversation topics</li>
                                <li>🗓️ Seasonal and holiday personalization</li>
                                <li>📊 Age-relevant suggestions and activities</li>
                            </ul>
                            <div class="action-steps">
                                <strong>Setting the Birthday:</strong>
                                <ol>
                                    <li>Click the date field to open the calendar</li>
                                    <li>Select the user's birth date</li>
                                    <li><strong>⭐ Click "Save Birthdate" to confirm</strong></li>
                                </ol>
                            </div>
                        </div>
                    `,
                    position: 'left'
                },
                {
                    target: 'div.bg-white:nth-of-type(3)',
                    title: '�‍👩‍👧‍👦 Friends & Family Management',
                    content: `
                        <div class="guide-step">
                            <h4>Add Important People</h4>
                            <p>Manage relationships by adding:</p>
                            <ul>
                                <li>👤 <strong>Names:</strong> First name or how they're usually addressed</li>
                                <li>❤️ <strong>Relationship:</strong> Mother, Friend, Caregiver, etc.</li>
                                <li>📝 <strong>About:</strong> Interests, background, personality traits</li>
                                <li>🎂 <strong>Birthday:</strong> For birthday reminders (MM-DD format)</li>
                            </ul>
                            <div class="action-steps">
                                <strong>Adding People:</strong>
                                <ol>
                                    <li>Click "Add Person" button</li>
                                    <li>Fill in name, relationship, and details</li>
                                    <li><strong>⭐ Click "Save" to add the person to the list</strong></li>
                                </ol>
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#manageRelationshipsBtn',
                    title: '🏷️ Custom Relationship Types',
                    content: `
                        <div class="guide-step">
                            <h4>Create Custom Relationships</h4>
                            <p>Customize relationship categories:</p>
                            <ul>
                                <li>➕ Add new relationship types (Therapist, Neighbor, etc.)</li>
                                <li>✏️ Modify existing categories</li>
                                <li>🗑️ Remove unused relationship types</li>
                                <li>📋 View all available relationships</li>
                            </ul>
                            <div class="action-steps">
                                <strong>Managing Relationships:</strong>
                                <ol>
                                    <li>Click "Manage Relationships" button</li>
                                    <li>Add, edit, or remove relationship types</li>
                                    <li><strong>⭐ Use "Save" to confirm changes</strong></li>
                                </ol>
                            </div>
                        </div>
                    `,
                    position: 'left'
                }
            ]
        });

                // User Profile Management Tour
        InteractiveGuide.registerGuide('user-profiles', {
            title: '👤 User Profile Management',
            description: 'Master user profile editing, data management, and customization',
            steps: [
                {
                    target: '#profileEditor, [data-user="profile"]',
                    title: '✏️ Profile Editor Interface',
                    content: `
                        <div class="guide-step">
                            <h4>Edit User Information</h4>
                            <p>Editable profile fields:</p>
                            <ul>
                                <li>📝 <strong>Basic Info:</strong> Name, email, phone</li>
                                <li>🎂 <strong>Personal:</strong> Birthdate, preferences</li>
                                <li>🔐 <strong>Security:</strong> Password, 2FA settings</li>
                                <li>🎨 <strong>Customization:</strong> Themes, layout</li>
                                <li>📱 <strong>Notifications:</strong> Alert preferences</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Practice:</strong> Click to open profile editor
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#userPreferences, [data-user="preferences"]',
                    title: '⚙️ User Preferences',
                    content: `
                        <div class="guide-step">
                            <h4>Customize User Experience</h4>
                            <p>Manage user settings:</p>
                            <ul>
                                <li>🎨 <strong>Theme:</strong> Light, dark, auto</li>
                                <li>🌍 <strong>Language:</strong> Interface localization</li>
                                <li>⏰ <strong>Timezone:</strong> Local time display</li>
                                <li>📧 <strong>Notifications:</strong> Email, push, in-app</li>
                                <li>🔒 <strong>Privacy:</strong> Data sharing controls</li>
                            </ul>
                        </div>
                    `,
                    position: 'bottom'
                },
                {
                    target: '#userActivity, [data-user="activity"]',
                    title: '📊 Activity Tracking',
                    content: `
                        <div class="guide-step">
                            <h4>Monitor User Engagement</h4>
                            <p>Track important metrics:</p>
                            <ul>
                                <li>🕒 Login frequency and duration</li>
                                <li>💬 Messages and interactions</li>
                                <li>📈 Feature usage patterns</li>
                                <li>🎯 Goal completion rates</li>
                                <li>❤️ Satisfaction indicators</li>
                            </ul>
                            <div class="tip">
                                Use activity data to personalize user experience
                            </div>
                        </div>
                    `,
                    position: 'left'
                }
            ]
        });

                // User Data Management Tour
        InteractiveGuide.registerGuide('user-data', {
            title: '💾 User Data Management',
            description: 'Learn to backup, restore, export, and manage user data safely',
            steps: [
                {
                    target: '#dataBackup, [data-user="backup"]',
                    title: '💾 Data Backup System',
                    content: `
                        <div class="guide-step">
                            <h4>Protect User Information</h4>
                            <p>Backup options available:</p>
                            <ul>
                                <li>🔄 <strong>Automatic:</strong> Scheduled daily backups</li>
                                <li>📱 <strong>Manual:</strong> On-demand backup creation</li>
                                <li>☁️ <strong>Cloud:</strong> Secure cloud storage</li>
                                <li>💽 <strong>Local:</strong> Download to device</li>
                                <li>🗜️ <strong>Compressed:</strong> Space-efficient archives</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Try it:</strong> Create a backup now
                            </div>
                        </div>
                    `,
                    position: 'top'
                },
                {
                    target: '#dataExport, [data-user="export"]',
                    title: '📤 Data Export Options',
                    content: `
                        <div class="guide-step">
                            <h4>Export User Data</h4>
                            <p>Available export formats:</p>
                            <ul>
                                <li>📄 <strong>JSON:</strong> Complete data structure</li>
                                <li>📊 <strong>CSV:</strong> Spreadsheet compatible</li>
                                <li>📝 <strong>PDF:</strong> Human-readable reports</li>
                                <li>🗃️ <strong>XML:</strong> Structured data format</li>
                            </ul>
                            <div class="warning">
                                <strong>⚠️ Privacy:</strong> Ensure compliance with data protection laws
                            </div>
                        </div>
                    `,
                    position: 'right'
                },
                {
                    target: '#dataImport, [data-user="import"]',
                    title: '📥 Data Import & Migration',
                    content: `
                        <div class="guide-step">
                            <h4>Import User Information</h4>
                            <p>Supported import sources:</p>
                            <ul>
                                <li>📁 Backup files (.bak, .zip)</li>
                                <li>📊 Spreadsheet files (.csv, .xlsx)</li>
                                <li>📄 JSON data files</li>
                                <li>🔗 External system APIs</li>
                            </ul>
                            <div class="tip">
                                Always validate data before importing
                            </div>
                        </div>
                    `,
                    position: 'bottom'
                }
            ]
        });

                // User Security & Permissions Tour
        InteractiveGuide.registerGuide('user-security', {
            title: '🔒 Security & Permissions',
            description: 'Manage user access, security settings, and permission levels',
            steps: [
                {
                    target: '#permissionMatrix, [data-user="permissions"]',
                    title: '🛡️ Permission Management',
                    content: `
                        <div class="guide-step">
                            <h4>Control User Access</h4>
                            <p>Permission levels:</p>
                            <ul>
                                <li>👑 <strong>Admin:</strong> Full system access</li>
                                <li>👨‍💼 <strong>Moderator:</strong> Content management</li>
                                <li>👤 <strong>User:</strong> Standard features</li>
                                <li>👁️ <strong>Viewer:</strong> Read-only access</li>
                                <li>🚫 <strong>Suspended:</strong> Limited access</li>
                            </ul>
                            <div class="practice-mode">
                                <strong>Practice:</strong> Modify user permissions
                            </div>
                        </div>
                    `,
                    position: 'center'
                },
                {
                    target: '#securitySettings, [data-user="security"]',
                    title: '🔐 Security Configuration',
                    content: `
                        <div class="guide-step">
                            <h4>Enhance Account Security</h4>
                            <p>Security features:</p>
                            <ul>
                                <li>🔑 Two-factor authentication</li>
                                <li>🔒 Password requirements</li>
                                <li>🕒 Session timeout settings</li>
                                <li>🌐 IP address restrictions</li>
                                <li>📱 Device management</li>
                            </ul>
                        </div>
                    `,
                    position: 'left'
                },
                {
                    target: '#auditLog, [data-user="audit"]',
                    title: '📝 Security Audit Log',
                    content: `
                        <div class="guide-step">
                            <h4>Track Security Events</h4>
                            <p>Monitored activities:</p>
                            <ul>
                                <li>🔓 Login attempts and locations</li>
                                <li>🔄 Permission changes</li>
                                <li>📝 Profile modifications</li>
                                <li>🗑️ Data deletions</li>
                                <li>⚠️ Suspicious activities</li>
                            </ul>
                            <div class="tip">
                                Review audit logs regularly for security
                            </div>
                        </div>
                    `,
                    position: 'right'
                }
            ]
        });

        // Connect help button to directly start User Overview guide
        function setupHelpButton() {
            const helpButton = document.getElementById('help-icon');
            if (helpButton) {
                helpButton.addEventListener('click', function() {
                    // Start the User Overview guide directly
                    InteractiveGuide.startGuide('user-overview');
                });
            }
        }

        // Create guide menu modal (only shown when help button is clicked)
        function showUserGuideMenu() {
            // Remove existing menu if any
            const existingMenu = document.getElementById('user-guide-menu');
            if (existingMenu) {
                existingMenu.remove();
            }

            const guideMenu = document.createElement('div');
            guideMenu.id = 'user-guide-menu';
            guideMenu.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
            guideMenu.innerHTML = `
                <div class="bg-white rounded-lg shadow-lg border p-6 max-w-md w-full mx-4">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="font-bold text-xl text-gray-800">👥 User Admin Guides</h3>
                        <button id="close-guide-menu" class="text-gray-400 hover:text-gray-600 text-2xl">
                            ✕
                        </button>
                    </div>
                    <div class="space-y-3">
                        <button data-guide="user-overview" 
                                class="guide-menu-btn w-full text-left px-4 py-3 rounded bg-blue-50 hover:bg-blue-100 text-blue-700 transition-colors">
                            📚 User Overview
                            <div class="text-sm text-blue-600 mt-1">Learn the basics of user management</div>
                        </button>
                        <button data-guide="user-profiles" 
                                class="guide-menu-btn w-full text-left px-4 py-3 rounded bg-green-50 hover:bg-green-100 text-green-700 transition-colors">
                            👤 Profile Management
                            <div class="text-sm text-green-600 mt-1">Edit and manage user profiles</div>
                        </button>
                        <button data-guide="user-data" 
                                class="guide-menu-btn w-full text-left px-4 py-3 rounded bg-purple-50 hover:bg-purple-100 text-purple-700 transition-colors">
                            💾 Data Management
                            <div class="text-sm text-purple-600 mt-1">Backup, export, and import user data</div>
                        </button>
                        <button data-guide="user-security" 
                                class="guide-menu-btn w-full text-left px-4 py-3 rounded bg-red-50 hover:bg-red-100 text-red-700 transition-colors">
                            🔒 Security & Permissions
                            <div class="text-sm text-red-600 mt-1">Manage access and security settings</div>
                        </button>
                    </div>
                </div>
            `;
            document.body.appendChild(guideMenu);

            // Add event listeners
            document.getElementById('close-guide-menu').addEventListener('click', function() {
                guideMenu.remove();
            });

            // Close on backdrop click
            guideMenu.addEventListener('click', function(e) {
                if (e.target === guideMenu) {
                    guideMenu.remove();
                }
            });

            // Add guide button listeners
            guideMenu.querySelectorAll('.guide-menu-btn').forEach(btn => {
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
