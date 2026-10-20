// Diskat landing page: EN/VI toggle (English by default) + screenshot tabs. No tracking, no external requests.
(function () {
  "use strict";

  var VI = {
    "nav.features": "Tính năng",
    "nav.safety": "An toàn",
    "nav.compare": "So sánh",
    "nav.changelog": "Nhật ký thay đổi",
    "nav.faq": "Hỏi đáp",

    "hero.badge1": "Miễn phí &amp; mã nguồn mở",
    "hero.badge2": "Windows 10 / 11",
    "hero.badge3": "Không thu thập dữ liệu",
    "hero.title1": "Biết ngay cái gì đang ngốn ổ đĩa.",
    "hero.title2": "Dọn dẹp thật an toàn.",
    "hero.lead": "Diskat quét hàng triệu file trong vài giây, đưa thư mục nặng nhất lên đầu và cho bạn chuyển chúng vào Thùng rác chỉ với một phím.",
    "cta.download": "Tải cho Windows",
    "cta.github": "Xem mã nguồn",
    "cta.star": "Star trên GitHub",
    "cta.note": "Một file .exe chạy ngay · 64-bit · Không cần cài đặt, không cần .NET",

    "stat1": "để quét 2 triệu file*",
    "stat2": "kết nối mạng hay theo dõi",
    "stat3": "ngôn ngữ: English &amp; Tiếng Việt",
    "stat4": "file duy nhất, không cần cài",
    "stat.note": "* Quét toàn bộ ổ hệ thống 430 GB trên SSD laptop, không cần quyền Admin.",

    "feat.eyebrow": "Tính năng",
    "feat.title": "Đủ mọi thứ để giải phóng dung lượng, không thừa thứ gì",
    "feat.lead": "Chọn một ổ hoặc thư mục. Vài giây sau bạn biết chính xác dung lượng đã đi đâu.",
    "f1.t": "Quét song song",
    "f1.d": "Nhiều luồng đọc thư mục cùng lúc, gần như không tốn bộ nhớ cho từng file. Kết quả hiện ra ngay trong lúc quét.",
    "f2.t": "Bản đồ dung lượng",
    "f2.d": "Mỗi ô có kích thước theo dung lượng nó chiếm. Nhấp để chọn, nhấp đúp để đi sâu vào trong.",
    "f3.t": "Cây thư mục đã sắp xếp",
    "f3.d": "Nặng nhất lên đầu, có thanh “% thư mục cha”, số file và ngày sửa. Sắp xếp theo cột bất kỳ, điều khiển bằng bàn phím.",
    "f4.t": "File lớn nhất",
    "f4.d": "500 file lớn nhất trên cả ổ trong một danh sách: ISO cũ, video, bản sao lưu. Chọn nhiều file và xóa một lần.",
    "f5.t": "Xóa ngay tại chỗ",
    "f5.d": "Bấm <kbd>Del</kbd> để chuyển vào Thùng rác hoặc <kbd>Shift+Del</kbd> để xóa hẳn. Tổng dung lượng cập nhật tức thì, không cần quét lại.",
    "f6.t": "Chạy quyền Admin",
    "f6.d": "Một cú nhấp để khởi động lại Diskat với quyền quản trị, đo luôn cả thư mục hệ thống bị chặn. Không bao giờ tự nâng quyền.",

    "gal.eyebrow": "Ảnh chụp",
    "gal.title": "Nhìn là hiểu",
    "gal.t1": "Tổng quan",
    "gal.t2": "File lớn nhất",
    "gal.t3": "Bản đồ thư mục",
    "gal.t4": "Xóa an toàn",
    "gal.c1": "Quét cả ổ đĩa và thấy ngay thư mục nặng nhất.",
    "gal.c2": "Những file lớn nhất ở bất kỳ đâu trên ổ, kèm thư mục chứa.",
    "gal.c3": "Bản đồ dung lượng thể hiện mọi file và thư mục theo kích thước.",
    "gal.c4": "Mọi thao tác xóa đều được xác nhận, mặc định vào Thùng rác.",

    "safe.eyebrow": "An toàn trên hết",
    "safe.title": "Được thiết kế để không bao giờ xóa nhầm",
    "safe.lead": "Công cụ dọn ổ đĩa chỉ hữu ích khi bạn tin được nó. Diskat luôn cẩn thận ngay từ mặc định.",
    "safe.1": "Mặc định vào Thùng rác, có hộp xác nhận hiện đầy đủ đường dẫn và dung lượng.",
    "safe.2": "Khóa gốc ổ đĩa, Windows, Program Files, ProgramData, AppData và thư mục gốc của mọi tài khoản, kể cả khi truy cập qua ổ subst hay junction.",
    "safe.3": "Không bao giờ đi theo junction hay symlink: không đếm trùng, không xóa xuyên qua liên kết.",
    "safe.4": "Cảnh báo khi thư mục chưa được quét đủ, để thư mục “0 B” không bao giờ là bất ngờ.",
    "safe.5": "Hoàn toàn ngoại tuyến và mã nguồn mở: bạn đọc được từng dòng code đụng tới file của mình.",

    "cmp.eyebrow": "So sánh",
    "cmp.title": "Diskat so với các ứng dụng khác",
    "cmp.lead": "Lĩnh vực này có nhiều công cụ rất tốt. Đây là cái nhìn thẳng thắn về vị trí của Diskat.",
    "cmp.r1": "Giá",
    "cmp.r2": "Mã nguồn mở",
    "cmp.r3": "Bản đồ treemap",
    "cmp.r4": "Cách quét",
    "cmp.r5": "Thế mạnh",
    "cmp.r6": "Giao diện tiếng Việt",
    "cmp.free": "Miễn phí",
    "cmp.yes": "Có",
    "cmp.no": "Không",
    "cmp.na": "Không nêu",
    "cmp.wiz.price": "Miễn phí cho cá nhân, doanh nghiệp phải trả phí",
    "cmp.ts.price": "Miễn phí cho cá nhân, phi thương mại; bản trả phí từ 20,40 €/người/năm",
    "cmp.ss.price": "Freeware (nhận ủng hộ)",
    "cmp.us.scan": "Quét thư mục song song; chạy được trên mọi loại ổ và ổ mạng",
    "cmp.wds.scan": "Quét thư mục; quét NTFS nhanh hơn khi chạy quyền Admin",
    "cmp.wiz.scan": "Đọc trực tiếp bảng MFT của NTFS (nhanh nhất trên NTFS)",
    "cmp.us.focus": "Đơn giản và an toàn: tìm thứ nặng, xóa, xong",
    "cmp.wds.focus": "Bộ công cụ cho người dùng chuyên sâu: file trùng, phân quyền, khôi phục, báo cáo",
    "cmp.wiz.focus": "Tốc độ tối đa trên ổ NTFS lớn",
    "cmp.ts.focus": "Báo cáo và quản lý lưu trữ doanh nghiệp (bản trả phí)",
    "cmp.ss.focus": "Khám phá bằng treemap, có bộ lọc và gắn thẻ",
    "cmp.note": "“Không nêu” nghĩa là trang web của nhà phát triển không đề cập. Thông tin được kiểm tra trên trang chính thức vào tháng 10/2026; hãy báo cho chúng tôi nếu có gì đã cũ.",
    "pick.us.t": "Chọn Diskat nếu…",
    "pick.us.d": "bạn muốn một công cụ gọn, nhanh, miễn phí, tin được khi xóa, và bạn (hoặc công ty bạn) dùng và kiểm tra được mà không cần mua giấy phép.",
    "pick.other.t": "Chọn công cụ khác nếu…",
    "pick.other.d": "bạn cần quét NTFS toàn ổ nhanh nhất có thể (WizTree), tìm file trùng, kiểm tra phân quyền hay khôi phục file (WinDirStat), hoặc xuất báo cáo PDF (TreeSize).",
    "cmp.limits": "Giới hạn hiện tại của Diskat: dung lượng tính theo kích thước file (không phải dung lượng thực chiếm trên đĩa), hard link được đếm theo từng liên kết, chỉ chạy trên Windows 64-bit.",

    "log.eyebrow": "Nhật ký thay đổi",
    "log.title": "Có gì mới",
    "log.latest": "Mới nhất",
    "log.date": "20 tháng 10, 2026",
    "log.intro": "Phiên bản công khai đầu tiên.",
    "log.added": "Thêm mới",
    "log.a1": "Bộ quét đa luồng, kết quả cập nhật trực tiếp, thư mục nặng nhất lên đầu.",
    "log.a2": "Cây thư mục có thanh “% thư mục cha”, bản đồ dung lượng hai cấp và danh sách File lớn nhất.",
    "log.a3": "Xóa vào Thùng rác hoặc xóa vĩnh viễn, quét lại từng thư mục bằng F5.",
    "log.a4": "Chạy quyền Admin, thẻ tổng quan ổ đĩa, truyền thư mục cần quét qua dòng lệnh.",
    "log.a5": "Giao diện tiếng Anh và tiếng Việt.",
    "log.safety": "An toàn",
    "log.s1": "Bảo vệ thư mục hệ thống và thư mục tài khoản, kiểm tra trên đường dẫn thật.",
    "log.s2": "Không bao giờ đi theo junction hay symlink, cả khi quét lẫn khi xóa.",
    "log.s3": "Từ chối tên kết thúc bằng dấu chấm hoặc khoảng trắng, vì Windows sẽ hiểu nhầm sang mục khác.",
    "log.full": "Xem toàn bộ nhật ký trên GitHub →",

    "faq.title": "Câu hỏi thường gặp",
    "faq.q1": "Windows báo “Windows protected your PC”. Diskat có an toàn không?",
    "faq.a1": "Bản tải về chưa được ký số nên SmartScreen cảnh báo với mọi ứng dụng mới. Bấm “More info” rồi “Run anyway”. Toàn bộ mã nguồn có trên GitHub nếu bạn muốn kiểm tra hoặc tự build.",
    "faq.q2": "Có thật sự miễn phí? Dùng ở công ty được không?",
    "faq.a2": "Được. Diskat miễn phí và mã nguồn mở, dùng cho cá nhân lẫn thương mại. Không quảng cáo, không tài khoản, không bản trả phí.",
    "faq.q3": "Diskat có gửi dữ liệu đi đâu không?",
    "faq.a3": "Không. Ứng dụng không bao giờ kết nối Internet. Thứ duy nhất được lưu là ngôn ngữ bạn chọn, ngay trên máy bạn.",
    "faq.q4": "Có cần quyền quản trị (Admin) không?",
    "faq.a4": "Không. Khi không có quyền Admin, một vài thư mục hệ thống không đọc được và được đánh dấu là bị chặn. Bấm “Quyền Admin” nếu muốn tính cả chúng.",
    "faq.q5": "Xóa nhầm có lấy lại được không?",
    "faq.a5": "Mục xóa bằng phím Del sẽ vào Thùng rác, bạn khôi phục từ đó được. Shift+Del xóa vĩnh viễn và không thể hoàn tác.",
    "faq.q6": "Hỗ trợ những phiên bản Windows nào?",
    "faq.a6": "Windows 10 và Windows 11, 64-bit. File exe chạy độc lập: không cần cài đặt, không cần .NET.",

    "final.title": "Giải phóng dung lượng trong 5 phút tới",
    "final.lead": "Tải Diskat, chọn một ổ đĩa, xóa những gì bạn không cần.",
    "foot.oss": "Mã nguồn mở theo giấy phép MIT",
    "foot.license": "Giấy phép",
    "foot.privacy": "Quyền riêng tư"
  };

  var META = {
    en: { title: document.title, desc: document.querySelector('meta[name="description"]').content, hero: "/assets/overview.png" },
    vi: {
      title: "Diskat · Phân tích dung lượng ổ đĩa miễn phí, mã nguồn mở cho Windows",
      desc: "Diskat quét hàng triệu file trong vài giây, đưa thư mục nặng nhất lên đầu và giúp bạn dọn dẹp an toàn. Miễn phí, mã nguồn mở cho Windows 10 và 11.",
      hero: "/assets/overview-vi.png"
    }
  };

  var nodes = Array.prototype.slice.call(document.querySelectorAll("[data-i18n]"));
  var english = nodes.map(function (n) { return n.innerHTML; });

  function apply(lang) {
    nodes.forEach(function (n, i) {
      var key = n.getAttribute("data-i18n");
      n.innerHTML = lang === "vi" && VI[key] ? VI[key] : english[i];
    });
    document.documentElement.lang = lang;
    document.title = META[lang].title;
    document.querySelector('meta[name="description"]').content = META[lang].desc;
    var hero = document.getElementById("hero-shot");
    if (hero) hero.src = META[lang].hero;
    document.querySelectorAll(".lang button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.getAttribute("data-lang") === lang));
    });
  }

  function saved() {
    try { return localStorage.getItem("diskat-lang"); } catch (e) { return null; }
  }

  document.querySelectorAll(".lang button").forEach(function (b) {
    b.addEventListener("click", function () {
      var lang = b.getAttribute("data-lang");
      try { localStorage.setItem("diskat-lang", lang); } catch (e) { /* trình duyệt chặn lưu trữ: vẫn đổi ngôn ngữ */ }
      apply(lang);
    });
  });

  var lang = saved() === "vi" ? "vi" : "en";
  if (lang !== "en") apply(lang);

  // Tab ảnh chụp
  var tabs = document.querySelectorAll(".tab");
  var shots = document.querySelectorAll(".shot");
  tabs.forEach(function (t) {
    t.addEventListener("click", function () {
      var idx = Number(t.getAttribute("data-shot"));
      tabs.forEach(function (x) { x.setAttribute("aria-selected", String(x === t)); });
      shots.forEach(function (s, i) { s.classList.toggle("active", i === idx); });
    });
  });
})();
