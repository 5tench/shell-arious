#!/bin/bash
#===============================================================================
# EC2 Decommission Script
#===============================================================================
# Usage: ./ec2-decommission.sh <instance-id> [--delete-all-volumes | --interactive-volumes]
#
# Requirements: aws cli, jq (standard bash tools only)
#
# SAFETY: This script ONLY affects the instance ID you pass at runtime.
#         No hardcoded IDs. All operations are scoped to the argument you provide.
#
#-------------------------------------------------------------------------------
# WHAT THIS SCRIPT DOES:
#-------------------------------------------------------------------------------
#   1. Fetches instance details (name, type, IP, AZ)
#   2. Lists ALL attached EBS volumes with their DeleteOnTermination flag
#   3. Offers to snapshot volumes BEFORE termination 
#   4. Stops the instance (you type 'yes')
#   5. Pauses for you to verify in AWS Console (you type 'verified')
#   6. Disables termination protection
#   7. Terminates the instance
#   8. Shows orphaned volumes (DeleteOnTermination=false) and optionally deletes them
#
# A log file is created: decommission_<instance-id>_<timestamp>.log
#
# PRO TIP: Volumes with Auto-delete: true are GONE when the instance terminates.
#          Use the snapshot prompt to back them up first!
#===============================================================================

set -e

INSTANCE_ID="$1"
DELETE_MODE="$2"

#===============================================================================
# HELPER FUNCTIONS (using only standard bash)
#===============================================================================

# Print a divider line
divider() {
    echo "──────────────────────────────────────────────────────────────"
}

# Print a message with timestamp
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Animated waiting with dots (standard bash, no special chars needed)
wait_with_dots() {
    local message="$1"
    local duration="$2"
    local i=0
    
    printf "  %s" "$message"
    while [ $i -lt $duration ]; do
        printf "."
        sleep 1
        i=$((i + 1))
    done
    printf " done!\n"
}

# Poll instance state with live feedback
poll_instance_state() {
    local target_instance="$1"
    local target_state="$2"
    local max_attempts=90
    local attempt=0
    
    echo ""
    while [ $attempt -lt $max_attempts ]; do
        # Query ONLY the specific instance we're tracking
        current_state=$(aws ec2 describe-instances \
            --instance-ids "$target_instance" \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text 2>/dev/null || echo "unknown")
        
        # Show progress
        dots=""
        for ((d=0; d<(attempt % 4); d++)); do dots="${dots}."; done
        printf "\r  Waiting for %s | Current: %-12s | Elapsed: %3ds %s   " "$target_state" "$current_state" "$((attempt * 2))" "$dots"
        
        if [ "$current_state" = "$target_state" ]; then
            printf "\n"
            return 0
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
    
    printf "\n"
    echo "  WARNING: Timed out waiting for $target_state"
    return 1
}

#===============================================================================
# INPUT VALIDATION
#===============================================================================

if [ -z "$INSTANCE_ID" ]; then
    echo ""
    echo "EC2 Decommission Script"
    divider
    echo "Usage: $0 <instance-id> [options]"
    echo ""
    echo "Options:"
    echo "  --delete-all-volumes    Auto-delete all orphaned EBS volumes"
    echo "  --interactive-volumes   Prompt for each volume before deleting"
    echo "  (no option)             List volumes only, don't delete"
    echo ""
    echo "Example: $0 i-0abc123def456789"
    echo ""
    exit 1
fi

# Validate instance ID format
if ! echo "$INSTANCE_ID" | grep -qE '^i-[a-f0-9]+$'; then
    echo ""
    echo "ERROR: Invalid instance ID format"
    echo "       Expected: i-xxxxxxxxx"
    echo "       Received: $INSTANCE_ID"
    echo ""
    exit 1
fi

#===============================================================================
# LOGGING SETUP
#===============================================================================

LOG_FILE="decommission_${INSTANCE_ID}_$(date '+%Y%m%d_%H%M%S').log"

# Write to log file (does NOT print to console)
write_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Initialize log file
{
    echo "================================================================================"
    echo "EC2 DECOMMISSION LOG"
    echo "================================================================================"
    echo "Started:     $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Instance ID: $INSTANCE_ID"
    echo "Run by:      $(whoami)"
    echo "Hostname:    $(hostname)"
    echo "Options:     $DELETE_MODE"
    echo "================================================================================"
    echo ""
} > "$LOG_FILE"

