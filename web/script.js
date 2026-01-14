const speedDisplay = document.getElementById('speed-display');
const analogGauge = document.getElementById('analog-gauge');
const locationDisplay = document.getElementById('location-display');
const limitInput = document.getElementById('limit-input');
const visualLimit = document.getElementById('visual-limit');
const limitSourceText = document.getElementById('limit-source-text');
const alarmThresholdText = document.getElementById('alarm-threshold-text');
const reportBtn = document.getElementById('report-btn');
// [修正] 指向側邊選單裡的按鈕 ID
const hudBtn = document.getElementById('drawer-hud-btn');
const minimapBtn = document.getElementById('minimap-btn');
const altitudeDisplay = document.getElementById('altitude-display');
const headingDisplay = document.getElementById('heading-display');

const voiceTextInput = document.getElementById('voice-text');
const toggleBtn = document.getElementById('toggle-btn');
const testTtsBtn = document.getElementById('test-tts-btn');
const btnMinus = document.getElementById('btn-minus');
const btnPlus = document.getElementById('btn-plus');
const clockEl = document.getElementById('clock');
const statusDiv = document.getElementById('status');
const autoLimitCheck = document.getElementById('auto-limit-check');
const autoLogCheck = document.getElementById('auto-log-check');
const drawer = document.getElementById('settings-drawer');
const overlay = document.getElementById('overlay');
const body = document.body;

const historyModal = document.getElementById('history-modal');
const historyListEl = document.getElementById('history-list');
const modalTitle = document.getElementById('modal-title');
const mapModal = document.getElementById('map-modal');
const helpModal = document.getElementById('help-modal');
const uploadHistoryModal = document.getElementById('upload-history-modal');
const uploadHistoryList = document.getElementById('upload-history-list');

const pipCanvas = document.getElementById('pip-canvas');
const pipCtx = pipCanvas.getContext('2d');
const pipVideo = document.getElementById('pip-video');

let watchId = null;
let wakeLock = null;
let lastSpeakTime = 0;
let lastBeepTime = 0;
let isMonitoring = false;
let lastOsmCheckTime = 0;
let lastAddressCheckTime = 0;
let isFirstFix = true;

let tripStartTime = null;
let tripMaxSpeed = 0;
let tripDistance = 0;
let currentTripPath = [];
let lastLat = null;
let lastLon = null;
let mapInstance = null;
let polylineLayer = null;
let currentMissingLat = null;
let currentMissingLon = null;

let miniMap = null;
let miniMapMarker = null;
let miniMapPolyline = null;
let miniMapPath = [];

let currentTheme = localStorage.getItem('speed_theme') || 'digital';
let currentGaugeTheme = localStorage.getItem('gauge_theme') || 'default';

const GAUGE_THEMES = {
    'default': { name: '經典綠', mainColor: '#0f0', tickColor: '#fff', faceColor: 'transparent', needleColor: '#0f0', textColor: '#0f0' },
    'sport': { name: '熱血紅', mainColor: '#f44336', tickColor: '#eee', faceColor: '#2b0000', needleColor: '#f44336', textColor: '#ffcdd2' },
    'cyber': { name: '未來藍', mainColor: '#00e5ff', tickColor: '#00e5ff', faceColor: '#001014', needleColor: '#fff', textColor: '#00e5ff' },
    'luxury': { name: '奢華金', mainColor: '#ffd700', tickColor: '#ffecb3', faceColor: '#1a1200', needleColor: '#ffd700', textColor: '#ffd700' }
};

const TOLERANCE = 38;
const PRE_WARNING_BUFFER = 5;
const synth = window.speechSynthesis;

window.addEventListener('load', () => {
    if (!localStorage.getItem('hasSeenHelp')) { showHelp(); localStorage.setItem('hasSeenHelp', 'true'); }
    // PWA disabled for dev
    // if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(()=>{});

    setTheme(currentTheme);
    initThemeSelector();
    drawGauge(0);
});

function initThemeSelector() {
    const list = document.getElementById('gauge-theme-list');
    if (!list) return;
    list.innerHTML = '';
    Object.keys(GAUGE_THEMES).forEach(key => {
        const theme = GAUGE_THEMES[key];
        const btn = document.createElement('button');
        btn.textContent = theme.name;
        btn.className = 'btn-set-speed'; // Reuse existing class for look
        btn.style.flex = '1 0 40%';
        btn.style.border = (currentGaugeTheme === key) ? `2px solid ${theme.mainColor}` : '1px solid #555';
        btn.style.color = theme.mainColor;
        btn.onclick = () => {
            currentGaugeTheme = key;
            localStorage.setItem('gauge_theme', key);
            initThemeSelector(); // Re-render to update active state
            drawGauge(parseInt(speedDisplay.textContent) || 0); // Redraw immediately
        };
        list.appendChild(btn);
    });
}

