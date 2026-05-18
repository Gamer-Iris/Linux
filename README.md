## 各操作マニュアル

**【ネットワーク図】**<br>
<img src="diagrams/Gamer-Iris_home_infra.drawio.svg" width="800"><br>

この README.md を利用者向けの正本手順として扱う。
詳細な実装は script / manifest / workflow 側を source of truth とし、README には導線と運用要点を書く。

**重要:**

- 実 secret / token / private key は commit しない。
- `~/Linux/platforms/setup/setup.sh all` は初回構築または全体を収束し直す時だけ使う。
- `setup.sh all` は構築完了後に GreetMate JAR の GitHub Release 登録 workflow を起動する。
- Release workflow は `deploy_to_servers=false` で起動するため、Minecraft サーバーへの deploy は行わない。
- GitHub CLI が使えない環境や検証目的で Release 登録を省略する場合は `setup.sh all --no-publish` を使う。

<details>
<summary>最短構築フロー</summary>

初見の場合は上から順に進める。
構築後の確認、個別 app 設定、運用手順は `setup.sh all` 完了後に必要なものだけ実施する。

1. 事前準備
2. Proxmox / Ceph / TrueNAS / VM / SSH を準備
3. k8s control-plane へ Git clone
4. `~/Linux/platforms/settings/settings_secret.yml` を作成・編集
5. Argo CD Deploy Key を作成・GitHub へ登録
6. Rook external cluster import の export を `~/Linux/platforms/setup/rook-ceph-env.sh` に保存
7. setup script を実行
8. 構築後確認
9. 必要な app だけ個別設定

```bash
~/Linux/platforms/setup/bootstrap.sh
~/Linux/platforms/setup/setup.sh --precheck
~/Linux/platforms/setup/setup.sh all --dry-run
~/Linux/platforms/setup/setup.sh secrets
~/Linux/platforms/setup/setup.sh all
```

更新時の使い分け:

| やりたいこと | 実行すること |
|---|---|
| Secret 値を変更する | `~/Linux/platforms/settings/settings_secret.yml` を編集し、`~/Linux/platforms/setup/setup.sh secrets` |
| SMB 接続先 IP だけ変更する | `~/Linux/platforms/settings/settings_secret.yml` を編集し、`~/Linux/platforms/setup/setup.sh control-plane` |
| SMB 認証情報も変更する | `~/Linux/platforms/setup/setup.sh secrets` 後に `~/Linux/platforms/setup/setup.sh control-plane` |
| app の再同期だけ行う | Argo CD で対象 Application を sync。例: `argocd app sync minecraft` |
| 初回構築する | `setup.sh --precheck` → `setup.sh all --dry-run` → `setup.sh secrets` → `setup.sh all` |
| GitHub CLI が使えない環境で全体収束だけ行う | `setup.sh all --no-publish` |

### setup.sh all と GreetMate Release

`setup.sh all` は全体収束後に GreetMate JAR の GitHub Release 登録 workflow を起動する。

| コマンド | 挙動 |
|---|---|
| `setup.sh all` | setup 完了後に Release workflow を起動する |
| `setup.sh all --no-publish` | setup のみ行い、Release workflow は起動しない |
| `setup.sh all --publish` | 後方互換用。`all` と同じく Release workflow を起動する |
| `setup.sh all --release` | 後方互換用。`all` と同じく Release workflow を起動する |
| `setup.sh all --dry-run` | Ansible check mode。Release workflow は起動しない |

Release workflow は常に `deploy_to_servers=false` で起動するため、Minecraft サーバーへの deploy は行わない。
`gh` が未インストール、未ログイン、または workflow 実行権限がない場合は publish ありの `all` は失敗する。
publish なしで再実行したい場合は `--no-publish` を使う。

同じ `pom.xml` version では再 publish できない。
再 publish する場合は GreetMate の `pom.xml` version を上げる。
既存 release / tag / asset は自動上書き・削除しない。

`setup.sh all` は deploy を行わないため、production Environment 承認不要で Release 登録だけを行う。

Minecraft サーバーへ deploy したい場合:

- GitHub Actions 画面から `Build and Release` workflow を手動実行する。
- `deploy_to_servers=true` を明示的に選ぶ。
- `production` 承認を通す。

</details>

<details>
<summary>リポジトリ構成方針</summary>

