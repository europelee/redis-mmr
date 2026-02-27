#!/bin/bash

# 测试 db_sd_list 功能的脚本
# 启动一个master和一个slave

REDIS_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_SERVER="$REDIS_DIR/src/redis-server"
REDIS_CLI="$REDIS_DIR/src/redis-cli"

MASTER_PORT=6379
SLAVE_PORT=6380

MASTER_DIR="$REDIS_DIR/test_master"
SLAVE_DIR="$REDIS_DIR/test_slave"

# 清理旧数据
cleanup() {
    echo "清理旧进程和数据..."
    $REDIS_CLI -p $MASTER_PORT SHUTDOWN NOSAVE 2>/dev/null
    $REDIS_CLI -p $SLAVE_PORT SHUTDOWN NOSAVE 2>/dev/null
    sleep 1
    rm -rf "$MASTER_DIR" "$SLAVE_DIR"
}

# 启动函数
start_servers() {
    # 创建数据目录
    mkdir -p "$MASTER_DIR" "$SLAVE_DIR"

    # 创建 Master 配置文件
    cat > "$MASTER_DIR/redis.conf" <<EOF
port $MASTER_PORT
dir $MASTER_DIR
dbfilename dump.rdb
db_sd_list "0,1,2"
daemonize yes
logfile $MASTER_DIR/redis.log
pidfile $MASTER_DIR/redis.pid
EOF

    echo "启动 Master (端口 $MASTER_PORT)..."
    $REDIS_SERVER "$MASTER_DIR/redis.conf"

    sleep 1

    echo "启动 Slave (端口 $SLAVE_PORT)..."
    $REDIS_SERVER --port $SLAVE_PORT \
        --dir "$SLAVE_DIR" \
        --dbfilename "dump.rdb" \
        --db_sd_list "0,1,2" \
        --replicaof 127.0.0.1 $MASTER_PORT \
        --daemonize yes \
        --logfile "$SLAVE_DIR/redis.log" \
        --pidfile "$SLAVE_DIR/redis.pid"

    sleep 2

    echo ""
    echo "=== 服务器状态 ==="
    echo "Master:"
    $REDIS_CLI -p $MASTER_PORT PING
    echo "Slave:"
    $REDIS_CLI -p $SLAVE_PORT PING
    echo ""
    echo "复制状态:"
    $REDIS_CLI -p $SLAVE_PORT INFO replication | grep -E "role|master_link_status"
}

# 测试函数
test_db_sd_list() {
    echo ""
    echo "=== 测试 db_sd_list ==="
    
    # 在 db 0 写入数据 (应该同步)
    echo "在 db 0 写入数据 (在 db_sd_list 中)..."
    $REDIS_CLI -p $MASTER_PORT -n 0 SET key_db0 "value_db0"
    
    # 在 db 1 写入数据 (应该同步)
    echo "在 db 1 写入数据 (在 db_sd_list 中)..."
    $REDIS_CLI -p $MASTER_PORT -n 1 SET key_db1 "value_db1"
    
    # 在 db 5 写入数据 (不应该同步)
    echo "在 db 5 写入数据 (不在 db_sd_list 中)..."
    $REDIS_CLI -p $MASTER_PORT -n 5 SET key_db5 "value_db5"
    
    sleep 1
    
    echo ""
    echo "=== 验证同步结果 ==="
    
    # 检查 slave 上的数据
    echo "Slave db 0 (应该有数据):"
    $REDIS_CLI -p $SLAVE_PORT -n 0 GET key_db0
    
    echo "Slave db 1 (应该有数据):"
    $REDIS_CLI -p $SLAVE_PORT -n 1 GET key_db1
    
    echo "Slave db 5 (不应该有数据):"
    $REDIS_CLI -p $SLAVE_PORT -n 5 GET key_db5
}

# 停止函数
stop_servers() {
    echo ""
    echo "停止服务器..."
    $REDIS_CLI -p $MASTER_PORT SHUTDOWN NOSAVE 2>/dev/null
    $REDIS_CLI -p $SLAVE_PORT SHUTDOWN NOSAVE 2>/dev/null
    echo "已停止"
}

# 主逻辑
case "${1:-start}" in
    start)
        cleanup
        start_servers
        echo ""
        echo "使用方法:"
        echo "  $0 test    - 运行测试"
        echo "  $0 stop    - 停止服务器"
        echo "  $0 cleanup - 清理所有数据"
        ;;
    test)
        test_db_sd_list
        ;;
    stop)
        stop_servers
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "用法: $0 {start|test|stop|cleanup}"
        exit 1
        ;;
esac