function updateClock() {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    clockEl.textContent = `${hours}:${minutes}`;
}
setInterval(updateClock, 1000);
updateClock();

const silentAudio = new Audio();
silentAudio.src = "data:audio/mp3;base64,SUQzBAAAAAABAFRYWFQAAAASAAADbWFqb3JfYnJhbmQAbXA0MgBUWFhUAAAAEQAAA21pbm9yX3ZlcnNpb24AMABUWFhUAAAAHAAAA2NvbXBhdGlibGVfYnJhbmRzAGlzb21tcDQyAFRTU0UAAAAPAAADTGF2ZjU3LjU2LjEwMAAAAAAAAAAAAAAA//uQZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWgAAAA0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQZAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQZAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQZAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQZAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQZAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==";
silentAudio.loop = true; silentAudio.volume = 0.01;

let beepAudio = new Audio('./sound.mp3');
function playCustomSound() {
    beepAudio.currentTime = 0;
    beepAudio.play().catch(e => console.log("Sound error", e));
}

testTtsBtn.addEventListener('click', () => { playCustomSound(); setTimeout(() => { speak(voiceTextInput.value || "測試語音"); }, 1000); });

window.toggleHud = function () {
    body.classList.toggle('hud-mode');
    if (drawer.classList.contains('open')) toggleMenu();
};

window.toggleMiniMap = function () {
    const el = document.getElementById('mini-map-overlay');
    const dashboard = document.querySelector('.dashboard');

    if (el.style.display === 'block') {
        el.style.display = 'none';
        minimapBtn.style.color = '#fff';
        dashboard.classList.remove('map-active');
    } else {
        el.style.display = 'block';
        minimapBtn.style.color = '#00e676';
        dashboard.classList.add('map-active');

        if (!miniMap) initMiniMap();
        else {
            setTimeout(() => { miniMap.invalidateSize(); }, 100);
        }
    }
};

window.setTheme = function (theme) {
    currentTheme = theme;
    localStorage.setItem('speed_theme', theme);

    if (theme === 'analog') {
        body.classList.add('theme-analog');
    } else {
        body.classList.remove('theme-analog');
    }
    if (drawer.classList.contains('open')) toggleMenu();
};

function drawGauge(speed) {
    const canvas = analogGauge;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    const cx = w / 2;
    const cy = h / 2;
    const r = w / 2 - 20;

    const theme = GAUGE_THEMES[currentGaugeTheme] || GAUGE_THEMES['default'];

    ctx.clearRect(0, 0, w, h);

    // Background Face
    if (theme.faceColor !== 'transparent') {
        ctx.beginPath();
        ctx.arc(cx, cy, r + 15, 0, 2 * Math.PI);
        ctx.fillStyle = theme.faceColor;
        ctx.fill();
    }

    let mainColor = theme.mainColor;
    let needleColor = theme.needleColor;
    let tickColor = theme.tickColor;

    // Safety Override
    if (body.classList.contains('danger')) { mainColor = '#fff'; needleColor = '#fff'; tickColor = '#fff'; }
    else if (body.classList.contains('warning')) { mainColor = '#000'; needleColor = '#000'; tickColor = '#333'; }

    ctx.beginPath();
    ctx.arc(cx, cy, r, 0.75 * Math.PI, 2.25 * Math.PI);
    ctx.lineWidth = 15;
    ctx.strokeStyle = '#333';
    ctx.stroke();

    ctx.fillStyle = '#aaa';
    ctx.font = 'bold 20px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    for (let i = 0; i <= 240; i += 20) {
        const angle = 0.75 * Math.PI + (i / 240) * (1.5 * Math.PI);
        const tx = cx + (r - 35) * Math.cos(angle);
        const ty = cy + (r - 35) * Math.sin(angle);
        const x1 = cx + (r - 10) * Math.cos(angle);
        const y1 = cy + (r - 10) * Math.sin(angle);
        const x2 = cx + r * Math.cos(angle);
        const y2 = cy + r * Math.sin(angle);
        ctx.beginPath();
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.lineWidth = 3;
        ctx.strokeStyle = tickColor;
        ctx.stroke();
        ctx.fillStyle = tickColor;
        ctx.fillText(i, tx, ty);
    }

    const displaySpeed = Math.min(speed, 240);
    const needleAngle = 0.75 * Math.PI + (displaySpeed / 240) * (1.5 * Math.PI);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + (r - 20) * Math.cos(needleAngle), cy + (r - 20) * Math.sin(needleAngle));
    ctx.lineWidth = 8;
    ctx.strokeStyle = needleColor;
    ctx.lineCap = 'round';
    ctx.shadowBlur = 10;
    ctx.shadowColor = needleColor;
    ctx.stroke();
    ctx.shadowBlur = 0;

    ctx.beginPath();
    ctx.arc(cx, cy, 10, 0, 2 * Math.PI);
    ctx.fillStyle = '#555';
    ctx.fill();

    ctx.fillStyle = mainColor;
    ctx.font = 'bold 40px Arial';
    ctx.fillText(Math.round(speed), cx, cy + 50);
    ctx.font = '16px Arial';
    ctx.fillStyle = theme.textColor || '#888';
    ctx.fillText('km/h', cx, cy + 80);
}

