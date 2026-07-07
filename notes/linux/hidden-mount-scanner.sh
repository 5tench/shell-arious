#!binbash
#===============================================================================
#
#   ██╗  ██╗██╗██████╗ ██████╗ ███████╗███╗   ██╗    ███╗   ███╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
#   ██║  ██║██║██╔══██╗██╔══██╗██╔════╝████╗  ██║    ████╗ ████║██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝
#   ███████║██║██║  ██║██║  ██║█████╗  ██╔██╗ ██║    ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║   ██║   
#   ██╔══██║██║██║  ██║██║  ██║██╔══╝  ██║╚██╗██║    ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║   ██║   
#   ██║  ██║██║██████╔╝██████╔╝███████╗██║ ╚████║    ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║   ██║   
#   ╚═╝  ╚═╝╚═╝╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝    ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   
#                                                                                                     
#   ███████╗ ██████╗ █████╗ ███╗   ██╗███╗   ██╗███████╗██████╗                                      
#   ██╔════╝██╔════╝██╔══██╗████╗  ██║████╗  ██║██╔════╝██╔══██╗                                     
#   ███████╗██║     ███████║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝                                     
#   ╚════██║██║     ██╔══██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗                                     
#   ███████║╚██████╗██║  ██║██║ ╚████║██║ ╚████║███████╗██║  ██║                                     
#   ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝                                     
#
#===============================================================================
# Hidden Mount Scanner
# Version 1.0.0
# Author Your Name
# License MIT
# Repository httpsgithub.comyourusernamehidden-mount-scanner
#===============================================================================
#
# DESCRIPTION
#   Discovers hidden data lurking underneath mount points on Linux systems.
#   When a filesystem is mounted over a directory, any existing files become
#   invisible but continue consuming disk space. This tool reveals them.
#
# USE CASES
#   - Troubleshoot df vs du discrepancies
#   - Find orphaned data after NFSstorage migrations
#   - Audit servers for hiddenuntracked data
#   - Fleet-wide scanning for storage anomalies
#   - Security audits for hidden files
#
# HOW IT WORKS
#   Uses bind mounts to create an alternate view of the root filesystem,
#   bypassing the normal mount table to reveal data hidden underneath
#   mount points.
#
# SAFETY
#   - READ-ONLY by default (no modifications)
#   - Bind mounts are temporary and auto-cleaned
#   - No files are deleted or modified
#
# REQUIREMENTS
#   - Linux with bash 4.0+
#   - Rootsudo privileges
#   - Standard utilities mount, findmnt, du, df, find
#
# EXAMPLES
#   sudo .hidden-mount-scanner.sh                    # Scan all mount points
#   sudo .hidden-mount-scanner.sh -t data          # Scan specific mount
#   sudo .hidden-mount-scanner.sh -f json           # JSON output
#   sudo .hidden-mount-scanner.sh -d                # Deep scan (slower)
#   sudo .hidden-mount-scanner.sh -q                # Quick scan (size only)
#
#===============================================================================

set -o pipefail
set -o nounset

# Script metadata
readonly VERSION=1.0.0
readonly SCRIPT_NAME=$(basename $0)
readonly SCRIPT_DIR=$(dirname $(readlink -f $0))

# Default configuration
BIND_MOUNT_BASE=tmp.hidden_mount_scanner_$$
OUTPUT_FORMAT=text      # text, json, csv
OUTPUT_FILE=
TARGET_MOUNT=           # Empty = scan all
SCAN_DEPTH=standard     # quick, standard, deep
MIN_SIZE_KB=4             # Ignore directories = 4KB (empty dirs)
VERBOSE=false
QUIET=false
NO_COLOR=false
CLEANUP_DONE=false

# Color codes (disabled with --no-color or non-terminal output)
setup_colors() {
    if [[ $NO_COLOR == true ]]  [[ ! -t 1 ]]; then
        RED= GREEN= YELLOW= BLUE= CYAN= BOLD= RESET=
    else
        RED='033[0;31m'
        GREEN='033[0;32m'
        YELLOW='033[0;33m'
        BLUE='033[0;34m'
        CYAN='033[0;36m'
        BOLD='033[1m'
        RESET='033[0m'
    fi
}

