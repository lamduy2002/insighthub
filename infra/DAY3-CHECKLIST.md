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
| MH3 | EKS namespace resource | dòng 827 | ✅ **xong thật trên AWS** (2026-09-29) — `kubernetes_namespace.app` (root platform) tạo `insighthub-dev` trên EKS `insighthub-lab`, `kubectl get ns` → Active, label `managed-by=terraform`. Bằng chứng `evidence/day3-mh3-mh6.txt` |
| MH4 | RDS PostgreSQL 16, encrypted, not public | dòng 828 | ✅ xong (`storage_encrypted=true`, `publicly_accessible=false`) |
| MH5 | ElastiCache Redis 7, **private subnet** | dòng 829 | ✅ code xong — thêm `aws_subnet.private[*]` (2 AZ, route table riêng không IGW/NAT, chi phí $0), `aws_db_subnet_group`/`aws_elasticache_subnet_group` đã chuyển sang subnet này. EKS cluster/node group giữ nguyên public. Chưa apply. |
| MH6 | IRSA: ServiceAccount + IAM Role binding | dòng 830, verify bằng `kubectl describe sa insighthub` | ✅ **xong thật, chứng minh ở mức runtime** — `kubectl describe sa insighthub -n insighthub-dev` → annotation `eks.amazonaws.com/role-arn: ...insighthub-app-role`; pod thật inject `AWS_ROLE_ARN=...insighthub-app-role` + `AWS_WEB_IDENTITY_TOKEN_FILE` (KHÔNG phải node role); và Secret `insighthub-app-secrets` được CSI sync ra 2 key → pod đã **thực sự dùng IRSA đọc được Secrets Manager**. Bằng chứng `evidence/day3-mh3-mh6.txt` |
| MH7 | `.github/workflows/iac.yml` | dòng 831 | ✅ đã viết — 7 job + `verification-source`, action pin theo commit SHA, conftest tải kèm verify sha256. Bootstrap OIDC **đã apply thật** (12 resource), 4 repo variable + 2 GitHub Environment (`production` có required reviewer) đã tạo |
| MH8 | Pipeline jobs fmt→lint→scan→policy→plan→cost→apply | dòng 832 | ✅ đủ 7 job **đúng tên**: `fmt`, `lint`, `security-scan`, `policy-check`, `plan`, `cost-estimate`, `apply`. Saved plan qua S3 SSE-KMS (không phải artifact GitHub), `apply` verify sha256 trước khi apply đúng file đã review |
| MH9 | Pipeline green trên PR | dòng 833 | 🔄 **đang xác minh lại** — xem mục Q.6. Lần chạy đầu (run `36532890593`, `36536653766`) fail vì **GitHub Actions bị chặn ở cấp tài khoản**: 8/8 job fail sau 6s, chưa job nào được cấp runner, annotation *"recent account payments have failed or your spending limit needs to be increased"*. Đã chẩn đoán chỉ-đọc và loại trừ nguyên nhân từ code (mọi `runs-on` là `ubuntu-24.04` — runner chuẩn miễn phí cho repo public; `/actions/permissions` = `enabled: true`; **`starter.yml` của giảng viên cũng fail y hệt cùng lúc**). Chủ repo đã gỡ chặn billing lúc ~15:15 (+07) và pipeline chạy lại được — kết quả cuối ghi ở Q.6 |
| MH10 | InsightHub Helm deploy | dòng 834 | ✅ **xong cả local lẫn AWS**. AWS (2026-09-29): `helm upgrade --install` chart `insighthub` lên ns `insighthub-dev` với `values-dev.yaml` + image digest ECR + `certificate_arn` + `--set-file migration.initSql`; 4/4 pod Running, HPA đọc CPU, Ingress cấp ALB. Chart `insighthub-local-deps` **cố ý KHÔNG cài lên EKS** (Postgres=RDS, Redis=ElastiCache). Local trước đó — 2 chart ở `infra/helm/` (`insighthub`, `insighthub-local-deps`), đã `helm upgrade` thật trên kind `insighthub-lab` ns `insighthub-local` (2026-09-29): 5/5 pod Running, smoke curl `/healthz` 200 · `/readyz` 200 · `POST /documents` 202 · status `ready` <2s · `POST /chat` 200 kèm `sources`; UI kiểm trên trình duyệt OK. Trên EKS chưa deploy (cần apply core+platform trước). Theo Guide local-first: **local PASS không tính là hoàn thành AWS** |
| MH11 | Smoke test upload+chat | dòng 835 | ✅ **xong trên HTTPS domain thật** `https://insighthub-lamduy.do2603.click`: `/healthz` 200 · `POST /documents` (PDF có text) **202 trong 0.21s** (SLA <1.0s) · status `ready` sau **1.7s** (SLA <30s) · `POST /chat` 200 kèm `sources` trích đúng PDF vừa upload. Thêm: HTTP→HTTPS 301, `/` (web) 200, `/metrics` 404 (không public). Output `evidence/day3-smoke-https.txt` |
| MH12 | `tflint --recursive` no warnings | dòng 836 | ✅ xong — đã chạy lại trên cả module chính + `infra/bootstrap/github-oidc/`: 0 errors, 0 warnings |
| MH13 | `checkov` no HIGH | dòng 837 | ✅ `checkov -d infra/` → **684 passed, 0 failed, 59 skipped, exit 0** (2026-09-29; số cũ 157/0/24 là khi chưa có Helm chart trong `infra/`) — phần `terraform` 163/0/**25**, `helm` 508/0/**34**, `kubernetes` 13/0/0. Mọi finding bỏ qua đều là `#checkov:skip` / `checkov.io/skip<n>` gắn tại resource kèm lý do (SPEC Mục 10 + 10b), không `--skip-check` toàn cục, không `--soft-fail`. Vẫn thiếu xác nhận độc lập severity "không HIGH" cho các finding skip (checkov OSS không trả field `severity`), nhưng exit code 0 nên job security-scan trong pipeline sẽ xanh. |
| MH14 | All resources tagged | dòng 838 | ✅ **xác minh trên AWS thật**: Tagging API trả **29 ARN** mang `LabId=day3-terraform`, đủ 8 tag (`project, environment, owner, cost_center, managed_by, Class, LabId, ExpiresAt`) — `evidence/day3-mh14-tags.txt`. Lưu ý trung thực: `aws_iam_role_policy`, `aws_iam_role_policy_attachment`, `aws_kms_alias`, `aws_eks_access_policy_association` **không nhận tag** (API không có trường tag), không phải bỏ sót. Áp dụng quyết định J.1 — `owner` (chữ thường) duy nhất trong `common_tags`, không còn `Owner`. Module bootstrap dùng tag scheme riêng có chủ đích (xem SPEC.md mục 2, phần Tagging) |

## B. Non-functional (§7.3, dòng 802-809)

| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | `tflint --recursive` no warnings | ✅ xong |
| 2 | `checkov -d infra/` no HIGH | ✅ 684 passed, 0 failed, 59 skipped kèm lý do inline (xem mục A/MH13). Thêm: job `security-scan` quét **bản render dev** riêng → 336 passed, 0 failed, 27 skipped |
| 3 | `conftest test ... tfplan.json` pass — **bắt buộc** (không phải Should-have, xem mục H) | ✅ local (2026-09-25) — `infra/policy/terraform/main.rego` (18 rule `deny`, Rego v1) + `main_test.rego` (`conftest verify`: 23/23 pass). Chạy trên plan thật (`terraform show -json tfplan`): **19 passed, 0 failures** (2026-09-29, plan core 50 to add). Danh sách rule + lý do helper `is_true`: `infra/SPEC.md` Mục 11. ⚠️ Pipeline CI (`iac.yml`) chưa có — CI phải cài Conftest 0.70.x. |
| 4 | Tags: project, environment, owner, cost_center, managed_by | ✅ áp dụng quyết định J.1 |
| 5 | Pipeline OIDC AWS (no long-lived keys) | ✅ bootstrap **đã apply thật** (12 resource): 2 role `gh_plan`/`gh_apply` trust theo `sub=...:environment:infra-plan|production` (StringEquals, không wildcard), KMS key cho saved plan. OIDC provider chuyển sang **data source** (xem J.6). ⚠️ chưa chứng minh được end-to-end vì Actions bị chặn billing (MH9). Lịch sử: code xong, chưa apply — `infra/bootstrap/github-oidc/` có OIDC provider + 2 role (`gh_plan`/`gh_apply`), `terraform plan` sạch (10 to add); chưa apply nên GitHub Actions thật vẫn chưa dùng được. Mọi apply thủ công hôm nay vẫn qua IAM user `DE000215` (long-lived key), hợp lệ cho thao tác thủ công. |
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
| `conftest test --policy policy/terraform tfplan.json` → pass — **bắt buộc** | ✅ local — chạy từ `infra/`, plan thật: **19 passed, 0 failures** (2026-09-29). ⚠️ `tfplan.json` **không được nằm trong `infra/` khi chạy checkov** (verify.py copy cả `infra/` rồi `checkov -d .` → checkov quét plan JSON, không thấy inline `#checkov:skip` → fail CKV2_AWS_57/50...). Sinh plan JSON ra ngoài `infra/` hoặc xoá trước bước checkov — xem SPEC Mục 11. |
| `infracost breakdown --path infra/` | ✅ |
| `gh run list --workflow=iac.yml` → ✓ | ❌ — workflow tồn tại, run `36532890593` fail do chặn billing cấp tài khoản (MH9) |
| `kubectl get ns insighthub-dev` → exists | ✅ Active (2026-09-29) |
| `kubectl get pods -n insighthub-dev` → Ready | ✅ 4/4 Running (api×2 theo HPA minReplicas, worker, web) |
| `curl .../healthz` → 200 | ✅ 200 (HTTPS, domain thật) |
| `curl -X POST .../documents` → 202 | ✅ 202 trong **0.21s** (SLA <1.0s) |
| `GET /documents` → ready <30s | ✅ **1.7s** |
| `curl -X POST .../chat` → 200 | ✅ 200, `sources` trích đúng PDF vừa upload |

## D. Kiến trúc §2.3 (dòng 189-204)

| Thành phần | Trạng thái |
|---|---|
| EKS namespace `insighthub-<env>` | ✅ code xong (`infra/platform/` — `kubernetes_namespace.app`), chưa apply |
| Deployment `web` + Service | ✅ chart `insighthub`, chạy thật trên kind |
| Deployment `api` + Service + **HPA** + **Ingress (TLS)** | ⚠️ Deployment/Service/HPA chạy thật trên kind (`metrics-server` đã cài, HPA đọc được CPU). **Ingress chưa chạy thật** — `ingress.enabled=false` ở local, bản dev mới chỉ `helm template` + checkov (cần ALB Controller trên EKS) |
| Deployment `ingestion-worker` | ✅ chart `insighthub`, chạy thật trên kind |
| Helm values + ConfigMap + Secret | ✅ `values-local.yaml`/`values-dev.yaml`, ConfigMap app+web, Secret từ chart local-deps (local) / CSI `secretObjects` (dev, chưa chạy thật) |
| RDS PostgreSQL 16 + pgvector | ✅ đã có trong Terraform, nay subnet **private** (MH5), chưa apply |
| ElastiCache Redis 7 | ✅ đã có trong Terraform, nay subnet **private** (MH5), chưa apply |
| IAM roles for service accounts (IRSA) | ✅ code xong — ALB controller + app (`insighthub`), chưa apply |

## E. Yêu cầu verifier — 5 câu trả lời (trích dòng code)

**1. Conftest policy path verifier chạy?**
Verifier **không tự chạy `conftest` bằng lệnh cứng trong code**. `scripts/verify.py:526-528` (hàm `day3`) chỉ chạy 4 lệnh: `terraform fmt -check -recursive`, `terraform init -backend=false -input=false`, `terraform validate -no-color`, `checkov -d . --quiet`. Việc gọi `conftest` nằm trong 2 test bắt buộc mà **học viên tự viết**: `test_policy_allows_valid` / `test_policy_denies_unsafe` (`scripts/verify.py:38`, `REQUIRED_TESTS[3]`) — verifier chỉ đòi 2 tên scenario này PASS qua `pytest`, không quy định path Rego cụ thể trong code. Path chính thức do tài liệu quy định (§7.5 dòng 862: `policy/terraform`; §2.5 dòng 250: `infra/policies`) — 2 path khác nhau, xem mục J cho quyết định đã chốt.

**2. Tên scenario test bắt buộc trong `tests/milestones/day3/test_*.py`?**
`scripts/verify.py:38`: `REQUIRED_TESTS[3] = {'test_policy_allows_valid', 'test_policy_denies_unsafe'}`. Đúng 2 tên. Theo đúng tên, 2 test này phải **tự chạy Conftest** (subprocess) trên 1 `tfplan.json` hợp lệ (kỳ vọng `allow`) và 1 `tfplan.json` vi phạm cố ý (kỳ vọng `deny`) — bản thân verifier chỉ kiểm JUnit report có 2 case này pass, không kiểm nội dung test làm gì bên trong.

✅ **Đã làm (2026-09-25)** — `tests/milestones/day3/test_policy.py`: cả 2 test gọi `conftest test --policy infra/policy/terraform <fixture>` qua `subprocess` (không `shell=True`), fixture ở `tests/milestones/day3/fixtures/`:
- `test_policy_allows_valid` — `valid_plan.json` phải exit 0.
- `test_policy_denies_unsafe` — `invalid_plan.json` phải exit ≠ 0 **và** output phải chứa deny message của `publicly_accessible`, tag `owner`, `transit_encryption_enabled`, `instance_class` (không chỉ kiểm exit code, tránh test pass vì lỗi parse).
- Test đọc repo root từ env `INSIGHTHUB_REPO_ROOT` (verify.py set sẵn, xem `run_tests`); chạy tay: `INSIGHTHUB_REPO_ROOT=$PWD venv/bin/python -m pytest tests/milestones/day3` → 2 passed.
- Dry-run `venv/bin/python scripts/verify.py day3 --ci-profile local --evidence-dir evidence` (evidence `mode: fixture`, deployment = placeholder) → `INCOMPLETE: Local preparation checked; GitHub pipeline remains mandatory for Day 3` — thông báo này chỉ xuất hiện **sau khi** pytest 2 test + fmt/init/validate/checkov đều pass (`scripts/verify.py:519-531`, rồi `main()` dòng 891). Phải dùng `venv/bin/python` (3.11, có pytest/PyYAML) vì verify.py chạy pytest bằng `sys.executable`; `/usr/bin/python3` (3.10) không có pytest → INCOMPLETE sớm.

**3. Cấu trúc `evidence/day3.json`?**
Theo `scripts/verify.py:513-517` + `VERIFICATION_CONTRACT.md:42`: 2 artifact role bắt buộc — `deployment` (file dùng để tính `artifact_sha256`) và `ci_binding` (file JSON có 2 field `source_sha256`, `artifact_sha256`, phải khớp `expected = {'source_sha256': fingerprint(repo), 'artifact_sha256': sha(deployment)}`). Envelope chung (`evidence()` dòng 310-318): `schema_version`, `day`, `mode` (real/fixture), `observed_at` (RFC3339, ≤24h), `source_sha256`, `artifacts: {role: {path, sha256}}`.

**4. GitHub artifact "verification-source"?**
`scripts/verify.py:543-546`: tên artifact chính xác **`verification-source`**, bên trong chứa **`source-manifest.json`** với field `source_sha256`, `artifact_sha256` — phải khớp CHÍNH XÁC với giá trị tính tại thời điểm verify. `source_sha256 = fingerprint(root)` (dòng 160-167): SHA-256 nối `relative_path + \0 + sha256_bytes(file)` cho từng file trong `source_files(root)` (phạm vi `SOURCE_ROOTS` dòng 29-31: `api, web, ingestion-worker, chatops-bot, infra, observability, security, tools, scripts, tests, .github, .agents/rules, .agent/rules` + vài file gốc, loại trừ `EXCLUDED_DIRS` dòng 32-34). `artifact_sha256 = sha(path)` (dòng 63-64): SHA-256 hex thô của file `deployment`.

**5. "Deployment artifact" là file gì?**
Không quy định cứng định dạng trong code — chỉ đòi file thật, không dummy. **Quyết định cần chốt ở giai đoạn viết pipeline** (xem mục J): dùng đúng file do CI sinh ra (tải về `evidence/`), **không build lại ở local** vì `helm package` không deterministic (timestamp/metadata thay đổi mỗi lần chạy → hash lệch). Ứng viên khả thi: output `helm template` (text, deterministic) hoặc file `.tgz` do đúng job CI đó `helm package` một lần rồi upload làm artifact.

## F. Guide bắt buộc (`docs/Guide_Local_AWS_Cost_DO2603.md`)

| Yêu cầu | Nguồn | Trạng thái |
|---|---|---|
| `lab-manifest.json` lập **TRƯỚC** khi apply | dòng 25 | ✅ **đã sửa ở lượt 2** — `evidence/day3-lab2-manifest.json` lập trước khi tạo bất kỳ tài nguyên nào, kèm `evidence/day3-inventory-before.txt`. (Lượt 1 từng lập bù sau, đã ghi nhận trung thực trong `day3-lab1-manifest.json` — không xoá lịch sử đó) |
| Tag `Class, LabId, Owner, ExpiresAt` | dòng 27 | ✅ code xong — `var.expires_at` **không còn default `""`**, bắt buộc truyền `-var`/`TF_VAR_expires_at` mỗi lần apply (Terraform tự chặn nếu thiếu). Đã test plan với `expires_at=2026-09-23T23:59:00+07:00` thành công. `Owner` (viết hoa) đã bỏ theo quyết định J.1 (dùng `owner` chữ thường, case-insensitive nên vẫn đáp ứng Guide). |
| Teardown + evidence trước/sau | dòng 187-190 (SPEC.md) | ✅ xong — inventory before/after, teardown sạch 34/34, 0 orphan |
| Gỡ inline policy tự cấp sau lượt cuối | suy từ mục "Kiểm tra tài nguyên còn sót" | ❌ chưa gỡ — đang giữ vì còn 1 lượt apply cuối cần dùng (đã ghi rõ trong manifest) |

## G. Nộp bài

| Yêu cầu | Nguồn | Trạng thái |
|---|---|---|
| Branch `day3-terraform` | §4.3 dòng 380 | ✅ đúng branch hiện tại |
| PR title `[Day 3] <mô tả>` | §4.3 dòng 386-388 | ✅ PR #2 — `[Day 3] IaC + pipeline: Terraform core/platform, policy gates, Helm chart` |
| `ai-prompts/day3.md` ≥3 prompt, đúng format (Host/Version/Context/Time/Prompt/Why/What changed) | §4.4 dòng 396-422 | ✅ **4 prompt nguyên văn** từ phiên 29/09/2026, đủ 7 trường. Không chép prompt pack giảng viên |
| `verify-day-3.sh` PASS | §4.2 dòng 362-372 | ❌ chưa chạy được — sẽ FAIL ở bước `run_tests` (thiếu `tests/milestones/day3/`) và các bước sau |
| Submission format §7.8 | dòng 908-923 | ✅ `evidence/day3-submission.md` — có mục "Việc còn thiếu và lý do" cho MH9 |
| Self-Check §7.9 (7 câu) | dòng 924-931 | ✅ trả lời đủ 7 câu trong `evidence/day3-submission.md`, dẫn số liệu đo thật |

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
4. **Bỏ `data.http.my_ip`, dùng `var.operator_cidrs` bắt buộc**: để `terraform plan` deterministic giữa local và CI (Acceptance §7.5) — trước đây plan **không** deterministic dù checklist từng đánh dấu ✅ nhầm (xem mục C). Thêm `validation` block chặn `0.0.0.0/0`/`::/0` (phòng thủ thêm, dù checkov không đọc được validation block — xem SPEC.md mục 10, finding CKV_AWS_38 mới). ✅ Đã áp dụng. **Cập nhật 2026-09-25**: đổi tên thành `var.admin_cidrs` (cùng validation, thêm kiểm CIDR hợp lệ + không rỗng) — xem mục O / SPEC.md Mục 2, 12.
5. **OIDC provider GitHub: `data` source, KHÔNG phải `resource`** (J.6, quyết định 2026-09-29). AWS chỉ cho 1 provider/URL issuer/account nên nó là tài nguyên cấp account dùng chung; thực tế đã do học viên khác tạo (`owner=DO-NGOC-VINH`). Quản lý bằng `resource` (kể cả sau `terraform import`) sẽ ghi đè tag sở hữu và `lab_expiry` của họ mỗi lần apply — phá đúng dấu vết truy trách nhiệm cleanup mà Guide yêu cầu. Cùng nguyên tắc với ACM cert `*.do2603.click`: **tài nguyên dùng chung thì chỉ tham chiếu, không quản lý**. Đánh đổi đã biết: chủ sở hữu có thể xoá nó bất cứ lúc nào, khi đó plan fail ngay ở data source (fail-fast) thay vì lỗi mơ hồ lúc assume role. ✅ Đã áp dụng.
6. **Provider kubernetes dùng `exec` auth**: thay `data.aws_eks_cluster_auth.lab.token` (tĩnh, hết hạn ~15 phút) bằng `exec { command = "aws", args = ["eks", "get-token", ...] }` — tránh lỗi token hết hạn giữa apply dài (EKS+node group từng mất >30 phút thực tế). Rủi ro B (cluster đã bị xóa khi plan/destroy) **không có cách Terraform tự giải quyết** — xử lý bằng quy trình teardown 7 bước bắt buộc (SPEC.md mục 8), không phải code. ✅ Đã áp dụng.

## K. Thứ tự đóng băng source (source freeze) — bắt buộc để `ci_binding`/`verification-source` khớp

`fingerprint(repo)` (mục E.4) tính lại **mỗi lần verify**, dựa trên toàn bộ nội dung hiện tại của các thư mục trong `SOURCE_ROOTS` — kể cả sửa chưa commit (`VERIFICATION_CONTRACT.md`: "does not depend on HEAD... or a clean working tree"). Do đó bắt buộc theo đúng thứ tự sau, không đảo:

1. Sửa xong **toàn bộ** source liên quan Day 3 (Terraform, pipeline, Helm chart, test) — không còn thay đổi dự kiến.
2. Chạy CI (`iac.yml`) lần cuối trên đúng commit đó — CI tự build `deployment` artifact + `source-manifest.json` (chứa `source_sha256`/`artifact_sha256` tính tại thời điểm CI chạy) và upload artifact `verification-source`.
3. Tải artifact `verification-source` về, đặt cạnh `evidence/`.
4. Tạo `evidence/day3.json` (envelope + 2 artifact role `deployment`, `ci_binding`) khớp đúng hash đã tính ở bước 2.
5. Chạy `./scripts/verify-day-3.sh` **trong vòng 24h** kể từ `observed_at` (giới hạn `--max-age-hours`, mặc định 24h).

**Mọi sửa source sau bước 2** (kể cả sửa nhỏ, chưa commit) làm `fingerprint(repo)` lệch khỏi `source_sha256` đã đóng băng trong `source-manifest.json` → verify FAIL ngay ở bước so khớp (`scripts/verify.py:547`). Nếu cần sửa thêm, phải quay lại bước 2 (chạy CI lại).

**Ràng buộc bổ sung — file plan không được nằm trong repo** (đo thật 2026-09-25):
- `fingerprint()` → `source_files()` (`scripts/verify.py:124`) đi `os.walk` trên mọi thư mục `SOURCE_ROOTS` (có `infra`), **không dùng git** → `.gitignore` không loại được gì. Chỉ bỏ qua thư mục trong `EXCLUDED_DIRS` và file `.env*`, `*.pyc`, `*.log`, `*.zip`, `*.html`, `REPORT_NAME`.
- `scripts/verify.py:32-34`:
  ```python
  EXCLUDED_DIRS = {'.git', '.venv', 'venv', 'node_modules', '__pycache__', '.next',
                   '.pytest_cache', '.terraform', 'dist', 'build', 'coverage', 'reports',
                   'evidence', 'artifacts', 'test-results'}
  ```
  → `infra/.terraform/` (và `infra/bootstrap/github-oidc/.terraform/`) **bị loại** ✅ (so khớp theo tên thư mục ở mọi cấp). `venv/` **bị loại** ✅ (thực tế `venv/` ở root cũng không thuộc `SOURCE_ROOTS`). `.terraform.lock.hcl` **không** bị loại — đúng, vì file này được commit.
- **Không** bị loại: `tfplan`, `tfplan.json`, `teardown.tfplan`, `lab.tfplan`, `*.tfstate*` → nếu nằm trong `infra/` ở local (không có trên runner) thì `source_sha256` local ≠ CI. Đã đo: 3 file plan (`infra/tfplan`, `infra/teardown.tfplan`, `infra/bootstrap/github-oidc/tfplan`) → `6e7de32b…`; chuyển sang `/tmp/insighthub-plans/` → `0456ae13…`. `find infra -name "*tfplan*"` giờ rỗng.
- **Quy tắc rộng hơn (đo thật 2026-09-29)**: ràng buộc không chỉ là file plan —
  **mọi file local-only nằm trong `SOURCE_ROOTS` đều phá source binding**, vì
  `source_files()` đi `os.walk` chứ không hỏi git, nên `.gitignore` **không**
  loại được gì. Lần chạy CI đầu tiên trên commit đã đóng băng vẫn lệch
  `source_sha256`, truy ra 3 file gitignore có chủ đích:
  `infra/.infracost/pricing.gob`, `infra/.infracost/terraform_modules/manifest.json`
  (cache Infracost) và `infra/k8s/mcp-readonly.kubeconfig` (kubeconfig MCP, có
  token). Cách xử lý: xoá cache Infracost (tái tạo được), chuyển kubeconfig ra
  `~/.kube/` và trỏ lại đường dẫn trong `.mcp.json`. Lưu ý **không dùng symlink**
  để lách — `source_files()` từ chối symlink (`Source symlink unsupported`).
  Lệnh kiểm trước mỗi lần đóng băng (so danh sách của verify.py với `git ls-files`):
  ```bash
  venv/bin/python -c "
  import importlib.util,pathlib,subprocess
  root=pathlib.Path('.').resolve()
  spec=importlib.util.spec_from_file_location('verify', root/'scripts'/'verify.py')
  m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  local={p.relative_to(root).as_posix() for p in m.source_files(root)}
  tracked=set(subprocess.run(['git','ls-files'],capture_output=True,text=True).stdout.split())
  print(sorted(local-tracked) or 'OK')"
  ```
- **Quy tắc**: mọi `terraform plan -out`, `terraform show -json`, `terraform plan -destroy -out` đều ghi ra ngoài repo — `/tmp/insighthub-plans/` ở local, `$RUNNER_TEMP` ở CI (lệnh mẫu: `infra/SPEC.md` Mục 11). Trước bước 2 và bước 5: chạy `find infra -path '*/.terraform' -prune -o \( -name "*tfplan*" -o -name "*.tfstate*" \) -print` phải rỗng. Loại `.terraform/` vì `terraform init` luôn tạo `.terraform/terraform.tfstate` — đó là cache cấu hình backend, không phải state hạ tầng; thư mục này vừa gitignore vừa nằm trong `EXCLUDED_DIRS` nên không ảnh hưởng fingerprint.

