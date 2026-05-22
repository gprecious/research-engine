import './globals.css';
export const metadata = { title: "Vectra — AI 이미지를 인쇄 가능한 벡터로" };
export default function Root({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
