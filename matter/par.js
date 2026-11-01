// Parallel runner (2026-10-31, user: make the trials faster). Runs one script per job, each job a set of environment
// variables (e.g. one world and one seed), at most MAXP at a time (default: CPU count - 2). Usage:
//   node par.js <script.js> '<json array of env objects>' [maxParallel]
// Each job's stdout/stderr goes to <outDir>/<script>-<k=v...>.log (outDir = env PAR_OUT or ./par-logs); a summary line per job.
const { spawn } = require("child_process"), os = require("os"), fs = require("fs"), path = require("path");
const [script, jobsJson, maxArg] = process.argv.slice(2), jobs = JSON.parse(jobsJson), MAXP = +(maxArg || Math.max(1, os.cpus().length - 2));
const outDir = process.env.PAR_OUT || path.join(__dirname, "par-logs"); fs.mkdirSync(outDir, { recursive: true });
let next = 0, running = 0, done = 0; const t0 = Date.now();
function launch() {
  while (running < MAXP && next < jobs.length) {
    const env = jobs[next++], tag = Object.entries(env).map(([k, v]) => `${k}=${v}`).join("_"), log = path.join(outDir, `${path.basename(script, ".js")}-${tag}.log`);
    const out = fs.openSync(log, "w"), ch = spawn(process.execPath, [script], { env: { ...process.env, ...env }, stdio: ["ignore", out, out] }); running++;
    const s = Date.now(); ch.on("exit", code => { running--; done++; console.log(`[${done}/${jobs.length}] ${tag} exit ${code} ${((Date.now() - s) / 1000).toFixed(0)}s -> ${log}`); if (done === jobs.length) console.log(`all done in ${((Date.now() - t0) / 1000).toFixed(0)}s`); else launch(); });
  }
}
launch();