function initMiniMap() {
    // [修改 1] 將預設縮放改成 20 (原本是 18)
    miniMap = L.map('realtime-map', {
        zoomControl: false,
        attributionControl: false
    }).setView([25.0330, 121.5654], 20);

    // [修改 2] 設定 maxNativeZoom 與 maxZoom
    L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        maxNativeZoom: 19,  // 告訴系統：圖資原本最清楚只到 19 層
        maxZoom: 22         // 告訴系統：但允許你數位放大到 22 層 (看起來更近)
    }).addTo(miniMap);

    if (currentMissingLat && currentMissingLon) {
        updateMiniMap(currentMissingLat, currentMissingLon);
    }
}

function updateMiniMap(lat, lon) {
    if (!miniMap) return;
    const latlng = [lat, lon];
    if (!miniMapMarker) { miniMapMarker = L.circleMarker(latlng, { radius: 8, fillColor: '#2979ff', color: '#fff', weight: 2, fillOpacity: 1 }).addTo(miniMap); }
    else { miniMapMarker.setLatLng(latlng); }
    miniMapPath.push(latlng);
    if (miniMapPath.length > 500) miniMapPath.shift();
    if (!miniMapPolyline) { miniMapPolyline = L.polyline(miniMapPath, { color: '#00e676', weight: 3 }).addTo(miniMap); }
    else { miniMapPolyline.setLatLngs(miniMapPath); }
    miniMap.setView(latlng, 20); miniMap.invalidateSize();
}

window.toggleMenu = function () {
    drawer.classList.toggle('open');
    if (drawer.classList.contains('open')) overlay.style.display = 'block';
    else overlay.style.display = 'none';
};

window.showHelp = function () { if (drawer.classList.contains('open')) toggleMenu(); helpModal.classList.add('show'); }
window.closeHelp = function () { helpModal.classList.remove('show'); }

window.editCurrentLimit = function () {
    if (!currentMissingLat || !currentMissingLon) { alert("尚未定位，無法修改"); return; }
    let defaultVal = limitInput.value || "50";
    const input = prompt("修正此路段速限為：", defaultVal);
    if (input) {
        const newLimit = parseInt(input);
        if (!isNaN(newLimit)) {
            saveCustomLimit(currentMissingLat, currentMissingLon, newLimit);
            setLimit(newLimit);
            alert(`✅ 已修正為 ${newLimit} km/h，下次經過會自動套用。`);
        }
    }
};

window.quickMarkMissing = function () {
    if (!currentMissingLat || !currentMissingLon) { alert("尚未定位，無法標記"); return; }
    saveCustomLimit(currentMissingLat, currentMissingLon, null);
    reportBtn.textContent = "✅ 已標記"; reportBtn.style.background = "#4caf50";
    setTimeout(() => { reportBtn.textContent = "📍 標記缺漏"; reportBtn.style.background = "#ff9800"; reportBtn.style.display = 'none'; }, 2000);
    statusDiv.textContent = "已標記此處，請稍後補填速限";
};

function saveCustomLimit(lat, lon, limit) {
    let reports = JSON.parse(localStorage.getItem('osm_reports') || "[]");

    // 取得當前地址
    const currentAddress = locationDisplay.textContent.replace('📍 ', '');
    const currentRoadName = currentAddress.split(' ').pop(); // 取出路名 (如 "安民街")

    let foundIndex = -1;

    // 搜尋重複邏輯
    for (let i = 0; i < reports.length; i++) {
        const r = reports[i];
        const dist = getDistanceFromLatLonInKm(r.lat, r.lon, lat, lon);

        let isDuplicate = false;

        // 條件 1: 距離極近 (< 200m)，無論路名
        if (dist < 0.2) {
            isDuplicate = true;
        }
        // 條件 2: 同一條路名 且 距離 < 1km
        else if (currentRoadName && r.address && r.address.includes(currentRoadName) && dist < 1.0) {
            isDuplicate = true;
        }

        if (isDuplicate) {
            foundIndex = i;
            break;
        }
    }

    if (foundIndex !== -1) {
        // [更新] 找到重複，更新位置與時間
        if (limit !== undefined) {
            reports[foundIndex].limit = limit;
        }
        // 更新為最新位置與時間
        reports[foundIndex].lat = lat;
        reports[foundIndex].lon = lon;
        reports[foundIndex].date = new Date().toLocaleString('zh-TW');
        reports[foundIndex].address = currentAddress;

        // 將更新的項目移到最前面
        const updatedReport = reports.splice(foundIndex, 1)[0];
        reports.unshift(updatedReport);

    } else {
        // [新增] 無重複
        const newReport = { lat: lat, lon: lon, limit: limit, date: new Date().toLocaleString('zh-TW'), address: currentAddress };
        reports.unshift(newReport); // 直接加到最前面
    }

    if (reports.length > 100) reports = reports.slice(0, 100); // 修正長度限制邏輯
    localStorage.setItem('osm_reports', JSON.stringify(reports));
}

