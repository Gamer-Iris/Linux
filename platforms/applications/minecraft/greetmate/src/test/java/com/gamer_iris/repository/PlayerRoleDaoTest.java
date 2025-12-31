/*
######################################################################################################################################################
# ファイル   : PlayerRoleDaoTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.repository;

import com.gamer_iris.Main;
import com.gamer_iris.database.DatabaseProvider;
import com.gamer_iris.exception.CriticalException;
import com.gamer_iris.exception.ErrorHandler;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.model.RoleData;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.sql.*;
import java.util.List;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * PlayerRoleDao のユニットテストクラス
 */
class PlayerRoleDaoTest {

    private Connection conn;
    private PreparedStatement stmt;
    private ResultSet rs;
    private UUID uuid;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setup() throws Exception {
        conn = mock(Connection.class);
        stmt = mock(PreparedStatement.class);
        rs = mock(ResultSet.class);
        uuid = UUID.randomUUID();
    }

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testPlayerRoleDaoConstructor_CoverageOnly() {
        new PlayerRoleDao();
    }

    /**
     * UUIDからプレイヤーが見つかる場合
     */
    @Test
    void testFindPlayerByUUID_ReturnsPlayer() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt("id")).thenReturn(1);
        when(rs.getString("player_name")).thenReturn("テストマン");
        when(rs.getInt("role")).thenReturn(2);
        when(rs.getTimestamp("update_time")).thenReturn(new Timestamp(System.currentTimeMillis()));

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            PlayerData data = PlayerRoleDao.findPlayerByUUID(uuid);
            assertNotNull(data);
            assertEquals("テストマン", data.getPlayerName());
        }
    }

    /**
     * UUIDからプレイヤーが見つからない場合
     */
    @Test
    void testFindPlayerByUUID_NotFound() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            PlayerData data = PlayerRoleDao.findPlayerByUUID(uuid);
            assertNull(data);
        }
    }

    /**
     * UUID検索時にSQLExceptionが発生する場合
     */
    @Test
    void testFindPlayerByUUID_SQLException() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorHandlerMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new SQLException("DB Error"));
            errorHandlerMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any()))
                    .thenAnswer(_ -> null);

            PlayerData data = PlayerRoleDao.findPlayerByUUID(uuid);
            assertNull(data);
        }
    }

    /**
     * UUID検索時にCriticalExceptionが発生する場合
     */
    @Test
    void testFindPlayerByUUID_CriticalException() throws Exception {
        UUID uuid = UUID.randomUUID();

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("critical error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            assertNull(PlayerRoleDao.findPlayerByUUID(uuid));
        }
    }

    /**
     * プレイヤーの登録に成功する場合
     */
    @Test
    void testInsertPlayer_Success() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(1);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.insertPlayer(uuid, "TestInsert", 3);
            assertTrue(result);
        }
    }

    /**
     * プレイヤーの登録に失敗する場合
     */
    @Test
    void testInsertPlayer_Failure() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(0);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.insertPlayer(uuid, "Test", 1);
            assertFalse(result);
        }
    }

    /**
     * プレイヤー登録時にSQLExceptionが発生する場合
     */
    @Test
    void testInsertPlayer_SQLException() throws Exception {
        UUID uuid = UUID.randomUUID();
        Connection mockConn = mock(Connection.class);

        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorHandlerMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Insert error"));
            errorHandlerMock.when(() -> ErrorHandler.handleCriticalError(any(), any(), any())).thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.insertPlayer(uuid, "target", 2);
            assertFalse(result);
        }
    }

    /**
     * プレイヤー登録時にCriticalExceptionが発生する場合
     */
    @Test
    void testInsertPlayer_CriticalException() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("DB fail"));
            mainMock.when(Main::getInstance).thenReturn(mock(Main.class));

            boolean result = PlayerRoleDao.insertPlayer(uuid, "X", 1);
            assertFalse(result);
            errorMock.verify(() -> ErrorHandler.handleCriticalError(any(), eq("DB fail"), any()), times(1));
        }
    }

    /**
     * UUID指定でプレイヤー削除に成功する場合
     */
    @Test
    void testDeletePlayerByUUID_Success() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(1);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.deletePlayerByUUID(uuid);
            assertTrue(result);
        }
    }

    /**
     * UUID指定でプレイヤー削除に失敗する場合
     */
    @Test
    void testDeletePlayerByUUID_Failure() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(0);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.deletePlayerByUUID(uuid);
            assertFalse(result);
        }
    }

    /**
     * プレイヤー削除時にSQLExceptionが発生する場合
     */
    @Test
    void testDeletePlayerByUUID_SQLException() throws Exception {
        UUID uuid = UUID.randomUUID();
        Connection mockConn = mock(Connection.class);

        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorHandlerMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Delete error"));
            errorHandlerMock.when(() -> ErrorHandler.handleCriticalError(any(), any(), any())).thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.deletePlayerByUUID(uuid);
            assertFalse(result);
        }
    }

    /**
     * プレイヤー削除時にCriticalExceptionが発生する場合
     */
    @Test
    void testDeletePlayerByUUID_CriticalException() throws Exception {
        UUID uuid = UUID.randomUUID();

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            assertFalse(PlayerRoleDao.deletePlayerByUUID(uuid));
        }
    }

    /**
     * プレイヤーのロール更新に成功する場合
     */
    @Test
    void testUpdatePlayerRoleByUUID_Success() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(1);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.updatePlayerRoleByUUID(uuid, 4);
            assertTrue(result);
        }
    }

    /**
     * プレイヤーのロール更新に失敗する場合
     */
    @Test
    void testUpdatePlayerRoleByUUID_Failure() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(0);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.updatePlayerRoleByUUID(uuid, 4);
            assertFalse(result);
        }
    }

    /**
     * プレイヤーのロール更新時にSQLExceptionが発生する場合
     */
    @Test
    void testUpdatePlayerRoleByUUID_SQLException() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            when(conn.prepareStatement(any())).thenThrow(new SQLException("update failed"));

            logMock.when(() -> LogWriter.writeError(anyString(), any())).thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.updatePlayerRoleByUUID(uuid, 4);
            assertFalse(result);
            logMock.verify(() -> LogWriter.writeError(contains("プレイヤー情報の更新に失敗"), any()), times(1));
        }
    }

    /**
     * プレイヤーのロール更新時にCriticalExceptionが発生する場合
     */
    @Test
    void testUpdatePlayerRoleByUUID_CriticalException() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("critical update error"));
            mainMock.when(Main::getInstance).thenReturn(mock(Main.class));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.updatePlayerRoleByUUID(uuid, 4);
            assertFalse(result);
            errorMock.verify(() -> ErrorHandler.handleCriticalError(any(), eq("critical update error"), any()),
                    times(1));
        }
    }

    /**
     * 指定ロール検証時に該当ロールが存在する場合
     */
    @Test
    void testIsValidRole_ReturnsTrue() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(1);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.isValidRole(2);
            assertTrue(result);
        }
    }

    /**
     * 指定ロール検証時に該当ロールが存在しない場合
     */
    @Test
    void testIsValidRole_ReturnsFalse() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(0);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.isValidRole(99);
            assertFalse(result);
        }
    }

    /**
     * 指定ロール検証時にResultSetが空の場合
     */
    @Test
    void testIsValidRole_ResultSetEmpty() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = PlayerRoleDao.isValidRole(100);
            assertFalse(result);
        }
    }

    /**
     * 指定ロール検証時にSQLExceptionが発生する場合
     */
    @Test
    void testIsValidRole_SQLExceptionThrown() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection)
                    .thenThrow(new SQLException("simulate"));

            logMock.when(() -> LogWriter.writeError(anyString(), any()))
                    .thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.isValidRole(1);
            assertFalse(result);
            logMock.verify(() -> LogWriter.writeError(contains("ロール存在チェックに失敗"), any()), times(1));
        }
    }

    /**
     * 指定ロール検証時にSQLExceptionが発生する場合
     */
    @Test
    void testIsValidRole_SQLException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            Connection mockConn = mock(Connection.class);
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Simulated error"));

            boolean result = PlayerRoleDao.isValidRole(1);
            assertFalse(result);
        }
    }

    /**
     * 指定ロール検証時にCriticalExceptionが発生する場合（パターン①）
     */
    @Test
    void testIsValidRole_CriticalExceptionThrown() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection)
                    .thenThrow(new CriticalException("critical"));

            Main dummyMain = mock(Main.class);
            mainMock.when(Main::getInstance).thenReturn(dummyMain);
            errMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any()))
                    .thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.isValidRole(1);
            assertFalse(result);
            errMock.verify(() -> ErrorHandler.handleCriticalError(any(), anyString(), any()), times(1));
        }
    }

    /**
     * 指定ロール検証時にCriticalExceptionが発生する場合（パターン②）
     */
    @Test
    void testIsValidRole_CriticalException() throws Exception {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {

            dbMock.when(DatabaseProvider::getConnection)
                    .thenThrow(new CriticalException("Critical error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any()))
                    .thenAnswer(_ -> null);

            boolean result = PlayerRoleDao.isValidRole(5);
            assertFalse(result);
        }
    }

    /**
     * ロールIDからRoleDataが取得できる場合
     */
    @Test
    void testFindRoleByRoleId_ReturnsRoleData() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt("id")).thenReturn(10);
        when(rs.getString("role_details")).thenReturn("特別な権限");
        when(rs.getString("login_text")).thenReturn("ようこそ %s");
        when(rs.getString("logout_text")).thenReturn("さようなら %s");
        when(rs.getString("kick_text")).thenReturn("%s がキックされました");
        when(rs.getString("ban_text")).thenReturn("%s がBANされました");
        when(rs.getTimestamp("update_time")).thenReturn(new Timestamp(System.currentTimeMillis()));

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            RoleData role = PlayerRoleDao.findRoleByRoleId(99);
            assertNotNull(role);
            assertEquals("特別な権限", role.getRoleDetails());
        }
    }

    /**
     * ロールIDからRoleDataが見つからない場合
     */
    @Test
    void testFindRoleByRoleId_NotFound() throws Exception {
        Connection conn = mock(Connection.class);
        PreparedStatement stmt = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            assertNull(PlayerRoleDao.findRoleByRoleId(1));
        }
    }

    /**
     * ロール検索時にSQLExceptionが発生する場合
     */
    @Test
    void testFindRoleByRoleId_SQLException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            Connection mockConn = mock(Connection.class);
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Simulated error"));

            assertNull(PlayerRoleDao.findRoleByRoleId(1));
        }
    }

    /**
     * ロール検索時にCriticalExceptionが発生する場合
     */
    @Test
    void testFindRoleByRoleId_CriticalException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            assertNull(PlayerRoleDao.findRoleByRoleId(1));
        }
    }

    /**
     * 全プレイヤー取得に成功する場合
     */
    @Test
    void testGetAllPlayers_ReturnsList() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt("id")).thenReturn(1);
        when(rs.getString("player_name")).thenReturn("P1");
        when(rs.getInt("role")).thenReturn(1);
        when(rs.getString("uuid")).thenReturn(uuid.toString());
        when(rs.getTimestamp("update_time")).thenReturn(new Timestamp(System.currentTimeMillis()));

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            List<PlayerData> players = PlayerRoleDao.getAllPlayers();
            assertEquals(1, players.size());
        }
    }

    /**
     * 全プレイヤー取得時にSQLExceptionが発生する場合
     */
    @Test
    void testGetAllPlayers_SQLException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            Connection mockConn = mock(Connection.class);
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Simulated error"));

            List<PlayerData> result = PlayerRoleDao.getAllPlayers();
            assertNotNull(result);
            assertTrue(result.isEmpty());
        }
    }

    /**
     * 全プレイヤー取得時にCriticalExceptionが発生する場合
     */
    @Test
    void testGetAllPlayers_CriticalException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            List<PlayerData> result = PlayerRoleDao.getAllPlayers();
            assertNotNull(result);
            assertTrue(result.isEmpty());
        }
    }

    /**
     * 非アクティブプレイヤー削除に成功する場合
     */
    @Test
    void testDeleteInactivePlayers_ReturnsCount() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(2);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            int result = PlayerRoleDao.deleteInactivePlayers(30);
            assertEquals(2, result);
        }
    }

    /**
     * 非アクティブプレイヤー削除時にSQLExceptionが発生する場合
     */
    @Test
    void testDeleteInactivePlayers_SQLException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            Connection mockConn = mock(Connection.class);
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Simulated error"));

            int result = PlayerRoleDao.deleteInactivePlayers(30);
            assertEquals(0, result);
        }
    }

    /**
     * 非アクティブプレイヤー削除時にCriticalExceptionが発生する場合
     */
    @Test
    void testDeleteInactivePlayers_CriticalException() throws Exception {
        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("error"));
            errorMock.when(() -> ErrorHandler.handleCriticalError(any(), anyString(), any())).thenAnswer(_ -> null);

            int deleted = PlayerRoleDao.deleteInactivePlayers(30);
            assertEquals(0, deleted);
        }
    }

}
