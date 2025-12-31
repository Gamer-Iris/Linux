/*
######################################################################################################################################################
# ファイル   : ErrorHandler.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.exception;

import com.gamer_iris.logging.LogWriter;
import org.bukkit.plugin.Plugin;

/**
 * 致命的なエラー発生時の処理を行うハンドラークラス
 */
public class ErrorHandler {

    /**
     * プラグイン内で発生した致命的なエラーを処理し、プラグインを無効化
     * 
     * @param plugin    対象プラグイン
     * @param message   表示用メッセージ
     * @param throwable 原因エラー
     */
    public static void handleCriticalError(Plugin plugin, String message, Throwable throwable) {
        String fullMessage = "[Greetmate] 重大エラー: " + message;
        LogWriter.writeError(fullMessage, throwable);
        plugin.getServer().getPluginManager().disablePlugin(plugin);
    }

}