**Ràng buộc bổ sung — môi trường verifier**: `scripts/verify.py` cần **Python 3.11+**, và chạy pytest bằng `sys.executable` → phải gọi bằng Python của venv đã cài `python -m pip install --require-hashes -r scripts/requirements-verification.txt` (`GETTING_STARTED.md` mục "Milestone verifier dependencies"). `/usr/bin/python3` (3.10, không pytest) → INCOMPLETE ngay ở `run_tests`. Pipeline CI phải làm đúng như vậy: `setup-python` 3.11+, venv, `pip install --require-hashes`, rồi chạy verifier bằng Python của venv.

**Ràng buộc bổ sung cho bước 2 — thời điểm chạy CI lần cuối** (cập nhật 2026-09-25 sau khi tách core/platform): core **không còn provider `kubernetes`** nên plan/apply core chạy được trên GitHub-hosted runner dù cluster đang sống hay chưa. Chỉ root platform + Helm cần endpoint EKS — job apply tạm thêm IP runner vào `public_access_cidrs` rồi khôi phục đúng `admin_cidrs` (`if: always()`), sau đó fresh plan core phải không có thay đổi (SPEC.md Mục 12). Ràng buộc "state phải rỗng" của bản cũ không còn cần; nhưng lần chạy CI cuối cho `verification-source` vẫn phải chạy **sau** khi mọi source đã đóng băng (bước 1-2).