function findCustomLimit(lat, lon) {
    const reports = JSON.parse(localStorage.getItem('osm_reports') || "[]");
    for (let r of reports) {
        if (Math.abs(r.lat - lat) < 0.0005 && Math.abs(r.lon - lon) < 0.0005) return r.limit;
    }
    return undefined;
}

window.updateReportSpeed = function (index, speed) {
    let reports = JSON.parse(localStorage.getItem('osm_reports') || "[]");
    reports[index].limit = speed;
    localStorage.setItem('osm_reports', JSON.stringify(reports));
    showOsmReports();
};

function addToUploadHistory(report, noteId) {
    let history = JSON.parse(localStorage.getItem('osm_uploaded_history') || "[]");
    history.unshift({ ...report, uploadDate: new Date().toLocaleString('zh-TW'), noteId: noteId });
    if (history.length > 50) history.pop();
    localStorage.setItem('osm_uploaded_history', JSON.stringify(history));
}

window.uploadToOsm = function (index) {
    let reports = JSON.parse(localStorage.getItem('osm_reports') || "[]");
    const r = reports[index];
    if (!r || !r.limit) { alert("請先設定速限後再上傳"); return; }
    const btn = document.getElementById(`upload-btn-${index}`);
    if (btn) { btn.disabled = true; btn.textContent = "上傳中..."; }
    const text = `User reported maxspeed: ${r.limit} km/h (via SpeedTrap WebApp)`;
    const url = `https://api.openstreetmap.org/api/0.6/notes.json?lat=${r.lat}&lon=${r.lon}&text=${encodeURIComponent(text)}`;
    fetch(url, { method: 'POST' }).then(response => response.json()).then(data => {
        const noteId = data.properties.id; const noteUrl = `https://www.openstreetmap.org/note/${noteId}`;
        addToUploadHistory(r, noteId); deleteReport(index);
        if (confirm(`✅ 筆記上傳成功！(ID: ${noteId})\n已移至「上傳紀錄」。\n是否要前往 OSM 查看？`)) { window.open(noteUrl, '_blank'); }
    }).catch(err => {
        alert("❌ 上傳失敗\n請檢查網路或稍後再試。"); if (btn) { btn.disabled = false; btn.textContent = "☁️ 上傳 OSM 筆記"; } console.error(err);
    });
};

window.showUploadHistory = function () {
    if (drawer.classList.contains('open')) toggleMenu();
    const history = JSON.parse(localStorage.getItem('osm_uploaded_history') || "[]");
    uploadHistoryList.innerHTML = "";
    if (history.length === 0) { uploadHistoryList.innerHTML = `<div class="empty-msg">尚無上傳紀錄</div>`; } else {
        history.forEach((h) => {
            const noteUrl = `https://www.openstreetmap.org/note/${h.noteId}`;
            const item = document.createElement('div'); item.className = 'history-item';
            item.innerHTML = `<div class="h-date">上傳於: ${h.uploadDate}</div><div style="font-size:1.1rem; font-weight:bold;">${h.address || "未知路段"}</div><div class="h-stats"><span>回報速限: <span style="color:#0f0">${h.limit}</span></span></div><div style="margin-top:5px;"><a href="${noteUrl}" target="_blank" class="btn-link">🔗 查看 OSM 筆記 (#${h.noteId})</a></div>`;
            uploadHistoryList.appendChild(item);
        });
    }
    uploadHistoryModal.classList.add('show');
}
window.closeUploadHistory = function () { uploadHistoryModal.classList.remove('show'); }
window.clearUploadHistory = function () { if (confirm("確定清除所有上傳紀錄嗎？")) { localStorage.removeItem('osm_uploaded_history'); showUploadHistory(); } }

