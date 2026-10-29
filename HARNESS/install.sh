#!/usr/bin/env bash
# EasyAIoT HARNESS 安装/构建/启停
# 上级 .scripts/docker/install_*.sh 通过 install_linux.sh 委托本脚本

# 严格模式：`-e`：任意命令失败时立即退出。。`-u`：未定义的变量立即退出。。`-o pipefail`：管道中任意命令失败时立即退出。
set -euo pipefail

# 获取当前脚本`install.sh`所在目录的绝对路径（ROOT就是当前`HARNESS`目录）
ROOT="$(cd "$(dirname "$0")" && pwd)"
# 切换到当前脚本`install.sh`所在目录（即当前`HARNESS`目录）
cd "${ROOT}"

# 获取EasyAIoT根目录（即当前`HARNESS`目录的上一级目录）
EASYAIOT_ROOT="$(cd "${ROOT}/.." && pwd)"
# 加载全局部署规格配置脚本（EasyAIoT根目录/.scripts/docker/deploy_profile.sh）。如果deploy_profile.sh文件不存在或加载失败，错误输出丢弃，并且不终止脚本，`|| true` 表示失败也继续执行
# shellcheck source=../.scripts/docker/deploy_profile.sh
source "${EASYAIOT_ROOT}/.scripts/docker/deploy_profile.sh" 2>/dev/null || true

# 读取第一个命令行参数。
# 例如：`bash install.sh install` 时，`cmd=install` 。
# 例如：`bash install.sh status` 时，`cmd=status` 。
cmd="${1:-help}"

# 确保harness.env文件存在，不存在则从harness.env.example复制成`harness.env`
ensure_env_file() {
  if [[ ! -f "${ROOT}/harness.env" ]]; then
    cp "${ROOT}/harness.env.example" "${ROOT}/harness.env"
    echo "[harness] 已生成 ${ROOT}/harness.env"
  fi
}

# 设置harness.env文件中的变量，如果变量存在则修改，如果变量不存在则添加
# 用法：`set_harness_env_var 变量名 变量值`
# 例如 `set_harness_env_var DEEPSEEK_API_KEY 123456` 会将 `DEEPSEEK_API_KEY=123456` 写入 `harness.env` 文件。如果变量存在则修改，如果变量不存在则添加
set_harness_env_var() {
  local key="$1"
  local val="$2"
  local file="${ROOT}/harness.env"
  ensure_env_file
  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "${file}"
  else
    echo "${key}=${val}" >> "${file}"
  fi
}

