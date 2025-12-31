/*
######################################################################################################################################################
# ファイル   : PlayerEventListenerTest.java
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
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerKickEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.util.UUID;
import static org.mockito.Mockito.*;

/**
 * PlayerEventListener のユニットテストクラス
 */
class PlayerEventListenerTest {

    private PlayerEventListener listener;
    private Player player;
    private UUID uuid;
    private String name;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setUp() {
        listener = new PlayerEventListener();
        player = mock(Player.class);
        uuid = UUID.randomUUID();
        name = "TestPlayer";

        when(player.getUniqueId()).thenReturn(uuid);
        when(player.getName()).thenReturn(name);
    }

    /**
     * キャッシュが存在しない状態でログインイベントが発生した場合
     */
    @Test
    void testOnPlayerJoin_WhenCacheMissing() {
        PlayerJoinEvent event = mock(PlayerJoinEvent.class);
        when(event.getPlayer()).thenReturn(player);

        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class);
                MockedStatic<NotificationDispatcher> notifyMock = mockStatic(NotificationDispatcher.class)) {
            cacheMock.when(() -> UserGreetingCacheManager.contains(uuid)).thenReturn(false);
            listener.onPlayerJoin(event);
            cacheMock.verify(() -> UserGreetingCacheManager.buildAndCache(uuid));
            logMock.verify(() -> LogWriter.writeInfo(contains("キャッシュ構築")));
            notifyMock.verify(() -> NotificationDispatcher.broadcastLoginMessage(uuid, name));
        }
    }

    /**
     * キャッシュが存在する状態でログインイベントが発生した場合
     */
    @Test
    void testOnPlayerJoin_WhenCacheExists() {
        PlayerJoinEvent event = mock(PlayerJoinEvent.class);
        when(event.getPlayer()).thenReturn(player);

        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<NotificationDispatcher> notifyMock = mockStatic(NotificationDispatcher.class)) {
            cacheMock.when(() -> UserGreetingCacheManager.contains(uuid)).thenReturn(true);
            listener.onPlayerJoin(event);
            cacheMock.verify(() -> UserGreetingCacheManager.buildAndCache(uuid), never());
            notifyMock.verify(() -> NotificationDispatcher.broadcastLoginMessage(uuid, name));
        }
    }

    /**
     * ログアウトイベントが発生した場合
     */
    @Test
    void testOnPlayerQuit() {
        PlayerQuitEvent event = mock(PlayerQuitEvent.class);
        when(event.getPlayer()).thenReturn(player);

        try (MockedStatic<NotificationDispatcher> notifyMock = mockStatic(NotificationDispatcher.class)) {
            listener.onPlayerQuit(event);
            notifyMock.verify(() -> NotificationDispatcher.broadcastLogoutMessage(uuid, name));
        }
    }

    /**
     * キックイベントが発生した場合
     */
    @Test
    void testOnPlayerKick() {
        PlayerKickEvent event = mock(PlayerKickEvent.class);
        when(event.getPlayer()).thenReturn(player);

        try (
                MockedStatic<NotificationDispatcher> notifyMock = mockStatic(NotificationDispatcher.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            listener.onPlayerKick(event);
            notifyMock.verify(() -> NotificationDispatcher.broadcastKickMessage(uuid, name));
            logMock.verify(() -> LogWriter.writeInfo(contains("キックされました")));
        }
    }

}
