/*
######################################################################################################################################################
# ファイル   : ConfigManagerTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.config;

import com.gamer_iris.Main;
import com.gamer_iris.exception.CriticalException;
import java.io.File;
import org.bukkit.configuration.file.FileConfiguration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * ConfigManager のユニットテストクラス
 */
class ConfigManagerTest {

    private Main pluginMock;
    private FileConfiguration configMock;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setUp() {
        pluginMock = mock(Main.class);
        configMock = mock(FileConfiguration.class);

        when(pluginMock.getDataFolder()).thenReturn(new java.io.File("."));
        when(pluginMock.getConfig()).thenReturn(configMock);
        when(pluginMock.getConfig().contains("cache")).thenReturn(true);
        when(configMock.getInt("cache.expireSeconds")).thenReturn(60);
        when(configMock.getInt("log.rotationIntervalHours")).thenReturn(1);
        when(configMock.getInt("log.retentionDays")).thenReturn(7);
        when(configMock.getInt("maintenance.cleanupIntervalHours")).thenReturn(2);
        when(configMock.getInt("maintenance.cleanupThresholdDays")).thenReturn(3);
        when(configMock.getInt("maintenance.syncIntervalSeconds")).thenReturn(30);
        when(configMock.getString("default.loginMessage")).thenReturn("login");
        when(configMock.getString("default.logoutMessage")).thenReturn("logout");
        when(configMock.getString("default.kickMessage")).thenReturn("kick");
        when(configMock.getString("default.banMessage")).thenReturn("ban");
    }

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testConfigManagerConstructor_CoverageOnly() {
        new ConfigManager();
    }

    /**
     * 有効な設定が読み込まれる場合
     */
    @Test
    void testInit_ValidConfig() throws Exception {
        assertDoesNotThrow(() -> ConfigManager.init(pluginMock));

        var method = ConfigManager.class.getDeclaredMethod("isValid");
        method.setAccessible(true);
        boolean result = (boolean) method.invoke(null);

        assertTrue(result);
    }

    /**
     * dataFolderが存在しない場合
     */
    @Test
    void testInitConfig_DataFolderNotExists() {
        Main plugin = mock(Main.class);
        File mockFile = mock(File.class);
        when(plugin.getDataFolder()).thenReturn(mockFile);
        when(mockFile.exists()).thenReturn(false);

        FileConfiguration config = mock(FileConfiguration.class);
        when(plugin.getConfig()).thenReturn(config);
        assertThrows(CriticalException.class, () -> ConfigManager.init(plugin));
    }

    /**
     * 設定にcacheキーが存在しない場合
     */
    @Test
    void testInitConfig_ConfigMissingCacheKey() {
        Main plugin = mock(Main.class);
        File mockFile = mock(File.class);
        when(plugin.getDataFolder()).thenReturn(mockFile);
        when(mockFile.exists()).thenReturn(true);

        FileConfiguration config = mock(FileConfiguration.class);
        when(plugin.getConfig()).thenReturn(config);
        when(config.contains("cache")).thenReturn(false);

        assertThrows(CriticalException.class, () -> ConfigManager.init(plugin));
    }

    /**
     * 無効な設定値（expireSeconds）で初期化に失敗する場合
     */
    @Test
    void testInit_InvalidValues_ThrowsCriticalException() {
        when(configMock.getInt("cache.expireSeconds")).thenReturn(-1);
        when(pluginMock.getConfig().contains("cache")).thenReturn(true);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログローテーション時間が小さすぎる場合
     */
    @Test
    void testIsValid_False_WhenLogRotationHoursTooLow() throws Exception {
        when(configMock.getInt("log.rotationIntervalHours")).thenReturn(-1);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログローテーション時間が大きすぎる場合
     */
    @Test
    void testIsValid_False_WhenLogRotationHoursTooHigh() throws Exception {
        when(configMock.getInt("log.rotationIntervalHours")).thenReturn(25);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログ保持日数が小さすぎる場合
     */
    @Test
    void testIsValid_False_WhenLogRetentionDaysTooLow() throws Exception {
        when(configMock.getInt("log.retentionDays")).thenReturn(0);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * クリーンアップ間隔時間が小さすぎる場合
     */
    @Test
    void testIsValid_False_WhenCleanupIntervalHoursTooLow() throws Exception {
        when(configMock.getInt("maintenance.cleanupIntervalHours")).thenReturn(-1);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * クリーンアップ間隔時間が大きすぎる場合
     */
    @Test
    void testIsValid_False_WhenCleanupIntervalHoursTooHigh() throws Exception {
        when(configMock.getInt("maintenance.cleanupIntervalHours")).thenReturn(25);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * クリーンアップ対象日数が小さすぎる場合
     */
    @Test
    void testIsValid_False_WhenCleanupThresholdDaysTooLow() throws Exception {
        when(configMock.getInt("maintenance.cleanupThresholdDays")).thenReturn(0);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * 同期間隔秒数が小さすぎる場合
     */
    @Test
    void testIsValid_False_WhenSyncIntervalSecondsTooLow() throws Exception {
        when(configMock.getInt("maintenance.syncIntervalSeconds")).thenReturn(-1);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログインメッセージがnullの場合
     */
    @Test
    void testIsValid_False_WhenDefaultLoginMessageNull() throws Exception {
        when(configMock.getString("default.loginMessage")).thenReturn(null);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログインメッセージが空白の場合
     */
    @Test
    void testIsValid_False_WhenDefaultLoginMessageBlank() throws Exception {
        when(configMock.getString("default.loginMessage")).thenReturn(" ");
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログアウトメッセージがnullの場合
     */
    @Test
    void testIsValid_False_WhenDefaultLogoutMessageNull() throws Exception {
        when(configMock.getString("default.logoutMessage")).thenReturn(null);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * ログアウトメッセージが空白の場合
     */
    @Test
    void testIsValid_False_WhenDefaultLogoutMessageBlank() throws Exception {
        when(configMock.getString("default.logoutMessage")).thenReturn(" ");
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * キックメッセージがnullの場合
     */
    @Test
    void testIsValid_False_WhenDefaultKickMessageNull() throws Exception {
        when(configMock.getString("default.kickMessage")).thenReturn(null);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * キックメッセージが空白の場合
     */
    @Test
    void testIsValid_False_WhenDefaultKickMessageBlank() throws Exception {
        when(configMock.getString("default.kickMessage")).thenReturn(" ");
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * BANメッセージがnullの場合
     */
    @Test
    void testIsValid_False_WhenDefaultBanMessageNull() throws Exception {
        when(configMock.getString("default.banMessage")).thenReturn(null);
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

    /**
     * BANメッセージが空白の場合
     */
    @Test
    void testIsValid_False_WhenDefaultBanMessageBlank() throws Exception {
        when(configMock.getString("default.banMessage")).thenReturn(" ");
        assertThrows(CriticalException.class, () -> ConfigManager.init(pluginMock));
    }

}
