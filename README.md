# Microservices Testing Stack

## k3s Cluster on Vagrant + VirtualBox

Lab cluster 3 เครื่อง (1 server + 2 agent) สำหรับทดสอบ microservices โดยแยกหน้าที่ชัดเจน:

- **Vagrant** — สร้าง VM, ตั้งค่า private network, hostname และ `/etc/hosts`
- **Ansible** — ติดตั้งและตั้งค่า k3s รวมถึง config อื่นๆ ทั้งหมด

📖 ขั้นตอนติดตั้ง k3s ด้วย Ansible แบบละเอียด: [K3S_SETUP.md](K3S_SETUP.md)

## Nodes

| Hostname      | Role   | IP              | CPU | RAM  |
| ------------- | ------ | --------------- | --- | ---- |
| `k3s-server`  | server | `192.168.56.10` | 2   | 4 GB |
| `k3s-agent-1` | agent  | `192.168.56.11` | 2   | 2 GB |
| `k3s-agent-2` | agent  | `192.168.56.12` | 2   | 2 GB |

- Base box: `bento/ubuntu-24.04`
- รวมใช้ RAM บน host ประมาณ 8 GB (ถ้าไม่พอ ลด RAM ของ server เหลือ 2–3 GB ได้)
- เปิด `linked_clone` เพื่อ clone จาก base disk เดียว ประหยัดพื้นที่และเวลา
- ปิด synced folder (`/vagrant`) เพราะ Ansible เป็นผู้จัดการ config ทั้งหมด

## Prerequisites

