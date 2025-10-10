# Vector 日誌收集測試環境

## 文件說明

- `vector.toml` - Vector 配置文件
- `docker-compose.yml` - Docker Compose 配置（可選）
- `logs/` - 收集的日誌輸出目錄
- `app-logs/` - 測試應用產生的日誌

## 使用方法（Podman）

### 1. 查看運行中的容器
```bash
podman ps
```

### 2. 查看 Vector 收集到的日誌（實時）
```bash
podman logs -f vector
```

### 3. 查看測試應用產生的日誌
```bash
podman logs -f test-app
```

### 4. 查看收集到的日誌文件
```bash
tail -f logs/collected-$(date +%Y-%m-%d).log
```

### 5. 通過 HTTP 發送日誌（需要 Token 認證）
```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer my-secret-token-2024" \
  -d '{"level":"info","message":"Your log message","service":"my-app"}'
```

**注意**：從此版本開始，HTTP 端點需要 Token 認證，詳見 [TOKEN-AUTH.md](TOKEN-AUTH.md)

### 6. 查看 Vector API 健康狀態
```bash
curl http://localhost:8686/health
```

### 7. 訪問 Vector GraphQL Playground
在瀏覽器打開：http://localhost:8686/playground

### 8. 停止和移除容器
```bash
podman stop test-app vector
podman rm test-app vector
```

## 開放的端口

- **8080** - HTTP 日誌接收端點（POST JSON 日誌到此端口）
- **8686** - Vector API 和管理界面

## 測試環境說明

- **test-app**: 模擬應用容器，每隔幾秒產生不同級別的 JSON 格式日誌到文件
- **vector**: 日誌收集器，支持：
  - 從文件收集日誌（`app-logs/*.log`）
  - 通過 HTTP 接收日誌（端口 8080）
  - 輸出到控制台
  - 保存到 `logs/` 目錄的文件中

## 收集到的日誌格式

日誌包含：
- `vector_timestamp` - Vector 處理時間
- `source_type` - 日誌來源（file 或 http）
- 原始日誌的所有字段（level, message 等）

## 示例：發送多條日誌

```bash
# 發送 info 日誌（需要 Token 認證）
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer my-secret-token-2024" \
  -d '{"level":"info","message":"User logged in","user_id":123}'

# 發送 error 日誌
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer my-secret-token-2024" \
  -d '{"level":"error","message":"Database connection failed","error":"timeout"}'
```

## Token 認證

此系統已加入 Token 認證保護 HTTP 端點。詳細說明請參考 [TOKEN-AUTH.md](TOKEN-AUTH.md)

**預設 Token**: `Bearer my-secret-token-2024`
