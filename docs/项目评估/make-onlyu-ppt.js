// Only-U 黑客松演示 PPT（3 页 · 2 分钟讲稿）— v2 基于代码实况重写
// 运行: node make-onlyu-ppt.js   -> 输出 Only-U-演示.pptx
const pptxgen = require("pptxgenjs");

const pptx = new pptxgen();
pptx.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
pptx.title = "Only-U — 黑客松演示";
pptx.author = "Only-U";

// ---------- 调色板（终端 / 运维主题） ----------
const F = {
  ink: "0B1220",        // 深色背景
  panel: "121C2E",      // 深色卡片
  panelLine: "2A3A5C",
  white: "FFFFFF",
  soft: "C9D4E8",
  muted: "6B7A93",
  ice: "9DB2E8",
  green: "2BD97C",      // 终端绿（唯一锐利强调色）
  greenDark: "0E9F5C",
  amber: "F5B94D",      // 预览 / 待确认
  amberDark: "B45309",
  bgLight: "F5F7FA",
  cardLine: "E2E6EE",
  inkText: "101828",
  mutedLight: "5A6B85",
  greenTint: "E3F6EC",
  greenTintLine: "9FE3C3",
  amberTint: "FDF0DC",
  amberTintLine: "E8C88A",
};
const CN = "Microsoft YaHei";
const MONO = "Courier New";
const shadow = () => ({ type: "outer", blur: 5, offset: 3, angle: 90, color: "101828", opacity: 0.14 });

// ---------- 通用小组件 ----------
function pill(slide, x, y, w, h, fill, lineColor, text, textColor, fontSize, bold, mono) {
  slide.addShape("ROUNDED_RECTANGLE", {
    x, y, w, h, rectRadius: h / 2,
    fill: { color: fill },
    line: lineColor ? { color: lineColor, width: 1 } : undefined,
  });
  slide.addText(text, {
    x, y, w, h, align: "center", valign: "middle", margin: 0,
    fontFace: mono ? MONO : CN, fontSize, bold: !!bold, color: textColor,
  });
}

// 终端窗口：面板 + 红黄绿圆点标题栏 + 逐行等宽文本（每行一条 addText，runs 数组混色）
// lines: 行数组；每行是 runs 数组 [{t, c, b}]
function terminal(slide, x, y, w, h, title, lines, fontSize, paraSpace) {
  fontSize = fontSize || 11.5;
  paraSpace = paraSpace || 5;
  slide.addShape("ROUNDED_RECTANGLE", {
    x, y, w, h, rectRadius: 0.09,
    fill: { color: F.panel }, line: { color: F.panelLine, width: 1 },
  });
  ["FF5F57", "FEBC2E", "28C840"].forEach((c, i) => {
    slide.addShape("ELLIPSE", {
      x: x + 0.22 + i * 0.22, y: y + 0.17, w: 0.13, h: 0.13,
      fill: { color: c },
    });
  });
  slide.addText(title, {
    x: x + 0.95, y: y + 0.08, w: w - 1.15, h: 0.3,
    valign: "middle", margin: 0, fontFace: MONO, fontSize: 10, color: "8A94A6",
  });
  slide.addShape("RECTANGLE", {
    x: x + 0.15, y: y + 0.46, w: w - 0.3, h: 0.012,
    fill: { color: F.panelLine },
  });
  const lineH = (fontSize * 1.25 + paraSpace) / 72;
  let ly = y + 0.62;
  for (const runs of lines) {
    slide.addText(
      runs.map((r) => ({ text: r.t, options: { color: r.c, bold: !!r.b } })),
      { x: x + 0.3, y: ly, w: w - 0.6, h: lineH, margin: 0, fontFace: MONO, fontSize, valign: "middle" }
    );
    ly += lineH;
  }
}

function badge(slide, x, y, d, num, fillColor, textColor, lineColor) {
  slide.addShape("ELLIPSE", {
    x, y, w: d, h: d,
    fill: { color: fillColor },
    line: lineColor ? { color: lineColor, width: 1.5 } : undefined,
  });
  slide.addText(String(num), {
    x, y, w: d, h: d, align: "center", valign: "middle", margin: 0,
    fontFace: CN, fontSize: 14, bold: true, color: textColor,
  });
}

// ============================================================
// 第 1 页 · 封面（深色）—— 真实数字：302 行 / 4.73 秒 / 7/7 Pester
// ============================================================
const s1 = pptx.addSlide();
s1.addNotes(
  "开场 40 秒。Only-U 是装在普通 U 盘里的 Windows 运维 Agent：插上、双击、出诊断，不用安装任何东西。右边是真实运行的诊断输出：磁盘、内存、关键事件、SMART、进程、打印机、驱动异常，一屏全出——302 行零依赖 PowerShell，不联网、不调模型，实机 4.73 秒跑完，7 项 Pester 测试全过。需求不是编的：队长用 U 盘跑 Claude Code 修机，一个月几十台，最常见就是 C 盘满、卡死、打印机、蓝屏。"
);
s1.addShape("RECTANGLE", { x: 0, y: 0, w: 13.33, h: 7.5, fill: { color: F.ink } });