- [VirtualBox](https://www.virtualbox.org/) (6.1.28 ขึ้นไป หรือ 7.x)
- [Vagrant](https://developer.hashicorp.com/vagrant)
- [Ansible](https://docs.ansible.com/) (รันจาก host)

## Quick Start

```bash
# สร้าง VM ทั้งหมด
vagrant up

# เก็บ snapshot สถานะเริ่มต้นไว้ rollback
vagrant snapshot save clean

# ติดตั้ง k3s ด้วย Ansible
ansible-playbook -i inventory.ini site.yml
```

## Private Network

VirtualBox ตั้งแต่ 6.1.28 จำกัด host-only network ไว้ที่ช่วง `192.168.56.0/21` โดย default
cluster นี้จึงใช้ `192.168.56.10–12` ซึ่งใช้ได้ทันทีโดยไม่ต้องตั้งค่าเพิ่ม

หากต้องการใช้ช่วง IP อื่น (เช่น `10.0.0.0/24`) ต้องเพิ่มช่วงนั้นใน `/etc/vbox/networks.conf` บน host ก่อน (Linux/macOS):

```text
* 10.0.0.0/24 192.168.56.0/21
```

## ⚠️ Network Interface สำหรับ k3s

ทุก VM มี 2 interface:

| Interface | ประเภท          | IP                                    |
| --------- | --------------- | ------------------------------------- |
| `eth0`    | NAT             | `10.0.2.15` (**เหมือนกันทุกเครื่อง**) |
| `eth1`    | Private network | `192.168.56.x`                        |

ถ้าไม่ระบุ k3s จะเลือก `eth0` ทำให้ node สื่อสารกันไม่ได้ จึงต้องส่ง flag เหล่านี้ทั้งฝั่ง server และ agent เสมอ:

```bash
--node-ip=<private ip ของเครื่องนั้น>
--flannel-iface=eth1
```

> ตรวจชื่อ interface จริงด้วย `ip a` ก่อน เพราะบาง box ใช้ชื่อแบบ `enp0s8`

## Ansible Inventory

Vagrant สร้าง SSH key แยกต่อเครื่องไว้ที่ `.vagrant/machines/<name>/virtualbox/private_key`

```ini
[server]
k3s-server ansible_host=192.168.56.10 ansible_ssh_private_key_file=.vagrant/machines/k3s-server/virtualbox/private_key

[agents]
k3s-agent-1 ansible_host=192.168.56.11 ansible_ssh_private_key_file=.vagrant/machines/k3s-agent-1/virtualbox/private_key
k3s-agent-2 ansible_host=192.168.56.12 ansible_ssh_private_key_file=.vagrant/machines/k3s-agent-2/virtualbox/private_key

[all:vars]
ansible_user=vagrant
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

รัน Ansible แยกจาก host แทนการใช้ Ansible provisioner ใน Vagrantfile เพื่อให้ re-run playbook ได้เร็วโดยไม่ผูกกับ VM lifecycle

## Common Commands

| คำสั่ง                           | ความหมาย                                       |
| -------------------------------- | ---------------------------------------------- |
| `vagrant up`                     | สร้าง/เปิด VM ทั้งหมด                          |
| `vagrant up k3s-server`          | สร้าง/เปิดเฉพาะเครื่องเดียว                    |
| `vagrant ssh k3s-server`         | SSH เข้าเครื่อง                                |
| `vagrant status`                 | ดูสถานะ VM                                     |
| `vagrant ssh-config`             | ดู SSH config (host, port, key path)           |
| `vagrant snapshot save clean`    | บันทึก snapshot                                |
| `vagrant snapshot restore clean` | rollback กลับ snapshot เพื่อทดสอบ Ansible ใหม่ |
| `vagrant halt`                   | ปิด VM                                         |
| `vagrant destroy -f`             | ลบ VM ทั้งหมด                                  |

## Troubleshooting

- **`vagrant up` error เรื่อง IP range** → IP อยู่นอกช่วง `192.168.56.0/21` ให้แก้ `/etc/vbox/networks.conf`
- **Node ไม่ join / pod ข้ามเครื่องคุยกันไม่ได้** → ตรวจว่าใส่ `--node-ip` และ `--flannel-iface` ถูก interface แล้ว
- **Ansible SSH ไม่ได้** → ตรวจ key path ด้วย `vagrant ssh-config`

## Local Database & Migrations

Postgres สำหรับพัฒนาบนเครื่อง รันด้วย docker compose และจัดการ migration ด้วย [goose](https://github.com/pressly/goose) ผ่าน mise task

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [mise](https://mise.jdx.dev/) แล้วรัน `mise install` เพื่อติดตั้ง goose และ toolchain อื่นตาม `mise.toml`

### Database ต่อ service

ทุก service มี database และ app user ของตัวเอง ส่วน `migrator` ใช้ร่วมกันทุก service

| Database       | App user (DML เท่านั้น) | ใช้โดย       |
| -------------- | ----------------------- | ------------ |
| `catalog`      | `catalog_service`       | catalog      |
| `booking`      | `booking_service`       | booking      |
| `payment`      | `payment_service`       | payment      |
| `partner`      | `partner_service`       | partner-api  |
| `notification` | `notification_service`  | notification |

- `migrator` เป็นเจ้าของทุก database ใช้รัน migration (DDL) เท่านั้น
- app user อ่านเขียนข้อมูลได้ แต่สร้าง แก้ หรือลบตารางไม่ได้ และเข้า database ของ service อื่นไม่ได้
- แต่ละ database ไม่มี schema `public` ใช้ schema ชื่อเดียวกับ database แทน (เช่น `catalog.venues`) และตั้ง `search_path` ให้ทั้ง `migrator` และ app user แล้ว จึงเขียน SQL โดยไม่ต้องใส่ชื่อ schema
- role, database และ schema สร้างโดย script ใน [scripts/postgres/init/](scripts/postgres/init/)

### Setup ครั้งแรก

สร้างไฟล์ 2 ไฟล์ที่ root (ทั้งคู่อยู่ใน `.gitignore` ห้าม commit) สุ่มรหัสผ่านด้วย `openssl rand -hex 16`

`.env` ให้ docker compose ใช้สร้าง role:

```dotenv
POSTGRES_PASSWORD=
MIGRATOR_PASSWORD=
CATALOG_SERVICE_PASSWORD=
BOOKING_SERVICE_PASSWORD=
PAYMENT_SERVICE_PASSWORD=
PARTNER_SERVICE_PASSWORD=
NOTIFICATION_SERVICE_PASSWORD=
```

`mise.local.toml` ให้ goose และ service ใช้เชื่อมต่อ (รหัสผ่านต้องตรงกับ `.env`):

```toml
[env]
MIGRATOR_DATABASE_URL_BASE = "postgres://migrator:<pw>@localhost:5432"
CATALOG_DATABASE_URL = "postgres://catalog_service:<pw>@localhost:5432/catalog?sslmode=disable"
# BOOKING_DATABASE_URL, PAYMENT_DATABASE_URL, ... รูปแบบเดียวกัน
```

จากนั้นเปิด database:

```bash
mise trust
make db-up
```

> init script รันเฉพาะตอนที่ volume ยังว่าง ถ้าเปลี่ยน script หรือรหัสผ่านใน `.env` ต้องรัน `make db-reset` (ข้อมูลเดิมหายทั้งหมด)

### Make Commands

รัน `make` เพื่อดูรายการคำสั่งทั้งหมด คำสั่งที่ทำงานกับ service ใด service หนึ่งต้องระบุ `SVC` เสมอ

| คำสั่ง                                               | ความหมาย                                                   |
| ---------------------------------------------------- | ---------------------------------------------------------- |
| `make db-up`                                         | เปิด Postgres                                              |
| `make db-down`                                       | ปิด Postgres (ข้อมูลยังอยู่)                               |
| `make db-reset`                                      | ⚠️ ลบข้อมูลทั้งหมด แล้วรัน init script ใหม่                |
| `make db-psql SVC=catalog`                           | เปิด psql ที่ database ของ service                         |
| `make migrate-create SVC=catalog NAME=create_venues` | สร้างไฟล์ migration ใหม่ใน `services/<svc>/db/migrations/` |
| `make migrate-up SVC=catalog`                        | รัน migration ที่ยังไม่ได้รันทั้งหมด                       |
| `make migrate-down SVC=catalog`                      | ย้อน migration ล่าสุด 1 ไฟล์                               |
| `make migrate-status SVC=catalog`                    | ดูว่า migration ไหนรันแล้ว ไหนยัง                          |
| `make migrate-redo SVC=catalog`                      | down แล้ว up migration ล่าสุด                              |
| `make migrate-validate SVC=catalog`                  | ตรวจไฟล์ migration โดยไม่ต้องต่อ database                  |

### กติกา migration

- migration ที่ merge แล้ว **ห้ามแก้** ถ้าต้องเปลี่ยนให้สร้างไฟล์ใหม่ (`migrate-redo` ใช้ได้เฉพาะไฟล์ที่ยังไม่ merge)
- production เดินหน้าอย่างเดียว ส่วน `-- +goose Down` มีไว้ใช้ตอน dev
- `CREATE INDEX CONCURRENTLY` ต้องอยู่ในไฟล์แยกที่มี `-- +goose NO TRANSACTION`

### เพิ่ม migration ให้ service อื่น

ตอนนี้มี mise task `catalog:migrate` ตัวเดียว ถ้าจะเริ่มทำ migration ของ service อื่น ให้เพิ่ม task ใน `mise.toml` โดยคัดลอกจาก `catalog:migrate` แล้วเปลี่ยน `dir` และชื่อ database ท้าย `GOOSE_DBSTRING` เช่น

```toml
[tasks."booking:migrate"]
dir = "services/booking"
env = { GOOSE_DRIVER = "postgres", GOOSE_DBSTRING = "{{env.MIGRATOR_DATABASE_URL_BASE}}/booking?sslmode=disable", GOOSE_MIGRATION_DIR = "db/migrations" }
run = "goose"
```

## Queries (sqlc)

query ของแต่ละ service เขียนเป็น SQL ใน `services/<svc>/db/queries/` แล้วใช้ [sqlc](https://docs.sqlc.dev) สร้างโค้ด Go ไว้ใน `services/<svc>/internal/store/` (ห้ามแก้ไฟล์ในนั้นด้วยมือ)

```bash
cd services/catalog
sqlc generate   # สร้างโค้ดใหม่หลังแก้ query หรือ migration
sqlc diff       # ตรวจว่าโค้ดที่ commit ตรงกับ SQL
```

📖 กฎ สูตร และ checklist การเขียน query: [SQLC_INSTRUCTIONS.md](/SQLC_INSTRUCTIONS.md)
