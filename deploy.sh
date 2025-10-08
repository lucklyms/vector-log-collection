#!/bin/bash
# Vector 日誌收集系統 - 自動部署腳本

set -e  # 遇到錯誤立即退出
set -x  # 顯示執行的命令（用於除錯）

echo "=== Vector 日誌收集系統部署腳本 ==="
echo ""

# 檢測使用 Docker 還是 Podman
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
    VOLUME_FLAG=":Z"
    echo "✓ 檢測到 Podman"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
    VOLUME_FLAG=""
    echo "✓ 檢測到 Docker"
else
    echo "⚠ 未安裝 Docker 或 Podman，正在自動安裝 Docker..."

    # 檢測系統類型並安裝 Docker
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo "檢測到 Debian/Ubuntu 系統"
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Rocky
        echo "檢測到 RHEL/CentOS 系統"
        sudo yum install -y docker
        sudo systemctl start docker
        sudo systemctl enable docker
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        echo "檢測到 Arch Linux"
        sudo pacman -S --noconfirm docker
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        echo "✗ 不支援的系統，請手動安裝 Docker"
        exit 1
    fi

    CONTAINER_CMD="docker"
    VOLUME_FLAG=""
    echo "✓ Docker 安裝完成"
fi

echo ""
echo "步驟 1: 創建必要目錄..."
# 設定日誌目錄（支援非互動模式）
if [ -z "$LOG_DIR" ]; then
    # 如果在非互動環境（如 CI/CD），使用預設值
    if [ -t 0 ]; then
        read -p "請輸入日誌存放的底層目錄 [預設: /var/log/vector-collected]: " LOG_DIR
    fi
    LOG_DIR=${LOG_DIR:-/var/log/vector-collected}
fi

echo "日誌將存放在: $LOG_DIR"

# 嘗試建立目錄（如果失敗，可能是權限問題）
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    # 如果有 sudo，使用 sudo
    if command -v sudo &> /dev/null; then
        sudo mkdir -p "$LOG_DIR"
    else
        echo "✗ 錯誤：無法建立目錄 $LOG_DIR"
        exit 1
    fi
fi

mkdir -p iis-logs apache-logs app-logs
echo "✓ 目錄創建完成"

echo ""
echo "步驟 2: 停止並移除舊容器（如果存在）..."
# 強制停止並移除舊容器
if $CONTAINER_CMD ps -a | grep -q vector-unified; then
    echo "發現舊容器，正在移除..."
    $CONTAINER_CMD stop vector-unified 2>/dev/null || true
    $CONTAINER_CMD rm -f vector-unified 2>/dev/null || true
    echo "✓ 舊容器已移除"
else
    echo "✓ 沒有舊容器"
fi

echo ""
echo "步驟 3: 啟動 Vector 容器..."
$CONTAINER_CMD run -d --name vector-unified \
  -p 8080:8080 \
  -p 5514:5514/udp \
  -p 5601:5601 \
  -p 8686:8686 \
  -v ./vector-final.toml:/etc/vector/vector.toml:ro \
  -v ./iis-logs:/iis-logs${VOLUME_FLAG} \
  -v ./apache-logs:/apache-logs${VOLUME_FLAG} \
  -v ./app-logs:/app-logs${VOLUME_FLAG} \
  -v "$LOG_DIR":/var/log/vector${VOLUME_FLAG} \
  timberio/vector:latest-alpine --config /etc/vector/vector.toml

echo "✓ 容器啟動完成"

echo ""
echo "步驟 4: 等待服務啟動..."
sleep 5

echo ""
echo "步驟 5: 驗證服務狀態..."
if $CONTAINER_CMD ps | grep vector-unified > /dev/null; then
    echo "✓ Vector 容器運行中"
else
    echo "✗ Vector 容器未運行"
    exit 1
fi

echo ""
echo "步驟 6: 測試 API..."
if curl -s http://localhost:8686/health | grep -q "ok"; then
    echo "✓ API 健康檢查通過"
else
    echo "✗ API 健康檢查失敗"
fi

echo ""
echo "==================================="
echo "✓✓✓ 部署完成！✓✓✓"
echo "==================================="
echo ""
echo "服務端口："
echo "  - HTTP 日誌接收: http://localhost:8080"
echo "  - Syslog UDP:    udp://localhost:5514"
echo "  - Syslog TCP:    tcp://localhost:5601"
echo "  - Vector API:    http://localhost:8686"
echo ""
echo "常用命令："
echo "  查看日誌: $CONTAINER_CMD logs -f vector-unified"
echo "  查看狀態: $CONTAINER_CMD ps"
echo "  停止服務: $CONTAINER_CMD stop vector-unified"
echo "  重啟服務: $CONTAINER_CMD restart vector-unified"
echo ""
echo "收集的日誌位置: $LOG_DIR"
echo ""
echo "所有遠端主機發送方式："
echo "  HTTP: curl -X POST http://$(hostname -I | awk '{print $1}'):8080 -H 'Content-Type: application/json' -d '{\"message\":\"test\"}'"
echo "  Syslog UDP: logger -n $(hostname -I | awk '{print $1}') -P 5514 'test'"
echo "  Syslog TCP: logger -n $(hostname -I | awk '{print $1}') -P 5601 -T 'test'"
echo ""