#===============================================================================
# Usage and Help
#===============================================================================
show_help() {
    cat  EOF
${BOLD}HIDDEN MOUNT SCANNER${RESET} v${VERSION}

Discovers hidden data underneath mount points on Linux systems.

${BOLD}USAGE${RESET}
    sudo $SCRIPT_NAME [OPTIONS]

${BOLD}OPTIONS${RESET}
    -t, --target PATH     Scan specific mount point only
    -f, --format FORMAT   Output format text (default), json, csv
    -o, --output FILE     Write output to file (in addition to stdout)
    -d, --deep            Deep scan file counts, oldestnewest files
    -q, --quick           Quick scan sizes only, skip file details
    -m, --min-size KB     Minimum size to report (default 4 KB)
    -v, --verbose         Verbose output with debug info
    --no-color            Disable colored output
    -h, --help            Show this help message
    -V, --version         Show version information

${BOLD}EXAMPLES${RESET}
    # Scan all mount points
    sudo $SCRIPT_NAME

    # Scan only data mount point
    sudo $SCRIPT_NAME -t data

    # Deep scan with JSON output to file
    sudo $SCRIPT_NAME -d -f json -o report.json

    # Quick fleet scan (minimal output)
    sudo $SCRIPT_NAME -q --no-color

${BOLD}EXIT CODES${RESET}
    0   Success, no hidden data found
    1   Success, hidden data found
    2   Error (permissions, invalid options, etc.)

${BOLD}BACKGROUND${RESET}
    When a filesystem is mounted over a directory (e.g., NFS over data),
    any files that existed in that directory become hidden - they still
    consume disk space but are inaccessible via normal paths.

    This commonly happens during storage migrations when data is copied
    to new storage but never deleted from the original location.

${BOLD}REFERENCES${RESET}
    - httpswww.baeldung.comlinuxbind-mounts
    - httpsserverfault.comquestions275206disk-full-du-tells-different

${BOLD}AUTHOR${RESET}
    Your Name your.email@example.com
    httpsgithub.comyourusernamehidden-mount-scanner

EOF
    exit 0
}

show_version() {
    echo $SCRIPT_NAME version $VERSION
    exit 0
}

#===============================================================================
# Logging Functions
#===============================================================================
log_info() {
    [[ $QUIET == true ]] && return
    echo -e ${GREEN}[INFO]${RESET} $1
}

log_warn() {
    echo -e ${YELLOW}[WARN]${RESET} $1 &2
}

log_error() {
    echo -e ${RED}[ERROR]${RESET} $1 &2
}

log_debug() {
    [[ $VERBOSE == true ]] && echo -e ${CYAN}[DEBUG]${RESET} $1
}

log_finding() {
    echo -e ${RED}[FOUND]${RESET} $1
}

#===============================================================================
# Utility Functions
#===============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error This script must be run as root (sudo)
        exit 2
    fi
}

check_dependencies() {
    local deps=(mount umount findmnt du df find awk grep)
    local missing=()
    
    for dep in ${deps[@]}; do
        if ! command -v $dep &devnull; then
            missing+=($dep)
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error Missing dependencies ${missing[]}
        exit 2
    fi
}

human_readable_size() {
    local size_kb=$1
    if [[ $size_kb -ge 1073741824 ]]; then
        echo $(awk BEGIN {printf %.1f, $size_kb1073741824})T
    elif [[ $size_kb -ge 1048576 ]]; then
        echo $(awk BEGIN {printf %.1f, $size_kb1048576})G
    elif [[ $size_kb -ge 1024 ]]; then
        echo $(awk BEGIN {printf %.1f, $size_kb1024})M
    else
        echo ${size_kb}K
    fi
}

get_size_kb() {
    local path=$1
    du -sk $path 2devnull  cut -f1  echo 0
}

#===============================================================================
# Cleanup Handler
#===============================================================================
cleanup() {
    [[ $CLEANUP_DONE == true ]] && return
    CLEANUP_DONE=true
    
    log_debug Cleaning up...
    
    # Unmount bind mount if it exists
    if mountpoint -q $BIND_MOUNT_BASE 2devnull; then
        umount $BIND_MOUNT_BASE 2devnull
        log_debug Unmounted $BIND_MOUNT_BASE
    fi
    
    # Remove bind mount directory
    if [[ -d $BIND_MOUNT_BASE ]]; then
        rmdir $BIND_MOUNT_BASE 2devnull
        log_debug Removed $BIND_MOUNT_BASE
    fi
}

