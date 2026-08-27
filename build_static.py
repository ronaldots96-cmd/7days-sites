"""Build the Flask templates as a static Cloudflare Pages site."""

from __future__ import annotations

import html
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"


def env_flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def prepare_environment() -> tuple[str, bool]:
    site_url = (
        os.getenv("SITE_URL", "").strip()
        or os.getenv("CF_PAGES_URL", "").strip()
        or "http://localhost:8000"
    ).rstrip("/")
    site_indexable = env_flag("SITE_INDEXABLE", default=False)

    if site_indexable and site_url.startswith("http://localhost"):
        raise RuntimeError(
            "SITE_INDEXABLE=true requires SITE_URL or CF_PAGES_URL to contain the public URL."
        )

    asset_version = (
        os.getenv("ASSET_VERSION", "").strip()
        or os.getenv("CF_PAGES_COMMIT_SHA", "").strip()[:12]
        or "local"
    )

    # app.py reads these values when it is imported.
    os.environ["APP_ENV"] = "production"
    os.environ["SITE_URL"] = site_url
    os.environ["SITE_INDEXABLE"] = "true" if site_indexable else "false"
    os.environ["ASSET_VERSION"] = asset_version
    return site_url, site_indexable


def reset_output() -> None:
    if DIST.exists():
        if DIST.parent != ROOT:
            raise RuntimeError(f"Refusing to remove unexpected output directory: {DIST}")
        shutil.rmtree(DIST)
    DIST.mkdir()


def render_pages() -> None:
    # Import only after prepare_environment(), so the template context uses the
    # Cloudflare deployment URL and the current commit as the asset version.
    from app import app

    webhook_url = os.getenv("BRIEFING_WEBHOOK_URL", "").strip()
    if webhook_url and not webhook_url.lower().startswith("https://"):
        raise RuntimeError("BRIEFING_WEBHOOK_URL must be an absolute HTTPS URL.")

    with app.test_client() as client:
        for route, output_name in (("/", "index.html"), ("/briefing", "briefing.html")):
            response = client.get(route, headers={"Accept-Encoding": "identity"})
            if response.status_code != 200:
                raise RuntimeError(f"Could not render {route}: HTTP {response.status_code}")

            page = response.get_data(as_text=True)
            if output_name == "briefing.html" and webhook_url:
                marker = 'data-webhook-url=""'
                if marker not in page:
                    raise RuntimeError("Briefing webhook marker was not found in rendered HTML.")
                page = page.replace(
                    marker,
                    f'data-webhook-url="{html.escape(webhook_url, quote=True)}"',
                    1,
                )

            unresolved = [token for token in ("{{", "{%") if token in page]
            if unresolved:
                raise RuntimeError(
                    f"Unresolved template syntax in {output_name}: {', '.join(unresolved)}"
                )
            (DIST / output_name).write_text(page, encoding="utf-8", newline="\n")


def copy_public_assets() -> None:
    shutil.copytree(ROOT / "static", DIST / "static")

    spa_ignore = shutil.ignore_patterns(
        "*.md",
        "*.pdf",
        "from whatsapp",
        "hero mobile.png",
        "hero pc.png",
        "capa-spa.png",
        "capa-spa-en.png",
    )
    shutil.copytree(ROOT / "spa", DIST / "spa", ignore=spa_ignore)
    shutil.copytree(
        ROOT / "merae-skin-studio",
        DIST / "merae-skin-studio",
        ignore=shutil.ignore_patterns("README.md"),
    )


