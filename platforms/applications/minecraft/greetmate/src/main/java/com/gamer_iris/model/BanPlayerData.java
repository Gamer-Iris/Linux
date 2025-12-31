/*
######################################################################################################################################################
# ファイル   : BanPlayerData.java
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
 * BAN登録されたプレイヤーの情報を持つデータクラス
 */
public class BanPlayerData {

    private final int id;
    private final String playerName;
    private final int role;
    private final UUID uuid;
    private final String reason;
    private final Date updateTime;

    /**
     * BAN情報のコンストラクタ
     * 
     * @param id         レコードID
     * @param playerName プレイヤー名
     * @param role       ロールID
     * @param uuid       ユーザーUUID
     * @param reason     BAN理由
     * @param updateTime 更新日時
     */
    public BanPlayerData(int id, String playerName, int role, UUID uuid, String reason, Date updateTime) {
        this.id = id;
        this.playerName = playerName;
        this.role = role;
        this.uuid = uuid;
        this.reason = reason;
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
     * BAN理由を取得
     * 
     * @return 理由
     */
    public String getReason() {
        return reason;
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
