# GithubActionsIaC — Laboratorio de CI/CD con GitHub Actions y OIDC

Despliegue de infraestructura en AWS con Terraform desde **GitHub Actions**, usando
**OpenID Connect (OIDC)** para obtener credenciales temporales. No se guarda ningún
`AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY` en GitHub.

## Arquitectura

```
GitHub Actions (rama development)
        │  id-token: write  →  token OIDC
        ▼
AWS IAM ── AssumeRoleWithWebIdentity ──► rol lab09-github-actions-dev
        │                                   (subject limitado a environment:dev)
        ▼
Terraform (backend S3 remoto, key lab09/dev/terraform.tfstate)
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ Cognito User Pool  ──► emite JWT                        │
│         │                                               │
│         ▼                                               │
│ API Gateway HTTP API ─ JWT authorizer                   │
│         │          └─► GET /hello  (requiere token)     │
│         │          └─► GET /health (publica)            │
│         ▼                                               │
│ Lambda (nodejs20.x) ──► CloudWatch Logs                 │
└─────────────────────────────────────────────────────────┘
```

## Estructura del repositorio

```
.
├── .github/workflows/
│   ├── deploy.yml      # push a development -> plan + apply (environment dev)
│   ├── destroy.yml     # manual, requiere escribir DESTROY
│   └── validate.yml    # pull requests: fmt + validate SIN credenciales AWS
├── bootstrap/          # se ejecuta UNA vez con un usuario administrador
│   ├── main.tf         # bucket de estado + proveedor OIDC + politica + rol
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── terraform/          # el stack del laboratorio
│   ├── backend.hcl.example
│   ├── versions.tf / providers.tf / variables.tf / locals.tf
│   ├── cognito.tf / lambda.tf / apigateway.tf / observability.tf
│   ├── outputs.tf
│   └── src/index.mjs
└── scripts/
    └── get-oidc-ids.ps1   # obtiene OWNER_ID y REPO_ID de GitHub
```

---

## Prerrequisitos

| Herramienta | Uso |
|---|---|
| Terraform >= 1.10 | `use_lockfile` del backend S3 requiere 1.10 o superior |
| AWS CLI v2 | Verificar recursos y ejecutar el bootstrap |
| Un usuario IAM administrador **con MFA** | Solo para el bootstrap |

> ⚠️ El usuario **root** se usa únicamente para tareas de cuenta (activar MFA,
> revisar facturación). **No se usan access keys de root** ni se despliega con él.

---

## Paso 1 — Preparar la cuenta de AWS

1. Activar MFA en el usuario root y **no** crear access keys para root.
2. Crear o usar un usuario administrador con MFA para el despliegue.
3. Elegir la región **us-east-2** y usarla para todos los recursos.
4. Configurar una **alerta de presupuesto** (AWS Budgets) para recibir avisos de costo.

   ```bash
   # Ejemplo: presupuesto de 5 USD con alerta al 80 %
   aws budgets create-budget --account-id <ACCOUNT_ID> \
     --budget '{"BudgetName":"lab09","BudgetLimit":{"Amount":"5","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
     --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"tu-correo@ejemplo.com"}]}]'
   ```

5. Verificar la identidad con la que se trabajará:

   ```bash
   aws sts get-caller-identity
   ```

---

## Paso 2 — Bootstrap: bucket de estado, proveedor OIDC y rol

El bootstrap crea los tres elementos que Terraform **no puede crear sin credenciales
previas**. Se ejecuta una sola vez, con el usuario administrador y estado local.

### 2.1 Obtener los IDs del repositorio

El subject OIDC con IDs inmutables (formato que GitHub usa para repositorios
creados desde julio de 2026) necesita `OWNER_ID` y `REPO_ID`:

```powershell
pwsh ./scripts/get-oidc-ids.ps1 -Owner henryflores04 -Repo GithubActionsIaC
```

Salida esperada:

```
OWNER_ID    : 12345678
REPO_ID     : 987654321

Subject OIDC (IDs inmutables):
  repo:henryflores04@12345678/GithubActionsIaC@987654321:environment:dev
```

> Si el repositorio todavía emite el subject heredado (`repo:OWNER/REPO:...`),
> pon `use_immutable_subject = false` en `terraform.tfvars`.

### 2.2 Configurar y aplicar

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars con state_bucket_name, github_owner_id y github_repo_id

