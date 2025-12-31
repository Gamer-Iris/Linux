/*
######################################################################################################################################################
# ファイル   : AdminCommandHandlerTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.command;

import com.gamer_iris.Main;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.repository.BanPlayerDao;
import com.gamer_iris.repository.PlayerRoleDao;
import org.bukkit.Bukkit;
import org.bukkit.OfflinePlayer;
import org.bukkit.Server;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.plugin.PluginManager;
import org.junit.jupiter.api.*;
import org.mockito.MockedStatic;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * AdminCommandHandler のユニットテストクラス
 */
class AdminCommandHandlerTest {

    private static AdminCommandHandler handler;
    private static Command command;
    private static MockedStatic<Main> mainMock;
    private static Player sender;
    private static UUID playerUUID;

    /**
     * グローバルモック設定
     */
    @BeforeAll
    static void beforeAll() {
        mainMock = mockStatic(Main.class);

        Main dummyMain = mock(Main.class);
        Server dummyServer = mock(Server.class);
        PluginManager dummyPluginManager = mock(PluginManager.class);

        when(dummyServer.getPluginManager()).thenReturn(dummyPluginManager);
        when(dummyMain.getServer()).thenReturn(dummyServer);

        mainMock.when(Main::getInstance).thenReturn(dummyMain);
        handler = new AdminCommandHandler();
        sender = mock(Player.class);
        command = mock(Command.class);
        playerUUID = UUID.randomUUID();

        when(sender.getUniqueId()).thenReturn(playerUUID);
    }

    /**
     * モック解放
     */
    @AfterAll
    static void afterAll() {
        mainMock.close();
    }

    /**
     * 未定義のコマンドが実行された場合
     */
    @Test
    void testUnknownCommand_ReturnsFalse() {
        when(command.getName()).thenReturn("unknown");
        assertFalse(handler.onCommand(sender, command, "unknown", new String[] {}));
    }

    /**
     * greetbanコマンドでBAN対象のロールが不正な場合
     */
    @Test
    void testBanCommand_InvalidRole() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(1);