#===============================================================================
# SCRIPT START
#===============================================================================

clear 2>/dev/null || true
echo ""
divider
echo "  EC2 DECOMMISSION SCRIPT"
divider
echo ""
echo "  Target Instance: $INSTANCE_ID"
echo "  Log file:        $LOG_FILE"
echo ""
echo "  >>> ONLY this instance will be affected <<<"
echo "  >>> No other servers will be touched    <<<"
echo ""
divider

#===============================================================================
# STEP 1: FETCH INSTANCE DETAILS
#===============================================================================

echo ""
log "[Step 1/7] Fetching instance details..."
echo ""

INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" 2>/dev/null || echo "")

if [ -z "$INSTANCE_INFO" ] || [ "$(echo "$INSTANCE_INFO" | jq '.Reservations | length')" -eq 0 ]; then
    echo "  ERROR: Instance $INSTANCE_ID not found in AWS"
    echo "  Please verify the instance ID and try again."
    echo ""
    exit 1
fi

INSTANCE_NAME=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].Tags[]? | select(.Key=="Name") | .Value // "N/A"')
INSTANCE_STATE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].State.Name')
INSTANCE_TYPE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].InstanceType')
INSTANCE_AZ=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')
PRIVATE_IP=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress // "N/A"')

echo "  Here's what I found:"
echo ""
echo "    Instance ID:    $INSTANCE_ID"
echo "    Name:           $INSTANCE_NAME"
echo "    Current State:  $INSTANCE_STATE"
echo "    Type:           $INSTANCE_TYPE"
echo "    AZ:             $INSTANCE_AZ"
echo "    Private IP:     $PRIVATE_IP"
echo ""

# Log instance details
write_log "INSTANCE DETAILS:"
write_log "  Name:        $INSTANCE_NAME"
write_log "  State:       $INSTANCE_STATE"
write_log "  Type:        $INSTANCE_TYPE"
write_log "  AZ:          $INSTANCE_AZ"
write_log "  Private IP:  $PRIVATE_IP"

if [ "$INSTANCE_STATE" = "terminated" ]; then
    echo "  This instance is already terminated. Nothing to do."
    echo ""
    exit 0
fi

#===============================================================================
# STEP 2: GET ATTACHED VOLUMES
#===============================================================================

log "[Step 2/7] Checking attached EBS volumes..."
echo ""