trap cleanup EXIT INT TERM

#===============================================================================
# Mount Point Discovery
#===============================================================================
get_mount_points() {
    # Get all mount points except root, proc, sys, dev, run, snap
    findmnt -rno TARGET  grep -vE ^$^(procsysdevrunsnap)  sort -u
}

get_mount_fstype() {
    local mount_point=$1
    findmnt -rno FSTYPE $mount_point 2devnull  echo unknown
}

get_mount_source() {
    local mount_point=$1
    findmnt -rno SOURCE $mount_point 2devnull  echo unknown
}

#===============================================================================
# Core Scanning Logic
#===============================================================================
setup_bind_mount() {
    # Create temporary bind mount of root filesystem
    mkdir -p $BIND_MOUNT_BASE
    
    if ! mount --bind  $BIND_MOUNT_BASE; then
        log_error Failed to create bind mount at $BIND_MOUNT_BASE
        return 1
    fi
    
    # Make it read-only for safety
    mount -o remount,ro,bind $BIND_MOUNT_BASE 2devnull  true
    
    log_debug Created bind mount at $BIND_MOUNT_BASE
    return 0
}

scan_mount_point() {
    local mount_point=$1
    local hidden_path=${BIND_MOUNT_BASE}${mount_point}
    
    log_debug Scanning $mount_point - $hidden_path
    
    # Check if hidden path exists
    if [[ ! -d $hidden_path ]]; then
        log_debug No hidden directory found for $mount_point
        return 0
    fi
    
    # Get size of hidden data
    local size_kb=$(get_size_kb $hidden_path)
    
    # Skip if below minimum size threshold
    if [[ $size_kb -le $MIN_SIZE_KB ]]; then
        log_debug Skipping $mount_point (size ${size_kb}KB = threshold ${MIN_SIZE_KB}KB)
        return 0
    fi
    
    local size_human=$(human_readable_size $size_kb)
    local mount_fstype=$(get_mount_fstype $mount_point)
    local mount_source=$(get_mount_source $mount_point)
    
    # Collect additional data for deep scan
    local file_count=0
    local dir_count=0
    local oldest_file=
    local newest_file=
    
    if [[ $SCAN_DEPTH == deep ]]; then
        file_count=$(find $hidden_path -type f 2devnull  wc -l)
        dir_count=$(find $hidden_path -type d 2devnull  wc -l)
        oldest_file=$(find $hidden_path -type f -printf '%T+ %pn' 2devnull  sort  head -1)
        newest_file=$(find $hidden_path -type f -printf '%T+ %pn' 2devnull  sort -r  head -1)
    fi
    
    # Output based on format
    case $OUTPUT_FORMAT in
        json)
            output_json_finding $mount_point $size_kb $size_human $mount_fstype 
                               $mount_source $file_count $dir_count $oldest_file $newest_file
            ;;
        csv)
            output_csv_finding $mount_point $size_kb $size_human $mount_fstype 
                              $mount_source $file_count $dir_count
            ;;
        )
            output_text_finding $mount_point $size_kb $size_human $mount_fstype 
                               $mount_source $file_count $dir_count $oldest_file $newest_file
            ;;
    esac
    
    return 1  # Return 1 to indicate hidden data found
}

#===============================================================================
# Output Formatters
#===============================================================================
declare -a JSON_FINDINGS=()
declare -a CSV_FINDINGS=()

output_text_finding() {
    local mount_point=$1
    local size_kb=$2
    local size_human=$3
    local mount_fstype=$4
    local mount_source=$5
    local file_count=$6
    local dir_count=$7
    local oldest_file=$8
    local newest_file=$9
    
    echo 
    log_finding Hidden data under ${BOLD}$mount_point${RESET}
    echo     Size        $size_human ($size_kb KB)
    echo     Mount Type  $mount_fstype
    echo     Mount From  $mount_source
    
    if [[ $SCAN_DEPTH == deep ]]; then
        echo     Files       $file_count
        echo     Directories $dir_count
        [[ -n $oldest_file ]] && echo     Oldest      $oldest_file
        [[ -n $newest_file ]] && echo     Newest      $newest_file
    fi
}