```text
README.md                    利用者向けの正本手順
diagrams/                    構成図
platforms/setup/             自動構築入口、Ansible、dynamic inventory
platforms/setup/lib/         setup.sh 共通処理
platforms/setup/validate/    README / shell / Python / K8s / Secret 品質検証
platforms/settings/          settings template（実 secret は commit しない）
platforms/kubernetes/        Kubernetes / Argo CD manifest
platforms/scripts/           構築後の運用 script
platforms/scripts/minecraft/ Minecraft 起動停止、backup / restore、変換処理
platforms/scripts/kubernetes/ Kubernetes health check
platforms/applications/      アプリケーションコード
.github/workflows/           CI / 運用 workflow
```

配置ルール:

- 構築処理は `~/Linux/platforms/setup/`、構築後の運用処理は `~/Linux/platforms/scripts/` に置く。
- Kubernetes manifest は `~/Linux/platforms/kubernetes/` に置く。
- 品質検証スクリプトは `~/Linux/platforms/setup/validate/` に置く。
- README 以外の Markdown は増やさない。
- 実 secret / token / private key は commit しない。

</details>

<details>
<summary>事前準備</summary>

以下を事前に準備する。
詳細な画面操作は各製品側の手順を正とし、この README では本リポジトリで必要な入力値だけ管理する。

- Discord webhook
- Tera Term などの SSH クライアント
- Cloudflare tunnel 用 token
- Tailscale
- Apps Script / スプレッドシート通知環境（必要時）
- Proxmox VE cluster
- Proxmox 上の Ceph / CephFS
- TrueNAS SMB 共有
- Minecraft backup 用共有
- Navidrome `/music` 用 `music` 共有
- Ubuntu Server VM
- k8s control-plane
- k8s worker

Proxmox / Ceph では、CephFS 名を `cephfs` として用意する。
Rook external cluster import でこの CephFS を Kubernetes から利用する。

</details>

<details>
<summary>初回セットアップ</summary>

### Proxmox / VM 側で準備すること

- 各 Proxmox node に SSH 可能な sudo ユーザーを用意する。
- Proxmox cluster と CephFS を作成する。
- Kubernetes 用 VM を作成し、固定 IP を決める。
- 各 VM に SSH 可能な sudo ユーザーを用意する。
- 各 VM の timezone を `Asia/Tokyo` にする。
- 各 VM の swap を無効化する。
- 各 VM へ `git` / `ufw` / `tmux` を導入する。
- 必要 port を ufw で許可する。

代表的な ufw 許可 port:

```text
22
179
2049
3300
5473
6443
6789
6800:7300/tcp
8006
9100
10250
```

### k8s control-plane で clone する

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
cd ~/Linux/platforms/setup
```

### settings_secret.yml を準備する

```bash
cp ~/Linux/platforms/settings/settings_secret_template.yml \
   ~/Linux/platforms/settings/settings_secret.yml
