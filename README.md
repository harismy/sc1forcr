# SC 1FORCR AutoScript

AutoScript untuk VPS Debian 12+ / Ubuntu 22+ dengan fitur:

- SSH
- VMess / VLESS / Trojan (Xray)
- UDP + ZIVPN
- Nginx + SSL Let's Encrypt
- API kompatibel endpoint `/vps/*` (agar bot lama tetap jalan)
- Menu CLI `menu` / `menu-sc-1forcr`
- Auto lock sementara 15 menit jika pemakaian IP melebihi `limitip` (cek tiap 15 menit)

---

## 1) Requirement

- OS: Debian 12+ atau Ubuntu 22+
- Domain sudah diarahkan ke IP VPS (A record)
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

Menu utama:

1. Add Account  
2. Renew Account  
3. Delete Account  
4. List Account  
5. Service Menu  
6. Backup/Restore ZIVPN Config  
7. Ganti Domain + Renew SSL  
8. Monitor Lock Sementara (IP Limit)  
9. Uninstall SC 1FORCR

---

## 4) Service yang dipakai

- `sc-1forcr-api.service`
- `sc-1forcr-iplimit.timer`
- `sc-1forcr-iplimit.service`
- `xray.service`
- `nginx.service`
- `ssh.service`
- `zivpn.service` (jika binary tersedia)

Cek status:

```bash
systemctl status sc-1forcr-api sc-1forcr-iplimit.timer xray nginx ssh
```

---

## 5) Uninstall

Dari menu: pilih nomor `9`, atau:

```bash
uninstall-sc-1forcr
```

> Uninstall ini tidak menghapus service inti seperti `nginx`, `xray`, `ssh`, `zivpn`.

---

## 6) Troubleshooting

### A) Certbot gagal (invalid email)

Gunakan email valid (boleh Gmail), contoh:

```bash
EMAIL=namakamu@gmail.com
```

### B) Certbot gagal (domain belum resolve)

- Pastikan A record domain ke IP VPS
- Cek:

```bash
dig +short tes.prem-1forcr.shop
```

### C) Cek log API

```bash
journalctl -u sc-1forcr-api -f
```

### D) Cek lock sementara IP-limit

- dari menu pilih `8`
- atau query DB:

```bash
sqlite3 /usr/sbin/potatonc/potato.db "SELECT * FROM temp_ip_locks;"
```

