// Family & Friends Interview System
// Specialized interview system for collecting information about family and friends
// Extends the audio interview system for relationship-focused data collection

class FamilyFriendsInterviewSystem {
    constructor() {
        this.isInitialized = false;
        this.isListening = false;
        this.recognition = null;
        this.currentQuestionIndex = 0;
        this.interviewData = {
            sessionId: this.generateSessionId(),
            startTime: new Date().toISOString(),
            responses: [],
            extractedPerson: null
        };
        
        // TTS properties
        this.ttsEnabled = true;
        this.currentUtterance = null;
        this.isAskingQuestion = false;
        this.shouldStopListening = false;
        this.isInterviewComplete = false;
        this.autoSaveTimeout = null;
        
        // Speech recognition properties
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        
        // Modal elements
        this.modal = null;
        this.questionText = null;
        this.progressBar = null;
        this.statusText = null;
        this.recognizedText = null;
        this.confirmResponseBtn = null;
        this.retryResponseBtn = null;
        
        // Load questions configuration - now just a simple array
        this.questions = FAMILY_FRIENDS_INTERVIEW_QUESTIONS;
        this.config = FAMILY_FRIENDS_INTERVIEW_CONFIG;
        
        console.log('FamilyFriendsInterviewSystem initialized with', this.questions.length, 'questions');
    }

