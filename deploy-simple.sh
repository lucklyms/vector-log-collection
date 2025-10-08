#!/bin/bash
# 簡化版部署腳本 - 專門給 GitHub Actions 使用

echo "=== Vector 簡化部署 ==="

# 設定變數
LOG_DIR=${LOG_DIR:-/var/log/vector-collected}
CONTAINER_CMD="docker"

# 檢查 Docker 或 Podman
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
    VOLUME_FLAG=":Z"
else
    CONTAINER_CMD="docker"
    VOLUME_FLAG=""
fi

echo "使用容器工具: $CONTAINER_CMD"
echo "日誌目錄: $LOG_DIR"

# 建立目錄
mkdir -p "$LOG_DIR"
mkdir -p iis-logs apache-logs app-logs logs

# 清理舊容器
$CONTAINER_CMD rm -f vector-unified 2>/dev/null || true

# 啟動新容器
$CONTAINER_CMD run -d --name vector-unified \
  -p 8080:8080 \
  -p 5514:5514/udp \
  -p 5601:5601 \
  -p 8686:8686 \
  -v $(pwd)/vector-final.toml:/etc/vector/vector.toml:ro \
  -v $(pwd)/iis-logs:/iis-logs${VOLUME_FLAG} \
  -v $(pwd)/apache-logs:/apache-logs${VOLUME_FLAG} \
  -v $(pwd)/app-logs:/app-logs${VOLUME_FLAG} \
  -v "$LOG_DIR":/var/log/vector${VOLUME_FLAG} \
  timberio/vector:latest-alpine --config /etc/vector/vector.toml

# 等待啟動
sleep 5

# 檢查狀態
if $CONTAINER_CMD ps | grep -q vector-unified; then
    echo "✓ 部署成功！"
    echo "日誌位置: $LOG_DIR"
    $CONTAINER_CMD ps | grep vector-unified
else
    echo "✗ 部署失敗"
    $CONTAINER_CMD logs vector-unified
    exit 1
fi
