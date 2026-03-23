/**
 * Audio Interview System
 * Interactive interview system for collecting comprehensive user information
 * Uses speech recognition, TTS, and AI-powered follow-up questions
 */

class AudioInterviewSystem {
    constructor() {
        this.isActive = false;
        this.isPaused = false;
        this.currentQuestionIndex = 0;
        this.interviewData = {
            userName: '',
            responses: [],
            friendsFamily: [],
            startTime: null,
            lastSaveTime: null
        };
        
        // Speech recognition
        this.recognition = null;
        this.isListening = false;
        this.currentRecognizedText = '';
        this.accumulatedText = ''; // Initialize accumulated text for multi-pause responses
        
        // TTS
        this.ttsEnabled = true;
        this.currentUtterance = null;
        
        // Question asking state
        this.isAskingQuestion = false;
        this.shouldStopListening = false;
        
        // Question management - Use comprehensive questions from interview-questions.js
        this.baseQuestions = [];
        this.loadComprehensiveQuestions();

        this.loadComprehensiveQuestions();
        
        this.currentQuestions = [...this.baseQuestions];
        this.additionalQuestions = [];
        
        this.initializeElements();
        this.setupEventListeners();
        this.initializeSpeechRecognition();
        
        // Load any saved interview progress
        this.loadSavedProgress();
        
        console.log('AudioInterviewSystem initialized successfully');
    }

    loadComprehensiveQuestions() {
        // Check if INTERVIEW_QUESTIONS is available from interview-questions.js
        if (typeof window.INTERVIEW_QUESTIONS !== 'undefined') {
            this.baseQuestions = this.convertComprehensiveQuestions(window.INTERVIEW_QUESTIONS);
        } else {
            // Fallback to basic questions if comprehensive questions aren't loaded
            console.warn('INTERVIEW_QUESTIONS not found, using fallback questions');
            this.baseQuestions = [
                {
                    id: 'user_name',
                    text: "What is the name of the person who will be using this application?",
                    type: 'identity',
                    required: true,
                    followUp: true
                },
                {
                    id: 'user_info',
                    text: "Can you tell me about this person - their interests, personality, and what's important to know about them?",
                    type: 'general',
                    required: true,
                    followUp: true
                }
            ];
        }
        
        this.currentQuestions = [...this.baseQuestions];
        this.additionalQuestions = [];
    }

    convertComprehensiveQuestions(interviewQuestions) {
        const convertedQuestions = [];
        
        // Convert the comprehensive question structure to the format expected by the audio system
        Object.keys(interviewQuestions).forEach(categoryKey => {
            if (categoryKey === 'INTERVIEW_CONFIG') return; // Skip config
            
            const categoryQuestions = interviewQuestions[categoryKey];
            categoryQuestions.forEach(questionObj => {
                convertedQuestions.push({
                    id: questionObj.id,
                    text: questionObj.question,
                    type: questionObj.category,
                    required: questionObj.required || false,
                    followUp: !!questionObj.followUp,
                    followUpQuestion: questionObj.followUp
                });
            });
        });
        
        return convertedQuestions;
    }

    initializeElements() {
        // Modal elements
        this.modal = document.getElementById('audioInterviewModal');
        this.startInterviewButton = document.getElementById('startInterviewButton');
        this.closeInterviewModal = document.getElementById('closeInterviewModal');
        this.closeInterviewBtn = document.getElementById('closeInterviewBtn');
        
        // Interview control elements
        this.startInterviewBtn = document.getElementById('startInterviewBtn');
        this.pauseResumeBtn = document.getElementById('pauseResumeBtn');
        this.skipQuestionBtn = document.getElementById('skipQuestionBtn');
        this.repeatQuestionBtn = document.getElementById('repeatQuestionBtn');
        
        // Status and progress elements
        this.interviewStatus = document.getElementById('interviewStatus');
        this.interviewProgress = document.getElementById('interviewProgress');
        this.currentQuestion = document.getElementById('currentQuestion');
        this.interviewLog = document.getElementById('interviewLog');
        
        // Voice recognition elements
        this.voiceRecognitionFeedback = document.getElementById('voiceRecognitionFeedback');
        this.recognizedText = document.getElementById('recognizedText');
        this.confirmResponseBtn = document.getElementById('confirmResponseBtn');
        this.retryResponseBtn = document.getElementById('retryResponseBtn');
        
        // Action buttons
        this.saveInterviewProgressBtn = document.getElementById('saveInterviewProgressBtn');
        this.restartInterviewBtn = document.getElementById('restartInterviewBtn');
        this.generateNarrativeBtn = document.getElementById('generateNarrativeBtn');
        this.closeInterviewModalBtn = document.getElementById('closeInterviewModal');
    }

