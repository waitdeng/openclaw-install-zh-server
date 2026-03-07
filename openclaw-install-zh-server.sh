#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# OpenClaw 汉化版 一键安装脚本（服务器加强版 + 回退 + 配置备份恢复）
#
# 基于汉化版 npm 包：
#   @qingchencloud/openclaw-zh
#
# 功能：
# 1. 检查/安装 Node.js 22+
# 2. 获取汉化版可用版本
# 3. 支持输入序号或完整版本号安装
# 4. 支持 install / rollback / restore-config 三种模式
# 5. 安装前自动备份 ~/.openclaw
# 6. 安装失败时自动尝试回退旧版本
# 7. 可选自动恢复最近一次配置备份
# 8. 自动修复 npm 全局 PATH
# 9. 自动创建 openclaw 命令软链接（如有需要）
# 10. 执行 openclaw onboard --install-daemon
# 11. 尝试启用 systemd --user 自启动
#
# 用法：
#   bash openclaw-install-zh-server.sh
#   bash openclaw-install-zh-server.sh 版本号
#   OPENCLAW_VERSION=版本号 bash openclaw-install-zh-server.sh
#
# 非交互：
#   ACTION=install OPENCLAW_VERSION=1.2.3 bash openclaw-install-zh-server.sh
#   ACTION=rollback OPENCLAW_VERSION=1.2.2 bash openclaw-install-zh-server.sh
#   ACTION=restore-config bash openclaw-install-zh-server.sh
#
# 可选环境变量：
#   AUTO_RESTORE_CONFIG_ON_FAIL=1
#   SKIP_ONBOARD=1
# =========================================================

PKG_NAME="@qingchencloud/openclaw-zh"
VERSION="${1:-${OPENCLAW_VERSION:-}}"
ACTION="${ACTION:-}"

LATEST_VERSION=""
CURRENT_VERSION=""
PREVIOUS_VERSION=""
SUDO=""

STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
BACKUP_ROOT="${OPENCLAW_BACKUP_DIR:-$HOME/.openclaw-backups}"
LAST_BACKUP_PATH=""
AUTO_RESTORE_CONFIG_ON_FAIL="${AUTO_RESTORE_CONFIG_ON_FAIL:-0}"
SKIP_ONBOARD="${SKIP_ONBOARD:-0}"

declare -a ALL_VERSIONS=()
declare -a DISPLAY_VERSIONS=()
declare -a BACKUP_DIRS=()

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

info() {
  echo "==> $*"
}

warn() {
  echo "警告: $*" >&2
}

die() {
  echo "错误: $*" >&2
  exit 1
}

run_quiet() {
  "$@" >/dev/null 2>&1 || true
}

setup_sudo() {
  if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
    SUDO="sudo"
  else
    SUDO=""
  fi
}

install_node22_debian_like() {
  info "安装 Node.js 22"
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y ca-certificates curl gnupg
  ${SUDO} mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key     | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main"     | ${SUDO} tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y nodejs
}

ensure_node() {
  if require_cmd node; then
    local node_major node_full
    node_major="$(node -p 'process.versions.node.split(".")[0]')"
    node_full="$(node -v)"
    if [ "${node_major}" -ge 22 ]; then
      info "Node 已满足最低主版本要求: ${node_full}"
      return 0
    fi
    warn "当前 Node 版本过低: ${node_full}，需要 >= 22.12.0"
  else
    warn "未检测到 Node.js"
  fi

  if require_cmd apt-get; then
    install_node22_debian_like
  else
    die "当前系统无 apt-get，无法自动安装 Node.js 22，请先手动安装 Node.js >= 22.12.0"
  fi
}

ensure_npm() {
  require_cmd npm || die "未检测到 npm，请确认 Node.js 安装正常"
}

get_npm_prefix() {
  npm prefix -g 2>/dev/null
}

get_npm_bin() {
  local prefix
  prefix="$(get_npm_prefix)"
  echo "${prefix}/bin"
}

ensure_npm_global_bin_in_path() {
  ensure_npm
  local npm_bin
  npm_bin="$(get_npm_bin)"
  case ":${PATH}:" in
    *":${npm_bin}:"*) ;;
    *) export PATH="${npm_bin}:${PATH}" ;;
  esac
}

append_path_hint_to_shell_profiles() {
  local npm_bin line profile
  npm_bin="$(get_npm_bin)"
  line="export PATH=\"${npm_bin}:\$PATH\""

  for profile in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    if [ -f "${profile}" ]; then
      grep -F "${line}" "${profile}" >/dev/null 2>&1 || echo "${line}" >> "${profile}"
    fi
  done
}

