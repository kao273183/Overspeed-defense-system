# iOS Live Activities 設定指南

為了啟用「動態島」與「鎖定畫面」的即時時速顯示，您需要手動在 Xcode 中進行一些設定。請按照以下步驟操作：

### 步驟 1：新增 Widget Extension
1.  在 Mac 上打開終端機，執行 `open ios/Runner.xcworkspace` 打開 Xcode 專案。
2.  在 Xcode 上方選單點選 **File** > **New** > **Target...**。
3.  搜尋並選擇 **Widget Extension**，點選 **Next**。
4.  **Product Name** 輸入：`SpeedDefenseWidget`。
5.  **Include Configuration App Intent**：**不要勾選**。
6.  點選 **Finish**。
7.  如果有跳出詢問 "Activate scheme?"，點選 **Activate**。

### 步驟 2：複製 Swift 程式碼
Xcode 左側檔案列表會出現 `SpeedDefenseWidget` 資料夾。

1.  **刪除** 資料夾內自動產生的 `.swift` 檔案 (例如 `SpeedDefenseWidget.swift` 等)。
2.  將專案中 `native_setup` 資料夾內的兩個檔案拖曳進去 Xcode 的 `SpeedDefenseWidget` 資料夾中 (記得勾選 "Copy items if needed")：
    *   `SpeedDefenseLiveActivity.swift`
    *   `SpeedDefenseWidgetBundle.swift`
    
    *(或者直接打開這兩個檔案，把內容複製貼上到 Xcode 裡對應的新檔案中)*

***

### 步驟 3：設定 App Groups (關鍵步驟！)
為了讓主程式跟 Widget 分享數據，必須開啟 App Groups。

**對於主程式 (Runner):**
1.  點選左側專案根目錄 (藍色 icon `Runner`)。
2.  選擇 **TARGETS** 下的 `Runner`。
3.  點選上方 **Signing & Capabilities** 分頁。
4.  點選左上角 **+ Capability**，搜尋 **App Groups** 並加入。
5.  在 App Groups 區塊，點選 **+**，輸入：`group.com.example.speedDefenseSystem` (這必須跟 `Info.plist` 或程式碼裡一致，建議自訂)。
    *   *注意：如果您的 Bundle ID 是 `com.minikao.speed`, 建議 Group ID 用 `group.com.minikao.speed`。請記得回報給我修改程式碼裡的 ID。* (目前預設用 `group.com.example.speedDefenseSystem`)

**對於 Widget (SpeedDefenseWidget):**
1.  同樣在 **TARGETS** 下選擇 `SpeedDefenseWidget`。
2.  點選 **Signing & Capabilities**。
3.  同樣加入 **App Groups**。
4.  **勾選** 剛剛在 Runner 建立的同一個 Group ID (例如 `group.com.example.speedDefenseSystem`)。

***

### 步驟 4：修改 Info.plist
1.  在 `Runner` 的 `Info.plist` (通常在 `ios/Runner/Info.plist`)：
    *   確認是否有 `NSSupportsLiveActivities` 設為 `YES` (我已經透過套件幫您加了，若無請手動加)。
2.  在 `SpeedDefenseWidget` 的 `Info.plist` (在 `SpeedDefenseWidget` 資料夾下)：
    *   點選右鍵 > **Add Row**。
    *   Key: `NSSupportsLiveActivities`
    *   Type: `Boolean`
    *   Value: `YES`

***

### 步驟 5：完成
關閉 Xcode，回到終端機重新執行：
```bash
flutter run
```
現在開啟「背景子母畫面 (PiP)」開關，並開始監控，縮小 App 後，您的動態島應該就會顯示時速了！
