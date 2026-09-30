# Day 5 AI Prompts

Bốn prompt dưới đây là **nguyên văn** những gì tôi đã gửi trong phiên làm Day 5 (30/09/2026). Chép trực
tiếp từ transcript của phiên (chỉ bỏ thẻ bao `<pasted_content>` của giao diện), không chỉnh cho đẹp,
không chép từ prompt pack của giảng viên. Phiên này bắt đầu bằng `/clear` sau khi xong Day 4, nên đây là
toàn bộ các prompt thiết kế của Day 5; các prompt ngắn còn lại chỉ là báo trạng thái ("Slack đã Verified",
"Loom đã quay"...). Model và phiên bản lấy từ chính phiên (`claude --version` = 2.1.285; model là Sonnet 5.5).
Giờ ghi theo mốc trong repo/log: prompt 1 lấy từ dấu thời gian của lệnh đầu tiên, prompt 2 và 3 từ giờ
commit ngay sau đó, prompt 4 suy ra từ `chatops-audit.log` (lệnh `confirm` có backtick bị bot trả help lúc
15:39:45, bot chạy đúng lại từ 15:45:30), nên ghi "khoảng".

---

## Prompt 1 - Tạo branch, khảo sát verifier và skeleton, trình bày checklist rồi mới ghi file

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `Running-Project-Specification-Student.md` §0, 4, 9; `scripts/verify.py` (`REQUIRED_TESTS` 36-42, `run_tests` 367-396, `audit_events` 665-676, `day5` 679-696); `scripts/VERIFICATION_CONTRACT.md`; `chatops-bot/` skeleton; `infra/DAY4-CHECKLIST.md`; `.mcp.json`. Kết quả: bản nháp checklist trình trong chat, chưa ghi file.
**Time**: 30/09/2026, khoảng 14:17 (+07)

**Prompt**:
````
Bắt đầu Day 5 (spec §9: ChatOps Bot & Incident Response). Hạn nộp: HẾT HÔM NAY. Chỉ làm Must-have MH1-MH11, bỏ Should/Nice-have trừ khi verifier bắt buộc. Tái sử dụng cluster kind insighthub-lab và Prometheus/K8s MCP từ Day 4 (đang chạy, KHÔNG được làm hỏng — Day 4 cần Prometheus sống tới 02:05 ngày 01/10).

Tạo branch day5-chatops từ day4-observability.

Khảo sát và lập infra/DAY5-CHECKLIST.md (CHỈ ĐỌC + viết 1 file, KHÔNG code gì khác).

Đọc: spec §0, §4, §9 (toàn bộ); docs/Guide_Local_AWS_Cost_DO2603.md; docs/lab-guides/ (file Day 5 nếu có); scripts/VERIFICATION_CONTRACT.md; scripts/verify.py phần day5 + scripts/verify-day-5.sh; chatops-bot/ (skeleton có sẵn); tests/milestones/ (xem có day5 không); infra/DAY4-CHECKLIST.md (để biết MCP, Prometheus, RBAC mcp-readonly đang cấu hình thế nào).

Từ CODE verifier, trả lời chính xác (trích dòng code):
1. verify.py day5 kiểm đúng những gì? Liệt kê từng assertion.
2. REQUIRED_TESTS[5] gồm những test tên gì, đặt ở đâu (tests/milestones/day5/ hay chatops-bot/tests/)?
3. Format audit JSON (run_id, events: timestamp/event_id/action/decision/user/test_run_id) — verifier đòi decision nào bắt buộc xuất hiện (denied, approval_required)?
4. INSIGHTHUB_VERIFY_RUN_ID và INSIGHTHUB_VERIFY_OBSERVATIONS dùng thế nào?
5. Verifier kiểm HTTP signature + health bằng cách nào? Cần INSIGHTHUB_BOT_URL, INSIGHTHUB_BOT_TRANSPORT không?
6. evidence/day5.json cần artifact role nào (permissions, audit...) và format?

Từ CODE skeleton chatops-bot/:
7. Đã có sẵn gì, thiếu gì cho MH1-MH10?
8. Cách gọi MCP backend từ bot (reuse Prometheus + K8s MCP của Day 2/4) — gọi trực tiếp Prometheus API hay qua MCP client? Spec MH7 đòi "Audit log shows MCP calls".

