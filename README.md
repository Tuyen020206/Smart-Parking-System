# Smart Parking System — Verilog + Python

Đồ án Kiến trúc Máy tính: thiết kế và kiểm chứng bộ điều khiển bãi đỗ xe thông minh ở mức RTL. Demo gồm **8 ô đỗ, 3 làn vào và 1 làn ra**.

Verilog điều khiển và lưu trạng thái. Python tạo kích thích, tính expected độc lập, gọi Icarus, đối chiếu actual và hiển thị kết quả. GUI là **phát lại dữ liệu RTL đã kiểm chứng**, chưa kết nối FPGA thật.

## Các khối chính

- `gate_node_fsm.v`: FSM sáu trạng thái, giữ giao dịch qua backpressure/timeout, kiểm tra phản hồi đúng ID/opcode/tag, lưu ACK hủy đến khi vùng chắn trống và chờ motion ACK trước phiên mới.
- `slot_node_sensor.v`: Trigger/Echo, đếm clock giữa các cạnh Echo đã đồng bộ, median năm mẫu, hai ngưỡng hysteresis, xác nhận liên tiếp, freshness và RGB.
- `central_arbiter.v`: Round-Robin, cập nhật nguyên tử C/N/R/D/Q và chống cấp quá sức chứa.
- `parking_mem_opt.v`: sáu bitmap, ownership/session, FIFO vòng, dedup hữu hạn và checkpoint/retire.
- `parking_top.v`: kết nối đầy đủ các khối. Testbench có mô hình barrier tự sinh limit, mô phỏng kẹt và monitor giữ payload khi stalled.

## Cài đặt

- Python **3.10+**, chỉ cần thư viện chuẩn cho các script mô phỏng.
- Icarus Verilog: `iverilog` và `vvp` trong PATH.
- GTKWave để xem VCD, tùy chọn.
- Tkinter/Tcl/Tk để mở GUI, tùy chọn. CLI vẫn chạy khi không có Tkinter.

Chạy từ thư mục gốc repository. Có thể thay `python` bằng `python3`.

## Chạy demo

```bash
python python/demo.py list
python python/demo.py run entry
python python/demo_gui.py --results results/demos/entry --at occupied
```

`run` thực sự gọi RTL và scoreboard trước khi in PASS. GUI có **Play/Pause**, **Next event** và **Run RTL then load**. Trục sự kiện có thể bỏ qua các chu kỳ yên lặng; cycle hiển thị là mốc thực trong CSV.

Một số kịch bản khác:

```bash
python python/demo.py run obstacle
python python/demo.py run last-slot
python python/demo.py run cancel
python python/demo.py run jam-open
python python/demo.py run jam-close
python python/demo.py run offline
python python/demo.py run replay
python python/demo.py run echo-50mhz
```

CLI có 19 lựa chọn. `entry` chạy xe vào–đỗ–rời ô–ra cổng với barrier model phản hồi vị trí. `obstacle` thử FIFO đầy cùng vật cản; `cancel` thử ACK hủy đến khi vùng chắn chưa trống.

## Chạy toàn bộ kiểm thử

```bash
python python/run_tests.py
python python/compare_results.py
python python/analyze_results.py
python python/replay_host.py
```

Nếu công cụ không có trong PATH:

```bash
python python/run_tests.py --iverilog /path/to/iverilog --vvp /path/to/vvp
python python/demo.py run entry --iverilog /path/to/iverilog --vvp /path/to/vvp
```

Kết quả V2 đã chạy và đối chiếu: **190 PASS / 0 fail**, thuộc **65 họ test**:

| Nhóm | Phạm vi | Lượt |
|---|---|---:|
| Engine | 25 họ × 8/33/128 ô × FIFO depth 3/8 | 150 |
| Sensor | Echo, median, hysteresis, lỗi, freshness và 50 MHz | 12 |
| Gate | FSM, ID/opcode/tag, backpressure, hủy, timeout và ACK | 15 |
| Top | Luồng xe, tranh suất, offline, booking, reset, vật cản và jam | 13 |

Tổng lần chạy đầy đủ: 2.448.425 cycle và 5.338.294 trường/điều kiện kiểm tra. Audit đọc lại 5.337.619 trường CSV; chỉ số này không gồm các kiểm tra phụ của runner. Tổng cycle có nhiều clock TB, không quy đổi thành một thời gian chung. Random có seed `20261125 + slots + depth`, 600 bước chính mỗi cấu hình engine.

Demo T09 đã chạy lại thành công trong bản sao chỉ mã nguồn, không có kết quả cũ: 17.701 cycle và 619.580 kiểm tra. Để xác nhận trên máy bạn, chạy lại các lệnh ở trên.

