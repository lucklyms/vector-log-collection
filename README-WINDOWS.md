# Vector Agent for Windows

Windows 版本的 Vector Agent 安裝指南，自動收集 Windows 系統日誌、IIS 日誌並回傳到中央伺服器。

## 快速安裝

### 方法 1：一鍵安裝（推薦）

以**系統管理員身分**開啟 PowerShell，執行：

```powershell
# 允許執行遠端腳本
Set-ExecutionPolicy Bypass -Scope Process -Force

# 下載並執行安裝腳本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent-windows.ps1" -OutFile "$env:TEMP\install-vector.ps1"
& "$env:TEMP\install-vector.ps1"
```

執行後會詢問中央伺服器 IP。

### 方法 2：指定伺服器 IP 直接安裝

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent-windows.ps1" -OutFile "$env:TEMP\install-vector.ps1"
& "$env:TEMP\install-vector.ps1" -VectorServer "192.168.1.100"
```

### 方法 3：下載後安裝

1. 下載腳本：https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent-windows.ps1
2. 右鍵點擊 PowerShell → **以系統管理員身分執行**
3. 執行：
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-agent-windows.ps1
```

## 收集的日誌類型

| 類型 | 來源 | 說明 |
|------|------|------|
| Windows 系統日誌 | System Event Log | 系統事件、硬體、驅動程式 |
| Windows 應用程式日誌 | Application Event Log | 應用程式錯誤和事件 |
| Windows 安全日誌 | Security Event Log | 登入、權限、安全審核 |
| IIS 日誌 | C:\inetpub\logs\LogFiles | IIS Web 伺服器日誌 |
| 應用程式日誌 | C:\logs, C:\app\logs | 自定義應用程式日誌 |

## 服務管理

### 查看服務狀態
```powershell
Get-Service Vector
```

### 啟動服務
```powershell
Start-Service Vector
```

### 停止服務
```powershell
Stop-Service Vector
```

### 重啟服務
```powershell
Restart-Service Vector
```

### 查看服務詳細資訊
```powershell
Get-Service Vector | Format-List *
```

### 設定開機自動啟動
```powershell
Set-Service -Name Vector -StartupType Automatic
```

## 配置檔位置

- 安裝路徑：`C:\Program Files\Vector\`
- 配置檔：`C:\Program Files\Vector\config\vector.toml`
- 本地日誌備份：`C:\ProgramData\Vector\logs\`

## 自定義配置

編輯配置檔：
```powershell
notepad "C:\Program Files\Vector\config\vector.toml"
```

### 新增自定義日誌路徑

在配置檔中添加：

```toml
[sources.custom_app]
  type = "file"
  include = ["D:/MyApp/logs/**/*.log"]
  read_from = "beginning"
```

然後重啟服務：
```powershell
Restart-Service Vector
```

### 收集特定 Windows Event Log

```toml
[sources.custom_event]
  type = "windows_event_log"
  log_name = "YourCustomLog"
```

### 調整批次發送設定

```toml
[sinks.send_to_central]
  batch.max_bytes = 5242880  # 5MB
  batch.timeout_secs = 10
```

## IIS 日誌設定

Vector 會自動收集 IIS 日誌，預設路徑：
- `C:\inetpub\logs\LogFiles\**\*.log`

### 確認 IIS 日誌格式

1. 開啟 **IIS 管理員**
2. 選擇站台 → **日誌**
3. 建議使用 **W3C** 格式
4. 確保日誌路徑為預設位置

### 自定義 IIS 日誌路徑

如果 IIS 日誌在其他位置，修改配置：

```toml
[sources.iis_logs]
  include = ["D:/IISLogs/**/*.log"]
```

## 防火牆設定

安裝腳本會自動設定防火牆規則。如需手動設定：

```powershell
# 允許 Vector 連線到中央伺服器
New-NetFirewallRule -DisplayName "Vector Agent Outbound" `
  -Direction Outbound `
  -Action Allow `
  -Protocol TCP `
  -RemotePort 8080,5601,8686
