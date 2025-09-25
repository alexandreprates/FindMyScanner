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
DEFAULT_MANUFACTURERS="all"

# Global control variables
SKIP_UPLOAD=false
SELECTED_ENV=""
QUIET_MODE=false
SELECTED_FORMAT=""
SELECTED_MIN_RSSI=""
SELECTED_MANUFACTURERS=""
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

# Validate manufacturer list
validate_manufacturers() {
    local manufacturers="$1"
    local IFS=','

    for manufacturer in $manufacturers; do
        case "$manufacturer" in
            Apple|Google|Samsung|Xiaomi|all) ;;
            *) return 1 ;;
        esac
    done
    return 0
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

# Convert manufacturers string to build flag value
manufacturers_to_flag() {
    local manufacturers="$1"
    local flag=0
    local IFS=','

    # Handle "all" case
    if [ "$manufacturers" = "all" ]; then
        echo "0xF"
        return
    fi

    for manufacturer in $manufacturers; do
        case "$manufacturer" in
            Apple)   flag=$((flag | 1)) ;;    # 0x1
            Google)  flag=$((flag | 2)) ;;    # 0x2
            Samsung) flag=$((flag | 4)) ;;    # 0x4
            Xiaomi)  flag=$((flag | 8)) ;;    # 0x8
        esac
    done

    printf "0x%X" "$flag"
}

# ============================================================================
# USER INTERFACE FUNCTIONS
# ============================================================================

# Display help message
show_help() {
    cat << 'EOF'
Usage: monitor2log.sh [OPTIONS]

Monitor PlatformIO device output with configurable format options.

WORKFLOW:
    1. Select environment (ESP32 board type)
    2. Choose whether to customize firmware settings
    3. If customizing: configure format, RSSI filter, and manufacturers
    4. Upload firmware with custom settings (if customization chosen)
    5. Start monitoring device output

OPTIONS:
    --env ENVIRONMENT         Specify the environment to use (e.g., esp32-s3)
    --format FORMAT           Specify output format: log, csv, or yaml
                             (triggers firmware customization if provided)
    --min-rssi=VALUE          Specify minimum RSSI threshold (e.g., --min-rssi=-70)
                             (triggers firmware customization if provided)
    --manufacturer=LIST       Specify manufacturers to filter (comma-separated)
                             Valid values: Apple, Google, Samsung, Xiaomi, all
                             Examples: --manufacturer=Apple,Google
                                      --manufacturer=all (default)
                             (triggers firmware customization if provided)
    --no-upload              Skip firmware customization and upload, use existing firmware
    --quiet                  Save logs only to file, without terminal display
    -h, --help               Show this help message and exit

EXAMPLES:
    # Interactive mode - will ask for customization
    ./monitor2log.sh

    # Custom firmware with specific settings
    ./monitor2log.sh --env esp32-s3 --format csv --min-rssi=-70 --manufacturer=Apple,Google

    # Use existing firmware without upload
    ./monitor2log.sh --no-upload --env esp32-wroom

    # Quiet monitoring with custom settings
    ./monitor2log.sh --format yaml --quiet --min-rssi=-80 --manufacturer=Samsung

For more information, visit: https://github.com/alexandreprates/FindMyScanner
EOF
}

# Display environment selection menu
show_environment_menu() {
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

# Handle format selection (interactive only - command line args handled in main)
select_format() {
    debug "Starting format selection"

    # Interactive selection
    show_format_menu

    # Get user choice
    while true; do
        local prompt="Choose output format (1-3)"
        printf "%s [2]: " "$prompt" >&2

        read choice
        choice=${choice:-2}

        case "$choice" in
            1) echo "log"; return ;;
            2) echo "csv"; return ;;
            3) echo "yaml"; return ;;
            *) echo "Invalid choice. Please enter 1, 2, or 3." >&2 ;;
        esac
    done
}

# Handle MIN_RSSI selection (interactive only - command line args handled in main)
select_min_rssi() {
    debug "Starting MIN_RSSI selection"

    # Interactive selection
    echo >&2
    echo "MIN_RSSI Filter Configuration:" >&2
    echo "Select signal strength threshold for device detection:" >&2
    echo "  0 -> NO-FILTER (accept all signals)" >&2
    echo "  1 -> -10 dBm   (very close)" >&2
    echo "  2 -> -20 dBm   (close)" >&2
    echo "  3 -> -30 dBm   (near)" >&2
    echo "  4 -> -40 dBm   (medium-close)" >&2
    echo "  5 -> -50 dBm   (medium)" >&2
    echo "  6 -> -60 dBm   (medium-far)" >&2
    echo "  7 -> -70 dBm   (far - default)" >&2
    echo "  8 -> -80 dBm   (distant)" >&2
    echo "  9 -> -100 dBm  (extremely distant)" >&2
    echo >&2

    # Get user input
    while true; do
        local prompt="Choose signal strength level (0-9)"
        printf "%s [7]: " "$prompt" >&2

        read rssi_choice
        rssi_choice=${rssi_choice:-7}

        # Convert choice to RSSI value
        case "$rssi_choice" in
            0) echo "-200"; return ;;  # NO-FILTER
            1) echo "-10"; return ;;
            2) echo "-20"; return ;;
            3) echo "-30"; return ;;
            4) echo "-40"; return ;;
            5) echo "-50"; return ;;
            6) echo "-60"; return ;;
            7) echo "-70"; return ;;
            8) echo "-80"; return ;;
            9) echo "-100"; return ;;
            *) echo "Invalid choice. Please enter a number between 0 and 9." >&2 ;;
        esac
    done
}

