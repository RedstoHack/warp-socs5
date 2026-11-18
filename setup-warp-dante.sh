#!/bin/bash

set -e

echo "=== Настройка WARP + Dante ==="

# 1. Установка пакетов
sudo apt-get update
sudo apt-get install wireguard-tools wireguard dante-server curl -y

# 2. Установка wgcf
curl -LJO https://github.com/ViRb3/wgcf/releases/download/v2.2.23/wgcf_2.2.23_linux_amd64
chmod +x wgcf_2.2.23_linux_amd64
sudo mv wgcf_2.2.23_linux_amd64 /usr/local/bin/wgcf

# 3. Настройка WireGuard
wgcf register --accept-tos
wgcf generate
sudo mkdir -p /etc/wireguard
sudo cp wgcf-profile.conf /etc/wireguard/warp.conf
sudo sed -i '/^\[Interface\]/a Table = off' /etc/wireguard/warp.conf
sudo sed -i 's/engage.cloudflareclient.com/162.159.192.1/g' /etc/wireguard/warp.conf

# 4. Запуск WireGuard
sudo systemctl enable wg-quick@warp
sudo systemctl start wg-quick@warp

# 5. Настройка Dante
sudo tee /etc/danted.conf > /dev/null << 'EOF'
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

internal: 127.0.0.1 port = 1080
external: warp

socksmethod: none
clientmethod: none

client pass {
    from: 127.0.0.0/8 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: error
}
EOF

# 6. Запуск Dante
sudo systemctl enable danted
sudo systemctl restart danted

# 7. Маршрут для nobody
sudo ip rule add from all uidrange 65534-65534 lookup 200 2>/dev/null || true
sudo ip route add default dev warp table 200 2>/dev/null || true

# 8. Автозагрузка маршрута
sudo tee /etc/systemd/system/warp-route.service > /dev/null << 'EOF'
[Unit]
Description=Add route for nobody to use warp interface
After=wg-quick@warp.service
Requires=wg-quick@warp.service
Before=danted.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/bin/sh -c 'ip rule add from all uidrange 65534-65534 lookup 200 2>/dev/null || true; ip route add default dev warp table 200 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable warp-route.service
sudo systemctl start warp-route.service

# 9. Проверка
echo ""
echo "=== Проверка ==="
sleep 3
ping -I warp 8.8.8.8 -c 2
echo ""
curl --socks5 127.0.0.1:1080 https://ifconfig.me

echo ""
echo "=== Установка завершена! ==="
