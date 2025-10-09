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

# 自動偵測外網 IP
echo "偵測外網 IP..."
AGENT_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
if [ -z "$AGENT_IP" ]; then
    # 備用方法
    AGENT_IP=$(curl -s --connect-timeout 5 icanhazip.com 2>/dev/null)
fi
if [ -z "$AGENT_IP" ]; then
    # 如果無法取得外網 IP，使用內網 IP
    AGENT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
fi
echo "偵測到 Agent IP: $AGENT_IP"

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

# 建立服務
echo ""
echo "步驟 5: 建立服務..."

# 清理可能存在的舊 Vector 進程
echo "清理舊的 Vector 進程..."
pkill -9 vector 2>/dev/null || true
sleep 1

# 偵測 init 系統
if command -v systemctl &> /dev/null; then
    # systemd 系統
    echo "偵測到 systemd，建立 systemd 服務..."
    cat > /etc/systemd/system/vector.service <<EOF
[Unit]
Description=Vector Log Agent
Documentation=https://vector.dev
After=network-online.target
Requires=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="AGENT_IP=$AGENT_IP"
ExecStart=/usr/local/bin/vector --config /etc/vector/vector.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

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

elif [ -f /etc/init.d/ ] || command -v service &> /dev/null; then
    # SysVinit / init.d 系統
    echo "偵測到 SysVinit，建立 init.d 服務..."
    cat > /etc/init.d/vector <<'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          vector
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Vector Log Agent
# Description:       Vector log collection agent
### END INIT INFO

AGENT_IP="AGENT_IP_PLACEHOLDER"
export AGENT_IP

case "$1" in
    start)
        echo "Starting Vector Agent..."
        /usr/local/bin/vector --config /etc/vector/vector.toml >> /var/log/vector-agent/vector.log 2>&1 &
        echo $! > /var/run/vector.pid
        echo "Vector Agent started"
        ;;
    stop)
        echo "Stopping Vector Agent..."
        if [ -f /var/run/vector.pid ]; then
            kill $(cat /var/run/vector.pid)
            rm /var/run/vector.pid
        fi
        pkill -f "vector --config" || true
        echo "Vector Agent stopped"
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f /var/run/vector.pid ] && kill -0 $(cat /var/run/vector.pid) 2>/dev/null; then
            echo "Vector Agent is running (PID: $(cat /var/run/vector.pid))"
        else
            echo "Vector Agent is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOF

    # 替換 AGENT_IP
    sed -i "s/AGENT_IP_PLACEHOLDER/$AGENT_IP/g" /etc/init.d/vector
    chmod +x /etc/init.d/vector

    # 啟用服務
    if command -v update-rc.d &> /dev/null; then
        update-rc.d vector defaults
    elif command -v chkconfig &> /dev/null; then
        chkconfig --add vector
        chkconfig vector on
    fi

    # 啟動服務
    /etc/init.d/vector start
    sleep 3

    if /etc/init.d/vector status | grep -q running; then
        echo "✓ Vector Agent 服務已啟動"
    else
        echo "✗ Vector Agent 啟動失敗，請檢查日誌："
        echo "   tail -f /var/log/vector-agent/vector.log"
        exit 1
    fi

elif command -v rc-update &> /dev/null; then
    # OpenRC 系統 (Alpine Linux, Gentoo)
    echo "偵測到 OpenRC，建立 OpenRC 服務..."
    cat > /etc/init.d/vector <<EOF
#!/sbin/openrc-run

name="vector"
description="Vector Log Agent"
command="/usr/local/bin/vector"
command_args="--config /etc/vector/vector.toml"
command_background="yes"
pidfile="/run/vector.pid"

export AGENT_IP="$AGENT_IP"

depend() {
    need net
    after firewall
}
EOF

    chmod +x /etc/init.d/vector
    rc-update add vector default
    rc-service vector start
    sleep 3

    if rc-service vector status | grep -q started; then
        echo "✓ Vector Agent 服務已啟動"
    else
        echo "✗ Vector Agent 啟動失敗，請檢查日誌："
        echo "   tail -f /var/log/vector-agent/vector.log"
        exit 1
    fi

else
    # 不支援的 init 系統，使用 cron + nohup
    echo "⚠ 未偵測到支援的 init 系統，使用 cron 自動啟動..."

    # 建立啟動腳本
    cat > /usr/local/bin/vector-start.sh <<EOF
#!/bin/bash
export AGENT_IP="$AGENT_IP"
if ! pgrep -f "vector --config /etc/vector/vector.toml" > /dev/null; then
    /usr/local/bin/vector --config /etc/vector/vector.toml >> /var/log/vector-agent/vector.log 2>&1 &
fi
EOF
    chmod +x /usr/local/bin/vector-start.sh

    # 加入 crontab (每分鐘檢查一次)
    (crontab -l 2>/dev/null | grep -v vector-start.sh; echo "* * * * * /usr/local/bin/vector-start.sh") | crontab -

    # 立即啟動
    /usr/local/bin/vector-start.sh
    sleep 3

    if pgrep -f "vector --config" > /dev/null; then
        echo "✓ Vector Agent 已啟動 (使用 cron 監控)"
        echo "  註：此系統將使用 cron 每分鐘檢查 Vector 是否運行"
    else
        echo "✗ Vector Agent 啟動失敗"
        exit 1
    fi
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
echo "服務管理："
if command -v systemctl &> /dev/null; then
    echo "  檢查狀態: systemctl status vector"
    echo "  查看日誌: journalctl -u vector -f"
    echo "  重啟服務: systemctl restart vector"
    echo "  停止服務: systemctl stop vector"
elif [ -f /etc/init.d/vector ]; then
    if command -v rc-service &> /dev/null; then
        echo "  檢查狀態: rc-service vector status"
        echo "  重啟服務: rc-service vector restart"
        echo "  停止服務: rc-service vector stop"
    else
        echo "  檢查狀態: service vector status (或 /etc/init.d/vector status)"
        echo "  重啟服務: service vector restart (或 /etc/init.d/vector restart)"
        echo "  停止服務: service vector stop (或 /etc/init.d/vector stop)"
    fi
    echo "  查看日誌: tail -f /var/log/vector-agent/vector.log"
else
    echo "  檢查狀態: ps aux | grep vector"
    echo "  查看日誌: tail -f /var/log/vector-agent/vector.log"
    echo "  停止服務: pkill -f 'vector --config'"
    echo "  註：使用 cron 自動監控，每分鐘檢查一次"
fi
echo ""
echo "本機日誌將自動回傳到: $VECTOR_SERVER"
echo "收集的日誌類型："
echo "  - 系統日誌 (syslog/messages/auth.log)"
echo "  - Apache/Nginx 日誌"
echo "  - 應用程式日誌"
echo "  - /var/log 下所有日誌"
echo ""
echo "到中央伺服器查看日誌："
echo "  tail -f /var/log/vector-collected/unified-\$(date +%Y-%m-%d).log"
echo ""
