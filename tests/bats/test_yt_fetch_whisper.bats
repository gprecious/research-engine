#!/usr/bin/env bats

# Covers the local-first Whisper fallback in scripts/yt_fetch.sh:
#  - no backend at all → helpful partial that points at local install
#  - local backend present (stubbed mlx_whisper) → transcribes with NO api key

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/yt_fetch.sh"

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  MODS="$BATS_TEST_TMPDIR/mods"
  mkdir -p "$MODS"
}

@test "whisper: no backend (local disabled + no keys) returns helpful partial" {
  run env -u GROQ_API_KEY -u OPENAI_API_KEY RESEARCH_ENGINE_WHISPER_DISABLE_LOCAL=1 \
    "$SCRIPT" transcribe /no/such/audio.mp3 "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '"transcript_source": *"none"'
  echo "$output" | grep -q 'mlx-whisper'
}

@test "whisper: local backend (stub mlx_whisper) produces ok + vtt with NO api key" {
  command -v ffmpeg >/dev/null || skip "ffmpeg required for audio extraction"
  cat > "$MODS/mlx_whisper.py" <<'PY'
def transcribe(audio, path_or_hf_repo=None, **kw):
    return {"text": "hi there", "language": "en",
            "segments": [{"start": 0.0, "end": 1.0, "text": " hi there"}]}
PY
  ffmpeg -nostdin -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 \
    "$BATS_TEST_TMPDIR/in.mp3" >/dev/null 2>&1

  run env -u GROQ_API_KEY -u OPENAI_API_KEY PYTHONPATH="$MODS" \
    "$SCRIPT" transcribe "$BATS_TEST_TMPDIR/in.mp3" "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '"transcript_source": *"whisper"'
  echo "$output" | grep -q 'mlx-whisper:'
  [ -s "$WORK/whisper.vtt" ]
  grep -q 'WEBVTT' "$WORK/whisper.vtt"
  grep -q 'hi there' "$WORK/whisper.vtt"
}

@test "whisper: local takes priority even when GROQ key is set (no network call)" {
  command -v ffmpeg >/dev/null || skip "ffmpeg required for audio extraction"
  cat > "$MODS/mlx_whisper.py" <<'PY'
def transcribe(audio, path_or_hf_repo=None, **kw):
    return {"text": "local wins", "language": "en",
            "segments": [{"start": 0.0, "end": 1.0, "text": " local wins"}]}
PY
  ffmpeg -nostdin -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 \
    "$BATS_TEST_TMPDIR/in.mp3" >/dev/null 2>&1

  # A bogus GROQ key must not be reached because local succeeds first.
  run env GROQ_API_KEY=bogus-should-not-be-used PYTHONPATH="$MODS" \
    "$SCRIPT" transcribe "$BATS_TEST_TMPDIR/in.mp3" "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'mlx-whisper:'
  grep -q 'local wins' "$WORK/whisper.vtt"
}
