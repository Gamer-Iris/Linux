#!/bin/bash

######################################################################################################################################################
# ファイル   : minecraft_restore_server.sh
# 引数       : [RSTEP] [--dry-run] [--yes] [--skip-snapshot]
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
JOB_RTN_CD=0
ABEND_FLG=0
RTN_CD=0

# エラーメッセージ設定
ERR_MESSAGE_01="ワークディレクトリ作成に失敗しました。"
ERR_MESSAGE_02="バックアップアーカイブが見つかりません。"
ERR_MESSAGE_03="アーカイブ展開に失敗しました。"
ERR_MESSAGE_04="リストアに失敗しました。"
ERR_MESSAGE_05="リストア前スナップショット作成に失敗しました。"
ERR_MESSAGE_06="アーカイブ整合性チェックに失敗しました（破損アーカイブを検知）。"

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
# フラグ解析（--dry-run / --yes / --skip-snapshot / RSTEP）
DRY_RUN=0
AUTO_CONFIRM=0
SKIP_SNAPSHOT=0
RSTEP=""
for _ARG in "$@"; do
  case "${_ARG}" in
    --dry-run)        DRY_RUN=1 ;;
    --yes)            AUTO_CONFIRM=1 ;;
    --skip-snapshot)  SKIP_SNAPSHOT=1 ;;
    *)                [ -z "${RSTEP}" ] && RSTEP="${_ARG}" ;;
  esac
done
# dry-run は書き込みを行わないため snapshot も不要
[ "${DRY_RUN}" = "1" ] && SKIP_SNAPSHOT=1

# 環境変数設定
## ワークフォルダ
WORK_DIR="${HOME}/Linux/platforms/kubernetes/apps/minecraft"
## リストア対象フォルダ
RESTORE_FOLDER1="/mnt/share/kubernetes/minecraft/server1"
RESTORE_FOLDER2="/mnt/share/kubernetes/minecraft/server2"
## リストア設定
USERNAME=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.username'`
PASSWORD=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.password'` && echo "${PASSWORD}" | sudo -S true
MNT_POINT="/mnt/truenas_minecraft_bk"
SMB_IP=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.smb.ip'`
SMB_USERNAME=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.smb.username'`
SMB_PASSWORD=`cat ~/Linux/platforms/settings/settings_secret.yml | yq eval '.smb.password'`
SMB_SHARE="//${SMB_IP}/Minecraft"
STAGE_DIR="${WORK_DIR}/restore_stage"
ARCHIVE_NAME="minecraft-backup.tgz"
ARCHIVE_FULL_PATH="${MNT_POINT}/${ARCHIVE_NAME}"
WORK_FULL_PATH1="${STAGE_DIR}"

# dry-run / mode 表示
if [ "${DRY_RUN}" = "1" ]; then
  echo "======================================================"
  echo "DRY RUN モード: 実際の書き込みは行いません"
  echo "  STEP040 は rsync --dry-run で変更内容のみ表示します"
  echo "======================================================"
fi

