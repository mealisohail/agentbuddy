#!/bin/bash
# End-to-end test against a real interactive Claude Code session running in tmux.
# Uses --settings for the hook, so ~/.claude/settings.json is never touched. Costs a few cheap model calls.
# Usage: tests/e2e.sh   (needs tmux, claude, and the app built: ./build.sh)
set -u
EXE=${EXE:-$HOME/Applications/AgentBuddy.app/Contents/MacOS/AgentBuddy}
MODEL=${MODEL:-haiku}
WORK=$(mktemp -d /tmp/agentbuddy-e2e-test.XXXXXX); WORK=$(cd "$WORK" && pwd -P)
SETTINGS=$WORK.settings.json
TMUX_S=agentbuddy-e2e
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
ctl()  { printf '%s' "$1" | "$EXE" --hook; }
state(){ ctl '{"control":"state"}'; }
# q <python expr over `s` = this test's session dict (or None)>
q()    { state | python3 -c "import json,sys; d=json.load(sys.stdin); s=next((x for x in d['sessions'] if x['cwd']=='$WORK'),None); print($1)"; }
wait_for() { # wait_for <seconds> <python-bool-expr>
  for _ in $(seq 1 $(($1*2))); do [ "$(q "$2")" = "True" ] && return 0; sleep 0.5; done; return 1; }
sid()  { q "s['id'] if s else ''"; }
send() { ctl "{\"control\":\"send\",\"session\":\"$(sid)\",\"text\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")}"; }
decide(){ ctl "{\"control\":\"decide\",\"session\":\"$(sid)\",\"decision\":\"$1\"${2:+,\"answers\":$2}}"; }
cleanup(){ tmux kill-session -t $TMUX_S 2>/dev/null; rm -rf "$WORK" "$SETTINGS"; }
trap cleanup EXIT INT TERM HUP

pgrep -x AgentBuddy >/dev/null || { open "$(dirname "$(dirname "$(dirname "$EXE")")")"; sleep 2; }
cat > "$SETTINGS" <<JSON
{"hooks":{"PermissionRequest":[{"matcher":"*","hooks":[{"type":"command","command":"'$EXE' --hook","timeout":600}]}]}}
JSON

# don't let the test session inherit this shell's Claude Code identity (e.g. when run from inside Claude Code)
for v in $(env | grep -oE '^CLAUDE[A-Z_]*'); do unset "$v"; done
echo "• starting claude in tmux ($WORK)"
tmux new-session -d -s $TMUX_S -x 220 -y 50 -c "$WORK" "claude --settings '$SETTINGS' --model $MODEL --permission-mode default"
for _ in $(seq 1 20); do   # accept the folder-trust prompt if shown
  sleep 1; tmux capture-pane -p -t $TMUX_S | grep -qi "trust this folder" && { tmux send-keys -t $TMUX_S Down; sleep 0.3; tmux send-keys -t $TMUX_S Enter; break; }
  [ -n "$(sid)" ] && break
done

echo "1. discovery"
wait_for 30 "s is not None and s['visible']" && ok "session listed" || { bad "session never appeared"; exit 1; }
[ "$(q "s['host']")" = "tmux" ] && ok "host detected as tmux" || bad "host is $(q "s['host']")"

echo "2. send prompt + Allow"
send "Use the Bash tool to run exactly: echo huddle-allow > allow.txt   (no other tools, then say done)" | grep -q '"ok":true' && ok "prompt typed into session" || bad "send failed"
wait_for 90 "s.get('pending')=='Bash'" && ok "permission request held in AgentBuddy" || bad "no pending Bash request"
[ "$(state | python3 -c 'import json,sys;print(json.load(sys.stdin)["expanded"])')" = "True" ] && ok "island opened for it" || bad "island did not open"
decide allow >/dev/null
for _ in $(seq 1 60); do [ -f "$WORK/allow.txt" ] && break; sleep 0.5; done
[ -f "$WORK/allow.txt" ] && ok "Allow ran the command" || bad "allow.txt missing"
wait_for 60 "s['status']=='idle'" && ok "back to idle" || bad "never went idle"
q "s['prompt']" | grep -q "huddle-allow" && ok "transcript prompt parsed" || bad "prompt not parsed: $(q "s['prompt']")"
q "len(s['steps'])>0" | grep -q True && ok "steps parsed: $(q "s['steps']")" || bad "no steps parsed"

