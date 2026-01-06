// sw.js - 自我毀滅版
self.addEventListener('install', (e) => {
    // 強制進入激活狀態
    self.skipWaiting();
});

self.addEventListener('activate', (e) => {
    e.waitUntil(
        // 1. 刪除所有快取
        caches.keys().then((keyList) => {
            return Promise.all(keyList.map((key) => {
                return caches.delete(key);
            }));
        }).then(() => {
            // 2. 告訴所有客戶端(分頁)立刻接管
            return self.clients.claim();
        }).then(() => {
            // 3. 註銷自己 (自殺)
            self.registration.unregister().then(() => {
                console.log('Service Worker 已自我毀滅並清除快取');
            });
        })
    );
});