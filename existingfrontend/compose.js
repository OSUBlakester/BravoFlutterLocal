let firebaseIdToken = null;
let currentAacUserId = null;
let currentDocumentId = null;
let documentsCache = [];

function setStatus(message, isError = false) {
    const statusEl = document.getElementById('status-text');
    statusEl.textContent = message;
    statusEl.style.color = isError ? '#dc2626' : '#1f2937';
}

async function authenticatedFetch(url, options = {}, _isRetry = false) {
    firebaseIdToken = sessionStorage.getItem('firebaseIdToken');
    currentAacUserId = sessionStorage.getItem('currentAacUserId');

    if (!firebaseIdToken || !currentAacUserId) {
        window.location.href = '/static/auth.html';
        throw new Error('User not authenticated');
    }

    const headers = options.headers || {};
    headers['Authorization'] = `Bearer ${firebaseIdToken}`;
    headers['X-User-ID'] = currentAacUserId;

    const adminTargetAccountId = sessionStorage.getItem('adminTargetAccountId');
    if (adminTargetAccountId) {
        headers['X-Admin-Target-Account'] = adminTargetAccountId;
    }

    options.headers = headers;

    const response = await fetch(url, options);
    if ((response.status === 401 || response.status === 403) && !_isRetry && typeof window.refreshFirebaseToken === 'function') {
        const newToken = await window.refreshFirebaseToken();
        if (newToken) {
            return authenticatedFetch(url, options, true);
        }
    }

    if (response.status === 401 || response.status === 403) {
        window.location.href = '/static/auth.html';
        throw new Error('Authentication failed');
    }

    return response;
}

function getHomeTarget() {
    const params = new URLSearchParams(window.location.search);
    return params.get('from') || '/static/gridpage.html?page=home';
}

function parseEmailList(value) {
    return String(value || '')
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
}

function updateTypeUI() {
    const isEmail = document.getElementById('document-type').value === 'email';
    const emailFields = document.getElementById('email-fields');
    emailFields.classList.toggle('hidden', !isEmail);
    document.getElementById('send-btn').disabled = !isEmail;
}

function applyDocumentToForm(doc) {
    const safeDoc = doc || {};
    currentDocumentId = safeDoc.id || null;

    document.getElementById('document-type').value = safeDoc.document_type || 'story';
    document.getElementById('document-title').value = safeDoc.title || '';
    document.getElementById('document-body').value = safeDoc.body || '';
    document.getElementById('email-to').value = Array.isArray(safeDoc.to) ? safeDoc.to.join(', ') : '';
    document.getElementById('email-cc').value = Array.isArray(safeDoc.cc) ? safeDoc.cc.join(', ') : '';
    document.getElementById('email-bcc').value = Array.isArray(safeDoc.bcc) ? safeDoc.bcc.join(', ') : '';
    document.getElementById('email-subject').value = safeDoc.subject || '';

    const url = (safeDoc.illustration_url || '').trim();
    const imageEl = document.getElementById('illustration-image');
    const placeholderEl = document.getElementById('illustration-placeholder');
    if (url) {
        imageEl.src = url;
        imageEl.classList.remove('hidden');
        placeholderEl.classList.add('hidden');
    } else {
        imageEl.removeAttribute('src');
        imageEl.classList.add('hidden');
        placeholderEl.classList.remove('hidden');
    }

    updateTypeUI();
}

function clearForm(documentType = 'story') {
    currentDocumentId = null;
    applyDocumentToForm({
        document_type: documentType,
        title: '',
        body: '',
        to: [],
        cc: [],
        bcc: [],
        subject: '',
        illustration_url: ''
    });
}

function renderDocumentsList() {
    const listEl = document.getElementById('documents-list');
    listEl.innerHTML = '';

    if (!documentsCache.length) {
        const empty = document.createElement('div');
        empty.className = 'doc-meta';
        empty.textContent = 'No saved creations yet.';
        listEl.appendChild(empty);
        return;
    }

    documentsCache.forEach((doc) => {
        const item = document.createElement('button');
        item.type = 'button';
        item.className = `doc-item ${doc.id === currentDocumentId ? 'active' : ''}`;
        item.innerHTML = `
            <div class="doc-title">${doc.title || 'Untitled'}</div>
            <div class="doc-meta">${doc.document_type || 'story'} • ${(doc.updated_at || '').slice(0, 10) || 'unknown date'}</div>
        `;
        item.addEventListener('click', () => applyDocumentToForm(doc));
        listEl.appendChild(item);
    });
}

async function loadDocuments() {
    setStatus('Loading saved creations...');
    const response = await authenticatedFetch('/api/compose/documents');
    if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    const data = await response.json();
    if (!data.success) {
        throw new Error(data.error || 'Failed to load creations');
    }
    documentsCache = Array.isArray(data.documents) ? data.documents : [];
    renderDocumentsList();
    setStatus('Creations loaded.');
}

function buildPayloadFromForm() {
    return {
        document_type: document.getElementById('document-type').value,
        title: document.getElementById('document-title').value,
        body: document.getElementById('document-body').value,
        to: parseEmailList(document.getElementById('email-to').value),
        cc: parseEmailList(document.getElementById('email-cc').value),
        bcc: parseEmailList(document.getElementById('email-bcc').value),
        subject: document.getElementById('email-subject').value
    };
}

