// Ground-truth types of templates-digest.toml used by the viewer (same wiring and labels).
const TYPES = [
  { name: "selfloop-pair-agent", label: "主体（自己結線つき）", L: [true, true, true], units: ["s1","s2","m1","m2","c1","c2"], theta: [1,1,2,2,1,1],
    sensors: { s1: 1, s2: 2 }, motors: { m1: 1, m2: 2 }, maintain: true, initial: ["c1","c2"],
    edges: [["c1","c1",1],["c2","c2",1],["c1","c2",1],["c2","c1",1],["s1","m1",1],["c1","m1",1],["s2","m2",1],["c2","m2",1]] },
  { name: "agent", label: "主体（基本）", L: [true, true, false], units: ["s1","s2","m1","m2","c1","c2"], theta: [1,1,2,2,1,1],
    sensors: { s1: 1, s2: 2 }, motors: { m1: 1, m2: 2 }, maintain: true, initial: ["c1","c2"],
    edges: [["c1","c2",1],["c2","c1",1],["s1","m1",1],["c1","m1",1],["s2","m2",1],["c2","m2",1]] },
  { name: "triangle-agent", label: "主体（3ユニットの核）", L: [true, true, true], units: ["s1","s2","m1","m2","c1","c2","c3"], theta: [1,1,2,2,1,1,1],
    sensors: { s1: 1, s2: 2 }, motors: { m1: 1, m2: 2 }, maintain: true, initial: ["c1","c2","c3"],
    edges: [["c1","c2",1],["c1","c3",1],["c2","c1",1],["c2","c3",1],["c3","c1",1],["c3","c2",1],["s1","m1",1],["c1","m1",1],["s2","m2",1],["c2","m2",1]] },
  { name: "omnivore", label: "選ばない型（omnivore）", L: [false, true, true], units: ["m1","m2","c1","c2","c3"], theta: [1,1,1,1,1],
    sensors: {}, motors: { m1: 1, m2: 2 }, maintain: true, initial: ["c1","c2","c3"],
    edges: [["c1","c2",1],["c1","c3",1],["c2","c1",1],["c2","c3",1],["c3","c1",1],["c3","c2",1],["c1","m1",1],["c2","m1",1],["c1","m2",1],["c3","m2",1]] },
  { name: "alternator", label: "交互に動く型（alternator）", L: [false, true, false], units: ["a","b","m1","m2"], theta: [1,1,1,1],
    sensors: {}, motors: { m1: 1, m2: 2 }, maintain: true, initial: ["a"],
    edges: [["a","b",1],["b","a",1],["a","m1",1],["b","m2",1]] },
  { name: "reflex", label: "反射（reflex）", L: [false, true, false], units: ["m1","c1","c2"], theta: [1,1,1],
    sensors: {}, motors: { m1: 1 }, maintain: true, initial: ["c1","c2"],
    edges: [["c1","c2",1],["c2","c1",1],["c1","m1",1]] },
];
if (typeof module !== "undefined") module.exports = TYPES;
