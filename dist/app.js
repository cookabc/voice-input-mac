// Voice Input App - Frontend Logic
'use strict';

const Tauri = window.__TAURI__;
const invoke = Tauri?.core?.invoke || Tauri?.invoke || window.__TAURI_INVOKE__;
const listen = Tauri?.event?.listen || Tauri?.listen || window.__TAURI_EVENT__?.listen;

const state = {
    isRecording: false,
    recordingStart: null,
    timerInterval: null,
    currentAudioPath: null,
    settings: null,
    history: [],
    health: null,
};

const elements = {
    micIcon: document.getElementById('mic-icon'),
    waveform: document.getElementById('waveform'),
    statusText: document.getElementById('status-text'),
    statusDetail: document.getElementById('status-detail'),
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
    hotkeyPill: document.getElementById('hotkey-pill'),
    runtimePill: document.getElementById('runtime-pill'),
    openWorkflowBtn: document.getElementById('open-workflow-btn'),
    openHistoryBtn: document.getElementById('open-history-btn'),
    closeWorkspaceBtn: document.getElementById('close-workspace-btn'),
    workspaceTitle: document.getElementById('workspace-title'),
    workspaceEyebrow: document.getElementById('workspace-eyebrow'),
};

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

async function invokeCmd(cmd, args = {}) {
    if (typeof invoke === 'function') {
        return await invoke(cmd, args);
    }
    throw new Error('Tauri API not available');
}

async function listenCmd(event, handler) {
    if (typeof listen === 'function') {
        return await listen(event, handler);
    }
    return () => {};
}

async function syncTrayState(title, isRecording = state.isRecording) {
    if (typeof invoke !== 'function') {
        return;
    }

    try {
        await invokeCmd('update_tray_state', {
            statusLabel: title,
            isRecording,
        });
    } catch {
        // Ignore tray sync failures so the capture flow stays responsive.
    }
}

function setStatus(title, detail = '', tone = 'default') {
    if (elements.statusText) {
        elements.statusText.textContent = title;
        elements.statusText.dataset.tone = tone;
    }

    if (elements.statusDetail) {
        elements.statusDetail.textContent = detail;
    }

    void syncTrayState(title, state.isRecording);
}

function setRuntimePill(label, stateName = 'neutral') {
    if (!elements.runtimePill) {
        return;
    }

    elements.runtimePill.textContent = label;
    elements.runtimePill.dataset.state = stateName;
}

function syncHotkeyPreview() {
    const value = elements.hotkey?.value || state.settings?.hotkey || 'Cmd+Shift+V';
    if (elements.hotkeyPill) {
        elements.hotkeyPill.textContent = value;
    }
}

function setActiveTab(targetTab) {
    elements.tabs.forEach((tab) => {
        tab.classList.toggle('active', tab.dataset.tab === targetTab);
    });

    elements.tabContents.forEach((content) => {
        content.classList.toggle('active', content.id === `${targetTab}-tab`);
    });

    if (elements.workspaceTitle && elements.workspaceEyebrow) {
        if (targetTab === 'history') {
            elements.workspaceEyebrow.textContent = 'History';
            elements.workspaceTitle.textContent = 'Reuse past transcripts';
        } else {
            elements.workspaceEyebrow.textContent = 'Workflow';
            elements.workspaceTitle.textContent = 'Tune the capture flow';
        }
    }
}

function openWorkspace(targetTab = 'settings') {
    showElement(elements.tabsSection);
    setActiveTab(targetTab);
}

function closeWorkspace() {
    hideElement(elements.tabsSection);
}

function hasTranscript() {
    return Boolean(elements.resultText?.textContent?.trim());
}

