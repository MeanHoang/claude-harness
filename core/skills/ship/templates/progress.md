<!-- Copy file này → thay {{...}} → dùng làm .claude/ship/<slug>/progress.md
     LUẬT: file này là PROJECTION của plan.html §4, KHÔNG phải nhật ký.
       · Checklist SINH TỪ plan.html — không tự thêm dòng không có trong plan
       · REWRITE tại chỗ, không append. Xong 1 item → tick nó, không viết thêm đoạn văn
       · ĐÚNG MỘT dòng `> **NOW:**` trong cả file
       · Kiến thức (quyết định, bài học, nợ) → decisions.md, KHÔNG để ở đây
       · Trần mềm ~150 dòng. Vượt = đang viết nhầm thứ vào đây
     Xoá nguyên comment này sau khi điền. -->
<!-- state
slug: {{task-slug}}
branch: {{feature/task-slug}}
kind: {{feature|bugfix}}
mode: {{SHIP|CONTINUE|STABILIZE}}
step: {{0-7}}
gate: {{none|1|2|3|ship-out}}
awaiting: {{none|user}}
plan: {{plan.html | none — STABILIZE không có plan}}
note: {{--note của anh, nguyên văn | none}}
-->

# Ship: {{Tên task}}

- **Task**: {{notion-url}}
- **Plan**: `plan.html` — checklist dưới đây sinh từ §4 của nó
- **Quyết định & bài học**: `decisions.md`

> **NOW:** {{một dòng duy nhất — đang ở đâu, chờ gì. Session sau đọc dòng này trước tiên}}

---

## Yêu cầu đã chốt (Gate 1)

{{3-6 gạch đầu dòng — cái user đã đồng ý ở Step 1. Chốt xong thì không sửa nữa.}}

---

## Checklist

Ký hiệu phase: ⬜ chưa làm · 🔄 đang code · 👀 đã báo cáo, chờ OK · ✅ đã commit

### ⬜ Phase 1 — {{tên phase, theo surface}}

`Pattern:` {{file.js:line}} — {{tên hàm/component}}

- [ ] {{file cần sửa}} — {{sửa gì cụ thể}}
- [ ] {{file cần sửa}} — {{sửa gì cụ thể}}
- [ ] eslint sạch trên diff phase
- [ ] review sạch context (`code-reviewer` + `/code-review`) — findings đã xử lý
- [ ] Verify: {{cách kiểm chứng phase này xong, lấy từ dòng Verify của plan}}
- [ ] Báo cáo Gate 3 → user OK → commit

### ⬜ Phase 2 — {{...}}

`Pattern:` {{file.js:line}} — {{...}}

- [ ] {{...}}
- [ ] eslint sạch trên diff phase
- [ ] review sạch context (`code-reviewer` + `/code-review`) — findings đã xử lý
- [ ] Verify: {{...}}
- [ ] Báo cáo Gate 3 → user OK → commit

---

## Finalize (Step 5)

- [ ] Master-drift check
- [ ] `/review-v2` toàn branch
- [ ] `/impact`
- [ ] `/translate` (nếu có label mới)
- [ ] `/test-checklist`
- [ ] `/mr`
- [ ] `/update-handle`

---

## Đang chờ user

{{Để trống nếu không chờ. Nếu chờ: chờ ở gate nào, câu hỏi là gì, hỏi lúc nào.
Trả lời xong → XOÁ khỏi mục này, đừng để lịch sử tồn.}}

---

## Việc phát sinh ngoài plan

{{Chỉ ghi thứ user đã đồng ý thêm vào scope. Mỗi dòng 1 checkbox + ngày + lý do.
Nếu nhiều hơn ~5 dòng → plan đã lệch thực tế, quay lại Gate 2 sửa plan.html
rồi sinh lại checklist, đừng để danh sách này thay thế plan.}}

- [ ] {{ngày}} — {{việc}} ({{user chốt gì}})
