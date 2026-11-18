#!/bin/bash
# Показывает, какой контейнер занимает 80/443 и как он маршрутизирует домены.
python3 - <<'PY'
import json, subprocess

ids = subprocess.check_output(["docker", "ps", "-q"], text=True).split()
print("== containers ==")
print(subprocess.check_output(
    ["docker", "ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}"],
    text=True,
))

def interesting(key: str) -> bool:
    k = key.lower()
    return any(s in k for s in (
        "traefik", "caddy", "nginx", "virtual", "compose.project",
        "compose.service", "coolify", "dokploy", "host", "rule",
    ))

for cid in ids:
    data = json.loads(subprocess.check_output(["docker", "inspect", cid], text=True))[0]
    ports = data["NetworkSettings"].get("Ports") or {}
    published = []
    for port, binds in ports.items():
        if binds and (port.startswith("80/") or port.startswith("443/")):
            published.append(port + "->" + ",".join(b.get("HostPort", "") for b in binds))
    if not published:
        continue
    name = data["Name"].lstrip("/")
    print(f"== publisher {name} ==")
    print("image", data["Config"].get("Image"))
    print("ports", ", ".join(published))
    labels = data["Config"].get("Labels") or {}
    for key in sorted(labels):
        if interesting(key):
            print(f"label {key}={labels[key][:240]}")
    for item in data.get("Mounts") or []:
        print(f"mount {item.get('Source')} -> {item.get('Destination')}")
    for entry in data["Config"].get("Env") or []:
        upper = entry.upper()
        if any(s in upper for s in ("PASSWORD", "SECRET", "TOKEN", "KEY", "DATABASE_URL")):
            continue
        if any(s in upper for s in ("HOST", "DOMAIN", "ACME", "LETSENCRYPT", "TRAEFIK", "VIRTUAL", "CADDY")):
            print("env", entry[:240])
PY
