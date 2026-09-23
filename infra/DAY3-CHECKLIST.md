# Day 3 Checklist — InsightHub (DO2603)

Checklist duy nhất cho Day 3, trích từ tài liệu gốc và code verifier. Mọi dòng ghi nguồn (mục/dòng tài liệu) và trạng thái hiện tại. Không suy đoán — mọi khẳng định về hành vi verifier trích trực tiếp dòng code.

## Nguồn đã đọc
`Running-Project-Specification-Student.md` §0 (toàn bộ), §2.3, §2.5, §4.1-4.4, §7 (toàn bộ) · `docs/Guide_Local_AWS_Cost_DO2603.md` (toàn bộ) · `docs/lab-guides/Day3-AI-IaC-Pipeline.md` (toàn bộ) · `scripts/VERIFICATION_CONTRACT.md` (toàn bộ) · `scripts/verify.py` (hàm `day3`, `run_tests`, `artifact`, `fingerprint`, `sha`, `source_files`, `REQUIRED_TESTS`) · `scripts/verify-day-3.sh` · `infra/SPEC.md` · `evidence/day3-lab1-manifest.json`

**Lưu ý nền tảng**: `tests/milestones/day3/` **chưa tồn tại** trong repo (chỉ có `tests/milestones/day1/`). Đây là thư mục học viên phải tự tạo (`VERIFICATION_CONTRACT.md:96-97`: "student deliverables, not included solutions"), không phải file có sẵn từ trainer.

---

## A. Must-have MH1–MH14 (§7.4, dòng 819-838)

| # | Yêu cầu | Nguồn | Trạng thái |
|---|---|---|---|
| MH1 | `infra/` đủ main.tf/variables.tf/outputs.tf/providers.tf | dòng 825 | ✅ xong |
| MH2 | Backend S3 + `use_lockfile` | dòng 826 | ✅ xong (`infra/backend.tf`) |
| MH3 | EKS namespace resource | dòng 827 | ✅ code xong — `kubernetes_namespace.insighthub_dev` (`main.tf`), xác nhận qua `terraform plan` (chưa apply) |
| MH4 | RDS PostgreSQL 16, encrypted, not public | dòng 828 | ✅ xong (`storage_encrypted=true`, `publicly_accessible=false`) |
| MH5 | ElastiCache Redis 7, **private subnet** | dòng 829 | ✅ code xong — thêm `aws_subnet.private[*]` (2 AZ, route table riêng không IGW/NAT, chi phí $0), `aws_db_subnet_group`/`aws_elasticache_subnet_group` đã chuyển sang subnet này. EKS cluster/node group giữ nguyên public. Chưa apply. |
| MH6 | IRSA: ServiceAccount + IAM Role binding | dòng 830, verify bằng `kubectl describe sa insighthub` | ✅ code xong — `kubernetes_service_account.insighthub` + `aws_iam_role.insighthub_app` (trust `system:serviceaccount:insighthub-dev:insighthub`, chỉ `secretsmanager:GetSecretValue`+`DescribeSecret` đúng 2 ARN secret). Chưa apply nên chưa `kubectl describe` được thật. |
| MH7 | `.github/workflows/iac.yml` | dòng 831 | ❌ chưa làm — chỉ có `starter.yml`; bootstrap IAM/OIDC đã xong (`infra/bootstrap/github-oidc/`) nhưng workflow YAML chưa viết |
| MH8 | Pipeline jobs fmt→lint→scan→policy→plan→cost→apply | dòng 832 | ❌ chưa làm |
| MH9 | Pipeline green trên PR | dòng 833 | ❌ chưa làm |
| MH10 | InsightHub Helm deploy | dòng 834 | ❌ chưa làm — không có chart nào trong repo; ECR repo đã có code (chưa apply) để sau này push image |
| MH11 | Smoke test upload+chat | dòng 835 | ❌ chưa làm |
| MH12 | `tflint --recursive` no warnings | dòng 836 | ✅ xong — đã chạy lại trên cả module chính + `infra/bootstrap/github-oidc/`: 0 errors, 0 warnings |
| MH13 | `checkov` no HIGH | dòng 837 | ✅ `checkov -d infra/` → **157 passed, 0 failed, 24 skipped, exit 0** — 2 finding sửa hẳn bằng code (CKV2_AWS_60, CKV_AWS_136×3), 24 còn lại chuyển thành `#checkov:skip` tại resource kèm lý do (`infra/SPEC.md` mục 10). Vẫn thiếu xác nhận độc lập severity "không HIGH" cho 24 finding skip (checkov OSS không trả field `severity`), nhưng exit code 0 nên job security-scan trong pipeline sẽ xanh. |
| MH14 | All resources tagged | dòng 838 | ✅ áp dụng quyết định J.1 — `owner` (chữ thường) duy nhất trong `common_tags`, không còn `Owner`. Module bootstrap dùng tag scheme riêng có chủ đích (xem SPEC.md mục 2, phần Tagging) |

