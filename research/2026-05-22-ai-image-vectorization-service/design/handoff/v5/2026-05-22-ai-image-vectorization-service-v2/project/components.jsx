/* Shared UI primitives — kept tiny, inline-style first. */

const VECTRA_BLUE = "#2f6bff";
const VECTRA_BLUE_DARK = "#1f55e0";
const VECTRA_INK = "#0b0d12";
const VECTRA_MUTED = "#6b7280";
const VECTRA_LINE = "rgba(11,13,18,0.08)";
const VECTRA_SOFT = "#f6f7f9";

function navigate(hash) {
  if (window.location.hash !== hash) {
    window.location.hash = hash;
  } else {
    // Force a re-render-friendly notification even if already there
    window.dispatchEvent(new HashChangeEvent("hashchange"));
  }
}

const navStyles = {
  bar: {
    position: "sticky",
    top: 0,
    zIndex: 50,
    backdropFilter: "saturate(140%) blur(12px)",
    WebkitBackdropFilter: "saturate(140%) blur(12px)",
    background: "rgba(255,255,255,0.78)",
    borderBottom: `1px solid ${VECTRA_LINE}`,
  },
  inner: {
    maxWidth: 1200,
    margin: "0 auto",
    padding: "16px 28px",
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 24,
  },
  brand: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    fontWeight: 600,
    letterSpacing: "-0.01em",
    fontSize: 17,
    color: VECTRA_INK,
    textDecoration: "none",
  },
  links: {
    display: "flex",
    alignItems: "center",
    gap: 28,
    fontSize: 14.5,
    color: "#3f4654",
  },
  link: {
    textDecoration: "none",
    color: "#3f4654",
    padding: "6px 0",
  },
  cta: {
    fontSize: 14,
    padding: "9px 16px",
    borderRadius: 999,
    background: VECTRA_INK,
    color: "white",
    border: "1px solid " + VECTRA_INK,
    fontWeight: 500,
    textDecoration: "none",
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
  },
};

function VectraMark({ size = 22 }) {
  // Original, geometric mark — three nested paths suggesting raster→vector trace.
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="2" y="2" width="20" height="20" rx="5" fill={VECTRA_INK} />
      <path
        d="M6 16 L10 8 L14 16"
        stroke="white"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <path
        d="M14 16 L18 8"
        stroke={VECTRA_BLUE}
        strokeWidth="1.8"
        strokeLinecap="round"
        fill="none"
      />
      <circle cx="18" cy="8" r="1.4" fill={VECTRA_BLUE} />
    </svg>
  );
}

function Nav({ current }) {
  return (
    <nav style={navStyles.bar}>
      <div style={navStyles.inner}>
        <a href="#/" style={navStyles.brand} onClick={(e) => { e.preventDefault(); navigate("#/"); }}>
          <VectraMark />
          <span>Vectra</span>
          <span style={{ fontSize: 11, color: VECTRA_MUTED, fontWeight: 500, marginLeft: 4, padding: "2px 6px", border: "1px solid " + VECTRA_LINE, borderRadius: 4, letterSpacing: "0.04em" }}>BETA</span>
        </a>
        <div style={navStyles.links}>
          <a href="#/" style={{ ...navStyles.link, color: current === "/" ? VECTRA_INK : "#3f4654", fontWeight: current === "/" ? 500 : 400 }}
             onClick={(e) => { e.preventDefault(); navigate("#/"); }}>Product</a>
          <a href="#/" style={navStyles.link} onClick={(e) => { e.preventDefault(); navigate("#/"); document.getElementById("how")?.scrollIntoView({ behavior: "smooth", block: "start" }); }}>How it works</a>
          <a href="#/" style={navStyles.link} onClick={(e) => { e.preventDefault(); navigate("#/"); document.getElementById("pricing")?.scrollIntoView({ behavior: "smooth", block: "start" }); }}>Pricing</a>
          <a
            href="#/upload"
            data-testid="cta-try"
            style={navStyles.cta}
            onClick={(e) => { e.preventDefault(); navigate("#/upload"); }}
          >
            Try free
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 6h6m0 0L6 3m3 3L6 9" stroke="white" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/></svg>
          </a>
        </div>
      </div>
    </nav>
  );
}

function Footer() {
  return (
    <footer style={{ borderTop: `1px solid ${VECTRA_LINE}`, marginTop: 96, padding: "40px 28px 56px", background: "#fff" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto", display: "flex", justifyContent: "space-between", alignItems: "flex-end", flexWrap: "wrap", gap: 24 }}>
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
            <VectraMark size={20} />
            <strong style={{ fontSize: 15 }}>Vectra</strong>
          </div>
          <div style={{ fontSize: 13, color: VECTRA_MUTED, maxWidth: 380 }}>
            AI 이미지를 인쇄소가 받는 벡터 파일로. 로고와 일러스트를 위한 raster-to-vector 파이프라인.
          </div>
        </div>
        <div style={{ display: "flex", gap: 28, fontSize: 13, color: VECTRA_MUTED }}>
          <a href="#/health" style={{ color: VECTRA_MUTED, textDecoration: "none" }} onClick={(e) => { e.preventDefault(); navigate("#/health"); }}>Status</a>
          <a href="#/" style={{ color: VECTRA_MUTED, textDecoration: "none" }} onClick={(e) => e.preventDefault()}>Docs</a>
          <a href="#/" style={{ color: VECTRA_MUTED, textDecoration: "none" }} onClick={(e) => e.preventDefault()}>Contact</a>
          <span>© 2026 Vectra Labs</span>
        </div>
      </div>
    </footer>
  );
}

function Button({ children, variant = "primary", testId, ...props }) {
  const base = {
    fontSize: 15,
    fontWeight: 500,
    padding: "12px 22px",
    borderRadius: 999,
    border: "1px solid transparent",
    transition: "transform 0.06s ease, background 0.15s ease, border-color 0.15s ease",
    display: "inline-flex",
    alignItems: "center",
    gap: 8,
    lineHeight: 1,
    letterSpacing: "-0.005em",
  };
  const variants = {
    primary: {
      background: VECTRA_BLUE,
      color: "white",
      borderColor: VECTRA_BLUE,
    },
    dark: {
      background: VECTRA_INK,
      color: "white",
      borderColor: VECTRA_INK,
    },
    ghost: {
      background: "transparent",
      color: VECTRA_INK,
      borderColor: VECTRA_LINE,
    },
    soft: {
      background: VECTRA_SOFT,
      color: VECTRA_INK,
      borderColor: VECTRA_LINE,
    },
  };
  return (
    <button
      data-testid={testId}
      style={{ ...base, ...variants[variant], ...(props.disabled ? { opacity: 0.5, cursor: "not-allowed" } : {}) }}
      onMouseDown={(e) => { if (!props.disabled) e.currentTarget.style.transform = "scale(0.98)"; }}
      onMouseUp={(e) => { e.currentTarget.style.transform = "scale(1)"; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = "scale(1)"; }}
      {...props}
    >
      {children}
    </button>
  );
}

Object.assign(window, {
  Nav, Footer, Button, VectraMark, navigate,
  VECTRA_BLUE, VECTRA_BLUE_DARK, VECTRA_INK, VECTRA_MUTED, VECTRA_LINE, VECTRA_SOFT,
});
