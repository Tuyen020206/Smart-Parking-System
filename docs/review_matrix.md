# Đánh giá hiện trạng và quyết định nâng cấp

Đối chiếu với mã nền178PASS. Cột rủi ro ghi phạm vi tìm thấy khi đọc mã và thêm regression; không xem README là bằng chứng.

| Chức năng | Đã có ở mã nền | Còn thiếu trước nâng cấp | Lỗi/rủi ro cụ thể | Kiểm chứng V2 |
|---|---|---|---|---|
| Bốn khối nối top | Có | Mô hình plant phản hồi | Limit thủ công chưa phát hiện lỗi chờ chuyển động | T09…T13, barrier_model |
| Tạo request/grant | Có | TX độc lập timeout | Nguồn có thể hạ valid khi vẫn bị stalled | G13, request_monitor mỗi cạnh |
| Grant đúng phiên | ID/tag | Đối chiếu opcode và grant muộn | Phản hồi sai loại/lost grant | G12/G14 |
| Passage N/R | Có | Chờ motion ACK trước phiên mới | Giao dịch cũ và phiên mới có thể chồng | G15/T06 |
| Hủy có xác minh | Có | Ghi nhớ ACK khi blocked | Kẹt WAIT_PASS khi clear đến sau ACK | Baseline G11 FAIL; V2 G11/T13 PASS |
| Trigger/Echo | Đo RTL | Kiểm clock50MHz | Đếm tick đơn giản có rủi ro lệch pha | Echo clock counter, S11/S12 |
| Median/hysteresis | Có | Không đổi thuật toán | Mẫu lỗi/dữ liệu quá hạn không được coi FREE | S01…S12, T09 |
| Ba cổng tranh suất | RR thực | Giữ regression | Không gọi chọn chỉ số nhỏ nhất là khoảng cách gần nhất | E04/T02, bitmap encoder |
| D/Q trong RTL | Có | Không mở rộng controller phân tán | Q chỉ có một Central sở hữu | E15/E16/T04/T05 |
| FIFO/backpressure | Có | Kiểm stall payload xuyên timeout | Pending phải giữ; FIFO không bảo đảm lưu qua mất điện | E13/E14/T10/G13 |
| Dedup phần cứng | CAM/history có | Snapshot bền chưa làm | CAM hữu hạn, sequence có thứ tự | E09…E12/E19/E21; host replay17trace |
| Reset/recovery | FAULT và khóa | Restore snapshot chưa làm | Reset RAM mất toàn bộ sổ | E22/T07, tài liệu ghi rõ cần đối soát |
| Chạy lại | Runner có | Casefilter, lock, hash nguồn; demo CLI/GUI | Không dùng CSV cũ thay lần chạy mới |190PASS, audit, clean-room T09 PASS |

Những cách nói đã sửa: “ô gần nhất” → chỉ số hợp lệ nhỏ nhất; “một clock” → nêu mốc raw/sync/mask/FSM; “giảm87,5%” → riêng sáu cờ; “FIFO giảmRAM” → giảm dịch payload; “đã chạyFPGA” → RTL simulation; “C_CPU” → cycles_rtl.
