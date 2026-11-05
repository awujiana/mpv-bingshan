#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v1.0.9 真机 E2E 夹具：用纯 Python 生成「内封 ASS 字幕」的最小 Matroska。

为什么需要自己写 muxer
----------------------
`uosc_subtitle_style` v1.0.9 的 ASS `Fontsize` 通道只在
`current-tracks/sub.external == false`（**内封**轨）时启用，因为只有内封 ASS
才会同时具备「带 `\\pos` 的 explicit 事件」+ 可读的 `sub-ass-extradata`。
用 `--sub-file=x.ass` 加载的是外挂轨，测不到新通道；直接 `mpv x.ass`
又因为没有视频/音频流而拒绝加载；真实示例 MKV 有 4.1 GB 且不在仓库里，
不可能进门禁。本机也没有 ffmpeg。

所以这里直接按 EBML/Matroska 规范写一个最小容器（约 5 KB）：

* 1 条 `V_MJPEG` 视频轨 —— Pillow 生成的 640x360 单帧静态画面，
  `bars>0` 时上下各留 `bars` px 纯黑条（模拟视频内嵌黑边，不是窗口 letterbox）。
* 1 条 `S_TEXT/ASS` 字幕轨 —— `CodecPrivate` 存 ASS 头（含 `PlayResY` 与
  `Style: Default,...,Fontsize`），`BlockGroup` 存事件；mpv 解析后
  `track-list` 里该轨 `external=false`，`sub-ass-extradata` 可读。

事件固定两条：`{\\pos(320,60)}TOPDIALOG`（explicit，`sub-pos`/`sub-scale`/
`sub-font-size` 对它无效，正是用户报障的「点缩放没反应」）与
`BOTTOMDIALOG`（普通对白，走原生通道）。探针只统计上字幕带 y20..130，
避开底部 OSD 提示与 uosc 控件。

用法
----
由 `tools/sub-style-e2e.py` 通过 importlib 调用 `build(path, bars=...)`；
也可单独运行生成文件自查：

    C:\\Python314\\python.exe tools/sub-style-mkv-fixture.py out.mkv 24
"""

import io
import struct

from PIL import Image

WIDTH, HEIGHT = 640, 360
DEFAULT_FONTSIZE = 20
DEFAULT_EVENTS = (
    '{\\pos(320,60)}TOPDIALOG',
    'BOTTOMDIALOG',
)

# ASS 样式表必须写在 CodecPrivate 里（Matroska 的 S_TEXT/ASS 规范）：
# 事件块只带 ReadOrder/Layer/Style/.../Text，样式表不会出现在 Block 内。
ASS_HEADER_TMPL = '''[Script Info]
ScriptType: v4.00+
PlayResX: 640
PlayResY: {playres_y}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,{fontsize},&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

'''


# ---- 最小 EBML 编码 ----------------------------------------------------

def _size(n, width=None):
    """EBML VINT 尺寸（首位为标记位）。width 给定时按固定字节数编码。"""
    if width is None:
        for w in (1, 2, 3, 4, 8):
            if n < (1 << (7 * w)) - 1:
                width = w
                break
    if width is None:
        raise ValueError('payload too large')
    return (n | (1 << (7 * width))).to_bytes(width, 'big')


def _el(eid, payload, width=None):
    return bytes.fromhex(eid) + _size(len(payload), width) + payload


def _uint(v):
    return b'\x00' if v == 0 else v.to_bytes((v.bit_length() + 7) // 8, 'big')


def _u(eid, v):
    return _el(eid, _uint(v))


def _s(eid, v):
    return _el(eid, v.encode('utf-8') if isinstance(v, str) else v)


def _block_group(track_no, text, read_order=None, duration_ms=60000):
    """Matroska BlockGroup：Block + BlockDuration（TimecodeScale=1ms）。"""
    if read_order is None:
        payload = text                       # 视频帧：原始 JPEG 字节
    else:
        # S_TEXT/ASS 块格式：ReadOrder,Layer,Style,Actor,MarginL,MarginR,
        #                    MarginV,Effect,Text
        payload = ('%d,0,Default,,0,0,0,,%s' % (read_order, text)).encode('utf-8')
    block = bytes([0x80 | track_no]) + struct.pack('>h', 0) + b'\x00' + payload
    return _el('A0', _el('A1', block) + _u('9B', duration_ms))


def build(path, bars=0, fontsize=DEFAULT_FONTSIZE, events=DEFAULT_EVENTS,
          frame_color=(110, 110, 110)):
    """写出 MKV，返回 path。bars>0 表示上下各留这么多像素的纯黑条。"""
    if not 0 <= bars < HEIGHT // 2:
        raise ValueError('bars out of range: %r' % (bars,))

    header = b''.join([
        _u('4286', 1),                 # EBMLVersion
        _u('42F7', 1),                 # EBMLReadVersion
        _u('42F2', 4),                 # EBMLMaxIDLength
        _u('42F3', 8),                 # EBMLMaxSizeLength
        _s('4282', 'matroska'),        # DocType
        _u('4287', 4),                 # DocTypeVersion
        _u('4285', 2),                 # DocTypeReadVersion
    ])
    ebml = _el('1A45DFA3', header)

    ass_header = ASS_HEADER_TMPL.format(playres_y=HEIGHT, fontsize=fontsize)
    video_track = b''.join([
        _u('D7', 1),                   # TrackNumber
        _u('73C5', 2),                 # TrackUID
        _u('83', 1),                   # TrackType=video
        _s('86', 'V_MJPEG'),           # CodecID
        _u('9C', 0),                   # FlagLacing=0
        _el('E0', _u('B0', WIDTH) + _u('BA', HEIGHT)),   # Video/PixelWidth/Height
    ])
    sub_track = b''.join([
        _u('D7', 2),                   # TrackNumber
        _u('73C5', 3),                 # TrackUID
        _u('83', 17),                  # TrackType=subtitle
        _s('86', 'S_TEXT/ASS'),
        _s('63A2', ass_header),        # CodecPrivate = ASS 头
    ])
    info = b''.join([
        _u('2AD7B1', 1000000),         # TimecodeScale = 1ms
        _s('4D80', 'sub-style-e2e'),
        _s('5741', 'sub-style-e2e'),
    ])
    tracks = _el('1654AE6B', _el('AE', video_track) + _el('AE', sub_track))

    frame = Image.new('RGB', (WIDTH, HEIGHT), (0, 0, 0))
    if bars:
        frame.paste(frame_color, (0, bars, WIDTH, HEIGHT - bars))
    else:
        frame.paste(frame_color, (0, 0, WIDTH, HEIGHT))
    buf = io.BytesIO()
    frame.save(buf, 'JPEG', quality=90)

    blocks = [_block_group(1, buf.getvalue())]
    for i, text in enumerate(events):
        blocks.append(_block_group(2, text, read_order=i))
    cluster = _el('1F43B675', _u('E7', 0) + b''.join(blocks))

    # Segment 用 8 字节 unknown size，省得回填长度；mpv/ffmpeg 都接受。
    segment = (bytes.fromhex('18538067') + b'\x01' + b'\xff' * 7
               + _el('1549A966', info) + tracks + cluster)
    with open(path, 'wb') as f:
        f.write(ebml + segment)
    return path


if __name__ == '__main__':
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else 'internal-ass.mkv'
    bar = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    import os
    build(out, bars=bar)
    print('WROTE %s bytes=%d bars=%d' % (out, os.path.getsize(out), bar))
