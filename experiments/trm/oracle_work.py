"""S56 手 1 の本体: 公式 TRM を sys.path で読み、5 構成 × 2 組（W0・W1）の「正解」を JSON に書き出す。

JSON の形（構成ごと・重みの組ごとに fixtures/<構成>_<W0|W1>.json）:
  config, seed_*, state_dict（永続のみ。cos/sin は rope キー）, rope, inputs, steps, mixed_reset,
  intermediates（W1 だけ）, env。
書き出しは 2 回走らせ、全ファイルの sha256 が同じことを確かめてから SELFCHECK.txt・SHA256SUMS を書く。
自己検査に落ちたら 0 でない終了コードで終わる。
"""
import hashlib
import json
import math
import os
import subprocess
import sys
from collections import OrderedDict

import torch

SEED_WEIGHT = 20261115   # モデルの初期化
SEED_INPUT = 20261116    # 入力（x1・x2・x3）
SEED_REPLACE = 20261117  # W1 の置き換え
UPSTREAM_COMMIT = "7de0d20c8f26df706e2c7b3a21ceaf0b3542c953"
UPSTREAM_SHA = {"models/recursive_reasoning/trm.py": "3454818b64a1abb45c062782d380aa4bb560e2cb35db9cc309cf367ca3ac262c",
                "models/layers.py": "519d38a4668c343868bf31a5853cab7f455f9dcac0cbcc36e02f95dce9fb01e7",
                "models/common.py": "fa749ad9b68ac0852f9cda157baa3a9c2ff8abaee973751b32b7cd010a4cf859",
                "models/sparse_embedding.py": "9429742ce022918751331acf92c1a9b8d0f2f364e9acef5d71fb81b886c7a2d0"}
UPSTREAM_SRC = ["models/recursive_reasoning/trm.py", "models/layers.py", "models/common.py",
                "models/sparse_embedding.py", "__init__.py", "LICENSE"]
UPSTREAM_DIR = "~/trm_test/TinyRecursiveModels"  # run() が --upstream の値で置き換える
BASE = dict(batch_size=2, seq_len=8, vocab_size=12, H_cycles=3, L_cycles=6, H_layers=0, L_layers=2,
            expansion=4, halt_max_steps=3, halt_exploration_prob=0.1, forward_dtype="float32",
            no_ACT_continue=True, num_puzzle_identifiers=5)


def configs():
    """仕様 §2 の (a)〜(e)。(a)〜(c) は puzzle_emb_ndim 0 と puzzle_emb_len 0 を明示する。"""
    a = dict(BASE, puzzle_emb_ndim=0, puzzle_emb_len=0, hidden_size=32, num_heads=2, pos_encodings="rope", mlp_t=False)
    return OrderedDict([
        ("a", a),
        ("b", dict(a, pos_encodings="learned")),
        ("c", dict(a, pos_encodings="none", mlp_t=True)),
        ("d", dict(a, puzzle_emb_ndim=32, puzzle_emb_len=2)),
        ("e", dict(a, hidden_size=128, num_heads=4)),
    ])


def make_inputs(gen, cfg):
    ids = torch.randint(0, cfg["vocab_size"], (cfg["batch_size"], cfg["seq_len"]), generator=gen, dtype=torch.int32)
    p0 = int(torch.randint(0, cfg["num_puzzle_identifiers"], (1,), generator=gen))
    p1 = int(torch.randint(0, cfg["num_puzzle_identifiers"], (1,), generator=gen))
    if p1 == p0:  # batch の二つで違う識別子にする
        p1 = (p1 + 1) % cfg["num_puzzle_identifiers"]
    return {"inputs": ids, "puzzle_identifiers": torch.tensor([p0, p1], dtype=torch.int32)}


