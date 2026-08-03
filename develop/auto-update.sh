#!/bin/bash
#
# auto-update.sh — 自动检测上游更新、构建并发布到 Gitee
#
# 用法：cd /vol3/1000/Projects/fn-native-metacubexd/develop && bash auto-update.sh
# 由 cron 任务调用，输出写入文件供 Hermes 读取
#

set -euo pipefail

REPO_DIR="/vol3/1000/Projects/fn-native-metacubexd"
DEVELOP_DIR="$REPO_DIR/develop"
SRC_DIR="$REPO_DIR/src"
DIST_DIR="$REPO_DIR/dist"
VERSIONS_FILE="$DEVELOP_DIR/versions"
MANIFEST_FILE="$SRC_DIR/manifest"
CHANGELOG_FILE="$REPO_DIR/CHANGELOG.md"
README_FILE="$REPO_DIR/README.md"
README_EN_FILE="$REPO_DIR/README.en.md"
LOG_FILE="$DEVELOP_DIR/auto-update.log"
GITEE_TOKEN="${GITEE_TOKEN:?GITEE_TOKEN 未设置}"
METACUBEXD_REPO="MetaCubeX/metacubexd"
MIHOMO_REPO="MetaCubeX/mihomo"

# 注入 PATH
export PATH="/vol1/@appcenter/nodejs_v24/bin:$DEVELOP_DIR:$PATH"
GH_PROXY="$DEVELOP_DIR/gh-proxy"

# 颜色
g() { printf '\033[32m%s\033[0m\n' "$1"; }
y() { printf '\033[33m%s\033[0m\n' "$1"; }
r() { printf '\033[31m%s\033[0m\n' "$1"; }
b() { printf '\033[34m%s\033[0m\n' "$1"; }

# 日志函数
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

# 获取上游最新版本
get_latest_version() {
    local repo="$1"
    "$GH_PROXY" latest-tag "$repo" 2>/dev/null | sed 's/^v//'
}

# 读取本地版本
get_local_version() {
    local key="$1"
    grep "^${key}=" "$VERSIONS_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || echo ""
}

# 从 GitHub 获取 Release Notes
get_github_release() {
    local tag="$1"
    curl -sL --max-time 30 \
        "https://api.github.com/repos/$METACUBEXD_REPO/releases/tags/$tag" \
        -H "Accept: application/vnd.github+json" 2>/dev/null
}

