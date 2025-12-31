/*
######################################################################################################################################################
# ファイル   : Main.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris;

import com.gamer_iris.command.AdminCommandHandler;
import com.gamer_iris.config.ConfigManager;
import com.gamer_iris.listener.PlayerEventListener;
import com.gamer_iris.logging.LogRotator;
import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.maintenance.MaintenanceScheduler;
import com.gamer_iris.exception.CriticalException;
import com.gamer_iris.exception.ErrorHandler;
import org.bukkit.plugin.java.JavaPlugin;

/**
 * Greetmate のエントリーポイントクラス
 */
public class Main extends JavaPlugin {

    private static Main instance;

    /**
     * プラグイン有効化時に実行される初期化処理
     */
    @Override
    public void onEnable() {
        instance = this;
        getLogger().info("プラグインを有効化しています...");
        LogWriter.writeInfo("[Greetmate] プラグインを有効化しています...");

        try {
            ConfigManager.init(this);
        } catch (CriticalException e) {
            ErrorHandler.handleCriticalError(this, e.getMessage(), e);
            return;
        }

        LogRotator.start();
        MaintenanceScheduler.start();

        registerListeners();
        registerCommands();

        getLogger().info("プラグインが正常に有効化されました。");
        LogWriter.writeInfo("[Greetmate] プラグインが正常に有効化されました。");
    }

    /**
     * プラグイン無効化時の処理
     */
    @Override
    public void onDisable() {
        getLogger().info("プラグインを無効化しました。");
        LogWriter.writeInfo("[Greetmate] プラグインを無効化しました。");
    }

    /**
     * シングルトンで使用する Main インスタンスを取得
     * 
     * @return Main クラス実体
     */
    public static Main getInstance() {
        return instance;
    }

    /**
     * プレイヤーのイベントリスナを登録
     */
    private void registerListeners() {
        getServer().getPluginManager().registerEvents(new PlayerEventListener(), this);
    }

    /**
     * コマンドハンドラを登録
     */
    private void registerCommands() {
        getCommand("greetban").setExecutor(new AdminCommandHandler());
        getCommand("greetrole").setExecutor(new AdminCommandHandler());
        getCommand("greetunban").setExecutor(new AdminCommandHandler());
    }

}
