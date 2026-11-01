// Stage 30: analysis of the session with the person, from the app's saved state (being/state; fetch it with
// ArtifactData get ... out_dir). Usage: node analyze_session.js <state.json>. Written before the session (frozen).
const fs = require("fs");
const d = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), L = d.data || d, S = L.session || { marks: [], ev: [] };
const marks = S.marks, ev = S.ev, out = { marks, events: ev.length, segments: {} };
for (let i = 0; i < marks.length; i++) {
  const [t0, lab] = marks[i]; if (lab === "end") continue;
  const t1 = i + 1 < marks.length ? marks[i + 1][0] : Infinity, E = ev.filter(e => e[1] > t0 && e[1] <= t1);
  const span = E.length ? Math.max(...E.map(e => e[1])) - t0 : 0;
  const part = (from, to, cond) => {
    const X = E.filter(e => e[1] > from && e[1] <= to), C = X.filter(e => e[0] === "c" && (cond === undefined || e[3] === cond));
    const A = X.filter(e => e[0] === "a" && (cond === undefined || e[2] === cond)), G = X.filter(e => e[0] === "g" && (cond === undefined || e[3] === cond));
    const steps = X.filter(e => e[0] === "s").length * 100;
    return { calls: C.length, waitingShare: C.length ? +(C.filter(e => e[2]).length / C.length).toFixed(3) : null,
             answerShare: C.length ? +(A.length / C.length).toFixed(3) : null, gestures: G.length, ignored: X.filter(e => e[0] === "u").reduce((s, e) => s + e[2], 0),
             countedSteps: steps, callsPer100: steps ? +(100 * C.length / steps).toFixed(1) : null };
  };
  const end = t0 + span, s = E.filter(e => e[0] === "s"), lastS = s[s.length - 1];
  out.segments[lab] = { from: t0, to: end, all: part(t0, end), last300: part(end - 300, end), last750: part(end - 750, end), first750: part(t0, t0 + 750),
    formShare: s.length ? +(s.filter(e => e[11]).length / s.length).toFixed(3) : null,
    atEnd: lastS ? { sedimentTotal: lastS[2], r9m3: [lastS[3], lastS[4]], r10m3: [lastS[5], lastS[6]], r11m3: [lastS[7], lastS[8]], c3m3: [lastS[9], lastS[10]] } : null };
  if (lab === "3") out.segments[lab].live = part(t0, end, 1), out.segments[lab].replay = part(t0, end, 0);
}
console.log(JSON.stringify(out, null, 1));