create_openclaw_symlink_if_needed() {
  local npm_bin target link_dir link_path resolved
  npm_bin="$(get_npm_bin)"
  target="${npm_bin}/openclaw"

  if [ ! -x "${target}" ]; then
    warn "未找到 npm 全局 openclaw 可执行文件: ${target}"
    return 0
  fi

  if require_cmd openclaw; then
    resolved="$(command -v openclaw || true)"
    info "当前 openclaw 命令路径: ${resolved}"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    for link_dir in /usr/local/bin /usr/bin; do
      if [ -d "${link_dir}" ]; then
        link_path="${link_dir}/openclaw"
        ln -sf "${target}" "${link_path}" || true
        if [ -x "${link_path}" ]; then
          info "已创建命令软链接: ${link_path} -> ${target}"
          hash -r || true
          return 0
        fi
      fi
    done
  fi

  warn "未能创建系统级软链接，已尝试仅修复 PATH"
}

detect_current_version() {
  ensure_npm_global_bin_in_path
  CURRENT_VERSION="$(npm list -g "${PKG_NAME}" --depth=0 2>/dev/null     | sed -n "s/.*${PKG_NAME}@//p"     | head -n1     | tr -d '[:space:]')"

  if [ -n "${CURRENT_VERSION}" ]; then
    info "当前已安装汉化版版本: ${CURRENT_VERSION}"
  else
    info "当前未检测到已安装的汉化版"
  fi
}

fetch_versions() {
  info "获取汉化版可用版本列表"
  ensure_npm_global_bin_in_path

  npm view "${PKG_NAME}" version >/dev/null 2>&1 || die "无法从 npm 获取 ${PKG_NAME} 信息，请检查网络或 npm 源"

  mapfile -t ALL_VERSIONS < <(
    npm view "${PKG_NAME}" versions --json 2>/dev/null | node -e '
      let s = "";
      process.stdin.on("data", d => s += d);
      process.stdin.on("end", () => {
        const parsed = JSON.parse(s);
        if (Array.isArray(parsed)) {
          for (const v of parsed) console.log(v);
        } else {
          process.exit(1);
        }
      });
    '
  )

  [ "${#ALL_VERSIONS[@]}" -gt 0 ] || die "未获取到版本列表"

  LATEST_VERSION="$(npm view "${PKG_NAME}" version 2>/dev/null | tr -d '[:space:]')"
  [ -n "${LATEST_VERSION}" ] || die "无法获取最新版本"

  info "最新版本: ${LATEST_VERSION}"
}

show_versions() {
  local total start i idx
  total="${#ALL_VERSIONS[@]}"
  start=0

  if [ "${total}" -gt 20 ]; then
    start=$((total - 20))
  fi

  DISPLAY_VERSIONS=()

  echo
  echo "最近可用版本（最新 20 个，序号越小越新）："
  idx=1
  for ((i=total-1; i>=start; i--)); do
    DISPLAY_VERSIONS+=("${ALL_VERSIONS[$i]}")
    printf "  [%02d] %s\n" "${idx}" "${ALL_VERSIONS[$i]}"
    idx=$((idx + 1))
  done
  echo
}

version_exists() {
  local target="$1" v
  for v in "${ALL_VERSIONS[@]}"; do
    if [ "${v}" = "${target}" ]; then
      return 0
    fi
  done
  return 1
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "$1" -ge 1 ] 2>/dev/null ;;
  esac
}

select_action() {
  local input

  if [ -n "${ACTION}" ]; then
    case "${ACTION}" in
      install|rollback|restore-config)
        info "操作模式: ${ACTION}"
        return 0
        ;;
      *)
        die "不支持的 ACTION: ${ACTION}，仅支持 install、rollback、restore-config"
        ;;
    esac
  fi

  echo "请选择操作："
  echo "  [1] 安装 / 切换到指定版本"
  echo "  [2] 回退到指定旧版本"
  echo "  [3] 仅恢复配置备份"
  echo

  while true; do
    read -r -p "请输入序号 [默认: 1]: " input
    input="${input:-1}"
    case "${input}" in
      1) ACTION="install"; return 0 ;;
      2) ACTION="rollback"; return 0 ;;
      3) ACTION="restore-config"; return 0 ;;
      *) warn "无效输入，请输入 1 / 2 / 3" ;;
    esac
  done
}

