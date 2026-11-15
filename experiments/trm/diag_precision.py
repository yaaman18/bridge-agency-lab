#!/usr/bin/env python3
"""S56 診断（測定だけ）: 構成 a・c・d の差が丸めの増幅か、本当の経路の差かを測る。

公式 TRM（SamsungSAILMontreal/TinyRecursiveModels, commit 7de0d20, MIT: LICENSE-upstream-MIT.txt）を
oracle_export.py と同じ作り方（同じ種・同じ入力・同じ shim）で組み、fixtures の state_dict を読む。
公式を Float32 と Float64（model.double()）の 2 回走らせ、ACT の手ごと（1〜3）の
logits・z_H・z_L・q_halt_logits・q_continue_logits の最大の絶対差を表に出し、
Float64 の出力を diag/py_f64_<構成>_<W>.json（行優先の平らな配列＋形）に書く（構成 a も c・d と同じ形式）。
ついでに Float32 の出力が fixtures の値とビット一致するか（max abs diff）を出す。
公式のコード・fixtures は読むだけで書かない。何も変更せず、結果は標準出力にだけ出す。

使い方: PYTHONDONTWRITEBYTECODE=1 ~/erie-c/.venv-trm/bin/python experiments/trm/diag_precision.py
"""
import sys

sys.dont_write_bytecode = True  # ラボにも公式のディレクトリにも __pycache__ を作らない

import json
import os
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
UPSTREAM = os.path.abspath(os.path.expanduser("~/trm_test/TinyRecursiveModels"))
FIXTURES = os.path.join(HERE, "fixtures")
DIAG = os.path.join(HERE, "diag")
PASSED = ("x1", "x2", "x1")  # ACT の手 1〜3 で渡すもの（oracle_work.run_act_sequence と同じ）
QUANTITIES = ("logits", "z_H", "z_L", "q_halt_logits", "q_continue_logits")
CONFIGS = ("a", "c", "d")  # a は条件の良い構成（有効性の確認 (ii) に使う）
WEIGHTS = ("W0", "W1")


def fixture_tensor(d):
    """fixtures の {"dtype","shape","data"}（行優先）→ torch のテンソル。"""
    import torch
    dt = {"float32": torch.float32, "int32": torch.int32, "int64": torch.int64, "bool": torch.bool}[d["dtype"]]
    if dt == torch.bool:
        data = [bool(v) for v in d["data"]]
    elif dt in (torch.int32, torch.int64):
        data = [int(v) for v in d["data"]]
    else:
        data = [float(v) for v in d["data"]]
    t = torch.tensor(data, dtype=dt)
    return t.reshape(tuple(int(x) for x in d["shape"]))


def load_fixture(c, w):
    with open(os.path.join(FIXTURES, "%s_%s.json" % (c, w)), encoding="utf-8") as f:
        return json.load(f)


def build(c, w, ACTV1):
    """fixtures と同じ構成の作り、fixtures の state_dict を読む（oracle_work.load_model と同じ）。"""
    fx = load_fixture(c, w)
    model = ACTV1(dict(fx["config"]))
    sd = OrderedDict((k, fixture_tensor(v)) for k, v in fx["state_dict"].items())
    model.load_state_dict(sd)
    model.eval()
    inputs = {k: {kk: fixture_tensor(vv) for kk, vv in v.items()} for k, v in fx["inputs"].items()}
    return model, fx, inputs


def run(model, inputs):
    """ACT の手 1〜3。x1,x2,x1 を渡し、each step の出力と carry の z を f64 で copy して返す。"""
    import torch
    out_steps = []
    with torch.no_grad():
        carry = model.initial_carry(inputs["x1"])
        for name in PASSED:
            carry, out = model(carry, inputs[name])
            out_steps.append({"logits": out["logits"].double().clone(),
                              "q_halt_logits": out["q_halt_logits"].double().clone(),
                              "q_continue_logits": out["q_continue_logits"].double().clone(),
                              "z_H": carry.inner_carry.z_H.double().clone(),
                              "z_L": carry.inner_carry.z_L.double().clone()})
    return out_steps


def maxdiff(a, b):
    return float((a.double() - b.double()).abs().max().item())


def flat_json(t):
    shape = [int(s) for s in t.shape]
    data = [float(v) for v in t.detach().reshape(-1).tolist()]  # 行優先（C order）の平らな配列
    return OrderedDict([("shape", shape), ("data", data)])


def reference(fx, k):
    """fixtures の step k の参照（tensor の辞書）。"""
    return {q: fixture_tensor(fx["steps"]["step%d" % k][q]) for q in QUANTITIES}


def j_diff(a, b):
    """同じ位置の値の (a-b)/|a| の最大（丸めを見る単位のない量）。"""
    d = (a.double() - b.double()).abs() / a.double().abs().clamp_min(1e-300)
    return float(d.max().item())


