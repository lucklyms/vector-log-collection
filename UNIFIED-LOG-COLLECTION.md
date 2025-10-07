# 統一日誌收集系統 - Vector 配置指南

## 📋 概述

此配置支持收集以下類型的日誌並轉換成統一格式：
- ✅ **IIS 日誌**（W3C 格式）
- ✅ **Apache 日誌**（訪問日誌 + 錯誤日誌）
- ✅ **System Log**（Syslog、系統日誌文件）
- ✅ **HTTP API**（自定義應用）

所有日誌都會被轉換成統一的 JSON 格式，方便查詢和分析。

---

## 🚀 快速開始

### 1. 啟動 Vector（統一日誌收集）

```bash
# 創建必要的目錄
mkdir -p iis-logs apache-logs

# 使用新配置啟動 Vector
podman run -d --name vector-unified \
  -p 8080:8080 \
  -p 514:514/udp \
  -p 601:601 \
  -p 8686:8686 \
  -v ./vector-unified.toml:/etc/vector/vector.toml:ro \
  -v ./iis-logs:/iis-logs:Z \
  -v ./apache-logs:/apache-logs:Z \
  -v ./logs:/var/log/vector:Z \
  timberio/vector:latest-alpine --config /etc/vector/vector.toml
```

### 2. 開放的端口

| 端口 | 協議 | 用途 |
|------|------|------|
| 8080 | HTTP | 接收 JSON 格式日誌 |
| 514  | UDP  | Syslog (標準端口) |
| 601  | TCP  | Syslog (可靠傳輸) |
| 8686 | HTTP | Vector API 管理界面 |

---

## 📝 如何發送日誌

### 方式 1：IIS 日誌

**在 IIS 服務器上配置：**

1. 將 IIS 日誌寫入到共享目錄或使用文件同步
2. 將日誌文件放到 Vector 的 `/iis-logs/` 目錄

**IIS 日誌格式設置：**
- 使用 **W3C Extended Log File Format**
- 建議欄位：date, time, s-sitename, s-computername, s-ip, cs-method, cs-uri-stem, cs-uri-query, s-port, cs-username, c-ip, cs(User-Agent), sc-status, sc-substatus, sc-win32-status, time-taken

**統一格式輸出範例：**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "log_type": "iis",
  "severity": "info",
  "source_host": "SERVER1",
  "http": {
    "method": "GET",
    "uri": "/index.html",
    "status": 200,
    "client_ip": "192.168.1.100",
    "user_agent": "Mozilla/5.0",
    "response_time_ms": 15
  }
}
```

---

### 方式 2：Apache 日誌

**配置 Apache 將日誌寫入 Vector 監控的目錄：**

編輯 Apache 配置（httpd.conf 或 virtualhost 配置）：

```apache
# 訪問日誌（Combined 格式）
CustomLog "/apache-logs/access.log" combined

# 錯誤日誌
ErrorLog "/apache-logs/error.log"
```

**統一格式輸出範例（訪問日誌）：**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "log_type": "apache_access",
  "severity": "info",
  "source_host": "web-server",
  "http": {
    "method": "GET",
    "uri": "/api/users",
    "status": 200,
    "client_ip": "192.168.1.50",
    "user_agent": "curl/7.68.0",
    "response_bytes": 2326
  }
}
```

**統一格式輸出範例（錯誤日誌）：**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "log_type": "apache_error",
  "severity": "error",
  "source_host": "web-server",
  "message": "File does not exist: /var/www/html/missing.html",
  "client_ip": "192.168.1.50"
}
```

---

### 方式 3：Syslog（系統日誌、網路設備）

**選項 A：UDP Syslog（端口 514）**

在 Linux 系統上配置 rsyslog 轉發：

編輯 `/etc/rsyslog.conf` 或 `/etc/rsyslog.d/50-vector.conf`：

```bash
# 轉發所有日誌到 Vector
*.* @你的Vector服務器IP:514
```

重啟 rsyslog：
```bash
sudo systemctl restart rsyslog
```

**選項 B：TCP Syslog（端口 601，更可靠）**

```bash
# 使用 TCP 傳輸（兩個 @@ 符號）
*.* @@你的Vector服務器IP:601
```

**選項 C：網路設備（路由器、交換機）**

在設備管理界面配置 Syslog Server：
```
Syslog Server: 你的Vector服務器IP
Port: 514 (UDP) 或 601 (TCP)
```

**統一格式輸出範例：**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "log_type": "syslog",
  "severity": "info",
  "source_host": "firewall-01",
  "message": "Connection established from 192.168.1.100",
  "syslog": {
    "facility": "daemon",
    "process": "firewalld"
  }
}
```

---

### 方式 4：HTTP API（自定義應用）

**直接發送 JSON 日誌：**

```bash
curl -X POST http://你的Vector服務器IP:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "level": "error",
    "message": "Database connection timeout",
    "service": "my-app",
    "user_id": 12345
  }'
```

