# Smart Parking System — Verilog + Python

Đồ án Kiến trúc Máy tính: thiết kế và kiểm chứng bộ điều khiển bãi đỗ xe thông minh bằng Verilog kết hợp Python.

Demo tích hợp **8 ô, 3 làn vào và 1 làn ra**. Verilog thực hiện điều khiển và lưu trạng thái; Python sinh dữ liệu, tính mô hình tham chiếu độc lập, gọi simulator và đối chiếu kết quả.

## Chức năng

- FSM cổng sáu trạng thái; kiểm tra đúng ID/phiên trước khi mở; giữ passage tới khi được nhận.
- Liên động vật cản tại cổng, độc lập với FIFO và host. Mốc phản ứng được tính từ `blocked` đã đồng bộ.
- Đo Trigger/Echo, median 5 mẫu, hysteresis, xác nhận liên tiếp, timeout và xử lý dữ liệu quá hạn.
- Round-Robin giữa các nguồn; cập nhật nguyên tử `C/N/R/D/Q` cùng trạng thái ô.
- Sáu bitmap tách trạng thái vật lý và quản lý, kèm owner/session tag.
- FIFO vòng có backpressure, full + pop + push và depth không phải lũy thừa hai.
- Hardware dedup: cùng ID/payload không tác động lần hai; payload khác báo lỗi; checkpoint/retire khi bảng đầy.
- Đặt trước `D`, quỹ offline `Q`, và mô phỏng host journal có flush/fsync trước checkpoint.

## Cấu trúc

```text
rtl/
  parking_top.v          # Nối gate, sensor, arbiter và memory
  gate_node_fsm.v        # FSM cổng
  slot_node_sensor.v     # Echo, median, hysteresis, freshness
  central_arbiter.v      # RR và C/N/R/D/Q
  parking_mem_opt.v      # Bitmap, ownership, FIFO, dedup
  common/               # Synchronizer, FIFO và parking_engine
tb/
  tb_parking_top.v       # Kiểm thử tích hợp
  tb_gate.v
  tb_sensor.v
  tb_memory.v            # Kiểm thử engine: Central + memory
  tasks/
  monitors/
python/
  run_tests.py           # Gọi Icarus và các scoreboard
  generate_vectors.py
  reference_model.py
  gate_checks.py
  sensor_checks.py
  top_checks.py
  compare_results.py
  analyze_results.py
  replay_host.py
docs/
  protocol.md           # Opcode, valid/ready, event layout và reset
```

## Cài đặt

- Python **3.10 trở lên**. Các script chỉ dùng thư viện chuẩn; không cần cài thư viện bằng pip.
- Icarus Verilog: hai lệnh `iverilog` và `vvp` có trong PATH.
- GTKWave là tùy chọn để xem waveform VCD.

Trên Ubuntu/Debian có thể cài công cụ:

```bash
sudo apt-get update
sudo apt-get install python3 iverilog gtkwave
```

## Chạy toàn bộ kiểm thử

Chạy từ thư mục gốc repository:

```bash
python python/run_tests.py
python python/compare_results.py
python python/analyze_results.py
python python/replay_host.py
```

Trên máy dùng lệnh `python3`, thay `python` bằng `python3`.

Nếu công cụ chưa có trong PATH:

```bash
python python/run_tests.py --iverilog /path/to/iverilog --vvp /path/to/vvp
```

Các thư mục kết quả được tạo tự động. Một lần chạy đầy đủ mặc định gồm **178 lượt / 53 họ test**:

| Nhóm | Phạm vi | Lượt chạy |
|---|---|---:|
| Engine | 25 ca × 8/33/128 ô × FIFO depth 3/8 | 150 |
| Sensor | Echo, median, nhiễu, hysteresis, timeout, freshness | 10 |
| Gate | FSM, ID/tag, pending, vật cản, hủy và timeout | 10 |
| Top | Vào–đỗ–ra, tranh suất cuối, offline, booking, reset | 8 |

