# Setup k3s Cluster ด้วย Ansible (บน Vagrant + VirtualBox)

คู่มือนี้ใช้ติดตั้ง k3s cluster 3 node (1 server + 2 agents) บน VM ที่ provision ด้วย Vagrant แล้ว โดยใช้ Ansible playbook ที่เขียนเอง

## Environment

| Host       | Role   | IP            |
| ---------- | ------ | ------------- |
| k3s-server | server | 192.168.56.10 |
| k3s-agent1 | agent  | 192.168.56.11 |
| k3s-agent2 | agent  | 192.168.56.12 |

- OS: Ubuntu (Vagrant box)
- Hypervisor: VirtualBox, private network `192.168.56.0/24`
- ชื่อ host ใน inventory **ต้องตรงกับชื่อ machine ใน Vagrantfile** (ใช้หา SSH key ใน `.vagrant/`)

## ⚠️ ข้อควรรู้: NAT interface ของ VirtualBox

ทุก VM ของ Vagrant มี interface แรกเป็น NAT ที่ได้ IP `10.0.2.15` **เหมือนกันทุกเครื่อง** ถ้าไม่กำหนดอะไร k3s จะเลือก IP นี้ ทำให้ node join ได้แต่ pod ข้ามเครื่องคุยกันไม่ได้

ต้องกำหนด `--node-ip` และ `--flannel-iface` ให้ชี้ไปที่ private network เสมอ เช็กชื่อ interface ด้วย:

```bash
vagrant ssh k3s-server -c "ip -br a"
```

ดูว่า IP `192.168.56.x` อยู่บน interface ไหน (มักเป็น `eth1` หรือ `enp0s8`) แล้วใส่ค่าใน `flannel_iface`

## โครงสร้างไฟล์

วางไฟล์ทั้งหมดในโฟลเดอร์เดียวกับ Vagrantfile

```text
.
├── Vagrantfile
├── ansible.cfg
├── inventory.yml
└── site.yml
```

### ansible.cfg

```ini
[defaults]
inventory = inventory.yml
host_key_checking = False
```

### inventory.yml

```yaml
all:
  vars:
    ansible_user: vagrant
    ansible_ssh_private_key_file: .vagrant/machines/{{ inventory_hostname }}/virtualbox/private_key
    flannel_iface: eth1 # เปลี่ยนตามผล ip -br a
  children:
    server:
      hosts:
        k3s-server: { ansible_host: 192.168.56.10, node_ip: 192.168.56.10 }
    agents:
      hosts:
        k3s-agent1: { ansible_host: 192.168.56.11, node_ip: 192.168.56.11 }
        k3s-agent2: { ansible_host: 192.168.56.12, node_ip: 192.168.56.12 }
    k3s_cluster:
      children:
        server:
        agents:
```

### site.yml

```yaml
- name: Prepare all nodes
  hosts: k3s_cluster
  become: true
  tasks:
    - name: Install curl
      ansible.builtin.apt:
        name: curl
        state: present
        update_cache: true

- name: Install k3s server
  hosts: server
  become: true
  tasks:
    - name: Download k3s install script
      ansible.builtin.get_url:
        url: https://get.k3s.io
        dest: /tmp/k3s-install.sh
        mode: "0755"

    - name: Install k3s (server)
      ansible.builtin.command:
        cmd: >
          /tmp/k3s-install.sh server
          --node-ip {{ node_ip }}
          --advertise-address {{ node_ip }}
          --flannel-iface {{ flannel_iface }}
          --write-kubeconfig-mode 644
        creates: /usr/local/bin/k3s
      environment:
        INSTALL_K3S_CHANNEL: stable

    - name: Read join token
      ansible.builtin.slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: node_token
      no_log: true

    - name: Fetch kubeconfig to host
      ansible.builtin.fetch:
        src: /etc/rancher/k3s/k3s.yaml
        dest: ./kubeconfig
        flat: true

- name: Join agents
  hosts: agents
  become: true
  vars:
    server_ip: "{{ hostvars[groups['server'][0]].node_ip }}"
    k3s_token: "{{ hostvars[groups['server'][0]].node_token.content | b64decode | trim }}"
  tasks:
    - name: Download k3s install script
      ansible.builtin.get_url:
        url: https://get.k3s.io
        dest: /tmp/k3s-install.sh
        mode: "0755"

    - name: Install k3s (agent)
      ansible.builtin.command:
        cmd: >
          /tmp/k3s-install.sh agent
          --node-ip {{ node_ip }}
          --flannel-iface {{ flannel_iface }}
        creates: /usr/local/bin/k3s
      environment:
        INSTALL_K3S_CHANNEL: stable
        K3S_URL: "https://{{ server_ip }}:6443"
        K3S_TOKEN: "{{ k3s_token }}"
      no_log: true
```

#### Playbook ทำงานอย่างไร