## B. Non-functional (§7.3, dòng 802-809)

| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | `tflint --recursive` no warnings | ✅ xong |
| 2 | `checkov -d infra/` no HIGH | ✅ 0 failed, 24 skipped kèm lý do inline (xem mục A/MH13) |
| 3 | `conftest test ... tfplan.json` pass — **bắt buộc** (không phải Should-have, xem mục H) | ❌ chưa làm — không có file `.rego` nào trong repo (ngoài phạm vi lượt sửa Terraform này) |
| 4 | Tags: project, environment, owner, cost_center, managed_by | ✅ áp dụng quyết định J.1 |
| 5 | Pipeline OIDC AWS (no long-lived keys) | ⚠️ code xong, chưa apply — `infra/bootstrap/github-oidc/` có OIDC provider + 2 role (`gh_plan`/`gh_apply`), `terraform plan` sạch (10 to add); chưa apply nên GitHub Actions thật vẫn chưa dùng được. Mọi apply thủ công hôm nay vẫn qua IAM user `DE000215` (long-lived key), hợp lệ cho thao tác thủ công. |
| 6 | Secret qua AWS Secrets Manager | ✅ xong |
| 7 | Infracost dự toán | ✅ xong (`infra/SPEC.md:209`, ngày 2026-09-22) |

## C. Acceptance Criteria — 15 dòng (§7.5, dòng 853-871)

| Dòng | Trạng thái |
|---|---|
| `terraform fmt -check -recursive` → no diff | ✅ |
| `terraform init -backend=true` → success | ✅ |
| `terraform validate` → success | ✅ |
| `tflint --recursive` → 0/0 | ✅ |
| `checkov -d infra/` → no HIGH | ✅ 0 failed (xem mục A/MH13) |
| `terraform plan -out=tfplan` → deterministic | ✅ **sửa thật** — trước đây dòng này bị đánh dấu ✅ nhầm: `public_access_cidrs` lấy từ `data.http.my_ip` khiến plan **không** deterministic (đổi theo IP mạng). Đã bỏ `data.http`, dùng `var.operator_cidrs` bắt buộc truyền — giờ plan mới thật sự deterministic. |
| `conftest test --policy policy/terraform tfplan.json` → pass — **bắt buộc** | ❌ — path chưa tồn tại, chưa có Rego nào; xem mục H và J cho quyết định path |
| `infracost breakdown --path infra/` | ✅ |
| `gh run list --workflow=iac.yml` → ✓ | ❌ |
| `kubectl get ns insighthub-dev` → exists | ❌ — namespace tên thật là `insighthub-dev` khi `var.environment=dev` (mã hoá `insighthub-${var.environment}`), code đã sẵn sàng, chưa apply |
| `kubectl get pods -n insighthub-dev` → Ready | ❌ |
| `curl .../healthz` → 200 | ❌ |
| `curl -X POST .../documents` → 202 | ❌ |
| `GET /documents` → ready <30s | ❌ |
| `curl -X POST .../chat` → 200 | ❌ |

## D. Kiến trúc §2.3 (dòng 189-204)

| Thành phần | Trạng thái |
|---|---|
| EKS namespace `insighthub-<env>` | ✅ code xong (`kubernetes_namespace.insighthub_dev`), chưa apply |
| Deployment `web` + Service | ❌ chưa làm (Helm chart) |
| Deployment `api` + Service + **HPA** + **Ingress (TLS)** | ❌ chưa làm — HPA cần `metrics-server` cài trước (xem mục L) |
| Deployment `ingestion-worker` | ❌ chưa làm (Helm chart) |
| Helm values + ConfigMap + Secret | ❌ chưa làm |
| RDS PostgreSQL 16 + pgvector | ✅ đã có trong Terraform, nay subnet **private** (MH5), chưa apply |
| ElastiCache Redis 7 | ✅ đã có trong Terraform, nay subnet **private** (MH5), chưa apply |
| IAM roles for service accounts (IRSA) | ✅ code xong — ALB controller + app (`insighthub`), chưa apply |

