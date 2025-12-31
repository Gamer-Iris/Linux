/*
######################################################################################################################################################
# ファイル   : MaintenanceSchedulerTest.java
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
import org.bukkit.Server;
import org.bukkit.entity.Player;
import org.bukkit.plugin.PluginManager;
import org.bukkit.scheduler.BukkitScheduler;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.util.List;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * MaintenanceScheduler のユニットテストクラス
 */
class MaintenanceSchedulerTest {

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testMaintenanceSchedulerConstructor_CoverageOnly() {
        new MaintenanceScheduler();
    }

    /**
     * スケジューラ起動時にタスクがスケジュールされる場合
     */
    @Test
    void testStart_ShouldScheduleTasks() {
        Main mainMock = mock(Main.class);
        BukkitScheduler scheduler = mock(BukkitScheduler.class);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<Main> mainStaticMock = mockStatic(Main.class)) {
            mainStaticMock.when(Main::getInstance).thenReturn(mainMock);
            bukkitMock.when(Bukkit::getScheduler).thenReturn(scheduler);
            configMock.when(ConfigManager::getSyncIntervalSeconds).thenReturn(10);
            configMock.when(ConfigManager::getCleanupIntervalHours).thenReturn(1);

            MaintenanceScheduler.start();

            verify(scheduler, times(2))
                    .runTaskTimerAsynchronously(eq(mainMock), any(Runnable.class), eq(0L), anyLong());
        }
    }

    /**
     * メンテナンス実行時にBAN対象プレイヤーを処理する場合
     */
    @Test
    void testPerformMaintenance_AndBanHandling() {
        Player player = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        String name = "TestPlayer";

        when(player.getUniqueId()).thenReturn(uuid);
        when(player.getName()).thenReturn(name);

        BanPlayerData ban = new BanPlayerData(1, name, 0, uuid, "reason", null);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> roleDaoMock = mockStatic(PlayerRoleDao.class);
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<BanPlayerDao> banDaoMock = mockStatic(BanPlayerDao.class);
                MockedStatic<NotificationDispatcher> dispatcherMock = mockStatic(NotificationDispatcher.class)) {
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(List.of(player));
            roleDaoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            roleDaoMock.when(() -> PlayerRoleDao.insertPlayer(uuid, name, 0)).thenReturn(true);
            cacheMock.when(() -> UserGreetingCacheManager.contains(uuid)).thenReturn(false);
            banDaoMock.when(BanPlayerDao::getAll).thenReturn(List.of(ban));
            roleDaoMock.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(true);

            MaintenanceSchedulerTestable.runMaintenance();

            logMock.verify(() -> LogWriter.writeInfo(contains("定期メンテナンス処理を開始")));
            logMock.verify(() -> LogWriter.writeInfo(contains("新規登録しました")));
            dispatcherMock.verify(() -> NotificationDispatcher.broadcastBanMessage(uuid, name));
        }
    }

    /**
     * メンテナンス実行時にプレイヤーが既にDB登録されている場合
     */
    @Test
    void testPerformMaintenance_WhenPlayerAlreadyInDb() {
        Player player = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        String name = "PlayerInDB";
        PlayerData existingData = mock(PlayerData.class);

        when(player.getUniqueId()).thenReturn(uuid);
        when(player.getName()).thenReturn(name);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class);
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            Main pluginMock = mock(Main.class);
            Server serverMock = mock(Server.class);
            PluginManager pluginManagerMock = mock(PluginManager.class);
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            when(pluginMock.getServer()).thenReturn(serverMock);
            when(serverMock.getPluginManager()).thenReturn(pluginManagerMock);

            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(List.of(player));
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existingData);
            cacheMock.when(() -> UserGreetingCacheManager.contains(uuid)).thenReturn(true);

            MaintenanceSchedulerTestable.runMaintenance();

            logMock.verify(() -> LogWriter.writeInfo(contains("定期メンテナンス処理を開始")), atLeastOnce());
        }
    }

    /**
     * BANプレイヤー削除に失敗する場合（通知は行わない）
     */
    @Test
    void testPerformMaintenance_WhenBanPlayerDeleteFails() {
        UUID uuid = UUID.randomUUID();
        String name = "BanFailPlayer";

        BanPlayerData ban = new BanPlayerData(1, name, 0, uuid, "reason", null);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class);
                MockedStatic<BanPlayerDao> banMock = mockStatic(BanPlayerDao.class);
                MockedStatic<NotificationDispatcher> dispatcherMock = mockStatic(NotificationDispatcher.class)) {
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(List.of());
            banMock.when(BanPlayerDao::getAll).thenReturn(List.of(ban));
            daoMock.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(false);

            MaintenanceSchedulerTestable.runMaintenance();

            dispatcherMock.verifyNoInteractions();
        }
    }

    /**
     * deleteFromDatabaseで削除に失敗する場合
     */
    @Test
    void testDeleteFromDatabase_WhenDeleteFails() {
        UUID uuid = UUID.randomUUID();

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            daoMock.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(false);

            boolean result = MaintenanceSchedulerTestable.callDeleteFromDatabase(uuid);
            assertFalse(result);
        }
    }

    /**
     * クリーンアップが正常に実行される場合
     */
    @Test
    void testPerformCleanup() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<PlayerRoleDao> roleDaoMock = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            configMock.when(ConfigManager::getCleanupThresholdDays).thenReturn(30);
            roleDaoMock.when(() -> PlayerRoleDao.deleteInactivePlayers(30)).thenReturn(5);

            MaintenanceSchedulerTestable.runCleanup();

            logMock.verify(() -> LogWriter.writeInfo(contains("クリーンアップを開始")));
            logMock.verify(() -> LogWriter.writeInfo(contains("削除件数: 5")));
        }
    }

    /**
     * メンテナンステスト用のユーティリティクラス
     */
    static class MaintenanceSchedulerTestable extends MaintenanceScheduler {

        /**
         * performMaintenance をリフレクションで実行する場合
         */
        static void runMaintenance() {
            try {
                var method = MaintenanceScheduler.class.getDeclaredMethod("performMaintenance");
                method.setAccessible(true);
                method.invoke(null);
            } catch (Exception e) {
                throw new RuntimeException("Failed to invoke performMaintenance via reflection", e);
            }
        }

        /**
         * performCleanup をリフレクションで実行する場合
         */
        static void runCleanup() {
            try {
                var method = MaintenanceScheduler.class.getDeclaredMethod("performCleanup");
                method.setAccessible(true);
                method.invoke(null);
            } catch (Exception e) {
                throw new RuntimeException("Failed to invoke performCleanup via reflection", e);
            }
        }

        /**
         * deleteFromDatabase をリフレクションで実行する場合
         * 
         * @param uuid 削除対象のUUID
         * @return 削除成功時は true、失敗時は false
         */
        static boolean callDeleteFromDatabase(UUID uuid) {
            try {
                var method = MaintenanceScheduler.class.getDeclaredMethod("deleteFromDatabase", UUID.class);
                method.setAccessible(true);
                return (boolean) method.invoke(null, uuid);
            } catch (Exception e) {
                throw new RuntimeException("Failed to call deleteFromDatabase via reflection", e);
            }
        }

    }

}