## L. Chuẩn bị trước khi deploy (bổ sung — không có mục riêng trong spec nhưng cần cho MH10/§2.3)

- **Cài `metrics-server`** trước khi deploy HPA cho `api` (§2.3 dòng 196) — HPA không hoạt động nếu thiếu `metrics-server` để cung cấp CPU/memory metrics. Cần cài **cả trên cluster local** (kind riêng — mục O.13; trước đây ghi minikube) **và trên EKS** (Helm chart `metrics-server` chính thức), vì đây là 2 cluster khác nhau, không tự động có sẵn.
- **Add-on cluster bắt buộc trên EKS** (Helm, sau `platform` apply, trước Helm app):
  1. Secrets Store CSI Driver — bật `syncSecret.enabled=true` (app chỉ đọc env, mục N.1).
  2. AWS provider ASCP (`secrets-store-csi-driver-provider-aws`).
  3. `metrics-server` (HPA api).
  4. AWS Load Balancer Controller — `serviceAccount.create=false`, dùng SA `aws-load-balancer-controller` do root platform tạo (IRSA), `vpcId` = output core `vpc_id`.
  Tất cả **phải gỡ trước platform destroy** (SPEC.md Mục 8, bước 5). ALB Controller chỉ gỡ **sau khi** ALB đã bị xóa (bước 3) — controller là thành phần xóa ALB qua finalizer Ingress.
