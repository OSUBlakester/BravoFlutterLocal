/**
 * Interactive Guide System for Bravo AAC
 * Provides guided tours, contextual help, and interactive tutorials
 */

class InteractiveGuide {
    constructor() {
        this.currentTour = null;
        this.currentStep = 0;
        this.isActive = false;
        this.guides = new Map();
        this.overlay = null;
        this.tooltip = null;
        this.progress = null;
        this.navigation = null;
        this.practiceMode = false;
        this.userProgress = this.loadUserProgress();
        
        this.init();
    }

    init() {
        this.createOverlayElements();
        this.loadPageGuides();
        this.attachEventListeners();
        this.checkAutoStart();
    }

    createOverlayElements() {
        // Main overlay
        this.overlay = document.createElement('div');
        this.overlay.id = 'guide-overlay';
        this.overlay.className = 'guide-overlay hidden';
        this.overlay.innerHTML = `
            <div class="guide-backdrop"></div>
            <div class="guide-highlight"></div>
        `;

        // Tooltip/content panel
        this.tooltip = document.createElement('div');
        this.tooltip.id = 'guide-tooltip';
        this.tooltip.className = 'guide-tooltip hidden';
        
        // Progress indicator
        this.progress = document.createElement('div');
        this.progress.id = 'guide-progress';
        this.progress.className = 'guide-progress hidden';
        
        // Navigation panel
        this.navigation = document.createElement('div');
        this.navigation.id = 'guide-navigation';
        this.navigation.className = 'guide-navigation hidden';

        document.body.appendChild(this.overlay);
        document.body.appendChild(this.tooltip);
        document.body.appendChild(this.progress);
        document.body.appendChild(this.navigation);

        this.injectStyles();
    }

