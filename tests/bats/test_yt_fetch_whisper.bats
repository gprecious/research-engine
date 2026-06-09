#!/usr/bin/env bats

# Covers the local-first Whisper fallback in scripts/yt_fetch.sh:
#  - no backend at all → helpful partial that points at local install
#  - whisper.cpp backend (stubbed whisper-cli) → transcribes with NO api key
#  - Python (mlx-whisper) backend (stubbed module) → transcribes with NO api key
#  - local takes priority over a configured cloud key
#
# The Python-backend tests pin RESEARCH_ENGINE_WHISPER_DISABLE_CPP=1 and
# RESEARCH_ENGINE_PYTHON=python3 so they exercise the stub module regardless of
# whether a real whisper.cpp install is present on the dev machine.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/yt_fetch.sh"

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  MODS="$BATS_TEST_TMPDIR/mods"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MODS" "$BIN"
  PY3="$(command -v python3 || true)"
}

@test "whisper: no backend (local disabled + no keys) returns helpful partial" {
  run env -u GROQ_API_KEY -u OPENAI_API_KEY RESEARCH_ENGINE_WHISPER_DISABLE_LOCAL=1 \
    "$SCRIPT" transcribe /no/such/audio.mp3 "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '"transcript_source": *"none"'
  echo "$output" | grep -q 'whisper.cpp'
}

@test "whisper: whisper.cpp backend (stub whisper-cli) produces ok + vtt with NO api key" {
  command -v ffmpeg >/dev/null || skip "ffmpeg required for audio extraction"
  # Stub whisper-cli: writes whisper.cpp-schema JSON to <-of>.json (offsets in ms).
  cat > "$BIN/whisper-cli" <<'SH'
#!/usr/bin/env bash
of=""
while [[ $# -gt 0 ]]; do case "$1" in -of) of="$2"; shift 2;; *) shift;; esac; done
cat > "$of.json" <<'JSON'
{"result":{"language":"en"},"transcription":[{"offsets":{"from":0,"to":1500},"text":" hi from cpp"}]}
JSON
SH
  chmod +x "$BIN/whisper-cli"
  : > "$BATS_TEST_TMPDIR/ggml-large-v3-turbo-q5_0.bin"   # fake model file
  ffmpeg -nostdin -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 \
    "$BATS_TEST_TMPDIR/in.mp3" >/dev/null 2>&1

  run env -u GROQ_API_KEY -u OPENAI_API_KEY \
    PATH="$BIN:$PATH" \
    RESEARCH_ENGINE_WHISPER_CPP_MODEL="$BATS_TEST_TMPDIR/ggml-large-v3-turbo-q5_0.bin" \
    "$SCRIPT" transcribe "$BATS_TEST_TMPDIR/in.mp3" "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '"transcript_source": *"whisper"'
  echo "$output" | grep -q 'whisper.cpp:'
  [ -s "$WORK/whisper.vtt" ]
  grep -q 'WEBVTT' "$WORK/whisper.vtt"
  grep -q 'hi from cpp' "$WORK/whisper.vtt"
}

@test "whisper: Python mlx-whisper backend (stub module) produces ok + vtt with NO api key" {
  command -v ffmpeg >/dev/null || skip "ffmpeg required for audio extraction"
  [ -n "$PY3" ] || skip "python3 required"
  cat > "$MODS/mlx_whisper.py" <<'PY'
def transcribe(audio, path_or_hf_repo=None, **kw):
    return {"text": "hi there", "language": "en",
            "segments": [{"start": 0.0, "end": 1.0, "text": " hi there"}]}
PY
  ffmpeg -nostdin -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 \
    "$BATS_TEST_TMPDIR/in.mp3" >/dev/null 2>&1

  run env -u GROQ_API_KEY -u OPENAI_API_KEY \
    RESEARCH_ENGINE_WHISPER_DISABLE_CPP=1 RESEARCH_ENGINE_PYTHON="$PY3" PYTHONPATH="$MODS" \
    "$SCRIPT" transcribe "$BATS_TEST_TMPDIR/in.mp3" "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '"transcript_source": *"whisper"'
  echo "$output" | grep -q 'mlx-whisper:'
  [ -s "$WORK/whisper.vtt" ]
  grep -q 'hi there' "$WORK/whisper.vtt"
}

@test "whisper: local takes priority even when GROQ key is set (no network call)" {
  command -v ffmpeg >/dev/null || skip "ffmpeg required for audio extraction"
  [ -n "$PY3" ] || skip "python3 required"
  cat > "$MODS/mlx_whisper.py" <<'PY'
def transcribe(audio, path_or_hf_repo=None, **kw):
    return {"text": "local wins", "language": "en",
            "segments": [{"start": 0.0, "end": 1.0, "text": " local wins"}]}
PY
  ffmpeg -nostdin -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 \
    "$BATS_TEST_TMPDIR/in.mp3" >/dev/null 2>&1

  # A bogus GROQ key must not be reached because local succeeds first.
  run env GROQ_API_KEY=bogus-should-not-be-used \
    RESEARCH_ENGINE_WHISPER_DISABLE_CPP=1 RESEARCH_ENGINE_PYTHON="$PY3" PYTHONPATH="$MODS" \
    "$SCRIPT" transcribe "$BATS_TEST_TMPDIR/in.mp3" "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'mlx-whisper:'
  grep -q 'local wins' "$WORK/whisper.vtt"
}
