#!/usr/bin/env python3
"""build app icons, welcome icon layers, launch images, tgs files, the phone sticker and the flag sprite

needs pillow, numpy and scipy (python3 -m venv v && v/bin/pip install pillow numpy scipy),
ffmpeg and rsvg-convert for the symbols, the phone and the flags

sources, all copied unchanged apart from scaling:
  resources/icons/source/exteria.png   the app icon, also the logo in the qr codes
  resources/phone/countries.txt        assets/countries.txt of the reference tree
  phone video                          twelve demo/Resources/IntroPhone.mp4, the original telegram red phone
  flag svgs                            flag-icons 7.5.0 (lipis, mit), flags/4x3
  symbols, the tab icons among them    res/drawable-* of the reference tree, the msg_, menu_, input_ and ic_ drawables of SYMBOL_ICONS
  resources/fonts                      Inter 4.1 (rsms, ofl), extras/ttf
  resources/fonts fallbacks            Noto Sans Math, Symbols, Symbols2 (notofonts, ofl) and Unifont 16.0.01, unifont and
                                       unifont_upper otf (unifoundry.com, ofl), the upstream files; see Fallback-LICENSE.txt
"""
import argparse
import glob
import gzip
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.optimize import least_squares

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MASTER = 1024

APP_ICONS = {
    "Icon.png": 57,
    "Icon@2x.png": 114,
    # the size in the name is what ios 6 matches against the icon size it wants; Icon@2x.png alone lost to the opaque Icon-60@2x.png
    "Icon-57.png": 57,
    "Icon-57@2x.png": 114,
    "Icon-60@2x.png": 120,
    "Icon-60@3x.png": 180,
    "Icon-72.png": 72,
    "Icon-72@2x.png": 144,
    "Icon-76.png": 76,
    "Icon-76@2x.png": 152,
    "Icon-83.5@2x.png": 167,
    "Icon-Small.png": 29,
    "Icon-Small@2x.png": 58,
    "Icon-Small@3x.png": 87,
    "Icon-Small-40.png": 40,
    "Icon-Small-40@2x.png": 80,
    "Icon-Small-40@3x.png": 120,
    "Icon-Small-50.png": 50,
    "Icon-Small-50@2x.png": 100,
}

# the logo in the middle of the login and profile qr codes, shown up to 64 points wide
QR_LOGOS = {
    "qr_logo.png": 64,
    "qr_logo@2x.png": 128,
    "qr_logo@3x.png": 192,
}

# the icon in the middle of the splash screen, shown SPLASH_POINTS wide; the launch image is dark, the dark screen color of the app, because
# a launch image cannot follow the chosen theme and a white one flashes on the dark themes
SPLASH_POINTS = 96
SPLASH_BACKGROUND = (21, 18, 31)
SPLASH_ICONS = {
    "splash_icon.png": 96,
    "splash_icon@2x.png": 192,
    "splash_icon@3x.png": 288,
}

# the spy shown as the sender of a gift whose sender stayed anonymous, up to 32 points wide
GIFT_ANONYMOUS = {
    "gift_anonymous.png": 32,
    "gift_anonymous@2x.png": 64,
    "gift_anonymous@3x.png": 96,
}
GIFT_ANONYMOUS_SOURCE = os.path.join(ROOT, "resources/icons/source/gift_anonymous.png")

# springboard of ios 5 and 6 paints a pre-rendered icon as it is, and the rounded mask it adds to the others did not show on the iphone 4s with ios 6.1.3 (the
# icon was a sharp square on the home screen). the sizes those systems ask for (57 and 114 on the iphone, 72 and 144 on the ipad) are drawn with their own
# rounded corners and the plist marks the icons pre-rendered. that springboard also takes the 120 pixel file of the 60 point icon, whose size matches its
# icon slot exactly, ahead of the 114 pixel one, so the 120 pixel files are rounded too; ios 7 and later mask them with a larger radius, which hides the
# transparent corners. the 76, 83.5 and 180 pixel files stay opaque squares
LEGACY_ICON_SIDES = (57, 114, 120, 72, 144)
LEGACY_ICON_RADIUS = 0.18

# share of the master edge dropped on every side, about the corner radius of the source artwork
ICON_BLEED = 0.08
WELCOME_LAYER_POINTS = 200
# the smoothing used to find the bumps flattens them, the source edge is about this much deeper
RIPPLE_GAIN = 1.4
GEOMETRY_HEADER = os.path.join(ROOT, "app/ui/shared/exteria_welcome_icon_geometry.h")
PHONE_HEADER = os.path.join(ROOT, "app/ui/shared/exteria_phone_ring.h")
FLAG_HEADER = os.path.join(ROOT, "app/ui/shared/exteria_flag_sprite.h")

PHONE_SIDE = 256
PHONE_STEP = 2
FLAG_TILE = (64, 48)
FLAG_COLUMNS = 16
FLAG_RADIUS = 7
# the country list also holds codes that are not countries
FLAG_FALLBACK = ("FT", "GO", "YL")
WELCOME_SCALES = ((1, ""), (2, "@2x"), (3, "@3x"))

# source file and the name it gets in the bundle
ANIMATIONS = {
    "stars_send": "welcome_fast",
    "giveaway_results": "welcome_free",
    "utyan_passcode": "welcome_secure",
    "utyan_gigagroup": "welcome_powerful",
    "utyan_saved_messages": "welcome_cloud",
    "utyan_call": "form_code",
    "tsv_setup_monkey_idle1": "form_password",
    "filters": "folders_hint",
    "tsv_monkey_close": "form_password_close",
    "tsv_setup_monkey_close_and_peek_to_idle": "form_password_open",
    "utyan_newborn": "form_name",
    "chats_archive": "swipe_archive",
    "chats_unarchive": "swipe_unarchive",
    "chats_hide": "swipe_hide",
    "chats_unhide": "swipe_unhide",
    "swipe_pin": "swipe_pin",
    "swipe_unpin": "swipe_unpin",
    "swipe_read": "swipe_read",
    "swipe_unread": "swipe_unread",
    "swipe_mute": "swipe_mute",
    "swipe_unmute": "swipe_unmute",
    "swipe_delete": "swipe_delete",
    "utyan_empty": "search_empty",
    "utyan_draw": "theme_duck",
    "android_30": "device_android",
    "iphone_30": "device_iphone",
    "ipad_30": "device_ipad",
    "mac_30": "device_mac",
    "windows_30": "device_windows",
    "linux_30": "device_linux",
    "ubuntu_30": "device_ubuntu",
    "chrome_30": "device_chrome",
    "safari_30": "device_safari",
    "edge_30": "device_edge",
    "firefox_30": "device_firefox",
    "contact_check": "check_done",
}

