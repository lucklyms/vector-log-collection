# Token 認證說明

## 概述

此日誌收集系統已加入 Token 認證機制，保護中央伺服器的 HTTP 端點，防止未授權的日誌提交。

## 認證機制

### 中央伺服器 (vector-final.toml)

中央伺服器在接收 HTTP 日誌時會驗證請求的 `Authorization` header：

```toml
[transforms.validate_token]
  type = "filter"
  inputs = ["http_logs"]
  condition = '''
    auth = .headers.authorization ?? ""

    valid_tokens = [
      "Bearer my-secret-token-2024",
      "Bearer agent-token-abc123",
      "Bearer production-token-xyz789"
    ]

    includes(valid_tokens, auth)
  '''
```

### 支援的 Token

目前系統預設支援以下三個 token：

1. `Bearer my-secret-token-2024` - 預設 token
2. `Bearer agent-token-abc123` - Agent 專用 token
3. `Bearer production-token-xyz789` - 生產環境 token

## 如何使用

### 1. Agent 配置

在 `vector-agent.toml` 或 `vector-agent-simple.toml` 中，已自動配置好認證 header：

```toml
[sinks.send_to_central]
  type = "http"
  uri = "http://223.27.34.248:8080"

  [sinks.send_to_central.request.headers]
    Authorization = "Bearer my-secret-token-2024"
```

### 2. 手動發送日誌 (curl)

使用 curl 發送日誌時，需要加入 `Authorization` header：

```bash
curl -X POST http://223.27.34.248:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer my-secret-token-2024" \
  -d '{"level":"info","message":"Test log message","service":"my-app"}'
```

### 3. 測試認證

#### 成功案例（帶正確 token）
```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer my-secret-token-2024" \
  -d '{"message":"Authenticated log"}'
```

#### 失敗案例（無 token）
```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"message":"Unauthenticated log"}'
```
此請求會被拒絕，日誌不會被記錄。

#### 失敗案例（錯誤 token）
```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer wrong-token" \
  -d '{"message":"Invalid token log"}'
```
此請求也會被拒絕。

## 自訂 Token

### 新增 Token

編輯 `vector-final.toml`，在 `valid_tokens` 陣列中新增你的 token：

```toml
valid_tokens = [
  "Bearer my-secret-token-2024",
  "Bearer agent-token-abc123",
  "Bearer production-token-xyz789",
  "Bearer your-new-token-here"    # 新增的 token
]
```

### 更換 Agent Token

編輯 agent 配置檔案，修改 `Authorization` 值：

```toml
[sinks.send_to_central.request.headers]
  Authorization = "Bearer your-new-token-here"
```

## 安全建議

1. **定期更換 Token**：建議每 3-6 個月更換一次 token
2. **不同環境使用不同 Token**：開發、測試、生產環境應使用不同的 token
3. **Token 長度**：建議使用至少 32 字元的隨機字串
4. **保密 Token**：不要將 token 提交到公開的版本控制系統
5. **使用環境變數**：建議將 token 存放在環境變數中，而非硬編碼

### 使用環境變數示例

```bash
export LOG_TOKEN="Bearer my-secret-token-2024"

# 修改 vector-agent.toml 使用環境變數
[sinks.send_to_central.request.headers]
  Authorization = "${LOG_TOKEN}"
```

## 故障排除

### 問題：日誌沒有被接收

1. 檢查是否有帶 `Authorization` header
2. 確認 token 格式正確（必須是 `Bearer <token>`）
3. 驗證 token 是否在 `valid_tokens` 列表中
4. 查看中央伺服器日誌：`podman logs -f vector`

### 問題：Agent 無法連接

1. 確認 agent 配置中的 `Authorization` header 設定正確
2. 確認網路連線正常
3. 檢查 agent 日誌：`journalctl -u vector-agent -f`

## 進階配置

### IP 白名單 + Token 雙重驗證

可以結合 IP 白名單和 token 驗證：

```toml
[transforms.validate_token_and_ip]
  type = "filter"
  inputs = ["http_logs"]
  condition = '''
    auth = .headers.authorization ?? ""
    source_ip = .headers."x-forwarded-for" ?? .remote_addr ?? ""

    valid_tokens = ["Bearer my-secret-token-2024"]
    allowed_ips = ["192.168.1.0/24", "10.0.0.0/8"]

    includes(valid_tokens, auth) && includes(allowed_ips, source_ip)
  '''
```

### Rate Limiting（速率限制）

可以在認證基礎上增加速率限制，防止 token 被濫用：

```toml
[transforms.rate_limit]
  type = "throttle"
  inputs = ["validate_token"]
  threshold = 1000      # 每個時間窗口最多 1000 個事件
  window_secs = 60      # 時間窗口為 60 秒
```
