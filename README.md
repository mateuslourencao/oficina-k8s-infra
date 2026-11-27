# Oficina Kubernetes Infrastructure

Infraestrutura como código do ambiente Kubernetes local da Oficina, provisionado com Terraform e Kind. Este repositório separa o ciclo de vida do cluster dos fontes da API, que continuam no repositório [soat-fase1-tech-challenge](https://github.com/mateuslourencao/soat-fase1-tech-challenge).

> **Escopo atual:** ambiente local de desenvolvimento e validação. O provider `tehcyx/kind` cria um cluster Kind no Docker; este projeto ainda não provisiona Kubernetes gerenciado em nuvem, API Gateway, banco gerenciado ou deploy contínuo em produção.

## Arquitetura

O Terraform cria o cluster `oficina-local`, mapeia as portas de acesso, constrói e carrega a imagem da aplicação, instala o Metrics Server e aplica os recursos Kubernetes com Kustomize. O HPA usa métricas de CPU e memória para escalar a API. O Metrics Server configura `--kubelet-insecure-tls`, necessário para o certificado do kubelet no Kind.

Os manifests da API, o `kustomization.yaml`, o Dockerfile e o código-fonte continuam no repositório da aplicação. O schema, manifests e estado Terraform do MySQL pertencem ao [oficina-db](https://github.com/mateuslourencao/oficina-db). O deploy integrado prepara o cluster, executa o Terraform do banco e aguarda o MySQL antes de aplicar a API. Este repositório não aplica nem mantém estado dos recursos do banco.

## Estrutura do repositório

```text
.
├── .gitignore
├── .github/
│   └── workflows/
│       └── main.yml
├── README.md
└── infra/
  ├── .terraform.lock.hcl
  ├── main.tf
  ├── outputs.tf
  ├── variables.tf
  └── versions.tf
```

- `main.tf`: define o cluster Kind, a construção/carregamento da imagem, a instalação do Metrics Server e a implantação da aplicação, aguardando o banco ficar pronto.
- `variables.tf`: configura o nome do cluster, as portas locais e o caminho do checkout da aplicação.
- `outputs.tf`: informa o nome do cluster e URLs locais da API e do MailHog.
- `versions.tf` e `.terraform.lock.hcl`: fixam os requisitos e a versão do provider Kind.
- `.gitignore`: evita versionar estado, cache, planos e variáveis locais do Terraform.

## Pré-requisitos

- Windows com PowerShell e Docker Desktop iniciado, em modo **Linux containers**;
- Terraform `>= 1.5.0`;
- Docker CLI, Kind e `kubectl` no `PATH`;
- acesso à internet para baixar o Metrics Server na primeira instalação;
- checkout do repositório da aplicação com seus manifests e fontes.

No Windows, instale Kind com WinGet, se necessário:

```powershell
winget install Kubernetes.kind
```

Confirme as ferramentas e o contexto Docker:

```powershell
docker context show
kind version
kubectl version --client
terraform version
```

O contexto Docker normalmente deve ser `desktop-linux`.

## Preparar os três repositórios

Por padrão, os três checkouts ficam lado a lado:

```text
Projetos/
├── oficina-k8s-infra/
├── oficina-db/
└── soat-fase1-tech-challenge/
```

Se os repositórios estiverem em outros caminhos, passe o caminho absoluto da aplicação com `application_path`. Exemplo no PowerShell:

```powershell
$AppPath = 'C:/caminho/soat-fase1-tech-challenge'
terraform -chdir=infra plan -var="application_path=$AppPath"
```

A pasta da aplicação deve conter `Dockerfile`, `pom.xml`, `src/`, `kustomization.yaml`, `scripts/install-metrics-server.ps1` e `k8s/`. O checkout de `oficina-db` deve conter seu diretório `terraform/`, `kustomization.yaml`, `schema.sql` e `k8s/`.

## Provisionar o ambiente

Execute os comandos na raiz deste repositório. A sequência prepara o cluster, aplica o banco pelo Terraform próprio e só depois implanta a aplicação:

```powershell
terraform -chdir=infra init
terraform -chdir=infra validate
terraform -chdir=infra plan
terraform -chdir=infra apply -target=kind_cluster.oficina -target=terraform_data.install_metrics_server
terraform -chdir=../oficina-db/terraform init
terraform -chdir=../oficina-db/terraform apply -var="cluster_context=kind-oficina-local"
terraform -chdir=infra apply
```

Se já existir estado local criado antes da configuração do backend local, migre-o uma vez com `terraform -chdir=infra init -migrate-state`.

Se os repositórios não estiverem lado a lado, acrescente `-var="application_path=C:/caminho/soat-fase1-tech-challenge"` aos comandos do Terraform de infraestrutura. No Terraform do banco, ajuste `-chdir` para a pasta `terraform` do checkout `oficina-db`.

Durante a aplicação, o Terraform:

1. cria o cluster Kind `oficina-local`;
2. instala o Metrics Server e aguarda as métricas dos nós;
3. executa o Terraform de `oficina-db`, que aplica seus manifests e aguarda o MySQL;
4. constrói e carrega a imagem da API no cluster;
5. aplica o Kustomize da aplicação;
6. aguarda os deployments da API e do MailHog ficarem prontos.

### Recursos implantados

| Recurso | Configuração | Acesso |
|---|---|---|
| API da Oficina | Deployment com 3 réplicas iniciais; container na porta 8081 | `http://localhost:8081` |
| HPA da API | mínimo 3 e máximo 10 réplicas; CPU 70%, memória 80% | `kubectl get hpa` |
| MySQL | MySQL 8, PVC de 2 GiB, schema inicial do projeto | Interno: `oficina-db-svc:3306` |
| MailHog | SMTP 1025 e interface web 8025 | `http://localhost:8025` |
| Metrics Server | métricas usadas pelo HPA | `kubectl top nodes` |

As portas do host são encaminhadas para os NodePorts do cluster: host `8081` para `30081` (API) e host `8025` para `30025` (MailHog).

## Verificar o ambiente

```powershell
kubectl --context kind-oficina-local get nodes
kubectl --context kind-oficina-local get deployments,services,pods
kubectl --context kind-oficina-local get hpa oficina-api
kubectl --context kind-oficina-local top nodes
kubectl --context kind-oficina-local top pods -l app=oficina-api
```

- API e Swagger: [http://localhost:8081/swagger-ui.html](http://localhost:8081/swagger-ui.html)
- MailHog: [http://localhost:8025](http://localhost:8025)

As métricas podem levar alguns minutos para aparecer depois da instalação. O HPA só consegue calcular a escala quando o Metrics Server fornece as métricas.

## Atualizar e reaplicar

O Terraform calcula fingerprints dos fontes da aplicação e dos manifests. Quando esses arquivos mudam, uma nova aplicação de `terraform apply` reconstrói a imagem e/ou reaplica os recursos afetados.

Para reaplicar os recursos manualmente depois de provisionar o cluster, aplique primeiro o Terraform do banco e depois o Terraform da aplicação:

```powershell
terraform -chdir=../oficina-db/terraform init
terraform -chdir=../oficina-db/terraform apply -var="cluster_context=kind-oficina-local"
terraform -chdir=infra apply
```

## Destruir o ambiente

Na raiz deste repositório:

```powershell
terraform -chdir=infra destroy
```

A confirmação do Terraform é solicitada antes da remoção. Isso exclui o cluster Kind e os recursos/dados que estavam armazenados nele.

## Estado e segurança

O estado local de execução manual fica em `infra/terraform.tfstate`. O deploy do GitHub Actions grava estados separados e persistentes fora do checkout do repositório, em `%USERPROFILE%\.terraform-state\oficina-k8s-infra\homolog.tfstate` e `production.tfstate`. O `.gitignore` exclui estado, backups, cache `.terraform/`, planos e arquivos `.tfvars`. Não remova essas proteções nem versione estado, credenciais ou configurações da máquina. O arquivo `.terraform.lock.hcl` deve ser mantido para fixar o provider.

Os manifests atuais da aplicação incluem credenciais destinadas somente ao ambiente local. Não reutilize esses valores em ambientes compartilhados ou produção; use um gerenciador de segredos e configure credenciais fora do Git.

## CI/CD e deploy automático local

O workflow `.github/workflows/main.yml` valida o Terraform em Pull Requests e gera um `plan` sem aplicar mudanças. Em pushes para `homolog` ou `main`, prepara o cluster, executa o Terraform do banco e depois implanta a aplicação num runner Windows self-hosted conectado à máquina local:

| Branch | Ambiente local | Cluster Kind | API | MailHog |
|---|---|---|---|---|
| `homolog` | Homologação | `oficina-homolog` | `http://localhost:8082` | `http://localhost:8026` |
| `main` | Produção local | `oficina-prod` | `http://localhost:8081` | `http://localhost:8025` |

O repositório da aplicação continua responsável pelos testes Maven e SonarCloud. Em PRs, ele aplica os manifests do banco diretamente no Kind temporário e depois valida a API. Após testes e Sonar aprovados num push para `homolog` ou `main`, dispara este workflow; este prepara o cluster, executa o Terraform de `oficina-db` e então aplica a aplicação no cluster persistente. Mudanças Terraform e da aplicação nas branches também disparam o deploy.

### Preparar o deploy local

1. Crie as branches `homolog` e `main` nos três repositórios. Cada ambiente usa a branch correspondente do banco.
2. Registre um runner self-hosted Windows no repositório `oficina-k8s-infra` com o rótulo adicional `oficina-local`. Ele deve usar a mesma conta Windows que tem acesso ao Docker Desktop.
3. Mantenha Docker Desktop em execução e instale Terraform, Kind, `kubectl` e PowerShell nessa máquina.
4. Se os repositórios da aplicação ou do banco forem privados, configure `APP_REPOSITORY_READ_TOKEN` e `DB_REPOSITORY_READ_TOKEN` nos secrets do repositório de infraestrutura, com leitura de conteúdo.
5. Configure `INFRA_DEPLOY_TOKEN` nos secrets do repositório da aplicação. Use um fine-grained token limitado a `oficina-k8s-infra` com permissão **Actions: write**, para disparar o workflow de deploy.
6. Ative proteção de branch e PRs nas configurações do GitHub. `main` deve exigir PR; não permita commits diretos.

O deploy manual via `workflow_dispatch` também está disponível. Escolha o ambiente e rode o workflow na branch correspondente (`homolog` para homologação local ou `main` para produção local).

> **Limite do ambiente:** “produção” aqui é apenas um segundo cluster Kind na máquina local. Ele não oferece alta disponibilidade real, acesso público ou continuidade quando a máquina está desligada. Isso ainda não satisfaz o requisito de produção em nuvem do Tech Challenge.
