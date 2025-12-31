/*
######################################################################################################################################################
# ファイル   : RoleDataTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.model;

import org.junit.jupiter.api.Test;
import java.util.Date;
import static org.junit.jupiter.api.Assertions.*;

/**
 * RoleData のユニットテストクラス
 */
class RoleDataTest {

    /**
     * 各getterが正常に値を返す場合
     */
    @Test
    void testRoleData_Getters() {
        Date now = new Date();
        RoleData data = new RoleData(
                1,
                3,
                "管理者",
                "ようこそ %s さん！",
                "またね %s！",
                "%s はキックされました",
                "%s がBANされました",
                now);

        assertEquals(1, data.getId());
        assertEquals(3, data.getRole());
        assertEquals("管理者", data.getRoleDetails());
        assertEquals("ようこそ %s さん！", data.getLoginText());
        assertEquals("またね %s！", data.getLogoutText());
        assertEquals("%s はキックされました", data.getKickText());
        assertEquals("%s がBANされました", data.getBanText());
        assertEquals(now, data.getUpdateTime());
    }

}
