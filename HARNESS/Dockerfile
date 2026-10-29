# 使用 Node.js 22 的 Debian Bookworm slim 镜像作为基础镜像。因为 HARNESS 基于 DeepSeek Harness，运行环境主要是 Node.js。
FROM node:22-bookworm-slim

# 在node:22-bookworm-slim基础镜像中安装系统工具和依赖：curl、git、ca-certificates、socat、python3、make、g++、pnpm@10。
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    curl git ca-certificates socat \
    python3 make g++ \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g pnpm@10

# 获取 Docker构建参数：从 install.sh脚本中do_build()函数组装的 docker build --build-arg "DSH_VERSION=0.1.0-rc.6" --build-arg "HARNESS_SIDEBAR_PACKAGE=dsh-better-sidebar@0.12.1" 命令中获取 Docker构建参数
ARG DSH_VERSION=0.1.0-rc.6
ARG HARNESS_SIDEBAR_PACKAGE=dsh-better-sidebar@0.12.1

# 在基础镜像中 安装 DeepSeek Harness 主程序
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" tsx

# 设置镜像容器中的工作目录为`/harness`
WORKDIR /harness

# 把本地 `HARNESS/plugins/` 目录（TypeScript插件）拷贝进镜像中的 `/harness/plugins/` 目录
COPY plugins/ /harness/plugins/
# 给插件目录创建软链接。这样`plugins/*.ts` 里的 TypeScript 插件可以正常 import DeepSeek Harness 的工具库。
RUN mkdir -p /harness/plugins/node_modules/@deepseek-ai \
  && ln -sf /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tools \
    /harness/plugins/node_modules/@deepseek-ai/dsh-tools \
  && ln -sf /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/cordis \
    /harness/plugins/node_modules/@deepseek-ai/cordis

# 把本地 `HARNESS/scripts/` 目录（HARNESS辅助脚本）拷贝进镜像中的 `/harness/scripts/` 目录
COPY scripts/ /harness/scripts/
# 把本地 `HARNESS/image/` 目录（EasyAIoT品牌资源、样式、图标、图片等）拷贝进镜像中的 `/harness/image/` 目录
COPY image/ /harness/image/
# 把本地 `HARNESS/docker-entrypoint.sh` 脚本（容器启动入口脚本）拷贝进镜像中的 `/usr/local/bin/harness-entrypoint.sh`
COPY docker-entrypoint.sh /usr/local/bin/harness-entrypoint.sh
# 赋予脚本执行权限，并在构建阶段执行`apply-branding.sh` ，把 HARNESS UI 改成 EasyAIoT 品牌。
RUN chmod +x /usr/local/bin/harness-entrypoint.sh \
    /harness/image/apply-branding.sh \
    /harness/scripts/ensure-ux-plugins.sh \
    /harness/scripts/purge-harness-workspace.sh \
  && HARNESS_APP_NAME=EasyAIoT HARNESS_APP_SHORT=EasyAIoT /harness/image/apply-branding.sh

# 构建期预装侧边栏到 seed，首启可离线复制到 DSH_HOME volume
# 构建镜像时预装侧边栏插件，把结果放到`/harness/dsh-seed`，这样容器首次启动时可以从 seed 复制插件，不必每次联网安装。
ENV DSH_HOME=/harness/dsh-seed
RUN mkdir -p /harness/dsh-seed \
  && HARNESS_ENABLE_SIDEBAR=1 \
     HARNESS_SIDEBAR_PACKAGE="${HARNESS_SIDEBAR_PACKAGE}" \
     HARNESS_UX_SEED=/harness/dsh-seed \
     /harness/scripts/ensure-ux-plugins.sh \
  || echo "[harness] WARN: sidebar seed install skipped (build continues)"

# 运行时工作目录必须是仓库根（资源管理器根 = 会话 cwd）
# 创建运行时工作区目录`/workspace/easyaiot` ，并把它设为容器运行时工作目录。
RUN mkdir -p /workspace/easyaiot
WORKDIR /workspace/easyaiot

# 设置运行时环境变量：
# DeepSeek Harness 的运行数据目录，compose 里会挂载 volume 持久化
ENV DSH_HOME=/data/dsh-home
# 内部监听地址
ENV HARNESS_LISTEN_HOST=127.0.0.1
# 对外端口
ENV HARNESS_LISTEN_PORT=3080
# Agent 工作区
ENV HARNESS_WORKSPACE=/workspace/easyaiot
# 启用文件树侧边栏
ENV HARNESS_ENABLE_SIDEBAR=1
# 侧边栏插件包
ENV HARNESS_SIDEBAR_PACKAGE=${HARNESS_SIDEBAR_PACKAGE}
# 预装插件种子目录
ENV HARNESS_UX_SEED=/harness/dsh-seed

# 声明容器会使用`3080` 端口。HARNESS Web UI 默认从这个端口访问
EXPOSE 3080

# 定义容器健康检查
HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=120s \
  CMD curl -fsS "http://127.0.0.1:${HARNESS_LISTEN_PORT}/" >/dev/null || exit 1

# 容器启动时执行`/usr/local/bin/harness-entrypoint.sh`
ENTRYPOINT ["/usr/local/bin/harness-entrypoint.sh"]
