import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export function scaffoldApp({ outDir, handoff, slug, title }) {
  mkdirSync(join(outDir, 'app'), { recursive: true });
  mkdirSync(join(outDir, 'app/upload'), { recursive: true });
  mkdirSync(join(outDir, 'app/health'), { recursive: true });
  mkdirSync(join(outDir, 'public'), { recursive: true });

  writeFileSync(join(outDir, 'package.json'), JSON.stringify({
    name: slug,
    version: '0.1.0',
    private: true,
    type: 'module',
    scripts: { dev: 'next dev', build: 'next build', start: 'next start -p ${PORT:-3000}' },
    dependencies: { next: '^14.2.0', react: '^18.3.0', 'react-dom': '^18.3.0' },
    devDependencies: { typescript: '^5.5.0', '@types/node': '^22.0.0', '@types/react': '^18.3.0' }
  }, null, 2));

  writeFileSync(join(outDir, 'next.config.mjs'), `export default { reactStrictMode: true };\n`);
  writeFileSync(join(outDir, 'tsconfig.json'), JSON.stringify({
    compilerOptions: { target: 'ES2022', module: 'ESNext', moduleResolution: 'Bundler', jsx: 'preserve', strict: true, esModuleInterop: true, skipLibCheck: true, baseUrl: '.', plugins: [{ name: 'next' }] },
    include: ['next-env.d.ts', '**/*.ts', '**/*.tsx']
  }, null, 2));

  const ds = handoff.designSystem || {};
  const colors = ds.colors || {};
  const css = `:root {\n${Object.entries(colors).map(([k, v]) => `  --${k}: ${v};`).join('\n')}\n}\nbody { background: var(--bg, #fff); color: var(--fg, #000); font-family: ${ds.typography?.base || 'system-ui'}, sans-serif; margin: 0; }\n`;
  writeFileSync(join(outDir, 'app/globals.css'), css);

  writeFileSync(join(outDir, 'app/layout.tsx'),
`import './globals.css';
export const metadata = { title: ${JSON.stringify(title)} };
export default function Root({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
`);

  writeFileSync(join(outDir, 'app/page.tsx'),
`export default function Home() {
  return (
    <main>
      <header style={{ padding: 48, textAlign: 'center' }}>
        <h1>${title}</h1>
        <p>Turn raster art into clean SVG in seconds.</p>
        <a href="/upload"><button data-testid="cta-try" style={{ padding: '12px 24px', borderRadius: 8 }}>Try free</button></a>
      </header>
    </main>
  );
}
`);

  // upload page — SVG mock 을 JSX 로 직접 렌더 (innerHTML 금지)
  writeFileSync(join(outDir, 'app/upload/page.tsx'),
`'use client';
import { useState } from 'react';
export default function Upload() {
  const [show, setShow] = useState(false);
  function onConvert() { setShow(true); }
  return (
    <main style={{ padding: 48 }}>
      <h2>Upload your image</h2>
      <input type="file" accept="image/*" />
      <button data-testid="convert" onClick={onConvert}>Convert</button>
      <div data-testid="svg-preview">
        {show && (
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" width={120} height={120}>
            <rect width={40} height={40} fill="var(--accent, #6c4cff)" />
          </svg>
        )}
      </div>
    </main>
  );
}
`);

  writeFileSync(join(outDir, 'app/health/route.ts'),
`export async function GET() { return new Response('ok', { status: 200 }); }\n`);

  if (handoff.pages[0]) {
    writeFileSync(join(outDir, 'public/sample-handoff.html'), handoff.pages[0].html);
  }
}
