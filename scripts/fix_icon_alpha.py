# -*- coding: utf-8 -*-
"""
fix_icon_alpha.py
独立处理鸿蒙应用图标 planer_icon.png，使其符合上架规则：
  1) 尺寸 1024x1024（本图已满足，仅校验，不缩放、不裁剪）
  2) 去除全部透明像素：对 alpha<255 的区域，用"最近邻不透明像素颜色"无缝填充
     （图标背景是蓝绿渐变，最近邻填充可让渐变自然延伸到四角，避免突兀色块）
  3) 输出为不透明 RGB PNG

用法：
  python fix_icon_alpha.py <src.png> [--out <dst.png>]
默认原地覆盖，并自动在同目录生成 <文件名>.bak 备份（已存在则不覆盖）。
"""

import argparse
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TARGET_SIZE = (1024, 1024)


def fill_transparent_with_nearest(img: Image.Image) -> Image.Image:
    """去透明，返回 RGB 图像。分两阶段：

    阶段一（背景传播）：只用完全不透明（alpha=255）像素的颜色，
    通过四邻域迭代扩散填满所有透明区域，得到连续的背景层
    （图标背景为蓝绿渐变，最近邻传播可让渐变自然延伸到四角）。

    阶段二（alpha 合成）：对半透明像素（0<alpha<255），按其 alpha
    与原颜色做标准 over 合成到背景层上，保留抗锯齿边缘，避免硬接缝。
    """
    rgba = np.array(img.convert("RGBA"), dtype=np.uint8)
    rgb = rgba[..., :3].astype(np.int32)
    alpha = rgba[..., 3]

    opaque = alpha == 255
    if opaque.all():
        return Image.fromarray(rgba[..., :3], "RGB")

    # ---- 阶段一：背景传播 ----
    filled = rgb.copy()
    frontier = opaque.copy()
    unknown = ~opaque
    while unknown.any():
        grown = frontier.copy()
        # 四方向平移，标记能从已知区域到达的新像素
        grown[1:, :] |= frontier[:-1, :]
        grown[:-1, :] |= frontier[1:, :]
        grown[:, 1:] |= frontier[:, :-1]
        grown[:, :-1] |= frontier[:, 1:]

        new_pixels = grown & unknown
        if not new_pixels.any():      # 理论上不会发生，防御性退出
            break

        # 对每个新像素，从四邻域的已知颜色中取一个，优先级：上/下/左/右
        cand_up = np.zeros_like(filled)
        cand_up[1:, :] = filled[:-1, :]
        up_ok = np.zeros_like(frontier)
        up_ok[1:, :] = frontier[:-1, :]

        dn_ok = np.zeros_like(frontier)
        dn_ok[:-1, :] = frontier[1:, :]
        cand_dn = np.zeros_like(filled)
        cand_dn[:-1, :] = filled[1:, :]

        lf_ok = np.zeros_like(frontier)
        lf_ok[:, 1:] = frontier[:, :-1]
        cand_lf = np.zeros_like(filled)
        cand_lf[:, 1:] = filled[:, :-1]

        rt_ok = np.zeros_like(frontier)
        rt_ok[:, :-1] = frontier[:, 1:]
        cand_rt = np.zeros_like(filled)
        cand_rt[:, :-1] = filled[:, 1:]

        remaining = new_pixels.copy()
        for ok, c in ((up_ok, cand_up), (dn_ok, cand_dn), (lf_ok, cand_lf), (rt_ok, cand_rt)):
            m = remaining & ok
            if m.any():
                filled[m] = c[m]
                remaining &= ~m

        frontier |= new_pixels
        unknown &= ~new_pixels

    # ---- 阶段二：半透明像素做 alpha over 合成 ----
    semi = (alpha > 0) & (alpha < 255)
    if semi.any():
        a = alpha[semi].astype(np.float32)[:, None] / 255.0
        filled[semi] = (rgb[semi] * a + filled[semi] * (1.0 - a)).astype(np.int32)

    out = np.clip(filled, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def verify(path: Path, original: Image.Image) -> None:
    """上架规则校验：尺寸 / 无透明 / 无裁剪（原不透明像素颜色不变）/ 格式 PNG。"""
    img = Image.open(path)
    assert img.size == TARGET_SIZE, f"尺寸不符: {img.size}"
    assert img.format == "PNG", f"格式不符: {img.format}"
    assert img.mode == "RGB", f"色彩模式不符: {img.mode}（应为无 alpha 的 RGB）"

    arr = np.array(img)
    assert arr.shape == (TARGET_SIZE[1], TARGET_SIZE[0], 3), "通道数异常"

    # 无裁剪校验：原图中完全不透明的像素，处理后颜色必须完全一致
    orig = np.array(original.convert("RGBA"), dtype=np.uint8)
    opaque = orig[..., 3] == 255
    same = (arr[opaque] == orig[..., :3][opaque]).all()
    assert same, "原不透明区域颜色被改动，图标主体不完整"

    print("[校验通过]")
    print(f"  尺寸        : {img.size[0]}x{img.size[1]}")
    print(f"  格式        : {img.format}")
    print(f"  色彩模式    : {img.mode}（无 alpha 通道，不存在透明像素）")
    print(f"  主体完整性  : 原不透明像素 100% 保持不变，无裁剪")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="待处理的 PNG 路径")
    ap.add_argument("--out", help="输出路径（默认原地覆盖并生成 .bak 备份）")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.is_file():
        print(f"文件不存在: {src}", file=sys.stderr)
        return 1

    original = Image.open(src)
    print(f"处理前: size={original.size}, mode={original.mode}, format={original.format}")

    fixed = fill_transparent_with_nearest(original)

    out = Path(args.out) if args.out else src
    if out == src:
        bak = src.with_suffix(src.suffix + ".bak")
        if not bak.exists():
            shutil.copy2(src, bak)
            print(f"已备份原图 -> {bak}")

    fixed.save(out, format="PNG")
    print(f"已写出 -> {out}")

    verify(out, original)
    return 0


if __name__ == "__main__":
    sys.exit(main())
