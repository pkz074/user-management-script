#!/bin/bash
set -e
set -u
set -o pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Script must run as root. Re-executing with sudo"
    exec sudo "$0" "$@"
fi

LOG_TAG="user_project"

log_action() {
    local message="$1"
    logger -t "$LOG_TAG" -p user.info "$message"
    echo "$message"
}

create_user() {
    read -p "Enter your username: " username

    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo -e "\nError: Invalid name format"
        echo "Username must start with a lowercase letter and contain only a-z, 0-9, underscores, or hyphens"
        read -p "Press Enter to continue"
        return 1
    fi

    if id "$username" &>/dev/null; then
        echo -e "\nError: User '$username' already exists"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(useradd -m -s /bin/bash "$username" 2>&1); then
        echo -e "\nError: Failed to create user"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully created user: $username"
    echo -e "\nNow set password"

    if ! passwd "$username"; then
        echo -e "\nWarning: Failed to set password"
        echo "The account is created but locked"
        log_action "Created user $username (password set FAILED)"
    else
        log_action "Successfully set password for $username"
    fi

    read -p "Press Enter to continue"
    return 0
}

delete_user() {
    read -p "Enter username to delete: " username
    if ! id "$username" &>/dev/null; then
        echo -e "\nError: User '$username' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    echo -e "\nWARNING: This will permanently delete the user '$username' and back up their home directory"
    read -p "Are you absolutely sure? (y/n): " confirm
    if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled"
        read -p "Press enter to continue"
        return 1
    fi

    local backup_dir="/var/backups/user_homes"
    mkdir -p "$backup_dir"
    local home_dir
    home_dir=$(grep "^$username:" /etc/passwd | cut -d: -f6)

    if [ -d "$home_dir" ]; then
        local backup_file="$backup_dir/$username-$(date +%F-%T).tar.gz"
        echo "Backing up $home_dir to $backup_file"
        if ! tar -czf "$backup_file" -C / "${home_dir#/}" 2>&1; then
            echo "\nWarning: Couldn't back up home dir, not deleting user"
            read -p "Press Enter to continue"
            return 1
        fi
        log_action "Backed up $home_dir to $backup_file"
    else
        echo "No home dir found at $home_dir, skipping backup"
    fi

    local error_msg
    if ! error_msg=$(userdel -r "$username" 2>&1); then
        echo -e "\nError: Failed to delete user"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully deleted user '$username' and their home dir"
    read -p "Press Enter to continue"
    return 0
}

lock_user() {
    read -p "Username to lock: " username
    if ! id "$username" &>/dev/null; then
        echo -e "\nError: User '$username' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(usermod -L "$username" 2>&1); then
        echo -e "\nError: Failed to lock account"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully locked account for user '$username'"
    echo "Account for '$username' is now locked."
    return 0
}

unlock_user() {
    read -p "Enter username to unlock: " username
    if ! id "$username" &>/dev/null; then
        echo -e "\nError: User '$username' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(usermod -U "$username" 2>&1); then
        echo -e "\nError: Failed to unlock account"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully unlocked account for user '$username'"
    echo "Account for '$username' is now unlocked"
    read -p "Press Enter to continue"
    return 0
}