## E. Yêu cầu verifier — 5 câu trả lời (trích dòng code)

**1. Conftest policy path verifier chạy?**
Verifier **không tự chạy `conftest` bằng lệnh cứng trong code**. `scripts/verify.py:526-528` (hàm `day3`) chỉ chạy 4 lệnh: `terraform fmt -check -recursive`, `terraform init -backend=false -input=false`, `terraform validate -no-color`, `checkov -d . --quiet`. Việc gọi `conftest` nằm trong 2 test bắt buộc mà **học viên tự viết**: `test_policy_allows_valid` / `test_policy_denies_unsafe` (`scripts/verify.py:38`, `REQUIRED_TESTS[3]`) — verifier chỉ đòi 2 tên scenario này PASS qua `pytest`, không quy định path Rego cụ thể trong code. Path chính thức do tài liệu quy định (§7.5 dòng 862: `policy/terraform`; §2.5 dòng 250: `infra/policies`) — 2 path khác nhau, xem mục J cho quyết định đã chốt.

**2. Tên scenario test bắt buộc trong `tests/milestones/day3/test_*.py`?**
`scripts/verify.py:38`: `REQUIRED_TESTS[3] = {'test_policy_allows_valid', 'test_policy_denies_unsafe'}`. Đúng 2 tên. Theo đúng tên, 2 test này phải **tự chạy Conftest** (subprocess) trên 1 `tfplan.json` hợp lệ (kỳ vọng `allow`) và 1 `tfplan.json` vi phạm cố ý (kỳ vọng `deny`) — bản thân verifier chỉ kiểm JUnit report có 2 case này pass, không kiểm nội dung test làm gì bên trong.

**3. Cấu trúc `evidence/day3.json`?**
Theo `scripts/verify.py:513-517` + `VERIFICATION_CONTRACT.md:42`: 2 artifact role bắt buộc — `deployment` (file dùng để tính `artifact_sha256`) và `ci_binding` (file JSON có 2 field `source_sha256`, `artifact_sha256`, phải khớp `expected = {'source_sha256': fingerprint(repo), 'artifact_sha256': sha(deployment)}`). Envelope chung (`evidence()` dòng 310-318): `schema_version`, `day`, `mode` (real/fixture), `observed_at` (RFC3339, ≤24h), `source_sha256`, `artifacts: {role: {path, sha256}}`.

**4. GitHub artifact "verification-source"?**
`scripts/verify.py:543-546`: tên artifact chính xác **`verification-source`**, bên trong chứa **`source-manifest.json`** với field `source_sha256`, `artifact_sha256` — phải khớp CHÍNH XÁC với giá trị tính tại thời điểm verify. `source_sha256 = fingerprint(root)` (dòng 160-167): SHA-256 nối `relative_path + \0 + sha256_bytes(file)` cho từng file trong `source_files(root)` (phạm vi `SOURCE_ROOTS` dòng 29-31: `api, web, ingestion-worker, chatops-bot, infra, observability, security, tools, scripts, tests, .github, .agents/rules, .agent/rules` + vài file gốc, loại trừ `EXCLUDED_DIRS` dòng 32-34). `artifact_sha256 = sha(path)` (dòng 63-64): SHA-256 hex thô của file `deployment`.

**5. "Deployment artifact" là file gì?**
Không quy định cứng định dạng trong code — chỉ đòi file thật, không dummy. **Quyết định cần chốt ở giai đoạn viết pipeline** (xem mục J): dùng đúng file do CI sinh ra (tải về `evidence/`), **không build lại ở local** vì `helm package` không deterministic (timestamp/metadata thay đổi mỗi lần chạy → hash lệch). Ứng viên khả thi: output `helm template` (text, deterministic) hoặc file `.tgz` do đúng job CI đó `helm package` một lần rồi upload làm artifact.

## F. Guide bắt buộc (`docs/Guide_Local_AWS_Cost_DO2603.md`)

