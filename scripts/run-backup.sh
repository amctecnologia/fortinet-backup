#!/usr/bin/env bash
set -euo pipefail

# Caminho absoluto do projeto — ajuste se necessário
PROJECT_DIR="/opt/fortigate-backup"

# Virtual environment Python (deixe em branco para ignorar)
VENV_DIR="${PROJECT_DIR}/venv"

# Argumentos extras passados ao script (ex: --vault-password-file)
EXTRA_ARGS="$*"

# Arquivo de log diário
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y-%m-%d).log"

mkdir -p "${LOG_DIR}"

log() {
  echo "$(date +%Y-%m-%dT%H:%M:%S) | $*" | tee -a "${LOG_FILE}"
}

log "=== Iniciando execução de backup FortiGate ==="

# Ativa virtual environment se existir
if [ -d "${VENV_DIR}" ]; then
  log "Ativando virtual environment: ${VENV_DIR}"
  source "${VENV_DIR}/bin/activate"
fi

cd "${PROJECT_DIR}"

log "Executando playbook..."

# shellcheck disable=SC2086
ansible-playbook playbooks/backup-fortigate.yml \
  ${EXTRA_ARGS} \
  >> "${LOG_FILE}" 2>&1

EXIT_CODE=$?

if [ "${EXIT_CODE}" -eq 0 ]; then
  log "=== Backup concluído com sucesso ==="
else
  log "=== Backup finalizado com erros (exit code: ${EXIT_CODE}) ==="
fi

exit "${EXIT_CODE}"