1. ติดตั้ง `curl` ทุก node
2. ติดตั้ง k3s server แล้วอ่าน join token ด้วย `slurp` (ได้ค่าเป็น base64 จึงต้อง `b64decode`)
3. ดึง kubeconfig กลับมาที่เครื่อง host
4. Agent ดึง IP และ token ของ server ผ่าน `hostvars` แล้ว join เข้า cluster
5. `creates:` ทำให้รัน playbook ซ้ำได้โดยไม่ติดตั้งทับ (idempotent)

## ขั้นตอนการใช้งาน

### 1. ทดสอบการเชื่อมต่อ

```bash
ansible all -m ping
```

ต้องได้ `pong` ครบทุก host

### 2. Lint และรัน playbook

```bash
ansible-lint site.yml
ansible-playbook site.yml
```

### 3. Merge kubeconfig เข้า ~/.kube/config

kubeconfig ของ k3s ชี้ไปที่ `127.0.0.1` และตั้งชื่อ cluster/user/context ว่า `default` ทั้งหมด ต้องแก้ทั้งสองอย่างก่อน merge เพื่อไม่ให้ชนกับ context เดิม

```bash
# ชี้ server ไปที่ IP ของ VM
sed -i 's/127.0.0.1/192.168.56.10/' kubeconfig

# เปลี่ยนชื่อ default -> k3s-vagrant
sed -i 's/: default$/: k3s-vagrant/' kubeconfig

# ตรวจสอบ (ทุกบรรทัดควรเป็น k3s-vagrant)
grep -E 'name:|cluster:|user:|current-context:' kubeconfig
```

> macOS ใช้ `sed -i ''` แทน `sed -i`

```bash
# backup ไฟล์เดิม
cp ~/.kube/config ~/.kube/config.bak

# merge แล้ว flatten เป็นไฟล์เดียว (เขียนลงไฟล์ชั่วคราวก่อนเสมอ)
KUBECONFIG=~/.kube/config:$PWD/kubeconfig kubectl config view --flatten > /tmp/kubeconfig-merged
mv /tmp/kubeconfig-merged ~/.kube/config
chmod 600 ~/.kube/config
```

> ห้าม redirect `>` ลง `~/.kube/config` ตรงๆ เพราะ shell จะล้างไฟล์ก่อนที่ kubectl จะอ่าน
> ถ้ายังไม่มี `~/.kube/config` ใช้ `mkdir -p ~/.kube && cp kubeconfig ~/.kube/config` แทน

### 4. ตรวจสอบ cluster

```bash
unset KUBECONFIG   # ถ้าเคย export ไว้
kubectl config use-context k3s-vagrant
kubectl get nodes -o wide
```

ผ่านเมื่อ:

- ทุก node อยู่ในสถานะ `Ready`
- `INTERNAL-IP` เป็น `192.168.56.x` **ไม่ใช่** `10.0.2.15`

## Troubleshooting

### `Cannot utilize private_key with SSH_AGENT disabled`

ใน ansible-core 2.19+ ตัวแปร `ansible_ssh_private_key` (ไม่มี `_file`) หมายถึง **เนื้อหา** ของ key ซึ่งต้องเปิด SSH agent ก่อน ต้องใช้ `ansible_ssh_private_key_file` สำหรับ path ของไฟล์

ถ้าสะกดถูกแล้วยังเจอ ให้หาว่ามีการตั้งค่าซ้อนอยู่ที่ไหน:

```bash
ansible-inventory --host k3s-server
ansible-config dump --only-changed
env | grep -i ANSIBLE
```

### Agent join ไม่สำเร็จ

`no_log: true` ซ่อน error message ไปด้วย ให้ปิดชั่วคราว (`no_log: false`) หรือดู log บน agent:

```bash
vagrant ssh k3s-agent1 -c "sudo journalctl -u k3s-agent -n 50"
```

### Fetch kubeconfig ไม่เจอไฟล์

path ที่ถูกคือ `/etc/rancher/k3s/k3s.yaml` (`.yaml` ไม่ใช่ `.yml`)

### Env var ไม่มีผล

ชื่อ env var แยกตัวพิมพ์เล็ก-ใหญ่ ต้องเป็น `INSTALL_K3S_CHANNEL` (ไม่ใช่ `INSTALL_K3s_CHANNEL`)

## Rollback / ถอนการติดตั้ง

k3s ติดตั้ง uninstall script ไว้ให้บนแต่ละ node

```bash
# agent
ansible agents -b -m ansible.builtin.command -a /usr/local/bin/k3s-agent-uninstall.sh

# server
ansible server -b -m ansible.builtin.command -a /usr/local/bin/k3s-uninstall.sh

# ลบ context ออกจาก kubeconfig ของเครื่อง host
kubectl config delete-context k3s-vagrant
kubectl config delete-cluster k3s-vagrant
kubectl config delete-user k3s-vagrant
```

หรือเริ่มใหม่ทั้งหมดด้วย `vagrant destroy -f && vagrant up`
