# Microservices Testing Stack

## k3s Cluster on Vagrant + VirtualBox

Lab cluster 3 เครื่อง (1 server + 2 agent) สำหรับทดสอบ microservices โดยแยกหน้าที่ชัดเจน:

- **Vagrant** — สร้าง VM, ตั้งค่า private network, hostname และ `/etc/hosts`
- **Ansible** — ติดตั้งและตั้งค่า k3s รวมถึง config อื่นๆ ทั้งหมด

## Nodes

| Hostname      | Role        | IP              | CPU | RAM  |
|---------------|-------------|-----------------|-----|------|
| `k3s-server`  | server      | `192.168.56.10` | 2   | 4 GB |
| `k3s-agent-1` | agent       | `192.168.56.11` | 2   | 2 GB |
| `k3s-agent-2` | agent       | `192.168.56.12` | 2   | 2 GB |

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

```
* 10.0.0.0/24 192.168.56.0/21
```

## ⚠️ Network Interface สำหรับ k3s

ทุก VM มี 2 interface:

| Interface | ประเภท          | IP                                   |
|-----------|-----------------|--------------------------------------|
| `eth0`    | NAT             | `10.0.2.15` (**เหมือนกันทุกเครื่อง**) |
| `eth1`    | Private network | `192.168.56.x`                       |

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

| คำสั่ง                                 | ความหมาย                                  |
|----------------------------------------|-------------------------------------------|
| `vagrant up`                           | สร้าง/เปิด VM ทั้งหมด                      |
| `vagrant up k3s-server`                | สร้าง/เปิดเฉพาะเครื่องเดียว                 |
| `vagrant ssh k3s-server`               | SSH เข้าเครื่อง                             |
| `vagrant status`                       | ดูสถานะ VM                                 |
| `vagrant ssh-config`                   | ดู SSH config (host, port, key path)        |
| `vagrant snapshot save clean`          | บันทึก snapshot                            |
| `vagrant snapshot restore clean`       | rollback กลับ snapshot เพื่อทดสอบ Ansible ใหม่ |
| `vagrant halt`                         | ปิด VM                                     |
| `vagrant destroy -f`                   | ลบ VM ทั้งหมด                              |

## Troubleshooting

- **`vagrant up` error เรื่อง IP range** → IP อยู่นอกช่วง `192.168.56.0/21` ให้แก้ `/etc/vbox/networks.conf`
- **Node ไม่ join / pod ข้ามเครื่องคุยกันไม่ได้** → ตรวจว่าใส่ `--node-ip` และ `--flannel-iface` ถูก interface แล้ว
- **Ansible SSH ไม่ได้** → ตรวจ key path ด้วย `vagrant ssh-config`
