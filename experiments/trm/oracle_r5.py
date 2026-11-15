#!/usr/bin/env python3
"""S56 r5: 公式 TRM（~/trm_test/TinyRecursiveModels, MIT）の「正解」を作り直し、
H の一巡の記録点を足して experiments/trm/fixtures_r5/ に書く（仕様 discussion/specs/S56-trm-port.md §r5）。

- 旧 fixtures（experiments/trm/fixtures/*.json）と同じ乱数・重み・入力（oracle_work の configs / make_inputs /
  build_model / replace_weights_W1 / run_act_sequence / run_mixed_reset / to_json をそのまま呼ぶ）。
- 旧 fixtures の steps・mixed_reset とビット一致すること（dtype・shape・バイト列で比較。+0.0/-0.0 を区別）を自己検査する。
- 歩 k・mixed_reset の 1 手について、公式の inner のモジュール（_input_embeddings, L_level, lm_head, q_head）を
  同じ順で直接呼び、H の各巡の頭と終わりを記録する。ACT の forward は書き換えず、呼び直さない。
- 自己検査の結果は SELFCHECK_r5.txt、SHA256SUMS を fixtures_r5/ に書く。落ちたら exit 1。
- あわせて、（メモリ上だけの）反例と巡数不一致の記録で検査関数が失敗に効くことを自己検査する。
実行: PYTHONDONTWRITEBYTECODE=1 ~/erie-c/.venv-trm/bin/python experiments/trm/oracle_r5.py
"""
import sys

sys.dont_write_bytecode = True

import hashlib
import json
import os
from collections import OrderedDict

import torch  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fixtures_r5")
OLD = os.path.join(HERE, "fixtures")
SELFCHECK = os.path.join(HERE, "SELFCHECK_r5.txt")
UPSTREAM = os.path.abspath(os.path.expanduser("~/trm_test/TinyRecursiveModels"))
# 公式 trm.py（参照した _Inner.forward と ACT forward の行番号。2026-11-15 に読んだ版）
UPSTREAM_SHA = {"models/recursive_reasoning/trm.py": "3454818b64a1abb45c062782d380aa4bb560e2cb35db9cc309cf367ca3ac262c"}
INNER_FORWARD_LINES = (196, 223)   # _Inner.forward: seq_info → input_embeddings → H の巡 → LM outputs
ACT_FORWARD_LINES = (249, 297)     # TinyRecursiveReasoningModel_ACTV1.forward: reset_carry → inner → steps/halted
L_ITERS_NOTE = ("diagnostic only, not used by G-TF: l_iters[i] is z_L after L-level call i+1 of the round "
                "(inside the official inner forward, lines %d-%d of models/recursive_reasoning/trm.py)"
                % INNER_FORWARD_LINES)
# 旧 fixtures の steps で比べるテンソル（連鎖の検査の対象）
TENS = ("logits", "q_halt_logits", "q_continue_logits", "z_H", "z_L", "steps", "halted")


