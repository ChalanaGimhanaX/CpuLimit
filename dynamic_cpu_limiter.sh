#!/bin/bash

# Define the target CPU usage you want to limit to (in percentage)
TARGET_CPU_USAGE=50

while true; do
    # Get the current total CPU usage by summing the CPU usage of all processes
    CURRENT_TOTAL_CPU=$(ps -eo pcpu --no-headers | awk '{sum+=$1} END {print sum}')

    # If the current total CPU usage is already below the target, continue to the next iteration
    if (( $(echo "$CURRENT_TOTAL_CPU <= $TARGET_CPU_USAGE" | bc -l) )); then
        echo "Current CPU usage ($CURRENT_TOTAL_CPU%) is below the target ($TARGET_CPU_USAGE%). No action required."
        sleep 1
        continue
    fi

    # Calculate the scaling factor to reduce CPU usage (how much we need to reduce)
    SCALING_FACTOR=$(echo "$TARGET_CPU_USAGE / $CURRENT_TOTAL_CPU" | bc -l)

    echo "Current total CPU usage: $CURRENT_TOTAL_CPU%"
    echo "Scaling factor: $SCALING_FACTOR"
    echo "Applying new CPU limits to processes..."

    # Iterate over all running processes, get their PID and CPU usage
    ps -eo pid,pcpu --sort=-pcpu --no-headers | while read pid cpu_usage; do
        # Skip the process if its CPU usage is 0
        if (( $(echo "$cpu_usage <= 0" | bc -l) )); then
            continue
        fi

        # Calculate the new CPU limit for this process based on the scaling factor
        NEW_LIMIT=$(echo "$cpu_usage * $SCALING_FACTOR" | bc -l)

        # Limit the process to the new CPU limit using cpulimit
        sudo cpulimit -p $pid -l ${NEW_LIMIT%.*} -b

        # Log the change for debugging
        echo "Process PID: $pid - Original CPU: $cpu_usage% - New CPU limit: ${NEW_LIMIT%.*}%"
    done

    echo "CPU limits applied to processes."

    # Sleep for 1 second before repeating
    sleep 1
done