echo "3. Deny"
send "Use the Bash tool to run exactly: echo nope > deny.txt   (if denied, just say denied)" >/dev/null
wait_for 90 "s.get('pending')=='Bash'" && ok "request held" || bad "no pending request"
decide deny >/dev/null
wait_for 60 "s['status']=='idle' and 'pending' not in s" && ok "session continued after deny" || bad "stuck after deny"
[ ! -f "$WORK/deny.txt" ] && ok "denied command did not run" || bad "deny.txt exists!"

echo "4. AskUserQuestion answered from AgentBuddy"
send "Use the AskUserQuestion tool to ask me which colour I prefer, header Colour, options Red and Blue. Then use Bash to run: echo <my answer> > colour.txt" >/dev/null
wait_for 90 "s.get('pending')=='AskUserQuestion'" && ok "question held" || bad "no pending question"
decide answer '["Blue"]' >/dev/null
wait_for 90 "s.get('pending')=='Bash'" && { ok "answer accepted, follow-up asked permission"; decide allow >/dev/null; } || bad "no follow-up Bash"
for _ in $(seq 1 60); do [ -f "$WORK/colour.txt" ] && break; sleep 0.5; done
grep -qi blue "$WORK/colour.txt" 2>/dev/null && ok "Claude received the answer (Blue)" || bad "colour.txt: $(cat "$WORK/colour.txt" 2>/dev/null)"
wait_for 60 "s['status']=='idle'" >/dev/null

echo "5. Pass through to Claude's own prompt"
send "Use the Bash tool to run exactly: echo pass > pass.txt" >/dev/null
wait_for 90 "s.get('pending')=='Bash'" && ok "request held" || bad "no pending request"
decide passthrough >/dev/null
wait_for 30 "s['status']=='waiting' and 'pending' not in s" && ok "native prompt shown, session marked waiting" || bad "status: $(q "s['status']")"
tmux send-keys -t $TMUX_S Escape; sleep 1
wait_for 60 "s['status']=='idle'" && ok "native prompt dismissed in terminal" || bad "not idle after Esc"

echo "5b. answered in Claude's own prompt while the card is showing (the VS Code case)"
send "Use the Bash tool to run exactly: echo native > native.txt" >/dev/null
wait_for 90 "s.get('pending')=='Bash'" && ok "request held" || bad "no pending request"
sleep 2
if tmux capture-pane -p -t $TMUX_S | grep -qiE "do you want|proceed\?"; then
  echo "    (CLI shows its own prompt in parallel with the hook)"
  tmux send-keys -t $TMUX_S Enter       # pick the default: Yes
  wait_for 15 "'pending' not in s" && ok "card cleared after answering natively" || bad "stale card stayed after native answer"
else
  echo "    (CLI waits for the hook before showing its prompt; only the editor case can race)"
  decide allow >/dev/null
fi
wait_for 60 "s['status']=='idle'" && ok "session idle again" || bad "not idle"

echo "6. hook process dies while held"
send "Use the Bash tool to run exactly: echo gone > gone.txt" >/dev/null
wait_for 90 "s.get('pending')=='Bash'" && ok "request held" || bad "no pending request"
pkill -f "AgentBuddy --hook" ; sleep 2
wait_for 10 "'pending' not in s" && ok "stale request removed from AgentBuddy" || bad "stale request still shown"
pgrep -x AgentBuddy >/dev/null && ok "app still running" || bad "app died"
tmux send-keys -t $TMUX_S Escape; sleep 1; tmux send-keys -t $TMUX_S Escape

echo "7. session exit"
tmux kill-session -t $TMUX_S
wait_for 15 "s is None" && ok "ended session removed" || bad "ended session still listed"

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