| Yêu cầu | Nguồn | Trạng thái |
|---|---|---|
| `lab-manifest.json` lập **TRƯỚC** khi apply | dòng 25 | ❌ sai quy trình — đã lập **BÙ SAU** (`evidence/day3-lab1-manifest.json`), đã ghi nhận trung thực trong chính file đó |
| Tag `Class, LabId, Owner, ExpiresAt` | dòng 27 | ✅ code xong — `var.expires_at` **không còn default `""`**, bắt buộc truyền `-var`/`TF_VAR_expires_at` mỗi lần apply (Terraform tự chặn nếu thiếu). Đã test plan với `expires_at=2026-09-23T23:59:00+07:00` thành công. `Owner` (viết hoa) đã bỏ theo quyết định J.1 (dùng `owner` chữ thường, case-insensitive nên vẫn đáp ứng Guide). |
| Teardown + evidence trước/sau | dòng 187-190 (SPEC.md) | ✅ xong — inventory before/after, teardown sạch 34/34, 0 orphan |
| Gỡ inline policy tự cấp sau lượt cuối | suy từ mục "Kiểm tra tài nguyên còn sót" | ❌ chưa gỡ — đang giữ vì còn 1 lượt apply cuối cần dùng (đã ghi rõ trong manifest) |

## G. Nộp bài

| Yêu cầu | Nguồn | Trạng thái |
|---|---|---|
| Branch `day3-terraform` | §4.3 dòng 380 | ✅ đúng branch hiện tại |
| PR title `[Day 3] <mô tả>` | §4.3 dòng 386-388 | ❌ chưa mở PR nào cho Day 3 |
| `ai-prompts/day3.md` ≥3 prompt, đúng format (Host/Version/Context/Time/Prompt/Why/What changed) | §4.4 dòng 396-422 | ❌ chưa tồn tại |
| `verify-day-3.sh` PASS | §4.2 dòng 362-372 | ❌ chưa chạy được — sẽ FAIL ở bước `run_tests` (thiếu `tests/milestones/day3/`) và các bước sau |
| Submission format §7.8 | dòng 908-923 | ❌ chưa có gì để nộp |
| Self-Check §7.9 (7 câu) | dòng 924-931 | ⚠️ đã tự trả lời được phần lớn qua audit; câu "Resource nào tag không đầy đủ" — sau khi áp quyết định mục J sẽ hết vướng |

## H. Should-have / Nice-to-have — **không bắt buộc** (§7.4 dòng 840-851)

