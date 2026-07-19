#!/bin/bash
# docker-overlay-trace.sh
# Trace Nessus findings in Docker overlay2 back to source images
# 
# Usage: ./docker-overlay-trace.sh <overlay2-path> [options]
#        ./docker-overlay-trace.sh --batch <file-with-paths>
#
# Examples:
#   ./docker-overlay-trace.sh /var/lib/docker/overlay2/abc123/diff/usr/bin/mongod
#   ./docker-overlay-trace.sh /var/lib/docker/overlay2/abc123/diff/usr/bin/mongod --format json
#   ./docker-overlay-trace.sh /var/lib/docker/overlay2/abc123/diff/usr/lib/libssl.so --target openssl
#   ./docker-overlay-trace.sh --batch nessus-paths.txt --format markdown
#   echo "/var/lib/docker/overlay2/abc/diff/usr/bin/mongod" | ./docker-overlay-trace.sh --batch -

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

VERSION=2.1.0
DOCKER_ROOT="${DOCKER_ROOT:-/var/lib/docker}"
IMAGEDB="${DOCKER_ROOT}/image/overlay2/imagedb/content/sha256"
LAYERDB="${DOCKER_ROOT}/image/overlay2/layerdb/sha256"

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Disable colors if not a terminal
if [[ ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" DIM="" BOLD="" NC=""
fi

# Known software patterns - add more as needed
declare -A VERSION_PATTERNS=(
    ["mongod"]="MONGODB_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["mongo"]="MONGODB_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["mongos"]="MONGODB_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["node"]="NODE_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["python"]="PYTHON_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["python3"]="PYTHON_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["java"]="JAVA_VERSION=([0-9]+)"
    ["postgres"]="PG_VERSION=([0-9]+\.[0-9]+)"
    ["nginx"]="NGINX_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["redis"]="REDIS_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["openssl"]="OPENSSL_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["libssl"]="OPENSSL_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["httpd"]="HTTPD_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["tomcat"]="TOMCAT_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["elasticsearch"]="ELASTICSEARCH_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["kafka"]="KAFKA_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
    ["zookeeper"]="ZOOKEEPER_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
)

# CPE mappings for CVE lookup (product name -> CPE vendor:product)
declare -A CPE_MAPPINGS=(
    ["mongod"]="mongodb:mongodb"
    ["mongo"]="mongodb:mongodb"
    ["node"]="nodejs:node.js"
    ["python"]="python:python"
    ["python3"]="python:python"
    ["java"]="oracle:jdk"
    ["postgres"]="postgresql:postgresql"
    ["nginx"]="nginx:nginx"
    ["redis"]="redis:redis"
    ["openssl"]="openssl:openssl"
    ["libssl"]="openssl:openssl"
    ["httpd"]="apache:http_server"
    ["tomcat"]="apache:tomcat"
    ["elasticsearch"]="elastic:elasticsearch"
)

# ============================================================================
# Quick reference / list patterns
# ============================================================================

list_patterns() {
    echo -e "${BOLD}Supported Software Patterns${NC}"
    echo ""
    echo -e "${CYAN}Binary${NC}          ${CYAN}Version Pattern${NC}                              ${CYAN}CPE (for CVE lookup)${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    for key in $(echo "${!VERSION_PATTERNS[@]}" | tr ' ' '\n' | sort); do
        local cpe="${CPE_MAPPINGS[$key]:-N/A}"
        printf "%-15s %-45s %s\n" "$key" "${VERSION_PATTERNS[$key]}" "$cpe"
    done
    echo ""
    echo -e "${DIM}Use --pattern to specify custom patterns at runtime${NC}"
    exit 0
}

# ============================================================================
# Argument parsing
# ============================================================================

OVERLAY_PATH=""
OUTPUT_FORMAT="human"  # human | json | markdown
TARGET_NAME=""         # Auto-detect from path if not specified
CUSTOM_PATTERN=""      # Override version pattern
VERBOSE=false
RUNNING_ONLY=false
BATCH_FILE=""          # File containing paths (one per line)
CHECK_ECR=false        # Check ECR for newer tags
ECR_REGION="${AWS_DEFAULT_REGION:-}"
LOOKUP_CVE=false       # Query NVD for CVEs
CVE_API_KEY="${NVD_API_KEY:-}"  # Optional NVD API key for faster lookups
QUIET_MODE=false       # Minimal output

usage() {
    cat <<EOF
${BOLD}docker-overlay-trace${NC} v${VERSION}
${DIM}Trace Nessus findings in Docker overlay2 back to source images${NC}

${YELLOW}USAGE:${NC}
    $0 <overlay2-path> [OPTIONS]
    $0 --batch <file> [OPTIONS]

${YELLOW}ARGUMENTS:${NC}
    ${GREEN}<overlay2-path>${NC}    Full path from Nessus finding (required unless --batch)

${YELLOW}OPTIONS:${NC}
    ${CYAN}-t, --target NAME${NC}       Binary name to search for (auto-detected if omitted)
    ${CYAN}-p, --pattern REGEX${NC}     Custom version extraction pattern
    ${CYAN}-f, --format FORMAT${NC}     Output format: human, json, markdown (default: human)
    ${CYAN}-r, --running-only${NC}      Only report if containers are actively running
    ${CYAN}-v, --verbose${NC}           Show detailed layer tracing
    ${CYAN}-h, --help${NC}              Show this help

${YELLOW}BATCH MODE:${NC}
    ${CYAN}-b, --batch FILE${NC}        Process multiple paths from file (one per line)
                            Use '-' to read from stdin

${YELLOW}INTEGRATIONS:${NC}
    ${CYAN}--ecr${NC}                   Check ECR for newer image tags
    ${CYAN}--ecr-region REGION${NC}     AWS region for ECR (default: \$AWS_DEFAULT_REGION)
    ${CYAN}--cve${NC}                   Look up known CVEs for detected version
    ${CYAN}--nvd-api-key KEY${NC}       NVD API key for faster CVE lookups

${YELLOW}UTILITIES:${NC}
    ${CYAN}--list-patterns${NC}         Show all known software patterns
    ${CYAN}--no-color${NC}              Disable colored output
    ${CYAN}--quiet${NC}                 Minimal output (just status line per image)

${YELLOW}EXAMPLES:${NC}
    ${DIM}# Basic MongoDB trace${NC}
    $0 /var/lib/docker/overlay2/abc123/diff/usr/bin/mongod

    ${DIM}# JSON output for automation${NC}
    $0 /var/lib/docker/overlay2/abc123/diff/usr/bin/mongod -f json

    ${DIM}# Full analysis with ECR and CVE lookup${NC}
    $0 /var/lib/docker/overlay2/abc123/diff/usr/bin/mongod --ecr --cve

    ${DIM}# Batch process multiple Nessus findings${NC}
    $0 --batch nessus-paths.txt -f markdown > report.md

    ${DIM}# Pipe paths from another command${NC}
    grep 'overlay2' nessus-report.csv | cut -d, -f3 | $0 --batch -

${YELLOW}ENVIRONMENT:${NC}
    DOCKER_ROOT          Override Docker root (default: /var/lib/docker)
    AWS_DEFAULT_REGION   Default AWS region for ECR
    NVD_API_KEY          NVD API key for CVE lookups

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET_NAME="$2"
            shift 2
            ;;
        -p|--pattern)
            CUSTOM_PATTERN="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -r|--running-only)
            RUNNING_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -b|--batch)
            BATCH_FILE="$2"
            shift 2
            ;;
        --ecr)
            CHECK_ECR=true
            shift
            ;;
        --ecr-region)
            ECR_REGION="$2"
            shift 2
            ;;
        --cve)
            LOOKUP_CVE=true
            shift
            ;;
        --nvd-api-key)
            CVE_API_KEY="$2"
            shift 2
            ;;
        --list-patterns)
            list_patterns
            ;;
        --no-color)
            RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" DIM="" BOLD="" NC=""
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "ERROR: Unknown option $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$OVERLAY_PATH" ]]; then
                OVERLAY_PATH="$1"
            else
                echo "ERROR: Unexpected argument $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$OVERLAY_PATH" ]] && [[ -z "$BATCH_FILE" ]]; then
    echo "ERROR: overlay2 path or --batch file required" >&2
    echo "Run with --help for usage" >&2
    exit 1
