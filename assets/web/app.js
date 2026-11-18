// CloudPocket v1.5 Web Client
let currentSubpath = '';
let isGridView = true;
let allowUploads = false;
let currentItems = [];
let currentFolderName = '';
let isSingleFolderShare = false;
let ws = null;

// Viewport Virtualization: Only load thumbnails when scrolled near viewport
const thumbnailObserver = (typeof IntersectionObserver !== 'undefined')
  ? new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const img = entry.target;
          const dataSrc = img.getAttribute('data-src');
          if (dataSrc) {
            img.src = dataSrc;
            img.removeAttribute('data-src');
          }
          observer.unobserve(img);
        }
      });
    }, { rootMargin: '200px 0px' })
  : null;

// Video Thumbnail Generation Queue & Viewport Observer
const videoThumbCache = new Map();
const videoQueue = [];
let activeVideoDecoders = 0;
const MAX_CONCURRENT_VIDEO_DECODES = 2;

const videoObserver = (typeof IntersectionObserver !== 'undefined')
  ? new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const area = entry.target;
          const path = area.getAttribute('data-video-path');
          if (path) {
            const item = currentItems.find((i) => i.path === path) || itemsToRenderGlobal.find((i) => i.path === path);
            if (item) {
              queueVideoThumbnail(item, area);
            }
            area.removeAttribute('data-video-path');
          }
          observer.unobserve(area);
        }
      });
    }, { rootMargin: '250px 0px' })
  : null;

function queueVideoThumbnail(item, previewArea) {
  if (videoThumbCache.has(item.path)) {
    applyVideoThumbnail(previewArea, videoThumbCache.get(item.path), item.name);
    return;
  }
  videoQueue.push({ item, previewArea });
  processVideoQueue();
}

function processVideoQueue() {
  if (activeVideoDecoders >= MAX_CONCURRENT_VIDEO_DECODES || videoQueue.length === 0) {
    return;
  }
  const task = videoQueue.shift();
  if (videoThumbCache.has(task.item.path)) {
    applyVideoThumbnail(task.previewArea, videoThumbCache.get(task.item.path), task.item.name);
    processVideoQueue();
    return;
  }

  // If card was removed from DOM before being processed
  if (!task.previewArea.isConnected) {
    processVideoQueue();
    return;
  }

  activeVideoDecoders++;
  extractVideoFrame(task.item)
    .then((dataUrl) => {
      videoThumbCache.set(task.item.path, dataUrl);
      applyVideoThumbnail(task.previewArea, dataUrl, task.item.name);
    })
    .catch(() => {
      // Graceful fallback: placeholder icon stays intact
    })
    .finally(() => {
      activeVideoDecoders--;
      processVideoQueue();
    });
}