function applyIdleStatus() {
    if (state.isRecording) {
        return;
    }

    if (state.health?.ready === false) {
        setStatus('Setup needed', state.health.issues.join(' '), 'danger');
        setRuntimePill('Setup required', 'warning');
        return;
    }

    if (hasTranscript()) {
        setStatus(
            'Transcript ready',
            'Paste it into the current field, or trigger another capture to replace it.',
            'success',
        );
        setRuntimePill('Transcript ready', 'ready');
        return;
    }

    setStatus(
        'Ready to dictate',
        `Press ${state.settings?.hotkey || 'Cmd+Shift+V'} or use the capture button, then speak naturally.`,
        'default',
    );
    setRuntimePill('Recorder ready', 'ready');
}

function updateRecorderControls() {
    elements.recordBtn.disabled = state.health?.ready === false;
    if (state.isRecording) {
        elements.micIcon?.classList.add('recording');
        showElement(elements.waveform);
        showElement(elements.timer);
        hideElement(elements.recordBtn);
        showElement(elements.stopBtn);
        return;
    }

    elements.micIcon?.classList.remove('recording');
    hideElement(elements.waveform);
    hideElement(elements.timer);
    showElement(elements.recordBtn);
    hideElement(elements.stopBtn);
}

async function startRecording() {
    if (state.health && !state.health.ready) {
        applyIdleStatus();
        return;
    }

    try {
        const audioPath = await invokeCmd('start_recording');

        if (audioPath) {
            state.isRecording = true;
            state.currentAudioPath = audioPath;
            state.recordingStart = Date.now();
            updateRecorderControls();
            setStatus('Listening now', 'Speak naturally. Trigger the hotkey again when you are done.', 'live');
            setRuntimePill('Live capture', 'live');
            state.timerInterval = setInterval(updateTimer, 1000);
        }
    } catch (error) {
        console.error('Failed to start recording:', error);
        setStatus('Could not start capture', String(error), 'danger');
    }
}

async function stopRecording() {
    try {
        await invokeCmd('stop_recording');

        state.isRecording = false;

        if (state.timerInterval) {
            clearInterval(state.timerInterval);
            state.timerInterval = null;
        }

        updateRecorderControls();
        setStatus('Transcribing locally', 'Running speech recognition with coli and preparing the transcript.', 'default');
        setRuntimePill('Transcribing', 'neutral');

        if (state.currentAudioPath) {
            await transcribeAudio(state.currentAudioPath);
        }
    } catch (error) {
        console.error('Failed to stop recording:', error);
        setStatus('Could not stop capture', String(error), 'danger');
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
            if (elements.resultText) elements.resultText.textContent = result.text;
            showElement(elements.resultSection);
            setStatus('Transcript ready', 'Paste it into the current app or start another capture.', 'success');
            await addHistoryEntry(result.text, result.lang, result.duration);

            if (state.settings?.autoPaste) {
                await pasteTranscription(result.text);
            }
        } else {
            throw new Error('No text in transcription result');
        }
    } catch (error) {
        console.error('Transcription failed:', error);
        setStatus('Transcription failed', String(error), 'danger');
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
        setStatus('Inserted into current app', 'The latest transcript was pasted into the active field.', 'success');
    } catch (error) {
        setStatus('Copied to clipboard', 'Auto-paste failed. Use the Paste button to try again manually.', 'danger');
    }
}

async function loadRuntimeHealth() {
    try {
        state.health = await invokeCmd('get_runtime_health');
        updateRecorderControls();
        applyIdleStatus();
    } catch (error) {
        state.health = null;
        setStatus('Health check unavailable', 'Could not inspect runtime dependencies in this session.', 'danger');
        setRuntimePill('Runtime unknown', 'warning');
    }
}

function updateTimer() {
    if (state.recordingStart) {
        const seconds = Math.floor((Date.now() - state.recordingStart) / 1000);
        if (elements.timer) elements.timer.textContent = formatTime(seconds);
    }
}