VOLUMES_JSON=$(aws ec2 describe-volumes \
    --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" 2>/dev/null || echo '{"Volumes":[]}')
VOLUME_IDS=$(echo "$VOLUMES_JSON" | jq -r '.Volumes[].VolumeId')

if [ -n "$VOLUME_IDS" ]; then
    echo "  Attached volumes:"
    echo ""
    write_log ""
    write_log "ATTACHED VOLUMES:"
    echo "$VOLUME_IDS" | while read -r VOL_ID; do
        [ -z "$VOL_ID" ] && continue
        VOL_SIZE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Size")
        VOL_TYPE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .VolumeType")
        VOL_DEVICE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Attachments[0].Device")
        VOL_DELETE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Attachments[0].DeleteOnTermination")
        echo "    - $VOL_ID | ${VOL_SIZE}GB | $VOL_TYPE | $VOL_DEVICE | Auto-delete: $VOL_DELETE"
        write_log "  $VOL_ID | ${VOL_SIZE}GB | $VOL_TYPE | $VOL_DEVICE | DeleteOnTermination: $VOL_DELETE"
    done
    echo ""
else
    echo "  No EBS volumes attached to this instance."
    write_log "ATTACHED VOLUMES: None"
    echo ""
fi

#===============================================================================
# STEP 3: SNAPSHOT VOLUMES (OPTIONAL)
#===============================================================================

if [ -n "$VOLUME_IDS" ]; then
    echo ""
    divider
    log "[Step 3/7] Snapshot attached volumes (optional)..."
    echo ""
    echo "  Volumes with Auto-delete: true will be PERMANENTLY DELETED"
    echo "  when the instance is terminated."
    echo ""
    echo "  Options:"
    echo "    [a] Snapshot ALL volumes"
    echo "    [i] Interactive - ask for each volume"
    echo "    [s] Skip - no snapshots (default)"
    echo ""
    printf "  Your choice [a/i/s]: "
    read -r SNAP_CHOICE
    
    case "$SNAP_CHOICE" in
        a|A)
            echo ""
            echo "  Creating snapshots for all volumes..."
            echo ""
            write_log ""
            write_log "SNAPSHOTS CREATED:"
            for VOL_ID in $VOLUME_IDS; do
                [ -z "$VOL_ID" ] && continue
                VOL_NAME=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Tags[]? | select(.Key==\"Name\") | .Value // \"N/A\"")
                SNAP_DESC="Pre-decommission snapshot of $VOL_ID from $INSTANCE_ID"
                printf "    Snapshotting %s (%s)..." "$VOL_ID" "$VOL_NAME"
                SNAP_ID=$(aws ec2 create-snapshot --volume-id "$VOL_ID" --description "$SNAP_DESC" --query "SnapshotId" --output text)
                echo " created: $SNAP_ID"
                write_log "  $SNAP_ID <- $VOL_ID ($VOL_NAME)"
            done
            echo ""
            echo "  All snapshots initiated. They will complete in the background."
            echo "  Snapshots are preserved even after volumes are deleted."
            echo ""
            ;;
        i|I)
            echo ""
            echo "  Interactive snapshot mode:"
            echo ""
            write_log ""
            write_log "SNAPSHOTS (interactive):"
            for VOL_ID in $VOLUME_IDS; do
                [ -z "$VOL_ID" ] && continue
                VOL_SIZE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Size")
                VOL_NAME=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Tags[]? | select(.Key==\"Name\") | .Value // \"N/A\"")
                VOL_DELETE=$(echo "$VOLUMES_JSON" | jq -r ".Volumes[] | select(.VolumeId==\"$VOL_ID\") | .Attachments[0].DeleteOnTermination")
                
                if [ "$VOL_DELETE" = "true" ]; then
                    DELETE_WARN=" [WILL BE DELETED]"
                else
                    DELETE_WARN=""
                fi
                
                printf "    Snapshot %s (%s, %sGB)%s? [y/n]: " "$VOL_ID" "$VOL_NAME" "$VOL_SIZE" "$DELETE_WARN"
                read -r SNAP_YN
                
                if [ "$SNAP_YN" = "y" ] || [ "$SNAP_YN" = "Y" ]; then
                    SNAP_DESC="Pre-decommission snapshot of $VOL_ID from $INSTANCE_ID"
                    SNAP_ID=$(aws ec2 create-snapshot --volume-id "$VOL_ID" --description "$SNAP_DESC" --query "SnapshotId" --output text)
                    echo "      Created: $SNAP_ID"
                    write_log "  $SNAP_ID <- $VOL_ID ($VOL_NAME)"
                else
                    echo "      Skipped."
                    write_log "  SKIPPED: $VOL_ID ($VOL_NAME)"
                fi
            done
            echo ""
            ;;
        *)
            echo ""
            echo "  Skipping snapshots."
            write_log ""
            write_log "SNAPSHOTS: Skipped by user"
            echo ""
            ;;
    esac
fi

#===============================================================================
# STEP 4: FIRST CONFIRMATION
#===============================================================================

divider
echo ""
echo "  CONFIRMATION REQUIRED"
echo ""
echo "  You are about to begin decommissioning:"
echo ""
echo "    $INSTANCE_ID ($INSTANCE_NAME)"
echo ""
echo "  This will STOP the server first so you can verify."
echo ""
printf "  Type 'yes' to proceed with shutdown: "
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo ""
    echo "  Aborted. No changes were made."
    echo ""
    exit 0
fi

#===============================================================================
# STEP 5: STOP INSTANCE
#===============================================================================

echo ""
divider
log "[Step 4/7] Stopping the instance..."
echo ""

if [ "$INSTANCE_STATE" = "running" ]; then
    echo "  Sending stop command to: $INSTANCE_ID"
    echo "  (Only this instance will be stopped)"
    echo ""
    
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" > /dev/null
    
    echo "  Powering down..."
    echo ""
    echo "  =========================================="
    echo "    SERVER SHUTDOWN IN PROGRESS"
    echo "    $INSTANCE_ID"
    echo "  =========================================="
    
    poll_instance_state "$INSTANCE_ID" "stopped"
    
    echo ""
    echo "  =========================================="
    echo "    SERVER IS NOW STOPPED"
    echo "    $INSTANCE_ID"
    echo "  =========================================="
    echo ""
    write_log ""
    write_log "INSTANCE STOPPED at $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo "  Instance is already stopped (state: $INSTANCE_STATE)"
    write_log ""
    write_log "INSTANCE ALREADY STOPPED (state: $INSTANCE_STATE)"
    echo ""
