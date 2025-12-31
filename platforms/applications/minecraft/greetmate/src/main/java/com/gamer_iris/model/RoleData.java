/*
######################################################################################################################################################
# ファイル   : RoleData.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.model;

import java.util.Date;

/**
 * ロールに関連する表示文や情報を持つデータクラス
 */
public class RoleData {

    private final int id;
    private final int role;
    private final String roleDetails;
    private final String loginText;
    private final String logoutText;
    private final String kickText;
    private final String banText;
    private final Date updateTime;

    /**
     * RoleData のコンストラクタ
     * 
     * @param id          レコードID
     * @param role        ロールID
     * @param roleDetails ロール説明
     * @param loginText   ログイン時文字列
     * @param logoutText  ログアウト時文字列
     * @param kickText    キック時文字列
     * @param banText     BAN時文字列
     * @param updateTime  更新日時
     */
    public RoleData(int id, int role, String roleDetails, String loginText, String logoutText, String kickText,
            String banText,
            Date updateTime) {
        this.id = id;
        this.role = role;
        this.roleDetails = roleDetails;
        this.loginText = loginText;
        this.logoutText = logoutText;
        this.kickText = kickText;
        this.banText = banText;
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
     * ロールIDを取得
     * 
     * @return ロールID
     */
    public int getRole() {
        return role;
    }

    /**
     * ロール説明を取得
     * 
     * @return 説明文字列
     */
    public String getRoleDetails() {
        return roleDetails;
    }

    /**
     * ログイン時文字列を取得
     * 
     * @return 文字列
     */
    public String getLoginText() {
        return loginText;
    }

    /**
     * ログアウト時文字列を取得
     * 
     * @return 文字列
     */
    public String getLogoutText() {
        return logoutText;
    }

    /**
     * キック時文字列を取得
     * 
     * @return 文字列
     */
    public String getKickText() {
        return kickText;
    }

    /**
     * BAN時文字列を取得
     * 
     * @return 文字列
     */
    public String getBanText() {
        return banText;
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
