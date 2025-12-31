/*
######################################################################################################################################################
# ファイル   : LogRotatorTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.logging;

import com.gamer_iris.Main;
import com.gamer_iris.config.ConfigManager;
import org.bukkit.Bukkit;
import org.bukkit.scheduler.BukkitScheduler;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.MockedStatic;
import java.io.File;
import java.io.FileWriter;
import java.io.FilenameFilter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.logging.Logger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * LogRotator のユニットテストクラス
 */
class LogRotatorTest {

    @TempDir
    Path tempDir;

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testLogRotatorConstructor_CoverageOnly() {
        new LogRotator();
    }

    /**
     * ログローテーションのスケジュールが正しく設定される場合
     */
    @Test
    void testStartSchedulesTask() {
        Main plugin = mock(Main.class);
        BukkitScheduler scheduler = mock(BukkitScheduler.class);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class)) {
            mainMock.when(Main::getInstance).thenReturn(plugin);
            bukkitMock.when(Bukkit::getScheduler).thenReturn(scheduler);
            configMock.when(ConfigManager::getLogRotationHours).thenReturn(1);

            LogRotator.start();

            verify(scheduler).runTaskTimerAsynchronously(eq(plugin), any(Runnable.class), eq(72000L), eq(72000L));
        }
    }

    /**
     * ログディレクトリが存在しない場合
     */
    @Test
    void testRotateLogs_LogDirDoesNotExist() {
        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);

            File logDir = new File(tempDir.toFile(), "logs");
            assertFalse(logDir.exists());

            LogRotatorTestable.callRotateLogs();
        }
    }

    /**
     * ログファイルが正常にローテートされる場合
     */
    @Test
    void testRotateLogs_MovesFilesCorrectly() throws Exception {
        File logDir = new File(tempDir.toFile(), "logs");
        assertTrue(logDir.mkdirs());

        File infoLog = new File(logDir, "info.log");
        try (FileWriter writer = new FileWriter(infoLog)) {
            writer.write("テストログ");
        }

        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        try (
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<LogWriter> logWriterMock = mockStatic(LogWriter.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            configMock.when(ConfigManager::getLogRetentionDays).thenReturn(30);

            LogRotatorTestable.callRotateLogs();

            File[] rotated = logDir.listFiles((_, name) -> name.matches("info_\\d{8}_\\d{6}\\.log"));
            assertNotNull(rotated);
            assertTrue(rotated.length >= 1);
            assertFalse(infoLog.exists());

            logWriterMock.verify(() -> LogWriter.writeInfo(contains("info.log をローテートしました")));
        }
    }

    /**
     * IOException が発生した場合
     */
    @Test
    void testRotateLogs_WhenIOExceptionOccurs() {
        File logDir = new File(tempDir.toFile(), "logs");
        assertTrue(logDir.mkdirs());

        File infoLog = new File(logDir, "info.log");
        try (FileWriter writer = new FileWriter(infoLog)) {
            writer.write("テストログ");
        } catch (IOException e) {
            fail("ログファイル作成に失敗: " + e.getMessage());
        }

        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        Logger logger = mock(Logger.class);
        try (
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<Files> filesMock = mockStatic(Files.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            configMock.when(ConfigManager::getLogRetentionDays).thenReturn(30);
            bukkitMock.when(Bukkit::getLogger).thenReturn(logger);
            filesMock.when(() -> Files.move(any(), any(), any())).thenThrow(new IOException("ローテート失敗テスト"));

            LogRotatorTestable.callRotateLogs();

            verify(logger).warning(contains("ログローテーションに失敗"));
        }
    }

    /**
     * 古いログファイルが削除される場合
     */
    @Test
    void testDeleteOldLogs_RemovesOldFiles() throws Exception {
        File logDir = new File(tempDir.toFile(), "logs");
        assertTrue(logDir.mkdirs());

        File oldLog = new File(logDir, "info_20000101_000000.log");
        assertTrue(oldLog.createNewFile());
        oldLog.setLastModified(System.currentTimeMillis() - (100L * 24 * 60 * 60 * 1000));

        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        try (
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logWriterMock = mockStatic(LogWriter.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            configMock.when(ConfigManager::getLogRetentionDays).thenReturn(30);

            LogRotatorTestable.callRotateLogs();

            assertFalse(oldLog.exists());
            logWriterMock.verify(() -> LogWriter.writeInfo(contains("古いログを削除しました")));
        }
    }

    /**
     * logDir.listFiles() が null を返す場合
     */
    @Test
    void testDeleteOldLogs_WhenListFilesReturnsNull() {
        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        File logDir = mock(File.class);
        when(logDir.listFiles(any(FilenameFilter.class))).thenReturn(null);

        try (
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            configMock.when(ConfigManager::getLogRetentionDays).thenReturn(30);

            LogRotatorTestable.callDeleteOldLogs(logDir);
        }
    }

    /**
     * ログファイル削除に失敗した場合
     */
    @Test
    void testDeleteOldLogs_DeleteFails() throws Exception {
        File logDir = spy(new File(tempDir.toFile(), "logs"));
        assertTrue(logDir.mkdirs());

        File undeletableLog = spy(new File(logDir, "info_20000101_000000.log"));
        assertTrue(undeletableLog.createNewFile());
        undeletableLog.setLastModified(System.currentTimeMillis() - (100L * 24 * 60 * 60 * 1000));
        doReturn(false).when(undeletableLog).delete();
        doReturn(new File[] { undeletableLog }).when(logDir).listFiles(any(FilenameFilter.class));

        Main pluginMock = mock(Main.class);
        when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());

        try (
                MockedStatic<Main> mainMock = mockStatic(Main.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<LogWriter> logWriterMock = mockStatic(LogWriter.class)) {
            mainMock.when(Main::getInstance).thenReturn(pluginMock);
            configMock.when(ConfigManager::getLogRetentionDays).thenReturn(30);

            LogRotatorTestable.callDeleteOldLogs(logDir);

            logWriterMock.verifyNoInteractions();
        }
    }

    /**
     * ログローテーション処理を直接実行するためのヘルパークラス
     */
    static class LogRotatorTestable extends LogRotator {

        /**
         * rotateLogs メソッドの呼び出し
         */
        static void callRotateLogs() {
            LogRotator.rotateLogs();
        }

        /**
         * deleteOldLogs メソッドの呼び出し
         * 
         * @param logDir ログディレクトリ
         */
        static void callDeleteOldLogs(File logDir) {
            try {
                java.lang.reflect.Method method = LogRotator.class.getDeclaredMethod("deleteOldLogs", File.class);
                method.setAccessible(true);
                method.invoke(null, logDir);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }

        /**
         * deleteOldLogs メソッドの呼び出し（listFiles の返却値を null にするケース）
         * 
         * @param logDir ログディレクトリ
         * @param files  無視されるファイル配列（ダミー）
         */
        static void callDeleteOldLogs(File logDir, File[] files) {
            try {
                java.lang.reflect.Method method = LogRotator.class.getDeclaredMethod("deleteOldLogs", File.class);
                method.setAccessible(true);
                when(logDir.listFiles(any(FilenameFilter.class))).thenReturn(null);
                method.invoke(null, logDir);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }

}
