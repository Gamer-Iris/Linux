#!/bin/bash
######################################################################################################################################################
# ファイル   : kubernetes_cron.sh
# 引数       : RSTEP（リスタートするジョブステップを指定）
# 復帰値     : 0 （正常終了）
#            : 10（異常終了）
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################

#*****************************************************************************************************************************************************
# 定数エリア
#*****************************************************************************************************************************************************
# フラグ
JOB_RTN_CD=0
ABEND_FLG=0
RTN_CD=0
COMMIT_FLG=0
MASKING_FLG=0

# GitHub設定
BRANCH_NAME="branch"
COMMIT_COMMENT_01="[update] HelmチャートのtargetRevisionを更新"
COMMIT_COMMENT_02="HelmチャートのtargetRevisionを最新のアプリケーションバージョンに合わせて更新。"

# マスキング設定
MASKING_COMMENT="ご自分の環境に合わせてください。"

# エラーメッセージ設定
ERR_MESSAGE_01="Helmリポジトリの操作に失敗しました。"
ERR_MESSAGE_02="Gitの操作に失敗しました。"
ERR_MESSAGE_03="Argo CDの操作に失敗しました。"
ERR_MESSAGE_04="稼働バージョンの取得に失敗しました。"
ERR_MESSAGE_05="最新バージョンの取得に失敗しました。"
ERR_MESSAGE_06="最新バージョンの適用に失敗しました。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# ジョブネーム設定
JOB_NAME=$(basename $0 | sed -e 's/.sh//g')

# 環境変数設定
USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.username'`
PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
KEY=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.key'`
APPNOTICE_HOST=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.appnotice.host'`
APPNOTICE_USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.appnotice.username'`
DISCORD_URL=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.discord.url'`

