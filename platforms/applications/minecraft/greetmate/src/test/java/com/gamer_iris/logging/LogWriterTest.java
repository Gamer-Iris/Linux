/*
######################################################################################################################################################
# ファイル   : LogWriterTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.logging;

import com.gamer_iris.Main;
import org.bukkit.plugin.PluginLogger;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.MockedConstruction;
import org.mockito.MockedStatic;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.logging.Logger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.*;

/**
 * LogWriter のユニットテストクラス
 */
class LogWriterTest {

    @TempDir
    static Path tempDir;

    private static File dataFolder;

    /**
     * ログ出力ディレクトリの初期化
     */
    @BeforeEach
    void setup() {
        dataFolder = tempDir.toFile();
    }

    /**
     * コンストラクタカバレッジテスト
     */
    @Test
    void testLogWriterConstructor_CoverageOnly() {
        new LogWriter();
    }

    /**
     * INFOログ出力が成功する場合
     */
    @Test
    void testWriteInfo() throws IOException {
        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            Main pluginMock = mock(Main.class);
            when(pluginMock.getDataFolder()).thenReturn(dataFolder);
            mainMock.when(Main::getInstance).thenReturn(pluginMock);

            String msg = "これはINFOログです";
            LogWriter.writeInfo(msg);

            File file = new File(dataFolder, "logs/info.log");
            assertTrue(file.exists());

            List<String> lines = Files.readAllLines(file.toPath());
            assertTrue(lines.get(lines.size() - 1).contains("[INFO] " + msg));
        }
    }

    /**
     * WARNログ出力が成功する場合
     */
    @Test
    void testWriteWarn() throws IOException {
        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            Main pluginMock = mock(Main.class);
            when(pluginMock.getDataFolder()).thenReturn(dataFolder);
            mainMock.when(Main::getInstance).thenReturn(pluginMock);

            String msg = "これはWARNログです";
            LogWriter.writeWarn(msg);
            File file = new File(dataFolder, "logs/warn.log");
            assertTrue(file.exists());

            List<String> lines = Files.readAllLines(file.toPath());
            assertTrue(lines.get(lines.size() - 1).contains("[WARN] " + msg));
        }
    }

    /**
     * Throwable付きでERRORログ出力が成功する場合
     */
    @Test
    void testWriteError_WithThrowable() throws IOException {
        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            Main pluginMock = mock(Main.class);
            Logger logger = mock(PluginLogger.class);
            when(pluginMock.getDataFolder()).thenReturn(dataFolder);
            when(pluginMock.getLogger()).thenReturn(logger);
            mainMock.when(Main::getInstance).thenReturn(pluginMock);

            String msg = "これはERRORログです";
            Throwable throwable = new RuntimeException("テストエラー");
            LogWriter.writeError(msg, throwable);
            File file = new File(dataFolder, "logs/error.log");
            assertTrue(file.exists());

            List<String> lines = Files.readAllLines(file.toPath());
            assertTrue(lines.stream().anyMatch(line -> line.contains("[ERROR] " + msg)));
            assertTrue(lines.stream().anyMatch(line -> line.contains("Caused by: java.lang.RuntimeException: テストエラー")));
        }
    }

    /**
     * IOException発生時にログがBukkit Loggerに出力される場合（Main取得成功）
     */
    @Test
    void testWriteError_WhenIOExceptionOccurs() throws Exception {
        MockedConstruction<FileWriter> mockedConstruction = mockConstruction(FileWriter.class, (mock, _) -> {
            doThrow(new IOException("強制エラー")).when(mock).write(anyString());
        });

        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            Main pluginMock = mock(Main.class);
            Logger logger = mock(Logger.class);
            when(pluginMock.getLogger()).thenReturn(logger);
            when(pluginMock.getDataFolder()).thenReturn(tempDir.toFile());
            mainMock.when(Main::getInstance).thenReturn(pluginMock);

            LogWriter.writeError("IOExceptionテスト", null);

            verify(logger).severe(contains("ログの書き込みに失敗しました"));
        } finally {
            mockedConstruction.close();
        }
    }

    /**
     * IOException発生時にMainがnullの場合
     */
    @Test
    void testWriteError_WhenIOExceptionOccursAndMainIsNull() throws Exception {
        MockedConstruction<FileWriter> mockedConstruction = mockConstruction(FileWriter.class, (mock, _) -> {
            doThrow(new IOException("テスト用IOException")).when(mock).write(anyString());
        });

        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            mainMock.when(Main::getInstance).thenReturn(null);

            LogWriter.writeError("IOException & null Main テスト", null);
        } finally {
            mockedConstruction.close();
        }
    }

    /**
     * Mainインスタンス取得時に例外が発生する場合
     */
    @Test
    void testWriteError_WhenMainIsNull() {
        try (MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            mainMock.when(Main::getInstance).thenThrow(new RuntimeException("Main unavailable"));

            LogWriter.writeError("テストメッセージ", null);
        }
    }

}