def one_weight(make, inputs, rel):
    """make() で真の Float64 の重みを持つモデルを組み、embed_tokens の表の絶対値が最大の要素を相対 rel だけずらす
    （2^-19 は f32 の 1/32 ulp の大きさ。q_head は公式が 0 にしているので動かさない）。
    f64 の走りを手 1 だけ走らせ、もととの logits の相対変化の最大を返す。"""
    m0 = make()
    W = m0.inner.embed_tokens.embedding_weight
    k = int(W.abs().reshape(-1).argmax().item())    # 0 始まりの通し番号
    i, j = k // W.shape[1], k % W.shape[1]
    x = inputs[PASSED[0]]
    def step(m):
        carry = m.initial_carry(x)
        carry, out = m(carry, x)
        return out["logits"].double().clone()
    base = step(m0)
    del m0
    p = make()
    p.inner.embed_tokens.embedding_weight[i, j] = p.inner.embed_tokens.embedding_weight[i, j] * (1.0 + rel)
    return j_diff(step(p), base)


def main():
    import torch
    sys.path.insert(0, HERE)
    sys.path.insert(0, UPSTREAM)
    import oracle_export as E
    E.install_buffer_shim(torch)
    torch.set_grad_enabled(False)
    from models.recursive_reasoning.trm import TinyRecursiveReasoningModel_ACTV1 as ACTV1

    os.makedirs(DIAG, exist_ok=True)
    lines = []
    p = lines.append
    p("S56 diag precision (measurement only): a, c and d, f32 vs f64, ACT steps 1-3")
    p("torch %s; python %s; upstream %s" % (torch.__version__, sys.version.split()[0], UPSTREAM))
    p("sequence: passed input x1, x2, x1 (as oracle_work.run_act_sequence steps 1-3); z after the step")
    p("all numbers are max abs diffs, not tolerances")
    for c in CONFIGS:
        for w in WEIGHTS:
            model, fx, inputs = build(c, w, ACTV1)
            f32_weights = model   # f64 の写しへ渡す重み・入力（Float32 の写し）
            f32_steps = run(model, inputs)
            model64 = model.double()
            f64_steps = run(model64, inputs)
            p("")
            p("== %s %s ==" % (c, w))
            p("step  quantity           f32|fixture|max   f64-vs-f32 max")
            for k in range(1, 4):
                ref = reference(fx, k)
                for q in QUANTITIES:
                    p("%4d  %-18s %17.6e  %16.6e" % (k, q, maxdiff(f32_steps[k - 1][q], ref[q].float()),
                                                      maxdiff(f64_steps[k - 1][q], f32_steps[k - 1][q])))
            for k in range(1, 4):
                ref = reference(fx, k)
                row = {q: maxdiff(f32_steps[k - 1][q], ref[q]) for q in QUANTITIES}
                p("  f32 fixture max step%d: %s" % (k, " ".join("%s=%.3e" % (q, v) for q, v in row.items())))
                row64 = {q: maxdiff(f64_steps[k - 1][q], f32_steps[k - 1][q]) for q in QUANTITIES}
                p("  f64 vs f32 max step%d: %s" % (k, " ".join("%s=%.3e" % (q, v) for q, v in row64.items())))
            obj = OrderedDict([("config", c), ("weights", w), ("dtype", "float64"),
                               ("sequence", list(PASSED)), ("layout", "row-major flat arrays with shape"),
                               ("steps", OrderedDict(("step%d" % (k + 1), OrderedDict(
                                   (q, flat_json(f64_steps[k][q])) for q in QUANTITIES)) for k in range(3)))])
            path = os.path.join(DIAG, "py_f64_%s_%s.json" % (c, w))
            with open(path, "w", encoding="utf-8") as f:
                json.dump(obj, f)
            p("wrote %s" % os.path.relpath(path, HERE))
            # f64 の写しの有効性の確認に使う: fixtures と同じ重み・入力の f32 の写し（同じ形式）を diag/py_f32_<構成>_<W>.json に。
            sd32 = OrderedDict((k, flat_json(v.detach())) for k, v in f32_weights.state_dict().items())
            ins32 = OrderedDict((n, OrderedDict((kk, flat_json(vv)) for kk, vv in inputs[n].items())) for n in PASSED)
            obj32 = OrderedDict([("config", c), ("weights", w), ("dtype", "float32"),
                                 ("sequence", list(PASSED)), ("layout", "row-major flat arrays with shape"),
                                 ("state_dict", sd32), ("inputs", ins32)])
            path32 = os.path.join(DIAG, "py_f32_%s_%s.json" % (c, w))
            with open(path32, "w", encoding="utf-8") as f:
                json.dump(obj32, f)
            p("wrote %s" % os.path.relpath(path32, HERE))
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
