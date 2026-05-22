'use client';
/* Upload page — verbatim port of claude.ai/design v5 handoff upload.jsx.
   Visual + interaction model preserved. */
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import {
  Nav,
  Footer,
  Button,
  VECTRA_BLUE,
  VECTRA_INK,
  VECTRA_LINE,
  VECTRA_MUTED,
  VECTRA_SOFT,
} from '../components-vectra';

const uploadStyles = {
  page: {
    minHeight: '100vh',
    background: '#ffffff',
    color: VECTRA_INK,
    display: 'flex',
    flexDirection: 'column',
  } as CSSProperties,
  shell: {
    maxWidth: 1100,
    margin: '0 auto',
    padding: '56px 28px 96px',
    width: '100%',
    flex: 1,
  } as CSSProperties,
  header: { marginBottom: 36 } as CSSProperties,
  crumb: {
    fontSize: 13,
    color: VECTRA_MUTED,
    letterSpacing: '0.04em',
    marginBottom: 14,
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
  } as CSSProperties,
  h1: {
    fontSize: 40,
    fontWeight: 600,
    letterSpacing: '-0.02em',
    margin: '0 0 10px',
    lineHeight: 1.1,
  } as CSSProperties,
  sub: { fontSize: 16, color: VECTRA_MUTED, margin: 0, maxWidth: 640 } as CSSProperties,
  grid: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 0.95fr) minmax(0, 1.05fr)',
    gap: 28,
    alignItems: 'start',
  } as CSSProperties,
  panel: {
    border: `1px solid ${VECTRA_LINE}`,
    borderRadius: 16,
    background: '#fff',
    padding: 24,
  } as CSSProperties,
  panelTitle: {
    fontSize: 13,
    letterSpacing: '0.08em',
    color: VECTRA_MUTED,
    fontFamily: 'ui-monospace, monospace',
    marginBottom: 18,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  } as CSSProperties,
  dropzone: {
    border: `1.5px dashed ${VECTRA_LINE}`,
    borderRadius: 14,
    padding: '44px 24px',
    background: VECTRA_SOFT,
    textAlign: 'center',
    cursor: 'pointer',
    transition: 'border-color 0.15s ease, background 0.15s ease',
  } as CSSProperties,
  dropzoneActive: {
    borderColor: VECTRA_BLUE,
    background: 'rgba(47,107,255,0.06)',
  } as CSSProperties,
  fileInput: {
    position: 'absolute',
    width: 1,
    height: 1,
    opacity: 0,
    pointerEvents: 'none',
  } as CSSProperties,
  filePill: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 10,
    padding: '8px 14px',
    background: '#fff',
    border: `1px solid ${VECTRA_LINE}`,
    borderRadius: 999,
    fontSize: 13.5,
    fontFamily: 'ui-monospace, monospace',
  } as CSSProperties,
  optionsRow: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: 10,
    marginTop: 20,
  } as CSSProperties,
  optionLabel: {
    fontSize: 11,
    letterSpacing: '0.08em',
    color: VECTRA_MUTED,
    fontFamily: 'ui-monospace, monospace',
    marginBottom: 6,
    display: 'block',
  } as CSSProperties,
  select: {
    width: '100%',
    padding: '10px 12px',
    border: `1px solid ${VECTRA_LINE}`,
    borderRadius: 10,
    background: '#fff',
    fontSize: 14,
    color: VECTRA_INK,
    fontFamily: 'inherit',
    appearance: 'none',
    cursor: 'pointer',
  } as CSSProperties,
  convertRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    marginTop: 24,
    flexWrap: 'wrap',
  } as CSSProperties,
  preview: {
    border: `1px solid ${VECTRA_LINE}`,
    borderRadius: 16,
    background: '#fff',
    overflow: 'hidden',
    minHeight: 460,
    display: 'flex',
    flexDirection: 'column',
  } as CSSProperties,
  previewHeader: {
    padding: '14px 18px',
    borderBottom: `1px solid ${VECTRA_LINE}`,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    background: VECTRA_SOFT,
  } as CSSProperties,
  previewBody: {
    flex: 1,
    padding: 28,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
    background:
      'repeating-conic-gradient(#f8f9fb 0% 25%, #ffffff 0% 50%) 50% / 18px 18px',
  } as CSSProperties,
  emptyHint: {
    textAlign: 'center',
    color: VECTRA_MUTED,
    fontSize: 14,
    maxWidth: 320,
  } as CSSProperties,
  metaRow: {
    display: 'flex',
    gap: 18,
    padding: '12px 18px',
    borderTop: `1px solid ${VECTRA_LINE}`,
    fontSize: 12.5,
    color: VECTRA_MUTED,
    fontFamily: 'ui-monospace, monospace',
    background: '#fff',
    flexWrap: 'wrap',
  } as CSSProperties,
  spinnerDot: (i: number): CSSProperties => ({
    width: 6,
    height: 6,
    borderRadius: 999,
    background: VECTRA_BLUE,
    animation: `vectra-dot 1s ${i * 0.16}s infinite ease-in-out`,
    display: 'inline-block',
  }),
};

