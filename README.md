# [Xray-core](https://github.com/XTLS/Xray-core) v26.3.27 setup

## Get started
```bash
curl -fSsLO https://raw.githubusercontent.com/uules/xray-setup/main/setup.sh
chmod +x setup.sh
bash setup.sh
```

## Troubleshooting

**Xray fails to start:**
```bash
systemctl status xray
```

**Validate config manually:**
```bash
xray run -test -c /usr/local/etc/xray/config.json
```

**Port 443 already in use:**
```bash
ss -tlnp | grep :443