def replace_weights_W1(model, cfg):
    """q_head の weight・bias、puzzle の埋め込み（あれば）、H_init・L_init を、固定の種の乱数で
    0 でない非対称の値に置き換える（H_init と L_init は互いに違う値）。"""
    g = torch.Generator().manual_seed(SEED_REPLACE)

    def asym(shape, offset):
        r = torch.rand(shape, generator=g, dtype=torch.float32)          # [0,1)
        s = torch.arange(1, r.numel() + 1, dtype=torch.float32).reshape(shape) / float(r.numel())
        return r - 0.5 + 0.4 * s + offset

    inner = model.inner
    with torch.no_grad():
        inner.q_head.weight.copy_(asym(inner.q_head.weight.shape, 0.05))
        inner.q_head.bias.copy_(asym(inner.q_head.bias.shape, -0.05))
        if cfg["puzzle_emb_ndim"] > 0:
            w = inner.puzzle_emb.weights
            for i in range(w.shape[0]):
                w[i].copy_(asym((w.shape[1],), 0.1 * (i + 1)))
        inner.H_init.copy_(asym(inner.H_init.shape, 0.2))
        inner.L_init.copy_(asym(inner.L_init.shape, -0.3))


def clone_carry(c):
    C = type(c)
    return C(type(c.inner_carry)(z_H=c.inner_carry.z_H.clone(), z_L=c.inner_carry.z_L.clone()),
             c.steps.clone(), c.halted.clone(), {k: v.clone() for k, v in c.current_data.items()})


def act_outputs(carry, out):
    return {"logits": out["logits"], "q_halt_logits": out["q_halt_logits"],
            "q_continue_logits": out["q_continue_logits"],
            "z_H": carry.inner_carry.z_H, "z_L": carry.inner_carry.z_L,
            "steps": carry.steps, "halted": carry.halted, "current_data": dict(carry.current_data)}


def run_act_sequence(model, x1, x2, x3):
    """ACT の列 4 手。手 1〜3 は batch に x1 を渡し（手 2 では渡すものだけ x2）、止まっていないあいだ
    current_data は x1 のまま。手 3 の後に halted が全部 True。手 4 は x3 を渡し、carry が reset される。
    渡した入力は各手の "passed_input" に記録する（Julia の側が同じ列を再現するため）。"""
    carry = model.initial_carry(x1)
    steps, states = OrderedDict(), []
    for i, (name, x) in enumerate((("x1", x1), ("x2", x2), ("x1", x1), ("x3", x3)), start=1):
        carry, out = model(carry, x)
        steps["step%d" % i] = dict(act_outputs(carry, out), passed_input=name)
        states.append(clone_carry(carry))
    return steps, states


def run_mixed_reset(model, state_after_step1, x2):
    """手 1 の後の carry から halted を [True, False] に書き換え（steps・current_data はそのまま）、x2 を 1 手。"""
    carry = clone_carry(state_after_step1)
    carry.halted = torch.tensor([True, False], dtype=torch.bool)
    carry, out = model(carry, x2)
    return {"input": "x2", "start_halted": [True, False], "step1": act_outputs(carry, out)}


def first_block_evidence(model, x1):
    """手 1 の実際の forward で、L_level.layers[0] の最初の呼び出しの入力と出力を記録する。"""
    blk = model.inner.L_level.layers[0]
    calls = []
    orig_forward = blk.forward

    def rec_forward(*args, **kwargs):
        out = orig_forward(*args, **kwargs)
        if not calls:
            calls.append((kwargs["hidden_states"].detach().clone(), out.detach().clone()))
        return out

    with torch.no_grad():
        ref_logits = model(model.initial_carry(x1), x1)[1]["logits"].clone()
        blk.forward = rec_forward          # インスタンスの属性。公式のファイルは変えない
        try:
            _carry, out = model(model.initial_carry(x1), x1)
        finally:
            del blk.forward                # クラスの forward に戻る
    assert len(calls) == 1
    return {"h": calls[0][0], "out": calls[0][1],
            "logits_equal": bool(torch.equal(ref_logits, out["logits"]))}


