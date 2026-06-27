## 概要

**【ネットワーク図】**<br>
<img src="diagrams/Gamer-Iris_home_infra.drawio.svg" width="800">

Ansible で全ノードのミドルウェアと Kubernetes クラスタを構築し、Argo CD で GitOps 運用する。

Kubernetes 上のアプリケーション:
Minecraft / Navidrome / WordPress / MariaDB + phpMyAdmin /
Grafana + Prometheus + Alertmanager / Cloudflare Tunnel。

この README を利用者向けの正本手順として扱う。<br>
詳細な実装は script / manifest / workflow 側を参照する。

## 重要事項

- 実 secret / token / private key は commit しない。
- `setup.sh all` は初回構築または全体を収束し直す時だけ使う。
- `setup.sh all` は `github.dispatch_build_release=true` の場合だけ Release workflow を起動する。
- Release workflow は `deploy_to_servers=false` で起動する。
  Minecraft への deploy は行わない。
- Release 登録を省略する場合は `--no-publish`、明示的に起動する場合は `--publish`。

## 最短構築フロー

初見の場合は上から順に進める。<br>
構築後の確認は `setup.sh all` 完了後に必要なものだけ実施する。

| フロー | 実行場所 | 内容 |
|---|---|---|
| 事前準備 | 作業PC / 各種 GUI | 外部サービスを準備 |
| インフラ準備 | Proxmox GUI / TrueNAS UI | cluster・CephFS・VM 作成 |
| Git clone | 各対象サーバ | clone・SSH 鍵設定 |
| Secret 作成 | 各対象サーバ | `settings_secret.yml` 作成 |
| GitHub 初期登録 | 作業PC | 空 repository へ通常の git push |
| Deploy Key | setup.sh実行ホスト + GitHub UI | 秘密鍵生成・公開鍵登録 |
| Rook 準備 | Ceph admin host → setup.sh実行ホスト | 外部 cluster import |
| setup 実行 | setup.sh実行ホスト | `setup.sh` で全体構築 |
| 構築後確認 | k8s操作ホスト | kubectl / argocd 確認 |

```bash
# setup.sh実行ホストで実行
cd ~/Linux/platforms/setup
./bootstrap.sh
./setup.sh --precheck
./setup.sh all --dry-run
./setup.sh common
./setup.sh secrets
./setup.sh all
```

- `setup.sh common` が正常終了してから `secrets` へ進む。
- 再起動が必要な場合は `sudo reboot` 後、`./setup.sh common` から再実行する。

空の GitHub repository へ初期登録する場合は、通常の git コマンドで push する。

```bash
git remote add origin git@github.com:Gamer-Iris/Linux.git
git push -u origin main
```

GitHub Actions が初回だけ `BuildFailed` / `startup_failure` になった場合は、空 commit で再実行を確認する。<br>
jobs / check runs が 0 件なら、GitHub 側の run / workflow metadata 異常として扱う。

## 実行場所

| 略称 | 実行場所 |
|---|---|
| 作業PC | ローカル PC・ブラウザ |
| Proxmox GUI | Proxmox Web UI |
| Proxmox node | Proxmox host の SSH シェル |
| Ceph admin host | `sudo ceph` が実行可能な Proxmox host |
| TrueNAS UI | TrueNAS Web UI |
| 各対象サーバ | Proxmox node / k8s VM |
| setup.sh実行ホスト | 通常は1台目の control-plane VM |
| k8s操作ホスト | 通常は setup.sh実行ホストと同一 |
| GitHub UI | GitHub Web UI（Actions / Settings） |

## 詳細の参照先

| 情報 | 参照先 |
|---|---|
| 初回構築・運用手順 | この README |
| 設定項目の詳細 | `settings_secret_template.yml` |
| setup.sh の全オプション | `setup.sh --help` |
| Ansible | `platforms/setup/site.yml`<br>`platforms/setup/roles/` |
| Kubernetes manifest | `platforms/kubernetes/` |
| Argo CD Application | `argo-cd-apps-deployment{1..4}.yml` |
| CI / 運用 workflow | `.github/workflows/` |
| 品質検証 | `platforms/setup/validate/` |
| Minecraft 運用 | `platforms/scripts/minecraft/` |

## 迷った時の入口

迷った場合は、状況に近い行から該当する手順へ進む。

| 状況 | 参照先 |
|---|---|
| 初回構築 | 手順 1〜3 |
| Grafana にログインできない | 手順 5「アプリ初期設定・ログイン」 |
| Minecraft が起動しない | 手順 7「Minecraft / GreetMate 運用」 |
| Pod / node が異常 | 手順 8「障害対応の初動」 |
| Secret が反映されない | 手順 4「構築後確認」 |
| Release / deploy したい | 手順 9「GitHub Actions / Release」 |

## 手順一覧

初回構築は手順 1 から順に進める。<br>
構築後の確認・運用は、必要な手順だけ開く。

