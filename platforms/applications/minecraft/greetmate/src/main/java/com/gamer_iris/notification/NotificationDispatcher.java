/*
######################################################################################################################################################
# ファイル   : NotificationDispatcher.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.notification;

import com.gamer_iris.cache.UserGreetingCacheManager;
import com.gamer_iris.config.ConfigManager;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import java.util.UUID;

/**
 * プレイヤーのアクションに対する通知を発射するクラス
 */
public class NotificationDispatcher {

    /**
     * ログイン時の通知を発射
     * 
     * @param uuid       プレイヤーUUID
     * @param playerName プレイヤー名
     */
    public static void broadcastLoginMessage(UUID uuid, String playerName) {
        String msg = UserGreetingCacheManager.getLoginText(uuid);
        if (msg == null) {
            UserGreetingCacheManager.buildAndCache(uuid);
            String cached = UserGreetingCacheManager.getLoginText(uuid);
            if (cached == null)
                msg = ConfigManager.getDefaultLoginMessage();
            else
                msg = cached;
        }
        broadcastMessage(String.format(msg, playerName));
    }

    /**
     * ログアウト時の通知を発射
     * 
     * @param uuid       プレイヤーUUID
     * @param playerName プレイヤー名
     */
    public static void broadcastLogoutMessage(UUID uuid, String playerName) {
        String msg = UserGreetingCacheManager.getLogoutText(uuid);
        if (msg == null) {
            UserGreetingCacheManager.buildAndCache(uuid);
            String cached = UserGreetingCacheManager.getLogoutText(uuid);
            if (cached == null)
                msg = ConfigManager.getDefaultLogoutMessage();
            else
                msg = cached;
        }
        broadcastMessage(String.format(msg, playerName));
    }

    /**
     * キック時の通知を発射
     * 
     * @param uuid       プレイヤーUUID
     * @param playerName プレイヤー名
     */
    public static void broadcastKickMessage(UUID uuid, String playerName) {
        String msg = UserGreetingCacheManager.getKickText(uuid);
        if (msg == null) {
            UserGreetingCacheManager.buildAndCache(uuid);
            String cached = UserGreetingCacheManager.getKickText(uuid);
            if (cached == null)
                msg = ConfigManager.getDefaultKickMessage();
            else
                msg = cached;
        }
        broadcastMessage(String.format(msg, playerName));
    }

    /**
     * BAN時の通知を発射
     * 
     * @param uuid       プレイヤーUUID
     * @param playerName プレイヤー名
     */
    public static void broadcastBanMessage(UUID uuid, String playerName) {
        String msg = UserGreetingCacheManager.getBanText(uuid);
        if (msg == null) {
            UserGreetingCacheManager.buildAndCache(uuid);
            String cached = UserGreetingCacheManager.getBanText(uuid);
            if (cached == null)
                msg = ConfigManager.getDefaultBanMessage();
            else
                msg = cached;
        }
        broadcastMessage(String.format(msg, playerName));
    }

    /**
     * 指定メッセージを全オンラインプレイヤーに発信
     * 
     * @param message 発信する文字列
     */
    private static void broadcastMessage(String message) {
        for (Player p : Bukkit.getOnlinePlayers()) {
            p.sendMessage(message);
        }
    }

}
