#!/usr/bin/env bash
# Verificador · Avaliação Prática de Docker · Cooperativa AgroVale (Turma A)
# Rode da RAIZ do projeto, com a stack no ar:   bash scripts/verificar.sh
# Funciona no Linux, no macOS e no Git Bash do Windows. Não precisa de Python.
# O verificador aponta o que está errado, não como consertar.

TURMA="A"
PREFIXO="agrovale"
SAL="DEVOPS-DOCKER-2026"

cd "$(dirname "$0")/.." || exit 2
OK=0; TOTAL=0

checar() {  # checar CODIGO "descrição" resultado(0=ok) "dica"
  TOTAL=$((TOTAL+1))
  if [ "$3" -eq 0 ]; then OK=$((OK+1)); echo "[ OK ] $1 $2"
  else echo "[FALHA] $1 $2"; [ -n "$4" ] && echo "         -> $4"; fi
}
http() { curl -s -m 8 "$1" 2>/dev/null; }
cid() { docker compose ps -q "$1" 2>/dev/null | head -n1; }
insp() { [ -n "$1" ] && docker inspect -f "$2" "$1" 2>/dev/null; }

echo "================================================================"
echo " Verificador · Avaliação Prática de Docker · Turma $TURMA"
echo "================================================================"

[ -f docker-compose.yml ] || [ -f compose.yaml ] || { echo "Rode na raiz do projeto (onde fica o docker-compose.yml)."; exit 2; }
[ -f .env ] || { echo "[FALHA] arquivo .env não encontrado."; exit 2; }
val() { grep -E "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r"'"'" | xargs; }
MAT=$(val MATRICULA); HUB=$(val DOCKERHUB_USER)
if ! echo "$MAT" | grep -Eq '^[0-9]{4,15}$'; then echo "[FALHA] MATRICULA ausente ou inválida no .env."; exit 2; fi
XX=$((10#${MAT: -2}))
P_PORTAL=$((8000+XX)); P_BLOG=$((9000+XX)); P_MANUT=$((7000+XX))
IMG="$HUB/$PREFIXO-portal:1.0-$MAT"
echo " Matrícula $MAT · portal $P_PORTAL · blog $P_BLOG · manutenção $P_MANUT"
echo

echo "A. Arquivos, imagens e Git"
DF=portal/Dockerfile; r=1; dica="portal/Dockerfile não encontrado"
if [ -f "$DF" ]; then
  FROM=$(grep -iE '^\s*FROM' "$DF" | head -n1 | awk '{print $2}')
  r=0; dica=""
  echo "$FROM" | grep -q ':' && ! echo "$FROM" | grep -q ':latest' || { r=1; dica="imagem base sem tag fixa (ou :latest). "; }
  grep -iqE '^\s*COPY' "$DF" || { r=1; dica="${dica}sem COPY. "; }
  grep -iqE '^\s*EXPOSE\s+80\b' "$DF" || { r=1; dica="${dica}sem EXPOSE 80. "; }
  grep -iqE '^\s*LABEL' "$DF" || { r=1; dica="${dica}sem LABEL. "; }
fi
checar A1 "portal/Dockerfile segue os requisitos" $r "$dica"

# Página de manutenção: sobe um container temporário da sua imagem e testa
r=1; dica="imagem manutencao:$MAT não encontrada. Construa com: docker build -t manutencao:$MAT ./manutencao"
if docker image inspect "manutencao:$MAT" >/dev/null 2>&1; then
  docker rm -f verif-manut >/dev/null 2>&1
  if docker run -d --name verif-manut -p "$P_MANUT:80" "manutencao:$MAT" >/dev/null 2>&1; then
    sleep 2
    if [ "$(insp verif-manut '{{.State.Running}}')" != "true" ]; then dica="o container da manutenção encerra logo depois de iniciar"
    elif http "http://localhost:$P_MANUT/" | grep -q "PAGINA-MANUTENCAO-OK"; then r=0
    else dica="o container sobe, mas a página servida não é o aviso de manutenção"; fi
  else dica="não foi possível iniciar a imagem (a porta $P_MANUT está ocupada?)"; fi
  docker rm -f verif-manut >/dev/null 2>&1
fi
checar A2 "imagem manutencao:$MAT corrigida e servindo o aviso" $r "$dica"

r=0
[ -n "$(git ls-files .env 2>/dev/null)" ] && r=1
grep -Eq '^\s*/?\.env\s*$' .gitignore 2>/dev/null || r=1
[ "$(git ls-files .env.example 2>/dev/null)" = ".env.example" ] || r=1
checar A3 ".env fora do Git e .env.example versionado" $r "confira o .gitignore e rode: git ls-files"

N=$(git rev-list --count HEAD 2>/dev/null || echo 0)
r=1; [ "$N" -ge 5 ] && git remote -v 2>/dev/null | grep -q github.com && r=0
checar A4 "5+ commits e remoto no GitHub (encontrados: $N)" $r "faça commits por etapa e configure o origin"

r=1; [ -n "$HUB" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "https://hub.docker.com/v2/repositories/$HUB/$PREFIXO-portal/tags/1.0-$MAT")" = "200" ] && r=0
checar A5 "imagem $IMG pública no Docker Hub" $r "não encontrada: repositório privado, tag fora da regra ou sem internet"

echo
echo "B. Stack em execução"
PORTAL=$(cid portal); BLOG=$(cid blog); DB=$(cid db)
r=0; for c in "$PORTAL" "$BLOG" "$DB"; do [ "$(insp "$c" '{{.State.Running}}')" = "true" ] || r=1; done
checar B1 "serviços portal, blog e db em execução" $r "confira com: docker compose ps"

r=1; [ "$(insp "$PORTAL" '{{.Config.Image}}')" = "$IMG" ] && r=0
checar B2 "portal roda a imagem publicada" $r "imagem em uso: $(insp "$PORTAL" '{{.Config.Image}}')"

r=1
docker compose port portal 80 2>/dev/null | grep -q ":$P_PORTAL$" && docker compose port blog 80 2>/dev/null | grep -q ":$P_BLOG$" && r=0
checar B3 "portas: portal em $P_PORTAL e blog em $P_BLOG" $r "portal=$(docker compose port portal 80 2>/dev/null) blog=$(docker compose port blog 80 2>/dev/null)"

r=0
[ -n "$(insp "$DB" '{{range $p, $b := .HostConfig.PortBindings}}{{$p}} {{end}}')" ] && r=1
insp "$DB" '{{range .Mounts}}{{.Type}}|{{.Destination}} {{end}}' | grep -q 'volume|/var/lib/mysql' || r=1
checar B4 "db sem porta publicada e com volume nomeado" $r "revise ports e volumes do serviço db"

r=1; insp "$BLOG" '{{range .Mounts}}{{.Type}}|{{.Destination}} {{end}}' | grep -q 'volume|/var/www/html' && r=0
checar B5 "blog com volume nomeado em /var/www/html" $r ""

nets() { insp "$1" '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | tr ' ' '\n' | grep -v '^$' | sort; }
COMUM=$(comm -12 <(nets "$PORTAL") <(nets "$BLOG") | comm -12 - <(nets "$DB") | grep -v '_default$')
r=1; [ -n "$COMUM" ] && r=0
checar B6 "rede própria compartilhada pelos três serviços" $r "os serviços estão na rede default do Compose"

r=0; for c in "$PORTAL" "$BLOG" "$DB"; do
  case "$(insp "$c" '{{.HostConfig.RestartPolicy.Name}}')" in unless-stopped|always) ;; *) r=1;; esac; done
checar B7 "política de restart nos três serviços" $r ""

r=0; grep -iE 'PASSWORD\s*[:=]' docker-compose.yml 2>/dev/null | grep -v '\${' | grep -q . && r=1
checar B8 "nenhuma senha escrita direto no docker-compose.yml" $r "senhas vêm do .env com \${VARIAVEL}"

echo
echo "C. Conteúdo e persistência"
r=1; http "http://localhost:$P_PORTAL/" | grep -q "$MAT" && ! http "http://localhost:$P_PORTAL/" | grep -q "SEU NOME AQUI" && r=0
checar C1 "portal mostra seu nome e sua matrícula" $r "edite o rodapé do index.html, reconstrua, publique e recrie o container"

r=1; http "http://localhost:$P_BLOG/?rest_route=/" | grep -Eq "\"name\": *\"[^\"]*$MAT" && r=0
checar C2 "WordPress instalado com a matrícula no título do site" $r "instale o WordPress pelo navegador em http://localhost:$P_BLOG"

POSTS=$(http "http://localhost:$P_BLOG/?rest_route=/wp/v2/posts&search=$MAT")
DATA_POST=$(echo "$POSTS" | grep -Eo '"date_gmt": *"[^"]*"' | tail -n1 | sed -E 's/.*: *"([^"]*)"/\1/')
CRIADO=$(insp "$BLOG" '{{.Created}}' | cut -c1-19)
r=1; dica="nenhum post com a sua matrícula no título"
if [ -n "$DATA_POST" ]; then
  if [[ "$DATA_POST" < "$CRIADO" ]]; then r=0
  else dica="o post existe, mas o container do blog não foi recriado depois dele (faça o ciclo de down e up)"; fi
fi
checar C3 "post sobreviveu à recriação do blog (post $DATA_POST · container $CRIADO)" $r "$dica"

echo
echo "================================================================"
echo " Resultado: $OK/$TOTAL verificações"
if [ "$OK" -eq "$TOTAL" ]; then
  if command -v sha256sum >/dev/null 2>&1; then H=$(printf '%s' "$TURMA:$MAT:$SAL" | sha256sum | cut -c1-8)
  else H=$(printf '%s' "$TURMA:$MAT:$SAL" | shasum -a 256 | cut -c1-8); fi
  echo " Código de conclusão: $(echo "$PREFIXO" | tr a-z A-Z)-$MAT-$(echo "$H" | tr a-f A-F)"
  echo " Copie o código para o respostas.md, faça o commit final e crie a tag v1.0."
else
  echo " Ainda há falhas. Corrija e rode de novo."
fi
echo "================================================================"
[ "$OK" -eq "$TOTAL" ]
