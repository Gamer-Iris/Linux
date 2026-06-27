#!/usr/bin/env python3
######################################################################################################################################################
# ファイル   : validate_k8s_policy.py
# 引数       : なし
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

"""Kubernetes manifest lightweight policy gate.

役割:
  kubeconform では拾いにくい運用ポリシーを補助的に検査する。

検査対象:
  platforms/kubernetes/apps 配下の YAML manifest。
  Helm values.yaml は Kubernetes manifest ではないため除外する。

戻り値:
  0: duplicate resource なし
  1: duplicate resource あり

注意:
  この repository では一部 image の latest 運用を意図的に許容する。
  resources は requests 中心で確認し、limits は一律必須にしない。
"""

import sys
from pathlib import Path

import yaml


ROOT = Path("platforms/kubernetes/apps")
WARNING_KINDS = {"Deployment", "StatefulSet", "DaemonSet", "CronJob", "Job"}
LATEST_ALLOWED_IMAGES = {
    "alpine",
    "bitnami/kubectl",
    "cloudflare/cloudflared",
    "deluan/navidrome",
    "itzg/bungeecord",
    "itzg/mc-backup",
    "mariadb",
    "phpmyadmin/phpmyadmin",
    "wordpress",
}


def iter_yaml_documents(path: Path):
    """YAML ファイル内の document を順に返す。

    YAML 構文エラーは CI で落とすため、そのまま例外を再送出する。
    """
    try:
        with path.open(encoding="utf-8") as handle:
            yield from yaml.safe_load_all(handle)
    except yaml.YAMLError as exc:
        print(f"ERROR: YAML parse failed: {path}: {exc}", file=sys.stderr)
        raise


def containers_from(doc):
    """workload manifest から containers 配列を取得する。

    kind ごとに pod template の位置が異なるため、policy check 側で吸収する。
    """
    kind = doc.get("kind")
    if kind in {"Deployment", "StatefulSet", "DaemonSet"}:
        return doc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if kind == "Job":
        return doc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if kind == "CronJob":
        return (
            doc.get("spec", {})
            .get("jobTemplate", {})
            .get("spec", {})
            .get("template", {})
            .get("spec", {})
            .get("containers", [])
        )
    return []


def image_repo(image: str) -> str:
    """image reference から tag を除いた repository 名を返す。"""
    if "@" in image:
        image = image.split("@", 1)[0]
    tail = image.rsplit("/", 1)[-1]
    if ":" in tail:
        return image.rsplit(":", 1)[0]
    return image


def main() -> int:
    """Kubernetes manifest の重複と軽量ポリシーを検査する。"""
    warnings = 0
    errors = 0
    seen = {}

    for path in sorted(ROOT.rglob("*.y*ml")):
        if path.name == "values.yaml":
            continue
        for index, doc in enumerate(iter_yaml_documents(path), start=1):
            if not isinstance(doc, dict):
                continue
            kind = doc.get("kind")
            meta = doc.get("metadata") or {}
            name = meta.get("name")
            namespace = meta.get("namespace", "default")

            if kind and name:
                key = (kind, namespace, name)
                if key in seen:
                    print(f"ERROR: duplicate resource {key}: {seen[key]} and {path}", file=sys.stderr)
                    errors += 1
                seen[key] = path

            if kind in WARNING_KINDS and not meta.get("namespace"):
                print(f"WARNING: {path}#{index}: {kind}/{name} has no metadata.namespace")
                warnings += 1

            for container in containers_from(doc):
                image = str(container.get("image", ""))
                cname = container.get("name", "<unnamed>")
                if image.endswith(":latest") and image_repo(image) not in LATEST_ALLOWED_IMAGES:
                    print(f"WARNING: {path}#{index}: container {cname} uses mutable latest tag: {image}")
                    warnings += 1
                if image.endswith(":latest") and container.get("imagePullPolicy") != "Always":
                    print(f"WARNING: {path}#{index}: container {cname} uses latest without imagePullPolicy Always: {image}")
                    warnings += 1
                resources = container.get("resources")
                if not resources:
                    print(f"INFO: {path}#{index}: container {cname} has no resources")
                elif "requests" not in resources:
                    print(f"INFO: {path}#{index}: container {cname} has resources but no requests")

    print(f"K8s policy: {errors} errors, {warnings} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
