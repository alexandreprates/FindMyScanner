#!/usr/bin/env bash

set -e  # Stop script on error

if $(which -s pio); then
    PLATFORMIO_BIN=$(which pio)
elif $(which -s platformio); then
    PLATFORMIO_BIN=$(which platformio)
else
    echo "Missing platformio command, check system preferences"
    exit 1
fi

# Control variables
SKIP_UPLOAD=false
SELECTED_ENV=""
QUIET_MODE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
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
            if [[ -n $2 && $2 != --* ]]; then
                SELECTED_ENV="$2"
                shift 2
            else
                echo "Error: --env requires a value"
                exit 1
            fi
            ;;
        -h|--help)
            echo "Usage: $0 [--no-upload] [--env ENVIRONMENT] [--quiet] [--help]"
            echo "  --no-upload        Skip upload process and go directly to log collection"
            echo "  --env ENVIRONMENT  Specify the environment to use (e.g., esp32-s3)"
            echo "  --quiet            Save logs only to file, without displaying on terminal"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Function to get the list of available environments
get_environments() {
    $PLATFORMIO_BIN project config | grep "^env:" | sed 's/env://g'
}

# Function to display environment menu
show_environment_menu() {
    local envs=("$@")
    echo "Please select the correct env for the connected board:"
    for i in "${!envs[@]}"; do
        echo "  $((i+1)). ${envs[$i]}"
    done
    echo
}

# Function to validate user input
validate_choice() {
    local choice=$1
    local max=$2

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$max" ]; then
        return 1
    fi

    return 0
}

# Function to validate if the specified environment is valid
validate_environment() {
    local env_to_check=$1
    local envs=("$@")

    # Remove the first argument (env_to_check) from the list
    shift
    local envs=("$@")

    for env in "${envs[@]}"; do
        if [ "$env" = "$env_to_check" ]; then
            return 0
        fi
    done
    return 1
}

echo "=== Platformio Monitor to Log ==="

environments=()
while IFS= read -r line; do
    environments+=("$line")
done < <(get_environments)

if [ ${#environments[@]} -eq 0 ]; then
    echo "Error: No environment found in platformio.ini"
    exit 1
fi

# Select environment
if [ -n "$SELECTED_ENV" ]; then
    # Validate if the specified environment is valid
    if validate_environment "$SELECTED_ENV" "${environments[@]}"; then
        selected_env="$SELECTED_ENV"
        echo "Environment specified via --env: $selected_env"
    else
        echo "Error: Environment '$SELECTED_ENV' is not valid"
        echo "Current project envs: ${environments[*]}"
        exit 1
    fi
else
    # Display menu and request user choice
    show_environment_menu "${environments[@]}"

    while true; do
        read -p "Choose environment (1-${#environments[@]}): " choice

        if validate_choice "$choice" "${#environments[@]}"; then
            selected_env="${environments[$((choice-1))]}"
            break
        else
            echo "Invalid option. Please choose a number between 1 and ${#environments[@]}."
        fi
    done
fi

# Upload project (if --no-upload was not specified)
if [ "$SKIP_UPLOAD" = false ]; then
    while true; do
        echo ""
        read -p "Do you want to upload the project? [Y]/n: " choice
        # Default to 'y' if user just presses Enter
        choice=${choice:-y}
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo "Compiling and uploading the project, may take a few seconds."
            $PLATFORMIO_BIN run -e "$selected_env" -t upload --silent
            if [ $? -ne 0 ]; then
                echo "Error: Project upload failed. Aborting!"
                exit 1
            fi
            break
        elif [[ "$choice" =~ ^[Nn]$ ]]; then
            echo "Ignoring firmware upload."
            break
        else
            echo "Invalid option. Please enter Y or n."
        fi
    done
else
    echo "Ignoring firmware upload."
fi

# Generate filename in yyyy-mm-dd-hh-mm.log format
TS="$(date +%Y-%m-%d-%H-%M)"
LOG_FILE="./logs/${selected_env}-${TS}.log"

# Create logs directory if it doesn't exist
mkdir -p logs

echo "=== Starting log collection ==="
echo "Logs will be saved to: $LOG_FILE"

if [ "$QUIET_MODE" = true ]; then
    echo "Quiet mode activated - logs only to file"
    echo "Press Ctrl+C to stop collection"
    echo

    # Start serial monitoring saving only to file
    $PLATFORMIO_BIN device monitor --quiet -e "$selected_env" > "$LOG_FILE"
else
    echo "Serial output will be displayed on terminal and saved to file"
    echo "Press Ctrl+C to stop collection"
    echo

    # Start serial monitoring with tee to display and save
    $PLATFORMIO_BIN device monitor --quiet -e "$selected_env" | tee "$LOG_FILE"
fi