function MockTracedSVG() {
  return (
    <svg
      viewBox="0 0 240 200"
      width="100%"
      height="100%"
      style={{ maxWidth: 440, maxHeight: 360, display: 'block' }}
      role="img"
      aria-label="Mock vectorized output"
    >
      <defs>
        <linearGradient id="mockA" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor={VECTRA_BLUE} />
          <stop offset="100%" stopColor="#1f55e0" />
        </linearGradient>
      </defs>
      <rect x="20" y="20" width="200" height="160" rx="16" fill="#ffffff" stroke={VECTRA_LINE} />
      <path
        d="M70 150 L110 60 L130 110 L150 60 L190 150 L170 150 L150 110 L130 150 L110 110 L90 150 Z"
        fill={VECTRA_INK}
      />
      <circle cx="180" cy="62" r="9" fill="url(#mockA)" />
      <path
        d="M70 150 L110 60 L130 110 L150 60 L190 150"
        fill="none"
        stroke={VECTRA_BLUE}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeDasharray="280"
        strokeDashoffset="280"
        style={{ animation: 'vectra-tracePath 1.4s 0.1s ease-out forwards' }}
      />
      {[
        [70, 150], [110, 60], [130, 110], [150, 60], [190, 150], [180, 62],
      ].map(([cx, cy], i) => (
        <rect
          key={i}
          x={cx - 3}
          y={cy - 3}
          width={6}
          height={6}
          fill="#ffffff"
          stroke={VECTRA_BLUE}
          strokeWidth="1.4"
          style={{ opacity: 0, animation: `vectra-fadeup 0.3s ${0.9 + i * 0.05}s ease-out forwards` }}
        />
      ))}
    </svg>
  );
}

type Status = 'idle' | 'converting' | 'done';

