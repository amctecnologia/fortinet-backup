# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible project for automated backup of FortiGate firewall configurations without FortiManager. Uses the `fortinet.fortios` collection to connect to each device via REST API token, save `.conf` files locally, and purge backups older than the configured retention period.

## Key Commands

### Setup

```bash
# Create and activate Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Ansible and the Fortinet collection
pip install ansible
ansible-galaxy collection install -r requirements.yml
```

### Running Backups

```bash
# All devices (interactive vault password prompt)
ansible-playbook playbooks/backup-fortigate.yml --ask-vault-pass

# All devices (vault password file)
ansible-playbook playbooks/backup-fortigate.yml --vault-password-file ~/.secure/.vault_pass

# Single device
ansible-playbook playbooks/backup-fortigate.yml --vault-password-file ~/.secure/.vault_pass --limit fw-matriz
```

### Credential Management

```bash
# Create encrypted token file for a new host
ansible-vault create host_vars/<hostname>.yml

# Edit existing encrypted token file
ansible-vault edit host_vars/<hostname>.yml

# View without editing
ansible-vault view host_vars/<hostname>.yml
```

### Automated Execution (cron)

The script at `scripts/run-backup.sh` is used for unattended cron execution. It activates the venv automatically if present at `$PROJECT_DIR/venv` and appends output to the daily log file.

```
0 2 * * * /opt/fortigate-backup/scripts/run-backup.sh --vault-password-file /home/usuario/.secure/.vault_pass
```

## Architecture

### Data Flow

1. `inventory/fortigates.yml` — defines hosts with `ansible_host` (IP) and `fortios_version`
2. `group_vars/fortigates.yml` — sets `httpapi` connection parameters for the entire group
3. `host_vars/<hostname>.yml` — holds the vault-encrypted `fortios_access_token` per device
4. `config.yml` — operational settings (`backup_base_path`, `log_base_path`, `retention_days`, `create_host_folder`)
5. `playbooks/backup-fortigate.yml` — main playbook: creates directories, calls `fortios_monitor_fact` with `selector: system_config_backup`, saves the result, logs outcome, and purges stale files

### Playbook Behavior

- `ignore_errors: true` on the fetch task — a failure on one device does not abort the remaining hosts
- All file operations (`copy`, `lineinfile`, `file`, `find`) use `delegate_to: localhost` because the Ansible control node manages the files, not the FortiGates
- Backup filename pattern: `<inventory_hostname>_<YYYYMMDDTHHmmss>.conf`
- Logs written to `logs/backup-YYYY-MM-DD.log` with `SUCESSO` or `FALHA` prefixes

### Adding a New FortiGate

1. Add the host to `inventory/fortigates.yml` with `ansible_host` and `fortios_version`
2. Create the encrypted token file: `ansible-vault create host_vars/<hostname>.yml`
3. Content must be: `fortios_access_token: "TOKEN"`

## Security Notes

- `host_vars/*.yml` files must always be vault-encrypted before committing — never in plaintext
- `~/.secure/.vault_pass` must have `chmod 600` and is excluded from the repo via `.gitignore`
- The `backups/` and `logs/` directories are gitignored; only `.gitkeep` files are tracked
- The REST API token profile should have `System Configuration: Read` only — no write access
