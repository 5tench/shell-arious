#!/usr/bin/env bash
set -uo pipefail

###############################################################################
# Prisma Cloud Defender Health Check — v2.0.0
#
# Read-only diagnostic tool for Prisma Defenders on ECS (EC2 launch type).
# Covers: container state, cgroup CPU/memory limits, WebSocket connectivity,
# network path (NAT gateway detection), TCP keepalive, DNS, ECS task state,
# disk pressure, kernel events, and defender logs.
#
# Modes:
#   Live (default) — refreshes dashboard at --interval.
#   One-shot (--once) — prints once, exits 0=PASS / 1=WARNING / 2=FAILURE.
#
# Safety: changes nothing. No restarts, prunes, deletes, or secret exposure.
###############################################################################

readonly VERSION="2.0.0"

# Defaults — all overridable via flags or env vars.
CONTAINER="${CONTAINER:-}"
ECS_CLUSTER="${ECS_CLUSTER:-}"
ECS_TASK="${ECS_TASK:-}"
PRISMA_CONSOLE_URL="${PRISMA_CONSOLE_URL:-}"
CONSOLE_WS_PORT="${CONSOLE_WS_PORT:-8084}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-5}"
LOG_DIR="${LOG_DIR:-}"
LOG_SINCE="${LOG_SINCE:-15m}"
AWS_REGION="${AWS_REGION:-}"
RUN_ONCE=false
DISK_WARN_PERCENT="${DISK_WARN_PERCENT:-85}"
DISK_FAIL_PERCENT="${DISK_FAIL_PERCENT:-95}"
MEM_WARN_PERCENT="${MEM_WARN_PERCENT:-85}"
CPU_THROTTLE_WARN="${CPU_THROTTLE_WARN:-100}"

# Delta tracking between live refreshes.
_PREV_CPU_THROTTLED=0

###############################################################################
# Usage
###############################################################################

usage() {
  cat <<'EOF'
Usage: prisma-healthcheck.sh --container <id-or-name> [options]

Required:
  --container VALUE       Defender container ID or name

Recommended:
  --cluster VALUE         ECS cluster name or ARN
  --task VALUE            ECS task ARN or ID
  --console-url URL       Console health/ping endpoint (no auth required)

Optional:
  --ws-port PORT          Console WebSocket port        [default: 8084]
  --interval SECONDS      Live refresh interval         [default: 5]
  --log-since DURATION    Defender log window            [default: 15m]
  --log-dir DIR           Save timestamped evidence logs
  --region REGION         AWS region for ECS CLI calls
  --once                  One-shot mode (PASS/WARNING/FAILURE exit code)
  --disk-warn PERCENT     Docker fs warning threshold   [default: 85]
  --disk-fail PERCENT     Docker fs failure threshold   [default: 95]
  --mem-warn PERCENT      Container mem warning pct     [default: 85]
  --cpu-throttle-warn N   CPU throttle count threshold  [default: 100]
  --version               Print version
  -h, --help              Show this help

All flags have env-var equivalents: CONTAINER, ECS_CLUSTER, ECS_TASK,
PRISMA_CONSOLE_URL, CONSOLE_WS_PORT, REFRESH_INTERVAL, LOG_SINCE, LOG_DIR,
AWS_REGION, DISK_WARN_PERCENT, DISK_FAIL_PERCENT, MEM_WARN_PERCENT,
CPU_THROTTLE_WARN.

Examples:
  sudo ./prisma-healthcheck.sh \
    --container defender-container \
    --cluster prod-cluster \
    --task arn:aws:ecs:us-east-1:123456789012:task/prod-cluster/abc123 \
    --console-url https://console.example.com:8083/api/v1/_ping \
    --log-dir /var/log/prisma-healthcheck

  ./prisma-healthcheck.sh --container "$CID" --once
EOF
}

###############################################################################
# Argument parsing
###############################################################################

