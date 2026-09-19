# 7days-sites

Site institucional e portfólio da SevenDay/Sites. A aplicação usa Flask apenas
durante o build para renderizar as páginas e gera um site estático em `dist/`,
pronto para publicação no Cloudflare Pages.

## Estrutura principal

- `templates/`: fontes HTML da home e do briefing.
- `static/`: CSS, JavaScript, imagens e thumbnails do portfólio.
- `spa/`: demo da Brazilian Clinic.
- `merae-skin-studio/`: demo da Merae Skin Studio.
- `app.py`: dados do portfólio e renderização Flask usada no build.
- `build_static.py`: gera a versão publicável em `dist/`.

Não edite arquivos dentro de `dist/`: eles são recriados a cada build.

## Rodar localmente

Requer Python e as dependências de `requirements.txt`.

```powershell
python -m pip install -r requirements.txt
$env:SITE_INDEXABLE = "false"
python build_static.py
npx.cmd wrangler pages dev dist
```

Acesse:

- `http://localhost:8788/`
- `http://localhost:8788/briefing`
- `http://localhost:8788/spa/`
- `http://localhost:8788/merae-skin-studio/`

O Wrangler reproduz o tratamento de rotas, redirects e headers do Pages. Em
macOS/Linux, use `npx wrangler pages dev dist`; para uma checagem rápida das
fontes sem instalar Node, use `python app.py`.

## Variáveis de build

- `SITE_INDEXABLE`: use `true` em Production e `false` em Preview. Sem valor
  explícito, o build reconhece a branch `main` como produção.
- `SITE_URL`: a URL canônica padrão é `https://7days-sites.pages.dev`. Use a
  variável somente para substituir esse endereço por um domínio definitivo.
- `ASSET_VERSION`: opcional. Sem ela, o build usa o SHA do commit fornecido
  pelo Cloudflare.
- `FORMS_WEBHOOK_URL`: endpoint público usado pelo navegador. O padrão é a
  Pages Function same-origin `/api/forms`, evitando CORS e sem expor o n8n.
- `N8N_LEAD_WEBHOOK_URL`: variável protegida da Pages Function. Em Production,
  configure como
  `https://n8n.v4lisboatech.com.br/webhook/7days-leadform`. Não é renderizada
  no HTML e não deve ser habilitada em Preview se testes não puderem cadastrar.

Não coloque a URL do n8n em `FORMS_WEBHOOK_URL`: isso faria o navegador voltar
ao POST cross-origin. Mantenha essa variável ausente ou com `/api/forms`.
- `GTM_CONTAINER_ID`: usa por padrão `GTM-MMBHLWJQ`. Defina uma string vazia
  para não carregar o container em um ambiente específico.

Os dois formulários enviam um `submission_id` estável para permitir
idempotência no webhook. O onboarding também envia `parent_lead_id` e
`parent_submission_id`, conectando a Fase 2 à captura original. Dados pessoais
seguem apenas no POST do formulário; os eventos do `dataLayer` contêm somente
metadados de jornada e seleção.

A função [functions/api/forms.js](functions/api/forms.js) valida origem, tipo e
tamanho do payload, encaminha o `submission_id` como chave de idempotência e só
confirma sucesso após o n8n responder com HTTP 2xx.

## Deploy

O deploy recomendado usa a integração Git do Cloudflare Pages:

```text
Framework preset: None
Build command: python -m pip install -r requirements.txt && python build_static.py
Build output directory: dist
```

O procedimento completo e o checklist para ativar o domínio definitivo estão
em [deploy-cloudflare-pages.md](deploy-cloudflare-pages.md).
