#!/bin/bash
# Vector Agent 安裝腳本 - 在遠端主機上執行
# 自動收集本機日誌並回傳到中央 Vector 伺服器
# 伺服器 IP: 223.27.34.248

set -e

echo "=== Vector Agent 安裝腳本 ==="
echo ""

# 檢查是否為 root
if [ "$EUID" -ne 0 ]; then
    echo "請使用 root 或 sudo 執行此腳本"
    exit 1
fi

# 固定中央伺服器 IP
VECTOR_SERVER="223.27.34.248"

echo "Vector 中央伺服器: $VECTOR_SERVER"
echo ""

# 測試連接
echo "步驟 1: 測試連接到 Vector 伺服器..."
if curl -s --connect-timeout 5 http://$VECTOR_SERVER:8686/health > /dev/null 2>&1; then
    echo "✓ Vector 伺服器連接成功"
else
    echo "⚠ 警告：無法連接到 Vector 伺服器 API，但繼續安裝"
fi

# 安裝 Vector
echo ""
echo "步驟 2: 安裝 Vector..."

if command -v vector &> /dev/null; then
    echo "✓ Vector 已安裝: $(vector --version)"
else
    echo "使用官方安裝腳本安裝 Vector..."
    curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y

    # 確保 vector 在 PATH 中
    if [ -f "$HOME/.vector/bin/vector" ]; then
        ln -sf $HOME/.vector/bin/vector /usr/local/bin/vector
    fi

    # 驗證安裝
    if command -v vector &> /dev/null; then
        echo "✓ Vector 安裝完成: $(vector --version)"
    else
        echo "✗ Vector 安裝失敗"
        exit 1
    fi
fi

# 建立必要目錄（先建立，再配置）
echo ""
echo "步驟 3: 建立必要目錄..."
mkdir -p /var/log/vector-agent
mkdir -p /var/lib/vector
mkdir -p /etc/vector
chown -R root:root /var/lib/vector
chmod 755 /var/lib/vector
echo "✓ 目錄建立完成"

# 下載並配置 Vector Agent
echo ""
echo "步驟 4: 配置 Vector Agent..."

curl -fsSL https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/vector-agent-simple.toml -o /etc/vector/vector.toml

# 替換伺服器 IP
sed -i "s/VECTOR_SERVER_IP/$VECTOR_SERVER/g" /etc/vector/vector.toml

# 驗證配置檔
echo "驗證配置檔..."
if /usr/local/bin/vector validate /etc/vector/vector.toml; then
    echo "✓ 配置檔驗證通過"
else
    echo "✗ 配置檔有錯誤"
    exit 1
fi

# 建立 systemd 服務檔
echo ""
echo "步驟 5: 建立 systemd 服務..."

if command -v systemctl &> /dev/null; then
    cat > /etc/systemd/system/vector.service <<'EOF'
[Unit]
Description=Vector Log Agent
Documentation=https://vector.dev
After=network-online.target
Requires=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/vector --config /etc/vector/vector.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    echo "✓ systemd 服務檔已建立"

    # 清理可能存在的舊 Vector 進程
    echo "清理舊的 Vector 進程..."
    pkill -9 vector 2>/dev/null || true
    sleep 1

    # 重新載入 systemd 並啟動服務
    systemctl daemon-reload
    systemctl enable vector
    systemctl start vector

    sleep 3

    if systemctl is-active --quiet vector; then
        echo "✓ Vector Agent 服務已啟動"
    else
        echo "✗ Vector Agent 啟動失敗，請檢查日誌："
        echo "   journalctl -u vector -f"
        exit 1
    fi
else
    # 手動啟動
    nohup vector --config /etc/vector/vector.toml > /var/log/vector-agent/vector.log 2>&1 &
    echo "✓ Vector Agent 已在背景啟動"
fi

# 測試發送
echo ""
echo "步驟 6: 測試日誌發送..."
logger "Vector Agent 測試日誌 - 來自 $(hostname) - $(date)"
echo "✓ 測試日誌已發送"

echo ""
echo "==================================="
echo "✓✓✓ Vector Agent 安裝完成！✓✓✓"
echo "==================================="
echo ""
echo "服務狀態："
echo "  檢查狀態: systemctl status vector"
echo "  查看日誌: journalctl -u vector -f"
echo "  重啟服務: systemctl restart vector"
echo ""
echo "本機日誌將自動回傳到: $VECTOR_SERVER"
echo "收集的日誌類型："
echo "  - 系統日誌 (journald/syslog)"
echo "  - Apache/Nginx 日誌"
echo "  - 應用程式日誌"
echo "  - Docker 容器日誌"
echo ""
echo "到中央伺服器查看日誌："
echo "  tail -f /var/log/vector-collected/unified-\$(date +%Y-%m-%d).log"
echo ""
