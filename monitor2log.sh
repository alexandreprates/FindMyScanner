#!/usr/bin/env bash

# ============================================================================
# PlatformIO Monitor to Log Script (Fixed)
# ============================================================================
# Description: Enhanced script for monitoring PlatformIO device output with
#              configurable format options and improved code organization
# Author: Alexandre Prates
# Date: 2025-09-22
# ============================================================================

# set -x  # Stop on error

# ============================================================================
# CONSTANTS AND GLOBAL VARIABLES
# ============================================================================

SCRIPT_NAME="$(basename "$0")"
LOGS_DIR="./logs"

# Default values
DEFAULT_FORMAT="csv"
DEFAULT_UPLOAD="y"
DEFAULT_MIN_RSSI="-70"

# Global control variables
SKIP_UPLOAD=false
SELECTED_ENV=""
QUIET_MODE=false
SELECTED_FORMAT=""
SELECTED_MIN_RSSI=""
PLATFORMIO_BIN=""

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Print error message and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Print info message
info() {
    echo "Info: $1"
}

# Print debug message (only if DEBUG is set)
debug() {
    echo "Debug: $1" >/dev/null
}

# Check if PlatformIO is available and set the binary path
setup_platformio() {
    if command -v pio >/dev/null 2>&1; then
        PLATFORMIO_BIN="pio"
        debug "Found pio command"
    elif command -v platformio >/dev/null 2>&1; then
        PLATFORMIO_BIN="platformio"
        debug "Found platformio command"
    else
        error_exit "PlatformIO command not found. Please install PlatformIO CLI."
    fi
}

# Validate if a value is a positive integer
is_positive_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$1" -gt 0 ] ;;
    esac
}

# Validate if a value is a valid integer (positive or negative)
is_integer() {
    case "$1" in
        ''|*[!0-9-]*) return 1 ;;
        -*) # Negative number
            local num="${1#-}"
            case "$num" in
                ''|*[!0-9]*) return 1 ;;
                *) return 0 ;;
            esac
            ;;
        *) # Positive number
            case "$1" in
                *[!0-9]*) return 1 ;;
                *) return 0 ;;
            esac
            ;;
    esac
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Validate output format
validate_format() {
    local format="$1"
    case "$format" in
        log|csv|yaml) return 0 ;;
        *) return 1 ;;
    esac
}

# Validate user choice against available options
validate_choice() {
    local choice="$1"
    local max="$2"

    if is_positive_integer "$choice" && [ "$choice" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# Validate if environment exists in available environments
validate_environment() {
    local env_to_check="$1"
    shift

    for env in "$@"; do
        if [ "$env" = "$env_to_check" ]; then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# PLATFORMIO INTERACTION
# ============================================================================

# Get list of available environments from platformio.ini
get_environments() {
    debug "Getting environments from platformio.ini"

    if [ -z "$PLATFORMIO_BIN" ]; then
        error_exit "PlatformIO binary not set. Call setup_platformio first."
    fi

    local envs
    envs=$($PLATFORMIO_BIN project config 2>/dev/null | grep "^env:" | sed 's/env://g')

    if [ -z "$envs" ]; then
        error_exit "No environments found in platformio.ini"
    fi

    echo "$envs"
}

# Convert format string to build flag value
format_to_flag() {
    local format="$1"
    case "$format" in
        log)  echo "0" ;;
        csv)  echo "1" ;;
        yaml) echo "2" ;;
        *)    echo "1" ;;  # Default to CSV
    esac
}

# ============================================================================
# USER INTERFACE FUNCTIONS
# ============================================================================

# Display help message
show_help() {
    cat << 'EOF'
Usage: monitor2log.sh [OPTIONS]

Monitor PlatformIO device output with configurable format options.

OPTIONS:
    --env ENVIRONMENT      Specify the environment to use (e.g., esp32-s3)
    --format FORMAT        Specify output format: log, csv, or yaml
    --min-rssi=VALUE       Specify minimum RSSI threshold (e.g., --min-rssi=-70)
    --no-upload           Skip upload process and go directly to monitoring
    --quiet               Save logs only to file, without terminal display
    -h, --help            Show this help message and exit

EXAMPLES:
    ./monitor2log.sh --env esp32-s3 --format csv --min-rssi=-70
    ./monitor2log.sh --format yaml --quiet --min-rssi=-80
    ./monitor2log.sh --no-upload --env esp32-wroom --min-rssi=-60

For more information, visit: https://github.com/alexandreprates/FindMyScanner
EOF
}

