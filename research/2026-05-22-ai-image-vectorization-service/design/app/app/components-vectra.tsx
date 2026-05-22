'use client';
/* Shared UI primitives — verbatim port of claude.ai/design v5 handoff components.jsx.
   Hash-router `navigate` calls replaced with Next.js <Link>; visuals/styles untouched. */
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { CSSProperties, ReactNode, MouseEvent } from 'react';

export const VECTRA_BLUE = '#2f6bff';
export const VECTRA_BLUE_DARK = '#1f55e0';
export const VECTRA_INK = '#0b0d12';
export const VECTRA_MUTED = '#6b7280';
export const VECTRA_LINE = 'rgba(11,13,18,0.08)';
export const VECTRA_SOFT = '#f6f7f9';

const navStyles: Record<string, CSSProperties> = {
  bar: {
    position: 'sticky',
    top: 0,
    zIndex: 50,
    backdropFilter: 'saturate(140%) blur(12px)',
    WebkitBackdropFilter: 'saturate(140%) blur(12px)',
    background: 'rgba(255,255,255,0.78)',
    borderBottom: `1px solid ${VECTRA_LINE}`,
  },
  inner: {
    maxWidth: 1200,
    margin: '0 auto',
    padding: '16px 28px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 24,
  },
  brand: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    fontWeight: 600,
    letterSpacing: '-0.01em',
    fontSize: 17,
    color: VECTRA_INK,
    textDecoration: 'none',
  },
  links: {
    display: 'flex',
    alignItems: 'center',
    gap: 28,
    fontSize: 14.5,
    color: '#3f4654',
  },
  link: {
    textDecoration: 'none',
    color: '#3f4654',
    padding: '6px 0',
  },
  cta: {
    fontSize: 14,
    padding: '9px 16px',
    borderRadius: 999,
    background: VECTRA_INK,
    color: 'white',
    border: '1px solid ' + VECTRA_INK,
    fontWeight: 500,
    textDecoration: 'none',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
  },
};

export function VectraMark({ size = 22 }: { size?: number }) {
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

export function Nav() {
  const pathname = usePathname();
  const isHome = pathname === '/';
  const scrollTo = (id: string) => (e: MouseEvent) => {
    e.preventDefault();
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  return (
    <nav style={navStyles.bar}>
      <div style={navStyles.inner}>
        <Link href="/" style={navStyles.brand}>
          <VectraMark />
          <span>Vectra</span>
          <span style={{ fontSize: 11, color: VECTRA_MUTED, fontWeight: 500, marginLeft: 4, padding: '2px 6px', border: '1px solid ' + VECTRA_LINE, borderRadius: 4, letterSpacing: '0.04em' }}>BETA</span>
        </Link>
        <div style={navStyles.links}>
          <Link href="/" style={{ ...navStyles.link, color: isHome ? VECTRA_INK : '#3f4654', fontWeight: isHome ? 500 : 400 }}>Product</Link>
          <a href="#how" style={navStyles.link} onClick={scrollTo('how')}>How it works</a>
          <a href="#pricing" style={navStyles.link} onClick={scrollTo('pricing')}>Pricing</a>
          <Link
            href="/upload"
            data-testid="cta-try"
            style={navStyles.cta}
          >
            Try free
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 6h6m0 0L6 3m3 3L6 9" stroke="white" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" /></svg>
          </Link>
        </div>
      </div>
    </nav>
  );
}

export function Footer() {
  return (
    <footer style={{ borderTop: `1px solid ${VECTRA_LINE}`, marginTop: 96, padding: '40px 28px 56px', background: '#fff' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: 24 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
            <VectraMark size={20} />
            <strong style={{ fontSize: 15 }}>Vectra</strong>
          </div>
          <div style={{ fontSize: 13, color: VECTRA_MUTED, maxWidth: 380 }}>
            AI 이미지를 인쇄소가 받는 벡터 파일로. 로고와 일러스트를 위한 raster-to-vector 파이프라인.
          </div>
        </div>
        <div style={{ display: 'flex', gap: 28, fontSize: 13, color: VECTRA_MUTED }}>
          <Link href="/health" style={{ color: VECTRA_MUTED, textDecoration: 'none' }}>Status</Link>
          <a href="#" style={{ color: VECTRA_MUTED, textDecoration: 'none' }} onClick={(e) => e.preventDefault()}>Docs</a>
          <a href="#" style={{ color: VECTRA_MUTED, textDecoration: 'none' }} onClick={(e) => e.preventDefault()}>Contact</a>
          <span>© 2026 Vectra Labs</span>
        </div>
      </div>
    </footer>
  );
}

type ButtonProps = {
  children: ReactNode;
  variant?: 'primary' | 'dark' | 'ghost' | 'soft';
  testId?: string;
  disabled?: boolean;
  onClick?: (e: MouseEvent<HTMLButtonElement>) => void;
};

export function Button({ children, variant = 'primary', testId, disabled, onClick }: ButtonProps) {
  const base: CSSProperties = {
    fontSize: 15,
    fontWeight: 500,
    padding: '12px 22px',
    borderRadius: 999,
    border: '1px solid transparent',
    transition: 'transform 0.06s ease, background 0.15s ease, border-color 0.15s ease',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    lineHeight: 1,
    letterSpacing: '-0.005em',
  };
  const variants: Record<string, CSSProperties> = {
    primary: { background: VECTRA_BLUE, color: 'white', borderColor: VECTRA_BLUE },
    dark: { background: VECTRA_INK, color: 'white', borderColor: VECTRA_INK },
    ghost: { background: 'transparent', color: VECTRA_INK, borderColor: VECTRA_LINE },
    soft: { background: VECTRA_SOFT, color: VECTRA_INK, borderColor: VECTRA_LINE },
  };
  return (
    <button
      data-testid={testId}
      disabled={disabled}
      onClick={onClick}
      style={{ ...base, ...variants[variant], ...(disabled ? { opacity: 0.5, cursor: 'not-allowed' } : {}) }}
      onMouseDown={(e) => { if (!disabled) (e.currentTarget as HTMLButtonElement).style.transform = 'scale(0.98)'; }}
      onMouseUp={(e) => { (e.currentTarget as HTMLButtonElement).style.transform = 'scale(1)'; }}
      onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.transform = 'scale(1)'; }}
    >
      {children}
    </button>
  );
}
