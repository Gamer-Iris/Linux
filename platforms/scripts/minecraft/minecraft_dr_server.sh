#!/bin/bash

######################################################################################################################################################
# ファイル   : minecraft_dr_server.sh
# 引数       : [--yes] [--skip-restore]
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

#*****************************************************************************************************************************************************
# 引数解析
#*****************************************************************************************************************************************************
AUTO_CONFIRM=0
SKIP_RESTORE=0
for _ARG in "$@"; do
  case "${_ARG}" in
    --yes)          AUTO_CONFIRM=1 ;;
    --skip-restore) SKIP_RESTORE=1 ;;
    *) echo "Unknown option: ${_ARG}" >&2; exit 1 ;;
  esac
done

#*****************************************************************************************************************************************************
# 定数
#*****************************************************************************************************************************************************
NAMESPACE="minecraft"
DEPLOYMENTS="minecraft-proxy minecraft-server1 minecraft-server2"
RESTORE_FOLDER1="/mnt/share/kubernetes/minecraft/server1"
RESTORE_FOLDER2="/mnt/share/kubernetes/minecraft/server2"
RESTORE_SCRIPT="$(dirname "$0")/minecraft_restore_server.sh"
POD_STOP_TIMEOUT=180    # Pod 停止待機タイムアウト（秒）
POD_START_TIMEOUT=300   # Pod 起動待機タイムアウト（秒）

#*****************************************************************************************************************************************************
# ヘルパー関数
#*****************************************************************************************************************************************************
confirm() {
  local MSG="$1"
  if [ "${AUTO_CONFIRM}" = "1" ]; then
    echo "[AUTO] ${MSG}"
    return 0
  fi
  echo ""
  echo ">>> ${MSG}"
  printf "続行しますか？ (y/N): "
  read -r _ANS
  case "${_ANS}" in
    [yY]) return 0 ;;
    *) echo "中止しました。" >&2; exit 0 ;;
  esac
}

step() {
  echo ""
  echo "======================================================"
  echo "[DR] ${1}"
  echo "======================================================"
}

#*****************************************************************************************************************************************************
# 前提確認
#*****************************************************************************************************************************************************
step "0" "前提確認"

echo "------------------------------------------------------"
echo "DR scope: K8s rebuild DR（external Ceph alive 前提）"
echo "  本スクリプトは external Ceph が正常稼働していることを前提とする。"
echo "  Ceph 自体が失われた場合は S3 remote から別途 restore が必要。"
echo "  事前に確認: ceph status（Ceph が HEALTH_OK であること）"
echo "------------------------------------------------------"
echo ""

echo "kubectl 接続確認..."
if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
  echo "ERROR: kubectl が cluster に接続できません" >&2
  echo "  kubeconfig を確認してください: echo \$KUBECONFIG" >&2
  exit 1
fi
echo "  kubectl: OK"

echo "minecraft namespace 確認..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "ERROR: namespace '${NAMESPACE}' が存在しません" >&2
  echo "  ArgoCD で namespaces app を sync してください:" >&2
  echo "    argocd app sync namespaces" >&2
  exit 1
fi
echo "  namespace: OK"

echo "minecraft Deployment 存在確認..."
for DEPLOY in ${DEPLOYMENTS}; do
  if ! kubectl -n "${NAMESPACE}" get deployment "${DEPLOY}" >/dev/null 2>&1; then
    echo "WARNING: deployment '${DEPLOY}' が存在しません" >&2
    echo "  ArgoCD で minecraft app を sync してください:" >&2
    echo "    argocd app sync minecraft" >&2
    echo "  （deployment が存在しない場合は DR-A の scale 操作をスキップします）"
  fi
done

echo "CephFS マウント確認..."
CEPHFS_OK=1
for DIR in "${RESTORE_FOLDER1}" "${RESTORE_FOLDER2}"; do
  if [ ! -d "${DIR}" ]; then
    echo "WARNING: ${DIR} が存在しないか、マウントされていません" >&2
    CEPHFS_OK=0
  else
    echo "  ${DIR}: OK"
  fi