export default function Upload() {
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [status, setStatus] = useState<Status>('idle');
  const [opts, setOpts] = useState({ mode: 'color', colors: '6', output: 'SVG' });
  const inputRef = useRef<HTMLInputElement | null>(null);

  function onPick(f?: File | null) {
    if (!f) return;
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setFile(f);
    setPreviewUrl(URL.createObjectURL(f));
    setStatus('idle');
  }

  function onConvert() {
    setStatus('converting');
    setTimeout(() => setStatus('done'), 850);
  }

  useEffect(() => () => { if (previewUrl) URL.revokeObjectURL(previewUrl); }, [previewUrl]);

  const dropProps = {
    onDragOver: (e: React.DragEvent) => { e.preventDefault(); setDragOver(true); },
    onDragLeave: () => setDragOver(false),
    onDrop: (e: React.DragEvent) => {
      e.preventDefault();
      setDragOver(false);
      const f = e.dataTransfer.files?.[0];
      if (f && f.type.startsWith('image/')) onPick(f);
    },
    onClick: () => inputRef.current?.click(),
  };

  return (
    <div style={uploadStyles.page}>
      <Nav />

      <div style={uploadStyles.shell}>
        <div style={uploadStyles.header}>
          <div style={uploadStyles.crumb}>VECTRA / CONVERT</div>
          <h1 style={uploadStyles.h1}>Upload an image</h1>
          <p style={uploadStyles.sub}>
            PNG · JPG · WebP 지원. 변환 결과는 미리보기 후 SVG · AI · EPS · PDF로 다운로드할 수 있습니다.
          </p>
        </div>

        <div style={uploadStyles.grid}>
          <div style={uploadStyles.panel}>
            <div style={uploadStyles.panelTitle}>
              <span>INPUT</span>
              <span style={{ color: VECTRA_MUTED }}>Max 20 MB</span>
            </div>

            <div
              {...dropProps}
              style={{ ...uploadStyles.dropzone, ...(dragOver ? uploadStyles.dropzoneActive : {}) }}
              role="button"
              aria-label="Choose or drop an image file"
            >
              <input
                ref={inputRef}
                type="file"
                accept="image/*"
                style={uploadStyles.fileInput}
                onChange={(e) => onPick(e.target.files?.[0])}
              />
              {file ? (
                <div>
                  <div style={{ marginBottom: 14, display: 'inline-block' }}>
                    {previewUrl && (
                      <img
                        src={previewUrl}
                        alt={file.name}
                        style={{ maxWidth: 160, maxHeight: 120, borderRadius: 8, border: `1px solid ${VECTRA_LINE}`, background: '#fff' }}
                      />
                    )}
                  </div>
                  <div style={uploadStyles.filePill}>
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                      <rect x="2.5" y="1.5" width="9" height="11" rx="1.5" stroke={VECTRA_INK} strokeWidth="1.2" />
                      <path d="M4.5 5h5M4.5 7.5h5M4.5 10h3" stroke={VECTRA_INK} strokeWidth="1.2" strokeLinecap="round" />
                    </svg>
                    {file.name}
                    <span style={{ color: VECTRA_MUTED }}>· {(file.size / 1024).toFixed(0)} KB</span>
                  </div>
                  <div style={{ marginTop: 14, fontSize: 13, color: VECTRA_MUTED }}>
                    Click to choose a different image
                  </div>
                </div>
              ) : (
                <div>
                  <svg width="36" height="36" viewBox="0 0 36 36" fill="none" style={{ marginBottom: 12 }} aria-hidden="true">
                    <rect x="3" y="3" width="30" height="30" rx="8" stroke={VECTRA_LINE} strokeWidth="1.4" />
                    <path d="M12 22l4-5 4 4 4-6 4 7" stroke={VECTRA_BLUE} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    <circle cx="14.5" cy="13.5" r="1.6" fill={VECTRA_INK} />
                  </svg>
                  <div style={{ fontSize: 16, fontWeight: 500, letterSpacing: '-0.005em', marginBottom: 6 }}>
                    Drop an image, or <span style={{ color: VECTRA_BLUE }}>browse</span>
                  </div>
                  <div style={{ fontSize: 13, color: VECTRA_MUTED }}>
                    PNG · JPG · WebP — up to 20 MB
                  </div>
                </div>
              )}
            </div>

            <div style={uploadStyles.optionsRow}>
              <div>
                <label style={uploadStyles.optionLabel}>MODE</label>
                <select
                  style={uploadStyles.select}
                  value={opts.mode}
                  onChange={(e) => setOpts({ ...opts, mode: e.target.value })}
                >
                  <option value="color">Color</option>
                  <option value="bw">Black &amp; white</option>
                  <option value="line">Line art</option>
                </select>
              </div>
              <div>
                <label style={uploadStyles.optionLabel}>COLORS</label>
                <select
                  style={uploadStyles.select}
                  value={opts.colors}
                  onChange={(e) => setOpts({ ...opts, colors: e.target.value })}
                >
                  <option value="2">2</option>
                  <option value="4">4</option>
                  <option value="6">6</option>
                  <option value="8">8</option>
                  <option value="16">16</option>
                </select>
              </div>
              <div>
                <label style={uploadStyles.optionLabel}>OUTPUT</label>
                <select
                  style={uploadStyles.select}
                  value={opts.output}
                  onChange={(e) => setOpts({ ...opts, output: e.target.value })}
                >
                  <option value="SVG">SVG</option>
                  <option value="AI">AI</option>
                  <option value="EPS">EPS</option>
                  <option value="PDF">PDF/X-1a</option>
                </select>
              </div>
            </div>

            <div style={uploadStyles.convertRow}>
              <Button
                testId="convert"
                variant="primary"
                disabled={!file || status === 'converting'}
                onClick={onConvert}
              >
                {status === 'converting' ? 'Converting…' : status === 'done' ? 'Re-convert' : 'Convert'}
                {status !== 'converting' && (
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                    <path d="M3 7h8m0 0L7.5 3.5M11 7l-3.5 3.5" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </Button>
              {status === 'done' && (
                <Button variant="ghost" onClick={() => alert('Download wired in production build.')}>
                  Download .{opts.output.toLowerCase()}
                </Button>
              )}
              {file && status === 'idle' && (
                <span style={{ fontSize: 13, color: VECTRA_MUTED }}>Ready · ~3s</span>
              )}
            </div>
          </div>

          <div style={uploadStyles.preview}>
            <div style={uploadStyles.previewHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 8, height: 8, borderRadius: 999, background: status === 'done' ? '#22c55e' : status === 'converting' ? VECTRA_BLUE : '#cdd5e1' }} />
                <span style={{ fontSize: 13, letterSpacing: '0.06em', fontFamily: 'ui-monospace, monospace', color: VECTRA_INK }}>
                  PREVIEW · {opts.output}
                </span>
              </div>
              <span style={{ fontSize: 12, color: VECTRA_MUTED, fontFamily: 'ui-monospace, monospace' }}>
                {status === 'idle' && '—'}
                {status === 'converting' && 'tracing…'}
                {status === 'done' && '0.84s · 1 path'}
              </span>
            </div>

            <div data-testid="svg-preview" style={uploadStyles.previewBody}>
              {status === 'idle' && (
                <div style={uploadStyles.emptyHint}>
                  {file ? 'Press Convert to trace this image.' : 'Your traced SVG will appear here.'}
                </div>
              )}

              {status === 'converting' && (
                <div style={{ display: 'flex', gap: 8, alignItems: 'center' }} aria-label="Converting">
                  <span style={uploadStyles.spinnerDot(0)} />
                  <span style={uploadStyles.spinnerDot(1)} />
                  <span style={uploadStyles.spinnerDot(2)} />
                </div>
              )}

              {status === 'done' && (
                <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }} className="v-fadeup">
                  <MockTracedSVG />
                </div>
              )}
            </div>

            <div style={uploadStyles.metaRow}>
              <span>nodes: {status === 'done' ? '14' : '—'}</span>
              <span>paths: {status === 'done' ? '3' : '—'}</span>
              <span>palette: {status === 'done' ? opts.colors : '—'}</span>
              <span style={{ marginLeft: 'auto' }}>CMYK · text outlined</span>
            </div>
          </div>
        </div>
      </div>

      <Footer />
    </div>
  );
}