window.showOsmReports = function () {
    toggleMenu(); const reports = JSON.parse(localStorage.getItem('osm_reports') || "[]");
    modalTitle.textContent = "缺漏標記列表"; historyListEl.innerHTML = "";
    const clearBtn = document.getElementById('history-clear-btn');
    if (clearBtn) {
        clearBtn.style.display = 'inline-block';
        clearBtn.onclick = window.clearAllReports;
    }
    if (reports.length === 0) { historyListEl.innerHTML = `<div class="empty-msg">尚無標記紀錄</div>`; } else {
        reports.forEach((r, idx) => {
            const editLink = `https://www.openstreetmap.org/edit?editor=id#map=19/${r.lat}/${r.lon}`;
            const isPending = (r.limit === null);
            let speedControls = '', actionButtons = '';
            if (isPending) {
                speedControls = `<div style="margin-top:5px;"><span style="color:#ff9800; font-size:0.9rem;">快速設定: </span><button class="btn-set-speed" onclick="updateReportSpeed(${idx}, 30)">30</button><button class="btn-set-speed" onclick="updateReportSpeed(${idx}, 40)">40</button><button class="btn-set-speed" onclick="updateReportSpeed(${idx}, 50)">50</button><button class="btn-set-speed" onclick="updateReportSpeed(${idx}, 60)">60</button></div>`;
            } else {
                speedControls = `<span style="color:#0f0">已設定: ${r.limit} km/h</span>`;
                actionButtons = `<button id="upload-btn-${idx}" class="btn-upload" onclick="uploadToOsm(${idx})">☁️ 上傳 OSM 筆記</button>`;
            }
            const item = document.createElement('div'); item.className = 'history-item';
            item.innerHTML = `<div class="h-date">${r.date}</div><div style="font-size:1.1rem; font-weight:bold;">${r.address || "未知路段"}</div><div class="h-stats">${speedControls}</div><div style="margin-top:8px; border-top:1px solid #444; padding-top:10px;">${actionButtons}<a href="${editLink}" target="_blank" class="btn-link">🌍 開啟編輯器</a><button class="btn-link" style="background:#d32f2f; margin-left:10px;" onclick="deleteReport(${idx})">刪除</button></div>`;
            historyListEl.appendChild(item);
        });
    }
    historyModal.classList.add('show');
}

window.deleteReport = function (index) { let reports = JSON.parse(localStorage.getItem('osm_reports') || "[]"); reports.splice(index, 1); localStorage.setItem('osm_reports', JSON.stringify(reports)); showOsmReports(); }

window.clearAllReports = function () {
    if (confirm("⚠️ 確定要刪除所有「缺漏標記」嗎？\n此動作無法復原！")) {
        localStorage.removeItem('osm_reports');
        showOsmReports();
    }
};

window.showHistory = function () {
    toggleMenu();
    renderHistory();
    const clearBtn = document.getElementById('history-clear-btn');
    if (clearBtn) {
        clearBtn.style.display = 'inline-block';
        clearBtn.onclick = window.clearHistory;
    }
    historyModal.classList.add('show');
};

window.deleteTrip = function (index) {
    if (!confirm("確定要刪除這筆紀錄嗎？")) return;
    let records = JSON.parse(localStorage.getItem('trip_records') || "[]");
    records.splice(index, 1);
    localStorage.setItem('trip_records', JSON.stringify(records));
    renderHistory();
};
window.closeHistory = function () { historyModal.classList.remove('show'); };
window.clearHistory = function () { if (confirm('確定要刪除所有紀錄嗎？')) { localStorage.removeItem('trip_records'); renderHistory(); } };

window.downloadGpx = function (index) {
    const records = JSON.parse(localStorage.getItem('trip_records') || "[]"); const record = records[index];
    if (!record || !record.path || record.path.length === 0) { alert("無軌跡資料"); return; }
    let gpx = `<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="SpeedTrapWebApp"><trk><name>Trip on ${record.date}</name><trkseg>`;
    record.path.forEach(pt => { gpx += `\n<trkpt lat="${pt[0]}" lon="${pt[1]}"></trkpt>`; });
    gpx += `\n</trkseg></trk></gpx>`;
    const blob = new Blob([gpx], { type: 'application/gpx+xml' }); const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = `trip_${record.date.replace(/[\/:\s]/g, '_')}.gpx`;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
};

