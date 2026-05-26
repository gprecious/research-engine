# Deep Research: "Let's build GPT: from scratch, in code, spelled out." (Andrej Karpathy)

**Source video:** <https://www.youtube.com/watch?v=kCc8FmEb1nY>
**Author:** Andrej Karpathy (former Director of AI at Tesla; founding member of OpenAI)
**Series:** Lecture 7 of *Neural Networks: Zero to Hero*
**Published:** January 2023 (announced on X on 2023-01-17)
**Runtime:** ~1h56m (the course page lists ~2h13m including the appended Q&A / addendum sections)
**Companion code:** `karpathy/ng-video-lecture` (GitHub) and the production-oriented `karpathy/nanoGPT`

---

## 1. One-paragraph summary

The video is a line-by-line, code-first lecture in which Karpathy builds and trains a small Generatively Pretrained Transformer (GPT) from scratch in PyTorch, following the architecture from the 2017 paper *Attention Is All You Need* and OpenAI's GPT-2/GPT-3. He starts from a character-level bigram baseline on a ~1MB "tiny Shakespeare" dataset (vocabulary of 65 unique characters) and incrementally adds the components of a Transformer decoder — self-attention, scaled dot-product attention, causal masking, positional embeddings, multi-head attention, feed-forward layers, residual connections, layer normalization, and dropout — ending with the core of `nanoGPT`. The pedagogical goal is to demystify the architecture behind ChatGPT by showing that the model itself is conceptually simple and reproducible in a few hundred lines of code.

---

## 2. Context and positioning

- This is the seventh and capstone lecture of the *Zero to Hero* series, which begins with micrograd (manual backprop) and the makemore series (autoregressive language modeling, tensors, `nn` basics). Karpathy explicitly recommends watching the earlier makemore videos first so viewers are comfortable with the autoregressive framework and PyTorch fundamentals.
- Stated prerequisites: "solid programming (Python)" and "intro-level math (e.g., derivative, gaussian)."
- The lecture was released roughly two months after ChatGPT's public launch (Nov 2022), and is framed as an answer to the question "what is the neural network under the hood of ChatGPT?"
- GitHub Copilot is used live during the lecture to help write code.

---

## 3. Structure / progression of the build

The lecture proceeds as an incremental construction, each step a runnable checkpoint:

1. **Intro & framing** — ChatGPT, Transformers, and the goal of building a tiny GPT.
2. **Data** — read and explore the tiny-Shakespeare text; build a character-level tokenizer (encode/decode by mapping each of 65 characters to an integer); create train/validation splits.
3. **Chunking & batching** — fixed-length context blocks (`block_size`), with inputs `x` and shifted targets `y`; stack into batches.
4. **Bigram baseline** — a single embedding-table model (`nn.Embedding(vocab_size, vocab_size)`) that predicts the next token from only the current token; train with cross-entropy and generate samples.
5. **Port to a script** — refactor into a clean training/generation script.
6. **The "mathematical trick" in self-attention** — develop weighted aggregation in four versions, from explicit averaging loops to a matrix-multiply with a lower-triangular matrix, then to a softmax formulation. This is the conceptual core of the lecture.
7. **Single self-attention head** — introduce query, key, and value projections; compute attention weights; apply causal masking.
8. **Scaled attention** — divide scores by `sqrt(head_size)` to control variance.
9. **Positional embeddings** — add a position embedding table to the token embeddings.
10. **Multi-head attention** — run several heads in parallel and concatenate.
11. **Feed-forward layers** — per-token MLP after attention.
12. **Transformer blocks** — stack attention + feed-forward, then add **residual connections** and **layer normalization** (pre-norm) and **dropout** to enable training a deeper network.
13. **Scaling up** — increase layers/heads/embedding size and train the larger model (the README notes a model on the order of ~10M parameters).
14. **Closing comparisons** — encoder vs. decoder Transformers; how this decoder-only setup differs from the original encoder–decoder; relationship to GPT-2/GPT-3, and the later stages (fine-tuning, RLHF) that turn a base model into an assistant like ChatGPT.

