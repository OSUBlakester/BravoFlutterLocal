// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

let userInfoTextarea = null;
let saveInfoButton = null;
let infoSaveStatus = null;

let userBirthdateInput = null;
let saveBirthdaysButton = null;
let birthdaySaveStatus = null;

// Friends & Family Elements
let friendsFamilyTableBody = null;
let addFriendsFamilyRowButton = null;
let saveFriendsFamilyButton = null;
let friendsFamilySaveStatus = null;
let relationshipsList = null;
let newRelationshipInput = null;
let addRelationshipBtn = null;

let hamburgerBtn = null;     
let adminNavDropdown = null;  

// --- State Variables ---
let currentUserInfo = '';
let currentBirthdays = { userBirthdate: null, friendsFamily: [] };
let currentFriendsFamily = { friends_family: [], available_relationships: [] };


// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("user_info_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        userInfoTextarea = document.getElementById('user-info');
        saveInfoButton = document.getElementById('saveInfoButton');
        infoSaveStatus = document.getElementById('info-save-status');

        // Birthday Elements
        userBirthdateInput = document.getElementById('userBirthdate');
        saveBirthdaysButton = document.getElementById('saveBirthdaysButton');
        birthdaySaveStatus = document.getElementById('birthday-save-status');

        // Friends & Family Elements
        friendsFamilyTableBody = document.getElementById('friendsFamilyTbody');
        addFriendsFamilyRowButton = document.getElementById('addFriendsFamilyRow');
        saveFriendsFamilyButton = document.getElementById('saveFriendsFamilyButton');
        friendsFamilySaveStatus = document.getElementById('friends-family-save-status');
        relationshipsList = document.getElementById('relationshipsList');
        newRelationshipInput = document.getElementById('newRelationship');
        addRelationshipBtn = document.getElementById('addRelationshipBtn');

        // Hamburger menu logic
        hamburgerBtn = document.getElementById('hamburger-btn');
        adminNavDropdown = document.getElementById('admin-nav-dropdown');  
        

        // Basic check for essential elements
        if (!userInfoTextarea || !saveInfoButton || !infoSaveStatus || !userBirthdateInput || 
            !saveBirthdaysButton || !birthdaySaveStatus || !friendsFamilyTableBody || 
            !addFriendsFamilyRowButton || !saveFriendsFamilyButton || !friendsFamilySaveStatus ||
            !relationshipsList || !newRelationshipInput || !addRelationshipBtn ||
            !hamburgerBtn || !adminNavDropdown) {
            console.error("CRITICAL ERROR: One or more essential DOM elements not found.");
            return;
        }

        // Add Event Listeners
        saveInfoButton.addEventListener('click', saveUserInfo);
        saveBirthdaysButton.addEventListener('click', saveBirthdays); 
        addFriendsFamilyRowButton.addEventListener('click', addFriendsFamilyRow);
        saveFriendsFamilyButton.addEventListener('click', saveFriendsFamily);
        addRelationshipBtn.addEventListener('click', addRelationship);

        // Hamburger menu toggle
        hamburgerBtn.addEventListener('click', () => {
            const dropdownContent = adminNavDropdown.querySelector('.dropdown-content');
            dropdownContent.style.display = dropdownContent.style.display === 'block' ? 'none' : 'block';
        });

        // Close dropdown when clicking outside
        document.addEventListener('click', (event) => {
            if (!adminNavDropdown.contains(event.target)) {
                const dropdownContent = adminNavDropdown.querySelector('.dropdown-content');
                dropdownContent.style.display = 'none';
            }
        });

        // Load initial data
        await loadUserInfo();
        await loadBirthdays();
        await loadFriendsFamily();
    }
}


// --- Status Display Helper ---
function showStatus(statusElement, message, isError = false, timeout = 3000) {
    if (!statusElement) return;
    statusElement.textContent = message;
    statusElement.className = isError ? 'text-sm text-red-600 ml-4 h-4 inline-block' : 'text-sm text-green-600 ml-4 h-4 inline-block';
    if (timeout > 0) {
        setTimeout(() => {
            statusElement.textContent = '';
        }, timeout);
    }
}