# STEPセット
NSTEP=""
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
      # 展開前に tar -tzf でアーカイブ全体を検証し、partial extract の偽成功を防ぐ。
      echo "アーカイブ整合性確認: ${ARCHIVE_FULL_PATH}"
      if ! tar -tzf "${ARCHIVE_FULL_PATH}" > /dev/null 2>&1; then
        echo "${ERR_MESSAGE_06}"
        echo "  対処: 新しいバックアップを取得してから restore を再実行してください。"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
      echo "アーカイブ整合性 OK"
      tar -xzf "${ARCHIVE_FULL_PATH}" -C "${STAGE_DIR}"
      # RETURN----------------------------------------------------------------------------------------------------------------------------------------
      RTN_CD=$?
      if [[ ${RTN_CD} -eq 0 ]]; then
        NSTEP="STEP035"
      else
        echo "${ERR_MESSAGE_03}"
        ABEND_FLG=1
        NSTEP="JOBEND"
        break
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP035
# リストア前スナップショット作成 + 確認プロンプト
# dry-run / --skip-snapshot 時はスナップショットをスキップする。
# 確認プロンプトは --yes / AUTO_CONFIRM で自動承認できる。
#*****************************************************************************************************************************************************
    "STEP035")
      # Pod running チェック（kubectl が利用可能な場合のみ）
      # restore は Pod 停止後に実施するべきだが、実行中でも技術的には可能。
      # live write 中の rsync 上書きは chunk 破損を引き起こすリスクがある。
      if command -v kubectl >/dev/null 2>&1; then
        _RUNNING_PODS=$(kubectl -n minecraft get pods \
          --field-selector=status.phase=Running \
          --no-headers 2>/dev/null | grep -c "minecraft-server" || true)
        if [ "${_RUNNING_PODS}" -gt 0 ]; then
          echo "======================================================"
          echo "WARNING: Minecraft サーバー Pod が ${_RUNNING_PODS} 個起動中です"
          echo "  live write 中の restore は chunk 破損を引き起こす可能性があります。"
          echo "  Pod を停止してから restore することを強く推奨します:"
          echo "    kubectl -n minecraft scale deployment minecraft-server1 minecraft-server2 --replicas=0"
          echo "    kubectl -n minecraft wait pod --for=delete -l 'app in (minecraft-server1,minecraft-server2)' --timeout=180s"
          echo "======================================================"
          if [ "${AUTO_CONFIRM}" = "0" ] && [ "${DRY_RUN}" = "0" ]; then
            printf "Pod 起動中のまま restore を続行しますか？（非推奨）(y/N): "
            read -r _POD_CONFIRM
            case "${_POD_CONFIRM}" in
              [yY]) echo "Pod 起動中のまま restore を続行します（自己責任）" ;;
              *) echo "restore をキャンセルしました。Pod を停止してから再実行してください。"; NSTEP="JOBEND"; break ;;
            esac
          fi
        fi
      fi

      # 確認プロンプト（dry-run 時は "dry-run 確認のみ" を表示）
      if [ "${DRY_RUN}" = "1" ]; then
        echo "------------------------------------------------------"
        echo "DRY RUN: 以下を上書き予定（実際の変更なし）"
        echo "  ${RESTORE_FOLDER1}"
        echo "  ${RESTORE_FOLDER2}"
        echo "------------------------------------------------------"
      elif [ "${AUTO_CONFIRM}" = "0" ]; then
        echo "======================================================"
        echo "WARNING: 以下のディレクトリを上書きします（破壊的操作）"
        echo "  ${RESTORE_FOLDER1}"
        echo "  ${RESTORE_FOLDER2}"
        echo ""
        echo "  --skip-snapshot なしの場合はスナップショットを作成後に上書きします"
        echo "  ロールバック先: ${MNT_POINT}/pre-restore-YYYYMMDD-HHMMSS/"
        echo "======================================================"
        printf "'YES' を入力してリストアを確認してください（それ以外でキャンセル）: "
        read -r _CONFIRM
        if [ "${_CONFIRM}" != "YES" ]; then
          echo "リストアをキャンセルしました。"
          NSTEP="JOBEND"
          break
        fi
      fi

      # リストア前スナップショット作成
      if [ "${SKIP_SNAPSHOT}" = "1" ]; then
        echo "リストア前スナップショットをスキップします（--skip-snapshot / --dry-run）"
        NSTEP="STEP040"
      else
        # EXEC------------------------------------------------------------------------------------------------------------------------------------------
        SNAPSHOT_LABEL="pre-restore-$(date +%Y%m%d-%H%M%S)"
        SNAPSHOT_DIR="${MNT_POINT}/${SNAPSHOT_LABEL}"
        echo "リストア前スナップショットを作成します: ${SNAPSHOT_DIR}"
        sudo mkdir -p "${SNAPSHOT_DIR}/server1" "${SNAPSHOT_DIR}/server2" && \
        sudo rsync -a --info=progress2 \
          "${RESTORE_FOLDER1}/" "${SNAPSHOT_DIR}/server1/" && \
        sudo rsync -a --info=progress2 \
          "${RESTORE_FOLDER2}/" "${SNAPSHOT_DIR}/server2/"
        # RETURN----------------------------------------------------------------------------------------------------------------------------------------
        RTN_CD=$?
        if [[ ${RTN_CD} -eq 0 ]]; then
          echo "スナップショット作成完了: ${SNAPSHOT_DIR}"
          echo "ロールバック方法:"
          echo "  sudo rsync -a ${SNAPSHOT_DIR}/server1/ ${RESTORE_FOLDER1}/"
          echo "  sudo rsync -a ${SNAPSHOT_DIR}/server2/ ${RESTORE_FOLDER2}/"
          # 古いスナップショットを削除（最新 3 件保持）
          mapfile -t _OLD_SNAPSHOTS < <(
            find "${MNT_POINT}" -maxdepth 1 -type d -name 'pre-restore-*' -printf '%T@ %p\n' 2>/dev/null \
              | sort -nr \
              | awk 'NR > 3 {sub(/^[^ ]+ /, ""); print}'
          )
          for _OLD in "${_OLD_SNAPSHOTS[@]}"; do
            if [[ "${_OLD}" != "${MNT_POINT}/pre-restore-"* ]]; then
              echo "削除対象外のパスを検出したためスキップします: ${_OLD}" >&2
              continue
            fi
            echo "古いスナップショットを削除: ${_OLD}"
            sudo rm -rf -- "${_OLD}"
          done
          NSTEP="STEP040"
        else
          echo "${ERR_MESSAGE_05}"
          ABEND_FLG=1
          NSTEP="JOBEND"
          break
        fi
      fi
    ;;