- **Hook Helm không bị `helm uninstall` xóa**: `SecretProviderClass` + migration Job là hook `pre-install,pre-upgrade`. Migration Job dùng `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`; `SecretProviderClass` không tự xóa được (phải tồn tại suốt vòng đời pod) → teardown xóa tường minh `kubectl -n insighthub-<env> delete secretproviderclass,job -l app.kubernetes.io/instance=<release>` **trước** khi gỡ CSI driver (SPEC.md Mục 8, bước 2).

## M. Việc đã làm trong lượt sửa Terraform này (2026-09-23, KHÔNG apply)

Toàn bộ thay đổi ở `infra/main.tf`, `infra/variables.tf`, `infra/providers.tf` + module mới `infra/bootstrap/github-oidc/`. Đã chạy `terraform fmt -check -recursive` (0 diff), `terraform validate` (cả 2 module), `tflint --recursive` (0/0), `checkov -d infra/` (153 passed / 28 failed ban đầu), `terraform plan` cho module chính (**47 to add**, state đang rỗng sau teardown lượt trước) và module bootstrap (**10 to add**). Không có lệnh `apply` nào chạy.

**Lượt tiếp theo cùng ngày**: sửa `copy_tags_to_snapshot`/`encryption_configuration` (đóng CKV2_AWS_60 + CKV_AWS_136×3 bằng code), chuyển 24 finding còn lại thành `#checkov:skip` tại resource → **`checkov -d infra/`: 157 passed, 0 failed, 24 skipped, exit 0**. `tflint`/`validate` vẫn sạch.

