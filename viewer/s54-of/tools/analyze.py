# Analyze University of Iowa MIS piano and violin samples into synthesis tables.
# usage: python -I analyze.py <wav_dir> <out_json> <out_header> [<previous_json>]
# With <previous_json>, piano results are taken from it when the piano wavs are absent (violin is analyzed anew).
import sys, json, wave, glob, os
import numpy as np

WAV, OUTJ, OUTH = sys.argv[1], sys.argv[2], sys.argv[3]
NOTE = {"A2": 110.0, "A3": 220.0, "A4": 440.0, "A5": 880.0}


def load(path):
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    return x, sr


def peak_interp(mag, k):
    if k <= 0 or k >= len(mag) - 1:
        return float(k), mag[k]
    a, b, c = np.log(mag[k - 1] + 1e-12), np.log(mag[k] + 1e-12), np.log(mag[k + 1] + 1e-12)
    p = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
    return k + p, np.exp(b - 0.25 * (a - c) * p)


# ---------------- piano ----------------
def piano(path, f0, npart=16):
    x, sr = load(path)
    env = np.abs(x)
    on = int(np.argmax(env > 0.2 * env.max()))
    on = max(0, on - int(0.005 * sr))
    x = x[on:]
    N = 16384 if f0 < 150 else 8192
    hop = 1024
    win = np.hanning(N)
    frames = (len(x) - N) // hop
    times = (np.arange(frames) * hop + N / 2) / sr
    S = np.array([np.abs(np.fft.rfft(win * x[i * hop:i * hop + N])) for i in range(frames)])
    df = sr / N
    # inharmonicity from an early frame
    fi = int(np.searchsorted(times, 0.25))
    ratios = []
    for n in range(1, npart + 1):
        lo, hi = int(n * f0 * 0.985 / df), int(n * f0 * 1.04 / df) + 1
        if hi >= S.shape[1]:
            break
        k = lo + int(np.argmax(S[fi, lo:hi]))
        kk, _ = peak_interp(S[fi], k)
        ratios.append((n, kk * df / (n * f0)))
    ns = np.array([r[0] for r in ratios], float)
    rr = np.array([r[1] for r in ratios])
    # rr^2 = s^2 (1 + B n^2): fit linear in n^2
    A = np.vstack([np.ones_like(ns), ns ** 2]).T
    c0, c1 = np.linalg.lstsq(A, rr ** 2, rcond=None)[0]
    B = max(0.0, c1 / c0)
    tune = np.sqrt(c0)
    parts = []
    noise_db = 20 * np.log10(np.median(S[-5:]) + 1e-12)
    for n in range(1, npart + 1):
        fn = n * f0 * tune * np.sqrt(1 + B * n * n)
        k = int(round(fn / df))
        if k + 3 >= S.shape[1] or fn > 12000:
            parts.append(None)
            continue
        track = S[:, k - 2:k + 3].max(axis=1)
        db = 20 * np.log10(track + 1e-12)
        a0 = db[int(np.searchsorted(times, 0.03)):int(np.searchsorted(times, 0.12)) + 1].max()
        def fit(t0, t1):
            m = (times >= t0) & (times <= t1) & (db > noise_db + 12)
            if m.sum() < 4:
                return None
            s, i = np.polyfit(times[m], db[m], 1)
            return s, i
        e = fit(0.06, 0.8)
        l = fit(1.0, 8.0)
        tau1 = 8.686 / max(1e-3, -e[0]) if e and e[0] < 0 else 0.6
        if l and l[0] < 0:
            tau2 = 8.686 / max(1e-3, -l[0])
            w2 = float(np.clip(10 ** ((l[1] - a0) / 20), 0.0, 1.0))
        else:
            tau2, w2 = tau1, 0.0
        tau2 = max(tau2, tau1)
        parts.append({"n": n, "amp_db": float(a0), "tau1": float(tau1), "tau2": float(tau2), "w2": w2})
    ref = max(p["amp_db"] for p in parts if p)
    for p in parts:
        if p:
            p["amp_db"] -= ref
    # hammer: broadband energy above 4 kHz in the first 15 ms relative to the partials' peak
    a = x[:int(0.015 * sr)]
    sp = np.abs(np.fft.rfft(a * np.hanning(len(a))))
    fr = np.fft.rfftfreq(len(a), 1 / sr)
    hammer = 20 * np.log10(np.sqrt(np.mean(sp[fr > 4000] ** 2)) / (sp.max() + 1e-12) + 1e-12)
    return {"f0": f0, "tune": float(tune), "B": float(B), "hammer_db": float(hammer), "partials": parts,
            "peak": float(np.abs(x).max())}