#*****************************************************************************************************************************************************
# STEP40
#*****************************************************************************************************************************************************
    "STEP040")
      # --dry-run の場合は rsync に --dry-run を付与して変更内容のみ表示する
      if [ "${DRY_RUN}" = "1" ]; then
        echo "DRY RUN: rsync --dry-run で変更内容を表示します（実際の書き込みなし）"
      fi
      # EXEC------------------------------------------------------------------------------------------------------------------------------------------

      # 1) ワールド/リソース/スポーン配下の「中身全削除（paper-world.yml と *.lock は残す）」
      # dry-run 時は削除をスキップ（rsync --dry-run で変更内容のみ表示する）
      shopt -s nullglob
      if [ "${DRY_RUN}" = "0" ]; then
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
      fi

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
      # dry-run 時は --dry-run を追加（実際の書き込みなし）
      _DRY_OPT=()
      [ "${DRY_RUN}" = "1" ] && _DRY_OPT=(--dry-run --itemize-changes)
      RSYNC_PLUGINS_OPTS=(-a --delete --prune-empty-dirs "${_DRY_OPT[@]}")
      RSYNC_WORLD_OPTS=(-a --delete --prune-empty-dirs --exclude='**/*.lock' --exclude='**/paper-world.yml' "${_DRY_OPT[@]}")

      for SERVER in 1 2; do
        SRC="${STAGE_DIR}/server${SERVER}"
        DST_VAR="RESTORE_FOLDER${SERVER}"
        DST="${!DST_VAR}"

        # ディレクトリ削除→差し替え（plugins）
        # dry-run 時は削除をスキップ / rsync --dry-run で変更内容のみ表示
        for REL in "${DIRS_REL[@]}"; do
          [[ -d "${SRC}/${REL}" || -f "${SRC}/${REL}" ]] || continue
          [ "${DRY_RUN}" = "0" ] && mkdir -p "${DST}/${REL}"
          [ "${DRY_RUN}" = "0" ] && find "${DST}/${REL}" -mindepth 1 -exec rm -rf {} +
          if [[ -d "${SRC}/${REL}" ]]; then
            rsync "${RSYNC_PLUGINS_OPTS[@]}" "${SRC}/${REL}/" "${DST}/${REL}/" \
              || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 2; }
          else
            rsync "${RSYNC_PLUGINS_OPTS[@]}" "${SRC}/${REL}" "${DST}/${REL}" \
              || { echo "${ERR_MESSAGE_04}"; ABEND_FLG=1; NSTEP="JOBEND"; break 2; }
          fi
        done

        # ファイル削除→差し替え（plugins）
        # dry-run 時は rm をスキップ / rsync --dry-run で変更内容のみ表示
        for REL in "${FILES_REL[@]}"; do
          [ "${DRY_RUN}" = "0" ] && rm -f "${DST}/${REL}"
          if [[ -f "${SRC}/${REL}" ]]; then
            [ "${DRY_RUN}" = "0" ] && mkdir -p "$(dirname "${DST}/${REL}")"
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
