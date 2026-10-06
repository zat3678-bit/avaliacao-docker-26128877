# Verificador · Avaliação Prática de Docker · Cooperativa AgroVale (Turma A)
# Rode da RAIZ do projeto, com a stack no ar:
#   powershell -ExecutionPolicy Bypass -File scripts\verificar.ps1
# Não precisa de Python. O verificador aponta o que está errado, não como consertar.

$TURMA = "A"
$PREFIXO = "agrovale"
$SAL = "DEVOPS-DOCKER-2026"

Set-Location (Join-Path $PSScriptRoot "..")
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"
$script:NumOk = 0; $script:NumTotal = 0

function Checar($codigo, $descricao, [bool]$ok, $dica) {
  $script:NumTotal++
  if ($ok) { $script:NumOk++; Write-Host "[ OK ] $codigo $descricao" -ForegroundColor Green }
  else { Write-Host "[FALHA] $codigo $descricao" -ForegroundColor Red; if ($dica) { Write-Host "         -> $dica" } }
}
function Http($url) {
  try {
    $c = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8).Content
    if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
    return [string]$c
  } catch { return "" }
}
function Status($url) {
  try { return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10).StatusCode } catch { return 0 }
}
function Cid($svc) { $r = docker compose ps -q $svc 2>$null; if ($r) { return ($r | Select-Object -First 1).Trim() } return "" }
function Insp($id, $fmt) { if (-not $id) { return "" }; $r = docker inspect -f $fmt $id 2>$null; return ($r -join " ").Trim() }

Write-Host "================================================================"
Write-Host " Verificador · Avaliação Prática de Docker · Turma $TURMA"
Write-Host "================================================================"

if (-not ((Test-Path docker-compose.yml) -or (Test-Path compose.yaml))) { Write-Host "Rode na raiz do projeto."; exit 2 }
if (-not (Test-Path .env)) { Write-Host "[FALHA] arquivo .env não encontrado."; exit 2 }
$envs = @{}
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([A-Za-z_]+)\s*=\s*(.*)$') { $envs[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'") }
}
$MAT = $envs["MATRICULA"]; $HUB = $envs["DOCKERHUB_USER"]
if (-not ($MAT -match '^\d{4,15}$')) { Write-Host "[FALHA] MATRICULA ausente ou inválida no .env."; exit 2 }
$XX = [int]$MAT.Substring($MAT.Length - 2)
$P_PORTAL = 8000 + $XX; $P_BLOG = 9000 + $XX; $P_MANUT = 7000 + $XX
$IMG = "$HUB/$PREFIXO-portal:1.0-$MAT"
Write-Host " Matrícula $MAT · portal $P_PORTAL · blog $P_BLOG · manutenção $P_MANUT`n"

Write-Host "A. Arquivos, imagens e Git"
$DF = "portal/Dockerfile"; $ok = $false; $dica = "portal/Dockerfile não encontrado"
if (Test-Path $DF) {
  $linhas = Get-Content $DF
  $from = ($linhas | Where-Object { $_ -match '^\s*FROM\s+' } | Select-Object -First 1) -replace '^\s*FROM\s+', ''
  $from = ($from -split '\s+')[0]
  $ok = $true; $dica = ""
  if (-not ($from -match ':') -or $from -match ':latest') { $ok = $false; $dica += "imagem base sem tag fixa (ou :latest). " }
  if (-not ($linhas -match '^\s*COPY\s')) { $ok = $false; $dica += "sem COPY. " }
  if (-not ($linhas -match '^\s*EXPOSE\s+80\b')) { $ok = $false; $dica += "sem EXPOSE 80. " }
  if (-not ($linhas -match '^\s*LABEL\s')) { $ok = $false; $dica += "sem LABEL. " }
}
Checar "A1" "portal/Dockerfile segue os requisitos" $ok $dica

$ok = $false; $dica = "imagem manutencao:$MAT não encontrada. Construa com: docker build -t manutencao:$MAT ./manutencao"
docker image inspect "manutencao:$MAT" *> $null
if ($LASTEXITCODE -eq 0) {
  docker rm -f verif-manut *> $null
  docker run -d --name verif-manut -p "${P_MANUT}:80" "manutencao:$MAT" *> $null
  if ($LASTEXITCODE -eq 0) {
    Start-Sleep -Seconds 2
    if ((Insp "verif-manut" "{{.State.Running}}") -ne "true") { $dica = "o container da manutenção encerra logo depois de iniciar" }
    elseif ((Http "http://localhost:$P_MANUT/") -match "PAGINA-MANUTENCAO-OK") { $ok = $true }
    else { $dica = "o container sobe, mas a página servida não é o aviso de manutenção" }
  } else { $dica = "não foi possível iniciar a imagem (a porta $P_MANUT está ocupada?)" }
  docker rm -f verif-manut *> $null
}
Checar "A2" "imagem manutencao:$MAT corrigida e servindo o aviso" $ok $dica

$tracked = git ls-files .env 2>$null
$gi = if (Test-Path .gitignore) { Get-Content .gitignore } else { @() }
$ex = git ls-files .env.example 2>$null
$ok = (-not $tracked) -and ($gi -match '^\s*/?\.env\s*$') -and ($ex -eq ".env.example")
Checar "A3" ".env fora do Git e .env.example versionado" $ok "confira o .gitignore e rode: git ls-files"

