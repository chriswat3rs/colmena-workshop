/* Colmena · service worker (v1.10 · app instalable)
   - La página (index.html) siempre se pide primero a internet: así cada quien recibe la versión nueva.
     Si no hay conexión, se abre la última copia guardada.
   - Íconos, manifiesto y librerías propias se guardan para abrir más rápido.
   - Nunca guarda nada de Supabase (datos, sesiones, IA): eso siempre va directo a internet. */
const VERSION = "20260926104017";
const CACHE = "colmena-" + VERSION;
const CORE = ["./", "./index.html", "./manifest.json", "./icons/icon-192.png", "./icons/icon-512.png", "./icons/apple-touch-icon.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k.startsWith("colmena-") && k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;                 /* Supabase, fuentes, etc.: directo a internet */
  if (req.mode === "navigate") {                               /* la página: primero internet, si no, la copia */
    e.respondWith(fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put("./index.html", copy)); }
      return res;
    }).catch(() => caches.match("./index.html").then((r) => r || caches.match("./"))));
    return;
  }
  if (url.searchParams.has("v")) return;                       /* revisión de versión nueva: siempre a internet */
  if (/\/(icons\/|email\/|manifest\.json|jspdf\.umd\.min\.js)/.test(url.pathname)) {
    e.respondWith(caches.match(req).then((hit) => {
      const net = fetch(req).then((res) => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); } return res; }).catch(() => hit);
      return hit || net;
    }));
  }
});
