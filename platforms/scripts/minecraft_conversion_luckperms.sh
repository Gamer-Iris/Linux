#!/bin/bash
######################################################################################################################################################
# ファイル   : minecraft_conversion_luckperms.sh
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
ERR_MESSAGE_01="コピーに失敗しました。"
ERR_MESSAGE_02="パッチに失敗しました。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# 環境変数設定
## DB関連
DATABASES_OSS=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.databases.oss'`
DATABASES_OSS_LOWERCASE="${DATABASES_OSS,,}"
DATABASES_ADDRESS=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.databases.address'`
DATABASES_DATABASE3_DATABASENAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.databases.database3.databasename'`
DATABASES_DATABASE3_USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.databases.database3.username'`
DATABASES_DATABASE3_PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.databases.database3.password'`
## ワークフォルダ
WORK_DIR="${HOME}"/Linux/platforms/kubernetes/apps/minecraft
## 変換対象フォルダ
CONVERSION_FOLDER1=/mnt/share/kubernetes/minecraft/proxy
CONVERSION_FOLDER2=/mnt/share/kubernetes/minecraft/server1
CONVERSION_FOLDER3=/mnt/share/kubernetes/minecraft/server2
## LuckPermsConfig
CONVERSION_FILE_NAME1=config.yml
CONVERSION_FULL_PATH1_1="${CONVERSION_FOLDER1}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}"
CONVERSION_FULL_PATH1_2="${CONVERSION_FOLDER2}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}"
CONVERSION_FULL_PATH1_3="${CONVERSION_FOLDER3}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}"
BACKUP_FULL_PATH1_1="${CONVERSION_FOLDER1}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}_bk"
BACKUP_FULL_PATH1_2="${CONVERSION_FOLDER2}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}_bk"
BACKUP_FULL_PATH1_3="${CONVERSION_FOLDER3}"/plugins/LuckPerms/"${CONVERSION_FILE_NAME1}_bk"
WORK_FULL_PATH1_1="${WORK_DIR}"/"${CONVERSION_FILE_NAME1}_1_1"
WORK_FULL_PATH1_2="${WORK_DIR}"/"${CONVERSION_FILE_NAME1}_1_2"
WORK_FULL_PATH1_3="${WORK_DIR}"/"${CONVERSION_FILE_NAME1}_1_3"

# STEPセット
NSTEP=""
RSTEP=$1
if [ "${RSTEP}" = "" ]; then
  NSTEP="JOBSTART"
else
  NSTEP="${RSTEP}"
fi

#*****************************************************************************************************************************************************
# JOBSTART_前準備
#*****************************************************************************************************************************************************
while true;do
  case "${NSTEP}" in
    "JOBSTART")
      NSTEP="STEP010"
    ;;

#*****************************************************************************************************************************************************
# STEP010
#*****************************************************************************************************************************************************
    "STEP010")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      cp -p "${CONVERSION_FULL_PATH1_1}" "${BACKUP_FULL_PATH1_1}" && cp -p "${CONVERSION_FULL_PATH1_1}" "${WORK_FULL_PATH1_1}" && \
      cp -p "${CONVERSION_FULL_PATH1_2}" "${BACKUP_FULL_PATH1_2}" && cp -p "${CONVERSION_FULL_PATH1_2}" "${WORK_FULL_PATH1_2}" && \
      cp -p "${CONVERSION_FULL_PATH1_3}" "${BACKUP_FULL_PATH1_3}" && cp -p "${CONVERSION_FULL_PATH1_3}" "${WORK_FULL_PATH1_3}"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="STEP020"
      else
        echo "${ERR_MESSAGE_01}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP020
#*****************************************************************************************************************************************************
    "STEP020")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      yq eval -i '.use-server-uuid-cache = true' "${WORK_FULL_PATH1_1}" && \
      yq eval -i ".storage-method = \"${DATABASES_OSS}\"" "${WORK_FULL_PATH1_1}" && \
      yq eval -i ".data.address = \"${DATABASES_ADDRESS}\"" "${WORK_FULL_PATH1_1}" && \
      yq eval -i ".data.database = \"${DATABASES_DATABASE3_DATABASENAME}\"" "${WORK_FULL_PATH1_1}" && \
      yq eval -i ".data.username = \"${DATABASES_DATABASE3_USERNAME}\"" "${WORK_FULL_PATH1_1}" && \
      yq eval -i ".data.password = \"${DATABASES_DATABASE3_PASSWORD}\"" "${WORK_FULL_PATH1_1}" && \
      yq eval -i '.server = "server1"' "${WORK_FULL_PATH1_2}" && \
      yq eval -i '.use-server-uuid-cache = true' "${WORK_FULL_PATH1_2}" && \
      yq eval -i ".storage-method = \"${DATABASES_OSS}\"" "${WORK_FULL_PATH1_2}" && \
      yq eval -i ".data.address = \"${DATABASES_ADDRESS}\"" "${WORK_FULL_PATH1_2}" && \
      yq eval -i ".data.database = \"${DATABASES_DATABASE3_DATABASENAME}\"" "${WORK_FULL_PATH1_2}" && \
      yq eval -i ".data.username = \"${DATABASES_DATABASE3_USERNAME}\"" "${WORK_FULL_PATH1_2}" && \
      yq eval -i ".data.password = \"${DATABASES_DATABASE3_PASSWORD}\"" "${WORK_FULL_PATH1_2}" && \
      yq eval -i '.server = "server2"' "${WORK_FULL_PATH1_3}" && \
      yq eval -i '.use-server-uuid-cache = true' "${WORK_FULL_PATH1_3}" && \
      yq eval -i ".storage-method = \"${DATABASES_OSS}\"" "${WORK_FULL_PATH1_3}" && \
      yq eval -i ".data.address = \"${DATABASES_ADDRESS}\"" "${WORK_FULL_PATH1_3}" && \
      yq eval -i ".data.database = \"${DATABASES_DATABASE3_DATABASENAME}\"" "${WORK_FULL_PATH1_3}" && \
      yq eval -i ".data.username = \"${DATABASES_DATABASE3_USERNAME}\"" "${WORK_FULL_PATH1_3}" && \
      yq eval -i ".data.password = \"${DATABASES_DATABASE3_PASSWORD}\"" "${WORK_FULL_PATH1_3}"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="STEP030"
      else
        echo "${ERR_MESSAGE_02}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP030
#*****************************************************************************************************************************************************
    "STEP030")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      cp -p "${WORK_FULL_PATH1_1}" "${CONVERSION_FULL_PATH1_1}" && \
      cp -p "${WORK_FULL_PATH1_2}" "${CONVERSION_FULL_PATH1_2}" && \
      cp -p "${WORK_FULL_PATH1_3}" "${CONVERSION_FULL_PATH1_3}"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="JOBEND"
      else
        echo "${ERR_MESSAGE_01}"
        ABEND_FLG=1
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

# WORK内容の削除
rm -r "${WORK_FULL_PATH1_1}"
rm -r "${WORK_FULL_PATH1_2}"
rm -r "${WORK_FULL_PATH1_3}"

# 呼出し元へリターンコードを返却
exit ${JOB_RTN_CD}