Chưa làm trong lượt này (nằm ngoài phạm vi "chỉ Terraform"): file Rego (`infra/policy/terraform/`), `tests/milestones/day3/test_*.py`, `.github/workflows/iac.yml`, Helm chart, `ai-prompts/day3.md`, `lab-manifest.json` lập trước (vẫn còn nợ từ lượt trước).

## N. Đầu vào deploy — audit Helm/pipeline (2026-09-25, chỉ đọc code app)

Đối chiếu spec §0.4, §2.3, §2.4, §2.5, §5.4, §7 và `GETTING_STARTED.md` §2. Kết luận: **không phải sửa code app** (giữ contract Day 1); 2 việc bắt buộc nằm ở Terraform (C1/C2, đã làm).

**N.1 Biến môi trường → ConfigMap/Secret.** api và worker dùng chung `Settings` (pydantic-settings; env = tên field viết hoa) — `api/app/core/config.py:13-65`; worker copy nguyên `api/app` (`ingestion-worker/Dockerfile:18`). App **chỉ đọc env** (`env_file=".env"`, không `secrets_dir` — `config.py:14-20`) → Secrets Store CSI phải dùng `secretObjects` sync thành K8s Secret (driver `syncSecret.enabled=true`) rồi `secretKeyRef`/`envFrom`; K8s Secret sync chỉ tồn tại khi có pod mount volume CSI → **api, worker, migration Job đều mount CSI**; rotate cần restart pod.

| Biến | Service | Bắt buộc | Bí mật | Đích |
|---|---|---|---|---|
| `DATABASE_URL` | api, worker | Có (default trỏ `postgres:5432`, `config.py:25-28`) | **Có** | Secret ← field `database_url` của `db-credentials` |
| `REDIS_URL` | api, worker | Có (default `redis://redis:6379/0`, `config.py:29`) | **Có** | Secret ← field `redis_url` của `redis-credentials` |
| `RAG_MODE`, `LLM_PROVIDER`, `EMBEDDING_PROVIDER` | api, worker | **Đặt tường minh** — code default `real`/`gemini` (`config.py:30-36`) | Không | ConfigMap = `fixture` |
| `EMBEDDING_DIM`(1024), `EMBEDDING_REVISION`, `LLM_MAX_TOKENS`, `PROVIDER_TIMEOUT_SECONDS` | api, worker | Tùy chọn (`config.py:54-59`) | Không | ConfigMap |
| `LOG_LEVEL`, `ENVIRONMENT`, `MAX_UPLOAD_BYTES`, `CHUNK_*`, `RETRIEVAL_TOP_K`, `HNSW_EF_SEARCH` | api, worker | Tùy chọn (`config.py:23-24, 60-65`) | Không | ConfigMap khi cần |
| `*_API_KEY` | api, worker | Chỉ khi `RAG_MODE=real` (`config.py:78-81`) | **Có** | Không dùng (fixture) |
| `*_MODEL`, `OPENAI_BASE_URL`, `OLLAMA_*` | api, worker | Chỉ khi real (`config.py:38-53`) | Không | — |
| `API_INTERNAL_URL` | web | Tùy chọn, default `http://api:8000` (`web/lib/api.ts:4`) | Không | env/ConfigMap |

**N.2 Postgres.** App dùng `DATABASE_URL` (psycopg conninfo) — `api/app/core/db.py:26-27`. libpq hỗ trợ `?sslmode=require` và percent-decode password trong URI (đã kiểm: `urlencode()` của Terraform với `#?[]:%!&*()=+{}<>~$^` → libpq decode khớp nguyên văn). → **C1**. `sslmode=require` là đủ (RDS `rds.force_ssl = 1`); `verify-full` + `sslrootcert` (CA bundle RDS mount vào pod) là **tùy chọn**.

**N.3 Redis.** api `api/app/core/queue.py:18-19`, worker `ingestion-worker/worker/settings.py:23` — cả hai `RedisSettings.from_dsn(REDIS_URL)`. arq 0.28.0 hỗ trợ `rediss://` (`ssl = scheme == 'rediss'`, `ssl_cert_reqs='required'`, `ssl_check_hostname=False`) nhưng lấy `password` từ `urlparse` **không unquote** → token chứa `#`, `?`, `[`, `]` làm hỏng URL, token percent-encode bị gửi nguyên `%XX` → AUTH fail. → **C2** (không sửa app). Cert ElastiCache do Amazon cấp, python slim có CA hệ thống — xác nhận ở smoke.

**N.4 Upload.** File đi qua **payload job Redis** (`api/app/routers/documents.py:39` `enqueue_job(..., content)`; worker nhận `content: bytes` — `ingestion-worker/worker/tasks.py:68-69`). **Không cần PVC/volume chung.** Mỗi job ≤ 10 MB trong Redis, `max_jobs = 10` (`settings.py:26`) + retry 3 lần — theo dõi RAM `cache.t3.micro` (~0,5 GB).

**N.5 Web.** Browser gọi đường dẫn tương đối cùng origin (`/api/documents`, `/api/proxy?target=upload|chat` — `web/components/UploadPanel.tsx:20,38,58`, `ChatPanel.tsx:18`); route handler server gọi `${API_URL}` (`web/app/api/proxy/route.ts:27`, `web/lib/api.ts:22,28`). **Không có `NEXT_PUBLIC_*`**, `API_INTERNAL_URL` đọc runtime server-side, trang `force-dynamic` (`web/app/page.tsx:6`) → không sửa source web (§2.5), chỉ đặt env `API_INTERNAL_URL=http://<api-svc>.<ns>.svc.cluster.local:8000`. Sau Ingress HTTPS không có mixed content. Acceptance §7.5 gọi thẳng `/healthz`, `/documents`, `/chat` trên host → Ingress route `/healthz`, `/readyz`, `/documents`, `/chat` → api, `/` → web (web dùng prefix `/api/*`, không trùng); **không public `/metrics`**.

**N.6 init.sql.** `CREATE EXTENSION IF NOT EXISTS vector;` (`infra/db/init.sql:3`); `VECTOR(1024)` (dòng 51) khớp `EMBEDDING_DIM=1024`; **không có `shared_preload_libraries`** (init.sql + docker-compose.yml) — đúng §0.4. Idempotent (`IF NOT EXISTS`), khối DO chặn schema legacy (dòng 5-17). **Chạy trên RDS**: K8s Job image `pgvector/pgvector:0.8.2-pg16@sha256:00ba258a…` (`docker-compose.yml:5`, có `psql`), user 999, `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f /sql/init.sql`; credential `DATABASE_URL` qua CSI; master user có `rds_superuser` → `CREATE EXTENSION` được. **Một nguồn duy nhất (quyết định)**: Helm nhận SQL bằng `--set-file` từ `infra/db/init.sql` lúc install/upgrade vào ConfigMap — **không copy file vào chart**. Job phải chạy **trước** api/worker (startup `initialize_database()` → `check_schema` fail khi thiếu schema — `api/app/core/db.py:43-49`, `ingestion-worker/worker/settings.py:13-14`) → Helm hook `pre-install,pre-upgrade`; `SecretProviderClass` cũng là hook với weight thấp hơn Job. Kiểm trước: `SELECT * FROM pg_available_extensions WHERE name='vector'` trên RDS 16.15.

**N.7 Dockerfile.**