select_target_version() {
  local input chosen index prompt_text

  if [ "${ACTION}" = "restore-config" ]; then
    return 0
  fi

  if [ -n "${VERSION}" ]; then
    version_exists "${VERSION}" || die "指定版本不存在: ${VERSION}"
    info "已指定目标版本: ${VERSION}"
    return 0
  fi

  if [ "${ACTION}" = "rollback" ]; then
    prompt_text="请输入要回退到的序号或版本号"
  else
    prompt_text="请输入要安装的序号或版本号"
  fi

  echo "输入方式："
  echo "  1) 输入序号，例如 1"
  echo "  2) 输入完整版本号，例如 ${LATEST_VERSION}"
  if [ "${ACTION}" = "install" ]; then
    echo "  3) 直接回车，默认安装最新版本"
  fi
  echo

  while true; do
    if [ "${ACTION}" = "install" ]; then
      read -r -p "${prompt_text} [默认: ${LATEST_VERSION}]: " input
      input="${input:-$LATEST_VERSION}"
    else
      read -r -p "${prompt_text}: " input
      [ -n "${input}" ] || { warn "回退模式下必须明确指定版本"; continue; }
    fi

    if is_positive_integer "${input}"; then
      index=$((input - 1))
      if [ "${index}" -ge 0 ] && [ "${index}" -lt "${#DISPLAY_VERSIONS[@]}" ]; then
        chosen="${DISPLAY_VERSIONS[$index]}"
        VERSION="${chosen}"
        info "你选择的目标版本是: ${VERSION}"
        return 0
      else
        warn "序号超出范围，请重新输入"
        continue
      fi
    fi

    if version_exists "${input}"; then
      VERSION="${input}"
      info "你选择的目标版本是: ${VERSION}"
      return 0
    fi

    warn "版本不存在: ${input}，请重新输入"
  done
}

ensure_not_same_version() {
  if [ "${ACTION}" = "restore-config" ]; then
    return 0
  fi
  if [ -n "${CURRENT_VERSION}" ] && [ "${CURRENT_VERSION}" = "${VERSION}" ]; then
    die "当前已是版本 ${VERSION}，无需重复操作"
  fi
}

save_previous_version() {
  PREVIOUS_VERSION="${CURRENT_VERSION:-}"
  if [ -n "${PREVIOUS_VERSION}" ]; then
    info "已记录当前版本，必要时可自动回退: ${PREVIOUS_VERSION}"
  fi
}

ensure_backup_root() {
  mkdir -p "${BACKUP_ROOT}"
}

backup_config_if_exists() {
  ensure_backup_root

  if [ ! -d "${STATE_DIR}" ]; then
    info "未发现配置目录，跳过配置备份: ${STATE_DIR}"
    LAST_BACKUP_PATH=""
    return 0
  fi

  local ts backup_dir
  ts="$(date '+%Y%m%d-%H%M%S')"
  backup_dir="${BACKUP_ROOT}/openclaw-backup-${ts}"

  info "备份配置目录: ${STATE_DIR}"
  mkdir -p "${backup_dir}"
  cp -a "${STATE_DIR}" "${backup_dir}/"

  LAST_BACKUP_PATH="${backup_dir}/$(basename "${STATE_DIR}")"
  info "配置已备份到: ${LAST_BACKUP_PATH}"
}

load_backups() {
  BACKUP_DIRS=()
  ensure_backup_root

  while IFS= read -r line; do
    [ -n "${line}" ] && BACKUP_DIRS+=("${line}")
  done < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name 'openclaw-backup-*' | sort -r)
}

show_backups() {
  local i=1
  load_backups

  echo
  echo "可用配置备份："
  if [ "${#BACKUP_DIRS[@]}" -eq 0 ]; then
    echo "  (无备份)"
    echo
    return 1
  fi

  for line in "${BACKUP_DIRS[@]}"; do
    printf "  [%02d] %s\n" "${i}" "${line}"
    i=$((i + 1))
  done
  echo
  return 0
}

