#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/classify_url.sh"

@test "youtube watch URL" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "$output" = "youtube" ]
}

@test "youtu.be short URL" {
  run "$SCRIPT" "https://youtu.be/dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "$output" = "youtube" ]
}

@test "arxiv abs URL" {
  run "$SCRIPT" "https://arxiv.org/abs/2301.12345"
  [ "$status" -eq 0 ]
  [ "$output" = "arxiv" ]
}

@test "arxiv pdf URL" {
  run "$SCRIPT" "https://arxiv.org/pdf/2301.12345.pdf"
  [ "$status" -eq 0 ]
  [ "$output" = "arxiv" ]
}

@test "github repo URL" {
  run "$SCRIPT" "https://github.com/anthropics/claude-code"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "huggingface model URL" {
  run "$SCRIPT" "https://huggingface.co/meta-llama/Llama-3-8B"
  [ "$status" -eq 0 ]
  [ "$output" = "huggingface" ]
}

@test "HN community URL" {
  run "$SCRIPT" "https://news.ycombinator.com/item?id=39000000"
  [ "$status" -eq 0 ]
  [ "$output" = "community" ]
}

@test "reddit community URL" {
  run "$SCRIPT" "https://www.reddit.com/r/LocalLLaMA/comments/abc/xyz/"
  [ "$status" -eq 0 ]
  [ "$output" = "community" ]
}

@test "generic blog URL falls back to blog" {
  run "$SCRIPT" "https://engineering.example.com/posts/some-post"
  [ "$status" -eq 0 ]
  [ "$output" = "blog" ]
}

@test "non-URL string classifies as topic" {
  run "$SCRIPT" "best practices for RAG pipelines"
  [ "$status" -eq 0 ]
  [ "$output" = "topic" ]
}

@test "empty input is an error" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}

@test "missing argument is an error" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
