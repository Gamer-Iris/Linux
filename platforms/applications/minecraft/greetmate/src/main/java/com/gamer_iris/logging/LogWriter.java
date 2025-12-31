/*
######################################################################################################################################################
# ファイル   : LogWriter.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.logging;

import com.gamer_iris.Main;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * プラグイン状態をログファイルに出力するログ書き込みユーティリティクラス
 */
public class LogWriter {

    private static final SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    /**
     * ログ出力用ディレクトリを取得
     * 
     * @return ログ格納用ディレクトリ
     */
    private static File getLogDir() {
        try {
            return new File(Main.getInstance().getDataFolder(), "logs");
        } catch (Exception e) {
            return new File("build/test-logs");
        }
    }

    /**
     * INFOレベルのログを出力
     * 
     * @param message ログメッセージ
     */
    public static void writeInfo(String message) {
        write("info.log", "[INFO] ", message, null);
    }

    /**
     * WARNレベルのログを出力
     * 
     * @param message ログメッセージ
     */
    public static void writeWarn(String message) {
        write("warn.log", "[WARN] ", message, null);
    }

    /**
     * ERRORレベルのログを出力
     * 
     * @param message   ログメッセージ
     * @param throwable 原因例外
     */
    public static void writeError(String message, Throwable throwable) {
        write("error.log", "[ERROR] ", message, throwable);
    }

    /**
     * 指定ファイルへログを書き込み
     * 
     * @param fileName  ファイル名
     * @param level     レベル文字列
     * @param message   ログメッセージ
     * @param throwable 例外あれば null可
     */
    private static void write(String fileName, String level, String message, Throwable throwable) {
        File logDir = getLogDir();

        if (!logDir.exists()) {
            logDir.mkdirs();
        }

        File file = new File(logDir, fileName);
        try (FileWriter writer = new FileWriter(file, true)) {
            String timestamp = dateFormat.format(new Date());
            writer.write(timestamp + " " + level + message + System.lineSeparator());
            if (throwable != null) {
                writer.write("Caused by: " + throwable.toString() + System.lineSeparator());
                for (StackTraceElement elem : throwable.getStackTrace()) {
                    writer.write("\tat " + elem.toString() + System.lineSeparator());
                }
            }
        } catch (IOException e) {
            if (Main.getInstance() != null) {
                Main.getInstance().getLogger().severe("ログの書き込みに失敗しました: " + e.getMessage());
            } else {
                System.err.println("[Greetmate] ログの書き込みに失敗しました（テスト環境など）: " + e.getMessage());
            }
        }
    }

}
