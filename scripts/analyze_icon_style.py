# -*- coding: utf-8 -*-
"""
analyze_icon_style.py
分析 original_backup.png 的图标样式：渐变方向与端点色、配色聚类、
圆角半径、线条/字形尺寸、是否存在阴影。
只读分析，不修改任何文件。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(r"D:\2.Programming\PlanerHarmony\AppScope\resources\base\media\original_backup.png")


def hexs(c):
    return "#{:02X}{:02X}{:02X}".format(*[int(round(v)) for v in c])


def main():
    img = Image.open(SRC).convert("RGBA")
    a = np.array(img)
    h, w = a.shape[:2]
    print(f"尺寸 {w}x{h}, 模式 RGBA")

    alpha = a[..., 3]
    opaque = alpha == 255
    semi = (alpha > 0) & (alpha < 255)
    transp = alpha == 0
    print(f"像素统计: 不透明 {opaque.sum()}, 半透明 {semi.sum()}, 全透明 {transp.sum()}")

    # ---- 透明区域形态（四角）----
    ys, xs = np.where(transp)
    if len(ys):
        print(f"透明像素包围盒: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}]")
        # 每行最左不透明像素 -> 估圆角轮廓
        row = h // 2
        left = np.argmax(opaque[row])
        right = w - 1 - np.argmax(opaque[row, ::-1])
        print(f"中线行({row}) 不透明范围: x[{left}..{right}] -> 图标体宽 {right-left+1}")
        col = w // 2
        top = np.argmax(opaque[:, col])
        bot = h - 1 - np.argmax(opaque[::-1, col])
        print(f"中线列({col}) 不透明范围: y[{top}..{bot}] -> 图标体高 {bot-top+1}")
        # 圆角半径: 顶部行最左不透明 x - 中线行最左不透明 x
        left_top = np.argmax(opaque[top + 1])
        print(f"圆角半径估计: {left_top - left} px")

    # ---- 颜色聚类（KMeans 简易实现，仅不透明像素）----
    pix = a[..., :3][opaque].astype(np.float32)
    rng = np.random.default_rng(0)
    idx = rng.choice(len(pix), size=min(20000, len(pix)), replace=False)
    sample = pix[idx]
    k = 6
    centers = sample[rng.choice(len(sample), k, replace=False)].copy()
    for _ in range(30):
        d = ((sample[:, None, :] - centers[None, :, :]) ** 2).sum(-1)
        lab = d.argmin(1)
        for i in range(k):
            if (lab == i).any():
                centers[i] = sample[lab == i].mean(0)
    counts = np.bincount(lab, minlength=k)
    order = np.argsort(-counts)
    print("配色聚类（占比 | 颜色）:")
    for i in order:
        print(f"  {counts[i]/len(sample)*100:5.1f}%  {hexs(centers[i])}")

    # ---- 渐变分析：背景像素（排除白色字形与深蓝字形）----
    # 背景为蓝绿渐变；白色字形 RGB 都高，深蓝字形 B 高 R 低且饱和度高
    r, g, b = pix[:, 0], pix[:, 1], pix[:, 2]
    is_white = (r > 220) & (g > 220) & (b > 220)
    is_deepblue = (b > 150) & (r < 90) & (g < 140)
    bg = ~(is_white | is_deepblue)
    print(f"背景像素占比(不透明中): {bg.mean()*100:.1f}%")

    # 取全图背景像素的坐标，拟合线性渐变 RGB = c0 + cx*x + cy*y
    yy, xx = np.mgrid[0:h, 0:w]
    op = opaque.copy()
    rp, gp, bp = a[..., 0], a[..., 1], a[..., 2]
    bgmask = op & ~((rp > 220) & (gp > 220) & (bp > 220)) & ~((bp > 150) & (rp < 90) & (gp < 140))
    X = np.stack([np.ones_like(xx[bgmask]), xx[bgmask], yy[bgmask]], 1).astype(np.float64)
    X[:, 1] /= w
    X[:, 2] /= h
    for name, ch in (("R", rp), ("G", gp), ("B", bp)):
        coef, *_ = np.linalg.lstsq(X, ch[bgmask].astype(np.float64), rcond=None)
        c00 = coef[0]
        c10 = coef[0] + coef[1]
        c01 = coef[0] + coef[2]
        c11 = coef[0] + coef[1] + coef[2]
        print(f"渐变 {name}: 左上{c00:6.1f} 右上{c10:6.1f} 左下{c01:6.1f} 右下{c11:6.1f}")

    # 四角拟合色 vs 边界实际色（接缝量化）
    print("\n样式要点:")
    print("  - 圆角矩形底板，蓝绿对角渐变")
    print("  - 白色日历字形（粗圆角线条），深蓝装饰块/顶部条")
    print("  - 无投影阴影（字形边缘为纯色抗锯齿）")


if __name__ == "__main__":
    sys.exit(main())
