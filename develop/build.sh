#!/bin/sh
#
# build.sh — 在 NAS（develop 目录）上编译 MetaCubeXD 面板并打包 fpk
#
# 用法：
#   cd <repo>/develop && bash build.sh
#
# 流程：
#   1. 注入 PATH（nodejs_v24 的 node/pnpm + gh-proxy 所在目录）
#   2. gh-proxy 检测 metacubexd 版本，本地无源码或有更新时拉取 latest 源码包
#   3. gh-proxy 检测 mihomo 版本，有更新时拉取 mihomo-linux-amd64-v1 内核
#   4. 更新 develop/versions
#   5. 编译 metacubexd（pnpm install + patch + build:server/build:ui）
#      产物放 app/server、app/www；mihomo 解压到 app/bin
#   6. 同步 manifest 的 version 为 metacubexd 版本（去掉 v）
#   7. fnpack build --directory ../ 并把 fpk 移到 dist/
#
# 兼容 POSIX sh（fnOS 默认 sh = dash）：
#   - 不用 pipefail（dash 不支持）：管道以最后一条命令的退出码为准
#   - 不用 BASH_SOURCE / 进程替换 < <() / read -d '' / shopt（均属 bash）
set -eu

#=============================================================================
# gh-proxy: GitHub 镜像加速下载工具（用法备查）
#   gh-proxy download <rel> -o <path> [-min-size N] [-c <config.json>]
#       下载 GitHub 资源，rel 是相对路径（不含 https://github.com/）
#   gh-proxy latest-tag <repo> [-c <config.json>]
#       查询最新 release 的 tag_name（如 v1.270.6）
#   gh-proxy release-info <repo> / releases <repo> / repo-info <repo> / probe
#   配置加载优先级：-c <file> > $GH_PROXY_CONFIG > 二进制旁 config.json > 内嵌默认
#   本脚本不传 -c，使用 gh-proxy 内嵌默认镜像源 + 匿名 GitHub API。
#=============================================================================

# ---- 路径 ----
# 目录结构：仓库根下 develop/（构建环境）、dist/（fpk 产出）、src/（fnOS 应用，
# fnpack 打包目标）。manifest/cmd/config/wizard/ICON/app 都在 src/ 下，
# 这样 fnpack build --directory src 不会递归进 develop/metacubexd 的坏 symlink。
# 用 $0 解析脚本所在目录（POSIX），不用 bash 专属的 BASH_SOURCE。
# 前提是 cd <repo>/develop && bash build.sh / sh build.sh —— $0 为 build.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_DIR/src"                   # fnOS 应用目录（fnpack 打包目标）
PATCH_DIR="$SCRIPT_DIR/patch"
VERSIONS_FILE="$SCRIPT_DIR/versions"
MANIFEST_FILE="$SRC_DIR/manifest"
DOWNLOAD_DIR="$SCRIPT_DIR/download"        # gh-proxy 下载产物（源码包/内核压缩包）
XD_DIR="$SCRIPT_DIR/metacubexd"           # 源码解包位置：develop/metacubexd
APP_DIR="$SRC_DIR/app"
OUT_SERVER="$APP_DIR/server"
OUT_WWW="$APP_DIR/www"
MIHOMO_BIN="$APP_DIR/bin/mihomo"
DIST_DIR="$REPO_DIR/dist"

# ---- 注入 PATH（必须）：nodejs_v24 的 node/pnpm + gh-proxy 所在目录 ----
# 不注入的话 pnpm / gh-proxy 会找不到
export PATH="/vol1/@appcenter/nodejs_v24/bin:$SCRIPT_DIR:$PATH"
GH_PROXY="$SCRIPT_DIR/gh-proxy"

METACUBEXD_REPO="MetaCubeX/metacubexd"
MIHOMO_REPO="MetaCubeX/mihomo"

# ---- 颜色 ----
g() { printf '\033[32m%s\033[0m\n' "$1"; }
y() { printf '\033[33m%s\033[0m\n' "$1"; }
r() { printf '\033[31m%s\033[0m\n' "$1"; }
die() { r "✗ $*"; exit 1; }