def trace_act(model, carry, batch):
    """ACT の 1 手を、公式と同じ順でモジュールを直接呼んで走らせる（forward は呼ばない）。
    1 手の頭の carry を受け取り、(新しい carry, 公式の out の辞書, 記録点) を返す。
    対応（公式の models/recursive_reasoning/trm.py）:
      ACT forward の 251: reset_carry            → ここで cin（carry_in）を作る
      ACT forward の 253: new_steps = where(...)  → steps
      ACT forward の 255: new_current_data        → cd（current_data）
      ACT forward の 258: inner(new_inner_carry, new_current_data) → 下のモジュール直呼び（INNER_FORWARD の各行）
    """
    inner = model.inner
    with torch.no_grad():
        C = type(carry)          # ACT の carry のクラス（内側の carry は type(carry.inner_carry)）
        # trm.py:251  new_inner_carry = self.inner.reset_carry(carry.halted, carry.inner_carry)
        cin = inner.reset_carry(carry.halted, type(carry.inner_carry)(z_H=carry.inner_carry.z_H.clone(),
                                                z_L=carry.inner_carry.z_L.clone()))
        # trm.py:253  new_steps = torch.where(carry.halted, 0, carry.steps)
        steps = torch.where(carry.halted, 0, carry.steps)
        # trm.py:255  new_current_data = {k: torch.where(...)}
        cd = {k: torch.where(carry.halted.view((-1,) + (1,) * (batch[k].ndim - 1)), batch[k], v)
              for k, v in carry.current_data.items()}
        # _Inner.forward の計算順: trm.py:196-223
        # trm.py:197-199  seq_info = dict(cos_sin=self.rotary_emb() if hasattr(...) else None)
        seq_info = dict(cos_sin=inner.rotary_emb() if hasattr(inner, "rotary_emb") else None)
        # trm.py:201-202  input_embeddings = self._input_embeddings(batch["inputs"], batch["puzzle_identifiers"])
        emb = inner._input_embeddings(cd["inputs"], cd["puzzle_identifiers"])
        # trm.py:205-206  it = 0 / z_H, z_L = carry.z_H, carry.z_L（この時点では cin の z_H・z_L）
        z_H, z_L = cin.z_H, cin.z_L
        z_H0, z_L0 = z_H, z_L            # 記録の巡 1 の頭（reset の後の carry）。以降は前の巡の終わり
        rounds = []
        # trm.py:207-216  H_cycles の巡（H_cycles-1 の no_grad の巡と 1 の巡）。H_cycles = 1 + (H_cycles-1) なので
        # 記録の巡は trm.py:196-223 の H の巡と同じ総数。推論（no_grad）なので 2 重のループで同じ順。
        for _H in range(inner.config.H_cycles):
            z_H_in, z_L_in = z_H, z_L    # trm.py:209 の z_H, z_L（巡の頭）
            l_iters = []
            # trm.py:210-212  for _L_step: z_L = self.L_level(z_L, z_H + input_embeddings, **seq_info)
            for _L in range(inner.config.L_cycles):
                z_L = inner.L_level(z_L, z_H + emb, **seq_info)
                l_iters.append(z_L.detach().clone())
            # trm.py:213  z_H = self.L_level(z_H, z_L, **seq_info)
            z_H = inner.L_level(z_H, z_L, **seq_info)
            ok_head = tensor_bits_eq(z_H_in, z_H0) and tensor_bits_eq(z_L_in, z_L0)
            z_H0, z_L0 = z_H, z_L
            rounds.append(OrderedDict([("z_H_in", z_H_in.detach().clone()), ("z_L_in", z_L_in.detach().clone()),
                                       ("z_H_out", z_H.detach().clone()), ("z_L_out", z_L.detach().clone()),
                                       ("l_iters", l_iters), ("z_H_after_update", z_H.detach().clone()),
                                       ("z_in_matches_prev", torch.tensor(ok_head))]))
        # trm.py:218-223  LM outputs（new_carry の z_H・z_L は上で作った最後の巡の z_H・z_L）
        logits = inner.lm_head(z_H)[:, inner.puzzle_emb_len:]
        q = inner.q_head(z_H[:, 0]).to(torch.float32)   # trm.py:222 Q-head; uses the first puzzle_emb position
        # trm.py:286-292  ACT forward の Step（no_grad）: new_steps + 1、halted = is_last_step（eval では training の分岐をとおらない）
        new_steps = steps + 1
        new_halted = new_steps >= model.config.halt_max_steps
        new_ic = type(cin)(z_H=z_H.detach(), z_L=z_L.detach())
        # 記録する out は、旧 fixtures の steps の形（logits・q に加え、新しい carry の z_H なども持つ）
        out = {"logits": logits, "q_halt_logits": q[..., 0], "q_continue_logits": q[..., 1],
               "z_H": new_ic.z_H, "z_L": new_ic.z_L, "steps": new_steps, "halted": new_halted,
               "current_data": cd}
    trace = OrderedDict([("carry_in", OrderedDict([("z_H", cin.z_H), ("z_L", cin.z_L)])),
                         ("current_data", cd), ("input_embeddings", emb), ("h_rounds", rounds),
                         ("outputs", out), ("l_iters_note", L_ITERS_NOTE)])
    new = C(new_ic, new_steps, new_halted, cd)
    return new, out, trace


