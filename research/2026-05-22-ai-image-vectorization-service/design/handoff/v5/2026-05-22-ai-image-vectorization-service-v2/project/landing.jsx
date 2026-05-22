/* Landing page — Hero + supporting sections.
   Uses globals from components.jsx: Nav, Footer, Button, VectraMark, navigate, VECTRA_* */

const landingStyles = {
  page: {
    minHeight: "100vh",
    background: "#ffffff",
    color: VECTRA_INK,
    display: "flex",
    flexDirection: "column",
  },
  heroWrap: {
    position: "relative",
    overflow: "hidden",
  },
  hero: {
    maxWidth: 1200,
    margin: "0 auto",
    padding: "96px 28px 80px",
    display: "grid",
    gridTemplateColumns: "minmax(0, 1.05fr) minmax(0, 1fr)",
    gap: 64,
    alignItems: "center",
  },
  eyebrow: {
    display: "inline-flex",
    alignItems: "center",
    gap: 8,
    fontSize: 13,
    color: VECTRA_MUTED,
    background: VECTRA_SOFT,
    border: `1px solid ${VECTRA_LINE}`,
    padding: "6px 12px",
    borderRadius: 999,
    marginBottom: 24,
    letterSpacing: "-0.005em",
  },
  h1: {
    fontSize: 56,
    lineHeight: 1.04,
    letterSpacing: "-0.025em",
    fontWeight: 600,
    margin: "0 0 20px",
    color: VECTRA_INK,
  },
  h1Accent: {
    color: VECTRA_BLUE,
    fontStyle: "normal",
  },
  subtitle: {
    fontSize: 28,
    lineHeight: 1.35,
    letterSpacing: "-0.015em",
    fontWeight: 400,
    color: "#3f4654",
    margin: "0 0 36px",
    maxWidth: 560,
  },
  ctaRow: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    flexWrap: "wrap",
    marginBottom: 28,
  },
  trustRow: {
    display: "flex",
    alignItems: "center",
    gap: 16,
    fontSize: 13.5,
    color: VECTRA_MUTED,
    flexWrap: "wrap",
  },
  trustDot: {
    width: 6,
    height: 6,
    borderRadius: 999,
    background: "#22c55e",
    boxShadow: "0 0 0 4px rgba(34,197,94,0.15)",
  },
};