    setupEventListeners() {
        // Modal controls
        this.startInterviewButton?.addEventListener('click', () => this.openInterviewModal());
        this.closeInterviewModalBtn?.addEventListener('click', () => {
            console.log('Close modal button clicked');
            this.handleCloseModal();
        });
        this.closeInterviewBtn?.addEventListener('click', () => {
            console.log('Close interview button clicked');
            this.handleCloseModal();
        });
        
        // Interview controls
        this.startInterviewBtn?.addEventListener('click', () => this.startInterview());
        this.pauseResumeBtn?.addEventListener('click', () => this.togglePauseResume());
        this.skipQuestionBtn?.addEventListener('click', () => this.skipCurrentQuestion());
        this.repeatQuestionBtn?.addEventListener('click', () => this.repeatCurrentQuestion());
        
        // Voice recognition controls
        this.confirmResponseBtn?.addEventListener('click', () => this.confirmCurrentResponse());
        this.retryResponseBtn?.addEventListener('click', () => this.retryVoiceRecognition());
        
        // Action buttons
        this.saveInterviewProgressBtn?.addEventListener('click', () => this.saveProgress());
        this.restartInterviewBtn?.addEventListener('click', () => this.restartInterview());
        this.generateNarrativeBtn?.addEventListener('click', () => this.generateAndSaveNarrative());
        
        // Close modal on escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.modal && !this.modal.classList.contains('hidden')) {
                this.closeInterviewModal();
            }
        });
    }

    initializeSpeechRecognition() {
        if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
            console.warn('Speech recognition not supported in this browser');
            this.updateStatus('Speech recognition not available. Please use Chrome/Edge for best experience.', 'warning');
            return;
        }

        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        this.recognition = new SpeechRecognition();
        
        this.recognition.continuous = true;
        this.recognition.interimResults = true;
        this.recognition.lang = 'en-US';
        
        this.recognition.onstart = () => {
            this.isListening = true;
            this.updateStatus('Listening for your response...', 'listening');
            this.showVoiceRecognitionFeedback(true);
        };
        
        this.recognition.onresult = (event) => {
            let interimTranscript = '';
            let finalTranscript = '';
            
            console.log('[INTERVIEW DEBUG] onresult fired. resultIndex:', event.resultIndex, 'total results:', event.results.length);
            console.log('[INTERVIEW DEBUG] Accumulated text before processing:', this.accumulatedText);
            
            for (let i = event.resultIndex; i < event.results.length; i++) {
                const transcript = event.results[i][0].transcript;
                if (event.results[i].isFinal) {
                    finalTranscript += transcript;
                    console.log('[INTERVIEW DEBUG] Final transcript chunk:', transcript);
                } else {
                    interimTranscript += transcript;
                    console.log('[INTERVIEW DEBUG] Interim transcript chunk:', transcript);
                }
            }
            
            // If we have final results, permanently add them to accumulated text
            if (finalTranscript.trim()) {
                const separator = (this.accumulatedText && this.accumulatedText.trim()) ? ' ' : '';
                this.accumulatedText = (this.accumulatedText || '') + separator + finalTranscript.trim();
                console.log('[INTERVIEW DEBUG] Final transcript added. New accumulated text:', this.accumulatedText);
            }
            
            // Current recognized text includes accumulated (final) text + interim (in-progress) text
            if (interimTranscript.trim()) {
                const separator = (this.accumulatedText && this.accumulatedText.trim()) ? ' ' : '';
                this.currentRecognizedText = (this.accumulatedText || '') + separator + interimTranscript.trim();
            } else {
                this.currentRecognizedText = this.accumulatedText || '';
            }
            
            console.log('[INTERVIEW DEBUG] Current recognized text:', this.currentRecognizedText);
            this.recognizedText.textContent = this.currentRecognizedText || '(Listening...)';
            
            // Show confirm button if we have any text
            if (finalTranscript.length > 0 || interimTranscript.length > 0) {
                this.confirmResponseBtn.classList.remove('hidden');
                this.retryResponseBtn.classList.remove('hidden');
            }
            

        };
        
        this.recognition.onerror = (event) => {
            console.error('Speech recognition error:', event.error);
            this.isListening = false;
            
            // Don't show error for aborted recognition (happens during normal operation)
            if (event.error === 'aborted') {
                console.log('Speech recognition was aborted (normal during restart/stop)');
                return;
            }
            
            // Only show error for actual problems
            if (event.error === 'no-speech' || event.error === 'not-allowed') {
                this.updateStatus('Speech recognition error. Click "Try Again" to retry.', 'error');
            }
        };
        
        this.recognition.onend = () => {
            this.isListening = false;
            
            console.log('[INTERVIEW DEBUG] Recognition ended. Current accumulated text:', this.accumulatedText);
            console.log('[INTERVIEW DEBUG] Recognition ended. Current recognized text:', this.currentRecognizedText);
            
            // Don't override accumulatedText here - it's already updated in onresult
            // Just ensure currentRecognizedText matches accumulated text
            this.currentRecognizedText = this.accumulatedText || '';
            
            if (!this.accumulatedText || this.accumulatedText.length < 1) {
                // No speech detected yet - keep trying to listen
                this.updateStatus('Listening for your response...', 'listening');
                
                // Auto-restart listening to wait for user to start speaking
                if (this.isActive && !this.isPaused && !this.shouldStopListening) {
                    setTimeout(() => {
                        if (!this.isListening && this.isActive && !this.isPaused && !this.shouldStopListening) {
                            this.continueListening();
                        }
                    }, 500);
                }
            } else {
                // We have some text - show buttons and keep listening for more
                this.updateStatus('Speaking detected. Keep talking or click "Confirm" when done, "Try Again" to restart.', 'info');
                this.confirmResponseBtn.classList.remove('hidden');
                this.retryResponseBtn.classList.remove('hidden');
                
                // Keep listening continuously until user clicks a button
                if (this.isActive && !this.isPaused && !this.shouldStopListening) {
                    setTimeout(() => {
                        if (!this.isListening && this.isActive && !this.isPaused && !this.shouldStopListening) {
                            this.continueListening();
                        }
                    }, 500);
                }
            }
        };
    }

    openInterviewModal() {
        this.modal.classList.remove('hidden');
        this.updateProgress();
        
        // Check if we have saved progress
        if (this.interviewData.responses.length > 0) {
            this.currentQuestion.textContent = `Welcome back! You have ${this.interviewData.responses.length} responses saved. Click "Start Interview" to continue or "Restart" to begin fresh.`;
            this.generateNarrativeBtn.classList.remove('hidden');
        }
    }

    handleCloseModal() {
        console.log('handleCloseModal called, checking method availability...');
        console.log('this.closeInterviewModal type:', typeof this.closeInterviewModal);
        console.log('this object:', this);
        
        try {
            // Method 1: Try direct call
            if (typeof this.closeInterviewModal === 'function') {
                console.log('Calling closeInterviewModal directly...');
                this.closeInterviewModal();
                return;
            }
            
            // Method 2: Try manual cleanup if method doesn't exist
            console.log('closeInterviewModal method not found, performing manual cleanup...');
            this.isActive = false;
            this.isPaused = false;
            
            // Stop listening
            if (this.recognition && this.isListening) {
                this.recognition.stop();
            }
            
            // Close modal
            if (this.modal) {
                this.modal.style.display = 'none';
                this.modal.classList.add('hidden');
                console.log('Modal closed manually');
            }
            
            // Save progress
            if (typeof this.saveProgress === 'function') {
                this.saveProgress();
            }
            
            // Clean up speech synthesis
            if (window.speechSynthesis) {
                window.speechSynthesis.cancel();
            }
            
        } catch (error) {
            console.error('Error in handleCloseModal:', error);
            // Method 3: Force close by finding modal in DOM
            const modal = document.getElementById('interviewModal');
            if (modal) {
                modal.style.display = 'none';
                modal.classList.add('hidden');
                console.log('Modal force closed via DOM');
            }
        }
    }

    closeInterviewModal() {
        console.log('closeInterviewModal called');
        this.isActive = false;
        this.isPaused = false;
        this.stopListening();
        
        if (this.modal) {
            this.modal.style.display = 'none';
            this.modal.classList.add('hidden');
        }
        
        // Save progress
        this.saveProgress();
        
        // Clean up speech synthesis
        if (window.speechSynthesis) {
            window.speechSynthesis.cancel();
        }
    }

    async startInterview() {
        if (!this.isActive) {
            this.isActive = true;
            this.interviewData.startTime = new Date().toISOString();
            this.updateStatus('Interview started', 'success');
            
            // Show interview controls
            this.startInterviewBtn.classList.add('hidden');
            this.pauseResumeBtn.classList.remove('hidden');
            this.skipQuestionBtn.classList.remove('hidden');
            this.repeatQuestionBtn.classList.remove('hidden');
        }
        
        this.isPaused = false;
        this.pauseResumeBtn.innerHTML = '<i class="fas fa-pause"></i> Pause';
        
        await this.askCurrentQuestion();
    }

    async askCurrentQuestion() {
        if (this.isPaused || !this.isActive) return;
        
        // Prevent duplicate calls
        if (this.isAskingQuestion) {
            console.log('Already asking a question, skipping duplicate call');
            return;
        }
        
        const question = this.getCurrentQuestion();
        if (!question) {
            await this.completeInterview();
            return;
        }
        
        this.isAskingQuestion = true;
        
        try {
            // Replace placeholders in question text
            const questionText = this.processQuestionText(question.text);
            
            this.currentQuestion.textContent = questionText;
            this.updateProgress();
            
            // Add question to log
            this.addToInterviewLog(`Q${this.currentQuestionIndex + 1}: ${questionText}`, 'question');
            
            // Hide listening UI during question announcement
            if (this.recognizedText) {
                this.recognizedText.textContent = 'Question being announced...';
            }
            
            // Speak the question and wait for it to complete
            await this.speakText(questionText);
            
            // Ensure TTS is completely finished with a longer pause
            // This prevents the microphone from picking up the tail end of TTS
            await new Promise(resolve => setTimeout(resolve, 1000));
            
            // Double-check TTS is not speaking before starting to listen
            if (speechSynthesis.speaking) {
                console.log('TTS still speaking, waiting...');
                await new Promise(resolve => {
                    const checkTTS = () => {
                        if (!speechSynthesis.speaking) {
                            setTimeout(resolve, 500); // Extra buffer
                        } else {
                            setTimeout(checkTTS, 100);
                        }
                    };
                    checkTTS();
                });
            }
            
            // Reset the stop flag for new question
            this.shouldStopListening = false;
            
            // Now start listening for response
            this.startListening();
        } finally {
            this.isAskingQuestion = false;
        }
    }

    getCurrentQuestion() {
        if (this.currentQuestionIndex < this.currentQuestions.length) {
            return this.currentQuestions[this.currentQuestionIndex];
        }
        return null;
    }

    processQuestionText(text) {
        const userName = this.interviewData.userName || 'the user';
        return text.replace(/\{userName\}/g, userName);
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

    startListening() {
        if (!this.recognition) {
            this.updateStatus('Speech recognition not available', 'error');
            return;
        }
        
        // Stop any existing recognition first to prevent conflicts
        if (this.isListening) {
            this.recognition.stop();
            // Wait a moment for it to fully stop
            setTimeout(() => this.startListening(), 100);
            return;
        }
        
        // Initialize accumulated text for fresh start
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        this.recognizedText.textContent = '(Listening...)';
        this.confirmResponseBtn.classList.add('hidden');
        
        try {
            this.recognition.start();
        } catch (error) {
            console.error('Error starting speech recognition:', error);
            // If already running, don't show error
            if (error.name !== 'InvalidStateError') {
                this.updateStatus('Could not start voice recognition', 'error');
            }
        }
    }

    continueListening() {
        if (!this.recognition) {
            this.updateStatus('Speech recognition not available', 'error');
            return;
        }
        
        console.log('[INTERVIEW DEBUG] Continue listening. Accumulated text:', this.accumulatedText);
        
        // Don't clear accumulated text - continue building on existing response
        this.currentRecognizedText = this.accumulatedText || '';
        this.recognizedText.textContent = this.currentRecognizedText || '(Listening...)';
        
        try {
            this.recognition.start();
        } catch (error) {
            console.error('Error continuing speech recognition:', error);
            this.updateStatus('Could not continue voice recognition', 'error');
        }
    }

    stopListening() {
        if (this.recognition && this.isListening) {
            this.recognition.stop();
        }
        this.showVoiceRecognitionFeedback(false);
    }

    showVoiceRecognitionFeedback(show) {
        if (show) {
            this.voiceRecognitionFeedback.classList.remove('hidden');
        } else {
            this.voiceRecognitionFeedback.classList.add('hidden');
        }
    }

    async confirmCurrentResponse() {
        if (!this.currentRecognizedText || this.currentRecognizedText.length < 1) {
            this.updateStatus('Please provide a response or skip this question', 'warning');
            return;
        }
        
        // Stop the continuous listening cycle
        this.shouldStopListening = true;
        
        // Clean up UI
        this.confirmResponseBtn.classList.add('hidden');
        this.retryResponseBtn.classList.add('hidden');
        
        this.updateStatus('Processing your response...', 'processing');
        
        const currentQuestion = this.getCurrentQuestion();
        if (!currentQuestion) {
            console.error('No current question available');
            this.updateStatus('Error: No question available', 'error');
            return;
        }
        
        const response = {
            questionId: currentQuestion.id,
            question: this.processQuestionText(currentQuestion.text),
            answer: this.currentRecognizedText.trim(),
            timestamp: new Date().toISOString(),
            type: currentQuestion.type
        };
        
        // Special handling for user name
        if (currentQuestion.id === 'user_name') {
            this.interviewData.userName = this.currentRecognizedText.trim();
        }
        
        this.interviewData.responses.push(response);
        this.addToInterviewLog(`A${this.currentQuestionIndex + 1}: ${response.answer}`, 'answer');
        
        this.stopListening();
        
        // Check if we need follow-up questions
        if (currentQuestion.followUp) {
            await this.generateFollowUpQuestions(response);
        }
        
        this.currentQuestionIndex++;
        
        // Brief pause before next question
        setTimeout(async () => {
            if (this.isActive && !this.isPaused) {
                await this.askCurrentQuestion();
            }
        }, 1500);
    }

    async generateFollowUpQuestions(response) {
        try {
            const prompt = `Based on this interview response about a user for an AAC application:

Question: ${response.question}
Answer: ${response.answer}

Generate 1-2 specific follow-up questions that would help gather more detailed information for their user profile. The questions should be:
- Specific and actionable
- Help understand preferences, habits, or important details
- Be natural conversation starters
- Focus on information that would help personalize their AAC experience

Return only the follow-up questions, one per line, without numbering or bullet points.`;

            const followUpResponse = await this.callLLM(prompt);
            
            if (followUpResponse && followUpResponse.trim()) {
                const questions = followUpResponse.split('\n').filter(q => q.trim().length > 10);
                
                questions.forEach(questionText => {
                    const followUpQuestion = {
                        id: `followup_${response.questionId}_${Date.now()}`,
                        text: questionText.trim(),
                        type: `${response.type}_followup`,
                        followUp: false
                    };
                    
                    // Insert follow-up questions after current question
                    this.currentQuestions.splice(this.currentQuestionIndex + 1, 0, followUpQuestion);
                });
            }
        } catch (error) {
            console.error('Error generating follow-up questions:', error);
        }
    }

    async callLLM(prompt) {
        try {
            const response = await window.authenticatedFetch('/llm', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    prompt: prompt
                })
            });
            
            if (response.ok) {
                const data = await response.json();
                return data.response || '';
            } else {
                console.error('LLM API error:', response.status, response.statusText);
                const errorText = await response.text();
                console.error('Error details:', errorText);
                throw new Error(`LLM API returned ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('LLM call failed:', error);
        }
        return '';
    }

    retryVoiceRecognition() {
        this.stopListening();
        // Reset the stop flag to allow listening again
        this.shouldStopListening = false;
        // Clear both current and accumulated text for fresh start
        this.accumulatedText = '';
        this.currentRecognizedText = '';
        this.confirmResponseBtn.classList.add('hidden');
        this.retryResponseBtn.classList.add('hidden');
        setTimeout(() => {
            this.startListening();
        }, 500);
    }

    skipCurrentQuestion() {
        this.stopListening();
        this.addToInterviewLog(`Q${this.currentQuestionIndex + 1}: Skipped`, 'skipped');
        this.currentQuestionIndex++;
        
        setTimeout(async () => {
            if (this.isActive && !this.isPaused) {
                await this.askCurrentQuestion();
            }
        }, 500);
    }

    async repeatCurrentQuestion() {
        this.stopListening();
        await this.askCurrentQuestion();
    }

    togglePauseResume() {
        this.isPaused = !this.isPaused;
        
        if (this.isPaused) {
            this.stopListening();
            this.stopTTS();
            this.pauseResumeBtn.innerHTML = '<i class="fas fa-play"></i> Resume';
            this.updateStatus('Interview paused', 'warning');
        } else {
            this.pauseResumeBtn.innerHTML = '<i class="fas fa-pause"></i> Pause';
            this.updateStatus('Interview resumed', 'success');
            setTimeout(async () => {
                await this.askCurrentQuestion();
            }, 1000);
        }
    }

    async completeInterview() {
        this.isActive = false;
        this.stopListening();
        this.stopTTS();
        
        this.updateStatus('Interview completed!', 'success');
        this.currentQuestion.textContent = 'Interview completed! You can now generate the user profile or review your responses.';
        
        // Hide interview controls and show generate button
        this.pauseResumeBtn.classList.add('hidden');
        this.skipQuestionBtn.classList.add('hidden');
        this.repeatQuestionBtn.classList.add('hidden');
        this.generateNarrativeBtn.classList.remove('hidden');
        
        // Auto-save progress
        await this.saveProgress();
    }

    async restartInterview() {
        if (confirm('Are you sure you want to restart the interview? All progress will be lost.')) {
            this.isActive = false;
            this.isPaused = false;
            this.currentQuestionIndex = 0;
            this.interviewData = {
                userName: '',
                responses: [],
                friendsFamily: [],
                startTime: null,
                lastSaveTime: null
            };
            this.currentQuestions = [...this.baseQuestions];
            
            this.clearInterviewLog();
            this.clearSavedProgress();
            this.updateProgress();
            
            // Reset UI
            this.startInterviewBtn.classList.remove('hidden');
            this.pauseResumeBtn.classList.add('hidden');
            this.skipQuestionBtn.classList.add('hidden');
            this.repeatQuestionBtn.classList.add('hidden');
            this.generateNarrativeBtn.classList.add('hidden');
            this.showVoiceRecognitionFeedback(false);
            
            this.currentQuestion.textContent = "Interview restarted. Click 'Start Interview' when you're ready to begin.";
            this.updateStatus('Ready to start interview', 'info');
        }
    }

    async generateAndSaveNarrative() {
        if (this.interviewData.responses.length === 0) {
            alert('No interview responses to process. Please complete the interview first.');
            return;
        }
        
        this.updateStatus('Generating user profile narrative...', 'processing');
        
        try {
            const narrative = await this.generateNarrative();
            await this.populateUserInfoFields(narrative);
            
            this.updateStatus('User profile generated and saved successfully!', 'success');
            alert('User profile has been generated and populated in the form. You can now review and make any adjustments before saving.');
            
            // Close the interview modal
            setTimeout(() => {
                this.handleCloseModal();
            }, 2000);
            
        } catch (error) {
            console.error('Error generating narrative:', error);
            this.updateStatus('Error generating user profile. Please try again.', 'error');
            alert('There was an error generating the user profile. Please try again or enter the information manually.');
        }
    }

    async generateNarrative() {
        try {
            // Prepare comprehensive interview responses for the API
            const responses = this.interviewData.responses.map(r => ({
                questionId: r.questionId,
                question: r.question,
                answer: r.answer,
                timestamp: r.timestamp || new Date().toISOString(),
                type: r.type || 'general'
            }));

            // Enhanced prompt that leverages the comprehensive nature of our questions
            const comprehensivePrompt = `Generate a detailed user profile narrative from this comprehensive interview. This information will be used by an AAC (Augmentative and Alternative Communication) system to provide personalized communication options.

Focus on creating a narrative that helps the communication system understand:
- The user's personality, preferences, and communication style
- Their relationships, interests, and daily life context  
- Their support needs and challenges
- Environmental factors that affect their communication
- Values and motivations that drive their choices

Write in third person as a cohesive, professional profile that caregivers and the AAC system can reference to provide better, more personalized communication support.`;

            // Call the backend API endpoint
            const response = await window.authenticatedFetch('/api/interview/generate-narrative', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    prompt: comprehensivePrompt,
                    responses: responses
                })
            });

            if (response.ok) {
                const data = await response.json();
                return data.narrative;
            } else {
                const errorData = await response.json();
                throw new Error(errorData.error || 'Failed to generate narrative');
            }
        } catch (error) {
            console.error('Error generating narrative:', error);
            
            // Fallback: Create a basic narrative from responses
            return this.createBasicNarrativeFromResponses();
        }
    }

    createBasicNarrativeFromResponses() {
        const responses = this.interviewData.responses;
        
        // Extract key information
        const nameResponse = responses.find(r => r.questionId.includes('name'));
        const userName = nameResponse ? nameResponse.answer.trim() : 'The user';
        
        let narrative = `This profile is for ${userName}.\n\n`;
        
        // Group responses by category
        const categories = {
            identity: [],
            communication: [],
            interests: [],
            relationships: [],
            daily_life: [],
            values: [],
            challenges: [],
            technology: []
        };
        
        responses.forEach(response => {
            const category = response.type || 'general';
            if (categories[category]) {
                categories[category].push(response);
            }
        });
        
        // Build narrative sections
        Object.keys(categories).forEach(category => {
            const categoryResponses = categories[category];
            if (categoryResponses.length > 0) {
                const categoryTitle = category.charAt(0).toUpperCase() + category.slice(1).replace('_', ' ');
                narrative += `${categoryTitle}:\n`;
                categoryResponses.forEach(response => {
                    narrative += `${response.answer}\n`;
                });
                narrative += '\n';
            }
        });
        
        return narrative;
    }

    async populateUserInfoFields(narrative) {
        // Extract user name and birthday from responses
        const nameResponse = this.interviewData.responses.find(r => r.questionId === 'user_name');
        const birthdayResponse = this.interviewData.responses.find(r => r.questionId === 'user_birthday');
        
        // Populate the user info textarea
        const userInfoTextarea = document.getElementById('user-info');
        if (userInfoTextarea) {
            userInfoTextarea.value = narrative;
        }
        
        // Populate birthday if we can parse it
        if (birthdayResponse) {
            const birthdayField = document.getElementById('userBirthdate');
            if (birthdayField) {
                const parsedDate = await this.parseBirthdayFromResponse(birthdayResponse.answer);
                if (parsedDate) {
                    birthdayField.value = parsedDate;
                }
            }
        }
        
        // Extract and populate friends/family information
        await this.populateFriendsFamily();
    }

    async parseBirthdayFromResponse(birthdayText) {
        try {
            const prompt = `Extract a date from this text and return it in YYYY-MM-DD format. If no year is mentioned, use 2000 as default.

Text: "${birthdayText}"

Return only the date in YYYY-MM-DD format or "NONE" if no valid date can be extracted.`;
            
            const response = await this.callLLM(prompt);
            const dateMatch = response.match(/\d{4}-\d{2}-\d{2}/);
            return dateMatch ? dateMatch[0] : null;
        } catch (error) {
            console.error('Error parsing birthday:', error);
            return null;
        }
    }

    async populateFriendsFamily() {
        // Look for responses that mention family members or friends
        const familyResponses = this.interviewData.responses.filter(r => 
            r.answer.toLowerCase().includes('family') || 
            r.answer.toLowerCase().includes('friend') ||
            r.answer.toLowerCase().includes('mom') ||
            r.answer.toLowerCase().includes('dad') ||
            r.answer.toLowerCase().includes('sister') ||
            r.answer.toLowerCase().includes('brother') ||
            r.answer.toLowerCase().includes('spouse') ||
            r.answer.toLowerCase().includes('wife') ||
            r.answer.toLowerCase().includes('husband')
        );
        
        if (familyResponses.length === 0) return;
        
        const familyText = familyResponses.map(r => r.answer).join(' ');
        
        try {
            const prompt = `Extract family members and friends from this text. For each person mentioned, provide:
- Name (what the user calls them)
- Relationship (mom, dad, sister, friend, etc.)
- Brief description (1-2 sentences about them)

Text: "${familyText}"

Format as JSON array:
[{"name": "Name", "relationship": "Relationship", "about": "Brief description"}]

Return only the JSON array or empty array [] if no clear people are mentioned.`;
            
            const response = await this.callLLM(prompt);
            
            if (!response || response.trim() === '') {
                console.log('No response from LLM for family extraction');
                return;
            }
            
            try {
                // Clean the response - sometimes LLM returns extra text
                let cleanResponse = response.trim();
                
                // Find JSON array in the response
                const jsonMatch = cleanResponse.match(/\[[\s\S]*\]/);
                if (jsonMatch) {
                    cleanResponse = jsonMatch[0];
                }
                
                const people = JSON.parse(cleanResponse);
                if (Array.isArray(people) && people.length > 0) {
                    console.log('Extracted family/friends:', people);
                    // Add these to the friends/family table if the functions exist
                    if (window.addFamilyMember) {
                        people.forEach(person => {
                            if (person.name && person.relationship) {
                                window.addFamilyMember(person.name, person.relationship, person.about || '', '');
                            }
                        });
                    }
                }
            } catch (parseError) {
                console.warn('Could not parse family members JSON:', parseError);
                console.warn('Raw response was:', response);
            }
        } catch (error) {
            console.error('Error extracting family members:', error);
        }
    }

    updateStatus(message, type = 'info') {
        const statusEl = this.interviewStatus.querySelector('span');
        const iconEl = this.interviewStatus.querySelector('i');
        
        if (statusEl) {
            statusEl.textContent = message;
        }
        
        if (iconEl) {
            iconEl.className = this.getStatusIcon(type);
        }
        
        console.log(`Interview Status [${type}]: ${message}`);
    }

    getStatusIcon(type) {
        const icons = {
            info: 'fas fa-info-circle text-blue-600',
            success: 'fas fa-check-circle text-green-600',
            warning: 'fas fa-exclamation-triangle text-yellow-600',
            error: 'fas fa-times-circle text-red-600',
            listening: 'fas fa-microphone-alt text-blue-600',
            processing: 'fas fa-spinner fa-spin text-blue-600'
        };
        return icons[type] || icons.info;
    }

    updateProgress() {
        const total = this.currentQuestions.length;
        const current = Math.min(this.currentQuestionIndex + 1, total);
        this.interviewProgress.textContent = `Question ${current} of ${total}`;
    }

    addToInterviewLog(message, type) {
        const logEntry = document.createElement('div');
        logEntry.className = `interview-log-entry ${type}`;
        
        const timestamp = new Date().toLocaleTimeString();
        logEntry.innerHTML = `
            <div class="flex justify-between items-start">
                <div class="flex-1">
                    <span class="text-sm text-gray-500">[${timestamp}]</span>
                    <div class="mt-1 ${this.getLogEntryClass(type)}">${message}</div>
                </div>
            </div>
        `;
        
        this.interviewLog.appendChild(logEntry);
        
        // Scroll to bottom
        this.interviewLog.scrollTop = this.interviewLog.scrollHeight;
    }

    getLogEntryClass(type) {
        const classes = {
            question: 'font-medium text-blue-800',
            answer: 'text-gray-700 italic',
            skipped: 'text-gray-500 italic'
        };
        return classes[type] || 'text-gray-700';
    }

    clearInterviewLog() {
        this.interviewLog.innerHTML = '<p class="text-gray-600 italic">Questions and answers will appear here as we progress through the interview.</p>';
    }

    getUserStorageKey() {
        const currentAacUserId = sessionStorage.getItem('currentAacUserId');
        if (currentAacUserId) {
            return `audioInterviewProgress_${currentAacUserId}`;
        }
        // Fallback to generic key if no user ID available
        return 'audioInterviewProgress';
    }

    async saveProgress() {
        try {
            this.interviewData.lastSaveTime = new Date().toISOString();
            
            const progressData = {
                interviewData: this.interviewData,
                currentQuestionIndex: this.currentQuestionIndex,
                currentQuestions: this.currentQuestions
            };
            
            const storageKey = this.getUserStorageKey();
            localStorage.setItem(storageKey, JSON.stringify(progressData));
            
            this.updateStatus('Progress saved', 'success');
            
            setTimeout(() => {
                if (!this.isActive) {
                    this.updateStatus('Ready to continue interview', 'info');
                }
            }, 2000);
            
        } catch (error) {
            console.error('Error saving progress:', error);
            this.updateStatus('Error saving progress', 'error');
        }
    }

    loadSavedProgress() {
        try {
            const storageKey = this.getUserStorageKey();
            const savedProgress = localStorage.getItem(storageKey);
            if (savedProgress) {
                const progressData = JSON.parse(savedProgress);
                
                this.interviewData = progressData.interviewData || this.interviewData;
                this.currentQuestionIndex = progressData.currentQuestionIndex || 0;
                this.currentQuestions = progressData.currentQuestions || [...this.baseQuestions];
                
                // Restore interview log
                if (this.interviewData.responses.length > 0) {
                    this.clearInterviewLog();
                    this.interviewData.responses.forEach((response, index) => {
                        this.addToInterviewLog(`Q${index + 1}: ${response.question}`, 'question');
                        this.addToInterviewLog(`A${index + 1}: ${response.answer}`, 'answer');
                    });
                }
                
                console.log('Loaded saved interview progress:', this.interviewData.responses.length, 'responses');
            }
        } catch (error) {
            console.error('Error loading saved progress:', error);
        }
    }

    clearSavedProgress() {
        const storageKey = this.getUserStorageKey();
        localStorage.removeItem(storageKey);
    }

    // Method to reset interview data when user changes (called during logout/profile switch)
    resetForNewUser() {
        console.log('Resetting interview system for new user');
        
        // Clear current interview data
        this.interviewData = {
            responses: [],
            startTime: null,
            lastSaveTime: null
        };
        
        // Reset state
        this.currentQuestionIndex = 0;
        this.currentQuestions = [...this.baseQuestions];
        this.isActive = false;
        this.isPaused = false;
        
        // Clear UI
        this.clearInterviewLog();
        if (this.currentQuestion) {
            this.currentQuestion.textContent = 'Click "Start Interview" to begin gathering information about the user.';
        }
        
        // Don't automatically clear saved progress since that might be for a different user
        // Each user's progress is stored separately now
    }

}

// Initialize the interview system when the page loads
document.addEventListener('DOMContentLoaded', () => {
    // Only create if it doesn't already exist
    if (!window.audioInterviewSystem && !window.interviewSystem) {
        setTimeout(() => {
            window.audioInterviewSystem = new AudioInterviewSystem();
            console.log('Audio Interview System initialized');
        }, 1000);
    }
});

// Function to refresh interview data when user context changes
window.refreshInterviewForUser = function() {
    if (window.audioInterviewSystem) {
        console.log('Refreshing interview data for current user');
        window.audioInterviewSystem.resetForNewUser();
        window.audioInterviewSystem.loadSavedProgress();
    }
};