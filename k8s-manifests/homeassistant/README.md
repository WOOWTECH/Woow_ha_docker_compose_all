# Home Assistant K3s/Kubernetes 部署指南

[English](#english) | [中文](#中文)

---

## English

### Overview

Open-source smart home automation platform supporting over 2000 IoT integrations. Home Assistant provides a unified interface for managing smart home devices, creating automations, and monitoring energy usage. This deployment includes a dedicated PostgreSQL 16 database for the recorder component, enabling long-term history storage and faster queries compared to the default SQLite.

> **GitHub Repo (Podman/Docker):** [Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)

### Architecture

```
                     Home Assistant K3s Architecture
 ============================================================================

   External Access              K3s Cluster (namespace: homeassistant)
  +----------------+       +--------------------------------------------------+
  |                |       |                                                  |
  |  Browser       |       |   +------------------------------------------+   |
  |  :18124  ------+--NodePort->|  Service: homeassistant                 |   |
  |                |       |   |  ClusterIP :8123                         |   |
  +----------------+       |   +-------------------+----------------------+   |
                           |                       |                          |
                           |                       v                          |
                           |   +------------------------------------------+   |
                           |   |  Pod: homeassistant (Deployment)         |   |
                           |   |  Image: home-assistant/home-assistant    |   |
                           |   |  Port: 8123                              |   |
                           |   |  Volume: /config (5Gi)                   |   |
                           |   |                                          |   |
                           |   |  Init Container: wait-for-postgres       |   |
                           |   +-------------------+----------------------+   |
                           |                       |                          |
                           |            Cluster-Internal DNS                  |
                           |     postgresql://postgres:5432/homeassistant     |
                           |                       |                          |
                           |                       v                          |
                           |   +------------------------------------------+   |
                           |   |  Pod: postgres (StatefulSet)             |   |
                           |   |  Image: postgres:16-alpine               |   |
                           |   |  Port: 5432                              |   |
                           |   |  Volume: /var/lib/postgresql/data (10Gi) |   |
                           |   +------------------------------------------+   |
                           |                                                  |
                           |   Service: postgres (ClusterIP :5432)            |
                           +--------------------------------------------------+
```

### Features

- Over 2000 IoT device integrations
- Visual automation editor and scripting engine
- Energy monitoring and statistics dashboard
- Companion mobile app (iOS/Android) with push notifications
- Dedicated PostgreSQL 16 recorder for long-term history
- Init container ensures database readiness before startup

### Quick Start

```bash
# 1. Update secrets before deploying
nano k8s-manifests/homeassistant/secret.yaml

# 2. Deploy all Home Assistant components
kubectl apply -k k8s-manifests/homeassistant/

# 3. Verify pods are running
kubectl -n homeassistant get pods

# 4. Watch Home Assistant startup logs
kubectl -n homeassistant logs deploy/homeassistant -f
```

### Configuration

#### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `TZ` | Timezone for the deployment | `Asia/Taipei` | Yes |

#### Secrets

Edit `secret.yaml` before deploying. The following secrets must be configured:

| Secret Key | Description | Default (change me!) |
|------------|-------------|----------------------|
| `POSTGRES_USER` | PostgreSQL username | `homeassistant` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `changeme` |
| `POSTGRES_DB` | PostgreSQL database name | `homeassistant` |

```bash
# Edit the secret file
nano k8s-manifests/homeassistant/secret.yaml
```

#### PostgreSQL Recorder Configuration

After first boot, add the recorder configuration to `/config/configuration.yaml` inside the Home Assistant pod:

```yaml
recorder:
  db_url: postgresql://homeassistant:<password>@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8
  purge_keep_days: 30
  commit_interval: 1
```

```bash
# Edit the configuration file
kubectl -n homeassistant exec -it deploy/homeassistant -- vi /config/configuration.yaml
```

### Accessing the Service

| Endpoint | URL | Protocol |
|----------|-----|----------|
| Home Assistant Web UI | `http://<node-ip>:18124` | HTTP (NodePort) |
| Internal (cluster) | `http://homeassistant.homeassistant.svc.cluster.local:8123` | HTTP |

On first access, you will be guided through the Home Assistant onboarding wizard to create your admin account and configure your home.

### Data Persistence

| PVC Name | Mount Path | Size | Purpose |
|----------|------------|------|---------|
| `ha-config` | `/config` | 5Gi | Home Assistant configuration, automations, scripts, blueprints |
| `postgres-data` | `/var/lib/postgresql/data` | 10Gi | PostgreSQL recorder database |

All PVCs use the `local-path` storage class (k3s default).

### Backup & Restore

#### Backup

```bash
# 1. Backup Home Assistant configuration
kubectl -n homeassistant exec deploy/homeassistant -- tar czf /tmp/ha-config-backup.tar.gz /config
kubectl -n homeassistant cp homeassistant/<ha-pod>:/tmp/ha-config-backup.tar.gz ./ha-config-backup.tar.gz

# 2. Backup PostgreSQL database
kubectl -n homeassistant exec sts/postgres -- pg_dump -U homeassistant homeassistant > ha-db-backup.sql
```

#### Restore

```bash
# 1. Restore Home Assistant configuration
kubectl -n homeassistant cp ./ha-config-backup.tar.gz homeassistant/<ha-pod>:/tmp/ha-config-backup.tar.gz
kubectl -n homeassistant exec deploy/homeassistant -- tar xzf /tmp/ha-config-backup.tar.gz -C /

# 2. Restore PostgreSQL database
kubectl -n homeassistant exec -i sts/postgres -- psql -U homeassistant homeassistant < ha-db-backup.sql

# 3. Restart Home Assistant to pick up restored config
kubectl -n homeassistant rollout restart deploy/homeassistant
```

### Useful Commands

```bash
# Check pod status
kubectl -n homeassistant get pods

# View Home Assistant logs
kubectl -n homeassistant logs deploy/homeassistant -f

# View PostgreSQL logs
kubectl -n homeassistant logs sts/postgres -f

# Restart Home Assistant
kubectl -n homeassistant rollout restart deploy/homeassistant

# Check configuration validity
kubectl -n homeassistant exec deploy/homeassistant -- python3 -m homeassistant --script check_config -c /config

# Test database connectivity from HA pod
kubectl -n homeassistant exec deploy/homeassistant -- \
  python3 -c "import psycopg2; psycopg2.connect('postgresql://homeassistant:changeme@postgres:5432/homeassistant')"
```

### Troubleshooting

#### Home Assistant pod stuck in Init (waiting for PostgreSQL)

The Home Assistant pod has an init container that waits for PostgreSQL to become available. Check PostgreSQL status:

```bash
kubectl -n homeassistant get pods -l component=postgres
kubectl -n homeassistant logs sts/postgres
```

#### Cannot discover devices on the local network

The deployment sets `hostNetwork: false` by default. If you need device discovery (mDNS, SSDP, UPnP), edit `homeassistant-deployment.yaml` and set:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

Then re-apply:

```bash
kubectl apply -k k8s-manifests/homeassistant/
```

#### Database connection errors in Home Assistant logs

Verify the recorder DB URL matches the credentials in `secret.yaml`:

```bash
# Test database connectivity from inside the HA pod
kubectl -n homeassistant exec deploy/homeassistant -- \
  python3 -c "import psycopg2; psycopg2.connect('postgresql://homeassistant:changeme@postgres:5432/homeassistant')"
```

#### Configuration check

```bash
kubectl -n homeassistant exec deploy/homeassistant -- python3 -m homeassistant --script check_config -c /config
```

#### Restart Home Assistant without losing the pod

```bash
kubectl -n homeassistant rollout restart deploy/homeassistant
```

### File Structure

```
homeassistant/
├── configmap.yaml                  # Environment variables (timezone)
├── homeassistant-deployment.yaml   # Deployment for Home Assistant pod (with init container)
├── homeassistant-service.yaml      # NodePort service (18124 -> 8123)
├── kustomization.yaml              # Kustomize resource list
├── namespace.yaml                  # Namespace: homeassistant
├── postgres-service.yaml           # ClusterIP service for PostgreSQL (5432)
├── postgres-statefulset.yaml       # StatefulSet for PostgreSQL 16
├── pvc.yaml                        # PersistentVolumeClaims for config and database
├── README.md                       # This file
└── secret.yaml                     # PostgreSQL credentials (change before deploy!)
```

---

## 中文

### 概述

Home Assistant 是開源智慧家庭自動化平台，支援超過 2000 種 IoT 整合。提供統一介面管理智慧家庭裝置、建立自動化、以及監控能源使用。本部署包含專用的 PostgreSQL 16 資料庫用於記錄器元件，實現長期歷史儲存及比預設 SQLite 更快的查詢效能。

> **GitHub Repo (Podman/Docker):** [Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)

### 架構圖

```
                     Home Assistant K3s 架構
 ============================================================================

   外部存取                   K3s 叢集 (namespace: homeassistant)
  +----------------+       +--------------------------------------------------+
  |                |       |                                                  |
  |  瀏覽器        |       |   +------------------------------------------+   |
  |  :18124  ------+--NodePort->|  Service: homeassistant                 |   |
  |                |       |   |  ClusterIP :8123                         |   |
  +----------------+       |   +-------------------+----------------------+   |
                           |                       |                          |
                           |                       v                          |
                           |   +------------------------------------------+   |
                           |   |  Pod: homeassistant (Deployment)         |   |
                           |   |  映像: home-assistant/home-assistant     |   |
                           |   |  埠號: 8123                              |   |
                           |   |  磁碟區: /config (5Gi)                   |   |
                           |   |                                          |   |
                           |   |  Init Container: wait-for-postgres       |   |
                           |   +-------------------+----------------------+   |
                           |                       |                          |
                           |              叢集內部 DNS                        |
                           |     postgresql://postgres:5432/homeassistant     |
                           |                       |                          |
                           |                       v                          |
                           |   +------------------------------------------+   |
                           |   |  Pod: postgres (StatefulSet)             |   |
                           |   |  映像: postgres:16-alpine                |   |
                           |   |  埠號: 5432                              |   |
                           |   |  磁碟區: /var/lib/postgresql/data (10Gi) |   |
                           |   +------------------------------------------+   |
                           |                                                  |
                           |   Service: postgres (ClusterIP :5432)            |
                           +--------------------------------------------------+
```

### 功能特色

- 超過 2000 種 IoT 裝置整合
- 視覺化自動化編輯器與腳本引擎
- 能源監控與統計儀表板
- 行動應用程式（iOS/Android）支援推播通知
- 專用 PostgreSQL 16 記錄器用於長期歷史儲存
- Init Container 確保資料庫就緒後才啟動

### 快速開始

```bash
# 1. 部署前先更新密鑰
nano k8s-manifests/homeassistant/secret.yaml

# 2. 部署所有 Home Assistant 元件
kubectl apply -k k8s-manifests/homeassistant/

# 3. 確認 Pod 運作中
kubectl -n homeassistant get pods

# 4. 查看 Home Assistant 啟動日誌
kubectl -n homeassistant logs deploy/homeassistant -f
```

### 設定

#### 環境變數

| 變數 | 說明 | 預設值 | 必填 |
|------|------|--------|------|
| `TZ` | 部署時區 | `Asia/Taipei` | 是 |

#### Secrets（密鑰）

部署前請編輯 `secret.yaml`，需設定以下密鑰：

| Secret Key | 說明 | 預設值（請變更！） |
|------------|------|-------------------|
| `POSTGRES_USER` | PostgreSQL 使用者名稱 | `homeassistant` |
| `POSTGRES_PASSWORD` | PostgreSQL 密碼 | `changeme` |
| `POSTGRES_DB` | PostgreSQL 資料庫名稱 | `homeassistant` |

```bash
# 編輯密鑰檔案
nano k8s-manifests/homeassistant/secret.yaml
```

#### PostgreSQL 記錄器設定

首次啟動後，在 Home Assistant Pod 內的 `/config/configuration.yaml` 中加入記錄器設定：

```yaml
recorder:
  db_url: postgresql://homeassistant:<password>@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8
  purge_keep_days: 30
  commit_interval: 1
```

```bash
# 編輯設定檔
kubectl -n homeassistant exec -it deploy/homeassistant -- vi /config/configuration.yaml
```

### 存取服務

| 端點 | URL | 協定 |
|------|-----|------|
| Home Assistant Web UI | `http://<node-ip>:18124` | HTTP (NodePort) |
| 叢集內部 | `http://homeassistant.homeassistant.svc.cluster.local:8123` | HTTP |

首次存取時，系統會引導您完成 Home Assistant 初始設定精靈，建立管理員帳號並設定您的家庭。

### 資料持久化

| PVC 名稱 | 掛載路徑 | 大小 | 用途 |
|----------|----------|------|------|
| `ha-config` | `/config` | 5Gi | Home Assistant 設定、自動化、腳本、藍圖 |
| `postgres-data` | `/var/lib/postgresql/data` | 10Gi | PostgreSQL 記錄器資料庫 |

所有 PVC 使用 `local-path` 儲存類別（k3s 預設）。

### 備份與還原

#### 備份

```bash
# 1. 備份 Home Assistant 設定
kubectl -n homeassistant exec deploy/homeassistant -- tar czf /tmp/ha-config-backup.tar.gz /config
kubectl -n homeassistant cp homeassistant/<ha-pod>:/tmp/ha-config-backup.tar.gz ./ha-config-backup.tar.gz

# 2. 備份 PostgreSQL 資料庫
kubectl -n homeassistant exec sts/postgres -- pg_dump -U homeassistant homeassistant > ha-db-backup.sql
```

#### 還原

```bash
# 1. 還原 Home Assistant 設定
kubectl -n homeassistant cp ./ha-config-backup.tar.gz homeassistant/<ha-pod>:/tmp/ha-config-backup.tar.gz
kubectl -n homeassistant exec deploy/homeassistant -- tar xzf /tmp/ha-config-backup.tar.gz -C /

# 2. 還原 PostgreSQL 資料庫
kubectl -n homeassistant exec -i sts/postgres -- psql -U homeassistant homeassistant < ha-db-backup.sql

# 3. 重啟 Home Assistant 以載入還原的設定
kubectl -n homeassistant rollout restart deploy/homeassistant
```

### 實用指令

```bash
# 查看 Pod 狀態
kubectl -n homeassistant get pods

# 查看 Home Assistant 日誌
kubectl -n homeassistant logs deploy/homeassistant -f

# 查看 PostgreSQL 日誌
kubectl -n homeassistant logs sts/postgres -f

# 重啟 Home Assistant
kubectl -n homeassistant rollout restart deploy/homeassistant

# 檢查設定有效性
kubectl -n homeassistant exec deploy/homeassistant -- python3 -m homeassistant --script check_config -c /config

# 從 HA Pod 測試資料庫連線
kubectl -n homeassistant exec deploy/homeassistant -- \
  python3 -c "import psycopg2; psycopg2.connect('postgresql://homeassistant:changeme@postgres:5432/homeassistant')"
```

### 疑難排解

#### Home Assistant Pod 停在 Init（等待 PostgreSQL）

Home Assistant Pod 有 Init Container 等待 PostgreSQL 就緒。請檢查 PostgreSQL 狀態：

```bash
kubectl -n homeassistant get pods -l component=postgres
kubectl -n homeassistant logs sts/postgres
```

#### 無法探索區域網路裝置

部署預設為 `hostNetwork: false`。若需要裝置探索（mDNS、SSDP、UPnP），請編輯 `homeassistant-deployment.yaml` 設定：

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

然後重新套用：

```bash
kubectl apply -k k8s-manifests/homeassistant/
```

#### Home Assistant 日誌中出現資料庫連線錯誤

確認記錄器 DB URL 與 `secret.yaml` 中的帳號密碼一致：

```bash
# 從 HA Pod 內部測試資料庫連線
kubectl -n homeassistant exec deploy/homeassistant -- \
  python3 -c "import psycopg2; psycopg2.connect('postgresql://homeassistant:changeme@postgres:5432/homeassistant')"
```

#### 設定檢查

```bash
kubectl -n homeassistant exec deploy/homeassistant -- python3 -m homeassistant --script check_config -c /config
```

#### 不中斷 Pod 重啟 Home Assistant

```bash
kubectl -n homeassistant rollout restart deploy/homeassistant
```

### 檔案結構

```
homeassistant/
├── configmap.yaml                  # 環境變數（時區）
├── homeassistant-deployment.yaml   # Home Assistant Pod 的 Deployment（含 Init Container）
├── homeassistant-service.yaml      # NodePort 服務 (18124 -> 8123)
├── kustomization.yaml              # Kustomize 資源列表
├── namespace.yaml                  # 命名空間: homeassistant
├── postgres-service.yaml           # PostgreSQL 的 ClusterIP 服務 (5432)
├── postgres-statefulset.yaml       # PostgreSQL 16 的 StatefulSet
├── pvc.yaml                        # 持久卷宣告（設定與資料庫）
├── README.md                       # 本文件
└── secret.yaml                     # PostgreSQL 帳號密碼（部署前請變更！）
```