# stem, scales, portrait size in points, first os that reads the plist entry, orientations
LAUNCH_IMAGES = [
    ("Default", (1, 2), 320, 480, "5.0", ("Portrait",)),
    ("Default-568h", (2,), 320, 568, "7.0", ("Portrait",)),
    ("Default-667h", (2,), 375, 667, "8.0", ("Portrait",)),
    ("Default-736h", (3,), 414, 736, "8.0", ("Portrait",)),
    ("Default-812h", (3,), 375, 812, "11.0", ("Portrait",)),
    ("Default-844h", (3,), 390, 844, "11.0", ("Portrait",)),
    ("Default-852h", (3,), 393, 852, "11.0", ("Portrait",)),
    ("Default-874h", (3,), 402, 874, "11.0", ("Portrait",)),
    ("Default-896h", (2, 3), 414, 896, "11.0", ("Portrait",)),
    ("Default-912h", (3,), 420, 912, "11.0", ("Portrait",)),
    ("Default-926h", (3,), 428, 926, "11.0", ("Portrait",)),
    ("Default-932h", (3,), 430, 932, "11.0", ("Portrait",)),
    ("Default-956h", (3,), 440, 956, "11.0", ("Portrait",)),
    ("Default-Portrait", (1, 2), 768, 1024, "5.0", ("Portrait",)),
    ("Default-Landscape", (1, 2), 768, 1024, "5.0", ("Landscape",)),
]
for _stem, _w, _h in (("1080h", 810, 1080), ("1112h", 834, 1112), ("1133h", 744, 1133),
                      ("1180h", 820, 1180), ("1194h", 834, 1194), ("1210h", 834, 1210), ("1366h", 1024, 1366),
                      ("1376h", 1032, 1376)):
    LAUNCH_IMAGES.append(("Default-Portrait-" + _stem, (2,), _w, _h, "9.0", ("Portrait",)))
    LAUNCH_IMAGES.append(("Default-Landscape-" + _stem, (2,), _w, _h, "9.0", ("Landscape",)))