| Image | Base (pin digest) | User | Port | HEALTHCHECK | CMD |
|---|---|---|---|---|---|
| api | `python:3.12.14-slim@sha256:78387bc3…` (`api/Dockerfile:3`) | `appuser` 1001/1001 (dòng 13-14, 19) | 8000 | `/readyz` (dòng 21-22) | `uvicorn app.main:app --host 0.0.0.0 --port 8000` |
| worker | như api (`ingestion-worker/Dockerfile:4`) | `appuser` 1001/1001 (dòng 14-15, 20) | — | `arq --check` (dòng 21-22) | `arq worker.settings.WorkerSettings` |
| web | `node:24.20.0-alpine@sha256:e67514e5…` (`web/Dockerfile:4,10,18`) | `nextjs` 1001 / `nodejs` 1001 (dòng 22-23, 28) | 3000 | `/api/health` (dòng 32-33) | `node server.js` |

Non-root trên K8s: `USER` trong image là **tên** → với `runAsNonRoot: true` kubelet không xác minh được ("non-numeric user") → **bắt buộc `runAsUser: 1001`, `runAsGroup: 1001`** (+ `fsGroup: 1001`). `readOnlyRootFilesystem: true` cần `emptyDir` `/tmp` (api: python-multipart spool > 1 MB; worker) và `/app/.next/cache` (web). Thêm `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`. K8s bỏ qua `HEALTHCHECK` Docker.

**N.8 Probe.** api: liveness `/healthz` (không chạm DB — `api/app/routers/health.py:12-14`), readiness `/readyz` (DB/schema/identity, 503 khi chưa sẵn sàng — dòng 17-23), thêm startupProbe (lifespan chờ pool ≤ 15 s — `db.py:46`). web: `/api/health` (`web/app/api/health/route.ts`, không kiểm api). worker: **exec `arq --check worker.settings.WorkerSettings`** (quyết định: không sửa code worker trong Day 3), `periodSeconds` ≥ 60. ⚠️ **Worker health endpoint (§5.4) là Should-have Day 1 chưa làm**; worker không có endpoint HTTP health/metrics (metrics worker là Nice-to-have §5.4 — chuẩn bị Day 4). arq mặc định `health_check_interval = 3600` (key TTL 3601 s) → probe **kém nhạy**: worker treo vẫn "khỏe" tới ~1 giờ. Metrics hiện chỉ ở api `/metrics` (`api/app/main.py:89-99`).

**N.9 RAG_MODE.** Code default `real` + `gemini` (`config.py:30-36`), chỉ compose/.env đặt fixture (`docker-compose.yml:32-34`, `.env.example:3-5`) → EKS phải đặt tường minh 3 biến `fixture`. Hợp lệ Day 3: "For Days 1-5 … the application may use a fixture LLM" (`scripts/VERIFICATION_CONTRACT.md:76-77`). Không trộn fixture/real trên cùng DB (`GETTING_STARTED.md:45`) — chuyển real cần DB/schema mới.

**N.10 Local (kind).** Postgres: `pgvector/pgvector:0.8.2-pg16@sha256:00ba258a66dac104fd5171074a0084462a64a1369d8513f3d0a634e2f24d15bc` (`docker-compose.yml:5`). Redis: **quyết định dùng `redis:7.x` pin digest** (khớp spec §2.4 "Redis 7" và ElastiCache 7.1), **không** dùng `redis:8.2.2-alpine` của compose (`docker-compose.yml:20`); **không sửa docker-compose.yml**. Local không TLS/auth (`redis://`), schema chạy bằng cùng migration Job như AWS.

**N.11 `starter.yml`.** Trigger `push` + `pull_request` mọi nhánh (dòng 2-4), `permissions: contents: read` (5-6), không cloud credential; chạy compose up → verifier tests → `make test-backend` → MCP tests → HTTP smoke → down `if: always()` (20-38). `actions/checkout` pin SHA `3d3c42e5…` (v7.0.1, dòng 17), image node pin digest (dòng 28). **Không xung đột** với `iac.yml` (tên workflow/job khác); lưu ý cả hai chạy trên PR (build image 2 lần); `id-token: write` chỉ cấp ở job cần trong `iac.yml`; giữ nguyên `starter.yml` làm baseline.

**N.12 Giới hạn upload 10 MB.** api `max_upload_bytes = 10 MiB` (`config.py:65`); middleware chặn body > 10 MiB + 64 KB → 413 (`api/app/core/upload_limit.py:20-43`); handler kiểm lại (`documents.py:22-26`); web proxy 11 MB (`web/app/api/proxy/route.ts:8`). **ALB không giới hạn kích thước body** → giới hạn nằm hoàn toàn ở app, không cần annotation body size. ALB idle timeout mặc định 60 s đủ cho upload/chat fixture; web proxy chờ tới 90 s (`route.ts:25`) → khi chuyển LLM real đặt `idle_timeout.timeout_seconds` ≈ 90-120. Target group health check: api `/readyz`, web `/api/health`.

### (A) Sửa code app
**Không có.** Contract Day 1 giữ nguyên; worker probe dùng `arq --check` với cấu hình hiện tại (N.8).

### (B) Chỉ cấu hình trong Helm
1. ConfigMap: `RAG_MODE`/`LLM_PROVIDER`/`EMBEDDING_PROVIDER=fixture`, `EMBEDDING_DIM=1024`, `EMBEDDING_REVISION`, `LOG_LEVEL`; web `API_INTERNAL_URL`.
2. Secrets Store CSI: `SecretProviderClass` (2 ARN từ output core `db_secret_arn`/`redis_secret_arn`, `jmesPath` → `database_url`, `redis_url`) + `secretObjects` → K8s Secret; driver `syncSecret.enabled=true`; api/worker/Job mount CSI; SA `insighthub` (IRSA).
3. Migration Job — hook `pre-install,pre-upgrade`, image pgvector (psql), SQL từ `--set-file` `infra/db/init.sql` → ConfigMap; `SecretProviderClass` hook weight thấp hơn.
4. securityContext: `runAsNonRoot`, `runAsUser/runAsGroup/fsGroup 1001`, `readOnlyRootFilesystem` + `emptyDir` (`/tmp`, `/app/.next/cache`), drop ALL, seccomp RuntimeDefault.
5. Probe: api `/healthz` / `/readyz` / startupProbe; web `/api/health`; worker exec `arq --check`, period ≥ 60 s.
6. Ingress ALB: `/healthz`, `/readyz`, `/documents`, `/chat` → api; `/` → web; không `/metrics`; ACM cert, listen 443, ssl-redirect, healthcheck-path theo service, idle timeout.
7. HPA api: `resources.requests` + metrics-server (chưa có trên EKS — mục L).
8. Values local: StatefulSet `pgvector/pgvector:0.8.2-pg16@sha256:00ba…` + `redis:7.x@sha256:…`; `redis://`, không sslmode. Values AWS: **không StatefulSet**.
9. Không PVC dùng chung.

### (C) Ngoài app, bắt buộc — Terraform `infra/modules/data` (✅ đã làm 2026-09-25)
- **C1** ✅ secret `db-credentials` thêm `database_url = "postgresql://<db_username>:${urlencode(password)}@<address>:5432/insighthub?sslmode=require"`. `db_username` thêm validation `^[A-Za-z][A-Za-z0-9_]{0,62}$` (quy tắc master username RDS) → nhúng nguyên văn an toàn.
- **C2** ✅ `random_password.redis_auth`: `length = 32`, `override_special = "-_"` (chỉ `[A-Za-z0-9-_]`, ~192 bit); secret `redis-credentials` thêm `redis_url = "rediss://:<token>@<primary_endpoint>:6379/0"`. Kiểm 2000 token ngẫu nhiên từ bộ ký tự này → arq `from_dsn` parse đúng password/host/port/ssl.

## O. Bổ sung thiết kế (2026-09-25 — refactor core/platform, chưa apply)

