/*
######################################################################################################################################################
# ファイル   : ErrorHandlerTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.exception;

import com.gamer_iris.logging.LogWriter;
import org.bukkit.Server;
import org.bukkit.plugin.Plugin;
import org.bukkit.plugin.PluginManager;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * ErrorHandler のユニットテストクラス
 */
class ErrorHandlerTest {

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testErrorHandlerTestConstructor_CoverageOnly() {
        new ErrorHandler();
    }

    /**
     * 致命的なエラーが発生した場合にログ出力とプラグインの無効化が行われる場合
     */
    @Test
    void testHandleCriticalError_DisablesPluginAndLogs() {
        Plugin pluginMock = mock(Plugin.class);
        PluginManager pluginManagerMock = mock(PluginManager.class);
        Server serverMock = mock(Server.class);

        when(pluginMock.getServer()).thenReturn(serverMock);
        when(serverMock.getPluginManager()).thenReturn(pluginManagerMock);

        String message = "DB破損";
        Throwable cause = new RuntimeException("詳細");

        try (MockedStatic<LogWriter> logWriterMock = mockStatic(LogWriter.class)) {
            ErrorHandler.handleCriticalError(pluginMock, message, cause);

            logWriterMock.verify(() -> LogWriter.writeError(contains("重大エラー: " + message), eq(cause)), times(1));

            verify(pluginManagerMock).disablePlugin(pluginMock);
        }
    }

}