# 确保`harness.env`文件中的 DEEPSEEK_API_KEY 变量存在：
# 如果DEEPSEEK_API_KEY 不存在，则交互式询问，提示用户输入，并写入`harness.env`，并把DEEPSEEK_API_KEY导出到当前脚本进程环境变量；
# 如果DEEPSEEK_API_KEY 存在，则跳过。
prompt_deepseek_api_key() {
  if [[ "${EASYAIOT_SKIP_HARNESS_KEY_PROMPT:-0}" = "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "[harness] 非交互环境，跳过 DeepSeek Key 输入（可在 Web UI Settings → Models 中配置）"
    return 0
  fi

  load_env
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    echo "[harness] harness.env 已有 DEEPSEEK_API_KEY，跳过输入（可在 Web UI Settings → Models 修改）"
    return 0
  fi

  echo ""
  echo "[harness] AI 助手需 DeepSeek API Key 才能对话；也可跳过，稍后在 Web UI 配置。"
  echo "[harness] 注册 / 充值：https://platform.deepseek.com/"
  read -r -p "请输入 DeepSeek API Key [回车跳过]: " _ds_key || _ds_key=""
  _ds_key="$(echo "${_ds_key}" | xargs)"
  if [[ -z "${_ds_key}" ]]; then
    echo "[harness] 已跳过 — 打开 :3080 → Settings → Models 填写 Key 即可"
    echo "[harness] 获取 Key：https://platform.deepseek.com/"
    return 0
  fi

  set_harness_env_var DEEPSEEK_API_KEY "${_ds_key}"
  export DEEPSEEK_API_KEY="${_ds_key}"
  echo "[harness] 已写入 harness.env（Web UI 中可随时修改，重启不会覆盖 UI 中的 Key）"
}

# 读取`harness.env` 并把里面的变量导入当前脚本进程环境变量
load_env() {
  ensure_env_file
  if [[ -f "${ROOT}/harness.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${ROOT}/harness.env"
    set +a
  fi
}

# 确保`harness.env`文件中的HARNESS_WORKSPACE_HOST变量存在：
# 如果HARNESS_WORKSPACE_HOST 不存在，则设置为EasyAIoT根目录（HARNESS目录的父目录），并且导出到当前脚本进程环境变量；
# 如果HARNESS_WORKSPACE_HOST 存在，则跳过。
ensure_host_paths() {
  load_env
  if [[ -z "${HARNESS_WORKSPACE_HOST:-}" ]]; then
    export HARNESS_WORKSPACE_HOST="${EASYAIOT_ROOT}"
    set_harness_env_var HARNESS_WORKSPACE_HOST "${EASYAIOT_ROOT}"
    echo "[harness] HARNESS_WORKSPACE_HOST -> ${EASYAIOT_ROOT}"
  fi
  mkdir -p "${ROOT}/.data"
}

# 使用 docker compose 命令
# 如果调用 compose up -d，则执行的是 docker compose -f docker-compose.yml up -d，启动容器
# 如果调用 compose logs -f，则执行的是 docker compose -f docker-compose.yml logs -f，查看日志
# 如果调用 compose ps，则执行的是 docker compose -f docker-compose.yml ps，查看容器状态
# 如果调用 compose down，则执行的是 docker compose -f docker-compose.yml down，停止并移除容器
compose() {
  ensure_host_paths
  if [[ -f "${ROOT}/harness.env" ]]; then
    docker compose -f "${ROOT}/docker-compose.yml" --env-file "${ROOT}/harness.env" "$@"
  else
    docker compose -f "${ROOT}/docker-compose.yml" "$@"
  fi
}

# 检查 `harness.env`文件中 HARNESS_IMAGE 镜像名称是否存在：
# 如果存在，则使用该镜像名称；
# 如果不存在，则使用默认镜像名称 easyaiot/harness:latest
# 最后使用 docker image inspect 命令检查docker镜像是否存在
image_exists() {
  docker image inspect "${HARNESS_IMAGE:-easyaiot/harness:latest}" >/dev/null 2>&1
}

usage() {
  cat <<'EOF'
用法: bash HARNESS/install.sh <command>

  install           构建镜像并启动（统一部署入口）
  build             构建 Docker 镜像
  start             启动服务
  stop / clean      停止并移除容器
  restart           重启
  update / rebuild  重建镜像并重启
  logs              查看日志
  status            健康检查
  help              显示帮助

示例:
  cp HARNESS/harness.env.example HARNESS/harness.env
  bash HARNESS/install.sh install
EOF
}

# 构建 HARNESS Docker 镜像。最终形成的命令如下：
# docker build \
  #  -f "/opt/easyaiot/HARNESS/Dockerfile" \                                 # Dockerfile 路径
  #  -t "easyaiot/harness:latest" \                                          # 镜像名称
  #  --build-arg "DSH_VERSION=0.1.0-rc.6" \                                  # DSH 版本（DeepSeek Harness 版本）
  #  --build-arg "HARNESS_SIDEBAR_PACKAGE=dsh-better-sidebar@0.12.1" \       # 侧边栏插件包
  #  --platform "linux/amd64" \                                              # 平台
  #  "/opt/easyaiot/HARNESS"                                                 # 构建上下文
do_build() {
  load_env
  echo "[harness] building ${HARNESS_IMAGE:-easyaiot/harness:latest} (dsh ${DSH_VERSION:-0.1.0-rc.6})"
  local -a build_args=(
    -f "${ROOT}/Dockerfile"
    -t "${HARNESS_IMAGE:-easyaiot/harness:latest}"
    --build-arg "DSH_VERSION=${DSH_VERSION:-0.1.0-rc.6}"
    --build-arg "HARNESS_SIDEBAR_PACKAGE=${HARNESS_SIDEBAR_PACKAGE:-dsh-better-sidebar@0.12.1}"
  )
  if [[ -n "${DOCKER_PLATFORM:-}" ]]; then
    build_args+=(--platform "${DOCKER_PLATFORM}")
  fi
  docker build "${build_args[@]}" "${ROOT}"
}

# 确保 LLM 统一网关有鉴权 Token 。否则`3082` 网关接口会拒绝访问。也就是说，确保`harness.env`文件中的 LLM_GATEWAY_TOKEN 变量存在：
# 如果 LLM_GATEWAY_TOKEN 不存在，则（优先使用`openssl rand -hex 24`、如果没有`openssl` ，用`/dev/urandom` 兜底）生成一个随机的 Token，并写入`harness.env`，并把 LLM_GATEWAY_TOKEN 导出到当前脚本进程环境变量；
# 如果 LLM_GATEWAY_TOKEN 存在，则跳过。
ensure_llm_gateway_token() {
  ensure_env_file
  load_env
  if [[ -n "${LLM_GATEWAY_TOKEN:-}" ]]; then
    return 0
  fi
  local token
  token="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  set_harness_env_var LLM_GATEWAY_TOKEN "${token}"
  export LLM_GATEWAY_TOKEN="${token}"
  echo "[harness] 已生成 LLM_GATEWAY_TOKEN 写入 harness.env（页面/Agent 调网关需携带此 Token）"
}

# 执行命令：`bash HARNESS/install.sh install` 时的核心逻辑
# 调用compose up -d函数：则执行的是 docker compose -f docker-compose.yml up -d，启动容器
do_install() {
  load_env
  prompt_deepseek_api_key
  ensure_llm_gateway_token
  load_env
  if [[ "${EASYAIOT_SKIP_BUILD:-0}" = "1" ]] && image_exists; then
    echo "[harness] 镜像已存在且 EASYAIOT_SKIP_BUILD=1，跳过构建"
  else
    do_build
  fi
  compose up -d
  echo "[harness] Web UI: http://127.0.0.1:${HARNESS_LISTEN_PORT:-3080}"
  echo "[harness] workspace: ${HARNESS_WORKSPACE_HOST}"
}

# 执行命令：`bash HARNESS/install.sh status` 时的核心逻辑
# 调用compose ps函数：则执行的是 docker compose -f docker-compose.yml ps，查看容器状态
show_status() {
  load_env
  local port="${HARNESS_LISTEN_PORT:-3080}"
  echo "[harness] container:"
  compose ps 2>/dev/null || true
  echo "[harness] HTTP check:"
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" "http://127.0.0.1:${port}/" 2>/dev/null || echo "unreachable"
}

case "${cmd}" in
  # `bash HARNESS/install.sh install`命令：构建镜像并启动（统一部署入口）
  install) do_install ;;
  # `bash HARNESS/install.sh build`命令：构建 Docker 镜像
  build) do_build ;;
  # `bash HARNESS/install.sh start`命令：启动服务
  start)
    load_env
    if ! image_exists; then
      echo "[harness] 镜像不存在，先构建..."
      do_build
    fi
    compose up -d
    echo "[harness] Web UI: http://127.0.0.1:${HARNESS_LISTEN_PORT:-3080}"
    ;;
  # `bash HARNESS/install.sh stop`命令 或 `bash HARNESS/install.sh clean`命令：停止并移除容器
  stop|clean) compose down ;;
  # `bash HARNESS/install.sh restart`命令：重启
  restart)
    bash "${ROOT}/install.sh" stop
    bash "${ROOT}/install.sh" start
    ;;
  # `bash HARNESS/install.sh update`命令 或 `bash HARNESS/install.sh rebuild`命令：重建镜像并重启
  update|rebuild)
    load_env
    if [[ "${EASYAIOT_SKIP_BUILD:-0}" = "1" ]] && image_exists; then
      echo "[harness] 预构建镜像已就绪（EASYAIOT_SKIP_BUILD=1），跳过构建，仅 recreate"
    elif ! command -v git >/dev/null 2>&1 && image_exists; then
      echo "[harness] 未检测到 git，使用本地镜像 recreate（不构建）"
    else
      do_build
    fi
    compose up -d --force-recreate
    echo "[harness] Web UI: http://127.0.0.1:${HARNESS_LISTEN_PORT:-3080}"
    ;;
  # `bash HARNESS/install.sh logs`命令：查看日志
  logs) compose logs -f --tail=200 ;;
  # `bash HARNESS/install.sh status`命令：健康检查
  status) show_status ;;
  # `bash HARNESS/install.sh help`命令 或 `bash HARNESS/install.sh --help`命令 或 `bash HARNESS/install.sh -h`命令：显示帮助
  help|--help|-h) usage ;;
  # 其他无效命令：显示帮助
  *)
    echo "unknown command: ${cmd}" >&2
    usage
    exit 1
    ;;
esac
