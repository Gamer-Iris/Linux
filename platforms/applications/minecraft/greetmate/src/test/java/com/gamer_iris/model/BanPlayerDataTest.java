/*
######################################################################################################################################################
# ファイル   : BanPlayerDataTest.java
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
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

/**
 * BanPlayerData のユニットテストクラス
 */
class BanPlayerDataTest {

    /**
     * 各getterが正常に値を返す場合
     */
    @Test
    void testBanPlayerData_Getters() {
        UUID uuid = UUID.randomUUID();
        Date now = new Date();
        BanPlayerData data = new BanPlayerData(123, "TestPlayer", 2, uuid, "不適切な発言", now);

        assertEquals(123, data.getId());
        assertEquals("TestPlayer", data.getPlayerName());
        assertEquals(2, data.getRole());
        assertEquals(uuid, data.getUuid());
        assertEquals("不適切な発言", data.getReason());
        assertEquals(now, data.getUpdateTime());
    }

}
