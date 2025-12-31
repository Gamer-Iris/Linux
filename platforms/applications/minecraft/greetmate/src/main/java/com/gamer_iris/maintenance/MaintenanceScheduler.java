/*
######################################################################################################################################################
# ファイル   : MaintenanceScheduler.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.maintenance;

import com.gamer_iris.Main;
import com.gamer_iris.cache.UserGreetingCacheManager;
import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.BanPlayerData;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.notification.NotificationDispatcher;
import com.gamer_iris.repository.BanPlayerDao;
import com.gamer_iris.repository.PlayerRoleDao;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.Plugin;
import java.util.List;
import java.util.UUID;

/**
 * 定期メンテナンス処理を実行するスケジューラークラス
 */
public class MaintenanceScheduler {

    /**
     * 定期メンテナンス、クリーンアップの定期実行を設定
     */
    public static void start() {
        Plugin plugin = Main.getInstance();

        long syncIntervalTicks = ConfigManager.getSyncIntervalSeconds() * 20L;
        long cleanupIntervalTicks = ConfigManager.getCleanupIntervalHours() * 60L * 60L * 20L;

        Bukkit.getScheduler().runTaskTimerAsynchronously(plugin, MaintenanceScheduler::performMaintenance, 0L,
                syncIntervalTicks);

        Bukkit.getScheduler().runTaskTimerAsynchronously(plugin, MaintenanceScheduler::performCleanup, 0L,
                cleanupIntervalTicks);
    }

    /**
     * 定期メンテナンス処理を実行
     */
    private static void performMaintenance() {
        LogWriter.writeInfo("[Greetmate] 定期メンテナンス処理を開始します...");

        syncOnlinePlayersToDatabase();
        handleBanPlayers();

        LogWriter.writeInfo("[Greetmate] 定期メンテナンス処理が完了しました。");
    }

    /**
     * オンラインプレイヤーの情報をDBに更新し、キャッシュを作成
     */
    private static void syncOnlinePlayersToDatabase() {
        for (Player player : Bukkit.getOnlinePlayers()) {
            UUID uuid = player.getUniqueId();
            String name = player.getName();

            PlayerData data = PlayerRoleDao.findPlayerByUUID(uuid);
            if (data == null) {
                PlayerRoleDao.insertPlayer(uuid, name, 0);
                LogWriter.writeInfo("[Greetmate] " + name + " をDBに新規登録しました。");
            }

            if (!UserGreetingCacheManager.contains(uuid)) {
                UserGreetingCacheManager.buildAndCache(uuid);
                LogWriter.writeInfo("[Greetmate] " + name + " のキャッシュ情報を投入しました。");
            }
        }
    }

    /**
     * BAN登録されたプレイヤーの情報を削除、通知を実行
     */
    private static void handleBanPlayers() {
        List<BanPlayerData> bannedList = BanPlayerDao.getAll();

        for (BanPlayerData ban : bannedList) {
            UUID uuid = ban.getUuid();
            String name = ban.getPlayerName();

            boolean wasInDb = deleteFromDatabase(uuid);
            if (wasInDb) {
                LogWriter.writeInfo("[Greetmate] BANプレイヤーをDBとキャッシュから削除: " + name + " (" + uuid + ")");
                NotificationDispatcher.broadcastBanMessage(uuid, name);
            }
        }
    }

    /**
     * DBとキャッシュから指定プレイヤーを削除
     * 
     * @param uuid プレイヤーUUID
     * @return DBから削除された場合true
     */
    private static boolean deleteFromDatabase(UUID uuid) {
        boolean deleted = PlayerRoleDao.deletePlayerByUUID(uuid);
        if (deleted) {
            UserGreetingCacheManager.remove(uuid);
        }
        return deleted;
    }

    /**
     * 使用履歴に基づくデータのクリーンアップを実行
     */
    private static void performCleanup() {
        LogWriter.writeInfo("[Greetmate] プレイヤーデータのクリーンアップを開始します...");

        int thresholdDays = ConfigManager.getCleanupThresholdDays();
        int deletedCount = PlayerRoleDao.deleteInactivePlayers(thresholdDays);

        LogWriter.writeInfo("[Greetmate] クリーンアップ完了。削除件数: " + deletedCount);
    }

}
