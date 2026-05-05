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
14. [Compatibilidade FortiOS 6.x e 7.x](#compatibilidade-fortios-6x-e-7x)
15. [Solução de problemas](#solução-de-problemas)

---

## Objetivo

Realizar backup periódico e automatizado das configurações completas de firewalls FortiGate em ambientes sem FortiManager. Cada equipamento é acessado via token de API individual através de chamadas REST diretas com `ansible.builtin.uri`, os backups são salvos localmente com controle de retenção e os tokens são protegidos com Ansible Vault.

O playbook **não depende** da collection `fortinet.fortios` para execução — usa apenas módulos nativos do Ansible (`ansible.builtin.uri`, `ansible.builtin.copy`, `ansible.builtin.file`, etc.).

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
```

Validar:

```bash
ansible --version
```

> **Nota:** A collection `fortinet.fortios` listada em `requirements.yml` **não é necessária** para execução dos backups. O playbook usa `ansible.builtin.uri` para chamar a API REST do FortiOS diretamente.

### 4. Criar o vault password file

```bash
mkdir -p ~/.secure
echo -n "SUA_SENHA_VAULT" > ~/.secure/.vault_pass
chmod 600 ~/.secure/.vault_pass
chmod 700 ~/.secure/
```

> **Importante:** Use `echo -n` para evitar quebra de linha no final da senha. Uma quebra de linha extra causa falha na descriptografia.

### 5. Configurar caminhos em config.yml

Edite `config.yml` e defina os caminhos **absolutos** para o servidor:

```yaml
backup_base_path: "/opt/fortigate-backup/backups"
log_base_path:    "/opt/fortigate-backup/logs"
```

> Os caminhos **precisam ser absolutos**. Caminhos relativos como `./backups` são resolvidos a partir do diretório `playbooks/`, não da raiz do projeto.

---

## Estrutura do projeto

```
/opt/fortigate-backup/
├── ansible.cfg                        # Configuração global do Ansible
├── requirements.yml                   # Collection fortinet.fortios (opcional)
├── config.yml                         # Caminhos absolutos e retenção
├── inventory/
│   ├── fortigates.yml                 # Lista de equipamentos (hosts)
│   ├── group_vars/
│   │   └── fortigates.yml             # ansible_connection: local
│   └── host_vars/
│       ├── fw-matriz.yml              # Token vault (inline) do fw-matriz
│       ├── fw-filial01.yml            # Token vault (inline) do fw-filial01
│       └── fw-filial02.yml            # Token vault (inline) do fw-filial02
├── playbooks/
│   └── backup-fortigate.yml           # Playbook principal
├── scripts/
│   └── run-backup.sh                  # Script para cron (PROJECT_DIR hardcoded)
├── backups/                           # Backups gerados (não versionado)
└── logs/                              # Logs de execução (não versionado)
```

> **Importante:** `host_vars/` e `group_vars/` devem estar **dentro de `inventory/`**. O Ansible busca essas pastas relativo ao diretório do inventário ou do playbook — arquivos na raiz do projeto são ignorados pelo `ansible-playbook`.

### ansible.cfg (configurações relevantes)

```ini
[defaults]
inventory         = ./inventory     # Diretório, não arquivo — habilita host_vars/group_vars automáticos
stdout_callback   = default         # "yaml" requer dependências extras; use "default"
host_key_checking = False
```

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

### Criar o arquivo de token (inline vault — método obrigatório)

Gere o valor criptografado do token com `ansible-vault encrypt_string`:

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

> **Atenção:** Use sempre `ansible-vault encrypt_string` (inline vault). **Não use** `ansible-vault create` — arquivos totalmente criptografados **não são carregados** pelo `ansible-playbook` nesta configuração.

---

## Como criar o token de API no FortiGate

### FortiOS 7.x

1. Acesse a interface web do FortiGate
2. Vá em **System > Administrators**
3. Clique em **Create New > REST API Admin**
4. Preencha:
   - **Username:** ansible-backup
   - **Administrator Profile:** perfil com permissão **Read/Write** (veja seção de permissões)
5. Clique em **OK** — o token será exibido **uma única vez**. Copie imediatamente.

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

> **FortiOS 7.x requer método POST** neste endpoint. GET retorna HTTP 405 Method Not Allowed.

---

## Permissões mínimas do token

> **Atenção:** o nível de permissão do token afeta diretamente o **conteúdo** do backup gerado.

| Perfil do token        | Permissão     | Comportamento no backup                                                              |
|------------------------|---------------|--------------------------------------------------------------------------------------|
| Somente leitura        | `Read`        | FortiOS insere `#password_mask=1` — seção `config system admin` fica **vazia**      |
| Leitura e escrita      | `Read/Write`  | Backup completo — `config system admin` contém as senhas criptografadas              |
| super_admin (built-in) | Total         | Backup completo — igual ao perfil Read/Write                                         |

### Implicação prática

Um backup gerado com token de **somente leitura** **não exporta as contas de administrador**. Ao restaurar esse backup em qualquer FortiGate, o dispositivo ficará sem contas configuradas e potencialmente inacessível via web ou console.

### Recomendação

Use um **Admin Profile com permissão Read/Write** (não necessariamente super_admin) para garantir backups completos e restauráveis:

| Área                  | Permissão recomendada |
|-----------------------|-----------------------|
| System Configuration  | Read/Write            |

> **Nota sobre valores `ENC`:** As senhas exportadas no backup têm prefixo `ENC` e são cifradas com chave derivada do número de série do dispositivo. Restaurar o backup em um FortiGate **diferente** (serial diferente) pode invalidar as senhas — use o factory reset e reconfigure nesse caso.

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

Gere novo valor com `encrypt_string` e substitua no arquivo `inventory/host_vars/<hostname>.yml`.

---

## Execução manual

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

Substitua `usuario` pelo nome do usuário do sistema.

O script `run-backup.sh`:
- Ativa automaticamente o venv localizado em `PROJECT_DIR/venv`
- Registra logs diários em `logs/backup-YYYY-MM-DD.log`
- Tem o caminho do projeto **hardcoded** em `PROJECT_DIR="/opt/fortigate-backup"` — ajuste se instalar em outro local

---

## Personalização de diretórios e retenção

Edite `config.yml`:

```yaml
backup_base_path: "/opt/fortigate-backup/backups"   # Caminho absoluto obrigatório
log_base_path:    "/opt/fortigate-backup/logs"       # Caminho absoluto obrigatório
retention_days:   90                                  # Dias para manter backups
create_host_folder: true                              # Subpasta por equipamento
```

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
3. **Use perfil Read/Write** para os tokens de API de backup — tokens somente leitura geram backups incompletos (sem seção `config system admin`), tornando o restore ineficaz.
4. **Proteja o vault password file** com `chmod 600`.
5. **Não versione** o diretório `backups/` — arquivos `.conf` contêm senhas e estrutura completa da rede.
6. **Restrinja o acesso à API do FortiGate** por IP de origem quando possível.
7. **Monitore os logs** — uma falha silenciosa pode deixar você sem backup.

---

## Compatibilidade FortiOS 6.x e 7.x

O playbook usa `ansible.builtin.uri` para chamar diretamente o endpoint REST:

```
POST /api/v2/monitor/system/config/backup?scope=global
```

| Aspecto                        | FortiOS 6.x             | FortiOS 7.x             |
|-------------------------------|-------------------------|-------------------------|
| Token REST API                | Disponível              | Disponível              |
| Método HTTP no endpoint       | GET ou POST             | **POST obrigatório**    |
| Validação de certificado TLS  | Desabilitada no playbook| Desabilitada no playbook|

**Requisitos nos FortiGates (ambas as versões):**
- HTTPS habilitado na interface de gerenciamento
- Administrador REST API com perfil de leitura
- Acesso da rede do servidor Ansible à porta 443 do FortiGate

---

## Solução de problemas

### Erro: `stdout_callback = yaml` inválido

```
ERROR! Invalid callback for stdout specified: yaml
```

**Causa:** O callback `yaml` requer Ansible 2.11+ com `community.general` instalado.  
**Solução:** Em `ansible.cfg`, use `stdout_callback = default`.

### Variável `fortios_access_token` indefinida no playbook

```
"fortios_access_token": "VARIABLE IS NOT DEFINED!"
```

Duas causas possíveis:

1. **Arquivo `host_vars` no local errado.** O `ansible-playbook` busca `host_vars` relativo ao diretório do inventário ou do playbook — **não** da raiz do projeto. Verifique se o arquivo está em `inventory/host_vars/<hostname>.yml`.

2. **Arquivo criado com `ansible-vault create`** (arquivo totalmente criptografado). Este formato **não é carregado** pelo `ansible-playbook`. Recrie usando `ansible-vault encrypt_string` (inline vault).

### Erro 401 (Unauthorized)

Token incorreto ou sem permissão. Verifique com:

```bash
ansible <hostname> -m debug -a "var=fortios_access_token" \
  --vault-password-file ~/.secure/.vault_pass
```

### Erro 405 (Method Not Allowed)

O endpoint de backup no FortiOS 7.x requer método POST. Confirme que `playbooks/backup-fortigate.yml` usa `method: POST` na task de backup.

### Erro de descriptografia do Vault

```
ERROR! Decryption failed (no vault secrets would unlock)
```

**Causa:** O vault password file contém uma quebra de linha extra.  
**Solução:** Recrie com `echo -n "SENHA" > ~/.secure/.vault_pass` (flag `-n` omite a quebra de linha).

### Backup gerado no diretório errado (`playbooks/backups/`)

Os caminhos em `config.yml` devem ser **absolutos**. Caminhos com `./` são resolvidos a partir do diretório `playbooks/`, não da raiz do projeto. Use `/opt/fortigate-backup/backups`.

### Host não encontrado no inventário

Confirme que `host_vars/<hostname>.yml` está em `inventory/host_vars/`, não na raiz do projeto.

### Cron não executa

```bash
sudo systemctl status cron
grep CRON /var/log/syslog | tail -20
chmod +x /opt/fortigate-backup/scripts/run-backup.sh
```

### FortiGate inacessível após restore de backup

**Sintoma:** Após restaurar um `.conf`, o dispositivo reinicia mas a interface web não responde e/ou nenhuma senha funciona no console.

**Causa mais comum:** O backup foi gerado com token de **somente leitura** (`System Configuration: Read`). Nesses casos, o FortiOS adiciona `#password_mask=1` e omite toda a seção `config system admin`. Ao restaurar, o dispositivo fica sem contas de administrador.

**Verificação:** Abra o arquivo `.conf` e procure:

```
#password_mask=1        <- indica backup incompleto (token somente leitura)
config system admin     <- se estiver vazio (só 'end'), confirma o problema
```

**Soluções em ordem:**
1. Tente `admin` com senha vazia (padrão de fábrica).
2. Conta `maintainer`: reinicie e, nos primeiros 60 s do prompt de login: `Login: maintainer` / `Password: bcpb<NUMERO_SERIE>` (pode estar desabilitada).
3. Factory reset: `execute factoryreset` no console, ou via boot menu (opção "Format boot device").
4. **Prevenção:** Gere backups com token Read/Write — assim `config system admin` será incluído.