    generateSessionId() {
        return 'ff_interview_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }



    async initialize() {
        if (this.isInitialized) return true;

        // Initialize speech recognition
        const speechReady = this.initializeSpeechRecognition();
        if (!speechReady) {
            return false;
        }

        this.isInitialized = true;
        console.log('Family/Friends interview system initialized successfully');
        return true;
    }

    createInterviewModal() {
        // Remove existing modal if present
        const existingModal = document.getElementById('familyFriendsInterviewModal');
        if (existingModal) {
            existingModal.remove();
        }

        const modalHTML = `
            <div id="familyFriendsInterviewModal" class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50" style="display: none;">
                <div class="relative top-20 mx-auto p-5 border w-11/12 max-w-2xl shadow-lg rounded-md bg-white">
                    <div class="mt-3">
                        <!-- Header -->
                        <div class="flex justify-between items-center mb-4 pb-3 border-b">
                            <div>
                                <h3 class="text-lg font-semibold text-gray-900">👤 ${this.config.title}</h3>
                                <p class="text-sm text-gray-600">${this.config.description}</p>
                            </div>
                            <button id="closeFamilyFriendsInterviewBtn" class="text-gray-400 hover:text-gray-600">
                                <i class="fas fa-times text-xl"></i>
                            </button>
                        </div>

                        <!-- Progress Section -->
                        <div class="mb-4">
                            <div class="flex justify-between text-sm text-gray-600 mb-2">
                                <span id="familyFriendsProgressText">Question 1 of 4</span>
                                <span id="familyFriendsStatusText">Ready to begin</span>
                            </div>
                            <div class="w-full bg-gray-200 rounded-full h-2">
                                <div id="familyFriendsProgressBar" class="bg-blue-600 h-2 rounded-full transition-all duration-300" style="width: 0%"></div>
                            </div>
                        </div>

                        <!-- Question Section -->
                        <div class="mb-6 p-4 bg-blue-50 rounded-lg">
                            <h4 id="familyFriendsQuestionText" class="text-lg font-medium text-gray-800 mb-2">
                                Preparing your interview...
                            </h4>
                        </div>

                        <!-- Recognition Display -->
                        <div class="mb-6 p-4 bg-gray-50 rounded-lg min-h-[80px]">
                            <h5 class="text-sm font-medium text-gray-700 mb-2">Your Response:</h5>
                            <p id="familyFriendsRecognizedText" class="text-gray-600 italic">
                                (Listening for your response...)
                            </p>
                        </div>

                        <!-- Manual Input Option -->
                        <div class="mb-4">
                            <label for="familyFriendsManualInput" class="block text-sm font-medium text-gray-700 mb-2">Or type your response:</label>
                            <input type="text" id="familyFriendsManualInput" class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500" placeholder="Type your response here...">
                        </div>

                        <!-- Control Buttons -->
                        <div class="flex justify-center space-x-4 mb-6">
                            <button id="familyFriendsConfirmBtn" class="px-6 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors">
                                <i class="fas fa-check mr-2"></i>Confirm
                            </button>
                            <button id="familyFriendsRetryBtn" class="px-6 py-2 bg-orange-600 text-white rounded-md hover:bg-orange-700 transition-colors">
                                <i class="fas fa-redo mr-2"></i>Try Again
                            </button>
                            <button id="familyFriendsSkipBtn" class="px-4 py-2 bg-gray-300 text-gray-700 rounded-md hover:bg-gray-400 transition-colors" style="display: none;">
                                <i class="fas fa-forward mr-2"></i>Skip
                            </button>
                        </div>

                        <!-- Results Preview -->
                        <div id="familyFriendsResultsPreview" class="mt-6 p-4 bg-green-50 rounded-lg border border-green-200" style="display: none;">
                            <h5 class="font-medium text-green-800 mb-2">
                                <i class="fas fa-user mr-2"></i>Person to Add
                            </h5>
                            <div id="familyFriendsExtractedPeople" class="text-sm text-green-700">
                                <!-- Person info will be displayed here -->
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        this.attachModalEventListeners();
    }

    attachModalEventListeners() {
        // Get modal elements
        this.modal = document.getElementById('familyFriendsInterviewModal');
        this.questionText = document.getElementById('familyFriendsQuestionText');
        this.progressBar = document.getElementById('familyFriendsProgressBar');
        this.progressText = document.getElementById('familyFriendsProgressText');
        this.statusText = document.getElementById('familyFriendsStatusText');
        this.recognizedText = document.getElementById('familyFriendsRecognizedText');
        this.manualInput = document.getElementById('familyFriendsManualInput');

        // Control buttons
        const closeBtn = document.getElementById('closeFamilyFriendsInterviewBtn');
        this.confirmResponseBtn = document.getElementById('familyFriendsConfirmBtn');
        this.retryResponseBtn = document.getElementById('familyFriendsRetryBtn');
        const skipBtn = document.getElementById('familyFriendsSkipBtn');

        // Event listeners
        closeBtn.addEventListener('click', () => this.closeModal());
        if (this.confirmResponseBtn) this.confirmResponseBtn.addEventListener('click', () => this.confirmResponse());
        if (this.retryResponseBtn) this.retryResponseBtn.addEventListener('click', () => this.retryResponse());
        if (skipBtn) skipBtn.addEventListener('click', () => this.skipQuestion());

        // Close on outside click
        this.modal.addEventListener('click', (e) => {
            if (e.target === this.modal) {
                this.closeModal();
            }
        });
    }

    async openInterviewModal() {
        const initialized = await this.initialize();
        if (!initialized) return;

        this.createInterviewModal();
        this.modal.style.display = 'block';
        await this.askCurrentQuestion();
        
        console.log('Family/Friends interview modal opened');
    }

    closeModal() {
        // Check if interview is in progress (but not if it's completed)
        const hasResponses = this.interviewData.responses.length > 0;
        const isInProgress = (this.currentQuestionIndex > 0 || this.isListening || hasResponses) && !this.isInterviewComplete;
        
        if (isInProgress) {
            const confirmClose = confirm('You have an interview in progress. Are you sure you want to close and lose the current progress?');
            if (!confirmClose) {
                return; // Don't close if user cancels
            }
        }
        
        // Stop TTS and listening
        this.stopTTS();
        this.shouldStopListening = true;
        if (this.isListening) {
            this.stopListening();
        }
        
        if (this.modal) {
            this.modal.style.display = 'none';
            // Small delay before removing to allow for animation
            setTimeout(() => {
                if (this.modal) {
                    this.modal.remove();
                    this.modal = null;
                }
                
                // Show the start button again
                const startBtn = document.getElementById('startFamilyFriendsInterviewBtn');
                if (startBtn) startBtn.style.display = 'block';
            }, 300);
        }
        
        // Reset interview state
        this.currentQuestionIndex = 0;
        this.interviewData.responses = [];
        this.isInterviewComplete = false;
        this.interviewData.extractedPeople = [];
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        
        console.log('Family/Friends interview modal closed');
    }
    
    async startAnotherInterview() {
        console.log('startAnotherInterview called');
        console.log('Current extractedPeople:', this.interviewData.extractedPeople);
        
        // Automatically add current person to the Friends & Family table before starting new interview
        if (this.interviewData.extractedPeople && this.interviewData.extractedPeople.length > 0) {
            await this.addCurrentPersonToTable();
        }
        
        // Reset the current interview state for new person
        this.currentQuestionIndex = 0;
        this.interviewData.responses = [];
        this.interviewData.extractedPeople = [];
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        
        // Hide results preview
        const resultsDiv = document.getElementById('familyFriendsResultsPreview');
        if (resultsDiv) {
            resultsDiv.style.display = 'none';
        }
        
        // Reset UI elements
        this.questionText.textContent = 'Ready to begin interview.';
        this.recognizedText.textContent = '';
        if (this.manualInput) this.manualInput.value = '';
        this.statusText.textContent = 'Ready to start another interview';
        this.progressBar.style.width = '0%';
        this.progressText.textContent = 'Ready to start';
        
        // Show control buttons for the new interview - use direct DOM access to ensure they exist
        const confirmBtn = document.getElementById('familyFriendsConfirmBtn');
        const retryBtn = document.getElementById('familyFriendsRetryBtn');
        const skipBtn = document.getElementById('familyFriendsSkipBtn');
        
        if (confirmBtn) {
            confirmBtn.classList.remove('hidden');
            confirmBtn.style.display = 'inline-block';
        }
        if (retryBtn) {
            retryBtn.classList.remove('hidden');
            retryBtn.style.display = 'inline-block';
        }
        if (skipBtn) {
            skipBtn.style.display = 'inline-block';
        }
        
        console.log('Ready to start another Family/Friends interview.');
        
        // Start the new interview
        await this.askCurrentQuestion();
    }
    
    async addCurrentPersonToTable() {
        try {
            if (!this.interviewData.extractedPeople || this.interviewData.extractedPeople.length === 0) {
                console.log('No current person to add');
                return;
            }
            
            const person = this.interviewData.extractedPeople[0];
            console.log('Adding current person to table:', person);
            
            // Ensure relationship exists
            if (person.relationship) {
                person.relationship = await this.ensureRelationshipExists(person.relationship);
            }
            
            // Create person object for currentFriendsFamily data structure
            const personForData = {
                name: person.name || '',
                relationship: person.relationship || '',
                about: person.about || '',
                birthday: person.birthday || ''
            };
            
            // Add to currentFriendsFamily data structure first
            if (window.currentFriendsFamily && window.currentFriendsFamily.friends_family) {
                window.currentFriendsFamily.friends_family.push(personForData);
                console.log('Added person to currentFriendsFamily data structure:', personForData);
            }
            
            // Add new row to table
            if (window.addFriendsFamilyRow) {
                window.addFriendsFamilyRow();
                
                // Get the last added row and populate it
                const tableBody = document.getElementById('friendsFamilyTbody');
                const rows = tableBody.querySelectorAll('tr');
                const lastRow = rows[rows.length - 1];
                
                if (lastRow) {
                    // Fill in the data (don't trigger change events since we already added to data structure)
                    const nameInput = lastRow.querySelector('input[placeholder="Name"]');
                    const relationshipSelect = lastRow.querySelector('.relationship-select');
                    const aboutTextarea = lastRow.querySelector('textarea');
                    const birthdayInput = lastRow.querySelector('input[placeholder="MM-DD"]');
                    
                    if (nameInput) nameInput.value = person.name || '';
                    if (aboutTextarea) aboutTextarea.value = person.about || '';
                    if (birthdayInput && person.birthday) birthdayInput.value = person.birthday;
                    
                    // Set relationship
                    if (relationshipSelect && person.relationship) {
                        const exactOption = relationshipSelect.querySelector(`option[value="${person.relationship}"]`);
                        if (exactOption) {
                            exactOption.selected = true;
                        }
                    }
                    
                    // Note: Not triggering change events since data is already in currentFriendsFamily structure
                }
            }
            
            console.log('Successfully added person to friends/family table:', person.name);
            
        } catch (error) {
            console.error('Error adding current person to table:', error);
        }
    }
    
    async completeAllInterviews() {
        try {
            this.statusText.textContent = 'Adding person and saving data...';
            
            // Add current person if exists
            if (this.interviewData.extractedPeople && this.interviewData.extractedPeople.length > 0) {
                await this.addCurrentPersonToTable();
                console.log('Person added to table and data structure');
                
                // Give a moment for DOM events to process
                await new Promise(resolve => setTimeout(resolve, 500));
            }
            
            // Save all friends/family data
            if (typeof window.saveFriendsFamily === 'function') {
                console.log('Calling saveFriendsFamily to save all data');
                console.log('Current friends/family data before save:', window.currentFriendsFamily);
                await window.saveFriendsFamily();
                console.log('Save completed successfully');
                console.log('Current friends/family data after save:', window.currentFriendsFamily);
            }
            
            // Show success message
            this.statusText.textContent = 'All interviews completed and saved!';
            
            // Stop all speech recognition and TTS
            this.stopTTS();
            this.shouldStopListening = true;
            if (this.isListening) {
                this.stopListening();
            }
            
            // Reset interview state to prevent "interview in progress" warning
            this.currentQuestionIndex = 0;
            this.interviewData.responses = [];
            this.interviewData.extractedPeople = [];
            this.isInterviewComplete = true;
            
            setTimeout(() => {
                this.closeModal();
                console.log('Interview process completed successfully');
                // Ensure the main page shows updated data
                if (typeof window.loadFriendsFamily === 'function') {
                    window.loadFriendsFamily();
                }
            }, 2000);
            
        } catch (error) {
            console.error('Error completing all interviews:', error);
            this.statusText.textContent = 'Error saving data: ' + error.message;
        }
    }
    
    async bulkAddAllPeople() {
        try {
            // Combine current person with pending people
            const allPeople = [];
            
            // Add pending people
            if (this.pendingPeople && this.pendingPeople.length > 0) {
                allPeople.push(...this.pendingPeople);
            }
            
            // Add current person if exists
            if (this.interviewData.extractedPeople && this.interviewData.extractedPeople.length > 0) {
                allPeople.push(...this.interviewData.extractedPeople);
            }
            
            if (allPeople.length === 0) {
                console.error('No people to add');
                return;
            }
            
            console.log(`Adding ${allPeople.length} people to Friends & Family list`);
            
            // Add each person to the table
            for (const person of allPeople) {
                // Ensure relationship exists
                if (person.relationship) {
                    person.relationship = await this.ensureRelationshipExists(person.relationship);
                }
                
                // Add new row
                if (window.addFriendsFamilyRow) {
                    window.addFriendsFamilyRow();
                    
                    // Get the last added row and populate it
                    const tableBody = document.getElementById('friendsFamilyTbody');
                    const rows = tableBody.querySelectorAll('tr');
                    const lastRow = rows[rows.length - 1];
                    
                    if (lastRow) {
                        const nameInput = lastRow.querySelector('input[placeholder="Name"]');
                        const relationshipSelect = lastRow.querySelector('.relationship-select');
                        const aboutTextarea = lastRow.querySelector('textarea');
                        const birthdayInput = lastRow.querySelector('input[placeholder="MM-DD"]');
                        
                        if (nameInput) nameInput.value = person.name || '';
                        if (aboutTextarea) aboutTextarea.value = person.about || '';
                        if (birthdayInput && person.birthday) birthdayInput.value = person.birthday;
                        
                        // Set relationship
                        if (relationshipSelect && person.relationship) {
                            const exactOption = relationshipSelect.querySelector(`option[value="${person.relationship}"]`);
                            if (exactOption) {
                                exactOption.selected = true;
                            }
                        }
                        
                        // Trigger change events
                        if (nameInput) nameInput.dispatchEvent(new Event('change'));
                        if (relationshipSelect) relationshipSelect.dispatchEvent(new Event('change'));
                        if (aboutTextarea) aboutTextarea.dispatchEvent(new Event('change'));
                        if (birthdayInput) birthdayInput.dispatchEvent(new Event('change'));
                    }
                }
            }
            
            // Clear pending people
            this.pendingPeople = [];
            
            // Update UI
            const bulkAddBtn = document.getElementById('bulkAddPeopleBtn');
            if (bulkAddBtn) {
                bulkAddBtn.innerHTML = '<i class="fas fa-check mr-2"></i>All People Added!';
                bulkAddBtn.disabled = true;
                bulkAddBtn.classList.remove('bg-purple-600', 'hover:bg-purple-700');
                bulkAddBtn.classList.add('bg-green-600');
            }
            
            console.log(`Successfully added ${allPeople.length} people to friends/family table`);
            
        } catch (error) {
            console.error('Error bulk adding people:', error);
        }
    }

    // Interview starts automatically when modal opens
    
    async askCurrentQuestion() {
        if (this.currentQuestionIndex >= this.questions.length) {
            this.finishInterview();
            return;
        }

        const currentQuestion = this.questions[this.currentQuestionIndex];
        const progress = ((this.currentQuestionIndex) / this.questions.length) * 100;

        // Update UI elements
        this.questionText.textContent = currentQuestion.question;
        this.progressBar.style.width = progress + '%';
        this.progressText.textContent = `Question ${this.currentQuestionIndex + 1} of ${this.questions.length}`;
        this.recognizedText.textContent = 'Question being asked...';

        // Show/hide appropriate buttons
        const skipBtn = document.getElementById('familyFriendsSkipBtn');
        const confirmBtn = document.getElementById('familyFriendsConfirmBtn');
        const retryBtn = document.getElementById('familyFriendsRetryBtn');
        
        // Show skip button for all questions after the first one (name is required)
        if (skipBtn) skipBtn.style.display = this.currentQuestionIndex > 0 ? 'inline-block' : 'none';
        
        // Keep confirm and retry buttons visible for user interaction
        if (confirmBtn) {
            confirmBtn.classList.remove('hidden');
            confirmBtn.style.display = 'inline-block';
        }
        if (retryBtn) {
            retryBtn.classList.remove('hidden');
            retryBtn.style.display = 'inline-block';
        }

        console.log(`Asking question ${this.currentQuestionIndex + 1}: ${currentQuestion.id}`);
        
        try {
            this.isAskingQuestion = true;
            this.statusText.textContent = 'Question being asked...';
            
            // Speak the question
            await this.speakText(currentQuestion.question);
            
            // Wait a moment after TTS finishes
            await new Promise(resolve => setTimeout(resolve, 1000));
            
            // Reset stop flag and start listening
            this.shouldStopListening = false;
            this.startListening();
            
        } finally {
            this.isAskingQuestion = false;
        }
    }



    startListening() {
        if (!this.recognition) {
            this.statusText.textContent = 'Speech recognition not available';
            return;
        }
        
        // Stop any existing recognition first
        if (this.isListening) {
            this.recognition.stop();
            setTimeout(() => this.startListening(), 100);
            return;
        }
        
        // Initialize for fresh start
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        this.recognizedText.textContent = '(Listening...)';
        // Keep buttons visible for user interaction
        this.confirmResponseBtn.classList.remove('hidden');
        this.retryResponseBtn.classList.remove('hidden');
        
        try {
            this.recognition.start();
        } catch (error) {
            console.error('Error starting speech recognition:', error);
            if (error.name !== 'InvalidStateError') {
                this.statusText.textContent = 'Could not start voice recognition';
            }
        }
    }
    
    continueListening() {
        if (!this.recognition) {
            this.statusText.textContent = 'Speech recognition not available';
            return;
        }
        
        // Don't clear accumulated text - continue building
        this.recognizedText.textContent = this.currentRecognizedText || '(Listening...)';
        
        try {
            this.recognition.start();
        } catch (error) {
            console.error('Error continuing speech recognition:', error);
            this.statusText.textContent = 'Could not continue voice recognition';
        }
    }

    stopListening() {
        if (this.recognition && this.isListening) {
            this.recognition.stop();
        }
    }



    initializeSpeechRecognition() {
        if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
            console.warn('Speech recognition not supported in this browser');
            alert('Speech recognition is not available in this browser. Please use Chrome or Edge for the best experience.');
            return false;
        }

        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        this.recognition = new SpeechRecognition();
        
        this.recognition.continuous = true;
        this.recognition.interimResults = true;
        this.recognition.lang = 'en-US';
        
        this.recognition.onstart = () => {
            this.isListening = true;
            console.log('Speech recognition started');
        };
        
        this.recognition.onresult = (event) => {
            let interimTranscript = '';
            let finalTranscript = '';
            
            for (let i = event.resultIndex; i < event.results.length; i++) {
                const transcript = event.results[i][0].transcript;
                if (event.results[i].isFinal) {
                    finalTranscript += transcript;
                } else {
                    interimTranscript += transcript;
                }
            }
            
            // Append new text to accumulated text
            const newText = finalTranscript || interimTranscript;
            if (newText.trim()) {
                const separator = (this.accumulatedText && this.accumulatedText.trim()) ? ' ' : '';
                this.currentRecognizedText = (this.accumulatedText || '') + separator + newText.trim();
            } else {
                this.currentRecognizedText = this.accumulatedText || '';
            }
            
            this.recognizedText.textContent = this.currentRecognizedText || '(Listening...)';
            
            // Show confirm/retry buttons if we have text
            if (finalTranscript.length > 0 || interimTranscript.length > 0) {
                this.confirmResponseBtn.classList.remove('hidden');
                this.retryResponseBtn.classList.remove('hidden');
            }
        };
        
        this.recognition.onerror = (event) => {
            console.error('Speech recognition error:', event.error);
            this.isListening = false;
            
            if (event.error === 'aborted') {
                console.log('Speech recognition was aborted (normal during restart/stop)');
                return;
            }
            
            if (event.error === 'no-speech' || event.error === 'not-allowed') {
                this.statusText.textContent = 'Speech recognition error. Click "Try Again" to retry.';
            }
        };
        
        this.recognition.onend = () => {
            this.isListening = false;
            
            // Save any final text for continuation
            if (this.currentRecognizedText && this.currentRecognizedText.trim()) {
                this.accumulatedText = this.currentRecognizedText;
            }
            
            if (this.currentRecognizedText.length < 1) {
                // No speech yet - keep listening
                this.statusText.textContent = 'Listening for your response...';
                
                if (!this.shouldStopListening) {
                    setTimeout(() => {
                        if (!this.isListening && !this.shouldStopListening) {
                            this.continueListening();
                        }
                    }, 500);
                }
            } else {
                // Have some text - show buttons and keep listening
                this.statusText.textContent = 'Keep talking or click "Confirm" when done, "Try Again" to restart.';
                this.confirmResponseBtn.classList.remove('hidden');
                this.retryResponseBtn.classList.remove('hidden');
                
                // Keep listening for more
                if (!this.shouldStopListening) {
                    setTimeout(() => {
                        if (!this.isListening && !this.shouldStopListening) {
                            this.continueListening();
                        }
                    }, 500);
                }
            }
        };
        
        return true;
    }



    async confirmResponse() {
        // Check both speech recognition and manual input
        const manualText = this.manualInput ? this.manualInput.value.trim() : '';
        const speechText = this.currentRecognizedText || '';
        const finalText = manualText || speechText;
        
        if (!finalText || finalText.length < 1) {
            this.statusText.textContent = 'Please provide a response (speech or text) or skip this question';
            return;
        }
        
        // Stop listening
        this.shouldStopListening = true;
        this.stopListening();
        
        // Hide buttons
        this.confirmResponseBtn.classList.add('hidden');
        this.retryResponseBtn.classList.add('hidden');
        
        this.statusText.textContent = 'Processing your response...';
        
        const currentQuestion = this.questions[this.currentQuestionIndex];
        
        const response = {
            questionId: currentQuestion.id,
            question: currentQuestion.question,
            answer: finalText,
            timestamp: new Date().toISOString()
        };
        
        this.interviewData.responses.push(response);
        console.log('Confirmed response:', response);
        
        // Move to next question
        this.currentQuestionIndex++;
        
        setTimeout(async () => {
            await this.askCurrentQuestion();
        }, 500);
    }
    
    retryResponse() {
        // Clear current response and restart listening
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        if (this.manualInput) this.manualInput.value = '';
        this.confirmResponseBtn.classList.add('hidden');
        this.retryResponseBtn.classList.add('hidden');
        
        setTimeout(() => {
            this.startListening();
        }, 500);
    }
    
    skipQuestion() {
        // Don't allow skipping the first question (name)
        if (this.currentQuestionIndex === 0) {
            this.statusText.textContent = 'Name is required - cannot skip this question';
            return;
        }
        
        const currentQuestion = this.questions[this.currentQuestionIndex];
        
        // Stop TTS and listening
        this.stopTTS();
        this.shouldStopListening = true;
        this.stopListening();
        
        // Add skipped response
        const skippedResponse = {
            questionId: currentQuestion.id,
            question: currentQuestion.question,
            skipped: true,
            timestamp: new Date().toISOString(),
            answer: '[Skipped]'
        };
        
        this.interviewData.responses.push(skippedResponse);
        this.currentQuestionIndex++;
        
        // Hide confirm/retry buttons and skip button temporarily
        this.confirmResponseBtn.classList.add('hidden');
        this.retryResponseBtn.classList.add('hidden');
        document.getElementById('familyFriendsSkipBtn').style.display = 'none';
        
        setTimeout(async () => {
            await this.askCurrentQuestion();
        }, 500);
        
        console.log('Skipped question:', currentQuestion.id);
    }

    async finishInterview() {
        this.statusText.textContent = 'Processing interview data...';
        
        try {
            // Stop all speech recognition and TTS immediately
            this.stopTTS();
            this.shouldStopListening = true;
            if (this.isListening) {
                this.stopListening();
            }
            
            // Process the interview data to extract family/friends
            await this.extractFamilyFriendsData();
            
            // Save interview data
            await this.saveInterviewData();
            
            // Show results preview
            this.showResultsPreview();
            
            console.log('Family/Friends interview completed successfully');
            
        } catch (error) {
            console.error('Error finishing family/friends interview:', error);
            this.statusText.textContent = 'Error processing interview data';
        }
    }

    async extractFamilyFriendsData() {
        const responses = this.interviewData.responses.filter(r => !r.skipped);
        
        // Simple direct mapping from responses
        const person = {
            name: '',
            relationship: '',
            about: '',
            birthday: ''
        };
        
        // Map each response by question ID
        responses.forEach(response => {
            switch(response.questionId) {
                case 'person_name':
                    person.name = response.answer.trim();
                    break;
                case 'relationship':
                    person.relationship = response.answer.trim();
                    break;
                case 'about_person':
                    person.about = response.answer.trim();
                    break;
                case 'birthday':
                    // Parse birthday to MM-DD format if possible
                    const birthdayText = response.answer.trim().toLowerCase();
                    if (birthdayText.includes("don't know") || birthdayText.includes("not sure")) {
                        person.birthday = '';
                    } else {
                        // Try to extract MM-DD from the response
                        const dateMatch = birthdayText.match(/(\w+)\s+(\d{1,2})/);
                        if (dateMatch) {
                            const month = this.parseMonth(dateMatch[1]);
                            const day = dateMatch[2].padStart(2, '0');
                            if (month) {
                                person.birthday = `${month}-${day}`;
                            }
                        }
                    }
                    break;
            }
        });
        
        // Only add if we have at least a name
        if (person.name) {
            this.interviewData.extractedPeople = [person];
            console.log('Extracted person data:', person);
            console.log('extractedPeople array now contains:', this.interviewData.extractedPeople);
        } else {
            console.log('No name found, not adding to extractedPeople. Person object:', person);
        }
    }
    
    parseMonth(monthName) {
        const months = {
            'january': '01', 'jan': '01',
            'february': '02', 'feb': '02',
            'march': '03', 'mar': '03',
            'april': '04', 'apr': '04',
            'may': '05',
            'june': '06', 'jun': '06',
            'july': '07', 'jul': '07',
            'august': '08', 'aug': '08',
            'september': '09', 'sep': '09', 'sept': '09',
            'october': '10', 'oct': '10',
            'november': '11', 'nov': '11',
            'december': '12', 'dec': '12'
        };
        
        return months[monthName.toLowerCase()] || null;
    }
    
    async speakText(text) {
        if (!this.ttsEnabled) return;
        
        return new Promise((resolve) => {
            // Stop any current speech
            if (this.currentUtterance) {
                speechSynthesis.cancel();
            }
            
            this.currentUtterance = new SpeechSynthesisUtterance(text);
            this.currentUtterance.rate = 0.9;
            this.currentUtterance.pitch = 1;
            this.currentUtterance.volume = 0.8;
            
            this.currentUtterance.onend = () => {
                resolve();
            };
            
            this.currentUtterance.onerror = () => {
                console.warn('TTS error');
                resolve();
            };
            
            speechSynthesis.speak(this.currentUtterance);
        });
    }
    
    stopTTS() {
        if (speechSynthesis.speaking) {
            speechSynthesis.cancel();
        }
        this.currentUtterance = null;
    }



    async saveInterviewData() {
        try {
            // Save the interview data to the server
            const response = await window.authenticatedFetch('/api/save-family-friends-interview', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    sessionId: this.interviewData.sessionId,
                    responses: this.interviewData.responses,
                    extractedPeople: this.interviewData.extractedPeople,
                    completedAt: new Date().toISOString()
                })
            });
            
            if (!response.ok) {
                throw new Error(`Failed to save interview data: ${response.status}`);
            }
            
            console.log('Family/Friends interview data saved successfully');
            
        } catch (error) {
            console.error('Error saving interview data:', error);
            // Continue anyway - we can still populate the UI
        }
    }

    showResultsPreview() {
        console.log('Showing results preview for:', this.interviewData.extractedPeople);
        const resultsDiv = document.getElementById('familyFriendsResultsPreview');
        const peopleDiv = document.getElementById('familyFriendsExtractedPeople');
        
        if (!resultsDiv || !peopleDiv) {
            console.error('Results display elements not found in DOM');
            return;
        }
        
        if (this.interviewData.extractedPeople.length > 0) {
            const person = this.interviewData.extractedPeople[0];
            const personHtml = `
                <div class="p-3 bg-white rounded border">
                    <div class="font-semibold text-gray-800">${person.name}</div>
                    ${person.relationship ? `<div class="text-sm text-gray-600">Relationship: ${person.relationship}</div>` : ''}
                    ${person.about ? `<div class="text-sm text-gray-600 mt-1">${person.about}</div>` : ''}
                    ${person.birthday ? `<div class="text-sm text-blue-600 mt-1">Birthday: ${person.birthday}</div>` : ''}
                </div>
            `;
            
            peopleDiv.innerHTML = personHtml;
            resultsDiv.style.display = 'block';
            
            // Remove existing buttons container if it exists
            const existingContainer = document.getElementById('familyFriendsButtonsContainer');
            if (existingContainer) {
                existingContainer.remove();
            }
            
            // Create fresh buttons container
            const buttonsContainer = document.createElement('div');
            buttonsContainer.id = 'familyFriendsButtonsContainer';
            buttonsContainer.className = 'mt-3 space-y-2';
            
            // Add Another Person button (automatically adds current person)
            const addAnotherBtn = document.createElement('button');
            addAnotherBtn.id = 'addAnotherPersonBtn';
            addAnotherBtn.className = 'px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors w-full';
            addAnotherBtn.innerHTML = '<i class="fas fa-user-plus mr-2"></i>Add Another Person';
            addAnotherBtn.addEventListener('click', () => {
                this.startAnotherInterview();
            });
            
            // Complete All Interviews button (adds current person and closes)
            const completeBtn = document.createElement('button');
            completeBtn.id = 'completeInterviewsBtn';
            completeBtn.className = 'px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors w-full font-semibold';
            completeBtn.innerHTML = '<i class="fas fa-check mr-2"></i>Complete All Interviews & Save';
            completeBtn.addEventListener('click', () => {
                console.log('User clicked Complete All Interviews button');
                this.completeAllInterviews();
            });
            
            buttonsContainer.appendChild(addAnotherBtn);
            buttonsContainer.appendChild(completeBtn);
            

            
            resultsDiv.appendChild(buttonsContainer);
            
            // Make the results section more prominent
            resultsDiv.scrollIntoView({ behavior: 'smooth', block: 'center' });
            
        } else {
            peopleDiv.innerHTML = '<p class="text-gray-600">Please provide at least a name to add this person.</p>';
            resultsDiv.style.display = 'block';
        }
        
        this.statusText.textContent = 'Interview completed! Choose an option below:';
        
        // Hide interview control buttons since interview is complete
        const confirmBtn = document.getElementById('familyFriendsConfirmBtn');
        const retryBtn = document.getElementById('familyFriendsRetryBtn');
        const skipBtn = document.getElementById('familyFriendsSkipBtn');
        
        if (confirmBtn) confirmBtn.style.display = 'none';
        if (retryBtn) retryBtn.style.display = 'none';
        if (skipBtn) skipBtn.style.display = 'none';
    }
    
    async ensureRelationshipExists(spokenRelationship) {
        try {
            // Check if we have access to the current friends family data
            if (!window.currentFriendsFamily || !window.currentFriendsFamily.available_relationships) {
                console.warn('currentFriendsFamily data not available, using spoken relationship as-is');
                return spokenRelationship;
            }
            
            const existingRelationships = window.currentFriendsFamily.available_relationships;
            const spokenLower = spokenRelationship.toLowerCase().trim();
            
            // Check if it already exists (case-insensitive)
            const existingMatch = existingRelationships.find(rel => rel.toLowerCase() === spokenLower);
            if (existingMatch) {
                console.log(`Relationship "${existingMatch}" already exists`);
                return existingMatch;
            }
            
            // Normalize the spoken relationship (capitalize first letter)
            const normalizedRelationship = spokenRelationship.charAt(0).toUpperCase() + 
                                         spokenRelationship.slice(1).toLowerCase();
            
            console.log(`Adding new relationship: "${normalizedRelationship}"`);
            
            // Add the new relationship using the API directly
            const response = await window.authenticatedFetch('/api/manage-relationships', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    action: 'add',
                    relationship: normalizedRelationship
                })
            });
            
            if (!response.ok) {
                const errorText = await response.text();
                console.error(`Failed to add relationship: ${response.status} ${errorText}`);
                return spokenRelationship;
            }
            
            const data = await response.json();
            
            // Update the current data structure
            window.currentFriendsFamily.available_relationships = data.available_relationships;
            
            // Re-render the table to update all dropdowns
            if (typeof window.renderFriendsFamilyTable === 'function') {
                window.renderFriendsFamilyTable();
            }
            
            // Also update any existing dropdowns in the modal if they exist
            const modalRelationshipSelects = document.querySelectorAll('.relationship-select');
            modalRelationshipSelects.forEach(select => {
                // Add the new relationship option if it doesn't exist
                const existingOption = select.querySelector(`option[value="${normalizedRelationship}"]`);
                if (!existingOption) {
                    const newOption = document.createElement('option');
                    newOption.value = normalizedRelationship;
                    newOption.textContent = normalizedRelationship;
                    select.appendChild(newOption);
                }
            });
            
            console.log(`Successfully added relationship: "${normalizedRelationship}"`);
            return normalizedRelationship;
            
        } catch (error) {
            console.error('Error ensuring relationship exists:', error);
            // Fallback to using the spoken relationship as-is
            return spokenRelationship;
        }
    }
}

// Initialize the global instance
window.familyFriendsInterviewSystem = null;

// Function to start the family/friends interview
function startFamilyFriendsInterview() {
    console.log("Starting Family & Friends interview...");
    
    // Check if interview is already running
    if (window.familyFriendsInterviewSystem && window.familyFriendsInterviewSystem.modal && window.familyFriendsInterviewSystem.modal.style.display !== 'none') {
        console.log("Interview already in progress");
        return;
    }
    
    // Check if the system is available
    if (typeof FamilyFriendsInterviewSystem === 'undefined') {
        console.error("FamilyFriendsInterviewSystem not available");
        alert("Family & Friends interview system is not available. Please refresh the page and try again.");
        return;
    }
    
    try {
        // Initialize the system if needed
        if (!window.familyFriendsInterviewSystem) {
            window.familyFriendsInterviewSystem = new FamilyFriendsInterviewSystem();
        }
        
        // Hide the start button during interview
        const startBtn = document.getElementById('startFamilyFriendsInterviewBtn');
        if (startBtn) startBtn.style.display = 'none';
        
        // Open the interview modal
        window.familyFriendsInterviewSystem.openInterviewModal();
        
    } catch (error) {
        console.error("Error starting family/friends interview:", error);
        alert("There was an error starting the Family & Friends interview. Please try again.");
    }
}

// CSS for the recording animation
const style = document.createElement('style');
style.textContent = `
    .recording-animation {
        animation: pulse 1.5s infinite;
    }
    
    @keyframes pulse {
        0% {
            box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.7);
        }
        70% {
            box-shadow: 0 0 0 10px rgba(239, 68, 68, 0);
        }
        100% {
            box-shadow: 0 0 0 0 rgba(239, 68, 68, 0);
        }
    }
    
    .record-button {
        transition: all 0.2s ease-in-out;
    }
    
    .record-button:hover {
        transform: scale(1.05);
    }
`;
document.head.appendChild(style);