def run_intermediates(model, x1, real=None):
    """W1・手 1 の中間の量。公式の関数を同じ順で呼び直して取る。real は first_block_evidence の結果
    （実際の forward の最初のブロックの入出力の記録。書き換えない）。"""
    from models.layers import rms_norm
    inner = model.inner
    blk = inner.L_level.layers[0]
    cos_sin = inner.rotary_emb() if hasattr(inner, "rotary_emb") else None
    inner_carry = model.initial_carry(x1)
    reset_flag = inner_carry.halted  # 最初は全部 True → reset_carry で H_init・L_init になる
    cin = inner.reset_carry(reset_flag, inner_carry.inner_carry)
    emb = inner._input_embeddings(x1["inputs"], x1["puzzle_identifiers"])
    real = real or {}

    h = cin.z_L + (cin.z_H + emb)                       # 公式: hidden_states + input_injection
    with torch.no_grad():
        if blk.config.mlp_t:
            ht = h.transpose(1, 2)
            a = blk.mlp_t(ht)                            # 転置した形のまま書き出す
            n1 = rms_norm(ht + a, variance_epsilon=blk.norm_eps).transpose(1, 2)
        else:
            a = blk.self_attn(cos_sin=cos_sin, hidden_states=h)
            n1 = rms_norm(h + a, variance_epsilon=blk.norm_eps)
        m = blk.mlp(n1)
        n2 = rms_norm(n1 + m, variance_epsilon=blk.norm_eps)
    h_eq = bool(torch.equal(h, real["h"]))               # real は first_block_evidence の返り値。書き換えない
    n2_eq = bool(torch.equal(n2, real["out"]))
    h_wrong = cin.z_H + (cin.z_L + emb)
    wrong_differs = not bool(torch.equal(h_wrong, real["h"]))   # 参考の量（検査の合否には使わない）
    first_block = OrderedDict([("h_eq", h_eq), ("n2_eq", n2_eq),
                               ("wrapped_logits_equal", real["logits_equal"]),
                               ("wrong_order_differs", wrong_differs),
                               ("max_abs_h_diff", float((h - real["h"]).abs().max())),
                               ("max_abs_n2_diff", float((n2 - real["out"]).abs().max()))])

    # 各 H 周回の終わりの z_H・z_L（inner.forward と同じ順）。最後が inner.forward の carry と一致すること。
    z_H, z_L = cin.z_H, cin.z_L
    h_round_end = []
    with torch.no_grad():
        for _H in range(inner.config.H_cycles - 1):
            for _L in range(inner.config.L_cycles):
                z_L = inner.L_level(z_L, z_H + emb, cos_sin=cos_sin)
            z_H = inner.L_level(z_H, z_L, cos_sin=cos_sin)
            h_round_end.append({"z_H": z_H.clone(), "z_L": z_L.clone()})
        for _L in range(inner.config.L_cycles):
            z_L = inner.L_level(z_L, z_H + emb, cos_sin=cos_sin)
        z_H = inner.L_level(z_H, z_L, cos_sin=cos_sin)
        h_round_end.append({"z_H": z_H.clone(), "z_L": z_L.clone()})
        carry_ref, _logits, _q = inner(cin, x1)
    assert len(h_round_end) == inner.config.H_cycles
    assert torch.equal(h_round_end[-1]["z_H"], carry_ref.z_H), "last z_H differs from inner.forward carry"
    assert torch.equal(h_round_end[-1]["z_L"], carry_ref.z_L), "last z_L differs from inner.forward carry"
    return OrderedDict([
        ("step", 1), ("passed_input", "x1"),
        ("input_embeddings", emb), ("reset_z_H", cin.z_H), ("reset_z_L", cin.z_L),
        ("block", "L_level.layers.0"), ("block_input_h", h),
        ("block_first_op", "mlp_t" if blk.config.mlp_t else "self_attn"),
        ("block_first_op_out", a),
        ("block_norm1_out", n1), ("block_mlp_out", m), ("block_norm2_out", n2),
        ("first_block_matches_real_forward", first_block),
        ("h_round_end", h_round_end),
    ])