# Display environment selection menu
show_environment_menu() {
    echo >&2
    echo "Available environments:" >&2
    local i=1
    for env in "$@"; do
        echo "  $i. $env" >&2
        i=$((i + 1))
    done
    echo >&2
}

# Display format selection menu
show_format_menu() {
    echo >&2
    echo "Available output formats:" >&2
    echo "  1. log  (Human-readable log format)" >&2
    echo "  2. csv  (Comma-separated values)" >&2
    echo "  3. yaml (YAML format)" >&2
    echo >&2
}

# ============================================================================
# SELECTION FUNCTIONS
# ============================================================================

# Handle environment selection (interactive or from arguments)
select_environment() {
    debug "Starting environment selection"

    # Get available environments
    local env_list
    env_list=$(get_environments)

    if [ -z "$env_list" ]; then
        error_exit "No environments found in platformio.ini"
    fi

    # Convert to array (compatible method)
    local environments=""
    local env_count=0

    # Use a simple approach to build the environment list
    for env in $env_list; do
        if [ -n "$env" ]; then
            if [ -z "$environments" ]; then
                environments="$env"
            else
                environments="$environments $env"
            fi
            env_count=$((env_count + 1))
        fi
    done

    debug "Found $env_count environments: $environments"

    # Use command line argument if provided
    if [ -n "$SELECTED_ENV" ]; then
        if validate_environment "$SELECTED_ENV" $environments; then
            info "Using environment from command line: $SELECTED_ENV" >&2
            echo "$SELECTED_ENV"
            return
        else
            error_exit "Environment '$SELECTED_ENV' not found. Available: $environments"
        fi
    fi

    # Interactive selection
    show_environment_menu $environments

    # Get user choice
    while true; do
        local prompt="Choose environment (1-$env_count)"
        printf "%s: " "$prompt" >&2

        read choice
        choice=${choice:-$default_choice}

        if validate_choice "$choice" "$env_count"; then
            # Get the selected environment
            local i=1
            for env in $environments; do
                if [ "$i" -eq "$choice" ]; then
                    echo "$env"
                    return
                fi
                i=$((i + 1))
            done
        else
            echo "Invalid choice. Please enter a number between 1 and $env_count." >&2
        fi
    done
}

# Handle format selection (interactive or from arguments)
select_format() {
    debug "Starting format selection"

    # Use command line argument if provided
    if [ -n "$SELECTED_FORMAT" ]; then
        if validate_format "$SELECTED_FORMAT"; then
            info "Using format from command line: $SELECTED_FORMAT" >&2
            echo "$SELECTED_FORMAT"
            return
        else
            error_exit "Invalid format '$SELECTED_FORMAT'. Valid options: log, csv, yaml"
        fi
    fi

    # Interactive selection
    show_format_menu

    # Get user choice
    while true; do
        local prompt="Choose output format (1-3)"
        printf "%s: " "$prompt" >&2

        read choice
        choice=${choice:-$default_choice}

        case "$choice" in
            1) echo "log"; return ;;
            2) echo "csv"; return ;;
            3) echo "yaml"; return ;;
            *) echo "Invalid choice. Please enter 1, 2, or 3." >&2 ;;
        esac
    done
}

# Handle MIN_RSSI selection (interactive or from arguments)
select_min_rssi() {
    debug "Starting MIN_RSSI selection"

    # Use command line argument if provided
    if [ -n "$SELECTED_MIN_RSSI" ]; then
        info "Using MIN_RSSI from command line: $SELECTED_MIN_RSSI" >&2
        echo "$SELECTED_MIN_RSSI"
        return
    fi

    # Interactive selection
    echo >&2
    echo "MIN_RSSI Filter Configuration:" >&2
    echo "This value sets the minimum RSSI threshold for device detection." >&2
    echo "Common values: -40 (close), -60 (medium), -80 (far), -100 (very far)" >&2
    echo >&2

    # Get user input
    while true; do
        local prompt="Enter MIN_RSSI value"
        printf "%s [%s]: " "$prompt" "$DEFAULT_MIN_RSSI" >&2

        read rssi_input
        rssi_input=${rssi_input:-$DEFAULT_MIN_RSSI}

        if is_integer "$rssi_input"; then
            echo "$rssi_input"
            return
        else
            echo "Invalid value. Please enter an integer (e.g., -70, -80, -60)." >&2
        fi
    done
}

# ============================================================================
# UPLOAD FUNCTIONS
# ============================================================================

