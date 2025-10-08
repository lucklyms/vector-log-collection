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

# 檢測系統並安裝 Vector
echo ""
echo "步驟 2: 安裝 Vector..."

if command -v vector &> /dev/null; then
    echo "✓ Vector 已安裝: $(vector --version)"
else
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo "檢測到 Debian/Ubuntu 系統"
        curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | bash
        apt-get install -y vector
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Rocky
        echo "檢測到 RHEL/CentOS 系統"
        curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.rpm.sh' | bash
        yum install -y vector
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        echo "檢測到 Arch Linux"
        pacman -S --noconfirm vector
    else
        echo "✗ 不支援的系統，嘗試使用 shell 安裝..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash
    fi
    echo "✓ Vector 安裝完成"
fi

# 下載並配置 Vector Agent
echo ""
echo "步驟 3: 配置 Vector Agent..."

mkdir -p /etc/vector
curl -fsSL https://raw.githubusercontent.com/lucklyms/vector-log-collection/master/vector-agent.toml -o /etc/vector/vector.toml

# 替換伺服器 IP
sed -i "s/VECTOR_SERVER_IP/$VECTOR_SERVER/g" /etc/vector/vector.toml

echo "✓ 配置完成"

# 建立日誌目錄
echo ""
echo "步驟 4: 建立必要目錄..."
mkdir -p /var/log/vector-agent
echo "✓ 目錄建立完成"

# 啟動 Vector Agent
echo ""
echo "步驟 5: 啟動 Vector Agent 服務..."

if command -v systemctl &> /dev/null; then
    # 使用 systemd
    systemctl enable vector
    systemctl restart vector

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
