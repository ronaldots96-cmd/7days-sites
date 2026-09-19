import gzip
import os
import re
from datetime import datetime, timezone
from xml.sax.saxutils import escape

from flask import (
    Flask,
    Response,
    abort,
    has_request_context,
    make_response,
    redirect,
    render_template,
    request,
    send_from_directory,
    url_for,
)


IS_PRODUCTION = os.getenv("APP_ENV", os.getenv("FLASK_ENV", "development")).lower() == "production"
ASSET_VERSION = os.getenv("ASSET_VERSION", "20260826")
CONFIGURED_SITE_URL = os.getenv("SITE_URL", "").strip().rstrip("/")
SITE_INDEXABLE = os.getenv("SITE_INDEXABLE", "false").lower() in {"1", "true", "yes", "on"}
GTM_CONTAINER_ID = os.getenv("GTM_CONTAINER_ID", "").strip().upper()
if GTM_CONTAINER_ID and not re.fullmatch(r"GTM-[A-Z0-9]+", GTM_CONTAINER_ID):
    raise RuntimeError("GTM_CONTAINER_ID must look like GTM-XXXXXXX.")
FORMS_WEBHOOK_URL = os.getenv("FORMS_WEBHOOK_URL", "").strip()
if FORMS_WEBHOOK_URL and not (
    FORMS_WEBHOOK_URL.lower().startswith("https://")
    or (FORMS_WEBHOOK_URL.startswith("/") and not FORMS_WEBHOOK_URL.startswith("//"))
):
    raise RuntimeError("FORMS_WEBHOOK_URL must be an HTTPS URL or a root-relative path.")

# Edit these two collections to swap portfolio categories, projects, links or thumbnails.
PORTFOLIO_CATEGORIES = [
    {"id": "home", "label": "Home services"},
    {"id": "wellness", "label": "Clinics & wellness"},
    {"id": "professional", "label": "Legal & professional"},
    {"id": "saas", "label": "B2B & SaaS"},
]

PORTFOLIO_PROJECTS = [
    {
        "title": "Lion Leak Detection",
        "category": "home",
        "theme": "pool",
        "type": "Lead-generation website",
        "status": "Privacy-safe demo",
        "url": "https://www.lionleak.com/",
        "image": "portfolio/lion-leak.webp",
        "image_small": "portfolio/lion-leak-720.webp",
        "alt": "Lion Leak Detection website homepage",
        "description": "A fast, trust-first local service journey built around calls, messages and urgent lead capture.",
    },
    {
        "title": "FloorSure Flooring",
        "category": "home",
        "theme": "flooring",
        "type": "Lead-generation website",
        "status": "Privacy-safe demo",
        "url": "https://floorsurellc.lovable.app/",
        "image": "portfolio/floorsure.webp",
        "image_small": "portfolio/floorsure-720.webp",
        "alt": "FloorSure flooring website homepage",
        "description": "A residential flooring page that pairs visual confidence with an estimate form above the fold.",
    },
    {
        "title": "Merae Skin Studio",
        "category": "wellness",
        "theme": "wellness",
        "type": "Industry concept",
        "status": "Privacy-safe demo",
        "url": "/merae-skin-studio/",
        "image": "portfolio/merae-skin-studio.webp",
        "image_small": "portfolio/merae-skin-studio-720.webp",
        "alt": "Merae Skin Studio portfolio concept homepage",
        "description": "A consultation-led concept for a premium medical-aesthetics studio, designed around informed choice.",
    },
    {
        "title": "Brazilian Clinic",
        "category": "wellness",
        "theme": "clinic",
        "type": "Conversion landing page",
        "status": "Privacy-safe demo",
        "url": "/spa/",
        "image": "portfolio/brazilian-clinic.webp",
        "image_small": "portfolio/brazilian-clinic-720.webp",
        "alt": "Brazilian aesthetics clinic day spa landing page",
        "description": "A high-intent spa landing page for a Brazilian aesthetics clinic, pairing premium storytelling, local SEO and WhatsApp booking.",
    },
    {
        "title": "Friedland Law",
        "category": "professional",
        "theme": "legal",
        "type": "Multi-page website",
        "status": "Privacy-safe demo",
        "url": "https://friedland-law-site.lovable.app",
        "image": "portfolio/friedland-law.webp",
        "image_small": "portfolio/friedland-law-720.webp",
        "alt": "Friedland Law website homepage",
        "description": "An authority-led multilingual legal experience that turns high-intent visits into consultations.",
    },
    {
        "title": "CbCloud MCP",
        "category": "saas",
        "theme": "saas",
        "type": "Product landing page",
        "status": "Privacy-safe demo",
        "url": "https://lp.cbcloud.com.br/mcp/?lang=en",
        "image": "portfolio/cbcloud-mcp.webp",
        "image_small": "portfolio/cbcloud-mcp-720.webp",
        "alt": "CbCloud MCP product landing page in English",
        "description": "A product-led SaaS page that turns complex AI infrastructure into a clear seven-day trial path.",
    },
]