<details>
<summary>1. 事前準備</summary>

この章の目的:

- 構築に必要な外部サービスとインフラを準備する。

この章でやること:

- Discord webhook / Cloudflare tunnel token / Tailscale を準備する。
- Proxmox cluster / CephFS（名前は `cephfs`）/ TrueNAS SMB 共有を準備する。
- Ubuntu Server VM（control-plane / worker）を作成する。
- 各対象サーバに前提条件を整える。

完了条件:

- Proxmox cluster・CephFS・VM が作成済み。
- TrueNAS の SMB 共有が作成済み。
- 各対象サーバに sudo ユーザー・ufw 設定が完了。

各対象サーバ（Proxmox node / VM 全台）で以下を実施:

- SSH 可能な sudo ユーザーを用意
- timezone を `Asia/Tokyo`、swap を無効化
- `git` / `ufw` を導入
- 必要 port を ufw で許可
  （22, 179, 2049, 3300, 5473, 6443, 6789, 6800:7300/tcp, 8006, 9100, 10250 等）
</details>

<details>
<summary>2. 初回セットアップ前の配置</summary>

この章の目的:

- setup.sh 実行前に必要なファイルを各サーバに配置する。

この章でやること:

- 各対象サーバへ Git clone し `settings_secret.yml` を作成する。
- Argo CD Deploy Key を作成する。
- Rook external cluster import を準備する。

完了条件:

- 各対象サーバに `~/Linux` と `settings_secret.yml` がある。
- setup.sh実行ホストに `~/.ssh/argo` と `rook-ceph-env.sh` がある。

### Git clone

**実行場所: 各対象サーバ（Proxmox node / VM 全台）**

```bash
git config --global user.name "自分の名前"
git config --global user.email "自分のメールアドレス"
ssh-keygen -t rsa -f ~/.ssh/id_git_rsa
chmod 600 ~/.ssh/id_git_rsa
cat ~/.ssh/id_git_rsa.pub
```

公開鍵を GitHub の SSH keys に登録してから clone する。

```bash
ssh -T git@github.com
cd
git clone git@github.com:Gamer-Iris/Linux.git
cd ~/Linux
git ls-files -z '*.sh' | xargs -0 -r chmod 755
```

### `settings_secret.yml`

**実行場所: 各対象サーバ（全台）**

`settings_secret.yml` が各対象サーバに存在することが `setup.sh` 実行の前提。

```bash
cd ~/Linux/platforms/settings
cp settings_secret_template.yml settings_secret.yml
chmod 600 settings_secret.yml
nano settings_secret.yml
cd ~/Linux/platforms/scripts
./update.sh
```

各項目の詳細は `settings_secret_template.yml` のコメントを正とする。<br>
`settings_secret.yml` は Git に commit しない。

| カテゴリ | 項目例 |
|---|---|
| 共通認証 | `username` / `password` / `key` |
| ノード定義 | `nodes.control_plane[]`<br>`nodes.workers[]`<br>`nodes.proxmox[]` |
| Kubernetes | `kubernetes.pod_network_cidr`<br>`kubernetes.cri_socket` |
| データベース | `databases.*` |
| 通知 | `appnotice.ip` / `discord.url` |
| アプリ Secret | `app_secrets.cloudflare.token`<br>`app_secrets.minecraft.rcon_password_*` |
| SMB | `smb.ip` / `smb.username`<br>`smb.password` |
| GitHub | `github.enabled` / `github.token`<br>`github.ssh_key_path` |
| Argo CD | `argocd.deploy_key_path`<br>`argocd.admin_password` |

### Argo CD Deploy Key

**実行場所: setup.sh実行ホスト** + **GitHub UI**

```bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/argo
chmod 600 ~/.ssh/argo
cat ~/.ssh/argo.pub
```

公開鍵を `Settings` → `Deploy keys` に登録する（write 権限不要）。<br>
`argocd.deploy_key_path` はこの秘密鍵パスに合わせる。

### Rook external cluster import

Ceph admin host と setup.sh実行ホストの 2 か所で操作が必要。

**Ceph admin host** で以下を実行し、出力された `export ...` 行を控える。

