#!/bin/bash

# MOCHU-OA V2.0 AI Agent 运行脚本
# 用于循环调用 GLM 模型执行开发任务
# 版本: 2.0.0
# 创建时间: 2026-04-06

set -e  # 遇到错误立即退出

# ==================== 配置 ====================
PROJECT_DIR="/root/.openclaw/workspace/MOCHUOA-V2"
TASK_FILE="$PROJECT_DIR/task.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/agent_$(date +%Y%m%d_%H%M%S).log"

# GLM 模型配置
MODEL_NAME="custom-code-coolyeah-net-glm5/glm-5"

# OpenClaw 配置
SESSION_ID="mochuoa-dev-$(date +%s)"  # 每次运行使用不同的会话ID
THINKING_LEVEL="medium"  # 思考级别: off|minimal|low|medium|high|xhigh
TIMEOUT=600  # 超时时间（秒）

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==================== 日志函数 ====================
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} - $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_section() {
    log "\n${BLUE}========================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}========================================${NC}\n"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

# ==================== 显示使用帮助 ====================
show_usage() {
    echo -e "${CYAN}使用方法:${NC}"
    echo -e "  $0 <运行次数>"
    echo ""
    echo -e "${CYAN}参数说明:${NC}"
    echo -e "  运行次数    指定 GLM 模型执行的次数（正整数）"
    echo ""
    echo -e "${CYAN}示例:${NC}"
    echo -e "  $0 5    # 运行 GLM 模型 5 次，执行 5 个开发任务"
    echo ""
    echo -e "${CYAN}说明:${NC}"
    echo -e "  每次运行 GLM 都会："
    echo -e "  1. 读取 task.json，选择一个未完成的任务"
    echo -e "  2. 按照 CLAUDE.md 中的工作流程执行开发"
    echo -e "  3. 更新 progress.txt 和 task.json"
    echo -e "  4. 提交 Git commit"
    echo ""
    echo -e "${CYAN}环境要求:${NC}"
    echo -e "  - OpenClaw CLI 已安装"
    echo -e "  - GLM-5 模型已配置"
    echo -e "  - 项目已运行 init.sh 初始化"
    exit 1
}

# ==================== 检查参数 ====================
check_parameters() {
    if [ $# -ne 1 ]; then
        log_error "参数数量错误"
        show_usage
    fi
    
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
        log_error "参数必须是正整数"
        show_usage
    fi
    
    if [ $1 -le 0 ]; then
        log_error "参数必须大于 0"
        show_usage
    fi
    
    RUN_COUNT=$1
}

# ==================== 初始化环境 ====================
init_environment() {
    log_section "初始化环境"
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    log_info "日志目录创建完成: $LOG_DIR"
    
    # 检查必要文件是否存在
    if [ ! -f "$TASK_FILE" ]; then
        log_error "task.json 文件不存在: $TASK_FILE"
        exit 1
    fi
    log_info "task.json 文件检查通过"
    
    if [ ! -f "$PROGRESS_FILE" ]; then
        log_error "progress.txt 文件不存在: $PROGRESS_FILE"
        exit 1
    fi
    log_info "progress.txt 文件检查通过"
    
    if [ ! -f "$CLAUDE_MD" ]; then
        log_error "CLAUDE.md 文件不存在: $CLAUDE_MD"
        exit 1
    fi
    log_info "CLAUDE.md 文件检查通过"
    
    # 检查 OpenClaw CLI
    if ! command -v openclaw &> /dev/null; then
        log_error "OpenClaw CLI 未安装"
        log_info "请安装 OpenClaw CLI: npm install -g openclaw"
        exit 1
    fi
    log_info "OpenClaw CLI 检查通过: $(command -v openclaw)"
    
    # 切换到项目目录
    cd "$PROJECT_DIR"
    log_info "工作目录: $(pwd)"
    
    # 检查是否需要先运行 init.sh
    if [ ! -d "backend" ]; then
        log_warn "项目目录结构未初始化"
        log_info "请先运行: ./init.sh"
        read -p "$(echo -e ${GREEN}是否现在运行 init.sh? (y/n): ${NC})" run_init
        if [ "$run_init" = "y" ]; then
            log_info "正在运行 init.sh..."
            chmod +x init.sh
            ./init.sh
        else
            log_error "请手动运行 init.sh 初始化项目环境"
            exit 1
        fi
    fi
    
    log_success "环境初始化完成"
}

# ==================== 统计任务状态 ====================
count_pending_tasks() {
    # 使用 jq 统计 pending 状态的任务数量
    if command -v jq &> /dev/null; then
        local count=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASK_FILE")
        echo $count
    else
        # 如果没有 jq，返回一个估计值
        echo "unknown"
    fi
}

# ==================== 构建提示词 ====================
build_prompt() {
    local iteration=$1
    
    cat << EOF
你是 MOCHU-OA V2.0 施工管理系统的 AI 开发助手。

**重要提示：请仔细阅读以下工作流程**

当前是第 ${iteration} 次运行。请按照以下步骤工作：

## 步骤 1: 读取任务列表
首先读取 $CLAUDE_MD 文件，了解完整的工作流程和开发规范。
然后读取 $TASK_FILE 文件，找到一个状态为 "pending" 的任务。

## 步骤 2: 选择任务
选择任务的优先级规则：
1. 优先选择 priority 为 "high" 的任务
2. 检查任务的 dependencies，确保依赖的任务都已完成
3. 如果有多个符合条件的任务，选择 id 最小的那个

## 步骤 3: 标记任务开始
在 task.json 中更新任务状态为 "in_progress"，并记录 started_at 时间。
同时在 progress.txt 中添加记录。

## 步骤 4: 执行开发
根据任务描述进行开发，遵循 CLAUDE.md 中定义的代码规范和测试要求。

## 步骤 5: 测试验证
开发完成后，编写单元测试并运行测试确保通过。

## 步骤 6: 更新进度文件
在 progress.txt 中详细记录完成的工作。

## 步骤 7: 更新任务状态
在 task.json 中更新任务状态为 "completed"，并记录 completed_at 时间。

## 步骤 8: Git 提交
使用 Git 提交代码，提交信息格式：[TASK-XXX] 简短描述

## 遇到困难时
如果遇到需求不明确、技术选型困难、依赖阻塞等问题，在 progress.txt 中记录并向人类求助。

**现在开始工作！请从 task.json 中选择一个任务并开始执行。**
EOF
}

# ==================== 调用 GLM 模型 ====================
call_glm_agent() {
    local iteration=$1
    local prompt=$(build_prompt $iteration)
    
    log_section "第 $iteration/$RUN_COUNT 次调用 GLM"
    
    # 显示当前任务状态
    local pending_count=$(count_pending_tasks)
    log_info "当前待处理任务数量: $pending_count"
    
    # 记录开始时间
    local start_time=$(date +%s)
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 保存提示词到文件（用于调试）
    local prompt_file="$LOG_DIR/prompt_${iteration}.txt"
    echo "$prompt" > "$prompt_file"
    log_info "提示词已保存到: $prompt_file"
    
    # 调用 OpenClaw Agent
    log_info "正在调用 OpenClaw Agent..."
    log_info "模型: $MODEL_NAME"
    log_info "会话ID: $SESSION_ID"
    log_info "思考级别: $THINKING_LEVEL"
    log_info "超时时间: ${TIMEOUT}秒"
    
    # 使用 openclaw agent 命令调用
    # --local: 本地运行（不通过Gateway）
    # --message: 传递提示词
    # --session-id: 会话ID（保持上下文）
    # --thinking: 思考级别
    # --timeout: 超时时间
    
    if openclaw agent \
        --local \
        --message "$prompt" \
        --session-id "$SESSION_ID" \
        --thinking "$THINKING_LEVEL" \
        --timeout "$TIMEOUT" \
        --verbose on \
        2>&1 | tee -a "$LOG_FILE"; then
        
        log_success "第 $iteration 次调用成功"
    else
        log_error "第 $iteration 次调用失败"
        log_warn "请检查日志文件: $LOG_FILE"
        # 继续执行，不退出
    fi
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_success "第 $iteration 次调用完成，耗时: ${duration} 秒"
    
    # 短暂暂停，让系统有时间处理
    sleep 2
}

# ==================== 主函数 ====================
main() {
    log_section "MOCHU-OA V2.0 AI Agent 运行脚本"
    
    log_info "运行次数: $RUN_COUNT"
    log_info "项目目录: $PROJECT_DIR"
    log_info "模型: $MODEL_NAME"
    log_info "会话ID: $SESSION_ID"
    
    # 循环调用 GLM
    for ((i=1; i<=RUN_COUNT; i++)); do
        call_glm_agent $i
        
        # 检查是否还有待处理的任务
        local pending_count=$(count_pending_tasks)
        if [ "$pending_count" = "0" ]; then
            log_success "所有任务已完成！"
            break
        fi
        
        # 如果不是最后一次，显示进度
        if [ $i -lt $RUN_COUNT ]; then
            log_info "进度: $i/$RUN_COUNT 完成"
            log_info "剩余待处理任务: $pending_count"
            log_info "等待 5 秒后继续下一次迭代..."
            sleep 5
        fi
    done
    
    log_section "运行完成"
    
    # 最终统计
    log_info "总运行次数: $RUN_COUNT"
    log_info "日志文件: $LOG_FILE"
    
    # 显示最终任务状态
    local final_pending=$(count_pending_tasks)
    log_info "剩余待处理任务: $final_pending"
    
    if [ "$final_pending" = "0" ]; then
        log_success "🎉 恭喜！所有任务已完成！"
    else
        log_warn "仍有 $final_pending 个任务待处理"
        log_info "可以再次运行本脚本继续处理剩余任务"
    fi
}

# ==================== 脚本入口 ====================
# 检查参数
check_parameters "$@"

# 初始化环境
init_environment

# 执行主函数
main

# 退出
exit 0