restore_backup_interactive() {
  local input index selected backup_state_dir

  show_backups || die "没有可恢复的配置备份"

  while true; do
    read -r -p "请输入要恢复的备份序号 [默认: 1]: " input
    input="${input:-1}"

    if ! is_positive_integer "${input}"; then
      warn "请输入有效序号"
      continue
    fi

    index=$((input - 1))
    if [ "${index}" -lt 0 ] || [ "${index}" -ge "${#BACKUP_DIRS[@]}" ]; then
      warn "序号超出范围"
      continue
    fi

    selected="${BACKUP_DIRS[$index]}"
    backup_state_dir="${selected}/$(basename "${STATE_DIR}")"

    [ -d "${backup_state_dir}" ] || die "备份目录不完整: ${backup_state_dir}"

    if [ -d "${STATE_DIR}" ]; then
      local ts current_backup
      ts="$(date '+%Y%m%d-%H%M%S')"
      current_backup="${BACKUP_ROOT}/restore-safety-${ts}"
      mkdir -p "${current_backup}"
      cp -a "${STATE_DIR}" "${current_backup}/"
      info "恢复前，当前配置已额外备份到: ${current_backup}/$(basename "${STATE_DIR}")"
      rm -rf "${STATE_DIR}"
    fi

    cp -a "${backup_state_dir}" "${STATE_DIR}"
    info "已恢复配置到: ${STATE_DIR}"
    return 0
  done
}

maybe_restore_latest_backup_on_fail() {
  if [ "${AUTO_RESTORE_CONFIG_ON_FAIL}" != "1" ]; then
    warn "未启用自动恢复配置（如需启用，设置 AUTO_RESTORE_CONFIG_ON_FAIL=1）"
    return 0
  fi

  if [ -z "${LAST_BACKUP_PATH}" ] || [ ! -d "${LAST_BACKUP_PATH}" ]; then
    warn "没有可自动恢复的最近配置备份"
    return 0
  fi

  warn "开始自动恢复最近一次配置备份: ${LAST_BACKUP_PATH}"

  if [ -d "${STATE_DIR}" ]; then
    rm -rf "${STATE_DIR}" || true
  fi

  cp -a "${LAST_BACKUP_PATH}" "${STATE_DIR}"
  info "已恢复配置到: ${STATE_DIR}"
}

cleanup_old_links_only() {
  rm -f /usr/local/bin/openclaw >/dev/null 2>&1 || true
  rm -f /usr/bin/openclaw >/dev/null 2>&1 || true
  hash -r || true
}

install_target_version() {
  info "安装 ${PKG_NAME}@${VERSION}"
  ensure_npm_global_bin_in_path
  export SHARP_IGNORE_GLOBAL_LIBVIPS=1

  npm install -g "${PKG_NAME}@${VERSION}"
  hash -r || true

  ensure_npm_global_bin_in_path
  cleanup_old_links_only
  create_openclaw_symlink_if_needed
  append_path_hint_to_shell_profiles
  hash -r || true

  if ! require_cmd openclaw; then
    local direct_bin
    direct_bin="$(get_npm_bin)/openclaw"
    [ -x "${direct_bin}" ] || die "安装完成，但未找到 ${direct_bin}"
  fi
}

rollback_to_previous_if_needed() {
  if [ -n "${PREVIOUS_VERSION}" ]; then
    warn "检测到已有旧版本，开始自动回退到 ${PREVIOUS_VERSION}"
    npm install -g "${PKG_NAME}@${PREVIOUS_VERSION}" >/dev/null 2>&1 || true
    hash -r || true
    ensure_npm_global_bin_in_path
    create_openclaw_symlink_if_needed
  else
    warn "没有可自动回退的旧版本"
  fi
}

openclaw_exec() {
  if require_cmd openclaw; then
    openclaw "$@"
    return
  fi

  local direct_bin
  direct_bin="$(get_npm_bin)/openclaw"

  if [ -x "${direct_bin}" ]; then
    "${direct_bin}" "$@"
    return
  fi

  die "无法执行 openclaw，请检查 npm 全局安装目录"
}

show_path_diagnostics() {
  echo
  info "PATH 诊断"
  echo "PATH=${PATH}"
  echo "npm prefix -g: $(get_npm_prefix)"
  echo "npm bin:      $(get_npm_bin)"
  echo "配置目录:     ${STATE_DIR}"
  echo "备份目录:     ${BACKUP_ROOT}"

  if [ -x "$(get_npm_bin)/openclaw" ]; then
    echo "npm 全局 openclaw: $(get_npm_bin)/openclaw"
  fi

  [ -e /usr/local/bin/openclaw ] && echo "/usr/local/bin/openclaw -> $(readlink -f /usr/local/bin/openclaw || echo /usr/local/bin/openclaw)"
  [ -e /usr/bin/openclaw ] && echo "/usr/bin/openclaw -> $(readlink -f /usr/bin/openclaw || echo /usr/bin/openclaw)"
}