window.showMap = function (index) {
    const records = JSON.parse(localStorage.getItem('trip_records') || "[]"); const record = records[index];
    if (!record || !record.path || record.path.length === 0) { alert("無軌跡資料"); return; }
    mapModal.classList.add('show');
    if (!mapInstance) { mapInstance = L.map('trip-map'); L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', { attribution: '&copy; OpenStreetMap &copy; CARTO', subdomains: 'abcd', maxZoom: 19 }).addTo(mapInstance); }
    if (polylineLayer) mapInstance.removeLayer(polylineLayer);
    setTimeout(() => { mapInstance.invalidateSize(); polylineLayer = L.polyline(record.path, { color: '#0f0', weight: 4, opacity: 0.8 }).addTo(mapInstance); mapInstance.fitBounds(polylineLayer.getBounds(), { padding: [50, 50] }); }, 100);
};
window.closeMap = function () { mapModal.classList.remove('show'); };

function saveTrip() {
    if (!tripStartTime) return; const now = new Date(); const durationMs = now - tripStartTime; if (durationMs < 10000 && tripDistance < 0.1) return;
    const hours = durationMs / 1000 / 3600; const avgSpeed = hours > 0 ? (tripDistance / hours) : 0;
    const record = { date: tripStartTime.toLocaleString('zh-TW'), duration: (durationMs / 1000 / 60).toFixed(1) + " 分", distance: tripDistance.toFixed(1) + " km", maxSpeed: Math.round(tripMaxSpeed) + " km/h", avgSpeed: Math.round(avgSpeed) + " km/h", path: currentTripPath };
    let records = JSON.parse(localStorage.getItem('trip_records') || "[]"); records.unshift(record); if (records.length > 20) records.pop();
    localStorage.setItem('trip_records', JSON.stringify(records)); alert(`🏁 行程結束\n里程: ${record.distance}\n時間: ${record.duration}`);
}

function renderHistory() {
    modalTitle.textContent = "行車紀錄"; const records = JSON.parse(localStorage.getItem('trip_records') || "[]"); historyListEl.innerHTML = "";
    if (records.length === 0) { historyListEl.innerHTML = `<div class="empty-msg">尚無紀錄</div>`; return; }
    records.forEach((r, index) => {
        const item = document.createElement('div'); item.className = 'history-item';
        item.innerHTML = `<div class="h-date">${r.date} - ${r.duration}</div><div class="h-stats"><div class="h-stat-box"><span class="h-label">極速</span><span class="h-val max">${r.maxSpeed}</span></div><div class="h-stat-box"><span class="h-label">平均</span><span class="h-val">${r.avgSpeed}</span></div><div class="h-stat-box"><span class="h-label">里程</span><span class="h-val">${r.distance}</span></div></div><div style="margin-top:10px;"><button class="btn-link" style="margin-top:5px;background:#007aff;" onclick="showMap(${index})">🗺️ 查看地圖</button><button class="btn-link btn-gpx" onclick="downloadGpx(${index})">💾 下載 GPX</button><button class="btn-link" style="background:#d32f2f; margin-left:10px;" onclick="deleteTrip(${index})">刪除</button></div>`;
        historyListEl.appendChild(item);
    });
}

window.setLimit = function (val) {
    limitInput.value = val;
    let hasLocal = false;
    if (currentMissingLat && currentMissingLon) { const saved = findCustomLimit(currentMissingLat, currentMissingLon); if (saved !== undefined && saved !== null) { hasLocal = true; } }
    updateVisualSign(val, false, false, false, hasLocal); updateThresholdDisplay(); updatePiP(0, val);
};
btnMinus.addEventListener('click', () => setLimit(Math.max(0, (parseInt(limitInput.value) || 0) - 10)));
btnPlus.addEventListener('click', () => setLimit((parseInt(limitInput.value) || 0) + 10));

toggleBtn.addEventListener('click', () => {
    silentAudio.play().catch(() => { });
    // 手機語音修復：強制解鎖 TTS
    speak(" ");
    if (!isMonitoring) startActiveMonitoring();
    else stopActiveMonitoring();
});

limitInput.addEventListener('input', () => { updateVisualSign(limitInput.value, false); updateThresholdDisplay(); updatePiP(0, limitInput.value); });

function updateThresholdDisplay() { const base = parseInt(limitInput.value) || 0; alarmThresholdText.textContent = base + TOLERANCE; }
async function requestWakeLock() { try { wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }
document.addEventListener('visibilitychange', async () => { if (wakeLock !== null && document.visibilityState === 'visible') await requestWakeLock(); });

function initGPS() {
    if (navigator.geolocation) {
        statusDiv.textContent = "定位中..."; locationDisplay.textContent = "定位中...";
        watchId = navigator.geolocation.watchPosition(updatePosition, handleError, { enableHighAccuracy: true, timeout: 5000, maximumAge: 0 });
    } else { alert("此瀏覽器不支援 GPS"); }
}
initGPS();

async function startActiveMonitoring() {
    silentAudio.play().catch(() => { }); playCustomSound();
    setTimeout(() => { speak("偵測開始"); }, 800);
    await requestWakeLock();
    tripStartTime = new Date(); tripMaxSpeed = 0; tripDistance = 0; currentTripPath = []; lastLat = null; lastLon = null;
    isMonitoring = true; toggleBtn.textContent = "🛑 停止偵測"; toggleBtn.classList.add('active'); statusDiv.textContent = "⚠️ 監控中";
}

function stopActiveMonitoring() {
    if (wakeLock !== null) wakeLock.release(); silentAudio.pause(); saveTrip();
    isMonitoring = false; toggleBtn.textContent = "🚀 啟動偵測"; toggleBtn.classList.remove('active');
    body.classList.remove('danger'); body.classList.remove('warning'); statusDiv.textContent = "已暫停";

    miniMapPath = [];
    if (miniMapPolyline) { miniMapPolyline.setLatLngs([]); }
}

function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    const R = 6371; const dLat = (lat2 - lat1) * (Math.PI / 180); const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

function updatePosition(position) {
    const lat = position.coords.latitude; const lon = position.coords.longitude;
    let speedMps = position.coords.speed; if (speedMps === null || speedMps < 0) speedMps = 0;
    const speedKmh = speedMps * 3.6;

    if (position.coords.altitude) altitudeDisplay.textContent = `Alt: ${Math.round(position.coords.altitude)}m`;
    if (position.coords.heading) {
        const deg = position.coords.heading;
        const dirs = ["北", "東北", "東", "東南", "南", "西南", "西", "西北"];
        const idx = Math.round(deg / 45) % 8;
        headingDisplay.textContent = `${dirs[idx]} (${Math.round(deg)}°)`;
    }

    currentMissingLat = lat; currentMissingLon = lon;

    // 更新小地圖
    if (document.getElementById('mini-map-overlay').style.display === 'block') {
        updateMiniMap(lat, lon);
    }

    if (isMonitoring) {
        if (lastLat !== null) {
            const dist = getDistanceFromLatLonInKm(lastLat, lastLon, lat, lon);
            if (speedKmh > 2 && dist > 0.0005 && dist < 0.2) tripDistance += dist;
            if (dist > 0.01) currentTripPath.push([lat, lon]);
        } else currentTripPath.push([lat, lon]);
        if (speedKmh > tripMaxSpeed) tripMaxSpeed = speedKmh;
        lastLat = lat; lastLon = lon;
    }

    speedDisplay.innerHTML = `${Math.round(speedKmh)}`;
    if (currentTheme === 'analog') drawGauge(speedKmh); // 更新指針

    const now = Date.now();
    const overpassServers = ["https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass.kumi.systems/api/interpreter"];

    if (autoLimitCheck.checked && ((now - lastOsmCheckTime > 15000 && speedKmh > 10) || isFirstFix)) {
        const savedLimit = findCustomLimit(lat, lon);
        if (savedLimit !== undefined) {
            if (savedLimit !== null) { limitInput.value = savedLimit; updateVisualSign(savedLimit, false, true); updateThresholdDisplay(); } else { updateVisualSign(null, true); }
        } else {
            (async () => {
                let success = false;
                const query = `[out:json];way[maxspeed](around:20,${lat},${lon});out tags;`;
                for (const server of overpassServers) {
                    if (success) break;
                    try {
                        const controller = new AbortController(); const timeoutId = setTimeout(() => controller.abort(), 3000);
                        const response = await fetch(`${server}?data=${encodeURIComponent(query)}`, { signal: controller.signal });
                        clearTimeout(timeoutId); if (!response.ok) throw new Error("Server busy");
                        const data = await response.json();
                        if (data.elements && data.elements.length > 0) {
                            // Smart Selection Logic
                            let bestLimit = 0;
                            const roads = data.elements.map(e => parseInt(e.tags.maxspeed)).filter(L => !isNaN(L));

                            if (roads.length > 0) {
                                if (speedKmh > 60) {
                                    // High Speed Mode: Prioritize highest limit (Highway > Ramp/Service)
                                    bestLimit = Math.max(...roads);
                                } else {
                                    // Low Speed Mode: Default to nearest (first result usually)
                                    // Or nearest to current speed? Let's stick to first for now but filter weird zeros
                                    bestLimit = roads[0];
                                }
                            }

                            if (bestLimit > 0) {
                                limitInput.value = bestLimit;
                                updateVisualSign(bestLimit, true);
                                updateThresholdDisplay();
                                updatePiP(0, bestLimit);
                                success = true;
                            }
                        }
                    } catch (e) { console.warn("Switching server..."); }
                }
                if (!success) setDefaultLimit(lat, lon);
            })();
        }
        lastOsmCheckTime = now; isFirstFix = false;
    }
    if (now - lastAddressCheckTime > 15000) { fetchAddress(lat, lon); lastAddressCheckTime = now; }
    checkOverSpeed(speedKmh); updatePiP(speedKmh, limitInput.value);
}

function checkOverSpeed(currentSpeed) {

    // Auto-hide Controls Logic
    const controls = document.querySelector('.primary-controls');
    if (isMonitoring && currentSpeed > 10) {
        if (controls) controls.classList.add('dock-hidden');
        body.classList.add('maximized-mode');
    } else if (currentSpeed < 8) { // Hysteresis
        if (controls) controls.classList.remove('dock-hidden');
        body.classList.remove('maximized-mode');
    }

    if (!isMonitoring) {
        body.classList.remove('danger', 'warning', 'maximized-mode');
        if (controls) controls.classList.remove('dock-hidden'); // Always show when stopped
        return;
    }
    const baseLimit = parseFloat(limitInput.value);
    const alarmTrigger = baseLimit + TOLERANCE;
    const preWarningStart = alarmTrigger - PRE_WARNING_BUFFER;
    const now = Date.now();
    if (currentSpeed > alarmTrigger) {
        body.classList.remove('warning'); body.classList.add('danger');
        if (now - lastSpeakTime > 3000) { playCustomSound(); setTimeout(() => speak(voiceTextInput.value), 1000); lastSpeakTime = now; }
    } else if (currentSpeed > preWarningStart) {
        body.classList.remove('danger'); body.classList.add('warning');
        if (now - lastBeepTime > 1000) { playCustomSound(); lastBeepTime = now; }
    } else { body.classList.remove('danger', 'warning'); }
}

async function fetchAddress(lat, lon) {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&zoom=18&addressdetails=1&accept-language=zh-TW`;
    try {
        const response = await fetch(url); const data = await response.json();
        if (data && data.address) {
            const road = data.address.road || ""; const suburb = data.address.suburb || data.address.city_district || ""; const city = data.address.city || "";
            locationDisplay.textContent = road ? `${suburb} ${road}` : `${city} ${suburb}`;
        }
    } catch (err) { }
}

function setDefaultLimit(lat, lon) {
    const defaultVal = 50; limitInput.value = defaultVal; updateVisualSign(defaultVal, true, false, true);
    updateThresholdDisplay(); updatePiP(0, defaultVal);
    if (autoLogCheck.checked && lat && lon) { saveCustomLimit(lat, lon, null); }
}

function updateVisualSign(val, isAuto, isCustom = false, isDefault = false, hasLocalOverride = false) {
    if (val && val > 0) {
        visualLimit.textContent = val; visualLimit.classList.remove('unknown');
        if (isDefault) {
            limitSourceText.innerHTML = "⚠️ 預設 (無資)"; limitSourceText.style.color = "#ff9800"; reportBtn.style.display = 'block';
        } else {
            reportBtn.style.display = 'none';
            if (isCustom) {
                limitSourceText.innerHTML = "📝 本地記憶 (點擊修改)"; limitSourceText.style.color = "#ff9800";
            } else {
                if (hasLocalOverride) { limitSourceText.innerHTML = "手動設定<br><span style='color:#ff9800;font-size:0.7rem;'>已有📝 本地記憶<br>(點擊圖示修改)</span>"; limitSourceText.style.color = "#aaa"; }
                else { limitSourceText.innerHTML = isAuto ? "OSM 自動" : "手動設定"; limitSourceText.style.color = isAuto ? "#4caf50" : "#aaa"; }
            }
        }
    } else {
        visualLimit.textContent = "?"; visualLimit.classList.add('unknown'); limitSourceText.innerHTML = "⚠️ 無速限資料"; limitSourceText.style.color = "#ff3b30"; reportBtn.style.display = 'block';
    }
}

// [手機語音修復] 
function speak(text) {
    if (!synth) return;
    synth.cancel(); // 重要：先取消之前的，避免卡住
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'zh-TW';
    u.rate = 1.0;

    // 強制抓取中文語音 (修正部分手機預設英文)
    const voices = synth.getVoices();
    const zhVoice = voices.find(v => v.lang.includes('zh-TW') || v.lang.includes('zh'));
    if (zhVoice) u.voice = zhVoice;

    synth.speak(u);
}

function handleError(error) { statusDiv.textContent = "❌ GPS 訊號遺失"; locationDisplay.textContent = "GPS 遺失"; }

// PiP Logic
function updatePiP(currentSpeed, limit) {
    pipCtx.fillStyle = '#000000'; pipCtx.fillRect(0, 0, 512, 512);
    const baseLimit = parseInt(limit) || 0;
    let bgColor = '#000000';
    if (isMonitoring) {
        if (currentSpeed > baseLimit + TOLERANCE) bgColor = '#b71c1c';
        else if (currentSpeed > baseLimit + TOLERANCE - PRE_WARNING_BUFFER) bgColor = '#fbc02d';
    }
    if (bgColor !== '#000000') { pipCtx.fillStyle = bgColor; pipCtx.fillRect(0, 0, 512, 512); }
    pipCtx.fillStyle = (bgColor === '#b71c1c') ? '#fff' : (bgColor === '#fbc02d' ? '#000' : '#0f0');
    pipCtx.font = 'bold 250px Arial'; pipCtx.textAlign = 'center'; pipCtx.textBaseline = 'middle';
    pipCtx.fillText(Math.round(currentSpeed), 256, 200);
    pipCtx.beginPath(); pipCtx.arc(256, 400, 70, 0, 2 * Math.PI); pipCtx.fillStyle = '#fff'; pipCtx.fill();
    pipCtx.lineWidth = 10; pipCtx.strokeStyle = '#cc0000'; pipCtx.stroke();
    pipCtx.fillStyle = '#000'; pipCtx.font = 'bold 60px Arial'; pipCtx.fillText(baseLimit, 256, 403);
}