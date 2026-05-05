# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible project for automated backup of FortiGate firewall configurations without FortiManager. The playbook uses `ansible.builtin.uri` to call the FortiOS REST API directly — it does **not** depend on the `fortinet.fortios` collection. Backups are saved locally as `.conf` files with configurable retention.

**Two directories:**
- `~/Documentos/PROJETOS/FORTINET-BACKUP/` — git repository (this repo)
- `/opt/fortigate-backup/` — deployed and running instance

## Key Commands

### Setup

```bash
# Create and activate Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Ansible (collection fortinet.fortios is NOT required)
pip install ansible
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

**Always use `ansible-vault encrypt_string` (inline vault). Never use `ansible-vault create` — fully encrypted files are NOT loaded by `ansible-playbook`.**

```bash
# Create encrypted token for a new host
ansible-vault encrypt_string \
  --vault-password-file ~/.secure/.vault_pass \
  'TOKEN_VALUE' \
  --name 'fortios_access_token'
# Paste output into inventory/host_vars/<hostname>.yml

# Verify token is loaded correctly
ansible <hostname> -m debug -a "var=fortios_access_token" \
  --vault-password-file ~/.secure/.vault_pass
```

### Automated Execution (cron)

The script at `scripts/run-backup.sh` has `PROJECT_DIR` hardcoded to `/opt/fortigate-backup`. Update it if deploying elsewhere.

```
0 2 * * * /opt/fortigate-backup/scripts/run-backup.sh --vault-password-file /home/usuario/.secure/.vault_pass
```

## Architecture

### Data Flow

1. `inventory/fortigates.yml` — defines hosts with `ansible_host` (IP) and `fortios_version`
2. `inventory/group_vars/fortigates.yml` — sets `ansible_connection: local` for the entire group
3. `inventory/host_vars/<hostname>.yml` — holds the vault-encrypted `fortios_access_token` per device (inline vault format)
4. `config.yml` — operational settings: `backup_base_path`, `log_base_path`, `retention_days`, `create_host_folder` — **paths must be absolute**
5. `playbooks/backup-fortigate.yml` — main playbook: uses `set_fact` to capture the vault token in host context, then calls `ansible.builtin.uri` with `method: POST` delegated to localhost, saves result, logs outcome, and purges stale files

### Critical Design Decisions

- **`ansible_connection: local`** in `group_vars` — Ansible does not attempt SSH to FortiGates
- **`set_fact` before `delegate_to`** — vault variable captured in host context before delegation, then accessed via `hostvars[inventory_hostname]['_fortios_token']` in the delegated uri task
- **`host_vars` and `group_vars` must be inside `inventory/`** — `ansible-playbook` resolves these relative to the inventory directory, not the project root
- **FortiOS 7.x requires POST** on `/api/v2/monitor/system/config/backup?scope=global` — GET returns HTTP 405
- **Inline vault only** — `ansible-vault create` produces fully encrypted files that are not loaded by `ansible-playbook` in this setup

### Adding a New FortiGate

1. Add to `inventory/fortigates.yml`: `ansible_host` and `fortios_version`
2. Generate inline vault token: `ansible-vault encrypt_string ... --name 'fortios_access_token'`
3. Save output to `inventory/host_vars/<hostname>.yml`

### Playbook Behavior

- `ignore_errors: true` on the fetch task — failure on one device does not abort remaining hosts
- All file operations use `delegate_to: localhost` — control node manages files, not FortiGates
- Backup filename pattern: `<inventory_hostname>_<YYYYMMDDTHHmmss>.conf`
- Logs written to `logs/backup-YYYY-MM-DD.log` with `SUCESSO` or `FALHA` prefixes

## Security Notes

- `inventory/host_vars/*.yml` files in the repo are **templates only** (placeholder vault blocks) — never commit real tokens
- `~/.secure/.vault_pass` must have `chmod 600` and is excluded from the repo
- Use `echo -n` when creating the vault password file — a trailing newline causes decryption failures
- `backups/` and `logs/` are gitignored; only `.gitkeep` files are tracked
- REST API token profile: `System Configuration: Read/Write` — tokens somente leitura geram `#password_mask=1` e omitem `config system admin`, tornando o restore ineficaz
