# User & Group Management Script

A comprehensive Bash script for Linux systems that allows administrators to manage users and groups efficiently. Supports both interactive mode and batch CSV processing, with logging for auditing purposes.

## Features

- **User management**  
  - Create new users  
  - Delete users (with optional backup of home directories)  
  - Lock and unlock user accounts  

- **Group management**  
  - Create new groups  
  - Delete groups  
  - Add users to groups  

- **Batch processing**  
  - Read users and groups from a CSV file  
  - Automatically create missing groups  
  - Lock user passwords by default  

- **Logging**  
  - All actions are logged via `logger` with the tag `user_project`  

## Requirements

- Linux system with Bash  
- Root privileges (script re-executes with `sudo` if needed)  
- Standard Linux utilities: `useradd`, `usermod`, `groupadd`, `groupdel`, `passwd`, `tar`, `logger`  

## Installation

Clone the repository or copy the script to your desired directory:

```bash
git clone https://github.com/pkz074/user-management-script.git
cd user-management-script
chmod +x user-mng.sh
```

## Usage

### Interactive Mode

Launch the script without arguments:

```bash
sudo ./user-mng.sh
```

* Displays a menu for user and group management
* Follow the prompts to create, delete, lock/unlock users, and manage groups

### Batch Mode

Prepare a CSV file with the following format:

```text
username,group1,group2,group3
alice,dev,ops
bob,admins
charlie
# lines starting with # are ignored
```

Run the script in batch mode:

```bash
sudo ./user-mng.sh --file users.csv
```

* Creates users and groups as specified
* Adds users to the listed groups
* Skips empty lines and comments
* Locks passwords for newly created users

## Logging

All actions performed by the script are logged to the system log (`/var/log/syslog` or `journalctl`) with the tag:

```text
user_project
```

Example:

```text
Nov 20 10:45:23 hostname user-mng.sh[1234]: Created user: alice
Nov 20 10:45:23 hostname user-mng.sh[1234]: Locked password for alice
Nov 20 10:45:24 hostname user-mng.sh[1234]: Added user 'alice' to group 'dev'
```

## Notes & Best Practices

* **Username and group naming rules**:

  * Start with a lowercase letter or underscore
  * Can contain lowercase letters, digits, hyphens, or underscores
  * Maximum length: 32 characters

* **Home directory backup**: Deleting a user backs up their home to `/var/backups/user_homes`

* **CSV input**: Trailing commas and extra spaces are handled safely

## Example Workflow

1. Interactive mode:

```bash
sudo ./user-mng.sh
```

* Select “Create User”
* Enter `alice`
* Set password

2. Batch mode:

```bash
sudo ./user-mng.sh --file users.csv
```

* Creates `alice`, `bob`, and `charlie`
* Creates missing groups `dev`, `ops`, `admins`
* Locks all new accounts

## License

This project is provided under the MIT License.
