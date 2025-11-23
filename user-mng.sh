#!/bin/bash
set -u
set -o pipefail

LOG_TAG="user_project"
BACKUP_DIR="/var/backups/user_homes"
USER_REGEX='^[a-z_][a-z0-9_-]{0,31}$'

if [ "$EUID" -ne 0 ]; then
    echo "Script must run as root. Re-executing with sudo"
    exec sudo "$0" "$@"
fi

log_action(){
    local message="$1"
   
    logger -t "$LOG_TAG" -p user.info "$message" 2>/dev/null
    echo ">> $message"
}

pause_prompt() {
    read -p "Press Enter to continue..."
}

validate_groupname() {
    local groupname="$1"
    if [ ${#groupname} -lt 1 ] || [ ${#groupname} -gt 32 ]; then
        return 1
    fi

    if ! [[ "$groupname" =~ $USER_REGEX ]]; then
        return 1
    fi
    return 0
}

create_user(){
    read -p "Enter new username: " username
    username=$(echo "$username" | xargs)

    if ! [[ "$username" =~ $USER_REGEX ]]; then
        echo "Error: Invalid username format (must start with letter/_, max 32 chars)."
        pause_prompt
        return 1
    fi

    if id "$username" &>/dev/null; then
        echo "Error: User '$username' already exists."
        pause_prompt
        return 1
    fi

    local error_msg
    if ! error_msg=$(useradd -m -s /bin/bash "$username" 2>&1); then
        echo "Error: Failed to create user. Details: $error_msg"
        pause_prompt
        return 1
    fi

    log_action "Created user: $username"

    echo "Set initial password:"
    if ! passwd "$username"; then
        echo "Warning: Password setup failed."
        log_action "Password set failed for $username"
    else
        log_action "Password set for $username"
    fi

    pause_prompt
}

delete_user(){
    read -p "Enter username to delete: " username
    username=$(echo "$username" | xargs)

    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist."
        pause_prompt
        return 1
    fi

    echo "WARNING: This will delete user '$username'"
    read -p "Are you sure? (y/n): " confirm
    if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled"
        pause_prompt
        return 1
    fi

    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        echo "Warning: Could not create backup directory."
        read -p "Continue without backup? (y/n): " continue_no_backup
        if ! [[ "$continue_no_backup" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            pause_prompt
            return 1
        fi
    fi

    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)

    if [ -d "$home_dir" ]; then
        local backup_file="$BACKUP_DIR/$username-$(date +%F-%T).tar.gz"
        echo "Backing up home directory to $backup_file"
        
        local backup_error
        if backup_error=$(tar -czf "$backup_file" -C / "${home_dir#/}" 2>&1); then
            log_action "Backed up $home_dir to $backup_file"
        else
            echo "Warning: Backup failed. Details: $backup_error"
            read -p "Continue anyway? (y/n): " continue_anyway
            if ! [[ "$continue_anyway" =~ ^[Yy]$ ]]; then
                echo "Operation cancelled."
                pause_prompt
                return 1
            fi
        fi
    fi

    local del_error
    if del_error=$(userdel -r "$username" 2>&1); then
        log_action "Deleted user '$username'"
    else
        echo "Error: Failed to delete user. Details: $del_error"
    fi

    pause_prompt
}

modify_user() {
    read -p "Enter username to modify: " username
    username=$(echo "$username" | xargs)

    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist"
        pause_prompt
        return 1
    fi

    echo "--- Modify User: $username ---"
    echo "1) Change Password"
    echo "2) Change Shell"
    echo "3) Change Full Name"
    echo "4) Cancel"
    read -p "Select option: " mod_choice

    case "$mod_choice" in
        1)
            if passwd "$username"; then
                log_action "Password modified for $username"
            else
                echo "Error: Password change failed."
            fi
            ;;
        2)
            read -p "Enter new shell: " new_shell
            new_shell=$(echo "$new_shell" | xargs)
            # FIX: Check against /etc/shells for security
            if [ -f "$new_shell" ] && [ -x "$new_shell" ] && grep -qx "$new_shell" /etc/shells 2>/dev/null; then
                usermod -s "$new_shell" "$username"
                log_action "Shell changed for $username"
            else
                echo "Error: Invalid shell (must be executable and listed in /etc/shells)"
            fi
            ;;
        3)
            read -p "Enter new full name: " new_name
            usermod -c "$new_name" "$username"
            log_action "Name changed for $username"
            ;;
        4) return 0 ;;
        *) echo "Invalid option" ;;
    esac
    pause_prompt
}

list_users() {
    echo "== System Users =="
    printf "%-15s | %-6s | %-20s | %-15s\n" "Username" "UID" "Home Directory" "Shell"
    echo "------------------------------------------------------------------"

    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {printf "%-15s | %-6s | %-20s | %-15s\n", $1, $3, $6, $7}' | sort
    
    echo "------------------------------------------------------------------"
    pause_prompt
}

lock_user(){
    read -p "Username to lock: " username
    username=$(echo "$username" | xargs)
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist."
        pause_prompt
        return 1
    fi

    if passwd -S "$username" 2>/dev/null | grep -q " L "; then
        echo "Warning: User already locked."
        pause_prompt
        return 0
    fi

    local lock_error
    if lock_error=$(usermod -L "$username" 2>&1); then
        log_action "Locked: $username"
    else
        echo "Error locking user. Details: $lock_error"
    fi
    pause_prompt
}