require_argument() {
  if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "ERROR: $1 requires a value." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)         require_argument "$1" "${2:-}"; CONTAINER="$2"; shift 2 ;;
    --cluster)           require_argument "$1" "${2:-}"; ECS_CLUSTER="$2"; shift 2 ;;
    --task)              require_argument "$1" "${2:-}"; ECS_TASK="$2"; shift 2 ;;
    --console-url)       require_argument "$1" "${2:-}"; PRISMA_CONSOLE_URL="$2"; shift 2 ;;
    --ws-port)           require_argument "$1" "${2:-}"; CONSOLE_WS_PORT="$2"; shift 2 ;;
    --interval)          require_argument "$1" "${2:-}"; REFRESH_INTERVAL="$2"; shift 2 ;;
    --log-since)         require_argument "$1" "${2:-}"; LOG_SINCE="$2"; shift 2 ;;
    --log-dir)           require_argument "$1" "${2:-}"; LOG_DIR="$2"; shift 2 ;;
    --region)            require_argument "$1" "${2:-}"; AWS_REGION="$2"; shift 2 ;;
    --disk-warn)         require_argument "$1" "${2:-}"; DISK_WARN_PERCENT="$2"; shift 2 ;;
    --disk-fail)         require_argument "$1" "${2:-}"; DISK_FAIL_PERCENT="$2"; shift 2 ;;
    --mem-warn)          require_argument "$1" "${2:-}"; MEM_WARN_PERCENT="$2"; shift 2 ;;
    --cpu-throttle-warn) require_argument "$1" "${2:-}"; CPU_THROTTLE_WARN="$2"; shift 2 ;;
    --once)              RUN_ONCE=true; shift ;;
    --version)           echo "prisma-healthcheck.sh $VERSION"; exit 0 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   echo "ERROR: Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

###############################################################################
# Validation
###############################################################################

is_percentage() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 0 && "$1" <= 100 ))
}

