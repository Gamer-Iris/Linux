/*
######################################################################################################################################################
# ファイル   : PlayerDataTest.java
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
 * PlayerData のユニットテストクラス
 */
class PlayerDataTest {

    /**
     * 各getterが正常に値を返す場合
     */
    @Test
    void testPlayerData_Getters() {
        UUID uuid = UUID.randomUUID();
        Date now = new Date();
        PlayerData data = new PlayerData(456, "SomePlayer", 1, uuid, now);

        assertEquals(456, data.getId());
        assertEquals("SomePlayer", data.getPlayerName());
        assertEquals(1, data.getRole());
        assertEquals(uuid, data.getUuid());
        assertEquals(now, data.getUpdateTime());
    }

}
