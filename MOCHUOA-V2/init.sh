#!/bin/bash

# MOCHU-OA V2.0 项目初始化脚本
# 版本: 1.0.0
# 创建时间: 2026-04-06

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装，请先安装 $1"
        return 1
    else
        log_info "$1 已安装: $(command -v $1)"
        return 0
    fi
}

# 主初始化流程
main() {
    log_section "MOCHU-OA V2.0 项目初始化开始"
    
    # 1. 检查系统依赖
    log_section "步骤 1/6: 检查系统依赖"
    
    log_info "检查 Java..."
    check_command java || {
        log_warn "Java 未安装，建议安装 JDK 17+"
    }
    
    log_info "检查 Node.js..."
    check_command node || {
        log_warn "Node.js 未安装，建议安装 Node.js 18+"
    }
    
    log_info "检查 npm..."
    check_command npm || {
        log_warn "npm 未安装"
    }
    
    log_info "检查 MySQL 客户端..."
    check_command mysql || {
        log_warn "MySQL 客户端未安装"
    }
    
    log_info "检查 Redis 客户端..."
    check_command redis-cli || {
        log_warn "Redis 客户端未安装"
    }
    
    log_info "检查 Git..."
    check_command git || {
        log_error "Git 未安装，这是必需的"
        exit 1
    }
    
    # 2. 创建项目目录结构
    log_section "步骤 2/6: 创建项目目录结构"
    
    # 后端目录结构
    mkdir -p backend/src/main/java/com/mochu/oa
    mkdir -p backend/src/main/resources
    mkdir -p backend/src/test/java/com/mochu/oa
    mkdir -p backend/db/migration
    mkdir -p backend/db/rollback
    
    # 前端目录结构
    mkdir -p frontend/src/views
    mkdir -p frontend/src/components
    mkdir -p frontend/src/api
    mkdir -p frontend/src/router
    mkdir -p frontend/src/store
    mkdir -p frontend/src/utils
    mkdir -p frontend/public
    
    # 文档目录
    mkdir -p docs/api
    mkdir -p docs/design
    mkdir -p docs/deployment
    
    # 脚本目录
    mkdir -p scripts
    
    log_info "项目目录结构创建完成"
    
    # 3. 初始化 Git 仓库
    log_section "步骤 3/6: 初始化 Git 仓库"
    
    if [ ! -d ".git" ]; then
        git init
        log_info "Git 仓库初始化完成"
    else
        log_info "Git 仓库已存在"
    fi
    
    # 4. 创建配置文件
    log_section "步骤 4/6: 创建配置文件"
    
    # 创建后端配置文件模板
    cat > backend/src/main/resources/application.yml.template << 'EOF'
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/mochu_oa?useUnicode=true&characterEncoding=utf8mb4&serverTimezone=Asia/Shanghai
    username: root
    password: your_password
    driver-class-name: com.mysql.cj.jdbc.Driver
  
  redis:
    host: localhost
    port: 6379
    password: 
    database: 0
  
  servlet:
    multipart:
      max-file-size: 50MB
      max-request-size: 500MB

server:
  port: 8080

mybatis-plus:
  mapper-locations: classpath*:/mapper/**/*.xml
  type-aliases-package: com.mochu.oa.entity
  global-config:
    db-config:
      logic-delete-field: deleted
      logic-delete-value: 1
      logic-not-delete-value: 0

minio:
  endpoint: http://localhost:9000
  access-key: minioadmin
  secret-key: minioadmin
  bucket-name: mochu-oa

jwt:
  secret: your_jwt_secret_key_here
  expiration: 2592000000  # 30天
EOF
    
    log_info "配置文件模板创建完成"
    
    # 5. 创建 README
    log_section "步骤 5/6: 创建项目文档"
    
    cat > README.md << 'EOF'
# MOCHU-OA V2.0 施工管理系统

## 项目简介

MOCHU-OA 是一个面向中小型施工企业的综合管理系统，支持项目全生命周期管理、合同管理、物资管理、财务管理等核心业务。

## 技术栈

### 后端
- Spring Boot 3.x (JDK 17+)
- MyBatis-Plus
- MySQL 8.0
- Redis 7.x
- MinIO

### 前端
- Vue 3
- Element Plus
- Axios

## 快速开始

### 环境要求
- JDK 17+
- Node.js 18+
- MySQL 8.0
- Redis 7.x

### 初始化项目
```bash
chmod +x init.sh
./init.sh
```

### 启动后端
```bash
cd backend
mvn spring-boot:run
```

### 启动前端
```bash
cd frontend
npm install
npm run dev
```

## 开发指南

请查看 [CLAUDE.md](./CLAUDE.md) 了解 AI 辅助开发流程。

## 文档

- [需求规格说明书 V3.2](./docs/requirements/)
- [API 文档](./docs/api/)
- [部署指南](./docs/deployment/)

## License

商业机密 - 未经授权禁止使用
EOF
    
    log_info "README.md 创建完成"
    
    # 6. 更新 progress.txt
    log_section "步骤 6/6: 更新进度日志"
    
    echo "" >> progress.txt
    echo "### $(date '+%Y-%m-%d %H:%M:%S') - 项目初始化完成" >> progress.txt
    echo "- **操作者**: init.sh 脚本" >> progress.txt
    echo "- **操作**: 执行项目初始化" >> progress.txt
    echo "- **状态**: 成功" >> progress.txt
    echo "- **详情**: " >> progress.txt
    echo "  - 检查了系统依赖" >> progress.txt
    echo "  - 创建了项目目录结构" >> progress.txt
    echo "  - 初始化了 Git 仓库" >> progress.txt
    echo "  - 创建了配置文件模板" >> progress.txt
    echo "  - 创建了项目文档" >> progress.txt
    echo "" >> progress.txt
    
    log_section "初始化完成！"
    
    log_info "下一步操作："
    log_info "1. 配置 backend/src/main/resources/application.yml"
    log_info "2. 创建 MySQL 数据库: mochu_oa"
    log_info "3. 启动 Redis 服务"
    log_info "4. 运行 ./run_agent.sh <次数> 开始 AI 辅助开发"
}

# 执行主函数
main