def nearest_fill(rgb, known):
    idx = ndi.distance_transform_edt(~known, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


def load_master(path):
    """square rgba master with a clean antialiased silhouette and no white halo"""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    near_white = rgb.min(axis=2) >= 240
    labels, _ = ndi.label(near_white)
    outside = labels == labels[0, 0]
    shape = ndi.binary_fill_holes(~outside)
    shape = ndi.binary_opening(shape, iterations=2)
    core = ndi.binary_erosion(shape, iterations=2)
    clean = nearest_fill(rgb, core)
    ys, xs = np.where(shape)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    color = Image.fromarray(clean.astype(np.uint8)).crop(box).resize((MASTER, MASTER), Image.LANCZOS)
    cover = Image.fromarray((shape * 255).astype(np.uint8)).crop(box).resize((MASTER, MASTER), Image.LANCZOS)
    cover = ndi.gaussian_filter(np.asarray(cover, dtype=np.float64) / 255.0, 0.7)
    alpha = np.clip((cover - 0.5) * 2.0 + 0.5, 0.0, 1.0)
    return np.asarray(color, dtype=np.float64), alpha


def to_image(rgb, alpha):
    out = np.zeros((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def harmonic_fill(rgb, known, size=256, iterations=4000):
    """smooth background under the artwork, solved on a small grid and scaled back up"""
    small_rgb = np.asarray(Image.fromarray(rgb.astype(np.uint8)).resize((size, size), Image.BOX), dtype=np.float64)
    small_known = np.asarray(Image.fromarray((known * 255).astype(np.uint8)).resize((size, size), Image.BOX)) > 250
    field = nearest_fill(small_rgb, small_known)
    for _ in range(iterations):
        padded = np.pad(field, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (padded[:-2, 1:-1] + padded[2:, 1:-1] + padded[1:-1, :-2] + padded[1:-1, 2:]) * 0.25
        field = np.where(small_known[..., None], small_rgb, avg)
    big = Image.fromarray(np.clip(field, 0, 255).astype(np.uint8)).resize((MASTER, MASTER), Image.BICUBIC)
    return np.asarray(big, dtype=np.float64)


def split_layers(rgb, alpha):
    """back, top wave, bottom wave and arrow as separate full canvas layers"""
    shape = alpha > 0.5
    # the crop touches the array border, so pad it or the distance there reads as far from the edge
    edge_dist = ndi.distance_transform_edt(np.pad(shape, 1))[1:-1, 1:-1]
    green = rgb[..., 1]
    ink = shape & (green < 135)
    # the dark rim joins the two waves along the left edge, so they are told apart away from it
    labels, count = ndi.label(ink & (edge_dist > 16))
    sizes = ndi.sum(ink & (edge_dist > 16), labels, range(1, count + 1))
    pieces = []
    for label in np.argsort(sizes)[::-1][:3]:
        if sizes[label] < 20000:
            continue
        core = labels == label + 1
        ys, _ = np.where(core)
        grown = ndi.binary_dilation(core, iterations=18) & ink
        touches_edge = edge_dist[grown].min() < 4
        pieces.append((grown, ys.mean(), touches_edge))
    arrow = [p for p in pieces if not p[2]]
    waves = sorted([p for p in pieces if p[2]], key=lambda p: p[1])
    if len(arrow) != 1 or len(waves) != 2:
        sys.exit("icon artwork did not split into one arrow and two waves")
    art = ink
    known_bg = shape & ~ndi.binary_dilation(art, iterations=7) & (edge_dist > 5)
    back_rgb = harmonic_fill(rgb, known_bg)

    layers = {}
    for name, piece in (("wave_top", waves[0][0]), ("wave_bottom", waves[1][0]), ("arrow", arrow[0][0])):
        inside = ndi.distance_transform_edt(piece)
        outside = ndi.distance_transform_edt(~piece)
        interior = piece & (inside > 4)
        fg = nearest_fill(rgb, interior)
        delta = fg - back_rgb
        span = np.maximum((delta * delta).sum(axis=2), 1.0)
        cover = ((rgb - back_rgb) * delta).sum(axis=2) / span
        band = (inside <= 4) & piece | (outside <= 4) & ~piece
        mix = np.where(band, np.clip(cover, 0.0, 1.0), piece.astype(np.float64))
        mix = np.where(outside > 4, 0.0, mix)
        layers[name] = (fg, mix * alpha)
    layers["back"] = (back_rgb, alpha)
    return layers


def resize_rgba(image, side):
    return image.resize((side, side), Image.LANCZOS)


def legacy_icon(square, side):
    """the opaque square drawn at side pixels, with transparent rounded corners when only ios 5 and 6 ask for that size"""
    if side not in LEGACY_ICON_SIDES:
        return square.convert("RGB").resize((side, side), Image.LANCZOS)
    from PIL import ImageDraw
    big = square.convert("RGBA")
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big.size[0] - 1, big.size[1] - 1), radius=round(big.size[0] * LEGACY_ICON_RADIUS), fill=255)
    big.putalpha(mask)
    return big.resize((side, side), Image.LANCZOS)


def write_png(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, optimize=True)


class Disk:
    """a scalloped disk fitted to one wave: centre, radius and a ripple that repeats all round"""

    def __init__(self, cx, cy, radius, bumps, amplitude, phase):
        self.cx, self.cy, self.radius = cx, cy, radius
        self.bumps, self.amplitude, self.phase = bumps, amplitude, phase

    def reach(self):
        return self.radius + self.amplitude + 4

    def radius_at(self, angle):
        return self.radius + self.amplitude * np.cos(self.bumps * angle - self.phase)

    def alpha(self, side, scale, center_x, center_y):
        """coverage on a side x side grid; (center_x, center_y) is the disk centre in grid units"""
        ys, xs = np.mgrid[0:side, 0:side]
        dx = (xs + 0.5 - center_x) / scale
        dy = (ys + 0.5 - center_y) / scale
        edge = self.radius_at(np.arctan2(dy, dx)) - np.hypot(dx, dy)
        return np.clip(edge * scale + 0.5, 0.0, 1.0)


def fit_disk(coverage, alpha):
    mask = coverage > 0.5
    edge = mask & ~ndi.binary_erosion(mask)
    outline = ndi.distance_transform_edt(np.pad(alpha > 0.5, 1))[1:-1, 1:-1]
    ys, xs = np.where(edge & (outline > 25))
    xs, ys = xs.astype(np.float64), ys.astype(np.float64)
    start = (xs.mean(), ys.mean(), 450.0)
    fit = least_squares(lambda p: np.hypot(xs - p[0], ys - p[1]) - p[2], start)
    cx, cy, radius = fit.x
    angle = np.arctan2(ys - cy, xs - cx)
    reach = np.hypot(xs - cx, ys - cy) - radius
    order = np.argsort(angle)
    angle, reach = angle[order], reach[order]
    grid = np.linspace(angle[0], angle[-1], 2048)
    ripple = ndi.uniform_filter1d(np.interp(grid, angle, reach), 15)
    ripple = ripple - ndi.uniform_filter1d(ripple, 400)
    # the strongest ripple over the visible arc gives the bump count for the full circle
    spectrum = np.abs(np.fft.rfft(ripple * np.hanning(len(ripple)), 1 << 16))
    cycles = np.fft.rfftfreq(1 << 16, d=(grid[1] - grid[0])) * 2 * np.pi
    band = (cycles >= 8) & (cycles <= 40)
    bumps = int(round(cycles[band][np.argmax(spectrum[band])]))
    basis = np.stack([np.cos(bumps * grid), np.sin(bumps * grid)], 1)
    (cos_part, sin_part), *_ = np.linalg.lstsq(basis, ripple, rcond=None)
    amplitude = float(np.hypot(cos_part, sin_part)) * RIPPLE_GAIN
    return Disk(cx, cy, radius, bumps, amplitude, float(np.arctan2(sin_part, cos_part)))


def build_waves(layers, alpha, out_dir):
    """fill images, scalloped disk masks and the geometry header the animated icon reads"""
    lines = ["/* generated by tools/make_assets.py, do not edit */", ""]
    disks = {}
    for name in ("wave_top", "wave_bottom"):
        fill, coverage = layers[name]
        disk = fit_disk(coverage, alpha)
        disks[name] = disk
        side = 2 * disk.reach()
        tag = name.upper()
        lines.append("#define EXTERIA_ICON_%s_CENTER_X %.5f" % (tag, disk.cx / MASTER))
        lines.append("#define EXTERIA_ICON_%s_CENTER_Y %.5f" % (tag, disk.cy / MASTER))
        lines.append("#define EXTERIA_ICON_%s_SIDE %.5f" % (tag, side / MASTER))
        fill_image = to_image(fill, np.ones_like(alpha))
        for scale, suffix in WELCOME_SCALES:
            points = WELCOME_LAYER_POINTS * scale
            write_png(resize_rgba(fill_image, points),
                      os.path.join(out_dir, "welcome_icon_%s_fill%s.png" % (name, suffix)))
            pixels = int(np.ceil(side * points / MASTER))
            mask = np.zeros((pixels, pixels, 4), dtype=np.uint8)
            mask[..., :3] = 255
            mask[..., 3] = (disk.alpha(pixels, points / MASTER, pixels / 2.0, pixels / 2.0) * 255 + 0.5).astype(np.uint8)
            write_png(Image.fromarray(mask, "RGBA"), os.path.join(out_dir, "welcome_icon_%s_disk%s.png" % (name, suffix)))
    with open(GEOMETRY_HEADER, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    return disks


def build_icons(rgb, out_dir):
    # remove the source rim before drawing the mask for the ios 5 and 6 icon sizes
    cut = int(MASTER * ICON_BLEED)
    square = to_image(rgb, np.ones(rgb.shape[:2])).convert("RGB").crop((cut, cut, MASTER - cut, MASTER - cut))
    for name, side in APP_ICONS.items():
        write_png(legacy_icon(square, side), os.path.join(out_dir, name))


def build_qr_logo(rgb, alpha, out_dir):
    # the clean master keeps the icon's own rounded silhouette as alpha, so the code shows its paper through the corners
    master = to_image(rgb, alpha)
    for name, side in QR_LOGOS.items():
        write_png(resize_rgba(master, side), os.path.join(out_dir, name))


def build_splash_icon(rgb, alpha, out_dir):
    master = to_image(rgb, alpha)
    for name, side in SPLASH_ICONS.items():
        write_png(resize_rgba(master, side), os.path.join(out_dir, name))


def build_gift_anonymous(source, out_dir):
    master = Image.open(source).convert("RGBA")
    for name, side in GIFT_ANONYMOUS.items():
        write_png(master.resize((side, side), Image.LANCZOS), os.path.join(out_dir, name))


def build_welcome_layers(layers, alpha, out_dir):
    for name in ("back", "arrow"):
        rgb, layer_alpha = layers[name]
        full = to_image(rgb, layer_alpha)
        for scale, suffix in WELCOME_SCALES:
            write_png(resize_rgba(full, WELCOME_LAYER_POINTS * scale),
                      os.path.join(out_dir, "welcome_icon_%s%s.png" % (name, suffix)))
    return build_waves(layers, alpha, out_dir)


def check_layers(rgb, alpha, layers, disks):
    canvas = np.zeros_like(rgb)
    for name in ("back", "wave_top", "wave_bottom", "arrow"):
        fill, cover = layers[name]
        if name in disks:
            disk = disks[name]
            side = int(np.ceil(2 * disk.reach()))
            ys, xs = np.mgrid[0:MASTER, 0:MASTER]
            edge = disk.radius_at(np.arctan2(ys + 0.5 - disk.cy, xs + 0.5 - disk.cx)) - np.hypot(xs + 0.5 - disk.cx, ys + 0.5 - disk.cy)
            cover = np.clip(edge + 0.5, 0.0, 1.0) * alpha
        canvas = fill * cover[..., None] + canvas * (1.0 - cover[..., None])
    inside = alpha > 0.99
    diff = np.abs(canvas - rgb)[inside]
    print("layer recompose error: mean %.2f, p99 %.1f" % (diff.mean(), np.percentile(diff, 99)))
    for name, disk in disks.items():
        print("%s: centre (%.0f, %.0f) radius %.0f, %d bumps per turn" % (name, disk.cx, disk.cy, disk.radius, disk.bumps))


def splash_launch_image(size, scale):
    """the splash as the app draws it on the dark themes: the icon in the middle of the dark screen color, so the start shows no other picture"""
    image = Image.new("RGB", size, SPLASH_BACKGROUND)
    icon = Image.open(os.path.join(ROOT, "resources/icons/splash_icon@3x.png")).convert("RGBA")
    side = SPLASH_POINTS * scale
    icon = icon.resize((side, side), Image.LANCZOS)
    image.paste(icon, ((size[0] - side) // 2, (size[1] - side) // 2), icon)
    return image


def check_launch_plist(plist_path):
    """a launch image the plist does not list is ignored and that screen size gets letterboxed"""
    with open(plist_path, "rb") as handle:
        listed = {(item["UILaunchImageName"], item["UILaunchImageOrientation"], item["UILaunchImageSize"],
                   item["UILaunchImageMinimumOSVersion"]) for item in plistlib.load(handle)["UILaunchImages"]}
    wanted = {(stem, orientations[0], "{%d, %d}" % (width, height), minimum)
              for stem, _scales, width, height, minimum, orientations in LAUNCH_IMAGES}
    if listed != wanted:
        sys.exit("packaging/Info.plist UILaunchImages differ from LAUNCH_IMAGES\nmissing: %s\nextra: %s"
                 % (sorted(wanted - listed), sorted(listed - wanted)))


# every ExteriaSymbol in the app but the two trash pieces, which are cut from msg_delete by
# build_trash_icons
SYMBOL_ICONS = (
    ("chats", "menu_chats", 0, False), ("person", "msg_contacts", 0, False), ("gear", "msg_settings", 0, False),
    ("magnifier", "msg_search", 0, True), ("pluscircle", "msg_add", 0, True), ("compose", "msg_edit", 0, True),
    ("bookmark", "msg_saved", 0, True), ("pin", "msg_pin_filled", 0, True), ("bellslash", "msg_mute", 0, True),
    ("archive", "msg_archive", 0, True), ("chevronright", "msg_arrowright", 0, True), ("check", "msg_check", 0, True),
    ("checkdouble", "msg_seen", 0, True), ("smiley", "input_smile", 0, True), ("keyboard", "input_keyboard", 0, True),
    ("sendarrow", "ic_send", 0, True), ("clock", "msg_recent", 0, True), ("arrowdown", "msg_go_down", 0, True),
    ("play", "baseline_play_arrow_36_white", 0, True), ("document", "msg_sendfile", 0, True),
    ("sticker", "msg_sticker", 0, True), ("backspace", "msg_clear_input", 0, True), ("microphone", "input_mic", 0, True),
    ("videocamera", "input_video", 0, True), ("cameraflip", "msg_photo_switch2", 0, True),
    ("paperclip", "input_attach", 0, True), ("gallery", "msg_gallery", 0, True), ("mappin", "msg_location", 0, True),
    ("lock", "msg_secret", 0, True), ("ellipsis", "ic_ab_other", 1, True), ("sun", "msg_brightness_high", 0, True),
    ("moon", "menu_night_mode_24", 0, True), ("megaphone", "msg_channel", 0, True), ("gift", "menu_gift", 0, True),
    ("heart", "msg_reactions_filled", 0, True), ("heartoutline", "msg_reactions", 0, True),
    ("star", "baseline_star_24", 0, True), ("close", "msg_close", 0, True), ("phone", "msg_calls", 0, True),
    ("at", "msg_mention", 0, True), ("cake", "menu_birthday", 0, True), ("logout", "msg_leave", 0, True),
    ("qr", "msg_qrcode", 0, True), ("link", "msg_link", 0, True), ("music", "baseline_music_note_24", 0, True),
    ("pause", "ic_pause", 0, True), ("next", "baseline_skip_next_24_white", 0, True),
    ("previous", "baseline_skip_previous_24_white", 0, True), ("eyeslash", "menu_hide_gift", 0, True),
    ("speaker", "msg_voice_speaker", 0, True), ("speakerslash", "baseline_volume_off_24_white", 0, True),
    ("ellipsisvertical", "ic_ab_other", 0, True), ("bell", "msg_unmute", 0, True), ("eye", "msg_views", 0, True),
    ("share", "msg_share", 0, True), ("bellmuted", "msg_mute", 0, True), ("pinnedlist", "msg_pinnedlist", 0, True),
    ("broom", "msg_clearcache", 0, True), ("back", "ic_ab_back", 0, True), ("externallink", "mini_external_link", 0, True),
    ("apps", "input_bot2", 0, True), ("copy", "msg_copy", 0, True),
    ("stars", "star", 0, True),
    ("filehq", "msg_filehq", 0, True), ("spoiler", "msg_spoiler", 0, True),
    ("qualitysd", "menu_quality_sd", 0, True), ("qualityhd", "menu_quality_hd", 0, True),
    ("callback", "msg_callback", 0, True), ("videocall", "msg_videocall", 0, True), ("background", "msg_background", 0, True), ("groupsmenu", "msg_groups", 0, True), ("clearhistory", "msg_clear", 0, True), ("help", "msg_help", 0, True), ("settingsold", "msg_settings_old", 0, True), ("fave", "msg_fave", 0, True), ("pinline", "msg_pin", 0, True), ("ghost", "ghost", 0, False),
    ("headerdraw", "msg_header_draw", 0, False),
    ("crop", "media_crop", 0, False), ("adjust", "media_settings", 0, False),
    ("draw", "media_draw", 0, False), ("rotate", "msg_photo_rotate", 0, False), ("mirror", "media_flip", 0, False),
    ("member", "outline_profile_member_24", 0, True), ("report", "report", 0, True),
    ("reply", "menu_reply", 0, True), ("forward", "msg_forward", 0, True), ("unpin", "msg_unpin", 0, True),
    ("info", "msg_info", 0, True), ("repeat", "msg_repeat", 0, True),
    ("settingsaccount", "settings_account", 0, True),
    ("settingschat", "settings_chat", 0, True),
    ("settingsstickers", "msg_premium_stickers", 0, True),
    ("settingsprivacy", "settings_privacy", 0, True),
    ("settingssounds", "settings_sounds", 0, True),
    ("settingsdata", "settings_data", 0, True),
    ("settingsfolders", "settings_folders", 0, True),
    ("settingsdevices", "settings_devices", 0, True),
    ("settingspower", "settings_power", 0, True),
    ("settingslanguage", "settings_language", 0, True),
    ("settingspremium", "settings_premium", 0, True),
    ("settingsstars", "settings_stars", 0, True),
    ("settingsbusiness", "settings_business", 0, True),
    ("settingsgift", "settings_gift", 0, True),
    ("settingsask", "settings_ask", 0, True),
    ("settingsfaq", "settings_faq", 0, True),
    ("settingsfeatures", "settings_features", 0, True),
    ("settingspolicy", "settings_policy", 0, True),
    ("block", "msg_block2", 0, True),
    ("qrmini", "msg_mini_qr", 0, True),
    ("globe", "msg_language", 0, True),
    ("translate", "ic_translate", 0, True),
    ("appdevices", "menu_devices", 0, True),
    ("deviceandroid", "device_phone_android", 0, True),
    ("deviceandroidtablet", "device_tablet_android", 0, True),
    ("deviceiphone", "device_phone_ios", 0, True),
    ("deviceipad", "device_tablet_ios", 0, True),
    ("devicewindows", "device_desktop_win", 0, True),
    ("devicemac", "device_desktop_osx", 0, True),
    ("devicedesktop", "device_desktop_other", 0, True),
    ("devicechrome", "device_web_chrome", 0, True),
    ("deviceedge", "device_web_edge", 0, True),
    ("devicefirefox", "device_web_firefox", 0, True),
    ("deviceopera", "device_web_opera", 0, True),
    ("devicesafari", "device_web_safari", 0, True),
    ("deviceweb", "device_web_other", 0, True),
)
# android density folders and the ios scale each one serves, with the pixel size of a 24 dp vector at that scale
SYMBOL_DENSITIES = (("drawable-mdpi", "", 24), ("drawable-xhdpi", "@2x", 48), ("drawable-xxhdpi", "@3x", 72))
# the share of the square a trimmed glyph fills, about what the line glyphs drawn in code used to take
SYMBOL_FILL = 0.8
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def vector_to_svg(path, side):
    """an android vector drawable as svg text; groups, clip paths and gradients are not read, so they stop the build"""
    root = ET.parse(path).getroot()
    view_w = float(root.get(ANDROID_NS + "viewportWidth"))
    view_h = float(root.get(ANDROID_NS + "viewportHeight"))
    shapes = []
    for node in root:
        if node.tag != "path":
            sys.exit("%s: unsupported vector element %s" % (path, node.tag))
        attrs = {key[len(ANDROID_NS):]: value for key, value in node.attrib.items() if key.startswith(ANDROID_NS)}
        fill, stroke = attrs.get("fillColor"), attrs.get("strokeColor")
        if (fill and not fill.startswith("#")) or (stroke and not stroke.startswith("#")):
            sys.exit("%s: a color that is not a literal" % path)

        def opacity(color):
            # android writes #AARRGGBB, a bare #RRGGBB is opaque
            return int(color[1:3], 16) / 255.0 if len(color) == 9 else 1.0

        fill_on = fill is not None and opacity(fill) > 0
        stroke_on = stroke is not None and opacity(stroke) > 0
        shapes.append('<path d="%s" fill="%s" fill-rule="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (
            attrs["pathData"], "#fff" if fill_on else "none",
            "evenodd" if attrs.get("fillType") == "evenOdd" else "nonzero",
            "#fff" if stroke_on else "none", attrs.get("strokeWidth", "0") if stroke_on else "0"))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %g %g">%s</svg>'
            % (side, side, view_w, view_h, "".join(shapes)))


def load_symbol_source(res_dir, name, folder, side):
    """the drawable as rgba: the bitmap of the density folder, or the vector drawn at the size of that density"""
    for extension in (".webp", ".png"):
        bitmap = os.path.join(res_dir, folder, name + extension)
        if os.path.exists(bitmap):
            return Image.open(bitmap).convert("RGBA")
    vector = os.path.join(res_dir, "drawable", name + ".xml")
    if not os.path.exists(vector):
        sys.exit("no %s in %s or drawable" % (name, folder))
    work = tempfile.mkdtemp()
    try:
        svg = os.path.join(work, "v.svg")
        png = os.path.join(work, "v.png")
        with open(svg, "w") as handle:
            handle.write(vector_to_svg(vector, side))
        subprocess.check_call(["rsvg-convert", "-w", str(side), "-h", str(side), "-o", png, svg])
        return Image.open(png).convert("RGBA")
    finally:
        shutil.rmtree(work)


def trim_to_square(image):
    """the glyph without its android padding, centred in a square with the same margin on every side"""
    box = image.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()
    if not box:
        sys.exit("a symbol source is empty")
    glyph = image.crop(box)
    side = int(round(max(glyph.size) / SYMBOL_FILL))
    square = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    square.alpha_composite(glyph, ((side - glyph.size[0]) // 2, (side - glyph.size[1]) // 2))
    return square


def split_trash(image):
    """the lid and the can of a trash glyph, each on a canvas of the whole glyph so both sit where they belong when stacked.
    The first empty row after the lid bar is the cut, and the lid turns about the left end of its bar"""
    alpha = np.asarray(image.getchannel("A"))
    filled = (alpha > 8).any(axis=1)
    first = int(np.argmax(filled))
    gap = first + int(np.argmin(filled[first:]))
    if gap <= first or not filled[gap:].any():
        sys.exit("the trash glyph has no gap between its lid and its can")
    pieces = []
    for keep in (slice(0, gap), slice(gap, alpha.shape[0])):
        part = np.zeros(alpha.shape + (4,), dtype=np.uint8)
        part[keep] = np.asarray(image)[keep]
        pieces.append(Image.fromarray(part, "RGBA"))
    return pieces[0], pieces[1]


def build_symbol_icons(res_dir, out_dir):
    """the glyphs of the app from the reference drawables, as white masks the app tints at run time"""
    for old in glob.glob(os.path.join(out_dir, "symbol_*.png")):
        os.remove(old)
    for name, source, turns, trim in SYMBOL_ICONS:
        for folder, suffix, side in SYMBOL_DENSITIES:
            image = load_symbol_source(res_dir, source, folder, side)
            mask = np.asarray(image).copy()
            mask[..., :3] = 255
            image = Image.fromarray(mask, "RGBA")
            if turns:
                image = image.rotate(90 * turns, expand=True)
            if trim:
                image = trim_to_square(image)
            write_png(image, os.path.join(out_dir, "symbol_%s%s.png" % (name, suffix)))
    for folder, suffix, side in SYMBOL_DENSITIES:
        mask = np.asarray(load_symbol_source(res_dir, "msg_delete", folder, side)).copy()
        mask[..., :3] = 255
        lid, can = split_trash(trim_to_square(Image.fromarray(mask, "RGBA")))
        write_png(lid, os.path.join(out_dir, "symbol_trashlid%s.png" % suffix))
        write_png(can, os.path.join(out_dir, "symbol_trashcan%s.png" % suffix))


def build_launch_images(out_dir):
    for stem, scales, width, height, _minimum, orientations in LAUNCH_IMAGES:
        for scale in scales:
            size = (width * scale, height * scale)
            if orientations[0] == "Landscape":
                size = (size[1], size[0])
            name = stem + ("@%dx" % scale if scale > 1 else "") + ".png"
            write_png(splash_launch_image(size, scale), os.path.join(out_dir, name))


# the device animations paint their cut-outs black, and swaps that black for the color of the circle
# behind them when it loads (SessionBottomSheet.setAnimation, colors[]), so here the swap is made
# once, in the file
DEVICE_CIRCLE_COLORS = {
    "device_android": 0x9AD164, "device_iphone": 0x5CAFFA, "device_ipad": 0x5CAFFA, "device_mac": 0x5BCBE3, "device_windows": 0x5BCBE3,
    "device_linux": 0x5CAFFA, "device_ubuntu": 0x5CAFFA, "device_chrome": 0xFF8AAC, "device_safari": 0xFF8AAC, "device_edge": 0xFF8AAC,
    "device_firefox": 0xFF845E,
}


def recolor_black(node, rgb):
    """every static solid color that is black becomes rgb; the colors of lottie are 0 to 1 floats"""
    if isinstance(node, dict):
        color = node.get("c")
        if isinstance(color, dict) and color.get("a") == 0 and isinstance(color.get("k"), list) and len(color["k"]) >= 3:
            if all(isinstance(value, (int, float)) for value in color["k"][:3]) and max(color["k"][:3]) < 0.01:
                color["k"][:3] = [((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0]
        for value in node.values():
            recolor_black(value, rgb)
    elif isinstance(node, list):
        for value in node:
            recolor_black(value, rgb)


def build_animations(source_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for source, name in ANIMATIONS.items():
        with open(os.path.join(source_dir, source + ".json"), "rb") as handle:
            data = handle.read()
        if name in DEVICE_CIRCLE_COLORS:
            document = json.loads(data)
            recolor_black(document, DEVICE_CIRCLE_COLORS[name])
            data = json.dumps(document, separators=(",", ":")).encode()
        with open(os.path.join(out_dir, name + ".tgs"), "wb") as handle:
            handle.write(gzip.compress(data, 9, mtime=0))


# the alternate app icons of the chat settings: the launcher icons that are a plain color with a
# picture over it
ALTERNATE_ICONS = ("exteraless", "blueprint", "red", "nya", "ayu", "quack")
# name of the file, side in pixels: the sizes the home screen of an iPhone and an iPad ask for
ALTERNATE_ICON_SIZES = (("-60@2x", 120), ("-60@3x", 180), ("-76", 76), ("-76@2x", 152), ("-83.5@2x", 167),
                        ("-57", 57), ("-57@2x", 114), ("-72", 72), ("-72@2x", 144))
ROUNDED_RADIUS = 0.22
# an adaptive icon is 108 dp wide and shows the 72 dp in the middle of it
ADAPTIVE_VISIBLE = 72.0 / 108.0


def background_color(path):
    """the color of a vector drawable that is one solid square, as an rgb tuple"""
    root = ET.parse(path).getroot()
    paths = [node for node in root if node.tag == "path"]
    if len(paths) != 1:
        sys.exit("%s: not a single solid square" % path)
    color = paths[0].get(ANDROID_NS + "fillColor")
    if not color or not color.startswith("#") or len(color) not in (7, 9):
        sys.exit("%s: a color that is not a literal" % path)
    return tuple(int(color[-6:][i:i + 2], 16) for i in (0, 2, 4))


def build_alternate_icons(res_dir, out_dir):
    """opaque squares at every iphone and ipad size, from the color and picture of the adaptive icon"""
    os.makedirs(out_dir, exist_ok=True)
    for name in ALTERNATE_ICONS:
        color = background_color(os.path.join(res_dir, "drawable", name + "_icon_background.xml"))
        picture = Image.open(os.path.join(res_dir, "drawable-xxxhdpi", name + "_icon_foreground.png")).convert("RGBA")
        side = picture.size[0]
        inset = round(side * (1 - ADAPTIVE_VISIBLE) / 2)
        picture = picture.crop((inset, inset, side - inset, side - inset)).resize((1024, 1024), Image.LANCZOS)
        icon = Image.new("RGBA", (1024, 1024), color + (255,))
        icon.alpha_composite(picture)
        icon = icon.convert("RGB")
        for suffix, pixels in ALTERNATE_ICON_SIZES:
            write_png(legacy_icon(icon, pixels), os.path.join(out_dir, name.capitalize() + suffix + ".png"))


# the splash shows the icon the person chose, so each alternate icon also has the picture the splash draws: rounded, at the three scales of splash_icon
SPLASH_SIDES = (("", 96), ("@2x", 192), ("@3x", 288))


def build_image_icons(source, name, out_dir):
    icon = Image.open(source).convert("RGB")
    if icon.width != icon.height:
        raise ValueError("%s icon must be square" % name)
    for suffix, pixels in ALTERNATE_ICON_SIZES:
        write_png(legacy_icon(icon, pixels), os.path.join(out_dir, name + suffix + ".png"))
    for suffix, pixels in SPLASH_SIDES:
        write_png(rounded_icon(icon, pixels), os.path.join(out_dir, "splash_" + name.lower() + suffix + ".png"))


def build_senkogram_icons(source, out_dir):
    build_image_icons(source, "SenkoGram", out_dir)


def build_alternate_splash_icons(res_dir, out_dir):
    """splash_<name>.png (and @2x, @3x) for each alternate icon, made from the same color and picture as the icons themselves"""
    os.makedirs(out_dir, exist_ok=True)
    for name in ALTERNATE_ICONS:
        color = background_color(os.path.join(res_dir, "drawable", name + "_icon_background.xml"))
        picture = Image.open(os.path.join(res_dir, "drawable-xxxhdpi", name + "_icon_foreground.png")).convert("RGBA")
        side = picture.size[0]
        inset = round(side * (1 - ADAPTIVE_VISIBLE) / 2)
        picture = picture.crop((inset, inset, side - inset, side - inset)).resize((1024, 1024), Image.LANCZOS)
        icon = Image.new("RGBA", (1024, 1024), color + (255,))
        icon.alpha_composite(picture)
        icon = icon.convert("RGB")
        for suffix, pixels in SPLASH_SIDES:
            write_png(rounded_icon(icon, pixels), os.path.join(out_dir, "splash_" + name + suffix + ".png"))


def rounded_icon(icon, pixels):
    """the icon at this size with transparent rounded corners, the mask drawn four times larger so the edge is smooth"""
    from PIL import ImageDraw
    scale = 4
    mask = Image.new("L", (pixels * scale, pixels * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, pixels * scale - 1, pixels * scale - 1), round(pixels * scale * ROUNDED_RADIUS), fill=255)
    out = icon.resize((pixels, pixels), Image.LANCZOS).convert("RGBA")
    out.putalpha(mask.resize((pixels, pixels), Image.LANCZOS))
    return out


def build_phone_ring(video, out_dir):
    """the red telephone, 30 frames a second, as numbered png files with real alpha"""
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, "phone_ring_*.png")):
        os.remove(old)
    work = tempfile.mkdtemp()
    try:
        subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-i", video, os.path.join(work, "f%03d.png")])
        sources = sorted(glob.glob(os.path.join(work, "f*.png")))[::PHONE_STEP]
        stream = float(subprocess.check_output(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
             "-of", "csv=p=0", video]).decode().split("/")[0])
        for index, source in enumerate(sources):
            packed = np.asarray(Image.open(source).convert("RGB"), dtype=np.float64)
            half = packed.shape[1] // 2
            # the colour half is premultiplied over black and the alpha half is its matte
            matte = packed[:, half:].mean(axis=2) / 255.0
            colour = np.where(matte[..., None] > 0.02, packed[:, :half] / np.maximum(matte[..., None], 0.02), 0)
            frame = to_image(np.clip(colour, 0, 255), matte).resize((PHONE_SIDE, PHONE_SIDE), Image.LANCZOS)
            frame = frame.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE)
            write_png(frame, os.path.join(out_dir, "phone_ring_%03d.png" % index))
    finally:
        shutil.rmtree(work)
    with open(PHONE_HEADER, "w") as handle:
        handle.write("/* generated by tools/make_assets.py, do not edit */\n\n#define EXTERIA_PHONE_RING_FRAMES %d\n"
                     "#define EXTERIA_PHONE_RING_FPS %d\n" % (len(sources), round(stream / PHONE_STEP)))


def flag_tile(svg):
    width, height = FLAG_TILE
    scale = 4
    png = subprocess.check_output(["rsvg-convert", "-w", str(width * scale), "-h", str(height * scale), svg])
    flag = Image.open(__import__("io").BytesIO(png)).convert("RGBA")
    return round_flag(flag, scale)


def round_flag(flag, scale):
    """rounded corners and a hairline so white flags keep their edge on a white card"""
    width, height = flag.size
    mask = Image.new("L", (width, height), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), FLAG_RADIUS * scale, fill=255)
    ring = Image.new("L", (width, height), 0)
    ImageDraw.Draw(ring).rounded_rectangle((0, 0, width - 1, height - 1), FLAG_RADIUS * scale, outline=255, width=scale)
    shade = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shade.paste((0, 0, 0, 36), (0, 0), ring)
    out = Image.alpha_composite(flag, shade)
    out.putalpha(mask)
    return out.resize(FLAG_TILE, Image.LANCZOS)


def globe_tile():
    from PIL import ImageDraw
    width, height = FLAG_TILE
    scale = 4
    tile = Image.new("RGBA", (width * scale, height * scale), (150, 160, 175, 255))
    draw = ImageDraw.Draw(tile)
    cx, cy, radius = width * scale // 2, height * scale // 2, height * scale // 2 - 5 * scale
    line = 2 * scale
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=(255, 255, 255, 255), width=line)
    draw.ellipse((cx - radius // 2, cy - radius, cx + radius // 2, cy + radius), outline=(255, 255, 255, 255), width=line)
    draw.line((cx - radius, cy, cx + radius, cy), fill=(255, 255, 255, 255), width=line)
    return round_flag(tile, scale)


def build_flags(svg_dir, countries, out_dir):
    """one sprite sheet, tiles in the order of flags.txt"""
    isos = []
    for line in open(countries, encoding="utf-8"):
        if line.strip():
            iso = line.split(";")[1]
            if iso not in isos:
                isos.append(iso)
    rows = (len(isos) + FLAG_COLUMNS - 1) // FLAG_COLUMNS
    sheet = Image.new("RGBA", (FLAG_COLUMNS * FLAG_TILE[0], rows * FLAG_TILE[1]), (0, 0, 0, 0))
    globe = globe_tile()
    for index, iso in enumerate(isos):
        svg = os.path.join(svg_dir, iso.lower() + ".svg")
        if iso in FLAG_FALLBACK:
            tile = globe
        elif os.path.exists(svg):
            tile = flag_tile(svg)
        else:
            sys.exit("no flag svg for %s" % iso)
        sheet.paste(tile, ((index % FLAG_COLUMNS) * FLAG_TILE[0], (index // FLAG_COLUMNS) * FLAG_TILE[1]))
    os.makedirs(out_dir, exist_ok=True)
    write_png(sheet, os.path.join(out_dir, "flag_sprite.png"))
    with open(os.path.join(out_dir, "flags.txt"), "w") as handle:
        handle.write("\n".join(isos) + "\n")
    with open(FLAG_HEADER, "w") as handle:
        handle.write("/* generated by tools/make_assets.py, do not edit */\n\n#define EXTERIA_FLAG_TILE_WIDTH %d\n"
                     "#define EXTERIA_FLAG_TILE_HEIGHT %d\n#define EXTERIA_FLAG_COLUMNS %d\n"
                     % (FLAG_TILE[0], FLAG_TILE[1], FLAG_COLUMNS))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("part", choices=("icons", "qrlogo", "splash", "giftanon", "launch", "animations", "symbols", "alticons", "senkogram", "telegram", "phone", "flags", "all"))
    parser.add_argument("--source", default=os.path.join(ROOT, "resources/icons/source/exteria.png"))
    parser.add_argument("--animations", default=os.environ.get("EXTERIA_LOTTIE_RAW", ""))
    parser.add_argument("--phone-video", default=os.environ.get("EXTERIA_PHONE_VIDEO", ""))
    parser.add_argument("--flag-svgs", default=os.environ.get("EXTERIA_FLAG_SVGS", ""))
    parser.add_argument("--icon-res", default=os.environ.get("EXTERIA_ICON_RES", ""))
    parser.add_argument("--out", default=os.path.join(ROOT, "resources"))
    args = parser.parse_args()
    if args.part in ("icons", "all"):
        rgb, alpha = load_master(args.source)
        build_icons(rgb, os.path.join(args.out, "icons"))
        layers = split_layers(rgb, alpha)
        disks = build_welcome_layers(layers, alpha, os.path.join(args.out, "icons"))
        check_layers(rgb, alpha, layers, disks)
    if args.part in ("qrlogo", "all"):
        rgb, alpha = load_master(args.source)
        build_qr_logo(rgb, alpha, os.path.join(args.out, "icons"))
    if args.part in ("splash", "all"):
        rgb, alpha = load_master(args.source)
        build_splash_icon(rgb, alpha, os.path.join(args.out, "icons"))
    if args.part in ("giftanon", "all"):
        build_gift_anonymous(GIFT_ANONYMOUS_SOURCE, os.path.join(args.out, "icons"))
    if args.part in ("launch", "all"):
        check_launch_plist(os.path.join(ROOT, "packaging/Info.plist"))
        build_launch_images(os.path.join(args.out, "launch"))
    if args.part in ("animations", "all"):
        if not args.animations:
            sys.exit("set EXTERIA_LOTTIE_RAW to the res/raw directory of the reference tree")
        build_animations(args.animations, os.path.join(args.out, "animations"))
    if args.part in ("symbols", "all"):
        if not args.icon_res:
            sys.exit("set EXTERIA_ICON_RES to the res directory of the reference tree")
        build_symbol_icons(args.icon_res, os.path.join(args.out, "icons"))
    if args.part in ("alticons", "all"):
        if not args.icon_res:
            sys.exit("set EXTERIA_ICON_RES to the res directory of the reference tree")
        build_alternate_icons(args.icon_res, os.path.join(args.out, "icons"))
        build_alternate_splash_icons(args.icon_res, os.path.join(args.out, "icons"))
    if args.part in ("senkogram", "all"):
        build_senkogram_icons(os.path.join(ROOT, "resources/icons/source/senkogram.png"), os.path.join(args.out, "icons"))
    if args.part in ("telegram", "all"):
        build_image_icons(os.path.join(ROOT, "resources/icons/source/telegram.png"), "Telegram", os.path.join(args.out, "icons"))
    if args.part in ("phone", "all"):
        if not args.phone_video:
            sys.exit("set EXTERIA_PHONE_VIDEO to IntroPhone.mp4")
        build_phone_ring(args.phone_video, os.path.join(args.out, "phone"))
    if args.part in ("flags", "all"):
        if not args.flag_svgs:
            sys.exit("set EXTERIA_FLAG_SVGS to the flag-icons flags/4x3 directory")
        build_flags(args.flag_svgs, os.path.join(args.out, "phone/countries.txt"), os.path.join(args.out, "phone"))


if __name__ == "__main__":
    main()
