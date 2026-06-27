#!/bin/bash

set -euo pipefail

######################################################################################################################################################
# ファイル   : minecraft_start.sh
# 引数       : RSTEP（リスタートするジョブステップを指定）
# 復帰値     : 0 （正常終了）
#            : 10（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

#*****************************************************************************************************************************************************
# 定数エリア
#*****************************************************************************************************************************************************
# フラグ
JOB_RTN_CD=0
ABEND_FLG=0
RTN_CD=0

# エラーメッセージ設定
ERR_MESSAGE_01="マインクラフトサーバー起動に失敗しました。"
ERR_MESSAGE_02="マインクラフトサーバー起動がタイムアウトしました。"
ERR_MESSAGE_03="Argo CDの操作に失敗しました。"
ERR_MESSAGE_04="PVC emergency maintenance が継続中のため Minecraft を起動できません。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# ジョブネーム設定
JOB_NAME=$(basename "$0" | sed -e 's/.sh//g')

# 環境変数設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
SETTINGS_FILE="${SETTINGS_FILE:-${REPO_ROOT}/platforms/settings/settings_secret.yml}"
MINECRAFT_K8S_DIR="${REPO_ROOT}/platforms/kubernetes/apps/minecraft"
USERNAME=`cat "${SETTINGS_FILE}" | yq eval '.username'`
PASSWORD=`cat "${SETTINGS_FILE}" | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
KEY=`cat "${SETTINGS_FILE}" | yq eval '.key'`
APPNOTICE_IP=`cat "${SETTINGS_FILE}" | yq eval '.appnotice.ip'`
APPNOTICE_USERNAME=`cat "${SETTINGS_FILE}" | yq eval '.appnotice.username'`
TIMEOUT_DURATION=300
MINECRAFT_NAMESPACE="minecraft"
PVC_MAINTENANCE_POD="minecraft-pvc-emergency-maintenance"
TARGET_PVCS="minecraft-proxy-pvc minecraft-server1-pvc minecraft-server2-pvc"

# 変数初期化
RESULT=""
ARGOCD_SERVER_ADDRESS=""

# STEPセット
NSTEP=""
RSTEP="${1:-}"
if [ "${RSTEP}" = "" ]; then
  NSTEP="JOBSTART"
else
  NSTEP="${RSTEP}"
fi

# アプリ通知関連
JOB_NAME_APP_NOTICE="${USERNAME}"_"$(basename "$0")"
APP_NOTICE_DIR="${REPO_ROOT}/platforms/appnotice"
REMOTE_APP_NOTICE_DIR="Linux/platforms/appnotice"
function appNotice ()
{
if [ "${USERNAME}" = "${APPNOTICE_USERNAME}" ]; then
  # アプリ通知 引数：$1（通知内容）、$2（エラー内容）
  cd "${APP_NOTICE_DIR}" && sudo python3 ./appNotice.py "${JOB_NAME_APP_NOTICE}" "$1" "$2"
else
  # アプリ通知 引数：$1（通知内容）、$2（エラー内容）
  ssh -i "${KEY}" "${APPNOTICE_USERNAME}"@"${APPNOTICE_IP}" "cd \"${REMOTE_APP_NOTICE_DIR}\" && echo \"${PASSWORD}\" | sudo -S python3 ./appNotice.py \"${JOB_NAME_APP_NOTICE}\" \"$1\" \"$2\""
fi
}

# ログ関連
LOG_DIR=/var/log/"$(echo "${JOB_NAME}" | sed -e 's/_.*//g')"
LOG_FILE="$(basename "$0" | sed -e 's/.sh//g').log"
if [ ! -e "${LOG_DIR}" ]; then
  sudo mkdir -m 777 "${LOG_DIR}"
fi
function log ()
{
  LOG="${LOG_DIR}"/"${LOG_FILE}"
  time=[$(date '+%Y/%m/%d %T')]
  # 正常終了時のログ出力 引数：$1
  sudo echo -e "${time}" "$1" | sudo tee -a ${LOG}
  if [[ "${2:-}" != "" ]]; then
    # 異常終了時のログ出力 引数：$2
    sudo echo -e "${2:-}" | sudo tee -a ${LOG}
  fi
}

function assert_no_pvc_maintenance ()
{
  KUBECTL_ERR="$(mktemp)"
  if ! RESULT=$(kubectl -n "${MINECRAFT_NAMESPACE}" get pods \
              --field-selector "metadata.name=${PVC_MAINTENANCE_POD}" \
              -o name 2>"${KUBECTL_ERR}"); then
    echo "PVC emergency maintenance Pod の状態を確認できないため Minecraft を起動しません。" >&2
    cat "${KUBECTL_ERR}" >&2
    rm -f "${KUBECTL_ERR}"
    exit 10
  fi
  rm -f "${KUBECTL_ERR}"
  if [ -n "${RESULT}" ]; then
    echo "${ERR_MESSAGE_04}" >&2
    echo "検出したPod: ${RESULT}" >&2
    echo "通常起動する前に Minecraft Maintenance workflow の pvc-emergency-finish を完了してください。" >&2
    exit 10
  fi
}

function assert_no_unknown_pvc_users ()
{
  KUBECTL_ERR="$(mktemp)"
  if ! POD_ROWS=$(kubectl -n "${MINECRAFT_NAMESPACE}" get pods \
                  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .metadata.ownerReferences[*]}{.kind}{"/"}{.name}{","}{end}{"|"}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{","}{end}{"\n"}{end}' \
                  2>"${KUBECTL_ERR}"); then
    echo "PVC 利用Podの状態を確認できないため Minecraft を起動しません。" >&2
    cat "${KUBECTL_ERR}" >&2
    rm -f "${KUBECTL_ERR}"
    exit 10
  fi
  rm -f "${KUBECTL_ERR}"

  while IFS='|' read -r POD_NAME POD_PHASE OWNER_REFS PVC_LIST; do
    [ -n "${POD_NAME}" ] || continue
    case "${POD_NAME}" in
      minecraft-proxy-*|minecraft-server1-*|minecraft-server2-*)
        continue
        ;;
    esac
    for PVC_NAME in ${TARGET_PVCS}; do
      case ",${PVC_LIST}," in
        *",${PVC_NAME},"*)
          echo "不明なPodがMinecraft PVCを使用中のため Minecraft を起動しません。" >&2
          echo "Pod=${POD_NAME} phase=${POD_PHASE} pvc=${PVC_NAME} owner=${OWNER_REFS}" >&2
          exit 10
          ;;
      esac
    done
  done <<EOF
${POD_ROWS}
EOF
}

#*****************************************************************************************************************************************************
# JOBSTART_前準備
#*****************************************************************************************************************************************************
assert_no_pvc_maintenance
assert_no_unknown_pvc_users
appNotice START ""
log "${JOB_NAME}"_START
while true;do
  case "${NSTEP}" in
    "JOBSTART")
      NSTEP="STEP010"
    ;;

#*****************************************************************************************************************************************************
# STEP010
#*****************************************************************************************************************************************************
    "STEP010")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                kubectl apply -f "${MINECRAFT_K8S_DIR}/minecraft-proxy.yml" && \
                kubectl apply -f "${MINECRAFT_K8S_DIR}/minecraft-deployment.yml"
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP020"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_01}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_01}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP020
#*****************************************************************************************************************************************************
    "STEP020")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                kubectl wait pod -n minecraft \
                  -l "app in (minecraft-proxy,minecraft-server1,minecraft-server2)" \
                  --for=condition=Ready \
                  --timeout="${TIMEOUT_DURATION}s" 2>&1
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP030"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_02}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_02}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP030
#*****************************************************************************************************************************************************
    "STEP030")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                ssh -i "${KEY}" "${APPNOTICE_USERNAME}"@"${APPNOTICE_IP}" \
                "export ARGOCD_SERVER_ADDRESS=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && \
                yes | argocd login \"\${ARGOCD_SERVER_ADDRESS}\" --username admin --password \"${PASSWORD}\" --insecure && \
                argocd app sync minecraft && \
                argocd app set minecraft --sync-policy automated"
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="JOBEND"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# JOBEND_ループを抜ける
#*****************************************************************************************************************************************************
    "JOBEND")
      break
    ;;
  esac
done

#*****************************************************************************************************************************************************
# 後片付け
#*****************************************************************************************************************************************************
# アベンドフラグが立っているか確認
if [ ${ABEND_FLG} -eq 1 ]; then
  # リターンコードのセット
  JOB_RTN_CD=10
fi

# 呼出し元へリターンコードを返却
appNotice END ""
log "${JOB_NAME}"_END
exit ${JOB_RTN_CD}
