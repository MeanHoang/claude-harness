---
name: surface-audit
description: "Bản đồ MỌI surface người dùng nhìn thấy + quy trình audit coverage. Dùng BẮT BUỘC khi: lên plan feature (/plan, /ship Gate 2), user nói 'cập nhật ở mọi surface', 'check surface', 'sót surface nào không', review/impact một feature storefront, hoặc sau khi code xong một feature đụng UI khách hàng. Walk từng dòng checklist, đánh dấu touched / not-affected / MISSED — không được kết luận 'đủ surface' nếu chưa đi hết bảng."
---

# Surface audit — bản đồ surface & audit coverage

**Vì sao tồn tại**: một feature từng sót nguyên một surface, vì surface đó có HELPER RIÊNG
trùng tên với helper của surface khác — nhìn tên tưởng đã sửa rồi. Phát hiện ở UAT chứ không
phải lúc plan. Skill này là checklist chống sót: đi từng dòng, không suy đoán.

## Quy trình audit (khi plan hoặc khi user yêu cầu "update mọi surface")

1. Xác định feature đụng GÌ: luồng nào, dữ liệu nào, kênh nào (kể cả kênh không phải UI).
2. Đi qua **từng nhóm** dưới đây theo thứ tự. Với mỗi surface trả lời:
   - `TOUCHED` — cần sửa (ghi file:line dự kiến)
   - `N/A` — không render/không liên quan dữ liệu này (ghi 1 câu VÌ SAO)
   - `EXCLUDED` — chủ đích bỏ qua (vd V2 legacy) — phải nêu trong plan cho user chốt
3. Surface nào "có copy helper riêng" (⚠️ bên dưới) phải mở code RIÊNG của nó kiểm tra
   — đừng suy từ surface cùng tên.
4. Kết quả = bảng coverage dán vào plan/report. Thiếu bảng = chưa audit.

## Your surface inventory — fill this in

The audit *method* above is the reusable part. The inventory below is yours to write: it is a map
of your own product, and it is exactly the knowledge you should not publish.

For each surface group, one row per surface:

| Surface | Real code path | ⚠️ Gotcha |
|---|---|---|
| {{surface name}} | `{{path/to/code}}` | {{what bites people here}} |

Suggested groups (rename to fit your product):

1. Storefront widgets (one row per generation still live)
2. Theme blocks / embeds
3. Customer-account extensions  ← in most products this is the group people forget
4. Checkout extensions
5. POS / admin extensions / server-side functions
6. Admin app pages
7. Non-UI channels (API, webhooks, exports, emails)

## Cross-cutting watch-outs

Keep a short list of traps that apply to every surface: dead surfaces that still look alive,
translation-key families, per-generation naming, feature flags that gate a whole group.