chmod 600 ~/Linux/platforms/settings/settings_secret.yml
nano ~/Linux/platforms/settings/settings_secret.yml
```

主な設定項目:

- `username` / `password` / `key`
- `nodes.control_plane[]` / `nodes.workers[]` / `nodes.proxmox[]`
- `kubernetes.pod_network_cidr` / `kubernetes.cri_socket`
- `databases.*`
- `appnotice.ip` / `appnotice.username`
- `discord.url`
- `app_secrets.cloudflare.token`
- `app_secrets.minecraft.rcon_password_server1`
- `app_secrets.minecraft.rcon_password_server2`
- `smb.ip` / `smb.username` / `smb.password`
- `github.ssh_key_path`
- `argocd.deploy_key_path` / `argocd.admin_password`

各項目の詳細は `~/Linux/platforms/settings/settings_secret_template.yml` のコメントを正とする。
`~/Linux/platforms/settings/settings_secret.yml` は Git に commit しない。

`github.enabled=false` の場合、`github.token` / webhook / runner 関連値は初回構築に不要。
`github.webhook_enabled=true` の場合だけ、GitHub token に対象 repository の Webhooks Read and write 権限が必要。

### Argo CD Deploy Key を準備する

```bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/argo
chmod 600 ~/.ssh/argo
cat ~/.ssh/argo.pub
```

公開鍵を GitHub repository の `Settings` → `Deploy keys` → `Add deploy key` に登録する。
Argo CD は repository を読むため、通常は write 権限を付けない。
`~/Linux/platforms/settings/settings_secret.yml` の `argocd.deploy_key_path` はこの秘密鍵パスに合わせる。

### Rook external cluster import を準備する

Ceph admin 権限を持つ Proxmox host で以下を実行する。
出力された `export ...` 行だけを k8s control-plane の `~/Linux/platforms/setup/rook-ceph-env.sh` に保存する。

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

k8s control-plane 側で保存後に権限を補正する。

```bash
nano ~/Linux/platforms/setup/rook-ceph-env.sh
chmod 600 ~/Linux/platforms/setup/rook-ceph-env.sh
```

### setup.sh を実行する

長時間実行になるため tmux 内で実行する。

```bash
tmux new -s setup
cd ~/Linux/platforms/setup
~/Linux/platforms/setup/bootstrap.sh
~/Linux/platforms/setup/setup.sh --precheck
~/Linux/platforms/setup/setup.sh all --dry-run
~/Linux/platforms/setup/setup.sh secrets
~/Linux/platforms/setup/setup.sh all
```

setup 関連コマンド:

| コマンド | 内容 |
|---|---|
| `bootstrap.sh` | k8s control-plane に yq / kubeseal / Ansible などの前提 CLI を準備する |
| `setup.sh --precheck` | settings、SSH、inventory、Ansible ping / become、Argo CD Deploy Key、rook-ceph-env.sh を確認する |
| `setup.sh all --dry-run` | Ansible check mode で構築前確認を行う。Release workflow は起動しない |
| `setup.sh secrets` | SealedSecret 生成に必要な基盤準備、SealedSecret manifest 再生成、承認時の Git commit / push と `secrets` Application sync を行う |
| `setup.sh all` | 全体を収束させた後、GreetMate JAR の GitHub Release 登録 workflow を起動する |
| `setup.sh all --no-publish` | 全体収束のみ行い、GitHub Release 登録 workflow は起動しない |
| `setup.sh all --publish` / `--release` | 後方互換用。`all` では既定で Release 登録が有効 |

非対話で実行する場合は、dry-run 成功後に `setup.sh secrets --yes`、`setup.sh all --yes` を使う。
ログは `~/Linux/platforms/setup/logs/` に出力される。

### GitHub Release / deploy の安全運用

`Build and Release` workflow は GreetMate JAR を build する。
build 後、GitHub Actions artifact に upload し、GitHub Release に JAR を添付する。

Release 作成前に以下を確認する。

- `v${version}` の GitHub Release が既にある場合は失敗する。
- `v${version}` の Git tag が既にある場合は失敗する。
- 同名 asset が既にある場合は失敗する。
- 既存 release / tag / asset は削除・上書きしない。
- 再 publish には `platforms/applications/minecraft/greetmate/pom.xml` の version bump が必要。

`deploy_to_servers=true` を選ぶと、`deploy-jar` job は GitHub Environment `production` を使用する。
`rcon-reload` は `deploy-jar` 成功後に動く。

GitHub repository settings で以下を設定する。

- Environment `production` を作成する。
- Required reviewers を設定する。
- Prevent self-review を有効化することを推奨する。

注意: Environment の required reviewers は workflow YAML だけでは設定されない。
GitHub UI / repository settings 側で設定する。

</details>

<details>
<summary>構築後確認・個別設定</summary>

ここから先は構築後の確認であり、通常は `setup.sh all` を再実行しない。

### 全体状態

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get csidriver
kubectl -n rook-ceph get pods
kubectl get pvc -A
argocd app list
```

確認観点:

- node が `Ready`
- 主要 Pod が `Running` / `Completed`
- Argo CD app が `Synced` / `Healthy`
- CephFS CSI driver と PVC が作成済み

### Argo CD

Argo CD 本体のデプロイ、admin パスワード設定、GitHub repository 登録は `setup.sh all` が行う。
ここでは接続だけ確認する。

```bash
kubectl get svc -n argocd -o wide
argocd app list
```

Argo CD 画面には `admin` / `~/Linux/platforms/settings/settings_secret.yml` の `argocd.admin_password` でログインする。

### Secret / SealedSecret

```bash
kubectl get applications -n argocd
kubectl get sealedsecrets --all-namespaces
kubectl get secret -A \
  | grep -E 'alertmanager-discord|cloudflare|mariadb-phpmyadmin|minecraft|navidrome-smb|wordpress'
argocd app get secrets
```

