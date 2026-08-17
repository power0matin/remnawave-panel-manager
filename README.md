<!-- Language Switcher -->
<p align="center">
  <b>🌐 This page:</b> English &nbsp;|&nbsp;
  <a href="./README.fa.md"><b>فارسی</b></a>
</p>

<h1 align="center">🚀 Remnawave Panel Manager</h1>

<!-- repo-badges:start -->
<p align="center">
  <a href="https://hits.sh/github.com/power0matin/remnawave-panel-manager/"><img src="https://hits.sh/github.com/power0matin/remnawave-panel-manager.svg?style=flat-square&amp;label=Views&amp;labelColor=18181B&amp;color=0EA5E9&amp;logo=github" alt="Repository Views"/></a>
  <a href="https://github.com/power0matin/remnawave-panel-manager/stargazers"><img src="https://img.shields.io/github/stars/power0matin/remnawave-panel-manager?style=flat-square&amp;label=Stars&amp;labelColor=18181B&amp;color=F59E0B&amp;logo=github&amp;logoColor=white" alt="GitHub Stars"/></a>
  <a href="https://github.com/power0matin/remnawave-panel-manager/forks"><img src="https://img.shields.io/github/forks/power0matin/remnawave-panel-manager?style=flat-square&amp;label=Forks&amp;labelColor=18181B&amp;color=6366F1&amp;logo=github&amp;logoColor=white" alt="GitHub Forks"/></a>
  <a href="https://github.com/power0matin/remnawave-panel-manager/issues"><img src="https://img.shields.io/github/issues/power0matin/remnawave-panel-manager?style=flat-square&amp;label=Issues&amp;labelColor=18181B&amp;color=22C55E&amp;logo=github&amp;logoColor=white" alt="GitHub Issues"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/power0matin/remnawave-panel-manager?style=flat-square&amp;label=License&amp;labelColor=18181B&amp;color=EF4444&amp;logo=github&amp;logoColor=white" alt="GitHub License"/></a>
</p>
<!-- repo-badges:end -->

<p align="center"><b>One-command installer & production-grade lifecycle manager for Remnawave Panel and Nodes</b></p>

<p align="center">
  <a href="https://github.com/power0matin/remnawave-panel-manager">
  </a>
  <a href="https://github.com/power0matin/remnawave-panel-manager/stargazers">
    <img src="https://img.shields.io/github/stars/power0matin/remnawave-panel-manager?style=flat&labelColor=333333&logoColor=E7E7E7&color=EEAA00&label=Stars&logo=github" />
  </a>
  <a href="./LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-success.svg" alt="License" />
  </a>
  <a href="https://github.com/power0matin/remnawave-panel-manager/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/power0matin/remnawave-panel-manager/ci.yml?label=CI&logo=github" alt="CI" />
  </a>
  <img src="https://img.shields.io/github/last-commit/power0matin/remnawave-panel-manager" alt="Last commit" />
  <img src="https://img.shields.io/github/issues/power0matin/remnawave-panel-manager" alt="Open issues" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Docker-required-0ea5e9?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/Caddy-Auto%20HTTPS-10b981?logo=caddy&logoColor=white" alt="Caddy" />
  <img src="https://img.shields.io/badge/PRs-welcome-10b981" alt="PRs welcome" />
</p>

## 📝 Overview

**Remnawave DeployKit** is a **production-grade Bash toolkit** that installs and manages:

- **Remnawave Panel** (Backend + Postgres + Valkey/Redis + Caddy)
- **Remnawave Nodes** (by pasting the Node compose from your panel)

It focuses on:

- **Reliability** (strict bash mode, validation, safer defaults)
- **Security** (random secrets, restricted .env permissions, localhost bind)
- **Operational UX** (clear commands: install/update/logs/status/backup/uninstall)

> This project is an unofficial deployment helper. Use at your own risk.

## ✨ Highlights

- ✅ Secure-by-default `.env` generation (random DB password & secrets)
- ✅ Caddy reverse proxy with **automatic HTTPS** (Let’s Encrypt)
- ✅ Services exposed safely (backend bound to `127.0.0.1`, public via Caddy only)
- ✅ Lifecycle commands: **install / uninstall / status / logs / update / backup**
- ✅ Docker installed via **official repository** (more stable than curl|sh)
- ✅ CI-ready (ShellCheck) for team-grade maintainability

## 🛡️ Requirements

### Server

- Debian/Ubuntu (APT-based)
- Root access (sudo)
- Open ports: `80/tcp`, `443/tcp`, `443/udp`
- DNS **A record** for your panel domain pointing to the server IP

### Local

- `git`

## ⚡ Quick Install (One-liner)

