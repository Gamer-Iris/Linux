/*
######################################################################################################################################################
# ファイル   : AdminCommandHandler.java
# 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# [修正履歴]
# V-001      : 2026/01/01                 Gamer-Iris   新規作成
# 
######################################################################################################################################################
*/
package com.gamer_iris.command;

import com.gamer_iris.logging.LogWriter;
import com.gamer_iris.model.BanPlayerData;
import com.gamer_iris.model.PlayerData;
import com.gamer_iris.repository.BanPlayerDao;
import com.gamer_iris.repository.PlayerRoleDao;
import org.bukkit.Bukkit;
import org.bukkit.OfflinePlayer;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import java.util.Date;
import java.util.Map;
import java.util.UUID;
import java.util.function.BiFunction;

/**
 * プレイヤー向け管理系コマンドを処理するハンドラークラス
 */
public class AdminCommandHandler implements CommandExecutor {

    private final Map<String, BiFunction<CommandSender, String[], Boolean>> commandHandlers = Map.of(
            "greetban", this::handleBan,
            "greetunban", this::handleUnban,
            "greetrole", this::handleRoleCommand);

    /**
     * 有効なコマンド名に対応した処理を分岐
     * 
     * @param sender  コマンド実行者
     * @param command 実行されたコマンド
     * @param label   入力されたラベル
     * @param args    引数
     * @return 処理した場合true
     */
    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        String cmd = command.getName().toLowerCase();
        return commandHandlers.getOrDefault(cmd, (_, _) -> false).apply(sender, args);
    }

    /**
     * 指定したプレイヤーをBAN登録
     * 
     * @param sender 実行者
     * @param args   引数
     * @return trueを返す
     */
    private boolean handleBan(CommandSender sender, String[] args) {
        Player playerSender = validatePlayerSender(sender);
        if ((playerSender == null || !hasPermission(sender, "greetmate.command.greetban")
                || !hasRequiredRole(playerSender))
                || !validateArgsLength(sender, args, 2, "§e[Greetmate] 使用法: /greetban <player> <reason>"))
            return true;

        String playerName = args[0];
        String reason = String.join(" ", args).substring(playerName.length()).trim();

        OfflinePlayer target = Bukkit.getOfflinePlayer(playerName);
        UUID uuid = target.getUniqueId();

        PlayerData targetData = PlayerRoleDao.findPlayerByUUID(uuid);
        int roleId = targetData != null ? targetData.getRole() : 0;

        BanPlayerData ban = new BanPlayerData(0, playerName, roleId, uuid, reason, new Date());
        BanPlayerDao.insert(ban);
        PlayerRoleDao.deletePlayerByUUID(uuid);

        sender.sendMessage("§a[Greetmate] " + playerName + " をBAN登録しました。");
        LogWriter.writeInfo("[Greetmate] BAN登録: " + playerName + " 理由: " + reason);
        return true;
    }

    /**
     * BANされたプレイヤーの解除を実行
     * 
     * @param sender 実行者
     * @param args   引数
     * @return trueを返す
     */
    private boolean handleUnban(CommandSender sender, String[] args) {
        Player playerSender = validatePlayerSender(sender);
        if ((playerSender == null || !hasPermission(sender, "greetmate.command.greetunban")
                || !hasRequiredRole(playerSender))
                || !validateArgsLength(sender, args, 1, "§e[Greetmate] 使用法: /greetunban <player>"))
            return true;

        String playerName = args[0];
        OfflinePlayer target = Bukkit.getOfflinePlayer(playerName);
        UUID uuid = target.getUniqueId();

        boolean deleted = BanPlayerDao.delete(uuid);
        if (deleted) {
            sender.sendMessage("§a[Greetmate] " + playerName + " のBANを解除しました。");
            LogWriter.writeInfo("[Greetmate] BAN解除: " + playerName);
        } else {
            sender.sendMessage("§c[Greetmate] BAN解除に失敗しました。該当プレイヤーは登録されていない可能性があります。");
        }

        return true;
    }

    /**
     * greetroleコマンドを処理分岐
     * 
     * @param sender 実行者
     * @param args   引数
     * @return trueを返す
     */
    private boolean handleRoleCommand(CommandSender sender, String[] args) {
        Player playerSender = validatePlayerSender(sender);
        if (playerSender == null
                || !hasPermission(sender, "greetmate.command.greetrole")
                || !hasRequiredRole(playerSender)) {
            return true;
        }

        if (!validateArgsLength(sender, args, 1, "§e[Greetmate] 使用法: /greetrole <set|register|del>"))
            return true;

        switch (args[0].toLowerCase()) {
            case "set":
                handleSet(sender, args);
                break;
            case "register":
                handleRegister(sender, args);
                break;
            case "del":
                handleDelete(sender, args);
                break;
            default:
                sender.sendMessage("§e[Greetmate] 使用法: /greetrole <set|register|del>");
        }

        return true;
    }

    /**
     * 登録済プレイヤーのロールIDを更新
     * 
     * @param sender 実行者
     * @param args   引数
     */
    private boolean handleSet(CommandSender sender, String[] args) {
        if (!validateArgsLength(sender, args, 3, "§e使用法: /greetrole set <player> <role>"))
            return true;

        String playerName = args[1];
        Integer roleId = getValidRoleIdOrAbort(sender, args[2]);
        if (roleId == null)
            return true;

        Player target = getPlayerOrAbort(sender, playerName);
        if (target == null)
            return true;

        UUID uuid = target.getUniqueId();
        PlayerData data = PlayerRoleDao.findPlayerByUUID(uuid);
        if (data == null) {
            sender.sendMessage("§c[Greetmate] 指定されたプレイヤーは登録されていません。/greetrole register を使ってください。");
            return true;
        }

        boolean updated = PlayerRoleDao.updatePlayerRoleByUUID(uuid, roleId);
        if (updated) {
            sender.sendMessage("§a[Greetmate] ロールを更新しました: " + playerName + " → " + roleId);
            LogWriter.writeInfo("[Greetmate] ロール更新: " + playerName + " → " + roleId);
        } else {
            sender.sendMessage("§c[Greetmate] ロールの更新に失敗しました。");
        }
        return true;
    }

    /**
     * プレイヤー情報を新規登録
     * 
     * @param sender 実行者
     * @param args   引数
     */
    private void handleRegister(CommandSender sender, String[] args) {
        if (!validateArgsLength(sender, args, 3, "§e使用法: /greetrole register <player> <role>"))
            return;

        String playerName = args[1];
        Integer roleId = getValidRoleIdOrAbort(sender, args[2]);
        if (roleId == null)
            return;

        Player target = getPlayerOrAbort(sender, playerName);
        if (target == null)
            return;

        UUID uuid = target.getUniqueId();
        PlayerData existing = PlayerRoleDao.findPlayerByUUID(uuid);

        if (existing != null) {
            sender.sendMessage("§c[Greetmate] 既に登録されています。/greetrole set を使ってください。");
            return;
        }

        boolean inserted = PlayerRoleDao.insertPlayer(uuid, playerName, roleId);
        if (inserted) {
            sender.sendMessage("§a[Greetmate] プレイヤーを登録しました: " + playerName + "（ロール: " + roleId + "）");
            LogWriter.writeInfo("[Greetmate] 新規プレイヤー登録: " + playerName + "（ロール: " + roleId + "）");
        } else {
            sender.sendMessage("§c[Greetmate] プレイヤー登録に失敗しました。");
        }
    }

    /**
     * 登録済プレイヤー情報を削除
     * 
     * @param sender 実行者
     * @param args   引数
     */
    private void handleDelete(CommandSender sender, String[] args) {
        boolean isValid = validateArgsLength(sender, args, 2, "§e使用法: /greetrole del <player>");
        String playerName = args.length > 1 ? args[1] : "";

        if (!isValid) {
            sender.sendMessage("§c[Greetmate] 引数が不正です。");
        } else {
            Player target = getPlayerOrAbort(sender, playerName);
            if (target == null) {
                sender.sendMessage("§c[Greetmate] プレイヤーの取得に失敗しました。");
            } else {
                UUID uuid = target.getUniqueId();
                boolean deleted = PlayerRoleDao.deletePlayerByUUID(uuid);
                if (deleted) {
                    sender.sendMessage("§a[Greetmate] プレイヤー情報を削除しました: " + playerName);
                    LogWriter.writeInfo("[Greetmate] プレイヤー情報削除: " + playerName);
                } else {
                    sender.sendMessage("§c[Greetmate] 削除に失敗しました。");
                }
            }
        }
    }

    /**
     * 実行者が指定された権限を持っているか確認
     * 
     * @param sender     実行者
     * @param permission 権限名
     * @return trueなら持っている
     */
    private boolean hasPermission(CommandSender sender, String permission) {
        if (!sender.hasPermission(permission)) {
            sender.sendMessage("§c[Greetmate] 権限がありません。");
            return false;
        }
        return true;
    }

    /**
     * 実行者がプレイヤーかどうかを確認
     * 
     * @param sender 実行者
     * @return Playerの場合はその実体 nullならコンソールからの実行
     */
    private Player validatePlayerSender(CommandSender sender) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("§c[Greetmate] プレイヤーからのみ実行できます。");
            return null;
        }
        return player;
    }

    /**
     * 必要なロールを持っているかを確認
     * 
     * @param player プレイヤー
     * @return 持っていればtrue
     */
    private boolean hasRequiredRole(Player player) {
        PlayerData data = PlayerRoleDao.findPlayerByUUID(player.getUniqueId());
        if (data == null || (data.getRole() != 3 && data.getRole() != 4)) {
            player.sendMessage("§c[Greetmate] ロール3または4のユーザーのみ実行可能です。");
            return false;
        }
        return true;
    }

    /**
     * 引数の長さを検証
     * 
     * @param sender   実行者
     * @param args     引数配列
     * @param required 必要数
     * @param usage    使用法文字列
     * @return 不足していればfalse
     */
    private boolean validateArgsLength(CommandSender sender, String[] args, int required, String usage) {
        if (args.length < required) {
            sender.sendMessage(usage);
            return false;
        }
        return true;
    }

    /**
     * 指定されたロールIDの検証
     * 
     * @param sender コマンド実行者
     * @param input  入力されたロールID文字列
     * @return 有効なロールID（数値）または null
     */
    private Integer getValidRoleIdOrAbort(CommandSender sender, String input) {
        try {
            int roleId = Integer.parseInt(input);
            if (!PlayerRoleDao.isValidRole(roleId)) {
                sender.sendMessage("§c[Greetmate] 指定されたロールIDは存在しません。");
                return null;
            }
            sender.sendMessage("§a[Greetmate] ロールIDの検証に成功しました。");
            return roleId;
        } catch (NumberFormatException e) {
            sender.sendMessage("§c[Greetmate] ロールは数値で指定してください。");
            return null;
        }
    }

    /**
     * オンラインプレイヤーの検証
     * 
     * @param sender コマンド実行者
     * @param name   対象プレイヤー名
     * @return 該当プレイヤーがオンラインなら Player、いなければ null
     */
    Player getPlayerOrAbort(CommandSender sender, String name) {
        Player player = Bukkit.getPlayerExact(name);
        if (player == null) {
            sender.sendMessage("§c[Greetmate] プレイヤーが見つかりません（オンラインである必要があります）。");
            return null;
        }
        sender.sendMessage("§a[Greetmate] プレイヤーの検証に成功しました。");
        return player;
    }

}