function applyVideoThumbnail(previewArea, dataUrl, name) {
  if (!previewArea || !previewArea.isConnected) return;
  const existingSvg = previewArea.querySelector('.video-placeholder-icon');
  if (existingSvg) existingSvg.remove();

  let thumb = previewArea.querySelector('img.preview-thumb');
  if (!thumb) {
    thumb = document.createElement('img');
    thumb.className = 'preview-thumb';
    thumb.alt = name;
    previewArea.insertBefore(thumb, previewArea.firstChild);
  }
  thumb.src = dataUrl;

  if (!previewArea.querySelector('.video-play-overlay')) {
    const playOverlay = document.createElement('div');
    playOverlay.className = 'video-play-overlay';
    playOverlay.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`;
    previewArea.appendChild(playOverlay);
  }
}

function extractVideoFrame(item) {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    video.preload = 'metadata';
    video.muted = true;
    video.playsInline = true;
    video.crossOrigin = 'anonymous';

    let isDone = false;
    let seekFallbackTimer = null;
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error('Video thumbnail timeout'));
    }, 8000);

    function cleanup() {
      if (isDone) return;
      isDone = true;
      clearTimeout(timer);
      if (seekFallbackTimer) clearTimeout(seekFallbackTimer);
      video.removeEventListener('loadedmetadata', onMetadata);
      video.removeEventListener('seeked', onSeeked);
      video.removeEventListener('error', onError);
      video.pause();
      video.removeAttribute('src');
      video.load();
    }

    function doCapture() {
      if (isDone) return;
      try {
        const vw = video.videoWidth;
        const vh = video.videoHeight;
        if (!vw || !vh) {
          cleanup();
          reject(new Error('No video dimensions'));
          return;
        }

        const canvas = document.createElement('canvas');
        const maxDim = 320;
        let w = vw;
        let h = vh;
        if (w > maxDim || h > maxDim) {
          if (w >= h) {
            h = Math.round((h * maxDim) / w);
            w = maxDim;
          } else {
            w = Math.round((w * maxDim) / h);
            h = maxDim;
          }
        }
        canvas.width = Math.max(w, 1);
        canvas.height = Math.max(h, 1);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.75);
        cleanup();
        resolve(dataUrl);
      } catch (err) {
        cleanup();
        reject(err);
      }
    }

    function onSeeked() {
      requestAnimationFrame(() => {
        doCapture();
      });
    }

    function onMetadata() {
      const dur = video.duration || 0;
      let targetTime = 1.0;
      if (dur > 0 && dur < 1.0) {
        targetTime = dur * 0.25;
      } else if (dur <= 0) {
        targetTime = 0.1;
      }

      seekFallbackTimer = setTimeout(() => {
        if (video.readyState >= 2) {
          doCapture();
        }
      }, 2500);

      try {
        video.currentTime = targetTime;
      } catch (_) {
        doCapture();
      }
    }

    function onError(e) {
      cleanup();
      reject(e);
    }

    video.addEventListener('loadedmetadata', onMetadata);
    video.addEventListener('seeked', onSeeked);
    video.addEventListener('error', onError);
    video.src = `/api/files/${encodeURIComponent(item.path)}`;
  });
}

// DOM Elements
const authSection = document.getElementById('authSection');
const authHeading = document.getElementById('authHeading');
const authIcon = document.getElementById('authIcon');
const mainContent = document.getElementById('mainContent');
const accessForm = document.getElementById('accessForm');
const visitorNameInput = document.getElementById('visitorNameInput');
const passwordFieldGroup = document.getElementById('passwordFieldGroup');
const passwordInput = document.getElementById('passwordInput');
const togglePasswordBtn = document.getElementById('togglePasswordBtn');
const accessSubmitBtn = document.getElementById('accessSubmitBtn');
const authError = document.getElementById('authError');
const visitorBadge = document.getElementById('visitorBadge');
const visitorBadgeName = document.getElementById('visitorBadgeName');
const googleAuthContainer = document.getElementById('googleAuthContainer');
const googleAuthError = document.getElementById('googleAuthError');
const fileContainer = document.getElementById('fileContainer');
const breadcrumbs = document.getElementById('breadcrumbs');
const fileInput = document.getElementById('fileInput');
const folderInput = document.getElementById('folderInput');
const viewGridBtn = document.getElementById('viewGridBtn');
const viewListBtn = document.getElementById('viewListBtn');
const uploadBtn = document.getElementById('uploadBtn');
const uploadFolderBtn = document.getElementById('uploadFolderBtn');
const downloadAllBtn = document.getElementById('downloadAllBtn');
const logoutBtn = document.getElementById('logoutBtn');
const previewModal = document.getElementById('previewModal');
const modalFilename = document.getElementById('modalFilename');
const modalDownloadBtn = document.getElementById('modalDownloadBtn');
const modalCloseBtn = document.getElementById('modalCloseBtn');
const modalBody = document.getElementById('modalBody');
const deviceSubtitle = document.getElementById('deviceSubtitle');
const liveTransferBanner = document.getElementById('liveTransferBanner');
const transferTitle = document.getElementById('transferTitle');
const transferProgressText = document.getElementById('transferProgressText');
const transferProgressBar = document.getElementById('transferProgressBar');
const sharedNoteCard = document.getElementById('sharedNoteCard');
const sharedNoteBody = document.getElementById('sharedNoteBody');
const copyNoteBtn = document.getElementById('copyNoteBtn');
const copyNoteText = document.getElementById('copyNoteText');
const selectToggleBtn = document.getElementById('selectToggleBtn');
const selectToggleText = document.getElementById('selectToggleText');
const selectionBar = document.getElementById('selectionBar');
const selectAllBtn = document.getElementById('selectAllBtn');
const clearSelectionBtn = document.getElementById('clearSelectionBtn');
const selectionCounter = document.getElementById('selectionCounter');
const downloadSelectedBtn = document.getElementById('downloadSelectedBtn');
const downloadSelectedText = document.getElementById('downloadSelectedText');
const modalMeta = document.getElementById('modalMeta');
const modalDownloadLabel = document.getElementById('modalDownloadLabel');
const dragDropOverlay = document.getElementById('dragDropOverlay');
const zipDownloadForm = document.getElementById('zipDownloadForm');
const zipDownloadPaths = document.getElementById('zipDownloadPaths');

const selectedItems = new Map();
let isSelectMode = false;
let itemsToRenderGlobal = [];
let isUploadingLocal = false;

// Helper to trigger ZIP download via POST to prevent HTTP 414 URL length errors
function downloadZipWithPaths(paths, defaultFilename) {
  requestWebWakeLock();
  let form = document.getElementById('zipDownloadForm');
  if (!form) {
    form = document.createElement('form');
    form.id = 'zipDownloadForm';
    form.method = 'POST';
    form.action = '/api/download-zip';
    form.style.display = 'none';
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = 'paths';
    input.id = 'zipDownloadPaths';
    form.appendChild(input);
    document.body.appendChild(form);
  }
  const input = document.getElementById('zipDownloadPaths') || form.querySelector('input[name="paths"]');
  const pathsValue = Array.isArray(paths) ? paths.join(',') : (paths || '');
  if (input) input.value = pathsValue;
  form.submit();
}

// Helper to download multiple files individually with sequential delay to prevent browser drop
async function downloadItemsSeparately(items) {
  if (!items || items.length === 0) return;

  await withTransferLock(async () => {
    if (liveTransferBanner) {
      liveTransferBanner.style.display = 'block';
      transferTitle.textContent = `Preparing download of ${items.length} item(s)...`;
      transferProgressText.textContent = `0 / ${items.length}`;
      transferProgressBar.style.width = '0%';
    }

    for (let i = 0; i < items.length; i++) {
      await waitForVisibilityOrOnline();
      const item = items[i];
      const pct = Math.round(((i + 1) / items.length) * 100);
      if (liveTransferBanner) {
        transferTitle.textContent = `Downloading (${i + 1}/${items.length}): ${item.name}`;
        transferProgressText.textContent = `${pct}%`;
        transferProgressBar.style.width = `${pct}%`;
      }

      if (item.isDirectory) {
        downloadZipWithPaths([item.path], `${item.name}.zip`);
      } else {
        triggerDownload(`/api/files/${encodeURIComponent(item.path)}`, item.name);
      }

      if (i < items.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }

    if (liveTransferBanner) {
      transferTitle.textContent = `All ${items.length} download(s) initiated!`;
      transferProgressText.textContent = '100%';
      transferProgressBar.style.width = '100%';
      setTimeout(() => {
        liveTransferBanner.style.display = 'none';
        transferProgressBar.style.width = '0%';
      }, 2800);
    }
  });
}

// Choice Modal Management
let currentDownloadChoiceCallbacks = null;

function openDownloadChoiceModal({ title, subtitle, onZip, onSeparate }) {
  const modal = document.getElementById('downloadChoiceModal');
  const titleEl = document.getElementById('downloadChoiceTitle');
  const metaEl = document.getElementById('downloadChoiceMeta');
  if (!modal) {
    if (onZip) onZip();
    return;
  }
  if (titleEl && title) titleEl.textContent = title;
  if (metaEl && subtitle) metaEl.textContent = subtitle;

  currentDownloadChoiceCallbacks = { onZip, onSeparate };
  modal.style.display = 'flex';
}

function closeDownloadChoiceModal() {
  const modal = document.getElementById('downloadChoiceModal');
  if (modal) modal.style.display = 'none';
  currentDownloadChoiceCallbacks = null;
}

const chooseZipBtn = document.getElementById('chooseZipBtn');
if (chooseZipBtn) {
  chooseZipBtn.addEventListener('click', () => {
    const cb = currentDownloadChoiceCallbacks?.onZip;
    closeDownloadChoiceModal();
    if (cb) cb();
  });
}

const chooseSeparateBtn = document.getElementById('chooseSeparateBtn');
if (chooseSeparateBtn) {
  chooseSeparateBtn.addEventListener('click', () => {
    const cb = currentDownloadChoiceCallbacks?.onSeparate;
    closeDownloadChoiceModal();
    if (cb) cb();
  });
}

const downloadChoiceCloseBtn = document.getElementById('downloadChoiceCloseBtn');
if (downloadChoiceCloseBtn) {
  downloadChoiceCloseBtn.addEventListener('click', closeDownloadChoiceModal);
}

const downloadChoiceModal = document.getElementById('downloadChoiceModal');
if (downloadChoiceModal) {
  downloadChoiceModal.addEventListener('click', (e) => {
    if (e.target === downloadChoiceModal) closeDownloadChoiceModal();
  });
}

if (uploadBtn) {
  uploadBtn.addEventListener('click', () => {
    if (fileInput) fileInput.click();
  });
}

if (uploadFolderBtn) {
  uploadFolderBtn.addEventListener('click', () => {
    if (folderInput) folderInput.click();
  });
}

if (selectToggleBtn) {
  selectToggleBtn.addEventListener('click', () => {
    isSelectMode = !isSelectMode;
    if (!isSelectMode) {
      selectedItems.clear();
    }
    renderFileList();
    updateSelectionUI();
  });
}

if (selectAllBtn) {
  selectAllBtn.addEventListener('click', () => {
    const isAllSelected = itemsToRenderGlobal.length > 0 && selectedItems.size >= itemsToRenderGlobal.length;
    if (isAllSelected) {
      selectedItems.clear();
    } else {
      itemsToRenderGlobal.forEach((item) => {
        selectedItems.set(item.path, item);
      });
      isSelectMode = true;
    }
    renderFileList();
    updateSelectionUI();
  });
}

if (clearSelectionBtn) {
  clearSelectionBtn.addEventListener('click', () => {
    selectedItems.clear();
    isSelectMode = false;
    renderFileList();
    updateSelectionUI();
  });
}

if (downloadSelectedBtn) {
  downloadSelectedBtn.addEventListener('click', () => {
    if (selectedItems.size === 0) return;

    if (selectedItems.size === 1) {
      const item = selectedItems.values().next().value;
      if (item.isDirectory) {
        downloadZipWithPaths([item.path], `${item.name}.zip`);
      } else {
        triggerDownload(`/api/files/${encodeURIComponent(item.path)}`, item.name);
      }
      return;
    }

    const items = Array.from(selectedItems.values());
    let totalSize = 0;
    items.forEach((i) => { totalSize += (i.size || 0); });

    openDownloadChoiceModal({
      title: `Download ${items.length} Items`,
      subtitle: `${items.length} items selected${totalSize > 0 ? ` (${formatSize(totalSize)})` : ''}`,
      onZip: () => {
        const paths = items.map((i) => i.path);
        downloadZipWithPaths(paths, `cloudpocket_selection_${Date.now()}.zip`);
        if (liveTransferBanner) {
          liveTransferBanner.style.display = 'block';
          transferTitle.textContent = `Preparing ZIP archive of ${items.length} item(s)...`;
          transferProgressText.textContent = '100%';
          transferProgressBar.style.width = '100%';
          setTimeout(() => {
            liveTransferBanner.style.display = 'none';
            transferProgressBar.style.width = '0%';
          }, 2500);
        }
      },
      onSeparate: () => {
        downloadItemsSeparately(items);
      },
    });
  });
}

if (copyNoteBtn) {
  copyNoteBtn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(sharedNoteBody.textContent);
      copyNoteText.textContent = 'Copied!';
      setTimeout(() => { copyNoteText.textContent = 'Copy'; }, 2000);
    } catch (_) {}
  });
}

// Synchronize Web UI Theme with Mobile Server Settings
function applyTheme(themeMode, primaryColor) {
  window.CloudPocketTheme.apply(themeMode);
}

// Visitor & Session Identity
let visitorId = localStorage.getItem('cp_vid');
if (!visitorId) {
  visitorId = 'v_' + Math.random().toString(36).substring(2, 10);
  localStorage.setItem('cp_vid', visitorId);
}
let currentUserName = localStorage.getItem('cp_visitor_name') || '';
let securityConfigGlobal = null;

// Password visibility toggle (recheck typed password)
if (togglePasswordBtn && passwordInput) {
  togglePasswordBtn.addEventListener('click', () => {
    const isPass = passwordInput.type === 'password';
    passwordInput.type = isPass ? 'text' : 'password';
    togglePasswordBtn.setAttribute('aria-label', isPass ? 'Hide password' : 'Show password');
    togglePasswordBtn.innerHTML = isPass
      ? `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="23" x2="23" y2="1"/></svg>`
      : `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>`;
  });
}

function updateUserBadge(name) {
  if (name && name.trim()) {
    currentUserName = name.trim();
    localStorage.setItem('cp_visitor_name', currentUserName);
    if (visitorBadgeName) visitorBadgeName.textContent = currentUserName;
    if (visitorBadge) visitorBadge.style.display = 'inline-flex';
    if (logoutBtn) logoutBtn.style.display = 'inline-flex';
  } else {
    currentUserName = '';
    localStorage.removeItem('cp_visitor_name');
    if (visitorBadge) visitorBadge.style.display = 'none';
    if (logoutBtn) logoutBtn.style.display = 'none';
  }
}

async function registerVisitor(name) {
  if (!name || !name.trim()) return;
  try {
    await fetch('/api/register-visitor', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name.trim(), visitorId: visitorId }),
    });
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'register_name',
        name: name.trim(),
        visitorId: visitorId,
      }));
    }
  } catch (_) {}
}

if (logoutBtn) {
  logoutBtn.addEventListener('click', async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
    } catch (_) {}
    updateUserBadge('');
    window.location.reload();
  });
}

// Check Security Mode & Auth Status on Load
async function init() {
  // 0. Extract and exchange URL fragment token (#t=... or #token=...)
  let fragmentToken = '';
  if (window.location.hash && window.location.hash.length > 1) {
    const hash = window.location.hash.substring(1);
    const params = new URLSearchParams(hash);
    fragmentToken = params.get('t') || params.get('token') || '';
  }

  // Fetch device info
  try {
    const devRes = await fetch('/api/device-info');
    if (devRes.ok) {
      const devData = await devRes.json();
      if (devData.deviceName) {
        const subText = document.getElementById('deviceSubtitleText');
        if (subText) subText.textContent = `Shared by ${devData.deviceName}`;
        else deviceSubtitle.textContent = `Shared by ${devData.deviceName}`;
      }
      if (devData.themeMode || devData.primaryColor) {
        applyTheme(devData.themeMode, devData.primaryColor);
      }
    }
  } catch (_) {}

  // If URL fragment token is present, exchange it for session cookie
  let tokenExchangeFailed = false;
  if (fragmentToken) {
    try {
      const exchangeRes = await fetch('/api/auth/exchange', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          token: fragmentToken,
          name: currentUserName || 'Guest',
          visitorId: visitorId,
        }),
      });

      // Clear the fragment immediately to prevent leakage
      try {
        window.history.replaceState(null, document.title, window.location.pathname + window.location.search);
      } catch (_) {}

      if (exchangeRes.ok) {
        const exchangeData = await exchangeRes.json();
        if (exchangeData.fullyAuthenticated) {
          if (!currentUserName) updateUserBadge('Guest');
          registerVisitor(currentUserName || 'Guest');
          showMain();
          loadFiles('');
          requestWebWakeLock();
          initWebSocket();
          return;
        }
      } else {
        tokenExchangeFailed = true;
      }
    } catch (_) {
      tokenExchangeFailed = true;
      try {
        window.history.replaceState(null, document.title, window.location.pathname + window.location.search);
      } catch (_) {}
    }
  }

  // Check auth & security mode
  try {
    const res = await fetch('/api/security-mode');
    if (!res.ok) throw new Error('Failed to fetch security status');
    const data = await res.json();
    securityConfigGlobal = data;

    if (data.sharedText && data.sharedText.trim().length > 0) {
      sharedNoteBody.textContent = data.sharedText;
      sharedNoteCard.style.display = 'block';
    } else {
      sharedNoteCard.style.display = 'none';
    }

    if (tokenExchangeFailed) {
      showAccessGate(data, true);
      const authMsg = document.getElementById('authMessage');
      if (authMsg) authMsg.textContent = 'This link has expired or is invalid. Enter the PIN to continue:';
      if (authError) {
        authError.textContent = 'This link has expired or is invalid. Enter the PIN to continue:';
        authError.style.display = 'block';
      }
    } else if (!data.requireGoogleAuth && !data.requirePassword) {
      if (currentUserName) {
        updateUserBadge(currentUserName);
        registerVisitor(currentUserName);
        showMain();
        loadFiles('');
      } else {
        showAccessGate(data, false);
      }
    } else {
      const authCheck = await fetch('/api/files');
      if (authCheck.ok && currentUserName) {
        updateUserBadge(currentUserName);
        registerVisitor(currentUserName);
        showMain();
        loadFiles('');
      } else {
        showAccessGate(data, true);
      }
    }
  } catch (err) {
    console.error('Init error:', err);
    loadFiles('');
  }

  requestWebWakeLock();
  initWebSocket();
}

// Screen Wake Lock & Web Lock Helpers to prevent mobile browsers from suspending transfers
let webWakeLockSentinel = null;
let wsPingTimer = null;

async function requestWebWakeLock() {
  if (typeof navigator !== 'undefined' && 'wakeLock' in navigator && document.visibilityState === 'visible') {
    try {
      if (!webWakeLockSentinel || webWakeLockSentinel.released) {
        webWakeLockSentinel = await navigator.wakeLock.request('screen');
        webWakeLockSentinel.addEventListener('release', () => {
          webWakeLockSentinel = null;
        });
      }
    } catch (_) {}
  }
}

async function withTransferLock(taskFn) {
  await requestWebWakeLock();
  if (typeof navigator !== 'undefined' && navigator.locks && navigator.locks.request) {
    let executedInLock = false;
    try {
      return await navigator.locks.request('cloudpocket_active_transfer', { mode: 'shared' }, async () => {
        executedInLock = true;
        return await taskFn();
      });
    } catch (e) {
      if (executedInLock) throw e;
    }
  }
  return await taskFn();
}

function waitForVisibilityOrOnline(timeoutMs = 4000) {
  if (!document.hidden) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    let settled = false;
    const done = () => {
      if (settled) return;
      settled = true;
      document.removeEventListener('visibilitychange', onVis);
      resolve();
    };
    const onVis = () => {
      if (!document.hidden) done();
    };
    document.addEventListener('visibilitychange', onVis);
    setTimeout(done, timeoutMs);
  });
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    requestWebWakeLock();
    if (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING) {
      initWebSocket();
    }
  }
});

window.addEventListener('online', () => {
  requestWebWakeLock();
  if (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING) {
    initWebSocket();
  }
});

['click', 'touchstart', 'drop'].forEach((evt) => {
  window.addEventListener(evt, () => {
    if (!webWakeLockSentinel) requestWebWakeLock();
  }, { passive: true });
});

// WebSocket for Live Transfer Monitoring
function initWebSocket() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}/ws/transfers`;

  try {
    ws = new WebSocket(wsUrl);
    ws.onopen = () => {
      document.getElementById('connectionStatus').textContent = 'Connected';
      if (currentUserName) {
        ws.send(JSON.stringify({
          type: 'register_name',
          name: currentUserName,
          visitorId: visitorId,
        }));
      }
      clearInterval(wsPingTimer);
      wsPingTimer = setInterval(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            ws.send(JSON.stringify({ type: 'ping' }));
          } catch (_) {}
        }
      }, 15000);
    };
    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'transfer_progress') {
          handleTransferProgress(msg);
        } else if (msg.type === 'transfer_cancelled' && activeUpload && activeUpload.name === (msg.filename || msg.id)) {
          activeUpload.cancelled = true;
          activeUpload.xhr.abort();
        } else if (msg.type === 'theme_changed') {
          applyTheme(msg.themeMode, msg.primaryColor);
        }
      } catch (_) {}
    };
    ws.onclose = () => {
      document.getElementById('connectionStatus').textContent = 'Reconnecting';
      clearInterval(wsPingTimer);
      setTimeout(initWebSocket, 3000);
    };
  } catch (_) {}
}

