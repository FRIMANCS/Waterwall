#!/bin/bash
set -e

INSTALL_DIR="/opt/waterwall"
SERVICE_FILE="/etc/systemd/system/waterwall.service"
DOWNLOAD_URL="https://github.com/FRIMANCS/Waterwall/raw/main/Waterwall"

echo "📦 نصب خودکار Waterwall"

# 🧼 حذف نسخه قبلی
if [ -d "$INSTALL_DIR" ]; then
    echo "🧼 حذف نسخه قبلی..."
    systemctl stop waterwall || true
    systemctl disable waterwall || true
    rm -rf "$INSTALL_DIR"
fi

# 📦 پیش‌نیازها
apt update -y && apt install -y curl unzip

# 📁 مسیر نصب
mkdir -p "$INSTALL_DIR/log" "$INSTALL_DIR/libs"

# ⬇️ دانلود فایل اجرایی
curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/Waterwall"
chmod +x "$INSTALL_DIR/Waterwall"

# ❓ گرفتن اطلاعات از کاربر
echo "🌍 این سرور داخل ایران است یا خارج؟"
echo "1) ایران"
echo "2) خارج"
read -p "↪ انتخاب شما (1 یا 2): " LOC_CHOICE

read -p "🟢 وارد کنید IP ایران (مثلاً 1.1.1.1): " IR_IP
read -p "🔵 وارد کنید IP خارج (مثلاً 2.2.2.2): " KH_IP
read -p "🟢 وارد کنید IP محلی تونل (مثلاً 10.10.0.1): " TUN_LOCAL
read -p "🔵 وارد کنید IP مقابل تونل (مثلاً 10.10.0.2): " TUN_REMOTE

# ✅ بر اساس انتخاب، فایل جدا بساز
if [[ "$LOC_CHOICE" == "1" ]]; then
    CONFIG_NAME="config_ir.json"
    echo "📄 در حال ساخت فایل کانفیگ مخصوص سرور ایران..."

    cat > "$INSTALL_DIR/$CONFIG_NAME" <<EOF
{
    "name": "iran",
    "nodes": [
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "wtun0",
                "device-ip": "$TUN_LOCAL/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "$IR_IP"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "$KH_IP"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap": 132
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "$TUN_REMOTE"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "$TUN_LOCAL"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "$KH_IP"
            }
        }
    ]
}
EOF

else
    CONFIG_NAME="config_kh.json"
    echo "📄 در حال ساخت فایل کانفیگ مخصوص سرور خارج..."

    cat > "$INSTALL_DIR/$CONFIG_NAME" <<EOF
{
    "name": "kharej",
    "nodes": [
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "wtun0",
                "device-ip": "$TUN_LOCAL/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "$KH_IP"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "$IR_IP"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap": 132
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "$TUN_REMOTE"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "$TUN_LOCAL"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "$IR_IP"
            }
        }
    ]
}
EOF

fi

# 🔧 core.json
cat > "$INSTALL_DIR/core.json" <<EOF
{
  "log": {
    "path": "log/",
    "internal": {
      "loglevel": "DEBUG",
      "file": "internal.log",
      "console": true
    },
    "core": {
      "loglevel": "DEBUG",
      "file": "core.log",
      "console": true
    },
    "network": {
      "loglevel": "DEBUG",
      "file": "network.log",
      "console": true
    },
    "dns": {
      "loglevel": "SILENT",
      "file": "dns.log",
      "console": false
    }
  },
  "dns": {},
  "misc": {
    "workers": 4,
    "ram-profile": "client",
    "libs-path": "libs/"
  },
  "configs": [
    "$CONFIG_NAME"
  ]
}
EOF

# 🧩 systemd
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Waterwall Tunnel Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/Waterwall -c core.json
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 🟢 فعال‌سازی
systemctl daemon-reload
systemctl enable waterwall
systemctl restart waterwall

echo "✅ نصب کامل شد!"
echo "📝 کانفیگ ساخته‌شده: $CONFIG_NAME"