# ---- 工具 ----
# 兼容 GNU/BSD sed 的原地替换
sed_inplace() {
  local expr="$1" file="$2"
  if sed --version >/dev/null 2>&1; then sed -i "$expr" "$file"
  else sed -i '' "$expr" "$file"; fi
}

# 读取 versions 文件中某 key 的值
get_ver() {
  local key="$1"
  [ -f "$VERSIONS_FILE" ] || return 0
  grep "^${key}=" "$VERSIONS_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

# 写入/更新 versions 文件中某 key
set_ver() {
  local key="$1" val="$2"
  if [ -f "$VERSIONS_FILE" ] && grep -q "^${key}=" "$VERSIONS_FILE"; then
    sed_inplace "s|^${key}=.*|${key}=${val}|" "$VERSIONS_FILE"
  else
    echo "${key}=${val}" >> "$VERSIONS_FILE"
  fi
}

# 去掉 tag 前导 v
strip_v() { local t="$1"; echo "${t#v}"; }

# ---- 前置检查 ----
[ -f "$GH_PROXY" ] || die "gh-proxy 不存在: $GH_PROXY"
command -v pnpm >/dev/null 2>&1 || die "pnpm 未找到（确认 nodejs_v24 已安装且 PATH 已注入）"
command -v node  >/dev/null 2>&1 || die "node 未找到（确认 nodejs_v24 已安装且 PATH 已注入）"

# ---- 规避 git dubious ownership（CVE-2022-24765 安全检查）----
# NAS 共享路径（/vol3/1000/...）上文件属主常与 SSH 登录用户不一致（SMB uid 映射、
# 跨用户访问等），git 2.35.2+ 会拒绝操作这类 .git 目录，报：
#   fatal: detected dubious ownership in repository at '...'
# 把源码目录预先登记为 trusted，避免第 1/4 步的 git init / checkout 被拦。
#
# 两个坑：
#   1) ownership 检查在访问层，必须用全局配置，单仓库 local config 无效
#   2) NAS 上 $HOME 常不可写（/home/<user> 不存在或无权限），导致
#      `git config --global` 报 "could not lock config file /home/.../.gitconfig"
# 解决：用 GIT_CONFIG_GLOBAL 指向一个当前用户可写的任意路径（这里用脚本
#       旁边的 .gitconfig-global，落在 develop/ 下，构造时可写），再写 safe.directory。
# GIT_CONFIG_GLOBAL 比每次 --global 改 ~/.gitconfig 更干净、不污染用户环境。
if command -v git >/dev/null 2>&1; then
  GIT_GLOBAL="$SCRIPT_DIR/.gitconfig-global"
  export GIT_CONFIG_GLOBAL="$GIT_GLOBAL"
  # safe.directory 可重复登记，--add 幂等；用全局文件而非 --global 避开 HOME 写入问题
  git config --file "$GIT_GLOBAL" --add safe.directory "$XD_DIR" 2>/dev/null || true
fi

g "==== MetaCubeXD 构建 ===="
echo "仓库根: $REPO_DIR"
echo "源码:   $XD_DIR"
echo "产物:   $APP_DIR"
echo

#=============================================================================
# 1. metacubexd 版本检测 + 按需下载源码
#    源码包内路径为 metacubexd-<ver>/***，去掉一层后解到 develop/metacubexd
#=============================================================================
g "---- 1/7 检测 metacubexd 版本 ----"
xd_tag="$("$GH_PROXY" latest-tag "$METACUBEXD_REPO")" \
  || die "获取 metacubexd 最新版本失败"
xd_ver="$(strip_v "$xd_tag")"
xd_local="$(get_ver metacubexd)"
echo "metacubexd: 最新=$xd_ver, 本地=${xd_local:-无}"

if [ ! -d "$XD_DIR" ] || [ "$xd_ver" != "$xd_local" ]; then
  mkdir -p "$DOWNLOAD_DIR"
  xd_tgz="$DOWNLOAD_DIR/metacubexd-${xd_ver}.tar.gz"
  y "拉取 metacubexd 源码包: v$xd_ver"
  rm -f "$xd_tgz"
  "$GH_PROXY" download "$METACUBEXD_REPO/archive/refs/tags/v${xd_ver}.tar.gz" \
    -o "$xd_tgz" -min-size 100000 \
    || die "下载 metacubexd 源码失败"
  rm -rf "$XD_DIR"
  mkdir -p "$XD_DIR"
  tar xzf "$xd_tgz" -C "$XD_DIR" --strip-components=1
  set_ver metacubexd "$xd_ver"
  # 解包后用 git 管理：建立干净的 baseline 提交（忽略 node_modules/构建产物）。
  # 这样每次打补丁前可 git checkout 回到原始状态，彻底规避幂等判断和补丁上下文
  # 不匹配的问题（源码树永远从原始状态出发，patch 一定干净应用）。
  # 关键：core.autocrlf=false，避免 git 改动换行符导致 patch 上下文不匹配。
  if command -v git >/dev/null 2>&1; then
    ( cd "$XD_DIR"
      printf 'node_modules/\n.output/\n.nuxt/\ndist/\ndist-electron/\n*.log\n' > .gitignore
      git init -q
      git config core.autocrlf false
      git config core.safecrlf false
      git add -A
      git -c user.name=build -c user.email=build@local -c commit.gpgsign=false \
        commit -q -m "baseline: metacubexd v${xd_ver} (upstream)"
    ) && g "✓ 已建立 git baseline" || y "⚠ git init 失败，将退回逐补丁幂等"
  fi
  g "✓ 源码已解压到 $XD_DIR"
else
  g "✓ metacubexd 已是最新，跳过下载"
fi
echo

#=============================================================================
# 2. mihomo 版本检测 + 按需下载内核
#    资源名形如 mihomo-linux-amd64-v1-v1.19.29.gz，解压出 mihomo 二进制
#=============================================================================
g "---- 2/7 检测 mihomo 版本 ----"
mihomo_tag="$("$GH_PROXY" latest-tag "$MIHOMO_REPO")" \
  || die "获取 mihomo 最新版本失败"
mihomo_ver="$(strip_v "$mihomo_tag")"
mihomo_local="$(get_ver mihomo)"
echo "mihomo: 最新=$mihomo_ver, 本地=${mihomo_local:-无}"

if [ ! -f "$MIHOMO_BIN" ] || [ "$mihomo_ver" != "$mihomo_local" ]; then
  mkdir -p "$DOWNLOAD_DIR"
  mihomo_gz="$DOWNLOAD_DIR/mihomo-linux-amd64-v1-v${mihomo_ver}.gz"
  y "拉取 mihomo 内核: v$mihomo_ver"
  rm -f "$mihomo_gz"
  "$GH_PROXY" download \
    "$MIHOMO_REPO/releases/download/v${mihomo_ver}/mihomo-linux-amd64-v1-v${mihomo_ver}.gz" \
    -o "$mihomo_gz" -min-size 1000000 \
    || die "下载 mihomo 内核失败"
  mkdir -p "$(dirname "$MIHOMO_BIN")"
  gunzip -c "$mihomo_gz" > "$MIHOMO_BIN"
  chmod +x "$MIHOMO_BIN"
  set_ver mihomo "$mihomo_ver"
  g "✓ mihomo 已解压到 $MIHOMO_BIN"
else
  g "✓ mihomo 已是最新，跳过下载"
fi
echo

#=============================================================================
# 3. 安装依赖
#=============================================================================
g "---- 3/7 安装依赖 ----"
cd "$XD_DIR"
# NAS 共享上 pnpm 解包常丢失原生二进制的可执行位（典型：esbuild），
# 导致其 postinstall 用 spawnSync 校验二进制时报 EACCES 并让整次 install
# 以非零退出 —— 进而 .bin/ 符号链接未完整生成，后续 `nitro` 等命令找不到。
# 用 --ignore-scripts 跳过生命周期脚本（仍会创建 node_modules 和 .bin 链接），
# 装完再手动补回原生二进制的可执行位。
#
# CI/非交互必备：
#   - CI=1            pnpm 见此变量会自动选默认项，不再发交互式确认
#                      （如「modules directories will be removed ... Proceed?」）
#   - --config.confirm-modules-purge=false  彻底关闭「清空 node_modules 重装」的二次确认
#                      （某些 pnpm 版本即便 CI=1 仍会问，加这个兜底）
# 不加的话脚本会停在 prompt 上没人替它回答，表现为「卡住不动」。
CI=1 pnpm install --frozen-lockfile --ignore-scripts \
  --config.confirm-modules-purge=false \
  || die "pnpm install 失败"

# 补回原生二进制的可执行位：
#   - esbuild 包里的 bin/esbuild（JS shim，build 时会被 spawn）
#   - @esbuild/linux-x64 里的 bin/esbuild（真正的原生二进制）
find node_modules -type f -name esbuild -path '*/bin/*' -exec chmod +x {} +
# 各 workspace 包的 .bin 也补一次（nitro/vite/nuxt 等命令在各包自己的 .bin）
find node_modules -path '*/.bin/*' -type l -exec chmod +x {} + 2>/dev/null || true

# nitro/nuxt 等命令在 workspace 各包的 node_modules/.bin（如 apps/server/.bin），
# 不在仓库根 .bin。pnpm run 会从包自身解析，无需根目录有，故不做根目录 nitro 检查。
echo

#=============================================================================
# 4. 应用补丁（patch/*.patch）+ 复制新增文件（patch/files）
#    打补丁前先用 git 把源码树恢复到 baseline 原始状态（丢掉上次运行残留的
#    补丁改动 / patch-index 注入 / 构建产物），保证每次都从干净状态打补丁。
#=============================================================================
g "---- 4/7 应用补丁 ----"

# 恢复 baseline：清掉 tracked 改动 + 上次复制进来的 untracked 文件，
# 保留 node_modules 等 .gitignore 里忽略的（pnpm install 的成果不丢）。
if [ -d "$XD_DIR/.git" ]; then
  ( cd "$XD_DIR"
    git checkout -q -- .
    # 删掉除 gitignore 外的所有 untracked（含上次复制的 patch/files 与 .output）
    git clean -qdff -e node_modules -e .output -e .nuxt -e dist -e dist-electron
  )
  g "✓ 已恢复 git baseline"
else
  y "⚠ 无 git baseline（.git 不存在），直接打补丁"
fi

if [ ! -d "$PATCH_DIR" ]; then
  y "无 patch 目录，跳过补丁"
else
  failed=0
  # 从 baseline 出发，补丁必然干净应用（无需 --reverse 幂等判断）。
  # 不用 bash 进程替换 < <(find -print0) / read -d ''（dash 不支持），
  # 改用 find -print 加 while read（补丁路径不含空格，NUL 分隔无必要）。
  patchfiles=$(find "$PATCH_DIR" -type f -name '*.patch' | sort)
  if [ -n "$patchfiles" ]; then
    # 关闭 set -e 期间的手动错误聚合：单条 patch 失败不立即退出，
    # 继续尝试其余补丁，最后统一汇总失败数。
    set +e
    printf '%s\n' "$patchfiles" | while IFS= read -r patchfile; do
      rel="${patchfile#$PATCH_DIR/}"
      # patch -p1 去掉 diff 路径第一段（a/ b/）；-t 不交互、--forward 不回退
      if patch -p1 -t --forward -i "$patchfile" -d "$XD_DIR" >/dev/null 2>&1; then
        g "✓ 应用: $rel"
      else
        r "✗ 应用失败（上下文不匹配）: $rel"
        # 管道里子 shell 的变量出不来，用临时文件传递失败计数
        echo x >>"$XD_DIR/.patch-failed"
      fi
    done
    set -e
    if [ -f "$XD_DIR/.patch-failed" ]; then
      failed=$(wc -l <"$XD_DIR/.patch-failed" | tr -d ' ')
      rm -f "$XD_DIR/.patch-failed"
    fi
    [ "$failed" -gt 0 ] && die "有 $failed 个补丁应用失败"
  fi
fi

# 复制新增文件（patch/files 整体覆盖进源码树）
if [ -d "$PATCH_DIR/files" ]; then
  cp -r "$PATCH_DIR/files/." "$XD_DIR/"
  g "✓ 新增文件已复制"
else
  y "无新增文件"
fi
echo

#=============================================================================
# 5. 编译 server + 复制产物到 app/server
#=============================================================================
g "---- 5/7 编译 server ----"
pnpm build:server
echo

g "---- 复制 server 产物 ----"
[ -d "$XD_DIR/apps/server/.output" ] || die "server 产物缺失: apps/server/.output"
mkdir -p "$APP_DIR"
rm -rf "$OUT_SERVER"
mkdir -p "$OUT_SERVER"
# 只复制 .output/server/（index.mjs、chunks/、node_modules/），运行时用不到 public 和 nitro.json
# WebSocket 反代（clash-api）已由源码侧 plugins/clash-proxy-ws.ts 编译进产物，无需后处理
cp -r "$XD_DIR/apps/server/.output/server/." "$OUT_SERVER/"
rm -rf "$XD_DIR/apps/server/.output"
g "✓ server 产物 -> $OUT_SERVER"
echo

#=============================================================================
# 6. 编译 ui + 复制产物到 app/www
#=============================================================================
g "---- 6/7 编译 ui ----"
# 相对 base './'：部署到 /app/metacubexd 子路径时静态资源自动解析为 ./_nuxt/xxx，
# 且规避 ssr:false + nuxt generate 下绝对子路径 baseURL 的重定向占位问题
export NUXT_APP_BASE_URL="./"
pnpm build:ui
echo

g "---- 复制 ui 产物 ----"
[ -d "$XD_DIR/packages/ui/.output/public" ] || die "ui 产物缺失: packages/ui/.output/public"
rm -rf "$OUT_WWW"
cp -r "$XD_DIR/packages/ui/.output/public/." "$OUT_WWW/"
rm -rf "$XD_DIR/packages/ui/.output"
g "✓ ui 产物 -> $OUT_WWW"
echo

#=============================================================================
# 7. 同步 manifest 版本 = metacubexd 版本（去 v），然后 fnpack 打包
#    fnpack 会先把 --directory 整个目录树复制到 /tmp 再过滤。src/ 只含
#    fnOS 应用文件（manifest/cmd/config/wizard/ICON/app），不含 develop/metacubexd
#    的坏符号链接（@electron/fuses），复制阶段安全。
#=============================================================================
g "---- 7/7 更新版本 + 打包 ----"
sed_inplace "s|^version=.*|version=${xd_ver}|" "$MANIFEST_FILE"
g "✓ manifest version=$xd_ver"

mkdir -p "$DIST_DIR"
# 打包 src/：fnOS 应用目录，不会递归进 develop/ 的坏 symlink。
# fnpack 把 fpk 输出到「当前工作目录」而非 --directory，所以打包前必须 cd 回
# develop/（第 3 步 pnpm install 会 cd 进 metacubexd 源码目录，否则 fpk 会
# 错误地生成在 metacubexd/ 下）。fpk 就落在 develop/，再移到 dist/。
( cd "$SCRIPT_DIR" && fnpack build --directory "$SRC_DIR" ) || die "fnpack 打包失败"

# fpk 生成在 develop/（fnpack 的 working directory），移到 dist/
# dash 没有 shopt nullglob：glob 无匹配时模式原样返回，故用 [ -e ] 跳过。
moved=0
for f in "$SCRIPT_DIR"/*.fpk; do
  [ -e "$f" ] || continue
  mv -f "$f" "$DIST_DIR/"
  g "✓ $(basename "$f") -> $DIST_DIR"
  moved=$((moved + 1))
done
[ "$moved" -gt 0 ] || die "未找到打包产出的 .fpk"
echo

g "==== 构建完成 ===="
echo "  server:  $OUT_SERVER"
echo "  www:     $OUT_WWW"
echo "  mihomo:  $MIHOMO_BIN"
echo "  dist:    $DIST_DIR"