output_json_finding() {
    local mount_point=$1
    local size_kb=$2
    local size_human=$3
    local mount_fstype=$4
    local mount_source=$5
    local file_count=$6
    local dir_count=$7
    local oldest_file=$8
    local newest_file=$9
    
    local json_obj=$(cat EOF
{
    mount_point $mount_point,
    size_bytes $((size_kb  1024)),
    size_human $size_human,
    mount_fstype $mount_fstype,
    mount_source $mount_source,
    file_count $file_count,
    dir_count $dir_count,
    oldest_file $oldest_file,
    newest_file $newest_file
}
EOF
)
    JSON_FINDINGS+=($json_obj)
}

output_csv_finding() {
    local mount_point=$1
    local size_kb=$2
    local size_human=$3
    local mount_fstype=$4
    local mount_source=$5
    local file_count=$6
    local dir_count=$7
    
    CSV_FINDINGS+=($mount_point,$size_kb,$size_human,$mount_fstype,$mount_source,$file_count,$dir_count)
}

print_text_header() {
    [[ $QUIET == true ]] && return
    
    echo 
    echo -e ${BOLD}═══════════════════════════════════════════════════════════════════════════════${RESET}
    echo -e ${BOLD}  HIDDEN MOUNT SCANNER v${VERSION}${RESET}
    echo -e ${BOLD}═══════════════════════════════════════════════════════════════════════════════${RESET}
    echo 
    echo   Hostname     $(hostname)
    echo   Date         $(date)
    echo   Scan Depth   $SCAN_DEPTH
    echo   Min Size     ${MIN_SIZE_KB} KB
    [[ -n $TARGET_MOUNT ]] && echo   Target Mount $TARGET_MOUNT
    echo 
    echo    READ-ONLY SCAN - NO CHANGES MADE 
    echo 
    echo -e ${BOLD}───────────────────────────────────────────────────────────────────────────────${RESET}
}

print_text_summary() {
    local total_mounts=$1
    local mounts_with_hidden=$2
    local total_hidden_kb=$3
    
    [[ $QUIET == true ]] && return
    
    echo 
    echo -e ${BOLD}───────────────────────────────────────────────────────────────────────────────${RESET}
    echo -e ${BOLD}  SUMMARY${RESET}
    echo -e ${BOLD}───────────────────────────────────────────────────────────────────────────────${RESET}
    echo 
    echo   Mount points scanned   $total_mounts
    echo   With hidden data       $mounts_with_hidden
    echo   Total hidden size      $(human_readable_size $total_hidden_kb)
    echo 
    
    if [[ $mounts_with_hidden -gt 0 ]]; then
        echo -e   ${RED}${BOLD}⚠ HIDDEN DATA DETECTED${RESET}
        echo 
        echo   To investigate further, use bind mount
        echo     sudo mkdir -p mntroot_check
        echo     sudo mount --bind  mntroot_check
        echo     ls -la mntroot_checkmount_point
        echo     sudo umount mntroot_check
    else
        echo -e   ${GREEN}✓ No significant hidden data found${RESET}
    fi
    
    echo 
    echo -e ${BOLD}═══════════════════════════════════════════════════════════════════════════════${RESET}
}

