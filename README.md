# FortiGate Backup Ansible

Backup automatizado de configurações de múltiplos firewalls FortiGate via Ansible, sem dependência de FortiManager. Compatível com FortiOS 6.x e 7.x.

---

## Sumário

1. [Objetivo](#objetivo)
2. [Pré-requisitos](#pré-requisitos)
3. [Preparação do servidor Ubuntu](#preparação-do-servidor-ubuntu)
4. [Instalação do Ansible](#instalação-do-ansible)
5. [Instalação da Collection Fortinet](#instalação-da-collection-fortinet)
6. [Estrutura do projeto](#estrutura-do-projeto)
7. [Configuração dos FortiGates](#configuração-dos-fortigates)
8. [Como criar o token de API no FortiGate](#como-criar-o-token-de-api-no-fortigate)
9. [Permissões mínimas do token](#permissões-mínimas-do-token)
10. [Ansible Vault: armazenamento seguro dos tokens](#ansible-vault-armazenamento-seguro-dos-tokens)
11. [Execução manual](#execução-manual)
12. [Agendamento via crontab](#agendamento-via-crontab)
13. [Personalização de diretórios e retenção](#personalização-de-diretórios-e-retenção)
14. [Como consultar os backups](#como-consultar-os-backups)
15. [Boas práticas de segurança](#boas-práticas-de-segurança)
16. [Compatibilidade FortiOS 6.x e 7.x](#compatibilidade-fortios-6x-e-7x)
17. [Solução de problemas](#solução-de-problemas)

---

## Objetivo

Realizar backup periódico e automatizado das configurações completas de firewalls FortiGate em ambientes sem FortiManager. Cada equipamento é acessado via token de API individual, os backups são salvos localmente com controle de retenção e os tokens são protegidos com Ansible Vault.

---

## Pré-requisitos

- Ubuntu Server 22.04 LTS ou 24.04 LTS
- Acesso administrativo ao servidor (sudo)
- Acesso HTTPS à interface de gerenciamento de cada FortiGate
- Token REST API configurado em cada FortiGate

---

## Preparação do servidor Ubuntu

### 1. Atualização inicial

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Instalação dos pacotes base

```bash
sudo apt install -y python3 python3-pip python3-venv git curl unzip jq cron
```

### 3. Garantir que o serviço cron está ativo

```bash
sudo systemctl enable cron
sudo systemctl start cron
sudo systemctl status cron
```

### 4. Criar diretório do projeto

```bash
sudo mkdir -p /opt/fortigate-backup
sudo chown -R $USER:$USER /opt/fortigate-backup
```

---

## Instalação do Ansible

A forma recomendada é via virtual environment Python, que isola as dependências do sistema e facilita atualizações.

### Via virtual environment (recomendado)

```bash
cd /opt/fortigate-backup
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install ansible
```

Validar:

```bash
ansible --version
```

### Via apt (alternativa)

```bash
sudo apt install -y ansible
```

Esta opção instala uma versão controlada pelo Ubuntu, que pode ser mais antiga. Para produção, prefira o virtual environment.

---

## Instalação da Collection Fortinet

Com o virtual environment ativo:

```bash
ansible-galaxy collection install -r requirements.yml
```

Ou diretamente:

```bash
ansible-galaxy collection install fortinet.fortios
```

Validar:

```bash
ansible-galaxy collection list | grep fortinet
```

---

## Estrutura do projeto

```
/opt/fortigate-backup/
├── ansible.cfg                  # Configuração global do Ansible
├── requirements.yml             # Dependências de collections
├── config.yml                   # Configurações operacionais (retenção, caminhos)
├── inventory/
│   └── fortigates.yml           # Lista de equipamentos
├── group_vars/
│   └── fortigates.yml           # Parâmetros de conexão comuns
├── host_vars/
│   ├── fw-matriz.yml            # Token vault do fw-matriz
│   ├── fw-filial01.yml          # Token vault do fw-filial01
│   └── fw-filial02.yml          # Token vault do fw-filial02
├── playbooks/
│   └── backup-fortigate.yml     # Playbook principal de backup
├── scripts/
│   └── run-backup.sh            # Script de execução (usado pelo cron)
├── backups/                     # Backups gerados (não versionado)
│   └── .gitkeep
├── logs/                        # Logs de execução (não versionado)
│   └── .gitkeep
├── .gitignore
└── README.md
```

---

## Configuração dos FortiGates

### Clonar o repositório no servidor

```bash
git clone <url-do-repositorio> /opt/fortigate-backup
cd /opt/fortigate-backup
```

### Adicionar um novo FortiGate ao inventário

Edite `inventory/fortigates.yml` e inclua o novo host:

```yaml
all:
  children:
    fortigates:
      hosts:
        fw-nova-filial:
          ansible_host: 192.168.50.1
          fortios_version: "7"
```

Em seguida, crie o arquivo de token para o novo host:

```bash
ansible-vault create host_vars/fw-nova-filial.yml
```

Insira o conteúdo:

```yaml
---
fortios_access_token: "TOKEN_GERADO_NO_FORTIGATE"
```

---

## Como criar o token de API no FortiGate

### FortiOS 7.x

1. Acesse a interface web do FortiGate
2. Vá em **System > Administrators**
3. Clique em **Create New > REST API Admin**
4. Preencha:
   - **Username:** ansible-backup (ou o nome desejado)
   - **Administrator Profile:** selecione o perfil com permissão de leitura
   - **PKI Group:** deixe vazio (não obrigatório)
   - **CORS Allow Origin:** deixe vazio
5. Clique em **OK**
6. O token será exibido uma única vez. Copie e guarde com segurança.

### FortiOS 6.x

1. Acesse a interface web
2. Vá em **System > Admin > Administrators**
3. Clique em **Create New**
4. Selecione **REST API Admin**
5. Siga os mesmos passos do 7.x

### Habilitar acesso API na interface

Certifique-se de que a interface de gerenciamento permite HTTPS e acesso via API:

```
Network > Interfaces > [interface de gerenciamento] > Administrative Access
```

Marque: **HTTPS**, **SSH** (opcional)

### Teste via curl

```bash
curl -k -H "Authorization: Bearer SEU_TOKEN" \
  https://IP_DO_FORTIGATE/api/v2/monitor/system/status
```

Resposta esperada: JSON com informações do sistema. Se retornar erro 401, o token está incorreto ou sem permissão.

---

## Permissões mínimas do token

O perfil de administrador associado ao token precisa ter ao menos as seguintes permissões em modo leitura:

| Área                  | Permissão mínima |
|-----------------------|------------------|
| System Configuration  | Read             |
| Log & Report          | None (opcional)  |

No FortiOS, use um **Admin Profile** customizado com acesso somente leitura ao sistema, sem acesso a políticas de firewall ou outros recursos sensíveis. Isso reduz o risco caso o token seja comprometido.

---

## Ansible Vault: armazenamento seguro dos tokens

O Ansible Vault criptografa os arquivos de variáveis, impedindo que tokens fiquem expostos no Git ou no sistema de arquivos.

### Criar arquivo de token criptografado

```bash
ansible-vault create host_vars/fw-matriz.yml
```

O editor padrão abrirá. Insira:

```yaml
---
fortios_access_token: "TOKEN_GERADO_NO_FORTIGATE"
```

Salve e feche. O arquivo ficará criptografado no disco.

### Editar arquivo existente

```bash
ansible-vault edit host_vars/fw-matriz.yml
```

### Visualizar sem editar

```bash
ansible-vault view host_vars/fw-matriz.yml
```

### Criptografar arquivo já existente em texto plano

```bash
ansible-vault encrypt host_vars/fw-matriz.yml
```

### Vault Password File (recomendado para cron)

Crie um arquivo com a senha do vault:

```bash
mkdir -p ~/.secure
nano ~/.secure/.vault_pass
```

Insira somente a senha, sem espaços ou quebras de linha extras. Em seguida:

```bash
chmod 600 ~/.secure/.vault_pass
chmod 700 ~/.secure/
```

Este arquivo nunca deve ser versionado no Git. Está incluído no `.gitignore`.

---

## Execução manual

### Com senha interativa

```bash
cd /opt/fortigate-backup
source venv/bin/activate
ansible-playbook playbooks/backup-fortigate.yml --ask-vault-pass
```

### Com Vault Password File

```bash
ansible-playbook playbooks/backup-fortigate.yml \
  --vault-password-file ~/.secure/.vault_pass
```

### Somente um equipamento

```bash
ansible-playbook playbooks/backup-fortigate.yml \
  --vault-password-file ~/.secure/.vault_pass \
  --limit fw-matriz
```

### Teste de conectividade (sem backup)

```bash
ansible fortigates -m fortinet.fortios.fortios_monitor_fact \
  -a "selector=system_status" \
  --vault-password-file ~/.secure/.vault_pass \
  -vvvv
```

---

## Agendamento via crontab

### Editar a crontab do usuário

```bash
crontab -e
```

### Execução diária às 02:00 sem vault password file

```
0 2 * * * /opt/fortigate-backup/scripts/run-backup.sh
```

### Execução diária às 02:00 com vault password file (recomendado)

```
0 2 * * * /opt/fortigate-backup/scripts/run-backup.sh --vault-password-file /home/usuario/.secure/.vault_pass
```

Substitua `usuario` pelo usuário do sistema que executará o backup.

### Considerações para ambiente não interativo

- O cron não carrega o ambiente do shell do usuário, por isso o `run-backup.sh` usa caminhos absolutos.
- O virtual environment é ativado automaticamente pelo script se existir em `PROJECT_DIR/venv`.
- Logs são gravados em `logs/backup-YYYY-MM-DD.log` automaticamente.
- O `--vault-password-file` elimina a necessidade de interação manual.

---

## Personalização de diretórios e retenção

Todas as configurações operacionais ficam em `config.yml`:

```yaml
backup_base_path: "./backups"     # Onde salvar os backups
log_base_path:    "./logs"        # Onde salvar os logs
retention_days:   90              # Dias para manter backups
create_host_folder: true          # Criar subpasta por equipamento
```

Para alterar o diretório de backup para um NAS montado, por exemplo:

```yaml
backup_base_path: "/mnt/nas/fortigate-backups"
```

Nenhuma alteração no playbook é necessária.

---

## Como consultar os backups

### Listar todos os backups

```bash
find /opt/fortigate-backup/backups -name "*.conf" | sort
```

### Backups de um equipamento específico

```bash
ls -lh /opt/fortigate-backup/backups/fw-matriz/
```

### Verificar o último backup de cada equipamento

```bash
for dir in /opt/fortigate-backup/backups/*/; do
  echo "=== $(basename $dir) ==="
  ls -t "$dir"*.conf 2>/dev/null | head -1
done
```

### Consultar logs

```bash
# Log do dia atual
cat /opt/fortigate-backup/logs/backup-$(date +%Y-%m-%d).log

# Todos os logs
ls -lh /opt/fortigate-backup/logs/
```

---

## Boas práticas de segurança

1. **Nunca commite tokens em texto plano.** Sempre use `ansible-vault encrypt` antes de fazer `git add` em arquivos `host_vars/`.
2. **Use perfil de somente leitura** para os tokens de API. Isso limita o impacto em caso de vazamento.
3. **Proteja o vault password file** com `chmod 600` e mantenha fora do repositório.
4. **Restrinja o acesso à API do FortiGate** por IP de origem sempre que possível (configuração no perfil do administrador REST).
5. **Monitore os logs de backup.** Uma falha silenciosa pode deixar você sem backup quando mais precisar.
6. **Rotacione os tokens periodicamente** e atualize os arquivos vault correspondentes.
7. **Não versione o diretório `backups/`.** Arquivos de configuração contêm senhas, rotas e estrutura completa da rede.

---

## Compatibilidade FortiOS 6.x e 7.x

O módulo `fortios_monitor_fact` com selector `system_config_backup` é compatível com FortiOS 6.2+ e todas as versões 7.x. Diferenças conhecidas:

| Aspecto                        | FortiOS 6.x          | FortiOS 7.x          |
|-------------------------------|----------------------|----------------------|
| Token REST API                | Disponível           | Disponível           |
| Endpoint de backup             | `/api/v2/monitor/...`| `/api/v2/monitor/...`|
| Validação de certificado       | Ignorada (`false`)   | Ignorada (`false`)   |
| Comportamento de erro de host  | Independente         | Independente         |

A opção `ignore_errors: true` por task garante que a falha em um equipamento não interrompe o backup dos demais. Cada host é tratado de forma independente.

**Requisitos no FortiGate (ambas as versões):**

- HTTPS habilitado na interface de gerenciamento
- Administrador REST API criado com perfil de leitura
- Token gerado e copiado corretamente
- Acesso da rede do servidor Ansible à porta 443 do FortiGate

---

## Solução de problemas

### Erro 401 (Unauthorized)

O token está incorreto, expirado ou sem permissão. Verifique no FortiGate e recrie o arquivo vault.

### Timeout de conexão

Verifique conectividade: `curl -k https://IP_DO_FORTIGATE`. Se não responder, há problema de roteamento ou firewall entre o servidor Ansible e o FortiGate.

### `fortios_monitor_fact` não encontrado

A collection não está instalada ou o virtual environment não está ativo.

```bash
source venv/bin/activate
ansible-galaxy collection install fortinet.fortios
```

### Backup vazio ou arquivo zerado

O FortiGate respondeu mas não retornou conteúdo. Verifique se o perfil do token tem permissão de leitura de configuração do sistema (`System Configuration: Read`).

### Cron não executa

Verifique se o serviço está ativo:

```bash
sudo systemctl status cron
```

Verifique o log do cron:

```bash
grep CRON /var/log/syslog | tail -20
```

Garanta que o script tem permissão de execução:

```bash
chmod +x /opt/fortigate-backup/scripts/run-backup.sh
```