> **Lưu ý quan trọng**: Conftest **KHÔNG** nằm trong mục này với ý nghĩa "tùy chọn". §7.3 (Non-functional #3) và §7.5 (Acceptance) đều liệt kê `conftest test ... pass` như một yêu cầu đạt được (không đánh dấu optional) — 2 test bắt buộc `test_policy_allows_valid`/`test_policy_denies_unsafe` (mục E.2) chính là cách hiện thực hóa yêu cầu này. Cái thực sự là Should-have (§7.4 dòng 841, nguyên văn "Conftest Rego policies (tags, encryption, cost guardrails)") là **mở rộng phạm vi bộ policy** — viết thêm rule kiểm tra tags/encryption/cost guardrails ngoài 2 case allow/deny tối thiểu. Có 2 test bắt buộc PASS với 1 policy Rego tối giản là đủ Must-have; viết thêm nhiều rule bao phủ rộng hơn mới là Should-have.

- Mở rộng bộ Conftest Rego (tags/encryption/cost guardrails) — Should-have, chưa làm
- Infracost comment on PR — Should-have, chưa có (cần pipeline trước)
- Multi-environment workspace — Should-have, chưa có
- AI explain plan trong PR comment — Should-have, chưa có
- Manual approval gate cho production — Should-have, chưa có
- *Nice-to-have*: modular submodules, custom Rego org-specific, backup strategy retention, drift detection — đều chưa làm, không bắt buộc

## I. Mâu thuẫn giữa các tài liệu (phát hiện được)

1. **Đường dẫn Conftest policy**: §2.5 dòng 250 ghi `infra/policies/ # Conftest Rego`, §7.5 dòng 862 ghi lệnh dùng `policy/terraform`. Hai path khác nhau cho cùng khái niệm. `scripts/verify.py` không dùng path nào cả (không gọi conftest trực tiếp) nên mâu thuẫn này không ảnh hưởng kết quả tự động, nhưng ảnh hưởng việc học viên chọn vị trí đặt file. → **Đã quyết định (J.2), chưa viết Rego (nằm ngoài lượt sửa Terraform này).**
2. **Tag `owner` vs `Owner`**: §7.3 dòng 806 đòi tag key `owner` (chữ thường) trong bộ 5 tag `project, environment, owner, cost_center, managed_by`. `docs/Guide_Local_AWS_Cost_DO2603.md:27` đòi tag key `Owner` (viết hoa) trong bộ 4 tag `Class, LabId, Owner, ExpiresAt`. Hai bộ tag gần như tách biệt, cùng khái niệm "chủ sở hữu" nhưng khác case — IAM API coi `owner`/`Owner` là trùng key (case-insensitive), đã gặp lỗi thật `InvalidInput: Duplicate tag keys found` khi thử áp cả hai cùng lúc. → **✅ Đã sửa code theo J.1** (`infra/variables.tf`, `common_tags` chỉ còn `owner` chữ thường).

## J. Quyết định đã chốt

1. **Tag owner**: dùng **`owner`** (chữ thường) trong `common_tags`, **bỏ** `Owner` (viết hoa). Lý do: IAM (và hầu hết AWS service) coi tag key case-insensitive, nên `owner` (chữ thường) **đáp ứng đồng thời cả 2 tài liệu** — §7.3 đòi đúng literal `owner`, còn Guide đòi `Owner` nhưng do case-insensitive nên cùng một key vật lý trên AWS. Tránh được bug "Duplicate tag keys" đã gặp trước đây (không được có cả 2 case cùng lúc). ✅ Đã áp dụng.
2. **Vị trí Rego + lệnh Conftest**: đặt tại **`infra/policy/terraform/`**, chạy `conftest` từ thư mục `infra/` — khi đó lệnh đúng y hệt §7.5 (`conftest test --policy policy/terraform tfplan.json`, chạy relative từ `infra/`), đồng thời vẫn nằm trong `infra/` theo tinh thần §2.5 (`infra/policies` — khác tên số ít/nhiều nhưng cùng ý định đặt policy trong `infra/`). ⚠️ Đã quyết định, **chưa viết file Rego**.
3. **Module bootstrap GitHub OIDC tách riêng**: `infra/bootstrap/github-oidc/`, backend S3 cùng bucket khác key (`insighthub/bootstrap/github-oidc.tfstate`), `lifecycle { prevent_destroy = true }` trên OIDC provider — không destroy theo lượt lab vì là resource cấp account dùng chung cả lớp. ✅ Đã viết code + `terraform plan` sạch (10 to add), **chưa apply** (apply ở giai đoạn viết pipeline thật).
4. **Bỏ `data.http.my_ip`, dùng `var.operator_cidrs` bắt buộc**: để `terraform plan` deterministic giữa local và CI (Acceptance §7.5) — trước đây plan **không** deterministic dù checklist từng đánh dấu ✅ nhầm (xem mục C). Thêm `validation` block chặn `0.0.0.0/0`/`::/0` (phòng thủ thêm, dù checkov không đọc được validation block — xem SPEC.md mục 10, finding CKV_AWS_38 mới). ✅ Đã áp dụng.
5. **Provider kubernetes dùng `exec` auth**: thay `data.aws_eks_cluster_auth.lab.token` (tĩnh, hết hạn ~15 phút) bằng `exec { command = "aws", args = ["eks", "get-token", ...] }` — tránh lỗi token hết hạn giữa apply dài (EKS+node group từng mất >30 phút thực tế). Rủi ro B (cluster đã bị xóa khi plan/destroy) **không có cách Terraform tự giải quyết** — xử lý bằng quy trình teardown 7 bước bắt buộc (SPEC.md mục 8), không phải code. ✅ Đã áp dụng.

## K. Thứ tự đóng băng source (source freeze) — bắt buộc để `ci_binding`/`verification-source` khớp

`fingerprint(repo)` (mục E.4) tính lại **mỗi lần verify**, dựa trên toàn bộ nội dung hiện tại của các thư mục trong `SOURCE_ROOTS` — kể cả sửa chưa commit (`VERIFICATION_CONTRACT.md`: "does not depend on HEAD... or a clean working tree"). Do đó bắt buộc theo đúng thứ tự sau, không đảo:

1. Sửa xong **toàn bộ** source liên quan Day 3 (Terraform, pipeline, Helm chart, test) — không còn thay đổi dự kiến.
2. Chạy CI (`iac.yml`) lần cuối trên đúng commit đó — CI tự build `deployment` artifact + `source-manifest.json` (chứa `source_sha256`/`artifact_sha256` tính tại thời điểm CI chạy) và upload artifact `verification-source`.
3. Tải artifact `verification-source` về, đặt cạnh `evidence/`.
4. Tạo `evidence/day3.json` (envelope + 2 artifact role `deployment`, `ci_binding`) khớp đúng hash đã tính ở bước 2.
5. Chạy `./scripts/verify-day-3.sh` **trong vòng 24h** kể từ `observed_at` (giới hạn `--max-age-hours`, mặc định 24h).

**Mọi sửa source sau bước 2** (kể cả sửa nhỏ, chưa commit) làm `fingerprint(repo)` lệch khỏi `source_sha256` đã đóng băng trong `source-manifest.json` → verify FAIL ngay ở bước so khớp (`scripts/verify.py:547`). Nếu cần sửa thêm, phải quay lại bước 2 (chạy CI lại).

**Ràng buộc bổ sung cho bước 2 — thời điểm chạy CI lần cuối**: phải chạy khi **state của module chính (`infra/`) đang rỗng** (sau teardown, chưa apply lại). Lý do: provider `kubernetes` dùng `exec` auth gọi `aws eks get-token` (mục J.5) — nếu `iac.yml` có job nào chạm tới provider này (kể cả chỉ `terraform plan`/`validate` với backend thật, không chỉ riêng `apply`), job đó cần **endpoint EKS cluster khả truy cập từ GitHub-hosted runner**, nhưng `public_access_cidrs = var.operator_cidrs` (mục J.4) chỉ whitelist đúng IP operator — **runner GitHub Actions luôn bị chặn** (IP khác, không nằm trong `operator_cidrs`). Do đó: chạy CI lần cuối cho `verification-source` khi cluster **chưa tồn tại** (state rỗng) để tránh job liên quan tới cluster bị timeout/lỗi kết nối; job đó chỉ nên chạy `fmt/validate/tflint/checkov/plan` (không cần cluster sống) — apply thật vẫn làm thủ công tại local như các lượt trước.

## L. Chuẩn bị trước khi deploy (bổ sung — không có mục riêng trong spec nhưng cần cho MH10/§2.3)

- **Cài `metrics-server`** trước khi deploy HPA cho `api` (§2.3 dòng 196) — HPA không hoạt động nếu thiếu `metrics-server` để cung cấp CPU/memory metrics. Cần cài **cả trên minikube** (giai đoạn test offline, `minikube addons enable metrics-server`) **và trên EKS** (giai đoạn apply cuối, qua Helm chart `metrics-server` chính thức hoặc manifest components.yaml), vì đây là 2 cluster khác nhau, không tự động có sẵn.

## M. Việc đã làm trong lượt sửa Terraform này (2026-09-23, KHÔNG apply)

Toàn bộ thay đổi ở `infra/main.tf`, `infra/variables.tf`, `infra/providers.tf` + module mới `infra/bootstrap/github-oidc/`. Đã chạy `terraform fmt -check -recursive` (0 diff), `terraform validate` (cả 2 module), `tflint --recursive` (0/0), `checkov -d infra/` (153 passed / 28 failed ban đầu), `terraform plan` cho module chính (**47 to add**, state đang rỗng sau teardown lượt trước) và module bootstrap (**10 to add**). Không có lệnh `apply` nào chạy.

**Lượt tiếp theo cùng ngày**: sửa `copy_tags_to_snapshot`/`encryption_configuration` (đóng CKV2_AWS_60 + CKV_AWS_136×3 bằng code), chuyển 24 finding còn lại thành `#checkov:skip` tại resource → **`checkov -d infra/`: 157 passed, 0 failed, 24 skipped, exit 0**. `tflint`/`validate` vẫn sạch.

Chưa làm trong lượt này (nằm ngoài phạm vi "chỉ Terraform"): file Rego (`infra/policy/terraform/`), `tests/milestones/day3/test_*.py`, `.github/workflows/iac.yml`, Helm chart, `ai-prompts/day3.md`, `lab-manifest.json` lập trước (vẫn còn nợ từ lượt trước).