unlock_user(){
    read -p "Username to unlock: " username
    username=$(echo "$username" | xargs)
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist."
        pause_prompt
        return 1
    fi

    if passwd -S "$username" 2>/dev/null | grep -q " P "; then
        echo "Warning: User already unlocked."
        pause_prompt
        return 0
    fi

    local unlock_error
    if unlock_error=$(usermod -U "$username" 2>&1); then
        log_action "Unlocked: $username"
    else
        echo "Error unlocking user. Details: $unlock_error"
    fi
    pause_prompt
}

create_group(){
    read -p "Enter new group name: " groupname
    groupname=$(echo "$groupname" | xargs)

    if ! validate_groupname "$groupname"; then
        echo "Error: Invalid group name."
        pause_prompt
        return 1
    fi

    if getent group "$groupname" &>/dev/null; then
        echo "Error: Group already exists."
        pause_prompt
        return 1
    fi

    local grp_error
    if grp_error=$(groupadd "$groupname" 2>&1); then
        log_action "Created group: $groupname"
    else
        echo "Error creating group. Details: $grp_error"
    fi
    pause_prompt
}

delete_group(){
    read -p "Enter group to delete: " groupname
    groupname=$(echo "$groupname" | xargs)

    if ! getent group "$groupname" &>/dev/null; then
        echo "Error: Group does not exist."
        pause_prompt
        return 1
    fi

    local users_with_group
    users_with_group=$(getent passwd | awk -F: -v gid="$(getent group "$groupname" | cut -d: -f3)" '$4 == gid {print $1}')
    
    if [ -n "$users_with_group" ]; then
        echo "Warning: Primary group for users: $users_with_group"
        read -p "Continue? (y/n): " confirm
        if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            pause_prompt
            return 0
        fi
    fi

    local cmd_output
    if cmd_output=$(groupdel "$groupname" 2>&1); then
        log_action "Deleted group: $groupname"
    else
        echo "Error deleting group. Details: $cmd_output"
    fi
    pause_prompt
}

add_user_group() {
    read -p "Enter username: " username
    username=$(echo "$username" | xargs)
    read -p "Enter group name: " groupname
    groupname=$(echo "$groupname" | xargs)

    if ! id "$username" &>/dev/null; then
        echo "Error: User does not exist."
        pause_prompt
        return 1
    fi
    if ! getent group "$groupname" &>/dev/null; then
        echo "Error: Group does not exist."
        pause_prompt
        return 1
    fi

    if groups "$username" 2>/dev/null | grep -qw "$groupname"; then
        echo "Warning: User already in group."
        pause_prompt
        return 0
    fi

    local add_error
    if add_error=$(usermod -aG "$groupname" "$username" 2>&1); then
        log_action "Added $username to $groupname"
    else
        echo "Error adding user to group. Details: $add_error"
    fi
    pause_prompt
}

process_user_file() {
    local input_file="$1"
    local line_num=0

    echo "Starting batch process from $input_file"

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue

        IFS=',' read -r username rest <<< "$line"
        username=$(echo "$username" | xargs)
        IFS=',' read -ra group_array <<< "$rest"

        if [ -z "$username" ]; then
            echo "Line $line_num: Missing username"
            continue
        fi

        if ! [[ "$username" =~ $USER_REGEX ]]; then
            echo "Line $line_num: Invalid username format"
            continue
        fi

        if ! id "$username" &>/dev/null; then
            local create_error
            if create_error=$(useradd -m -s /bin/bash "$username" 2>&1); then
                log_action "Batch created: $username"
                passwd -l "$username" &>/dev/null
            else
                echo "Line $line_num: Error creating $username. Details: $create_error"
                continue
            fi
        fi

        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs)
            [ -z "$group" ] && continue

            if ! validate_groupname "$group"; then
                echo "Line $line_num: Invalid group $group"
                continue
            fi

            if ! getent group "$group" &>/dev/null; then
                local grp_create_error
                if grp_create_error=$(groupadd "$group" 2>&1); then
                    log_action "Batch created group: $group"
                else
                    echo "Line $line_num: Error creating group $group. Details: $grp_create_error"
                    continue
                fi
            fi

            local add_grp_error
            if add_grp_error=$(usermod -aG "$group" "$username" 2>&1); then
                echo " - Added to $group"
            else
                echo "Line $line_num: Error adding to $group. Details: $add_grp_error"
            fi
        done

    done < "$input_file"

    log_action "Batch complete"
}

batch_process(){
    local input_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                if [ -z "${2:-}" ]; then 
                    echo "Error: Option '$1' requires a file argument."
                    exit 1
                fi
                input_file="$2"
                shift 2 
                ;;
            *)
                echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$input_file" ] || [ ! -r "$input_file" ]; then
        echo "Error: Valid --file required"
        exit 1
    fi

    process_user_file "$input_file"
}

main_menu(){
    while true; do
        clear
        echo "=========================================="
        echo " User & Group Management System"
        echo "=========================================="
        echo "1) Create User"
        echo "2) Delete User"
        echo "3) Modify User"
        echo "4) List Users"
        echo "5) Lock User"
        echo "6) Unlock User"
        echo "7) Create Group"
        echo "8) Delete Group"
        echo "9) Add User to Group"
        echo "0) Exit"
        echo "=========================================="
        read -p "Enter choice: " choice

        case "$choice" in
            1) create_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) list_users ;;
            5) lock_user ;;
            6) unlock_user ;;
            7) create_group ;;
            8) delete_group ;;
            9) add_user_group ;;
            0) log_action "Exit"; exit 0 ;;
            *) echo "Invalid option"; pause_prompt ;;
        esac
    done
}

log_action "Script started"

if [ $# -gt 0 ]; then
    batch_process "$@"
else
    main_menu
fi