fi

# ============================================================================
# Core functions
# ============================================================================

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
}

# Extract cache-id from overlay2 path
extract_cache_id() {
    local path="$1"
    echo "$path" | grep -oP 'overlay2/\K[a-f0-9]{64}' | head -1
}

# Find diff-id from cache-id via layerdb
cache_to_diff_id() {
    local cache_id="$1"
    
    # Search layerdb for the cache-id and get the diff file
    for chain_dir in "${LAYERDB}"/*; do
        if [[ -d "$chain_dir" ]]; then
            local cache_file="${chain_dir}/cache-id"
            if [[ -f "$cache_file" ]] && grep -q "$cache_id" "$cache_file" 2>/dev/null; then
                local diff_file="${chain_dir}/diff"
                if [[ -f "$diff_file" ]]; then
                    cat "$diff_file"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

# Find all images containing a specific diff-id
find_images_with_diff() {
    local diff_id="$1"
    local short_diff="${diff_id#sha256:}"
    
    # Search all image manifests for this diff-id
    grep -l "$short_diff" "${IMAGEDB}"/* 2>/dev/null | while read -r manifest; do
        basename "$manifest"
    done
}

# Extract version from image history
extract_version() {
    local image_sha="$1"
    local pattern="$2"
    local manifest="${IMAGEDB}/${image_sha}"
    
    if [[ -f "$manifest" ]]; then
        grep -oP "$pattern" "$manifest" | head -1 | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)?'
    fi
}

# Get image tags from docker
get_image_tags() {
    local image_sha="$1"
    docker image ls --format '{{.Repository}}:{{.Tag}}' --filter "id=sha256:${image_sha}" 2>/dev/null | head -5
}

# Get image labels
get_image_labels() {
    local image_sha="$1"
    docker inspect "sha256:${image_sha}" --format '{{json .Config.Labels}}' 2>/dev/null
}

# Get image creation date
get_image_created() {
    local image_sha="$1"
    docker inspect "sha256:${image_sha}" --format '{{.Created}}' 2>/dev/null
}

# Check if any container is using this image
get_running_containers() {
    local image_sha="$1"
    docker ps --filter "ancestor=sha256:${image_sha}" --format '{{.ID}}\t{{.Names}}\t{{.Status}}' 2>/dev/null
}

get_all_containers() {
    local image_sha="$1"
    docker ps -a --filter "ancestor=sha256:${image_sha}" --format '{{.ID}}\t{{.Names}}\t{{.Status}}' 2>/dev/null
}

# ============================================================================
# ECR Integration
# ============================================================================

check_ecr_for_updates() {
    local image_tag="$1"
    local repo_name=""
    local current_tag=""
    
    # Parse repository and tag from image reference
    if [[ "$image_tag" =~ ^([^:]+):(.+)$ ]]; then
        repo_name="${BASH_REMATCH[1]}"
        current_tag="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    
    # Extract just the repo name if it includes registry
    if [[ "$repo_name" =~ \.ecr\.[^/]+/(.+)$ ]]; then
        repo_name="${BASH_REMATCH[1]}"
    fi
    
    if ! command -v aws &>/dev/null; then
        log "AWS CLI not available, skipping ECR check"
        return 1
    fi
    
    if [[ -z "$ECR_REGION" ]]; then
        log "ECR_REGION not set, use --ecr-region or set AWS_DEFAULT_REGION"
        return 1
    fi
    
    log "Checking ECR for repo: $repo_name in region: $ECR_REGION"
    
    # Get latest tags from ECR
    local tags
    tags=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$ECR_REGION" \
        --query 'sort_by(imageDetails,&imagePushedAt)[-5:].imageTags[0]' \
        --output text 2>/dev/null) || return 1
    
    echo "$tags"
}

# ============================================================================
# CVE Lookup (NVD)
# ============================================================================

lookup_cves() {
    local product="$1"
    local version="$2"
    
    if ! command -v curl &>/dev/null; then
        log "curl not available, skipping CVE lookup"
        return 1
    fi
    
    local cpe_string="${CPE_MAPPINGS[$product]:-}"
    if [[ -z "$cpe_string" ]]; then
        log "No CPE mapping for $product"
        return 1
    fi
    
    local vendor product_name
    vendor="${cpe_string%%:*}"
    product_name="${cpe_string##*:}"
    
    # Build CPE 2.3 match string
    local cpe_match="cpe:2.3:a:${vendor}:${product_name}:${version}:*:*:*:*:*:*:*"
    
    log "Querying NVD for CPE: $cpe_match"
    
    local api_url="https://services.nvd.nist.gov/rest/json/cves/2.0?cpeName=${cpe_match}"
    local headers=()
    
    if [[ -n "$CVE_API_KEY" ]]; then
        headers+=(-H "apiKey: $CVE_API_KEY")
    fi
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 "${headers[@]}" "$api_url" 2>/dev/null) || return 1
    
    # Parse CVE IDs and scores
    if command -v jq &>/dev/null; then
        echo "$response" | jq -r '.vulnerabilities[]? | 
            "\(.cve.id)\t\(.cve.metrics.cvssMetricV31[0]?.cvssData.baseScore // .cve.metrics.cvssMetricV2[0]?.cvssData.baseScore // "N/A")\t\(.cve.metrics.cvssMetricV31[0]?.cvssData.baseSeverity // "N/A")"' 2>/dev/null
    else
        # Fallback: basic grep for CVE IDs
        echo "$response" | grep -oP 'CVE-[0-9]+-[0-9]+' | sort -u
    fi
}

# Get severity color
severity_color() {
    local severity="$1"
    case "${severity^^}" in
        CRITICAL) echo "$RED" ;;
        HIGH)     echo "$RED" ;;
        MEDIUM)   echo "$YELLOW" ;;
        LOW)      echo "$GREEN" ;;
        *)        echo "$NC" ;;
    esac
}

# ============================================================================
# Pretty printing helpers
# ============================================================================

print_header() {
    local title="$1"
    local width=60
    echo ""
    echo -e "${BLUE}╔$(printf '═%.0s' $(seq 1 $((width-2))))╗${NC}"
    printf "${BLUE}║${NC} ${BOLD}%-$((width-4))s${NC} ${BLUE}║${NC}\n" "$title"
    echo -e "${BLUE}╚$(printf '═%.0s' $(seq 1 $((width-2))))╝${NC}"
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}┌─ ${BOLD}$title${NC}"
}

print_field() {
    local label="$1"
    local value="$2"
    local color="${3:-$NC}"
    printf "${DIM}│${NC}  %-14s ${color}%s${NC}\n" "$label:" "$value"
}

print_separator() {
    echo -e "${DIM}├$(printf '─%.0s' $(seq 1 50))${NC}"
}

print_end_section() {
    echo -e "${DIM}└$(printf '─%.0s' $(seq 1 50))${NC}"
}

print_status_badge() {
    local status="$1"
    case "$status" in
        running)
            echo -e "${RED}${BOLD}● RUNNING${NC}"
            ;;
        stopped)
            echo -e "${YELLOW}○ STOPPED${NC}"
            ;;
        cached)
            echo -e "${GREEN}◌ CACHED ONLY${NC}"
            ;;
    esac
}

# ============================================================================
# Main analysis
# ============================================================================

analyze() {
    # Auto-detect target name from path if not specified
    if [[ -z "$TARGET_NAME" ]]; then
        TARGET_NAME=$(basename "$OVERLAY_PATH")
        log "Auto-detected target: $TARGET_NAME"
    fi
    
    # Select version pattern
    local version_pattern="$CUSTOM_PATTERN"
    if [[ -z "$version_pattern" ]]; then
        version_pattern="${VERSION_PATTERNS[$TARGET_NAME]:-}"
        if [[ -z "$version_pattern" ]]; then
            version_pattern="${TARGET_NAME^^}_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"
            log "No known pattern for $TARGET_NAME, using generic: $version_pattern"
        fi
    fi
    
    # Extract cache-id
    local cache_id
    cache_id=$(extract_cache_id "$OVERLAY_PATH")
    if [[ -z "$cache_id" ]]; then
        error "Could not extract cache-id from path: $OVERLAY_PATH"
        exit 1
    fi
    log "Cache ID: $cache_id"
    
    # Results collection
    declare -A results
    results[path]="$OVERLAY_PATH"
    results[target]="$TARGET_NAME"
    results[cache_id]="$cache_id"
    
    # Find diff-id
    local diff_id
    diff_id=$(cache_to_diff_id "$cache_id") || true
    if [[ -n "$diff_id" ]]; then
        results[diff_id]="$diff_id"
        log "Diff ID: $diff_id"
    fi
    
    # Find images - try multiple methods
    local images=()
    
    # Method 1: Via diff-id lookup
    if [[ -n "${diff_id:-}" ]]; then
        while IFS= read -r img; do
            [[ -n "$img" ]] && images+=("$img")
        done < <(find_images_with_diff "$diff_id")
    fi
    
    # Method 2: Direct grep for cache-id in imagedb (fallback)
    if [[ ${#images[@]} -eq 0 ]]; then
        log "Trying direct search in imagedb..."
        while IFS= read -r manifest; do
            [[ -n "$manifest" ]] && images+=("$(basename "$manifest")")
        done < <(grep -rl "$cache_id" "${IMAGEDB}" 2>/dev/null || true)
    fi
    
    # Method 3: Search all layer content for the diff pattern
    if [[ ${#images[@]} -eq 0 ]] && [[ -n "${diff_id:-}" ]]; then
        local short_diff="${diff_id#sha256:}"
        log "Searching for diff pattern: $short_diff"
        while IFS= read -r manifest; do
            if [[ -n "$manifest" ]]; then
                images+=("$(basename "$manifest")")
            fi
        done < <(grep -l "$short_diff" "${IMAGEDB}"/* 2>/dev/null || true)
    fi
    
    results[image_count]="${#images[@]}"
    
    # Analyze each image
    declare -a image_details=()
    for image_sha in "${images[@]}"; do
        local tags version created running_containers all_containers labels
        
        tags=$(get_image_tags "$image_sha")
        version=$(extract_version "$image_sha" "$version_pattern")
        created=$(get_image_created "$image_sha")
        running_containers=$(get_running_containers "$image_sha")
        all_containers=$(get_all_containers "$image_sha")
        labels=$(get_image_labels "$image_sha")
        
        # Skip if running-only mode and no running containers
        if [[ "$RUNNING_ONLY" == true ]] && [[ -z "$running_containers" ]]; then
            continue
        fi
        
        image_details+=("$(cat <<EOF
{
  "sha": "${image_sha}",
  "tags": "${tags}",
  "version": "${version}",
  "created": "${created}",
  "running_containers": "${running_containers}",
  "all_containers": "${all_containers}",
  "labels": ${labels:-"{}"}
}
EOF
)")
    done
    
    # Output
    output_results "${results[@]}" "${image_details[@]}"
}

# ============================================================================
# Output formatting
# ============================================================================

output_results() {
    case "$OUTPUT_FORMAT" in
        json)
            output_json
            ;;
        markdown)
            output_markdown
            ;;
        *)
            if [[ "$QUIET_MODE" == true ]]; then
                output_quiet
            else
                output_human
            fi
            ;;
    esac
}

output_quiet() {
    # One-line summary per image
    if [[ ${#image_details[@]} -eq 0 ]]; then
        echo -e "${YELLOW}NO_IMAGE${NC}\t$OVERLAY_PATH"
        return
    fi
    
    for detail in "${image_details[@]}"; do
        local sha tags version running status_icon status_text
        sha=$(echo "$detail" | grep -oP '"sha":\s*"\K[^"]+')
        tags=$(echo "$detail" | grep -oP '"tags":\s*"\K[^"]+')
        version=$(echo "$detail" | grep -oP '"version":\s*"\K[^"]*')
        running=$(echo "$detail" | grep -oP '"running_containers":\s*"\K[^"]*')
        
        if [[ -n "$running" ]]; then
            status_icon="${RED}●${NC}"
            status_text="RUNNING"
        else
            status_icon="${GREEN}○${NC}"
            status_text="CACHED"
        fi
        
        local display_tag="${tags:-sha256:${sha:0:12}}"
        local display_ver="${version:+v$version}"
        
        echo -e "${status_icon} ${status_text}\t${display_tag}\t${display_ver:-?}\t${TARGET_NAME}"
    done
}

output_human() {
    print_header "Docker Overlay2 Vulnerability Trace"
    
    print_section "Input Analysis"
    print_field "Path" "$OVERLAY_PATH"
    print_field "Target" "$TARGET_NAME"
    print_field "Cache ID" "${results[cache_id]:0:16}..."
    [[ -n "${results[diff_id]:-}" ]] && print_field "Diff ID" "${results[diff_id]:0:20}..."
    print_end_section
    
    if [[ ${#image_details[@]} -eq 0 ]]; then
        print_section "Results"
        echo -e "${DIM}│${NC}  ${YELLOW}No matching images found${NC}"
        echo -e "${DIM}│${NC}"
        echo -e "${DIM}│${NC}  ${DIM}Possible reasons:${NC}"
        echo -e "${DIM}│${NC}    • Image was pruned but layers remain orphaned"
        echo -e "${DIM}│${NC}    • Layer is from a base image not directly tagged"
        echo -e "${DIM}│${NC}"
        echo -e "${DIM}│${NC}  ${GREEN}Try: docker system prune -a${NC}"
        print_end_section
        return
    fi
    
    print_section "Found ${#image_details[@]} Image(s)"
    
    for detail in "${image_details[@]}"; do
        local sha tags version created running all labels
        sha=$(echo "$detail" | grep -oP '"sha":\s*"\K[^"]+')
        tags=$(echo "$detail" | grep -oP '"tags":\s*"\K[^"]+')
        version=$(echo "$detail" | grep -oP '"version":\s*"\K[^"]*')
        created=$(echo "$detail" | grep -oP '"created":\s*"\K[^"]+')
        running=$(echo "$detail" | grep -oP '"running_containers":\s*"\K[^"]*')
        all=$(echo "$detail" | grep -oP '"all_containers":\s*"\K[^"]*')
        
        echo ""
        echo -e "${DIM}│${NC}  ${MAGENTA}${BOLD}sha256:${sha:0:12}${NC}"
        [[ -n "$tags" ]] && print_field "Tags" "$tags" "$CYAN"
        [[ -n "$version" ]] && print_field "Version" "$TARGET_NAME $version" "$YELLOW"
        [[ -n "$created" ]] && print_field "Created" "${created:0:10}"
        
        # Status with badge
        if [[ -n "$running" ]]; then
            echo -e "${DIM}│${NC}  Status:        $(print_status_badge running)"
            echo -e "${DIM}│${NC}  ${DIM}Containers:${NC}"
            echo "$running" | while IFS=$'\t' read -r cid cname cstatus; do
                echo -e "${DIM}│${NC}    ${RED}►${NC} $cid ${DIM}($cname)${NC}"
            done
        elif [[ -n "$all" ]]; then
            echo -e "${DIM}│${NC}  Status:        $(print_status_badge stopped)"
        else
            echo -e "${DIM}│${NC}  Status:        $(print_status_badge cached)"
        fi
        
        # ECR check
        if [[ "$CHECK_ECR" == true ]] && [[ -n "$tags" ]]; then
            local ecr_tags
            ecr_tags=$(check_ecr_for_updates "$tags" 2>/dev/null) || true
            if [[ -n "$ecr_tags" ]]; then
                echo -e "${DIM}│${NC}"
                echo -e "${DIM}│${NC}  ${CYAN}ECR Latest Tags:${NC}"
                echo "$ecr_tags" | head -5 | while read -r tag; do
                    echo -e "${DIM}│${NC}    ${GREEN}→${NC} $tag"
                done
            fi
        fi
        
        # CVE lookup
        if [[ "$LOOKUP_CVE" == true ]] && [[ -n "$version" ]]; then
            local cves
            cves=$(lookup_cves "$TARGET_NAME" "$version" 2>/dev/null) || true
            if [[ -n "$cves" ]]; then
                echo -e "${DIM}│${NC}"
                echo -e "${DIM}│${NC}  ${RED}Known CVEs:${NC}"
                echo "$cves" | head -10 | while IFS=$'\t' read -r cve_id score severity; do
                    local sev_color
                    sev_color=$(severity_color "$severity")
                    if [[ -n "$score" ]] && [[ "$score" != "N/A" ]]; then
                        echo -e "${DIM}│${NC}    ${sev_color}●${NC} $cve_id ${DIM}(CVSS: $score - $severity)${NC}"
                    else
                        echo -e "${DIM}│${NC}    ${YELLOW}●${NC} $cve_id"
                    fi
                done
            fi
        fi
        
        print_separator
    done
    
    # Remediation section
    print_section "Remediation"
    
    local has_running=false
    for detail in "${image_details[@]}"; do
        if echo "$detail" | grep -q '"running_containers":\s*"[^"]'; then
            has_running=true
            break
        fi
    done
    
    if [[ "$has_running" == true ]]; then
        echo -e "${DIM}│${NC}  ${RED}${BOLD}⚠ Active containers found${NC}"
        echo -e "${DIM}│${NC}"
        echo -e "${DIM}│${NC}  ${WHITE}Action Required:${NC}"
        echo -e "${DIM}│${NC}    1. Identify patched image version from vendor"
        echo -e "${DIM}│${NC}    2. Update deployment (ECS task def, docker-compose, k8s)"
        echo -e "${DIM}│${NC}    3. Roll out new containers"
        echo -e "${DIM}│${NC}    4. Prune old images after verification"
    else
        echo -e "${DIM}│${NC}  ${GREEN}${BOLD}✓ No running containers${NC}"
        echo -e "${DIM}│${NC}"
        echo -e "${DIM}│${NC}  ${WHITE}Quick Fix:${NC}"
        echo -e "${DIM}│${NC}    ${CYAN}docker image prune -a${NC}"
        echo -e "${DIM}│${NC}"
        echo -e "${DIM}│${NC}  ${DIM}Nessus finding should clear after prune + rescan${NC}"
    fi
    print_end_section
    echo ""
}

output_json() {
    local images_json=""
    for detail in "${image_details[@]}"; do
        [[ -n "$images_json" ]] && images_json+=","
        
        # Add ECR and CVE data if enabled
        local ecr_tags_json="[]"
        local cves_json="[]"
        
        local tags version
        tags=$(echo "$detail" | grep -oP '"tags":\s*"\K[^"]+')
        version=$(echo "$detail" | grep -oP '"version":\s*"\K[^"]*')
        
        if [[ "$CHECK_ECR" == true ]] && [[ -n "$tags" ]]; then
            local ecr_tags
            ecr_tags=$(check_ecr_for_updates "$tags" 2>/dev/null) || true
            if [[ -n "$ecr_tags" ]]; then
                ecr_tags_json=$(echo "$ecr_tags" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
            fi
        fi
        
        if [[ "$LOOKUP_CVE" == true ]] && [[ -n "$version" ]]; then
            local cves
            cves=$(lookup_cves "$TARGET_NAME" "$version" 2>/dev/null) || true
            if [[ -n "$cves" ]] && command -v jq &>/dev/null; then
                cves_json=$(echo "$cves" | head -20 | while IFS=$'\t' read -r cve_id score severity; do
                    echo "{\"id\":\"$cve_id\",\"cvss\":\"$score\",\"severity\":\"$severity\"}"
                done | jq -s '.' 2>/dev/null || echo "[]")
            fi
        fi
        
        # Inject ECR and CVE data into detail
        detail=$(echo "$detail" | sed "s/}$/,\"ecr_tags\":$ecr_tags_json,\"cves\":$cves_json}/")
        images_json+="$detail"
    done
    
    cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "version": "$VERSION",
  "path": "$OVERLAY_PATH",
  "target": "$TARGET_NAME",
  "cache_id": "${results[cache_id]}",
  "diff_id": "${results[diff_id]:-}",
  "images": [$images_json],
  "has_running_containers": $(echo "${image_details[*]}" | grep -q '"running_containers":\s*"[^"]' && echo true || echo false),
  "remediation": $(echo "${image_details[*]}" | grep -q '"running_containers":\s*"[^"]' && echo '"upgrade_required"' || echo '"prune_safe"')
}
EOF
}

output_markdown() {
    echo "# Docker Overlay2 Trace Report"
    echo ""
    echo "_Generated: $(date '+%Y-%m-%d %H:%M:%S')_"
    echo ""
    echo "## Summary"
    echo ""
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Path | \`${OVERLAY_PATH:0:60}...\` |"
    echo "| Target | \`$TARGET_NAME\` |"
    echo "| Cache ID | \`${results[cache_id]:0:16}...\` |"
    echo ""
    
    if [[ ${#image_details[@]} -gt 0 ]]; then
        echo "## Identified Images"
        echo ""
        
        local has_running=false
        
        for detail in "${image_details[@]}"; do
            local sha tags version created running all
            sha=$(echo "$detail" | grep -oP '"sha":\s*"\K[^"]+')
            tags=$(echo "$detail" | grep -oP '"tags":\s*"\K[^"]+')
            version=$(echo "$detail" | grep -oP '"version":\s*"\K[^"]*')
            created=$(echo "$detail" | grep -oP '"created":\s*"\K[^"]+')
            running=$(echo "$detail" | grep -oP '"running_containers":\s*"\K[^"]*')
            
            echo "### \`sha256:${sha:0:12}\`"
            echo ""
            [[ -n "$tags" ]] && echo "- **Tags:** \`$tags\`"
            [[ -n "$version" ]] && echo "- **Version:** $TARGET_NAME \`$version\`"
            [[ -n "$created" ]] && echo "- **Created:** ${created:0:10}"
            
            if [[ -n "$running" ]]; then
                has_running=true
                echo "- **Status:** 🔴 **RUNNING**"
            else
                echo "- **Status:** 🟢 Cached only"
            fi
            
            # CVE lookup
            if [[ "$LOOKUP_CVE" == true ]] && [[ -n "$version" ]]; then
                local cves
                cves=$(lookup_cves "$TARGET_NAME" "$version" 2>/dev/null) || true
                if [[ -n "$cves" ]]; then
                    echo ""
                    echo "#### Known CVEs"
                    echo ""
                    echo "| CVE ID | CVSS | Severity |"
                    echo "|--------|------|----------|"
                    echo "$cves" | head -10 | while IFS=$'\t' read -r cve_id score severity; do
                        echo "| $cve_id | $score | $severity |"
                    done
                fi
            fi
            
            # ECR check
            if [[ "$CHECK_ECR" == true ]] && [[ -n "$tags" ]]; then
                local ecr_tags
                ecr_tags=$(check_ecr_for_updates "$tags" 2>/dev/null) || true
                if [[ -n "$ecr_tags" ]]; then
                    echo ""
                    echo "#### Available ECR Tags"
                    echo ""
                    echo "$ecr_tags" | head -5 | while read -r tag; do
                        echo "- \`$tag\`"
                    done
                fi
            fi
            
            echo ""
        done
        
        echo "## Remediation"
        echo ""
        if [[ "$has_running" == true ]]; then
            echo "> ⚠️ **Active containers found - upgrade required**"
            echo ""
            echo "1. Identify patched image version from vendor"
            echo "2. Update deployment configuration"
            echo "3. Roll out new containers"
            echo "4. Verify and prune old images"
        else
            echo "> ✅ **No running containers - safe to prune**"
            echo ""
            echo "\`\`\`bash"
            echo "docker image prune -a"
            echo "\`\`\`"
        fi
    else
        echo "## Results"
        echo ""
        echo "> ⚠️ No matching images found"
        echo ""
        echo "Possible causes:"
        echo "- Image was pruned but orphan layers remain"
        echo "- Layer belongs to an untagged base image"
    fi
}

# ============================================================================
# Entry point
# ============================================================================

# Verify we can access docker paths
if [[ ! -d "$IMAGEDB" ]]; then
    error "Cannot access $IMAGEDB"
    error "Run with sudo or ensure proper permissions"
    exit 1
fi

# Batch mode handling
if [[ -n "$BATCH_FILE" ]]; then
    print_header "Batch Processing Mode"
    
    declare -a all_results=()
    path_count=0
    
    # Read paths from file or stdin
    while IFS= read -r path || [[ -n "$path" ]]; do
        # Skip empty lines and comments
        [[ -z "$path" ]] && continue
        [[ "$path" =~ ^# ]] && continue
        
        ((path_count++))
        echo -e "${CYAN}Processing [$path_count]:${NC} ${DIM}$path${NC}"
        
        OVERLAY_PATH="$path"
        TARGET_NAME=""  # Reset for auto-detection
        
        # Run analysis (capture output for batch summary)
        analyze 2>/dev/null || true
        
    done < <(if [[ "$BATCH_FILE" == "-" ]]; then cat; else cat "$BATCH_FILE"; fi)
    
    echo ""
    echo -e "${GREEN}Processed $path_count path(s)${NC}"
    exit 0
fi

# Single path mode
analyze