    injectStyles() {
        const styles = `
            <style>
                .guide-overlay {
                    position: fixed;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    z-index: 10000;
                    pointer-events: none;
                }

                .guide-overlay.active {
                    pointer-events: auto;
                }

                .guide-backdrop {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background: rgba(0, 0, 0, 0.7);
                    backdrop-filter: blur(2px);
                }

                .guide-highlight {
                    position: absolute;
                    border: 3px solid #3b82f6;
                    border-radius: 8px;
                    box-shadow: 0 0 20px rgba(59, 130, 246, 0.5);
                    background: rgba(59, 130, 246, 0.1);
                    pointer-events: none;
                    transition: all 0.3s ease;
                    animation: pulse-highlight 2s infinite;
                }

                @keyframes pulse-highlight {
                    0%, 100% { box-shadow: 0 0 20px rgba(59, 130, 246, 0.5); }
                    50% { box-shadow: 0 0 30px rgba(59, 130, 246, 0.8); }
                }

                .guide-tooltip {
                    position: fixed;
                    max-width: 400px;
                    background: white;
                    border-radius: 12px;
                    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
                    z-index: 10001;
                    transform: scale(0.8) translateY(10px);
                    opacity: 0;
                    transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
                    border: 1px solid #e5e7eb;
                }

                .guide-tooltip.visible {
                    transform: scale(1) translateY(0);
                    opacity: 1;
                }

                .guide-tooltip-header {
                    padding: 20px 20px 0;
                    border-bottom: 1px solid #f3f4f6;
                }

                .guide-tooltip-title {
                    font-size: 18px;
                    font-weight: bold;
                    color: #1f2937;
                    margin: 0;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }

                .guide-tooltip-content {
                    padding: 20px;
                    color: #4b5563;
                    line-height: 1.6;
                }

                .guide-tooltip-media {
                    margin: 15px 0;
                    border-radius: 8px;
                    overflow: hidden;
                }

                .guide-tooltip-media img,
                .guide-tooltip-media video {
                    width: 100%;
                    height: auto;
                    display: block;
                }

                .guide-tooltip-footer {
                    padding: 0 20px 20px;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    gap: 12px;
                }

                .guide-btn {
                    padding: 10px 16px;
                    border-radius: 6px;
                    border: none;
                    cursor: pointer;
                    font-weight: 500;
                    transition: all 0.2s;
                    display: flex;
                    align-items: center;
                    gap: 6px;
                }

                .guide-btn-primary {
                    background: #3b82f6;
                    color: white;
                }

                .guide-btn-primary:hover {
                    background: #2563eb;
                }

                .guide-btn-secondary {
                    background: #f3f4f6;
                    color: #6b7280;
                }

                .guide-btn-secondary:hover {
                    background: #e5e7eb;
                }

                .guide-btn-danger {
                    background: #ef4444;
                    color: white;
                }

                .guide-btn-danger:hover {
                    background: #dc2626;
                }

                .guide-progress {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: white;
                    padding: 15px 20px;
                    border-radius: 25px;
                    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
                    z-index: 10002;
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    font-weight: 500;
                    color: #1f2937;
                }

                .guide-progress-bar {
                    width: 100px;
                    height: 6px;
                    background: #e5e7eb;
                    border-radius: 3px;
                    overflow: hidden;
                }

                .guide-progress-fill {
                    height: 100%;
                    background: linear-gradient(90deg, #3b82f6, #10b981);
                    border-radius: 3px;
                    transition: width 0.3s ease;
                }

                .guide-navigation {
                    position: fixed;
                    bottom: 20px;
                    left: 50%;
                    transform: translateX(-50%);
                    background: white;
                    padding: 15px 20px;
                    border-radius: 50px;
                    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
                    z-index: 10002;
                    display: flex;
                    align-items: center;
                    gap: 10px;
                }

                .guide-nav-btn {
                    width: 40px;
                    height: 40px;
                    border-radius: 50%;
                    border: none;
                    background: #f3f4f6;
                    color: #6b7280;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 0.2s;
                }

                .guide-nav-btn:hover:not(:disabled) {
                    background: #3b82f6;
                    color: white;
                    transform: scale(1.1);
                }

                .guide-nav-btn:disabled {
                    opacity: 0.3;
                    cursor: not-allowed;
                }

                .guide-steps-indicator {
                    display: flex;
                    gap: 6px;
                    margin: 0 10px;
                }

                .guide-step-dot {
                    width: 8px;
                    height: 8px;
                    border-radius: 50%;
                    background: #d1d5db;
                    transition: all 0.2s;
                }

                .guide-step-dot.active {
                    background: #3b82f6;
                    transform: scale(1.3);
                }

                .guide-step-dot.completed {
                    background: #10b981;
                }

                .guide-tooltip-arrow {
                    position: absolute;
                    width: 0;
                    height: 0;
                    border: 8px solid transparent;
                }

                .guide-tooltip-arrow.top {
                    bottom: -16px;
                    left: 50%;
                    transform: translateX(-50%);
                    border-top-color: white;
                }

                .guide-tooltip-arrow.bottom {
                    top: -16px;
                    left: 50%;
                    transform: translateX(-50%);
                    border-bottom-color: white;
                }

                .guide-tooltip-arrow.left {
                    right: -16px;
                    top: 50%;
                    transform: translateY(-50%);
                    border-left-color: white;
                }

                .guide-tooltip-arrow.right {
                    left: -16px;
                    top: 50%;
                    transform: translateY(-50%);
                    border-right-color: white;
                }

                .guide-practice-mode {
                    position: fixed;
                    top: 20px;
                    left: 20px;
                    background: linear-gradient(135deg, #f59e0b, #d97706);
                    color: white;
                    padding: 12px 20px;
                    border-radius: 25px;
                    font-weight: bold;
                    z-index: 10002;
                    box-shadow: 0 10px 30px rgba(245, 158, 11, 0.3);
                    animation: bounce-practice 2s infinite;
                }

                @keyframes bounce-practice {
                    0%, 100% { transform: translateY(0); }
                    50% { transform: translateY(-5px); }
                }

                .guide-clickable-hint {
                    position: relative;
                    cursor: pointer !important;
                }

                .guide-clickable-hint::after {
                    content: '';
                    position: absolute;
                    top: -5px;
                    left: -5px;
                    right: -5px;
                    bottom: -5px;
                    border: 2px dashed #3b82f6;
                    border-radius: 8px;
                    animation: dash-border 1s linear infinite;
                    pointer-events: none;
                }

                @keyframes dash-border {
                    0% { border-color: #3b82f6; }
                    50% { border-color: #10b981; }
                    100% { border-color: #3b82f6; }
                }

                .hidden {
                    display: none !important;
                }

                .guide-completion-celebration {
                    position: fixed;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    background: white;
                    padding: 40px;
                    border-radius: 20px;
                    box-shadow: 0 30px 60px rgba(0, 0, 0, 0.3);
                    z-index: 10003;
                    text-align: center;
                    max-width: 400px;
                    animation: celebration-popup 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
                }

                @keyframes celebration-popup {
                    0% { transform: translate(-50%, -50%) scale(0.5); opacity: 0; }
                    100% { transform: translate(-50%, -50%) scale(1); opacity: 1; }
                }

                .guide-completion-icon {
                    font-size: 60px;
                    margin-bottom: 20px;
                    animation: bounce 1s ease-in-out infinite alternate;
                }

                @keyframes bounce {
                    0% { transform: translateY(0); }
                    100% { transform: translateY(-10px); }
                }
            </style>
        `;
        
        if (!document.querySelector('#guide-styles')) {
            const styleElement = document.createElement('div');
            styleElement.id = 'guide-styles';
            styleElement.innerHTML = styles;
            document.head.appendChild(styleElement);
        }
    }