```bash
LATEST_VERSION=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
  https://github.com/rook/rook/releases/latest | sed 's#.*/##')
LATEST_VERSION_WITHOUT_V=${LATEST_VERSION#v}
LATEST_RELEASE_BRANCH="release-$(echo "${LATEST_VERSION_WITHOUT_V}" | awk -F. '{print $1"."$2}')"
sudo ceph osd pool ls
sudo ceph fs ls
sudo ceph osd pool ls | grep -qx rbd || sudo ceph osd pool create rbd
sudo ceph osd pool application enable rbd rbd
sudo rbd pool init rbd || true
RBD_POOL_NAME="rbd"
CEPHFS_NAME="cephfs"
(
  ROOK_TMP_DIR=$(mktemp -d)
  trap 'rm -rf "${ROOK_TMP_DIR}"' EXIT
  wget -O "${ROOK_TMP_DIR}/create-external-cluster-resources.py" \
    "https://raw.githubusercontent.com/rook/rook/${LATEST_RELEASE_BRANCH}/deploy/examples/create-external-cluster-resources.py"
  sudo python3 "${ROOK_TMP_DIR}/create-external-cluster-resources.py" \
    --ceph-conf /etc/pve/ceph.conf \
    --keyring /etc/pve/priv/ceph.client.admin.keyring \
    --namespace rook-ceph-external \
    --rbd-data-pool-name "${RBD_POOL_NAME}" \
    --cephfs-filesystem-name "${CEPHFS_NAME}" \
    --format bash \
    --skip-monitoring-endpoint
)
```

**setup.sh実行ホスト** で `export ...` 行を保存する。

```bash
nano ~/Linux/platforms/setup/rook-ceph-env.sh
chmod 600 ~/Linux/platforms/setup/rook-ceph-env.sh
```
</details>

<details>
<summary>3. setup.sh 実行・再実行</summary>

この章の目的:

- Kubernetes クラスタと全アプリを構築する。

この章でやること:

- setup.sh で初回構築する。
- 手動再起動後の再開手順を確認する。
- 更新時の使い分けを確認する。

完了条件:

- `setup.sh all` が正常終了している。
- `argocd app list` で全 app が Synced / Healthy。

**実行場所: setup.sh実行ホスト**

初回は `bootstrap.sh` → `--precheck` → `all --dry-run` → `common` → `secrets` → `all` の順で実行する。<br>
`common` の前に `bootstrap.sh` を実行し、kubeseal / Ansible などの前提 CLI を導入する。

```bash
cd ~/Linux/platforms/setup
./bootstrap.sh
./setup.sh --precheck
./setup.sh all --dry-run
./setup.sh common
./setup.sh secrets
./setup.sh all
```

`all --dry-run` は Ansible check mode であり実インストールは行わない。

`kubeseal` / `ansible` / `ansible-playbook` / `ansible-inventory` が不足している場合は、`./bootstrap.sh` を実行してから再実行する。

`setup.sh common` は `/var/run/reboot-required` がある node だけを再起動する。<br>
setup.sh実行ホスト自身に再起動が必要な場合は案内を出して停止する。

手動再起動後は、前提 CLI 導入済みのため `common` から再開する。

```bash
sudo reboot
# 再接続後
cd ~/Linux/platforms/setup
./setup.sh common
./setup.sh secrets
./setup.sh all
```

`secrets` へ進む条件: `common` が正常終了し、手動再起動案内が残っていないこと。

### コマンド一覧

| コマンド | 内容 |
|---|---|
| `bootstrap.sh` | 前提 CLI を初期導入 |
| `setup.sh --precheck` | settings / SSH / inventory 等を確認 |
| `setup.sh common` | 共通ミドルウェア導入 |
| `setup.sh control-plane` | control-plane 初期化 |
| `setup.sh workers` | worker を k8s クラスタへ参加 |
| `setup.sh secrets` | SealedSecret 生成・Git 反映 |
| `setup.sh node-config` | crontab / logrotate 設定 |
| `setup.sh all` | 全体収束 |
| `setup.sh all --no-publish` | Release workflow は起動しない |
| `setup.sh all --publish` | Release workflow を強制起動 |

その他オプションは `setup.sh --help` を参照。<br>
ログは `~/Linux/platforms/setup/logs/` に出力される。

### 更新時の使い分け

| やりたいこと | 実行すること |
|---|---|
| Secret 値を変更 | `settings_secret.yml` を更新後<br>`setup.sh secrets` |
| SMB IP だけ変更 | `settings_secret.yml` を更新後<br>`setup.sh control-plane` |
| SMB 認証情報も変更 | `setup.sh secrets`<br>→ `setup.sh control-plane` |
| app の再同期 | `argocd app sync APPLICATION_NAME` |
| Release なしで全体収束 | `setup.sh all --no-publish` |

### local CLI 更新

- local CLI 更新は `setup.sh` / `bootstrap.sh` では自動実行しない。確認は `check-local-tools.sh`、手動更新は `update-local-tools.sh --apply`。
- 週次確認・自動更新は `Local Tools Check` / `Local Tools Auto Update` workflow が担う。
</details>

<details>
<summary>4. 構築後確認</summary>

この章の目的:

- 構築結果が正常であることを確認する。

この章でやること:

- Kubernetes / Argo CD の全体状態を確認する。
- Secret / SealedSecret が反映されていることを確認する。

完了条件:

- 全 node が `Ready`、主要 Pod が `Running` / `Completed`。
- Argo CD app が `Synced` / `Healthy`。
- 必要な Secret が各 namespace に存在する。