def tensor_bytes(t):
    """連続なテンソルの生のバイト列（dtype の幅そのまま。+0.0 と -0.0 は違うバイト列になる）。"""
    return t.detach().contiguous().view(torch.uint8).numpy().tobytes()


def tensor_bits_eq(got, want):
    """ビット一致: dtype・shape が同じで、バイト列が同じ（torch.equal は +0.0 と -0.0 を区別しないので使わない）。"""
    return (got.dtype == want.dtype and tuple(got.shape) == tuple(want.shape)
            and tensor_bytes(got) == tensor_bytes(want))


def load_json(W, path):
    """JSON を、テンソルを torch.Tensor に戻した辞書として読む（float32 の data は文字列として読み込み、
    W._rebuild で float32 の配列にする経路。符号つきゼロまでそのまま戻る）。"""
    with open(path, encoding="utf-8") as f:
        return W._rebuild(json.loads(f.read(), object_pairs_hook=W._keep))


def with_carry(c, out):
    """oracle_work.act_outputs を新しい carry と out で呼び、z_H・z_L も out 側に持たせた dict にする。"""
    return {"logits": out["logits"], "q_halt_logits": out["q_halt_logits"],
            "q_continue_logits": out["q_continue_logits"],
            "z_H": c.inner_carry.z_H, "z_L": c.inner_carry.z_L, "steps": c.steps, "halted": c.halted,
            "current_data": dict(c.current_data)}


def dict_eq(got, want):
    """out の辞書（tensor と dict）のビット一致。外れた名前の列を返す。"""
    bad = [f for f in TENS if not tensor_bits_eq(got[f], want[f])]
    for ck in want["current_data"]:
        g = got["current_data"].get(ck)
        if g is None or not tensor_bits_eq(g, want["current_data"][ck]):
            bad.append("current_data/" + ck)
    return bad


def run_sequence(model, x1, x2, x3):
    """4 手と混ざった reset を、モジュールを直接呼んで走らせ、記録点も取る。
    steps の 4 歩の passed_input は ["x1","x2","x1","x3"]（旧 fixtures の steps は 5 歩を持つ）。"""
    steps, tr_steps, states, traces = OrderedDict(), OrderedDict(), [], []
    carry = model.initial_carry(x1)
    for i, x in enumerate((x1, x2, x1, x3), start=1):
        carry, out, trace = trace_act(model, carry, x)
        if i <= 4:
            out["passed_input"] = ["x1", "x2", "x1", "x3"][i - 1]
        steps["step%d" % i] = out
        tr_steps["step%d" % i] = trace
        traces.append((i, out, trace))
        states.append(carry)
    # 混ざった reset: 歩 1 の後の carry に、halted = [True, False] を立てて x2 を入れる（旧 fixtures の mixed_reset と同じ口）
    c = states[0]
    C = type(c)
    start = C(type(c.inner_carry)(z_H=c.inner_carry.z_H.clone(), z_L=c.inner_carry.z_L.clone()),
              c.steps.clone(), torch.tensor([True, False], dtype=torch.bool),
              {k: v.clone() for k, v in c.current_data.items()})
    new, out, trace = trace_act(model, start, x2)
    tr_mixed = OrderedDict([("step1", trace)])
    traces.append((None, out, trace))
    mixed = {"input": "x2", "start_halted": [True, False], "step1": out}
    return steps, tr_steps, mixed, tr_mixed, states, traces, new


def cfg_H(W):
    return W.CUR["H_cycles"]


def cfg_L(W):
    return W.CUR["L_cycles"]


