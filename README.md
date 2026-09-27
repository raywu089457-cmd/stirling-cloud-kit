# stirling-cloud-kit

把 [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF) 架到雲端 VM，**永遠開著，不用開自己的電腦**，而且**只有自己的裝置連得到**。

```
你的手機 / 筆電 ──Tailscale 加密網路──> 雲端 VM ──> Stirling PDF
                                          （只綁 127.0.0.1，網際網路掃不到）
```

## 為什麼這樣設計

| 決定 | 原因 |
|---|---|
| 容器只綁 `127.0.0.1:8080` | 對外完全不開 port。網路上掃不到，也不會有 iptables/ufw 跟 Docker 打架的問題 |
| 走 Tailscale 而不是公開網址 | 不用設帳密、不用買網域、不用憑證，而且只有你自己的裝置進得來 |
| 資料掛在 `./data` | 容器砍掉重建，設定跟資料都還在 |

## 需要什麼

一台**永遠免費**的 Ubuntu VM。唯一符合「真的免費 + 規格夠」的選擇是 **Oracle Cloud Always Free**：

- ARM Ampere A1：**2 核 / 12 GB RAM**（2026/6/15 被砍半，原本 4核/24GB）
- 200 GB 磁碟、10 TB 流量
- Stirling PDF 只要 2 GB 就能跑，建議 4 GB —— 12 GB 非常夠

> ⚠️ Oracle 註冊常卡在信用卡驗證。見下方「註冊過關技巧」。

## 安裝

### 方法 A：全自動（推薦）

1. 建 VM 時，選 **Ubuntu 22.04 或 24.04**、shape 選 `VM.Standard.A1.Flex`（2 OCPU / 12 GB）
2. 在 **Show advanced options → Initialization script (Cloud-init)** 貼上 `cloud-init.yaml` 的內容
3. **先把裡面那行 `tskey-auth-REPLACE_ME` 換成你自己的 Tailscale auth key**
   - 到 https://login.tailscale.com/admin/settings/keys 產生
   - 勾 **Reusable** 和 **Ephemeral**，期限 90 天
4. 建好後等 5～10 分鐘（第一次要拉 image）
5. 打開 `http://<VM名稱>.<你的tailnet>.ts.net:8080`

### 方法 B：手動（已有一台 VM）

```bash
curl -fsSL https://raw.githubusercontent.com/<你的帳號>/stirling-cloud-kit/main/setup.sh -o setup.sh
TS_AUTHKEY="tskey-auth-xxxxx" bash setup.sh
```

沒有 auth key 也可以，腳本會印一個網址讓你點進去登入。

### 方法 C：在你自己電腦上先試

```bash
git clone https://github.com/<你的帳號>/stirling-cloud-kit.git
cd stirling-cloud-kit
docker compose up -d
# 打開 http://localhost:8080
```

## Oracle 註冊過關技巧

社群回報失敗率很高，這些是實際有用的：

- 用**真實的信用卡或簽帳卡**（不要用虛擬卡、預付卡）
- 帳單地址跟卡片登記的**完全一致**（連標點都一樣）
- 用 Chrome，**關掉**擋追蹤 / 廣告阻擋擴充功能、**不要開 VPN**
- 用無痕模式重試
- 一次只註冊一個帳號

如果真的過不了，替代方案（都要錢，但很便宜）：
[Hetzner](https://www.hetzner.com/cloud) CAX11（2核/4GB）約 €4/月、[Vultr](https://www.vultr.com/) / [DigitalOcean](https://www.digitalocean.com/) 約 $5/月。這兩個的腳本一樣能用。

## 常用指令

```bash
cd /opt/stirling

sudo docker compose ps              # 看狀態
sudo docker compose logs -f         # 看 log
sudo docker compose restart         # 重啟
sudo docker compose pull && sudo docker compose up -d   # 更新到最新版
sudo docker compose down            # 關掉

sudo tailscale serve status         # 看代理設定
sudo tailscale status               # 看 tailnet 成員
```

## 更新 Stirling

```bash
cd /opt/stirling
sudo docker compose pull
sudo docker compose up -d
```

`data/configs` 不會被動到，設定和資料庫都保留。

## 常見問題

**打開網址連不上？**
1. 你的裝置有連上 Tailscale 嗎（手機要看 App 有沒有開）
2. VM 上的服務起來了嗎：`sudo docker compose ps` 要看到 `healthy`
3. 代理設好了嗎：`sudo tailscale serve status`

**`tailscale serve` 失敗？**
通常是 tailnet 沒開 HTTPS/MagicDNS。到 https://login.tailscale.com/admin/dns 開啟 MagicDNS。
真的不行就用 VM 的 Tailscale IP 直接連：`http://100.x.x.x:8080`
（這種情況要把 compose 裡的 `127.0.0.1:8080:8080` 改成 `8080:8080`，並且在雲端防火牆**確保 8080 不對外開放**。）

**記憶體不夠 / 容器一直重啟？**
Stirling 是 Java，吃記憶體。VM 給 4 GB 以上比較保險。
真的只有 2 GB，把 image 換成輕量版 `stirling-pdf:latest-ultra-lite`（只有基本功能）。

**想讓別人也能用？**
那就不該走 Tailscale 了。改成公開網址 + 打開登入驗證：
```yaml
ports:
  - "8080:8080"
environment:
  SECURITY_ENABLELOGIN: "true"
```
然後在雲端防火牆開放 8080，並在 UI 裡設一組強密碼。

## 安全性

- 服務本身在 `127.0.0.1`，只有 VM 自己碰得到
- 對外連線是 Tailscale 的 WireGuard 加密通道
- 雲端防火牆只需要開 **22 (SSH)**
- 沒有設登入驗證是**刻意的** —— 因為只有你的 tailnet 進得來
- 你上傳的 PDF 全程留在这台 VM 上，不會經過任何第三方服務

## 授權

本部署包是設定檔，隨便用。Stirling PDF 本身是 MIT（部分目錄另有授權），版權屬於 Stirling PDF Inc.。
