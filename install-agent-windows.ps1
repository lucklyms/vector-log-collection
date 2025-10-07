# Vector Agent for Windows - 自動安裝腳本
# 需要以管理員權限執行

param(
    [string]$VectorServer = ""
)

Write-Host "=== Vector Agent Windows 安裝腳本 ===" -ForegroundColor Green
Write-Host ""

# 檢查管理員權限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "錯誤：請以管理員權限執行此腳本" -ForegroundColor Red
    Write-Host "右鍵點擊 PowerShell -> 以系統管理員身分執行" -ForegroundColor Yellow
    exit 1
}

# 詢問 Vector 伺服器 IP
if ([string]::IsNullOrEmpty($VectorServer)) {
    $VectorServer = Read-Host "請輸入 Vector 中央伺服器 IP"
}

if ([string]::IsNullOrEmpty($VectorServer)) {
    Write-Host "錯誤：必須提供 Vector 伺服器 IP" -ForegroundColor Red
    exit 1
}

Write-Host "Vector 中央伺服器: $VectorServer" -ForegroundColor Cyan
Write-Host ""

# 測試連接
Write-Host "步驟 1: 測試連接到 Vector 伺服器..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://${VectorServer}:8686/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "✓ Vector 伺服器連接成功" -ForegroundColor Green
} catch {
    Write-Host "⚠ 警告：無法連接到 Vector 伺服器，但繼續安裝" -ForegroundColor Yellow
}

# 下載 Vector
Write-Host ""
Write-Host "步驟 2: 下載 Vector..." -ForegroundColor Yellow

$vectorVersion = "0.34.1"
$downloadUrl = "https://packages.timber.io/vector/$vectorVersion/vector-$vectorVersion-x86_64-pc-windows-msvc.zip"
$downloadPath = "$env:TEMP\vector.zip"
$installPath = "C:\Program Files\Vector"

try {
    Write-Host "下載中: $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
    Write-Host "✓ 下載完成" -ForegroundColor Green
} catch {
    Write-Host "✗ 下載失敗: $_" -ForegroundColor Red
    exit 1
}

# 解壓縮
Write-Host ""
Write-Host "步驟 3: 安裝 Vector..." -ForegroundColor Yellow

if (Test-Path $installPath) {
    Write-Host "移除舊版本..."
    Remove-Item -Path $installPath -Recurse -Force
}

New-Item -ItemType Directory -Path $installPath -Force | Out-Null
Expand-Archive -Path $downloadPath -DestinationPath $installPath -Force

# 找到 vector.exe
$vectorExe = Get-ChildItem -Path $installPath -Filter "vector.exe" -Recurse | Select-Object -First 1
if ($vectorExe) {
    $vectorBinPath = $vectorExe.DirectoryName
    Copy-Item -Path "$vectorBinPath\*" -Destination $installPath -Recurse -Force
    Write-Host "✓ Vector 安裝完成: $installPath\vector.exe" -ForegroundColor Green
} else {
    Write-Host "✗ 找不到 vector.exe" -ForegroundColor Red
    exit 1
}

# 建立配置檔
Write-Host ""
Write-Host "步驟 4: 建立配置檔..." -ForegroundColor Yellow

$configPath = "$installPath\config"
New-Item -ItemType Directory -Path $configPath -Force | Out-Null

$configContent = @"
# Vector Agent 配置 - Windows 版本
# 主機名稱: $env:COMPUTERNAME

# ==================== 數據源 ====================

# Windows Event Log - 系統日誌
[sources.windows_system]
  type = "windows_event_log"
  log_name = "System"

# Windows Event Log - 應用程式日誌
[sources.windows_application]
  type = "windows_event_log"
  log_name = "Application"

# Windows Event Log - 安全日誌
[sources.windows_security]
  type = "windows_event_log"
  log_name = "Security"

# IIS 日誌
[sources.iis_logs]
  type = "file"
  include = ["C:/inetpub/logs/LogFiles/**/*.log"]
  read_from = "beginning"
  ignore_older_secs = 86400

# 應用程式日誌
[sources.app_logs]
  type = "file"
  include = ["C:/logs/**/*.log", "C:/app/logs/**/*.log"]
  read_from = "beginning"
  ignore_older_secs = 86400

# ==================== 數據轉換 ====================

# 添加主機資訊
[transforms.add_host_info]
  type = "remap"
  inputs = ["windows_system", "windows_application", "windows_security", "iis_logs", "app_logs"]
  source = '''
    .agent_hostname = "$env:COMPUTERNAME"
    .agent_os = "windows"
    .collected_at = now()
    .source_agent = "vector-agent-windows"
  '''

# ==================== 輸出到中央伺服器 ====================

