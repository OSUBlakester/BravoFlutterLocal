/**
 * AAC Image Creator JavaScript
 * Global admin tool for generating and managing AAC images
 */

let currentStep = 1;
let currentConcept = '';
let currentSubconcepts = [];
let generatedImages = [];

// Initialize the image creator when page loads
function initializeImageCreator() {
    console.log('Image Creator initialized');
    updateStepIndicator();
}

// Utility function to get authentication token
async function getAuthHeaders() {
    try {
        const token = await window.getAuthToken();
        return {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
        };
    } catch (error) {
        console.error('Error getting auth token:', error);
        throw new Error('Authentication failed');
    }
}

// Update step indicator UI
function updateStepIndicator() {
    for (let i = 1; i <= 4; i++) {
        const step = document.getElementById(`step-${i}`);
        const panel = document.getElementById(`step-${i}-panel`);
        
        if (i < currentStep) {
            step.classList.add('completed');
            step.classList.remove('active');
            if (panel) panel.classList.add('hidden');
        } else if (i === currentStep) {
            step.classList.add('active');
            step.classList.remove('completed');
            if (panel) panel.classList.remove('hidden');
        } else {
            step.classList.remove('active', 'completed');
            if (panel) panel.classList.add('hidden');
        }
    }
}

// Move to next step
function goToStep(step) {
    currentStep = step;
    updateStepIndicator();
}

// Step 1: Generate subconcepts
async function generateSubconcepts() {
    const concept = document.getElementById('concept-input').value.trim();
    const variations = parseInt(document.getElementById('variations-count').value);
    
    if (!concept) {
        alert('Please enter a concept category');
        return;
    }
    
    const btn = document.getElementById('generate-subconcepts-btn');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Generating...';
    btn.disabled = true;
    
    try {
        const headers = await getAuthHeaders();
        const response = await fetch('/api/imagecreator/generate-subconcepts', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                concept: concept,
                variations: variations,
                style: 'Apple memoji style'
            })
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to generate subconcepts');
        }
        
        const data = await response.json();
        currentConcept = data.concept;
        currentSubconcepts = data.subconcepts;
        
        // Display subconcepts for editing
        displaySubconceptsForEditing();
        goToStep(2);
        
    } catch (error) {
        console.error('Error generating subconcepts:', error);
        alert('Error generating subconcepts: ' + error.message);
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

// Display subconcepts for editing
function displaySubconceptsForEditing() {
    const container = document.getElementById('subconcepts-container');
    container.innerHTML = '';
    
    currentSubconcepts.forEach((subconcept, index) => {
        const subconceptDiv = document.createElement('div');
        subconceptDiv.className = 'flex items-center gap-2';
        subconceptDiv.innerHTML = `
            <input 
                type="text" 
                value="${subconcept}" 
                class="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                onchange="updateSubconcept(${index}, this.value)"
            >
            <button 
                onclick="removeSubconcept(${index})" 
                class="text-red-600 hover:text-red-800 p-1"
                title="Remove"
            >
                <i class="fas fa-trash"></i>
            </button>
        `;
        container.appendChild(subconceptDiv);
    });
}

// Update subconcept
function updateSubconcept(index, value) {
    currentSubconcepts[index] = value.trim();
}

// Remove subconcept
function removeSubconcept(index) {
    currentSubconcepts.splice(index, 1);
    displaySubconceptsForEditing();
}

// Add custom subconcept
function addCustomSubconcept() {
    const subconcept = prompt('Enter a new subconcept:');
    if (subconcept && subconcept.trim()) {
        currentSubconcepts.push(subconcept.trim());
        displaySubconceptsForEditing();
    }
}

// Step 3: Generate images
async function generateImages() {
    if (currentSubconcepts.length === 0) {
        alert('Please add at least one subconcept');
        return;
    }
    
    goToStep(3);
    
    const progressText = document.getElementById('progress-text');
    progressText.textContent = `0/${currentSubconcepts.length}`;
    
    try {
        const headers = await getAuthHeaders();
        const response = await fetch('/api/imagecreator/generate-images', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                concept: currentConcept,
                subconcepts: currentSubconcepts,
                style: 'Apple memoji style'
            })
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to generate images');
        }
        
        const data = await response.json();
        generatedImages = data.images;
        
        // Display generated images for review
        displayGeneratedImages();
        goToStep(4);
        
    } catch (error) {
        console.error('Error generating images:', error);
        alert('Error generating images: ' + error.message);
        goToStep(2); // Go back to previous step
    }
}

