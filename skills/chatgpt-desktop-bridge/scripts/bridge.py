from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any


DEFAULT_REPO = Path(os.getenv("AI_MESSENGER_REPO", r"C:\Repos\ai-messenger"))
DEFAULT_DB = Path(os.getenv("AI_MESSENGER_DB", str(DEFAULT_REPO / "data" / "ai-messenger.db")))
SOURCE_ROOT = DEFAULT_REPO / "src"
if str(SOURCE_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT))

from ai_messenger.mailbox import activate_mailbox, import_receipts, prepare_mailbox, publish_next
from ai_messenger.store import MessengerStore


def emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="chatgpt-desktop-bridge")
    root.add_argument("--db", default=str(DEFAULT_DB))
    sub = root.add_subparsers(dest="command", required=True)

    setup = sub.add_parser("setup")
    setup.add_argument("--endpoint", default="chatgpt-design-desktop")

    activate = sub.add_parser("activate")
    activate.add_argument("--endpoint", default="chatgpt-design-desktop")
    activate.add_argument("--approve-live", action="store_true")

    send = sub.add_parser("send")
    send.add_argument("--channel", required=True)
    send.add_argument("--source", required=True)
    send.add_argument("--target", required=True)
    body = send.add_mutually_exclusive_group(required=True)
    body.add_argument("--body")
    body.add_argument("--body-file")
    send.add_argument("--correlation-id", default="")
    send.add_argument("--idempotency-key", default="")
    send.add_argument("--metadata-json", default="{}")
    send.add_argument("--publish", action="store_true")

    receive = sub.add_parser("receive")
    receive.add_argument("--endpoint", default="chatgpt-design-desktop")

    status = sub.add_parser("status")
    status.add_argument("--endpoint", default="chatgpt-design-desktop")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    store = MessengerStore(args.db)
    store.initialize()
    try:
        if args.command == "setup":
            result = prepare_mailbox(store, args.endpoint)
            contract = Path(__file__).resolve().parents[1] / "references" / "listener-contract.md"
            mailbox_contract = Path(result["mailbox_root"]) / "LISTENER_INSTRUCTIONS.md"
            shutil.copyfile(contract, mailbox_contract)
            result["listener_contract"] = str(mailbox_contract)
            emit({"ok": True, **result})
        elif args.command == "activate":
            emit({"ok": True, **activate_mailbox(store, args.endpoint, approve_live=args.approve_live)})
        elif args.command == "send":
            text = args.body if args.body is not None else Path(args.body_file).read_text(encoding="utf-8-sig")
            metadata = json.loads(args.metadata_json)
            if not isinstance(metadata, dict):
                raise ValueError("metadata-json must be an object")
            message, created = store.enqueue_message(
                args.channel,
                args.source,
                args.target,
                {"body": text, "metadata": metadata},
                correlation_id=args.correlation_id,
                idempotency_key=args.idempotency_key,
            )
            published = publish_next(store, args.target) if args.publish else None
            emit({"ok": True, "created": created, "message": message, "published": published})
        elif args.command == "receive":
            emit({"ok": True, **import_receipts(store, args.endpoint)})
        elif args.command == "status":
            emit(
                {
                    "ok": True,
                    "endpoint": store.get_endpoint(args.endpoint),
                    "live_enabled": store.get_setting("live_enabled", "off"),
                    "kill_switch": store.get_setting("kill_switch", "off"),
                }
            )
        return 0
    except Exception as error:
        emit({"ok": False, "error": str(error), "type": type(error).__name__})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