        try (MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class)) {
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetban", new String[] { "a", "b" }));
        }
    }

    /**
     * greetbanコマンドが正常に処理される場合
     */
    @Test
    void testBanCommand_Success() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "targetPlayer", "Bad", "behavior" };
        UUID targetUUID = UUID.randomUUID();
        OfflinePlayer offlineTarget = mock(OfflinePlayer.class);
        when(offlineTarget.getUniqueId()).thenReturn(targetUUID);
        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class);
                MockedStatic<BanPlayerDao> banDao = mockStatic(BanPlayerDao.class);
                MockedStatic<LogWriter> logWriter = mockStatic(LogWriter.class)) {

            bukkitMock.when(() -> Bukkit.getOfflinePlayer("targetPlayer")).thenReturn(offlineTarget);
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(any())).thenReturn(mockData);
            roleDao.when(() -> PlayerRoleDao.deletePlayerByUUID(eq(targetUUID))).thenReturn(true);
            banDao.when(() -> BanPlayerDao.insert(any())).thenAnswer(_ -> null);
            logWriter.when(() -> LogWriter.writeInfo(anyString())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetban", args));
        }
    }

    /**
     * greetbanコマンドで対象プレイヤーが未登録だった場合
     */
    @Test
    void testBanCommand_TargetDataNull() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "targetPlayer", "bad", "behavior" };
        UUID targetUUID = UUID.randomUUID();
        OfflinePlayer offlineTarget = mock(OfflinePlayer.class);
        when(offlineTarget.getUniqueId()).thenReturn(targetUUID);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<BanPlayerDao> ban = mockStatic(BanPlayerDao.class);
                MockedStatic<LogWriter> log = mockStatic(LogWriter.class)) {
            bukkit.when(() -> Bukkit.getOfflinePlayer("targetPlayer")).thenReturn(offlineTarget);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(targetUUID)).thenReturn(null);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(targetUUID)).thenReturn(true);
            ban.when(() -> BanPlayerDao.insert(any())).thenAnswer(_ -> null);
            log.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetban", args));
        }
    }

    /**
     * greetbanコマンドの引数が不足している場合
     */
    @Test
    void testBanCommand_TooFewArgs() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(4);

        try (
                MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class)) {
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetban", new String[] { "a" }));
        }
    }

    /**
     * greetbanコマンドで実行者がパーミッションを持たない場合
     */
    @Test
    void testHandleBan_NoPermission() {
        when(command.getName()).thenReturn("greetban");
        when(sender.hasPermission(anyString())).thenReturn(false);
        assertTrue(handler.onCommand(sender, command, "greetban", new String[] { "target", "reason" }));
    }

    /**
     * greetunbanコマンドで実行者のロールが足りない場合
     */
    @Test
    void testHandleUnban_InsufficientRole() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "targetPlayer" };
        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(2);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);
            assertTrue(handler.onCommand(sender, command, "greetunban", args));
        }
    }

    /**
     * greetunbanコマンドで実行者のロールが不足している場合
     */
    @Test
    void testHandleUnban_InvalidRole() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);
        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(2);

        try (MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class)) {
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);
            assertTrue(handler.onCommand(sender, command, "greetunban", new String[] { "targetPlayer" }));
        }
    }

    /**
     * greetunbanコマンドの引数が不足している場合
     */
    @Test
    void testHandleUnban_TooFewArguments() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(4);

        try (
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);
            assertTrue(handler.onCommand(sender, command, "greetunban", new String[] {}));
        }
    }

    /**
     * greetunbanコマンドで削除に失敗する場合
     */
    @Test
    void testUnbanCommand_DeleteFails() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "targetPlayer" };
        UUID targetUUID = UUID.randomUUID();
        OfflinePlayer offlineTarget = mock(OfflinePlayer.class);
        when(offlineTarget.getUniqueId()).thenReturn(targetUUID);
        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(4);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> roleDaoMock = mockStatic(PlayerRoleDao.class);
                MockedStatic<BanPlayerDao> banDaoMock = mockStatic(BanPlayerDao.class)) {
            bukkitMock.when(() -> Bukkit.getOfflinePlayer("targetPlayer")).thenReturn(offlineTarget);
            roleDaoMock.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);
            banDaoMock.when(() -> BanPlayerDao.delete(targetUUID)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetunban", args));
        }
    }

    /**
     * greetunbanコマンドで実行者がパーミッションを持たない場合
     */
    @Test
    void testUnbanCommand_NoPermission() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(false);
        assertTrue(handler.onCommand(sender, command, "greetunban", new String[] { "targetPlayer" }));
    }

    /**
     * greetunbanコマンドで実行者がPlayerでない場合
     */
    @Test
    void testUnbanCommand_NotPlayerSender() {
        CommandSender nonPlayer = mock(CommandSender.class);
        when(command.getName()).thenReturn("greetunban");
        assertTrue(handler.onCommand(nonPlayer, command, "greetunban", new String[] { "targetPlayer" }));
    }

    /**
     * greetunbanコマンドが正常に処理される場合
     */
    @Test
    void testUnbanCommand_Success() {
        when(command.getName()).thenReturn("greetunban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "targetPlayer" };
        UUID targetUUID = UUID.randomUUID();
        OfflinePlayer offlineTarget = mock(OfflinePlayer.class);
        when(offlineTarget.getUniqueId()).thenReturn(targetUUID);
        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(4);

        try (
                MockedStatic<Bukkit> bukkitMock = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class);
                MockedStatic<BanPlayerDao> banDao = mockStatic(BanPlayerDao.class);
                MockedStatic<LogWriter> logWriter = mockStatic(LogWriter.class)) {

            bukkitMock.when(() -> Bukkit.getOfflinePlayer("targetPlayer")).thenReturn(offlineTarget);
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);
            banDao.when(() -> BanPlayerDao.delete(targetUUID)).thenReturn(true);
            logWriter.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetunban", args));
        }
    }

    /**
     * greetroleコマンドのdelでDELETEに失敗する場合
     */
    @Test
    void testHandleRoleCommand_Delete_FailureToDelete() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        String[] args = { "del", "target" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのdelで正常に処理される場合
     */
    @Test
    void testHandleRoleCommand_Delete_Success() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        String[] args = { "del", "target" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> logWriter = mockStatic(LogWriter.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(true);
            logWriter.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドの引数が不足している場合
     */
    @Test
    void testHandleRoleCommand_MissingSubcommandArgs() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", new String[] {}));
        }
    }

    /**
     * greetroleコマンドで実行者が権限を持っていない場合
     */
    @Test
    void testHandleRoleCommand_NoPermission() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(false);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", new String[] { "set" }));
        }
    }

    /**
     * greetroleコマンドのregisterで既に登録済みの場合
     */
    @Test
    void testHandleRoleCommand_Register_AlreadyExists() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        PlayerData existing = mock(PlayerData.class);

        String[] args = { "register", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existing);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでINSERTに失敗する場合
     */
    @Test
    void testHandleRoleCommand_Register_FailureToInsert() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        String[] args = { "register", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでロール形式が不正な場合
     */
    @Test
    void testHandleRoleCommand_Register_InvalidRoleFormat() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "register", "target", "notAnInt" };

        assertTrue(handler.onCommand(sender, command, "greetrole", args));
    }

    /**
     * greetroleコマンドのregisterで正常に処理される場合
     */
    @Test
    void testHandleRoleCommand_Register_Success() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        String[] args = { "register", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> logWriter = mockStatic(LogWriter.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(true);
            logWriter.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetでINSERTに失敗する場合
     */
    @Test
    void testHandleRoleCommand_Set_InsertFails() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        PlayerData existing = mock(PlayerData.class);
        String[] args = { "set", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existing);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetでロール形式が数値でない場合
     */
    @Test
    void testHandleRoleCommand_Set_InvalidRoleFormat() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "set", "target", "not_a_number" };

        assertTrue(handler.onCommand(sender, command, "greetrole", args));
    }

    /**
     * greetroleコマンドのsetで未登録プレイヤーを対象とした場合
     */
    @Test
    void testHandleRoleCommand_Set_NotRegistered() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        String[] args = { "set", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetで正常に処理される場合
     */
    @Test
    void testHandleRoleCommand_Set_Success() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        PlayerData existing = mock(PlayerData.class);
        String[] args = { "set", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> logWriter = mockStatic(LogWriter.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existing);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(true);
            logWriter.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドの不明なサブコマンドが指定された場合
     */
    @Test
    void testHandleRoleCommand_UnknownSubcommand() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "invalidsub" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(4);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetでロール形式が不正な場合
     */
    @Test
    void testHandleSet_InvalidRoleFormat() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "set", "target", "abc" };

        assertTrue(handler.onCommand(sender, command, "greetrole", args));
    }

    /**
     * greetroleコマンドのsetでロールIDが存在しない場合
     */
    @Test
    void testHandleSet_IsValidRole_EvaluatedFalseBranch() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        String[] args = { "set", "target", "2" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(null);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetで指定プレイヤーが登録されていない場合
     */
    @Test
    void testHandleSet_PlayerNotRegistered() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "set", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetで対象プレイヤーがnullの場合
     */
    @Test
    void testHandleSet_PlayerNull() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "set", "target", "2" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(null);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetで引数が不足している場合
     */
    @Test
    void testHandleSet_TooFewArgs() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", new String[] { "set" }));
        }
    }

    /**
     * greetroleコマンドのsetでロール更新に失敗した場合
     */
    @Test
    void testHandleSet_UpdateFails() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "set", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(3);
        PlayerData targetData = mock(PlayerData.class);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(targetData);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.updatePlayerRoleByUUID(uuid, 2)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetで登録済みかつ削除に失敗する場合
     */
    @Test
    void testHandleSet_UpdateFails_Registered() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");

        PlayerData existing = mock(PlayerData.class);
        String[] args = { "set", "target", "2" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existing);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(false);
            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのsetでロール更新に成功した場合
     */
    @Test
    void testHandleSet_UpdateSuccess() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "set", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(4);
        PlayerData targetData = mock(PlayerData.class);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> log = mockStatic(LogWriter.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(targetData);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.updatePlayerRoleByUUID(uuid, 2)).thenReturn(true);
            log.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * handleRegisterで既に登録済みのプレイヤーが指定された場合
     */
    @Test
    void testHandleRegister_AlreadyExists() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData existing = mock(PlayerData.class);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(existing);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでinsertPlayerがfalseを返す場合（カバレッジ用）
     */
    @Test
    void testHandleRegister_InsertFails_Cover() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(false);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでプレイヤー登録に成功した場合
     */
    @Test
    void testHandleRegister_InsertSuccess() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "2" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(4);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> log = mockStatic(LogWriter.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(uuid)).thenReturn(null);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);
            dao.when(() -> PlayerRoleDao.insertPlayer(uuid, "target", 2)).thenReturn(true);
            log.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでロール形式が不正な場合
     */
    @Test
    void testHandleRegister_InvalidRoleFormat() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "notNumber" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(4);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            Player target = mock(Player.class);
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterで対象プレイヤーがnullの場合
     */
    @Test
    void testHandleRegister_PlayerNull() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "2" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(4);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(null);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterでプレイヤーが取得できなかった場合
     */
    @Test
    void testHandleRegister_PlayerIsNull() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "register", "target", "2" };

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(null);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.isValidRole(2)).thenReturn(true);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのregisterで引数が不足している場合
     */
    @Test
    void testHandleRegister_TooFewArgs() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", new String[] { "register" }));
        }
    }

    /**
     * greetroleコマンドのdelで削除に失敗する場合
     */
    @Test
    void testHandleDelete_DeleteFails() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);
        when(target.getName()).thenReturn("target");
        String[] args = { "del", "target" };

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(false);

            PlayerData executorData = mock(PlayerData.class);
            when(executorData.getRole()).thenReturn(3);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのdelでプレイヤー情報削除に成功した場合
     */
    @Test
    void testHandleDelete_DeleteSuccess() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "del", "target" };

        Player target = mock(Player.class);
        UUID uuid = UUID.randomUUID();
        when(target.getUniqueId()).thenReturn(uuid);

        PlayerData executorData = mock(PlayerData.class);
        when(executorData.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class);
                MockedStatic<LogWriter> log = mockStatic(LogWriter.class)) {

            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(executorData);
            dao.when(() -> PlayerRoleDao.deletePlayerByUUID(uuid)).thenReturn(true);
            log.when(() -> LogWriter.writeInfo(any())).thenAnswer(_ -> null);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのdelで対象プレイヤーがnullの場合
     */
    @Test
    void testHandleDelete_PlayerNull() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        String[] args = { "del", "target" };

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (
                MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class);
                MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(null);
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);

            assertTrue(handler.onCommand(sender, command, "greetrole", args));
        }
    }

    /**
     * greetroleコマンドのdelで引数が不足している場合
     */
    @Test
    void testHandleDelete_TooFewArgs() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData data = mock(PlayerData.class);
        when(data.getRole()).thenReturn(3);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(data);
            assertTrue(handler.onCommand(sender, command, "greetrole", new String[] { "del" }));
        }
    }

    /**
     * greetroleコマンドで実行者がパーミッションを持たない場合
     */
    @Test
    void testHasPermission_False() {
        CommandSender noPerm = mock(CommandSender.class);
        when(noPerm.hasPermission(anyString())).thenReturn(false);
        when(command.getName()).thenReturn("greetrole");
        assertTrue(handler.onCommand(noPerm, command, "greetrole", new String[] { "set" }));
    }

    /**
     * 実行者がPlayerでない場合
     */
    @Test
    void testValidatePlayerSender_NotPlayer() {
        CommandSender consoleSender = mock(CommandSender.class);
        when(command.getName()).thenReturn("greetban");
        assertTrue(handler.onCommand(consoleSender, command, "greetban", new String[] { "a", "b" }));
    }

    /**
     * greetbanコマンドでプレイヤーデータがnullの場合
     */
    @Test
    void testHasRequiredRole_DataNull() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        try (MockedStatic<PlayerRoleDao> dao = mockStatic(PlayerRoleDao.class)) {
            dao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(null);
            assertTrue(handler.onCommand(sender, command, "greetban", new String[] { "a", "b" }));
        }
    }

    /**
     * greetbanコマンドで実行者のロールが無効な場合
     */
    @Test
    void testHasRequiredRole_FailsWithInvalidRole() {
        when(command.getName()).thenReturn("greetban");
        when(sender.getUniqueId()).thenReturn(playerUUID);
        when(sender.hasPermission(anyString())).thenReturn(true);

        PlayerData mockData = mock(PlayerData.class);
        when(mockData.getRole()).thenReturn(999);

        try (MockedStatic<PlayerRoleDao> roleDao = mockStatic(PlayerRoleDao.class)) {
            roleDao.when(() -> PlayerRoleDao.findPlayerByUUID(playerUUID)).thenReturn(mockData);

            assertTrue(handler.onCommand(sender, command, "greetban", new String[] { "target", "reason" }));
        }
    }

    /**
     * greetroleコマンドの引数が不足している場合
     */
    @Test
    void testValidateArgsLength_TooFew() {
        when(command.getName()).thenReturn("greetrole");
        when(sender.hasPermission(anyString())).thenReturn(true);
        assertTrue(handler.onCommand(sender, command, "greetrole", new String[] {}));
    }

    /**
     * getPlayerOrAbortでプレイヤーが正常に取得できる場合
     */
    @Test
    void testGetPlayerOrAbort_Success() {
        Player target = mock(Player.class);

        try (MockedStatic<Bukkit> bukkit = mockStatic(Bukkit.class)) {
            bukkit.when(() -> Bukkit.getPlayerExact("target")).thenReturn(target);
            assertNotNull(handler.getPlayerOrAbort(sender, "target"));
        }
    }

}