let activeUpload = null;
let bannerHideTimer = null;
let reloadFilesDebounceTimer = null;

function debouncedReloadFiles() {
  clearTimeout(reloadFilesDebounceTimer);
  reloadFilesDebounceTimer = setTimeout(() => {
    loadFiles(currentSubpath);
  }, 400);
}

function handleTransferProgress(data) {
  // If local client is actively uploading via XHR, let XHR drive the progress bar to avoid DOM thrashing
  if (isUploadingLocal && data.direction === 'upload') {
    return;
  }
  liveTransferBanner.style.display = 'block';
  const isUpload = data.direction === 'upload';
  transferTitle.textContent = `${isUpload ? '⬆ Uploading' : '⬇ Downloading'} ${data.filename}`;

  const percent = (data.total && data.total > 0)
    ? Math.min(100, Math.round((data.transferred / data.total) * 100))
    : 0;
  transferProgressText.textContent = `${percent}%`;
  transferProgressBar.style.width = `${percent}%`;

  clearTimeout(bannerHideTimer);
  if (percent >= 100 && (data.total && data.total > 0)) {
    if (isUpload) {
      debouncedReloadFiles();
    }
    bannerHideTimer = setTimeout(() => {
      liveTransferBanner.style.display = 'none';
      transferProgressBar.style.width = '0%';
    }, 2500);
  }
}

