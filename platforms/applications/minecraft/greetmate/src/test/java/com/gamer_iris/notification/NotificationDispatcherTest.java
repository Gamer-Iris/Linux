/*
######################################################################################################################################################
# ファイル   : NotificationDispatcherTest.java
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.util.Collections;
import java.util.Set;
import java.util.UUID;
import static org.mockito.Mockito.*;

/**
 * NotificationDispatcher のユニットテストクラス
 */
class NotificationDispatcherTest {

    private UUID uuid;
    private String name;
    private Player playerMock;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setup() {
        uuid = UUID.randomUUID();
        name = "テストユーザー";
        playerMock = mock(Player.class);
    }

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testNotificationDispatcherConstructor_CoverageOnly() {
        new NotificationDispatcher();
    }

    /**
     * ログインメッセージがキャッシュから取得できる場合
     */
    @Test
    void testBroadcastLoginMessage_FromCache() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLoginText(uuid)).thenReturn("ようこそ %s！");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLoginMessage(uuid, name);

            verify(playerMock).sendMessage("ようこそ テストユーザー！");
        }
    }

    /**
     * ログインメッセージが再構築後に取得できる場合
     */
    @Test
    void testBroadcastLoginMessage_RebuildCacheSuccess() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLoginText(uuid))
                    .thenReturn(null)
                    .thenReturn("再構築ようこそ %s！");
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLoginMessage(uuid, name);

            verify(playerMock).sendMessage("再構築ようこそ テストユーザー！");
        }
    }

    /**
     * ログインメッセージがデフォルトにフォールバックされる場合
     */
    @Test
    void testBroadcastLoginMessage_UsesDefaultMessage() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLoginText(uuid))
                    .thenReturn(null)
                    .thenReturn(null);
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            configMock.when(ConfigManager::getDefaultLoginMessage).thenReturn("デフォルトようこそ %s！");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLoginMessage(uuid, name);

            verify(playerMock).sendMessage("デフォルトようこそ テストユーザー！");
        }
    }

    /**
     * ログアウトメッセージがキャッシュから取得できる場合
     */
    @Test
    void testBroadcastLogoutMessage_FromCache() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLogoutText(uuid)).thenReturn("さようなら %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLogoutMessage(uuid, name);

            verify(playerMock).sendMessage("さようなら テストユーザー");
        }
    }

    /**
     * ログアウトメッセージが再構築後に取得できる場合
     */
    @Test
    void testBroadcastLogoutMessage_RebuildCacheSuccess() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLogoutText(uuid))
                    .thenReturn(null)
                    .thenReturn("再構築さようなら %s");
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLogoutMessage(uuid, name);

            verify(playerMock).sendMessage("再構築さようなら テストユーザー");
        }
    }

    /**
     * ログアウトメッセージがデフォルトにフォールバックされる場合
     */
    @Test
    void testBroadcastLogoutMessage_UsesDefaultMessage() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getLogoutText(uuid))
                    .thenReturn(null)
                    .thenReturn(null);
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            configMock.when(ConfigManager::getDefaultLogoutMessage).thenReturn("デフォルトさようなら %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastLogoutMessage(uuid, name);

            verify(playerMock).sendMessage("デフォルトさようなら テストユーザー");
        }
    }

    /**
     * キックメッセージがキャッシュから取得できる場合
     */
    @Test
    void testBroadcastKickMessage_FromCache() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getKickText(uuid)).thenReturn("キックされた %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastKickMessage(uuid, name);

            verify(playerMock).sendMessage("キックされた テストユーザー");
        }
    }

    /**
     * キックメッセージが再構築後に取得できる場合
     */
    @Test
    void testBroadcastKickMessage_RebuildCacheSuccess() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getKickText(uuid))
                    .thenReturn(null)
                    .thenReturn("再構築キック %s");
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastKickMessage(uuid, name);

            verify(playerMock).sendMessage("再構築キック テストユーザー");
        }
    }

    /**
     * キックメッセージがデフォルトにフォールバックされる場合
     */
    @Test
    void testBroadcastKickMessage_UsesDefaultMessage() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getKickText(uuid))
                    .thenReturn(null)
                    .thenReturn(null);
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            configMock.when(ConfigManager::getDefaultKickMessage).thenReturn("デフォルトキック %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastKickMessage(uuid, name);

            verify(playerMock).sendMessage("デフォルトキック テストユーザー");
        }
    }

    /**
     * BANメッセージがキャッシュから取得できる場合
     */
    @Test
    void testBroadcastBanMessage_FromCache() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getBanText(uuid)).thenReturn("BANされた %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastBanMessage(uuid, name);

            verify(playerMock).sendMessage("BANされた テストユーザー");
        }
    }

    /**
     * BANメッセージが再構築後に取得できる場合
     */
    @Test
    void testBroadcastBanMessage_RebuildCacheSuccess() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getBanText(uuid))
                    .thenReturn(null)
                    .thenReturn("再構築BAN %s");
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastBanMessage(uuid, name);

            verify(playerMock).sendMessage("再構築BAN テストユーザー");
        }
    }

    /**
     * BANメッセージがデフォルトにフォールバックされる場合
     */
    @Test
    void testBroadcastBanMessage_UsesDefaultMessage() {
        try (
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class);
                MockedStatic<ConfigManager> configMock = mockStatic(ConfigManager.class);
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class)) {

            cacheMock.when(() -> UserGreetingCacheManager.getBanText(uuid))
                    .thenReturn(null)
                    .thenReturn(null);
            cacheMock.when(() -> UserGreetingCacheManager.buildAndCache(uuid)).then(_ -> null);
            configMock.when(ConfigManager::getDefaultBanMessage).thenReturn("デフォルトBAN %s");
            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Set.of(playerMock));

            NotificationDispatcher.broadcastBanMessage(uuid, name);

            verify(playerMock).sendMessage("デフォルトBAN テストユーザー");
        }
    }

    /**
     * オンラインプレイヤーが存在しない場合のメッセージ送信確認
     */
    @Test
    void testBroadcastMessage_EmptyOnlinePlayers() {
        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<UserGreetingCacheManager> cacheMock = mockStatic(UserGreetingCacheManager.class)) {

            bukkitMock.when(Bukkit::getOnlinePlayers).thenReturn(Collections.emptySet());
            cacheMock.when(() -> UserGreetingCacheManager.getLoginText(uuid)).thenReturn("ようこそ %s！");

            NotificationDispatcher.broadcastLoginMessage(uuid, name);
        }
    }

}
