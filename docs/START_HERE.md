# Chạy sản phẩm

1. Cài Python>=3.10 và Icarus Verilog (`iverilog`, `vvp` trong PATH).
2. Tại thư mục gốc: `python python/demo.py run entry`.
3. Nếu có Tkinter: `python python/demo_gui.py --results results/demos/entry --at occupied`.
4. Chạy bộ đầy đủ bằng `python python/run_tests.py`, rồi `python python/compare_results.py`.
5. Tạo số liệu: `python python/analyze_results.py`; host replay: `python python/replay_host.py`.

GUI phát lại actual từ RTL đã đối chiếu. Nút Run RTL gọi Icarus và chỉ tải kết quả khi thành công. Không phải FPGA trực tiếp. Chạy `python python/demo.py list` để xem19 lựa chọn.

Mở GTKWave: `gtkwave results/vcd/T10_auto_obstacle.vcd docs/obstacle.gtkw`. Đến cuối dữ liệu để thấy vật cản; xem blocked_sync, close/open, pending và FIFO count.

Lọc test mà giữ bộ đầy đủ: `python python/run_tests.py --suite gate --case G11_cancel_blocked --out results/my-g11`.

README có bảng190 lượt/65 họ, cấu hình và xử lý lỗi Icarus/Tkinter. Phải chạy lại trên máy bạn để tạo actual/expected, VCD và logs; repository không chứa kết quả sinh sẵn. Báo cáo và slide nằm trong gói bàn giao đầy đủ riêng, không đưa lên repository này.