function showAccessGate(securityConfig, isProtected) {
  authSection.style.display = 'block';
  mainContent.style.display = 'none';

  const authMsg = document.getElementById('authMessage');
  const hasGoogle = securityConfig?.requireGoogleAuth;
  const hasPassword = securityConfig?.requirePassword;

  if (visitorNameInput && currentUserName) {
    visitorNameInput.value = currentUserName;
  }

  if (hasPassword) {
    if (authIcon) authIcon.textContent = '🔒';
    if (authHeading) authHeading.textContent = 'Protected Session';
    if (authMsg) authMsg.textContent = 'Enter your name and password to access the shared files.';
    if (passwordFieldGroup) passwordFieldGroup.style.display = 'block';
    if (passwordInput) passwordInput.required = true;
    if (accessSubmitBtn) accessSubmitBtn.textContent = 'Unlock & Access Files';
    if (!currentUserName && visitorNameInput) {
      visitorNameInput.focus();
    } else if (passwordInput) {
      passwordInput.focus();
    }
  } else {
    if (authIcon) authIcon.textContent = '👋';
    if (authHeading) authHeading.textContent = 'Welcome to CloudPocket';
    if (authMsg) authMsg.textContent = 'Please enter your name to access the shared files.';
    if (passwordFieldGroup) passwordFieldGroup.style.display = 'none';
    if (passwordInput) passwordInput.required = false;
    if (accessSubmitBtn) accessSubmitBtn.textContent = 'Access Files';
    if (visitorNameInput) visitorNameInput.focus();
  }

  if (hasGoogle && googleAuthContainer) {
    googleAuthContainer.style.display = 'block';
    initGoogleAuth(securityConfig.googleClientId);
  } else if (googleAuthContainer) {
    googleAuthContainer.style.display = 'none';
  }
}

async function initGoogleAuth(clientId) {
  const btnContainer = document.getElementById('googleSignInButton');
  if (!clientId) {
    btnContainer.innerHTML = '<p class="error-msg">Google Client ID is not configured by sender.</p>';
    return;
  }
  if (!window.google) {
    try {
      await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://accounts.google.com/gsi/client';
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    } catch (_) {
      btnContainer.textContent = 'Google sign-in could not load. Check your connection and retry.';
      return;
    }
  }
  if (window.google) {
    btnContainer.innerHTML = '';
    google.accounts.id.initialize({
      client_id: clientId,
      callback: handleGoogleCredentialResponse,
    });
    google.accounts.id.renderButton(
      btnContainer,
      { theme: 'filled_blue', size: 'large', text: 'continue_with', shape: 'pill' }
    );
  }
}

async function handleGoogleCredentialResponse(response) {
  try {
    googleAuthError.style.display = 'none';
    const res = await fetch('/api/auth/google', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id_token: response.credential }),
    });

    if (res.ok) {
      const data = await res.json();
      if (data.fullyAuthenticated) {
        showMain();
        loadFiles('');
      } else if (data.needsPassword) {
        document.getElementById('authMessage').textContent = `Google verified (${data.email}). Enter session password.`;
        googleAuthContainer.style.display = 'none';
        if (passwordFieldGroup) passwordFieldGroup.style.display = 'block';
        if (passwordInput) passwordInput.focus();
      }
    } else {
      const data = await res.json();
      googleAuthError.textContent = data.message || 'Google authentication failed';
      googleAuthError.style.display = 'block';
    }
  } catch (_) {
    googleAuthError.textContent = 'Verification request failed';
    googleAuthError.style.display = 'block';
  }
}

if (accessForm) {
  accessForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (authError) authError.style.display = 'none';
    const name = visitorNameInput ? visitorNameInput.value.trim() : '';
    if (!name) {
      if (authError) {
        authError.textContent = 'Please enter your name.';
        authError.style.display = 'block';
      }
      return;
    }

    const hasPassword = securityConfigGlobal?.requirePassword;
    if (hasPassword) {
      const pass = passwordInput ? passwordInput.value : '';
      try {
        const res = await fetch('/api/auth/password', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ password: pass, name: name, visitorId: visitorId }),
        });

        if (res.ok) {
          const data = await res.json();
          if (data.fullyAuthenticated) {
            updateUserBadge(name);
            registerVisitor(name);
            showMain();
            loadFiles('');
          }
        } else {
          const data = await res.json();
          if (authError) {
            authError.textContent = data.message || 'Incorrect password';
            authError.style.display = 'block';
          }
        }
      } catch (_) {
        if (authError) {
          authError.textContent = 'Connection error';
          authError.style.display = 'block';
        }
      }
    } else {
      updateUserBadge(name);
      registerVisitor(name);
      showMain();
      loadFiles('');
    }
  });
}