    loadPageGuides() {
        const currentPage = this.getCurrentPage();
        
        // Load guides based on current page
        switch (currentPage) {
            case 'admin':
                this.loadAdminGuides();
                break;
            case 'help_admin':
                this.loadHelpAdminGuides();
                break;
            case 'user_info_admin':
                this.loadUserInfoAdminGuides();
                break;
            case 'favorites_admin':
                this.loadFavoritesAdminGuides();
                break;
            case 'audio_admin':
                this.loadAudioAdminGuides();
                break;
            case 'user_current_admin':
                this.loadUserCurrentAdminGuides();
                break;
            case 'user_diary_admin':
                this.loadUserDiaryAdminGuides();
                break;
            case 'admin_nav':
                this.loadAdminNavGuides();
                break;
            default:
                this.loadDefaultGuides();
        }
    }

    getCurrentPage() {
        const path = window.location.pathname;
        const filename = path.split('/').pop().replace('.html', '');
        return filename || 'home';
    }

    registerGuide(id, guide) {
        this.guides.set(id, guide);
    }

    startTour(guideId) {
        const guide = this.guides.get(guideId);
        if (!guide) {
            console.warn(`Guide ${guideId} not found`);
            return;
        }

        this.currentTour = guide;
        this.currentStep = 0;
        this.isActive = true;
        
        // Show overlay elements
        this.overlay.classList.remove('hidden');
        this.overlay.classList.add('active');
        this.tooltip.classList.remove('hidden');
        this.progress.classList.remove('hidden');
        this.navigation.classList.remove('hidden');

        // Start practice mode if enabled
        if (guide.practiceMode) {
            this.enablePracticeMode();
        }

        this.showStep(0);
        this.updateProgress();
        this.updateNavigation();
    }

    showStep(stepIndex) {
        if (!this.currentTour || stepIndex >= this.currentTour.steps.length) {
            return;
        }

        const step = this.currentTour.steps[stepIndex];
        this.currentStep = stepIndex;

        // Highlight target element
        this.highlightElement(step.target);

        // Position and show tooltip
        this.showTooltip(step);

        // Update UI
        this.updateProgress();
        this.updateNavigation();

        // Execute step action if any
        if (step.action) {
            step.action();
        }

        // Auto-advance if specified
        if (step.autoAdvance) {
            setTimeout(() => {
                this.nextStep();
            }, step.autoAdvance);
        }
    }

    highlightElement(selector) {
        // Remove existing clickable hints
        document.querySelectorAll('.guide-clickable-hint').forEach(el => {
            el.classList.remove('guide-clickable-hint');
        });

        if (!selector) {
            this.overlay.querySelector('.guide-highlight').style.display = 'none';
            return;
        }

        const element = document.querySelector(selector);
        if (!element) {
            console.warn(`Element ${selector} not found`);
            return;
        }

        const rect = element.getBoundingClientRect();
        const highlight = this.overlay.querySelector('.guide-highlight');
        
        highlight.style.display = 'block';
        highlight.style.left = `${rect.left - 5}px`;
        highlight.style.top = `${rect.top - 5}px`;
        highlight.style.width = `${rect.width + 10}px`;
        highlight.style.height = `${rect.height + 10}px`;

        // Add clickable hint if in practice mode
        if (this.practiceMode) {
            element.classList.add('guide-clickable-hint');
        }

        // Scroll element into view
        element.scrollIntoView({ 
            behavior: 'smooth', 
            block: 'center',
            inline: 'center'
        });
    }

