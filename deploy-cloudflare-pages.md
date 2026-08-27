# Deploy no Cloudflare Pages

Este projeto é publicado como site estático. O Flask roda somente durante o
build; o Cloudflare Pages serve o conteúdo gerado em `dist/`.

## 1. Preparar o repositório

Antes do primeiro deploy, rode o build local e confirme que a home, o briefing
e as duas demos abrem corretamente:

```powershell
python -m pip install -r requirements.txt
$env:SITE_INDEXABLE = "false"
python build_static.py
npx.cmd wrangler pages dev dist
```

No macOS/Linux, use `npx wrangler pages dev dist`.

Depois, envie o projeto para o repositório Git. A pasta `dist/` é artefato de
build e não deve ser versionada.

## 2. Criar o projeto no Pages

1. No painel Cloudflare, abra **Workers & Pages**.
2. Escolha **Create application → Pages → Connect to Git**.
3. Autorize o provedor Git, selecione o repositório e a branch de produção
   (normalmente `main`).
4. Use estas configurações:

```text
Framework preset: None
Build command: python -m pip install -r requirements.txt && python build_static.py
Build output directory: dist
Root directory: deixe vazio (raiz do repositório)
```

5. Em **Environment variables**, configure `SITE_INDEXABLE=false` tanto para
   **Production** quanto para **Preview**.
6. Não crie `SITE_URL` nesta fase. O build usará automaticamente
   `CF_PAGES_URL`, definido pelo Pages para cada deploy.
7. Se necessário, configure `BRIEFING_WEBHOOK_URL`. `ASSET_VERSION` pode ficar
   vazio, pois o SHA do commit será usado como versão dos assets.
8. Inicie o deploy. Ao concluir, o Pages fornecerá uma URL como
   `https://nome-do-projeto.pages.dev`.

Cada novo push na branch de produção gera outro deploy. Pull requests e outras
branches podem gerar previews isolados, que também devem permanecer com
`SITE_INDEXABLE=false`.

## 3. Verificar o deploy temporário

Teste as rotas:

```text
/
/briefing
/spa/
/merae-skin-studio/
/robots.txt
/uma-rota-inexistente
```

Confirme também:

- home e portfólio sem marcas de template como `{{ ... }}`;
- filtros, links e previews dos cards funcionando;
- briefing abrindo e, se configurado, chegando ao webhook correto;
- resposta 404 real para uma rota inexistente;
- meta robots e cabeçalho `X-Robots-Tag` com `noindex` na URL temporária;
- ausência de erros relevantes no console do navegador.

Os arquivos `_headers` e `_redirects` são gerados dentro de `dist/` pelo build
e aplicados automaticamente pelo Cloudflare Pages.

## 4. Ativar o domínio definitivo

Quando o domínio estiver comprado e validado:

1. Adicione-o em **Pages → Custom domains** e conclua a configuração DNS.
2. Na variável de **Production**, defina `SITE_URL=https://dominio-final.com`
   (sem barra no final).
3. Altere `SITE_INDEXABLE=true` somente em **Production**. Mantenha `false` no
   ambiente de **Preview**.
4. Faça um novo deploy e confirme canonical, Open Graph, `robots.txt` e
   `sitemap.xml` apontando para o domínio final.
5. Teste formulário, webhook, links externos, páginas de demo e a página 404.
6. Garanta que links internos não apontem para `pages.dev`; se a URL temporária
   continuar acessível, mantenha o canonical no domínio final ou configure um
   redirecionamento permanente.
7. Cadastre o domínio e envie o sitemap nas ferramentas de busca somente após
   essas validações.

Se o build falhar, abra os logs do deploy no Pages. Os primeiros pontos a
conferir são a versão do Python, a instalação de `requirements.txt` e se
`build_static.py` realmente criou `dist/index.html`.
