#!/bin/bash

VERSION="8.0.0"
LOG_DIR="./log_find"
SEARCH_STRING_FILE="search_string"
LOG_FILE="$LOG_DIR/log_find_$(date '+%Y%m%d_%H-%M-%S').log"
VERBOSE=0
MAX_FILES=2
MAX_DURATION=$((2 * 60))
DELETE_FILES=0
TIME_FILTER_MINUTES=0
DATE_FILTER=""
PRINT_MATCHES=0
UNINSTALL=0
SCRIPT_NAME=$(basename "$0")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;35m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

log_message() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local message="$timestamp [$SCRIPT_NAME] $1"
  echo "$message" | tee -a "$LOG_FILE" >/dev/null
}

print_message() {
  local color=$1
  local message=$2
  local log_level=${3:-INFO}
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo "$timestamp [$SCRIPT_NAME] $log_level: $message" >> "$LOG_FILE"
  
  case $color in
    red)    echo -e "${RED}$message${NC}" ;;
    green)  echo -e "${GREEN}$message${NC}" ;;
    yellow) echo -e "${YELLOW}$message${NC}" ;;
    cyan)   echo -e "${CYAN}$message${NC}" ;;
    blue)   echo -e "${BLUE}$message${NC}" ;;
    *)      echo "$message" ;;
  esac
}

print_header() {
  echo -e "${BLUE}"
  echo "===================================================================="
  echo " LogHound v$VERSION - Advanced Log Search Utility"
  echo "===================================================================="
  echo -e "${NC}"
}

print_footer() {
  echo -e "${BLUE}"
  echo "===================================================================="
  echo " LogHound completed. Search results in: $LOG_FILE"
  echo "===================================================================="
  echo -e "${NC}"
}

print_section() {
  local title=$1
  echo -e "${CYAN}"
  echo "===================================================================="
  echo " $title"
  echo "===================================================================="
  echo -e "${NC}"
}

install_script() {
  print_section "Installation Started"
  
  for file2 in search_string ims_string startUp_string; do
    if [[ ! -f "$file2" ]]; then
      touch "$file2"
      print_message green "[SUCCESS] Created file: $file2"
    else
      print_message yellow "File already exists: $file2"
    fi
  done

  print_message cyan "Please put the strings you want to search in the target file(s) into search_string, ims_string, and startUp_string."

  if [[ $EUID -ne 0 ]]; then
    print_message red "You must be root to create symlinks in /usr/local/bin. Please run with sudo."
    exit 1
  fi

  script_path=$(realpath "$0")
  ln -sf "$script_path" /usr/local/bin/LogHound
  print_message green "[SUCCESS] Created symlink: /usr/local/bin/LogHound -> $script_path"

  for file in search_string ims_string startUp_string; do
    if [[ -f "$file" ]]; then
      ln -sf "$(realpath "$file")" "/root/$file"
      print_message green "[SUCCESS] Created symlink: /root/$file -> $(realpath "$file")"
    else
      print_message red "Error: File $file not found."
    fi
  done

  print_message green "Installation complete. You can now run 'LogHound' from any directory."
  exit 0
}

