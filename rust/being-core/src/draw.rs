//! Drawing into a pixel frame buffer (no_std): rectangles, rounded rectangles, lines, discs and a 5x7 bitmap font
//! (ASCII digits, lower-case letters and a few signs, drawn for this lab). The same calls can later drive a small
//! display on dedicated hardware. Pixels are RGBA bytes in memory (u32 = r | g << 8 | b << 16 | a << 24).

use alloc::vec;
use alloc::vec::Vec;

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    pub const fn hex(x: u32) -> Rgb {
        Rgb((x >> 16) as u8, (x >> 8) as u8, x as u8)
    }
    fn px(self) -> u32 {
        self.0 as u32 | (self.1 as u32) << 8 | (self.2 as u32) << 16 | 0xff00_0000
    }
}

pub fn floor(x: f64) -> f64 {
    let i = x as i64 as f64;
    if i > x {
        i - 1.0
    } else {
        i
    }
}
pub fn round(x: f64) -> i64 {
    floor(x + 0.5) as i64
}

pub struct Frame {
    pub w: usize,
    pub h: usize,
    pub px: Vec<u32>,
}

impl Frame {
    pub fn new(w: usize, h: usize) -> Frame {
        Frame { w, h, px: vec![0; w * h] }
    }
    pub fn clear(&mut self, c: Rgb) {
        let p = c.px();
        for x in self.px.iter_mut() {
            *x = p;
        }
    }
    #[inline]
    fn put(&mut self, x: i64, y: i64, c: Rgb, a: f64) {
        if x < 0 || y < 0 || x >= self.w as i64 || y >= self.h as i64 {
            return;
        }
        let i = y as usize * self.w + x as usize;
        if a >= 1.0 {
            self.px[i] = c.px();
        } else if a > 0.0 {
            let o = self.px[i];
            let mix = |n: u32, s: u8| -> u32 { ((n as f64) * (1.0 - a) + (s as f64) * a + 0.5) as u32 };
            let r = mix(o & 0xff, c.0);
            let g = mix((o >> 8) & 0xff, c.1);
            let b = mix((o >> 16) & 0xff, c.2);
            self.px[i] = r | g << 8 | b << 16 | 0xff00_0000;
        }
    }
    /// Filled rectangle, coordinates in device pixels (rounded to the pixel grid).
    pub fn rect(&mut self, x: f64, y: f64, w: f64, h: f64, c: Rgb) {
        self.rect_a(x, y, w, h, c, 1.0)
    }
    pub fn rect_a(&mut self, x: f64, y: f64, w: f64, h: f64, c: Rgb, a: f64) {
        let (x0, y0, x1, y1) = (round(x), round(y), round(x + w), round(y + h));
        for yy in y0..y1 {
            for xx in x0..x1 {
                self.put(xx, yy, c, a);
            }
        }
    }
    /// Filled rectangle with rounded corners of radius r.
    pub fn rrect(&mut self, x: f64, y: f64, w: f64, h: f64, r: f64, c: Rgb, a: f64) {
        let (x0, y0, x1, y1) = (round(x), round(y), round(x + w), round(y + h));
        let r = r.min((w / 2.0).max(0.0)).min((h / 2.0).max(0.0));
        for yy in y0..y1 {
            for xx in x0..x1 {
                let (px, py) = (xx as f64 + 0.5, yy as f64 + 0.5);
                let cx = if px < x + r { x + r } else if px > x + w - r { x + w - r } else { px };
                let cy = if py < y + r { y + r } else if py > y + h - r { y + h - r } else { py };
                let (dx, dy) = (px - cx, py - cy);
                if dx * dx + dy * dy <= r * r {
                    self.put(xx, yy, c, a);
                }
            }
        }
    }
    /// Outline of a rounded rectangle, stroke width t (centred on the edge).
    pub fn rrect_line(&mut self, x: f64, y: f64, w: f64, h: f64, r: f64, t: f64, c: Rgb) {
        let h2 = t / 2.0;
        let (x0, y0, x1, y1) = (round(x - h2 - 1.0), round(y - h2 - 1.0), round(x + w + h2 + 1.0), round(y + h + h2 + 1.0));
        for yy in y0..y1 {
            for xx in x0..x1 {
                let (px, py) = (xx as f64 + 0.5, yy as f64 + 0.5);
                let outer = in_rrect(px, py, x - h2, y - h2, w + t, h + t, r + h2);
                let inner = in_rrect(px, py, x + h2, y + h2, w - t, h - t, (r - h2).max(0.0));
                if outer && !inner {
                    self.put(xx, yy, c, 1.0);
                }
            }
        }
    }
    pub fn disc(&mut self, cx: f64, cy: f64, r: f64, c: Rgb) {
        let (x0, y0, x1, y1) = (round(cx - r - 1.0), round(cy - r - 1.0), round(cx + r + 1.0), round(cy + r + 1.0));
        for yy in y0..y1 {
            for xx in x0..x1 {
                let (dx, dy) = (xx as f64 + 0.5 - cx, yy as f64 + 0.5 - cy);
                if dx * dx + dy * dy <= r * r {
                    self.put(xx, yy, c, 1.0);
                }
            }
        }
    }
    /// A line of width t (drawn as discs along the segment).
    pub fn line(&mut self, x0: f64, y0: f64, x1: f64, y1: f64, t: f64, c: Rgb) {
        let len = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).max(0.0);
        let steps = (sqrt(len) * 2.0) as i64 + 1;
        for i in 0..=steps {
            let f = i as f64 / steps as f64;
            self.disc(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, t / 2.0, c);
        }
    }
    /// Text in the 5x7 font with pixel size s (each font pixel is s x s); returns the width drawn.
    pub fn text(&mut self, x: f64, y: f64, s: f64, txt: &str, c: Rgb) -> f64 {
        let mut cx = x;
        for ch in txt.chars() {
            if let Some(g) = glyph(ch) {
                for (row, bits) in g.iter().enumerate() {
                    for (col, b) in bits.bytes().enumerate() {
                        if b == b'#' {
                            self.rect(cx + col as f64 * s, y + row as f64 * s, s, s, c);
                        }
                    }
                }
            } else if ch != ' ' {
                self.rect(cx + s, y + s, 3.0 * s, 5.0 * s, c);
            }
            cx += 6.0 * s;
        }
        cx - x
    }
}

