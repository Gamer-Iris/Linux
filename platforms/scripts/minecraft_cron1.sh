#!/bin/bash
######################################################################################################################################################
# ファイル   : minecraft_cron1.sh
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

# エラーメッセージ設定
ERR_MESSAGE_01="呼び出し先処理にて異常を検知しました。"
ERR_MESSAGE_02="resourceワールドのディレクトリ削除に失敗しました。"
ERR_MESSAGE_03="resourceワールドの差し替えに失敗しました。"
ERR_MESSAGE_04="バックアップディレクトリの削除に失敗しました。"
ERR_MESSAGE_05="ログローテーションに失敗しました。"

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

# 変数初期化
RESULT=""

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
      RESULT=$(~/Linux/platforms/scripts/minecraft_stop.sh)
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
                rm -rf /mnt/share/kubernetes/minecraft/server1/resource && \
                rm -rf /mnt/share/kubernetes/minecraft/server1/resource_nether && \
                rm -rf /mnt/share/kubernetes/minecraft/server1/resource_the_end && \
                rm -rf /mnt/share/kubernetes/minecraft/server2/resource && \
                rm -rf /mnt/share/kubernetes/minecraft/server2/resource_nether && \
                rm -rf /mnt/share/kubernetes/minecraft/server2/resource_the_end
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
                tar -xzf /mnt/share/kubernetes/minecraft/server1/server1_resources_backup.tgz -C /mnt/share/kubernetes/minecraft/server1/ && \
                tar -xzf /mnt/share/kubernetes/minecraft/server2/server2_resources_backup.tgz -C /mnt/share/kubernetes/minecraft/server2/
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
      RESULT=$(
                rm -rf /mnt/share/kubernetes/minecraft/server1/server1_resources_backup && \
                rm -rf /mnt/share/kubernetes/minecraft/server2/server2_resources_backup
              )
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
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
      RESULT=$(~/Linux/platforms/scripts/minecraft_start.sh)
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [ -n "${RESULT}" ]; then
        log "${RESULT}"
      fi
      if [[ ${RTN_CD} -eq 0 ]]; then
        log "${JOB_NAME}"_"${NSTEP}"_END
        NSTEP="STEP060"
      else
        ABEND_FLG=1
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_01}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_01}"
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
                find /mnt/share/kubernetes/minecraft/server1/logs -name '????-??-??-*.log.gz' -exec sh -c 'file_date=$(echo "{}" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}"); today=$(date +%s); file_timestamp=$(date -d $file_date +%s); if [ $(($today - $file_timestamp)) -gt $((14 * 24 * 3600)) ]; then rm "{}"; fi' \; && \
                find /mnt/share/kubernetes/minecraft/server2/logs -name '????-??-??-*.log.gz' -exec sh -c 'file_date=$(echo "{}" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}"); today=$(date +%s); file_timestamp=$(date -d $file_date +%s); if [ $(($today - $file_timestamp)) -gt $((14 * 24 * 3600)) ]; then rm "{}"; fi' \;
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
        appNotice "${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
        log "${JOB_NAME}"_"${NSTEP}"_ABBEND "${ERR_MESSAGE_05}"
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
