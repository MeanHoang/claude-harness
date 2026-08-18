<!-- Copy file này → dùng làm .claude/ship/<slug>/decisions.md
     LUẬT: APPEND-ONLY. Entry cũ không bao giờ sửa, không bao giờ xoá.
       · Chỉ ghi thứ KHÔNG derive được từ code/git/test:
         quyết định + lý do + phương án đã loại, bài học kiến trúc, nợ kỹ thuật, ràng buộc user đặt
       · KHÔNG ghi: số test pass, danh sách commit, mô tả code hiện trạng,
         tiến độ (→ progress.md), thứ đọc `git log`/`git diff` là ra
       · Mỗi entry PHẢI có: ngày · cái gì · **Vì:** lý do · file:line nếu có
       · Bài học lặp ≥2 lần → không ở lại đây nữa: đẩy lên CLAUDE.md, hook, hoặc test.
         Ghi lại lần 3 nghĩa là file này đang chứng kiến lỗi lặp mà không chặn được.
     Xoá nguyên comment này sau khi điền entry đầu tiên. -->

# Decisions — {{Tên task}}

Append-only. Mới nhất lên đầu. Đọc cùng `progress.md` (tiến độ) và `plan.html` (kế hoạch).

---

## {{YYYY-MM-DD}} — {{Quyết định một dòng}}

**Vì:** {{lý do — ràng buộc thật, không phải sở thích}}
**Đã loại:** {{phương án B và vì sao không chọn}}
**Chứng cứ:** `{{file.js:line}}`
**Ai chốt:** {{user | tôi, user chưa phản đối}}

---

## Nợ kỹ thuật

Thứ cố ý để lại. Mỗi dòng: cái gì · vì sao hoãn · điều kiện để làm.

- {{...}} — hoãn vì {{...}}; làm khi {{...}}

---

## Bài học kiến trúc

Thứ tốn thời gian mới tìm ra, session sau đọc để không tốn lại.

- **{{tên bài học}}** — {{1-3 dòng}} (`{{file:line}}`)
