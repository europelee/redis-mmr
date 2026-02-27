# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码仓库中工作提供指导。

## 项目概述

这是 **Redis** 代码仓库 - 一个用作数据库、缓存、消息代理等的内存数据结构存储系统。代码库主要用 C 语言编写，部分模块（如 RedisJSON）使用 Rust。

## 构建命令

### 基本构建
```sh
make                       # 构建核心 Redis
make test                  # 运行测试套件
make clean                 # 清理构建产物
make distclean             # 清理所有内容，包括缓存的构建选项
```

### 带模块构建（查询引擎、布隆过滤器、JSON 等）
```sh
make BUILD_WITH_MODULES=yes
```

### 带 TLS 支持构建
```sh
make BUILD_TLS=yes
```

### 常用构建标志
- `BUILD_WITH_MODULES=yes` - 包含 RedisJSON、时间序列、布隆过滤器、布谷鸟过滤器、count-min sketch、top-k、t-digest 和 Redis 查询引擎
- `BUILD_TLS=yes` - 启用 TLS 支持
- `USE_SYSTEMD=yes` - 构建 systemd 支持
- `MALLOC=libc` - 使用 libc malloc 而非 jemalloc（非 Linux 系统默认）
- `32bit` - 构建 32 位二进制文件
- `V=1` - 详细构建输出
- `DISABLE_WERRORS=yes` - 禁用模块的 -Werror（开发时有用）
- `INSTALL_RUST_TOOLCHAIN=yes` - 安装模块所需的 Rust 工具链
- `BUILD_INTEL_SVS_OPT=yes` - 构建 Intel SVS-VAMANA 优化（仅限 RSALv2 许可）

### 完整构建（所有功能）
```sh
export BUILD_TLS=yes BUILD_WITH_MODULES=yes INSTALL_RUST_TOOLCHAIN=yes DISABLE_WERRORS=yes
make -j "$(nproc)" all
```

## 运行 Redis
```sh
./src/redis-server redis-full.conf   # 使用完整配置启动服务器
./src/redis-cli                       # 使用 CLI 连接
```

## 运行测试

### 测试套件
```sh
make test                             # 运行所有测试
./runtest --tls                       # 使用 TLS 运行测试
```

### 选择性测试
```sh
./runtest --single unit/expire        # 运行单个测试文件
./runtest --only-tests unit/acl       # 运行匹配模式的测试
```

### 测试选项
- `--tls` - 使用 TLS 运行
- `--valgrind` - 使用 valgrind 运行
- `--quiet` - 安静模式
- `--verbose` - 详细输出
- `--stop-on-failure` - 首次失败时停止
- `--single <test>` - 运行单个测试
- `--accurate` - 运行更精确（更慢）的测试

## 架构概览

### 核心源码 (`src/`)
- `server.c` - 主服务器逻辑和命令分发
- `db.c` - 数据库操作
- `networking.c` - 客户端连接处理
- `aof.c` / `rdb.c` - 持久化（AOF 和 RDB 快照）
- `replication.c` - 主从复制
- `cluster.c` / `cluster_legacy.c` - 集群实现
- `eval.c` / `script.c` - Lua 脚本引擎
- `module.c` - 模块 API 实现
- `pubsub.c` - 发布/订阅消息
- `stream.c` - 流数据类型

### 关键数据结构
- `dict.c` - 哈希表实现
- `adlist.c` - 双向链表
- `sds.c` - 简单动态字符串
- `rax.c` - 基数树
- `quicklist.c` - ziplist 链表
- `listpack.c` - 顺序数据结构

### 事件循环 (`ae.c`)
具有可插拔事件处理程序的抽象事件循环：
- `ae_select.c` - select() 后端
- `ae_epoll.c` - epoll() 后端（Linux）
- `ae_kqueue.c` - kqueue() 后端（BSD/macOS）
- `ae_evport.c` - event ports（Solaris）

### 模块 (`modules/`)
- `redisjson/` - JSON 数据类型和查询支持
- `redisearch/` - 全文搜索和查询引擎
- `redistimeseries/` - 时间序列数据类型
- `redisbloom/` - 布隆过滤器、布谷鸟过滤器、count-min sketch、top-k、t-digest
- `vector-sets/` - 带有 VAMANA 索引的向量集数据类型

### 测试 (`tests/`)
- `tests/unit/` - 核心功能的单元测试
- `tests/unit/type/` - 特定数据类型的测试
- `tests/unit/moduleapi/` - 模块 API 测试
- `tests/unit/cluster/` - 集群测试
- `tests/integration/` - 集成测试
- `tests/test_helper.tcl` - 主测试运行器（基于 Tcl）

## 关键开发说明

### 依赖项
依赖项位于 `deps/`（hiredis、lua、jemalloc、linenoise 等）。修改后不会自动重新构建 - 更新依赖后请运行 `make distclean`。

### 命令定义
Redis 命令在 `src/commands/` 下的 JSON 文件中定义，并生成到 `src/commands.c`。

### 编码规范
- C99 标准（支持时使用 C11 原子操作）
- 使用 `-Werror` 严格警告（开发时模块可使用 `DISABLE_WERRORS=yes`）
- 静态函数使用 `REDIS_STATIC`
- 保留帧指针用于性能分析（`-fno-omit-frame-pointer`）

### TLS 开发
使用 TLS 代码时，生成测试证书：
```sh
./utils/gen-test-certs.sh
```

### 内存调试
```sh
make SANITIZER=address    # AddressSanitizer
make SANITIZER=undefined  # UndefinedBehaviorSanitizer
make SANITIZER=thread     # ThreadSanitizer
make SANITIZER=memory     # MemorySanitizer（仅 clang）
```

## 故障排除

### 从头重新构建
```sh
make distclean   # 清理所有内容并重新构建
```

### 32 位构建问题
```sh
# 安装 libc6-dev-i386 和 g++-multilib，然后：
make CFLAGS="-m32 -march=native" LDFLAGS="-m32"
```

### 模块构建问题
```sh
# 对于模块，确保安装 Rust：
make INSTALL_RUST_TOOLCHAIN=yes
```