// 赛事信息
s1.addShape("ROUNDED_RECTANGLE", {
  x: 0.8, y: 0.7, w: 4.55, h: 0.44, rectRadius: 0.22,
  fill: { color: F.panel }, line: { color: F.panelLine, width: 1 },
});
s1.addText("赤兔 AI 黑客松 · 产品赛道「单人成军」", {
  x: 0.8, y: 0.7, w: 4.55, h: 0.44, align: "center", valign: "middle", margin: 0,
  fontFace: CN, fontSize: 11, color: F.ice,
});

// 标题
s1.addText("Only-U", {
  x: 0.8, y: 1.35, w: 7.2, h: 1.0, margin: 0,
  fontFace: "Calibri", fontSize: 64, bold: true, color: F.white,
});
s1.addText([
  { text: "U 盘 ", options: { color: F.green, bold: true } },
  { text: "插上就跑的 Windows 运维 Agent", options: { color: F.white, bold: true } },
], {
  x: 0.8, y: 2.5, w: 7.4, h: 0.62, margin: 0,
  fontFace: CN, fontSize: 26, valign: "middle",
});

// 核心口号
pill(s1, 0.8, 3.42, 3.95, 0.58, F.green, null, "插上 · 双击 · 出诊断 —— 不用安装", F.ink, 15, true);

// 三个硬数字（代码实况）
[["302 行", "零依赖诊断器"], ["4.73 秒", "实机出报告"], ["7/7", "Pester 测试"]].forEach(([num, label], i) => {
  const x = 0.8 + i * 2.45;
  s1.addText(num, {
    x, y: 4.25, w: 2.25, h: 0.55, margin: 0,
    fontFace: "Calibri", fontSize: 30, bold: true, color: F.green,
  });
  s1.addText(label, {
    x, y: 4.82, w: 2.25, h: 0.32, margin: 0,
    fontFace: CN, fontSize: 12, color: F.soft,
  });
});

// 底部备注
s1.addText("需求来自真实修机：U 盘跑 Claude Code · 一个月几十台 · C 盘满 / 卡死 / 打印机 / 蓝屏", {
  x: 0.8, y: 6.7, w: 7.2, h: 0.35, margin: 0, fontFace: CN, fontSize: 11, color: F.muted,
});

// 右侧终端窗口（真实诊断输出样式）
terminal(s1, 8.15, 1.0, 4.4, 5.35, "C:\\Only-U\\portable — 诊断.cmd", [
  [{ t: "> ", c: F.green, b: true }, { t: "diagnose.cmd", c: F.white, b: true }, { t: "  · 只读体检", c: F.muted }],
  [{ t: "红灯区：无 —— 未见致命异常", c: F.green, b: true }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 磁盘 C: 剩余 23.4 GB (12%)", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 内存 62% · 提交 58% <90%", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 7 天关键事件 0 条 (2004/存储超时)", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " SMART 健康 · 0 不可纠正读错", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " Top5 内存进程已列出（只列不杀）", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 打印机正常 · PnP 异常设备 0", c: F.soft }],
  [{ t: "[!]", c: F.amber, b: true }, { t: " 临时目录可回收 ~4.1 GB（只统计）", c: F.white }],
  [{ t: "4.73s · 零依赖 · 不联网 · 报告随盘带走", c: F.ice }],
  [{ t: "▌", c: F.green, b: true }],
]);

// ============================================================
// 第 2 页 · 一套脚本两条路径 + 双层防护（浅色）
// ============================================================
const s2 = pptx.addSlide();
s2.addNotes(
  "中间 40 秒。没网也饿不死：诊断脚本就是地板，双击就能跑，扫描有限时限量——每个目录 8 秒、2 万文件上限，超了就跳过，绝不把人家的破电脑扫卡死；拒绝 UNC、跳过重解析点。清理是双层防护：白名单只有 4 个 Temp 目录，桌面、文档、下载、图片前缀直接封锁；默认预览，用户说「确认」才真删。有网是加分项：start.cmd 拉起 TUI，Agent 调的是同一套脚本——清理逻辑不写两份。"
);
s2.addShape("RECTANGLE", { x: 0, y: 0, w: 13.33, h: 7.5, fill: { color: F.bgLight } });