```

## 測試日誌發送

### 發送測試 Windows Event
```powershell
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Information -Message "測試日誌"
```

### 使用 PowerShell 直接發送到 Vector
```powershell
$log = @{
    level = "info"
    message = "來自 Windows PowerShell 的測試"
    hostname = $env:COMPUTERNAME
    timestamp = (Get-Date).ToString("o")
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://192.168.1.100:8080" -Method Post -Body $log -ContentType "application/json"
```

### 建立測試日誌檔案
```powershell
"Test log entry $(Get-Date)" | Out-File -Append "C:\logs\test.log"
```

## 查看本地日誌備份

```powershell
# 查看今天的備份
Get-Content "C:\ProgramData\Vector\logs\backup-$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 50

# 即時監看
Get-Content "C:\ProgramData\Vector\logs\backup-$(Get-Date -Format 'yyyy-MM-dd').log" -Wait -Tail 10
```

## 故障排除

### 服務無法啟動

1. 檢查配置檔語法：
```powershell
& "C:\Program Files\Vector\vector.exe" validate --config "C:\Program Files\Vector\config\vector.toml"
```

2. 查看 Windows 事件檢視器：
   - 開始 → 事件檢視器 → Windows 記錄檔 → 應用程式
   - 搜尋 "Vector" 相關事件

3. 查看本地日誌：
```powershell
Get-Content "C:\ProgramData\Vector\logs\*.log" -Tail 100
```

### 無法連接到中央伺服器

1. 測試網路連接：
```powershell
Test-NetConnection -ComputerName 192.168.1.100 -Port 8080
```

2. 檢查防火牆：
```powershell
Get-NetFirewallRule -DisplayName "*Vector*"
```

3. 測試 HTTP 連接：
```powershell
Invoke-WebRequest -Uri "http://192.168.1.100:8686/health"
```

### 日誌未出現在中央伺服器

1. 確認服務正在運行：
```powershell
Get-Service Vector
```

2. 檢查本地備份是否有日誌：
```powershell
Get-ChildItem "C:\ProgramData\Vector\logs\"
```

3. 重啟服務：
```powershell
Restart-Service Vector
```

### IIS 日誌未收集

1. 確認 IIS 日誌路徑：
```powershell
Get-ChildItem "C:\inetpub\logs\LogFiles\" -Recurse
```

2. 檢查 Vector 是否有讀取權限
3. 修改配置檔中的路徑

## 完全移除

```powershell
# 停止並刪除服務
Stop-Service Vector
& "C:\Program Files\Vector\nssm.exe" remove Vector confirm

# 刪除安裝檔案
Remove-Item "C:\Program Files\Vector" -Recurse -Force
Remove-Item "C:\ProgramData\Vector" -Recurse -Force

# 刪除防火牆規則
Remove-NetFirewallRule -DisplayName "Vector Agent Outbound"
```

## 批次部署（多台 Windows 伺服器）

### 使用 PowerShell Remoting

在管理機器上執行：

```powershell
$servers = @("server1", "server2", "server3")
$vectorServer = "192.168.1.100"

foreach ($server in $servers) {
    Invoke-Command -ComputerName $server -ScriptBlock {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent-windows.ps1" -OutFile "$env:TEMP\install-vector.ps1"
        & "$env:TEMP\install-vector.ps1" -VectorServer $using:vectorServer
    }
}
```

### 使用 Group Policy (GPO)

1. 下載 `install-agent-windows.ps1` 到共享資料夾
2. 建立 GPO：電腦設定 → 原則 → Windows 設定 → 指令碼 → 啟動
3. 新增 PowerShell 指令碼

### 使用 SCCM/Intune

建立應用程式部署，執行：
```powershell
powershell.exe -ExecutionPolicy Bypass -File install-agent-windows.ps1 -VectorServer "192.168.1.100"
```

## 效能調優

### 減少磁碟 I/O

編輯配置檔，關閉本地備份：

```toml
# 註解掉本地備份
# [sinks.local_backup]
#   type = "file"
#   ...
```

### 減少 CPU 使用

```toml
[sinks.send_to_central]
  batch.timeout_secs = 30  # 增加批次間隔
```

### 限制記憶體使用

```toml
[sinks.send_to_central]
  buffer.max_size = 104857600  # 100MB
```

## 監控

### 查看 Vector 效能計數器

```powershell
Get-Counter "\Process(vector)\% Processor Time"
Get-Counter "\Process(vector)\Working Set"
```

### 建立效能監控

1. 開啟 **效能監視器** (perfmon)
2. 新增計數器：
   - Process → vector → % Processor Time
   - Process → vector → Working Set
   - Network Interface → Bytes Sent/sec

## 安全性建議

1. 使用 HTTPS 連接（需中央伺服器支援）
2. 限制服務帳戶權限
3. 定期更新 Vector 版本
4. 審核日誌存取權限
5. 加密敏感日誌內容

## 支援的 Windows 版本

- ✅ Windows Server 2016/2019/2022
- ✅ Windows 10/11
- ✅ 需要 .NET Framework 4.7.2 或更新版本