FAQ_ITEMS = [
    {
        "question": "Why is this cheaper than agencies here?",
        "answer": "We're based in Brazil, work lean and use a tested component system. The work is custom; the overhead is not. That cost structure keeps the price lower without turning the project into template assembly.",
    },
    {
        "question": "What if I don't like the design?",
        "answer": "You see a live preview partway through, not only at the end. Every package includes revisions, and the project only launches after your approval.",
    },
    {
        "question": "Do I need to pay monthly?",
        "answer": "No. You own the domain, code and all accounts. Optional hosting and maintenance is $49/month if you'd rather not manage it, and you can cancel anytime.",
    },
    {
        "question": "Can you improve my current site instead?",
        "answer": "Sometimes — and if updating your existing site is the cheaper answer, we'll say so. Send the link and you'll get an honest recommendation.",
    },
    {
        "question": "How do we handle payment?",
        "answer": "50% to start and 50% before launch, by bank transfer, Wise or card. An invoice is provided for every project.",
    },
]


app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = not IS_PRODUCTION
app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 31536000 if IS_PRODUCTION else 0
app.jinja_env.auto_reload = not IS_PRODUCTION
SPA_DIRECTORY = os.path.join(app.root_path, "spa")
MERAE_DIRECTORY = os.path.join(app.root_path, "merae-skin-studio")
MERAE_ASSETS_DIRECTORY = os.path.join(MERAE_DIRECTORY, "assets")


def site_url() -> str:
    if CONFIGURED_SITE_URL:
        return CONFIGURED_SITE_URL
    if has_request_context():
        return request.url_root.rstrip("/")
    return "http://localhost:8000"


def structured_data(base_url: str) -> dict:
    organization_id = f"{base_url}/#organization"
    website_id = f"{base_url}/#website"
    return {
        "@context": "https://schema.org",
        "@graph": [
            {
                "@type": "Organization",
                "@id": organization_id,
                "name": "Sevenday Sites",
                "url": f"{base_url}/",
                "email": "hello@sevendaysites.studio",
                "description": "Custom websites for small businesses, delivered in 3–7 days.",
                "logo": {
                    "@type": "ImageObject",
                    "url": f"{base_url}/static/favicon.svg?v={ASSET_VERSION}",
                },
                "areaServed": "Worldwide",
                "knowsLanguage": ["English", "Portuguese"],
            },
            {
                "@type": "WebSite",
                "@id": website_id,
                "url": f"{base_url}/",
                "name": "Sevenday Sites",
                "publisher": {"@id": organization_id},
                "inLanguage": "en",
            },
            {
                "@type": "Service",
                "@id": f"{base_url}/#website-design-service",
                "name": "Small business website design and development",
                "serviceType": "Website design and development",
                "description": "Custom, mobile-first websites with fixed pricing and delivery in 3–7 working days.",
                "provider": {"@id": organization_id},
                "areaServed": "Worldwide",
                "offers": [
                    {
                        "@type": "Offer",
                        "name": "Landing Page",
                        "price": "600",
                        "priceCurrency": "USD",
                        "url": f"{base_url}/briefing?plan=landing",
                    },
                    {
                        "@type": "Offer",
                        "name": "Simple Website",
                        "price": "1000",
                        "priceCurrency": "USD",
                        "url": f"{base_url}/briefing?plan=simple",
                    },
                    {
                        "@type": "Offer",
                        "name": "Premium Website",
                        "price": "1600",
                        "priceCurrency": "USD",
                        "url": f"{base_url}/briefing?plan=premium",
                    },
                ],
            },
            {
                "@type": "FAQPage",
                "@id": f"{base_url}/#faq",
                "mainEntity": [
                    {
                        "@type": "Question",
                        "name": item["question"],
                        "acceptedAnswer": {"@type": "Answer", "text": item["answer"]},
                    }
                    for item in FAQ_ITEMS
                ],
            },
        ],
    }


@app.context_processor
def inject_site_context():
    base_url = site_url()
    return {
        "asset_version": ASSET_VERSION,
        "site_url": base_url,
        "canonical_url": f"{base_url}/",
        "robots_directive": (
            "index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1"
            if SITE_INDEXABLE
            else "noindex, nofollow"
        ),
        "portfolio_categories": PORTFOLIO_CATEGORIES,
        "portfolio_projects": PORTFOLIO_PROJECTS,
        "faq_items": FAQ_ITEMS,
        "structured_data": structured_data(base_url),
        "gtm_container_id": GTM_CONTAINER_ID,
        "forms_webhook_url": FORMS_WEBHOOK_URL,
    }