s2.addText("一套脚本，两条路径", {
  x: 0.8, y: 0.5, w: 8, h: 0.65, margin: 0, fontFace: CN, fontSize: 34, bold: true, color: F.inkText,
});
s2.addText("没网能诊断，有网能聊天；安全是结构，不是口号", {
  x: 0.8, y: 1.16, w: 8, h: 0.4, margin: 0, fontFace: CN, fontSize: 14, color: F.mutedLight,
});

// 卡片 A：离线
s2.addShape("ROUNDED_RECTANGLE", {
  x: 0.8, y: 1.85, w: 5.69, h: 3.35, rectRadius: 0.08,
  fill: { color: F.white }, line: { color: F.cardLine, width: 1 }, shadow: shadow(),
});
badge(s2, 1.1, 2.12, 0.36, 1, F.greenDark, F.white);
s2.addText("离线路径 · 没网也能跑", {
  x: 1.6, y: 2.03, w: 3.4, h: 0.5, margin: 0, valign: "middle",
  fontFace: CN, fontSize: 16, bold: true, color: F.inkText,
});
pill(s2, 5.05, 2.17, 1.15, 0.34, F.amberTint, F.amberTintLine, "演示保底", F.amberDark, 9.5, true);
terminal(s2, 1.1, 2.72, 5.1, 1.68, "C:\\Only-U\\portable", [
  [{ t: "> ", c: F.greenDark, b: true }, { t: "diagnose.cmd · 只读 · 4.73s 出报告", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 扫描限时 8s/目录 · 限量 20k 文件", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 拒 UNC · 跳重解析点 · 可取消", c: F.soft }],
  [{ t: "> ", c: F.greenDark, b: true }, { t: "clean.cmd · 默认预览", c: F.soft }],
], 10, 2);
s2.addText("扫描超限就跳过——绝不把客户的破电脑扫卡死", {
  x: 1.1, y: 4.52, w: 5.1, h: 0.45, margin: 0, fontFace: CN, fontSize: 11.5, color: F.mutedLight,
});

// 卡片 B：有网
s2.addShape("ROUNDED_RECTANGLE", {
  x: 6.84, y: 1.85, w: 5.69, h: 3.35, rectRadius: 0.08,
  fill: { color: F.white }, line: { color: F.cardLine, width: 1 }, shadow: shadow(),
});
badge(s2, 7.14, 2.12, 0.36, 2, F.greenDark, F.white);
s2.addText("有网路径 · TUI 里的 Agent", {
  x: 7.64, y: 2.03, w: 3.4, h: 0.5, margin: 0, valign: "middle",
  fontFace: CN, fontSize: 16, bold: true, color: F.inkText,
});
pill(s2, 11.15, 2.17, 1.15, 0.34, F.greenTint, F.greenTintLine, "加分项", F.greenDark, 9.5, true);
terminal(s2, 7.14, 2.72, 5.1, 1.68, "dsh-tui — start.cmd", [
  [{ t: "you> ", c: F.greenDark, b: true }, { t: " C 盘满了，帮我看看", c: F.white }],
  [{ t: "Agent> ", c: F.ice, b: true }, { t: " 已跑诊断 · 红灯区无异常", c: F.soft }],
  [{ t: "Agent> ", c: F.ice, b: true }, { t: " 预览：临时目录可回收 4.1 GB", c: F.soft }],
  [{ t: "等你确认后才 -Execute …", c: F.amber }],
], 10, 2);
s2.addText("自然语言 → 调的是同一套 ps1（skill 硬约束）", {
  x: 7.14, y: 4.52, w: 5.1, h: 0.45, margin: 0, fontFace: CN, fontSize: 11.5, color: F.mutedLight,
});

// 中间说明
s2.addText([
  { text: "两条路径共用 ", options: { color: F.mutedLight } },
  { text: "portable\\*.ps1", options: { fontFace: MONO, color: F.greenDark, bold: true } },
  { text: " —— 清理逻辑不写两份", options: { color: F.mutedLight } },
], {
  x: 0.8, y: 5.36, w: 11.73, h: 0.4, align: "center", margin: 0,
  fontFace: CN, fontSize: 12, valign: "middle",
});

// 双层防护底线条
s2.addShape("ROUNDED_RECTANGLE", {
  x: 0.8, y: 5.95, w: 11.73, h: 0.95, rectRadius: 0.12,
  fill: { color: F.inkText },
});
s2.addText([
  { text: "双层误删防护：", options: { color: F.green, bold: true } },
  { text: "白名单仅 4 个 Temp 目录 · ", options: { color: F.white } },
  { text: "桌面/文档/下载/图片 前缀封锁", options: { color: F.green, bold: true } },
  { text: " · 默认预览 · 显式确认", options: { color: F.white } },
], {
  x: 1.2, y: 5.95, w: 10.9, h: 0.95, margin: 0, valign: "middle", align: "center",
  fontFace: CN, fontSize: 14,
});

