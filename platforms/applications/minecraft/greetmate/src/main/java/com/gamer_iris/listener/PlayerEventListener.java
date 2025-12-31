/*
######################################################################################################################################################
# ファイル   : PlayerEventListener.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.listener;

import com.gamer_iris.cache.UserGreetingCacheManager;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.notification.NotificationDispatcher;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerKickEvent;
import java.util.UUID;

/**
 * プレイヤーのログイン、ログアウト、キックのイベントを管理するリスナークラス
 */
public class PlayerEventListener implements Listener {

    /**
     * プレイヤーがサーバーにログインした際の処理
     * 
     * @param event ログインイベント
     */
    @EventHandler
    public void onPlayerJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();
        UUID uuid = player.getUniqueId();
        String name = player.getName();

        if (!UserGreetingCacheManager.contains(uuid)) {
            UserGreetingCacheManager.buildAndCache(uuid);
            LogWriter.writeInfo("[Greetmate] ログイン時にキャッシュ構築: " + name);
        }

        NotificationDispatcher.broadcastLoginMessage(uuid, name);
    }

    /**
     * プレイヤーがログアウトした際の処理
     * 
     * @param event ログアウトイベント
     */
    @EventHandler
    public void onPlayerQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        UUID uuid = player.getUniqueId();
        String name = player.getName();

        NotificationDispatcher.broadcastLogoutMessage(uuid, name);
    }

    /**
     * プレイヤーがキックされた際の処理
     * 
     * @param event キックイベント
     */
    @EventHandler
    public void onPlayerKick(PlayerKickEvent event) {
        Player player = event.getPlayer();
        UUID uuid = player.getUniqueId();
        String name = player.getName();

        NotificationDispatcher.broadcastKickMessage(uuid, name);
        LogWriter.writeInfo("[Greetmate] プレイヤーがキックされました: " + name + " (" + uuid + ")");
    }

}
