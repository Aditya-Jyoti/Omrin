# Omrin

A self-hosted infrastructure setup using **Ansible**, **Docker Compose**, and **Traefik**. Omrin provisions a fresh VPS from a bare OS into a hardened, Docker-based host with automatic HTTPS routing for every service you add.

## Overview

Omrin is designed to run on a **VPS** (e.g. Contabo, Hetzner) or a **locally provisioned VM** (via Vagrant, for testing). It handles everything from the first root login to running services:

- **Ansible** provisions the server: creates a deploy user, hardens SSH, sets the hostname, installs CLI tooling, installs Docker, configures the firewall, deploys services, and sets up automated off-site backups.
- **Docker Compose** orchestrates each service as an isolated stack.
- **Traefik** acts as a reverse proxy, automatically routing subdomains to containers and provisioning Let's Encrypt TLS certificates.
- **rclone + systemd timer** backs up all persistent service data to OneDrive nightly, with ntfy notifications on start/success/failure.
- **Vagrant** provides a throwaway local VM so you can test the full provisioning flow before touching a real server.

## How it works

Provisioning happens in two phases, run as two separate playbooks:

| Phase        | Playbook         | Connects as | What it does                                                                                                        |
| :----------- | :--------------- | :---------- | :------------------------------------------------------------------------------------------------------------------ |
| 1. Bootstrap | `bootstrap.yaml` | `root`      | Creates the deploy user, installs its SSH key, grants passwordless sudo. After this, you log in as the deploy user. |
| 2. Main      | `main.yaml`      | deploy user | Installs CLI tools, sets hostname, installs Docker, configures UFW, hardens SSH, deploys services, sets up backups. |

The split exists because phase 1 needs root (the only account that exists on a fresh VPS), while phase 2 runs as your unprivileged deploy user with sudo. Running bootstrap first means that by the time SSH hardening happens in phase 2, your key-based login as the deploy user already works — so you never lock yourself out.

