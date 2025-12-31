/*
######################################################################################################################################################
# ファイル   : UserGreetingCacheManager.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.cache;

import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.model.RoleData;
import com.gamer_iris.repository.PlayerRoleDao;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * プレイヤーごとの挨拶メッセージをキャッシュするマネージャークラス
 */
public class UserGreetingCacheManager {

    private static final Map<UUID, CacheEntry> cache = new ConcurrentHashMap<>();

    /**
     * 有効なキャッシュが存在するかを確認
     * 
     * @param uuid 対象プレイヤーのUUID
     * @return trueならキャッシュが有効
     */
    public static boolean contains(UUID uuid) {
        CacheEntry entry = cache.get(uuid);
        return entry != null && !entry.isExpired();
    }

    /**
     * プレイヤーとロール情報を元に挨拶メッセージを構築しキャッシュへ登録
     * 
     * @param uuid 対象プレイヤーのUUID
     */
    public static void buildAndCache(UUID uuid) {
        PlayerData player = PlayerRoleDao.findPlayerByUUID(uuid);
        if (player == null) {
            LogWriter.writeWarn("[Greetmate] UUIDからプレイヤーが見つかりませんでした: " + uuid);
            return;
        }

        RoleData role = PlayerRoleDao.findRoleByRoleId(player.getRole());
        if (role == null) {
            LogWriter.writeWarn("[Greetmate] ロール情報が見つかりませんでした: role=" + player.getRole());
            return;
        }

        cache.put(uuid,
                new CacheEntry(role.getLoginText(), role.getLogoutText(), role.getKickText(),
                        role.getBanText()));
    }

    /**
     * キャッシュから指定UUIDのエントリを削除
     * 
     * @param uuid 対象プレイヤーのUUID
     */
    public static void remove(UUID uuid) {
        cache.remove(uuid);
    }

    /**
     * ログインメッセージを取得
     * 
     * @param uuid 対象プレイヤーのUUID
     * @return キャッシュが有効な場合はメッセージ 無効ならnull
     */
    public static String getLoginText(UUID uuid) {
        CacheEntry entry = cache.get(uuid);
        return entry != null && !entry.isExpired()
                ? entry.loginText
                : null;
    }

    /**
     * ログアウトメッセージを取得
     * 
     * @param uuid 対象プレイヤーのUUID
     * @return キャッシュが有効な場合はメッセージ 無効ならnull
     */
    public static String getLogoutText(UUID uuid) {
        CacheEntry entry = cache.get(uuid);
        return entry != null && !entry.isExpired()
                ? entry.logoutText
                : null;
    }

    /**
     * キックメッセージを取得
     * 
     * @param uuid 対象プレイヤーのUUID
     * @return キャッシュが有効な場合はメッセージ 無効ならnull
     */
    public static String getKickText(UUID uuid) {
        CacheEntry entry = cache.get(uuid);
        return entry != null && !entry.isExpired()
                ? entry.kickText
                : null;
    }

    /**
     * BANメッセージを取得
     * 
     * @param uuid 対象プレイヤーのUUID
     * @return キャッシュが有効な場合はメッセージ 無効ならnull
     */
    public static String getBanText(UUID uuid) {
        CacheEntry entry = cache.get(uuid);
        return entry != null && !entry.isExpired()
                ? entry.banText
                : null;
    }

    /**
     * 挨拶メッセージとキャッシュ時刻を保持する内部クラス
     */
    private static class CacheEntry {
        final String loginText;
        final String logoutText;
        final String kickText;
        final String banText;
        final long timestamp;

        /**
         * 各種メッセージとタイムスタンプを保持
         * 
         * @param loginText  ログイン時メッセージ
         * @param logoutText ログアウト時メッセージ
         * @param kickText   キック時メッセージ
         * @param banText    BAN時メッセージ
         */
        CacheEntry(String loginText, String logoutText, String kickText, String banText) {
            this.loginText = loginText;
            this.logoutText = logoutText;
            this.kickText = kickText;
            this.banText = banText;
            this.timestamp = System.currentTimeMillis();
        }

        /**
         * キャッシュが有効期限を超えているか判定
         * 
         * @return trueなら期限切れ
         */
        boolean isExpired() {
            long elapsed = (System.currentTimeMillis() - timestamp) / 1000;
            return elapsed > ConfigManager.getCacheExpireSeconds();
        }
    }

}
