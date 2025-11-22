#!/bin/bash
set -u
set -o pipefail

LOG_TAG="user_project"
BACKUP_DIR="/var/backups/user_homes"

if [ "$EUID" -ne 0 ]; then
    echo "Script must run as root. Re-executing with sudo"
    exec sudo "$0" "$@"
fi

log_action(){
    local message="$1"
    logger -t "$LOG_TAG" -p user.info "$message"
    echo ">> $message"
}

pause_prompt() {
    read -p "Press Enter to continue..."
}

# Create a new user
create_user(){
    read -p "Enter new username: " username

    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Error: Invalid username format."
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

# Delete a user with optional backup
delete_user(){
    read -p "Enter username to delete: " username

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

    mkdir -p "$BACKUP_DIR"
    home_dir=$(grep "^$username:" /etc/passwd | cut -d: -f6)

    if [ -d "$home_dir" ]; then
        backup_file="$BACKUP_DIR/$username-$(date +%F-%T).tar.gz"
        echo "Backing up home directory to $backup_file"
        if tar -czf "$backup_file" -C / "${home_dir#/}" 2>/dev/null; then
            log_action "Backed up $home_dir to $backup_file"
        else
            echo "Warning: Backup failed."
        fi
    fi

    if userdel -r "$username" 2>/dev/null; then
        log_action "Deleted user '$username'"
    else
        echo "Error: Failed to delete user"
    fi

    pause_prompt
}

# Modify password, shell, or name
modify_user() {
    read -p "Enter username to modify: " username

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
            passwd "$username"
            log_action "Password modified for $username"
            ;;
        2)
            read -p "Enter new shell: " new_shell
            if [ -x "$new_shell" ]; then
                usermod -s "$new_shell" "$username"
                log_action "Shell changed for $username"
            else
                echo "Error: Invalid shell"
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

# List regular users
list_users() {
    echo "== System Users =="
    printf "%-15s | %-6s | %-20s | %-15s\n" "Username" "UID" "Home Directory" "Shell"
    echo "------------------------------------------------------------------"

    awk -F: '$3 >= 1000 && $1 != "nobody" {printf "%-15s | %-6s | %-20s | %-15s\n", $1, $3, $6, $7}' /etc/passwd

    echo "------------------------------------------------------------------"
    pause_prompt
}

# Lock user account
lock_user(){
    read -p "Username to lock: " username
    if usermod -L "$username" 2>/dev/null; then
        log_action "Locked: $username"
    else
        echo "Error locking user."
    fi
    pause_prompt
}

# Unlock user account
unlock_user(){
    read -p "Username to unlock: " username
    if usermod -U "$username" 2>/dev/null; then
        log_action "Unlocked: $username"
    else
        echo "Error unlocking user"
    fi
    pause_prompt
}

# Create group
create_group(){
    read -p "Enter new group name: " groupname
    if groupadd "$groupname" 2>/dev/null; then
        log_action "Created group: $groupname"
    else
        echo "Error creating group"
    fi
    pause_prompt
}

# Delete group
delete_group(){
    read -p "Enter group to delete: " groupname
    if groupdel "$groupname" 2>/dev/null; then
        log_action "Deleted group: $groupname"
    else
        echo "Error deleting group"
    fi
    pause_prompt
}

# Add user to group
add_user_group() {
    read -p "Enter username: " username
    read -p "Enter group name: " groupname

    if usermod -aG "$groupname" "$username" 2>/dev/null; then
        log_action "Added $username to $groupname"
    else
        echo "Error adding user to group"
    fi
    pause_prompt
}

# Batch process CSV user creation
process_user_file() {
    local input_file="$1"
    local line_num=0

    echo "Starting batch process from $input_file"

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue

        IFS=',' read -r username rest <<< "$line"
        IFS=',' read -ra group_array <<< "$rest"

        if [ -z "$username" ]; then
            echo "Line $line_num: Missing username"
            continue
        fi

        if ! id "$username" &>/dev/null; then
            if useradd -m -s /bin/bash "$username"; then
                log_action "Batch created: $username"
                passwd -l "$username" &>/dev/null
            else
                echo "Error creating $username."
                continue
            fi
        fi

        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs)
            [ -z "$group" ] && continue

            if ! getent group "$group" &>/dev/null; then
                groupadd "$group"
                log_action "Batch created group: $group"
            fi

            usermod -aG "$group" "$username"
            echo "  - Added to $group"
        done

    done < "$input_file"

    log_action "Batch complete"
}

batch_process(){
    local input_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                input_file="$2"
                shift; shift ;;
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
        echo "   User & Group Management System"
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
