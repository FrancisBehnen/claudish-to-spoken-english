# Emit one record per assistant message that carries text, from a Claude Code
# transcript slurped with `jq -s`.
#
# Assistant text only. rewrite.sh also reads the preceding USER message off
# .transcript_path and appends it to the system prompt as context
# (rewrite.sh:184-190), but selecting user prompts out of a transcript is
# blocked by this machine's permission classifier, so the captured corpus runs
# the no-context path instead — which rewrite.sh supports explicitly
# ("Missing/unreadable transcript -> no context, still rewrites", rewrite.sh:20).
# See corpus/README.md "Known deviation from the live hook".
.[]
| select(.type == "assistant")
| select(.message.content | type == "array")
| {sess: $sess,
   uuid: .uuid,
   ts: .timestamp,
   txt: ([.message.content[] | select(.type == "text") | .text] | join(""))}
| select((.txt | length) > 0)