def check_chain(W, trace, real_new):
    """連鎖: 巡 h の z_in は前の巡の z_out（巡 1 は reset の後の carry）、巡の数は H_cycles、
    各巡の L の回数は L_cycles、最後の巡の終わりは実際の ACT forward が返した新しい carry とビット一致。
    real_new はその forward の新しい carry。外れた所の名前列を返す（空なら通る）。"""
    hr = trace["h_rounds"]
    bad = []
    if len(hr) != cfg_H(W):                       # 巡数の不一致も失敗に効かせる
        bad.append("rounds%d!=%d" % (len(hr), cfg_H(W)))
    for h, r in enumerate(hr):
        prev = trace["carry_in"] if h == 0 else hr[h - 1]
        if not (tensor_bits_eq(r["z_H_in"], prev["z_H"] if h == 0 else prev["z_H_out"])
                and tensor_bits_eq(r["z_L_in"], prev["z_L"] if h == 0 else prev["z_L_out"])):
            bad.append("in%d" % (h + 1))
        if not bool(r["z_in_matches_prev"]):
            bad.append("inprev%d" % (h + 1))
        if not tensor_bits_eq(r["z_H_out"], r["z_H_after_update"]):
            bad.append("out%d" % (h + 1))
        if len(r["l_iters"]) != cfg_L(W):
            bad.append("liter%d" % (h + 1))
    ic = real_new.inner_carry
    if not (tensor_bits_eq(hr[-1]["z_H_out"], ic.z_H) and tensor_bits_eq(hr[-1]["z_L_out"], ic.z_L)):
        bad.append("carry")
    if not tensor_bits_eq(trace["carry_in"]["z_H"], hr[0]["z_H_in"]):
        bad.append("carry_in_H")
    return bad