done
if [ "${CEPHFS_OK}" = "0" ]; then
  echo "WARNING: CephFS マウントが不完全です" >&2
  echo "  Rook external cluster の状態を確認してください:" >&2
  echo "    kubectl -n rook-ceph-external get pod" >&2
  echo "    ceph status" >&2
  echo ""
  confirm "CephFS マウントが不完全ですが続行しますか？（restore 先が存在しない場合は失敗します）"
fi

echo "restore スクリプト確認..."
if [ ! -f "${RESTORE_SCRIPT}" ]; then
  echo "ERROR: restore スクリプトが見つかりません: ${RESTORE_SCRIPT}" >&2
  exit 1
fi
echo "  restore script: OK"

echo ""
echo "前提確認完了。DR を開始します。"
confirm "DR フローを開始します"

#*****************************************************************************************************************************************************
# Minecraft Pod 停止
#*****************************************************************************************************************************************************
step "A" "Minecraft Pod 停止"

echo "現在の Pod 状態:"
kubectl -n "${NAMESPACE}" get pods 2>/dev/null || echo "  (Pod なし)"

# いずれかの deployment が running かどうか確認
RUNNING_COUNT=0
for DEPLOY in ${DEPLOYMENTS}; do
  REPLICAS=$(kubectl -n "${NAMESPACE}" get deployment "${DEPLOY}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  [ "${REPLICAS}" -gt 0 ] && RUNNING_COUNT=$((RUNNING_COUNT + 1))
done

if [ "${RUNNING_COUNT}" = "0" ]; then
  echo "Minecraft Pod は既に停止しています（scale 0）"
else
  confirm "Minecraft サーバーを停止します（replicas: 0 に scale）"
  for DEPLOY in ${DEPLOYMENTS}; do
    kubectl -n "${NAMESPACE}" scale deployment "${DEPLOY}" --replicas=0 \
      2>/dev/null || true
  done

  echo "Pod 終了を待機します（最大 ${POD_STOP_TIMEOUT} 秒）..."
  echo "※ terminationGracePeriodSeconds: 120 のため最大 2 分かかります"
  WAITED=0
  while [ "${WAITED}" -lt "${POD_STOP_TIMEOUT}" ]; do
    REMAINING=$(kubectl -n "${NAMESPACE}" get pods \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l)
    [ "${REMAINING}" = "0" ] && break
    echo "  残 Pod: ${REMAINING}（待機中 ${WAITED}/${POD_STOP_TIMEOUT}秒）"
    sleep 10
    WAITED=$((WAITED + 10))
  done

  FINAL_COUNT=$(kubectl -n "${NAMESPACE}" get pods --no-headers 2>/dev/null | wc -l)
  if [ "${FINAL_COUNT}" != "0" ]; then
    echo "WARNING: ${POD_STOP_TIMEOUT} 秒経過後も Pod が残っています" >&2
    kubectl -n "${NAMESPACE}" get pods
    confirm "Pod が残っていますが restore を続行しますか？（データ破損リスクあり）"
  else
    echo "全 Pod が停止しました"
  fi
fi

#*****************************************************************************************************************************************************
# CephFS データ確認
#*****************************************************************************************************************************************************
step "B" "CephFS データ確認"

echo "現在の world data 状態:"
for SERVER in 1 2; do
  DIR_VAR="RESTORE_FOLDER${SERVER}"
  DIR="${!DIR_VAR}"
  if [ -d "${DIR}" ]; then
    FILE_COUNT=$(find "${DIR}" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
    echo "  server${SERVER}: ${DIR} (${FILE_COUNT} entries)"
    ls -la "${DIR}" 2>/dev/null | head -10 || true
  else
    echo "  server${SERVER}: ${DIR} — NOT FOUND（マウントなし / データなし）"
  fi
done

echo ""
echo "CephFS にデータが残っている場合、restore なしで Pod を起動するだけで復旧できます。"
echo "データが失われている / 破損している場合は restore を実行してください。"

#*****************************************************************************************************************************************************
# restore 実行
#*****************************************************************************************************************************************************
step "C" "world data restore"

if [ "${SKIP_RESTORE}" = "1" ]; then
  echo "--skip-restore が指定されているため restore をスキップします"
  echo "restore を手動実行する場合:"
  echo "  bash ${RESTORE_SCRIPT} [--dry-run] [--yes]"
else
  echo ""
  echo "restore を実行する前に dry-run で変更内容を確認することを推奨します:"
  echo "  bash ${RESTORE_SCRIPT} --dry-run"
  echo ""
  confirm "restore を実行します（${RESTORE_SCRIPT}）"

  RESTORE_ARGS=""
  [ "${AUTO_CONFIRM}" = "1" ] && RESTORE_ARGS="--yes"

  # shellcheck disable=SC2086
  bash "${RESTORE_SCRIPT}" ${RESTORE_ARGS}
  echo "restore 完了"
fi

#*****************************************************************************************************************************************************
# Minecraft Pod 起動
#*****************************************************************************************************************************************************
step "D" "Minecraft Pod 起動"

confirm "Minecraft サーバーを起動します（replicas: 1 に scale）"

for DEPLOY in ${DEPLOYMENTS}; do
  kubectl -n "${NAMESPACE}" scale deployment "${DEPLOY}" --replicas=1 \
    2>/dev/null || echo "WARNING: ${DEPLOY} の scale に失敗（存在しない可能性）"
done

echo "Pod 起動を待機します（最大 ${POD_START_TIMEOUT} 秒）..."
echo "※ JVM 起動 + world load に 2〜5 分かかります"
WAITED=0
while [ "${WAITED}" -lt "${POD_START_TIMEOUT}" ]; do
  READY_COUNT=$(kubectl -n "${NAMESPACE}" get pods \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | grep -c "Running" || true)
  echo "  Running Pod: ${READY_COUNT}（待機中 ${WAITED}/${POD_START_TIMEOUT}秒）"
  [ "${READY_COUNT}" -ge 2 ] && break   # server1 + server2 が Running
  sleep 15
  WAITED=$((WAITED + 15))
done

#*****************************************************************************************************************************************************
# 起動確認
#*****************************************************************************************************************************************************
step "E" "起動確認"

echo "Pod 状態:"
kubectl -n "${NAMESPACE}" get pods

echo ""
echo "minecraft-server1 の直近ログ:"
kubectl -n "${NAMESPACE}" logs \
  -l app=minecraft-server1 \
  -c minecraft-server1 \
  --tail=20 2>/dev/null || echo "  (ログ取得失敗 / Pod 未起動)"

echo ""
echo "minecraft-server2 の直近ログ:"
kubectl -n "${NAMESPACE}" logs \
  -l app=minecraft-server2 \
  -c minecraft-server2 \
  --tail=20 2>/dev/null || echo "  (ログ取得失敗 / Pod 未起動)"

echo ""
echo "======================================================"
echo "DR フロー完了"
echo ""
echo "次の確認を手動で実施してください:"
echo "  1. Minecraft に接続してワールドデータを確認する"
echo "  2. Prometheus / Grafana でアラートがないことを確認する:"
echo "       http://192.168.11.73（Grafana）"
echo "       http://192.168.11.72（Alertmanager）"
echo "  3. Alertmanager の maintenance silence を解除する（設定している場合）:"
echo "       amtool silence expire --alertmanager.url=http://192.168.11.72 <silence-id>"
echo ""
echo "問題が発生した場合のロールバック:"
echo "  bash ${RESTORE_SCRIPT} --dry-run  # 変更内容確認"
echo "  ls ${MNT_POINT:-/mnt/truenas_minecraft_bk}/pre-restore-*/  # スナップショット確認"
echo "  sudo rsync -a <snapshot>/server1/ ${RESTORE_FOLDER1}/"
echo "  sudo rsync -a <snapshot>/server2/ ${RESTORE_FOLDER2}/"
echo "======================================================"