# 格式化更新说明为中文
format_changelog() {
    local json="$1"
    local tag="$2"
    
    # 提取 body（release notes）
    local body
    body=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body',''))" 2>/dev/null || echo "")
    
    if [ -z "$body" ]; then
        echo "更新说明暂缺，请查看上游 release notes"
        return
    fi
    
    # 转换为中文格式（简化处理）
    local result=""
    result+="魔方面板 v${tag}<br>"
    result+="<br>"
    
    # 按段处理
    while IFS= read -r line; do
        # 跳过空行和标题
        if [[ -z "$line" ]] || [[ "$line" =~ ^## ]]; then
            continue
        fi
        # Features
        if [[ "$line" =~ \*\*(.+)\*\*:\ (.+) ]]; then
            local feature="${BASH_REMATCH[1]}"
            local desc="${BASH_REMATCH[2]}"
            result+="【新特性】${desc}<br>"
        # Bug fixes section header
        elif [[ "$line" =~ "Bug Fixes" ]]; then
            :  # 跳过标签
        elif [[ "$line" =~ ^\* ]]; then
            local fix="${line#\* }"
            result+="【修复】${fix}<br>"
        fi
    done <<< "$body"
    
    # 如果没有提取到内容，返回原始说明
    if [[ -z "$result" ]]; then
        result="详情见上游 release notes：https://github.com/$METACUBEXD_REPO/releases/tag/$tag"
    fi
    
    echo "$result"
}

# 更新 manifest
update_manifest() {
    local version="$1"
    local changelog="$2"
    
    # 更新 version
    sed_inplace "s|^version=.*|version=${version}|" "$MANIFEST_FILE"
    
    # 更新 changelog（转义特殊字符）
    local escaped_changelog
    escaped_changelog=$(echo "$changelog" | sed 's/|/\\|/g; s/"/\\"/g')
    sed_inplace "s|^changelog=.*|changelog=\"${escaped_changelog}\"|" "$MANIFEST_FILE"
    
    log "✓ manifest 已更新 (v${version})"
}

# 更新 CHANGELOG.md
update_changelog() {
    local version="$1"
    local date="$2"
    local content="$3"
    
    # 读取现有内容
    local existing
    existing=$(cat "$CHANGELOG_FILE")
    
    # 更新顶部当前版本声明
    local updated_existing
    updated_existing=$(echo "$existing" | sed "s|当前打包版本：\*\*面板 metacubexd \`.*\`\*\*|当前打包版本：**面板 metacubexd \`${version}\`**|")
    
    # 插入新的版本条目
    local new_entry
    new_entry="
---

## [${version}] - ${date}

面板 metacubexd [${version}](https://github.com/MetaCubeX/metacubexd/releases/tag/v${version})

### 更新说明

${content}

> 完整更新记录见上游 [Release Notes](https://github.com/MetaCubeX/metacubexd/releases/tag/v${version})。"
    
    # 将新条目插入到"当前打包版本"段落后
    echo "$updated_existing" | sed "/^当前打包版本：/a\\${new_entry}" > "$CHANGELOG_FILE"
    
    log "✓ CHANGELOG.md 已更新"
}

# 更新 README 徽章
update_readme_badges() {
    local version="$1"
    
    # 更新 README.md
    sed_inplace "s|\[![面板](https://img.shields.io/badge/面板-v[0-9.]*-orange)\](https://github.com/MetaCubeX/metacubexd/releases)|[![面板](https://img.shields.io/badge/面板-v${version}-orange)](https://github.com/MetaCubeX/metacubexd/releases)|" "$README_FILE"
    sed_inplace "s|v${version/1.270/1.270}\\.6|v${version}|g" "$README_FILE"  # 更精确的版本替换
    sed_inplace "s|v1\\.270\\.6|v${version}|g" "$README_FILE"
    
    # 更新 README.en.md
    sed_inplace "s|\[![Dashboard](https://img.shields.io/badge/dashboard-v[0-9.]*-orange)\](https://github.com/MetaCubeX/metacubexd/releases)|[![Dashboard](https://img.shields.io/badge/dashboard-v${version}-orange)](https://github.com/MetaCubeX/metacubexd/releases)|" "$README_EN_FILE"
    sed_inplace "s|v1\\.270\\.6|v${version}|g" "$README_EN_FILE"
    
    log "✓ README 徽章已更新"
}

# 上传到 Gitee
upload_to_gitee() {
    local version="$1"
    local fpk_path="$2"
    local changelog="$3"
    
    local tag="v${version}"
    local release_url="https://gitee.com/api/v5/repos/rexond/fn-native-metacubexd/releases"
    
    # 检查是否已存在该版本的 release
    local existing
    existing=$(curl -sL --max-time 30 "$release_url?access_token=$GITEE_TOKEN" 2>/dev/null)
    if echo "$existing" | grep -q "\"tag_name\":\"$tag\""; then
        log "⚠ Release $tag 已存在，跳过创建"
        return 0
    fi
    
    # 创建 release
    local release_body
    release_body=$(cat <<EOF
魔方面板 v${version}

${changelog}
EOF
)
    
    local release_data
    release_data=$(curl -sL --max-time 30 -X POST \
        "$release_url?access_token=$GITEE_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"tag_name\":\"$tag\",\"name\":\"$tag\",\"body\":\"$release_body\"}" \
        2>/dev/null)
    
    if ! echo "$release_data" | grep -q '"id"'; then
        log "✗ 创建 Release 失败: $release_data"
        return 1
    fi
    
    local release_id
    release_id=$(echo "$release_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    
    # 上传 fpk 文件
    log "上传 fpk 文件..."
    local asset_result
    asset_result=$(curl -sL --max-time 180 -X POST \
        -H "Authorization: Bearer $GITEE_TOKEN" \
        -F "file=@$fpk_path" \
        "https://gitee.com/api/v5/repos/rexond/fn-native-metacubexd/releases/$release_id/attach_files?access_token=$GITEE_TOKEN" \
        2>/dev/null)
    
    if echo "$asset_result" | grep -q 'browser_download_url'; then
        log "✓ fpk 已上传到 Gitee Release (v${tag})"
    else
        log "⚠ fpk 上传可能失败: $asset_result"
    fi
    
    log "✓ Gitee Release 创建完成 (v${tag})"
}

# sed 原地替换（兼容 GNU/BSD）
sed_inplace() {
    local expr="$1"
    local file="$2"
    if sed --version >/dev/null 2>&1; then
        sed -i "$expr" "$file"
    else
        sed -i '' "$expr" "$file"
    fi
}

# ==================== 主流程 ====================
main() {
    log "==== 开始自动更新检查 ===="
    log "仓库: $REPO_DIR"
    
    # 1. 获取最新版本
    log "检查上游版本..."
    local latest_xd
    latest_xd=$(get_latest_version "$METACUBEXD_REPO")
    local latest_mihomo
    latest_mihomo=$(get_latest_version "$MIHOMO_REPO")
    
    local current_xd
    current_xd=$(get_local_version "metacubexd")
    local current_mihomo
    current_mihomo=$(get_local_version "mihomo")
    
    log "metacubexd: 最新=$latest_xd, 当前=${current_xd:-无}"
    log "mihomo: 最新=$latest_mihomo, 当前=${current_mihomo:-无}"
    
    # 2. 检查是否有更新
    local has_update=false
    if [ "$latest_xd" != "$current_xd" ]; then
        has_update=true
        log "→ metacubexd 有新版本: $current_xd → $latest_xd"
    fi
    if [ "$latest_mihomo" != "$current_mihomo" ]; then
        has_update=true
        log "→ mihomo 有新版本: $current_mihomo → $latest_mihomo"
    fi
    
    if [ "$has_update" = false ]; then
        log "已是最新版本，无需更新"
        echo "无更新" >> "$LOG_FILE"
        return 0
    fi
    
    # 3. 更新 versions 文件
    sed_inplace "s|^metacubexd=.*|metacubexd=${latest_xd}|" "$VERSIONS_FILE"
    if [ "$latest_mihomo" != "$current_mihomo" ]; then
        sed_inplace "s|^mihomo=.*|mihomo=${latest_mihomo}|" "$VERSIONS_FILE"
    fi
    log "✓ versions 已更新"
    
    # 4. 获取上游更新说明
    log "获取上游 release notes..."
    local release_json
    release_json=$(get_github_release "v${latest_xd}")
    local release_date
    release_date=$(echo "$release_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('published_at','')[:10])" 2>/dev/null || echo "unknown")
    
    # 5. 构建中文 changelog
    local changelog
    changelog=$(format_changelog "$release_json" "$latest_xd")
    
    # 6. 更新 manifest
    update_manifest "$latest_xd" "$changelog"
    
    # 7. 更新 CHANGELOG.md
    update_changelog "$latest_xd" "$release_date" "$changelog"
    
    # 8. 更新 README 徽章
    update_readme_badges "$latest_xd"
    
    # 9. 构建
    log "开始构建..."
    cd "$DEVELOP_DIR"
    if bash build.sh 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ 构建成功"
    else
        log "✗ 构建失败"
        echo "构建失败" >> "$LOG_FILE"
        return 1
    fi
    
    # 10. 上传到 Gitee
    local fpk_path="$DIST_DIR/metacubexd.fpk"
    if [ -f "$fpk_path" ]; then
        upload_to_gitee "$latest_xd" "$fpk_path" "$changelog"
        log "✓ 发布完成"
    else
        log "✗ 未找到 fpk 文件: $fpk_path"
        return 1
    fi
    
    log "==== 更新完成: v${latest_xd} ===="
    echo "成功: v${latest_xd}" >> "$LOG_FILE"
}

# 执行
main "$@"