---

## 4. Core claims and key ideas

- **GPT = a Transformer decoder trained as an autoregressive language model.** The model predicts the next token given previous tokens; "generative pretraining" is simply this next-token objective at scale.
- **Self-attention is a data-dependent weighted aggregation over a set of tokens.** Each token emits a **query** ("what am I looking for"), a **key** ("what do I contain"), and a **value** ("what I will communicate if attended to"). Attention weights are the softmax of query·key affinities; the output is the weighted sum of values.
  - Karpathy's framing (paraphrased from the lecture): "Every single token will emit two vectors — a query and a key. The query vector is *what am I looking for*, and the key vector is *what do I contain*."
- **Attention has no notion of space; it operates over sets.** Because attention is permutation-equivariant, position must be injected explicitly — hence **positional embeddings** added to token embeddings.
- **Causal masking enforces autoregression.** A lower-triangular mask (`tril`) sets future positions to `-inf` before softmax (`wei.masked_fill(tril == 0, float('-inf'))`), so a token can only attend to itself and the past. This is what makes it a *decoder* (vs. an encoder, which allows full bidirectional attention).
- **Scaling by 1/sqrt(head_size) keeps softmax well-behaved.** Without scaling, dot products grow with dimension, pushing softmax toward a one-hot ("too peaky") distribution that effectively turns attention into a hard lookup of a single token; the scaling preserves a diffuse, trainable distribution at initialization.
- **Multi-head attention** lets the model attend to different kinds of information in parallel subspaces, then concatenates the results.
- **Residual connections + pre-norm LayerNorm + dropout** are the optimization tricks that make a deep stack trainable: blocks compute `x = x + sa(ln1(x))` and `x = x + ffwd(ln2(x))`, giving gradients a clean "highway."
- **The architecture is the easy part.** The genuinely hard parts of building a real GPT are data collection, compute (GPUs), distributed-training infrastructure, and the post-training alignment stages — not the model code.

---

## 5. Citations and referenced works

- **Vaswani et al., "Attention Is All You Need" (2017)** — the Transformer paper the architecture follows.
- **OpenAI GPT-2 and GPT-3 papers / models** — the production systems whose decoder-only design this lecture mirrors.
- **ChatGPT (OpenAI, 2022)** — the motivating application; Karpathy notes that turning a base GPT into ChatGPT requires further fine-tuning and RLHF not covered in this video.
- **`karpathy/nanoGPT`** — the practical sibling repo. It reproduces GPT-2 (124M) on OpenWebText (~4 days on one 8×A100 40GB node), with ~300-line train and model files, and also supports a 3-minute character-level Shakespeare demo (6 layers, 6 heads, 384 channels, block size 256).
- **`karpathy/ng-video-lecture`** — the exact lecture code (`bigram.py`, `gpt.py`, `input.txt`); designed to be hacked and walked through via `git log`.
- **micrograd / makemore (earlier Zero to Hero lectures)** — recommended prerequisites.
- Karpathy also pointed (in discussion) to the **Meta OPT training logbook** as a record of real-world large-model training pain.

---

## 6. Reception

- **Strongly positive.** On Hacker News and across follow-up blog reviews, the dominant reaction is praise for clarity. One commenter (an instructor) said they "learn something new about the material and about how to teach it," and another that "when Karpathy explains stuff it just clicks in my head."
- The lecture is widely cited as a canonical entry point for understanding Transformers, and has spawned many reimplementations, written walkthroughs, and visual "deep dive" companion posts.
- Reviewers single out specific intuitions as the most valuable takeaways: the asymmetry of queries vs. keys, GPU-friendly masked attention, and the clean separation of "where to look" (query/key) from "what to say" (value).

---

## 7. Limitations and caveats

