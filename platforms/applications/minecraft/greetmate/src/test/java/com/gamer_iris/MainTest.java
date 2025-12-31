/*
######################################################################################################################################################
# ファイル   : MainTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris;

import org.mockbukkit.mockbukkit.MockBukkit;
import com.gamer_iris.command.AdminCommandHandler;
import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.exception.CriticalException;
import com.gamer_iris.logging.LogWriter;
import org.bukkit.command.PluginCommand;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import org.mockito.MockedStatic;

/**
 * Main クラスのユニットテストクラス
 */
class MainTest {

    private Main plugin;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setUp() {
        MockBukkit.mock();
    }

    /**
     * 各テスト後の後処理
     */
    @AfterEach
    void tearDown() {
        MockBukkit.unmock();
    }

    /**
     * onEnableが正常に動作する場合
     */
    @Test
    void testOnEnable_NormalFlow() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {

            configMock.when(() -> ConfigManager.init(any())).thenAnswer(_ -> null);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            plugin = MockBukkit.load(Main.class);

            assertNotNull(plugin);
            assertTrue(plugin.isEnabled());
            assertEquals(plugin, Main.getInstance());

            PluginCommand command = plugin.getCommand("greetrole");
            assertNotNull(command);
            assertTrue(command.getExecutor() instanceof AdminCommandHandler);
        }
    }

    /**
     * onEnableでCriticalExceptionが発生する場合
     */
    @Test
    void testOnEnable_CriticalException() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {

            configMock.when(() -> ConfigManager.init(any()))
                    .thenThrow(new CriticalException("Config error"));
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            plugin = MockBukkit.load(Main.class);

            assertNotNull(plugin);
            assertEquals(plugin, Main.getInstance());
        }
    }

    /**
     * onDisableが正常に動作する場合
     */
    @Test
    void testOnDisable() {
        plugin = MockBukkit.load(Main.class);

        try (MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            plugin.onDisable();
            assertFalse(plugin.isEnabled());
        }
    }

    /**
     * getInstanceが正常に取得できる場合
     */
    @Test
    void testGetInstance() {
        plugin = MockBukkit.load(Main.class);
        assertEquals(plugin, Main.getInstance());
    }

}