Checklist phải có: MH1-MH11 + 10 dòng Acceptance §9.5 + NFR §9.3, mỗi dòng ghi nguồn và trạng thái; 3 intent và nguồn dữ liệu từng intent; thiết kế permission 3-tier (read auto / write ask-confirm / destructive token); những thứ CẦN TÔI LÀM TAY (Slack App bot token + signing secret + scopes + event URL; ngrok authtoken; Loom screencast); rủi ro (ACK <3s, durable queue, replay 5 phút, bot reply chính nó, RAM máy 2 vCPU đang gánh cả stack Day 4); ước lượng thời gian từng phần.

Trình bày checklist cho tôi duyệt TRƯỚC KHI ghi file. Không code ở lượt này.
````

**Why it worked**:
- Đặt ràng buộc lớn nhất ngay đầu (không làm hỏng Prometheus/cluster Day 4, hạn hôm nay, chỉ MH1-MH11), nên agent không đề xuất dựng lại hạ tầng hay làm Should/Nice-have.
- 8 câu hỏi buộc **trích dòng code** thay vì tóm tắt spec. Nhờ đó có các sự thật kiểm chứng được và đổi thiết kế: test của verifier nằm ở `tests/milestones/day5/` chứ không phải `chatops-bot/tests/`; pytest chạy với `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1` nên test phải đồng bộ; verifier đòi cả `denied` lẫn `approval_required`; skeleton có schema audit sai (`ts/tool/approved`).
- "Trình bày trước khi ghi file, không code" tạo gate review. Bản nháp còn bộc lộ hai rủi ro tôi chưa nghĩ tới: `kubectl` mặc định đang trỏ EKS đã xoá, và mọi commit trong `chatops-bot/`, `infra/`, `tests/` đều làm lệch `source_sha256` của Day 4.

**What I changed**:
- Duyệt bản nháp với một chỉnh sửa (prompt 2), không sửa checklist trực tiếp.

---

## Prompt 2 - Duyệt checklist, chốt 3 quyết định thiết kế, giao thứ tự làm theo bảng rủi ro

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: bản nháp checklist ở prompt 1 và câu hỏi (a)(b)(c) của agent. Kết quả: `infra/DAY5-CHECKLIST.md` (commit `8ab6057`), rồi `chatops-bot/app/{security,audit,permissions,store,intents,service,factory}.py`, `tests/milestones/day5/test_chatops.py`.
**Time**: 30/09/2026, khoảng 14:30 (+07), suy ra từ giờ commit `8ab6057`

**Prompt**:
````
Duyệt, chỉnh 1 điểm:
- Lệnh scale: cho N từ 1 đến 5 (Acceptance §9.5 dùng đúng "scale api to 5" và kỳ vọng bot hỏi confirm với token). N ngoài 1-5 thì denied.

Chốt:
(a) Đồng ý cả 3: SQLite WAL cho queue/dedup/retry (ghi deviation so với Redis/ARQ), tự viết signature + httpx, test thật ở tests/milestones/day5/ và bản mỏng ở chatops-bot/tests/.
(b) Scale thực thi bằng --dry-run=server, ghi rõ vào deviation (node 99% CPU requests).
(c) Giữ nguyên infra/DAY5-CHECKLIST.md.

Kiểm .gitignore có chặn chatops-bot/.env chưa, chưa có thì thêm TRƯỚC khi tôi tạo file đó.

Ghi checklist rồi LÀM LUÔN theo thứ tự ưu tiên trong bảng rủi ro: MH3 (signature) + MH8 (audit) + MH9 (permission) + MH10 (tests) trước, không cần Slack thật. Báo ngắn sau mỗi phần. Khi tới phần cần Slack live thì dừng báo tôi.
````

**Why it worked**:
- Mỗi quyết định có **lý do một dòng** (deviation so với Redis/ARQ, node 99% CPU requests), nên agent ghi thẳng vào checklist thay vì hỏi lại.
- Chỉnh N thành 1-5 dựa vào Acceptance §9.5 ("scale api to 5") thay vì con số agent tự chọn; nếu để 1-3, dòng acceptance số 8 không thể chạy.
- Thứ tự "signature, audit, permission, tests trước, không cần Slack" cho phép làm và kiểm chứng toàn bộ phần bảo mật khi tôi chưa có Slack App. Agent còn tự kiểm test bằng 5 đột biến (nới replay window, bỏ so sánh chữ ký, bỏ ràng buộc user, bỏ dedup, bỏ giới hạn N): cả 5 làm test đỏ.
- "Dừng khi tới phần cần Slack live" giữ ranh giới rõ giữa việc agent làm được và việc chỉ tôi làm được (tạo Slack App, authtoken ngrok, Loom).

**What I changed**:
- Không sửa code do agent viết ở bước này. Phát hiện ở bước sau: agent tự sửa lỗi `readonly_kubeconfig` rỗng khiến `kubernetes-mcp-server` rơi về context mặc định (EKS đã xoá); mặc định giờ luôn là kubeconfig read-only.