uninstall_script() {
  print_section "Uninstallation Started"
  
  if [[ -L "/usr/local/bin/LogHound" ]]; then
    rm -f "/usr/local/bin/LogHound"
    print_message green "[SUCCESS] Removed symlink: /usr/local/bin/LogHound"
  fi

  for file in search_string ims_string startUp_string; do
    if [[ -L "/root/$file" ]]; then
      rm -f "/root/$file"
      print_message green "[SUCCESS] Removed symlink: /root/$file"
    fi
  done

  if [[ -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"
    print_message green "[SUCCESS] Removed log directory: $LOG_DIR"
  fi

  print_message green "Uninstallation complete. All symlinks and logs removed."
  exit 0
}

escape_regex() {
  echo "$1" | sed -e 's/[]\/$*.^|[]/\\&/g' -e 's/[(){}?+]/\\&/g'
}

search_in_files() {
  local search_string=$(escape_regex "$1")
  local file="$2"
  local match_count=0
  local regex_pattern=$(echo "$search_string" | sed 's/*/.*/g')

  if [[ "$VERBOSE" -eq 1 || "$PRINT_MATCHES" -eq 1 ]]; then
    echo "===== START OF FILE: $file =====" >> "$LOG_FILE"
  fi

  if [[ "$file" == *.gz ]]; then
    if [[ "$VERBOSE" -eq 1 || "$PRINT_MATCHES" -eq 1 ]]; then
      matches=$(zgrep -ia -E -n "$regex_pattern" "$file")
      match_count=$(echo "$matches" | grep -c '[^[:space:]]')
      if [[ "$match_count" -gt 0 ]]; then
        log_message "Found $match_count matches for '$search_string' in $file"
        if [[ "$PRINT_MATCHES" -eq 1 ]]; then
          echo "$matches" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)
            echo "$line_num | $line_content" >> "$LOG_FILE"
            print_message red "Line $line_num:" 
            echo "     $line_content"
          done
        else
          zgrep -ia -E "$regex_pattern" "$file" >> "$LOG_FILE"
        fi
      fi
    else
      match_count=$(zgrep -ia -E "$regex_pattern" "$file" | wc -l)
    fi
  elif [[ "$file" == *.tar.gz || "$file" == *.tgz ]]; then
    if [[ "$VERBOSE" -eq 1 || "$PRINT_MATCHES" -eq 1 ]]; then
      matches=$(tar -xzf "$file" -O | grep -ia -E -n "$regex_pattern")
      match_count=$(echo "$matches" | grep -c '[^[:space:]]')
      if [[ "$match_count" -gt 0 ]]; then
        log_message "Found $match_count matches for '$search_string' in $file"
        if [[ "$PRINT_MATCHES" -eq 1 ]]; then
          echo "$matches" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)
            echo "$line_num | $line_content" >> "$LOG_FILE"
            print_message red "Line $line_num:" 
            echo "     $line_content"
          done
        else
          tar -xzf "$file" -O | grep -ia -E "$regex_pattern" >> "$LOG_FILE"
        fi
      fi
    else
      match_count=$(tar -xzf "$file" -O | grep -ia -E "$regex_pattern" | wc -l)
    fi
  else
    if [[ "$VERBOSE" -eq 1 || "$PRINT_MATCHES" -eq 1 ]]; then
      matches=$(grep -ia -E -n "$regex_pattern" "$file")
      match_count=$(echo "$matches" | grep -c '[^[:space:]]')
      if [[ "$match_count" -gt 0 ]]; then
        log_message "Found $match_count matches for '$search_string' in $file"
        if [[ "$PRINT_MATCHES" -eq 1 ]]; then
          echo "$matches" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)
            echo "$line_num | $line_content" >> "$LOG_FILE"
            print_message red "Line $line_num:" 
            echo "     $line_content"
          done
        else
          grep -ia -E "$regex_pattern" "$file" >> "$LOG_FILE"
        fi
      fi
    else
      match_count=$(grep -ia -E "$regex_pattern" "$file" | wc -l)
    fi
  fi

  if [[ "$VERBOSE" -eq 1 || "$PRINT_MATCHES" -eq 1 ]]; then
    echo "===== END OF FILE: $file =====" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
  fi

  echo "$match_count"
}

cleanup() {
  log_message "Script terminated. Cleaning up..."
  exit 0
}

trap cleanup SIGINT SIGTERM

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -s, --search-file <file>    Specify file containing search strings (default: search_string)"
  echo "  -f, --file <file>           Search in a single file"
  echo "  -d, --directory <dir>       Search in all files in a directory"
  echo "  -m, --multiple <file1>...   Search in multiple files"
  echo "  -t, --time <minutes>        Process files modified in last X minutes"
  echo "      --date <pattern>        Process files with date pattern in names (yyyymmdd[hh[mm[ss]])"
  echo "  -vvv, --verbose             Print lines from target files in log file"
  echo "      --print                 Log matching lines with line numbers"
  echo "      --delete                Delete all log_find directories/files"
  echo "      --install               Install script and create required files"
  echo "      --uninstall             Remove all symlinks and log files"
  echo "  -h, --help                  Show this help message"
  echo
  echo "Examples:"
  echo "  $0 -vvv /var/log            # Search in /var/log and Print lines in log file"
  echo "  $0 -f app.log               # Search in app.log file"
  echo "  $0 -t 30                    # Search in files modified in last 30 minutes"
  echo "  $0 --date 20230101          # Search in files with '20230101' in name"
  echo
}

prompt_no_args() {
  print_header
  usage
  echo -e "${YELLOW}Do you really want to execute the script without any option? (yes/no)${NC}"
  read -p "" answer
  
  answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  
  if [[ "$answer" != "yes" ]]; then
    print_message yellow "Terminating execution..."
    exit 0
  fi
  
  print_message yellow "Proceeding with default execution..."
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -vvv|--verbose)
      VERBOSE=1
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters
set -- "${POSITIONAL[@]}"

