#!/usr/bin/env bash
# EasyAIoT HARNESS — 启动 DeepSeek Harness Web UI
set -euo pipefail

WORKSPACE="${HARNESS_WORKSPACE:-/workspace/easyaiot}"
mkdir -p "${DSH_HOME:-/data/dsh-home}" "${WORKSPACE}"

# 设置 Node.js 模块查找路径。目的：让后面的 TypeScript 插件能找到 DeepSeek Harness 自带的依赖，比如`@deepseek-ai/dsh-tools` 、`@deepseek-ai/cordis` 。
export NODE_PATH="/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules${NODE_PATH:+:${NODE_PATH}}"

# plugins 目录可经 volume 热挂载（免重建镜像）；volume 会遮蔽构建期 node_modules 符号链接，这里补齐
# 补齐 HARNESS 插件目录下的依赖软链接。原因是`docker-compose.yml` 里会把宿主机的`HARNESS/plugins` 挂载到容器的`/harness/plugins`，这个挂载会覆盖 Dockerfile 构建期创建的`node_modules` 软链接，所以容器启动时要重新创建。
mkdir -p /harness/plugins/node_modules/@deepseek-ai
ln -sfn /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tools \
  /harness/plugins/node_modules/@deepseek-ai/dsh-tools
ln -sfn /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/cordis \
  /harness/plugins/node_modules/@deepseek-ai/cordis

# 执行品牌脚本apply-branding.sh，应用 EasyAIoT 品牌样式，替换图标、标题、页面文案等，修正 HARNESS UI 的品牌表现。
if [[ -x /harness/image/apply-branding.sh ]]; then
  /harness/image/apply-branding.sh
fi

# 把 HARNESS 的项目本体文件`AGENTS.md`（EasyAIoT 的项目知识说明）注入到工作区根目录。
ONTOLOGY="/harness/ontology/AGENTS.md"
if [[ -d "${WORKSPACE}" && -f "${ONTOLOGY}" ]]; then
  if [[ ! -e "${WORKSPACE}/AGENTS.md" ]]; then
    ln -sf "${ONTOLOGY}" "${WORKSPACE}/AGENTS.md" 2>/dev/null \
      || cp "${ONTOLOGY}" "${WORKSPACE}/AGENTS.md"
    echo "[harness] linked ontology -> ${WORKSPACE}/AGENTS.md"
  fi
fi

# 默认 Cursor Light 浅色主题
# 设置 HARNESS 默认主题为浅色`light` 。
SETTINGS_FILE="${DSH_HOME:-/data/dsh-home}/settings.yaml"
if [[ ! -f "${SETTINGS_FILE}" ]]; then
  cat > "${SETTINGS_FILE}" <<'EOF'
ui-theme:
  preference: light
EOF
  echo "[harness] seeded ui-theme preference=light"
elif grep -q '^ui-theme:' "${SETTINGS_FILE}"; then
  python3 - <<'PY' "${SETTINGS_FILE}"
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
newt = re.sub(r"(ui-theme:\n(?:  .*\n)*?  preference:\s*)\S+", r"\1light", t, count=1)
if "ui-theme:" in t and "preference:" in t:
    if newt != t:
        p.write_text(newt, encoding="utf-8")
        print("updated ui-theme preference=light")
    else:
        # ensure preference line is dark
        if re.search(r"preference:\s*light\b", t):
            print("ui-theme already light")
        else:
            t2 = re.sub(r"(preference:\s*)\S+", r"\1light", t, count=1)
            p.write_text(t2, encoding="utf-8")
            print("forced ui-theme preference=light")
else:
    p.write_text(t.rstrip() + "\n\nui-theme:\n  preference: light\n", encoding="utf-8")
    print("appended ui-theme preference=light")
PY
else
  printf '\nui-theme:\n  preference: light\n' >> "${SETTINGS_FILE}"
  echo "[harness] appended ui-theme preference=light"
fi

# 预装 / 补齐文件树侧边栏等 UX 插件（失败不阻断启动）
# 启动时安装或补齐 UX 插件，比如文件树侧边栏。
if [[ -x /harness/scripts/ensure-ux-plugins.sh ]]; then
  /harness/scripts/ensure-ux-plugins.sh || true
fi

# 只要 EasyAIoT 项目工作区：清掉 /harness 历史会话与其它工作区残留
# 清理旧会话和错误工作区残留。
if [[ -x /harness/scripts/purge-harness-workspace.sh ]]; then
  /harness/scripts/purge-harness-workspace.sh || true
fi

# 准备启动`dsh` 的参数。
PUBLIC_PORT="${HARNESS_LISTEN_PORT:-3080}"
DSH_PORT="${HARNESS_DSH_INTERNAL_PORT:-3081}"
HOST="127.0.0.1"

# 启动`dsh` 的参数数组
LAUNCHER=(--profile web --host "${HOST}" --port "${DSH_PORT}")

