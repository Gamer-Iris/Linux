#!/bin/bash
######################################################################################################################################################
# ファイル   : minecraft_backup_server.sh
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
JOB_RTN_CD=0
ABEND_FLG=0
RTN_CD=0

# エラーメッセージ設定
ERR_MESSAGE_01="ワークディレクトリ作成に失敗しました。"
ERR_MESSAGE_02="バックアップ抽出に失敗しました。"
ERR_MESSAGE_03="アーカイブ作成に失敗しました。"
ERR_MESSAGE_04="退避先への転送に失敗しました。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# 環境変数設定
## ワークフォルダ
WORK_DIR="${HOME}/Linux/platforms/kubernetes/apps/minecraft"
## バックアップ対象フォルダ
BACKUP_FOLDER1="/mnt/share/kubernetes/minecraft/server1"
BACKUP_FOLDER2="/mnt/share/kubernetes/minecraft/server2"
## バックアップ設定
USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.username'`
PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
MNT_POINT="/mnt/truenas_minecraft_bk"
SMB_HOST=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.host'`
SMB_USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.username'`
SMB_PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.password'`
SMB_SHARE="//${SMB_HOST}/Minecraft"
STAGE_DIR="${WORK_DIR}/backup_stage"
ARCHIVE_NAME="minecraft-backup.tgz"
WORK_FULL_PATH1="${WORK_DIR}/backup_stage"
WORK_FULL_PATH2="${WORK_DIR}/.minecraft_backup_includes.rsync"
WORK_FULL_PATH3="${WORK_DIR}/.rsync_tmp"
WORK_FULL_PATH4="${STAGE_DIR}"
WORK_FULL_PATH5="${WORK_DIR}/${ARCHIVE_NAME}"

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
      mkdir -p "${WORK_DIR}" && rm -rf "${STAGE_DIR}" && mkdir -p "${STAGE_DIR}"
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
      { cat > "${WORK_FULL_PATH2}" <<-'__RSYNC_INC__'
+ */
+ *.*.*/
+ *.*.*_nether/
+ *.*.*_the_end/
+ *.*.*/**
+ *.*.*_nether/**
+ *.*.*_the_end/**
+ plugins/
+ plugins/Chunky/tasks/**
+ plugins/Multiverse-Core/worlds.yml
+ plugins/Multiverse-Inventories/groups/**
+ plugins/Multiverse-Inventories/players/**
+ plugins/Multiverse-Inventories/worlds/**
+ plugins/Multiverse-Inventories/groups.yml
+ plugins/Multiverse-NetherPortals/config.yml
+ plugins/Multiverse-Portals/portals.yml
+ plugins/WorldEdit/.archive-unpack/
+ plugins/WorldEdit/.archive-unpack/5f7cd289/**
+ plugins/WorldEdit/.archive-unpack/56b76b46/**
- plugins/WorldEdit/.archive-unpack/**
+ plugins/WorldEdit/sessions/**
+ plugins/WorldGuard/cache/**
+ plugins/WorldGuard/worlds/**
+ resource/**
+ resource_nether/**
+ resource_the_end/**
+ spawn/**
+ ops.json
+ whitelist.json
- *
__RSYNC_INC__
} && \
      RSYNC_COMMON_OPTS=(
           -a
           --prune-empty-dirs
           --exclude='/libraries/**'
           --exclude='/versions/**'
           --exclude='**/*.lock'
           --exclude='**/paper-world.yml'
           --include-from="${WORK_FULL_PATH2}"
      ) && \
      rsync "${RSYNC_COMMON_OPTS[@]}" "${BACKUP_FOLDER1}/" "${STAGE_DIR}/server1/" && \
      rsync "${RSYNC_COMMON_OPTS[@]}" "${BACKUP_FOLDER2}/" "${STAGE_DIR}/server2/"
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
      cd "${STAGE_DIR}" && tar -czf "${WORK_FULL_PATH5}" .
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 && -s "${WORK_FULL_PATH5}" ]]; then
        NSTEP="STEP040"
      else
        echo "${ERR_MESSAGE_03}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP040
#*****************************************************************************************************************************************************
    "STEP040")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      sudo mkdir -p "${MNT_POINT}" && \
      if ! mountpoint -q "${MNT_POINT}"; then
        sudo mount -t cifs "${SMB_SHARE}" "${MNT_POINT}" \
          -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},file_mode=0666,dir_mode=0777,vers=3.0,iocharset=utf8"
      fi && \
      sudo cp -f "${WORK_FULL_PATH5}" "${MNT_POINT}/"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="JOBEND"
      else
        echo "${ERR_MESSAGE_04}"
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
if [ ${ABEND_FLG} -eq 1 ]; then
  JOB_RTN_CD=10
fi

# WORK内容の削除
rm -rf "${WORK_FULL_PATH1}"
rm -rf "${WORK_FULL_PATH2}"
rm -rf "${WORK_FULL_PATH3}"
rm -rf "${WORK_FULL_PATH4}"
rm -rf "${WORK_FULL_PATH5}"

# 呼出し元へリターンコードを返却
exit ${JOB_RTN_CD}