$N = 0; $c = git rev-list --count HEAD 2>$null; if ($c) { $N = [int]$c }
$rem = (git remote -v 2>$null) -join " "
Checar "A4" "5+ commits e remoto no GitHub (encontrados: $N)" (($N -ge 5) -and ($rem -match "github.com")) "faça commits por etapa e configure o origin"

$ok = $false
if ($HUB) { $ok = (Status "https://hub.docker.com/v2/repositories/$HUB/$PREFIXO-portal/tags/1.0-$MAT") -eq 200 }
Checar "A5" "imagem $IMG pública no Docker Hub" $ok "não encontrada: repositório privado, tag fora da regra ou sem internet"

Write-Host "`nB. Stack em execução"
$PORTAL = Cid "portal"; $BLOG = Cid "blog"; $DB = Cid "db"
$ok = $true; foreach ($x in @($PORTAL, $BLOG, $DB)) { if ((Insp $x "{{.State.Running}}") -ne "true") { $ok = $false } }
Checar "B1" "serviços portal, blog e db em execução" $ok "confira com: docker compose ps"

$imgUso = Insp $PORTAL "{{.Config.Image}}"
Checar "B2" "portal roda a imagem publicada" ($imgUso -eq $IMG) "imagem em uso: $imgUso"

$pp = (docker compose port portal 80 2>$null) -join " "; $pb = (docker compose port blog 80 2>$null) -join " "
Checar "B3" "portas: portal em $P_PORTAL e blog em $P_BLOG" (($pp -match ":$P_PORTAL\b") -and ($pb -match ":$P_BLOG\b")) "portal=$pp blog=$pb"

$pubDb = Insp $DB '{{range $p, $b := .HostConfig.PortBindings}}{{$p}} {{end}}'
$mDb = Insp $DB '{{range .Mounts}}{{.Type}}|{{.Destination}} {{end}}'
Checar "B4" "db sem porta publicada e com volume nomeado" ((-not $pubDb) -and ($mDb -match 'volume\|/var/lib/mysql')) "revise ports e volumes do serviço db"

$mBlog = Insp $BLOG '{{range .Mounts}}{{.Type}}|{{.Destination}} {{end}}'
Checar "B5" "blog com volume nomeado em /var/www/html" ($mBlog -match 'volume\|/var/www/html') ""

function Redes($id) { return @((Insp $id '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}') -split '\s+' | Where-Object { $_ }) }
$comum = Redes $PORTAL | Where-Object { (Redes $BLOG) -contains $_ -and (Redes $DB) -contains $_ -and $_ -notmatch '_default$' }
Checar "B6" "rede própria compartilhada pelos três serviços" ([bool]$comum) "os serviços estão na rede default do Compose"

$ok = $true; foreach ($x in @($PORTAL, $BLOG, $DB)) { if (@("unless-stopped", "always") -notcontains (Insp $x "{{.HostConfig.RestartPolicy.Name}}")) { $ok = $false } }
Checar "B7" "política de restart nos três serviços" $ok ""

$senhas = Get-Content docker-compose.yml | Where-Object { $_ -match 'PASSWORD\s*[:=]' -and $_ -notmatch '\$\{' }
Checar "B8" "nenhuma senha escrita direto no docker-compose.yml" (-not $senhas) 'senhas vêm do .env com ${VARIAVEL}'

Write-Host "`nC. Conteúdo e persistência"
$pag = Http "http://localhost:$P_PORTAL/"
Checar "C1" "portal mostra seu nome e sua matrícula" (($pag -match $MAT) -and ($pag -notmatch "SEU NOME AQUI")) "edite o rodapé do index.html, reconstrua, publique e recrie o container"

$raiz = Http "http://localhost:$P_BLOG/?rest_route=/"
Checar "C2" "WordPress instalado com a matrícula no título do site" ($raiz -match ('"name":\s*"[^"]*' + $MAT)) "instale o WordPress pelo navegador em http://localhost:$P_BLOG"

$posts = Http "http://localhost:$P_BLOG/?rest_route=/wp/v2/posts&search=$MAT"
$datas = [regex]::Matches($posts, '"date_gmt":\s*"([^"]*)"') | ForEach-Object { $_.Groups[1].Value }
$dataPost = if ($datas) { @($datas)[-1] } else { "" }
$criado = Insp $BLOG "{{.Created}}"; if ($criado.Length -ge 19) { $criado = $criado.Substring(0, 19) }
$ok = $false; $dica = "nenhum post com a sua matrícula no título"
if ($dataPost) {
  if ([string]::CompareOrdinal($dataPost, $criado) -lt 0) { $ok = $true }
  else { $dica = "o post existe, mas o container do blog não foi recriado depois dele (faça o ciclo de down e up)" }
}
Checar "C3" "post sobreviveu à recriação do blog (post $dataPost · container $criado)" $ok $dica

Write-Host "`n================================================================"
Write-Host " Resultado: $($script:NumOk)/$($script:NumTotal) verificações"
if ($script:NumOk -eq $script:NumTotal) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("${TURMA}:${MAT}:$SAL"))
  $h = (($bytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 8).ToUpper()
  Write-Host " Código de conclusão: $($PREFIXO.ToUpper())-$MAT-$h" -ForegroundColor Cyan
  Write-Host " Copie o código para o respostas.md, faça o commit final e crie a tag v1.0."
} else { Write-Host " Ainda há falhas. Corrija e rode de novo." }
Write-Host "================================================================"
if ($script:NumOk -eq $script:NumTotal) { exit 0 } else { exit 1 }