---

## Prompt 3 - Commit WIP, sửa intent ingest theo nghĩa "hôm nay", cài ngrok có kiểm checksum

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `chatops-bot/app/service.py` (`_on_ingest`), Prometheus MCP thật, apt repo `ngrok-agent.s3.amazonaws.com`. Kết quả: commit `1b2a13a`, câu trả lời ingest "ready tăng +176 (53 → 229)", `~/.local/bin/ngrok` 3.39.11.
**Time**: 30/09/2026, khoảng 14:44 (+07), suy ra từ giờ commit `1b2a13a`

**Prompt**:
````
Trước phần live:
1. Commit WIP toàn bộ code Day 5 đang untracked, push lên day5-chatops.
2. Sửa intent ingest: trả số tài liệu ready TĂNG trong hôm nay (giá trị hiện tại trừ giá trị lúc 00:00 giờ máy +07, qua Prometheus MCP), kèm tổng số. Test vẫn phải xanh.
3. Cài ngrok vào ~/.local/bin (pin version, kiểm checksum). Không chạy config authtoken, tôi tự làm.
4. SLACK_BOT_USER_ID: sau khi tôi tạo .env, bạn tự lấy bằng auth.test từ bot token rồi ghi vào .env (không in token ra).
Xong thì báo tôi, tôi làm tiếp phần của tôi.
````

**Why it worked**:
- Đánh số 4 việc độc lập và nói rõ ranh giới ("không chạy config authtoken, tôi tự làm", "không in token ra"): agent không đụng vào secret và chỉ gọi `auth.test` khi `.env` đã có.
- "Pin version, kiểm checksum" buộc agent tìm nguồn xác minh thật. ngrok không công bố checksum cho bản `.tgz`, nên agent chuyển sang apt repo chính thức: chữ ký GPG của `Release` hợp lệ, hash `Packages` khớp, `sha256sum -c` của `.deb` OK, binary trong `.deb` trùng bản `.tgz`. Agent cũng nói rõ điểm tin cậy ban đầu là public key tải từ chính ngrok.
- Định nghĩa "hôm nay" cụ thể (trừ giá trị lúc 00:00 +07, qua MCP) tạo ra `offset <giây>s` trên Prometheus, có test cho biên nửa đêm UTC↔+07 và trường hợp thiếu baseline.

**What I changed**:
- Chưa sửa gì trong code của agent. Tôi tự tạo Slack App, cấu hình authtoken ngrok và `chatops-bot/.env`.

---

## Prompt 4 - Sửa lỗi lệnh confirm bị dính dấu định dạng của Slack, kèm test tái hiện

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `chatops-bot/app/intents.py` (`normalize`), `chatops-bot/chatops-audit.log` (`intent.help` sau `k8s.scale approval_required`), `tests/milestones/day5/test_chatops.py`. Kết quả: `_SLACK_FORMATTING` trong `normalize`, 9 test mới (chạy ở cả hai thư mục test nên tổng 72 pass).
**Time**: 30/09/2026, khoảng 15:41 (+07), suy ra từ audit log

**Prompt**:
````
Bug: khi người dùng copy lệnh từ tin của bot, Slack gửi kèm dấu backtick (`confirm C55DB51D`) nên intents.normalize không khớp regex confirm, bot trả help. Sửa normalize: bỏ ký tự định dạng Slack (backtick, *, _, ~) trước khi parse. Thêm test cho trường hợp "`confirm ABC12345`". Restart bot, giữ nguyên tunnel ngrok. Báo tôi khi xong.
````

**Why it worked**:
- Prompt có **triệu chứng, nguyên nhân giả định, chỗ sửa và ký tự cụ thể**, nên agent sửa đúng một hàm và không đụng vào luồng chữ ký hay approval.
- Yêu cầu "thêm test cho `` `confirm ABC12345` ``" cho một test tái hiện. Agent còn bỏ bản sửa ra để xác nhận 9 test đỏ, rồi khôi phục và kiểm tra lại (72 pass).
- "Restart bot, giữ nguyên tunnel ngrok" tránh bắt tôi dán lại Request URL vào Slack; agent chỉ khởi động lại uvicorn và kiểm `/healthz` qua URL public.

**What I changed**:
- Agent nêu một tác dụng phụ: bỏ cả `_` nghĩa là tên có dấu gạch dưới mất dấu đó khi parse. Các tên hiện tại (token hex, `insighthub-api`) không bị ảnh hưởng nên tôi giữ nguyên.
