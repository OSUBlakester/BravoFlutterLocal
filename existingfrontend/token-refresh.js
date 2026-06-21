/**
 * Firebase Token Refresh Module
 * 
 * Keeps Firebase ID tokens fresh for pages that rely on sessionStorage tokens.
 * Firebase ID tokens expire after 1 hour. This module:
 * 1. Initializes the Firebase Auth SDK (if not already initialized)
 * 2. Listens for auth state AND token changes, auto-updates sessionStorage
 * 3. Sets up a proactive refresh timer (every 10 minutes)
 * 4. Exposes refreshFirebaseToken() for on-demand refresh (e.g., on 401)
 * 5. Falls back to silent re-authentication using saved credentials if
 *    the Firebase SDK loses the user session (e.g., IndexedDB cleared)
 * 
 * Usage: Include Firebase SDK scripts BEFORE this script:
 *   <script src="https://www.gstatic.com/firebasejs/9.6.1/firebase-app-compat.js"></script>
 *   <script src="https://www.gstatic.com/firebasejs/9.6.1/firebase-auth-compat.js"></script>
 *   <script src="/static/token-refresh.js"></script>
 */

(function() {
    'use strict';

    const TOKEN_KEY = 'firebaseIdToken';
    const REFRESH_INTERVAL_MS = 10 * 60 * 1000; // 10 minutes (well within 1-hour token lifetime)
    const AUTH_STATE_TIMEOUT_MS = 10 * 1000; // 10 second timeout for auth state resolution
    let refreshTimer = null;
    let isInitialized = false;
    let initPromise = null;
    let authStateResolved = false;
    let silentReauthAttempted = false; // Prevent infinite re-auth loops

    /**
     * Initialize Firebase and set up token auto-refresh.
     * Safe to call multiple times — will only initialize once.
     */
    async function initTokenRefresh() {
        if (initPromise) return initPromise;
        
        initPromise = _doInit();
        return initPromise;
    }

    async function _doInit() {
        if (isInitialized) return;

        try {
            // Initialize Firebase if not already done
            if (!firebase.apps.length) {
                const response = await fetch('/api/frontend-config');
                if (!response.ok) throw new Error(`Config fetch failed: ${response.status}`);
                const config = await response.json();
                if (!config.apiKey) throw new Error('Invalid Firebase config');
                firebase.initializeApp(config);
                console.log('[TokenRefresh] Firebase initialized for project:', config.projectId);
            }

            // Explicitly set LOCAL persistence (IndexedDB) to ensure session survives page reloads
            try {
                await firebase.auth().setPersistence(firebase.auth.Auth.Persistence.LOCAL);
            } catch (e) {
                console.warn('[TokenRefresh] Could not set persistence:', e);
            }

            // Wait for Firebase to restore auth state from IndexedDB.
            await new Promise((resolve) => {
                const timeout = setTimeout(() => {
                    console.warn('[TokenRefresh] Auth state resolution timed out after', AUTH_STATE_TIMEOUT_MS / 1000, 'seconds');
                    authStateResolved = true;
                    resolve();
                }, AUTH_STATE_TIMEOUT_MS);

                firebase.auth().onAuthStateChanged(async (user) => {
                    if (!authStateResolved) {
                        clearTimeout(timeout);
                        authStateResolved = true;
                    }

                    if (user) {
                        try {
                            const token = await user.getIdToken();
                            sessionStorage.setItem(TOKEN_KEY, token);
                            console.log('[TokenRefresh] Token updated via onAuthStateChanged, uid:', user.uid);
                        } catch (e) {
                            console.warn('[TokenRefresh] Failed to get token in onAuthStateChanged:', e);
                        }
                    } else {
                        console.warn('[TokenRefresh] AUTH STATE CHANGED TO NULL — user signed out or session lost');
                    }

                    resolve();
                });
            });

            // Also listen for token changes (fires on auto-refresh, not just sign-in/out)
            firebase.auth().onIdTokenChanged(async (user) => {
                if (user) {
                    try {
                        const token = await user.getIdToken();
                        sessionStorage.setItem(TOKEN_KEY, token);
                        console.log('[TokenRefresh] Token updated via onIdTokenChanged');
                    } catch (e) {
                        console.warn('[TokenRefresh] Failed to get token in onIdTokenChanged:', e);
                    }
                }
            });

            // Set up proactive refresh timer
            _startRefreshTimer();

            isInitialized = true;
            console.log('[TokenRefresh] Initialized — user:', !!firebase.auth().currentUser,
                        ', savedCreds:', !!(localStorage.getItem('bravoSavedEmail') && localStorage.getItem('bravoSavedPassword')));
        } catch (e) {
            console.error('[TokenRefresh] Initialization error:', e);
        }
    }

    /**
     * Attempt silent re-authentication using saved credentials from localStorage.
     * This is the fallback when firebase.auth().currentUser is null (session lost).
     * Returns the new token, or null if re-auth failed.
     */
    async function _attemptSilentReauth() {
        if (silentReauthAttempted) {
            console.warn('[TokenRefresh] Silent re-auth already attempted this session, skipping');
            return null;
        }
        silentReauthAttempted = true;

        const savedEmail = localStorage.getItem('bravoSavedEmail');
        const savedPassword = localStorage.getItem('bravoSavedPassword');

        if (!savedEmail || !savedPassword) {
            console.warn('[TokenRefresh] No saved credentials available for silent re-auth');
            return null;
        }

        try {
            console.log('[TokenRefresh] Attempting silent re-authentication with saved credentials...');
            const userCredential = await firebase.auth().signInWithEmailAndPassword(savedEmail, savedPassword);
            const newToken = await userCredential.user.getIdToken();
            sessionStorage.setItem(TOKEN_KEY, newToken);
            console.log('[TokenRefresh] Silent re-authentication successful!');
            silentReauthAttempted = false; // Reset flag on success so future attempts work
            return newToken;
        } catch (e) {
            console.error('[TokenRefresh] Silent re-authentication failed:', e.code, e.message);
            return null;
        }
    }

    /**
     * Force-refresh the Firebase ID token and update sessionStorage.
     * Returns the new token, or null if refresh failed.
     * 
     * Strategy:
     * 1. Try getIdToken(true) if currentUser exists
     * 2. If no currentUser, fall back to silent re-auth with saved credentials
     * 3. If all fails, return null (caller handles redirect to login)
     */
    async function refreshFirebaseToken() {
        try {
            // Ensure Firebase is initialized AND auth state is resolved
            await initTokenRefresh();

            let user = firebase.auth().currentUser;

            // Strategy 1: Use existing Firebase session
            if (user) {
                try {
                    const newToken = await user.getIdToken(true);
                    sessionStorage.setItem(TOKEN_KEY, newToken);
                    console.log('[TokenRefresh] Token force-refreshed successfully via getIdToken');
                    return newToken;
                } catch (e) {
                    console.warn('[TokenRefresh] getIdToken(true) failed:', e.code || e.message);
                    // Fall through to re-auth
                }
            } else {
                console.warn('[TokenRefresh] No current user — Firebase session lost');
            }

            // Strategy 2: Silent re-authentication with saved credentials
            console.log('[TokenRefresh] Attempting silent re-auth fallback...');
            const reauthToken = await _attemptSilentReauth();
            if (reauthToken) {
                return reauthToken;
            }

            console.error('[TokenRefresh] All refresh strategies exhausted');
            return null;
        } catch (e) {
            console.error('[TokenRefresh] Force refresh failed:', e);
            return null;
        }
    }

    function _startRefreshTimer() {
        if (refreshTimer) clearInterval(refreshTimer);
        
        refreshTimer = setInterval(async () => {
            const user = firebase.auth().currentUser;
            console.log('[TokenRefresh] Proactive refresh triggered — currentUser:', !!user);
            await refreshFirebaseToken();
        }, REFRESH_INTERVAL_MS);
    }

    // Expose globally
    window.initTokenRefresh = initTokenRefresh;
    window.refreshFirebaseToken = refreshFirebaseToken;

    // Auto-initialize when the script loads (non-blocking)
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => initTokenRefresh());
    } else {
        initTokenRefresh();
    }
})();
