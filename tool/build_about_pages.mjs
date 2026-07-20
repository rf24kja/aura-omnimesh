// Generates the localized About section: website/about/<code>/index.html
// for every language module in tool/about_content/, plus sitemap.xml with
// hreflang alternates. One template guarantees identical structure and a
// complete hreflang cluster on every page — the thing Google actually
// checks. Run:  node tool/build_about_pages.mjs
//
// Design language mirrors index.html: obsidian, 1px slate rails, uppercase
// labels, zero radius, zero external requests (CSP: default-src 'none').

import { mkdirSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SITE = 'https://aura-omnimesh.pages.dev';
const CONTENT_DIR = join(ROOT, 'tool', 'about_content');

const langs = [];
for (const f of readdirSync(CONTENT_DIR).filter((f) => f.endsWith('.mjs')).sort()) {
  langs.push((await import(`./about_content/${f}`)).default);
}
// English is the canonical root (/about/) and x-default.
langs.sort((a, b) => (a.code === '' ? -1 : b.code === '' ? 1 : 0));

const urlOf = (l) => `${SITE}/about/${l.code ? l.code + '/' : ''}`;
const esc = (s) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const jsonEsc = (s) => JSON.stringify(s);

const hreflangLinks = () =>
  [
    ...langs.map(
      (l) => `<link rel="alternate" hreflang="${l.hreflang}" href="${urlOf(l)}">`,
    ),
    `<link rel="alternate" hreflang="x-default" href="${urlOf(langs[0])}">`,
  ].join('\n');

const CSS = `
  :root{--obsidian:#111111;--carbon:#181818;--type:#ffffff;
    --dim:rgba(255,255,255,.70);--slate:#777777;--hair:rgba(119,119,119,.25);
    --emerald:#2FBF71;--s1:8px;--s2:16px;--s3:24px;--s4:32px;--s5:48px;--s6:96px;
    --maxw:960px}
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:var(--obsidian);color:var(--type);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",
    "Noto Sans","Noto Sans KR","Noto Sans SC","Noto Sans JP","Noto Sans Devanagari",
    Arial,sans-serif;font-size:15px;line-height:1.6;-webkit-font-smoothing:antialiased}
  ::selection{background:rgba(255,255,255,.2)}
  a{color:var(--type)}
  .rail{max-width:var(--maxw);margin:0 auto;
    border-left:1px solid var(--slate);border-right:1px solid var(--slate)}
  @media (max-width:1000px){.rail{border-left:0;border-right:0}}
  .pad{padding-left:var(--s3);padding-right:var(--s3)}
  .label{font-size:11px;font-weight:600;letter-spacing:.14em;
    text-transform:uppercase;color:var(--slate)}
  nav{border-bottom:1px solid var(--slate);position:sticky;top:0;
    background:var(--obsidian);z-index:10}
  .nav-row{display:flex;align-items:center;justify-content:space-between;
    padding-top:var(--s2);padding-bottom:var(--s2)}
  .wordmark{font-size:13px;font-weight:600;letter-spacing:.18em;text-decoration:none}
  nav .label a{color:var(--slate);text-decoration:none}
  nav .label a:hover{color:var(--type)}
  header.about{padding-top:var(--s5);padding-bottom:var(--s4)}
  h1{font-size:clamp(30px,5vw,46px);line-height:1.1;font-weight:600;
    letter-spacing:-0.02em;margin:var(--s3) 0}
  .lede{color:var(--dim);max-width:60ch}
  section.sec{border-top:1px solid var(--hair);
    padding-top:var(--s4);padding-bottom:var(--s4)}
  h2{font-size:21px;font-weight:600;letter-spacing:-0.01em;margin:var(--s2) 0 var(--s2)}
  .sec p{color:var(--dim);max-width:66ch;margin-bottom:var(--s2)}
  ol.steps{list-style:none;counter-reset:st;max-width:66ch}
  ol.steps li{counter-increment:st;border-left:2px solid var(--emerald);
    padding:2px 0 2px var(--s2);margin-bottom:var(--s3)}
  ol.steps li::before{content:counter(st,decimal-leading-zero);
    font-size:11px;font-weight:600;letter-spacing:.14em;color:var(--slate);display:block}
  ol.steps strong{display:block;margin:2px 0 4px}
  ol.steps span{color:var(--dim)}
  ul.plain{list-style:none;max-width:66ch}
  ul.plain li{padding-left:var(--s2);margin-bottom:var(--s1);
    border-left:1px solid var(--slate);color:var(--dim)}
  ul.plain li strong{color:var(--type)}
  details{border-top:1px solid var(--hair);max-width:66ch}
  details:last-of-type{border-bottom:1px solid var(--hair)}
  summary{cursor:pointer;padding:var(--s2) 0;font-weight:500;list-style:none}
  summary::-webkit-details-marker{display:none}
  summary::after{content:"+";float:right;color:var(--slate)}
  details[open] summary::after{content:"\\2212"}
  details p{color:var(--dim);padding-bottom:var(--s2)}
  .langs{display:flex;flex-wrap:wrap;gap:var(--s1) var(--s2);max-width:66ch}
  .langs a{color:var(--slate);text-decoration:none;font-size:13px}
  .langs a:hover{color:var(--type)}
  .langs a[aria-current]{color:var(--type);border-bottom:1px solid var(--emerald)}
  footer{border-top:1px solid var(--slate);padding-top:var(--s4);padding-bottom:var(--s5)}
  footer .pad{display:flex;justify-content:space-between;gap:var(--s2);
    flex-wrap:wrap;color:var(--slate);font-size:13px}
  footer a{color:var(--slate);text-decoration:none}
  footer a:hover{color:var(--type)}
`;

function page(l) {
  const c = l.content;
  const faqLd = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    inLanguage: l.hreflang,
    mainEntity: c.faq.items.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  };
  const aboutLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: c.title,
    description: c.metaDescription,
    inLanguage: l.hreflang,
    url: urlOf(l),
    isPartOf: { '@type': 'WebSite', name: 'Aura OmniMesh', url: SITE + '/' },
  };
  const steps = c.how.steps
    .map((s) => `      <li><strong>${esc(s.t)}</strong><span>${esc(s.d)}</span></li>`)
    .join('\n');
  const items = (list) =>
    list.map((i) => `      <li>${i}</li>`).join('\n');
  const faq = c.faq.items
    .map(
      (f) => `      <details>
        <summary>${esc(f.q)}</summary>
        <p>${esc(f.a)}</p>
      </details>`,
    )
    .join('\n');
  const langLinks = langs
    .map(
      (x) =>
        `        <a href="/about/${x.code ? x.code + '/' : ''}" hreflang="${x.hreflang}" lang="${x.hreflang}"${x.code === l.code ? ' aria-current="page"' : ''}>${x.nativeName}</a>`,
    )
    .join('\n');

  return `<!doctype html>
<html lang="${l.hreflang}" dir="${l.dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(c.title)}</title>
<meta name="description" content="${esc(c.metaDescription)}">
<link rel="canonical" href="${urlOf(l)}">
${hreflangLinks()}
<meta property="og:type" content="article">
<meta property="og:title" content="${esc(c.title)}">
<meta property="og:description" content="${esc(c.metaDescription)}">
<meta property="og:url" content="${urlOf(l)}">
<meta name="twitter:card" content="summary">
<meta name="theme-color" content="#111111">
<script type="application/ld+json">
${JSON.stringify(aboutLd, null, 1)}
</script>
<script type="application/ld+json">
${JSON.stringify(faqLd, null, 1)}
</script>
<style>${CSS}</style>
</head>
<body>
<nav>
  <div class="rail pad nav-row">
    <a class="wordmark" href="/">AURA&nbsp;OMNIMESH</a>
    <span class="label"><a href="/">${esc(c.backHome)}</a></span>
  </div>
</nav>

<div class="rail">
  <header class="about pad">
    <span class="label">${esc(c.kicker)}</span>
    <h1>${esc(c.h1)}</h1>
    <p class="lede">${esc(c.lede)}</p>
  </header>

  <main>
    <section class="sec pad">
      <span class="label">${esc(c.whatIs.label)}</span>
      <h2>${esc(c.whatIs.h2)}</h2>
      ${c.whatIs.paras.map((p) => `<p>${p}</p>`).join('\n      ')}
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.why.label)}</span>
      <h2>${esc(c.why.h2)}</h2>
      ${c.why.paras.map((p) => `<p>${p}</p>`).join('\n      ')}
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.how.label)}</span>
      <h2>${esc(c.how.h2)}</h2>
      <ol class="steps">
${steps}
      </ol>
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.solves.label)}</span>
      <h2>${esc(c.solves.h2)}</h2>
      <ul class="plain">
${items(c.solves.items)}
      </ul>
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.who.label)}</span>
      <h2>${esc(c.who.h2)}</h2>
      <ul class="plain">
${items(c.who.items)}
      </ul>
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.principles.label)}</span>
      <h2>${esc(c.principles.h2)}</h2>
      <ul class="plain">
${items(c.principles.items)}
      </ul>
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.limits.label)}</span>
      <h2>${esc(c.limits.h2)}</h2>
      <ul class="plain">
${items(c.limits.items)}
      </ul>
    </section>

    <section class="sec pad">
      <span class="label">FAQ</span>
      <h2>${esc(c.faq.h2)}</h2>
${faq}
    </section>

    <section class="sec pad">
      <span class="label">${esc(c.langLabel)}</span>
      <div class="langs">
${langLinks}
      </div>
    </section>
  </main>

  <footer>
    <div class="pad">
      <span>${esc(c.footerTag)}</span>
      <span>
        <a href="/privacy.html">Privacy</a> &nbsp;&middot;&nbsp;
        <a href="/terms.html">Terms</a> &nbsp;&middot;&nbsp;
        <a href="https://github.com/rf24kja/aura-omnimesh" rel="noopener">GitHub</a>
      </span>
    </div>
  </footer>
</div>
</body>
</html>
`;
}

// ---- emit pages -----------------------------------------------------------
for (const l of langs) {
  const dir = join(ROOT, 'website', 'about', l.code);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'index.html'), page(l));
  console.log(`about/${l.code ? l.code + '/' : ''}index.html  (${l.hreflang})`);
}

// ---- sitemap with hreflang clusters ---------------------------------------
const alt = () =>
  [
    ...langs.map(
      (x) =>
        `    <xhtml:link rel="alternate" hreflang="${x.hreflang}" href="${urlOf(x)}"/>`,
    ),
    `    <xhtml:link rel="alternate" hreflang="x-default" href="${urlOf(langs[0])}"/>`,
  ].join('\n');

const aboutUrls = langs
  .map(
    (l) => `  <url><loc>${urlOf(l)}</loc><priority>0.8</priority>
${alt()}
  </url>`,
  )
  .join('\n');

writeFileSync(
  join(ROOT, 'website', 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url><loc>${SITE}/</loc><priority>1.0</priority></url>
${aboutUrls}
  <url><loc>${SITE}/privacy.html</loc><priority>0.5</priority></url>
  <url><loc>${SITE}/terms.html</loc><priority>0.5</priority></url>
</urlset>
`,
);
console.log('sitemap.xml rebuilt with hreflang clusters');
