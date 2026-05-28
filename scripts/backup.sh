#!/bin/bash
# ============================================================
# ai-api-agg 数据库与配置自动备份脚本 v2
# ============================================================
# 功能：
#   (无参数)   旧版兼容模式 — 备份数据库+配置，保留 7 天
#   --full     全量备份 — SQLite integrity check + SHA256 + 30 天保留
#   --incremental 增量备份 — WAL + 变更页，比全量小很多，7 天保留
#   --upload   备份后自动 rsync/scp 到远程
#
# 用法：
#   bash backup.sh                       # 兼容旧版
#   bash backup.sh --full                # 全量备份
#   bash backup.sh --full --upload       # 全量 + 上传远程
#   bash backup.sh --incremental         # 增量备份
#   bash backup.sh --incremental --upload
#
# 环境变量：
#   BACKUP_RETENTION_DAYS        全量备份保留天数（默认 30）
#   INCREMENTAL_RETENTION_DAYS   增量备份保留天数（默认 7）
#   REMOTE_BACKUP_HOST           远程备份主机（如 user@backup.example.com）
#   REMOTE_BACKUP_PATH           远程备份路径（如 /data/backups/ai-api-agg/）
#   BACKUP_RSYNC_DEST            旧版 rsync 目标（兼容）
#   BACKUP_SCP_DEST              旧版 scp 目标（兼容）
# ============================================================

set -e

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$BACKUP_DIR/backup.log"
DB_FILE="$PROJECT_DIR/backend/data/app.db"
CONFIG_DIR="$PROJECT_DIR/config"
DOCKER_DIR="$PROJECT_DIR/docker"
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# ---------- 通知函数 ----------
notify_backup() {
  local level="$1" title="$2" message="$3"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
  fi
}

# ---------- 默认环境变量 ----------
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
INCREMENTAL_RETENTION_DAYS="${INCREMENTAL_RETENTION_DAYS:-7}"

# ---------- 时间戳 ----------
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
TIMESTAMP_EPOCH=$(date +%s)

# ---------- 参数解析 ----------
MODE="legacy"
DO_UPLOAD=false

for arg in "$@"; do
    case "$arg" in
        --full)
            MODE="full"
            ;;
        --incremental)
            MODE="incremental"
            ;;
        --upload)
            DO_UPLOAD=true
            ;;
        *)
            echo "未知参数: $arg"
            echo "用法: $0 [--full|--incremental] [--upload]"
            exit 1
            ;;
    esac
done

# ---------- 日志函数 ----------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------- 初始化 ----------
init() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/full"
    mkdir -p "$BACKUP_DIR/incremental"

    # 初始化 manifest.json（如果不存在）
    if [ ! -f "$BACKUP_DIR/manifest.json" ]; then
        echo '{"version":"2.0","backups":[]}' > "$BACKUP_DIR/manifest.json"
    fi
}

# ---------- 清单管理 ----------
manifest_add() {
    local filename="$1" size="$2" sha256="$3" type="$4" timestamp="$5"

    local tmp
    tmp=$(mktemp)
    jq --arg fn "$filename" \
       --arg sz "$size" \
       --arg sh "$sha256" \
       --arg tp "$type" \
       --arg ts "$timestamp" \
       '.backups += [{"filename":$fn,"size_bytes":($sz|tonumber),"sha256":$sh,"type":$tp,"timestamp":($ts|tonumber)}]' \
       "$BACKUP_DIR/manifest.json" > "$tmp" && mv "$tmp" "$BACKUP_DIR/manifest.json"
}

manifest_remove() {
    local filename="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg fn "$filename" \
       '.backups = [.backups[] | select(.filename != $fn)]' \
       "$BACKUP_DIR/manifest.json" > "$tmp" && mv "$tmp" "$BACKUP_DIR/manifest.json"
}

# ---------- SHA256 校验和 ----------
generate_sha256() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# ---------- SQLite 完整性检查 ----------
sqlite_integrity_check() {
    local db="$1"
    if [ ! -f "$db" ]; then
        log "WARNING: 数据库文件不存在 ($db)，跳过完整性检查"
        return 0
    fi
    local result
    result=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>&1) || true
    if [ "$result" = "ok" ]; then
        log "SQLite 完整性检查: 通过 ($db)"
        return 0
    else
        log "ERROR: SQLite 完整性检查失败: $result"
        return 1
    fi
}