    showTooltip(step) {
        const tooltip = this.tooltip;
        
        // Build tooltip content
        tooltip.innerHTML = `
            <div class="guide-tooltip-header">
                <h3 class="guide-tooltip-title">
                    ${step.icon ? `<span>${step.icon}</span>` : ''}
                    ${step.title}
                </h3>
            </div>
            <div class="guide-tooltip-content">
                ${step.content}
                ${step.media ? this.renderMedia(step.media) : ''}
                ${step.tips ? `<div class="guide-tips">${step.tips}</div>` : ''}
            </div>
            <div class="guide-tooltip-footer">
                <div class="guide-step-counter">
                    Step ${this.currentStep + 1} of ${this.currentTour.steps.length}
                </div>
                <div class="guide-actions">
                    ${this.currentStep > 0 ? '<button class="guide-btn guide-btn-secondary" id="tooltip-prev-btn">← Previous</button>' : ''}
                    ${step.interactive ? '<button class="guide-btn guide-btn-primary" id="tooltip-try-btn">Try It!</button>' : ''}
                    <button class="guide-btn guide-btn-primary" id="tooltip-next-btn">
                        ${this.currentStep === this.currentTour.steps.length - 1 ? 'Complete!' : 'Next →'}
                    </button>
                </div>
            </div>
            <div class="guide-tooltip-arrow ${this.getTooltipArrowDirection(step.target)}"></div>
        `;

        // Add event listeners to tooltip buttons
        const prevBtn = tooltip.querySelector('#tooltip-prev-btn');
        const nextBtn = tooltip.querySelector('#tooltip-next-btn');
        const tryBtn = tooltip.querySelector('#tooltip-try-btn');

        if (prevBtn) {
            prevBtn.addEventListener('click', () => this.prevStep());
        }
        if (nextBtn) {
            nextBtn.addEventListener('click', () => this.nextStep());
        }
        if (tryBtn) {
            tryBtn.addEventListener('click', () => this.handleInteraction());
        }

        // Position tooltip
        this.positionTooltip(step.target);
        
        // Show with animation
        setTimeout(() => {
            tooltip.classList.add('visible');
        }, 100);
    }

    renderMedia(media) {
        if (media.type === 'image') {
            return `<div class="guide-tooltip-media"><img src="${media.src}" alt="${media.alt || ''}" /></div>`;
        } else if (media.type === 'video') {
            return `<div class="guide-tooltip-media"><video controls src="${media.src}" ${media.autoplay ? 'autoplay' : ''} ${media.loop ? 'loop' : ''}></video></div>`;
        } else if (media.type === 'gif') {
            return `<div class="guide-tooltip-media"><img src="${media.src}" alt="${media.alt || ''}" /></div>`;
        }
        return '';
    }

    positionTooltip(targetSelector) {
        if (!targetSelector) {
            // Center the tooltip
            this.tooltip.style.left = '50%';
            this.tooltip.style.top = '50%';
            this.tooltip.style.transform = 'translate(-50%, -50%)';
            return;
        }

        const element = document.querySelector(targetSelector);
        if (!element) return;

        const rect = element.getBoundingClientRect();
        const tooltipRect = this.tooltip.getBoundingClientRect();
        const viewport = {
            width: window.innerWidth,
            height: window.innerHeight
        };

        let left, top;

        // Try to position tooltip to the right of the element
        if (rect.right + tooltipRect.width + 20 <= viewport.width) {
            left = rect.right + 20;
            top = rect.top + (rect.height / 2) - (tooltipRect.height / 2);
        }
        // Try to position tooltip to the left
        else if (rect.left - tooltipRect.width - 20 >= 0) {
            left = rect.left - tooltipRect.width - 20;
            top = rect.top + (rect.height / 2) - (tooltipRect.height / 2);
        }
        // Position below
        else if (rect.bottom + tooltipRect.height + 20 <= viewport.height) {
            left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
            top = rect.bottom + 20;
        }
        // Position above
        else {
            left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
            top = rect.top - tooltipRect.height - 20;
        }

        // Ensure tooltip stays within viewport
        left = Math.max(20, Math.min(left, viewport.width - tooltipRect.width - 20));
        top = Math.max(20, Math.min(top, viewport.height - tooltipRect.height - 20));

        this.tooltip.style.left = `${left}px`;
        this.tooltip.style.top = `${top}px`;
        this.tooltip.style.transform = 'none';
    }

    getTooltipArrowDirection(targetSelector) {
        // This would be enhanced to calculate the actual direction
        // For now, return a default
        return 'bottom';
    }

    updateProgress() {
        if (!this.currentTour) return;

        const progress = (this.currentStep + 1) / this.currentTour.steps.length * 100;
        
        this.progress.innerHTML = `
            <span>Guide Progress</span>
            <div class="guide-progress-bar">
                <div class="guide-progress-fill" style="width: ${progress}%"></div>
            </div>
            <span>${this.currentStep + 1}/${this.currentTour.steps.length}</span>
        `;
    }