// --- User Info Functions ---
async function loadUserInfo() {
    console.log("Loading user info...");
    showStatus(infoSaveStatus, "Loading...", false, 0);
    try {
        const response = await window.authenticatedFetch('/api/user-info', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`User info fetch failed: ${response.status} ${errorText}`);
        }
        const data = await response.json();
        currentUserInfo = data.userInfo || '';
        userInfoTextarea.value = currentUserInfo;
        console.log("User info loaded.");
        showStatus(infoSaveStatus, "Loaded.", false, 1500);

    } catch (error) {
        console.error("Error loading user info:", error);
        showStatus(infoSaveStatus, `Error loading: ${error.message}`, true, 5000);
        currentUserInfo = '';
        userInfoTextarea.value = '';
    }
}

async function saveUserInfo() {
    console.log("Saving user info...");
    showStatus(infoSaveStatus, "Saving...", false, 0);

    const userInfo = userInfoTextarea.value;

    try {
        const response = await window.authenticatedFetch('/api/user-info', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify({ userInfo: userInfo })
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Save failed: ${response.status} ${errorText}`);
        }
        currentUserInfo = userInfo;
        console.log("User info saved successfully.");
        showStatus(infoSaveStatus, "Saved successfully!", false);

    } catch (error) {
        console.error("Error saving user info:", error);
        showStatus(infoSaveStatus, `Error saving: ${error.message}`, true, 5000);
    }
}


// --- Birthday Functions (Simplified) ---
async function loadBirthdays() {
    console.log("Loading birthdays...");
    showStatus(birthdaySaveStatus, "Loading...", false, 0);
    try {
        const response = await window.authenticatedFetch('/api/birthdays', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Birthdays fetch failed: ${response.status} ${errorText}`);
        }
        const data = await response.json();
        currentBirthdays = {
            userBirthdate: data.userBirthdate || null,
            friendsFamily: Array.isArray(data.friendsFamily) ? data.friendsFamily : []
        };

        if (userBirthdateInput) {
            userBirthdateInput.value = currentBirthdays.userBirthdate || '';
        }
        console.log("Birthdays loaded:", currentBirthdays);
        showStatus(birthdaySaveStatus, "Loaded.", false, 1500);

    } catch (error) {
        console.error("Error loading birthdays:", error);
        showStatus(birthdaySaveStatus, `Error loading: ${error.message}`, true, 5000);
        currentBirthdays = { userBirthdate: null, friendsFamily: [] };
    }
}

