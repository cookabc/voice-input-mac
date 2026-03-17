// Voice Input App - Frontend Logic
'use strict';

// Check Tauri 2 API availability - try different possible paths
const Tauri = window.__TAURI__;
const invoke = Tauri?.core?.invoke || Tauri?.invoke || window.__TAURI_INVOKE__;
const listen = Tauri?.event?.listen || Tauri?.listen || window.__TAURI_EVENT__?.listen;

// App State
const state = {
    isRecording: false,
    recordingStart: null,
    timerInterval: null,
    currentAudioPath: null,
    settings: null,
    history: [],
    health: null,
};

// DOM Elements
const elements = {
    micIcon: document.getElementById('mic-icon'),
    waveform: document.getElementById('waveform'),
    statusText: document.getElementById('status-text'),
    timer: document.getElementById('timer'),
    recordBtn: document.getElementById('record-btn'),
    stopBtn: document.getElementById('stop-btn'),
    resultSection: document.getElementById('result-section'),
    resultText: document.getElementById('result-text'),
    copyResultBtn: document.getElementById('copy-result-btn'),
    pasteBtn: document.getElementById('paste-btn'),
    newRecordingBtn: document.getElementById('new-recording-btn'),
    tabsSection: document.getElementById('tabs-section'),
    tabs: document.querySelectorAll('.tab'),
    tabContents: document.querySelectorAll('.tab-content'),
    hotkey: document.getElementById('hotkey'),
    model: document.getElementById('model'),
    polish: document.getElementById('polish'),
    autoPaste: document.getElementById('auto-paste'),
    useApplescript: document.getElementById('use-applescript'),
    historyCount: document.getElementById('history-count'),
    saveSettingsBtn: document.getElementById('save-settings-btn'),
    changeHotkeyBtn: document.getElementById('change-hotkey-btn'),
    historyList: document.getElementById('history-list'),
    clearHistoryBtn: document.getElementById('clear-history-btn'),
};

