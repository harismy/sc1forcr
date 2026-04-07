# SC 1FORCR Nexus AutoScript

AutoScript gratis dan open source untuk VPS dengan fitur:

- SSH (OpenSSH + Dropbear)
- VMess / VLESS / Trojan (Xray)
- UDP backend: ZIVPN atau UDP Custom (single active backend)
- Nginx + Let's Encrypt + HAProxy TLS mux
- API kompatibel endpoint dengan bot 1FORCR`/vps/*` (bot lama tetap jalan)
- Menu CLI `menu` / `menu-sc-1forcr`
- Trial account (auto-delete 1 jam dari menu akun)
- Auto lock sementara 15 menit saat melampaui `limitip`

---

## 1) Requirement

- OS: Debian 10+ atau Ubuntu 20+
- Domain sudah diarahkan ke IP VPS (A record) di cloudflare
- Jalankan sebagai `root`

---

## 2) Install

```bash
curl -fL --retry 5 --retry-delay 2 https://raw.githubusercontent.com/harismy/sc1forcr/main/setup-autoscript-compat.sh -o /tmp/setup-autoscript-compat.sh
sed -i 's/\r$//' /tmp/setup-autoscript-compat.sh
chmod +x /tmp/setup-autoscript-compat.sh
bash /tmp/setup-autoscript-compat.sh
```

## 3) Menu VPS

Jalankan:

```bash
menu
```

atau:

```bash
menu-sc-1forcr
```

### Menu utama

1. Menu Akun
2. Service Menu
3. Backup/Restore
4. Change Domain
5. Monitor User Lock
6. Monitor User Login
7. Tools

### Menu Akun

1. Add Account
2. Trial Account (1 jam)
3. Renew Account
4. Edit Limit IP
5. Delete Account
6. List Account (termasuk kolom `LIM_IP`)
7. Unlock Account

### Tools

1. Informasi Key SC
2. Install API Summary 1FORCR
3. Setting Banner HTML (SSH/Dropbear)
4. Update Script

---

## 4) Endpoint API yang dipakai bot

Contoh endpoint utama:

- SSH/ZIVPN:
  - Create: `/vps/sshvpn`
  - Trial: `/vps/trialsshvpn`
  - Renew: `/vps/renewsshvpn/:username/:exp`
  - Delete: `/vps/deletesshvpn/:username`
- VMess:
  - `/vps/vmessall`, `/vps/trialvmessall`, `/vps/renewvmess/:username/:exp`, `/vps/deletevmess/:username`
- VLESS:
  - `/vps/vlessall`, `/vps/trialvlessall`, `/vps/renewvless/:username/:exp`, `/vps/deletevless/:username`
- Trojan:
  - `/vps/trojanall`, `/vps/trialtrojanall`, `/vps/renewtrojan/:username/:exp`, `/vps/deletetrojan/:username`

---

## 5) Service yang dipakai

- `sc-1forcr-api.service`
- `sc-1forcr-sshws.service`
- `sc-1forcr-iplimit.timer`
- `sc-1forcr-iplimit.service`
- `sc-1forcr-autoreboot.timer`
- `sc-1forcr-udp-bootfix.service`
- `xray.service`
- `nginx.service`
- `haproxy.service`
- `ssh.service`
- `dropbear.service`
- `zivpn.service` atau `sc-1forcr-udpcustom.service`

Cek status:

```bash
systemctl status sc-1forcr-api sc-1forcr-sshws sc-1forcr-iplimit.timer xray nginx haproxy ssh dropbear
```

---

## 6) Uninstall

Menu uninstall disembunyikan dari menu utama. Jika tetap dibutuhkan:

```bash
uninstall-sc-1forcr
```

Catatan: uninstall helper tidak menghapus seluruh komponen sistem inti (`nginx`, `xray`, `ssh`, cert, package apt, dll).

---

## 7) Troubleshooting

### A) Certbot gagal

- Pastikan domain A record sudah ke IP VPS.
- Cek resolve:

```bash
dig +short tes.prem-1forcr.shop
```

### B) Cek log API

```bash
journalctl -u sc-1forcr-api -f
```

### C) Cek lock sementara IP-limit

- Dari menu utama pilih `5) Monitor User Lock`
- Atau query DB:

```bash
sqlite3 /usr/sbin/potatonc/potato.db "SELECT * FROM temp_ip_locks;"
```

### D) ZIVPN/UDPHC setelah reboot

- Pastikan service boot-fix aktif:

```bash
systemctl status sc-1forcr-udp-bootfix.service
```