async function saveBirthdays() {
    console.log("Saving birthdays...");
    showStatus(birthdaySaveStatus, "Saving...", false, 0);

    const userBday = userBirthdateInput ? userBirthdateInput.value : null;

    if (userBday && !/^\d{4}-\d{2}-\d{2}$/.test(userBday)) {
         showStatus(birthdaySaveStatus, "User Birthdate must be in YYYY-MM-DD format or empty.", true, 5000);
         userBirthdateInput.focus();
         return;
    }

    const dataToSave = {
        userBirthdate: userBday || null,
        friendsFamily: currentBirthdays.friendsFamily || []
    };

    try {
        const response = await window.authenticatedFetch('/api/birthdays', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(dataToSave)
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Save failed: ${response.status} ${errorText}`);
        }
        currentBirthdays = await response.json();
        userBirthdateInput.value = currentBirthdays.userBirthdate || '';

        console.log("Birthdays saved successfully.");
        showStatus(birthdaySaveStatus, "Saved successfully!", false);

    } catch (error) {
        console.error("Error saving birthdays:", error);
        showStatus(birthdaySaveStatus, `Error saving: ${error.message}`, true, 5000);
    }
}


// --- Friends & Family Functions ---
function renderRelationshipsList() {
    if (!relationshipsList) return;
    relationshipsList.innerHTML = '';

    currentFriendsFamily.available_relationships.forEach((relationship, index) => {
        const tag = document.createElement('span');
        tag.className = 'inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800';
        tag.innerHTML = `
            ${relationship}
            <button type="button" class="ml-2 text-blue-600 hover:text-blue-800" onclick="removeRelationship(${index})">
                <i class="fas fa-times"></i>
            </button>
        `;
        relationshipsList.appendChild(tag);
    });
}

function renderFriendsFamilyTable() {
    if (!friendsFamilyTableBody) return;
    friendsFamilyTableBody.innerHTML = '';

    const friendsFamilyList = Array.isArray(currentFriendsFamily.friends_family) ? currentFriendsFamily.friends_family : [];

    friendsFamilyList.forEach((person, index) => {
        const row = document.createElement('tr');
        row.dataset.index = index;

        // Name Cell
        const nameCell = document.createElement('td');
        nameCell.className = 'px-4 py-2';
        const nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.value = person.name || '';
        nameInput.placeholder = 'Name';
        nameInput.className = 'border px-2 py-1 w-full text-sm';
        nameInput.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].name = e.target.value.trim();
        });
        nameCell.appendChild(nameInput);

        // Relationship Cell
        const relationshipCell = document.createElement('td');
        relationshipCell.className = 'px-4 py-2';
        const relationshipSelect = document.createElement('select');
        relationshipSelect.className = 'border px-2 py-1 w-full text-sm relationship-select';
        
        // Add default option
        const defaultOption = document.createElement('option');
        defaultOption.value = '';
        defaultOption.textContent = 'Select...';
        relationshipSelect.appendChild(defaultOption);

        // Add relationship options
        currentFriendsFamily.available_relationships.forEach(rel => {
            const option = document.createElement('option');
            option.value = rel;
            option.textContent = rel;
            if (person.relationship === rel) option.selected = true;
            relationshipSelect.appendChild(option);
        });

        relationshipSelect.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].relationship = e.target.value;
        });
        relationshipCell.appendChild(relationshipSelect);

        // About Cell
        const aboutCell = document.createElement('td');
        aboutCell.className = 'px-4 py-2';
        const aboutTextarea = document.createElement('textarea');
        aboutTextarea.value = person.about || '';
        aboutTextarea.placeholder = 'Background, interests, etc.';
        aboutTextarea.className = 'border px-2 py-1 w-full text-sm resize-none';
        aboutTextarea.rows = 2;
        aboutTextarea.addEventListener('change', (e) => {
            currentFriendsFamily.friends_family[index].about = e.target.value.trim();
        });
        aboutCell.appendChild(aboutTextarea);

        // Birthday Cell
        const birthdayCell = document.createElement('td');
        birthdayCell.className = 'px-4 py-2';
        const birthdayInput = document.createElement('input');
        birthdayInput.type = 'text';
        birthdayInput.value = person.birthday || '';
        birthdayInput.placeholder = 'MM-DD';
        birthdayInput.pattern = '\\d{2}-\\d{2}';
        birthdayInput.maxLength = 5;
        birthdayInput.className = 'border px-2 py-1 w-full text-sm';
        birthdayInput.addEventListener('change', (e) => {
            const value = e.target.value;
            if (value === '' || /^\d{2}-\d{2}$/.test(value)) {
                if (value !== '') {
                    const [month, day] = value.split('-').map(Number);
                    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
                        currentFriendsFamily.friends_family[index].birthday = value;
                    } else {
                        alert('Invalid month or day (MM-DD).');
                        e.target.value = currentFriendsFamily.friends_family[index].birthday || '';
                    }
                } else {
                    currentFriendsFamily.friends_family[index].birthday = '';
                }
            } else {
                alert('Please use MM-DD format (e.g., 05-21)');
                e.target.value = currentFriendsFamily.friends_family[index].birthday || '';
            }
        });
        birthdayCell.appendChild(birthdayInput);

        // Action Cell
        const actionCell = document.createElement('td');
        actionCell.className = 'px-4 py-2';
        const deleteButton = document.createElement('button');
        deleteButton.innerHTML = '<i class="fas fa-trash mr-1"></i>Delete';
        deleteButton.type = 'button';
        deleteButton.className = 'button-danger px-2 py-1 text-xs';
        deleteButton.onclick = () => {
            currentFriendsFamily.friends_family.splice(index, 1);
            renderFriendsFamilyTable();
        };
        actionCell.appendChild(deleteButton);

        row.appendChild(nameCell);
        row.appendChild(relationshipCell);
        row.appendChild(aboutCell);
        row.appendChild(birthdayCell);
        row.appendChild(actionCell);
        friendsFamilyTableBody.appendChild(row);
    });
}

function addFriendsFamilyRow() {
    if (!Array.isArray(currentFriendsFamily.friends_family)) {
        currentFriendsFamily.friends_family = [];
    }
    currentFriendsFamily.friends_family.push({ 
        name: '', 
        relationship: '', 
        about: '', 
        birthday: '' 
    });
    renderFriendsFamilyTable();
    
    // Focus the name input of the new row
    const newRowInput = friendsFamilyTableBody.querySelector(`tr[data-index="${currentFriendsFamily.friends_family.length - 1}"] input[placeholder="Name"]`);
    if (newRowInput) newRowInput.focus();
}

async function loadFriendsFamily() {
    console.log("Loading friends & family...");
    showStatus(friendsFamilySaveStatus, "Loading...", false, 0);
    try {
        const response = await window.authenticatedFetch('/api/friends-family', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' }, 
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Friends & family fetch failed: ${response.status} ${errorText}`);
        }
        const data = await response.json();
        currentFriendsFamily = {
            friends_family: Array.isArray(data.friends_family) ? data.friends_family : [],
            available_relationships: Array.isArray(data.available_relationships) ? data.available_relationships : []
        };

        renderRelationshipsList();
        renderFriendsFamilyTable();
        console.log("Friends & family loaded:", currentFriendsFamily);
        showStatus(friendsFamilySaveStatus, "Loaded.", false, 1500);

    } catch (error) {
        console.error("Error loading friends & family:", error);
        showStatus(friendsFamilySaveStatus, `Error loading: ${error.message}`, true, 5000);
        currentFriendsFamily = { friends_family: [], available_relationships: [] };
        renderRelationshipsList();
        renderFriendsFamilyTable();
    }
}

