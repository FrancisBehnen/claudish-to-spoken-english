#!/usr/bin/env python3
"""Build a hook payload fixture from a text file.

  mkpayload.py display <file> <message_id>   -> a MessageDisplay final-chunk payload
  mkpayload.py stop    <file> [session_id]   -> a Stop payload

The Stop shape is the ELEVEN fields observed on 2.1.245 (spec §2).
`stop_reason` and `model` are absent on purpose: they appear in the docs and
not on the wire, and nothing in speak.sh may reference them.
"""
import json
import sys


def main(argv):
    kind = argv[1]
    text = open(argv[2], encoding="utf-8").read()
    if kind == "display":
        print(json.dumps({
            "session_id": argv[3] if len(argv) > 3 else "fixture-session",
            "transcript_path": "/nonexistent/transcript.jsonl",
            "cwd": "/tmp",
            "prompt_id": "prompt-fixture-1",
            "hook_event_name": "MessageDisplay",
            "turn_id": "turn-fixture-1",
            "message_id": argv[4] if len(argv) > 4 else "msg-fixture-1",
            "index": 0,
            "final": True,
            "delta": text,
        }))
    else:
        print(json.dumps({
            "session_id": argv[3] if len(argv) > 3 else "fixture-session",
            "transcript_path": "/nonexistent/transcript.jsonl",
            "cwd": "/tmp",
            "prompt_id": "prompt-fixture-1",
            "permission_mode": "default",
            "effort": "medium",
            "hook_event_name": "Stop",
            "stop_hook_active": False,
            "last_assistant_message": text,
            "background_tasks": [],
            "session_crons": [],
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
