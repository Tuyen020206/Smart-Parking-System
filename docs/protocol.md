# Hợp đồng giao tiếp và trạng thái

Mọi giao dịch nội bộ theo valid/ready: nguồn giữ valid và toàn bộ payload tới cạnh rising có cả hai bằng 1. Chọn tối đa một command/clock. Sensor có ưu tiên trước command và dùng cùng FIFO; backpressure không đi vào đường mask close.

Chủ sở hữu: Central ghi C,N,R,D,Q/online/RR và response; memory ghi sáu bitmap, owner/tag, FIFO và dedup; gate ghi phiên/motion/pending; sensor ghi lịch đo, năm mẫu và trạng thái đo. Không có hai module cùng ghi một thanh ghi.

Nguồn 0–2: làn vào. Nguồn 3: làn ra. Nguồn 4: host tin cậy. `event_id = source8 | epoch24 | sequence32`. Sequence tăng nghiêm ngặt trên từng nguồn, bắt đầu 1 sau reset/đổi epoch đúng quy trình. Không cho wrap trong cùng epoch. Bản tin đến trễ ngoài cache với sequence cũ bị STALE. Epoch không đổi nóng khi thiết kế đang hoạt động; đổi sau reset/đối soát có kiểm soát.

| op | Lệnh | Nguồn | Tác động nếu thành công |
|---|---|---|---|
| 0 | ALLOC_NORMAL | 0–2 | R+1; online, đủ A và ô eligible, permit=1 |
| 1 | ENTER | 0–2 | R−1,N+1; đúng owner/tag/ô, passage xác minh |
| 2 | CANCEL_VERIFIED | 0–2 | R−1; đúng owner/tag và xác minh chưa vào |
| 3 | EXIT_PASS | 3 | N−1; đã EXIT_AUTH đúng phiên, ô không báo occupied |
| 4 | BOOK | 4 | D += data; online, còn sức chứa |
| 5 | ALLOC_BOOKED | 0–2 | D−1,R+1; online, permit và ô eligible |
| 6 | GRANT_Q | 4 | Q += data; online và còn sức chứa |
| 7 | ALLOC_OFFLINE | 0–2 | Q−1,R+1; offline, Q>0, permit và ô eligible |
| 8 | SET_ONLINE | 4 | online = data[0] |
| 9 | SET_CAPACITY | 4 | C = data, 0…SLOTS; không sửa N/R/D/Q |
| 10 | MAINT | 4 | maintenance[slot] = data[0] |
| 11 | EXIT_AUTH | 3 | giữ quyền ra bằng exit_owner/exit_tag; chưa giảm N |
| 12 | CANCEL_BOOK | 4 | D -= data, 0<data≤D |

Mã phản hồi: 0 OK, 1 DENIED, 2 BAD_SLOT, 3 BAD_STATE, 4 CONFLICT, 5 STALE, 6 BAD_EPOCH, 7 BAD_SOURCE, 8 BAD_OP, 9 NOT_AUTH, 10 NOT_READY. Kiểm tra memory có thể trả BAD_STATE trước kiểm tra quyền nếu nhiều điều kiện cùng sai. Chỉ status0 của một giao dịch mới được xem là commit thành công.

`A=max(0,C−N−R−D−Q)`. O=popcount(occupied & valid), chỉ dùng đối soát. Không trừ O thêm lần nữa. Khi giảm C dưới tổng cam kết: available=0, overcommitted=1; không hạ N cho khớp C. ALLOC_NORMAL/BOOK/GRANT_Q không được tăng tổng cam kết. ALLOC_BOOKED/OFFLINE có thể chuyển phần D/Q đã cam kết sang R mà không tăng tổng.

Một bản ghi FIFO 256 bit:

| Bit | Trường |
|---|---|
| 255:192 | ID64 |
| 191:184 | op8; command 0…12; sensor = 128 |
| 183:176 | status8 |
| 175:160 | slot16 |
| 159:144 | tag16 |
| 143:128 | data16 |
| 127:112 / 111:96 / 95:80 / 79:64 / 63:48 | C / N / R / D / Q, mỗi trường16 |
| 47:40 | flags8; sensor bit1=known, bit0=occupied |
| 39:0 | pad40 = 0 |

Command mới, kể cả bị từ chối theo nghiệp vụ, cần một entry dedup và một event. Duplicate và early reject không tạo event mới. Sensor dùng source=0xFE và không chiếm CAM command. FIFO là hàng đợi đọc tổ hợp, valid chỉ khi count>0. Slot/result 0xFFFF nghĩa chưa có ô.

Payload dedup56 = op8 | slot16 | data16 | tag16. Một entry có ID64 + payload56 + status8 + result_slot16 + valid1 = 145 bit. Bảng đầy không đẩy bỏ tự động. Retire chỉ nhận khi source/epoch đúng và sequence không vượt event đã được FIFO giao ở chu kỳ trước. Đó mới là điều kiện phần cứng; host còn phải fsync journal trước ACK. Highwater không bị retire nên gói cũ không biến thành giao dịch mới.

Reset xóa SRAM và lịch sử. RAM không cung cấp chống replay xuyên mất nguồn. Khôi phục đầy đủ C/N/R/D/Q/owner/snapshot từ đĩa chưa được hiện thực; giữ run_enable=0 và FAULT cho tới quy trình vận hành có kiểm soát.

Sensor hỗ trợ CLK_HZ là bội nguyên của 1 MHz, 50≤MIN_ECHO_US≤MAX_ECHO_US≤65535, D_ON<D_OFF, CONFIRM≥1. Demo đo 1 MHz, gap100µs, timeout3000µs, ngưỡng100/140mm. Mặc định RTL 50MHz, gap60000µs, timeout30000µs, ngưỡng1000/1200mm. Hai bộ tham số phục vụ hai mục đích khác nhau.

Median dùng 5 bộ lưu16bit, sorting tổ hợp với vòng lặp hữu hạn. Ngưỡng tách hai hướng chuyển; CONFIRM=3, lần đầu nhận trạng thái cần 7 mẫu. Một mẫu lỗi xóa cửa sổ, báo UNKNOWN và đòi lấy lại mẫu hợp lệ. STALE_US mặc định 2×(GAP+MAX_ECHO+TRIGGER). Nếu đang giữ snapshot chờ ready, giữ payload ổn định; khi snapshot quá hạn được ACK, lập tức xếp UNKNOWN tiếp theo và xóa cửa sổ trước khi đo lại. Sensor ưu tiên làm cho command chưa thể chen vào giữa hai status này.
