#!/bin/bash
# Remove the mtime-damaged copies an earlier `cp -R` made in out/. The originals in
# out-round2-sighup/ are untouched -- cp does not modify its source -- so nothing is
# lost. Only the seven re-run configurations legitimately live in out/.
#
# RIG here names the author's RUN TREE, not the rig's scripts. Overridable.
set -u
RIG=${RIG:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25}
KEEP=" C12a_pgid_pubfirst C12b_pgid_sweepfirst C13b_perplayer_sametiming
C16a_pending_sweepfirst C16b_pending_pubfirst C15c_norecheck_death_pgid
C17_setsid_player "
for d in "$RIG"/out/C*-*; do
  [[ -d "$d" ]] || continue
  b=$(basename "$d"); cfg=${b%-*}
  # NOTE: KEEP must be whitespace-normalised to one line first. A multi-line
  # string breaks *" $cfg "* for every entry adjacent to a newline.
  case " $(echo $KEEP) " in *" $cfg "*) continue ;; esac
  rm -rf "$d"
  echo "removed damaged copy: $b"
done
