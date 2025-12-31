/*
######################################################################################################################################################
# ファイル   : PlayerData.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.model;

import java.util.Date;
import java.util.UUID;

/**
 * プレイヤーの基本情報を持つデータクラス
 */
public class PlayerData {

    private final int id;
    private final String playerName;
    private final int role;
    private final UUID uuid;
    private final Date updateTime;

    /**
     * プレイヤー情報のコンストラクタ
     * 
     * @param id         レコードID
     * @param playerName プレイヤー名
     * @param role       ロールID
     * @param uuid       ユーザーUUID
     * @param updateTime 更新日時
     */
    public PlayerData(int id, String playerName, int role, UUID uuid, Date updateTime) {
        this.id = id;
        this.playerName = playerName;
        this.role = role;
        this.uuid = uuid;
        this.updateTime = updateTime;
    }

    /**
     * レコードIDを取得
     * 
     * @return ID
     */
    public int getId() {
        return id;
    }

    /**
     * プレイヤー名を取得
     * 
     * @return 名前
     */
    public String getPlayerName() {
        return playerName;
    }

    /**
     * ロールIDを取得
     * 
     * @return ロールID
     */
    public int getRole() {
        return role;
    }

    /**
     * ユーザーUUIDを取得
     * 
     * @return UUID
     */
    public UUID getUuid() {
        return uuid;
    }

    /**
     * 更新日時を取得
     * 
     * @return Date
     */
    public Date getUpdateTime() {
        return updateTime;
    }

}