function showMain() {
  authSection.style.display = 'none';
  mainContent.style.display = 'block';
  logoutBtn.style.display = 'inline-block';
}

// View Toggle Handlers - Smooth CSS class swap without DOM destruction
viewGridBtn.addEventListener('click', () => {
  isGridView = true;
  viewGridBtn.classList.add('active');
  viewGridBtn.setAttribute('aria-pressed', 'true');
  viewListBtn.setAttribute('aria-pressed', 'false');
  viewListBtn.classList.remove('active');
  fileContainer.classList.remove('file-list');
  fileContainer.classList.add('file-grid');
});

viewListBtn.addEventListener('click', () => {
  isGridView = false;
  viewListBtn.classList.add('active');
  viewListBtn.setAttribute('aria-pressed', 'true');
  viewGridBtn.setAttribute('aria-pressed', 'false');
  viewGridBtn.classList.remove('active');
  fileContainer.classList.remove('file-grid');
  fileContainer.classList.add('file-list');
});

// Filter Chips Handlers
let activeFilter = 'all';
const filterChips = document.querySelectorAll('.filter-chip');
filterChips.forEach((chip) => {
  chip.addEventListener('click', () => {
    filterChips.forEach((c) => {
      c.classList.remove('active');
      c.setAttribute('aria-selected', 'false');
    });
    chip.classList.add('active');
    chip.setAttribute('aria-selected', 'true');
    activeFilter = chip.getAttribute('data-filter') || 'all';
    renderFileList();
  });
});

// Load Files
async function loadFiles(subpath) {
  currentSubpath = subpath;
  fileContainer.innerHTML = '<div class="loading-spinner">Loading files...</div>';
  renderBreadcrumbs();

  try {
    const url = `/api/files?subpath=${encodeURIComponent(subpath)}`;
    const res = await fetch(url);

    if (res.status === 401) {
      location.reload();
      return;
    }

    if (!res.ok) throw new Error('Failed to load files');

    const data = await res.json();
    currentItems = data.items || [];
    document.getElementById('pageTitle').textContent = data.isReceiveMode ? 'Receive files' : 'Shared files';
    document.getElementById('pageDescription').textContent = data.isReceiveMode
      ? 'Choose files or drop them here.'
      : `${currentItems.length} ${currentItems.length === 1 ? 'item' : 'items'} available.`;
    allowUploads = data.allowUploads;
    if (data.folderName) currentFolderName = data.folderName;
    if (data.isSingleFolderShare !== undefined) isSingleFolderShare = data.isSingleFolderShare;

    selectedItems.clear();
    isSelectMode = false;
    updateSelectionUI();

    if (downloadAllBtn) {
      downloadAllBtn.style.display = currentItems.length > 0 ? 'inline-flex' : 'none';
    }
    if (selectToggleBtn) {
      selectToggleBtn.style.display = currentItems.length > 0 ? 'inline-flex' : 'none';
    }
    if (uploadBtn) {
      uploadBtn.style.display = allowUploads ? 'inline-flex' : 'none';
    }
    if (uploadFolderBtn) {
      uploadFolderBtn.style.display = allowUploads ? 'inline-flex' : 'none';
    }
    const filterChipsBar = document.getElementById('filterChipsBar');
    if (filterChipsBar) {
      filterChipsBar.style.display = currentItems.length > 0 ? 'flex' : 'none';
    }

    renderFileList();
  } catch (err) {
    fileContainer.textContent = '';
    const error = document.createElement('div');
    error.className = 'loading-spinner';
    error.textContent = 'Could not load files. Check the host is still sharing.';
    const retry = document.createElement('button');
    retry.className = 'btn btn-secondary';
    retry.textContent = 'Try again';
    retry.addEventListener('click', () => loadFiles(currentSubpath));
    error.appendChild(document.createElement('br'));
    error.appendChild(retry);
    fileContainer.appendChild(error);
  }
}

function renderBreadcrumbs() {
  const container = document.getElementById('breadcrumbList') || breadcrumbs;
  container.innerHTML = '';

  const homeCrumb = document.createElement('li');
  homeCrumb.className = `crumb ${currentSubpath === '' ? 'active' : ''}`;
  const rootLabel = (isSingleFolderShare && currentFolderName) ? currentFolderName : 'Home';
  homeCrumb.innerHTML = `<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg> <span class="crumb-text"></span>`;
  homeCrumb.querySelector('.crumb-text').textContent = rootLabel;
  if (currentSubpath !== '') {
    homeCrumb.addEventListener('click', () => loadFiles(''));
  }
  container.appendChild(homeCrumb);

  if (currentSubpath) {
    const segments = currentSubpath.split('/').filter(Boolean);
    let accum = '';
    segments.forEach((seg, index) => {
      accum += (index === 0 ? '' : '/') + seg;
      const thisPath = accum;
      const isLast = index === segments.length - 1;

      const sep = document.createElement('li');
      sep.className = 'crumb-separator';
      sep.setAttribute('aria-hidden', 'true');
      sep.textContent = '>';
      container.appendChild(sep);

      const crumb = document.createElement('li');
      crumb.className = `crumb ${isLast ? 'active' : ''}`;
      crumb.textContent = seg;
      if (!isLast) {
        crumb.addEventListener('click', () => loadFiles(thisPath));
      }
      container.appendChild(crumb);
    });
  }
}

function toggleItemSelection(item, card, checkbox) {
  if (selectedItems.has(item.path)) {
    selectedItems.delete(item.path);
    if (card) card.classList.remove('is-selected');
    if (checkbox) checkbox.checked = false;
  } else {
    selectedItems.set(item.path, item);
    if (card) card.classList.add('is-selected');
    if (checkbox) checkbox.checked = true;
  }
  if (selectedItems.size > 0) {
    isSelectMode = true;
  }
  updateSelectionUI();
}

function updateSelectionUI() {
  const count = selectedItems.size;
  if (count > 0 || isSelectMode) {
    if (selectionBar) selectionBar.style.display = 'flex';
    if (fileContainer) fileContainer.classList.add('selection-mode-active');
    if (selectToggleBtn) {
      selectToggleBtn.classList.add('active');
      if (selectToggleText) selectToggleText.textContent = isSelectMode ? 'Cancel' : 'Select';
    }
  } else {
    if (selectionBar) selectionBar.style.display = 'none';
    if (fileContainer) fileContainer.classList.remove('selection-mode-active');
    if (selectToggleBtn) {
      selectToggleBtn.classList.remove('active');
      if (selectToggleText) selectToggleText.textContent = 'Select';
    }
  }

  if (selectionCounter) {
    let totalSize = 0;
    selectedItems.forEach((i) => { totalSize += (i.size || 0); });
    selectionCounter.textContent = `${count} ${count === 1 ? 'item' : 'items'} selected${totalSize > 0 ? ` (${formatSize(totalSize)})` : ''}`;
  }

  if (downloadSelectedBtn) {
    downloadSelectedBtn.disabled = count === 0;
  }
  if (downloadSelectedText) {
    downloadSelectedText.textContent = `Download Selected (${count})`;
  }

  if (selectAllBtn) {
    const isAllSelected = itemsToRenderGlobal.length > 0 && selectedItems.size >= itemsToRenderGlobal.length;
    selectAllBtn.textContent = isAllSelected ? 'Deselect All' : 'Select All';
  }
}