fi

#===============================================================================
# STEP 6: VALIDATION CHECKPOINT - USER VERIFIES IN CONSOLE
#===============================================================================

divider
echo ""
echo "  VALIDATION CHECKPOINT"
echo ""
echo "  The server is now STOPPED. Before we proceed:"
echo ""
echo "    1. Open the EC2 Console in your browser"
echo "    2. Find instance: $INSTANCE_ID"
echo "    3. Confirm the state shows 'stopped'"
echo "    4. Verify this is the correct server to decommission"
echo "    5. Confirm no other instances were affected"
echo ""
echo "  Take your time - the script will wait."
echo ""
printf "  When ready, type 'verified' to continue: "
read -r VERIFY

if [ "$VERIFY" != "verified" ]; then
    echo ""
    echo "  Aborted. The instance remains STOPPED but was NOT terminated."
    echo ""
    echo "  To restart it later:"
    echo "    aws ec2 start-instances --instance-ids $INSTANCE_ID"
    echo ""
    exit 0
fi

#===============================================================================
# STEP 7: DISABLE TERMINATION PROTECTION
#===============================================================================

echo ""
divider
log "[Step 5/7] Disabling termination protection..."
echo ""
echo "  Target: $INSTANCE_ID (only this instance)"

aws ec2 modify-instance-attribute \
    --no-disable-api-termination \
    --instance-id "$INSTANCE_ID"

echo "  Done - termination protection disabled."
echo ""

#===============================================================================
# STEP 8: TERMINATE INSTANCE
#===============================================================================

divider
log "[Step 6/7] Terminating instance..."
echo ""
echo "  =========================================="
echo "    TERMINATING SERVER"
echo "    $INSTANCE_ID"
echo "  =========================================="
echo ""
echo "  Sending terminate command..."
echo "  (Only this instance will be terminated)"
echo ""

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null

poll_instance_state "$INSTANCE_ID" "terminated"

echo ""
echo "  =========================================="
echo "    SERVER TERMINATED SUCCESSFULLY"
echo "    $INSTANCE_ID"
echo "  =========================================="
echo ""

write_log ""
write_log "INSTANCE TERMINATED at $(date '+%Y-%m-%d %H:%M:%S')"

#===============================================================================
# STEP 9: HANDLE ORPHANED VOLUMES
#===============================================================================

divider
log "[Step 7/7] Checking for orphaned EBS volumes..."
echo ""

if [ -z "$VOLUME_IDS" ]; then
    echo "  No volumes were attached. Nothing to clean up."
    echo ""
