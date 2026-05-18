/*
######################################################################################################################################################
# ファイル   : MainTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris;

import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.exception.CriticalException;
import com.gamer_iris.exception.ErrorHandler;
import com.gamer_iris.logging.LogRotator;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.maintenance.MaintenanceScheduler;
import org.junit.jupiter.api.*;
import org.mockbukkit.mockbukkit.MockBukkit;
import org.mockito.MockedStatic;
import java.lang.reflect.Field;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

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
    void tearDown() throws Exception {
        if (MockBukkit.isMocked()) {
            MockBukkit.unmock();
        }

        Field instanceField = Main.class.getDeclaredField("instance");
        instanceField.setAccessible(true);
        instanceField.set(null, null);
    }

    /**
     * onEnableが正常に動作する場合
     */
    @Test
    void testOnEnable_NormalFlow() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<LogRotator> rotatorMock = mockStatic(LogRotator.class);
                MockedStatic<MaintenanceScheduler> schedulerMock = mockStatic(MaintenanceScheduler.class)) {

            configMock.when(() -> ConfigManager.init(any())).thenAnswer(_ -> null);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            rotatorMock.when(LogRotator::start).thenAnswer(_ -> null);
            schedulerMock.when(MaintenanceScheduler::start).thenAnswer(_ -> null);

            plugin = MockBukkit.load(Main.class);

            assertNotNull(plugin);
            assertEquals(plugin, Main.getInstance());

            assertNotNull(plugin.getCommand("greetban"));
            assertNotNull(plugin.getCommand("greetrole"));
            assertNotNull(plugin.getCommand("greetunban"));

            configMock.verify(() -> ConfigManager.init(plugin));
            rotatorMock.verify(LogRotator::start);
            schedulerMock.verify(MaintenanceScheduler::start);
            logMock.verify(() -> LogWriter.writeInfo(contains("正常に有効化")));
        }
    }

    /**
     * onEnableがCriticalExceptionを発生させた場合
     */
    @Test
    void testOnEnable_CriticalException() {
        CriticalException exception = new CriticalException("config error");

        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<LogRotator> rotatorMock = mockStatic(LogRotator.class);
                MockedStatic<MaintenanceScheduler> schedulerMock = mockStatic(MaintenanceScheduler.class);
                MockedStatic<ErrorHandler> errorHandlerMock = mockStatic(ErrorHandler.class)) {

            configMock.when(() -> ConfigManager.init(any())).thenThrow(exception);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            plugin = MockBukkit.load(Main.class);

            assertNotNull(plugin);
            assertEquals(plugin, Main.getInstance());
            errorHandlerMock.verify(() -> ErrorHandler.handleCriticalError(plugin, "config error", exception));
            rotatorMock.verifyNoInteractions();
            schedulerMock.verifyNoInteractions();
        }
    }

    /**
     * onDisableが正常に動作する場合
     */
    @Test
    void testOnDisable() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<LogRotator> rotatorMock = mockStatic(LogRotator.class);
                MockedStatic<MaintenanceScheduler> schedulerMock = mockStatic(MaintenanceScheduler.class)) {

            configMock.when(() -> ConfigManager.init(any())).thenAnswer(_ -> null);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            rotatorMock.when(LogRotator::start).thenAnswer(_ -> null);
            schedulerMock.when(MaintenanceScheduler::start).thenAnswer(_ -> null);

            plugin = MockBukkit.load(Main.class);

            assertDoesNotThrow(() -> plugin.onDisable());
            logMock.verify(() -> LogWriter.writeInfo(contains("無効化")));
        }
    }

    /**
     * getInstanceが正常に取得できる場合
     */
    @Test
    void testGetInstance() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<LogRotator> rotatorMock = mockStatic(LogRotator.class);
                MockedStatic<MaintenanceScheduler> schedulerMock = mockStatic(MaintenanceScheduler.class)) {

            configMock.when(() -> ConfigManager.init(any())).thenAnswer(_ -> null);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            rotatorMock.when(LogRotator::start).thenAnswer(_ -> null);
            schedulerMock.when(MaintenanceScheduler::start).thenAnswer(_ -> null);

            plugin = MockBukkit.load(Main.class);

            assertEquals(plugin, Main.getInstance());
        }
    }

    /**
     * MockBukkit経由でMainクラスを正常にロードできる場合
     */
    @Test
    void testConstructor_WithMockBukkit() {
        try (
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<LogRotator> rotatorMock = mockStatic(LogRotator.class);
                MockedStatic<MaintenanceScheduler> schedulerMock = mockStatic(MaintenanceScheduler.class)) {
            configMock.when(() -> ConfigManager.init(any())).thenAnswer(_ -> null);
            logMock.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            rotatorMock.when(LogRotator::start).thenAnswer(_ -> null);
            schedulerMock.when(MaintenanceScheduler::start).thenAnswer(_ -> null);

            plugin = MockBukkit.load(Main.class);

            assertNotNull(plugin);
        }
    }

}
