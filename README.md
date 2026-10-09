# Ckagngoc Clipboard

Ckagngoc Clipboard là ứng dụng thanh menu dành cho macOS, giúp lưu lại và tìm nhanh lịch sử nội dung đã sao chép. Ứng dụng hỗ trợ văn bản, hình ảnh và tệp; lịch sử được lưu cục bộ trên máy Mac.

## Tính năng

- Tự động theo dõi nội dung mới trên clipboard.
- Lưu tối đa 100 mục gần đây, gồm văn bản, hình ảnh và tệp.
- Tìm kiếm trong lịch sử và lọc các mục đã ghim.
- Ghim mục quan trọng, sao chép lại hoặc xóa từng mục.
- Mở cửa sổ clipboard bằng phím tắt toàn cục `⌃⌥V` mặc định; có thể đổi phím tắt trong phần cài đặt.
- Xóa toàn bộ lịch sử hoặc thoát ứng dụng từ giao diện.
- Mã hóa lịch sử đã lưu bằng AES-GCM; khóa mã hóa được giữ trong Keychain của macOS.
- Lưu lịch sử trên máy Mac, không gửi dữ liệu clipboard đến máy chủ.

## Yêu cầu

- macOS 27 trở lên.
- Xcode hỗ trợ macOS deployment target 27.0 trở lên.

## Build và chạy

1. Mở `CkagngocClipboard.xcodeproj` bằng Xcode.
2. Chọn scheme **CkagngocClipboard**.
3. Chọn máy Mac làm đích chạy, sau đó nhấn **Run** (`⌘R`).

Có thể build từ Terminal:

```sh
xcodebuild -project CkagngocClipboard.xcodeproj \
  -scheme CkagngocClipboard \
  -configuration Debug \
  build
```

## Sử dụng

Sau khi mở ứng dụng, biểu tượng clipboard xuất hiện trên thanh menu macOS. Nhấn biểu tượng để mở lịch sử hoặc dùng `⌃⌥V`. Chọn một mục để đưa nội dung đó trở lại clipboard, sau đó nhấn `⌘V` để dán.

Trong cửa sổ ứng dụng, bạn có thể tìm kiếm, chuyển giữa **Gần đây** và **Đã ghim**, ghim/bỏ ghim hoặc xóa mục. Mở **Cài đặt** để ghi lại phím tắt. Nhấp chuột phải vào biểu tượng trên thanh menu để mở menu, trong đó có tùy chọn thoát ứng dụng.

## Lưu trữ và quyền riêng tư

Lịch sử được mã hóa và lưu cục bộ tại:

```text
~/Library/Application Support/CkagngocClipboard/history.plist
```

Khóa giải mã được lưu trong Keychain của macOS. Ứng dụng không tải lịch sử clipboard lên mạng. Nội dung clipboard có thể chứa thông tin nhạy cảm; hãy ghim hoặc xóa mục theo nhu cầu và dùng **Xóa lịch sử** khi muốn xóa toàn bộ dữ liệu đã lưu.