    updateNavigation() {
        if (!this.currentTour) return;

        const steps = this.currentTour.steps.map((_, index) => {
            const status = index < this.currentStep ? 'completed' : 
                          index === this.currentStep ? 'active' : '';
            return `<div class="guide-step-dot ${status}"></div>`;
        }).join('');

        this.navigation.innerHTML = `
            <button class="guide-nav-btn" id="guide-prev-btn" ${this.currentStep === 0 ? 'disabled' : ''}>
                ←
            </button>
            <div class="guide-steps-indicator">${steps}</div>
            <button class="guide-nav-btn" id="guide-next-btn">
                ${this.currentStep === this.currentTour.steps.length - 1 ? '✓' : '→'}
            </button>
            <button class="guide-nav-btn guide-btn-danger" id="guide-close-btn" title="Exit Guide">
                ×
            </button>
        `;

        // Add event listeners to navigation buttons
        const prevBtn = this.navigation.querySelector('#guide-prev-btn');
        const nextBtn = this.navigation.querySelector('#guide-next-btn');
        const closeBtn = this.navigation.querySelector('#guide-close-btn');

        if (prevBtn) {
            prevBtn.addEventListener('click', () => this.prevStep());
        }
        if (nextBtn) {
            nextBtn.addEventListener('click', () => this.nextStep());
        }
        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.endTour());
        }
    }

    nextStep() {
        if (!this.currentTour) return;

        if (this.currentStep < this.currentTour.steps.length - 1) {
            this.tooltip.classList.remove('visible');
            setTimeout(() => {
                this.showStep(this.currentStep + 1);
            }, 200);
        } else {
            this.completeTour();
        }
    }

    prevStep() {
        if (!this.currentTour || this.currentStep === 0) return;

        this.tooltip.classList.remove('visible');
        setTimeout(() => {
            this.showStep(this.currentStep - 1);
        }, 200);
    }

    handleInteraction() {
        const step = this.currentTour.steps[this.currentStep];
        if (step.interactive && step.interactiveAction) {
            step.interactiveAction();
        }
    }

    enablePracticeMode() {
        this.practiceMode = true;
        
        const practiceIndicator = document.createElement('div');
        practiceIndicator.className = 'guide-practice-mode';
        practiceIndicator.innerHTML = '🎯 Practice Mode Active';
        practiceIndicator.id = 'guide-practice-indicator';
        
        document.body.appendChild(practiceIndicator);
    }

    disablePracticeMode() {
        this.practiceMode = false;
        const indicator = document.getElementById('guide-practice-indicator');
        if (indicator) {
            indicator.remove();
        }
        
        // Remove all clickable hints
        document.querySelectorAll('.guide-clickable-hint').forEach(el => {
            el.classList.remove('guide-clickable-hint');
        });
    }

    completeTour() {
        this.saveUserProgress();
        this.showCompletionCelebration();
        setTimeout(() => {
            this.endTour();
        }, 3000);
    }

    showCompletionCelebration() {
        const celebration = document.createElement('div');
        celebration.className = 'guide-completion-celebration';
        celebration.innerHTML = `
            <div class="guide-completion-icon">🎉</div>
            <h2>Congratulations!</h2>
            <p>You've completed the "${this.currentTour.title}" guide!</p>
            <div style="margin-top: 20px;">
                <div class="guide-completion-stats">
                    <span>✅ ${this.currentTour.steps.length} steps completed</span>
                </div>
            </div>
        `;
        
        document.body.appendChild(celebration);
        
        // Add confetti effect
        this.triggerConfetti();
        
        setTimeout(() => {
            celebration.remove();
        }, 3000);
    }

    triggerConfetti() {
        // Simple confetti effect
        for (let i = 0; i < 50; i++) {
            setTimeout(() => {
                const confetti = document.createElement('div');
                confetti.style.cssText = `
                    position: fixed;
                    width: 10px;
                    height: 10px;
                    background: ${['#3b82f6', '#10b981', '#f59e0b', '#ef4444'][Math.floor(Math.random() * 4)]};
                    top: -10px;
                    left: ${Math.random() * 100}%;
                    z-index: 10004;
                    animation: confetti-fall 3s ease-out forwards;
                    transform: rotate(${Math.random() * 360}deg);
                `;
                
                if (!document.querySelector('#confetti-styles')) {
                    const style = document.createElement('style');
                    style.id = 'confetti-styles';
                    style.textContent = `
                        @keyframes confetti-fall {
                            to {
                                transform: translateY(100vh) rotate(720deg);
                                opacity: 0;
                            }
                        }
                    `;
                    document.head.appendChild(style);
                }
                
                document.body.appendChild(confetti);
                
                setTimeout(() => confetti.remove(), 3000);
            }, i * 50);
        }
    }

    endTour() {
        this.isActive = false;
        this.currentTour = null;
        this.currentStep = 0;
        
        // Hide all guide elements
        this.overlay.classList.add('hidden');
        this.overlay.classList.remove('active');
        this.tooltip.classList.add('hidden');
        this.tooltip.classList.remove('visible');
        this.progress.classList.add('hidden');
        this.navigation.classList.add('hidden');
        
        // Disable practice mode
        this.disablePracticeMode();
        
        // Remove highlights
        this.highlightElement(null);
    }

    attachEventListeners() {
        // ESC key to exit
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isActive) {
                this.endTour();
            }
        });

        // Click outside tooltip to close (optional)
        this.overlay.addEventListener('click', (e) => {
            if (e.target === this.overlay.querySelector('.guide-backdrop')) {
                this.endTour();
            }
        });
    }

    checkAutoStart() {
        // Check if this is the user's first visit to this page
        const page = this.getCurrentPage();
        const hasVisited = this.userProgress.visitedPages?.includes(page);
        
        if (!hasVisited && this.guides.has(`${page}-intro`)) {
            // Auto-start intro guide
            setTimeout(() => {
                this.startTour(`${page}-intro`);
            }, 1000);
        }
    }

    loadUserProgress() {
        try {
            return JSON.parse(localStorage.getItem('guide-progress') || '{}');
        } catch {
            return {};
        }
    }

    saveUserProgress() {
        const page = this.getCurrentPage();
        this.userProgress.visitedPages = this.userProgress.visitedPages || [];
        
        if (!this.userProgress.visitedPages.includes(page)) {
            this.userProgress.visitedPages.push(page);
        }

        this.userProgress.completedGuides = this.userProgress.completedGuides || [];
        if (this.currentTour && !this.userProgress.completedGuides.includes(this.currentTour.id)) {
            this.userProgress.completedGuides.push(this.currentTour.id);
        }

        localStorage.setItem('guide-progress', JSON.stringify(this.userProgress));
    }

    // Guide definitions for different pages
    loadAdminGuides() {
        // We'll define these in separate files for each admin page
    }

    loadHelpAdminGuides() {
        // Will be defined in help-admin-guide.js
    }

    loadUserInfoAdminGuides() {
        // Will be defined in user-info-admin-guide.js
    }

    loadFavoritesAdminGuides() {
        // Will be defined in favorites-admin-guide.js
    }

    loadAudioAdminGuides() {
        // Will be defined in audio-admin-guide.js
    }

    loadUserCurrentAdminGuides() {
        // Will be defined in user-current-admin-guide.js
    }

    loadUserDiaryAdminGuides() {
        // Will be defined in user-diary-admin-guide.js
    }

    loadAdminNavGuides() {
        // Will be defined in admin-nav-guide.js
    }

    loadDefaultGuides() {
        // Default guides for main app
    }
}

// Make the class available globally immediately
window.InteractiveGuide = InteractiveGuide;

// Initialize the guide system
let interactiveGuideInstance;
document.addEventListener('DOMContentLoaded', () => {
    interactiveGuideInstance = new InteractiveGuide();
    
    // Add static methods to the class that delegate to the instance
    InteractiveGuide.registerGuide = function(id, config) {
        if (interactiveGuideInstance) {
            return interactiveGuideInstance.registerGuide(id, config);
        } else {
            console.warn('InteractiveGuide instance not ready yet');
        }
    };
    
    InteractiveGuide.startGuide = function(id) {
        if (interactiveGuideInstance) {
            return interactiveGuideInstance.startTour(id);
        } else {
            console.warn('InteractiveGuide instance not ready yet');
        }
    };
    
    InteractiveGuide.endTour = function() {
        if (interactiveGuideInstance) {
            return interactiveGuideInstance.endTour();
        } else {
            console.warn('InteractiveGuide instance not ready yet');
        }
    };
});

// Export for use in other scripts
if (typeof module !== 'undefined' && module.exports) {
    module.exports = InteractiveGuide;
}
