(function () {
  'use strict';

  // State
  let ws = null;
  let myParticipantId = null;
  let myNickname = '';
  let myColor = '#38BDF8';
  let remainingSeconds = 0;
  let countdownTimer = null;
  let messageCount = 0;
  let fileCount = 0;
  let participantCount = 1;
  let typingTimeout = null;
  let isRoomBurned = false;
  let incomingQueue = Promise.resolve();

  // DOM Elements
  const joinModal = document.getElementById('joinModal');
  const joinForm = document.getElementById('joinForm');
  const nicknameInput = document.getElementById('nicknameInput');
  const pinGroup = document.getElementById('pinGroup');
  const pinInput = document.getElementById('pinInput');
  const joinError = document.getElementById('joinError');
  const countdownDisplay = document.getElementById('countdownDisplay');
  const participantCountText = document.getElementById('participantCountText');
  const chatFeed = document.getElementById('chatFeed');
  const messageInput = document.getElementById('messageInput');
  const sendBtn = document.getElementById('sendBtn');
  const typingIndicator = document.getElementById('typingIndicator');
  const typingText = document.getElementById('typingText');
  const watermarkOverlay = document.getElementById('watermarkOverlay');
  const burnedScreen = document.getElementById('burnedScreen');
  const statMessages = document.getElementById('statMessages');
  const statFiles = document.getElementById('statFiles');
  const statParticipants = document.getElementById('statParticipants');

  // 1. Mobile App Deep Link Helper & Token Extraction
  function getInviteToken() {
    if (window.location.hash && window.location.hash.length > 1) {
      const hash = window.location.hash.substring(1);
      const params = new URLSearchParams(hash);
      return params.get('k') || params.get('token') || '';
    }
    const queryToken = new URLSearchParams(window.location.search).get('token');
    return queryToken || '';
  }

  // Payload encryption engine (WebCrypto AES-256-GCM; legacy CBC decrypt only)
  let e2eCryptoKey = null;

  function bufferToBase64(buf) {
    const bytes = new Uint8Array(buf);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  function base64ToBuffer(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function computeRoomSecret(token, pin) {
    const cleanToken = (token || '').trim();
    const cleanPin = (pin || '').trim();
    if (cleanToken && cleanPin) {
      return `${cleanToken}:${cleanPin}`;
    } else if (cleanToken) {
      return cleanToken;
    } else if (cleanPin) {
      return cleanPin;
    }
    return null;
  }

  async function deriveAesKey(secret) {
    const enc = new TextEncoder();
    const secretBytes = enc.encode(secret);
    const hash = await window.crypto.subtle.digest('SHA-256', secretBytes);
    const gcmKey = await window.crypto.subtle.importKey(
      'raw',
      hash,
      { name: 'AES-GCM' },
      false,
      ['encrypt', 'decrypt']
    );
    let cbcKey = null;
    try {
      cbcKey = await window.crypto.subtle.importKey(
        'raw',
        hash,
        { name: 'AES-CBC' },
        false,
        ['decrypt']
      );
    } catch (_) {}
    return { gcmKey, cbcKey };
  }

  async function initE2e(token, pin) {
    try {
      if (window.crypto && window.crypto.subtle) {
        const secret = computeRoomSecret(token, pin);
        if (secret) {
          e2eCryptoKey = await deriveAesKey(secret);
        } else {
          e2eCryptoKey = null;
        }
      }
    } catch (e) {
      console.warn('Payload encryption is unavailable in this browser.');
      e2eCryptoKey = null;
    }
  }

  async function encryptText(cryptoKeys, text) {
    const enc = new TextEncoder();
    const iv = window.crypto.getRandomValues(new Uint8Array(12));
    const key = cryptoKeys.gcmKey || cryptoKeys;
    const encryptedBuf = await window.crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: iv, tagLength: 128 },
      key,
      enc.encode(text)
    );
    return {
      ciphertext: bufferToBase64(encryptedBuf),
      iv: bufferToBase64(iv),
      alg: 'AES-GCM',
    };
  }

  async function decryptText(cryptoKeys, ciphertextB64, ivB64, alg) {
    try {
      const rawCipher = base64ToBuffer(ciphertextB64);
      const rawIv = base64ToBuffer(ivB64);

      if (rawIv.length === 12 || alg === 'AES-GCM') {
        const key = cryptoKeys.gcmKey || cryptoKeys;
        const decryptedBuf = await window.crypto.subtle.decrypt(
          { name: 'AES-GCM', iv: rawIv, tagLength: 128 },
          key,
          rawCipher
        );
        return new TextDecoder().decode(decryptedBuf);
      } else if ((rawIv.length === 16 || alg === 'AES-CBC') && cryptoKeys.cbcKey) {
        const decryptedBuf = await window.crypto.subtle.decrypt(
          { name: 'AES-CBC', iv: rawIv },
          cryptoKeys.cbcKey,
          rawCipher
        );
        return new TextDecoder().decode(decryptedBuf);
      }
      return null;
    } catch (err) {
      return null;
    }
  }

  function openInNativeApp() {
    const currentUrl = window.location.origin + window.location.pathname;
    let hashPin = '';
    if (window.location.hash) {
      const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));
      hashPin = hashParams.get('pin') || '';
    }
    const pin = pinInput.value.trim() || hashPin || new URLSearchParams(window.location.search).get('pin') || '';
    const nick = nicknameInput.value.trim() || '';
    const token = getInviteToken();
    let appUrl = `cloudpocket://room?url=${encodeURIComponent(currentUrl)}`;
    if (token) appUrl += `&token=${encodeURIComponent(token)}`;
    if (pin) appUrl += `#pin=${encodeURIComponent(pin)}`;
    if (nick) appUrl += `&nick=${encodeURIComponent(nick)}`;

    window.location.href = appUrl;

    setTimeout(() => {
      if (!document.hidden) {
        window.open('https://github.com/madebyarjun', '_blank');
      }
    }, 1500);
  }

  function checkNativeAppRedirect() {
    const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
    if (isMobile && !window.location.search.includes('nobounce')) {
      const appUrl = `cloudpocket://room?url=${encodeURIComponent(window.location.href)}`;
      const iframe = document.createElement('iframe');
      iframe.style.display = 'none';
      iframe.src = appUrl;
      document.body.appendChild(iframe);
      setTimeout(() => {
        try { document.body.removeChild(iframe); } catch (_) {}
      }, 1200);
    }
  }

  // 2. Fetch Room Configuration on Load
  async function checkRoomInfo() {
    try {
      const res = await fetch('/api/room/info');
      if (res.status === 404) {
        showBurnedScreen('Room not active or expired');
        return;
      }
      const data = await res.json();
      window.CloudPocketTheme.apply(data.themeMode);
      remainingSeconds = data.remainingSeconds || 0;
      if (data.isCountdownActive !== false) startCountdown();
      else countdownDisplay.textContent = 'Starts on join';

      // Update room title and code badges if provided
      if (data.roomName) {
        document.title = `${data.roomName} — CloudPocket`;
        const modalTitle = document.getElementById('modalRoomTitle');
        if (modalTitle) modalTitle.textContent = data.roomName;
        const welcomeTitle = document.getElementById('welcomeRoomTitle');
        if (welcomeTitle) welcomeTitle.textContent = data.roomName;
      }
      if (data.roomCode) {
        const headerBadge = document.getElementById('roomCodeBadge');
        if (headerBadge) {
          headerBadge.textContent = data.roomCode;
          headerBadge.classList.remove('hidden');
        }
        const modalBadge = document.getElementById('modalRoomCodeBadge');
        if (modalBadge) {
          modalBadge.textContent = `Room Code: ${data.roomCode}`;
          modalBadge.classList.remove('hidden');
        }
      }

      const inviteToken = getInviteToken();

      if (data.requirePin) {
        pinGroup.classList.remove('hidden');
        pinInput.required = true;
      } else {
        pinGroup.classList.add('hidden');
        pinInput.required = false;
      }

      // Check PIN in URL fragment (#pin=1234) or fallback to query param
      let hashPin = '';
      if (window.location.hash) {
        const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));
        hashPin = hashParams.get('pin') || '';
      }
      const urlParams = new URLSearchParams(window.location.search);
      const urlPin = hashPin || urlParams.get('pin');
      if (urlPin) {
        pinInput.value = urlPin;
      }

      // Check saved name in sessionStorage
      const savedName = sessionStorage.getItem('cp_room_name');
      if (savedName) {
        nicknameInput.value = savedName;
      }
    } catch (_) {
      showBurnedScreen('Cannot connect to room server');
    }
  }

  // 3. Countdown Timer Ticker
  function startCountdown() {
    clearInterval(countdownTimer);
    updateCountdownDisplay();
    countdownTimer = setInterval(() => {
      if (remainingSeconds > 0) {
        remainingSeconds--;
        updateCountdownDisplay();
      } else {
        clearInterval(countdownTimer);
        showBurnedScreen('Timer expired');
      }
    }, 1000);
  }

  function updateCountdownDisplay() {
    const m = Math.floor(remainingSeconds / 60);
    const s = remainingSeconds % 60;
    countdownDisplay.textContent = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }

  // 4. Join Form Submission
  joinForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    joinError.classList.add('hidden');
    joinError.textContent = '';

    const nick = nicknameInput.value.trim();
    if (!nick) return;

    const token = getInviteToken();

    if (!pinGroup.classList.contains('hidden')) {
      const pinVal = pinInput.value.trim();
      if (!pinVal) {
        joinError.textContent = 'Room PIN is required.';
        joinError.classList.remove('hidden');
        return;
      }
      try {
        const authRes = await fetch('/api/room/auth', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pin: pinVal }),
        });
        if (!authRes.ok) {
          joinError.textContent = 'Incorrect PIN. Please try again.';
          joinError.classList.remove('hidden');
          return;
        }
      } catch (_) {
        joinError.textContent = 'PIN verification failed.';
        joinError.classList.remove('hidden');
        return;
      }
    }

    myNickname = nick;
    sessionStorage.setItem('cp_room_name', myNickname);
    setupWatermark(myNickname);
    await initE2e(token, pinInput.value.trim());
    connectWebSocket();
  });

  function setupWatermark(name) {
    const repeated = Array(12).fill(name).join('   •   ');
    watermarkOverlay.textContent = Array(8).fill(repeated).join('\n');
  }

  // Screen Wake Lock & Visibility Recovery
  let roomWakeLock = null;
  async function requestRoomWakeLock() {
    if (!isRoomBurned && typeof navigator !== 'undefined' && 'wakeLock' in navigator && document.visibilityState === 'visible') {
      try {
        if (!roomWakeLock || roomWakeLock.released) {
          roomWakeLock = await navigator.wakeLock.request('screen');
          roomWakeLock.addEventListener('release', () => {
            roomWakeLock = null;
          });
        }
      } catch (_) {}
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && !isRoomBurned) {
      requestRoomWakeLock();
      if (myNickname && (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING)) {
        connectWebSocket();
      }
    }
  });

  window.addEventListener('online', () => {
    if (!isRoomBurned && myNickname && (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING)) {
      requestRoomWakeLock();
      connectWebSocket();
    }
  });

  // 5. WebSocket Connection & Event Handling
  function connectWebSocket() {
    if (isRoomBurned) return;
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    requestRoomWakeLock();
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/room`;

    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      const joinPayload = {
        type: 'join',
        nickname: myNickname,
        client: 'browser',
        secureMode: false,
      };
      const token = getInviteToken();
      if (token) {
        joinPayload.token = token;
      }
      if (pinInput.value.trim()) {
        joinPayload.pin = pinInput.value.trim();
      }
      ws.send(JSON.stringify(joinPayload));
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        incomingQueue = incomingQueue.then(() => handleServerMessage(msg)).catch(() => {});
      } catch (_) {}
    };

    ws.onclose = () => {
      sendBtn.disabled = true;
      if (!isRoomBurned) {
        // Attempt reconnect if not explicitly destroyed
        setTimeout(() => {
          if (!isRoomBurned) connectWebSocket();
        }, 2000);
      }
    };

    ws.onerror = () => {
      if (ws) ws.close();
    };
  }

  async function handleServerMessage(msg) {
    switch (msg.type) {
      case 'welcome':
        if (msg.roomToken) await initE2e(msg.roomToken, pinInput.value.trim());
        updateChatSecurity();
        if (Number.isFinite(msg.remainingSeconds)) remainingSeconds = msg.remainingSeconds;
        startCountdown();
        myParticipantId = msg.participantId;
        myColor = msg.color || '#38BDF8';
        if (msg.roomName) {
          document.title = `${msg.roomName} — CloudPocket`;
          const welcomeTitle = document.getElementById('welcomeRoomTitle');
          if (welcomeTitle) welcomeTitle.textContent = msg.roomName;
        }
        if (msg.roomCode) {
          const headerBadge = document.getElementById('roomCodeBadge');
          if (headerBadge) {
            headerBadge.textContent = msg.roomCode;
            headerBadge.classList.remove('hidden');
          }
        }
        if (msg.messages && Array.isArray(msg.messages)) {
          for (const histMsg of msg.messages) {
            const isHistFile = histMsg.type === 'file' || histMsg.messageType === 'file' || Boolean(histMsg.filename) || Boolean(histMsg.fileDownloadPath);
            if (histMsg.isE2e && histMsg.ciphertext && histMsg.iv && e2eCryptoKey) {
              decryptText(e2eCryptoKey, histMsg.ciphertext, histMsg.iv, histMsg.alg).then((dec) => {
                if (dec) histMsg.text = dec;
                if (isHistFile) appendFileMessage(histMsg);
                else appendChatMessage(histMsg);
              });
            } else {
              if (isHistFile) appendFileMessage(histMsg);
              else appendChatMessage(histMsg);
            }
          }
        }
        joinModal.classList.add('hidden');
        messageInput.focus();
        break;

      case 'participant_joined':
        appendSystemChip(`${msg.participant.nickname} joined the room`);
        break;

      case 'participant_left':
        appendSystemChip(`${msg.nickname} left the room`);
        break;

      case 'chat_message':
        messageCount++;
        const isFileMsg = msg.type === 'file' || msg.messageType === 'file' || Boolean(msg.filename) || Boolean(msg.fileDownloadPath);
        if (isFileMsg) {
          fileCount++;
          appendFileMessage(msg);
        } else {
          if (msg.isE2e && msg.ciphertext && msg.iv && e2eCryptoKey) {
            decryptText(e2eCryptoKey, msg.ciphertext, msg.iv, msg.alg).then((dec) => {
              if (dec) msg.text = dec;
              appendChatMessage(msg);
            });
          } else {
            appendChatMessage(msg);
          }
        }
        break;

      case 'typing_indicator':
        if (msg.participantId !== myParticipantId) {
          if (msg.isTyping) {
            typingText.textContent = `${msg.nickname} is typing...`;
            typingIndicator.classList.remove('hidden');
          } else {
            typingIndicator.classList.add('hidden');
          }
        }
        break;

      case 'heartbeat':
        remainingSeconds = msg.remainingSeconds;
        updateCountdownDisplay();
        if (msg.participantCount !== undefined) {
          participantCount = msg.participantCount;
          participantCountText.textContent = `${participantCount} online`;
        }
        break;

      case 'room_destroyed':
        showBurnedScreen(msg.reason || 'Room burned');
        break;

      case 'error':
        appendSystemChip(`⚠️ ${msg.message}`);
        break;
    }
  }

  // 6. Safe DOM Message Rendering (100% XSS Proof via textContent)
  function appendChatMessage(msg) {
    const isSent = msg.senderId === myParticipantId;

    const row = document.createElement('div');
    row.className = `msg-row ${isSent ? 'sent' : 'received'}`;

    // Avatar
    const avatar = document.createElement('div');
    avatar.className = 'msg-avatar';
    avatar.style.backgroundColor = msg.color || '#38BDF8';
    avatar.textContent = (msg.senderNickname || '?').charAt(0).toUpperCase();

    // Body
    const body = document.createElement('div');
    body.className = 'msg-body';

    // Meta (author, tier badge, time)
    const meta = document.createElement('div');
    meta.className = 'msg-meta';

    const author = document.createElement('span');
    author.className = 'msg-author';
    author.textContent = isSent ? 'You' : msg.senderNickname;
    author.style.color = msg.color || '#38BDF8';
    meta.appendChild(author);

    const tierBadge = document.createElement('span');
    tierBadge.className = `msg-tier-badge ${msg.isSecureClient ? 'secure' : 'browser'}`;
    tierBadge.textContent = msg.isSecureClient ? 'App' : 'Browser';
    meta.appendChild(tierBadge);

    const time = document.createElement('span');
    time.className = 'msg-time';
    const date = msg.timestamp ? new Date(msg.timestamp) : new Date();
    time.textContent = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    meta.appendChild(time);

    if (msg.isE2e) {
      const lockIcon = document.createElement('span');
      lockIcon.className = 'msg-lock-icon';
      lockIcon.title = 'AES-GCM encrypted payload. Admission credentials are shared with the host.';
      lockIcon.innerHTML = `<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
      meta.appendChild(lockIcon);
    }

    body.appendChild(meta);

    // Text Bubble
    const bubble = document.createElement('div');
    bubble.className = 'msg-bubble';
    bubble.textContent = msg.text || '';
    body.appendChild(bubble);

    row.appendChild(avatar);
    row.appendChild(body);

    chatFeed.appendChild(row);
    scrollToBottom();
  }

  function appendFileMessage(msg) {
    const isSent = msg.senderId === myParticipantId;

    const row = document.createElement('div');
    row.className = `msg-row ${isSent ? 'sent' : 'received'}`;

    const avatar = document.createElement('div');
    avatar.className = 'msg-avatar';
    avatar.style.backgroundColor = msg.color || '#38BDF8';
    avatar.textContent = (msg.senderNickname || '?').charAt(0).toUpperCase();

    const body = document.createElement('div');
    body.className = 'msg-body';

    const meta = document.createElement('div');
    meta.className = 'msg-meta';

    const author = document.createElement('span');
    author.className = 'msg-author';
    author.textContent = isSent ? 'You' : msg.senderNickname;
    author.style.color = msg.color || '#38BDF8';
    meta.appendChild(author);

    const tierBadge = document.createElement('span');
    tierBadge.className = `msg-tier-badge ${msg.isSecureClient ? 'secure' : 'browser'}`;
    tierBadge.textContent = msg.isSecureClient ? 'App' : 'Browser';
    meta.appendChild(tierBadge);

    body.appendChild(meta);

    // File Card
    const card = document.createElement('div');
    card.className = 'file-card';

    const ext = (msg.filename || '').split('.').pop().toLowerCase();
    const isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].includes(ext);
    const isVideo = ['mp4', 'webm', 'mov'].includes(ext);
    const isAudio = ['mp3', 'wav', 'ogg', 'aac', 'm4a'].includes(ext);

    if (isImg && msg.fileDownloadPath) {
      const img = document.createElement('img');
      img.src = msg.fileDownloadPath;
      img.className = 'file-preview-media';
      img.alt = msg.filename || 'Photo';
      img.loading = 'lazy';
      img.draggable = false;
      img.oncontextmenu = (e) => e.preventDefault();
      card.appendChild(img);
    } else if (isVideo && msg.fileDownloadPath) {
      const video = document.createElement('video');
      video.src = msg.fileDownloadPath;
      video.controls = true;
      video.controlsList = 'nodownload';
      video.className = 'file-preview-media';
      video.oncontextmenu = (e) => e.preventDefault();
      card.appendChild(video);
    } else if (isAudio && msg.fileDownloadPath) {
      const audio = document.createElement('audio');
      audio.src = msg.fileDownloadPath;
      audio.controls = true;
      audio.controlsList = 'nodownload';
      audio.style.width = '100%';
      audio.style.marginBottom = '8px';
      card.appendChild(audio);
    }

    const headerRow = document.createElement('div');
    headerRow.className = 'file-header-row';

    const iconBox = document.createElement('div');
    iconBox.className = 'file-icon-box';
    iconBox.textContent = getFileBadge(msg.filename);

    const info = document.createElement('div');
    info.className = 'file-info';

    const title = document.createElement('div');
    title.className = 'file-title';
    title.textContent = msg.filename || 'Shared file';

    const size = document.createElement('div');
    size.className = 'file-size';
    size.textContent = `${formatBytes(msg.fileSize || 0)} • View-only`;

    info.appendChild(title);
    info.appendChild(size);

    const appOnlyBadge = document.createElement('span');
    appOnlyBadge.className = 'msg-tier-badge secure';
    appOnlyBadge.textContent = 'View-Only';

    headerRow.appendChild(iconBox);
    headerRow.appendChild(info);
    headerRow.appendChild(appOnlyBadge);

    card.appendChild(headerRow);

    body.appendChild(card);
    row.appendChild(avatar);
    row.appendChild(body);

    chatFeed.appendChild(row);
    scrollToBottom();
  }

  function appendSystemChip(text) {
    const chip = document.createElement('div');
    chip.className = 'system-chip';
    chip.textContent = text;
    chatFeed.appendChild(chip);
    scrollToBottom();
  }

  function scrollToBottom() {
    chatFeed.scrollTop = chatFeed.scrollHeight;
  }

  // 7. Message Sending
  function isLocalHttpChat() {
    if (window.location.protocol !== 'http:') return false;
    const host = (window.location.hostname || '').toLowerCase();
    if (host === 'localhost' || host === '[::1]' || host === '::1' || host.endsWith('.local')) return true;
    if (/^\[?(?:f[cd][0-9a-f]{2}:|fe80:)/.test(host)) return true;
    const octets = host.split('.').map(Number);
    if (octets.length !== 4 || octets.some(n => !Number.isInteger(n) || n < 0 || n > 255)) return false;
    return octets[0] === 127 || octets[0] === 10 ||
      (octets[0] === 192 && octets[1] === 168) ||
      (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] === 169 && octets[1] === 254);
  }

  function updateChatSecurity() {
    const label = document.getElementById('transportLabel');
    const description = document.querySelector('.sec-text');
    const localPlaintext = !e2eCryptoKey && isLocalHttpChat();
    label.textContent = e2eCryptoKey ? 'Encrypted payloads' : (localPlaintext ? 'Unencrypted chat' : 'Encryption unavailable');
    description.textContent = localPlaintext
      ? 'Unencrypted local chat. People on this network may read messages. Use HTTPS or the app for payload encryption.'
      : (e2eCryptoKey ? 'Browsers cannot prevent screenshots. Room admission credentials are shared with the host and transport relay.' : 'Encryption is unavailable. Use HTTPS or the native app to send messages.');
    sendBtn.disabled = !e2eCryptoKey && !localPlaintext;
  }

  async function sendMessage() {
    const text = messageInput.value.trim();
    if (!text || sendBtn.disabled || !ws || ws.readyState !== WebSocket.OPEN) return;

    if (e2eCryptoKey) {
      try {
        const enc = await encryptText(e2eCryptoKey, text);
        ws.send(JSON.stringify({
          type: 'message',
          text: '',
          e2e: true,
          ciphertext: enc.ciphertext,
          iv: enc.iv,
          alg: enc.alg,
        }));
      } catch (err) {
        document.querySelector('.sec-text').textContent = 'Encryption failed. Your message was not sent. Reconnect and try again.';
        return;
      }
    } else {
      if (!isLocalHttpChat()) return;
      ws.send(JSON.stringify({
        type: 'message',
        text: text,
      }));
    }

    messageInput.value = '';
    messageInput.style.height = 'auto';
    emitTyping(false);
  }

  sendBtn.addEventListener('click', sendMessage);

  messageInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });

  messageInput.addEventListener('input', () => {
    messageInput.style.height = 'auto';
    messageInput.style.height = `${Math.min(messageInput.scrollHeight, 120)}px`;
    emitTyping(true);
  });

  function emitTyping(isTyping) {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    clearTimeout(typingTimeout);
    ws.send(JSON.stringify({ type: 'typing', isTyping: isTyping }));
    if (isTyping) {
      typingTimeout = setTimeout(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'typing', isTyping: false }));
        }
      }, 2500);
    }
  }

  // 10. Self-Destruct Burn Screen
  function showBurnedScreen(reason) {
    if (isRoomBurned) return;
    isRoomBurned = true;

    clearInterval(countdownTimer);
    if (ws) {
      try { ws.close(); } catch (_) {}
      ws = null;
    }

    statMessages.textContent = messageCount;
    statFiles.textContent = fileCount;
    statParticipants.textContent = participantCount;

    chatFeed.textContent = '';
    burnedScreen.classList.remove('hidden');

    try {
      window.history.replaceState(null, '', '/');
    } catch (_) {}
  }

  // Helpers
  function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
  }

  function getFileBadge(filename) {
    const ext = (filename || '').split('.').pop().toUpperCase();
    return (ext && ext.length <= 4) ? ext : 'FILE';
  }

  // Initialize & Listeners
  const openAppBtn = document.getElementById('openAppBtn');
  if (openAppBtn) openAppBtn.addEventListener('click', openInNativeApp);

  const joinAppBtn = document.getElementById('joinAppBtn');
  if (joinAppBtn) joinAppBtn.addEventListener('click', openInNativeApp);

  checkNativeAppRedirect();
  checkRoomInfo();

})();
