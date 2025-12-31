/*
######################################################################################################################################################
# ファイル   : UserGreetingCacheManagerTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.cache;

import com.gamer_iris.Main;
import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.model.RoleData;
import com.gamer_iris.repository.PlayerRoleDao;
import org.junit.jupiter.api.*;
import org.mockito.MockedStatic;
import java.io.File;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.*;

/**
 * UserGreetingCacheManager のユニットテストクラス
 */
class UserGreetingCacheManagerTest {

    private UUID uuid;
    private PlayerData playerData;
    private RoleData roleData;
    private static MockedStatic<ConfigManager> configMock;
    private static MockedStatic<LogWriter> logMock;
    private static MockedStatic<Main> mainMock;

    /**
     * グローバルモック設定
     */
    @BeforeAll
    static void beforeAll() {
        mainMock = mockStatic(Main.class);
        Main dummyMain = mock(Main.class);
        when(dummyMain.getDataFolder()).thenReturn(new File("build/tmp/test-logs"));
        mainMock.when(Main::getInstance).thenReturn(dummyMain);
        configMock = mockStatic(ConfigManager.class);
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(60);
        logMock = mockStatic(LogWriter.class);
    }

    /**
     * モック解放
     */
    @AfterAll
    static void afterAll() {
        mainMock.close();
        configMock.close();
        logMock.close();
    }

    /**
     * UUID初期化
     */
    @BeforeEach
    void setUp() {
        uuid = UUID.randomUUID();
        playerData = mock(PlayerData.class);
        roleData = mock(RoleData.class);
    }

    /**
     * コンストラクタカバレッジテスト
     */
    @Test
    void testUserGreetingCacheManagerConstructor_CoverageOnly() {
        new UserGreetingCacheManager();
    }

    /**
     * エントリがnullの場合
     */
    @Test
    void testContains_WhenEntryIsNull() {
        UUID testUuid = UUID.randomUUID();
        assertFalse(UserGreetingCacheManager.contains(testUuid));
    }