# ---------- 清理旧备份 ----------
cleanup_old_backups() {
    local type="$1"    # "full" or "incremental"
    local retention_days="$2"
    local subdir

    if [ "$type" = "full" ]; then
        subdir="full"
    else
        subdir="incremental"
    fi

    local deleted=0
    local cutoff
    cutoff=$(date -d "$retention_days days ago" +%s)

    for backup_file in "$BACKUP_DIR/$subdir"/*.tar.gz; do
        [ -f "$backup_file" ] || continue
        local filename
        filename=$(basename "$backup_file")
        # 从文件名提取时间戳: backup-full-2026-05-28-143022.tar.gz
        local date_part
        date_part=$(echo "$filename" | grep -oP '\d{4}-\d{2}-\d{2}-\d{6}')
        if [ -n "$date_part" ]; then
            # 将 2026-05-28-143022 → 2026-05-28 14:30:22
            local y m d hh mm ss
            y=${date_part:0:4}
            m=${date_part:5:2}
            d=${date_part:8:2}
            hh=${date_part:11:2}
            mm=${date_part:13:2}
            ss=${date_part:15:2}
            local file_epoch
            file_epoch=$(date -d "${y}-${m}-${d} ${hh}:${mm}:${ss}" +%s 2>/dev/null) || continue
            if [ "$file_epoch" -lt "$cutoff" ]; then
                log "清理旧${type}备份: $filename"
                # 同步清理 .sha256 文件
                rm -f "$backup_file" "${backup_file}.sha256"
                manifest_remove "$filename"
                deleted=$((deleted + 1))
            fi
        fi
    done
    log "清理完成: 删除 $deleted 个旧${type}备份（保留 ${retention_days} 天）"
}

# ---------- 清理旧式备份（无参数模式） ----------
cleanup_legacy_backups() {
    local deleted=0
    local cutoff
    cutoff=$(date -d "7 days ago" +%s)

    for old_backup in "$BACKUP_DIR"/backup-*.tar.gz; do
        [ -f "$old_backup" ] || continue
        [ -L "$old_backup" ] && continue
        local filename
        filename=$(basename "$old_backup")
        local date_part
        date_part=$(echo "$filename" | grep -oP '\d{4}-\d{2}-\d{2}')
        if [ -n "$date_part" ]; then
            local file_date
            file_date=$(date -d "$date_part" +%s 2>/dev/null || true)
            if [ -n "$file_date" ] && [ "$file_date" -lt "$cutoff" ]; then
                log "清理旧备份: $filename"
                rm -f "$old_backup"
                deleted=$((deleted + 1))
            fi
        fi
    done
    log "清理完成，删除了 $deleted 个旧备份"
}

# ---------- 上传到远程 ----------
upload_to_remote() {
    local file="$1"

    # 优先使用新环境变量 REMOTE_BACKUP_HOST + REMOTE_BACKUP_PATH
    if [ -n "${REMOTE_BACKUP_HOST:-}" ] && [ -n "${REMOTE_BACKUP_PATH:-}" ]; then
        log "开始远程备份 -> ${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/"
        # 上传主备份文件
        if rsync -avz "$file" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>&1 | tee -a "$LOG_FILE"; then
            log "远程备份上传成功 (rsync)"
        else
            log "ERROR: rsync 上传失败，尝试 scp..."
            if scp "$file" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>&1 | tee -a "$LOG_FILE"; then
                log "远程备份上传成功 (scp fallback)"
            else
                log "ERROR: 远程备份上传失败（不影响本地备份）"
                return 1
            fi
        fi
        # 上传 SHA256 文件
        if [ -f "${file}.sha256" ]; then
            rsync -avz "${file}.sha256" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>/dev/null || \
            scp "${file}.sha256" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>/dev/null || true
        fi
        # 上传 manifest
        rsync -avz "$BACKUP_DIR/manifest.json" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>/dev/null || \
        scp "$BACKUP_DIR/manifest.json" "${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" 2>/dev/null || true
        return 0
    fi

    # 兼容旧版环境变量
    if [ -n "${BACKUP_RSYNC_DEST:-}" ]; then
        log "开始 rsync 异地备份 -> $BACKUP_RSYNC_DEST"
        if rsync -avz "$file" "$BACKUP_RSYNC_DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "rsync 异地备份成功"
            [ -f "${file}.sha256" ] && rsync -avz "${file}.sha256" "$BACKUP_RSYNC_DEST" 2>/dev/null || true
        else
            log "ERROR: rsync 异地备份失败（不影响本地备份）"
        fi
    fi

    if [ -n "${BACKUP_SCP_DEST:-}" ]; then
        log "开始 scp 异地备份 -> $BACKUP_SCP_DEST"
        if scp "$file" "$BACKUP_SCP_DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "scp 异地备份成功"
            [ -f "${file}.sha256" ] && scp "${file}.sha256" "$BACKUP_SCP_DEST" 2>/dev/null || true
        else
            log "ERROR: scp 异地备份失败（不影响本地备份）"
        fi
    fi
}

# ============================================================
# 模式：全量备份 (--full)
# ============================================================
do_full_backup() {
    log "========== 开始全量备份 (v2) =========="

    local backup_name="backup-full-${TIMESTAMP}.tar.gz"
    local backup_path="$BACKUP_DIR/full/$backup_name"

    # 1. WAL Checkpoint
    if [ -f "$DB_FILE" ]; then
        log "执行 WAL checkpoint: $DB_FILE"
        sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" || log "WARNING: WAL checkpoint 失败"
    else
        log "WARNING: 数据库文件不存在 ($DB_FILE)"
    fi

    # 2. SQLite 完整性检查
    if [ -f "$DB_FILE" ]; then
        sqlite_integrity_check "$DB_FILE" || {
            log "ERROR: 完整性检查失败，备份中止"
            return 1
        }
    fi

    # 3. 创建临时备份目录
    local tmp_dir
    tmp_dir=$(mktemp -d)

    cleanup() { rm -rf "$tmp_dir"; }
    trap cleanup EXIT

    # 4. 备份数据库（含 WAL/SHM）
    if [ -f "$DB_FILE" ]; then
        mkdir -p "$tmp_dir/db"
        cp "$DB_FILE" "$tmp_dir/db/app.db"
        [ -f "$DB_FILE-wal" ] && cp "$DB_FILE-wal" "$tmp_dir/db/"
        [ -f "$DB_FILE-shm" ] && cp "$DB_FILE-shm" "$tmp_dir/db/"
        log "数据库备份完成"
    fi

    # 5. 备份配置
    mkdir -p "$tmp_dir/config"
    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        cp "$CONFIG_DIR/config.yaml" "$tmp_dir/config/"
    fi
    [ -f "$CONFIG_DIR/config.example.yaml" ] && cp "$CONFIG_DIR/config.example.yaml" "$tmp_dir/config/"

    mkdir -p "$tmp_dir/docker"
    [ -f "$DOCKER_DIR/.env" ] && cp "$DOCKER_DIR/.env" "$tmp_dir/docker/"
    [ -f "$DOCKER_DIR/docker-compose.yml" ] && cp "$DOCKER_DIR/docker-compose.yml" "$tmp_dir/docker/"

    # 6. 打包压缩
    cd "$tmp_dir"
    tar czf "$backup_path" .
    cd "$PROJECT_DIR"

    local backup_size
    backup_size=$(stat -c%s "$backup_path")
    log "全量备份打包完成: $backup_name ($(du -h "$backup_path" | cut -f1))"

    # 7. 生成 SHA256 校验和
    local sha256_hash
    sha256_hash=$(generate_sha256 "$backup_path")
    echo "$sha256_hash  $backup_name" > "${backup_path}.sha256"
    log "SHA256: $sha256_hash"

    # 8. 更新 manifest
    manifest_add "$backup_name" "$backup_size" "$sha256_hash" "full" "$TIMESTAMP_EPOCH"

    # 9. 创建 latest 符号链接
    ln -sf "$backup_path" "$BACKUP_DIR/full/backup-full-latest.tar.gz"
    cp "${backup_path}.sha256" "$BACKUP_DIR/full/backup-full-latest.tar.gz.sha256" 2>/dev/null || true

    # 10. 清理旧全量备份
    cleanup_old_backups "full" "$BACKUP_RETENTION_DAYS"

    # 11. 上传（可选）
    if [ "$DO_UPLOAD" = true ]; then
        upload_to_remote "$backup_path"
    fi

    log "========== 全量备份完成: $backup_name =========="
    notify_backup "info" "全量备份完成" "备份文件: $backup_name, 大小: $(du -h "$backup_path" | cut -f1), SHA256: ${sha256_hash:0:16}..."
}

# ============================================================
# 模式：增量备份 (--incremental)
# ============================================================
do_incremental_backup() {
    log "========== 开始增量备份 (v2) =========="

    if [ ! -f "$DB_FILE" ]; then
        log "ERROR: 数据库文件不存在 ($DB_FILE)，增量备份中止"
        return 1
    fi

    local backup_name="backup-incr-${TIMESTAMP}.tar.gz"
    local backup_path="$BACKUP_DIR/incremental/$backup_name"

    # 1. 复制数据库文件（不执行 checkpoint，保留 WAL 内容）
    local tmp_dir
    tmp_dir=$(mktemp -d)

    cleanup() { rm -rf "$tmp_dir"; }
    trap cleanup EXIT

    mkdir -p "$tmp_dir/db"

    # 使用 SQLite 的 backup API 创建热备份（一致性快照）
    sqlite3 "$DB_FILE" ".backup '$tmp_dir/db/app.db'" 2>/dev/null || {
        log "WARNING: .backup 失败，使用 cp 作为兜底"
        cp "$DB_FILE" "$tmp_dir/db/app.db"
    }

    # 复制 WAL 和 SHM 文件（增量关键）
    [ -f "$DB_FILE-wal" ] && cp "$DB_FILE-wal" "$tmp_dir/db/"
    [ -f "$DB_FILE-shm" ] && cp "$DB_FILE-shm" "$tmp_dir/db/"

    log "数据库增量文件复制完成"

    # 2. 备份配置（轻量）
    mkdir -p "$tmp_dir/config"
    [ -f "$CONFIG_DIR/config.yaml" ] && cp "$CONFIG_DIR/config.yaml" "$tmp_dir/config/"

    mkdir -p "$tmp_dir/docker"
    [ -f "$DOCKER_DIR/.env" ] && cp "$DOCKER_DIR/.env" "$tmp_dir/docker/"
    [ -f "$DOCKER_DIR/docker-compose.yml" ] && cp "$DOCKER_DIR/docker-compose.yml" "$tmp_dir/docker/"

    # 3. 打包压缩
    cd "$tmp_dir"
    tar czf "$backup_path" .
    cd "$PROJECT_DIR"

    local backup_size
    backup_size=$(stat -c%s "$backup_path")
    log "增量备份打包完成: $backup_name ($(du -h "$backup_path" | cut -f1))"

    # 4. 生成 SHA256 校验和
    local sha256_hash
    sha256_hash=$(generate_sha256 "$backup_path")
    echo "$sha256_hash  $backup_name" > "${backup_path}.sha256"
    log "SHA256: $sha256_hash"

    # 5. 更新 manifest
    manifest_add "$backup_name" "$backup_size" "$sha256_hash" "incremental" "$TIMESTAMP_EPOCH"

    # 6. 创建 latest 符号链接
    ln -sf "$backup_path" "$BACKUP_DIR/incremental/backup-incr-latest.tar.gz"

    # 7. 清理旧增量备份
    cleanup_old_backups "incremental" "$INCREMENTAL_RETENTION_DAYS"

    # 8. 上传（可选）
    if [ "$DO_UPLOAD" = true ]; then
        upload_to_remote "$backup_path"
    fi

    log "========== 增量备份完成: $backup_name =========="
    notify_backup "info" "增量备份完成" "备份文件: $backup_name, 大小: $(du -h "$backup_path" | cut -f1)"
}

# ============================================================
# 模式：旧版兼容备份（无参数）
# ============================================================
do_legacy_backup() {
    log "========== 开始备份 (旧版兼容模式) =========="

    local backup_file="$BACKUP_DIR/backup-${TIMESTAMP}.tar.gz"

    # 1. WAL Checkpoint
    if [ -f "$DB_FILE" ]; then
        log "执行 WAL checkpoint: $DB_FILE"
        sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" || log "WARNING: WAL checkpoint 失败，继续执行"
    else
        log "WARNING: 数据库文件不存在 ($DB_FILE)，跳过 checkpoint"
    fi

    # 2. 创建临时备份目录
    local tmp_dir
    tmp_dir=$(mktemp -d)

    cleanup() { rm -rf "$tmp_dir"; }
    trap cleanup EXIT

    # 3. 备份数据库
    if [ -f "$DB_FILE" ]; then
        mkdir -p "$tmp_dir/db"
        cp "$DB_FILE" "$tmp_dir/db/app.db"
        [ -f "$DB_FILE-wal" ] && cp "$DB_FILE-wal" "$tmp_dir/db/"
        [ -f "$DB_FILE-shm" ] && cp "$DB_FILE-shm" "$tmp_dir/db/"
        log "数据库备份完成"
    else
        log "WARNING: 数据库文件不存在，跳过 ($DB_FILE)"
    fi

    # 4. 备份配置文件
    mkdir -p "$tmp_dir/config"
    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        cp "$CONFIG_DIR/config.yaml" "$tmp_dir/config/"
        log "config.yaml 备份完成"
    else
        log "WARNING: config.yaml 不存在，跳过"
    fi
    [ -f "$CONFIG_DIR/config.example.yaml" ] && cp "$CONFIG_DIR/config.example.yaml" "$tmp_dir/config/"

    mkdir -p "$tmp_dir/docker"
    if [ -f "$DOCKER_DIR/.env" ]; then
        cp "$DOCKER_DIR/.env" "$tmp_dir/docker/"
        log "docker/.env 备份完成"
    else
        log "WARNING: docker/.env 不存在，跳过"
    fi
    [ -f "$DOCKER_DIR/docker-compose.yml" ] && cp "$DOCKER_DIR/docker-compose.yml" "$tmp_dir/docker/"

    # 5. 打包压缩
    cd "$tmp_dir"
    tar czf "$backup_file" .
    cd "$PROJECT_DIR"
    log "备份打包完成: $backup_file ($(du -h "$backup_file" | cut -f1))"

    # 6. 清理 7 天前的旧备份
    cleanup_legacy_backups

    # 7. 异地备份（可选，兼容旧版）
    # rsync 远程备份
    if [ -n "${BACKUP_RSYNC_DEST:-}" ]; then
        log "开始 rsync 异地备份 -> $BACKUP_RSYNC_DEST"
        if rsync -avz "$backup_file" "$BACKUP_RSYNC_DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "rsync 异地备份成功"
        else
            log "ERROR: rsync 异地备份失败（不影响本地备份）"
        fi
    else
        log "未配置 BACKUP_RSYNC_DEST，跳过 rsync 异地备份"
    fi

    # scp 远程备份
    if [ -n "${BACKUP_SCP_DEST:-}" ]; then
        log "开始 scp 异地备份 -> $BACKUP_SCP_DEST"
        if scp "$backup_file" "$BACKUP_SCP_DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "scp 异地备份成功"
        else
            log "ERROR: scp 异地备份失败（不影响本地备份）"
        fi
    else
        log "未配置 BACKUP_SCP_DEST，跳过 scp 异地备份"
    fi

    # 8. 更新 latest 符号链接
    ln -sf "$backup_file" "$BACKUP_DIR/backup-latest.tar.gz"

    # 9. 生成 SHA256 和 manifest（v2 增强）
    local sha256_hash
    sha256_hash=$(generate_sha256 "$backup_file")
    local backup_size
    backup_size=$(stat -c%s "$backup_file")
    echo "$sha256_hash  $backup_file" > "${backup_file}.sha256"

    manifest_add "backup-${TIMESTAMP}.tar.gz" "$backup_size" "$sha256_hash" "legacy" "$TIMESTAMP_EPOCH"

    log "========== 备份完成 =========="
    log "备份文件: $backup_file"
    log "日志文件: $LOG_FILE"
    notify_backup "info" "备份完成(旧版)" "备份文件: backup-${TIMESTAMP}.tar.gz, 大小: $(du -h "$backup_file" | cut -f1)"
}

# ============================================================
# 主入口
# ============================================================
init

case "$MODE" in
    full)
        do_full_backup
        ;;
    incremental)
        do_incremental_backup
        ;;
    legacy)
        do_legacy_backup
        ;;
esac