[[ -z "$CONTAINER" ]] && { echo "ERROR: --container is required." >&2; usage >&2; exit 2; }
[[ "$REFRESH_INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --interval must be numeric." >&2; exit 2; }
[[ "$CONSOLE_WS_PORT" =~ ^[0-9]+$ ]] || { echo "ERROR: --ws-port must be a port number." >&2; exit 2; }

for t in "$DISK_WARN_PERCENT" "$DISK_FAIL_PERCENT" "$MEM_WARN_PERCENT"; do
  is_percentage "$t" || { echo "ERROR: Thresholds must be 0-100." >&2; exit 2; }
done

(( DISK_WARN_PERCENT >= DISK_FAIL_PERCENT )) && { echo "ERROR: --disk-warn must be < --disk-fail." >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 2; }

###############################################################################
# Runtime setup
###############################################################################

LOG_FILE=""
if [[ -n "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR" || { echo "ERROR: Cannot create $LOG_DIR" >&2; exit 2; }
  LOG_FILE="$LOG_DIR/prisma-healthcheck-$(hostname -s)-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE" || { echo "ERROR: Cannot write $LOG_FILE" >&2; exit 2; }
fi

aws_region_args=()
[[ -n "$AWS_REGION" ]] && aws_region_args=(--region "$AWS_REGION")

###############################################################################
# IMDS helpers
###############################################################################

get_instance_id() {
  local token instance
  token=$(curl -fsS --max-time 1 -X PUT \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
    http://169.254.169.254/latest/api/token 2>/dev/null || true)

  if [[ -n "$token" ]]; then
    instance=$(curl -fsS --max-time 1 \
      -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)
  else
    instance=$(curl -fsS --max-time 1 \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)
  fi
  printf '%s' "${instance:-unavailable}"
}

get_imds_field() {
  local field="$1" token value
  token=$(curl -fsS --max-time 1 -X PUT \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
    http://169.254.169.254/latest/api/token 2>/dev/null || true)

  if [[ -n "$token" ]]; then
    value=$(curl -fsS --max-time 1 \
      -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/$field" 2>/dev/null || true)
  else
    value=$(curl -fsS --max-time 1 \
      "http://169.254.169.254/latest/meta-data/$field" 2>/dev/null || true)
  fi
  printf '%s' "${value:-unavailable}"
}

###############################################################################
# Small helpers
###############################################################################

print_section() {
  printf '\n=== %-61s===\n' "$1 "
}

get_container_pid() {
  docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null
}

get_docker_disk_percent() {
  df -P /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_container_memory_percent() {
  docker stats --no-stream --format '{{.MemPerc}}' "$CONTAINER" 2>/dev/null \
    | head -n1 | tr -d '%' | awk '{printf "%.0f",$1}'
}

check_console_connectivity() {
  curl -skS --connect-timeout 3 --max-time 8 \
    -o /dev/null \
    -w 'HTTP=%{http_code} DNS=%{time_namelookup}s Connect=%{time_connect}s TLS=%{time_appconnect}s Total=%{time_total}s RemoteIP=%{remote_ip}\n' \
    "$PRISMA_CONSOLE_URL"
}

###############################################################################
# WebSocket / network namespace checks
###############################################################################

check_websocket_state() {
  local pid
  pid=$(get_container_pid)
  [[ -z "$pid" || "$pid" == "0" ]] && { echo "  Unable to determine container PID."; return 1; }

  local found=0 hex_port
  hex_port=$(printf '%04X' "$CONSOLE_WS_PORT")

  # Try nsenter + ss first (readable output, available on most AL2/AL2023).
  if command -v nsenter >/dev/null 2>&1 && command -v ss >/dev/null 2>&1; then
    local ss_out
    ss_out=$(nsenter -t "$pid" -n ss -tn state established 2>/dev/null \
      | grep ":${CONSOLE_WS_PORT}" || true)
    if [[ -n "$ss_out" ]]; then
      echo "  ESTAB (via ss):"
      echo "$ss_out"
      found=1
    fi
  fi

  # Fallback: parse /proc/net/tcp{,6} from the container's namespace.
  if (( found == 0 )); then
    local proc_path matches
    for proto in tcp tcp6; do
      proc_path="/proc/$pid/net/$proto"
      [[ -r "$proc_path" ]] || continue
      matches=$(awk -v port="$hex_port" '
        NR>1 { split($3,r,":"); if (r[2]==port && $4=="01") print "  ESTAB  local="$2"  remote="$3 }
      ' "$proc_path" 2>/dev/null || true)
      if [[ -n "$matches" ]]; then
        echo "$matches"
        found=1
        break
      fi
    done
  fi

  if (( found == 0 )); then
    echo "  No ESTABLISHED connection on port $CONSOLE_WS_PORT"
    return 1
  fi
  return 0
}

show_all_container_connections() {
  local pid
  pid=$(get_container_pid)
  [[ -z "$pid" || "$pid" == "0" ]] && { echo "  Unable to determine container PID."; return; }

  if command -v nsenter >/dev/null 2>&1 && command -v ss >/dev/null 2>&1; then
    nsenter -t "$pid" -n ss -tn 2>/dev/null || echo "  nsenter+ss failed."
  elif [[ -r "/proc/$pid/net/tcp" ]]; then
    echo "  sl  local_address          rem_address            st"
    awk 'NR>1 {printf "  %-4s %-22s %-22s %s\n",$1,$2,$3,$4}' "/proc/$pid/net/tcp" 2>/dev/null || true
  else
    echo "  Cannot read container network state."
  fi
}

###############################################################################
# Cgroup helpers (v1 + v2)
###############################################################################

_find_cgroup_file() {
  local subdir="$1" filename="$2"
  local full_id
  full_id=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null || true)
  [[ -z "$full_id" ]] && return 1

  local base
  for base in \
    "/sys/fs/cgroup/${subdir}/docker/$full_id" \
    "/sys/fs/cgroup/${subdir}/ecs/$full_id"; do
    [[ -r "$base/$filename" ]] && { printf '%s' "$base/$filename"; return 0; }
  done

  local v2="/sys/fs/cgroup/system.slice/docker-${full_id}.scope/$filename"
  [[ -r "$v2" ]] && { printf '%s' "$v2"; return 0; }

  return 1
}

get_cpu_throttle_stats() {
  local stat_file
  stat_file=$(_find_cgroup_file "cpu,cpuacct" "cpu.stat" 2>/dev/null) \
    || stat_file=$(_find_cgroup_file "cpu" "cpu.stat" 2>/dev/null) \
    || { printf 'unavailable'; return; }

  awk '/nr_periods/    {p=$2}
       /nr_throttled/  {t=$2}
       /throttled_time/{tt=$2}
       END {printf "%s %s %s",p,t,tt}' "$stat_file" 2>/dev/null
}

get_cpu_quota_info() {
  local full_id
  full_id=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null || true)
  [[ -z "$full_id" ]] && { printf 'unavailable'; return; }

  local quota_file period_file base
  for base in \
    "/sys/fs/cgroup/cpu,cpuacct/docker/$full_id" \
    "/sys/fs/cgroup/cpu/docker/$full_id" \
    "/sys/fs/cgroup/cpu,cpuacct/ecs/$full_id" \
    "/sys/fs/cgroup/cpu/ecs/$full_id"; do
    quota_file="$base/cpu.cfs_quota_us"
    period_file="$base/cpu.cfs_period_us"
    if [[ -r "$quota_file" && -r "$period_file" ]]; then
      local quota period
      quota=$(cat "$quota_file" 2>/dev/null)
      period=$(cat "$period_file" 2>/dev/null)
      if [[ "$quota" == "-1" ]]; then
        printf 'unlimited (no CPU reservation)'
      else
        printf '%s vCPU (quota=%sus period=%sus)' \
          "$(awk "BEGIN {printf \"%.2f\",$quota/$period}")" "$quota" "$period"
      fi
      return
    fi
  done

  local v2="/sys/fs/cgroup/system.slice/docker-${full_id}.scope/cpu.max"
  if [[ -r "$v2" ]]; then
    local max_val
    max_val=$(cat "$v2" 2>/dev/null)
    if [[ "$max_val" == "max "* ]]; then
      printf 'unlimited (%s)' "$max_val"
    else
      local q p
      q=$(awk '{print $1}' <<< "$max_val")
      p=$(awk '{print $2}' <<< "$max_val")
      printf '%s vCPU (%s)' "$(awk "BEGIN {printf \"%.2f\",$q/$p}")" "$max_val"
    fi
    return
  fi

  printf 'unavailable'
}

get_memory_limit() {
  local full_id
  full_id=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null || true)
  [[ -z "$full_id" ]] && { printf 'unavailable'; return; }

  local limit="" base
  for base in \
    "/sys/fs/cgroup/memory/docker/$full_id" \
    "/sys/fs/cgroup/memory/ecs/$full_id"; do
    [[ -r "$base/memory.limit_in_bytes" ]] && { limit=$(cat "$base/memory.limit_in_bytes" 2>/dev/null); break; }
  done

  if [[ -z "$limit" ]]; then
    local v2="/sys/fs/cgroup/system.slice/docker-${full_id}.scope/memory.max"
    [[ -r "$v2" ]] && limit=$(cat "$v2" 2>/dev/null)
  fi

  if [[ -z "$limit" || "$limit" == "max" ]]; then
    printf 'unlimited'
  elif [[ "$limit" =~ ^[0-9]+$ ]]; then
    (( limit >= 4611686018427387904 )) && { printf 'unlimited'; return; }
    printf '%s MiB' "$(( limit / 1048576 ))"
  else
    printf '%s' "$limit"
  fi
}

###############################################################################
# Network path / keepalive
###############################################################################

check_network_path() {
  local public_ip mac subnet_id vpc_id
  public_ip=$(get_imds_field "public-ipv4")
  mac=$(get_imds_field "network/interfaces/macs/" | head -c 17)

  if [[ -n "$mac" && "$mac" != "unavailable" ]]; then
    subnet_id=$(get_imds_field "network/interfaces/macs/${mac}/subnet-id")
    vpc_id=$(get_imds_field "network/interfaces/macs/${mac}/vpc-id")
  else
    subnet_id="unavailable"
    vpc_id="unavailable"
  fi

  printf 'Public IPv4  : %s\n' "${public_ip:-none}"
  printf 'VPC          : %s\n' "$vpc_id"
  printf 'Subnet       : %s\n' "$subnet_id"

  if [[ -z "$public_ip" || "$public_ip" == "unavailable" ]]; then
    printf 'NAT Gateway  : LIKELY (no public IP — idle timeout risk at 350s)\n'
  else
    printf 'NAT Gateway  : NO (instance has public IP)\n'
  fi
}

show_tcp_keepalive() {
  local ka_time ka_intvl ka_probes
  if [[ -r /proc/sys/net/ipv4/tcp_keepalive_time ]]; then
    ka_time=$(cat /proc/sys/net/ipv4/tcp_keepalive_time 2>/dev/null || echo "?")
    ka_intvl=$(cat /proc/sys/net/ipv4/tcp_keepalive_intvl 2>/dev/null || echo "?")
    ka_probes=$(cat /proc/sys/net/ipv4/tcp_keepalive_probes 2>/dev/null || echo "?")
  else
    ka_time="?"; ka_intvl="?"; ka_probes="?"
  fi

  printf 'tcp_keepalive_time   : %ss\n' "$ka_time"
  printf 'tcp_keepalive_intvl  : %ss\n' "$ka_intvl"
  printf 'tcp_keepalive_probes : %s\n'  "$ka_probes"

  if [[ "$ka_time" =~ ^[0-9]+$ ]] && (( ka_time > 300 )); then
    printf '*** WARNING: keepalive_time (%ss) > NAT gateway idle timeout (350s).\n' "$ka_time"
    printf '    Fix: sysctl -w net.ipv4.tcp_keepalive_time=60\n'
  fi
}

###############################################################################
# Container DNS / threads
###############################################################################

show_container_dns() {
  local pid
  pid=$(get_container_pid)
  [[ -z "$pid" || "$pid" == "0" ]] && { echo "  Unable to determine container PID."; return; }

  local resolv="/proc/$pid/root/etc/resolv.conf"
  if [[ -r "$resolv" ]]; then
    cat "$resolv" 2>/dev/null
  else
    echo "  Cannot read container resolv.conf"
  fi
}

get_container_thread_count() {
  local pid
  pid=$(get_container_pid)
  [[ -z "$pid" || "$pid" == "0" ]] && { printf 'unavailable'; return; }

  local count
  count=$(find "/proc/$pid/task" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  printf '%s' "${count:-unavailable}"
}

###############################################################################
# Health evaluation
###############################################################################

evaluate_health() {
  local overall=0

  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "FAIL  Defender container unavailable: $CONTAINER"
    echo "Overall Status: FAILURE"
    return 2
  fi

  local status running health oom restarts
  status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)
  running=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$CONTAINER" 2>/dev/null || echo unknown)
  oom=$(docker inspect -f '{{.State.OOMKilled}}' "$CONTAINER" 2>/dev/null || echo false)
  restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo unknown)

  if [[ "$status" == "running" && "$running" == "true" ]]; then
    echo "PASS  Defender container is running"
  else
    echo "FAIL  Defender state: status=$status running=$running"
    overall=2
  fi

  if [[ "$health" == "healthy" || "$health" == "N/A" ]]; then
    echo "PASS  Docker health: $health"
  else
    echo "FAIL  Docker health: $health"
    overall=2
  fi

  [[ "$oom" == "true" ]] && { echo "FAIL  OOM-killed"; overall=2; } || echo "PASS  Not OOM-killed"

  if [[ "$restarts" =~ ^[0-9]+$ ]] && (( restarts > 0 )); then
    echo "WARN  Restart count: $restarts"
    (( overall < 1 )) && overall=1
  else
    echo "PASS  Restart count: ${restarts:-0}"
  fi

  # WebSocket to Console
  local ws_rc=0
  check_websocket_state >/dev/null 2>&1 || ws_rc=$?
  if (( ws_rc == 0 )); then
    echo "PASS  WebSocket (port $CONSOLE_WS_PORT) ESTABLISHED"
  else
    echo "FAIL  WebSocket (port $CONSOLE_WS_PORT) NOT established"
    overall=2
  fi

  # CPU throttling
  local throttle_raw
  throttle_raw=$(get_cpu_throttle_stats || true)
  if [[ "$throttle_raw" != "unavailable" ]]; then
    local nr_throttled
    nr_throttled=$(awk '{print $2}' <<< "$throttle_raw")
    if [[ "$nr_throttled" =~ ^[0-9]+$ ]] && (( nr_throttled > CPU_THROTTLE_WARN )); then
      echo "WARN  CPU throttled $nr_throttled times (threshold $CPU_THROTTLE_WARN)"
      (( overall < 1 )) && overall=1
    else
      echo "PASS  CPU throttled ${nr_throttled:-0} times"
    fi
  else
    echo "INFO  CPU throttle stats unavailable"
  fi

  # CPU quota — warn if no reservation at all
  local quota_info
  quota_info=$(get_cpu_quota_info)
  if [[ "$quota_info" == *"no CPU reservation"* ]]; then
    echo "WARN  CPU quota: unlimited — no guaranteed CPU (heartbeat starvation risk)"
    (( overall < 1 )) && overall=1
  fi

  # Docker filesystem
  local disk_pct
  disk_pct=$(get_docker_disk_percent || true)
  if [[ "$disk_pct" =~ ^[0-9]+$ ]]; then
    if (( disk_pct >= DISK_FAIL_PERCENT )); then
      echo "FAIL  Docker disk: ${disk_pct}% (threshold ${DISK_FAIL_PERCENT}%)"
      overall=2
    elif (( disk_pct >= DISK_WARN_PERCENT )); then
      echo "WARN  Docker disk: ${disk_pct}% (threshold ${DISK_WARN_PERCENT}%)"
      (( overall < 1 )) && overall=1
    else
      echo "PASS  Docker disk: ${disk_pct}%"
    fi
  else
    echo "WARN  Docker disk: unable to evaluate"
    (( overall < 1 )) && overall=1
  fi

  # Container memory
  local mem_pct
  mem_pct=$(get_container_memory_percent || true)
  if [[ "$mem_pct" =~ ^[0-9]+$ ]]; then
    if (( mem_pct >= MEM_WARN_PERCENT )); then
      echo "WARN  Container memory: ${mem_pct}% (threshold ${MEM_WARN_PERCENT}%)"
      (( overall < 1 )) && overall=1
    else
      echo "PASS  Container memory: ${mem_pct}%"
    fi
  else
    echo "WARN  Container memory: unable to evaluate"
    (( overall < 1 )) && overall=1
  fi

  # TCP keepalive vs NAT gateway
  local ka_time
  ka_time=$(cat /proc/sys/net/ipv4/tcp_keepalive_time 2>/dev/null || echo "?")
  if [[ "$ka_time" =~ ^[0-9]+$ ]] && (( ka_time > 300 )); then
    echo "WARN  tcp_keepalive_time: ${ka_time}s (NAT idle drop risk)"
    (( overall < 1 )) && overall=1
  elif [[ "$ka_time" =~ ^[0-9]+$ ]]; then
    echo "PASS  tcp_keepalive_time: ${ka_time}s"
  fi

  # ECS task
  if [[ -n "$ECS_CLUSTER" && -n "$ECS_TASK" ]] && command -v aws >/dev/null 2>&1; then
    local ecs_last ecs_health
    ecs_last=$(aws ecs describe-tasks ${aws_region_args[@]+"${aws_region_args[@]}"} \
      --cluster "$ECS_CLUSTER" --tasks "$ECS_TASK" \
      --query 'tasks[0].lastStatus' --output text 2>/dev/null || true)
    ecs_health=$(aws ecs describe-tasks ${aws_region_args[@]+"${aws_region_args[@]}"} \
      --cluster "$ECS_CLUSTER" --tasks "$ECS_TASK" \
      --query 'tasks[0].healthStatus' --output text 2>/dev/null || true)

    if [[ "$ecs_last" == "RUNNING" ]] && [[ "$ecs_health" == "HEALTHY" || "$ecs_health" == "UNKNOWN" || "$ecs_health" == "None" ]]; then
      echo "PASS  ECS task: last=$ecs_last health=$ecs_health"
    else
      echo "FAIL  ECS task: last=${ecs_last:-unknown} health=${ecs_health:-unknown}"
      overall=2
    fi
  else
    echo "INFO  ECS check skipped (cluster/task/aws-cli not available)"
  fi

  # Console reachability
  if [[ -n "$PRISMA_CONSOLE_URL" ]]; then
    local result
    result=$(check_console_connectivity 2>/dev/null || true)
    if [[ "$result" =~ HTTP=([0-9]{3}) ]]; then
      local code="${BASH_REMATCH[1]}"
      if [[ "$code" != "000" && "$code" -lt 500 ]]; then
        echo "PASS  Console reachable (HTTP $code)"
      else
        echo "FAIL  Console returned HTTP $code"
        overall=2
      fi
    else
      echo "FAIL  Console unreachable"
      overall=2
    fi
  else
    echo "INFO  Console check skipped (no --console-url)"
  fi

  case "$overall" in
    0) echo "Overall Status: PASS" ;;
    1) echo "Overall Status: WARNING" ;;
    *) echo "Overall Status: FAILURE" ;;
  esac
  return "$overall"
}

###############################################################################
# Dashboard
###############################################################################

snapshot() {
  local now
  now=$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')

  echo "=================================================================="
  echo "               PRISMA CLOUD HEALTH CHECK  v$VERSION"
  echo "=================================================================="
  printf 'Timestamp : %s\n' "$now"
  printf 'Hostname  : %s\n' "$(hostname -f 2>/dev/null || hostname)"
  printf 'Instance  : %s\n' "$(get_instance_id)"
  printf 'Mode      : %s\n' "$([[ "$RUN_ONCE" == true ]] && echo one-shot || echo live)"
  printf 'Refresh   : %ss\n' "$REFRESH_INTERVAL"
  printf 'Log Window: %s\n' "$LOG_SINCE"

  print_section "DEFENDER IDENTITY"
  docker inspect "$CONTAINER" --format '
Container ID : {{.Id}}
Container    : {{.Name}}
Image        : {{.Config.Image}}
Image ID     : {{.Image}}
Task ARN     : {{index .Config.Labels "com.amazonaws.ecs.task-arn"}}
Task Family  : {{index .Config.Labels "com.amazonaws.ecs.task-definition-family"}}
Task Revision: {{index .Config.Labels "com.amazonaws.ecs.task-definition-version"}}' 2>&1 || true

  print_section "DEFENDER STATUS"
  docker inspect "$CONTAINER" --format '
Status       : {{.State.Status}}
Running      : {{.State.Running}}
Paused       : {{.State.Paused}}
Restarting   : {{.State.Restarting}}
Health       : {{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}
OOMKilled    : {{.State.OOMKilled}}
ExitCode     : {{.State.ExitCode}}
RestartCount : {{.RestartCount}}
Started      : {{.State.StartedAt}}
Finished     : {{.State.FinishedAt}}
Error        : {{if .State.Error}}{{.State.Error}}{{else}}None{{end}}' 2>&1 || true

  print_section "CGROUP RESOURCE LIMITS"
  printf 'CPU Limit    : %s\n' "$(get_cpu_quota_info)"
  printf 'Memory Limit : %s\n' "$(get_memory_limit)"
  echo
  local throttle_raw
  throttle_raw=$(get_cpu_throttle_stats || true)
  if [[ "$throttle_raw" != "unavailable" ]]; then
    local nr_periods nr_throttled throttled_ns
    nr_periods=$(awk '{print $1}' <<< "$throttle_raw")
    nr_throttled=$(awk '{print $2}' <<< "$throttle_raw")
    throttled_ns=$(awk '{print $3}' <<< "$throttle_raw")

    printf 'CPU Periods      : %s\n' "${nr_periods:-0}"
    printf 'CPU Throttled    : %s\n' "${nr_throttled:-0}"
    if [[ "${throttled_ns:-0}" =~ ^[0-9]+$ ]] && (( throttled_ns > 0 )); then
      printf 'Throttled Time   : %ss\n' "$(awk "BEGIN {printf \"%.2f\",$throttled_ns/1000000000}")"
    else
      printf 'Throttled Time   : 0s\n'
    fi

    if [[ "$RUN_ONCE" == false && "$nr_throttled" =~ ^[0-9]+$ ]]; then
      printf 'Throttle Delta   : +%s (since last refresh)\n' "$(( nr_throttled - _PREV_CPU_THROTTLED ))"
      _PREV_CPU_THROTTLED="$nr_throttled"
    fi
  else
    echo "  CPU throttle stats unavailable (cgroup path not found)."
  fi

  print_section "CONTAINER RESOURCES (LIVE)"
  docker stats --no-stream \
    --format 'CPU={{.CPUPerc}}  Memory={{.MemUsage}} ({{.MemPerc}})  NetIO={{.NetIO}}  BlockIO={{.BlockIO}}  PIDs={{.PIDs}}' \
    "$CONTAINER" 2>&1 || true
  printf 'Threads    : %s\n' "$(get_container_thread_count)"

  print_section "WEBSOCKET CONNECTION (PORT $CONSOLE_WS_PORT)"
  check_websocket_state 2>&1 || true

  print_section "ALL CONTAINER TCP CONNECTIONS"
  show_all_container_connections 2>&1 || true

  print_section "NETWORK PATH"
  check_network_path 2>&1 || true

  print_section "TCP KEEPALIVE SETTINGS"
  show_tcp_keepalive 2>&1 || true

  print_section "CONTAINER DNS"
  show_container_dns 2>&1 || true

  print_section "DOCKER FILESYSTEM CAPACITY"
  df -h /var/lib/docker 2>&1 || true

  print_section "DOCKER FILESYSTEM INODES"
  df -i /var/lib/docker 2>&1 || true

  print_section "DOCKER OBJECT USAGE"
  docker system df 2>&1 || true

  print_section "HOST LOAD AND MEMORY"
  uptime 2>&1 || true
  echo
  free -h 2>&1 || true

  print_section "FILESYSTEM LATENCY"
  if command -v iostat >/dev/null 2>&1; then
    iostat -xz 1 1 2>&1 || true
  else
    echo "iostat unavailable (sysstat not installed)."
  fi

  print_section "ECS TASK STATE"
  if [[ -n "$ECS_CLUSTER" && -n "$ECS_TASK" ]] && command -v aws >/dev/null 2>&1; then
    aws ecs describe-tasks \
      ${aws_region_args[@]+"${aws_region_args[@]}"} \
      --cluster "$ECS_CLUSTER" \
      --tasks "$ECS_TASK" \
      --query 'tasks[0].{
        TaskArn:taskArn,
        TaskDefinition:taskDefinitionArn,
        Last:lastStatus,
        Desired:desiredStatus,
        Health:healthStatus,
        Connectivity:connectivity,
        ConnectivityAt:connectivityAt,
        StartedAt:startedAt,
        StopCode:stopCode,
        StoppedReason:stoppedReason,
        CPU:cpu,
        Memory:memory
      }' \
      --output table 2>&1 || true
  else
    echo "Skipped (provide --cluster and --task with AWS CLI access)."
  fi

  print_section "PRISMA CONSOLE CONNECTIVITY"
  if [[ -n "$PRISMA_CONSOLE_URL" ]]; then
    check_console_connectivity 2>&1 || echo "Console connectivity check failed."
  else
    echo "Skipped (provide --console-url)."
  fi

  print_section "KERNEL EVENTS — LAST 5 MINUTES"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -k --since '5 minutes ago' --no-pager 2>/dev/null \
      | grep -Ei 'oom|killed process|no space|overlay|docker|i/o error|throttl' \
      || echo "No matching kernel events."
  elif [[ -r /var/log/messages ]]; then
    tail -100 /var/log/messages 2>/dev/null \
      | grep -Ei 'oom|killed process|no space|docker' \
      || echo "No matching entries."
  else
    echo "journalctl and /var/log/messages unavailable."
  fi

  print_section "DOCKER DAEMON EVENTS — LAST 5 MINUTES"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u docker --since '5 minutes ago' --no-pager 2>/dev/null \
      | grep -Ei 'error|fail|no space|overlay|mount|timeout|throttl' \
      || echo "No matching Docker daemon events."
  else
    echo "journalctl unavailable."
  fi

  print_section "DEFENDER LOGS — LAST $LOG_SINCE (FILTERED)"
  docker logs --tail 50 --since "$LOG_SINCE" "$CONTAINER" 2>&1 \
    | grep -Ei 'erro|warn|fail|timeout|disconnect|closed|refused|denied|scan|registry|heartbeat|ping|ws\.' \
    || echo "No matching log entries."
  echo
  echo "--- Full tail (last 10 lines) ---"
  docker logs --tail 10 "$CONTAINER" 2>&1 || true

  print_section "HEALTH SUMMARY"
  set +e
  evaluate_health
  local result=$?
  set -e 2>/dev/null || true

  echo
  echo "=================================================================="
  [[ "$RUN_ONCE" == false ]] && echo "Press Ctrl+C to stop.  Refreshing every ${REFRESH_INTERVAL}s."
  [[ -n "$LOG_FILE" ]] && echo "Evidence log: $LOG_FILE"

  return "$result"
}

###############################################################################
# Main
###############################################################################

cleanup() {
  [[ "$RUN_ONCE" == false ]] && printf '\nHealth check stopped.\n'
  [[ -n "$LOG_FILE" ]] && printf 'Evidence saved to: %s\n' "$LOG_FILE"
}
trap cleanup EXIT INT TERM

run_snapshot() {
  if [[ -n "$LOG_FILE" ]]; then
    snapshot | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
  else
    snapshot
  fi
}

if [[ "$RUN_ONCE" == true ]]; then
  run_snapshot
  exit $?
fi

while true; do
  clear
  set +e
  run_snapshot
  set -e 2>/dev/null || true
  [[ -n "$LOG_FILE" ]] && printf '\n\n' >> "$LOG_FILE"
  sleep "$REFRESH_INTERVAL"
done