# ---------------- violin ----------------
def violin_notes(path):
    x, sr = load(path)
    hop, N = 512, 2048
    rms = np.array([np.sqrt(np.mean(x[i:i + N] ** 2)) for i in range(0, len(x) - N, hop)])
    db = 20 * np.log10(rms + 1e-9)
    on = db > db.max() - 30
    segs, i = [], 0
    while i < len(on):
        if on[i]:
            j = i
            while j < len(on) and on[j]:
                j += 1
            if (j - i) * hop / sr > 0.8:
                segs.append((i * hop, j * hop + N))
            i = j
        else:
            i += 1
    out = []
    for s0, s1 in segs:
        seg = x[s0:s1]
        L = len(seg)
        st = seg[int(0.25 * L):int(0.8 * L)]
        M = 1 << int(np.floor(np.log2(min(len(st), 65536))))
        st = st[:M]
        sp = np.abs(np.fft.rfft(st * np.hanning(M)))
        df = sr / M
        fr = np.arange(len(sp)) * df
        # f0 by harmonic sum over candidates 180-1400 Hz
        cands = np.arange(180, 1400, 0.5)
        score = [sum(np.log(sp[min(len(sp) - 1, int(round(h * c / df)))] + 1e-9) for h in range(1, 6)) for c in cands]
        f0 = cands[int(np.argmax(score))]
        k = int(round(f0 / df))
        kk, _ = peak_interp(sp, k - 3 + int(np.argmax(sp[k - 3:k + 4])))
        f0 = kk * df
        harm = []
        mask = np.zeros(len(sp), bool)
        for n in range(1, 41):
            fn = n * f0
            if fn > 14000:
                break
            k = int(round(fn / df))
            w = max(3, int(0.012 * fn / df))
            lo, hi = max(0, k - w), min(len(sp) - 1, k + w)
            kp = lo + int(np.argmax(sp[lo:hi + 1]))
            harm.append((n, fn, float(sp[kp])))
            mask[max(0, kp - 6):kp + 7] = True
        # noise: short frames (vibrato barely moves the pitch within 46 ms), harmonics masked around the local f0
        full = seg[int(0.25 * L):int(0.8 * L)]
        Nn = 2048
        dfn = sr / Nn
        frn = np.arange(Nn // 2 + 1) * dfn
        hn, ht = 0.0, 0.0
        for i in range(0, len(full) - Nn, Nn):
            spn = np.abs(np.fft.rfft(full[i:i + Nn] * np.hanning(Nn))) ** 2
            k1 = int(round(f0 / dfn))
            lo, hi = max(1, int(k1 * 0.95)), int(k1 * 1.05) + 2
            kk, _ = peak_interp(np.sqrt(spn), lo + int(np.argmax(spn[lo:hi])))
            fl = kk * dfn
            m = np.zeros(len(spn), bool)
            for n in range(1, int(14000 / fl) + 1):
                fn = n * fl
                w = max(3 * dfn, 0.012 * fn)
                m |= np.abs(frn - fn) <= w
            sel = frn > 100
            hn += np.sum(spn[sel & ~m]); ht += np.sum(spn[sel])
        noise_ratio = float(hn / (ht + 1e-12))
        # vibrato: track the 3rd partial with short frames
        Nv, hv = 8192, 256
        fs3 = []
        for i in range(0, len(full) - Nv, hv):
            spv = np.abs(np.fft.rfft(full[i:i + Nv] * np.hanning(Nv)))
            dfv = sr / Nv
            k = int(round(3 * f0 / dfv))
            lo, hi = k - 6, k + 7
            kp = lo + int(np.argmax(spv[lo:hi]))
            kk, _ = peak_interp(spv, kp)
            fs3.append(kk * dfv / 3)
        fs3 = np.array(fs3)
        cents = 1200 * np.log2(fs3 / np.median(fs3))
        cents -= np.polyval(np.polyfit(np.arange(len(cents)), cents, 2), np.arange(len(cents)))
        fsr = sr / hv
        C = np.abs(np.fft.rfft(cents * np.hanning(len(cents))))
        cf = np.fft.rfftfreq(len(cents), 1 / fsr)
        band = (cf > 3) & (cf < 9)
        vib_rate = float(cf[band][np.argmax(C[band])]) if band.any() else 0.0
        vib_depth = float(np.std(cents) * np.sqrt(2))
        # attack and release on the RMS envelope of the segment
        e = np.array([np.sqrt(np.mean(seg[i:i + 1024] ** 2)) for i in range(0, L - 1024, 256)])
        steady = np.median(e[int(0.3 * len(e)):int(0.7 * len(e))])
        a10 = np.argmax(e > 0.1 * steady); a90 = np.argmax(e > 0.9 * steady)
        r90 = len(e) - 1 - np.argmax(e[::-1] > 0.9 * steady); r10 = len(e) - 1 - np.argmax(e[::-1] > 0.1 * steady)
        out.append({"f0": float(f0), "harm": harm, "noise_ratio": noise_ratio, "vib_rate": vib_rate,
                    "vib_depth_cents": vib_depth, "attack": float((a90 - a10) * 256 / sr),
                    "release": float((r10 - r90) * 256 / sr), "dur": float(L / sr)})
    return out


res = {"piano": {}, "violin": []}
PREV = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else None
for dyn in ("pp", "mf", "ff"):
    for nm, f0 in NOTE.items():
        p = os.path.join(WAV, f"Piano.{dyn}.{nm}.wav")
        if os.path.exists(p):
            res["piano"][f"{dyn}.{nm}"] = piano(p, f0)
        elif PREV:
            res["piano"][f"{dyn}.{nm}"] = PREV["piano"][f"{dyn}.{nm}"]
import re
SEMI = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
def expected_f0(name):
    # one-note files such as LLVln_ArcoVib_A4_f.wav name their pitch; scale files do not
    m = re.search(r"_([A-G])(b?)(\d)_", name)
    if not m:
        return None
    k = SEMI[m.group(1)] - (1 if m.group(2) else 0) + 12 * (int(m.group(3)) - 4)
    return 440.0 * 2 ** (k / 12)
skipped = 0
for p in sorted(glob.glob(os.path.join(WAV, "Violin.*.wav"))):
    ef = expected_f0(os.path.basename(p))
    for n in violin_notes(p):
        n["file"] = os.path.basename(p)
        # drop segments that are not the played note (noise, ring-off): short, or off the named pitch
        if n["dur"] < 1.5 or (ef and abs(1200 * np.log2(n["f0"] / ef)) > 100):
            skipped += 1
            continue
        res["violin"].append(n)
print("violin segments skipped:", skipped)

# violin body: amplitude of harmonic n times n (relative to a 1/n sawtooth), pooled, binned by 1/6 octave
pts = []
for v in res["violin"]:
    a1 = max(h[2] for h in v["harm"])
    for n, fn, a in v["harm"]:
        pts.append((fn, 20 * np.log10(a * n / a1 + 1e-12)))
pts = np.array(pts)
edges = 150 * 2 ** (np.arange(0, 6.6 * 6 + 1) / 6)
body = []
for lo, hi in zip(edges[:-1], edges[1:]):
    m = (pts[:, 0] >= lo) & (pts[:, 0] < hi)
    if m.sum() >= 3:
        body.append((float(np.sqrt(lo * hi)), float(np.median(pts[m, 1]))))
bf = np.array([b[0] for b in body]); bd = np.array([b[1] for b in body])
bd = np.convolve(np.pad(bd, 1, mode="edge"), [0.25, 0.5, 0.25], mode="valid")
bd -= bd.max()
res["violin_body"] = list(zip(bf.tolist(), bd.tolist()))
V = res["violin"]
res["violin_summary"] = {k: float(np.nanmedian([v[k] for v in V])) for k in ("noise_ratio", "vib_rate", "vib_depth_cents", "attack", "release")}
res["violin_summary"]["notes"] = len(V)
json.dump(res, open(OUTJ, "w"), indent=1)

# ---------------- header ----------------
H = ["// generated by analyze.py. Piano: University of Iowa MIS (free to use without restrictions,",
     "// theremin.music.uiowa.edu/MIS.html), pp/mf/ff A2-A5. Violin: whatever Violin.*.wav were given; on 2026-11-17",
     "// VSCO-2 Community Edition (CC0) Solo Violin / Arco Vib, G3-E6, p and f (MIS violins are played without vibrato).",
     "#pragma once", "namespace inst {"]
dyns, notes = ("pp", "mf", "ff"), ("A2", "A3", "A4", "A5")
H.append("static const int PP = 16;")
H.append("static const double pianoF0[4] = {110.0, 220.0, 440.0, 880.0};")
for key, name in (("B", "pianoB"), ("hammer_db", "pianoHammerDb"), ("peak", "pianoPeak")):
    rows = [", ".join(f"{res['piano'][f'{d}.{n}'][key]:.6g}" for n in notes) for d in dyns]
    H.append(f"static const double {name}[3][4] = {{" + ", ".join("{" + r + "}" for r in rows) + "};")
for key, name, dflt in (("amp_db", "pianoAmpDb", -90), ("tau1", "pianoTau1", 0.3), ("tau2", "pianoTau2", 0.3), ("w2", "pianoW2", 0)):
    blocks = []
    for d in dyns:
        nb = []
        for n in notes:
            ps = res["piano"][f"{d}.{n}"]["partials"]
            nb.append("{" + ", ".join(f"{(p[key] if p else dflt):.5g}" for p in ps) + "}")
        blocks.append("{" + ", ".join(nb) + "}")
    H.append(f"static const double {name}[3][4][PP] = {{" + ", ".join(blocks) + "};")
H.append(f"static const int bodyN = {len(bf)};")
H.append("static const double bodyF[bodyN] = {" + ", ".join(f"{v:.1f}" for v in bf) + "};")
H.append("static const double bodyDb[bodyN] = {" + ", ".join(f"{v:.2f}" for v in bd) + "};")
s = res["violin_summary"]
H.append(f"static const double violinNoiseRatio = {s['noise_ratio']:.5g};")
H.append(f"static const double violinVibRate = {s['vib_rate']:.4g};")
H.append(f"static const double violinVibCents = {s['vib_depth_cents']:.4g};")
H.append(f"static const double violinAttack = {s['attack']:.4g};")
H.append(f"static const double violinRelease = {s['release']:.4g};")
H.append("}")
open(OUTH, "w").write("\n".join(H) + "\n")
print(json.dumps(res["violin_summary"]))
for k in ("mf.A2", "mf.A3", "mf.A4", "mf.A5", "ff.A4", "pp.A4"):
    p = res["piano"][k]
    print(k, "B=%.2e" % p["B"], "hammer %.1f dB" % p["hammer_db"],
          "amp", [round(q["amp_db"], 1) if q else None for q in p["partials"][:8]],
          "tau1", [round(q["tau1"], 2) if q else None for q in p["partials"][:4]],
          "tau2", [round(q["tau2"], 1) if q else None for q in p["partials"][:4]])
print("body", [(round(f), round(d, 1)) for f, d in res["violin_body"]])