install_daemon() {
  if [ "${SKIP_ONBOARD}" = "1" ]; then
    warn "已设置 SKIP_ONBOARD=1，跳过 onboard --install-daemon"
    return 0
  fi

  info "安装 / 更新 daemon"
  echo "注意：接下来会进入 OpenClaw 的 onboard 流程"
  openclaw_exec onboard --install-daemon
}

enable_systemd_user_service_if_possible() {
  info "尝试启用 systemd --user 开机自启"

  if ! require_cmd systemctl; then
    warn "未检测到 systemctl，跳过 systemd 自启动配置"
    return 0
  fi

  local found svc
  found=""

  for svc in     openclaw-gateway-default.service     openclaw-gateway.service
  do
    if systemctl --user list-unit-files 2>/dev/null | grep -q "^${svc}[[:space:]]"; then
      found="${svc}"
      break
    fi
  done

  if [ -z "${found}" ]; then
    found="$(systemctl --user list-unit-files 2>/dev/null | awk '/^openclaw-gateway.*\.service/ {print $1; exit}')"
  fi

  if [ -n "${found}" ]; then
    info "找到服务: ${found}"
    run_quiet systemctl --user daemon-reload
    systemctl --user enable "${found}" || true
    systemctl --user restart "${found}" || systemctl --user start "${found}" || true

    if require_cmd loginctl; then
      run_quiet loginctl enable-linger "$(id -un)"
    fi
  else
    warn "未发现 OpenClaw 的 systemd --user 服务文件"
    warn "这通常说明当前环境不是标准用户会话，或 onboard 尚未完成"
  fi
}

perform_install_or_rollback() {
  save_previous_version
  backup_config_if_exists

  if ! install_target_version; then
    warn "目标版本安装失败"
    rollback_to_previous_if_needed
    maybe_restore_latest_backup_on_fail
    die "安装失败，已尝试自动回退，并按配置决定是否恢复备份"
  fi

  detect_current_version
  if [ "${CURRENT_VERSION}" != "${VERSION}" ]; then
    warn "安装后检测到的版本与目标版本不一致"
    rollback_to_previous_if_needed
    maybe_restore_latest_backup_on_fail
    die "版本校验失败，已尝试自动回退，并按配置决定是否恢复备份"
  fi
}

show_result() {
  echo
  info "执行结果"

  if require_cmd openclaw; then
    echo "openclaw 路径: $(command -v openclaw)"
    echo "openclaw 版本: $(openclaw --version 2>/dev/null || echo unknown)"
  elif [ -x "$(get_npm_bin)/openclaw" ]; then
    echo "openclaw 路径: $(get_npm_bin)/openclaw"
    echo "openclaw 版本: $($(get_npm_bin)/openclaw --version 2>/dev/null || echo unknown)"
  else
    warn "openclaw 未找到"
  fi

  [ -n "${PREVIOUS_VERSION}" ] && echo "操作前版本: ${PREVIOUS_VERSION}"
  [ -n "${CURRENT_VERSION}" ] && echo "当前版本:   ${CURRENT_VERSION}"
  [ -n "${VERSION}" ] && echo "目标版本:   ${VERSION}"
  echo "操作模式:   ${ACTION}"
  [ -n "${LAST_BACKUP_PATH}" ] && echo "最近备份:   ${LAST_BACKUP_PATH}"

  show_path_diagnostics

  if require_cmd systemctl; then
    echo
    echo "systemd --user 中的 OpenClaw 服务："
    systemctl --user list-units --all 'openclaw-gateway*' --no-pager || true

    echo
    echo "服务状态："
    systemctl --user status 'openclaw-gateway*' --no-pager || true
  fi

  echo
  echo "常用命令："
  echo "  openclaw --version"
  echo "  openclaw dashboard"
  echo "  openclaw gateway status"
  echo "  systemctl --user status 'openclaw-gateway*'"
  echo "  journalctl --user -u openclaw-gateway-default.service -n 100 --no-pager"
  echo "  journalctl --user -u openclaw-gateway.service -n 100 --no-pager"
}

main() {
  setup_sudo
  ensure_node
  detect_current_version
  fetch_versions
  show_versions
  select_action

  if [ "${ACTION}" = "restore-config" ]; then
    restore_backup_interactive
    show_result
    return 0
  fi

  select_target_version
  ensure_not_same_version
  perform_install_or_rollback
  install_daemon
  enable_systemd_user_service_if_possible
  detect_current_version
  show_result
}

main "$@"
