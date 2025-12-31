/*
######################################################################################################################################################
# ファイル   : PlayerRoleDao.java
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
import java.sql.*;
import java.util.*;
import java.util.Date;

/**
 * プレイヤーとロールのDB操作を担当するDAOクラス
 */
public class PlayerRoleDao {

    private static final String PLAYER_TABLE = "players";
    private static final String ROLE_TABLE = "roles";

    /**
     * UUID指定でプレイヤー情報を取得
     * 
     * @param uuid ユーザーUUID
     * @return PlayerData 実体
     */
    public static PlayerData findPlayerByUUID(UUID uuid) {
        String sql = "SELECT id, player_name, role, uuid, update_time FROM " + PLAYER_TABLE + " WHERE uuid = ?";
        Connection conn = null;
        PreparedStatement stmt = null;
        ResultSet rs = null;

        try {
            conn = DatabaseProvider.getConnection();
            stmt = conn.prepareStatement(sql);
            stmt.setString(1, uuid.toString());
            rs = stmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                String name = rs.getString("player_name");
                int role = rs.getInt("role");
                Date updateTime = rs.getTimestamp("update_time");

                return new PlayerData(id, name, role, uuid, updateTime);

            }
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return null;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] プレイヤー情報の取得に失敗しました。", e);
            return null;
        }

        return null;
    }

    /**
     * プレイヤー情報を新規登録
     * 
     * @param uuid       ユーザーUUID
     * @param playerName プレイヤー名
     * @param role       ロールID
     * @return 成功した場合true
     */
    public static boolean insertPlayer(UUID uuid, String playerName, int role) {
        String sql = "INSERT INTO " + PLAYER_TABLE + " (player_name, role, uuid, update_time) VALUES (?, ?, ?, ?)";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setString(1, playerName);
            stmt.setInt(2, role);
            stmt.setString(3, uuid.toString());
            stmt.setTimestamp(4, new Timestamp(System.currentTimeMillis()));

            return stmt.executeUpdate() > 0;
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return false;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] プレイヤー登録に失敗しました。", e);
            return false;
        }
    }

    /**
     * UUID指定でプレイヤーを削除
     * 
     * @param uuid ユーザーUUID
     * @return 成功した場合true
     */
    public static boolean deletePlayerByUUID(UUID uuid) {
        String sql = "DELETE FROM " + PLAYER_TABLE + " WHERE uuid = ?";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setString(1, uuid.toString());
            return stmt.executeUpdate() > 0;
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] プレイヤー削除に失敗しました。", e);
        }

        return false;
    }

    /**
     * UUIDでプレイヤーのロールを更新
     * 
     * @param uuid ユーザーUUID
     * @param role ロールID
     * @return 成功した場合true
     */
    public static boolean updatePlayerRoleByUUID(UUID uuid, int role) {
        String sql = "UPDATE " + PLAYER_TABLE + " SET role = ?, update_time = ? WHERE uuid = ?";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setInt(1, role);
            stmt.setTimestamp(2, new Timestamp(System.currentTimeMillis()));
            stmt.setString(3, uuid.toString());

            return stmt.executeUpdate() > 0;
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return false;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] プレイヤー情報の更新に失敗しました。", e);
            return false;
        }
    }

    /**
     * roleID指定でロール情報を取得
     * 
     * @param roleId ロールID
     * @return RoleData 実体
     */
    public static RoleData findRoleByRoleId(int roleId) {
        String sql = "SELECT id, role, role_details, login_text, logout_text, kick_text, ban_text, update_time FROM "
                + ROLE_TABLE
                + " WHERE role = ?";

        Connection conn = null;
        PreparedStatement stmt = null;
        ResultSet rs = null;

        try {
            conn = DatabaseProvider.getConnection();
            stmt = conn.prepareStatement(sql);
            stmt.setInt(1, roleId);
            rs = stmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                String details = rs.getString("role_details");
                String login = rs.getString("login_text");
                String logout = rs.getString("logout_text");
                String kick = rs.getString("kick_text");
                String ban = rs.getString("ban_text");
                Date updateTime = rs.getTimestamp("update_time");

                return new RoleData(id, roleId, details, login, logout, kick, ban, updateTime);
            }
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return null;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] ロール情報の取得に失敗しました。", e);
            return null;
        }

        return null;
    }

    /**
     * すべてのプレイヤー情報を取得
     * 
     * @return PlayerData 一覧
     */
    public static List<PlayerData> getAllPlayers() {
        List<PlayerData> players = new ArrayList<>();
        String sql = "SELECT id, player_name, role, uuid, update_time FROM " + PLAYER_TABLE;

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql);
                ResultSet rs = stmt.executeQuery()) {

            while (rs.next()) {
                int id = rs.getInt("id");
                String name = rs.getString("player_name");
                int role = rs.getInt("role");
                UUID uuid = UUID.fromString(rs.getString("uuid"));
                Date updateTime = rs.getTimestamp("update_time");

                players.add(new PlayerData(id, name, role, uuid, updateTime));
            }
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return players;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] プレイヤー一覧の取得に失敗しました。", e);
            return players;
        }

        return players;
    }

    /**
     * 指定されたロールIDがrolesテーブルに存在するか検証
     * 
     * @param roleId 検証対象のロールID
     * @return 存在すればtrue、存在しなければfalse
     */
    public static boolean isValidRole(int roleId) {
        String sql = "SELECT COUNT(*) FROM " + ROLE_TABLE + " WHERE role = ?";
        try (
                Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, roleId);
            ResultSet rs = stmt.executeQuery();
            boolean result = false;
            if (rs.next()) {
                result = rs.getInt(1) > 0;
            }
            rs.close();
            return result;
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] ロール存在チェックに失敗しました。", e);
        }
        return false;
    }

    /**
     * 指定日数より最終更新が早いプレイヤーを削除
     * 
     * @param thresholdDays 利用終了間阅する間隔日数
     * @return 削除件数
     */
    public static int deleteInactivePlayers(int thresholdDays) {
        String sql = "DELETE FROM " + PLAYER_TABLE + " WHERE update_time < NOW() - INTERVAL ? DAY";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setInt(1, thresholdDays);
            return stmt.executeUpdate();
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return 0;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] 古いプレイヤーデータの削除に失敗しました。", e);
            return 0;
        }
    }

}