Random có 600 bước chính mỗi cấu hình; seed là `20261125 + slots + depth`, thêm bước khởi tạo và drain pending. Kết quả đã kiểm chứng của bản nguồn này được nêu trong lịch sử commit; để xác nhận môi trường của bạn, chạy lại các lệnh trên.

## Chạy riêng từng nhóm

```bash
python python/run_tests.py --suite top
python python/run_tests.py --suite sensor
python python/run_tests.py --suite gate
python python/run_tests.py --suite engine --sizes 8 --depths 8
```

Lần chạy mới thay thế summary/metadata và các tệp trùng tên. Chạy lại toàn bộ trước khi dùng `analyze_results.py`, vì phân tích so sánh các cấu hình cần đủ dữ liệu.

## Đọc kết quả

- `results/metadata.json`: trạng thái, cấu hình, seed, tổng kiểm tra và hash RTL.
- `results/summary.csv`: từng lượt PASS; lỗi làm runner trả mã khác 0.
- `results/csv/<test>/`: kích thích, actual từ Verilog, expected từ Python và milestone khi phù hợp.
- `results/vcd/`: waveform của các kịch bản chính.
- `results/logs/`: lệnh chạy, phiên bản, mã thoát và log.
- `results/metrics.csv`, `storage.csv`, `baseline.csv`: latency và phân tích lưu trữ.
- `results/journals/`: journal do host phát lại từ trace thực; chưa phải UART/live host.

Ví dụ:

```bash
gtkwave results/vcd/T03_obstacle_fifo.vcd
```

Trong `T01_entry_park_exit`, xe rời ô chỉ làm occupied giảm; `N` giảm khi xe qua cổng ra. `T02_last_slot` cho ba làn tranh một suất và chỉ một làn được mở. `T03_obstacle_fifo` giữ passage khi FIFO đầy, xử lý vật cản, đóng lại và commit ENTER đúng một lần.

Các tệp kết quả được tạo khi chạy và được `.gitignore` loại khỏi Git. Repository chỉ lưu mã nguồn, testbench, cấu hình và hướng dẫn kỹ thuật.

## Lưu ý kỹ thuật

- Đây là sản phẩm **RTL và đồng mô phỏng file-based**; chưa synthesis, pin constraints, Fmax hay triển khai FPGA thật.
- Clock top/sensor TB = 1 MHz; engine/gate TB = 100 MHz giả lập. Mặc định sensor RTL = 50 MHz. Đây không phải chứng minh timing trên chip.
- Chọn ô hợp lệ có chỉ số nhỏ nhất, chưa tính khoảng cách theo sơ đồ bãi.
- `A = max(0, C − N − R − D − Q)`; occupied dùng đối soát, không trừ thêm lần nữa.
- Bitmap giảm 87,5% **riêng sáu cờ** so với cờ theo byte. FIFO giữ nguyên payload và thêm con trỏ; dedup cần thêm bộ nhớ. Số bit logic không phải số LUT/FF/BRAM.
- Ticket, clear-stable, cancel/recovery và lệnh host là đầu vào tin cậy từ môi trường; chưa có OCR, tính phí hoặc xác thực mật mã.
- Reset xóa RAM/count và đưa gate vào FAULT. Chưa có snapshot restore đầy đủ sau mất nguồn; cần khóa và đối soát trước khi vận hành trở lại.
- Quỹ Q do một Central sở hữu; chưa chia quota cho controller phân tán.
- Trong môi trường Windows đã dùng, compiler native có lúc trả access violation `0xC0000005`. Tùy chọn `--compile-attempts N` chỉ retry mã lỗi này và ghi lại từng lần; mặc định một lần. Lỗi cú pháp hoặc mô phỏng không bị bỏ qua.

Chi tiết opcode, quyền nguồn, trường event và chính sách sequence/epoch xem [docs/protocol.md](docs/protocol.md).