Secret が未反映の場合は、`secrets` Application、sealed-secrets controller、対象 namespace の Secret 有無を確認する。

重要な注意点:

- `~/Linux/platforms/settings/settings_secret.yml` は Git に commit しない。
- `setup.sh secrets` が Git 管理する生成物は SealedSecret manifest のみ。
- 対象は `~/Linux/platforms/kubernetes/apps/secrets/*.yml`。
- `setup.sh secrets` の `??` は生成された未追跡 SealedSecret 候補を表す。
- 差分がない場合、commit / push は skip される。

### SMB / Navidrome music PV

Navidrome の `/music` は、TrueNAS SMB 共有 `music` を `navidrome-music-pvc` で mount する。

注意:

- `~/Linux/platforms/kubernetes/apps/storages/smb-pvc-navidrome-music.yml` は Git 管理する。
- この manifest は `${SMB_IP}` placeholder 付きで保持する。
- 実 IP 入り manifest は Git に保存しない。

`setup.sh all` / `setup.sh control-plane` が `${SMB_IP}` を展開して直接 apply する。

```bash
kubectl get csidriver smb.csi.k8s.io
kubectl -n kube-system get pod | grep smb
kubectl -n navidrome get pvc navidrome-music-pvc
```

### app 個別設定（必要時のみ）

初回構築直後に全 app の個別設定を必ず実施する必要はない。
利用する app だけ確認・設定する。

### Grafana / monitoring（任意）

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get pvc
kubectl get svc -n monitoring -o wide
argocd app get monitoring
```

Grafana admin password を変更する場合:

```bash
NEWPW='任意のGrafana adminパスワード'
kubectl -n monitoring exec -it "$POD" -c grafana -- \
  grafana cli --homepath /usr/share/grafana \
  admin reset-admin-password "$NEWPW"
```

### Navidrome（任意）

```bash
kubectl get svc -n navidrome -o wide
kubectl -n navidrome get pvc
```

初回ログイン後、必要に応じて UI 言語、プレイヤー設定、トランスコード設定を変更する。
`/music` は TrueNAS SMB 共有への読み書き可能 mount のため、TrueNAS 側の snapshot / backup を有効化しておく。
大量 scan や音楽ファイル追加は負荷の低い時間帯に実施する。

### MariaDB / phpMyAdmin（必要時）

```bash
kubectl get svc -n mariadb-phpmyadmin -o wide
```

必要に応じて phpMyAdmin から app 用 DB / user を作成する。
GreetMate 用 DB には、`~/Linux/platforms/applications/minecraft/greetmate/src/main/resources/sql/` 配下の SQL を使う。
以下の順で実行する。

```text
create_ban_players.sql
create_players.sql
create_roles.sql
insert_roles.sql
```

既存 DB に適用する場合は事前に backup を取得する。
`CREATE TABLE IF NOT EXISTS` は既存列、index、charset、collation を変更しない。

### WordPress（必要時）

```bash
kubectl get svc -n wordpress -o wide
```

必要に応じて WordPress UI から初期設定または backup plugin による復元を行う。
DB 接続情報は `wordpress-secret` から参照される。

### Minecraft（必要時）

```bash
~/Linux/platforms/scripts/minecraft/minecraft_stop.sh
~/Linux/platforms/scripts/minecraft/minecraft_conversion_server.sh
~/Linux/platforms/scripts/minecraft/minecraft_start.sh
```

プラグイン追加・設定変換は必要時のみ実施する。
変換 script は `~/Linux/platforms/scripts/minecraft/` 配下にあり、対象 plugin ごとに実行する。

GreetMate JAR は通常 GitHub Actions の `Build and Release` workflow で作成した release artifact を使う。
`setup.sh all` は構築完了後に Release 登録 workflow を起動する。
ローカルで作成する場合は Java 25 と Maven を使う。

```bash
cd ~/Linux/platforms/applications/minecraft/greetmate
mvn clean package
```

resource ワールドの backup や restore は破壊的操作になり得る。
事前に backup / snapshot を確認してから実施する。

### GitHub 連携（必要時）

`github.enabled=true` の場合だけ self-hosted runner、webhook、workflow permission の設定対象になる。
初期状態では `github.enabled=false` のため、Webhook が空でも正常。
必要時のみ GitHub UI で以下を確認する。

- `Settings` → `Webhooks`
- `Settings` → `Actions` → `Runners`
- `Settings` → `Deploy keys`
- `Settings` → `Secrets and variables` → `Actions`
- `Settings` → `Environments` → `production`

</details>

<details>
<summary>運用・品質管理（運用保守者向け）</summary>

### 定期確認

```bash
argocd app list
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl -n minecraft get cronjob
kubectl -n minecraft get jobs | tail
```

### 障害時の入口

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A | grep LoadBalancer
argocd app list
```