// Display generated images for review
function displayGeneratedImages() {
    const container = document.getElementById('generated-images-container');
    container.innerHTML = '';
    
    generatedImages.forEach((imageData, index) => {
        const imageCard = document.createElement('div');
        imageCard.className = 'image-card cursor-pointer';
        imageCard.dataset.index = index;
        imageCard.onclick = () => toggleImageSelection(index);
        
        imageCard.innerHTML = `
            <img src="${imageData.image_url}" alt="${imageData.subconcept}" class="w-full h-48 object-cover">
            <div class="p-3">
                <h3 class="font-semibold text-gray-800">${imageData.subconcept}</h3>
                <p class="text-sm text-gray-600">${currentConcept}</p>
            </div>
            <div class="absolute top-2 right-2 hidden" id="check-${index}">
                <div class="bg-green-500 text-white rounded-full w-6 h-6 flex items-center justify-center">
                    <i class="fas fa-check text-sm"></i>
                </div>
            </div>
        `;
        
        container.appendChild(imageCard);
    });
}

// Toggle image selection
function toggleImageSelection(index) {
    const card = document.querySelector(`[data-index="${index}"]`);
    const check = document.getElementById(`check-${index}`);
    
    if (card.classList.contains('selected')) {
        card.classList.remove('selected');
        check.classList.add('hidden');
        generatedImages[index].selected = false;
    } else {
        card.classList.add('selected');
        check.classList.remove('hidden');
        generatedImages[index].selected = true;
    }
}

// Select all images
function selectAllImages() {
    generatedImages.forEach((_, index) => {
        const card = document.querySelector(`[data-index="${index}"]`);
        const check = document.getElementById(`check-${index}`);
        
        card.classList.add('selected');
        check.classList.remove('hidden');
        generatedImages[index].selected = true;
    });
}

// Deselect all images
function deselectAllImages() {
    generatedImages.forEach((_, index) => {
        const card = document.querySelector(`[data-index="${index}"]`);
        const check = document.getElementById(`check-${index}`);
        
        card.classList.remove('selected');
        check.classList.add('hidden');
        generatedImages[index].selected = false;
    });
}

// Store selected images
async function storeSelectedImages() {
    const selectedImages = generatedImages.filter(img => img.selected);
    
    if (selectedImages.length === 0) {
        alert('Please select at least one image to store');
        return;
    }
    
    if (!confirm(`Store ${selectedImages.length} images to the global AAC database?`)) {
        return;
    }
    
    try {
        const headers = await getAuthHeaders();
        
        // Prepare images data
        const imagesToStore = selectedImages.map(img => ({
            image_url: img.image_url,
            concept: currentConcept,
            subconcept: img.subconcept
        }));
        
        const response = await fetch('/api/imagecreator/store-images', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                images: imagesToStore
            })
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to store images');
        }
        
        const data = await response.json();
        
        alert(`Successfully stored ${data.stored_images.length} images to the AAC database!`);
        
        // Offer to start over or browse images
        if (confirm('Would you like to create more images?')) {
            startOver();
        } else {
            showImageBrowser();
        }
        
    } catch (error) {
        console.error('Error storing images:', error);
        alert('Error storing images: ' + error.message);
    }
}

// Start over
function startOver() {
    currentStep = 1;
    currentConcept = '';
    currentSubconcepts = [];
    generatedImages = [];
    
    // Reset form
    document.getElementById('concept-input').value = '';
    document.getElementById('variations-count').value = '10';
    
    updateStepIndicator();
}

// Image Browser functionality
function showImageBrowser() {
    document.getElementById('image-browser-modal').classList.remove('hidden');
    searchImages(); // Load all images initially
}