else
    # Give AWS a moment to release volumes
    wait_with_dots "Waiting for volume status update" 5
    echo ""
    
    ORPHANED_VOLS=""
    echo "$VOLUME_IDS" | while read -r VOL_ID; do
        [ -z "$VOL_ID" ] && continue
        VOL_STATUS=$(aws ec2 describe-volumes --volume-ids "$VOL_ID" \
            --query "Volumes[0].State" --output text 2>/dev/null || echo "deleted")
        if [ "$VOL_STATUS" = "available" ]; then
            echo "$VOL_ID" >> /tmp/orphaned_vols_$$
        fi
    done
    
    if [ -f /tmp/orphaned_vols_$$ ]; then
        ORPHANED_VOLS=$(cat /tmp/orphaned_vols_$$)
        rm -f /tmp/orphaned_vols_$$
    fi
    
    if [ -z "$ORPHANED_VOLS" ]; then
        echo "  All volumes were auto-deleted. No orphans found."
        write_log ""
        write_log "ORPHANED VOLUMES: None (all auto-deleted by AWS)"
        echo ""
    else
        ORPHAN_COUNT=$(echo "$ORPHANED_VOLS" | wc -l | tr -d ' ')
        echo "  Found $ORPHAN_COUNT orphaned volume(s):"
        echo ""
        write_log ""
        write_log "ORPHANED VOLUMES FOUND: $ORPHAN_COUNT"
        
        for VOL_ID in $ORPHANED_VOLS; do
            VOL_INFO=$(aws ec2 describe-volumes --volume-ids "$VOL_ID" 2>/dev/null)
            VOL_SIZE=$(echo "$VOL_INFO" | jq -r '.Volumes[0].Size')
            VOL_TYPE=$(echo "$VOL_INFO" | jq -r '.Volumes[0].VolumeType')
            VOL_AZ=$(echo "$VOL_INFO" | jq -r '.Volumes[0].AvailabilityZone')
            VOL_NAME=$(echo "$VOL_INFO" | jq -r '.Volumes[0].Tags[]? | select(.Key=="Name") | .Value // "N/A"')
            
            echo "    Volume: $VOL_ID"
            echo "    Name:   $VOL_NAME"
            echo "    Size:   ${VOL_SIZE} GB"
            echo "    Type:   $VOL_TYPE"
            echo "    AZ:     $VOL_AZ"
            echo "    ----------------------------------------"
            write_log "  $VOL_ID | $VOL_NAME | ${VOL_SIZE}GB | $VOL_TYPE"
        done
        echo ""
        
        case "$DELETE_MODE" in
            --delete-all-volumes)
                echo "  Auto-deleting all orphaned volumes..."
                echo ""
                write_log ""
                write_log "ORPHANED VOLUMES DELETED (auto):"
                for VOL_ID in $ORPHANED_VOLS; do
                    printf "    Deleting %s..." "$VOL_ID"
                    aws ec2 delete-volume --volume-id "$VOL_ID"
                    echo " done"
                    write_log "  DELETED: $VOL_ID"
                done
                echo ""
                echo "  All orphaned volumes deleted."
                ;;
                
            --interactive-volumes)
                echo "  Interactive mode: reviewing each volume"
                echo ""
                write_log ""
                write_log "ORPHANED VOLUMES (interactive):"
                for VOL_ID in $ORPHANED_VOLS; do
                    VOL_INFO=$(aws ec2 describe-volumes --volume-ids "$VOL_ID" 2>/dev/null)
                    VOL_SIZE=$(echo "$VOL_INFO" | jq -r '.Volumes[0].Size')
                    VOL_NAME=$(echo "$VOL_INFO" | jq -r '.Volumes[0].Tags[]? | select(.Key=="Name") | .Value // "N/A"')
                    
                    printf "    Delete %s (%s, %sGB)? [y/n/q]: " "$VOL_ID" "$VOL_NAME" "$VOL_SIZE"
                    read -r CHOICE
                    
                    case "$CHOICE" in
                        y|Y)
                            aws ec2 delete-volume --volume-id "$VOL_ID"
                            echo "      Deleted."
                            write_log "  DELETED: $VOL_ID ($VOL_NAME)"
                            ;;
                        n|N)
                            echo "      Skipped."
                            write_log "  KEPT: $VOL_ID ($VOL_NAME)"
                            ;;
                        q|Q)
                            echo "      Quitting. Remaining volumes not deleted."
                            write_log "  QUIT: Remaining volumes not processed"
                            break
                            ;;
                        *)
                            echo "      Skipped (invalid input)."
                            write_log "  KEPT: $VOL_ID (invalid input)"
                            ;;
                    esac
                done
                ;;
                
            *)
                echo "  Volumes NOT deleted. To delete them manually, run:"
                write_log ""
                write_log "ORPHANED VOLUMES KEPT (no delete flag):"
                for VOL_ID in $ORPHANED_VOLS; do
                    write_log "  $VOL_ID"
                done
                echo ""
                for VOL_ID in $ORPHANED_VOLS; do
                    echo "    aws ec2 delete-volume --volume-id $VOL_ID"
                done
                echo ""
                echo "  Or re-run this script with --delete-all-volumes or --interactive-volumes"
                ;;
        esac
    fi
fi

#===============================================================================
# COMPLETE
#===============================================================================

echo ""
divider
echo ""
echo "  DECOMMISSION COMPLETE"
echo ""
echo "  Instance:  $INSTANCE_ID"
echo "  Name:      $INSTANCE_NAME"
echo "  Status:    Terminated"
echo ""
echo "  Remember to:"
echo "    - Move the Terraform config to archive/"
echo "    - Update any inventory files"
echo "    - Document in change management"
echo ""
echo "  Log file: $LOG_FILE"
echo ""
divider
echo ""

# Finalize log
{
    echo ""
    echo "================================================================================"
    echo "DECOMMISSION COMPLETE"
    echo "================================================================================"
    echo "Ended:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Instance: $INSTANCE_ID"
    echo "Name:     $INSTANCE_NAME"
    echo "Status:   Terminated"
    echo "================================================================================"
} >> "$LOG_FILE"