create_group() {
    read -p "Enter new group name: " groupname
    if ! [[ "$groupname" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo -e "\nError: Invalid group name format"
        read -p "Press Enter to continue"
        return 1
    fi

    if getent group "$groupname" &>/dev/null; then
        echo -e "\nError: Group '$groupname' already exists"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(groupadd "$groupname" 2>&1); then
        echo -e "\nError: Failed to create group"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully created group: $groupname"
    echo "Group '$groupname' created"
    read -p "Press Enter to continue"
    return 0
}

delete_group() {
    read -p "Enter your group name to delete: " groupname
    if ! getent group "$groupname" &>/dev/null; then
        echo -e "\nError: Group '$groupname' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    read -p "Sure you want to delete the group '$groupname'? (y/n): " confirm
    if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(groupdel "$groupname" 2>&1); then
        echo -e "\nError: Failed to delete group"
        echo "Details: $error_msg"
        echo "You often can't delete a group if it's the primary group for any user"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully deleted group: $groupname"
    echo "Group '$groupname' deleted"
    read -p "Press Enter to continue"
    return 0
}

add_user_group() {
    read -p "Enter username: " username
    if ! id "$username" &>/dev/null; then
        echo -e "\nError: User '$username' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    read -p "Enter group name to add user to: " groupname
    if ! getent group "$groupname" &>/dev/null; then
        echo -e "\nError: Group '$groupname' doesn't exist"
        read -p "Press Enter to continue"
        return 1
    fi

    local error_msg
    if ! error_msg=$(usermod -aG "$groupname" "$username" 2>&1); then
        echo -e "\nError: Failed to add user to group"
        echo "Details: $error_msg"
        read -p "Press Enter to continue"
        return 1
    fi

    log_action "Successfully added user '$username' to group '$groupname'"
    echo "User '$username' added to group '$groupname'"
    return 0
}

batch_process() {
    local input_file=""
    TEMP=$(getopt -o f: --long file: -n 'manage.sh' -- "$@")
    if [ $? -ne 0 ]; then
        echo "Error: Invalid argument" >&2
        exit 1
    fi
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -f | --file)
                input_file="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Internal error"
                exit 1
                ;;
        esac
    done

    if [ -z "$input_file" ]; then
        echo "Error: --file <filename> is required for batch mode"
        return 1
    fi

    if [ ! -r "$input_file" ]; then
        echo "Error: File '$input_file' not found or not readable"
        return 1
    fi

    process_user_file "$input_file"
}

process_user_file() {
    local input_file="$1"
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        IFS=',' read -r username rest <<< "$line"
        IFS=',' read -ra group_array <<< "$rest"

        if [ -z "$username" ]; then
            echo "Skipping line $line_num: No username found"
            continue
        fi

        echo "Processing $username"

        if id "$username" &>/dev/null; then
            echo "User '$username' already exists, skipping"
        else
            if useradd -m -s /bin/bash "$username"; then
                log_action "Created user: $username"
                passwd -l "$username" &>/dev/null
                log_action "Locked password for $username"
            else
                echo "Error creating $username, skipping"
                continue
            fi
        fi

        for group in "${group_array[@]}"; do
            if [ -n "$group" ]; then
                if ! getent group "$group" &>/dev/null; then
                    echo "Group '$group' not found, creating"
                    groupadd "$group"
                    log_action "Created group: $group"
                fi
                usermod -aG "$group" "$username" &>/dev/null
                log_action "Added user '$username' to group '$group'"
            fi
        done
    done < "$input_file"
    echo "Batch processing complete"
}

main_menu() {
    while true; do
        clear
        echo "==== User Functions ===="
        echo "1) Create User"
        echo "2) Delete User"
        echo "3) Lock User Account"
        echo "4) Unlock User Account"
        echo "==== Group Functions ===="
        echo "5) Create Group"
        echo "6) Delete Group"
        echo "7) Add User to Group"
        echo "9) Exit"

        read -p "Enter your choice: " choice
        case "$choice" in
            1) create_user ;;
            2) delete_user ;;
            3) lock_user ;;
            4) unlock_user ;;
            5) create_group ;;
            6) delete_group ;;
            7) add_user_group ;;
            9)
                log_action "Exiting"
                echo "Bye bye"
                break
                ;;
            *) echo "Invalid option, try again"; read -p "Press enter to continue" ;;
        esac
    done
}

log_action "User management script started"

if [ $# -eq 0 ]; then
    log_action "Started in interactive mode"
    main_menu
else
    log_action "Started in batch mode"
    batch_process "$@"
fi
