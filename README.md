# snip — Clipboard History Manager for macOS

A lightweight, native macOS menu bar app to manage your clipboard history.  
Built with Swift + SwiftUI, runs entirely local, zero external dependencies.

---

## Yêu cầu hệ thống

| Mục | Yêu cầu |
|-----|---------|
| macOS | 13 Ventura trở lên |
| Chip | Apple Silicon hoặc Intel |
| Swift | 5.9+ |
| Xcode CLT | Command Line Tools (không cần Xcode IDE) |

---

## Cài đặt Swift Command Line Tools

Nếu bạn chưa cài (lần đầu dùng Swift trên máy):

```bash
xcode-select --install
```

Kiểm tra đã cài thành công:

```bash
swift --version
# Swift version 5.9.x (swift-5.9.x-RELEASE)
```

---

## Build & Chạy app

```bash
# Clone hoặc cd vào thư mục project
cd /path/to/snip

# Build (debug build, đủ nhanh để phát triển)
swift build

# Chạy app
swift run
```

App sẽ **không hiện gì trên màn hình** — đó là bình thường.  
Nhìn lên **thanh menu** (góc phải trên cùng màn hình), bạn sẽ thấy icon 📋.

> **Tip:** Lần đầu build sẽ mất 1-2 phút để compile. Các lần sau nhanh hơn nhiều.

---

## Dừng app

Cách 1 — Từ Terminal (nếu chạy bằng `swift run`):
```
Ctrl + C
```

Cách 2 — Từ menu bar (khi đã build thành binary):
```bash
pkill snip
```

---

## Cách dùng

### Xem lịch sử clipboard
Click vào icon 📋 trên menu bar → Popover hiện ra với danh sách các mục đã copy.

### Tìm kiếm
Gõ vào ô tìm kiếm ở trên cùng của popover.

### Copy lại một mục
Click vào bất kỳ mục nào trong danh sách → nội dung được copy vào clipboard.

### Ghim mục quan trọng
Hover vào mục → click icon 📌 → mục được ghim (không bị auto-xóa, hiện ưu tiên đầu danh sách).

### Xóa một mục
Hover vào mục → click icon 🗑️.

### Xóa toàn bộ lịch sử
Cuộn xuống cuối popover → click "Xóa lịch sử (giữ mục ghim)".

---

## Tính năng Drag Zone

### Bật Drag Zone
Trong popover → kéo xuống phần Settings → bật toggle **Drag Zone**.

> ⚠️ **Cần quyền Accessibility:** Lần đầu bật, macOS sẽ hỏi cấp quyền.

### Cấp quyền Accessibility (bắt buộc cho Drag Zone)

1. Mở **System Settings** → **Privacy & Security** → **Accessibility**
2. Click dấu **+** → thêm app `snip`  
   *(hoặc nếu dùng `swift run`: thêm **Terminal** hoặc **iTerm2**)*
3. Bật toggle cho app đó
4. **Quay lại snip** → bật lại toggle Drag Zone

### Cách dùng Drag Zone
1. Bôi đen (select) text ở bất kỳ app nào (Safari, Notes, Word...)
2. **Kéo** đoạn text đó (không cần Cmd+C)
3. Thả vào panel nhỏ nổi ở góc dưới phải màn hình
4. Nội dung được lưu vào lịch sử **và** copy vào clipboard để Cmd+V ngay

> **Lưu ý:** Panel tự hiện khi phát hiện bạn đang kéo, tự ẩn khi thả xong.

---

## Lưu trữ dữ liệu

Tất cả dữ liệu lưu tại:

```
~/Library/Application Support/snip/
├── history.json      ← Metadata (text, timestamp, isPinned, đường dẫn ảnh)
└── Images/           ← File PNG của các mục ảnh
    ├── <uuid>.png
    └── ...
```

**Giới hạn:** Tối đa 200 mục (mục ghim không tính vào giới hạn).  
Khi vượt giới hạn, mục cũ nhất bị xóa tự động (kèm file ảnh nếu có).

---

## Câu hỏi kỹ thuật thường gặp

### Tại sao dùng polling thay vì event listener cho clipboard?

macOS **không có API event-driven** để theo dõi clipboard (không có notification hay callback khi clipboard thay đổi). Cách duy nhất là so sánh `NSPasteboard.general.changeCount` — một số nguyên tăng mỗi khi clipboard thay đổi. App poll mỗi **0.5 giây** — tải CPU gần như bằng 0 vì chỉ so sánh 1 số nguyên.

### Tại sao không dùng Electron?

Electron nhúng toàn bộ Chromium browser engine (~100-150MB RAM chỉ để chạy nền) và luôn tốn CPU để render. Trên MacBook Air M4 không có quạt tản nhiệt, điều này gây nóng máy và giảm tuổi thọ. App Swift native idle ở **<5MB RAM** và **~0% CPU**.

### Hạn chế của Drag Zone heuristic

Drag Zone dùng **heuristic** (phỏng đoán) để phát hiện khi bạn đang kéo:
- Phát hiện `leftMouseDown` → di chuyển >10px → coi là "có thể đang kéo" → hiện panel
- **False positive:** Panel có thể hiện khi bạn click-drag để scroll (không phải drag nội dung)
- **False negative:** Hiếm khi không phát hiện nếu drag quá nhanh
- Đây là giới hạn đã biết của macOS API (không có cách phát hiện drag chính xác 100% từ app ngoài)

---

## Kiến trúc code

```
Sources/snip/
├── main.swift           # Entry point, NSApplication setup
├── AppDelegate.swift    # Status bar icon, popover, điều phối monitor
├── ClipboardItem.swift  # Data model (Codable)
├── ClipboardMonitor.swift  # Polling, lưu JSON, quản lý ảnh
├── ContentView.swift    # SwiftUI UI chính
├── DragZonePanel.swift  # NSPanel + NSDraggingDestination
└── DragMonitor.swift    # Global mouse event monitor
```