# Handle firmware upload process
handle_upload() {
    local env="$1"
    local format="$2"
    local min_rssi="$3"

    debug "Starting upload process for env=$env format=$format min_rssi=$min_rssi"

    if [ "$SKIP_UPLOAD" = "true" ]; then
        info "Skipping firmware upload (--no-upload specified)" >&2
        echo "n"
        return
    fi

    # Get user confirmation
    while true; do
        echo >&2
        local prompt="Upload firmware with $format format and MIN_RSSI=$min_rssi?"
            prompt="$prompt [Y/n]"
        printf "%s: " "$prompt" >&2

        read choice
        choice=${choice:-$default_upload}

        case "$choice" in
            [Yy]*)
                if perform_upload "$env" "$format" "$min_rssi"; then
                    info "Firmware upload completed successfully" >&2
                    echo "y"
                    return
                else
                    error_exit "Firmware upload failed"
                fi
                ;;
            [Nn]*)
                info "Skipping firmware upload" >&2
                echo "n"
                return
                ;;
            *)
                echo "Please enter Y or N." >&2
                ;;
        esac
    done
}

# Perform the actual firmware upload
perform_upload() {
    local env="$1"
    local format="$2"
    local min_rssi="$3"
    local format_flag

    format_flag=$(format_to_flag "$format")

    info "Compiling and uploading firmware..."

    # Set build flags via environment variable
    export PLATFORMIO_BUILD_FLAGS="-DOUTPUT_FORMAT_FLAG=$format_flag -DMIN_RSSI_FLAG=$min_rssi"

    # Perform upload
    if $PLATFORMIO_BIN run -e "$env" -t upload --silent; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# MONITORING FUNCTIONS
# ============================================================================

# Setup and start log monitoring
start_monitoring() {
    local env="$1"
    local format="$2"
    local min_rssi="$3"

    debug "Starting monitoring for env=$env format=$format min_rssi=$min_rssi"

    # Create logs directory
    mkdir -p "$LOGS_DIR"

    # Generate log filename
    local timestamp
    timestamp=$(date +%Y-%m-%d-%H-%M)
    local log_file="$LOGS_DIR/${env}-${timestamp}.${format}"

    echo
    echo "=== Starting log collection ==="
    info "Environment: $env"
    info "Format: $format"
    info "MIN_RSSI: $min_rssi"
    info "Log file: $log_file"
    echo

    # Start monitoring based on quiet mode
    if [ "$QUIET_MODE" = "true" ]; then
        info "Quiet mode - logs saved to file only"
        echo "Press Ctrl+C to stop monitoring"
        echo
        $PLATFORMIO_BIN device monitor --no-reconnect --quiet -e "$env" > "$log_file"
    else
        info "Logs displayed on terminal and saved to file"
        echo "Press Ctrl+C to stop monitoring"
        echo
        $PLATFORMIO_BIN device monitor --no-reconnect --quiet -e "$env" | tee "$log_file"
    fi
}

# ============================================================================
# ARGUMENT PROCESSING
# ============================================================================

# Process command line arguments
process_arguments() {
    while [ $# -gt 0 ]; do
        case $1 in
            --no-upload)
                SKIP_UPLOAD=true
                shift
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --env)
                if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then
                    SELECTED_ENV="$2"
                    shift 2
                else
                    error_exit "--env requires a value"
                fi
                ;;
            --format)
                if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then
                    if validate_format "$2"; then
                        SELECTED_FORMAT="$2"
                        shift 2
                    else
                        error_exit "--format must be one of: log, csv, yaml"
                    fi
                else
                    error_exit "--format requires a value (log, csv, or yaml)"
                fi
                ;;
            --min-rssi=*)
                local rssi_value="${1#--min-rssi=}"
                if [ -z "$rssi_value" ]; then
                    error_exit "--min-rssi requires a value (e.g., --min-rssi=-70)"
                elif is_integer "$rssi_value"; then
                    SELECTED_MIN_RSSI="$rssi_value"
                    shift
                else
                    error_exit "--min-rssi must be an integer (e.g., -70, -80, -60)"
                fi
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown argument: $1. Use --help for usage information."
                ;;
        esac
    done
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

# Main execution function
main() {
    echo "=== PlatformIO Monitor to Log ==="
    echo

    # Setup and validation
    setup_platformio

    # Interactive selections
    local selected_env
    local selected_format
    local selected_min_rssi
    local upload_choice

    selected_env=$(select_environment)
    selected_format=$(select_format)
    selected_min_rssi=$(select_min_rssi)
    upload_choice=$(handle_upload "$selected_env" "$selected_format" "$selected_min_rssi")

    # Start monitoring
    start_monitoring "$selected_env" "$selected_format" "$selected_min_rssi"
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [ "${0##*/}" = "monitor2log.sh" ] || [ "${0##*/}" = "bash" ]; then
    process_arguments "$@"
    main
fi