# HTTP 方式回傳
[sinks.send_to_central]
  type = "http"
  inputs = ["add_host_info"]
  uri = "http://${VectorServer}:8080"
  encoding.codec = "json"

  # 批次發送設定
  batch.max_bytes = 1048576
  batch.timeout_secs = 5

  # 重試設定
  request.retry_attempts = 5
  request.retry_initial_backoff_secs = 1

# 本地備份
[sinks.local_backup]
  type = "file"
  inputs = ["add_host_info"]
  path = "C:/ProgramData/Vector/logs/backup-%Y-%m-%d.log"
  encoding.codec = "json"
"@

$configFile = "$configPath\vector.toml"
$configContent | Out-File -FilePath $configFile -Encoding UTF8
Write-Host "✓ 配置檔已建立: $configFile" -ForegroundColor Green

# 建立日誌目錄
Write-Host ""
Write-Host "步驟 5: 建立日誌目錄..." -ForegroundColor Yellow
$logDir = "C:\ProgramData\Vector\logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Write-Host "✓ 日誌目錄已建立: $logDir" -ForegroundColor Green

# 安裝 Windows 服務
Write-Host ""
Write-Host "步驟 6: 安裝 Windows 服務..." -ForegroundColor Yellow

# 停止舊服務（如果存在）
$service = Get-Service -Name "Vector" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "停止舊服務..."
    Stop-Service -Name "Vector" -Force
    & sc.exe delete Vector
    Start-Sleep -Seconds 2
}

# 使用 NSSM 安裝服務（更穩定）
$nssmPath = "$installPath\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    Write-Host "下載 NSSM (Non-Sucking Service Manager)..."
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $nssmZip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing
    Expand-Archive -Path $nssmZip -DestinationPath $env:TEMP -Force
    Copy-Item "$env:TEMP\nssm-2.24\win64\nssm.exe" $nssmPath
}

# 安裝服務
& $nssmPath install Vector "$installPath\vector.exe" "--config $configFile"
& $nssmPath set Vector AppDirectory $installPath
& $nssmPath set Vector DisplayName "Vector Log Agent"
& $nssmPath set Vector Description "Vector 日誌收集代理程式，自動回傳日誌到中央伺服器"
& $nssmPath set Vector Start SERVICE_AUTO_START

Write-Host "✓ Windows 服務已安裝" -ForegroundColor Green

# 設定防火牆規則
Write-Host ""
Write-Host "步驟 7: 設定防火牆..." -ForegroundColor Yellow
try {
    New-NetFirewallRule -DisplayName "Vector Agent Outbound" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 8080,5601,8686 -ErrorAction SilentlyContinue | Out-Null
    Write-Host "✓ 防火牆規則已新增" -ForegroundColor Green
} catch {
    Write-Host "⚠ 防火牆設定失敗（可能需手動設定）" -ForegroundColor Yellow
}

# 啟動服務
Write-Host ""
Write-Host "步驟 8: 啟動 Vector 服務..." -ForegroundColor Yellow
Start-Service -Name "Vector"
Start-Sleep -Seconds 3

$service = Get-Service -Name "Vector"
if ($service.Status -eq "Running") {
    Write-Host "✓ Vector 服務已啟動" -ForegroundColor Green
} else {
    Write-Host "✗ Vector 服務啟動失敗" -ForegroundColor Red
    Write-Host "請檢查: C:\ProgramData\Vector\logs\" -ForegroundColor Yellow
}

# 測試發送
Write-Host ""
Write-Host "步驟 9: 測試日誌發送..." -ForegroundColor Yellow
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Information -Message "Vector Agent 測試日誌 - 來自 $env:COMPUTERNAME - $(Get-Date)"
Write-Host "✓ 測試日誌已發送" -ForegroundColor Green

# 完成
Write-Host ""
Write-Host "===================================" -ForegroundColor Green
Write-Host "✓✓✓ Vector Agent 安裝完成！✓✓✓" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green
Write-Host ""
Write-Host "服務管理：" -ForegroundColor Cyan
Write-Host "  查看狀態: Get-Service Vector"
Write-Host "  啟動服務: Start-Service Vector"
Write-Host "  停止服務: Stop-Service Vector"
Write-Host "  重啟服務: Restart-Service Vector"
Write-Host ""
Write-Host "配置檔位置: $configFile" -ForegroundColor Cyan
Write-Host "本地日誌備份: $logDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "日誌將自動回傳到: $VectorServer" -ForegroundColor Cyan
Write-Host ""
Write-Host "收集的日誌類型：" -ForegroundColor Cyan
Write-Host "  - Windows 系統事件"
Write-Host "  - Windows 應用程式事件"
Write-Host "  - Windows 安全事件"
Write-Host "  - IIS 日誌"
Write-Host "  - 應用程式日誌"
Write-Host ""
Write-Host "到中央伺服器查看日誌：" -ForegroundColor Cyan
Write-Host "  tail -f /var/log/vector-collected/unified-`$(date +%Y-%m-%d).log" -ForegroundColor Yellow
Write-Host ""