| # | Hạng mục | Trạng thái |
|---|---|---|
| O.1 | Tách **core** (`infra/`, key `insighthub/core/terraform.tfstate`) / **platform** (`infra/platform/`, key `insighthub/platform/terraform.tfstate`, đọc core qua `terraform_remote_state`) / bootstrap (giữ vị trí). Core không còn provider kubernetes. Thứ tự apply bootstrap → core → platform → Helm; teardown Helm → chờ ALB xóa → Route53 → platform destroy → core destroy (SPEC Mục 8) | ✅ code xong; core plan thật **50 to add** (2026-09-29); platform chỉ validate (plan cần cluster sống) |
| O.2 | Modules `infra/modules/{network,eks,data,ecr}` | ✅ code xong |
| O.3 | `terraform.tfvars.example` cho core và platform (giá trị giả) | ✅ |
| O.4 | EKS `API_AND_CONFIG_MAP` + access entry cho `gh_apply` và `operator_principal_arns`, `bootstrap_cluster_creator_admin_permissions = false`; `admin_cidrs` thay `operator_cidrs` | ✅ code xong |
| O.5 | RDS `aws_db_parameter_group` `rds.force_ssl = 1` + Conftest rule kiểm trên plan | ✅ code + rule; ❌ **audit app `sslmode=require`** chưa làm |
| O.6 | Bootstrap: environment `infra-plan`/`production`, state `gh_plan` chỉ đọc (lock Get/Put/Delete), KMS key + `plans/` cho saved plan, quyền `gh_apply` (access entry, UpdateClusterConfig/DescribeUpdate chỉ cluster lab, ECR push, parameter group) | ✅ code xong, chưa apply; ❌ tạo 2 GitHub Environment + required reviewer trên repo |
| O.7 | Pin mọi GitHub Action theo **commit SHA** (không tag) + **checksum** cho tool tải về (terraform, tflint, checkov, conftest 0.70.x, infracost, helm, kubectl) | ❌ chưa viết workflow |
| O.8 | Apply bằng **saved plan** + so **checksum** sau environment approval (plan job → S3 `plans/` SSE-KMS → apply job tải, so sha256, apply, xóa) — không upload plan làm artifact | ⚠️ thiết kế (SPEC Mục 12), chưa viết workflow |
| O.9 | Pipeline có: app tests, image build (push ECR bằng `gh_apply`), **source binding** (`source-manifest.json` + chart archive **deterministic** làm `deployment` artifact), Infracost PR comment, AI giải thích plan **đã sanitize** (bỏ giá trị sensitive/ARN account trước khi gửi) | ❌ |
| O.10 | PR từ fork **không có cloud identity** (không environment, không `id-token: write`, không secret) — chỉ chạy fmt/validate/lint/checkov/conftest trên fixture | ❌ chưa viết workflow (trust `gh_plan` đã chặn bằng `sub` environment) |
| O.11 | Tạm thêm IP runner vào `public_access_cidrs` trong job apply rồi khôi phục (`if: always()`), không `ignore_changes`; platform plan -out → in log → apply đúng file (trade-off: không human review riêng cho platform) | ⚠️ thiết kế (SPEC Mục 12) |
| O.12 | Helm chart: probes, resources, securityContext, HPA, Ingress (ACM + domain có sẵn), Secrets Store CSI (`SecretProviderClass`), migration Job; values `local`/`dev` — local chạy Postgres/Redis **trong cluster**, AWS dùng RDS/ElastiCache (**không StatefulSet** trên AWS) | ✅ code xong — 2 chart (SPEC Mục 13). Ràng buộc "không StatefulSet trên AWS" là **bất biến theo cấu trúc**: chart app không có template StatefulSet nào. Ingress + SecretProviderClass mới chỉ `helm template` + checkov (bật ở `values-dev`), **chưa chạy thật** vì cần EKS + ALB Controller + CSI driver |
| O.13 | Test local bằng **kind riêng** (không dùng cluster lab chung) + kiểm UI trên trình duyệt | ✅ xong (2026-09-29) — kind `insighthub-lab` (context `kind-insighthub-lab`, tách hẳn khỏi cluster EKS), ns `insighthub-local`; `helm upgrade` 2 chart, 5/5 pod Running; smoke curl PASS toàn bộ; UI kiểm trên Edge qua `kubectl port-forward` (web 3000, api 8000) — upload + chat chạy được |
| O.14 | Evidence: image digest, test **allow/deny quyền** (IRSA đọc được 2 secret, bị từ chối secret khác; gh_plan không ghi được state), tag inventory, **fresh plan sau apply không thay đổi**, runbook, requirement matrix, PR description | ❌ |
| O.15 | **ACM cert + DNS**: cert `*.do2603.click` là tài nguyên dùng chung có sẵn → Terraform chỉ `data` tham chiếu + output `certificate_arn`, không tạo/không xóa; record Route53 `insighthub-lamduy.do2603.click` tạo bằng CLI ở job deploy, xóa ở bước 4 teardown | ✅ code + tài liệu xong (SPEC Mục 2 "Load Balancing", Mục 8 bước 4). Plan core resolve ra ARN cert thật. Record Route53 chưa tạo (chưa deploy EKS) |
| O.16 | **Pin `eks_version`** (`var.eks_version`, default `1.36`) thay vì để AWS chọn default — default đổi theo thời gian nên plan không deterministic | ✅ xong. Kéo theo finding mới CKV_AWS_339 (dương tính giả, danh sách version hardcode của checkov 3.3.19 chỉ tới 1.35) → `#checkov:skip` kèm lý do, SPEC Mục 10 |


## P. Lượt 2026-09-29 — ACM/DNS, ServiceAccount, `eks_version`, deploy local

### P.1 Thay đổi code