// Utility Functions
function formatTime(seconds) {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

function formatDate(timestamp) {
    const date = new Date(timestamp * 1000);
    const now = new Date();
    const diff = now - date;

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
}

function showElement(el) {
    el?.classList.remove('hidden');
}

function hideElement(el) {
    el?.classList.add('hidden');
}

// Tauri Invoke Wrapper - Tauri 2
async function invokeCmd(cmd, args = {}) {
    if (typeof invoke === 'function') {
        return await invoke(cmd, args);
    }
    throw new Error('Tauri API not available');
}

// Tauri Listen Wrapper - Tauri 2
async function listenCmd(event, handler) {
    if (typeof listen === 'function') {
        return await listen(event, handler);
    }
    return () => {};
}

// Recording Functions
async function startRecording() {
    if (state.health && !state.health.ready) {
        if (elements.statusText) elements.statusText.textContent = state.health.issues.join(' ');
        return;
    }

    try {
        const audioPath = await invokeCmd('start_recording');

        if (audioPath) {
            state.isRecording = true;
            state.currentAudioPath = audioPath;
            state.recordingStart = Date.now();

            // Update UI
            elements.micIcon?.classList.add('recording');
            showElement(elements.waveform);
            showElement(elements.timer);
            hideElement(elements.recordBtn);
            showElement(elements.stopBtn);
            if (elements.statusText) elements.statusText.textContent = 'Recording...';

            // Start timer
            state.timerInterval = setInterval(updateTimer, 1000);
        }
    } catch (error) {
        console.error('Failed to start recording:', error);
        if (elements.statusText) elements.statusText.textContent = 'Error: ' + error;
    }
}

async function stopRecording() {
    try {
        console.log('Stopping recording...');
        await invokeCmd('stop_recording');
        console.log('Recording stopped');

        state.isRecording = false;

        // Stop timer
        if (state.timerInterval) {
            clearInterval(state.timerInterval);
            state.timerInterval = null;
        }

        // Update UI
        elements.micIcon?.classList.remove('recording');
        hideElement(elements.waveform);
        hideElement(elements.timer);
        showElement(elements.recordBtn);
        hideElement(elements.stopBtn);
        if (elements.statusText) elements.statusText.textContent = 'Processing...';

        // Transcribe
        if (state.currentAudioPath) {
            await transcribeAudio(state.currentAudioPath);
        }
    } catch (error) {
        console.error('Failed to stop recording:', error);
        if (elements.statusText) elements.statusText.textContent = 'Error: ' + error;
        resetRecordingUI();
    }
}

async function transcribeAudio(audioPath) {
    try {
        const result = await invokeCmd('transcribe_audio', {
            audioPath,
            model: state.settings?.model,
            polish: state.settings?.polish,
        });

        if (result?.text) {
            // Show result
            if (elements.resultText) elements.resultText.textContent = result.text;
            showElement(elements.resultSection);
            hideElement(elements.tabsSection);
            if (elements.statusText) elements.statusText.textContent = 'Done!';

            // Add to history
            await addHistoryEntry(result.text, result.lang, result.duration);

            // Auto paste if enabled
            if (state.settings?.autoPaste) {
                await pasteTranscription(result.text);
            }
        } else {
            throw new Error('No text in transcription result');
        }
    } catch (error) {
        console.error('Transcription failed:', error);
        if (elements.statusText) elements.statusText.textContent = 'Transcription failed: ' + error;
    } finally {
        state.currentAudioPath = null;
    }
}

async function pasteTranscription(text) {
    try {
        await invokeCmd('paste_transcription', {
            text,
            useApplescript: state.settings?.useApplescript,
        });
    } catch (error) {
        if (elements.statusText) {
            elements.statusText.textContent = 'Text copied, but auto-paste failed';
        }
    }
}

async function loadRuntimeHealth() {
    try {
        state.health = await invokeCmd('get_runtime_health');

        if (elements.recordBtn) {
            elements.recordBtn.disabled = !state.health?.ready;
        }

        if (elements.statusText && state.health) {
            if (state.health.ready) {
                elements.statusText.textContent = 'Ready';
                elements.statusText.style.color = '';
            } else {
                elements.statusText.textContent = state.health.issues.join(' ');
                elements.statusText.style.color = '#ff4a4a';
            }
        }
    } catch (error) {
        state.health = null;
    }
}

function updateTimer() {
    if (state.recordingStart) {
        const seconds = Math.floor((Date.now() - state.recordingStart) / 1000);
        if (elements.timer) elements.timer.textContent = formatTime(seconds);
    }
}

function resetRecordingUI() {
    elements.micIcon?.classList.remove('recording');
    hideElement(elements.waveform);
    hideElement(elements.timer);
    showElement(elements.recordBtn);
    hideElement(elements.stopBtn);
    hideElement(elements.resultSection);
    showElement(elements.tabsSection);
    if (elements.statusText) {
        elements.statusText.textContent = state.health?.ready === false
            ? state.health.issues.join(' ')
            : 'Ready';
    }
}

async function addHistoryEntry(text, lang, duration) {
    const entry = {
        id: Date.now().toString(),
        text,
        timestamp: Math.floor(Date.now() / 1000),
        lang,
        duration,
    };

    try {
        await invokeCmd('add_history_entry', { entry });
        await loadHistory();
    } catch (error) {
        // Silently fail for history errors
    }
}

async function loadHistory() {
    try {
        const history = await invokeCmd('get_history');
        state.history = history || [];
        renderHistory();
    } catch (error) {
        // Use empty history on error
        state.history = [];
    }
}

function renderHistory() {
    if (!elements.historyList) return;

    if (state.history.length === 0) {
        elements.historyList.innerHTML = '<div class="history-empty">No history yet</div>';
        return;
    }

    elements.historyList.innerHTML = state.history.map(entry => `
        <div class="history-item" data-id="${entry.id}">
            <div class="history-item-text">${escapeHtml(entry.text)}</div>
            <div class="history-item-meta">
                <span>${formatDate(entry.timestamp)}</span>
                <span>${entry.lang || 'unknown'}</span>
            </div>
            <div class="history-item-actions">
                <button class="btn btn-small" onclick="copyHistoryItem('${entry.id}')">Copy</button>
                <button class="btn btn-small btn-secondary" onclick="pasteHistoryItem('${entry.id}')">Paste</button>
                <button class="btn btn-small btn-danger" onclick="deleteHistoryItem('${entry.id}')">Delete</button>
            </div>
        </div>
    `).join('');
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

async function copyHistoryItem(id) {
    const entry = state.history.find(e => e.id === id);
    if (entry) {
        try {
            await invokeCmd('copy_to_clipboard_cmd', { text: entry.text });
        } catch (error) {
            // Silently fail
        }
    }
}

async function pasteHistoryItem(id) {
    const entry = state.history.find(e => e.id === id);
    if (entry) {
        await pasteTranscription(entry.text);
    }
}

async function deleteHistoryItem(id) {
    try {
        await invokeCmd('delete_history_item', { id });
        await loadHistory();
    } catch (error) {
        // Silently fail
    }
}

// Settings Functions
async function loadSettings() {
    try {
        const settings = await invokeCmd('get_settings');
        state.settings = settings;
        updateSettingsUI();
    } catch (error) {
        // Use default settings
        state.settings = {
            hotkey: 'Cmd+Shift+V',
            model: 'sensevoice',
            polish: true,
            autoPaste: true,
            useApplescript: true,
            historyCount: 50,
        };
    }
}

function updateSettingsUI() {
    if (!state.settings) return;

    if (elements.hotkey) elements.hotkey.value = state.settings.hotkey;
    if (elements.model) elements.model.value = state.settings.model;
    if (elements.polish) elements.polish.checked = state.settings.polish;
    if (elements.autoPaste) elements.autoPaste.checked = state.settings.autoPaste;
    if (elements.useApplescript) elements.useApplescript.checked = state.settings.useApplescript;
    if (elements.historyCount) elements.historyCount.value = state.settings.historyCount;
}

async function saveSettings() {
    const newSettings = {
        hotkey: elements.hotkey?.value || 'Cmd+Shift+V',
        model: elements.model?.value || 'sensevoice',
        polish: elements.polish?.checked ?? true,
        autoPaste: elements.autoPaste?.checked ?? true,
        useApplescript: elements.useApplescript?.checked ?? true,
        historyCount: parseInt(elements.historyCount?.value) || 50,
    };

    try {
        await invokeCmd('register_hotkey', { accelerator: newSettings.hotkey });
        await invokeCmd('update_settings', { settings: newSettings });
        state.settings = newSettings;
        if (elements.hotkey) {
            elements.hotkey.value = newSettings.hotkey;
        }
        showSaveNotification();
    } catch (error) {
        console.error('Failed to save settings:', error);
        showSaveError(error);
    }
}

function showSaveNotification() {
    if (elements.statusText) {
        const originalText = elements.statusText.textContent;
        elements.statusText.textContent = 'Settings saved!';
        elements.statusText.style.color = '#4ade80';
        setTimeout(() => {
            elements.statusText.textContent = originalText;
            elements.statusText.style.color = '';
        }, 2000);
    }
}

function showSaveError(error) {
    if (elements.statusText) {
        const originalText = elements.statusText.textContent;
        elements.statusText.textContent = 'Failed to save settings';
        elements.statusText.style.color = '#ff4a4a';
        setTimeout(() => {
            elements.statusText.textContent = originalText;
            elements.statusText.style.color = '';
        }, 2000);
    }
}

// Event Handlers
function setupEventListeners() {
    // Recording buttons
    elements.recordBtn?.addEventListener('click', startRecording);
    elements.stopBtn?.addEventListener('click', stopRecording);

    // Result buttons
    elements.copyResultBtn?.addEventListener('click', async () => {
        const text = elements.resultText?.textContent || '';
        try {
            await invokeCmd('copy_to_clipboard_cmd', { text });
        } catch (error) {
            console.error('Copy failed:', error);
        }
    });

    elements.pasteBtn?.addEventListener('click', async () => {
        const text = elements.resultText?.textContent || '';
        await pasteTranscription(text);
    });

    elements.newRecordingBtn?.addEventListener('click', () => {
        resetRecordingUI();
    });

    // Tabs
    elements.tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const targetTab = tab.dataset.tab;
            elements.tabs.forEach(t => t.classList.remove('active'));
            elements.tabContents.forEach(c => c.classList.remove('active'));
            tab.classList.add('active');
            document.getElementById(`${targetTab}-tab`)?.classList.add('active');
        });
    });

    // Settings
    elements.saveSettingsBtn?.addEventListener('click', saveSettings);

    elements.changeHotkeyBtn?.addEventListener('click', () => {
        const currentValue = elements.hotkey?.value || 'Cmd+Shift+V';
        const nextValue = prompt(
            'Enter a global hotkey, for example Cmd+Shift+V or Command+Shift+V',
            currentValue,
        );

        if (nextValue && elements.hotkey) {
            elements.hotkey.value = nextValue.trim();
        }
    });

    // History
    elements.clearHistoryBtn?.addEventListener('click', async () => {
        if (confirm('Clear all history?')) {
            try {
                await invokeCmd('clear_history');
                await loadHistory();
            } catch (error) {
                console.error('Clear history failed:', error);
            }
        }
    });
}

// Listen for global events
async function setupGlobalListeners() {
    // Hotkey pressed event
    await listenCmd('hotkey-pressed', () => {
        if (state.isRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    });

    // Toggle recording event
    await listenCmd('toggle-recording', () => {
        if (state.isRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    });
}

// Initialize App
async function init() {
    // Show API status in UI
    if (elements.statusText) {
        if (typeof invoke !== 'function') {
            elements.statusText.textContent = 'Tauri API not available';
            elements.statusText.style.color = '#ff4a4a';
        } else {
            elements.statusText.textContent = 'Checking dependencies...';
        }
    }

    await loadRuntimeHealth();

    // Load settings
    await loadSettings();

    // Load history
    await loadHistory();

    // Setup event listeners
    setupEventListeners();

    // Setup global listeners
    await setupGlobalListeners();
}

// Start app when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
