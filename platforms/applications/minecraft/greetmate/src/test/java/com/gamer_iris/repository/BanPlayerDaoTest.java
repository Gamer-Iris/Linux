/*
######################################################################################################################################################
# ファイル   : BanPlayerDaoTest.java
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
import com.gamer_iris.model.BanPlayerData;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.sql.*;
import java.util.Date;
import java.util.List;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * BanPlayerDao のユニットテストクラス
 */
class BanPlayerDaoTest {

    private Connection conn;
    private PreparedStatement stmt;
    private ResultSet rs;
    private UUID uuid;
    private BanPlayerData banData;

    /**
     * 各テスト前の初期化処理
     */
    @BeforeEach
    void setup() throws Exception {
        conn = mock(Connection.class);
        stmt = mock(PreparedStatement.class);
        rs = mock(ResultSet.class);
        uuid = UUID.randomUUID();
        banData = new BanPlayerData(1, "BannedPlayer", 2, uuid, "TestReason", new Date());
    }

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testBanPlayerDaoConstructor_CoverageOnly() {
        new BanPlayerDao();
    }

    /**
     * BAN情報を全件取得できる場合
     */
    @Test
    void testGetAll_ReturnsList() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt("id")).thenReturn(banData.getId());
        when(rs.getString("player_name")).thenReturn(banData.getPlayerName());
        when(rs.getInt("role")).thenReturn(banData.getRole());
        when(rs.getString("uuid")).thenReturn(banData.getUuid().toString());
        when(rs.getString("reason")).thenReturn(banData.getReason());
        when(rs.getTimestamp("update_time")).thenReturn(new Timestamp(banData.getUpdateTime().getTime()));

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            List<BanPlayerData> result = BanPlayerDao.getAll();
            assertEquals(1, result.size());
            assertEquals("BannedPlayer", result.get(0).getPlayerName());
        }
    }

    /**
     * BAN情報取得時にCriticalExceptionが発生する場合
     */
    @Test
    void testGetAll_CriticalException() {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("getAll failed"));
            mainMock.when(Main::getInstance).thenReturn(mock(Main.class));

            List<BanPlayerData> result = BanPlayerDao.getAll();
            assertNotNull(result);
            assertTrue(result.isEmpty());

            errorMock.verify(() -> ErrorHandler.handleCriticalError(any(), eq("getAll failed"), any()), times(1));
        }
    }

    /**
     * BAN情報取得時にSQLExceptionが発生する場合
     */
    @Test
    void testGetAll_SQLException() {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new SQLException("DB error"));

            List<BanPlayerData> result = BanPlayerDao.getAll();
            assertNotNull(result);
            assertTrue(result.isEmpty());

            logMock.verify(() -> LogWriter.writeError(contains("BAN情報の取得に失敗しました。"), any()), times(1));
        }
    }

    /**
     * BAN情報を正常に登録できる場合
     */
    @Test
    void testInsert_Success() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(1);

        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);

            BanPlayerDao.insert(banData);

            verify(stmt).executeUpdate();
            logMock.verify(() -> LogWriter.writeInfo(contains("BANプレイヤーを登録")), times(1));
        }
    }

    /**
     * BAN情報登録時にCriticalExceptionが発生する場合
     */
    @Test
    void testInsert_CriticalException() {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("DB fail"));
            mainMock.when(Main::getInstance).thenReturn(mock(Main.class));

            BanPlayerDao.insert(banData);
            errorMock.verify(() -> ErrorHandler.handleCriticalError(any(), eq("DB fail"), any()), times(1));
        }
    }

    /**
     * BAN情報登録時にSQLExceptionが発生する場合
     */
    @Test
    void testInsert_SQLException() throws Exception {
        Connection mockConn = mock(Connection.class);

        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(mockConn);
            when(mockConn.prepareStatement(any())).thenThrow(new SQLException("Statement failed"));

            BanPlayerDao.insert(banData);
            logMock.verify(() -> LogWriter.writeError(contains("BANプレイヤーの登録に失敗しました。"), any()), times(1));
        }
    }

    /**
     * BAN情報を正常に削除できる場合
     */
    @Test
    void testDelete_ReturnsTrue() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(1);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = BanPlayerDao.delete(uuid);
            assertTrue(result);
        }
    }

    /**
     * BAN情報の削除で影響行が0件だった場合
     */
    @Test
    void testDelete_ReturnsFalseWhenNoRowsAffected() throws Exception {
        when(conn.prepareStatement(any())).thenReturn(stmt);
        when(stmt.executeUpdate()).thenReturn(0);

        try (MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = BanPlayerDao.delete(uuid);
            assertFalse(result);
        }
    }

    /**
     * BAN情報削除時にCriticalExceptionが発生する場合
     */
    @Test
    void testDelete_CriticalException_ReturnsFalse() {
        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<ErrorHandler> errorMock = mockStatic(ErrorHandler.class);
                MockedStatic<Main> mainMock = mockStatic(Main.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenThrow(new CriticalException("delete failed"));
            mainMock.when(Main::getInstance).thenReturn(mock(Main.class));

            boolean result = BanPlayerDao.delete(uuid);
            assertFalse(result);
            errorMock.verify(() -> ErrorHandler.handleCriticalError(any(), eq("delete failed"), any()), times(1));
        }
    }

    /**
     * BAN情報削除時にSQLExceptionが発生する場合
     */
    @Test
    void testDelete_SQLException_ReturnsFalse() throws Exception {
        when(conn.prepareStatement(any())).thenThrow(new SQLException("fail"));

        try (
                MockedStatic<DatabaseProvider> dbMock = mockStatic(DatabaseProvider.class);
                MockedStatic<LogWriter> logMock = mockStatic(LogWriter.class)) {
            dbMock.when(DatabaseProvider::getConnection).thenReturn(conn);
            boolean result = BanPlayerDao.delete(uuid);
            assertFalse(result);
            logMock.verify(() -> LogWriter.writeError(contains("BANプレイヤーの削除に失敗"), any()), times(1));
        }
    }

}