    /**
     * 有効期限が切れた場合
     */
    @Test
    void testContains_WhenEntryIsExpired() throws InterruptedException {
        UUID testUuid = UUID.randomUUID();
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(0);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getLoginText()).thenReturn("expired");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(testUuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(testUuid);
            Thread.sleep(1500);

            assertFalse(UserGreetingCacheManager.contains(testUuid));
        }
    }

    /**
     * キャッシュを正常に保持できる場合
     */
    @Test
    void testBuildAndCache_Success() {
        when(playerData.getRole()).thenReturn(1);
        when(roleData.getLoginText()).thenReturn("ようこそ！");
        when(roleData.getLogoutText()).thenReturn("またね！");
        when(roleData.getKickText()).thenReturn("キックされたよ！");
        when(roleData.getBanText()).thenReturn("BANされました。");

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(uuid);

            assertTrue(UserGreetingCacheManager.contains(uuid));
            assertEquals("ようこそ！", UserGreetingCacheManager.getLoginText(uuid));
            assertEquals("またね！", UserGreetingCacheManager.getLogoutText(uuid));
            assertEquals("キックされたよ！", UserGreetingCacheManager.getKickText(uuid));
            assertEquals("BANされました。", UserGreetingCacheManager.getBanText(uuid));
        }
    }

    /**
     * プレイヤーが見つからない場合
     */
    @Test
    void testBuildAndCache_PlayerNotFound() {
        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);

            UserGreetingCacheManager.buildAndCache(uuid);

            assertFalse(UserGreetingCacheManager.contains(uuid));
            logMock.verify(() -> LogWriter.writeWarn(contains("UUIDからプレイヤーが見つかりませんでした")), times(1));
        }
    }

    /**
     * ロール情報が見つからない場合
     */
    @Test
    void testBuildAndCache_RoleNotFound() {
        when(playerData.getRole()).thenReturn(99);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(99)).thenReturn(null);

            UserGreetingCacheManager.buildAndCache(uuid);

            assertFalse(UserGreetingCacheManager.contains(uuid));
            logMock.verify(() -> LogWriter.writeWarn(contains("ロール情報が見つかりませんでした")), times(1));
        }
    }

    /**
     * キャッシュを削除する場合
     */
    @Test
    void testRemove_RemovesCacheEntry() {
        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getLoginText()).thenReturn("削除対象");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(uuid);
            assertTrue(UserGreetingCacheManager.contains(uuid));

            UserGreetingCacheManager.remove(uuid);
            assertFalse(UserGreetingCacheManager.contains(uuid));
        }
    }

    /**
     * getLoginText: キャッシュなしの場合の挙動
     */
    @Test
    void testGetLoginText_WhenNoCacheEntry() {
        UUID testUuid = UUID.randomUUID();
        assertNull(UserGreetingCacheManager.getLoginText(testUuid));
    }

    /**
     * getLoginText: キャッシュが期限切れの場合の挙動
     */
    @Test
    void testGetLoginText_WhenCacheIsExpired() throws Exception {
        UUID testUuid = UUID.randomUUID();
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(0);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getLoginText()).thenReturn("expired");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(testUuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(testUuid);
            Thread.sleep(1500);

            assertNull(UserGreetingCacheManager.getLoginText(testUuid));
        }
    }

    /**
     * getLogoutText: キャッシュなしの場合の挙動
     */
    @Test
    void testGetLogoutText_WhenNoCacheEntry() {
        UUID testUuid = UUID.randomUUID();
        assertNull(UserGreetingCacheManager.getLogoutText(testUuid));
    }

    /**
     * getLogoutText: キャッシュが期限切れの場合の挙動
     */
    @Test
    void testGetLogoutText_WhenCacheIsExpired() throws Exception {
        UUID testUuid = UUID.randomUUID();
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(0);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getLogoutText()).thenReturn("expired");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(testUuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(testUuid);
            Thread.sleep(1500);

            assertNull(UserGreetingCacheManager.getLogoutText(testUuid));
        }
    }

    /**
     * getKickText: キャッシュなしの場合の挙動
     */
    @Test
    void testGetKickText_WhenNoCacheEntry() {
        UUID testUuid = UUID.randomUUID();
        assertNull(UserGreetingCacheManager.getKickText(testUuid));
    }

    /**
     * getKickText: キャッシュが期限切れの場合の挙動
     */
    @Test
    void testGetKickText_WhenCacheIsExpired() throws Exception {
        UUID testUuid = UUID.randomUUID();
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(0);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getKickText()).thenReturn("expired");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(testUuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(testUuid);
            Thread.sleep(1500);

            assertNull(UserGreetingCacheManager.getKickText(testUuid));
        }
    }

    /**
     * getBanText: キャッシュなしの場合の挙動
     */
    @Test
    void testGetBanText_WhenNoCacheEntry() {
        UUID testUuid = UUID.randomUUID();
        assertNull(UserGreetingCacheManager.getBanText(testUuid));
    }

    /**
     * getBanText: キャッシュが期限切れの場合の挙動
     */
    @Test
    void testGetBanText_WhenCacheIsExpired() throws Exception {
        UUID testUuid = UUID.randomUUID();
        configMock.when(ConfigManager::getCacheExpireSeconds).thenReturn(0);

        try (MockedStatic<PlayerRoleDao> daoMock = mockStatic(PlayerRoleDao.class)) {
            when(playerData.getRole()).thenReturn(1);
            when(roleData.getBanText()).thenReturn("expired");
            daoMock.when(() -> PlayerRoleDao.findPlayerByUUID(testUuid)).thenReturn(playerData);
            daoMock.when(() -> PlayerRoleDao.findRoleByRoleId(1)).thenReturn(roleData);

            UserGreetingCacheManager.buildAndCache(testUuid);
            Thread.sleep(1500);

            assertNull(UserGreetingCacheManager.getBanText(testUuid));
        }
    }

}
