# Skill / Contexto para Agentes de IA — Geração de Landing Pages (Padrão Flask + Docker)

## 1. Objetivo da Skill

Esta skill define regras obrigatórias para agentes de IA responsáveis por gerar landing pages dentro do sistema padronizado da empresa.

O objetivo é garantir que todas as LPs sejam compatíveis com:

- Estrutura Flask (1 app por cliente)
- Rotas baseadas em `/lp/<slug>`
- Execução via Docker em EasyPanel
- Regras de SEO, Performance e Tracking
- Compatibilidade com renderização por arquivo HTML ou template Flask

---

## 2. Contexto Arquitetural Obrigatório

Cada cliente possui um único aplicativo Flask responsável por servir múltiplas landing pages.

As LPs são acessadas via:

```

/lp/<slug>

```

E são armazenadas como arquivos HTML dentro do diretório:

```

/lps/<slug>.html

````

O Flask apenas serve o conteúdo — não deve gerar lógica de página.

---

## 3. Responsabilidade do Agente de IA

O agente de IA deve gerar **LPs completas e prontas para produção**, incluindo:

- Estrutura HTML completa
- SEO embutido
- Tracking embutido
- Estilização (CSS inline ou interno)
- Conteúdo completo da página
- CTA otimizado para conversão

O resultado final deve ser um HTML utilizável diretamente pelo Flask.

---

## 4. Estrutura Obrigatória da Landing Page

Toda landing page gerada deve seguir esta estrutura mínima:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">

    <!-- SEO OBRIGATÓRIO -->
    <title>{TITLE_OTIMIZADO}</title>
    <meta name="description" content="{DESCRIPTION_OTIMIZADA}">

    <!-- Open Graph OBRIGATÓRIO -->
    <meta property="og:title" content="{TITLE_OTIMIZADO}">
    <meta property="og:description" content="{DESCRIPTION_OTIMIZADA}">
    <meta property="og:type" content="website">

    <!-- Responsividade -->
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- Tracking base obrigatório -->
    <script src="/static/tracking.js"></script>
</head>

<body>

    <header>
        <h1>{HEADLINE_PRINCIPAL}</h1>
    </header>

    <main>
        <section>
            {CONTEÚDO_PERSUASIVO_OTIMIZADO}
        </section>

        <section>
            <button onclick="trackCTA()">
                {CTA_PRINCIPAL}
            </button>
        </section>
    </main>

</body>
</html>
````

---

## 5. Regras de SEO (OBRIGATÓRIAS)

Toda LP gerada deve seguir:

* Um único `<h1>` por página
* Uso correto de hierarquia `<h2>`, `<h3>` quando necessário
* Título otimizado para intenção de busca
* Descrição clara e persuasiva
* Estrutura legível por Google
* Não gerar conteúdo duplicado entre páginas

---

## 6. Regras de Performance (OBRIGATÓRIAS)

O HTML gerado deve ser leve e otimizado:

* Evitar bibliotecas externas pesadas
* CSS preferencialmente inline ou mínimo interno
* Evitar imagens não otimizadas
* Usar lazy loading quando aplicável
* Evitar scripts desnecessários
* Tempo de carregamento otimizado (< 3s ideal)

---

## 7. Regras de Tracking (OBRIGATÓRIAS)

Toda LP deve incluir:

### Eventos obrigatórios:

* page_view automático ao carregar
* click_cta ao clicar no botão principal

### Implementação padrão:

```javascript
function trackCTA() {
    // Evento obrigatório
    console.log("CTA clicado");
}
```

### Regras adicionais:

* Sempre incluir `/static/tracking.js`
* Sempre incluir suporte a UTM parameters na estrutura da página
* Nunca remover tracking base

---

## 8. Regras de Estrutura Flask

O agente deve assumir sempre:

* A página será servida via `/lp/<slug>`
* O HTML será carregado como arquivo estático ou string
* Nenhuma lógica de backend deve ser necessária na LP
* Toda lógica deve estar embutida no HTML final

---

## 9. Regras de Conteúdo

Toda LP deve ser:

* Focada em conversão
* Clara e objetiva
* Sem excesso de texto irrelevante
* Estruturada em blocos (headline → problema → solução → CTA)
* Adaptada ao contexto da campanha

---

## 10. Regras de Consistência

O agente deve garantir:

* Estilo consistente entre LPs de um mesmo cliente
* Tom de voz alinhado à marca
* Estrutura visual previsível
* CTA sempre visível e claro

---

## 11. Output Obrigatório do Agente

O agente SEMPRE deve retornar:

* Um arquivo HTML completo
* Pronto para ser salvo em `/lps/<slug>.html`
* Sem dependências externas obrigatórias
* Compatível com Flask + Docker + EasyPanel

---

## 12. Restrições Importantes

* Não gerar backend Flask
* Não gerar múltiplos arquivos
* Não depender de build tools (Vite, React, etc.)
* Não quebrar padrão `/lp/<slug>`
* Não remover tracking padrão
* Não ignorar regras de SEO e performance

---

## 13. Objetivo Final

Garantir que qualquer landing page gerada por IA seja:

* Diretamente deployável
* Compatível com arquitetura Flask padrão
* Otimizada para SEO e conversão
* Consistente com o sistema de tracking
* Leve, rápida e escalável dentro do Docker + EasyPanel
