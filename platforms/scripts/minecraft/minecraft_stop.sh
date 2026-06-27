#!/bin/bash

set -euo pipefail

######################################################################################################################################################
# ファイル   : minecraft_stop.sh
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
ERR_MESSAGE_01="Argo CDの操作に失敗しました。"
ERR_MESSAGE_02="マインクラフトサーバー停止に失敗しました。"
ERR_MESSAGE_03="マインクラフトサーバー Pod の終了確認がタイムアウトしました。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# ジョブネーム設定
JOB_NAME=$(basename "$0" | sed -e 's/.sh//g')

# 環境変数設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
SETTINGS_FILE="${SETTINGS_FILE:-${REPO_ROOT}/platforms/settings/settings_secret.yml}"
USERNAME=`cat "${SETTINGS_FILE}" | yq eval '.username'`
PASSWORD=`cat "${SETTINGS_FILE}" | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
KEY=`cat "${SETTINGS_FILE}" | yq eval '.key'`
APPNOTICE_IP=`cat "${SETTINGS_FILE}" | yq eval '.appnotice.ip'`
APPNOTICE_USERNAME=`cat "${SETTINGS_FILE}" | yq eval '.appnotice.username'`
TIMEOUT_DURATION=300

# 変数初期化
RESULT=""

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

#*****************************************************************************************************************************************************
# JOBSTART_前準備
#*****************************************************************************************************************************************************
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
                ssh -i "${KEY}" "${APPNOTICE_USERNAME}"@"${APPNOTICE_IP}" \
                "export ARGOCD_SERVER_ADDRESS=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && \
                yes | argocd login \"\${ARGOCD_SERVER_ADDRESS}\" --username admin --password \"${PASSWORD}\" --insecure && \
                argocd app set minecraft --sync-policy none"
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
                kubectl scale deployment -n minecraft minecraft-proxy --replicas=0 && \
                kubectl scale deployment -n minecraft minecraft-server1 --replicas=0 && \
                kubectl scale deployment -n minecraft minecraft-server2 --replicas=0
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
# STEP030 — Pod 終了確認（kubectl wait --for=delete）
#*****************************************************************************************************************************************************
    "STEP030")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                kubectl wait pod -n minecraft \
                  -l "app in (minecraft-proxy,minecraft-server1,minecraft-server2)" \
                  --for=delete \
                  --timeout="${TIMEOUT_DURATION}s" 2>&1
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP040"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP040 — stale lock ファイル削除
#*****************************************************************************************************************************************************
    "STEP040")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=0
      for SERVER in server1 server2; do
        PODS=$(kubectl get pods -n minecraft \
          -l "app=minecraft-${SERVER}" \
          --field-selector=status.phase=Running \
          -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
        if [ -n "${PODS}" ]; then
          for POD in ${PODS}; do
            log "stale lock 削除: ${POD}"
            kubectl exec -n minecraft "${POD}" \
              -c "minecraft-${SERVER}" -- \
              find /data -maxdepth 2 \( -name "*.lck" -o -name "*.lock" \) -delete \
              2>/dev/null || true
          done
        else
          log "minecraft-${SERVER}: Running Pod なし（stale lock 削除はスキップ）"
        fi
      done
      # proxy の lock は /server 配下
      PROXY_PODS=$(kubectl get pods -n minecraft \
        -l app=minecraft-proxy \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
      if [ -n "${PROXY_PODS}" ]; then
        for POD in ${PROXY_PODS}; do
          kubectl exec -n minecraft "${POD}" \
            -c minecraft-proxy -- \
            find /server -maxdepth 2 -name "*.lck" -delete \
            2>/dev/null || true
        done
      fi
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="JOBEND"
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
