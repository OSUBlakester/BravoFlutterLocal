class AvatarAdmin {
    constructor() {
        this.users = [];
        this.presets = [];
        this.selectedPreset = null;
        this.currentEditingUser = null;
        this.unsavedChanges = new Set();
        
        this.init();
    }

    async init() {
        console.log('Initializing Avatar Admin...');
        
        // Setup event listeners
        this.setupEventListeners();
        
        // Load initial data
        await this.loadUsers();
        await this.loadPresets();
        
        // Setup auto-save
        this.setupAutoSave();
    }

    setupEventListeners() {
        // Main action buttons
        document.getElementById('save-all-button')?.addEventListener('click', () => this.saveAllChanges());
        document.getElementById('export-presets-button')?.addEventListener('click', () => this.exportPresets());
        document.getElementById('create-preset-button')?.addEventListener('click', () => this.createPreset());
        document.getElementById('bulk-assign-button')?.addEventListener('click', () => this.showBulkAssign());
        document.getElementById('reset-defaults-button')?.addEventListener('click', () => this.resetToDefaults());
        
        // Refresh buttons
        document.getElementById('refresh-users')?.addEventListener('click', () => this.loadUsers());
        document.getElementById('refresh-presets')?.addEventListener('click', () => this.loadPresets());
        
        // Filter
        document.getElementById('user-filter')?.addEventListener('input', (e) => this.filterUsers(e.target.value));
        
        // Avatar editor modal
        document.getElementById('close-editor')?.addEventListener('click', () => this.closeEditor());
        document.getElementById('cancel-edit')?.addEventListener('click', () => this.closeEditor());
        document.getElementById('save-avatar')?.addEventListener('click', () => this.saveCurrentAvatar());
        
        // Bulk assign modal
        document.getElementById('close-bulk-assign')?.addEventListener('click', () => this.closeBulkAssign());
        document.getElementById('cancel-bulk-assign')?.addEventListener('click', () => this.closeBulkAssign());
        document.getElementById('apply-bulk-assign')?.addEventListener('click', () => this.applyBulkAssign());
        document.getElementById('select-all-users')?.addEventListener('click', () => this.selectAllUsers());
        document.getElementById('deselect-all-users')?.addEventListener('click', () => this.deselectAllUsers());

        // Handle clicks outside modals to close them
        document.getElementById('avatar-editor-modal')?.addEventListener('click', (e) => {
            if (e.target.id === 'avatar-editor-modal') this.closeEditor();
        });
        document.getElementById('bulk-assign-modal')?.addEventListener('click', (e) => {
            if (e.target.id === 'bulk-assign-modal') this.closeBulkAssign();
        });
        
        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.closeEditor();
                this.closeBulkAssign();
            }
            if (e.key === 's' && (e.ctrlKey || e.metaKey)) {
                e.preventDefault();
                this.saveAllChanges();
            }
        });
    }

    async loadUsers() {
        console.log('Loading users...');
        const container = document.getElementById('users-container');
        const loading = document.getElementById('users-loading');
        const countElement = document.getElementById('user-count');
        
        if (loading) loading.classList.remove('hidden');
        if (container) container.innerHTML = '';
        
        try {
            const response = await fetch('/api/admin/users');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            this.users = data.users || [];
            
            this.renderUsers();
            
            if (countElement) {
                countElement.textContent = `${this.users.length} users`;
            }
            
        } catch (error) {
            console.error('Error loading users:', error);
            this.showMessage('Failed to load users', 'error');
            
            // Use demo data for development
            this.users = this.generateDemoUsers();
            this.renderUsers();
            if (countElement) {
                countElement.textContent = `${this.users.length} users (demo)`;
            }
        } finally {
            if (loading) loading.classList.add('hidden');
        }
    }

    async loadPresets() {
        console.log('Loading avatar presets...');
        const container = document.getElementById('presets-container');
        
        try {
            const response = await fetch('/api/admin/avatar-presets');
            let data;
            
            if (response.ok) {
                data = await response.json();
                this.presets = data.presets || [];
            } else {
                // Use default presets if API not available
                this.presets = this.getDefaultPresets();
            }
            
            this.renderPresets();
            
        } catch (error) {
            console.error('Error loading presets:', error);
            this.presets = this.getDefaultPresets();
            this.renderPresets();
        }
    }

    renderUsers() {
        const container = document.getElementById('users-container');
        if (!container) return;
        
        const filteredUsers = this.getFilteredUsers();
        
        if (filteredUsers.length === 0) {
            container.innerHTML = `
                <div class="col-span-full text-center py-8 text-gray-500">
                    <i class="fas fa-users text-4xl mb-4"></i>
                    <p>No users found</p>
                </div>
            `;
            return;
        }
        
        container.innerHTML = filteredUsers.map(user => this.renderUserCard(user)).join('');
        
        // Add click handlers for edit buttons
        container.querySelectorAll('[data-edit-user]').forEach(button => {
            button.addEventListener('click', (e) => {
                const username = e.target.closest('[data-edit-user]').dataset.editUser;
                this.editUserAvatar(username);
            });
        });
    }

    renderUserCard(user) {
        const avatarUrl = this.generateAvatarUrl(user.avatarConfig || this.getDefaultAvatarConfig());
        const hasCustomAvatar = user.avatarConfig && Object.keys(user.avatarConfig).length > 0;
        const isModified = this.unsavedChanges.has(user.username);
        
        return `
            <div class="user-card bg-gray-50 border border-gray-200 rounded-lg p-4 ${isModified ? 'ring-2 ring-orange-200' : ''}">
                <div class="flex items-center space-x-4">
                    <div class="relative">
                        <img src="${avatarUrl}" alt="${user.username}" class="avatar-preview w-16 h-16">
                        ${hasCustomAvatar ? '<div class="absolute -top-1 -right-1 w-4 h-4 bg-green-500 rounded-full border-2 border-white"></div>' : ''}
                        ${isModified ? '<div class="absolute -bottom-1 -right-1 w-4 h-4 bg-orange-500 rounded-full border-2 border-white"><i class="fas fa-exclamation text-white text-xs"></i></div>' : ''}
                    </div>
                    <div class="flex-1">
                        <h3 class="font-semibold text-gray-800">${user.displayName || user.username}</h3>
                        <p class="text-sm text-gray-600">${user.username}</p>
                        <p class="text-xs text-gray-500">
                            ${hasCustomAvatar ? 'Custom Avatar' : 'Default Avatar'}
                            ${user.lastUsed ? ` • Last used: ${new Date(user.lastUsed).toLocaleDateString()}` : ''}
                        </p>
                    </div>
                </div>
                <div class="mt-3 flex space-x-2">
                    <button data-edit-user="${user.username}" class="flex-1 bg-blue-600 hover:bg-blue-700 text-white text-sm px-3 py-2 rounded-md flex items-center justify-center space-x-1">
                        <i class="fas fa-edit"></i>
                        <span>Edit Avatar</span>
                    </button>
                    <button onclick="avatarAdmin.previewAvatar('${user.username}')" class="bg-gray-600 hover:bg-gray-700 text-white text-sm px-3 py-2 rounded-md">
                        <i class="fas fa-eye"></i>
                    </button>
                    ${hasCustomAvatar ? `<button onclick="avatarAdmin.resetUserAvatar('${user.username}')" class="bg-orange-600 hover:bg-orange-700 text-white text-sm px-3 py-2 rounded-md"><i class="fas fa-undo"></i></button>` : ''}
                </div>
            </div>
        `;
    }

    renderPresets() {
        const container = document.getElementById('presets-container');
        if (!container) return;
        
        if (this.presets.length === 0) {
            container.innerHTML = `
                <div class="col-span-full text-center py-4 text-gray-500">
                    <p>No presets available</p>
                </div>
            `;
            return;
        }
        
        container.innerHTML = this.presets.map(preset => this.renderPresetCard(preset)).join('');
        
        // Add click handlers for presets
        container.querySelectorAll('[data-preset-id]').forEach(card => {
            card.addEventListener('click', (e) => {
                const presetId = e.target.closest('[data-preset-id]').dataset.presetId;
                this.selectPreset(presetId);
            });
        });
    }

    renderPresetCard(preset) {
        const avatarUrl = this.generateAvatarUrl(preset.config);
        const isSelected = this.selectedPreset === preset.id;
        
        return `
            <div data-preset-id="${preset.id}" class="preset-card border-2 border-gray-200 rounded-lg p-3 text-center ${isSelected ? 'selected' : ''}">
                <img src="${avatarUrl}" alt="${preset.name}" class="avatar-preview w-12 h-12 mx-auto mb-2">
                <h4 class="text-sm font-medium text-gray-800 truncate">${preset.name}</h4>
                <p class="text-xs text-gray-500">${preset.description || ''}</p>
                <div class="mt-2 flex justify-center space-x-1">
                    <button onclick="avatarAdmin.editPreset('${preset.id}')" class="text-blue-600 hover:text-blue-800 text-xs">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button onclick="avatarAdmin.duplicatePreset('${preset.id}')" class="text-green-600 hover:text-green-800 text-xs">
                        <i class="fas fa-copy"></i>
                    </button>
                    ${!preset.isDefault ? `<button onclick="avatarAdmin.deletePreset('${preset.id}')" class="text-red-600 hover:text-red-800 text-xs"><i class="fas fa-trash"></i></button>` : ''}
                </div>
            </div>
        `;
    }

    async editUserAvatar(username) {
        const user = this.users.find(u => u.username === username);
        if (!user) return;
        
        this.currentEditingUser = user;
        
        // Show modal
        const modal = document.getElementById('avatar-editor-modal');
        const title = document.getElementById('editor-title');
        const container = document.getElementById('avatar-editor-container');
        
        if (title) title.textContent = `Edit Avatar for ${user.displayName || user.username}`;
        if (modal) modal.classList.remove('hidden');
        
        // Load avatar editor
        if (container && window.AvatarSelector) {
            try {
                // Create a new avatar selector instance for editing
                const avatarConfig = user.avatarConfig || this.getDefaultAvatarConfig();
                
                container.innerHTML = `
                    <div id="temp-avatar-editor" class="h-full p-4">
                        <div class="h-full flex">
                            <div class="w-1/3 pr-4">
                                <div class="sticky top-4">
                                    <h4 class="font-semibold mb-2">Preview</h4>
                                    <div id="temp-avatar-preview" class="text-center mb-4">
                                        <img id="temp-avatar-img" src="${this.generateAvatarUrl(avatarConfig)}" alt="Avatar Preview" class="w-32 h-32 rounded-full mx-auto border-4 border-gray-200">
                                    </div>
                                    <div class="space-y-2">
                                        <button id="temp-reset-avatar" class="w-full bg-gray-600 hover:bg-gray-700 text-white px-3 py-2 rounded-md text-sm">
                                            <i class="fas fa-undo mr-2"></i>Reset to Default
                                        </button>
                                        <button id="temp-random-avatar" class="w-full bg-purple-600 hover:bg-purple-700 text-white px-3 py-2 rounded-md text-sm">
                                            <i class="fas fa-dice mr-2"></i>Random Avatar
                                        </button>
                                    </div>
                                </div>
                            </div>
                            <div class="flex-1 overflow-y-auto">
                                <div id="temp-avatar-controls" class="space-y-4">
                                    <!-- Avatar controls will be generated here -->
                                </div>
                            </div>
                        </div>
                    </div>
                `;
                
                this.setupTempAvatarEditor(avatarConfig);
                
            } catch (error) {
                console.error('Error setting up avatar editor:', error);
                container.innerHTML = `
                    <div class="flex items-center justify-center h-full text-gray-500">
                        <div class="text-center">
                            <i class="fas fa-exclamation-triangle text-4xl mb-4"></i>
                            <p>Failed to load avatar editor</p>
                        </div>
                    </div>
                `;
            }
        }
    }

    setupTempAvatarEditor(initialConfig) {
        const controls = document.getElementById('temp-avatar-controls');
        const preview = document.getElementById('temp-avatar-img');
        
        let currentConfig = { ...initialConfig };
        
        const updatePreview = () => {
            if (preview) {
                preview.src = this.generateAvatarUrl(currentConfig);
            }
        };
        
        // Generate controls for each avatar option
        const avatarOptions = this.getAvatarOptions();
        let controlsHtml = '';
        
        Object.keys(avatarOptions).forEach(category => {
            controlsHtml += `
                <div class="border border-gray-200 rounded-lg p-4">
                    <h5 class="font-medium text-gray-800 mb-3 capitalize">${category.replace(/([A-Z])/g, ' $1').trim()}</h5>
                    <div class="grid grid-cols-3 gap-2">
                        ${avatarOptions[category].map(option => `
                            <button class="avatar-option-btn px-3 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50 ${currentConfig[category] === option.value ? 'bg-blue-100 border-blue-500 text-blue-700' : ''}" 
                                    data-category="${category}" data-value="${option.value}">
                                ${option.label}
                            </button>
                        `).join('')}
                    </div>
                </div>
            `;
        });
        
        if (controls) {
            controls.innerHTML = controlsHtml;
            
            // Add event listeners to option buttons
            controls.querySelectorAll('.avatar-option-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const category = e.target.dataset.category;
                    const value = e.target.dataset.value;
                    
                    // Update current config
                    currentConfig[category] = value;
                    
                    // Update button states
                    controls.querySelectorAll(`[data-category="${category}"]`).forEach(b => {
                        b.classList.remove('bg-blue-100', 'border-blue-500', 'text-blue-700');
                        b.classList.add('border-gray-300');
                    });
                    e.target.classList.add('bg-blue-100', 'border-blue-500', 'text-blue-700');
                    e.target.classList.remove('border-gray-300');
                    
                    updatePreview();
                });
            });
        }
        
        // Setup reset button
        document.getElementById('temp-reset-avatar')?.addEventListener('click', () => {
            currentConfig = this.getDefaultAvatarConfig();
            this.setupTempAvatarEditor(currentConfig);
        });
        
        // Setup random button
        document.getElementById('temp-random-avatar')?.addEventListener('click', () => {
            currentConfig = this.generateRandomAvatarConfig();
            this.setupTempAvatarEditor(currentConfig);
        });
        
        // Store current config for saving
        this.currentEditingConfig = currentConfig;
    }

    async saveCurrentAvatar() {
        if (!this.currentEditingUser || !this.currentEditingConfig) return;
        
        try {
            // Update user config
            this.currentEditingUser.avatarConfig = { ...this.currentEditingConfig };
            
            // Mark as changed
            this.unsavedChanges.add(this.currentEditingUser.username);
            
            // Close editor
            this.closeEditor();
            
            // Refresh display
            this.renderUsers();
            
            this.showMessage(`Avatar updated for ${this.currentEditingUser.displayName || this.currentEditingUser.username}`, 'success');
            
        } catch (error) {
            console.error('Error saving avatar:', error);
            this.showMessage('Failed to save avatar', 'error');
        }
    }

    closeEditor() {
        const modal = document.getElementById('avatar-editor-modal');
        if (modal) modal.classList.add('hidden');
        
        this.currentEditingUser = null;
        this.currentEditingConfig = null;
    }

    showBulkAssign() {
        const modal = document.getElementById('bulk-assign-modal');
        const presetSelector = document.getElementById('bulk-preset-selector');
        const userSelector = document.getElementById('bulk-user-selector');
        
        if (modal) modal.classList.remove('hidden');
        
        // Populate presets
        if (presetSelector) {
            presetSelector.innerHTML = this.presets.map(preset => `
                <div class="preset-option text-center border-2 border-gray-200 rounded-lg p-2 cursor-pointer hover:border-blue-300" data-preset-id="${preset.id}">
                    <img src="${this.generateAvatarUrl(preset.config)}" alt="${preset.name}" class="w-12 h-12 mx-auto rounded-full mb-1">
                    <p class="text-xs font-medium">${preset.name}</p>
                </div>
            `).join('');
            
            // Add preset selection handlers
            presetSelector.querySelectorAll('.preset-option').forEach(option => {
                option.addEventListener('click', (e) => {
                    presetSelector.querySelectorAll('.preset-option').forEach(o => {
                        o.classList.remove('border-blue-500', 'bg-blue-50');
                        o.classList.add('border-gray-200');
                    });
                    e.currentTarget.classList.add('border-blue-500', 'bg-blue-50');
                    e.currentTarget.classList.remove('border-gray-200');
                    
                    this.selectedBulkPreset = e.currentTarget.dataset.presetId;
                });
            });
        }
        
        // Populate users
        if (userSelector) {
            userSelector.innerHTML = this.users.map(user => `
                <label class="flex items-center space-x-3 p-2 hover:bg-gray-50 rounded">
                    <input type="checkbox" class="bulk-user-checkbox" data-username="${user.username}">
                    <img src="${this.generateAvatarUrl(user.avatarConfig || this.getDefaultAvatarConfig())}" alt="${user.username}" class="w-8 h-8 rounded-full">
                    <div class="flex-1">
                        <p class="font-medium text-sm">${user.displayName || user.username}</p>
                        <p class="text-xs text-gray-500">${user.username}</p>
                    </div>
                </label>
            `).join('');
        }
    }

    closeBulkAssign() {
        const modal = document.getElementById('bulk-assign-modal');
        if (modal) modal.classList.add('hidden');
        
        this.selectedBulkPreset = null;
    }

    selectAllUsers() {
        document.querySelectorAll('.bulk-user-checkbox').forEach(checkbox => {
            checkbox.checked = true;
        });
    }

    deselectAllUsers() {
        document.querySelectorAll('.bulk-user-checkbox').forEach(checkbox => {
            checkbox.checked = false;
        });
    }

    async applyBulkAssign() {
        if (!this.selectedBulkPreset) {
            this.showMessage('Please select a preset first', 'warning');
            return;
        }
        
        const selectedUsers = Array.from(document.querySelectorAll('.bulk-user-checkbox:checked'))
            .map(checkbox => checkbox.dataset.username);
        
        if (selectedUsers.length === 0) {
            this.showMessage('Please select at least one user', 'warning');
            return;
        }
        
        const preset = this.presets.find(p => p.id === this.selectedBulkPreset);
        if (!preset) return;
        
        // Apply preset to selected users
        selectedUsers.forEach(username => {
            const user = this.users.find(u => u.username === username);
            if (user) {
                user.avatarConfig = { ...preset.config };
                this.unsavedChanges.add(username);
            }
        });
        
        this.closeBulkAssign();
        this.renderUsers();
        
        this.showMessage(`Applied ${preset.name} to ${selectedUsers.length} users`, 'success');
    }

    async saveAllChanges() {
        if (this.unsavedChanges.size === 0) {
            this.showMessage('No changes to save', 'info');
            return;
        }
        
        const changedUsers = Array.from(this.unsavedChanges).map(username => 
            this.users.find(u => u.username === username)
        ).filter(Boolean);
        
        try {
            // Save each user's avatar config
            const savePromises = changedUsers.map(user => 
                fetch(`/api/admin/users/${user.username}/avatar`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ avatarConfig: user.avatarConfig })
                })
            );
            
            await Promise.all(savePromises);
            
            // Clear unsaved changes
            this.unsavedChanges.clear();
            this.renderUsers();
            
            this.showMessage(`Saved avatar changes for ${changedUsers.length} users`, 'success');
            
        } catch (error) {
            console.error('Error saving changes:', error);
            this.showMessage('Failed to save some changes', 'error');
        }
    }

    getFilteredUsers() {
        const filter = document.getElementById('user-filter')?.value.toLowerCase() || '';
        if (!filter) return this.users;
        
        return this.users.filter(user => 
            user.username.toLowerCase().includes(filter) ||
            (user.displayName && user.displayName.toLowerCase().includes(filter))
        );
    }

    filterUsers(filter) {
        this.renderUsers();
    }

    generateAvatarUrl(config) {
        const baseUrl = 'https://avataaars.io/';
        const params = new URLSearchParams();
        
        Object.keys(config).forEach(key => {
            if (config[key]) {
                params.append(key, config[key]);
            }
        });
        
        return baseUrl + '?' + params.toString();
    }

    getDefaultAvatarConfig() {
        return {
            avatarStyle: 'Circle',
            topType: 'ShortHairShortFlat',
            accessoriesType: 'Blank',
            hairColor: 'BrownDark',
            facialHairType: 'Blank',
            clotheType: 'BlazerShirt',
            clotheColor: 'BlueGray',
            eyeType: 'Default',
            eyebrowType: 'Default',
            mouthType: 'Default',
            skinColor: 'Light'
        };
    }

    getAvatarOptions() {
        return {
            topType: [
                { value: 'NoHair', label: 'No Hair' },
                { value: 'Eyepatch', label: 'Eyepatch' },
                { value: 'Hat', label: 'Hat' },
                { value: 'Hijab', label: 'Hijab' },
                { value: 'Turban', label: 'Turban' },
                { value: 'WinterHat1', label: 'Winter Hat 1' },
                { value: 'WinterHat2', label: 'Winter Hat 2' },
                { value: 'WinterHat3', label: 'Winter Hat 3' },
                { value: 'WinterHat4', label: 'Winter Hat 4' },
                { value: 'LongHairBigHair', label: 'Long Big Hair' },
                { value: 'LongHairBob', label: 'Long Bob' },
                { value: 'LongHairBun', label: 'Long Bun' },
                { value: 'LongHairCurly', label: 'Long Curly' },
                { value: 'LongHairCurvy', label: 'Long Curvy' },
                { value: 'LongHairDreads', label: 'Long Dreads' },
                { value: 'LongHairFrida', label: 'Long Frida' },
                { value: 'LongHairFro', label: 'Long Fro' },
                { value: 'LongHairFroBand', label: 'Long Fro Band' },
                { value: 'LongHairNotTooLong', label: 'Long Not Too Long' },
                { value: 'LongHairShavedSides', label: 'Long Shaved Sides' },
                { value: 'LongHairMiaWallace', label: 'Long Mia Wallace' },
                { value: 'LongHairStraight', label: 'Long Straight' },
                { value: 'LongHairStraight2', label: 'Long Straight 2' },
                { value: 'LongHairStraightStrand', label: 'Long Straight Strand' },
                { value: 'ShortHairDreads01', label: 'Short Dreads 01' },
                { value: 'ShortHairDreads02', label: 'Short Dreads 02' },
                { value: 'ShortHairFrizzle', label: 'Short Frizzle' },
                { value: 'ShortHairShaggyMullet', label: 'Short Shaggy Mullet' },
                { value: 'ShortHairShortCurly', label: 'Short Curly' },
                { value: 'ShortHairShortFlat', label: 'Short Flat' },
                { value: 'ShortHairShortRound', label: 'Short Round' },
                { value: 'ShortHairShortWaved', label: 'Short Waved' },
                { value: 'ShortHairSides', label: 'Short Sides' },
                { value: 'ShortHairTheCaesar', label: 'The Caesar' },
                { value: 'ShortHairTheCaesarSidePart', label: 'Caesar Side Part' }
            ],
            accessoriesType: [
                { value: 'Blank', label: 'None' },
                { value: 'Kurt', label: 'Kurt' },
                { value: 'Prescription01', label: 'Prescription 1' },
                { value: 'Prescription02', label: 'Prescription 2' },
                { value: 'Round', label: 'Round' },
                { value: 'Sunglasses', label: 'Sunglasses' },
                { value: 'Wayfarers', label: 'Wayfarers' }
            ],
            hairColor: [
                { value: 'Auburn', label: 'Auburn' },
                { value: 'Black', label: 'Black' },
                { value: 'Blonde', label: 'Blonde' },
                { value: 'BlondeGolden', label: 'Golden Blonde' },
                { value: 'Brown', label: 'Brown' },
                { value: 'BrownDark', label: 'Dark Brown' },
                { value: 'PastelPink', label: 'Pastel Pink' },
                { value: 'Platinum', label: 'Platinum' },
                { value: 'Red', label: 'Red' },
                { value: 'SilverGray', label: 'Silver Gray' }
            ],
            facialHairType: [
                { value: 'Blank', label: 'None' },
                { value: 'BeardMedium', label: 'Beard Medium' },
                { value: 'BeardLight', label: 'Beard Light' },
                { value: 'BeardMagestic', label: 'Beard Majestic' },
                { value: 'MoustacheFancy', label: 'Moustache Fancy' },
                { value: 'MoustacheMagnum', label: 'Moustache Magnum' }
            ],
            clotheType: [
                { value: 'BlazerShirt', label: 'Blazer Shirt' },
                { value: 'BlazerSweater', label: 'Blazer Sweater' },
                { value: 'CollarSweater', label: 'Collar Sweater' },
                { value: 'GraphicShirt', label: 'Graphic Shirt' },
                { value: 'Hoodie', label: 'Hoodie' },
                { value: 'Overall', label: 'Overall' },
                { value: 'ShirtCrewNeck', label: 'Crew Neck' },
                { value: 'ShirtScoopNeck', label: 'Scoop Neck' },
                { value: 'ShirtVNeck', label: 'V Neck' }
            ],
            eyeType: [
                { value: 'Default', label: 'Default' },
                { value: 'Close', label: 'Close' },
                { value: 'Cry', label: 'Cry' },
                { value: 'Dizzy', label: 'Dizzy' },
                { value: 'EyeRoll', label: 'Eye Roll' },
                { value: 'Happy', label: 'Happy' },
                { value: 'Hearts', label: 'Hearts' },
                { value: 'Side', label: 'Side' },
                { value: 'Squint', label: 'Squint' },
                { value: 'Surprised', label: 'Surprised' },
                { value: 'Wink', label: 'Wink' },
                { value: 'WinkWacky', label: 'Wink Wacky' }
            ],
            eyebrowType: [
                { value: 'Default', label: 'Default' },
                { value: 'DefaultNatural', label: 'Default Natural' },
                { value: 'AngryNatural', label: 'Angry Natural' },
                { value: 'FlatNatural', label: 'Flat Natural' },
                { value: 'RaisedExcited', label: 'Raised Excited' },
                { value: 'RaisedExcitedNatural', label: 'Raised Excited Natural' },
                { value: 'SadConcerned', label: 'Sad Concerned' },
                { value: 'SadConcernedNatural', label: 'Sad Concerned Natural' },
                { value: 'UnibrowNatural', label: 'Unibrow Natural' },
                { value: 'UpDown', label: 'Up Down' },
                { value: 'UpDownNatural', label: 'Up Down Natural' }
            ],
            mouthType: [
                { value: 'Default', label: 'Default' },
                { value: 'Concerned', label: 'Concerned' },
                { value: 'Disbelief', label: 'Disbelief' },
                { value: 'Eating', label: 'Eating' },
                { value: 'Grimace', label: 'Grimace' },
                { value: 'Sad', label: 'Sad' },
                { value: 'ScreamOpen', label: 'Scream Open' },
                { value: 'Serious', label: 'Serious' },
                { value: 'Smile', label: 'Smile' },
                { value: 'Tongue', label: 'Tongue' },
                { value: 'Twinkle', label: 'Twinkle' },
                { value: 'Vomit', label: 'Vomit' }
            ],
            skinColor: [
                { value: 'Tanned', label: 'Tanned' },
                { value: 'Yellow', label: 'Yellow' },
                { value: 'Pale', label: 'Pale' },
                { value: 'Light', label: 'Light' },
                { value: 'Brown', label: 'Brown' },
                { value: 'DarkBrown', label: 'Dark Brown' },
                { value: 'Black', label: 'Black' }
            ]
        };
    }

    generateRandomAvatarConfig() {
        const options = this.getAvatarOptions();
        const config = {};
        
        Object.keys(options).forEach(category => {
            const categoryOptions = options[category];
            const randomOption = categoryOptions[Math.floor(Math.random() * categoryOptions.length)];
            config[category] = randomOption.value;
        });
        
        config.avatarStyle = 'Circle';
        return config;
    }

    getDefaultPresets() {
        return [
            {
                id: 'default',
                name: 'Default',
                description: 'Standard avatar',
                isDefault: true,
                config: this.getDefaultAvatarConfig()
            },
            {
                id: 'happy',
                name: 'Happy',
                description: 'Cheerful expression',
                config: { ...this.getDefaultAvatarConfig(), eyeType: 'Happy', mouthType: 'Smile' }
            },
            {
                id: 'cool',
                name: 'Cool',
                description: 'Sunglasses and attitude',
                config: { ...this.getDefaultAvatarConfig(), accessoriesType: 'Sunglasses', mouthType: 'Serious' }
            },
            {
                id: 'professional',
                name: 'Professional',
                description: 'Business attire',
                config: { ...this.getDefaultAvatarConfig(), clotheType: 'BlazerShirt', accessoriesType: 'Prescription01' }
            }
        ];
    }

    generateDemoUsers() {
        return [
            {
                username: 'alice',
                displayName: 'Alice Johnson',
                lastUsed: '2024-01-15',
                avatarConfig: null
            },
            {
                username: 'bob',
                displayName: 'Bob Smith', 
                lastUsed: '2024-01-14',
                avatarConfig: { ...this.getDefaultAvatarConfig(), eyeType: 'Happy', mouthType: 'Smile' }
            },
            {
                username: 'charlie',
                displayName: 'Charlie Brown',
                lastUsed: '2024-01-13',
                avatarConfig: { ...this.getDefaultAvatarConfig(), accessoriesType: 'Sunglasses' }
            },
            {
                username: 'diana',
                displayName: 'Diana Prince',
                lastUsed: '2024-01-12',
                avatarConfig: null
            },
            {
                username: 'test_user',
                displayName: 'Test User',
                lastUsed: '2024-01-16',
                avatarConfig: { ...this.getDefaultAvatarConfig(), topType: 'LongHairBob', skinColor: 'Tanned' }
            }
        ];
    }

    showMessage(text, type = 'info') {
        const container = document.getElementById('message-container');
        if (!container) return;
        
        const colors = {
            success: 'bg-green-500',
            error: 'bg-red-500',
            warning: 'bg-yellow-500',
            info: 'bg-blue-500'
        };
        
        const message = document.createElement('div');
        message.className = `${colors[type]} text-white px-4 py-2 rounded-lg shadow-lg transition-all duration-300 transform translate-x-full`;
        message.textContent = text;
        
        container.appendChild(message);
        
        // Animate in
        setTimeout(() => {
            message.classList.remove('translate-x-full');
        }, 10);
        
        // Remove after 5 seconds
        setTimeout(() => {
            message.classList.add('translate-x-full');
            setTimeout(() => {
                if (message.parentNode) {
                    message.parentNode.removeChild(message);
                }
            }, 300);
        }, 5000);
    }

    setupAutoSave() {
        // Auto-save every 5 minutes if there are unsaved changes
        setInterval(() => {
            if (this.unsavedChanges.size > 0) {
                console.log('Auto-saving changes...');
                this.saveAllChanges();
            }
        }, 300000); // 5 minutes
    }

    async exportPresets() {
        try {
            const data = {
                presets: this.presets,
                exportDate: new Date().toISOString(),
                version: '1.0'
            };
            
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            a.download = `avatar-presets-${new Date().toISOString().split('T')[0]}.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            
            URL.revokeObjectURL(url);
            
            this.showMessage('Presets exported successfully', 'success');
            
        } catch (error) {
            console.error('Error exporting presets:', error);
            this.showMessage('Failed to export presets', 'error');
        }
    }
}

// Initialize avatar admin when page loads
let avatarAdmin;

document.addEventListener('DOMContentLoaded', () => {
    avatarAdmin = new AvatarAdmin();
});

// Export for global access
window.avatarAdmin = avatarAdmin;