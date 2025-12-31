/*
######################################################################################################################################################
# ファイル   : BanPlayerDao.java
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
import com.gamer_iris.model.BanPlayerData;
import com.gamer_iris.logging.LogWriter;
import java.sql.*;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.UUID;

/**
 * BAN登録プレイヤーのDB操作を担当するDAOクラス
 */
public class BanPlayerDao {

    private static final String TABLE_NAME = "ban_players";

    /**
     * すべてのBANプレイヤー情報を取得
     * 
     * @return BANデータリスト
     */
    public static List<BanPlayerData> getAll() {
        List<BanPlayerData> result = new ArrayList<>();

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(
                        "SELECT id, player_name, role, uuid, reason, update_time FROM " + TABLE_NAME);
                ResultSet rs = stmt.executeQuery()) {

            while (rs.next()) {
                int id = rs.getInt("id");
                String name = rs.getString("player_name");
                int role = rs.getInt("role");
                UUID uuid = UUID.fromString(rs.getString("uuid"));
                String reason = rs.getString("reason");
                Date updateTime = rs.getTimestamp("update_time");

                result.add(new BanPlayerData(id, name, role, uuid, reason, updateTime));
            }
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return result;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] BAN情報の取得に失敗しました。", e);
            return result;
        }

        return result;
    }

    /**
     * BANプレイヤー情報をDBへ登録
     * 
     * @param ban 登録対象のBANデータ
     */
    public static void insert(BanPlayerData ban) {
        String sql = "INSERT INTO " + TABLE_NAME
                + " (player_name, role, uuid, reason, update_time) VALUES (?, ?, ?, ?, ?)";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setString(1, ban.getPlayerName());
            stmt.setInt(2, ban.getRole());
            stmt.setString(3, ban.getUuid().toString());
            stmt.setString(4, ban.getReason());
            stmt.setTimestamp(5, new Timestamp(ban.getUpdateTime().getTime()));
            stmt.executeUpdate();

            LogWriter.writeInfo("[Greetmate] BANプレイヤーを登録: " + ban.getPlayerName());
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] BANプレイヤーの登録に失敗しました。", e);
            return;
        }

        return;
    }

    /**
     * UUID指定でBANプレイヤーをDBから削除
     * 
     * @param uuid BANプレイヤーUUID
     * @return 削除された場合true
     */
    public static boolean delete(UUID uuid) {
        String sql = "DELETE FROM " + TABLE_NAME + " WHERE uuid = ?";

        try (Connection conn = DatabaseProvider.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setString(1, uuid.toString());
            int affected = stmt.executeUpdate();
            return affected > 0;
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(Main.getInstance(), e.getMessage(), e);
            return false;
        } catch (SQLException e) {
            LogWriter.writeError("[Greetmate] BANプレイヤーの削除に失敗しました。", e);
            return false;
        }
    }

}
