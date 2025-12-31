#!/bin/bash
######################################################################################################################################################
# ファイル   : minecraft_restore_server.sh
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
ERR_MESSAGE_02="バックアップアーカイブが見つかりません。"
ERR_MESSAGE_03="アーカイブ展開に失敗しました。"
ERR_MESSAGE_04="リストアに失敗しました。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# 環境変数設定
## ワークフォルダ
WORK_DIR="${HOME}/Linux/platforms/kubernetes/apps/minecraft"
## リストア対象フォルダ
RESTORE_FOLDER1="/mnt/share/kubernetes/minecraft/server1"
RESTORE_FOLDER2="/mnt/share/kubernetes/minecraft/server2"
## リストア設定
USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.username'`
PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
MNT_POINT="/mnt/truenas_minecraft_bk"
SMB_HOST=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.host'`
SMB_USERNAME=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.username'`
SMB_PASSWORD=`cat ~/Linux/platforms/settings/settings.yml | yq eval '.smb.password'`
SMB_SHARE="//${SMB_HOST}/Minecraft"
STAGE_DIR="${WORK_DIR}/restore_stage"
ARCHIVE_NAME="minecraft-backup.tgz"
ARCHIVE_FULL_PATH="${MNT_POINT}/${ARCHIVE_NAME}"
WORK_FULL_PATH1="${STAGE_DIR}"

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
      mkdir -p "${WORK_DIR}" && rm -rf "${STAGE_DIR}" && mkdir -p "${STAGE_DIR}" && mkdir -p "${RESTORE_FOLDER1}" "${RESTORE_FOLDER2}"
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
# STEP20
#*****************************************************************************************************************************************************
    "STEP020")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      sudo mkdir -p "${MNT_POINT}" && \
      if ! mountpoint -q "${MNT_POINT}"; then
        sudo mount -t cifs "${SMB_SHARE}" "${MNT_POINT}" \
          -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},file_mode=0666,dir_mode=0777,vers=3.0,iocharset=utf8"
      fi
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 && -s "${ARCHIVE_FULL_PATH}" ]]; then
        NSTEP="STEP030"
      else
        echo "${ERR_MESSAGE_02}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP30
#*****************************************************************************************************************************************************
    "STEP030")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------
      tar -xzf "${ARCHIVE_FULL_PATH}" -C "${STAGE_DIR}"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="STEP040"
      else
        echo "${ERR_MESSAGE_03}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP40
#*****************************************************************************************************************************************************
    "STEP040")
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------

      # 1) ワールド/リソース/スポーン配下の「中身全削除（paper-world.yml と *.lock は残す）」
      shopt -s nullglob
      for SERVER in 1 2; do
        BASE_VAR="RESTORE_FOLDER${SERVER}"
        BASE="${!BASE_VAR}"
        for D in \
          "${BASE}"/[0-9]*.[0-9]*.[0-9]* \
          "${BASE}"/[0-9]*.[0-9]*.[0-9]*_nether \
          "${BASE}"/[0-9]*.[0-9]*.[0-9]*_the_end \
          "${BASE}/resource" \
          "${BASE}/resource_nether" \
          "${BASE}/resource_the_end" \
          "${BASE}/spawn"
        do
          [[ -d "$D" ]] || continue
          find "$D" -mindepth 1 \
            \( -name 'paper-world.yml' -o -name '*.lock' \) -prune -o -exec rm -rf {} +
        done
      done

      # 2) plugins配下：フォルダ指定は配下全削除→差し替え、ファイル指定は削除→差し替え
      DIRS_REL=(
        "plugins/Chunky/tasks"
        "plugins/Multiverse-Inventories/groups"
        "plugins/Multiverse-Inventories/players"
        "plugins/Multiverse-Inventories/worlds"
        "plugins/WorldEdit/.archive-unpack/5f7cd289"
        "plugins/WorldEdit/.archive-unpack/56b76b46"
        "plugins/WorldEdit/sessions"
        "plugins/WorldGuard/cache"
        "plugins/WorldGuard/worlds"
      )
      FILES_REL=(
        "plugins/Multiverse-Core/worlds.yml"
        "plugins/Multiverse-Inventories/groups.yml"
        "plugins/Multiverse-NetherPortals/config.yml"
        "plugins/Multiverse-Portals/portals.yml"
        "ops.json"
        "whitelist.json"
      )

      # rsync オプションを用途別に分離
      RSYNC_PLUGINS_OPTS=(-a --delete --prune-empty-dirs)  # ← plugins 用（除外なし）
      RSYNC_WORLD_OPTS=(-a --delete --prune-empty-dirs --exclude='**/*.lock' --exclude='**/paper-world.yml')  # ← ワールド/リソース/spawn 用

      for SERVER in 1 2; do
        SRC="${STAGE_DIR}/server${SERVER}"
        DST_VAR="RESTORE_FOLDER${SERVER}"
        DST="${!DST_VAR}"

        # ディレクトリ削除→差し替え（plugins）
        for REL in "${DIRS_REL[@]}"; do
          [[ -d "${SRC}/${REL}" || -f "${SRC}/${REL}" ]] || continue
          mkdir -p "${DST}/${REL}"
          find "${DST}/${REL}" -mindepth 1 -exec rm -rf {} +
          if [[ -d "${SRC}/${REL}" ]]; then
            rsync "${RSYNC_PLUGINS_OPTS[@]}" "${SRC}/${REL}/" "${DST}/${REL}/" \
              || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 2; }
          else
            rsync "${RSYNC_PLUGINS_OPTS[@]}" "${SRC}/${REL}" "${DST}/${REL}" \
              || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 2; }
          fi
        done

        # ファイル削除→差し替え（plugins）
        for REL in "${FILES_REL[@]}"; do
          rm -f "${DST}/${REL}"
          if [[ -f "${SRC}/${REL}" ]]; then
            mkdir -p "$(dirname "${DST}/${REL}")"
            rsync "${RSYNC_PLUGINS_OPTS[@]}" "${SRC}/${REL}" "${DST}/${REL}" \
              || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 2; }
          fi
        done
      done

      # 3) ワールド/リソース/スポーンの保険同期（ここは .lock / paper-world.yml を除外）
      for SERVER in 1 2; do
        SRC="${STAGE_DIR}/server${SERVER}"
        DST_VAR="RESTORE_FOLDER${SERVER}"
        DST="${!DST_VAR}"

        for NAME in \
          $(basename -a "${SRC}"/[0-9]*.[0-9]*.[0-9]* 2>/dev/null) \
          $(basename -a "${SRC}"/[0-9]*.[0-9]*.[0-9]*_nether 2>/dev/null) \
          $(basename -a "${SRC}"/[0-9]*.[0-9]*.[0-9]*_the_end 2>/dev/null) \
          resource resource_nether resource_the_end spawn
        do
          [[ -d "${SRC}/${NAME}" ]] || continue
          mkdir -p "${DST}/${NAME}"
          rsync "${RSYNC_WORLD_OPTS[@]}" "${SRC}/${NAME}/" "${DST}/${NAME}/" \
            || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 3; }
        done
      done

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

# 呼出し元へリターンコードを返却
exit ${JOB_RTN_CD}
