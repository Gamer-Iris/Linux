/*
######################################################################################################################################################
# ファイル   : DatabaseProvider.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.database;

import com.gamer_iris.exception.CriticalException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * DB接続を確立するプロバイダークラス
 */
public class DatabaseProvider {

    /**
     * クラス初期化時にJDBCドライバをロード
     */
    static {
        loadDriver();
    }

    /**
     * DB接続用のConnectionを取得
     * 
     * @return JDBC Connection実体
     * @throws SQLException JDBC接続失敗時
     */
    public static Connection getConnection() throws SQLException {
        String url = System.getenv("MINECRAFT_DB_URL");
        String user = System.getenv("MINECRAFT_DB_USER");
        String pass = System.getenv("MINECRAFT_DB_PASSWORD");

        if (url == null || user == null || pass == null) {
            throw new CriticalException("DB接続情報（URL/USER/PASSWORD）が環境変数に設定されていません。");
        }

        return DriverManager.getConnection(url, user, pass);
    }

    /**
     * JDBCドライバのロードを実行
     */
    private static void loadDriver() {
        try {
            Class.forName("org.mariadb.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            throw new CriticalException("JDBCドライバのロードに失敗しました。", e);
        }
    }

}