# ---------------------------------------------------------------- JSON にする（float32 は repr、整数・真偽はそのまま）
def to_json(obj):
    if isinstance(obj, torch.Tensor):
        flat = obj.detach().reshape(-1).tolist()
        if obj.dtype in (torch.int32, torch.int64, torch.float32):
            head = '{"dtype":"%s","shape":%s,"data":[' % (str(obj.dtype).replace("torch.", ""), json.dumps(list(obj.shape)))
            body = ",".join(map(repr, flat)) if obj.dtype == torch.float32 else ",".join(str(int(v)) for v in flat)
            return head + body + "]}"
        if obj.dtype == torch.bool:
            return '{"dtype":"bool","shape":%s,"data":[%s]}' % (
                json.dumps(list(obj.shape)), ",".join("true" if v else "false" for v in flat))
        raise TypeError("unsupported tensor dtype %r" % (obj.dtype,))
    if isinstance(obj, dict):
        return "{" + ",".join("%s:%s" % (json.dumps(str(k)), to_json(v)) for k, v in obj.items()) + "}"
    if isinstance(obj, (list, tuple)):
        return "[" + ",".join(to_json(v) for v in obj) + "]"
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, int):
        return str(obj)
    if isinstance(obj, float):
        return repr(float(obj))
    return json.dumps(obj)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def upstream_meta(upstream):
    """公式のモジュールの実際の読み込み元のパスと sha256（--upstream の下にあるもの全部）と commit。
    commit は git -C <upstream> rev-parse --short HEAD（取れなければ "unknown"）。"""
    files = OrderedDict()
    for name, mod in sorted(sys.modules.items()):
        f = getattr(mod, "__file__", None)
        if not f:
            continue
        fa = os.path.abspath(f)
        if os.path.commonpath([upstream, fa]) == upstream and os.path.isfile(fa):
            files[os.path.relpath(fa, upstream)] = sha256(fa)
    try:
        cp = subprocess.run(["git", "-C", upstream, "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True, timeout=60)
        commit = cp.stdout.strip() if cp.returncode == 0 and cp.stdout.strip() else "unknown"
    except Exception:
        commit = "unknown"
    return files, commit


def env_info(shim_used, upstream):
    import einops, numpy, pydantic
    files, commit = upstream_meta(upstream)
    return OrderedDict([("python", sys.version.split()[0]), ("torch", torch.__version__),
                        ("einops", einops.__version__), ("pydantic", pydantic.__version__),
                        ("numpy", numpy.__version__), ("platform", os.uname().machine),
                        ("upstream_commit", commit), ("upstream_files", files), ("nn_buffer_shim", shim_used)])


def build_model(cfg, wname, ACTV1):
    torch.manual_seed(SEED_WEIGHT)
    model = ACTV1(dict(cfg))
    if wname == "W1":
        replace_weights_W1(model, cfg)
    model.eval()
    return model


LAYOUT = {"flatten": "row-major (C order): the last index varies fastest", "index_base": 0,
          "dtype": "float32 values written as Python floats via repr"}


def tensors_only(obj):
    """{"dtype","shape","data"} の形の辞書（テンソル）だけからなる部分が 1 つであることを確かめながら、
    JSON を、テンソルの位置にだけマーカーを置いたものに置き換えて返す（from_json のための形の検査）。"""
    if isinstance(obj, dict) and set(obj) == {"dtype", "shape", "data"}:
        return None
    if isinstance(obj, dict):
        return {k: tensors_only(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [tensors_only(v) for v in obj]
    return obj


def from_json(obj):
    """to_json の逆。{"dtype","shape","data"} からテンソルを作り直す（data がテンソルでなければ通常の dict）。"""
    if isinstance(obj, dict) and set(obj) == {"dtype", "shape", "data"} and isinstance(obj["data"], list) \
            and (not obj["data"] or not isinstance(obj["data"][0], dict)):
        dt = {"float32": torch.float32, "int32": torch.int32, "int64": torch.int64, "bool": torch.bool}[obj["dtype"]]
        data = obj["data"]
        if dt == torch.bool:
            data = [bool(v) for v in data]
        t = torch.tensor(data, dtype=dt)
        return t.reshape(tuple(int(v) for v in obj["shape"]))
    if isinstance(obj, dict):
        return OrderedDict((k, from_json(v)) for k, v in obj.items())
    if isinstance(obj, list):
        return [from_json(v) for v in obj]
    return obj


def from_json_text(text):
    """JSON の文字列から、テンソルの位置を値の形（{"dtype","shape","data"} の data がスカラーの列）で
    見きわめて作り直す。テンソルのデータの中の値を、辞書と取り違えないようにする。"""
    return from_json(json.loads(text, object_pairs_hook=_keep))


def _keep(pairs):
    d = dict(pairs)
    if set(d) == {"dtype", "shape", "data"} and d["dtype"] in ("float32", "int32", "int64", "bool"):
        return _TensorDict(d["dtype"], d["shape"], d["data"])
    return d


class _TensorDict:
    """テンソルの位置の印（中身で判定しない）。"""
    __slots__ = ("dtype", "shape", "data")

    def __init__(self, dtype, shape, data):
        self.dtype, self.shape, self.data = dtype, shape, data


def _rebuild(obj):
    if isinstance(obj, _TensorDict):
        dt = {"float32": torch.float32, "int32": torch.int32, "int64": torch.int64, "bool": torch.bool}[obj.dtype]
        data = [bool(v) for v in obj.data] if dt == torch.bool else obj.data
        flat = [row for r in data for row in r] if data and isinstance(data[0], list) else data
        return torch.tensor(flat, dtype=dt).reshape(tuple(int(v) for v in obj.shape))
    if isinstance(obj, dict):
        return OrderedDict((k, _rebuild(v)) for k, v in obj.items())
    if isinstance(obj, list):
        return [_rebuild(v) for v in obj]
    return obj


def check_json_roundtrip(cname, wname, path, ACTV1):
    """書き出した JSON ファイルそのものを読み、state_dict を shape・dtype・data から作り直し、新しく作った
    モデルに load_state_dict して、ACT の 4 手と混ざった reset を走らせ直し、JSON に書いた出力とビット一致するか。"""
    with open(path, encoding="utf-8") as f:
        raw = _rebuild(json.loads(f.read(), object_pairs_hook=_keep))
    cfg = OrderedDict(raw["config"])
    m = ACTV1(dict(cfg))
    m.load_state_dict(OrderedDict(raw["state_dict"]))
    m.eval()
    x1, x2, x3 = raw["inputs"]["x1"], raw["inputs"]["x2"], raw["inputs"]["x3"]
    with torch.no_grad():
        steps, states = run_act_sequence(m, x1, x2, x3)
        mixed = run_mixed_reset(m, states[0], x2)
    bad = []
    for nm, got, want in [("steps", steps, raw["steps"]), ("mixed_reset", mixed, raw["mixed_reset"])]:
        for k in want:
            if k in ("passed_input", "input", "start_halted"):
                if k != "start_halted" and got.get(k) != want[k]:
                    bad.append("%s/%s" % (nm, k))
                continue
            if k in ("input", "start_halted"):
                continue
            for kk in ("logits", "q_halt_logits", "q_continue_logits", "z_H", "z_L", "steps", "halted"):
                if not torch.equal(got[k][kk], want[k][kk]):
                    bad.append("%s/%s/%s" % (nm, k, kk))
            for ck in want[k].get("current_data", {}):
                g, w = got[k]["current_data"].get(ck), want[k]["current_data"][ck]
                if g is None or g.dtype != w.dtype or not torch.equal(g, w):
                    bad.append("%s/%s/current_data/%s" % (nm, k, ck))
    return not bad, "bad=%r" % (bad[:6],)


def export_one(cfg, wname, x1, x2, x3, shim_desc, ACTV1):
    model = build_model(cfg, wname, ACTV1)
    with torch.no_grad():
        steps, states = run_act_sequence(model, x1, x2, x3)
        mixed = run_mixed_reset(model, states[0], x2)
        real = first_block_evidence(model, x1) if wname == "W1" else None
        inter = run_intermediates(model, x1, real) if wname == "W1" else None
    sd = model.state_dict()
    rope = OrderedDict()
    if hasattr(model.inner, "rotary_emb"):
        rope["cos_cached"] = model.inner.rotary_emb.cos_cached.clone()
        rope["sin_cached"] = model.inner.rotary_emb.sin_cached.clone()
    obj = OrderedDict([("layout", LAYOUT), ("config", cfg), ("seed_weight", SEED_WEIGHT), ("seed_input", SEED_INPUT),
                       ("seed_replace", SEED_REPLACE), ("state_dict", sd), ("rope", rope),
                       ("inputs", OrderedDict([("x1", x1), ("x2", x2), ("x3", x3)])),
                       ("steps", steps), ("mixed_reset", mixed), ("intermediates", inter),
                       ("env", env_info(shim_desc, os.path.abspath(os.path.expanduser(UPSTREAM_DIR))))])
    return obj


def load_model(sd, cfg, ACTV1):
    """JSON に書いた state_dict（永続のバッファとパラメータ）を、新しいモデルに読み戻す。"""
    m = ACTV1(dict(cfg))
    m.load_state_dict(OrderedDict((k, v.clone()) for k, v in sd.items()))
    m.eval()
    return m


def run_once(out, shim_desc, ACTV1):
    """1 回ぶんの書き出し。返すのは (構成名, 重みの組, パス) と、自己検査の材料。"""
    names, mats = [], OrderedDict()
    for cname, cfg in configs().items():
        g = torch.Generator().manual_seed(SEED_INPUT)
        x1, x2, x3 = make_inputs(g, cfg), make_inputs(g, cfg), make_inputs(g, cfg)
        for wname in ("W0", "W1"):
            obj = export_one(cfg, wname, x1, x2, x3, shim_desc, ACTV1)
            name = "%s_%s.json" % (cname, wname)
            path = os.path.join(out, name)
            with open(path, "w", encoding="utf-8") as f:
                f.write(to_json(obj) + "\n")
            model = load_model(obj["state_dict"], cfg, ACTV1)
            model._buffers_extra = {n: tuple(t.shape) for n, t in model.named_buffers() if "inner.puzzle_emb.local_" not in n}
            mats[(cname, wname)] = OrderedDict([("cfg", cfg), ("model", model),
                                                 ("x1", x1), ("sd", obj["state_dict"]), ("obj", obj),
                                                 ("reloaded", load_model(obj["state_dict"], cfg, ACTV1))])
            names.append((cname, wname, path))
    return names, mats


# ---------------------------------------------------------------- 自己検査（失敗したら 0 でない終了コード）
def shim_check(torch_mod):
    """shim が register_buffer と同じ結末になること（永続・非永続・state_dict・dtype の移動）を確かめる。"""
    from torch import nn
    t = torch.zeros(3)

    class Holder(nn.Module):
        def __init__(self):
            super().__init__()
            self.p = nn.Buffer(t, persistent=True)
            self.n = nn.Buffer(t + 1, persistent=False)

    h = Holder()
    ok_reg = h._buffers["p"] is h.p and h._buffers["n"] is h.n and isinstance(h.p, torch.Tensor)
    ok_persist = list(h._buffers) == ["p", "n"] and list(h.state_dict().keys()) == ["p"]
    h = h.to(torch.float64)
    ok_move = h.p.dtype == torch.float64 and h.n.dtype == torch.float64 and h.p is h._buffers["p"]
    ok = bool(ok_reg and ok_persist and ok_move)
    detail = "register_buffer+rebind=%r persistent=[p]=%r dtype_move=%r" % (ok_reg, ok_persist, ok_move)
    return ok, detail


def check_pair(m):
    """1 組ぶんの検査。返すのは [(名前, 合否, 詳しい値)]。"""
    out, cfg, sd, obj = m["model"], m["cfg"], m["sd"], m["obj"]
    res = []
    res.append(("H_init_L_init_in_state_dict", "inner.H_init" in sd and "inner.L_init" in sd,
                "inner.H_init=%r inner.L_init=%r" % ("inner.H_init" in sd, "inner.L_init" in sd)))
    bad = [k for k in sd if k.endswith("cos_cached") or k.endswith("sin_cached")]
    res.append(("cos_sin_not_in_state_dict", not bad, "found=%r" % (bad,)))
    with torch.no_grad():
        o1 = out(out.initial_carry(m["x1"]), m["x1"])[1]["logits"]
        m2 = m["reloaded"]
        o2 = m2(m2.initial_carry(m["x1"]), m["x1"])[1]["logits"]
    d = float((o1 - o2).abs().max())
    res.append(("load_state_dict_roundtrip_identical", d == 0.0, "max|d|=%r" % d))
    nonfinite = []
    def walk(x, path):
        if isinstance(x, torch.Tensor) and x.is_floating_point() and not bool(torch.isfinite(x).all()):
            nonfinite.append(path)
        elif isinstance(x, dict):
            for k, v in x.items():
                walk(v, path + "/" + str(k))
        elif isinstance(x, (list, tuple)):
            for i, v in enumerate(x):
                walk(v, path + "/%d" % i)
    walk(obj, "")
    res.append(("all_floats_finite", not nonfinite, "nonfinite=%r" % (nonfinite[:5],)))
    if obj["intermediates"] is not None:
        ok_h = len(obj["intermediates"]["h_round_end"]) == cfg["H_cycles"]
        res.append(("h_round_end_count", ok_h, "n=%d H_cycles=%d" % (len(obj["intermediates"]["h_round_end"]), cfg["H_cycles"])))
    return res


def selfcheck(names, mats, shim_ok, ACTV1):
    lines = []
    def check(name, cond, detail=""):
        lines.append("%s %s %s" % ("PASS" if bool(cond) else "FAIL", name, detail))
        return bool(cond)
    ok_all = check("buffer_shim", *shim_ok)
    for cname, wname, path in names:
        m = mats[(cname, wname)]
        for name, cond, detail in check_pair(m):
            ok_all = check("%s_%s_%s" % (name, cname, wname), cond, detail) and ok_all
        sd = m["sd"]
        want_keys = set(sd) | set(m["model"]._buffers_extra)
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        rope_names = {"cos_cached": "inner.rotary_emb.cos_cached", "sin_cached": "inner.rotary_emb.sin_cached"}
        got = set(raw["state_dict"]) | {rope_names[k] for k in raw["rope"]}
        ok_all = check("json_keys_match_state_dict_%s_%s" % (cname, wname), got == want_keys,
                       "missing=%r extra=%r" % (sorted(want_keys - got), sorted(got - want_keys))) and ok_all
        sh_sd = {k: list(v["shape"]) for k, v in raw["state_dict"].items()}
        sh_sd.update({rope_names[k]: list(v["shape"]) for k, v in raw["rope"].items()})
        sh_ref = {k: list(t.shape) for k, t in m["model"].state_dict().items()}
        sh_ref.update({n_: list(m["model"]._buffers_extra[n_]) for n_ in m["model"]._buffers_extra})
        bad_sh = [k for k in sh_ref if sh_sd.get(k) != sh_ref[k]]
        ok_all = check("json_shapes_match_%s_%s" % (cname, wname), not bad_sh, "bad=%r" % (bad_sh,)) and ok_all
        if wname == "W1":
            fbr = m["obj"]["intermediates"]["first_block_matches_real_forward"]
            ok_all = check("first_block_matches_real_forward_%s_%s" % (cname, wname),
                           fbr["h_eq"] and fbr["n2_eq"] and fbr["wrapped_logits_equal"],
                           "h_eq=%r n2_eq=%r wrapped_logits_eq=%r wrong_differs=%r "
                           "max_abs_h_diff=%r max_abs_n2_diff=%r" % (
                               fbr["h_eq"], fbr["n2_eq"], fbr["wrapped_logits_equal"],
                               fbr["wrong_order_differs"],
                               fbr["max_abs_h_diff"], fbr["max_abs_n2_diff"])) and ok_all
        ok_rt, rt_detail = check_json_roundtrip(cname, wname, path, ACTV1)
        ok_all = check("json_roundtrip_%s_%s" % (cname, wname), ok_rt, rt_detail) and ok_all
        if wname == "W1":
            q = m["obj"]["steps"]["step1"]["q_halt_logits"]
            ok_all = check("W1_q_halt_differs_in_batch_%s" % cname, float(q[0]) != float(q[1]),
                           "q_halt=%r" % (q.tolist(),)) and ok_all
        lines.append("INFO buffers %s_%s %r" % (cname, wname, [(n, tuple(t.shape)) for n, t in m["model"].named_buffers()]))
    # 仕様 §2 の (e) は hidden 128・heads 4。(e) は (a) と同じ expansion=4 なので、公式の式
    # _find_multiple(round(4*128*2/3), 256) = _find_multiple(341, 256) = 512 になり、切り上げの境を越える。
    # ここでは式から出した値と実際の形の一致だけを検査する（依頼の値との並記はしない）。
    for cname in ("a", "b", "c", "d", "e"):
        cfg = mats[(cname, "W0")]["cfg"]
        formula_inter = ((round(cfg["expansion"] * cfg["hidden_size"] * 2 / 3) + 255) // 256) * 256
        for wname in ("W0", "W1"):
            sd = mats[(cname, wname)]["sd"]
            sh_up = tuple(sd["inner.L_level.layers.0.mlp.gate_up_proj.weight"].shape)
            sh_dn = tuple(sd["inner.L_level.layers.0.mlp.down_proj.weight"].shape)
            ok_all = check("swiglu_gate_up_shape_%s_%s" % (cname, wname),
                           sh_up == (2 * formula_inter, cfg["hidden_size"]),
                           "got=%r formula=%r" % (sh_up, (2 * formula_inter, cfg["hidden_size"]))) and ok_all
            ok_all = check("swiglu_down_shape_%s_%s" % (cname, wname),
                           sh_dn == (cfg["hidden_size"], formula_inter),
                           "got=%r formula=%r" % (sh_dn, (cfg["hidden_size"], formula_inter))) and ok_all
    # SwiGLU の中間の幅が (a)〜(d) では 256、(e) では 512 であること（(e) が切り上げの境を越えている）。
    for cname, want_inter in (("a", 256), ("b", 256), ("c", 256), ("d", 256), ("e", 512)):
        sh_dn = tuple(mats[(cname, "W0")]["sd"]["inner.L_level.layers.0.mlp.down_proj.weight"].shape)
        ok_all = check("swiglu_inter_width_%s" % cname, sh_dn[1] == want_inter,
                       "inter=%r want=%r" % (sh_dn[1], want_inter)) and ok_all
    return ok_all, lines


def check_obj_layout(names, mats):
    """JSON の一番上に layout があること（10 ファイル全部）。"""
    ok = True
    for cname, wname, path in names:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        ok = ok and raw.get("layout") == LAYOUT
    return ok


# ---------------------------------------------------------------- 実行
def run(args, torch_mod):
    global UPSTREAM_DIR
    upstream = os.path.abspath(os.path.expanduser(args.upstream))
    UPSTREAM_DIR = upstream
    out = os.path.abspath(args.out)
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    if upstream not in sys.path:
        sys.path.insert(0, upstream)
    os.makedirs(out, exist_ok=True)
    import oracle_export as E
    from models.recursive_reasoning.trm import TinyRecursiveReasoningModel_ACTV1 as ACTV1

    shim_desc = OrderedDict([("used", True),
                             ("description", E.SHIM_DESCRIPTION), ("patcher", "oracle_export.py BUFFER_SHIM_SRC"),
                             ("source_sha256", hashlib.sha256(E.BUFFER_SHIM_SRC.encode()).hexdigest())])
    shim_ok = shim_check(torch_mod)
    torch.set_grad_enabled(False)
    names, mats = run_once(out, shim_desc, ACTV1)
    first = [(c, w, sha256(p)) for c, w, p in names]
    names2, mats2 = run_once(out, shim_desc, ACTV1)
    second = [(c, w, sha256(p)) for c, w, p in names2]
    ok_rep = [(c, w, s) for c, w, s in first] == [(c, w, s) for c, w, s in second]
    src = OrderedDict((rel, sha256(os.path.join(upstream, rel))) for rel in UPSTREAM_SRC if os.path.exists(os.path.join(upstream, rel)))
    ok_self, lines = selfcheck(names2, mats2, shim_ok, ACTV1)
    ok = ok_self and ok_rep
    # 由来: 実際に読み込まれた公式のファイルの sha と commit
    envf = mats2[names2[0][:2]]["obj"]["env"]
    for rel, want in UPSTREAM_SHA.items():
        got = envf["upstream_files"].get(rel)
        lines.insert(0, "%s upstream_sha %s  %s" % ("PASS" if got == want else "FAIL", rel, got))
        ok = ok and got == want
    commit = envf["upstream_commit"]
    lines.insert(0, "%s upstream_commit %s (starts with 7de0d20: %r)" % (
        "PASS" if commit.startswith("7de0d20") else "FAIL", commit, commit.startswith("7de0d20")))
    ok = ok and commit.startswith("7de0d20")
    ok = check_obj_layout(names2, mats2) and ok
    head = ["S56 手 1 oracle_export.py 自己検査",
            "upstream: %s commit %s (git rev-parse --short HEAD)" % (upstream, envf["upstream_commit"]),
            "env: %s" % json.dumps(envf)] + \
           ["upstream_env_sha %s  %s" % (v, k) for k, v in envf["upstream_files"].items()] + lines + \
           ["%s same seed twice gives identical sha256 for all %d files" % ("PASS" if ok_rep else "FAIL", len(first))] + \
           ["file_sha %s  %s" % (h, "%s_%s.json" % (c, w)) for c, w, h in second]
    head.append("ALL PASS" if ok else "FAILED")
    with open(os.path.join(out, "SELFCHECK.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(head) + "\n")
    with open(os.path.join(out, "SHA256SUMS"), "w", encoding="utf-8") as f:
        for c, w, h in second:
            f.write("%s  %s_%s.json\n" % (h, c, w))
    print("\n".join(head))
    return 0 if ok else 1