**Limitations the lecture itself acknowledges:**
- **Toy scale.** The trained model is ~10M parameters on ~1MB of Shakespeare — orders of magnitude below GPT-3 (175B). It demonstrates mechanism, not capability.
- **Character-level tokenization only.** It uses a 65-character vocabulary; real systems use sub-word/byte-pair tokenization, which the video does not cover (Karpathy later made a separate "Let's build the GPT Tokenizer" lecture for this).
- **No alignment stages.** Pretraining only — supervised fine-tuning, instruction tuning, and RLHF (the steps that produce an assistant like ChatGPT) are mentioned but not built.
- **Decoder-only.** Encoder and encoder–decoder variants are discussed conceptually but not implemented.
- **Weight initialization is under-treated.** The companion repo README notes initialization "isn't covered to the extent that it should be," causing slower convergence; it points readers to `nanoGPT/model.py` for proper init, and warns the lecture code differs slightly from full nanoGPT so direct code transfer is not clean.

**Limitations noted by the community / inherent to the format:**
- **Prerequisite-heavy.** Without the earlier makemore/micrograd background and comfort with PyTorch tensors and broadcasting, parts (especially the matrix-multiply "trick" and batched attention) can be hard to follow.
- **Not production guidance.** It deliberately omits the genuinely hard engineering of real GPTs: data pipelines, multi-GPU/distributed training, mixed precision, evaluation, and scaling laws.
- **Pedagogical code, not optimized code.** The code favors readability over performance/correctness edge cases (e.g., simplified attention without flash-attention kernels, no KV-caching for generation).

---

## 8. Key takeaways for a reader/practitioner

- A GPT is conceptually small: a stack of identical decoder blocks (masked multi-head self-attention + per-token MLP, wrapped in residual + pre-norm), trained to predict the next token.
- The "magic" of attention reduces to a learned, data-dependent weighted average; masking makes it causal, scaling keeps it numerically stable, and positional embeddings restore order information.
- Scale (data + parameters + compute) and post-training alignment — not the architecture — are what separate this teaching model from ChatGPT.
- Best paired with the `ng-video-lecture` repo for hands-on `git log` walkthrough and `nanoGPT` for a production-grade reference implementation.

---

## Sources

- [Andrej Karpathy — Let's build GPT (YouTube)](https://www.youtube.com/watch?v=kCc8FmEb1nY)
- [Andrej Karpathy on X — lecture announcement](https://x.com/karpathy/status/1615398117683388417)
- [Neural Networks: Zero to Hero (course page)](https://karpathy.ai/zero-to-hero.html)
- [karpathy/ng-video-lecture (lecture code, GitHub)](https://github.com/karpathy/ng-video-lecture)
- [karpathy/nanoGPT (GitHub)](https://github.com/karpathy/nanoGPT)
- [Hacker News discussion of the video](https://news.ycombinator.com/item?id=34414716)
- [Class Central — course listing / syllabus](https://www.classcentral.com/course/youtube-let-s-build-gpt-from-scratch-in-code-spelled-out-127034)
- [Hun Tae Kim — "Karpathy's 'Let's Build GPT From Scratch' — Review"](https://ht0324.github.io/blog/2025/Karpathy-gpt/)
- [Francesco Pochetti — "A visual deep dive into the Transformer's architecture: turning Karpathy's masterclass into pictures"](https://francescopochetti.com/a-visual-deep-dive-into-the-transformers-architecture-turning-karpathys-masterclass-into-pictures/)
- [Belinda Mo — "Build GPT from scratch, with Karpathy" (study notes)](https://write.justanexperiment.com/%F0%9F%8F%A1-earth/Computer-Science/Artificial-Intelligence/Build-GPT-from-scratch,-with-Karpathy)
- [Simon Willison — Running nanoGPT on a MacBook M2](https://til.simonwillison.net/llms/nanogpt-shakespeare-m2)