@app.after_request
def optimize_response(response):
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault("Permissions-Policy", "camera=(), geolocation=(), microphone=()")

    if not SITE_INDEXABLE and request.endpoint != "static":
        response.headers["X-Robots-Tag"] = "noindex, nofollow"

    if request.endpoint == "static":
        response.headers["Cache-Control"] = (
            "public, max-age=31536000, immutable" if IS_PRODUCTION else "no-cache"
        )
    elif response.mimetype in {"text/html", "application/xml", "text/xml"}:
        response.headers.setdefault("Cache-Control", "no-cache")

    compressible = {
        "text/html",
        "text/javascript",
        "text/css",
        "text/plain",
        "text/xml",
        "application/javascript",
        "application/json",
        "application/manifest+json",
        "application/xml",
        "image/svg+xml",
    }
    accepts_gzip = "gzip" in request.headers.get("Accept-Encoding", "").lower()
    can_compress = (
        accepts_gzip
        and request.method != "HEAD"
        and response.status_code >= 200
        and response.status_code < 300
        and not response.direct_passthrough
        and "Content-Encoding" not in response.headers
        and response.mimetype in compressible
    )
    if can_compress:
        data = response.get_data()
        if len(data) >= 1024:
            compressed = gzip.compress(data, compresslevel=6)
            if len(compressed) < len(data):
                response.set_data(compressed)
                response.headers["Content-Encoding"] = "gzip"
                response.headers["Content-Length"] = str(len(compressed))
                response.vary.add("Accept-Encoding")

    return response


@app.get("/")
def home():
    return render_template("index.html")


@app.get("/spa/")
def spa_demo():
    response = make_response(send_from_directory(SPA_DIRECTORY, "index.html", max_age=0))
    response.direct_passthrough = False
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
    return response


@app.get("/spa")
@app.get("/spa/index.html")
def spa_demo_redirect():
    return redirect(url_for("spa_demo"), code=308)


@app.get("/spa/<path:asset_path>")
def spa_asset(asset_path):
    if not asset_path.startswith(("images/", "video/")):
        abort(404)
    response = make_response(
        send_from_directory(
            SPA_DIRECTORY,
            asset_path,
            max_age=86400 if IS_PRODUCTION else 0,
        )
    )
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
    return response


@app.get("/merae-skin-studio/")
def merae_demo():
    response = make_response(send_from_directory(MERAE_DIRECTORY, "index.html", max_age=0))
    response.direct_passthrough = False
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
    return response


@app.get("/merae-skin-studio")
@app.get("/merae-skin-studio/index.html")
def merae_demo_redirect():
    return redirect(url_for("merae_demo"), code=308)


@app.get("/merae-skin-studio/assets/<path:asset_path>")
def merae_asset(asset_path):
    response = make_response(
        send_from_directory(
            MERAE_ASSETS_DIRECTORY,
            asset_path,
            max_age=86400 if IS_PRODUCTION else 0,
        )
    )
    if response.mimetype in {"text/css", "text/javascript", "application/javascript"}:
        response.direct_passthrough = False
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
    return response


@app.get("/index")
@app.get("/index.html")
def legacy_home():
    return redirect(url_for("home"), code=301)


@app.get("/favicon.ico")
def legacy_favicon():
    return redirect(url_for("static", filename="favicon.svg", v=ASSET_VERSION), code=302)


@app.get("/robots.txt")
def robots():
    sitemap_line = f"Sitemap: {site_url()}/sitemap.xml\n" if SITE_INDEXABLE else ""
    body = f"User-agent: *\nAllow: /\nDisallow: /lp/help\n{sitemap_line}"
    return Response(body, mimetype="text/plain")


@app.get("/sitemap.xml")
def sitemap():
    template_path = os.path.join(app.root_path, "templates", "index.html")
    modified = datetime.fromtimestamp(
        os.path.getmtime(template_path), tz=timezone.utc
    ).date().isoformat()
    location = escape(f"{site_url()}/")
    url_entry = (
        f"  <url><loc>{location}</loc><lastmod>{modified}</lastmod>"
        "<changefreq>monthly</changefreq><priority>1.0</priority></url>\n"
        if SITE_INDEXABLE
        else ""
    )
    body = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{url_entry}"
        "</urlset>\n"
    )
    return Response(body, mimetype="application/xml")


@app.get("/<slug>")
def landing_page(slug):
    if "." in slug:
        abort(404)
    path = os.path.join(app.root_path, "templates", f"{slug}.html")
    if not os.path.isfile(path):
        abort(404)
    response = make_response(render_template(f"{slug}.html"))
    if slug == "briefing":
        response.headers["X-Robots-Tag"] = "noindex, follow"
    return response


@app.get("/lp/help")
def list_slugs():
    template_dir = os.path.join(app.root_path, "templates")
    slug_list = sorted(
        file_name[:-5]
        for file_name in os.listdir(template_dir)
        if file_name.endswith(".html")
    )
    response = make_response({str(index): slug for index, slug in enumerate(slug_list)})
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    return response


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")), debug=not IS_PRODUCTION)