**実行場所: k8s操作ホスト**

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pvc -A
argocd app list
```

Argo CD 画面には `admin` / `argocd.admin_password` でログインする。

### Secret / SealedSecret 確認

```bash
kubectl get sealedsecrets --all-namespaces
kubectl get secret -A \
  | grep -E 'alertmanager-discord|cloudflare|mariadb-phpmyadmin|minecraft|navidrome-smb|wordpress'
argocd app get secrets
```

- `settings_secret.yml` は Git に commit しない。
- `setup.sh secrets` が Git 管理する生成物は SealedSecret manifest のみ。
- Secret が未反映の場合は `secrets` Application と sealed-secrets controller を確認する。
</details>

<details>
<summary>5. アプリ初期設定・ログイン</summary>

この章の目的:

- 利用するアプリの初期設定・ログインを行う。

この章でやること:

- アプリの namespace / ログイン方法を確認する。
- Grafana admin password を取得またはリセットする。
- phpMyAdmin で DB ユーザー・データベースを作成する。
- WordPress に WPvivid を導入しバックアップを設定する。

完了条件:

- 利用するアプリに正常にログインできる。
- DB ユーザー・データベースが作成済みで権限が確認できる。
- WordPress のバックアップスケジュールが有効。

利用する app だけ確認・設定する。

| アプリ | namespace | Argo CD App |
|---|---|---|
| Grafana | `monitoring` | `monitoring` |
| Prometheus | `monitoring` | `monitoring` |
| Alertmanager | `monitoring` | `monitoring` |
| Argo CD | `argocd` | — (Helm) |
| Navidrome | `navidrome` | `navidrome` |
| MariaDB | `mariadb-phpmyadmin` | `mariadb-phpmyadmin` |
| phpMyAdmin | `mariadb-phpmyadmin` | `mariadb-phpmyadmin` |
| WordPress | `wordpress` | `wordpress` |
| Minecraft | `minecraft` | `minecraft` |
| Cloudflare | `cloudflare` | `cloudflare` |
| SealedSecrets | `sealed-secrets` | `sealed-secrets` |
| Rook / Ceph | `rook-ceph` | `rook-release` |

### 初回ログインと注意

- **Argo CD**: `admin` + `argocd.admin_password`。
  password 変更は `settings_secret.yml` 更新後 `setup.sh all`。
- **Navidrome**: 初回アクセス時に admin 作成。
  `/music` は TrueNAS SMB mount。
- **MariaDB / phpMyAdmin**: `root` + `databases.root_password`。
- **WordPress**: 初回アクセス時に admin 作成。
  DB 接続は `wordpress-secret`。
- **Minecraft**: クライアント接続。
  Argo CD は `prune: false` / `selfHeal: false`。
- **Cloudflare Tunnel**: token は `cloudflare-secret`。
  設定変更は Dashboard。
- **SealedSecrets**: `setup.sh secrets` が manifest 生成。
- **Rook / Ceph**: CephFS StorageClass `cephfs-storage-class`。

### Grafana admin password

**実行場所: k8s操作ホスト**

初期パスワードの取得:

```bash
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

ユーザー名は `admin`。<br>
初回ログイン後、Grafana UI の「User Info → Change Password」でパスワードを変更する。

**admin パスワードを忘れた場合のリセット:**

Grafana は永続 PVC（`grafana-pvc`）を使用する。<br>
Argo CD で再同期しても admin パスワードは Helm values の初期値に戻らない。<br>
`grafana cli` を使ってリセットする。

```bash
# k8s操作ホストで実行
POD=$(kubectl -n monitoring get pod \
  -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}')
read -rsp 'New Grafana admin password: ' NEWPW; echo
kubectl -n monitoring exec -it "$POD" -c grafana -- \
  grafana cli --homepath /usr/share/grafana \
  admin reset-admin-password "$NEWPW"
unset NEWPW
```

リセット後のログインユーザー名は `admin`。

実装ファイル:

- Helm values: `platforms/kubernetes/apps/monitoring/values.yml`
- Alert rules: `platforms/kubernetes/apps/monitoring/rules/`
- PVC: `platforms/kubernetes/apps/storages/cephfs-pvc-monitoring.yml`

### DB ツール一式設定

**実行場所: k8s操作ホスト**

phpMyAdmin の Service IP を確認する。

```bash
kubectl get svc -n mariadb-phpmyadmin -o wide
```

`root` + `databases.root_password` で phpMyAdmin にログインし、以下の 6 データベースを作成する。

| データベース | 対応する設定キー |
|---|---|
| `minecraft_bluemap1` | `databases.database1` |
| `minecraft_bluemap2` | `databases.database2` |
| `minecraft_greetmate1` | `databases.database1` |
| `minecraft_greetmate2` | `databases.database2` |
| `minecraft_luckperms` | `databases.database3` |
| `wordpress` | `databases.database4` |