async function saveCurrentDocument() {
    const payload = buildPayloadFromForm();
    const isUpdate = Boolean(currentDocumentId);
    setStatus(isUpdate ? 'Saving creation...' : 'Starting new creation...');

    const response = await authenticatedFetch(
        isUpdate ? `/api/compose/documents/${currentDocumentId}` : '/api/compose/documents',
        {
            method: isUpdate ? 'PUT' : 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        }
    );

    if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Save failed (${response.status})`);
    }

    const data = await response.json();
    if (!data.success) {
        throw new Error(data.error || 'Save failed');
    }

    const saved = data.document;
    if (saved && saved.id) {
        const existingIndex = documentsCache.findIndex((item) => item.id === saved.id);
        if (existingIndex >= 0) {
            documentsCache[existingIndex] = saved;
        } else {
            documentsCache.unshift(saved);
        }
        currentDocumentId = saved.id;
        renderDocumentsList();
        applyDocumentToForm(saved);
    }

    setStatus('Creation saved.');
}

async function deleteCurrentDocument() {
    if (!currentDocumentId) {
        setStatus('Save this creation first before deleting.', true);
        return;
    }
    if (!window.confirm('Delete this creation?')) {
        return;
    }

    setStatus('Deleting creation...');
    const response = await authenticatedFetch(`/api/compose/documents/${currentDocumentId}`, {
        method: 'DELETE'
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Delete failed (${response.status})`);
    }

    documentsCache = documentsCache.filter((item) => item.id !== currentDocumentId);
    clearForm('story');
    renderDocumentsList();
    setStatus('Creation deleted.');
}

async function generateIllustration() {
    if (!currentDocumentId) {
        setStatus('Save the creation first before generating an illustration.', true);
        return;
    }

    setStatus('Generating AI illustration...');
    const style = document.getElementById('illustration-style').value || 'storybook illustration';
    const response = await authenticatedFetch(`/api/compose/documents/${currentDocumentId}/illustrate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ style, regenerate: true })
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Illustration failed (${response.status})`);
    }

    const data = await response.json();
    if (!data.success || !data.document) {
        throw new Error(data.error || 'Illustration failed');
    }

    const updated = data.document;
    const existingIndex = documentsCache.findIndex((item) => item.id === updated.id);
    if (existingIndex >= 0) {
        documentsCache[existingIndex] = updated;
    }
    applyDocumentToForm(updated);
    renderDocumentsList();
    setStatus('Illustration generated.');
}

async function sendCurrentEmail() {
    if (!currentDocumentId) {
        setStatus('Save the email draft first.', true);
        return;
    }

    if (document.getElementById('document-type').value !== 'email') {
        setStatus('Switch document type to Email to send.', true);
        return;
    }

    setStatus('Sending email...');
    const response = await authenticatedFetch(`/api/compose/documents/${currentDocumentId}/send-email`, {
        method: 'POST'
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Send failed (${response.status})`);
    }

    const data = await response.json();
    if (!data.success) {
        throw new Error(data.error || 'Send failed');
    }

    setStatus('Email sent successfully.');
}

async function connectGmail() {
    setStatus('Creating Gmail connection URL...');
    const response = await authenticatedFetch('/api/email/connect-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: 'gmail' })
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Connect URL failed (${response.status})`);
    }

    const data = await response.json();
    const url = data.connect_url;
    if (!url) {
        throw new Error('Connect URL missing');
    }

    window.location.href = url;
}

function setupEventListeners() {
    document.getElementById('home-btn').addEventListener('click', () => {
        window.location.href = getHomeTarget();
    });

    document.getElementById('new-story-btn').addEventListener('click', () => clearForm('story'));
    document.getElementById('new-email-btn').addEventListener('click', () => clearForm('email'));
    document.getElementById('document-type').addEventListener('change', updateTypeUI);

    document.getElementById('save-btn').addEventListener('click', () => {
        saveCurrentDocument().catch((error) => {
            console.error('Save error:', error);
            setStatus(`Save failed: ${error.message}`, true);
        });
    });

    document.getElementById('delete-btn').addEventListener('click', () => {
        deleteCurrentDocument().catch((error) => {
            console.error('Delete error:', error);
            setStatus(`Delete failed: ${error.message}`, true);
        });
    });

    document.getElementById('illustrate-btn').addEventListener('click', () => {
        generateIllustration().catch((error) => {
            console.error('Illustration error:', error);
            setStatus(`Illustration failed: ${error.message}`, true);
        });
    });

    document.getElementById('send-btn').addEventListener('click', () => {
        sendCurrentEmail().catch((error) => {
            console.error('Send email error:', error);
            setStatus(`Send failed: ${error.message}`, true);
        });
    });

    document.getElementById('gmail-connect-btn').addEventListener('click', () => {
        connectGmail().catch((error) => {
            console.error('Gmail connect error:', error);
            setStatus(`Gmail connect failed: ${error.message}`, true);
        });
    });
}

async function initialize() {
    setupEventListeners();
    clearForm('story');
    try {
        await loadDocuments();
    } catch (error) {
        console.error('Initialization error:', error);
        setStatus(`Failed to load creations: ${error.message}`, true);
    }
}

initialize();