> Recommended (runs as root via sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/remnawave-panel-manager/main/install.sh | sudo bash
```

### Direct install (no menu)

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/remnawave-panel-manager/main/install.sh | sudo bash -s -- install-panel --domain panel.example.com --email admin@example.com
```

> Security note: Running remote scripts is convenient but trust-sensitive. Use the manual install below if you prefer to review the code first.

## 🧑‍🔧 Manual Install (Recommended for advanced users)

```bash
sudo apt-get update -y
sudo apt-get install -y git

git clone https://github.com/power0matin/remnawave-panel-manager.git
cd remnawave-panel-manager

chmod +x remnawave-manager.sh
sudo ./remnawave-manager.sh install-panel --domain panel.example.com --email admin@example.com
```

✅ After installation:

- Panel URL: `https://panel.example.com`
- Config: `/opt/remnawave/.env`

## 🧩 Install Node (on a Node server)

```bash
sudo apt-get update -y
sudo apt-get install -y git

git clone https://github.com/power0matin/remnawave-panel-manager.git
cd remnawave-panel-manager

chmod +x remnawave-manager.sh
sudo ./remnawave-manager.sh install-node
```

The script will open an editor. Paste the **docker-compose.yml** provided by your panel under:
**Panel → Nodes → Create Node**

## 🧰 Operations

### Status

```bash
sudo ./remnawave-manager.sh status
```

### Logs

```bash
sudo ./remnawave-manager.sh logs --panel --tail 200
sudo ./remnawave-manager.sh logs --node  --tail 200
```

### Update (pull latest images + recreate)

```bash
sudo ./remnawave-manager.sh update --panel
sudo ./remnawave-manager.sh update --node
```

### Backup

```bash
sudo ./remnawave-manager.sh backup --panel
sudo ./remnawave-manager.sh backup --node --out /root/node-backup.tgz
```

### Uninstall

```bash
sudo ./remnawave-manager.sh uninstall-panel --yes
sudo ./remnawave-manager.sh uninstall-node  --yes
```

## 🔒 Security Notes (Recommended)

- Use a **fresh server** and keep it updated:

  ```bash
  sudo apt-get update -y && sudo apt-get upgrade -y
  ```

- Ensure firewall allows only required ports (80/443 + SSH):

  - UFW example:

    ```bash
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 443/udp
    sudo ufw enable
    ```

- `.env` secrets are generated automatically and saved at:

  - `/opt/remnawave/.env` (permissions set to `600`)

- Backend is exposed only on **localhost** (`127.0.0.1:3000`) and served publicly through Caddy.

## 🧯 Troubleshooting

### 1) Domain / SSL issues

- Check DNS A record points to the correct server IP.
- Confirm ports `80/443` are open and not used by another service.

### 2) Check services

```bash
sudo ./remnawave-manager.sh status
```

### 3) Check logs

```bash
sudo ./remnawave-manager.sh logs --panel --tail 300
```

### 4) Caddy certificate problems

- Sometimes DNS propagation delays can cause TLS failures. Wait a few minutes and retry:

```bash
sudo ./remnawave-manager.sh update --panel
```

## 🗂️ Project Structure

```text
.
├─ remnawave-manager.sh
├─ README.md
├─ README.fa.md
├─ LICENSE
└─ .github/
   └─ workflows/
      └─ ci.yml
```

## 🤝 Contributing

PRs are welcome.

### Guidelines

- Keep scripts ShellCheck-clean
- Prefer small, focused changes

Suggested commit format (Conventional Commits):

```text
feat: add non-interactive mode
fix: improve domain validation
docs: update README with firewall notes
```

## 🧭 Roadmap

- [ ] Non-interactive install mode (CI/provisioning friendly)
- [ ] Built-in DNS / port checks
- [ ] Automated backups for DB volumes
- [ ] Optional fail2ban + hardened SSH recommendations

## 📜 License

This project is licensed under the **MIT License** — see [LICENSE](./LICENSE).

## 📬 Contact

**Matin Shahabadi (متین شاه‌آبادی / متین شاه آبادی)**

- Website: [https://matinshahabadi.ir](https://matinshahabadi.ir)
- Email: [me@matinshahabadi.ir](mailto:me@matinshahabadi.ir)
- GitHub: [https://github.com/power0matin](https://github.com/power0matin)
- LinkedIn: [https://www.linkedin.com/in/matin-shahabadi](https://www.linkedin.com/in/matin-shahabadi)

[![Stargazers over time](https://starchart.cc/power0matin/remnawave-panel-manager.svg?variant=adaptive)](https://starchart.cc/power0matin/remnawave-panel-manager)

<p align="center">
  © Created by <a href="https://github.com/power0matin">power0matin</a>
</p>