| # | Thay đổi | File |
|---|---|---|
| 1 | `data "aws_acm_certificate" "app"` (`*.do2603.click`, `ISSUED`, `most_recent`) + output `certificate_arn` | `infra/main.tf`, `infra/outputs.tf` |
| 2 | ServiceAccount `insighthub` chuyển từ chart app → chart `insighthub-local-deps`; bỏ hook `pre-install/hook-weight -20`; `serviceAccount.create=false` ở cả 3 values; guard `fail` trong `insighthub.serviceAccountName` | `infra/helm/insighthub/templates/{serviceaccount.yaml (xoá),_helpers.tpl,NOTES.txt}`, `infra/helm/insighthub/values*.yaml`, `infra/helm/insighthub-local-deps/{values.yaml,templates/serviceaccount.yaml,templates/NOTES.txt}` |
| 3 | `var.eks_version` (default `1.36`) → `aws_eks_cluster.version` | `infra/variables.tf`, `infra/main.tf`, `infra/modules/eks/{variables,main}.tf` |
| 4 | `#checkov:skip=CKV_AWS_339` kèm lý do (hệ quả của #3) | `infra/modules/eks/main.tf` |

### P.2 Kết quả chạy (tất cả PASS, không hạ assertion nào)

| Lệnh | Kết quả |
|---|---|
| `terraform fmt -check -recursive infra/` | no diff |
| `terraform validate` × 3 root (core, platform, bootstrap) | 3/3 Success |
| `tflint --recursive` (từ `infra/`) | exit 0, 0 error, 0 warning |
| `checkov -d infra/` | 687 passed, 0 failed, 56 skipped, **exit 0** |
| `terraform -chdir=infra plan -out="$PLAN_DIR/core.tfplan"` | 50 to add; output `certificate_arn` resolve ra ARN cert thật |
| `conftest test --policy policy/terraform "$PLAN_DIR/core.tfplan.json"` | 19 tests, 0 failures |
| `pytest tests/milestones/day3` | 2 passed |
| `helm lint` × 4 (app default/local/dev + local-deps) | 0 chart failed |
| `helm template` × 3 + assert | app render **0** object `ServiceAccount`; local-deps render SA `insighthub`; pod spec vẫn `serviceAccountName: insighthub`; `--set serviceAccount.create=true` → FAIL đúng thông báo |
| `bash scripts/package-chart.sh --verify` | DETERMINISTIC OK |
| `find infra … *tfplan*/*.tfstate*` | rỗng (ràng buộc mục K) |
| `helm upgrade` 2 chart trên kind + smoke curl | 5/5 pod Running; `/healthz` 200, `/readyz` 200, `POST /documents` 202, `ready` <2s, `POST /chat` 200 kèm `sources`; UI trên Edge OK |

`$PLAN_DIR = /tmp/insighthub-plans` (ngoài repo, đúng mục K).

### P.3 Ghi chú vận hành phát hiện trong lượt này

- **Nâng cấp chart trên cluster đã cài bản cũ**: SA `insighthub` bản cũ do hook
  của release app tạo nên **không có** annotation `meta.helm.sh/release-name`
  → `helm upgrade insighthub-deps` báo `invalid ownership metadata` và dừng.
  Phải `kubectl -n insighthub-local delete sa insighthub` trước rồi mới
  upgrade. An toàn vì mọi pod đều `automountServiceAccountToken: false`.
  Cài mới hoàn toàn thì không gặp.
- **`kubectl port-forward` trên WSL2**: `KUBECTL_PORT_FORWARD_WEBSOCKETS=false`
  vẫn có tác dụng, port-forward **không** sập trong suốt phiên kiểm UI.
  Lỗi `bind: address already in use` gặp lúc đầu là do truyền
  `--address 127.0.0.1,0.0.0.0` (0.0.0.0 đã bao 127.0.0.1 nên tự đụng nhau),
  **không** phải bug websocket — bỏ cờ `--address` là chạy bình thường. Không
  cần đổi sang NodePort.
- **`data` source ACM làm `plan` core phụ thuộc AWS thật**: cert bị xóa hoặc
  hết trạng thái `ISSUED` thì `terraform plan` lỗi ngay. Đây là fail-fast có
  chủ đích (không apply ra Ingress thiếu cert), nhưng job plan trong CI vì thế
  **bắt buộc có quyền `acm:ListCertificates` + `acm:DescribeCertificate`** —
  kiểm lại policy `gh_plan` khi viết `iac.yml` (`ReadOnlyAccess` đã phủ).

## Q. Lượt AWS 2 (2026-09-29) — apply thật, smoke HTTPS, teardown

### Q.1 Bối cảnh: apply từ local, KHÔNG qua CI

Ghi trung thực để reviewer không hiểu nhầm: hạ tầng lượt này **apply bằng IAM
user `DE000215` từ máy local**, không qua GitHub Actions.

Lý do tại thời điểm chạy (khoảng 13:50–15:10 +07): GitHub Actions bị chặn ở cấp
tài khoản vì vấn đề thanh toán, mọi job fail sau 6 giây trước cả khi được cấp
runner. Đợi thì hết giờ lab, nên chọn apply local và ghi lại lý do thay vì bỏ
trống MH3/MH6/MH10/MH11/MH14.

**Cập nhật ~15:15 (+07)**: chủ repo đã gỡ chặn billing, pipeline chạy lại được
(Q.6). Nhưng phần hạ tầng AWS thì **vẫn là apply từ local** — không sửa lại mô
tả này cho đẹp, vì đó là điều đã thực sự xảy ra. Nếu cần chứng minh apply qua
CI thì phải chạy thêm một lượt lab nữa qua `workflow_dispatch`, và lượt đó
chưa chạy. Lý do này cũng ghi trong `evidence/day3-lab2-manifest.json` trường
`apply_method_reason`.

### Q.2 Trình tự đã chạy

bootstrap (12 resource) → core (**49 to add**) → platform (3) → 4 add-on →
push 3 image lên ECR → Helm app → Route53 → smoke HTTPS → fresh plan →
teardown 8 bước.

Add-on cài đúng thứ tự phụ thuộc: metrics-server, Secrets Store CSI Driver +
ASCP, rồi AWS Load Balancer Controller (`serviceAccount.create=false`, dùng SA
do root platform tạo, `vpcId` = output core).

### Q.3 Bốn phát hiện thật trong lượt này

**Q.3.1 — OIDC provider đã thuộc về học viên khác.** `terraform apply` bootstrap
trả `EntityAlreadyExists`. Import rồi apply như comment cũ hướng dẫn thì plan
cho thấy sẽ **ghi đè tag `owner=DO-NGOC-VINH`, `lab_expiry`** của họ. Đã chuyển
sang `data` source — cùng nguyên tắc đã áp cho ACM cert. Xem J.6.

**Q.3.2 — Drift vĩnh viễn ở `rds.force_ssl`.** Fresh plan ngay sau apply ra
`1 to change`: đây là parameter **static**, AWS luôn lưu `apply_method =
pending-reboot`, còn provider mặc định gửi `immediate`. Khai tường minh
`apply_method = "pending-reboot"` → plan sạch. Giá trị vẫn có hiệu lực
(`ParameterApplyStatus = in-sync`), đã kiểm chứng từ pod trong VPC:
`sslmode=disable` bị RDS từ chối (`no pg_hba.conf entry ... no encryption`),
`sslmode=require` vào được với TLSv1.3 — `evidence/day3-rds-tls-proof.txt`.
**Nếu không chạy fresh plan sau apply thì không bao giờ phát hiện ra.**

**Q.3.3 — Chart ASCP bundle sẵn CSI driver làm subchart.** Cài driver thành
release Helm riêng gây xung đột ownership (`invalid ownership metadata` trên SA
`secrets-store-csi-driver`). Cách đúng: chỉ cài ASCP, bật subchart bằng
`--set 'secrets-store-csi-driver.syncSecret.enabled=true'`.

**Q.3.4 — Endpoint public không có xác thực.** Trong lúc kiểm UI, có tài liệu
lạ xuất hiện trong `GET /documents` và bị `/chat` trích làm `sources`. Hoá ra
là chủ repo tự upload thử, nhưng nó phơi ra đúng bản chất: ALB + Ingress không
kèm lớp xác thực nào, ai biết URL đều upload/đọc/chat được. Xác thực **không
thuộc phạm vi Day 3** (spec không yêu cầu) nên không thêm vào; cách xử lý là
xoá tài liệu bằng `DELETE /documents/{id}` (chunk tự xoá theo
`ON DELETE CASCADE`) và teardown sớm. **Ghi lại đây như một ràng buộc phải giải
quyết trước khi đưa kiến trúc này đi xa hơn môi trường lab.**

### Q.4 Kết quả đo được

| Hạng mục | Kết quả |
|---|---|
| Fresh plan sau apply (core + platform) | **No changes**, `-detailed-exitcode = 0` cả hai |
| Smoke HTTPS | `/healthz` 200 · `POST /documents` **202 / 0.21s** · `ready` **1.7s** · `POST /chat` 200 + `sources` |
| IRSA runtime | pod có `AWS_ROLE_ARN=...insighthub-app-role`, Secret do CSI sync 2 key |
| Tagging | 29 ARN, đủ 8 tag |
| Image | 3 image ECR kèm digest (`evidence/day3-image-digests.txt`); deploy bằng **digest**, không chỉ tag |
| Teardown | 8 bước SPEC Mục 8, ALB về 0 trước khi destroy, ACM cert còn nguyên `ISSUED` |
| Chi phí thực | hạ tầng sống ~1.2h × $0.2154/h ≈ **$0.26** |

### Q.5 Việc CHƯA làm (không che)

- **MH9 pipeline xanh** — chặn billing cấp tài khoản, xem mục A.
- **`evidence/day3.json` phải để `mode: fixture`** thay vì `real`: artifact
  `verification-source` (chứa `source_sha256`/`artifact_sha256`) do CI sinh, mà
  CI chưa chạy được. Ràng buộc source freeze ở mục K vẫn nguyên giá trị — khi
  billing thông, chạy CI trên commit đã đóng băng rồi mới tạo `day3.json`.
- **Infracost PR comment** — job `cost-estimate` chưa chạy; dự toán local vẫn có
  ($157.19/tháng, SPEC Mục 8).
- **Mở rộng bộ Conftest Rego** (Should-have) — giữ nguyên 19 rule.