# Handle manufacturers selection (interactive only - command line args handled in main)
select_manufacturers() {
    debug "Starting manufacturers selection"

    # Interactive selection
    echo >&2
    echo "Manufacturer Filter Configuration:" >&2
    echo "Select which manufacturers to monitor:" >&2
    echo "  1. Apple    (AirTag, Find My)" >&2
    echo "  2. Google   (Fast Pair)" >&2
    echo "  3. Samsung  (SmartTag)" >&2
    echo "  4. Xiaomi   (Anti-Lost)" >&2
    echo "  5. all      (All manufacturers - default)" >&2
    echo >&2
    echo "You can enter multiple numbers separated by commas (e.g., 1,2,4)" >&2
    echo >&2

    # Get user input
    while true; do
        local prompt="Choose manufacturers (1-5 or combinations)"
        printf "%s [5]: " "$prompt" >&2

        read manufacturers_input
        manufacturers_input=${manufacturers_input:-5}

        # Convert numbers to manufacturer names
        local selected_manufacturers=""
        local IFS=','

        for choice in $manufacturers_input; do
            case "$choice" in
                1) selected_manufacturers="${selected_manufacturers}${selected_manufacturers:+,}Apple" ;;
                2) selected_manufacturers="${selected_manufacturers}${selected_manufacturers:+,}Google" ;;
                3) selected_manufacturers="${selected_manufacturers}${selected_manufacturers:+,}Samsung" ;;
                4) selected_manufacturers="${selected_manufacturers}${selected_manufacturers:+,}Xiaomi" ;;
                5) selected_manufacturers="all"; break ;;
                *) echo "Invalid choice: $choice. Please enter numbers 1-5." >&2; continue 2 ;;
            esac
        done

        if [ -n "$selected_manufacturers" ]; then
            echo "$selected_manufacturers"
            return
        else
            echo "Please select at least one manufacturer." >&2
        fi
    done
}

