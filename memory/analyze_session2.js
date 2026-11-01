// Stage 31: analysis of a session (app v3.2 or llm_partner.js), revision of analyze_session.js: consecutive marks with the
// same label are merged (stage 30 pressed segment 1 four times), and steps per condition in segment 3 are counted from the
// block-switch events ("b"). Usage: node analyze_session2.js <state.json>  (or require() and call analyze(L)).
function analyze(L) {
  const S = L.session || { marks: [], ev: [] }, ev = S.ev;
  const marks = S.marks.filter((m, i, a) => i === 0 || m[1] !== a[i - 1][1]);
  const out = { marks, events: ev.length, segments: {} };
  const condAt = (() => { const B = ev.filter(e => e[0] === "b"); return t => { let c = 1; for (const e of B) { if (e[1] <= t) c = e[2]; else break; } return c; }; })();
  for (let i = 0; i < marks.length; i++) {
    const [t0, lab] = marks[i]; if (lab === "end") continue;
    const t1 = i + 1 < marks.length ? marks[i + 1][0] : Math.max(t0, ...ev.map(e => e[1]));
    const part = (from, to, cond) => {
      const X = ev.filter(e => e[1] > from && e[1] <= to);
      const C = X.filter(e => e[0] === "c" && (cond === undefined || e[3] === cond)), A = X.filter(e => e[0] === "a" && (cond === undefined || e[2] === cond));
      let steps = to - from; if (cond !== undefined) { steps = 0; for (let t = from + 1; t <= to; t++) if (condAt(t) === cond) steps++; }
      return { steps, calls: C.length, callsPer100: steps ? +(100 * C.length / steps).toFixed(1) : null, waitingShare: C.length ? +(C.filter(e => e[2]).length / C.length).toFixed(3) : null,
               answerShare: C.length ? +(A.length / C.length).toFixed(3) : null, gestures: X.filter(e => e[0] === "g" && (cond === undefined || e[3] === cond)).length,
               ignored: X.filter(e => e[0] === "u").reduce((s, e) => s + e[2], 0) };
    };
    const s = ev.filter(e => e[0] === "s" && e[1] > t0 && e[1] <= t1), lastS = s[s.length - 1];
    const seg = { from: t0, to: t1, all: part(t0, t1), first750: part(t0, Math.min(t1, t0 + 750)), last750: part(Math.max(t0, t1 - 750), t1), last300: part(Math.max(t0, t1 - 300), t1),
      formShare: s.length ? +(s.filter(e => e[11]).length / s.length).toFixed(3) : null,
      atEnd: lastS ? { sedimentTotal: lastS[2], r9m3: [lastS[3], lastS[4]], r10m3: [lastS[5], lastS[6]], r11m3: [lastS[7], lastS[8]], c3m3: [lastS[9], lastS[10]] } : null };
    if (lab === "3") { seg.live = part(t0, t1, 1); seg.replay = part(t0, t1, 0); }
    out.segments[lab] = seg;
  }
  return out;
}
module.exports = { analyze };
if (require.main === module) { const d = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8")); console.log(JSON.stringify(analyze(d.data || d), null, 1)); }
