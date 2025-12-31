/*
######################################################################################################################################################
# ファイル   : LogRotator.java
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
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.text.SimpleDateFormat;
import java.util.*;

/**
 * ログファイルのローテーションを管理するマネージャークラス
 */
public class LogRotator {

    private static final SimpleDateFormat suffixFormat = new SimpleDateFormat("yyyyMMdd_HHmmss");
    private static final String[] TARGET_FILES = { "info.log", "warn.log", "error.log" };

    /**
     * ローテーションの定期実行を開始
     */
    public static void start() {
        long intervalTicks = ConfigManager.getLogRotationHours() * 60L * 60L * 20L;
        Bukkit.getScheduler().runTaskTimerAsynchronously(Main.getInstance(), LogRotator::rotateLogs, intervalTicks,
                intervalTicks);
    }

    /**
     * 実際のローテーション処理を実行
     */
    public static void rotateLogs() {
        File logDir = new File(Main.getInstance().getDataFolder(), "logs");
        if (!logDir.exists())
            return;

        for (String fileName : TARGET_FILES) {
            File original = new File(logDir, fileName);
            if (!original.exists())
                continue;

            String timestamp = suffixFormat.format(new Date());
            File rotated = new File(logDir, fileName.replace(".log", "_" + timestamp + ".log"));

            try {
                Files.move(original.toPath(), rotated.toPath(), StandardCopyOption.REPLACE_EXISTING);
                LogWriter.writeInfo(fileName + " をローテートしました: " + rotated.getName());
            } catch (IOException e) {
                Bukkit.getLogger().warning("ログローテーションに失敗: " + e.getMessage());
            }
        }

        deleteOldLogs(logDir);
    }

    /**
     * 保持期間を超過したログファイルを削除
     * 
     * @param logDir ログディレクトリ
     */
    private static void deleteOldLogs(File logDir) {
        String patternPrefix = Arrays.stream(TARGET_FILES)
                .map(name -> name.replace(".log", ""))
                .reduce((a, b) -> a + "|" + b)
                .orElse("");
        String regex = "(" + patternPrefix + ")_\\d{8}_\\d{6}\\.log";
        File[] files = logDir.listFiles((_, name) -> name.matches(regex));
        if (files == null)
            return;

        int retentionDays = ConfigManager.getLogRetentionDays();
        long cutoff = System.currentTimeMillis() - (retentionDays * 24L * 60L * 60L * 1000L);

        for (File file : files) {
            if (file.lastModified() < cutoff) {
                if (file.delete()) {
                    LogWriter.writeInfo("古いログを削除しました: " + file.getName());
                }
            }
        }
    }

}