# Ask if user wants to customize firmware
ask_firmware_customization() {
    debug "Starting firmware customization question"

    # If arguments were provided via command line, consider as customization
    if [ -n "$SELECTED_FORMAT" ] || [ -n "$SELECTED_MIN_RSSI" ] || [ -n "$SELECTED_MANUFACTURERS" ]; then
        info "Using custom firmware settings from command line" >&2
        echo "y"
        return
    fi

    # If --no-upload was specified, skip customization
    if [ "$SKIP_UPLOAD" = "true" ]; then
        info "Skipping firmware customization (--no-upload specified)" >&2
        echo "n"
        return
    fi

    # Interactive question
    while true; do
        echo >&2
        local prompt="Do you want to customize firmware settings (format, RSSI filter, manufacturers)?"
        prompt="$prompt [Y/n]"
        printf "%s: " "$prompt" >&2

        read choice
        choice=${choice:-"y"}

        case "$choice" in
            [Yy]*)
                echo "y"
                return
                ;;
            [Nn]*)
                echo "n"
                return
                ;;
            *)
                echo "Please enter Y or N." >&2
                ;;
        esac
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
    local manufacturers="$4"

    debug "Starting upload process for env=$env format=$format min_rssi=$min_rssi manufacturers=$manufacturers"

    if [ "$SKIP_UPLOAD" = "true" ]; then
        info "Skipping firmware upload (--no-upload specified)" >&2
        return 1
    fi

    # Get user confirmation
    while true; do
        echo >&2
        local prompt="Upload firmware with $format format, MIN_RSSI=$min_rssi, and manufacturers=$manufacturers ?"
            prompt="$prompt [Y/n]"
        printf "%s: " "$prompt" >&2

        read choice
        choice=${choice:-$DEFAULT_UPLOAD}

        case "$choice" in
            [Yy]*)
                if perform_upload "$env" "$format" "$min_rssi" "$manufacturers"; then
                    info "Firmware upload completed successfully" >&2
                    return 0
                else
                    error_exit "Firmware upload failed"
                fi
                ;;
            [Nn]*)
                echo "Would you like to change the configuration?" >&2
                printf "Change settings? [Y/n]: " >&2
                read change_choice
                change_choice=${change_choice:-"y"}

                case "$change_choice" in
                    [Yy]*)
                        info "Returning to configuration menu..." >&2
                        return 2  # Special return code to indicate reconfiguration needed
                        ;;
                    [Nn]*)
                        info "Proceeding with existing firmware (may have different settings)" >&2
                        return 1
                        ;;
                    *)
                        echo "Please enter Y or N." >&2
                        continue
                        ;;
                esac
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
    local manufacturers="$4"
    local format_flag
    local manufacturers_flag

    format_flag=$(format_to_flag "$format")
    manufacturers_flag=$(manufacturers_to_flag "$manufacturers")

    info "Compiling and uploading firmware..."

    # Set build flags via environment variable
    export PLATFORMIO_BUILD_FLAGS="-DOUTPUT_FORMAT_FLAG=$format_flag -DMIN_RSSI_FLAG=$min_rssi -DMANUFACTURES_FLAG=$manufacturers_flag"

    # First compile the project
    info "Compiling project for environment: $env"
    if ! $PLATFORMIO_BIN run -e "$env" --silent; then
        error_exit "Compilation failed for environment: $env"
    fi

    # Then perform upload
    info "Uploading firmware to device..."
    # if $PLATFORMIO_BIN run -e "$env" -t upload --silent; then
    if $PLATFORMIO_BIN run -e "$env" -t upload; then
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
    local manufacturers="$4"

    debug "Starting monitoring for env=$env format=$format min_rssi=$min_rssi manufacturers=$manufacturers"

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
    info "Manufacturers: $manufacturers"
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
            --manufacturer=*)
                local manufacturers_value="${1#--manufacturer=}"
                if [ -z "$manufacturers_value" ]; then
                    error_exit "--manufacturer requires a value (e.g., --manufacturer=Apple,Google)"
                elif validate_manufacturers "$manufacturers_value"; then
                    SELECTED_MANUFACTURERS="$manufacturers_value"
                    shift
                else
                    error_exit "--manufacturer must contain valid values: Apple, Google, Samsung, Xiaomi, all"
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
    echo "=== Monitor to Log ==="

    # Setup and validation
    setup_platformio

    # Step 1: Select environment
    local selected_env
    selected_env=$(select_environment)

    # Configuration loop - allows user to return and reconfigure
    while true; do
        # Step 2: Ask if user wants to customize firmware
        local customize_firmware
        customize_firmware=$(ask_firmware_customization)

        # Step 3: Collect settings (either from command line or interactive)
        local selected_format="$DEFAULT_FORMAT"
        local selected_min_rssi="$DEFAULT_MIN_RSSI"
        local selected_manufacturers="$DEFAULT_MANUFACTURERS"

        if [ "$customize_firmware" = "y" ]; then
            # Use command line arguments if provided, otherwise ask interactively
            if [ -n "$SELECTED_FORMAT" ]; then
                selected_format="$SELECTED_FORMAT"
                info "Using format from command line: $selected_format" >&2
            else
                selected_format=$(select_format)
            fi

            if [ -n "$SELECTED_MIN_RSSI" ]; then
                selected_min_rssi="$SELECTED_MIN_RSSI"
                info "Using MIN_RSSI from command line: $selected_min_rssi" >&2
            else
                selected_min_rssi=$(select_min_rssi)
            fi

            if [ -n "$SELECTED_MANUFACTURERS" ]; then
                selected_manufacturers="$SELECTED_MANUFACTURERS"
                info "Using manufacturers from command line: $selected_manufacturers" >&2
            else
                selected_manufacturers=$(select_manufacturers)
            fi

            # Step 4: Upload firmware with custom settings
            local upload_result
            handle_upload "$selected_env" "$selected_format" "$selected_min_rssi" "$selected_manufacturers"
            upload_result=$?

            case $upload_result in
                0)
                    info "Using uploaded firmware with custom settings" >&2
                    break  # Exit configuration loop, proceed to monitoring
                    ;;
                1)
                    info "Using existing firmware (may have different settings)" >&2
                    break  # Exit configuration loop, proceed to monitoring
                    ;;
                2)
                    # User wants to reconfigure - clear command line arguments for interactive mode
                    SELECTED_FORMAT=""
                    SELECTED_MIN_RSSI=""
                    SELECTED_MANUFACTURERS=""
                    echo >&2
                    info "=== Reconfiguring firmware settings ===" >&2
                    continue  # Return to configuration loop
                    ;;
            esac
        else
            # Use defaults/command line args but skip upload
            if [ -n "$SELECTED_FORMAT" ]; then
                selected_format="$SELECTED_FORMAT"
            fi
            if [ -n "$SELECTED_MIN_RSSI" ]; then
                selected_min_rssi="$SELECTED_MIN_RSSI"
            fi
            if [ -n "$SELECTED_MANUFACTURERS" ]; then
                selected_manufacturers="$SELECTED_MANUFACTURERS"
            fi

            info "Using firmware settings: format=$selected_format, MIN_RSSI=$selected_min_rssi, manufacturers=$selected_manufacturers" >&2
            info "Note: These settings may not match the actual firmware if no upload was performed" >&2
            break  # Exit configuration loop, proceed to monitoring
        fi
    done

    # Step 5: Start monitoring
    start_monitoring "$selected_env" "$selected_format" "$selected_min_rssi" "$selected_manufacturers"
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [ "${0##*/}" = "monitor2log.sh" ] || [ "${0##*/}" = "bash" ]; then
    process_arguments "$@"
    main
fi