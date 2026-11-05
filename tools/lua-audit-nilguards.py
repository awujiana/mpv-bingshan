# -*- coding: utf-8 -*-
"""扫描「被 nil 守卫掩盖的错误调用」—— 本项目踩过多次同类坑，故固化此检查。

背景（2026-10-05）：
  本项目连续发现 4 处「有 nil/类型守卫，所以不崩溃，但功能静默失效」的缺陷：
    1. require 'osd-button' 失败（script-modules 不在 package.path）
    2. mp.command_native({"command","expand-path",…}) 返回 nil（3 个站点）
    3. notify.info 被当 printf 用 → duration 收到字符串 → 抛错
    4. （同上第 3 类的第 4 个站点）
  它们的共同点：**静态语法检查全过，真机才炸**。
  教训：**「有 nil 守卫」不等于「安全」** —— 它把「崩溃」变成了「静默不工作」，
  后者更难发现。

本脚本做四类静态检查：
  A. command_native 首元素是否是多余的 "command" 包装（必返回 nil）
  B. notify.* 是否被当 printf 用（首参含格式符 且 传了额外参数）
  C. command_native 返回值是否被直接 :method() 调用（真实返回 nil 时才会抛错）
  D. require 'x' 的模块是否真的在可搜索路径上（script-modules 需手动 prepend）

规则 B/C 的精确度是实测校准过的（2026-10-05），见下方各自注释 ——
**静态检查工具的误报比没有工具更糟**，它会训练人忽略告警。
落地校准的两条实测结论（见 tools/probe-expand-text.lua）：
  · expand-text **不会**返回 nil（未定义属性→"(error)"，非法模板→原样），
    故 TopBar.lua:40 的 `:gsub()` 链式调用安全 → 规则 C 跳过它并整体降为 INFO。
  · notify 的首参若已是 `string.format(...)` 的返回值，是**正确**写法，
    不能被规则 B 命中 → 用 strip_nested_calls() 剥掉嵌套实参后再判定。

自检：本工具的检出能力用「金丝雀」验证过（故意重新注入 4 类缺陷后应全部命中，
而正确写法的 3 行应保持静默）。改动规则后请重跑金丝雀，避免规则失效无人察觉。

用法：python tools/lua-audit-nilguards.py
退出码：0 = 无 P0/P1，1 = 有 P0/P1（INFO 不影响退出码）
"""
import re, glob, os, sys

FILES = []
for pat in ('scripts/**/*.lua', 'script-modules/**/*.lua', 'osc-style/**/*.lua'):
    FILES += glob.glob(pat, recursive=True)

findings = []   # (级别, 规则, 文件, 行号, 代码, 说明)

def add(level, rule, path, i, line, note):
    findings.append((level, rule, path, i, line.strip(), note))