# 変数初期化
RESULT=""
HELM_RELEASE=""
NAME=""
NAMESPACE=""
CHART_FULL=""
CHART_NAME=""
FULL_CHART_PATH=""
WORKING_VERSION=""
LATEST_VERSION=""
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
  ssh -i "${KEY}" "${APPNOTICE_USERNAME}"@"${APPNOTICE_HOST}" "cd "${APP_NOTICE_DIR}" && echo "${PASSWORD}" | sudo -S python3 ./appNotice.py "${JOB_NAME_APP_NOTICE}" "$1" "$2""
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
# STEP010
#*****************************************************************************************************************************************************
    "STEP010")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                helm repo update && \
                helm list -A -o json | jq -c '.[]' | while read -r HELM_RELEASE; do
                  NAME=$(echo "${HELM_RELEASE}" | jq -r '.name')
                  NAMESPACE=$(echo "${HELM_RELEASE}" | jq -r '.namespace')
                  CHART_FULL=$(echo "${HELM_RELEASE}" | jq -r '.chart')
                  CHART_NAME=$(echo "${CHART_FULL}" | awk -F- 'NF{NF-=1};1' OFS=-)
                  FULL_CHART_PATH=$(helm search repo --versions | grep "/${CHART_NAME}" | awk 'NR==1 {print $1}')
                  WORKING_VERSION=$(echo "${CHART_FULL}" | awk -F- '{print $NF}')
                  echo "${WORKING_VERSION}"
                  LATEST_VERSION=$(helm search repo "${FULL_CHART_PATH}" --versions | awk 'NR==2 {print $2}')
                  echo "${LATEST_VERSION}"
                  if [[ "${WORKING_VERSION}" != "${LATEST_VERSION}" ]]; then
                    helm upgrade "${NAME}" "${FULL_CHART_PATH}" -n "${NAMESPACE}"
                  fi
                done
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
                eval `ssh-agent` && \
                ssh-add ~/.ssh/id_git_rsa && \
                cd ~/Linux && \
                git show-ref --verify --quiet refs/heads/"${BRANCH_NAME}" || git checkout -b "${BRANCH_NAME}" main
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
# STEP040
#*****************************************************************************************************************************************************
    "STEP040")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(kubectl get applications sealed-secrets -n argocd -o=jsonpath='{.spec.source.targetRevision}')
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        WORKING_VERSION=$RESULT
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP050"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP050
#*****************************************************************************************************************************************************
    "STEP050")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(helm search repo sealed-secrets/sealed-secrets -o yaml | yq eval '.[] | select(.name == "sealed-secrets/sealed-secrets") | .version' -)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        LATEST_VERSION=$RESULT
        log "${JOB_NAME}"_"${NSTEP}"_END
        if [[ "${WORKING_VERSION}" == "${LATEST_VERSION}" ]]; then
          NSTEP="STEP070"
        else
          NSTEP="STEP060"
        fi
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP060
#*****************************************************************************************************************************************************
    "STEP060")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                sed -i "s/^\(\s*targetRevision:\s*\)${WORKING_VERSION}/\1${LATEST_VERSION}/" ~/Linux/platforms/kubernetes/argo-cd-apps-deployment2.yml && \
                kubectl apply -f ~/Linux/platforms/kubernetes/argo-cd-apps-deployment2.yml && \
                argocd app sync sealed-secrets && \
                cd ~/Linux && \
                git add ~/Linux/platforms/kubernetes/argo-cd-apps-deployment2.yml
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        COMMIT_FLG=1
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP070"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_06}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_06}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP070
#*****************************************************************************************************************************************************
    "STEP070")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(kubectl get applications monitoring -n argocd -o=jsonpath='{.spec.source.targetRevision}')
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        WORKING_VERSION=$RESULT
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP080"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_04}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP080
#*****************************************************************************************************************************************************
    "STEP080")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(helm search repo prometheus-community/kube-prometheus-stack -o yaml | yq eval '.[] | select(.name == "prometheus-community/kube-prometheus-stack") | .version' -)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        LATEST_VERSION=$RESULT
        log "${JOB_NAME}"_"${NSTEP}"_END
        if [[ "${WORKING_VERSION}" == "${LATEST_VERSION}" ]]; then
          NSTEP="STEP100"
        else
          NSTEP="STEP090"
        fi
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP090
#*****************************************************************************************************************************************************
    "STEP090")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                sed -i "s/^\(\s*targetRevision:\s*\)${WORKING_VERSION}/\1${LATEST_VERSION}/" ~/Linux/platforms/kubernetes/argo-cd-apps-deployment4.yml && \
                kubectl apply -f ~/Linux/platforms/kubernetes/argo-cd-apps-deployment4.yml && \
                sleep 600 && \
                {
                  for app in cloudflare coredns mariadb-phpmyadmin metallb minecraft monitoring navidrome wordpress; do
                    argocd app sync "${app}"
                  done
                } && \
                for service in monitoring-kube-prometheus-kube-etcd monitoring-kube-prometheus-kube-controller-manager monitoring-kube-prometheus-kube-proxy monitoring-kube-prometheus-kube-scheduler; do
                  kubectl -n monitoring delete serviceMonitor "${service}"
                done && \
                for rule in monitoring-kube-prometheus-etcd monitoring-kube-prometheus-kubernetes-system-controller-manager monitoring-kube-prometheus-kubernetes-system-kube-proxy monitoring-kube-prometheus-kubernetes-system-scheduler; do
                  kubectl -n monitoring delete prometheusrules "${rule}"
                done && \
                sed -i "s|${DISCORD_URL}|${MASKING_COMMENT}|g" ~/Linux/platforms/kubernetes/argo-cd-apps-deployment4.yml && \
                cd ~/Linux && \
                git add ~/Linux/platforms/kubernetes/argo-cd-apps-deployment4.yml
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        COMMIT_FLG=1
        MASKING_FLG=1
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP100"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_06}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_06}"
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP100
#*****************************************************************************************************************************************************
    "STEP100")
      log "${JOB_NAME}"_"${NSTEP}"_START

      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      RESULT=$(
                if [[ ${COMMIT_FLG} -eq 1 ]]; then
                  eval `ssh-agent` && \
                  ssh-add ~/.ssh/id_git_rsa && \
                  cd ~/Linux && \
                  git commit -m "${COMMIT_COMMENT_01}" -m "${COMMIT_COMMENT_02}" && \
                  git push origin "${BRANCH_NAME}" && \
                  if [[ ${MASKING_FLG} -eq 1 ]]; then
                    sed -i "s|${MASKING_COMMENT}|${DISCORD_URL}|g" ~/Linux/platforms/kubernetes/argo-cd-apps-deployment4.yml
                  fi
                fi
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
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_02}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_02}"
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