# 这个 patch 用来加载 EasyAIoT 插件、调整 Harness 行为等
if [[ -f /harness/cordis.patch.yml ]]; then
  LAUNCHER=(--profile web --patch /harness/cordis.patch.yml --host "${HOST}" --port "${DSH_PORT}")
fi

# 处理可信 Host 列表。用途：允许 WEB 或 IDEA 门户通过 iframe/跨域方式嵌入或访问 HARNESS。
if [[ -n "${HARNESS_TRUSTED_HOSTS:-}" ]]; then
  IFS=',' read -ra TRUSTED <<< "${HARNESS_TRUSTED_HOSTS}"
  for th in "${TRUSTED[@]}"; do
    th="$(echo "${th}" | xargs)"
    [[ -n "${th}" ]] && LAUNCHER+=(--trusted-host "${th}")
  done
fi

# 打印启动信息
echo "[harness] starting dsh internal ${HOST}:${DSH_PORT}, public 0.0.0.0:${PUBLIC_PORT}"
echo "[harness] workspace=${WORKSPACE} DSH_HOME=${DSH_HOME:-/data/dsh-home}"

# 把环境变量中的模型 Key 初始化到 HARNESS 的凭据文件。
CRED_FILE="${DSH_HOME:-/data/dsh-home}/.credentials.yaml"
if [[ -n "${OPENAI_API_KEY:-}" || -n "${DEEPSEEK_API_KEY:-}" ]]; then
  if [[ -f "${CRED_FILE}" && -s "${CRED_FILE}" ]]; then
    echo "[harness] ${CRED_FILE} already exists — keep Web UI key settings (env seed skipped)"
  else
    mkdir -p "$(dirname "${CRED_FILE}")"
    chmod 700 "$(dirname "${CRED_FILE}")"
    {
      echo "# auto-seeded from HARNESS/harness.env at first container start"
      [[ -n "${DEEPSEEK_API_KEY:-}" ]] && printf 'DEEPSEEK_API_KEY: "%s"\n' "${DEEPSEEK_API_KEY}"
      [[ -n "${OPENAI_API_KEY:-}" ]] && printf 'OPENAI_API_KEY: "%s"\n' "${OPENAI_API_KEY}"
    } > "${CRED_FILE}"
    chmod 600 "${CRED_FILE}"
    echo "[harness] seeded ${CRED_FILE} from environment"
  fi
fi

# 关键：必须从仓库根启动，否则新会话 cwd=/harness，侧边栏只看得到镜像内文件
# 确保工作区存在，并切换到工作区目录。
if [[ ! -d "${WORKSPACE}" ]]; then
  echo "[harness] ERROR: workspace dir missing: ${WORKSPACE}" >&2
  exit 1
fi
cd "${WORKSPACE}"
echo "[harness] process cwd=$(pwd) (explorer root = session cwd)"

# 旧会话若 cwd=/harness，资源管理器只会显示镜像目录（启动时已自动清理）
# 检查旧的错误会话是否还存在，如果还存在，就打印警告。
if [[ -d "${DSH_HOME:-/data/dsh-home}/sessions/--harness--" ]]; then
  echo "[harness] WARN: sessions/--harness-- still present after purge"
fi

# 启动 DeepSeek Harness Web UI。命令是： dsh --profile web --patch /harness/cordis.patch.yml --host 127.0.0.1 --port 3081
dsh "${LAUNCHER[@]}" &
DSH_PID=$!

# 等待`dsh` 服务启动成功。这里使用 curl 检查`dsh` 是否启动成功。最多检查 90 次，每次间隔 1 秒，也就是最多等 90 秒。
for _ in $(seq 1 90); do
  if curl -fsS "http://${HOST}:${DSH_PORT}/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${DSH_PID}" 2>/dev/null; then
    wait "${DSH_PID}" || true
    exit 1
  fi
  sleep 1
done

echo "[harness] dsh ready, socat 0.0.0.0:${PUBLIC_PORT} -> ${HOST}:${DSH_PORT}"
echo "[harness] note: standalone browser access is redirected by brand.js to IDEA portal"

# LLM 统一网关（easyaiot-llm-gateway 插件监听 127.0.0.1:LLM_GATEWAY_PORT），对外暴露同号端口
# 暴露 LLM 统一网关端口
LLM_GATEWAY_PORT="${LLM_GATEWAY_PORT:-3082}"
socat TCP-LISTEN:"${LLM_GATEWAY_PORT}",fork,reuseaddr,bind=0.0.0.0 TCP:"127.0.0.1:${LLM_GATEWAY_PORT}" &
echo "[harness] llm-gateway socat 0.0.0.0:${LLM_GATEWAY_PORT} -> 127.0.0.1:${LLM_GATEWAY_PORT}"

# 把 HARNESS Web UI 对外暴露
exec socat TCP-LISTEN:"${PUBLIC_PORT}",fork,reuseaddr,bind=0.0.0.0 TCP:"${HOST}:${DSH_PORT}"