for path in FILES:
    src = open(path, encoding='utf-8', errors='ignore').read()
    lines = src.split('\n')

    # 判断某行是否为注释（-- 开头，或 doxygen --[[ ]] 块内）。
    # 必须排除注释，否则会把「解释这个 bug 的注释」和「示例代码」误报为 bug
    # —— 工具误报比没有工具更糟，会训练人忽略告警。
    #
    # ⚠️ 2026-10-06 修正：初版对块注释是「从当前行往前找未闭合的 --[[」逐行判定，
    #    但块内**第 2 行起**往前扫到 `--[[` 那一行时 opens/closes 正好抵消，
    #    判定立刻返回 False —— 于是块注释中段的正文被当成了代码。
    #    实测后果：chapterskip.lua 头部注释里的 "chapterskip.lua"、
    #    hash.lua 注释里的 "sha256" 都被当成变量引用，凭空多出 5 条误报。
    #    改为**一次性预扫**整份文件，标记块注释区间。
    block_comment = [False] * len(lines)
    in_block = False
    for k, l in enumerate(lines):
        if in_block:
            block_comment[k] = True
        pos = 0
        while pos < len(l):
            if in_block:
                end = l.find(']]', pos)
                if end == -1:
                    break
                in_block = False
                pos = end + 2
            else:
                c = l.find('--', pos)
                if c == -1:
                    break
                if l.startswith('--[[', c):
                    in_block = True
                    block_comment[k] = True
                    pos = c + 4
                else:
                    # 普通行注释：本行剩余全是注释，不可能再起块
                    break

    def is_comment(idx):
        if block_comment[idx]:
            return True
        return lines[idx].lstrip().startswith('--')

    def code_of(idx):
        """返回该行去掉行尾注释后的部分，用于规则匹配。"""
        ln = lines[idx]
        # 去掉 -- 之后的同行注释（不处理字符串内的 --，够用）
        pos = ln.find('--')
        return ln if pos < 0 else ln[:pos]

    def strip_nested_calls(s):
        """把嵌套的 (...) 调用替换成占位符，只保留最外层的括号。

        用途：规则 B 要判断「格式符字面量是不是 notify 的第一个实参」。
        若该字面量位于一个嵌套调用内部（典型：string.format("%s = %s", ...)），
        它是**已修正**的正确写法，不应命中。
        此前用朴素正则 `%s` 后跟逗号来匹配，会把 string.format 内的字面量
        误判为 notify 的首参 —— 这是本工具唯一一处真实误报（dispatcher.lua:590），
        在这里根治。
        """
        out = []
        depth = 0
        for ch in s:
            if ch == '(':
                depth += 1
                if depth == 1:
                    out.append(ch)
            elif ch == ')':
                if depth == 1:
                    out.append(ch)
                depth = max(0, depth - 1)
            elif depth == 0:
                out.append(ch)
            # depth >= 2 的内容整体丢弃（即嵌套调用的实参列表）
        return ''.join(out)

    # A. command_native({"command", ...}) —— 多余包装
    for i, ln in enumerate(lines, 1):
        if is_comment(i - 1):
            continue
        if re.search(r'command_native\s*\(\s*\{\s*["\']command["\']\s*,', code_of(i - 1)):
            add('P0', 'A/command_native 多余包装', path, i, ln,
                '首元素是 "command" → 必返回 nil，mpv 报 Command \'command\' not found')

    # B. notify.* 被当 printf 用
    #
    # 判定两点，缺一不可：
    #   (1) notify 的**第一个实参**本身是含格式符的字面量（而非变量，
    #       也非 string.format(...) 的返回值）；
    #   (2) 该调用还有第二个实参（会被当成 tag）。
    # 只有两者同时成立才是真缺陷 —— 此时第三个位置（duration）若有值
    # 就会是字符串，mp.osd_message 对它做算术直接抛错（已实测复现）。
    #
    # 格式符全集按 Lua 标准来：%d %i %u %o %x %X %e %E %f %g %G %c %q %%（以及 %5.2f 这类）。
    # 此前只查 %s/%d，会漏掉 string.format("%d items", n) 之外的写法。
    FMT_SPEC = r'%[-+ #0]*\d*\.?\d*[diuoxXeEfgGqcs]'
    for i, ln in enumerate(lines, 1):
        if is_comment(i - 1):
            continue
        code = code_of(i - 1)
        m = re.search(r'notify\.(warn|info|error|success)\s*\(', code)
        if not m:
            continue
        outer = strip_nested_calls(code[m.end():])   # 只留最外层实参列表
        # (1) 第一个实参是字面量，且字面量里含格式符
        first = re.match(r'\s*(["\'])(.*?)\1', outer, re.S)
        if not first or not re.search(FMT_SPEC, first.group(2)):
            continue
        # (2) 后面还跟着逗号 → 有额外实参
        rest = outer[first.end():].lstrip()
        if not rest.startswith(','):
            continue
        # 排除「额外实参只是个数字/ nil」——那种情况 duration 类型正确，不算缺陷
        extra = rest[1:].strip()
        if re.fullmatch(r'[\d.]+|nil\s*\)?\s*$', extra):
            continue
        add('P0', 'B/notify 误用为 printf', path, i, ln,
            'notify 签名是 (text, tag, duration)，**不是 printf**；'
            '第三参会收到字符串 → mp.osd_message 对其做算术 → Lua error。'
            '改法：先用 string.format 预格式化再传入')

    # C. command_native(...):method() 无守卫
    #
    # 这一条**故意定为 INFO**，因为是否真的会抛错取决于是哪个命令：
    #   实测（2026-10-05，见 tools/probe-expand-text.md）：
    #     expand-text  **不会**返回 nil —— 未定义属性展开成字面量 "(error)"，
    #                   非法模板（如 "${"）原样返回。故 :gsub() 永远安全，
    #                   既不会抛错、也不会静默失效。
    #     expand-path  则**可能**返回 nil（这正是本机 3 处缺陷 2 的成因）。
    # 由于静态无法判定命令名，报 P0/P1 都会产生误报 → 降为 INFO，仅供人工确认。
    SAFE_CMD = ('expand-text',)   # 已实测不会返回 nil 的命令
    for i, ln in enumerate(lines, 1):
        if is_comment(i - 1):
            continue
        code = code_of(i - 1)
        m = re.search(r'command_native\s*\(\s*\{([^}]*)\}\s*\)\s*:\s*(\w+)', code)
        if not m:
            continue
        cmd = m.group(1)
        if any("'%s'" % c in cmd or '"%s"' % c in cmd for c in SAFE_CMD):
            continue   # 实测安全，不报
        add('INFO', 'C/返回值直接调方法', path, i, ln,
            'command_native 失败时返回 nil，直接 :%s() 会抛错。'
            '注意：expand-text 经实测不会返回 nil；expand-path 会。'
            '请人工确认命令名后再决定是否加守卫' % m.group(2))

    # D. require 的模块是否可达（只查 script-modules 下的自建模块）
    #    特例：模块文件自身文档里演示 require 用法是正常的，跳过模块自身。
    is_module_itself = path.replace('\\', '/').startswith('script-modules/')
    for i, ln in enumerate(lines, 1):
        if is_comment(i - 1):
            continue
        m = re.search(r"require\s*['\"]([^'\"]+)['\"]", code_of(i - 1))
        if not m:
            continue
        mod = m.group(1)
        if mod.startswith('mp') or mod.startswith('lib') or mod.startswith('modules'):
            continue
        candidate = 'script-modules/%s.lua' % mod
        if os.path.exists(candidate):
            # 模块文件自身的注释/示例不算
            if is_module_itself and os.path.basename(path) == mod + '.lua':
                continue
            if 'package.path' not in src:
                add('P0', 'D/模块不可达', path, i, ln,
                    "require '%s' 指向 %s，但本文件未 prepend package.path "
                    "→ mpv 只搜 <mpv根>/lua/，加载会失败" % (mod, candidate))

    # E. 局部变量在闭包中被引用，但 `local X = nil` 声明在其**后**
    #
    #    2026-10-06 新增。Lua 的局部变量作用域**从声明语句之后**才开始，
    #    所以把 `local X = nil` 写在引用它的回调闭包之后，闭包里的 X 会
    #    绑定到**全局变量**（mpv 环境中为 nil）：
    #        local h = mp.command_native_async({...}, function(...)
    #            if X and ... then ... end     -- X 是全局 nil → 恒为假
    #        end)
    #        local X = nil                      -- ← 太晚了，闭包看不到
    #    结果：那个分支**永不执行**，不报错、不崩溃 —— 又一例「守卫掩盖的静默失效」。
    #
    #    实测：本项目 7 个文件（apis/*.lua + modules/api.lua）全栽在这个模式上，
    #    变量名都是 registered_token，后果是 cancel_fn 永不从 request_registry
    #    注销 → 随每次请求无界增长。
    #
    #    ⚠️ 本规则的取向是「宁可漏报，不可误报」。初版只看缩进，一跑就 22 条，
    #    **全是误报**：把字符串内容（`"servers",`）、表字段（`title = title,`）、
    #    以及别的函数里恰好同名的局部量都算了进来。误报比没有工具更糟，
    #    所以这里加了 4 道抑制：
    #      (1) 先抹掉字符串字面量与注释再匹配 —— `"servers"` 不是引用
    #      (2) 字段位置不算引用 —— `.X` / `:X(` / 表字段 `X = v,`
    #      (3) 文件更早处（含同一行内、`X` 出现位置之前）已存在**同名绑定**
    #          （local 声明 / for 循环变量 / 函数参数）则跳过 ——
    #          说明那个引用绑的是别的变量，不是全局
    #      (4) 引用缩进必须严格大于声明缩进 —— 引用得在更深的嵌套块里
    #    代价：若同一文件更早处恰好有同名局部量，真缺陷会被漏掉。
    #    可接受 —— `registered_token` / `cancel_fn` 这类名字极不可能重名。
    def _strip_code(line):
        """抹掉字符串字面量内容与注释，只留代码骨架（不处理 [[ ]] 长串）。"""
        out, i, n, quote = [], 0, len(line), None
        while i < n:
            c = line[i]
            if quote:
                if c == '\\':
                    i += 2
                    continue
                if c == quote:
                    quote = None
                    out.append(c)
                i += 1
                continue
            if c in ('"', "'"):
                quote = c
                out.append(c)
                i += 1
                continue
            if line.startswith('--', i):
                break
            out.append(c)
            i += 1
        return ''.join(out)

    def _binds_name(name, code):
        """该行是否**声明/绑定**了 name（local 声明、for 循环变量、函数参数）。"""
        esc = re.escape(name)
        if re.search(r'\blocal\s+[^=]*\b%s\b' % esc, code):
            return True
        for hm in re.finditer(r'\bfor\s+([A-Za-z_][\w\s,]*?)\s*(?:in\b|=)', code):
            if re.search(r'\b%s\b' % esc, hm.group(1)):
                return True
        for pm in re.finditer(r'function\s*[^()]*\(([^()]*)\)', code):
            if re.search(r'\b%s\b' % esc, pm.group(1)):
                return True
        return False

    def _is_binding_here(code, start, end):
        """该出现处**本身**就是声明点（`local X` / `for X in` / 函数参数）。"""
        prefix = code[:start]
        if re.search(r'\blocal\s+[^=]*$', prefix):
            return True
        if re.search(r'\bfor\s+[^=]*$', prefix):
            return True
        fpos = prefix.rfind('function')
        if fpos >= 0:
            tail = prefix[fpos:]
            if tail.count('(') > tail.count(')'):
                return True
        return False

    def _is_field(code, start, end):
        """name 出现在 [start,end) 处，是否为字段名/字段访问而非变量引用。"""
        p = start - 1
        while p >= 0 and code[p] in ' \t':
            p -= 1
        if p >= 0 and code[p] in '.:':
            return True
        q = end
        while q < len(code) and code[q] in ' \t':
            q += 1
        if q < len(code) and code[q] == '=' and not code.startswith('==', q):
            return True
        return False

    decl_res = [
        re.compile(r'^(\s*)local\s+([A-Za-z_]\w*)\s*=\s*nil\s*(?:--.*)?$'),
        # `local function f()` 同理：函数体里引用**后面才定义**的 f 会绑到全局。
        # 2026-10-06 补：我自己在 apis/bangumi_user.lua 里把
        # `local function do_request` 写在 M.request **之后**，M.request 里的
        # do_request 编译成了全局引用 → 运行时 attempt to call a nil value。
        # 只认 `local X = nil` 的初版判据漏掉了这一类。
        re.compile(r'^(\s*)local\s+function\s+([A-Za-z_]\w*)\s*\('),
    ]
    for i, ln in enumerate(lines):
        if is_comment(i):
            continue
        m = None
        for r in decl_res:
            m = r.match(ln)
            if m:
                break
        if not m:
            continue
        name = m.group(2)
        if len(name) < 3:          # 跳过 i/j/k/n 这类临时变量
            continue
        decl_indent = len(m.group(1))
        ref_re = re.compile(r'\b%s\b' % re.escape(name))
        for j in range(i):
            if is_comment(j):
                continue
            code = _strip_code(lines[j])
            # (1)+(2) 只剩真正的**变量引用**位置（排除字符串、字段名、声明点本身）
            if not any(not _is_field(code, mm.start(), mm.end())
                       and not _is_binding_here(code, mm.start(), mm.end())
                       for mm in ref_re.finditer(code)):
                continue
            # (4) 引用必须落在更深的嵌套块里
            if len(lines[j]) - len(lines[j].lstrip()) <= decl_indent:
                continue
            # (3) 更早处已有同名绑定 → 该引用绑的不是全局
            if any(_binds_name(name, _strip_code(lines[k])) for k in range(j)):
                continue
            add('P1', 'E/闭包捕获全局（声明晚于引用）', path, i + 1, ln,
                "第 %d 行在更深缩进处引用了 '%s'，而它的 local 声明到第 %d 行"
                "才出现 → 闭包绑定的是全局变量（mpv 中为 nil），守卫恒为假 / "
                "调用即 attempt to call a nil value，该分支静默失效"
                % (j + 1, name, i + 1))
            break

# 输出
P0 = [f for f in findings if f[0] == 'P0']
P1 = [f for f in findings if f[0] == 'P1']
INFO = [f for f in findings if f[0] == 'INFO']

print("扫描 %d 个 Lua 文件" % len(FILES))
print("=" * 68)
if not findings:
    print("未发现可疑模式 ✅")
else:
    for level, rule, path, i, line, note in findings:
        print("[%s] %s" % (level, rule))
        print("     %s:%d" % (path, i))
        print("     %s" % line[:110])
        print("     → %s" % note)
        print()
print("=" * 68)
print("P0（必然静默失效/抛错）: %d" % len(P0))
print("P1（潜在隐患）: %d" % len(P1))
print("INFO（需人工确认，非缺陷）: %d" % len(INFO))
# 只有 P0/P1 才算「有发现」；INFO 不影响退出码，避免误报污染 CI
sys.exit(1 if (P0 or P1) else 0)
