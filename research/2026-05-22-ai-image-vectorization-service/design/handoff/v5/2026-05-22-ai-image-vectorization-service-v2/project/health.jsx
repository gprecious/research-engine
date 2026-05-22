/* Health check page — minimal "OK" centered. */

function Health() {
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#ffffff",
        color: VECTRA_INK,
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        flexDirection: "column",
        gap: 14,
      }}
    >
      <span
        style={{
          width: 10,
          height: 10,
          borderRadius: 999,
          background: "#22c55e",
          boxShadow: "0 0 0 6px rgba(34,197,94,0.15)",
        }}
        aria-hidden="true"
      />
      <div style={{ fontSize: 40, letterSpacing: "0.04em", fontWeight: 500 }}>OK</div>
      <div style={{ fontSize: 12, color: VECTRA_MUTED, letterSpacing: "0.1em" }}>
        VECTRA · 200
      </div>
    </div>
  );
}

window.Health = Health;