def write_cloudflare_files(site_url: str, site_indexable: bool) -> None:
    redirects = """/index / 301
/briefing.html /briefing 301
/briefing/ /briefing 301
/spa /spa/ 301
/spa/index.html /spa/ 301
/merae-skin-studio /merae-skin-studio/ 301
/merae-skin-studio/index.html /merae-skin-studio/ 301
/favicon.ico /static/favicon.svg 302
"""
    (DIST / "_redirects").write_text(redirects, encoding="utf-8", newline="\n")

    headers = """/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), geolocation=(), microphone=()
"""
    if site_indexable:
        headers += """
/briefing
  X-Robots-Tag: noindex, follow

/spa/*
  X-Robots-Tag: noindex, nofollow, noarchive

/merae-skin-studio/*
  X-Robots-Tag: noindex, nofollow, noarchive
"""
    else:
        headers += "  X-Robots-Tag: noindex, nofollow, noarchive\n"
    (DIST / "_headers").write_text(headers, encoding="utf-8", newline="\n")

    robots = "User-agent: *\nAllow: /\n"
    if site_indexable:
        robots += f"Sitemap: {site_url}/sitemap.xml\n"
    (DIST / "robots.txt").write_text(robots, encoding="utf-8", newline="\n")

    if site_indexable:
        last_modified = datetime.now(timezone.utc).date().isoformat()
        sitemap = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>{html.escape(site_url)}/</loc><lastmod>{last_modified}</lastmod><changefreq>monthly</changefreq><priority>1.0</priority></url>
</urlset>
"""
        (DIST / "sitemap.xml").write_text(sitemap, encoding="utf-8", newline="\n")

    not_found = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Page not found | Sevenday Sites</title>
  <style>
    :root{font-family:Arial,sans-serif;color:#111;background:#f7f2e8}
    body{min-height:100vh;display:grid;place-items:center;margin:0;padding:24px;text-align:center}
    main{max-width:620px}strong{display:block;font-size:clamp(4rem,18vw,9rem);line-height:.9}
    h1{font-size:clamp(2rem,7vw,4rem);margin:.4em 0}p{font-size:1.1rem;line-height:1.6}
    a{display:inline-block;margin-top:1rem;padding:.9rem 1.2rem;border:2px solid #111;border-radius:12px;background:#baff38;color:#111;font-weight:800;text-decoration:none;box-shadow:4px 4px 0 #111}
    a:focus-visible{outline:4px solid #1769ff;outline-offset:4px}
  </style>
</head>
<body><main><strong>404</strong><h1>This page took the day off.</h1><p>The address may have changed, or the page may no longer exist.</p><a href="/">Back to Sevenday Sites</a></main></body>
</html>
"""
    (DIST / "404.html").write_text(not_found, encoding="utf-8", newline="\n")


def validate_output() -> None:
    required = (
        "index.html",
        "briefing.html",
        "404.html",
        "_headers",
        "_redirects",
        "robots.txt",
        "static/favicon.svg",
        "static/portfolio/brazilian-clinic.webp",
        "spa/index.html",
        "spa/video/video-spa.mp4",
        "merae-skin-studio/index.html",
        "merae-skin-studio/assets/css/styles.css",
    )
    missing = [path for path in required if not (DIST / path).is_file()]
    if missing:
        raise RuntimeError(f"Static build is missing: {', '.join(missing)}")

    forbidden = (
        "spa/lp-spa.md",
        "spa/images/from whatsapp/01.jfif",
        "merae-skin-studio/README.md",
    )
    leaked = [path for path in forbidden if (DIST / path).exists()]
    if leaked:
        raise RuntimeError(f"Non-public source files leaked into dist: {', '.join(leaked)}")


def main() -> None:
    site_url, site_indexable = prepare_environment()
    reset_output()
    render_pages()
    copy_public_assets()
    write_cloudflare_files(site_url, site_indexable)
    validate_output()

    files = [path for path in DIST.rglob("*") if path.is_file()]
    total_bytes = sum(path.stat().st_size for path in files)
    print(
        f"Built {len(files)} files in {DIST} ({total_bytes / 1024 / 1024:.2f} MiB) "
        f"for {site_url}; indexable={site_indexable}."
    )


if __name__ == "__main__":
    main()