function resetRecordingUI() {
    state.isRecording = false;
    updateRecorderControls();
    applyIdleStatus();
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
                <span>${escapeHtml(entry.lang || 'unknown')}</span>
            </div>
            <div class="history-item-actions">
                <button class="btn btn-small" data-action="copy" data-id="${entry.id}">Copy</button>
                <button class="btn btn-small btn-secondary" data-action="paste" data-id="${entry.id}">Paste</button>
                <button class="btn btn-small btn-danger" data-action="delete" data-id="${entry.id}">Delete</button>
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
        updateSettingsUI();
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
    syncHotkeyPreview();
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
        syncHotkeyPreview();
        showSaveNotification();
    } catch (error) {
        console.error('Failed to save settings:', error);
        showSaveError(error);
    }
}

function showSaveNotification() {
    setStatus('Settings saved', 'Your trigger and insertion workflow have been updated.', 'success');
    window.setTimeout(applyIdleStatus, 2200);
}

function showSaveError() {
    setStatus('Could not save settings', 'The hotkey or workflow configuration was rejected.', 'danger');
    window.setTimeout(applyIdleStatus, 2200);
}

function setupEventListeners() {
    elements.recordBtn?.addEventListener('click', startRecording);
    elements.stopBtn?.addEventListener('click', stopRecording);

    elements.copyResultBtn?.addEventListener('click', async () => {
        const text = elements.resultText?.textContent || '';
        try {
            await invokeCmd('copy_to_clipboard_cmd', { text });
            setStatus('Copied transcript', 'The latest transcript is now in your clipboard.', 'success');
        } catch (error) {
            console.error('Copy failed:', error);
            setStatus('Copy failed', String(error), 'danger');
        }
    });

    elements.pasteBtn?.addEventListener('click', async () => {
        const text = elements.resultText?.textContent || '';
        await pasteTranscription(text);
    });

    elements.newRecordingBtn?.addEventListener('click', () => {
        if (elements.resultText) {
            elements.resultText.textContent = '';
        }
        hideElement(elements.resultSection);
        applyIdleStatus();
    });

    elements.tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            setActiveTab(tab.dataset.tab || 'settings');
        });
    });

    elements.openWorkflowBtn?.addEventListener('click', () => openWorkspace('settings'));
    elements.openHistoryBtn?.addEventListener('click', () => openWorkspace('history'));
    elements.closeWorkspaceBtn?.addEventListener('click', closeWorkspace);

    elements.saveSettingsBtn?.addEventListener('click', saveSettings);

    elements.changeHotkeyBtn?.addEventListener('click', () => {
        const currentValue = elements.hotkey?.value || 'Cmd+Shift+V';
        const nextValue = prompt(
            'Enter a global hotkey, for example Cmd+Shift+V or Command+Shift+V',
            currentValue,
        );

        if (nextValue && elements.hotkey) {
            elements.hotkey.value = nextValue.trim();
            syncHotkeyPreview();
        }
    });

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

    elements.historyList?.addEventListener('click', async (event) => {
        const button = event.target.closest('[data-action]');
        if (!button) return;

        const { action, id } = button.dataset;
        if (!id) return;

        if (action === 'copy') {
            await copyHistoryItem(id);
        } else if (action === 'paste') {
            await pasteHistoryItem(id);
        } else if (action === 'delete') {
            await deleteHistoryItem(id);
        }
    });
}

async function setupGlobalListeners() {
    await listenCmd('hotkey-pressed', () => {
        if (state.isRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    });

    await listenCmd('toggle-recording', () => {
        if (state.isRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    });

    await listenCmd('open-preferences', () => {
        openWorkspace('settings');
    });

    await listenCmd('open-history', () => {
        openWorkspace('history');
    });
}

async function init() {
    if (elements.statusText) {
        if (typeof invoke !== 'function') {
            setStatus('Tauri unavailable', 'The frontend was opened without the desktop runtime APIs.', 'danger');
        } else {
            setStatus('Checking runtime', 'Inspecting recorder, speech recognition, and paste services.', 'default');
        }
    }

    await loadSettings();
    await loadRuntimeHealth();
    await loadHistory();
    setupEventListeners();
    await setupGlobalListeners();
    updateRecorderControls();
    applyIdleStatus();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