terraform init
terraform plan
terraform apply
```

Salida relevante:

```
deploy_role_arn  = "arn:aws:iam::<ACCOUNT_ID>:role/lab09-github-actions-dev"
oidc_subject     = "repo:henryflores04@.../GithubActionsIaC@...:environment:dev"
state_bucket_name = "lab09-tfstate-..."
```

**Guarda estos tres valores**, se usan como variables en GitHub.

> ⚠️ El bootstrap mantiene su estado en local (`bootstrap/terraform.tfstate`).
> Está excluido por `.gitignore`. **No lo borres** mientras el laboratorio exista,
> o Terraform perderá el control del rol y del proveedor OIDC.

---

## Paso 3 — Configurar el repositorio de GitHub

### 3.1 Crear el entorno `dev`

**Settings → Environments → New environment** → nombre `dev`.

- **Deployment branches:** *Selected branches* → agregar `development`.
- Deshabilitar el despliegue desde pull requests de forks.
- Opcional: *Required reviewers* si el plan lo permite.

> El entorno debe llamarse exactamente `dev` porque el subject del rol OIDC
> termina en `:environment:dev`.

### 3.2 Cargar las variables

**Settings → Secrets and variables → Actions → Variables** (o en las variables del
entorno `dev`):

| Nombre | Valor |
|---|---|
| `AWS_REGION` | `us-east-2` |
| `AWS_ROLE_ARN` | ARN del rol `lab09-github-actions-dev` |
| `TF_STATE_BUCKET` | Nombre del bucket de estado |

**Son variables, no secretos.** El ARN del rol no es una credencial: quien lo
conoce no puede asumirlo sin un token OIDC del repositorio y entorno correctos.

### 3.3 Crear la rama de despliegue

`deploy.yml` solo se dispara con `push` sobre `development`:

```bash
git checkout -b development
git push -u origin development
```

---

## Paso 4 — Desplegar

El primer `push` a `development` dispara el workflow **Deploy (dev)**, que:

1. Asume el rol mediante OIDC.
2. Ejecuta `terraform fmt -check`, `init`, `validate`, `plan` y `apply`.
3. Publica la URL de la API en el *Step Summary* del run.

También se puede lanzar manualmente desde **Actions → Deploy (dev) → Run workflow**.

### Probar la API sin token (debe fallar con 401)

```bash
curl -i "$(terraform -chdir=terraform output -raw api_hello_url)"
```

Respuesta esperada: `HTTP/2 401` con `www-authenticate: Bearer`.

### Probar la ruta pública

```bash
curl -s "$(terraform -chdir=terraform output -raw api_health_url)" | jq
```

### Probar la ruta protegida con un token de Cognito

```bash
POOL_ID=$(terraform -chdir=terraform output -raw cognito_user_pool_id)
CLIENT_ID=$(terraform -chdir=terraform output -raw cognito_client_id)

# 1. Crear un usuario de prueba (una sola vez)
aws cognito-idp sign-up \
  --client-id "$CLIENT_ID" \
  --username alumno@ejemplo.com \
  --password 'Lab09!Password#2026'

# 2. Confirmarlo (en un User Pool real se haría con el código enviado por correo)
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id "$POOL_ID" \
  --username alumno@ejemplo.com

# 3. Obtener el access token
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id "$CLIENT_ID" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=alumno@ejemplo.com,PASSWORD='Lab09!Password#2026' \
  --query 'AuthenticationResult.AccessToken' --output text)

# 4. Invocar la ruta protegida
curl -s -H "Authorization: Bearer $TOKEN" \
  "$(terraform -chdir=terraform output -raw api_hello_url)" | jq
```

> El flujo `USER_PASSWORD_AUTH` no está habilitado en el cliente por defecto
> (`ALLOW_USER_SRP_AUTH` es el flujo de las aplicaciones reales). Para pruebas por
> CLI, habilítalo temporalmente en `cognito.tf` añadiendo `"ALLOW_USER_PASSWORD_AUTH"`
> a `explicit_auth_flows`, o usa `admin-initiate-auth` con `ADMIN_USER_PASSWORD_AUTH`.

---

## Paso 5 — Destruir

**Actions → Destroy (dev) → Run workflow**, escribir `DESTROY` y ejecutar.

El workflow ejecuta `terraform destroy` y publica en el resumen una verificación de
que no quedan recursos del laboratorio.

> **Alternativa local:** `terraform -chdir=terraform destroy`.
>
> **Recordatorio de costo:** Lambda y API Gateway pueden generar cargos menores.
> Destruir el entorno al terminar el laboratorio.

---

## Uso local (opcional)

```bash
cd terraform
cp backend.hcl.example backend.hcl
# editar backend.hcl con el bucket y la region reales

terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

`backend.hcl` **no se versiona**: está en `.gitignore`. La autenticación local usa el
perfil de AWS CLI (`AWS_PROFILE`), nunca claves escritas en el repositorio.

---

## Decisiones de diseño

