#!/bin/bash
# 遠端主機設定腳本 - 自動將日誌發送到 Vector

set -e

echo "=== 遠端主機日誌設定腳本 ==="
echo ""

# 詢問 Vector 伺服器 IP
read -p "請輸入 Vector 伺服器 IP: " VECTOR_HOST
if [ -z "$VECTOR_HOST" ]; then
    echo "✗ 錯誤：必須提供 Vector 伺服器 IP"
    exit 1
fi

echo ""
echo "Vector 伺服器: $VECTOR_HOST"
echo ""

# 測試連接
echo "步驟 1: 測試連接到 Vector..."
if curl -s --connect-timeout 5 http://$VECTOR_HOST:8686/health > /dev/null; then
    echo "✓ Vector 連接成功"
else
    echo "✗ 警告：無法連接到 Vector (可能需要開啟防火牆)"
fi

# 設定 rsyslog
echo ""
echo "步驟 2: 設定系統日誌自動轉發..."

if command -v rsyslog &> /dev/null || [ -f /etc/rsyslog.conf ]; then
    echo "檢測到 rsyslog"

    # 備份原設定
    sudo cp /etc/rsyslog.conf /etc/rsyslog.conf.backup.$(date +%Y%m%d)

    # 添加 Vector 轉發規則
    if ! grep -q "### Vector Log Collection ###" /etc/rsyslog.conf; then
        echo "" | sudo tee -a /etc/rsyslog.conf
        echo "### Vector Log Collection ###" | sudo tee -a /etc/rsyslog.conf
        echo "# 轉發所有日誌到 Vector (UDP)" | sudo tee -a /etc/rsyslog.conf
        echo "*.* @${VECTOR_HOST}:5514" | sudo tee -a /etc/rsyslog.conf
        echo "# 轉發所有日誌到 Vector (TCP - 更可靠)" | sudo tee -a /etc/rsyslog.conf
        echo "#*.* @@${VECTOR_HOST}:5601" | sudo tee -a /etc/rsyslog.conf

        sudo systemctl restart rsyslog
        echo "✓ rsyslog 設定完成並重啟"
    else
        echo "✓ rsyslog 已經設定過"
    fi
else
    echo "⚠ 未檢測到 rsyslog"
fi

# 設定 journald (systemd)
echo ""
echo "步驟 3: 設定 systemd journal 轉發..."

if command -v journalctl &> /dev/null; then
    echo "檢測到 systemd journal"

    sudo mkdir -p /etc/systemd/journald.conf.d/

    cat << EOF | sudo tee /etc/systemd/journald.conf.d/vector-forward.conf
[Journal]
# 轉發到 syslog
ForwardToSyslog=yes
EOF

    sudo systemctl restart systemd-journald
    echo "✓ journald 設定完成"
else
    echo "⚠ 未檢測到 systemd journal"
fi

# 建立測試腳本
echo ""
echo "步驟 4: 建立測試腳本..."

cat << 'EOF' > /tmp/test-vector-log.sh
#!/bin/bash
VECTOR_HOST=$1

if [ -z "$VECTOR_HOST" ]; then
    echo "用法: $0 <Vector伺服器IP>"
    exit 1
fi

echo "測試 HTTP 日誌發送..."
curl -X POST http://$VECTOR_HOST:8080 \
  -H "Content-Type: application/json" \
  -d "{\"level\":\"info\",\"message\":\"HTTP測試來自 $(hostname)\",\"hostname\":\"$(hostname)\",\"timestamp\":\"$(date -Iseconds)\"}"

echo ""
echo "測試 Syslog UDP 發送..."
logger -n $VECTOR_HOST -P 5514 "Syslog UDP 測試來自 $(hostname)"

echo ""
echo "測試 Syslog TCP 發送..."
logger -n $VECTOR_HOST -P 5601 -T "Syslog TCP 測試來自 $(hostname)"

echo ""
echo "✓ 測試完成，請到 Vector 伺服器查看日誌"
EOF

chmod +x /tmp/test-vector-log.sh
echo "✓ 測試腳本建立完成: /tmp/test-vector-log.sh"

# Apache 日誌設定
echo ""
echo "步驟 5: Apache 日誌設定（如果需要）..."

if [ -d /etc/apache2 ] || [ -d /etc/httpd ]; then
    echo "檢測到 Apache"
    echo ""
    echo "如需轉發 Apache 日誌，請將以下內容加到 Apache 配置："
    echo ""
    echo "  CustomLog \"|/usr/bin/logger -n $VECTOR_HOST -P 5514 -t apache\" combined"
    echo ""
fi

# IIS 設定說明
echo ""
echo "步驟 6: IIS 日誌設定（Windows）..."
echo "在 Windows 伺服器上執行 PowerShell："
echo ""
echo "  # 安裝 nxlog 或使用 Windows Event Forwarding"
echo "  # 或使用檔案共享方式掛載 IIS 日誌目錄"
echo ""

echo ""
echo "==================================="
echo "✓✓✓ 設定完成！✓✓✓"
echo "==================================="
echo ""
echo "測試指令："
echo "  /tmp/test-vector-log.sh $VECTOR_HOST"
echo ""
echo "手動發送範例："
echo "  HTTP:       curl -X POST http://$VECTOR_HOST:8080 -H 'Content-Type: application/json' -d '{\"message\":\"test\"}'"
echo "  Syslog UDP: logger -n $VECTOR_HOST -P 5514 'test message'"
echo "  Syslog TCP: logger -n $VECTOR_HOST -P 5601 -T 'test message'"
echo ""
echo "系統日誌現在會自動轉發到 Vector 伺服器"
echo ""
