# Deployment Skill — Home Assistant + PostgreSQL Docker Compose

This document serves as a quick-reference deployment skill card for setting up and managing the Home Assistant + PostgreSQL Docker Compose stack.

---

## Skill Summary

| Field | Value |
|-------|-------|
| **Stack** | Home Assistant + PostgreSQL 16 |
| **Container Runtime** | Docker / Podman with `docker-compose` |
| **Default Ports** | HA: `8123`, PG: `5432` |
| **Config Location** | `./config/` |
| **Database** | Named Docker volume `postgres_data` |

---

## Pre-Flight Checklist

- [ ] Docker 20.10+ and Docker Compose V2 installed
- [ ] At least 2 GB RAM and 10 GB free disk
- [ ] Ports 8123 and 5432 are available
- [ ] `.env` file created from `.env.example`
- [ ] `config/secrets.yaml` created from `config/secrets.yaml.example`
- [ ] Passwords in `.env` and `secrets.yaml` match

---

## Deploy

```bash
# 1. Clone
git clone https://github.com/WOOWTECH/Woow_ha_docker_compose_all.git
cd Woow_ha_docker_compose_all

# 2. Configure
cp .env.example .env
# Edit .env — set POSTGRES_PASSWORD

cp config/secrets.yaml.example config/secrets.yaml
# Edit secrets.yaml — update recorder_db_url password

# 3. Launch
docker compose up -d

# 4. Verify
docker compose ps
docker exec ha_postgres pg_isready -U homeassistant
# Open http://<HOST>:8123
```

---

## Day-2 Operations

### Update

```bash
docker compose pull && docker compose up -d
```

### Backup

```bash
docker exec ha_postgres pg_dump -U homeassistant -d homeassistant | gzip > ha_backup_$(date +%Y%m%d).sql.gz
```

### Restore

```bash
docker compose stop homeassistant
gunzip -c ha_backup_YYYYMMDD.sql.gz | docker exec -i ha_postgres psql -U homeassistant -d homeassistant
docker compose start homeassistant
```

### Logs

```bash
docker compose logs -f homeassistant
docker compose logs -f postgres
```

### Health Check

```bash
docker compose ps
docker exec ha_postgres pg_isready -U homeassistant
curl -s http://localhost:8123/api/ -H "Authorization: Bearer YOUR_TOKEN" | head
```

### DB Size

```bash
docker exec -it ha_postgres psql -U homeassistant -d homeassistant -c "
SELECT pg_size_pretty(pg_database_size('homeassistant'));"
```

---

## Destroy (Full Reset)

```bash
docker compose down -v
rm -rf config/.storage config/home-assistant_v2.db
docker compose up -d
```

---

## Environment Variables Reference

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `POSTGRES_USER` | `homeassistant` | No | DB user |
| `POSTGRES_PASSWORD` | — | **Yes** | DB password |
| `POSTGRES_DB` | `homeassistant` | No | DB name |
| `POSTGRES_PORT` | `5432` | No | Exposed PG port |
| `HA_VERSION` | `stable` | No | HA image tag |
| `HA_PORT` | `8123` | No | Exposed HA port |
| `TZ` | `Asia/Taipei` | No | Timezone |

---

## Network Topology

```
Host:8123 ──► homeassistant ──► postgres:5432
                                  (ha_network)
```

Both containers share the `ha_network` bridge network. Home Assistant connects to PostgreSQL using the Docker service name `postgres` as hostname.

---

## Security Notes

- `.env` and `config/secrets.yaml` contain credentials — **never commit them**.
- Use a reverse proxy (Nginx, Traefik, Caddy) with TLS for internet-facing deployments.
- Restrict `POSTGRES_PORT` exposure if external DB access is not needed (remove the `ports` mapping in `docker-compose.yml`).
