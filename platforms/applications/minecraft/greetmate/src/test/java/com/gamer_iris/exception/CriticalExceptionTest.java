/*
######################################################################################################################################################
# ファイル   : CriticalExceptionTest.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.exception;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

/**
 * CriticalException のユニットテストクラス
 */
class CriticalExceptionTest {

    /**
     * メッセージのみを指定して例外を生成する場合
     */
    @Test
    void testConstructor_WithMessage() {
        String msg = "重大な問題が発生しました";
        CriticalException ex = new CriticalException(msg);

        assertEquals(msg, ex.getMessage());
        assertNull(ex.getCause());
    }

    /**
     * メッセージと原因を指定して例外を生成する場合
     */
    @Test
    void testConstructor_WithMessageAndCause() {
        String msg = "データベース接続失敗";
        Throwable cause = new RuntimeException("詳細な原因");
        CriticalException ex = new CriticalException(msg, cause);

        assertEquals(msg, ex.getMessage());
        assertEquals(cause, ex.getCause());
    }

}
