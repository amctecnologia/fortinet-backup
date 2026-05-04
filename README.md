# FortiGate Backup Ansible

Backup automatizado de configurações de múltiplos firewalls FortiGate via Ansible, sem dependência de FortiManager. Compatível com FortiOS 6.x e 7.x (testado em 7.6.x).

---

## Sumário

1. [Objetivo](#objetivo)
2. [Pré-requisitos](#pré-requisitos)
3. [Instalação](#instalação)
4. [Estrutura do projeto](#estrutura-do-projeto)
5. [Configuração dos FortiGates](#configuração-dos-fortigates)
6. [Como criar o token de API no FortiGate](#como-criar-o-token-de-api-no-fortigate)
7. [Permissões mínimas do token](#permissões-mínimas-do-token)
8. [Ansible Vault: armazenamento seguro dos tokens](#ansible-vault-armazenamento-seguro-dos-tokens)
9. [Execução manual](#execução-manual)
10. [Agendamento via crontab](#agendamento-via-crontab)
11. [Personalização de diretórios e retenção](#personalização-de-diretórios-e-retenção)
12. [Como consultar os backups](#como-consultar-os-backups)
13. [Boas práticas de segurança](#boas-práticas-de-segurança)
14. [Solução de problemas](#solução-de-problemas)

---

## Objetivo

Realizar backup periódico e automatizado das configurações completas de firewalls FortiGate em ambientes sem FortiManager. Cada equipamento é acessado via token de API individual através de chamadas REST diretas, os backups são salvos localmente com controle de retenção e os tokens são protegidos com Ansible Vault.

---

## Pré-requisitos

- Ubuntu Server 22.04 LTS ou 24.04 LTS
- Acesso administrativo ao servidor (sudo)
- Acesso HTTPS à interface de gerenciamento de cada FortiGate
- Token REST API configurado em cada FortiGate

---

## Instalação

### 1. Preparar o servidor

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv git curl unzip
sudo mkdir -p /opt/fortigate-backup
sudo chown -R $USER:$USER /opt/fortigate-backup
```

### 2. Clonar o repositório

```bash
git clone <url-do-repositorio> /opt/fortigate-backup
cd /opt/fortigate-backup
```

### 3. Criar o virtual environment e instalar dependências

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install ansible
ansible-galaxy collection install -r requirements.yml
```

Validar:

```bash
ansible --version
ansible-galaxy collection list | grep fortinet
```

### 4. Ajustar caminhos no config.yml

Edite `config.yml` e defina os caminhos absolutos para o servidor:

```yaml
backup_base_path: "/opt/fortigate-backup/backups"
log_base_path:    "/opt/fortigate-backup/logs"
```

### 5. Criar o vault password file

```bash
mkdir -p ~/.secure
echo -n "SUA_SENHA_VAULT" > ~/.secure/.vault_pass
chmod 600 ~/.secure/.vault_pass
chmod 700 ~/.secure/
```

---

## Estrutura do projeto

```
/opt/fortigate-backup/
├── ansible.cfg                        # Configuração global do Ansible
├── requirements.yml                   # Dependências de collections
├── config.yml                         # Caminhos e retenção (caminhos absolutos)
├── inventory/
│   ├── fortigates.yml                 # Lista de equipamentos
│   ├── group_vars/
│   │   └── fortigates.yml             # Parâmetros de conexão do grupo
│   └── host_vars/
│       ├── fw-matriz.yml              # Token vault do fw-matriz
│       ├── fw-filial01.yml            # Token vault do fw-filial01
│       └── fw-filial02.yml            # Token vault do fw-filial02
├── playbooks/
│   └── backup-fortigate.yml           # Playbook principal
├── scripts/
│   └── run-backup.sh                  # Script de execução para cron
├── backups/                           # Backups gerados (não versionado)
└── logs/                              # Logs de execução (não versionado)
```

> **Importante:** `host_vars/` e `group_vars/` ficam dentro de `inventory/`. Isso é necessário para que o Ansible os encontre corretamente ao executar `ansible-playbook`.

---

## Configuração dos FortiGates

### Adicionar um novo FortiGate ao inventário

Edite `inventory/fortigates.yml`:

```yaml
all:
  children:
    fortigates:
      hosts:
        fw-nova-filial:
          ansible_host: 192.168.50.1
          fortios_version: "7"
```

### Criar o arquivo de token (inline vault)

Gere o valor criptografado do token:

```bash
ansible-vault encrypt_string \
  --vault-password-file ~/.secure/.vault_pass \
  'TOKEN_GERADO_NO_FORTIGATE' \
  --name 'fortios_access_token'
```

O comando exibirá algo como:

```yaml
fortios_access_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  64363163323562...
```

Crie o arquivo `inventory/host_vars/fw-nova-filial.yml` com esse conteúdo:

```yaml
---
fortios_access_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  64363163323562...
```

> **Atenção:** Use sempre `ansible-vault encrypt_string` (inline vault), não `ansible-vault create`. O formato de arquivo totalmente criptografado não é carregado corretamente pelo `ansible-playbook`.

---

## Como criar o token de API no FortiGate

### FortiOS 7.x

1. Acesse a interface web do FortiGate
2. Vá em **System > Administrators**
3. Clique em **Create New > REST API Admin**
4. Preencha:
   - **Username:** ansible-backup
   - **Administrator Profile:** perfil com permissão de leitura
5. Clique em **OK** — o token será exibido uma única vez

### FortiOS 6.x

1. Vá em **System > Admin > Administrators**
2. Clique em **Create New > REST API Admin**
3. Siga os mesmos passos do 7.x

### Habilitar acesso HTTPS na interface

```
Network > Interfaces > [interface de gerenciamento] > Administrative Access
```

Marque: **HTTPS**

### Testar o token

```bash
curl -k -X POST \
  -H "Authorization: Bearer SEU_TOKEN" \
  "https://IP_DO_FORTIGATE/api/v2/monitor/system/config/backup?scope=global" \
  -o teste_backup.conf
```

Resposta esperada: arquivo de configuração salvo. Se retornar JSON com erro, verifique o token e as permissões.

---

## Permissões mínimas do token

| Área                  | Permissão mínima |
|-----------------------|------------------|
| System Configuration  | Read             |

Use um **Admin Profile** customizado com acesso somente leitura ao sistema.

---

## Ansible Vault: armazenamento seguro dos tokens

### Criar token criptografado (inline vault — método correto)

```bash
ansible-vault encrypt_string \
  --vault-password-file ~/.secure/.vault_pass \
  'TOKEN_AQUI' \
  --name 'fortios_access_token'
```

Cole o output em `inventory/host_vars/<hostname>.yml`.

### Verificar token armazenado

```bash
ansible <hostname> -m debug -a "var=fortios_access_token" \
  --vault-password-file ~/.secure/.vault_pass
```

### Atualizar token existente

Gere novo valor com `encrypt_string` e substitua no arquivo `host_vars`.

---

## Execução manual

### Com vault password file

```bash
cd /opt/fortigate-backup
source venv/bin/activate

# Todos os equipamentos
ansible-playbook playbooks/backup-fortigate.yml \
  --vault-password-file ~/.secure/.vault_pass

# Somente um equipamento
ansible-playbook playbooks/backup-fortigate.yml \
  --vault-password-file ~/.secure/.vault_pass \
  --limit fw-matriz
```

### Teste de conectividade (sem fazer backup)

```bash
ansible fortigates -m debug -a "var=ansible_host" \
  --vault-password-file ~/.secure/.vault_pass
```

---

## Agendamento via crontab

```bash
crontab -e
```

Adicionar linha para execução diária às 02:00:

```
0 2 * * * /opt/fortigate-backup/scripts/run-backup.sh --vault-password-file /home/usuario/.secure/.vault_pass
```

O script `run-backup.sh` ativa automaticamente o venv e registra logs diários em `logs/backup-YYYY-MM-DD.log`.

---

## Personalização de diretórios e retenção

Edite `config.yml`:

```yaml
backup_base_path: "/opt/fortigate-backup/backups"   # Caminho absoluto obrigatório
log_base_path:    "/opt/fortigate-backup/logs"       # Caminho absoluto obrigatório
retention_days:   90                                  # Dias para manter backups
create_host_folder: true                              # Subpasta por equipamento
```

> Os caminhos devem ser **absolutos**. Caminhos relativos são resolvidos a partir do diretório do playbook, não da raiz do projeto.

Para usar um NAS montado:

```yaml
backup_base_path: "/mnt/nas/fortigate-backups"
```

---

## Como consultar os backups

```bash
# Listar todos os backups
find /opt/fortigate-backup/backups -name "*.conf" | sort

# Backups de um equipamento específico
ls -lh /opt/fortigate-backup/backups/fw-matriz/

# Último backup de cada equipamento
for dir in /opt/fortigate-backup/backups/*/; do
  echo "=== $(basename $dir) ==="
  ls -t "$dir"*.conf 2>/dev/null | head -1
done

# Log do dia atual
cat /opt/fortigate-backup/logs/backup-$(date +%Y-%m-%d).log
```

---

## Boas práticas de segurança

1. **Use sempre inline vault** (`encrypt_string`) para os tokens — nunca armazene em texto plano.
2. **Não use `ansible-vault create`** para os arquivos `host_vars` — use `encrypt_string` e salve em arquivo YAML normal.
3. **Use perfil de somente leitura** para os tokens de API.
4. **Proteja o vault password file** com `chmod 600`.
5. **Não versione** o diretório `backups/` — arquivos `.conf` contêm senhas e estrutura completa da rede.
6. **Restrinja o acesso à API do FortiGate** por IP de origem quando possível.
7. **Monitore os logs** — uma falha silenciosa pode deixar você sem backup.

---

## Solução de problemas

### Erro: `stdout_callback = yaml` inválido

```
ERROR! Invalid callback for stdout specified: yaml
```

**Causa:** Versão do Ansible incompatível com o callback `yaml`.  
**Solução:** Em `ansible.cfg`, use `stdout_callback = default`.

### Erro: variável `fortios_access_token` indefinida no playbook

**Causa:** Arquivo `host_vars` criado com `ansible-vault create` (arquivo totalmente criptografado) não é carregado corretamente pelo `ansible-playbook`.  
**Solução:** Recriar usando `ansible-vault encrypt_string` (inline vault) conforme descrito em [Ansible Vault](#ansible-vault-armazenamento-seguro-dos-tokens).

### Erro 401 (Unauthorized)

Token incorreto ou sem permissão. Verifique com:

```bash
ansible <hostname> -m debug -a "var=fortios_access_token" \
  --vault-password-file ~/.secure/.vault_pass
```

### Erro 405 (Method Not Allowed)

O endpoint de backup requer método POST. Confirme que `playbooks/backup-fortigate.yml` usa `method: POST` na task `Obter configuração completa do FortiGate`.

### Host não encontrado no inventário

Confirme que `host_vars/<hostname>.yml` está em `inventory/host_vars/`, não na raiz do projeto. O Ansible busca `host_vars` relativo ao diretório do playbook ou do inventory — não ao CWD.

### Cron não executa

```bash
sudo systemctl status cron
grep CRON /var/log/syslog | tail -20
chmod +x /opt/fortigate-backup/scripts/run-backup.sh
```

### Backup gerado no diretório errado

Os caminhos em `config.yml` devem ser **absolutos**. Caminhos com `./` são resolvidos a partir do diretório `playbooks/`, não da raiz do projeto.