Chạy riêng và lưu thư mục khác để giữ kết quả toàn bộ:

```bash
python python/run_tests.py --suite top --out results/my-top
python python/run_tests.py --suite gate --case G11_cancel_blocked --out results/my-g11
python python/run_tests.py --suite sensor --case S11_clock_50mhz --out results/my-s11
```

Runner tạo thư mục đầu ra, khóa chống chạy đồng thời cùng `--out`, lưu hash RTL/TB/Python và trả mã lỗi khác 0 khi thất bại hoặc không có test khớp. Một lần chạy nhóm top không phải bộ đầy đủ 190 lượt. `analyze_results.py` yêu cầu bộ `all` đầy đủ.

## Đọc kết quả

- `results/metadata.json`: trạng thái, cấu hình, seed, phiên bản công cụ, compile attempts, hash nguồn và số kiểm tra.
- `results/summary.csv`: kết quả từng lượt.
- `results/csv/<case>/`: vector/Echo, actual, expected và milestones khi phù hợp.
- `results/vcd/`, `results/logs/`: waveform và lệnh/log thực thi.
- `results/metrics.csv`, `interlock.csv`, `grant_latency.csv`: mốc đo độ trễ.
- `results/storage.csv`, `baseline.csv`: ước lượng trạng thái và so sánh cấu trúc.
- `results/journals/`: host phát lại event từ trace, có flush/fsync trước ACK; chưa phải host UART trực tiếp.

```bash
gtkwave results/vcd/T10_auto_obstacle.vcd docs/obstacle.gtkw
```

Nếu chưa thấy sự kiện, bấm đến cuối dữ liệu hoặc xem khoảng 9370–9410 microsecond. VCD dùng đơn vị lưu 1 ps; clock top TB là 1 MHz.

## Bộ nhớ và các giới hạn

- `A = max(0, C − N − R − D − Q)`. Occupied dùng đối soát; không trừ O thêm lần nữa. Khi passage còn pending, N chưa commit nhưng R vẫn giữ suất.
- Sáu bitmap cho 8 ô cần 48 bit so với 384 bit cờ theo byte: giảm **87,5% riêng phần cờ**. FIFO vòng giảm dịch dữ liệu, không giảm payload RAM.
- Cấu hình 8 ô/CAM32/FIFO8 khoảng **11.810 bit trạng thái chức năng**, tăng 692 bit từ V1 để giữ giao dịch và đếm Echo. Đây không phải số LUT/FF/BRAM sau synthesis.
- Chọn ô hợp lệ có chỉ số nhỏ nhất; chưa tính khoảng cách địa lý.
- Barrier model có vị trí chuẩn hóa 0…12 và jam; không mô phỏng lực/quán tính hoặc chứng nhận an toàn cơ khí.
- Liên động tính từ blocked đã đồng bộ; tách raw→synchronizer→mask→FSM. Không gọi đây là thời gian dừng motor.
- Clear, cancel/recovery, ticket và host là đầu vào tin cậy. Xe đi qua sau một cancel đã xác minh là mâu thuẫn môi trường, chuyển FAULT. Exit grant mồ côi cần đối soát thủ công.
- Reset xóa RAM và đưa gate vào FAULT. Snapshot restore đầy đủ, quota phân tán, UART, OCR và thanh toán chưa làm.
- Chưa synthesis, Fmax, pin constraints hoặc FPGA thật. Không có CPU/cache nên không dùng C_CPU/AMAT làm số đo sản phẩm.

## Lỗi thường gặp

- Thiếu Icarus: cài tool hoặc truyền `--iverilog`/`--vvp`; chưa chạy thành công thì chưa có PASS.
- `_tkinter`/`init.tcl`: dùng Python có Tcl/Tk hoặc CLI.
- Source mismatch: chạy lại sau khi sửa mã; không sửa metadata để đổi kết quả.
- Compile native trên môi trường Windows đã dùng có thể lỗi `0xC0000005`. `--compile-attempts N` chỉ retry mã này và ghi mọi lần thử; mặc định 1. Lỗi cú pháp/mô phỏng vẫn dừng. Nếu gặp đúng lỗi này có thể dùng `--compile-attempts 512`.

Repository chỉ chứa mã nguồn, testbench, cấu hình và tài liệu kỹ thuật. Báo cáo, Word/PDF, slide, hình, kết quả sinh tự động, compiler và môi trường ảo được loại khỏi Git.

Xem [giao thức](docs/protocol.md), [hướng dẫn bắt đầu](docs/START_HERE.md), [kiểm kê](docs/inventory.md) và [bảng đánh giá](docs/review_matrix.md).