fn in_rrect(px: f64, py: f64, x: f64, y: f64, w: f64, h: f64, r: f64) -> bool {
    if px < x || px > x + w || py < y || py > y + h {
        return false;
    }
    let cx = if px < x + r { x + r } else if px > x + w - r { x + w - r } else { px };
    let cy = if py < y + r { y + r } else if py > y + h - r { y + h - r } else { py };
    let (dx, dy) = (px - cx, py - cy);
    dx * dx + dy * dy <= r * r
}

pub fn text_width(txt: &str, s: f64) -> f64 {
    txt.chars().count() as f64 * 6.0 * s - s
}

pub fn sqrt(x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    let mut r = if x > 1.0 { x / 2.0 } else { 1.0 };
    for _ in 0..40 {
        r = 0.5 * (r + x / r);
    }
    r
}

/// The 5x7 font: rows top to bottom, '#' = ink. Upper-case letters are drawn as lower case.
fn glyph(c: char) -> Option<&'static [&'static str; 7]> {
    let c = c.to_ascii_lowercase();
    FONT.iter().find(|(k, _)| *k == c).map(|(_, g)| g)
}

static FONT: [(char, [&str; 7]); 58] = [
    ('0', [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."]),
    ('1', ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."]),
    ('2', [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"]),
    ('3', ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."]),
    ('4', ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."]),
    ('5', ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."]),
    ('6', ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."]),
    ('7', ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."]),
    ('8', [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."]),
    ('9', [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."]),
    (',', [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."]),
    ('.', [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."]),
    ('-', [".....", ".....", ".....", "#####", ".....", ".....", "....."]),
    ('>', [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."]),
    ('<', ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."]),
    ('=', [".....", ".....", "#####", ".....", "#####", ".....", "....."]),
    ('/', [".....", "....#", "...#.", "..#..", ".#...", "#....", "....."]),
    (':', [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."]),
    ('(', ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."]),
    (')', [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."]),
    ('%', ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"]),
    ('+', [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."]),
    ('a', [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"]),
    ('b', ["#....", "#....", "#.##.", "##..#", "#...#", "#...#", "####."]),
    ('c', [".....", ".....", ".###.", "#....", "#....", "#...#", ".###."]),
    ('d', ["....#", "....#", ".##.#", "#..##", "#...#", "#...#", ".####"]),
    ('e', [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."]),
    ('f', ["..##.", ".#..#", ".#...", "###..", ".#...", ".#...", ".#..."]),
    ('g', [".....", ".####", "#...#", "#...#", ".####", "....#", ".###."]),
    ('h', ["#....", "#....", "#.##.", "##..#", "#...#", "#...#", "#...#"]),
    ('i', ["..#..", ".....", ".##..", "..#..", "..#..", "..#..", ".###."]),
    ('j', ["...#.", ".....", "..##.", "...#.", "...#.", "#..#.", ".##.."]),
    ('k', ["#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#."]),
    ('l', [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."]),
    ('m', [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#...#", "#...#"]),
    ('n', [".....", ".....", "#.##.", "##..#", "#...#", "#...#", "#...#"]),
    ('o', [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."]),
    ('p', [".....", "####.", "#...#", "#...#", "####.", "#....", "#...."]),
    ('q', [".....", ".####", "#...#", "#...#", ".####", "....#", "....#"]),
    ('r', [".....", ".....", "#.##.", "##..#", "#....", "#....", "#...."]),
    ('s', [".....", ".....", ".####", "#....", ".###.", "....#", "####."]),
    ('t', [".#...", ".#...", "###..", ".#...", ".#...", ".#..#", "..##."]),
    ('u', [".....", ".....", "#...#", "#...#", "#...#", "#..##", ".##.#"]),
    ('v', [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.."]),
    ('w', [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#."]),
    ('x', [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"]),
    ('y', [".....", "#...#", "#...#", "#...#", ".####", "....#", ".###."]),
    ('z', [".....", ".....", "#####", "...#.", "..#..", ".#...", "#####"]),
    ('!', ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."]),
    ('?', [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."]),
    ('_', [".....", ".....", ".....", ".....", ".....", ".....", "#####"]),
    ('*', [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."]),
    ('#', [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."]),
    ('[', [".###.", ".#...", ".#...", ".#...", ".#...", ".#...", ".###."]),
    (']', [".###.", "...#.", "...#.", "...#.", "...#.", "...#.", ".###."]),
    ('\'', ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."]),
    ('"', [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", "....."]),
    ('|', ["..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."]),
];
