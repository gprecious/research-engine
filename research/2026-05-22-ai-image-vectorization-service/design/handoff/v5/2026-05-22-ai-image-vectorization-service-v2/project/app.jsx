/* App shell — hash-based router. */

function useHashRoute() {
  const [hash, setHash] = React.useState(window.location.hash || "#/");
  React.useEffect(() => {
    const onChange = () => setHash(window.location.hash || "#/");
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  return hash;
}

function App() {
  const hash = useHashRoute();
  const route = hash.replace(/^#/, "") || "/";

  React.useEffect(() => {
    window.scrollTo({ top: 0, behavior: "auto" });
  }, [route]);

  if (route === "/upload") return <Upload />;
  if (route === "/health") return <Health />;
  return <Landing />;
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