### Minecraft 起動停止

```bash
~/Linux/platforms/scripts/minecraft/minecraft_start.sh
~/Linux/platforms/scripts/minecraft/minecraft_stop.sh
```

Minecraft restore は破壊的操作になり得るため、必ず dry-run を先に実行する。
backup 成功は restore 成功を保証しない。
大きな変更後または年 1〜2 回は restore dry-run を確認する。

```bash
~/Linux/platforms/scripts/minecraft/minecraft_restore_server.sh --dry-run
```

### Minecraft PVC 緊急メンテ

Minecraft PVC 緊急メンテは GitHub Actions の `Minecraft Maintenance` workflow から実行する。
PVC を直接変更できる危険操作のため、実行前に backup / snapshot を取得する。
`pvc-emergency-finish` を忘れると Minecraft は停止したままになる。

```text
task=pvc-emergency-start
task=pvc-emergency-finish
```

確認欄には以下を入力する。

```text
I understand PVC contents can be modified or deleted
```

メンテナンス Pod に入る場合:

```bash
kubectl -n minecraft exec -it minecraft-pvc-emergency-maintenance -- /bin/bash
```

メンテナンス Pod は `ubuntu:latest` と `imagePullPolicy: Always` を使用する。
Docker Official Image の `ubuntu:latest` で最新 LTS に追従する意図であり、`ubuntu:rolling` は使わない。

### GitHub Actions / 品質ゲート

主な workflow:

| workflow | 役割 |
|---|---|
| `Infrastructure Validate` | README / Secret / shell / Python / YAML / Kubernetes / Ansible の検証 |
| `Test on Pull Request` | GreetMate の Maven test |
| `Build and Release` | GreetMate JAR の build / release、必要時の Minecraft 反映 |
| `Minecraft Maintenance` | Minecraft resource refresh / backup / restore / PVC emergency |
| `Pre-commit Autoupdate` | pre-commit hook rev 更新 PR 作成 |

`Build and Release` と `Minecraft Maintenance` の一部は self-hosted runner と Kubernetes 接続を前提にする。

README / shell / inventory / Kubernetes manifest の事故防止チェックは GitHub Actions で自動実行する。
PR 前に手元で確認する場合は以下を実行する。

```bash
cd ~/Linux/platforms/setup/validate
./check_secrets.sh
./validate_readme.sh
./validate_shell_safety.sh
./validate_release_workflows.sh
./validate_python.sh
python3 validate_k8s_policy.py
```

`pre-commit` を使用する場合は `~/Linux/.pre-commit-config.yml` の hooks でも同じ検証を実行できる。

```bash
cd ~/Linux
PRE_COMMIT_HOME=/tmp/pre-commit-cache pre-commit run -c ~/Linux/.pre-commit-config.yml --all-files
```

pre-commit hook は「固定 `rev` + autoupdate PR」による最新追従運用とする。
`~/Linux/.pre-commit-config.yml` の外部 hook は release tag / revision を `rev` に記録する。
HEAD / main / master tracking は使わない。

GitHub Actions の `Pre-commit Autoupdate` workflow は、週次または手動実行で pre-commit を更新・検証する。
実行するコマンドは以下の 2 つ。

- `pre-commit autoupdate -c ~/Linux/.pre-commit-config.yml`
- `pre-commit run -c ~/Linux/.pre-commit-config.yml --all-files`

差分がある場合だけ `chore/pre-commit-autoupdate` branch から Pull Request を作成する。
main への直接 push と自動 merge は行わず、review 後に取り込む。

`~/Linux/.pre-commit-config.yml` の `additional_dependencies` は hook 実行環境ごとの補助依存として扱う。
最新追従方針に合わせて version pin しない。
固定化が必要になった場合は README の方針も「固定依存」へ変更する。

実機確認が必要なものは、Kubernetes cluster、Argo CD sync、GitHub Actions、SMB mount、Minecraft PVC メンテ、Navidrome scan。
必要になったタイミングで個別に確認する。

</details>