# Second pass to handle other arguments
if [[ $# -eq 0 ]]; then
  prompt_no_args
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install)
        install_script
        ;;
      --delete)
        DELETE_FILES=1
        shift
        ;;
      -t|--time)
        if [[ -z "$2" ]]; then
          print_message red "Option -t requires an argument" >&2
          usage
          exit 1
        fi
        TIME_FILTER_MINUTES="$2"
        shift 2
        ;;
      --date)
        if [[ -z "$2" ]]; then
          print_message red "Option --date requires an argument" >&2
          usage
          exit 1
        fi
        DATE_FILTER="$2"
        shift 2
        ;;
      --print)
        PRINT_MATCHES=1
        shift
        ;;
      --uninstall)
        UNINSTALL=1
        shift
        ;;
      -s|--search-file)
        if [[ -z "$2" ]]; then
          print_message red "Option -s requires an argument" >&2
          usage
          exit 1
        fi
        SEARCH_STRING_FILE="$2"
        shift 2
        ;;
      -f|--file)
        if [[ -z "$2" ]]; then
          print_message red "Option -f requires an argument" >&2
          usage
          exit 1
        fi
        TARGET_FILES=("$2")
        shift 2
        ;;
      -d|--directory)
        if [[ -z "$2" ]]; then
          print_message red "Option -d requires an argument" >&2
          usage
          exit 1
        fi
        SEARCH_DIRS=("$2")
        TARGET_FILES=$(find "${SEARCH_DIRS[@]}" -type f \( -name "*.log" -o -name "*.gz" -o -name "*.tar.gz" -o -name "*.tgz" \))
        shift 2
        ;;
      -m|--multiple)
        shift
        if [[ $# -eq 0 ]]; then
          print_message red "Option -m requires at least one file argument" >&2
          usage
          exit 1
        fi
        TARGET_FILES=("$@")
        break
        ;;
      -h|--help)
        print_header
        usage
        exit 0
        ;;
      *)
        print_message red "Invalid option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
fi

print_header

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_script
fi

if [[ $# -eq 0 && -z "${TARGET_FILES[@]}" && -z "${SEARCH_DIRS[@]}" ]]; then
  SEARCH_DIRS=("/data/storage/log")
  TARGET_FILES=$(find "${SEARCH_DIRS[@]}" -type f \( -name "IMS*.log" -o -name "IMS*.gz" -o -name "IMS*.tar.gz" -o -name "IMS*.tgz" \) -printf '%T+ %p\n' | sort -r | head -n $MAX_FILES | cut -d' ' -f2-)
fi

if [[ "$TIME_FILTER_MINUTES" -gt 0 ]]; then
  if [[ -z "${SEARCH_DIRS[@]}" ]]; then
    SEARCH_DIRS=(".")
  fi
  TARGET_FILES=$(find "${SEARCH_DIRS[@]}" -type f \( -name "*.log" -o -name "*.gz" -o -name "*.tar.gz" -o -name "*.tgz" \) -mmin -"$TIME_FILTER_MINUTES")
fi

if [[ -n "$DATE_FILTER" ]]; then
  if [[ -z "${SEARCH_DIRS[@]}" ]]; then
    SEARCH_DIRS=(".")
  fi
  TARGET_FILES=$(find "${SEARCH_DIRS[@]}" -type f \( -name "*.log" -o -name "*.gz" -o -name "*.tar.gz" -o -name "*.tgz" \) -name "*$DATE_FILTER*")
fi

log_message "Starting string search script"

if [[ ! -f "$SEARCH_STRING_FILE" ]]; then
  print_message red "Error: Search string file '$SEARCH_STRING_FILE' not found. Please install the script first and place your keywords in '$SEARCH_STRING_FILE'."
  exit 1
fi

START_TIME=$(date +%s)

if [[ "$DELETE_FILES" -eq 1 ]]; then
  print_section "File Deletion Started"
  log_message "Starting deletion of folders named 'log_find' or files matching 'log_find'"
  
  find / -type d -name "*log_find*" -exec rm -rf {} + 2>/dev/null
  print_message green "Deleted folders named 'log_find'"
  log_message "Deleted folders named 'log_find'"

  find / -type f -name "*log_find*" -exec rm -f {} + 2>/dev/null
  print_message green "Deleted files matching 'log_find' in their names"
  log_message "Deleted files matching 'log_find' in their names"

  print_message green "Deletion completed"
  log_message "Deletion completed"
  exit 0
fi

while IFS= read -r search_string; do
  if [[ -z "$search_string" ]]; then
    continue
  fi

  print_section "Searching for: '$search_string'"

  for file in ${TARGET_FILES[@]}; do
    if [[ -f "$file" ]]; then
      match_count=$(search_in_files "$search_string" "$file")
      if [[ "$match_count" -gt 0 ]]; then
        print_message green "O Found '$search_string' $match_count times in $file"
      else
        print_message yellow "X '$search_string' not found in $file"
      fi
    else
      print_message red "Error: File '$file' not found."
    fi

    CURRENT_TIME=$(date +%s)
    if [[ -z "${TARGET_FILES[@]}" && -z "${SEARCH_DIRS[@]}" && $((CURRENT_TIME - START_TIME)) -ge $MAX_DURATION ]]; then
      log_message "Script execution time exceeded $MAX_DURATION seconds. Exiting..."
      print_message yellow "Script execution time exceeded. Exiting..."
      exit 0
    fi
  done
done < "$SEARCH_STRING_FILE"

print_footer
exit 0