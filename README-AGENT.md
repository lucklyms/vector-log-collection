# Vector Agent 部署方案

使用 Vector Agent 在每個遠端主機上自動收集並回傳日誌到中央伺服器。

## 架構說明

```
遠端主機 1 (Vector Agent)  ──┐
遠端主機 2 (Vector Agent)  ──┤
遠端主機 3 (Vector Agent)  ──┼──> 中央 Vector 伺服器 ──> 統一日誌檔案
遠端主機 N (Vector Agent)  ──┘
```

## 優點

- ✅ 自動收集所有日誌（系統、Apache、Nginx、Docker、應用程式）
- ✅ 自動重試和錯誤處理
- ✅ 批次發送，減少網路開銷
- ✅ 本地備份，防止資料遺失
- ✅ 添加主機名稱標籤，方便識別
- ✅ 使用 systemd 管理，開機自動啟動

## 部署步驟

### 1. 部署中央 Vector 伺服器

```bash
git clone https://github.com/lucklyms/vector-log-collection.git
cd vector-log-collection
./deploy.sh
# 輸入日誌存放路徑，例如：/data/logs
```

### 2. 在每個遠端主機安裝 Agent

#### 方法 A：一鍵安裝（推薦）

```bash
curl -fsSL https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent.sh | sudo bash
```

執行後會詢問中央伺服器 IP。

#### 方法 B：下載後安裝

```bash
wget https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent.sh
chmod +x install-agent.sh
sudo ./install-agent.sh
```

#### 方法 C：指定伺服器 IP 直接安裝

```bash
curl -fsSL https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent.sh | sudo VECTOR_SERVER=192.168.1.100 bash
```

### 3. 使用 GitHub Actions 批次部署

修改 `.github/workflows/deploy.yml`，添加多主機部署：

```yaml
- name: Deploy agents to all hosts
  run: |
    for host in host1 host2 host3; do
      ssh user@$host "curl -fsSL https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/install-agent.sh | sudo VECTOR_SERVER=${{ secrets.VECTOR_SERVER_IP }} bash"
    done
```

## Agent 收集的日誌類型

| 日誌類型 | 路徑 | 說明 |
|---------|------|------|
| 系統日誌 | journald | systemd 系統日誌 |
| Syslog | /var/log/syslog, /var/log/messages | 傳統系統日誌 |
| Apache | /var/log/apache2/*, /var/log/httpd/* | Apache access/error 日誌 |
| Nginx | /var/log/nginx/* | Nginx access/error 日誌 |
| 應用日誌 | /var/log/app/*, /opt/app/logs/* | 自定義應用日誌 |
| Docker | Docker socket | 所有容器日誌 |

## 管理 Agent

### 查看狀態
```bash
sudo systemctl status vector
```

### 查看即時日誌
```bash
sudo journalctl -u vector -f
```

### 重啟 Agent
```bash
sudo systemctl restart vector
```

### 停止 Agent
```bash
sudo systemctl stop vector
```

### 修改配置
```bash
sudo vi /etc/vector/vector.toml
sudo systemctl restart vector
```

## 自定義配置

如需收集特定路徑的日誌，編輯 `/etc/vector/vector.toml`：

```toml
[sources.custom_app]
  type = "file"
  include = ["/your/custom/path/**/*.log"]
  read_from = "beginning"
```

然後重啟服務：
```bash
sudo systemctl restart vector
```

## 查看中央伺服器日誌

在中央 Vector 伺服器上：

```bash
# 查看今天的日誌
tail -f /var/log/vector-collected/unified-$(date +%Y-%m-%d).log

# 搜尋特定主機的日誌
grep "agent_hostname.*web-server-01" /var/log/vector-collected/unified-*.log

# 使用 jq 解析 JSON 日誌
tail -f /var/log/vector-collected/unified-$(date +%Y-%m-%d).log | jq .
```

## 故障排除

### Agent 無法連接到中央伺服器

1. 檢查防火牆：
```bash
# 在中央伺服器開啟端口
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=5601/tcp
sudo firewall-cmd --reload
```

2. 測試連接：
```bash
curl http://中央伺服器IP:8686/health
```

### Agent 服務無法啟動

查看詳細錯誤：
```bash
sudo journalctl -u vector -n 50
```

測試配置檔案：
```bash
vector validate /etc/vector/vector.toml
```

### 日誌未出現在中央伺服器

1. 檢查 Agent 是否正常運行
2. 檢查 Agent 日誌是否有錯誤
3. 在 Agent 主機手動發送測試日誌：
```bash
logger "這是測試日誌"
```

4. 檢查網路連接

## 效能調優

### 減少網路頻寬使用

編輯 `/etc/vector/vector.toml`：

```toml
[sinks.send_to_central]
  # 增加批次大小
  batch.max_bytes = 5242880  # 5MB
  batch.timeout_secs = 10
```

### 增加本地緩衝

```toml
[sinks.send_to_central]
  buffer.type = "disk"
  buffer.max_size = 268435488  # 256MB
```

## 安全性

### 使用 TLS 加密傳輸

需要在中央伺服器配置 HTTPS，然後修改 Agent 配置：

```toml
[sinks.send_to_central]
  uri = "https://vector-server:8443"
  tls.verify_certificate = true
```

### 使用驗證

添加 API Token：

```toml
[sinks.send_to_central]
  headers.Authorization = "Bearer YOUR_TOKEN"
```