`databases.database1` 〜 `databases.database4` の各 `username` に対応する DB ユーザーを作成する。

同じユーザー名が複数の設定キーに指定されている場合、ユーザー作成は 1 回でよい。

各ユーザーに対応するデータベース固有の権限を付与する。

| 設定キー | 権限を付与するデータベース |
|---|---|
| `databases.database1.username` | `minecraft_bluemap1` / `minecraft_greetmate1` |
| `databases.database2.username` | `minecraft_bluemap2` / `minecraft_greetmate2` |
| `databases.database3.username` | `minecraft_luckperms` |
| `databases.database4.username` | `wordpress` |

ユーザー名とパスワードの実値は Git 管理外の `platforms/settings/settings_secret.yml` を参照し、キー構成は `platforms/settings/settings_secret_template.yml` を確認する。

各ユーザーで phpMyAdmin にログインし、DB と権限が確認できれば完了。

### WordPress / WPvivid 設定

**実行場所: k8s操作ホスト**

WordPress の Service IP を確認する。

```bash
kubectl get svc -n wordpress -o wide
```

WordPress 管理画面にログインし、WPvivid Backup & Restore プラグインを導入する。

- プラグイン: [WPvivid Backup & Restore](https://wordpress.org/plugins/wpvivid-backuprestore/)

バックアップの復元:

- `WPvivid Backup` → `バックアップ＆復元` → `アップロード` を開く。
- `*_backup_all.zip` をドラッグ＆ドロップし `Upload` を実行する。
- `バックアップ＆復元` → `復元` を実行する。
- 復元後、不要になったアップロード済みバックアップを削除する。

スケジュール・保持設定:

- `スケジュール` → `バックアップスケジュールの有効化` → `変更を保存` を実行する。
- `設定` → `バックアップの保持` を `7` にして `変更を保存` する。

ディスク整理・動作確認:

- `設定` → `WPvivid で使用する Web サーバーのディスクスペース` で全てにチェックし `空にする` を実行する。
- `バックアップ＆復元` → `バックアップ` を実行する。
- 作成したバックアップをダウンロードし、削除する。
- 再度 `設定` → `WPvivid で使用する Web サーバーのディスクスペース` で全てにチェックし `空にする` を実行する。
</details>

<details>
<summary>6. 外部バックアップ・通知</summary>

この章の目的:

- Proxmox VM バックアップと Gmail → Discord 通知の外部手動設定を整理する。

この章でやること:

- Proxmox 側の VM バックアップ設定を確認する。
- Spreadsheet / Apps Script 通知を設定する。

完了条件:

- Minecraft 内部バックアップと Proxmox VM バックアップの違いを区別できる。
- TrueNAS 通知メールを Discord へ転送できる。

### Proxmox VM バックアップ

**実行場所: Proxmox GUI**

これは Proxmox guest 全体を保護する外部手動設定。<br>
Minecraft PVC、`mc-backup` sidecar、resource baseline archive とは別物として扱う。

| 項目 | 設定 |
|---|---|
| ストレージ | `Proxmox` |
| スケジュール | `tue 04:00` |
| 選択モード | 全部 |
| メール送信先 | 管理者メールアドレス |
| 通知 | 常に通知 |
| 圧縮 | `ZSTD` |
| モード | スナップショット |
| Retention | 毎週保持 `2` |

### Spreadsheet / Apps Script 通知

**実行場所: 作業PC / Google Spreadsheet / Apps Script**

参照資材:

- `platforms/appnotice/appNotice.csv`
- `platforms/appnotice/appNotice.gs`

設定内容:

- Spreadsheet に `appNotice` シートを作成する。
- `appNotice.csv` の内容を反映し、`C2` に Discord webhook URL を設定する。
- `appNotice.gs` の `SpreadsheetApp.openByUrl(...)` を実 Spreadsheet URL に置換する。
- Apps Script の `hook` 関数を時間主導型トリガーで 30 分おきに実行する。
- エラー通知は毎日通知にする。

現行コードの注意:

- Advanced Gmail API の追加は不要。
- 使用するサービスは `GmailApp` / `SpreadsheetApp` / `UrlFetchApp`。
- 初回実行時に Gmail、Spreadsheet、外部通信の認可が必要。
- Gmail 検索条件は `subject:TrueNAS is:unread`。
- Proxmox 通知メールは現行コードでは拾わない。
- Discord 送信に全件成功した場合だけ既読化し、スレッドをゴミ箱へ移動する。
- 失敗時は未読維持で再試行されるため、同じスレッド内の既読メッセージを含めて二重通知になる可能性がある。
</details>

<details>
<summary>7. Minecraft / GreetMate 運用</summary>

この章の目的:

- Minecraft の起動停止・復旧・DB 初期設定を行う。

この章でやること:

- start / stop と PVC 緊急メンテナンスを実行する。
- PVC 緊急メンテナンスと GreetMate DB 初期設定を行う。

完了条件:

- Minecraft が正常に起動している。
- PVC 緊急メンテナンス中でないことを確認できる。

**実行場所: k8s操作ホスト**

```bash
cd ~/Linux/platforms/scripts/minecraft
./minecraft_start.sh
./minecraft_stop.sh
```

`minecraft_start.sh` / `minecraft_stop.sh` は script 自身の配置場所から repository root を算出する。<br>
workflow から checkout 配下の script を実行した場合も、同じ checkout 配下の manifest と `settings_secret.yml` を参照する。

`minecraft_start.sh` は `minecraft-pvc-emergency-maintenance` Pod が存在する場合、Deployment apply や Argo CD 操作より前に非0終了する。<br>
PVC emergency maintenance 中は `pvc-emergency-finish` でメンテナンス Pod の削除完了を確認してから起動する。

`minecraft_start.sh` / `minecraft_stop.sh` は appNotice 通知のため、`settings_secret.yml` の `APPNOTICE_IP` / `APPNOTICE_USERNAME` で指定した SSH 先へ接続する。<br>
SSH 先には `platforms/appnotice` 相当の資材が配置されている前提があるため、新規構築時は外部 appNotice 通知先の配置も確認する。<br>
appNotice 通知を使わない運用にする場合は、通知処理の扱いを事前に確認する。

必要コマンド:

- `kubectl`
- `argocd`
- `yq`
- `ssh`
- `sudo`

restore / backup-export / resource-refresh は Phase 0 では無効化中。<br>
必須構造検証、snapshot、rollback、baseline archive 作成が揃うまで標準手順として実行しない。

GreetMate ローカルビルド:

```bash
cd ~/Linux/platforms/applications/minecraft/greetmate
mvn clean package
```

### PVC 緊急メンテナンス

`Minecraft Maintenance` workflow の `pvc-emergency-start` / `pvc-emergency-finish` を使う。<br>
PVC を直接変更できる危険操作のため、実行前に backup / snapshot を取得する。<br>
`pvc-emergency-finish` を忘れると Minecraft は停止したままになる。

`minecraft-pvc-emergency-maintenance` Pod は PVC 緊急メンテナンス中の運用ロックとして扱う。<br>
`pvc-emergency-start` は既存ロックがある場合に失敗し、`pvc-emergency-finish` はロック Pod が既に削除済みでも Minecraft がReadyなら no-op として終了する。<br>
Minecraft が停止中または起動確認前に失敗した場合は、同じ確認文字列で `pvc-emergency-finish` を再実行して起動確認へ進める。

`Minecraft Maintenance` workflow は `production` Environment を参照する。<br>
GitHub 側で `production` Environment と Required reviewers 等の保護ルールを設定しない限り、手動承認は保証されない。<br>
利用可能な保護機能は repository の公開範囲と GitHub plan に依存する。

利用可能な task:

| task | 状態 | 備考 |
|---|---|---|
| `bluemap-reload` | 条件付き利用可能 | メンテナンス Pod 不在、server1/server2 Ready、BlueMap JAR 配置済み、RCON Secret key 存在時のみJob作成 |
| `pvc-emergency-start` | 利用可能 | 既存メンテナンス Pod がある場合は失敗 |
| `pvc-emergency-finish` | 利用可能 | メンテナンス Pod を削除後に Minecraft を起動。途中失敗後の再実行に対応 |
| `resource-refresh` | 無効化中 | baseline 作成と rollback が未整備 |
| `backup-export` | 無効化中 | CronJob と Secret が未実装 |
| `restore` | 無効化中 | 必須構造検証、snapshot、rollback が未整備 |

timeout 時は GitHub Actions summary と Pod 状態を確認する。<br>
PVC emergency Pod が作成されていない場合は、Minecraft が停止途中または停止中の可能性を確認してから `pvc-emergency-finish` を再実行する。

### ログ確認

Kubernetes 上のログは `kubectl logs` を優先する。

```bash
kubectl -n minecraft logs deploy/minecraft-proxy -c minecraft-proxy --tail=200
kubectl -n minecraft logs deploy/minecraft-server1 -c minecraft-server1 --tail=200
kubectl -n minecraft logs deploy/minecraft-server2 -c minecraft-server2 --tail=200
kubectl -n minecraft logs deploy/minecraft-server1 -c minecraft-backup-1 --tail=200
kubectl -n minecraft logs deploy/minecraft-server2 -c minecraft-backup-2 --tail=200
kubectl -n minecraft get jobs
kubectl -n minecraft logs job/JOB_NAME --tail=200
```

host 側 script ログ:

```bash
sudo tail -n 200 /var/log/update/update.log
sudo tail -n 200 /var/log/minecraft/minecraft_start.log
sudo tail -n 200 /var/log/minecraft/minecraft_stop.log
```

`minecraft_cron2.log` は対象 script がないため使用しない。<br>
`minecraft_cron1.log` は現行 Ansible の cron 登録対象ではないため、日常確認手順には含めない。

### Plugin 配置状況

GreetMate 以外の plugin JAR 取得・配置は未自動化。<br>
conversion script の存在は plugin 導入済みを意味しない。

| plugin | 配置先 | 取得・配置 | conversion | 備考 |
|---|---|---|---|---|
| BlueBorder | server1 / server2 | 未自動化 | なし | 要確認 |
| BlueMap | server1 / server2 | 未自動化 | あり | RCON reload は導入済みの場合のみ |
| Chunky | server1 / server2 | 未自動化 | あり | backup/restore は関連データのみ |
| CoreProtect | server1 / server2 | 未自動化 | なし | 操作は兄弟 Minecraft README を参照 |
| DecentHolograms | server1 / server2 | 未自動化 | なし | 要確認 |
| Geyser | proxy | 未自動化 | あり | proxy 互換性は要確認 |
| Floodgate | proxy | 未自動化 | あり | proxy 互換性は要確認 |
| GreetMate | server1 / server2 | workflow でJAR配置 | DB SQL 手順あり | reload は PlugManX 導入済みの場合のみ |
| LuckPerms | proxy / server1 / server2 | 未自動化 | あり | DB 設定変換あり |
| LunaChat | server1 / server2 | 未自動化 | あり | 要確認 |
| Multiverse-Core | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |
| Multiverse-Portals | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |
| Multiverse-NetherPortals | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |
| Multiverse-Inventories | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |
| PlaceholderAPI | server1 / server2 | 未自動化 | なし | 要確認 |
| PlugManX | server1 / server2 | 未自動化 | なし | GreetMate reload の前提 |
| TabTPS | server1 / server2 | 未自動化 | なし | 要確認 |
| ViaVersion | server1 / server2 | 未自動化 | なし | 要確認 |
| ViaBackwards | server1 / server2 | 未自動化 | なし | 要確認 |
| ViaRewind | server1 / server2 | 未自動化 | なし | 要確認 |
| WorldEdit | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |
| WorldGuard | server1 / server2 | 未自動化 | なし | 関連データ restore のみ |

ゲーム内 OP 操作と plugin 固有コマンドは兄弟 repository `../Minecraft/README.md` を参照する。

### Conversion script

存在する script:

- `minecraft_conversion_server.sh`
- `minecraft_conversion_bluemap.sh`
- `minecraft_conversion_chunky.sh`
- `minecraft_conversion_geysermc.sh`
- `minecraft_conversion_luckperms.sh`
- `minecraft_conversion_lunachat.sh`

これらは `/mnt/share/kubernetes/minecraft` 配下を直接編集する前提。<br>
現在の CephFS PVC とこの host path の接続根拠は repository 内では確認できない。<br>
標準手順として直接実行せず、PVC maintenance Pod または Job 化を別途設計する。

### Resource ワールド

`minecraft-resource-refresh` CronJob は Phase 0 で無効化中。<br>
baseline archive 作成 Job、archive 検証、rollback が未実装のため、現行運用手順としては提供しない。

### Minecraft バージョン更新

- `VERSION`: Minecraft サーバーバージョン。
- `LEVEL`: ワールド保存名。
- 同じ値でも役割は異なるため、`LEVEL` を安易に変更しない。
- 一部 image は意図的に `latest` を使用し、最新追従を再現性より優先する。
- `latest` 運用のため `imagePullPolicy: Always` を明示し、Pod 作成・再作成時に最新 image を pull 確認する。
- 実行中 Pod が自動的に最新版へ置き換わるわけではないため、更新反映には rollout restart、Pod 再作成、または再デプロイが必要。
- resources は requests 中心とし、limits は一律設定しない。
- ただし `minecraft-server1` / `minecraft-server2` 本体は既存設定を維持しており、現時点では requests 未設定。`validate_k8s_policy.py` では INFO として表示されるため、実運用後の CPU / Memory 使用量を見て必要に応じて requests を追加する。
- backup、restore、rollback が検証できるまで破壊的更新は行わない。
- 任意 RCON 操作は未整備のため、旧 `mcrcon -t` は現行標準手順として扱わない。

### GreetMate DB 初期設定

`minecraft_greetmate1` と `minecraft_greetmate2` のそれぞれに対し、phpMyAdmin から以下の順で SQL を実行する:

1. `create_ban_players.sql`
2. `create_players.sql`
3. `create_roles.sql`
4. `insert_roles.sql`

SQL は `platforms/applications/minecraft/greetmate/src/main/resources/sql/` にある。
</details>

<details>
<summary>8. 障害対応の初動</summary>

この章の目的: 障害発生時に最初に確認するコマンドと導線を提供する。

この章でやること:

- 状態確認コマンドを実行し、症状に応じた確認先を特定する。

完了条件: kubectl / argocd の初動コマンドと障害時の導線が分かる。

**実行場所: k8s操作ホスト**

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A | grep LoadBalancer
argocd app list
```

| 症状 | 確認先 |
|---|---|
| node が NotReady | `kubectl describe node NODE_NAME` |
| Pod が起動しない | `kubectl -n NAMESPACE logs POD_NAME` |
| Argo CD が OutOfSync | `argocd app sync APPLICATION_NAME` |
| Secret が未反映 | `argocd app get secrets` |
| PVC が Pending | `kubectl get pvc -A` |
| Grafana ログイン不可 | 手順 5「アプリ初期設定・ログイン」 |
| Minecraft 障害 | 手順 7「Minecraft / GreetMate 運用」 |
| Job が失敗 | `kubectl -n NAMESPACE logs job/JOB_NAME` |
| GitHub Actions が失敗 | Actions run の summary と logs |
</details>

<details>
<summary>9. GitHub Actions / Release</summary>

この章の目的: workflow の役割と Release / deploy の注意を確認する。

この章でやること:

- workflow 一覧を確認する。
- Minecraft deploy の手順と Release / tag / asset の制約を確認する。

完了条件:

- 各 workflow の用途と production 承認の必要性を確認できる。
- release / tag / asset が自動上書きされないことを確認できる。

| workflow | 実行 | 役割 |
|---|---|---|
| `Infrastructure Validate` | push / PR | 品質検証 |
| `Test on Pull Request` | PR | GreetMate Maven test |
| `Build and Release` | 手動 | JAR build / release |
| `Minecraft Maintenance` | 手動 | BlueMap reload / PVC emergency |
| `Pre-commit Autoupdate` | 週次 / 手動 | hook rev 更新 PR |
| `Local Tools Check` | 週次 / 手動 | local CLI 検知 |
| `Local Tools Auto Update` | 週次 / 手動 | local CLI 自動更新 |

`Build and Release` の build / release job は GitHub-hosted runner を使う。<br>
`Build and Release` の deploy / reload job と `Minecraft Maintenance` は self-hosted runner を前提にする。

Minecraft を操作する `deploy-jar` / `rcon-reload` job と `Minecraft Maintenance` は共通 concurrency group `minecraft-operations` を使う。<br>
concurrency は workflow run 中だけの排他であり、PVC emergency maintenance 完了までの状態ロックは `minecraft-pvc-emergency-maintenance` Pod の存在確認で行う。

`Minecraft Maintenance` は `production` Environment を参照する。<br>
GitHub 側で Environment 保護ルールを設定しない限り、Required reviewers による承認は保証されない。

### Minecraft deploy

GitHub Actions 画面から `Build and Release` を手動実行し `deploy_to_servers=true` を選ぶ。<br>
`deploy-jar` job は GitHub Environment `production` を使用する。<br>
Required reviewers / Prevent self-review の設定を推奨する。

deploy / reload は旧 JAR 削除前と RCON Job 作成前にメンテナンス Pod 不在、server1/server2 Deployment と Pod のReadyを確認する。<br>
ただし server1 成功後に server2 が失敗した場合の原子的 rollback は未実装。<br>
PlugManX 未導入時や reload 失敗時は自動復旧しない。

### Release / tag / asset の注意

`setup.sh all` は deploy を行わないため production Environment 承認不要で Release 登録だけを行う。<br>
起動には `github.owner` / `github.repo` / `github.token`（Actions: Read and write）が必要。

- `github.dispatch_build_release=false` の場合、Release workflow を起動しない。
- `github.dispatch_build_release=true` の場合だけ起動する。
- 明示的に起動: `setup.sh all --publish`。
  省略: `setup.sh all --no-publish`。
- `setup.sh all --dry-run` では Release workflow は起動しない。
- 既存の release / tag / asset は自動で削除・上書きしない。
- 再 publish する場合は `pom.xml` の version を上げる。
</details>

<details>
<summary>10. 検証・品質ゲート</summary>

この章の目的: README / Secret / shell / workflow / K8s policy の品質を検証する。

この章でやること:

- validate scripts を実行する。
- pre-commit を実行する（未インストール時は skip）。

完了条件: validate scripts が全て PASSED。

**実行場所: k8s操作ホスト**

```bash
cd ~/Linux/platforms/setup/validate
./check_secrets.sh
./validate_readme.sh
./validate_shell_safety.sh
./validate_release_workflows.sh
./validate_python.sh
python3 ./validate_k8s_policy.py
```

```bash
cd ~/Linux
PRE_COMMIT_HOME=/tmp/pre-commit-cache pre-commit run -c .pre-commit-config.yml --all-files
```

pre-commit hook は「固定 `rev` + autoupdate PR」で最新追従する。
</details>
