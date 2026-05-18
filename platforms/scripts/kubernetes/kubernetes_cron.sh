#!/bin/bash

######################################################################################################################################################
# ファイル   : kubernetes_cron.sh
# 引数       : RSTEP（リスタートするジョブステップを指定）
# 復帰値     : 0 （正常終了）
#            : 10（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
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
ERR_MESSAGE_01="Helmリポジトリの操作に失敗しました。"
ERR_MESSAGE_03="Argo CDの操作に失敗しました。"
ERR_MESSAGE_04="kubectl の操作に失敗しました。"
ERR_MESSAGE_05="NotReady な Node が検出されました。"
ERR_MESSAGE_06="ディスク使用率が閾値（${DISK_THRESHOLD_PCT}%）を超えています。"
ERR_MESSAGE_07="kubelet サービスが正常に動作していません。"

# ディスク使用率警告閾値（%）
DISK_THRESHOLD_PCT=80

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# ジョブネーム設定
JOB_NAME=$(basename $0 | sed -e 's/.sh//g')

# 環境変数設定
USERNAME=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.username'`
PASSWORD=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
KEY=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.key'`
APPNOTICE_IP=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.appnotice.ip'`
APPNOTICE_USERNAME=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.appnotice.username'`

# 変数初期化
RESULT=""
ARGOCD_SERVER_ADDRESS=""

# STEPセット
NSTEP=""
RSTEP=$1
if [ "${RSTEP}" = "" ]; then
  NSTEP="JOBSTART"
else
  NSTEP="${RSTEP}"
fi

# アプリ通知関連
JOB_NAME_APP_NOTICE="${USERNAME}"_"$(basename $0)"
APP_NOTICE_DIR=/home/"${APPNOTICE_USERNAME}"/Linux/platforms/appnotice
function appNotice ()
{
if [ "${USERNAME}" = "${APPNOTICE_USERNAME}" ]; then
  # アプリ通知 引数：$1（通知内容）、$2（エラー内容）
  cd "${APP_NOTICE_DIR}" && sudo python3 ./appNotice.py "${JOB_NAME_APP_NOTICE}" "$1" "$2"
else
  # アプリ通知 引数：$1（通知内容）、$2（エラー内容）
  ssh -i "${KEY}" "${APPNOTICE_USERNAME}"@"${APPNOTICE_IP}" "cd "${APP_NOTICE_DIR}" && echo "${PASSWORD}" | sudo -S python3 ./appNotice.py "${JOB_NAME_APP_NOTICE}" "$1" "$2""
fi
}

# ログ関連
LOG_DIR=/var/log/"$(echo "${JOB_NAME}" | sed -e 's/_.*//g')"
LOG_FILE="$(basename $0 | sed -e 's/.sh//g').log"
if [ ! -e "${LOG_DIR}" ]; then
  sudo mkdir -m 777 "${LOG_DIR}"
fi
function log ()
{
  LOG="${LOG_DIR}"/"${LOG_FILE}"
  time=[$(date '+%Y/%m/%d %T')]
  # 正常終了時のログ出力 引数：$1
  sudo echo -e "${time}" "$1" | sudo tee -a ${LOG}
  if [[ $2 != "" ]]; then
    # 異常終了時のログ出力 引数：$2
    sudo echo -e "$2" | sudo tee -a ${LOG}
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
# STEP010 — Helm リポジトリキャッシュ更新
#   helm repo update のみ実行する（upgrade は行わない）。
#   bootstrap chart（ArgoCD / MetalLB）の upgrade は operator review 後に
#   setup.sh control-plane を再実行する。
#   Day-1 chart（sealed-secrets / monitoring 等）は ArgoCD targetRevision: "*" で latest-following。
#*****************************************************************************************************************************************************
    "STEP010")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(helm repo update)
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
# STEP020 — ArgoCD 接続確認
#*****************************************************************************************************************************************************
    "STEP020")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                ARGOCD_SERVER_ADDRESS=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && \
                yes | argocd login ${ARGOCD_SERVER_ADDRESS} --username admin --password "${PASSWORD}"
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
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP030 — Node ステータス確認（NotReady があれば異常終了）
#*****************************************************************************************************************************************************
    "STEP030")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(kubectl get nodes --no-headers)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -ne 0 ]]; then
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        NSTEP="JOBEND"
        break
      fi
      NOT_READY=$(echo "${RESULT}" | grep -v " Ready " || true)
      if [ -n "${NOT_READY}" ]; then
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        log "${NOT_READY}"
        NSTEP="JOBEND"
        break
      fi
      log "${JOB_NAME}"_"${NSTEP}"_END
      NSTEP="STEP040"
    ;;

#*****************************************************************************************************************************************************
# STEP040 — ArgoCD Application 同期状態確認（OutOfSync / Degraded があればログ記録）
#   ※ 同期ズレは fail-fast ではなくログ記録に留める（ArgoCD が自己修復中の場合を考慮）
#*****************************************************************************************************************************************************
    "STEP040")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(argocd app list --output wide 2>&1)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        UNSYNCED=$(echo "${RESULT}" | grep -E "OutOfSync|Degraded|Unknown" || true)
        if [ -n "${UNSYNCED}" ]; then
          appNotice "${NSTEP}"_WARN "ArgoCD に同期ズレまたは Degraded なアプリケーションがあります。"
          log "${JOB_NAME}"_"${NSTEP}"_WARN "${UNSYNCED}"
        fi
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP050"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_03}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP050 — ディスク使用率確認（${DISK_THRESHOLD_PCT}% 超過で警告通知）
#   ※ fail-fast ではなく警告通知に留める（disk full は運用介入で対応）
#*****************************************************************************************************************************************************
    "STEP050")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(df -h --output=pcent,target 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$1); if($1+0 > '"${DISK_THRESHOLD_PCT}"') print $0}')
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      if [ -n "${RESULT}" ]; then
        appNotice "${NSTEP}"_WARN "${ERR_MESSAGE_06}"
        log "${JOB_NAME}"_"${NSTEP}"_WARN "${ERR_MESSAGE_06}"
        log "${RESULT}"
      fi
      log "${JOB_NAME}"_"${NSTEP}"_END
      NSTEP="STEP060"
    ;;

#*****************************************************************************************************************************************************
# STEP060 — kubelet サービス health 確認
#*****************************************************************************************************************************************************
    "STEP060")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(systemctl is-active kubelet 2>&1)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      if [ "${RESULT}" != "active" ]; then
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_07}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_07}"
        log "kubelet status: ${RESULT}"
        NSTEP="JOBEND"
        break
      fi
      log "${JOB_NAME}"_"${NSTEP}"_END
      NSTEP="JOBEND"
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