function renderEmptyState({ icon, title, message, actionText, onAction, isReceiveZone }) {
  const zoneClass = isReceiveZone ? 'empty-folder-state receive-zone' : 'empty-folder-state';
  const idAttr = isReceiveZone ? ' id="receiveDropZone"' : '';
  const actionMarkup = isReceiveZone
    ? `<div class="receive-zone-actions">
        <button class="btn btn-primary btn-pill" id="emptyActionBtn" type="button">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
          <span>Select Files</span>
        </button>
        <button class="btn btn-secondary btn-pill" id="emptyFolderBtn" type="button">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/><polyline points="12 11 12 17"/><polyline points="9 14 12 11 15 14"/></svg>
          <span>Select Folder</span>
        </button>
      </div>`
    : (actionText ? `<button class="btn btn-primary btn-pill empty-action-btn" id="emptyActionBtn">${actionText}</button>` : '');

  fileContainer.innerHTML = `
    <div class="${zoneClass}"${idAttr}>
      <div class="empty-icon-wrap">${icon}</div>
      <p class="empty-folder-title">${title}</p>
      <p class="empty-folder-sub">${message}</p>
      ${actionMarkup}
    </div>
  `;
  if (isReceiveZone) {
    const dropZone = document.getElementById('receiveDropZone');
    const actionBtn = document.getElementById('emptyActionBtn');
    const folderBtn = document.getElementById('emptyFolderBtn');
    if (actionBtn) {
      actionBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (fileInput) fileInput.click();
      });
    }
    if (folderBtn) {
      folderBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (folderInput) folderInput.click();
      });
    }
    if (dropZone) {
      dropZone.addEventListener('click', () => {
        if (fileInput) fileInput.click();
      });
      dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropZone.classList.add('drag-over');
      });
      dropZone.addEventListener('dragleave', () => {
        dropZone.classList.remove('drag-over');
      });
      dropZone.addEventListener('drop', async (e) => {
        e.preventDefault();
        dropZone.classList.remove('drag-over');
        if (e.dataTransfer) {
          const files = await getFilesFromDataTransfer(e.dataTransfer);
          if (files && files.length > 0) {
            uploadFiles(files);
          }
        }
      });
    }
  } else if (actionText && onAction) {
    const actionBtn = document.getElementById('emptyActionBtn');
    if (actionBtn) actionBtn.addEventListener('click', onAction);
  }
}