async function saveFriendsFamily() {
    console.log("Saving friends & family...");
    showStatus(friendsFamilySaveStatus, "Saving...", false, 0);

    // Filter out incomplete entries
    const validEntries = currentFriendsFamily.friends_family.filter(person => 
        person.name && person.name.trim() !== '' && 
        person.relationship && person.relationship.trim() !== ''
    );

    const dataToSave = {
        friends_family: validEntries,
        available_relationships: currentFriendsFamily.available_relationships
    };

    try {
        const response = await window.authenticatedFetch('/api/friends-family', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }, 
            body: JSON.stringify(dataToSave)
        });
        if (!response.ok) {
             const errorText = await response.text();
             throw new Error(`Save failed: ${response.status} ${errorText}`);
        }
        currentFriendsFamily = await response.json();
        renderFriendsFamilyTable();

        console.log("Friends & family saved successfully.");
        showStatus(friendsFamilySaveStatus, "Saved successfully!", false);

    } catch (error) {
        console.error("Error saving friends & family:", error);
        showStatus(friendsFamilySaveStatus, `Error saving: ${error.message}`, true, 5000);
    }
}

async function addRelationship() {
    const newRelationship = newRelationshipInput.value.trim();
    if (!newRelationship) {
        alert('Please enter a relationship type.');
        return;
    }

    if (currentFriendsFamily.available_relationships.includes(newRelationship)) {
        alert('This relationship type already exists.');
        return;
    }

    try {
        const response = await window.authenticatedFetch('/api/manage-relationships', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'add',
                relationship: newRelationship
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Add relationship failed: ${response.status} ${errorText}`);
        }

        const data = await response.json();
        currentFriendsFamily.available_relationships = data.available_relationships;
        newRelationshipInput.value = '';
        renderRelationshipsList();
        renderFriendsFamilyTable(); // Re-render to update dropdowns

    } catch (error) {
        console.error("Error adding relationship:", error);
        alert(`Error adding relationship: ${error.message}`);
    }
}

async function removeRelationship(index) {
    const relationship = currentFriendsFamily.available_relationships[index];
    if (!relationship) return;

    if (!confirm(`Remove "${relationship}" from available relationships?`)) return;

    try {
        const response = await window.authenticatedFetch('/api/manage-relationships', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'remove',
                relationship: relationship
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Remove relationship failed: ${response.status} ${errorText}`);
        }

        const data = await response.json();
        currentFriendsFamily.available_relationships = data.available_relationships;
        renderRelationshipsList();
        renderFriendsFamilyTable(); // Re-render to update dropdowns

    } catch (error) {
        console.error("Error removing relationship:", error);
        alert(`Error removing relationship: ${error.message}`);
    }
}


// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("user_info_admin.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}


// --- Event Listeners ---
document.addEventListener('adminUserContextReady', () => {
    console.log("user_info_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("user_info_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("user_info_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
});

// Make removeRelationship available globally for onclick handlers
window.removeRelationship = removeRelationship;
