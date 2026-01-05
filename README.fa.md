<!-- Language Switcher -->
<p align="center">
  <b>🌐 این صفحه:</b> فارسی &nbsp;|&nbsp;
  <a href="./README.md"><b>English</b></a>
</p>

<h1 align="center">🚀 اسکریپت نصب خودکار پنل Remnawave</h1>
<p align="center"><b>نصب سریع تک‌خطی + مدیریت کامل پنل و نود (Production-grade)</b></p>

<p align="center">
  <a href="#">
    <img src="https://badges.strrl.dev/visits/power0matin/remnawave-panel-manager?style=flat&labelColor=333333&logoColor=E7E7E7&label=Visits&logo=github" />
  </a>
  <a href="#">
    <img src="https://img.shields.io/github/stars/power0matin/remnawave-panel-manager?style=flat&labelColor=333333&logoColor=E7E7E7&color=EEAA00&label=Stars&logo=github" />
  </a>
</p>

## ✅ این اسکریپت چه کارهایی انجام می‌دهد؟

- نصب Docker (به روش رسمی و پایدار)
- راه‌اندازی دیتابیس Postgres
- راه‌اندازی Valkey/Redis
- نصب و راه‌اندازی پنل Remnawave
- نصب Caddy و گرفتن SSL خودکار (HTTPS)
- ابزارهای مدیریتی: وضعیت، لاگ، آپدیت، بکاپ، حذف کامل

## ⚡ روش نصب سریع (تک خطی)

> پیشنهاد شده (با دسترسی روت):

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/power0matin/remnawave-panel-manager/main/install.sh)
```

### اجرای مستقیم با آرگومان (بدون منو)

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/power0matin/remnawave-panel-manager/main/install.sh) install-panel --domain panel.example.com --email admin@example.com
```

## 🧑‍🔧 نصب دستی (برای افراد حرفه‌ای)

```bash
sudo apt-get update -y
sudo apt-get install -y git

git clone https://github.com/power0matin/remnawave-panel-manager.git
cd remnawave-panel-manager

chmod +x remnawave-manager.sh
sudo ./remnawave-manager.sh install-panel --domain panel.example.com --email admin@example.com
```

✅ بعد از نصب:

- آدرس پنل: `https://panel.example.com`
- فایل تنظیمات: `/opt/remnawave/.env`

## 🧩 نصب نود (روی سرور نود)

### روش سریع

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/power0matin/remnawave-panel-manager/main/install.sh) install-node
```

### روش دستی

```bash
git clone https://github.com/power0matin/remnawave-panel-manager.git
cd remnawave-panel-manager

chmod +x remnawave-manager.sh
sudo ./remnawave-manager.sh install-node
```

سپس از پنل مسیر زیر را بروید و compose را paste کنید:
**Panel → Nodes → Create Node**

## 🧰 دستورات مدیریتی

```bash
sudo ./remnawave-manager.sh status
sudo ./remnawave-manager.sh logs --panel --tail 200
sudo ./remnawave-manager.sh update --panel
sudo ./remnawave-manager.sh backup --panel
sudo ./remnawave-manager.sh uninstall-panel
```

## 📜 لایسنس

MIT

<p align="center">
  © ساخته شده توسط <a href="https://github.com/power0matin">power0matin</a>
</p>