function renderFileList() {
  fileContainer.innerHTML = '';

  if (currentItems.length === 0 && !allowUploads) {
    renderEmptyState({
      icon: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`,
      title: 'This folder is empty',
      message: 'No files found in this directory.',
    });
    return;
  }

  if (currentItems.length === 0 && allowUploads) {
    renderEmptyState({
      icon: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>`,
      title: 'Ready to Receive Files',
      message: 'Drag and drop files here, or click below to select files from your device.',
      actionText: 'Select Files to Send',
      isReceiveZone: true,
    });
    return;
  }

  let itemsToRender = currentItems;
  if (activeFilter === 'images') {
    itemsToRender = currentItems.filter((i) => !i.isDirectory && isImage(i.name));
  } else if (activeFilter === 'videos') {
    itemsToRender = currentItems.filter((i) => !i.isDirectory && isVideo(i.name));
  } else if (activeFilter === 'audio') {
    itemsToRender = currentItems.filter((i) => !i.isDirectory && isAudio(i.name));
  } else if (activeFilter === 'docs') {
    itemsToRender = currentItems.filter((i) => !i.isDirectory && isDocument(i.name));
  } else if (activeFilter === 'folders') {
    itemsToRender = currentItems.filter((i) => i.isDirectory);
  }

  itemsToRenderGlobal = itemsToRender;

  if (itemsToRender.length === 0) {
    renderEmptyState({
      icon: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>`,
      title: 'No matching files',
      message: 'No items in this directory match the selected filter.',
      actionText: 'Show All Files',
      onAction: () => {
        filterChips.forEach((c) => {
          c.classList.remove('active');
          c.setAttribute('aria-selected', 'false');
        });
        const allChip = document.querySelector('.filter-chip[data-filter="all"]');
        if (allChip) {
          allChip.classList.add('active');
          allChip.setAttribute('aria-selected', 'true');
        }
        activeFilter = 'all';
        renderFileList();
      },
    });
    updateSelectionUI();
    return;
  }

  itemsToRender.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'file-card';

    const isSelected = selectedItems.has(item.path);
    if (isSelected) {
      card.classList.add('is-selected');
    }

    // Selection Checkbox
    const checkWrap = document.createElement('div');
    checkWrap.className = 'card-checkbox-wrap';
    checkWrap.title = 'Select item';
    checkWrap.innerHTML = `
      <input type="checkbox" ${isSelected ? 'checked' : ''}>
      <svg class="custom-check-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
    `;
    checkWrap.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleItemSelection(item, card, checkWrap.querySelector('input'));
    });
    card.appendChild(checkWrap);

    const isDir = item.isDirectory;
    const isImg = isImage(item.name);
    const isVid = isVideo(item.name);
    const isAud = isAudio(item.name);
    const downloadUrl = `/api/files/${encodeURIComponent(item.path)}`;

    // Preview area
    const previewArea = document.createElement('div');
    previewArea.className = 'file-preview-area';

    if (isDir) {
      previewArea.innerHTML = `<svg width="48" height="48" viewBox="0 0 24 24" fill="#F59E0B"><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>`;
    } else if (isImg) {
      const thumb = document.createElement('img');
      const thumbUrl = `/api/thumbnail?path=${encodeURIComponent(item.path)}&size=512`;
      thumb.className = 'preview-thumb';
      thumb.alt = item.name;
      // Do not pull multi-megabyte full files on thumbnail failure!
      thumb.onerror = () => {
        thumb.style.display = 'none';
        previewArea.innerHTML = `<svg width="48" height="48" viewBox="0 0 24 24" fill="#3B82F6"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>`;
      };

      if (thumbnailObserver) {
        thumb.setAttribute('data-src', thumbUrl);
        // Minimal transparent 1x1 SVG placeholder while off-screen
        thumb.src = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSI+PC9zdmc+';
        thumbnailObserver.observe(thumb);
      } else {
        thumb.src = thumbUrl;
      }
      previewArea.appendChild(thumb);
    } else if (isVid && item.remainingDownloads == null) {
      previewArea.innerHTML = `
        <svg class="video-placeholder-icon" width="48" height="48" viewBox="0 0 24 24" fill="#8B5CF6"><path d="M18 3v2h-2V3H8v2H6V3H4v18h2v-2h2v2h8v-2h2v2h2V3h-2zM8 17H6v-2h2v2zm0-4H6v-2h2v2zm0-4H6V7h2v2zm10 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V7h2v2z"/></svg>
        <div class="video-play-overlay"><svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></div>
      `;

      if (videoThumbCache.has(item.path)) {
        applyVideoThumbnail(previewArea, videoThumbCache.get(item.path), item.name);
      } else if (videoObserver) {
        previewArea.setAttribute('data-video-path', item.path);
        videoObserver.observe(previewArea);
      } else {
        queueVideoThumbnail(item, previewArea);
      }
    } else if (isAud) {
      previewArea.innerHTML = `
        <svg width="48" height="48" viewBox="0 0 24 24" fill="#10B981"><path d="M12 3v9.28a4.39 4.39 0 00-1.5-.28 4.5 4.5 0 104.5 4.5V6h4V3h-7z"/></svg>
        <div class="audio-play-overlay"><svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></div>
      `;
    } else {
      previewArea.innerHTML = `<svg width="44" height="44" viewBox="0 0 24 24" fill="#38BDF8"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>`;
    }

    // Info area
    const infoArea = document.createElement('div');
    infoArea.className = 'file-info-area';

    const title = document.createElement('div');
    title.className = 'file-title';
    title.textContent = item.name;

    const metaRow = document.createElement('div');
    metaRow.className = 'file-meta-row';

    const meta = document.createElement('span');
    meta.className = 'file-meta';
    meta.textContent = isDir ? 'Folder' : formatSize(item.size);
    metaRow.appendChild(meta);

    if (item.remainingDownloads !== undefined && item.remainingDownloads !== null) {
      const badge = document.createElement('span');
      badge.className = 'vault-badge';
      badge.textContent = `${item.remainingDownloads} left`;
      metaRow.appendChild(badge);
    }

    infoArea.appendChild(title);
    infoArea.appendChild(metaRow);

    card.appendChild(previewArea);
    card.appendChild(infoArea);

    card.tabIndex = 0;
    card.setAttribute('role', 'button');
    card.setAttribute('aria-label', `${isDir ? 'Open folder' : 'Open file'} ${item.name}`);
    card.addEventListener('keydown', (event) => {
      if (event.target === card && (event.key === 'Enter' || event.key === ' ')) {
        event.preventDefault();
        card.click();
      }
    });
    card.addEventListener('click', () => {
      if (isSelectMode) {
        toggleItemSelection(item, card, checkWrap.querySelector('input'));
      } else if (isDir) {
        loadFiles(item.path);
      } else if ((isImg || isVid || isAud) && item.remainingDownloads == null) {
        openPreview(item, downloadUrl);
      } else {
        triggerDownload(downloadUrl, item.name);
      }
    });

    fileContainer.appendChild(card);
  });

  updateSelectionUI();
}

// Global Drag & Drop Handler (Always active when uploads are allowed)
let dragCounter = 0;

function isDragWithFiles(e) {
  if (!e.dataTransfer) return false;
  if (e.dataTransfer.types) {
    for (let i = 0; i < e.dataTransfer.types.length; i++) {
      if (e.dataTransfer.types[i] === 'Files') return true;
    }
  }
  return false;
}

window.addEventListener('dragenter', (e) => {
  e.preventDefault();
  if (!allowUploads) return;
  if (isDragWithFiles(e)) {
    dragCounter++;
    if (dragDropOverlay) {
      dragDropOverlay.style.display = 'flex';
      // Force reflow for smooth transition
      dragDropOverlay.offsetHeight;
      dragDropOverlay.classList.add('active');
    }
  }
});

window.addEventListener('dragleave', (e) => {
  e.preventDefault();
  if (!allowUploads) return;
  dragCounter--;
  if (dragCounter <= 0) {
    dragCounter = 0;
    if (dragDropOverlay) {
      dragDropOverlay.classList.remove('active');
      setTimeout(() => {
        if (dragCounter === 0) dragDropOverlay.style.display = 'none';
      }, 200);
    }
  }
});

window.addEventListener('dragover', (e) => {
  e.preventDefault();
  if (e.dataTransfer) {
    e.dataTransfer.dropEffect = allowUploads ? 'copy' : 'none';
  }
});

// Helper to recursively extract files and preserve directory structure from DataTransfer items
async function getFilesFromDataTransfer(dataTransfer) {
  const files = [];
  if (dataTransfer.items && dataTransfer.items.length > 0 && dataTransfer.items[0].webkitGetAsEntry) {
    const queue = [];
    for (let i = 0; i < dataTransfer.items.length; i++) {
      const item = dataTransfer.items[i];
      if (item.kind === 'file') {
        const entry = item.webkitGetAsEntry();
        if (entry) queue.push(entry);
      }
    }
    while (queue.length > 0) {
      const entry = queue.shift();
      if (entry.isFile) {
        try {
          const file = await new Promise((resolve, reject) => entry.file(resolve, reject));
          file.customRelativePath = entry.fullPath ? entry.fullPath.replace(/^\/+/, '') : file.name;
          files.push(file);
        } catch (_) {}
      } else if (entry.isDirectory) {
        try {
          const dirReader = entry.createReader();
          const readAllEntries = async () => {
            const all = [];
            let batch;
            do {
              batch = await new Promise((resolve) => dirReader.readEntries(resolve, () => resolve([])));
              if (batch && batch.length > 0) {
                all.push(...batch);
              }
            } while (batch && batch.length > 0);
            return all;
          };
          const subEntries = await readAllEntries();
          for (const sub of subEntries) {
            queue.push(sub);
          }
        } catch (_) {}
      }
    }
    if (files.length > 0) return files;
  }
  return Array.from(dataTransfer.files || []);
}

window.addEventListener('drop', async (e) => {
  e.preventDefault();
  dragCounter = 0;
  if (dragDropOverlay) {
    dragDropOverlay.classList.remove('active');
    setTimeout(() => {
      dragDropOverlay.style.display = 'none';
    }, 200);
  }
  if (!allowUploads) return;
  if (e.dataTransfer) {
    const files = await getFilesFromDataTransfer(e.dataTransfer);
    if (files && files.length > 0) {
      uploadFiles(files);
    }
  }
});

if (fileInput) {
  fileInput.addEventListener('change', (e) => {
    if (e.target.files && e.target.files.length > 0) {
      uploadFiles(e.target.files);
      fileInput.value = ''; // Reset so the same file can be picked again
    }
  });
}

if (folderInput) {
  folderInput.addEventListener('change', (e) => {
    if (e.target.files && e.target.files.length > 0) {
      uploadFiles(e.target.files);
      folderInput.value = ''; // Reset so the same folder can be picked again
    }
  });
}

// Batch Upload Implementation with Non-Blocking Status Reporting
async function uploadFiles(files) {
  if (!files || files.length === 0 || isUploadingLocal) return;
  files = Array.from(files);
  isUploadingLocal = true;
  let successCount = 0;
  let failCount = 0;

  try {
  await withTransferLock(async () => {
    for (let i = 0; i < files.length; i++) {
      await waitForVisibilityOrOnline();
      await requestWebWakeLock();
      const file = files[i];
      liveTransferBanner.style.display = 'block';
      const displayName = file.webkitRelativePath || file.customRelativePath || file.name;
      transferTitle.textContent = `⬆ Uploading ${displayName} (${i + 1}/${files.length})`;
      transferProgressBar.style.backgroundColor = '';

      let uploaded = false;
      for (let attempt = 1; attempt <= 3 && !uploaded; attempt++) {
        try {
          if (attempt > 1) {
            await waitForVisibilityOrOnline();
            await requestWebWakeLock();
            transferTitle.textContent = `⬆ Resuming ${displayName} (${i + 1}/${files.length})...`;
          }
          await uploadSingleFile(file, (percent) => {
            transferProgressText.textContent = `${percent}%`;
            transferProgressBar.style.width = `${percent}%`;
          });
          uploaded = true;
          successCount++;
        } catch (err) {
          const isFatal = err && (err.cancelled || (err.status >= 400 && err.status < 500));
          if (isFatal || attempt === 3) {
            failCount++;
            transferTitle.textContent = `❌ Upload failed: ${file.name}`;
            transferProgressBar.style.backgroundColor = 'var(--cp-color-danger)';
            await new Promise((r) => setTimeout(r, 1200));
            break;
          }
          await new Promise((r) => setTimeout(r, 1500));
        }
      }
    }
  });

  } catch (_) {
    failCount = files.length - successCount;
  } finally {
    isUploadingLocal = false;
    activeUpload = null;
  }

  if (failCount > 0) {
    transferTitle.textContent = `Uploaded ${successCount}/${files.length} file(s). ${failCount} failed.`;
  } else {
    transferTitle.textContent = `✔ All ${files.length} file(s) uploaded successfully!`;
  }
  transferProgressText.textContent = failCount ? 'Incomplete' : '100%';
  transferProgressBar.style.width = failCount ? `${Math.round(successCount / files.length * 100)}%` : '100%';

  setTimeout(() => {
    liveTransferBanner.style.display = 'none';
    transferProgressBar.style.width = '0%';
    transferProgressBar.style.backgroundColor = '';
    loadFiles(currentSubpath);
  }, 1600);
}

function uploadSingleFile(file, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const upload = { xhr, name: file.name, cancelled: false };
    activeUpload = upload;
    const fail = (message) => {
      const error = new Error(message);
      error.status = xhr.status;
      error.cancelled = upload.cancelled;
      reject(error);
    };
    xhr.open('POST', '/api/upload');
    xhr.setRequestHeader('X-Filename', encodeURIComponent(file.name));
    xhr.setRequestHeader('X-Filesize', file.size.toString());

    // Determine subpath: merge currentSubpath with folder structure from webkitRelativePath or customRelativePath
    let targetSubpath = currentSubpath || '';
    const relPath = file.webkitRelativePath || file.customRelativePath || '';
    if (relPath) {
      const parts = relPath.replace(/\\/g, '/').split('/');
      parts.pop(); // Remove the filename itself
      if (parts.length > 0) {
        const fileFolder = parts.join('/');
        targetSubpath = targetSubpath ? `${targetSubpath}/${fileFolder}` : fileFolder;
      }
    }

    if (targetSubpath) {
      xhr.setRequestHeader('X-Subpath', encodeURIComponent(targetSubpath));
    }

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const percent = Math.round((e.loaded / e.total) * 100);
        onProgress(percent);
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else if (xhr.status === 413) {
        fail('Server rejected the file size (HTTP 413). Try a smaller file or local Wi-Fi.');
      } else if (xhr.status === 524) {
        fail('Upload timed out (HTTP 524). Try smaller files or local Wi-Fi.');
      } else {
        let msg = xhr.statusText;
        try {
          const res = JSON.parse(xhr.responseText);
          if (res.message) msg = res.message;
        } catch (_) {}
        fail(msg || `Upload failed (HTTP ${xhr.status})`);
      }
    };

    xhr.onerror = () => fail('Network error during upload');
    xhr.onabort = () => fail(upload.cancelled ? 'Upload cancelled by host' : 'Upload interrupted');
    xhr.send(file);
  });
}

// Media Preview Modal
let previewReturnFocus = null;
function openPreview(item, url) {
  previewReturnFocus = document.activeElement;
  modalFilename.textContent = item.name;
  if (modalMeta) {
    modalMeta.textContent = formatSize(item.size);
  }
  const dlSep = url.includes('?') ? '&' : '?';
  modalDownloadBtn.href = `${url}${dlSep}download=1`;
  modalDownloadBtn.download = item.name;
  if (modalDownloadLabel) {
    modalDownloadLabel.textContent = `Download (${formatSize(item.size)})`;
  }
  modalBody.innerHTML = '';

  if (isImage(item.name)) {
    const img = document.createElement('img');
    // Load lightweight 512px preview (~25-35 KB) first so modal opens instantly without pulling 15-25 MB original
    img.src = `/api/thumbnail?path=${encodeURIComponent(item.path)}&size=512`;
    img.alt = item.name;
    img.style.maxHeight = '70vh';
    img.style.maxWidth = '100%';
    img.style.objectFit = 'contain';
    img.onerror = () => {
      img.onerror = null;
      img.src = url;
    };
    modalBody.appendChild(img);
  } else if (isVideo(item.name)) {
    const vid = document.createElement('video');
    vid.src = url;
    vid.controls = true;
    vid.autoplay = true;
    if (videoThumbCache.has(item.path)) {
      vid.poster = videoThumbCache.get(item.path);
    }
    modalBody.appendChild(vid);
  } else if (isAudio(item.name)) {
    const aud = document.createElement('audio');
    aud.src = url;
    aud.controls = true;
    aud.autoplay = true;
    aud.style.width = '100%';
    aud.style.marginTop = '24px';
    modalBody.appendChild(aud);
  }

  previewModal.style.display = 'flex';
  modalCloseBtn.focus();
}

function closeModal() {
  previewModal.style.display = 'none';
  modalBody.innerHTML = '';
  if (previewReturnFocus && previewReturnFocus.isConnected) previewReturnFocus.focus();
}

modalCloseBtn.addEventListener('click', closeModal);
previewModal.addEventListener('click', (e) => {
  if (e.target === previewModal) closeModal();
});
document.addEventListener('keydown', (e) => {
  const activeModal = [previewModal, downloadChoiceModal].find(modal => modal && modal.style.display === 'flex');
  if (e.key === 'Tab' && activeModal) {
    const targets = Array.from(activeModal.querySelectorAll('button, a[href], input, [tabindex="0"]')).filter(el => !el.disabled && el.getClientRects().length);
    const first = targets[0], last = targets[targets.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }
  if (e.key === 'Escape') {
    if (previewModal && previewModal.style.display === 'flex') closeModal();
    if (downloadChoiceModal && downloadChoiceModal.style.display === 'flex') closeDownloadChoiceModal();
  }
});

// Download All with Choice
if (downloadAllBtn) {
  downloadAllBtn.addEventListener('click', () => {
    if (currentItems.length === 0) {
      downloadZipWithPaths([], 'cloudpocket_all.zip');
      return;
    }

    if (currentItems.length === 1 && !currentItems[0].isDirectory) {
      triggerDownload(`/api/files/${encodeURIComponent(currentItems[0].path)}`, currentItems[0].name);
      return;
    }

    const items = currentItems;
    let totalSize = 0;
    items.forEach((i) => { totalSize += (i.size || 0); });

    openDownloadChoiceModal({
      title: 'Download All Items',
      subtitle: `All ${items.length} items in current view${totalSize > 0 ? ` (${formatSize(totalSize)})` : ''}`,
      onZip: () => {
        downloadZipWithPaths([], 'cloudpocket_all.zip');
        if (liveTransferBanner) {
          liveTransferBanner.style.display = 'block';
          transferTitle.textContent = `Preparing ZIP archive of all items...`;
          transferProgressText.textContent = '100%';
          transferProgressBar.style.width = '100%';
          setTimeout(() => {
            liveTransferBanner.style.display = 'none';
            transferProgressBar.style.width = '0%';
          }, 2500);
        }
      },
      onSeparate: () => {
        downloadItemsSeparately(items);
      },
    });
  });
}

function triggerDownload(url, filename) {
  requestWebWakeLock();
  const sep = url.includes('?') ? '&' : '?';
  const downloadUrl = url.includes('download=1') ? url : `${url}${sep}download=1`;
  const a = document.createElement('a');
  a.href = downloadUrl;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

// Helpers
function formatSize(bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  let s = bytes;
  while (s >= 1024 && i < units.length - 1) {
    s /= 1024;
    i++;
  }
  return `${s.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function isImage(name) {
  return /\.(jpe?g|png|gif|webp|svg|bmp)$/i.test(name);
}

function isVideo(name) {
  return /\.(mp4|webm|mkv|mov|avi|m4v|3gp|flv|wmv|ts|ogv)$/i.test(name);
}

function isAudio(name) {
  return /\.(mp3|wav|ogg|m4a|aac|flac)$/i.test(name);
}

function isDocument(name) {
  return /\.(pdf|docx?|xlsx?|pptx?|txt|csv|json|md|html|xml|zip|tar|gz)$/i.test(name);
}

// Launch initialization
document.addEventListener('DOMContentLoaded', init);
