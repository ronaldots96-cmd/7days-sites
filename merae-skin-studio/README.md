# Merae Skin Studio

Standalone, build-free portfolio concept for a premium medical-aesthetics and skin-wellness studio.

## Run locally

From this folder:

```powershell
python -m http.server 4173
```

Then open `http://localhost:4173/`.

The directory is self-contained and uses only relative paths, so it can be moved to another repository or deployed as a static site without changes.

## Structure

```text
merae-skin-studio/
├── index.html
├── README.md
└── assets/
    ├── css/styles.css
    ├── js/main.js
    └── images/
        ├── hero-portrait.webp
        ├── consultation.webp
        ├── skin-detail.webp
        └── studio-interior.webp
```

## Important concept safeguards

- Merae is a fictional brand and is not validated for commercial naming or trademark use.
- The page uses `noindex, nofollow` and visibly identifies itself as a portfolio concept.
- The booking form is a local interaction demo. It does not transmit or store visitor data.
- No reviews, licenses, provider credentials, medical outcomes, before/after comparisons, addresses, or statistics are invented.
- A real implementation requires verified provider information, jurisdiction-specific scope review, privacy review, service disclosures, approved scheduling/intake tooling, and legal review.

## Tracking hooks

The site dispatches browser events through:

```js
window.addEventListener('merae:track', event => {
  console.log(event.detail);
});
```

If `window.dataLayer` already exists, the same events are pushed there. No analytics vendor is loaded by default.

## Generated imagery

All four images were generated with the built-in image generation workflow and converted locally to optimized WebP files. No external stock assets are required.

Prompt set, summarized:

1. **Hero portrait:** natural adult skin, calm editorial portrait, subject on the right, ivory studio, negative space for copy; no procedures, text, logos, watermark, or retouching.
2. **Consultation:** two adult women in an unhurried consultation, warm ivory room, sage and plum accents; no devices, treatment, text, logos, or implied outcome.
3. **Skin detail:** adult three-quarter portrait with authentic pores, freckles and fine lines; no treatment tools, heavy retouching, text, logos, watermark, or before/after implication.
4. **Studio interior:** empty limewash and travertine interior with pale oak, sage ceramics and a plum chair; no people, medical machinery, text, logos, or branded products.

## Production handoff

Before adapting this concept for a real clinic:

1. Replace concept notices with verified business and provider information.
2. Remove `noindex` only after content, privacy, accessibility and legal review.
3. Connect the booking CTA to an approved scheduling/intake system.
4. Add real analytics and consent handling appropriate to the deployment.
5. Validate every treatment statement, credential and image usage with the clinic.