### OIDC en lugar de access keys

GitHub firma un token OIDC por ejecución y AWS lo intercambia por credenciales
temporales. Ventajas frente a guardar claves en *secrets*: no hay credenciales de
larga duración que rotar, y el rol solo es asumible desde el repositorio y el
entorno exactos.

### Política administrada por el cliente, no `AdministratorAccess`

`bootstrap/main.tf` define una política con permisos acotados a Cognito, API Gateway,
Lambda, CloudWatch Logs, los roles de ejecución de Lambda y el backend de estado:

- `s3:ListBucket` limitado al prefijo `lab09/dev/` mediante condición `s3:prefix`.
- Operaciones de objeto limitadas al `tfstate`, su `.tflock` y el `.backup`.
- `iam:PassRole` solo sobre el rol de ejecución de Lambda y solo hacia
  `lambda.amazonaws.com`.
- Recursos de Lambda y de logs restringidos por el prefijo `lab09-dev-`.

### Sin comodines en el subject

`token.actions.githubusercontent.com:sub` se compara con `StringEquals` contra un
único valor. Un comodín permitiría que cualquier rama, PR o fork del repositorio
asumiera el rol de despliegue.

### Validación de PR sin credenciales

`validate.yml` no declara `id-token: write` ni configura credenciales de AWS. Solo
ejecuta `terraform fmt` y `validate` con `init -backend=false`, por lo que no puede
tocar el estado remoto ni asumir el rol.

### Bloqueo de estado sin DynamoDB

`use_lockfile = true` usa el bloqueo nativo de S3 (Terraform >= 1.10) y evita tener
que crear y mantener una tabla DynamoDB solo para el lockfile.

---

## Solución de problemas

### `Not authorized to perform sts:AssumeRoleWithWebIdentity`

El subject del token no coincide con el de la política de confianza.

```bash
# Ver el subject real que emite GitHub en ese run
# (agregar temporalmente al workflow):
#   - run: echo "${{ github.event_name }} / ${{ github.ref }} / ${{ github.environment }}"
```

Comprobar el valor exacto configurado:

```bash
aws iam get-role --role-name lab09-github-actions-dev \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

Causas habituales: el job no declara `environment: dev`, el repositorio no emite
IDs inmutables y la política usa el formato nuevo (o al revés), o el nombre del
entorno en GitHub no es exactamente `dev`.

### `AccessDenied` durante `terraform apply`

La política del rol es de mínimo privilegio y puede quedarse corta al añadir
recursos nuevos. El mensaje de error indica la acción exacta que falta; añadirla en
`bootstrap/main.tf` y volver a aplicar el bootstrap.

### `Error acquiring the state lock`

Otro run quedó a medias. Si no hay ningún workflow en ejecución:

```bash
aws s3 rm "s3://$TF_STATE_BUCKET/lab09/dev/terraform.tfstate.tflock"
```

### `BucketAlreadyExists` en el bootstrap

Los nombres de bucket S3 son únicos a nivel global. Cambiar `state_bucket_name` por
uno que incluya, por ejemplo, el ID de cuenta.

### El stage de API Gateway falla por permisos de logs

La política de recurso de CloudWatch Logs (`observability.tf`) debe existir antes de
crear el stage. Terraform resuelve la dependencia por referencia, pero si el rol de
despliegue no tiene `logs:PutResourcePolicy` el error aparece como
`CloudWatch Logs role ARN must be set in account settings`.

---

## Evidencia para el informe

El entregable es un **PDF con una captura por cada punto**:

| # | Evidencia |
|---|---|
| 1 | `aws sts get-caller-identity` con la cuenta del laboratorio |
| 2 | Bucket de estado con *Block public access*, cifrado y versionado activos |
| 3 | Proveedor OIDC `token.actions.githubusercontent.com` con audience `sts.amazonaws.com` |
| 4 | Política de confianza del rol con el `sub` exacto y `StringEquals` |
| 5 | Política de permisos del rol (sin `AdministratorAllowed` ni `*` en acciones) |
| 6 | Entorno `dev` en GitHub con la rama `development` permitida |
| 7 | Variables `AWS_REGION`, `AWS_ROLE_ARN` y `TF_STATE_BUCKET` |
| 8 | Workflow **Deploy** en verde (**ejecución del action**) |
| 9 | `terraform apply` con el resumen de recursos creados |
| 10 | `401` en `GET /hello` sin token |
| 11 | `200` en `GET /hello` con token de Cognito |
| 12 | Workflow **Destroy** en verde |
| 13 | Verificación de que no quedan recursos del laboratorio |
| 14 | URL del repositorio: `https://github.com/henryflores04/GithubActionsIaC` |
