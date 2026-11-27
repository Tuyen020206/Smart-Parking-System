# Kiểm kê và thay đổi V2

Đầu vào: mã nguồn bản178PASS, commit gốc a833bc830af147cbb67f073777d0d0f57965d4b3. Hash nguồn ban đầu ở baseline.json. Bản gốc `smart_parking_integrated` và bản đã push trước được giữ nguyên.

| Thành phần | Tình trạng V2 |
|---|---|
| Gate6state | TX ổn định, ACK hủy sticky, responseopcode, lategrant, motionACK |
| Sensor | Echo clockcounter; median5, hysteresis, freshness giữ nguyên |
| Central + memory | Giữ giao diện/thuật toán hiện có, test regression đủ150engine |
| Top | Thêm barrier model phản hồi và stall monitor trong TB |
| Python | casefilter, runlock, sourcehash, CLI19scenario, Tkinterreplay |
| Kiểm thử | 190/190;65họ; xem metadata/summary/log thực |
| Thuật toán | 11bộ input/output/mãgiả/lưuđồ/vídụ/timing/test/giớihạn |
| Hình |17hìnhcơbản+11lưuđồ+ảnhGUI/GTKWave thật+tríchCSV/log mới |
| Báo cáo |5chương, tài liệu người mới,15slide,40hỏiđáp |

Baseline G11 chạy với gate cũ đã FAIL, tái hiện mất ACKhủy khi blocked. Kết quả cố ý này ở baseline_regressions, được tách khỏi190PASS. Các lần chạy CLI riêng không cộng vào190PASS.

Chưa FPGA/synthesis/timing/MTBF/UART/OCR/thanh toán/snapshotrestore/xeđổiô/quota phân tán. GUI là phát lại output RTL; Python không thay RTL tính actual. Repository V2 chỉ giữ mã/test/cấu hình và tài liệu kỹ thuật; báo cáo và output ở gói bàn giao riêng.
