/*
######################################################################################################################################################
# ファイル   : DatabaseProviderTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.database;

import com.gamer_iris.exception.CriticalException;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;
import java.sql.Connection;
import java.sql.DriverManager;
import static com.github.stefanbirkner.systemlambda.SystemLambda.withEnvironmentVariable;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;

/**
 * DatabaseProvider のユニットテストクラス
 */
class DatabaseProviderTest {

    /**
     * コンストラクタのカバレッジ確認
     */
    @Test
    void testDatabaseProviderConstructor_CoverageOnly() {
        new DatabaseProvider();
    }

    /**
     * JDBCドライバが見つからない場合に初期化で例外が発生する場合
     */
    @Test
    void testStaticInitializer_ThrowsException_WhenDriverNotFound() throws Exception {
        assertThrows(ExceptionInInitializerError.class, () -> {
            URL[] urls = { new File("target/classes/").toURI().toURL() };
            try (URLClassLoader testClassLoader = new URLClassLoader(urls, null)) {
                Class.forName("com.gamer_iris.database.DatabaseProvider", true, testClassLoader);
            }
        });
    }

    /**
     * 環境変数が正しく設定されている場合に接続が成功する場合
     */
    @Test
    void testGetConnection_Success() throws Exception {
        Connection mockConn = mock(Connection.class);

        try (MockedStatic<DriverManager> dmMock = mockStatic(DriverManager.class)) {
            dmMock.when(() -> DriverManager.getConnection(any(), any(), any())).thenReturn(mockConn);

            withEnvironmentVariable("MINECRAFT_DB_URL", "jdbc:mariadb://localhost/test")
                    .and("MINECRAFT_DB_USER", "user")
                    .and("MINECRAFT_DB_PASSWORD", "pass")
                    .execute(() -> {
                        Connection conn = DatabaseProvider.getConnection();
                        assertNotNull(conn);
                        assertEquals(mockConn, conn);
                    });
        }
    }

    /**
     * DB接続環境変数（URL）が未設定の場合
     */
    @Test
    void testGetConnection_ThrowsException_WhenEnvMissing() throws Exception {
        withEnvironmentVariable("MINECRAFT_DB_URL", null)
                .and("MINECRAFT_DB_USER", "user")
                .and("MINECRAFT_DB_PASSWORD", "pass")
                .execute(() -> {
                    CriticalException ex = assertThrows(CriticalException.class, DatabaseProvider::getConnection);
                    assertTrue(ex.getMessage().contains("DB接続情報"));
                });
    }

    /**
     * DB接続環境変数（ユーザ名）が未設定の場合
     */
    @Test
    void testGetConnection_ThrowsException_WhenUserEnvMissing() throws Exception {
        withEnvironmentVariable("MINECRAFT_DB_URL", "jdbc:mariadb://localhost/test")
                .and("MINECRAFT_DB_USER", null)
                .and("MINECRAFT_DB_PASSWORD", "pass")
                .execute(() -> {
                    CriticalException ex = assertThrows(CriticalException.class, DatabaseProvider::getConnection);
                    assertTrue(ex.getMessage().contains("DB接続情報"));
                });
    }

    /**
     * DB接続環境変数（パスワード）が未設定の場合
     */
    @Test
    void testGetConnection_ThrowsException_WhenPasswordEnvMissing() throws Exception {
        withEnvironmentVariable("MINECRAFT_DB_URL", "jdbc:mariadb://localhost/test")
                .and("MINECRAFT_DB_USER", "user")
                .and("MINECRAFT_DB_PASSWORD", null)
                .execute(() -> {
                    CriticalException ex = assertThrows(CriticalException.class, DatabaseProvider::getConnection);
                    assertTrue(ex.getMessage().contains("DB接続情報"));
                });
    }

}