function HeroVisual() {
  // Original visual: side-by-side raster preview vs traced vector preview.
  const accent = VECTRA_BLUE;
  return (
    <div
      style={{
        position: "relative",
        background: "#fff",
        border: `1px solid ${VECTRA_LINE}`,
        borderRadius: 20,
        padding: 22,
        boxShadow: "0 30px 60px -30px rgba(11,13,18,0.18), 0 8px 24px -16px rgba(11,13,18,0.12)",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 18 }}>
        <div style={{ display: "flex", gap: 6 }}>
          <span style={{ width: 10, height: 10, borderRadius: 999, background: "#e5e7eb" }} />
          <span style={{ width: 10, height: 10, borderRadius: 999, background: "#e5e7eb" }} />
          <span style={{ width: 10, height: 10, borderRadius: 999, background: "#e5e7eb" }} />
        </div>
        <div style={{ fontSize: 11.5, letterSpacing: "0.06em", color: VECTRA_MUTED, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" }}>
          TRACE · 0.84s
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
        {/* Raster side — simulated pixel grid */}
        <div style={{ border: `1px solid ${VECTRA_LINE}`, borderRadius: 12, padding: 14, background: VECTRA_SOFT }}>
          <div style={{ fontSize: 11, letterSpacing: "0.08em", color: VECTRA_MUTED, marginBottom: 10, fontFamily: "ui-monospace, monospace" }}>INPUT.PNG</div>
          <svg viewBox="0 0 120 120" width="100%" style={{ display: "block", imageRendering: "pixelated" }}>
            {Array.from({ length: 12 }).map((_, y) =>
              Array.from({ length: 12 }).map((_, x) => {
                const cx = x - 5.5;
                const cy = y - 5.5;
                const d = Math.sqrt(cx * cx + cy * cy);
                const inside = d < 5;
                const ring = d > 3.2 && d < 4.6;
                let fill = "transparent";
                if (inside) fill = "#0b0d12";
                if (ring) fill = accent;
                // jagged outer noise on a couple of cells
                if ((x + y) % 7 === 0 && d > 4.8 && d < 5.6) fill = "#cdd5e1";
                return <rect key={`${x}-${y}`} x={x * 10} y={y * 10} width={10} height={10} fill={fill} />;
              })
            )}
          </svg>
        </div>

        {/* Vector side — smooth traced curves */}
        <div style={{ border: `1px solid ${VECTRA_LINE}`, borderRadius: 12, padding: 14, background: "#fff" }}>
          <div style={{ fontSize: 11, letterSpacing: "0.08em", color: VECTRA_MUTED, marginBottom: 10, fontFamily: "ui-monospace, monospace" }}>OUTPUT.SVG</div>
          <svg viewBox="0 0 120 120" width="100%" style={{ display: "block" }}>
            <circle cx="60" cy="60" r="42" fill="none" stroke={accent} strokeWidth="6" />
            <circle cx="60" cy="60" r="28" fill={VECTRA_INK} />
            {/* Trace animation outline */}
            <circle
              cx="60"
              cy="60"
              r="50"
              fill="none"
              stroke={accent}
              strokeWidth="1.4"
              strokeDasharray="6 6"
              opacity="0.5"
            />
            {/* Anchor points */}
            {[
              [60, 10], [110, 60], [60, 110], [10, 60],
            ].map(([cx, cy], i) => (
              <g key={i}>
                <rect x={cx - 3} y={cy - 3} width={6} height={6} fill="#fff" stroke={accent} strokeWidth="1.4" />
              </g>
            ))}
          </svg>
        </div>
      </div>

      <div style={{ marginTop: 16, display: "flex", justifyContent: "space-between", fontSize: 12, color: VECTRA_MUTED, fontFamily: "ui-monospace, monospace" }}>
        <span>144 × 144 px</span>
        <span style={{ color: VECTRA_BLUE }}>→</span>
        <span>1 path · ∞ scale</span>
      </div>
    </div>
  );
}

function HowItWorks() {
  const steps = [
    { n: "01", t: "Upload", d: "PNG, JPG, 또는 AI 생성 이미지를 드롭하세요. 최대 20MB." },
    { n: "02", t: "Auto-trace", d: "vtracer 기반 파이프라인이 색 영역을 분리하고 Bézier 곡선으로 변환합니다." },
    { n: "03", t: "Refine", d: "노드 단순화, 컬러 모드 (CMYK / Pantone), 텍스트 outline 변환을 자동 적용." },
    { n: "04", t: "Export", d: "SVG · AI · EPS · PDF/X-1a 패키지로 다운로드. 인쇄소에 그대로 전달." },
  ];
  return (
    <section id="how" style={{ maxWidth: 1200, margin: "0 auto", padding: "40px 28px 80px" }}>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 36, gap: 24, flexWrap: "wrap" }}>
        <h2 style={{ fontSize: 28, fontWeight: 600, letterSpacing: "-0.02em", margin: 0 }}>How it works</h2>
        <p style={{ color: VECTRA_MUTED, fontSize: 15, maxWidth: 480, margin: 0 }}>
          업로드부터 인쇄 가능한 패키지까지, 평균 3초. 결과가 마음에 안 들면 후처리 파라미터를 직접 조절하거나 디자이너 리뷰를 요청할 수 있습니다.
        </p>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 20 }}>
        {steps.map((s) => (
          <div key={s.n} style={{ border: `1px solid ${VECTRA_LINE}`, borderRadius: 14, padding: 22, background: "#fff" }}>
            <div style={{ fontSize: 12, letterSpacing: "0.1em", color: VECTRA_BLUE, fontFamily: "ui-monospace, monospace", marginBottom: 14 }}>{s.n}</div>
            <div style={{ fontSize: 17, fontWeight: 600, marginBottom: 8, letterSpacing: "-0.01em" }}>{s.t}</div>
            <div style={{ fontSize: 14, color: VECTRA_MUTED, lineHeight: 1.55 }}>{s.d}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

function FormatStrip() {
  const formats = ["SVG", "AI", "EPS", "PDF/X-1a", "PNG"];
  return (
    <section style={{ maxWidth: 1200, margin: "0 auto", padding: "20px 28px 0" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 20, padding: "20px 24px", background: VECTRA_SOFT, border: `1px solid ${VECTRA_LINE}`, borderRadius: 14, flexWrap: "wrap" }}>
        <span style={{ fontSize: 13, color: VECTRA_MUTED, letterSpacing: "0.05em" }}>EXPORT FORMATS</span>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          {formats.map((f) => (
            <span key={f} style={{ fontSize: 13, fontWeight: 500, padding: "6px 12px", background: "#fff", border: `1px solid ${VECTRA_LINE}`, borderRadius: 999, fontFamily: "ui-monospace, monospace", letterSpacing: "0.02em" }}>
              {f}
            </span>
          ))}
        </div>
        <span style={{ fontSize: 13, color: VECTRA_MUTED, marginLeft: "auto" }}>
          CMYK · spot color · text outlined · ≥ 0.5pt
        </span>
      </div>
    </section>
  );
}

function Landing() {
  return (
    <div style={landingStyles.page}>
      <Nav current="/" />

      <div style={landingStyles.heroWrap} className="hero-grid">
        <div style={landingStyles.hero}>
          <div className="v-fadeup">
            <span style={landingStyles.eyebrow}>
              <span style={{ width: 6, height: 6, borderRadius: 999, background: VECTRA_BLUE }} />
              v0.4 · vtracer + post-processing pipeline
            </span>
            <h1 style={landingStyles.h1}>
              Vectorize <em style={landingStyles.h1Accent}>raster art</em>
              <br />
              that print shops accept.
            </h1>
            <p style={landingStyles.subtitle}>
              AI 로고와 일러스트를 단숨에 SVG · AI · EPS 로. 인쇄소가 거절하지 않는 깨끗한 벡터, 평균 3초.
            </p>
            <div style={landingStyles.ctaRow}>
              <a
                href="#/upload"
                data-testid="cta-try"
                onClick={(e) => { e.preventDefault(); navigate("#/upload"); }}
                style={{ textDecoration: "none" }}
              >
                <Button variant="primary">
                  Try free
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                    <path d="M3 7h8m0 0L7.5 3.5M11 7l-3.5 3.5" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </Button>
              </a>
              <a
                href="#how"
                onClick={(e) => {
                  e.preventDefault();
                  document.getElementById("how")?.scrollIntoView({ behavior: "smooth", block: "start" });
                }}
                style={{ textDecoration: "none" }}
              >
                <Button variant="ghost">See how it works</Button>
              </a>
            </div>
            <div style={landingStyles.trustRow}>
              <span style={landingStyles.trustDot} />
              <span>No signup for first 3 conversions</span>
              <span style={{ color: VECTRA_LINE }}>·</span>
              <span>SVG · AI · EPS · PDF/X-1a</span>
              <span style={{ color: VECTRA_LINE }}>·</span>
              <span>CMYK ready</span>
            </div>
          </div>

          <div className="v-fadeup" style={{ animationDelay: "0.08s" }}>
            <HeroVisual />
          </div>
        </div>
      </div>

      <FormatStrip />
      <HowItWorks />

      <Footer />
    </div>
  );
}

window.Landing = Landing;
