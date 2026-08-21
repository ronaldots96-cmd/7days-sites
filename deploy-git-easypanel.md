# Tutorial: Deploy via Git no EasyPanel

## 1. Criar repositório no GitHub

```bash
# Na raiz do projeto
git init
git add .
git commit -m "Initial commit"
```

Crie um repositório no GitHub (sem README, sem .gitignore) e suba:

```bash
git remote add origin https://github.com/seu-user/seu-repo.git
git branch -M main
git push -u origin main
```

## 2. Conectar no EasyPanel

1. Acesse o painel do EasyPanel
2. Vá em **Deployments → Create Deployment**
3. Escolha **Git Provider** e conecte sua conta GitHub
4. Selecione o repositório e a branch `main`
5. Em **Build Settings**:
   - **Dockerfile**: `Dockerfile`
   - **Porta Interna**: `5010`
6. Defina domínio/subdomínio se desejar
7. Clique em **Deploy**

## 3. Fluxo de atualização

Toda vez que alterar uma LP:

```bash
git add templates/campanha-x.html
git commit -m "Atualiza LP campanha-x"
git push
```

O EasyPanel detecta o push, rebuilda a imagem e atualiza o container automaticamente.

## 4. Verificar deploy

Acesse pelo domínio configurado:

```
https://seu-dominio.com/lp/1
https://seu-dominio.com/lp/campanha-x
```
