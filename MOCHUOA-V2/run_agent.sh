#!/bin/bash

# MOCHU-OA V2.0 AI Agent 运行脚本
# 用于循环调用 GLM 模型执行开发任务
# 版本: 1.0.0
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
    
    # 切换到项目目录
    cd "$PROJECT_DIR"
    log_info "工作目录: $(pwd)"
    
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

请严格按照 $CLAUDE_MD 中定义的工作流程执行任务：

**工作流程：**
1. 读取 task.json 文件
2. 选择一个状态为 "pending" 的任务（优先选择 priority 为 "high" 的任务）
3. 标记任务为 "in_progress"
4. 执行开发任务
5. 测试验证
6. 更新 progress.txt 和 task.json
7. 使用 Git 提交代码

**当前迭代：** 第 $iteration 次运行

**重要提醒：**
- 仔细阅读 CLAUDE.md 中的所有规范
- 遇到困难时，在 progress.txt 中记录并向人类求助
- 每完成一个任务都要 Git commit
- 保持代码质量，编写测试

现在开始工作！请从 task.json 中选择一个任务并开始执行。
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
    
    # 调用 OpenClaw 的 sessions_spawn 工具
    # 注意：这里使用 OpenClaw 的工具调用方式
    # 由于我们在 shell 脚本中，我们需要使用 openclaw CLI 或其他方式
    
    # 方法1: 如果有 openclaw CLI 工具
    if command -v openclaw &> /dev/null; then
        log_info "使用 OpenClaw CLI 调用 GLM 模型"
        log_info "模型: $MODEL_NAME"
        log_info "工作目录: $PROJECT_DIR"
        
        # 使用 openclaw 命令行工具
        # 这里假设 openclaw 有一个 run 或 exec 子命令
        # 需要根据实际的 OpenClaw CLI 语法调整
        
        # 记录提示词到文件
        local prompt_file="$LOG_DIR/prompt_${iteration}.txt"
        echo "$prompt" > "$prompt_file"
        log_info "提示词已保存到: $prompt_file"
        
        # 调用模型（这里需要根据实际的 OpenClaw API 调整）
        # 假设使用某种方式调用 GLM
        # 例如：通过 HTTP API、CLI 工具等
        
        log_warn "请手动执行以下命令来调用 GLM："
        echo ""
        echo "  cd $PROJECT_DIR"
        echo "  # 使用你的 GLM 客户端工具，传入以下提示词："
        echo "  # 提示词文件: $prompt_file"
        echo ""
        
    else
        # 方法2: 如果没有 CLI，提供手动调用指南
        log_warn "未检测到 OpenClaw CLI 工具"
        log_info "请手动调用 GLM 模型，使用以下信息："
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}手动调用信息${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "模型名称: ${YELLOW}$MODEL_NAME${NC}"
        echo -e "工作目录: ${YELLOW}$PROJECT_DIR${NC}"
        echo -e "提示词文件: ${YELLOW}$LOG_DIR/prompt_${iteration}.txt${NC}"
        echo ""
        echo -e "提示词内容:"
        echo -e "${YELLOW}----------------------------------------${NC}"
        echo "$prompt"
        echo -e "${YELLOW}----------------------------------------${NC}"
        echo ""
        
        # 保存提示词到文件
        echo "$prompt" > "$LOG_DIR/prompt_${iteration}.txt"
        
        # 等待用户确认
        read -p "$(echo -e ${GREEN}按 Enter 键继续下一次迭代，或输入 'q' 退出...${NC})" user_input
        if [ "$user_input" = "q" ]; then
            log_info "用户选择退出"
            exit 0
        fi
    fi
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "第 $iteration 次调用完成，耗时: ${duration} 秒"
}

# ==================== 主函数 ====================
main() {
    log_section "MOCHU-OA V2.0 AI Agent 运行脚本"
    
    log_info "运行次数: $RUN_COUNT"
    log_info "项目目录: $PROJECT_DIR"
    log_info "模型: $MODEL_NAME"
    
    # 检查是否需要先运行 init.sh
    if [ ! -d "$PROJECT_DIR/backend" ]; then
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
