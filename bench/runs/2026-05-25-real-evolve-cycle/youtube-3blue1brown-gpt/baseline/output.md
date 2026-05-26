# Deep Research Report: "But what is a GPT? Visual intro to transformers"

## Metadata

| Field | Value |
|---|---|
| **Title** | But what is a GPT? Visual intro to transformers \| Chapter 5, Deep Learning |
| **Alternate title** | Transformers, the tech behind LLMs \| Deep Learning Chapter 5 |
| **Channel / Author** | 3Blue1Brown (Grant Sanderson); text adaptation by Justin Sun |
| **URL** | https://www.youtube.com/watch?v=wjZofJX0v4M |
| **Companion lesson** | https://www.3blue1brown.com/lessons/gpt |
| **Published** | April 1, 2024 |
| **Length** | ~27 minutes |
| **Series** | Deep Learning, Chapter 5 (first of a multi-part transformer series; Chapter 6 "Attention in transformers" followed April 7, 2024) |
| **Animation tooling** | Manim (Sanderson's custom Python animation library) |

---

## Executive Summary

This is the opening installment of 3Blue1Brown's transformer series — a **visual, intuition-first introduction** to how Generative Pre-trained Transformers (GPTs) work. Rather than diving straight into the attention mechanism (deferred to Chapter 6), it establishes the **end-to-end data flow** of a transformer: text → tokens → embedding vectors → alternating attention/MLP blocks → an unembedding step → a probability distribution over the next token, sampled and repeated. The video uses GPT-3's published dimensions as a concrete running example and builds geometric intuition for word embeddings, dot products, the softmax function, and the temperature parameter.

The acronym is unpacked literally: **G**enerative (it generates new text), **P**re-trained (trained in advance on large corpora, with the possibility of later fine-tuning), and **T**ransformer — the architectural innovation that is "the main driving force behind the recent boom in AI."

---

## Core Claims and Concepts

### 1. A GPT is a next-token predictor run in a loop
The central claim: a GPT "takes in a piece of text, then produces a prediction of what comes next, in the form of a probability distribution." Long-form generation is achieved by the **predict → sample → repeat** loop: predict a distribution over the next token, sample one, append it to the input, and feed it back in. This is why the same model with the same prompt can produce different outputs on different runs.

### 2. The high-level pipeline (the "data flow")
The video frames the whole network as a sequence of stages:
1. **Tokenization** — input text is broken into tokens (words or sub-word fragments).
2. **Embedding** — each token is mapped to a high-dimensional vector via a learned embedding matrix.
3. **Attention blocks** — vectors "talk to each other," updating their values based on surrounding context.
4. **Multilayer perceptron (MLP) / feed-forward blocks** — each vector is processed in parallel through the same transformation.
5. **Repetition** — attention and MLP blocks alternate many times.
6. **Unembedding + softmax** — the final vector is mapped to logits over the vocabulary and normalized into a probability distribution.

### 3. Embeddings encode meaning geometrically
Words become vectors in a high-dimensional space where **"words with similar meanings tend to land on vectors close to each other."** Crucially, *directions* in this space carry semantic meaning. The video's signature example is the analogy structure:

> woman − man ≈ queen − king

Other directional examples discussed include gender and nationality/geography relationships that emerge automatically from training (e.g., differences between country and capital vectors). The takeaway: the model is never told these relationships explicitly; they fall out of the learning process.

### 4. Dot products measure alignment
The dot product is introduced as the tool for measuring how aligned two vectors are: **positive** when they point in similar directions, **zero** when perpendicular, **negative** when opposed. This is positioned as the mathematical primitive underlying both semantic similarity and (later) attention.

### 5. Context flows into each vector
As vectors pass through the network's layers, each one absorbs meaning from its surroundings — the example being how an embedding for a word can shift depending on the words around it. GPT-3 processed a fixed **context window of 2,048 tokens**, which bounds how much surrounding text can influence any prediction.

### 6. Softmax and temperature
The final logits are converted into a valid probability distribution by **softmax**: exponentiate each value (e raised to the value), then divide by the sum so outputs lie in (0,1) and sum to 1. A **temperature** parameter rescales the logits before softmax:
- **Higher temperature** → flatter, more uniform distribution → more varied / "creative" (and more error-prone) output.
- **Lower temperature** → probability concentrates on the highest-scoring token → more predictable, deterministic output.

### 7. Parameters are the "knobs" learned by training
The model's behavior is entirely encoded in its weight matrices ("parameters"), tuned via backpropagation on training data. The video uses **GPT-3's 175 billion parameters**, organized across roughly **28,000 matrices** in about eight categories, as its concrete reference point.

---

## Key Numbers (GPT-3, as cited in the video)

| Quantity | Value |
|---|---|
| Total parameters | 175 billion |
| Vocabulary size (tokens) | 50,257 |
| Embedding dimension | 12,288 |
| Context window | 2,048 tokens |
| Embedding matrix (W_E) parameters | 50,257 × 12,288 ≈ **617 million** |
| Unembedding matrix (W_U) parameters | ≈ **617 million** (structurally mirrors W_E) |
| Approx. matrix count | ~28,000 matrices across ~8 categories |

Note that the embedding + unembedding matrices together (~1.2 billion parameters) are only a small fraction of the full 175 billion — most of the parameters live in the attention and MLP blocks, which later chapters address.

---

## Notable Quotes / Framing

- GPT = "Generative Pre-trained Transformer," with the **transformer** being "the main driving force behind the recent boom in AI."
- A GPT "produce[s] a prediction of what comes next, in the form of a probability distribution."
- On embeddings: "words with similar meanings tend to land on vectors close to each other," and directions in embedding space encode semantic relationships.
- Grant Sanderson framed the release as "the first of what will be several chapters about this topic," noting transformers were "one of the most requested topics for the channel in the last year or two."

---

## Pedagogical Structure

The video is deliberately **scaffolding-first**: it explains everything *around* attention (embeddings, the overall block structure, unembedding, softmax, temperature, parameter counting) so that the dedicated attention chapter can focus purely on that mechanism. It assumes loose familiarity with the earlier "Deep Learning" chapters (neural networks, backpropagation) but is largely self-contained. The explanation leans heavily on geometric visualization (vectors in space, directional analogies) rather than equations or code.

---

## Limitations and Caveats

These reflect both the inherent scope of an introductory explainer and points the video itself flags or glosses over:

1. **Attention is deferred, not explained.** The single most important and novel component of the transformer — self-attention — is only previewed here; the actual mechanics are saved for Chapter 6. A viewer watching only this video does not learn how attention works.

2. **MLP / feed-forward blocks are mentioned but not unpacked.** The video names the per-token MLP step and notes a large share of parameters live there, but defers the detailed treatment to a later chapter.

3. **GPT-3-specific numbers may not generalize.** All concrete figures (175B parameters, 50,257-token vocabulary, 12,288 dims, 2,048-token context) are from GPT-3 (2020). Newer models use larger context windows, different tokenizers, and architectural variations, so the specifics are illustrative rather than current.

4. **Simplifications for intuition.** The embedding-direction analogies (woman − man ≈ queen − king) are a well-known, intuitive illustration but are an idealization — real embedding arithmetic is noisier and the clean parallelograms are approximate. The video presents them as intuition pumps, not exact identities.

5. **Encoder/decoder distinction is largely omitted.** The original "Attention Is All You Need" transformer is an encoder–decoder model; GPTs are decoder-only. The video focuses on the GPT (decoder-only, autoregressive) story and does not dwell on the broader transformer taxonomy or non-text modalities.

6. **Training is treated as a black box.** Backpropagation and "tuning weights on training data" are referenced, but the optimization process, data curation, and pre-training/fine-tuning/RLHF pipeline are out of scope.

7. **Conceptual, not implementation-level.** No code, no exact matrix-multiplication walkthroughs of attention, and no discussion of practical engineering (positional encodings get light treatment, batching, hardware, etc.).

---

## Reception and Context

- The companion written lesson is hosted at 3blue1brown.com and was adapted to text by Justin Sun.
- Community reception was strongly positive; a representative comment called it "by far the best resource I've found for gaining intuition" about transformers.
- It sits within 3Blue1Brown's broader, highly regarded "Neural Networks / Deep Learning" series and is frequently recommended as an entry point before reading the original transformer paper.
- Chapter 6, "Attention in transformers, step-by-step," published April 7, 2024, is the direct continuation and is where the attention mechanism is actually derived.

---

## Sources

- [3Blue1Brown official lesson — "Transformers, the tech behind LLMs / But what is a GPT?"](https://www.3blue1brown.com/lessons/gpt)
- [YouTube video (wjZofJX0v4M)](https://www.youtube.com/watch?v=wjZofJX0v4M)
- [Grant Sanderson, "But what is a GPT?" (Substack)](https://3blue1brown.substack.com/p/but-what-is-a-gpt)
- [3Blue1Brown lesson — "Attention in transformers, step-by-step" (Chapter 6)](https://www.3blue1brown.com/lessons/attention)
- [Simon Willison — "3Blue1Brown: Attention in transformers, visually explained"](https://simonwillison.net/2024/Apr/11/3blue1brown/)
- [Rohan Kotwani, "But what is a GPT? Visual intro to Transformers" (Medium)](https://medium.com/lazy-by-design/but-what-is-a-gpt-visual-intro-to-transformers-3blue1brown-d078447b8ef4)
- [Class Central course listing](https://www.classcentral.com/course/youtube-but-what-is-a-gpt-visual-intro-to-transformers-deep-learning-chapter-5-287857)
- [Transcript mirror (ytscribe / pickscribe)](https://pickscribe.com/v/wjZofJX0v4M)

*Research compiled May 25, 2026 using web search and page fetches. Direct verbatim transcript access was limited; technical figures and claims were cross-checked across the official 3Blue1Brown lesson page, Grant Sanderson's own post, and multiple independent summaries.*
