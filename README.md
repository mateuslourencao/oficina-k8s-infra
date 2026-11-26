# Oficina Kubernetes Infrastructure

Infraestrutura como código do ambiente Kubernetes local da Oficina, provisionado com Terraform e Kind. Este repositório separa o ciclo de vida do cluster dos fontes da API, que continuam no repositório [soat-fase1-tech-challenge](https://github.com/mateuslourencao/soat-fase1-tech-challenge).

> **Escopo atual:** ambiente local de desenvolvimento e validação. O provider `tehcyx/kind` cria um cluster Kind no Docker; este projeto ainda não provisiona Kubernetes gerenciado em nuvem, API Gateway, banco gerenciado ou deploy contínuo em produção.

## Arquitetura

O Terraform cria o cluster `oficina-local`, mapeia as portas de acesso, constrói e carrega a imagem da aplicação, instala o Metrics Server e aplica os recursos Kubernetes com Kustomize. O HPA usa métricas de CPU e memória para escalar a API. O Metrics Server configura `--kubelet-insecure-tls`, necessário para o certificado do kubelet no Kind.

Os manifests, o `kustomization.yaml`, o `schema.sql`, o Dockerfile e o código-fonte da API são mantidos no repositório da aplicação. O Terraform usa esses arquivos para construir e implantar a versão local da API.

## Estrutura do repositório

```text
.
├── .gitignore
├── README.md
└── infra/
  ├── .terraform.lock.hcl
  ├── main.tf
  ├── outputs.tf
  ├── variables.tf
  └── versions.tf
```

- `main.tf`: define o cluster Kind, a construção/carregamento da imagem, a instalação do Metrics Server e a aplicação dos manifests.
- `variables.tf`: configura o nome do cluster e o caminho do checkout da aplicação.
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

## Preparar os dois repositórios

Por padrão, espera-se que ambos estejam lado a lado:

```text
Projetos/
├── oficina-k8s-infra/
└── soat-fase1-tech-challenge/
```

Se o repositório da aplicação estiver em outro caminho, passe seu caminho absoluto na variável `application_path` em todos os comandos Terraform abaixo. Exemplo no PowerShell:

```powershell
$AppPath = 'C:/caminho/soat-fase1-tech-challenge'
terraform -chdir=infra plan -var="application_path=$AppPath"
```

A pasta da aplicação deve conter `Dockerfile`, `pom.xml`, `src/`, `kustomization.yaml`, `schema.sql`, `scripts/install-metrics-server.ps1` e `k8s/`.

## Provisionar o ambiente

Execute os comandos na raiz deste repositório. O `apply` mostra o plano e solicita confirmação antes de criar ou alterar recursos.

```powershell
terraform -chdir=infra init
terraform -chdir=infra validate
terraform -chdir=infra plan
terraform -chdir=infra apply
```

Se os repositórios não estiverem lado a lado, acrescente `-var="application_path=C:/caminho/soat-fase1-tech-challenge"` a `plan` e `apply`.

Durante a aplicação, o Terraform:

1. cria o cluster Kind `oficina-local`;
2. constrói a imagem `soat-fase1-tech-challenge-app:dev` com o Docker e carrega-a no cluster;
3. instala o Metrics Server e aguarda as métricas dos nós;
4. aplica o Kustomize da aplicação;
5. aguarda os deployments do MySQL, da API e do MailHog ficarem prontos.

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

Para reaplicar os manifests manualmente depois de provisionar o cluster, no PowerShell:

```powershell
$AppPath = '../soat-fase1-tech-challenge'
kubectl --context kind-oficina-local apply -k $AppPath
kubectl --context kind-oficina-local rollout status deployment/oficina-db --timeout=180s
kubectl --context kind-oficina-local rollout status deployment/oficina-api --timeout=240s
kubectl --context kind-oficina-local rollout status deployment/mailhog --timeout=120s
```

## Destruir o ambiente

Na raiz deste repositório:

```powershell
terraform -chdir=infra destroy
```

A confirmação do Terraform é solicitada antes da remoção. Isso exclui o cluster Kind e os recursos/dados que estavam armazenados nele.

## Estado e segurança

O backend remoto do Terraform ainda não está configurado; o estado fica local em `infra/terraform.tfstate`. O `.gitignore` exclui o estado e seus backups, cache `.terraform/`, planos e arquivos `.tfvars`. Não remova essas proteções nem versione estado, credenciais ou configurações da máquina. O arquivo `.terraform.lock.hcl` deve ser mantido para fixar o provider.

Os manifests atuais da aplicação incluem credenciais destinadas somente ao ambiente local. Não reutilize esses valores em ambientes compartilhados ou produção; use um gerenciador de segredos e configure credenciais fora do Git.

## CI/CD e próximos passos

O workflow `.github/workflows/main.yml` deste repositório roda em Pull Requests, em pushes para `commit-inicial`, `main` ou `master` quando há mudanças em `infra/`, e também pode ser iniciado manualmente. Ele verifica a formatação, inicializa os providers sem backend remoto, valida a configuração e gera um `terraform plan`. O plano é somente uma verificação: não executa `apply` nem cria um cluster.

Como o plano calcula fingerprints dos fontes e manifests da aplicação, o workflow também faz checkout de `soat-fase1-tech-challenge` na branch `main`. Se esse repositório for privado, configure o secret `APP_REPOSITORY_READ_TOKEN` neste repositório com permissão de leitura de conteúdo no repositório da aplicação. Para um repositório público, o token padrão do workflow pode ser suficiente.

O workflow no repositório da aplicação permanece responsável pelos testes Maven, análise SonarCloud, build da imagem e implantação de validação em um cluster Kind temporário. Ele não publica uma imagem nem faz deploy contínuo em ambiente persistente.

O `apply` automatizado ainda não foi habilitado: a infraestrutura provisiona Kind local e seus provisioners usam PowerShell. Para o desenho corporativo do Tech Challenge ainda serão necessários um provider de nuvem, backend remoto, estratégia de deploy, proteção de branches e regras de aprovação para produção.
