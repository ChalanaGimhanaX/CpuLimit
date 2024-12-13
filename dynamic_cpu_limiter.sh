#!/bin/bash

# dynamic_cpu_limiter.sh
# Description: Dynamically limits CPU usage to prevent VPS throttling.

# -------------------------------
# Configuration and Initialization
# -------------------------------

# Default CPU usage limit (can be overridden by user input)
DEFAULT_TARGET_CPU_USAGE=50

# Function to display usage
usage() {
    echo "Usage: $0 [-l CPU_LIMIT]"
    echo "  -l CPU_LIMIT  Set the target CPU usage limit (in percentage). Default is $DEFAULT_TARGET_CPU_USAGE."
    exit 1
}

# Parse command-line arguments
while getopts ":l:h" opt; do
  case ${opt} in
    l )
      TARGET_CPU_USAGE=$OPTARG
      ;;
    h )
      usage
      ;;
    \? )
      echo "Invalid Option: -$OPTARG" 1>&2
      usage
      ;;
    : )
      echo "Invalid Option: -$OPTARG requires an argument" 1>&2
      usage
      ;;
  esac
done
shift $((OPTIND -1))

# Set default if not provided
TARGET_CPU_USAGE=${TARGET_CPU_USAGE:-$DEFAULT_TARGET_CPU_USAGE}

# Ensure TARGET_CPU_USAGE is a valid number between 1 and 100
if ! [[ "$TARGET_CPU_USAGE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: CPU limit must be a number."
    usage
fi

if (( $(echo "$TARGET_CPU_USAGE < 1" | bc -l) )) || (( $(echo "$TARGET_CPU_USAGE > 100" | bc -l) )); then
    echo "Error: CPU limit must be between 1 and 100."
    usage
fi

# Log file path
LOG_FILE="/var/log/dynamic_cpu_limiter.log"

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Function to log messages with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# -------------------------------
# Swap Memory Management (Optional)
# -------------------------------

# Function to create swap if not present
create_swap() {
    if swapon --show | grep -q "^/swapfile"; then
        log "Swap is already enabled."
    else
        log "Creating swap memory..."
        fallocate -l 1G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        log "Swap memory created and enabled."
    fi
}

# Uncomment the following line if you want the script to manage swap
# create_swap

# -------------------------------
# CPU Usage Monitoring and Limiting
# -------------------------------

# Function to get total number of CPU cores
get_cpu_cores() {
    nproc
}

# Function to read /proc/stat and return idle and total CPU times
read_cpu_times() {
    awk '/^cpu / {idle=$5; total=0; for(i=2;i<=8;i++) total+=$i; print idle, total}' /proc/stat
}

# Function to calculate total CPU usage percentage based on two readings
calculate_cpu_usage() {
    local idle1=$1
    local total1=$2
    local idle2=$3
    local total2=$4

    local idle_diff=$(( idle2 - idle1 ))
    local total_diff=$(( total2 - total1 ))

    if [ $total_diff -eq 0 ]; then
        echo "0"
    else
        cpu_usage=$(echo "scale=2; 100 * ($total_diff - $idle_diff) / $total_diff" | bc)
        echo "$cpu_usage"
    fi
}

# Function to limit CPU usage of a process
limit_cpu_usage() {
    local pid=$1
    local new_limit=$2

    # Ensure new_limit is at least 1%
    if (( $(echo "$new_limit < 1" | bc -l) )); then
        new_limit=1
    fi

    # Check if cpulimit is installed
    if ! command -v cpulimit &> /dev/null; then
        log "❌ cpulimit could not be found. Please install it using 'sudo apt-get install cpulimit'."
        exit 1
    fi

    # Check if cpulimit is already limiting this PID
    if pgrep -f "cpulimit.*-p $pid" > /dev/null; then
        log "⚠️ cpulimit is already limiting PID $pid. Skipping."
        return
    fi

    # Apply CPU limit using cpulimit in background
    cpulimit -p "$pid" -l "$new_limit" -b >/dev/null 2>&1 &
    if [ $? -eq 0 ]; then
        log "✅ Applied CPU limit of ${new_limit}% to PID $pid."
    else
        log "❌ Failed to apply CPU limit to PID $pid."
    fi
}

# Function to monitor and limit CPU usage
monitor_cpu() {
    local cpu_limit=$1
    local cpu_cores=$2

    # Initial CPU times
    read -r idle1 total1 < <(read_cpu_times)

    # Sleep interval between measurements (in seconds)
    sleep_interval=2

    while true; do
        # Read CPU times again after sleep interval
        sleep "$sleep_interval"
        read -r idle2 total2 < <(read_cpu_times)

        # Calculate CPU usage
        CURRENT_TOTAL_CPU=$(calculate_cpu_usage "$idle1" "$total1" "$idle2" "$total2")

        # Update previous times for next iteration
        idle1=$idle2
        total1=$total2

        # Calculate target threshold with a margin (e.g., 10%)
        THRESHOLD=$(echo "$cpu_limit + 10" | bc -l)

        if (( $(echo "$CURRENT_TOTAL_CPU < $cpu_limit" | bc -l) )); then
            log "ℹ️ Current CPU usage (${CURRENT_TOTAL_CPU}%) is below the target (${cpu_limit}%). No action required."
            continue
        elif (( $(echo "$CURRENT_TOTAL_CPU > $THRESHOLD" | bc -l) )); then
            log "⚠️ Current CPU usage (${CURRENT_TOTAL_CPU}%) exceeds the threshold (${THRESHOLD}%). Initiating CPU limiting."
        else
            log "ℹ️ Current CPU usage (${CURRENT_TOTAL_CPU}%) is within acceptable limits."
            continue
        fi

        # Iterate over top CPU-consuming processes
        # Exclude this script and system processes to prevent self-throttling
        ps -eo pid,pcpu,comm --sort=-pcpu --no-headers | grep -vE "(${BASHPID}|systemd|sshd|bash|cpulimit)" | while read -r pid cpu_usage comm; do
            # Skip processes with negligible CPU usage
            if (( $(echo "$cpu_usage < 1" | bc -l) )); then
                continue
            fi

            # Calculate new CPU limit based on scaling factor
            SCALING_FACTOR=$(echo "$cpu_limit / $CURRENT_TOTAL_CPU" | bc -l)
            NEW_LIMIT=$(echo "$cpu_usage * $SCALING_FACTOR" | bc -l)
            NEW_LIMIT_INT=$(printf "%.0f" "$NEW_LIMIT")

            # Apply the CPU limit if necessary
            if (( $(echo "$NEW_LIMIT < $cpu_usage" | bc -l) )); then
                limit_cpu_usage "$pid" "$NEW_LIMIT_INT"
            fi
        done

        log "🔄 CPU limiting actions completed."
    done
}

# -------------------------------
# Main Execution
# -------------------------------

main() {
    local cpu_limit=$TARGET_CPU_USAGE
    local cpu_cores=$(get_cpu_cores)

    log "🚀 Starting Dynamic CPU Limiter Service with a target CPU usage of ${cpu_limit}% across ${cpu_cores} cores."

    # Start monitoring CPU usage in the foreground
    monitor_cpu "$cpu_limit" "$cpu_cores"
}

# Start the main function
main