`main.yaml` roles run in this order: `tools` → `docker` → `firewall` → `ssh` → `services` → `backup`. Each role is tagged, so you can re-run just one part of the stack instead of the whole playbook (see [Re-running a single part of the stack](#re-running-a-single-part-of-the-stack)).

## Project Structure

```
.
├── ansible/
│   ├── ansible.cfg               # Ansible configuration (roles path, ssh settings)
│   ├── requirements.yaml         # Ansible Galaxy collections to install
│   │
│   ├── group_vars/
│   │   ├── all.yaml              # Non-secret configuration (user, domain, paths, service list, tools, backup schedule)
│   │   ├── secrets.yaml          # Encrypted secrets (Ansible Vault) — NOT committed in plaintext
│   │   └── secrets.yaml.example  # Template showing the secrets structure
│   │
│   ├── inventory/                # Which hosts to target
│   │   ├── vagrant/              # Local test VM (bootstrap + main inventories)
│   │   └── contabo/              # Production VPS (bootstrap + main inventories), uses an SSH alias, not a hardcoded IP
│   │
│   ├── playbooks/
│   │   ├── bootstrap.yaml        # Phase 1: initial server setup (run as root)
│   │   └── main.yaml             # Phase 2: tools, docker, firewall, ssh hardening, services, backups
│   │
│   ├── roles/
│   │   ├── tools/                 # CLI utilities (fish, btop, ctop, etc), fish as default shell, hostname, MOTD removal
│   │   ├── docker/                # Docker Engine + Compose plugin installation
│   │   ├── firewall/              # UFW configuration (allows SSH, HTTP, HTTPS)
│   │   ├── ssh/                   # SSH hardening (disable root login + password auth)
│   │   ├── services/               # Deploys each enabled service via Docker Compose
│   │   └── backup/                 # rclone + systemd timer, nightly OneDrive backup with ntfy notifications
│   │
│   └── services/                 # Service definitions
│       ├── service.env.j2        # Template that generates each service's .env file
│       ├── traefik/              # Reverse proxy
│       ├── syncbrowser/          # Syncthing + Filebrowser
│       ├── linkding/             # Bookmark manager
│       ├── radicale/             # CalDAV/CardDAV server
│       ├── vaultwarden/          # Self-hosted password manager
│       ├── kavita/               # Manga / comics / books / light novels server
│       ├── uptime-kuma/          # Service uptime monitoring
│       ├── beszel/               # Server + container resource monitoring (hub + agent)
│       └── ntfy/                 # Self-hosted push notifications
│
├── scripts/
│   └── test_setup.sh             # Smoke test for the Vagrant VM (ssh, sudo, firewall checks)
├── Vagrantfile                   # Local development VM definition
└── README.md
```

## Configuration

### Non-secret values — `group_vars/all.yaml`

| Variable               | Meaning                                                                           |
| :--------------------- | :-------------------------------------------------------------------------------- |
| `new_user`             | The deploy user Ansible creates and uses for phase 2.                             |
| `ssh_port`             | Port sshd listens on. Change from `22` if you want a non-standard port.           |
| `domain`               | Base domain. Services are routed at `<service>.<domain>`.                         |
| `server_hostname`      | System hostname set on the VPS (separate from the public domain).                 |
| `root_path`            | Where service compose files live on the server (`/home/<user>/Omrin`).            |
| `services_path`        | Where Ansible reads service compose definitions from in this repo.                |
| `data_path`            | Where persistent service data is stored (`/data/omrin`).                          |
| `ssh_public_key_path`  | Local path to the public key installed for the deploy user.                       |
| `apt_tools`            | List of CLI tools installed via apt (fish, btop, htop, tmux, jq, etc).            |
| `onedrive_backup_path` | Folder name created in OneDrive root for backups.                                 |
| `backup_schedule`      | systemd `OnCalendar` time for the nightly backup (server-local time).             |
| `backup_exclude_paths` | Glob patterns excluded from the backup sync (e.g. raw `pgdata` covered by dumps). |
| `services`             | List of services with an `enabled` flag. Toggle a service off to stop it.         |

### Secrets — `group_vars/secrets.yaml` (Ansible Vault)

Secrets are encrypted with Ansible Vault and decrypted at runtime using the vault password file. The structure (see `secrets.yaml.example`):

```yaml
email: you@example.com # used by Traefik for Let's Encrypt registration

# Full contents of ~/.config/rclone/rclone.conf after authorizing the
# OneDrive remote locally (see Backups section below). Remote must be
# named [onedrive].
rclone_config: |
  [onedrive]
  type = onedrive
  token = {"access_token":"...", ...}
  drive_id = ...
  drive_type = personal

# ntfy topic for backup notifications. Treat like a secret - anyone who
# knows the topic name can publish/subscribe to it on a public instance.
ntfy_backup_topic: "your-private-topic-name"

service_secrets:
  vaultwarden: {}
  radicale: {}
  linkding:
    SUPERUSER_NAME: aditya
    SUPERUSER_PASSWORD: changeme
  beszel:
    LISTEN: "45876"
    KEY: "..."
    TOKEN: "..."
```

Each key under `service_secrets.<name>` becomes an environment variable in that service's `.env` file. Services that need no extra variables can be omitted entirely (the template skips any service with no entry).

To edit secrets:

```bash
cd ansible
ansible-vault edit group_vars/secrets.yaml --vault-password-file=../.vault_pass
```

### How env files are generated

The `services/service.env.j2` template runs once per enabled service and writes a `.env` next to its compose file. Every service automatically gets:

```
DATA_PATH=<data_path>
DOMAIN=<domain>
EMAIL=<email>
```

plus any key/value pairs defined under `service_secrets.<name>`.

## Prerequisites

On your **local machine** (the control node):

- Ansible (`ansible-core` or full `ansible`)
- The `community.docker` collection:
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yaml
  ```
- An SSH keypair whose public key path matches `ssh_public_key_path` in `all.yaml`
- A vault password file at `.vault_pass` (gitignored). Copy `.vault_pass_example` and put your real vault password in it.
- `rclone` installed locally, for the one-time OneDrive authorization (see [Backups](#backups))

On the **target server**:

- A fresh Debian 12 (Bookworm) install with root SSH access.

## Deploying to a fresh VPS

These steps assume a brand-new Debian 12 VPS where you can SSH in as `root`.

### 1. Point DNS at the server

Create an **A record** for your base domain and a **wildcard** (or per-service) record pointing at the VPS IP, so Traefik can route subdomains and pass Let's Encrypt's HTTP challenge:

```
A   omrin.in       <VPS_IP>
A   *.omrin.in     <VPS_IP>
```

### 2. Add an SSH alias

So nothing hardcodes the IP. In `~/.ssh/config`:

```
Host omrin
    HostName <VPS_IP>
    User aditya
    IdentityFile ~/.ssh/personal
```

The Contabo inventories reference the host `omrin`, which resolves through this config. (During bootstrap, before the deploy user exists, Ansible connects as `root` directly via the inventory file instead.)

### 3. Configure your values

- Edit `ansible/group_vars/all.yaml` — set `domain`, `server_hostname`, confirm `new_user`, and adjust `ssh_port` if desired.
- Create/edit `ansible/group_vars/secrets.yaml` from the example, with your real email and any service secrets.

### 4. Run phase 1 — bootstrap (as root)

```bash
cd ansible
ansible-playbook playbooks/bootstrap.yaml \
  -i inventory/contabo/contabo-bootstrap.yaml
```

This creates your deploy user and installs your SSH key. **Verify you can log in as the deploy user before continuing:**

```bash
ssh aditya@<VPS_IP>     # or: ssh -p <ssh_port> aditya@<VPS_IP>
```

### 5. Run phase 2 — main deploy (as the deploy user)

```bash
ansible-playbook playbooks/main.yaml \
  -i inventory/contabo/contabo-main.yaml \
  --vault-password-file=../.vault_pass
```

This installs CLI tools, sets the hostname, removes the MOTD, installs Docker, locks down SSH and the firewall, starts every enabled service, and sets up nightly backups. Once it finishes, your services are reachable at `https://<service>.<domain>` with valid TLS certificates.

> **Note:** if you changed `ssh_port`, after phase 2 you must connect on the new port. Update the `Port` in your `~/.ssh/config` accordingly. Also reconnect with a fresh SSH session afterward to land in `fish` instead of the shell your session started with.

## Re-running a single part of the stack

Every role in `main.yaml` is tagged, so you don't need to re-run the whole playbook for a small change:

```bash
ansible-playbook playbooks/main.yaml -i inventory/contabo/contabo-main.yaml \
  --vault-password-file=../.vault_pass --tags services   # just redeploy compose files
  # other tags: tools, docker, firewall, ssh, backup
```

## Adding a new service

1. Create `ansible/services/<name>/docker-compose.yaml`. Reference env vars with `${VAR:?}` so deployment fails loudly if a var is missing. Attach it to the shared `proxy` network and add Traefik labels to expose it over HTTPS:

   ```yaml
   services:
     <name>:
       ...
       networks:
         - proxy
       labels:
         - traefik.enable=true
         - traefik.http.routers.<name>.rule=Host(`<name>.${DOMAIN:?}`)
         - traefik.http.routers.<name>.entrypoints=websecure
         - traefik.http.routers.<name>.tls.certresolver=letsencrypt
         - traefik.http.services.<name>.loadbalancer.server.port=<internal-port>

   networks:
     proxy:
       external: true
   ```

   Mount persistent data under `${DATA_PATH:?}/<name>/...` so it's automatically covered by the nightly backup.

2. If the service needs secrets or extra env vars, add them under `service_secrets.<name>` in the vault.
3. Add the service to the `services` list in `all.yaml` with `enabled: true`.
4. Re-run the main playbook (or just `--tags services`).

To disable a service, set `enabled: false` — the next run stops and removes it.

### Postgres-backed services

For any service with its own Postgres database, run a `pgbackup` sidecar container alongside it (using `prodrigestivill/postgres-backup-local`) instead of relying on file-level sync of the live `pgdata` directory, which isn't crash-consistent. The sidecar dumps to `${DATA_PATH}/<name>/db_dumps` on its own schedule with built-in retention (daily/weekly/monthly). Add the raw `pgdata` path to `backup_exclude_paths` in `all.yaml` once you do this, since the dumps already cover that data.

## Backups

Nightly, all of `data_path` is synced to OneDrive via `rclone`, scheduled with a systemd timer (`omrin-backup.timer` / `omrin-backup.service`), with ntfy notifications sent at start, on success, and on failure (with error details).

### One-time setup (per machine you authorize from)

OneDrive auth requires an interactive browser step, so it can't be done by Ansible directly:

1. Install rclone locally and authorize a remote named `onedrive`:
   ```bash
   curl https://rclone.org/install.sh | sudo bash
   rclone config   # create remote "onedrive", type "onedrive", region "global", auto config via browser
   ```
2. Verify it works: `rclone lsd onedrive:`
3. Copy `~/.config/rclone/rclone.conf` into `rclone_config` in the vault (see [Secrets](#secrets--group_varssecretsyaml-ansible-vault) above).
4. Add a private `ntfy_backup_topic` to the vault, and subscribe to it in the ntfy mobile app pointed at `https://ntfy.<domain>`.
5. Deploy: `--tags backup`.

> rclone on the server must be a recent release (installed via the official install script, not Debian's stale apt package) — older versions have a known bug where OneDrive uploads silently fail with `unauthenticated` even though reads succeed and the token is valid.

### Verifying backups

```bash
sudo systemctl start omrin-backup.service   # trigger a backup immediately instead of waiting for the schedule
journalctl -u omrin-backup.service -f       # watch it run
systemctl list-timers omrin-backup.timer    # confirm the next scheduled run
tail -f ~/.local/log/omrin-backup.log       # backup log
```

### Restoring

```bash
docker compose -f ~/Omrin/<service>/docker-compose.yaml down
# extract/copy the backed-up data into /data/omrin/<service>/...
docker compose -f ~/Omrin/<service>/docker-compose.yaml up -d
```

For Postgres-backed services, restore via the `db_dumps/*.sql.gz` dump (`psql` or `pg_restore`) rather than copying `pgdata` directly.

## Local testing with Vagrant

To test the full provisioning flow in a throwaway VM before deploying to production:

```bash
vagrant up          # boots a Debian 12 VM and runs both playbooks
./scripts/test_setup.sh   # smoke-tests ssh, sudo, and firewall
vagrant destroy     # tear it down
```

The Vagrantfile runs `bootstrap` then `main` automatically, using the `inventory/vagrant/` inventories.

## License

MIT — see [LICENSE](./LICENSE).