function closeImageBrowser() {
    document.getElementById('image-browser-modal').classList.add('hidden');
}

async function searchImages() {
    const concept = document.getElementById('search-concept').value.trim();
    const tag = document.getElementById('search-tag').value.trim();
    
    try {
        const headers = await getAuthHeaders();
        
        // Build query parameters
        const params = new URLSearchParams();
        if (concept) params.append('concept', concept);
        if (tag) params.append('tag', tag);
        params.append('limit', '100');
        
        const response = await fetch(`/api/imagecreator/images?${params}`, {
            headers: headers
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to search images');
        }
        
        const data = await response.json();
        displayBrowserImages(data.images);
        
    } catch (error) {
        console.error('Error searching images:', error);
        alert('Error searching images: ' + error.message);
    }
}

function displayBrowserImages(images) {
    const container = document.getElementById('browser-images-container');
    container.innerHTML = '';
    
    if (images.length === 0) {
        container.innerHTML = `
            <div class="col-span-full text-center py-8 text-gray-500">
                <i class="fas fa-image text-4xl mb-4"></i>
                <p>No images found</p>
            </div>
        `;
        return;
    }
    
    images.forEach(image => {
        const imageCard = document.createElement('div');
        imageCard.className = 'image-card';
        
        const createdDate = image.created_at ? new Date(image.created_at).toLocaleDateString() : 'Unknown';
        const tags = image.tags ? image.tags.slice(0, 5).join(', ') : 'No tags';
        
        imageCard.innerHTML = `
            <img src="${image.image_url}" alt="${image.subconcept}" class="w-full h-48 object-cover">
            <div class="p-3">
                <h3 class="font-semibold text-gray-800">${image.subconcept}</h3>
                <p class="text-sm text-gray-600 mb-1">${image.concept}</p>
                <p class="text-xs text-gray-500 mb-2">Created: ${createdDate}</p>
                <div class="text-xs text-gray-400 mb-3" title="${image.tags ? image.tags.join(', ') : ''}">
                    Tags: ${tags}${image.tags && image.tags.length > 5 ? '...' : ''}
                </div>
                <div class="flex gap-2">
                    <button 
                        onclick="editImageTags('${image.id}')" 
                        class="text-blue-600 hover:text-blue-800 text-sm"
                        title="Edit Tags"
                    >
                        <i class="fas fa-tag"></i>
                    </button>
                    <button 
                        onclick="deleteImage('${image.id}')" 
                        class="text-red-600 hover:text-red-800 text-sm"
                        title="Delete Image"
                    >
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        `;
        
        container.appendChild(imageCard);
    });
}

async function editImageTags(imageId) {
    try {
        // Get current tags (you'd need to fetch the image details)
        const currentTags = prompt('Enter tags (comma-separated):');
        if (!currentTags) return;
        
        const tags = currentTags.split(',').map(tag => tag.trim()).filter(tag => tag);
        
        const headers = await getAuthHeaders();
        const response = await fetch(`/api/imagecreator/images/${imageId}/tags`, {
            method: 'PUT',
            headers: headers,
            body: JSON.stringify(tags)
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to update tags');
        }
        
        alert('Tags updated successfully!');
        searchImages(); // Refresh the display
        
    } catch (error) {
        console.error('Error updating tags:', error);
        alert('Error updating tags: ' + error.message);
    }
}

async function deleteImage(imageId) {
    if (!confirm('Are you sure you want to delete this image? This action cannot be undone.')) {
        return;
    }
    
    try {
        const headers = await getAuthHeaders();
        const response = await fetch(`/api/imagecreator/images/${imageId}`, {
            method: 'DELETE',
            headers: headers
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to delete image');
        }
        
        alert('Image deleted successfully!');
        searchImages(); // Refresh the display
        
    } catch (error) {
        console.error('Error deleting image:', error);
        alert('Error deleting image: ' + error.message);
    }
}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // ESC to close modals
    if (e.key === 'Escape') {
        closeImageBrowser();
    }
});

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeImageCreator);
} else {
    initializeImageCreator();
}
