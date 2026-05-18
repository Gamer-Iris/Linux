#!/usr/bin/env python3

######################################################################################################################################################
# ファイル   : inventory.sh
# 引数       : --list | --host <username>
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
#
######################################################################################################################################################

#*****************************************************************************************************************************************************
# 環境設定エリア
#*****************************************************************************************************************************************************
import json
import os
import shutil
import subprocess
import sys

#*****************************************************************************************************************************************************
# 処理内容エリア
#*****************************************************************************************************************************************************

######################################################################################################################################################
# get_settings_file 関数
# @return str : settings_secret.yml の絶対パス
######################################################################################################################################################
def get_settings_file() -> str:
    script_dir = os.path.dirname(os.path.realpath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, "../.."))
    return os.path.join(repo_root, "platforms", "settings", "settings_secret.yml")


######################################################################################################################################################
# yq_eval 関数
# @param  expr     : yq の評価式
# @param  filepath : 対象 YAML ファイルパス
# @return str      : 評価結果（文字列）
######################################################################################################################################################
def yq_eval(expr: str, filepath: str) -> str:
    result = subprocess.run(
        ["yq", "eval", expr, filepath],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


######################################################################################################################################################
# yq_eval_json 関数
# @param  expr     : yq の評価式
# @param  filepath : 対象 YAML ファイルパス
# @return object   : 評価結果（JSON デシリアライズ済み）
######################################################################################################################################################
def yq_eval_json(expr: str, filepath: str) -> object:
    result = subprocess.run(
        ["yq", "eval", "--output-format=json", expr, filepath],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


######################################################################################################################################################
# build_inventory 関数
# @param  settings_file : settings_secret.yml の絶対パス
# @return dict          : Ansible インベントリ辞書
######################################################################################################################################################
def build_inventory(settings_file: str) -> dict:
    default_username = yq_eval(".username", settings_file)
    default_ssh_key = yq_eval(".key", settings_file)
    default_become_password = yq_eval(".password", settings_file)
    expose_become_password = os.environ.get("LINUX_SETUP_EXPOSE_BECOME_PASSWORD") == "1"

    def add_become_password(hostvars: dict, node: dict) -> None:
        become_password = node.get("password") or default_become_password
        hostvars["ansible_become_password"] = become_password
        hostvars["ansible_become_pass"] = become_password

    def resolve_key(node: dict) -> str:
        """ホスト個別の key を返す。未設定の場合はデフォルト値にフォールバック"""
        return os.path.expanduser(node.get("key") or default_ssh_key)

    def host_alias(group: str, index: int, node: dict) -> str:
        """Ansible inventory 上の一意なホスト名を返す"""
        return node.get("name") or f"{group}-{index + 1:02d}"

    # グループ: control_plane
    cp_nodes_raw = yq_eval_json(".nodes.control_plane", settings_file)
    cp_hosts = []
    cp_hostvars = {}
    if isinstance(cp_nodes_raw, list):
        for index, node in enumerate(cp_nodes_raw):
            username = node.get("username") or default_username
            if not username:
                continue
            alias = host_alias("control-plane", index, node)
            cp_hosts.append(alias)
            cp_hostvars[alias] = {
                "ansible_host": node.get("ip", ""),
                "ansible_user": username,
                "ansible_ssh_private_key_file": resolve_key(node),
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_become_method": "sudo",
                "ansible_become_user": "root",
                "ansible_ssh_use_tty": False,
            }
            if expose_become_password:
                add_become_password(cp_hostvars[alias], node)

    # グループ: workers
    w_nodes_raw = yq_eval_json(".nodes.workers", settings_file)
    w_hosts = []
    w_hostvars = {}
    if isinstance(w_nodes_raw, list):
        for index, node in enumerate(w_nodes_raw):
            username = node.get("username") or default_username
            if not username:
                continue
            alias = host_alias("worker", index, node)
            w_hosts.append(alias)
            w_hostvars[alias] = {
                "ansible_host": node.get("ip", ""),
                "ansible_user": username,
                "ansible_ssh_private_key_file": resolve_key(node),
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_become_method": "sudo",
                "ansible_become_user": "root",
                "ansible_ssh_use_tty": False,
            }
            if expose_become_password:
                add_become_password(w_hostvars[alias], node)

    # グループ: proxmox
    px_nodes_raw = yq_eval_json(".nodes.proxmox", settings_file)
    px_hosts = []
    px_hostvars = {}
    if isinstance(px_nodes_raw, list):
        for index, node in enumerate(px_nodes_raw):
            username = node.get("username") or default_username
            if not username:
                continue
            alias = host_alias("proxmox", index, node)
            px_hosts.append(alias)
            px_hostvars[alias] = {
                "ansible_host": node.get("ip", ""),
                "ansible_user": username,
                "ansible_ssh_private_key_file": resolve_key(node),
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_become_method": "sudo",
                "ansible_become_user": "root",
                "ansible_ssh_use_tty": False,
            }
            if expose_become_password:
                add_become_password(px_hostvars[alias], node)

    # 全 hostvars マージ
    all_hostvars = {}
    all_hostvars.update(cp_hostvars)
    all_hostvars.update(w_hostvars)
    all_hostvars.update(px_hostvars)

    inventory = {
        "control_plane": {
            "hosts": cp_hosts,
        },
        "workers": {
            "hosts": w_hosts,
        },
        "proxmox": {
            "hosts": px_hosts,
        },
        "k8s": {
            "children": ["control_plane", "workers"],
        },
        "_meta": {
            "hostvars": all_hostvars,
        },
    }

    return inventory


######################################################################################################################################################
# main 関数
# @param  なし
######################################################################################################################################################
def main():
    if "--list" in sys.argv:
        settings_file = get_settings_file()
        if not os.path.exists(settings_file):
            print(
                f"settings_secret.yml が見つかりません: {settings_file}",
                file=sys.stderr,
            )
            print(
                "platforms/settings/settings_secret_template.yml をコピーし、実値に編集してください。",
                file=sys.stderr,
            )
            print(
                json.dumps({"_meta": {"hostvars": {}}}),
                file=sys.stderr,
            )
            sys.exit(1)
        if shutil.which("yq") is None:
            print(
                "コマンドが見つかりません: yq",
                file=sys.stderr,
            )
            print(
                "inventory.sh は settings_secret.yml の読み込みに yq を使用します。",
                file=sys.stderr,
            )
            sys.exit(1)
        inventory = build_inventory(settings_file)
        print(json.dumps(inventory, ensure_ascii=False, indent=2))

    elif "--host" in sys.argv:
        # 個別ホスト情報は _meta.hostvars で一括提供するため空を返す
        print(json.dumps({}))

    else:
        print(
            "使用方法: inventory.sh --list | --host <username>",
            file=sys.stderr,
        )
        sys.exit(1)


######################################################################################################################################################
# エントリーポイント
# @param  -
######################################################################################################################################################
if __name__ == "__main__":
    main()
