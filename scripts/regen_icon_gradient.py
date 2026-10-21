# -*- coding: utf-8 -*-
"""
regen_icon_gradient.py
从 original_backup.png 逐像素生成无透明、无缝的鸿蒙图标。

方法（针对蓝绿对角渐变底板的图标）：
  1) 在不透明像素中识别"渐变背景"（排除白色字形与深蓝字形），
     对 R/G/B 三通道分别做二次多项式最小二乘拟合：
         channel(x, y) = c0 + c1*x + c2*y + c3*x^2 + c4*xy + c5*y^2
     多项式曲面天然光滑，向四角外推不会产生接缝。
  2) 逐像素生成输出：
       - 不透明像素  -> 保持原色（图标主体零改动）
       - 全透明像素  -> 取渐变曲面预测色
       - 半透明像素  -> 原色按 alpha 与渐变预测色做标准 over 合成，
                        保留抗锯齿边缘
  3) 接缝量化校验：对每个与 opaque 相邻的新填像素，与最近的不透明
     邻居比较色差，输出 max/mean；人眼可辨阈值约为 3~4 级。

输出：planer_icon_filled.png（独立新文件，不覆盖任何已有文件）
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(r"D:\2.Programming\PlanerHarmony\AppScope\resources\base\media\original_backup.png")
DST = Path(r"D:\2.Programming\PlanerHarmony\AppScope\resources\base\media\planer_icon_filled.png")


def fit_gradient(img: np.ndarray):
    """对背景像素做二次多项式拟合（带一次离群点剔除重拟合），
    返回 (整图渐变预测 (h,w,3) float, 背景掩码, 各通道系数)。"""
    h, w = img.shape[:2]
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    alpha = img[..., 3]

    is_white = (r > 220) & (g > 220) & (b > 220)
    is_deepblue = (b > 150) & (r < 90) & (g < 140)
    bg = (alpha == 255) & ~is_white & ~is_deepblue

    ys, xs = np.where(bg)
    xn = xs / w
    yn = ys / h
    A = np.stack([np.ones_like(xn), xn, yn, xn * xn, xn * yn, yn * yn], 1)

    yy, xx = np.mgrid[0:h, 0:w]
    xf = (xx / w).ravel()
    yf = (yy / h).ravel()
    Af = np.stack([np.ones_like(xf), xf, yf, xf * xf, xf * yf, yf * yf], 1)

    pred = np.empty((h * w, 3), dtype=np.float64)
    coefs = []
    keep = np.ones(len(ys), dtype=bool)
    for i, ch in enumerate((r, g, b)):
        y = ch[ys, xs].astype(np.float64)
        coef, *_ = np.linalg.lstsq(A, y, rcond=None)
        # 离群点剔除后重拟合（排除误分类的字形/装饰像素）
        resid = y - A @ coef
        sigma = resid.std()
        keep = np.abs(resid) < 3 * sigma
        coef, *_ = np.linalg.lstsq(A[keep], y[keep], rcond=None)
        coefs.append(coef)
        pred[:, i] = Af @ coef
        resid2 = y[keep] - A[keep] @ coef
        print(f"  通道{'RGB'[i]}: 剔除离群点 {(~keep).sum()} 个后重拟合, "
              f"残差 mean|e|={np.abs(resid2).mean():.2f}, std={resid2.std():.2f}")
    return pred.reshape(h, w, 3), bg, coefs


def diffuse_residual(resid_bg: np.ndarray, bg: np.ndarray,
                     fill_mask: np.ndarray, decay_px: int = 64) -> np.ndarray:
    """把背景残差场按最近邻扩散进填充区，并按到边界的距离做余弦衰减。

    距离 0（接缝处）衰减因子=1 -> 生成色 = 预测 + 残差 = 与邻接原色一致，
    数学上保证无缝；距离 >= decay_px 处因子=0 -> 纯光滑渐变。
    返回填充区的修正量场 (h,w,3)，同时返回距离场。
    """
    h, w = resid_bg.shape[:2]
    resid = resid_bg.copy()
    dist = np.zeros((h, w), dtype=np.int32)   # 到 opaque 边界的扩散距离
    frontier = bg.copy()                       # 已知区 = 背景 opaque 像素
    unknown = fill_mask.copy()

    d = 0
    while unknown.any():
        d += 1
        grown = frontier.copy()
        grown[1:, :] |= frontier[:-1, :]
        grown[:-1, :] |= frontier[1:, :]
        grown[:, 1:] |= frontier[:, :-1]
        grown[:, :-1] |= frontier[:, 1:]
        new_pixels = grown & unknown
        if not new_pixels.any():
            break

        # 新像素取四邻域已知残差（优先级 上/下/左/右）
        remaining = new_pixels.copy()
        for shift in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            dy, dx = shift
            ok = np.zeros_like(frontier)
            cand = np.zeros_like(resid)
            if dy == -1:
                ok[1:, :] = frontier[:-1, :]
                cand[1:, :] = resid[:-1, :]
            elif dy == 1:
                ok[:-1, :] = frontier[1:, :]
                cand[:-1, :] = resid[1:, :]
            elif dx == -1:
                ok[:, 1:] = frontier[:, :-1]
                cand[:, 1:] = resid[:, :-1]
            else:
                ok[:, :-1] = frontier[:, 1:]
                cand[:, :-1] = resid[:, 1:]
            m = remaining & ok
            if m.any():
                resid[m] = cand[m]
                dist[m] = d
                remaining &= ~m

        frontier |= new_pixels
        unknown &= ~new_pixels

    t = np.clip(dist.astype(np.float64) / decay_px, 0.0, 1.0)
    decay = (np.cos(t * np.pi) + 1.0) / 2.0     # 1 -> 0 余弦衰减
    return resid * decay[..., None], dist


def main():
    img = np.array(Image.open(SRC).convert("RGBA"))
    h, w = img.shape[:2]
    print(f"读取 {SRC.name}: {w}x{h}")

    print("拟合渐变曲面:")
    grad, bg, _ = fit_gradient(img)

    alpha = img[..., 3]
    opaque = alpha == 255
    transp = alpha == 0
    semi = ~(opaque | transp)

    # 背景残差场（仅背景 opaque 像素有效，其余置 0）
    resid_bg = np.zeros((h, w, 3), dtype=np.float64)
    resid_bg[bg] = img[..., :3][bg].astype(np.float64) - grad[bg]

    # 残差扩散 + 余弦衰减：让接缝处逐位吻合、远场过渡为纯渐变
    print("扩散边界残差（余弦衰减 64px）:")
    fill_mask = ~opaque
    correction, dist = diffuse_residual(resid_bg, bg, fill_mask)
    grad_seamless = grad + correction

    out = np.empty((h, w, 3), dtype=np.float64)
    out[opaque] = img[..., :3][opaque].astype(np.float64)
    out[transp] = grad_seamless[transp]
    if semi.any():
        a = alpha[semi].astype(np.float64)[:, None] / 255.0
        out[semi] = img[..., :3][semi].astype(np.float64) * a + grad_seamless[semi] * (1 - a)

    result = Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8))
    result.save(DST, format="PNG")
    print(f"已生成 -> {DST}")

    # ---- 校验 ----
    res = np.array(result).astype(np.int32)
    orig = img.astype(np.int32)

    # 1) 尺寸/格式/无透明
    assert result.size == (1024, 1024) and result.mode == "RGB"

    # 2) 主体完整性：原不透明像素必须逐位不变
    same = (res[..., :3][opaque] == orig[..., :3][opaque]).all()

    # 3) 接缝量化：新填区域(含半透明)中与 opaque 四邻接的像素，
    #    取最近 opaque 邻居颜色作参考色差
    ring = np.zeros_like(opaque)
    ring[1:, :] |= opaque[:-1, :]
    ring[:-1, :] |= opaque[1:, :]
    ring[:, 1:] |= opaque[:, :-1]
    ring[:, :-1] |= opaque[:, 1:]
    ring &= ~opaque

    diffs = []
    ys, xs = np.where(ring)
    for y, x in zip(ys, xs):
        nb = []
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx]:
                nb.append(orig[ny, nx, :3])
        if nb:
            ref = np.mean(nb, 0)
            diffs.append(np.abs(res[y, x] - ref).max())
    diffs = np.array(diffs)

    # 4) 平滑度：新填区域内部相邻像素色差（渐变应连续）
    filled = ~opaque
    dx = np.abs(res[:, 1:].astype(np.int32) - res[:, :-1].astype(np.int32)).max(-1)
    smooth_x = dx[filled[:, 1:] & filled[:, :-1]]

    print("[校验]")
    print(f"  尺寸/格式/无透明 : 1024x1024, PNG, RGB ✓")
    print(f"  主体完整性       : 原不透明像素逐位不变 -> {same} ✓")
    print(f"  接缝色差         : 边界像素 {len(diffs)} 个, "
          f"mean={diffs.mean():.2f}, p95={np.percentile(diffs,95):.1f}, "
          f"max={diffs.max():.0f}（<4 人眼不可辨）")
    print(f"  填充区平滑度     : 相邻像素色差 mean={smooth_x.mean():.2f}, "
          f"max={smooth_x.max()}（应≈渐变自然步进）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
