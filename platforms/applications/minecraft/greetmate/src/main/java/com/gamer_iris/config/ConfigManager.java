/*
######################################################################################################################################################
# ファイル   : ConfigManager.java
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
import org.bukkit.configuration.file.FileConfiguration;

/**
 * config.yml を読み込み設定を取得するマネージャークラス
 */
public class ConfigManager {

    private static FileConfiguration config;

    /**
     * config.yml を読み込み初期化を行う
     * 
     * @param plugin プラグイン実体
     */
    public static void init(Main plugin) {
        if (!plugin.getDataFolder().exists() || !plugin.getConfig().contains("cache")) {
            throw new CriticalException("config.yml が存在しない、または破損しています。");
        }

        plugin.saveDefaultConfig();
        config = plugin.getConfig();

        if (!isValid()) {
            throw new CriticalException("config.yml に不整値があります。");
        }
    }

    /**
     * キャッシュの有効期限を秒単位で取得
     * 
     * @return 秒数
     */
    public static int getCacheExpireSeconds() {
        return config.getInt("cache.expireSeconds");
    }

    /**
     * ログローテーション間隔を時間単位で取得
     * 
     * @return 時数
     */
    public static int getLogRotationHours() {
        return config.getInt("log.rotationIntervalHours");
    }

    /**
     * ログ保持期間を日数単位で取得
     * 
     * @return 日数
     */
    public static int getLogRetentionDays() {
        return config.getInt("log.retentionDays");
    }

    /**
     * クリーンアップ間隔を時間単位で取得
     * 
     * @return 時数
     */
    public static int getCleanupIntervalHours() {
        return config.getInt("maintenance.cleanupIntervalHours");
    }

    /**
     * クリーン対象となる利用者のデータ保持期間を日数単位で取得
     * 
     * @return 日数
     */
    public static int getCleanupThresholdDays() {
        return config.getInt("maintenance.cleanupThresholdDays");
    }

    /**
     * DB同期間隔を秒単位で取得
     * 
     * @return 秒数
     */
    public static int getSyncIntervalSeconds() {
        return config.getInt("maintenance.syncIntervalSeconds");
    }

    /**
     * デフォルトのログインメッセージを取得
     * 
     * @return メッセージ文字列
     */
    public static String getDefaultLoginMessage() {
        return config.getString("default.loginMessage");
    }

    /**
     * デフォルトのログアウトメッセージを取得
     * 
     * @return メッセージ文字列
     */
    public static String getDefaultLogoutMessage() {
        return config.getString("default.logoutMessage");
    }

    /**
     * デフォルトのキック時メッセージを取得
     * 
     * @return メッセージ文字列
     */
    public static String getDefaultKickMessage() {
        return config.getString("default.kickMessage");
    }

    /**
     * デフォルトのBAN時メッセージを取得
     * 
     * @return メッセージ文字列
     */
    public static String getDefaultBanMessage() {
        return config.getString("default.banMessage");
    }

    /**
     * config.yml に不正な値が含まれていないかを検証
     * 
     * @return trueなら有効
     */
    private static boolean isValid() {
        return getCacheExpireSeconds() > 0
                && getLogRotationHours() > 0 && getLogRotationHours() <= 24
                && getLogRetentionDays() >= 1
                && getCleanupIntervalHours() > 0 && getCleanupIntervalHours() <= 24
                && getCleanupThresholdDays() >= 1
                && getSyncIntervalSeconds() > 0
                && getDefaultLoginMessage() != null && !getDefaultLoginMessage().trim().isEmpty()
                && getDefaultLogoutMessage() != null && !getDefaultLogoutMessage().trim().isEmpty()
                && getDefaultKickMessage() != null && !getDefaultKickMessage().trim().isEmpty()
                && getDefaultBanMessage() != null && !getDefaultBanMessage().trim().isEmpty();
    }

}