def main():
    import oracle_export as E
    E.install_buffer_shim(torch)
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    if UPSTREAM not in sys.path:
        sys.path.insert(0, UPSTREAM)
    import oracle_work as W
    from models.recursive_reasoning.trm import TinyRecursiveReasoningModel_ACTV1 as ACTV1
    lines = []
    ok_all = True

    def check(name, ok, detail=""):
        nonlocal ok_all
        lines.append("%s %s %s" % ("PASS" if bool(ok) else "FAIL", name, detail))
        ok_all = bool(ok) and ok_all

    os.makedirs(OUT, exist_ok=True)
    torch.set_grad_enabled(False)
    # 公式の forward とモジュール直呼びが同じ演算の選択になるよう、決定的な算法だけを使う（oracle_work.run() と同じ設定）
    torch.use_deterministic_algorithms(True)
    files = []
    for cname in ("a", "b", "c", "d", "e"):
        cfg = W.configs()[cname]
        g = torch.Generator().manual_seed(W.SEED_INPUT)
        x1, x2, x3 = W.make_inputs(g, cfg), W.make_inputs(g, cfg), W.make_inputs(g, cfg)
        for wname in ("W0", "W1"):
            tag = "%s_%s" % (cname, wname)
            model = W.build_model(cfg, wname, ACTV1)   # 同じ初期化の種・同じ置き換え
            W.CUR = cfg
            steps, tr_steps, mixed, tr_mixed, states, traces, mixed_new = run_sequence(model, x1, x2, x3)
            obj = OrderedDict([("layout", W.LAYOUT), ("config", cfg), ("seed_weight", W.SEED_WEIGHT),
                               ("seed_input", W.SEED_INPUT), ("seed_replace", W.SEED_REPLACE),
                               ("state_dict", model.state_dict()), ("rope", OrderedDict()),
                               ("inputs", OrderedDict([("x1", x1), ("x2", x2), ("x3", x3)])),
                               ("steps", steps), ("mixed_reset", mixed),
                               ("trace", OrderedDict([("steps", tr_steps), ("mixed_reset", tr_mixed)])),
                               ("trace_note", "h_rounds[].l_iters and .z_H_after_update are diagnostic, not used by G-TF")])
            if hasattr(model.inner, "rotary_emb"):
                obj["rope"]["cos_cached"] = model.inner.rotary_emb.cos_cached.clone()
                obj["rope"]["sin_cached"] = model.inner.rotary_emb.sin_cached.clone()
            path = os.path.join(OUT, tag + ".json")
            with open(path, "w", encoding="utf-8") as f:
                f.write(W.to_json(obj) + "\n")
            files.append((tag, path))

            # 実際の ACT forward（oracle_work の口）と比べる
            with torch.no_grad():
                f_steps, f_states = W.run_act_sequence(model, x1, x2, x3)
                f_mixed = W.run_mixed_reset(model, f_states[0], x2)
            bad = []
            f_acts = [with_carry(f_states[i], f_steps["step%d" % (i + 1)]) for i in range(4)]
            for i in range(4):
                k = "step%d" % (i + 1)
                bad += ["forward/%s/%s" % (k, n) for n in dict_eq(steps[k], f_acts[i])]
            c0 = type(f_states[0])(type(f_states[0].inner_carry)(
                z_H=f_states[0].inner_carry.z_H.clone(), z_L=f_states[0].inner_carry.z_L.clone()),
                f_states[0].steps.clone(), torch.tensor([True, False], dtype=torch.bool),
                {k: v.clone() for k, v in f_states[0].current_data.items()})
            mixed_c, mixed_o = model(c0, x2)
            bad += ["forward/mixed/%s" % n for n in dict_eq(mixed["step1"], with_carry(mixed_c, mixed_o))]
            bad += ["forward/mixed/%s" % n for n in dict_eq(mixed["step1"], f_mixed["step1"])]
            check("module_calls_equal_forward_%s" % tag, not bad, "bad=%r" % (bad[:6],))

            # (PT5-0) 旧 fixtures とビット一致（旧 JSON の float32 の data を float32 に戻す経路で比べる）
            old = load_json(W, os.path.join(OLD, tag + ".json"))
            bad = []
            for k, want in [("steps", old["steps"]), ("mixed_reset", old["mixed_reset"])]:
                got = steps if k == "steps" else mixed
                for kk in want:
                    if kk in ("passed_input", "input", "start_halted"):
                        if got.get(kk) != want[kk]:
                            bad.append("%s/%s" % (k, kk))
                        continue
                    bad += ["%s/%s/%s" % (k, kk, n) for n in dict_eq(got[kk], want[kk])]
            check("PT5-0_old_fixtures_bitequal_%s" % tag, not bad, "bad=%r" % (bad[:6],))

            # (連鎖) 各歩の巡の連鎖が、実際の forward が返した新しい carry と最後の巡でビット一致。outputs も ACT の出力と一致
            bad = []
            for i, out, trace in traces[:4]:
                k = "step%d" % i
                bad += [k + "/" + n for n in check_chain(W, trace, f_states[i - 1])]
                bad += [k + "/out/" + n for n in ("logits", "q_halt_logits", "q_continue_logits")
                        if not tensor_bits_eq(out[n], f_steps[k][n])]
            bad += ["mix/" + n for n in check_chain(W, tr_mixed["step1"], mixed_new)]
            bad += ["mix/out/" + n for n in ("logits", "q_halt_logits", "q_continue_logits")
                    if not tensor_bits_eq(mixed["step1"][n], f_mixed["step1"][n])]
            check("chain_%s" % tag, not bad, "H=%d L=%d bad=%r" % (cfg["H_cycles"], cfg["L_cycles"], bad[:6]))

            # (読み戻し) 書いた JSON を読み戻した値が、書く前のテンソルとビット一致
            back = load_json(W, path)
            bad = []
            for k in obj:
                if k in ("steps", "mixed_reset", "trace"):
                    continue
                if k == "config":
                    if dict(back[k]) != dict(obj[k]):
                        bad.append(k)
                elif k == "inputs":
                    bad += ["inputs/%s/%s" % (n, m) for n in obj[k] for m in obj[k][n]
                            if not tensor_bits_eq(back[k][n][m], obj[k][n][m])]
                elif k in ("state_dict", "rope"):
                    if list(back[k]) != list(obj[k]):
                        bad.append(k + "/keys")
                    bad += [k + "/" + n for n in obj[k] if not tensor_bits_eq(back[k][n], obj[k][n])]
            for nm, got, want in (("steps", back["steps"], steps), ("mixed_reset", back["mixed_reset"], mixed)):
                for k in want:
                    if k in ("passed_input", "input", "start_halted"):
                        continue
                    bad += ["%s/%s/%s" % (nm, k, n) for n in dict_eq(got[k], want[k])]
            for nm, tr_ in (("steps", tr_steps), ("mixed_reset", tr_mixed)):
                for k in tr_:
                    a, b = back["trace"][nm][k], tr_[k]
                    if not isinstance(b.get("l_iters_note"), str) or a["l_iters_note"] != b["l_iters_note"]:
                        bad.append("%s/%s/l_iters_note" % (nm, k))
                    for n in ("z_H", "z_L"):
                        if not tensor_bits_eq(a["carry_in"][n], b["carry_in"][n]):
                            bad.append("%s/%s/carry_in/%s" % (nm, k, n))
                    bad += ["%s/%s/current_data/%s" % (nm, k, n) for n in b["current_data"]
                            if not tensor_bits_eq(a["current_data"][n], b["current_data"][n])]
                    if not tensor_bits_eq(a["input_embeddings"], b["input_embeddings"]):
                        bad.append("%s/%s/input_embeddings" % (nm, k))
                    if len(a["h_rounds"]) != len(b["h_rounds"]):
                        bad.append("%s/%s/h_rounds/count" % (nm, k))
                    for h, (ra, rb) in enumerate(zip(a["h_rounds"], b["h_rounds"])):
                        for f in ("z_H_in", "z_L_in", "z_H_out", "z_L_out", "z_H_after_update",
                                  "z_in_matches_prev"):
                            if not tensor_bits_eq(ra[f], rb[f]):
                                bad.append("%s/%s/h%d/%s" % (nm, k, h + 1, f))
                        if len(ra["l_iters"]) != len(rb["l_iters"]) or not all(
                                tensor_bits_eq(u, v) for u, v in zip(ra["l_iters"], rb["l_iters"])):
                            bad.append("%s/%s/h%d/l_iters" % (nm, k, h + 1))
                    bad += ["%s/%s/outputs/%s" % (nm, k, n) for n in ("logits", "q_halt_logits", "q_continue_logits")
                            if not tensor_bits_eq(a["outputs"][n], b["outputs"][n])]
            check("readback_%s" % tag, not bad, "bad=%r" % (bad[:6],))
            lines.append("INFO file %s %s" % (tag, os.path.basename(path)))

    # 検査関数が実際に失敗に効くことの確認（メモリ上だけ。ファイルには残さない）
    neg1 = torch.tensor([0.0, -0.0], dtype=torch.float32)
    pos1 = torch.tensor([0.0, 0.0], dtype=torch.float32)
    check("bitequal_rejects_signed_zero", (not tensor_bits_eq(neg1, pos1)) and bool(torch.equal(neg1, pos1)),
          "torch.equal=True, tensor_eq=%r" % tensor_bits_eq(neg1, pos1))
    check("bitequal_accepts_identical", tensor_bits_eq(neg1, neg1.clone()))
    probe = OrderedDict((k, v) for k, v in tr_steps["step1"].items())   # 1 巡削った記録（メモリ上の写し）
    probe["h_rounds"] = list(tr_steps["step1"]["h_rounds"][:-1]) if cfg_H(W) > 1 else []
    check("chain_rejects_missing_round", check_chain(W, probe, mixed_new) != [],
          "bad=%r" % (check_chain(W, probe, mixed_new)[:3],))
    check("chain_accepts_recorded", check_chain(W, tr_steps["step1"], states[0]) == [],
          "bad=%r" % (check_chain(W, tr_steps["step1"], states[0])[:3],))

    # 由来（公式の trm.py の sha）
    sha = hashlib.sha256(open(os.path.join(UPSTREAM, "models/recursive_reasoning/trm.py"), "rb").read()).hexdigest()
    check("upstream_sha_trm_py", sha == UPSTREAM_SHA["models/recursive_reasoning/trm.py"], sha)

    with open(os.path.join(OUT, "SHA256SUMS"), "w", encoding="utf-8") as f:
        for tag, path in files:
            f.write("%s  %s\n" % (hashlib.sha256(open(path, "rb").read()).hexdigest(), os.path.basename(path)))
            if W.sha256(path) != hashlib.sha256(open(path, "rb").read()).hexdigest():
                ok_all = False
    lines.append("files %d" % len(files))
    lines.append("ALL PASS" if ok_all else "FAILED")
    with open(SELFCHECK, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