// ============================================================
// 第 3 页 · 密封运行时 + 多 agent 开发 + 收束（深色）
// ============================================================
const s3 = pptx.addSlide();
s3.addNotes(
  "收尾 40 秒。最难的不是接模型，是把 LLM 运行时塞进 FAT32 U 盘：pnpm 的符号链接在 FAT32 上活不了，我们用 bake-usb.ps1 打出扁平化 CLI，还二进制 patch 了上游的 ensureSymlink 让它容忍 FAT32——客户机零安装，拔盘带走，数据不落客户机。开发模式也是卖点：队长定 ADR，两位队友各自的 AI agent 按 GitHub issue 开分支交 PR，用 agent 团队交付 agent 产品。一句话：不用安装、不敢乱删。无线网卡是下一阶段。"
);
s3.addShape("RECTANGLE", { x: 0, y: 0, w: 13.33, h: 7.5, fill: { color: F.ink } });

s3.addText("把 LLM 运行时烤进 FAT32 U 盘", {
  x: 0.8, y: 0.5, w: 9.5, h: 0.6, margin: 0, fontFace: CN, fontSize: 32, bold: true, color: F.white,
});
s3.addText("客户机零安装 · 拔盘带走 · 数据不落客户机", {
  x: 0.8, y: 1.13, w: 9, h: 0.4, margin: 0, fontFace: CN, fontSize: 13, color: F.muted,
});

const rows = [
  ["bake-usb.ps1 · 230 行烤盘", "pnpm deploy 扁平化 dsh CLI + 便携 Node → 不装 Node / pnpm / CLI"],
  ["二进制 patch ensureSymlink", "上游运行时依赖 NTFS 符号链接，patch 后容忍 FAT32 —— 真实 U 盘能跑"],
  ["多 Agent 协作开发", "队长定 ADR，队友的 AI agent 按 issue 开分支交 PR —— 用 agent 团队交付 agent 产品"],
];
rows.forEach(([head, desc], i) => {
  const y = 1.75 + i * 1.37;
  s3.addShape("ROUNDED_RECTANGLE", {
    x: 0.8, y, w: 7.4, h: 1.15, rectRadius: 0.09,
    fill: { color: F.panel }, line: { color: F.panelLine, width: 1 },
  });
  badge(s3, 1.1, y + 0.36, 0.42, i + 1, F.panel, F.green, F.green);
  s3.addText(head, {
    x: 1.75, y: y + 0.12, w: 6.25, h: 0.38, margin: 0,
    fontFace: CN, fontSize: 15, bold: true, color: F.white, valign: "middle",
  });
  s3.addText(desc, {
    x: 1.75, y: y + 0.56, w: 6.3, h: 0.5, margin: 0,
    fontFace: CN, fontSize: 11, color: F.ice,
  });
});

// 右侧烤盘终端
terminal(s3, 8.5, 1.75, 4.05, 2.85, "开发机 — 烤盘", [
  [{ t: "> ", c: F.green, b: true }, { t: "scripts\\bake-usb.ps1 -Dest F:\\Only-U", c: F.white }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " pnpm deploy 扁平化 dsh CLI", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " patch ensureSymlink (FAT32)", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " 便携 node.exe + profile 入盘", c: F.soft }],
  [{ t: "[OK]", c: F.green, b: true }, { t: " GBK 入口 cmd · --help 自检过", c: F.soft }],
  [{ t: "[OK] 密封完成 —— 拔盘带走", c: F.green, b: true }],
], 10.5, 4);
pill(s3, 8.5, 4.85, 1.95, 0.42, F.panel, F.panelLine, "FAT32 · 无符号链接", F.ice, 10.5, false, true);
pill(s3, 10.6, 4.85, 1.95, 0.42, F.panel, F.panelLine, "客户机零安装", F.ice, 10.5, false, true);

// 收束条
s3.addShape("ROUNDED_RECTANGLE", {
  x: 0.8, y: 5.95, w: 11.73, h: 0.95, rectRadius: 0.12,
  fill: { color: F.panel }, line: { color: F.panelLine, width: 1 },
});
s3.addText([
  { text: "「不用安装 · ", options: { color: F.white } },
  { text: "不敢乱删", options: { color: F.green } },
  { text: "」", options: { color: F.white } },
], {
  x: 0.8, y: 5.95, w: 11.73, h: 0.95, align: "center", valign: "middle", margin: 0,
  fontFace: CN, fontSize: 24, bold: true,
});
s3.addText("无线网卡 · 下一阶段", {
  x: 9.9, y: 6.28, w: 2.5, h: 0.3, margin: 0, align: "right",
  fontFace: CN, fontSize: 10.5, color: F.muted,
});

pptx.writeFile({ fileName: "Only-U-演示.pptx" }).then((f) => console.log("written:", f));