print_json_output() {
    local total_mounts=$1
    local mounts_with_hidden=$2
    local total_hidden_kb=$3
    
    local findings_json=
    if [[ ${#JSON_FINDINGS[@]} -gt 0 ]]; then
        findings_json=$(printf %s, ${JSON_FINDINGS[@]})
        findings_json=[${findings_json%,}]
    else
        findings_json=[]
    fi
    
    cat EOF
{
    scanner_version $VERSION,
    hostname $(hostname),
    timestamp $(date -Iseconds),
    scan_depth $SCAN_DEPTH,
    summary {
        mounts_scanned $total_mounts,
        mounts_with_hidden_data $mounts_with_hidden,
        total_hidden_bytes $((total_hidden_kb  1024)),
        total_hidden_human $(human_readable_size $total_hidden_kb)
    },
    findings $findings_json
}
EOF
}

print_csv_output() {
    echo mount_point,size_kb,size_human,mount_fstype,mount_source,file_count,dir_count
    for finding in ${CSV_FINDINGS[@]}; do
        echo $finding
    done
}

#===============================================================================
# Disk Analysis (df vs du comparison)
#===============================================================================
print_disk_analysis() {
    [[ $QUIET == true ]] && return
    [[ $OUTPUT_FORMAT != text ]] && return
    
    echo 
    echo -e ${BOLD}───────────────────────────────────────────────────────────────────────────────${RESET}
    echo -e ${BOLD}  DISK ANALYSIS (df vs du comparison)${RESET}
    echo -e ${BOLD}───────────────────────────────────────────────────────────────────────────────${RESET}
    echo 
    
    # Get list of local (non-network) filesystems
    while IFS= read -r line; do
        local mount_point=$(echo $line  awk '{print $6}')
        local device=$(echo $line  awk '{print $1}')
        local df_used=$(echo $line  awk '{print $3}')  # In KB
        
        # Skip pseudo filesystems
        [[ $mount_point ==  ]]  continue
        
        local du_visible=$(du -sxk $mount_point 2devnull  cut -f1  echo 0)
        local gap=$((df_used - du_visible))
        
        if [[ $gap -gt 102400 ]]; then  # Gap  100MB
            echo   Mount $mount_point ($device)
            echo     df reports  $(human_readable_size $df_used)
            echo     du visible  $(human_readable_size $du_visible)
            echo     Gap         $(human_readable_size $gap) ${RED}⚠${RESET}
            echo 
        fi
    done  (df -Pk 2devnull  tail -n +2  grep ^dev)
}

#===============================================================================
# Main Execution
#===============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h--help)
                show_help
                ;;
            -V--version)
                show_version
                ;;
            -t--target)
                TARGET_MOUNT=$2
                shift 2
                ;;
            -f--format)
                OUTPUT_FORMAT=$2
                if [[ ! $OUTPUT_FORMAT =~ ^(textjsoncsv)$ ]]; then
                    log_error Invalid format $OUTPUT_FORMAT (use text, json, csv)
                    exit 2
                fi
                shift 2
                ;;
            -o--output)
                OUTPUT_FILE=$2
                shift 2
                ;;
            -d--deep)
                SCAN_DEPTH=deep
                shift
                ;;
            -q--quick)
                SCAN_DEPTH=quick
                shift
                ;;
            -m--min-size)
                MIN_SIZE_KB=$2
                shift 2
                ;;
            -v--verbose)
                VERBOSE=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            )
                log_error Unknown option $1
                echo Use -h for help
                exit 2
                ;;
        esac
    done
}

main() {
    parse_args $@
    setup_colors
    
    check_root
    check_dependencies
    
    # Print header
    [[ $OUTPUT_FORMAT == text ]] && print_text_header
    
    # Setup bind mount
    if ! setup_bind_mount; then
        exit 2
    fi
    
    # Get mount points to scan
    local mount_points
    if [[ -n $TARGET_MOUNT ]]; then
        mount_points=$TARGET_MOUNT
    else
        mount_points=$(get_mount_points)
    fi
    
    # Scan each mount point
    local total_mounts=0
    local mounts_with_hidden=0
    local total_hidden_kb=0
    
    while IFS= read -r mount_point; do
        [[ -z $mount_point ]] && continue
        
        ((total_mounts++))
        log_debug Processing mount point $mount_point
        
        if ! scan_mount_point $mount_point; then
            ((mounts_with_hidden++))
            local hidden_path=${BIND_MOUNT_BASE}${mount_point}
            local size_kb=$(get_size_kb $hidden_path)
            total_hidden_kb=$((total_hidden_kb + size_kb))
        fi
    done  $mount_points
    
    # Print disk analysis
    [[ $OUTPUT_FORMAT == text ]] && print_disk_analysis
    
    # Print output based on format
    case $OUTPUT_FORMAT in
        json)
            local output=$(print_json_output $total_mounts $mounts_with_hidden $total_hidden_kb)
            echo $output
            [[ -n $OUTPUT_FILE ]] && echo $output  $OUTPUT_FILE
            ;;
        csv)
            local output=$(print_csv_output)
            echo $output
            [[ -n $OUTPUT_FILE ]] && echo $output  $OUTPUT_FILE
            ;;
        )
            print_text_summary $total_mounts $mounts_with_hidden $total_hidden_kb
            ;;
    esac
    
    # Exit code 0 = no hidden data, 1 = hidden data found
    [[ $mounts_with_hidden -gt 0 ]] && exit 1  exit 0
}

# Run main function
main $@