**在應用程式中集成（Python 範例）：**

```python
import requests
import json

def send_log(level, message, **extra):
    log_data = {
        "level": level,
        "message": message,
        **extra
    }
    requests.post(
        "http://你的Vector服務器IP:8080",
        json=log_data
    )

# 使用
send_log("error", "User login failed", user_id=123, ip="192.168.1.1")
```

**統一格式輸出範例：**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "log_type": "http",
  "severity": "error",
  "source_host": "unknown",
  "message": "Database connection timeout",
  "service": "my-app",
  "user_id": 12345
}
```

---

## 📊 統一日誌格式

所有日誌都會被轉換成以下統一結構：

```json
{
  "timestamp": "ISO 8601 時間戳",
  "log_type": "日誌類型 (iis, apache_access, apache_error, syslog, http)",
  "severity": "嚴重程度 (info, warning, error)",
  "source_host": "來源主機名",
  "message": "日誌訊息",

  "http": {  // 僅 HTTP 相關日誌有此欄位
    "method": "HTTP 方法",
    "uri": "請求 URI",
    "status": "HTTP 狀態碼",
    "client_ip": "客戶端 IP",
    "user_agent": "User Agent",
    "response_time_ms": "響應時間（毫秒）",
    "response_bytes": "響應大小（字節）"
  },

  "syslog": {  // 僅 Syslog 日誌有此欄位
    "facility": "Syslog facility",
    "process": "進程名"
  },

  "raw_log": "原始日誌內容",
  "collected_at": "收集時間戳"
}
```

---

## 🔍 查詢日誌

### 查看收集到的日誌

```bash
# 實時查看
tail -f logs/unified-$(date +%Y-%m-%d).log

# 查看所有錯誤日誌
cat logs/unified-*.log | jq 'select(.severity == "error")'

# 查看特定來源的日誌
cat logs/unified-*.log | jq 'select(.log_type == "iis")'

# 查看 HTTP 狀態碼 >= 500 的日誌
cat logs/unified-*.log | jq 'select(.http.status >= 500)'

# 查看特定主機的日誌
cat logs/unified-*.log | jq 'select(.source_host == "SERVER1")'
```

### 統計分析

```bash
# 統計各類型日誌數量
cat logs/unified-*.log | jq -r '.log_type' | sort | uniq -c

# 統計 HTTP 狀態碼分布
cat logs/unified-*.log | jq -r '.http.status' | sort | uniq -c

# 統計最慢的 HTTP 請求
cat logs/unified-*.log | jq -r 'select(.http.response_time_ms != null) | "\(.http.response_time_ms) \(.http.uri)"' | sort -rn | head
```

---

## 🛠️ 管理命令

```bash
# 查看 Vector 狀態
podman logs vector-unified

# 查看 Vector API 健康狀態
curl http://localhost:8686/health

# 訪問 GraphQL Playground
# 瀏覽器打開：http://localhost:8686/playground

# 停止 Vector
podman stop vector-unified

# 重啟 Vector（配置更改後）
podman restart vector-unified

# 查看實時日誌流
podman logs -f vector-unified
```

---

## 🔒 安全建議

1. **防火牆配置**
   - 僅開放必要的端口
   - 限制來源 IP（白名單）

2. **Syslog 安全**
   - 優先使用 TCP (601) 而非 UDP (514)
   - 考慮使用 TLS 加密傳輸

3. **HTTP API 安全**
   - 建議添加身份驗證（可在 Vector 前加 Nginx）
   - 使用 HTTPS

4. **日誌輪轉**
   - 定期清理舊日誌文件
   - 考慮壓縮歸檔

---

## 📤 下一步：發送到 Elasticsearch

如果需要將日誌發送到 Elasticsearch，取消配置文件中的註釋：

```toml
[sinks.elasticsearch]
  type = "elasticsearch"
  inputs = ["unified_format"]
  endpoint = "http://elasticsearch:9200"
  bulk.index = "logs-%Y.%m.%d"
  bulk.action = "create"
```

---

## 🆘 故障排除

### 日誌沒有被收集

1. 檢查 Vector 是否正常運行：
   ```bash
   podman logs vector-unified
   ```

2. 檢查文件路徑是否正確掛載

3. 檢查端口是否被占用：
   ```bash
   sudo netstat -tulpn | grep -E '(514|601|8080|8686)'
   ```

### Syslog 無法接收

1. 確認防火牆已開放端口：
   ```bash
   sudo firewall-cmd --add-port=514/udp --permanent
   sudo firewall-cmd --add-port=601/tcp --permanent
   sudo firewall-cmd --reload
   ```

2. 檢查 SELinux（如果啟用）

3. 測試發送：
   ```bash
   logger -n 你的Vector服務器IP -P 514 "Test message"
   ```

---

## 📞 支持

查看 README.md 獲取更多資訊。
