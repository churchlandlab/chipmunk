#!/bin/bash
# Run the chipmunk_solo MATLAB checks on a rig, each in its own fresh MATLAB, against a
# temporary clone of this repository's committed state (the checkout itself is not touched).
#
#   chipmunk_solo/tests/run_rig_checks.sh [offline|emulator|real|all]    (default: all)
#
#   offline   20 checks that need no Bpod, plus the original-protocol isolation check
#   emulator  6 sessions in Bpod('EMU'), including a 1,000-trial endurance run (up to ~1 h)
#   real      FakeSubject sessions on the real Bpod with cameras, ending with Stop during a
#             trial and passive replay; then leaves Bpod ready for auto-detection
#
# Close MATLAB and stop any session first: the real check takes over the Bpod port.
# Environment (defaults in brackets): OUT [~/chipmunk-rig-checks/<time>], BPOD [~/Bpod_Gen2],
# BPOD_PORT [/dev/ttyACM0], CAMERA_CONFIG [~/labcams/default.json], DISPLAY [:1],
# XAUTHORITY [~/.Xauthority]. Prints PASS/FAIL per check and ALL_PASS at the end.
set -u
MODE=${1:-all}
case $MODE in offline|emulator|real|all) ;; *) echo "usage: $0 [offline|emulator|real|all]"; exit 2;; esac
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:-$HOME/chipmunk-rig-checks/$(date +%Y%m%d_%H%M%S)}
BPOD=${BPOD:-$HOME/Bpod_Gen2}; BPOD_PORT=${BPOD_PORT:-/dev/ttyACM0}
CAMERA_CONFIG=${CAMERA_CONFIG:-$HOME/labcams/default.json}
export DISPLAY=${DISPLAY:-:1} XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
pgrep -x MATLAB >/dev/null && { echo "MATLAB is running; close it first."; exit 1; }
mkdir -p "$OUT/logs"; T=$OUT/repo
git clone -q "$REPO" "$T" && git -C "$T" log -1 --format='Testing %h %s'
S=$T/chipmunk_solo/tests; L=$OUT/logs; fail=0

check() {  # name, MATLAB code, success marker
  if timeout 3600 matlab -batch "$2" >"$L/$1.log" 2>&1 && grep -q "$3" "$L/$1.log"; then echo "PASS $1"
  else echo "FAIL $1 (log: $L/$1.log)"; grep -v '^\s*$' "$L/$1.log" | tail -5; fail=1; fi
}
emulator() { echo "addpath('$BPOD'); Bpod('EMU'); global BpodSystem; if ~isequal(BpodSystem.EmulatorMode,1) && isfield(BpodSystem.GUIHandles,'LaunchEmuModeButton'), cb=get(BpodSystem.GUIHandles.LaunchEmuModeButton,'Callback'); feval(cb,BpodSystem.GUIHandles.LaunchEmuModeButton,[]); end; assert(BpodSystem.EmulatorMode==1,'not emulator'); cd('$S'); $1; disp('CHECK_DONE')"; }

if [ "$MODE" = offline ] || [ "$MODE" = all ]; then
  for f in "$S"/check_*.m; do
    n=$(basename "$f" .m)
    case $n in  # emulator/real-Bpod sessions, hand-driven checks, and the isolation check below
      check_chipmunk_*|check_passive_replay_emulator|check_native_picker|check_historical_equivalence|check_original_isolation) continue;;
    esac
    check "$n" "cd('$S'); $n; disp('CHECK_DONE')" CHECK_DONE
  done
  check original_isolation "cd('$S'); check_original_isolation('$T')" ORIGINAL_ISOLATION_PASS  # cd, not addpath: the check rejects Solo folders on the path
fi

if [ "$MODE" = emulator ] || [ "$MODE" = all ]; then
  E=$OUT/emulator
  check emu_outcomes_left "$(emulator "check_chipmunk_outcomes('$E/outcomes_left',1,1)")" CHECK_DONE
  check emu_outcomes_right "$(emulator "check_chipmunk_outcomes('$E/outcomes_right',1,0)")" CHECK_DONE
  check emu_manipulation "$(emulator "check_chipmunk_manipulation_session('$E/manipulation')")" CHECK_DONE
  check emu_replay_session "$(emulator "check_chipmunk_replay_session('$E/replay_session')")" CHECK_DONE
  check emu_passive_replay "$(emulator "check_passive_replay_emulator('$E/passive_replay')")" CHECK_DONE
  check emu_endurance "$(emulator "check_chipmunk_endurance('$E/endurance')")" CHECK_DONE
fi

if [ "$MODE" = real ] || [ "$MODE" = all ]; then
  export CHIPMUNK_REAL_BPOD_CHECK=1
  check real_bpod "addpath('$BPOD'); Bpod('$BPOD_PORT'); global BpodSystem; assert(BpodSystem.EmulatorMode==0,'not real Bpod'); cd('$S'); check_chipmunk_replay_session('$OUT/real',{'VisualTask','MultipleModalitiesTask'},'$CAMERA_CONFIG'); disp('CHECK_DONE'); close all force" CHECK_DONE
  unset CHIPMUNK_REAL_BPOD_CHECK
  # A session that ends abnormally can leave Bpod "connected" (no discovery bytes) and a stale
  # port lock, so the next Bpod() cannot find the port. Clear both.
  pkill -x MATLAB; sleep 5
  for f in /run/lock/LCK..* /var/lock/LCK..*; do [ -e "$f" ] && { p=$(tr -d ' \n' < "$f"); kill -0 "$p" 2>/dev/null || rm -f "$f"; }; done
  check bpod_reset "addpath('$BPOD'); addpath(genpath(fullfile('$BPOD','Functions'))); s=ArCOMObject_Bpod('$BPOD_PORT',12000000); pause(1.5); n=s.bytesAvailable; if n>0, s.read(n,'uint8'); end; if n==0, s.write('Z','uint8'); pause(2); n=s.bytesAvailable; end; clear s; assert(n>0,'Bpod sends no discovery bytes'); disp('BPOD_DISCOVERABLE')" BPOD_DISCOVERABLE
fi

pgrep -x MATLAB >/dev/null && echo "WARN MATLAB still running"
echo "Logs and outputs: $OUT"
[ $fail = 0 ] && echo ALL_PASS
exit $fail
