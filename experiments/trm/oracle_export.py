#!/usr/bin/env python3
"""S56 手 1: 公式 TRM（~/trm_test/TinyRecursiveModels, commit 7de0d20, MIT）を PyTorch 2.2.2 / CPU で走らせ、
「正解」の数値を JSON に書き出す（仕様 discussion/specs/S56-trm-port.md §2・§2.1）。

使い方: python oracle_export.py --upstream ~/trm_test/TinyRecursiveModels --out experiments/trm/fixtures
公式のファイルは書き換えない。PyTorch 2.2.2 にない torch.nn.Buffer は、import の前にここで shim として与える。
本体は同じディレクトリの oracle_work.py（このスクリプトは shim・引数・実行の口だけを持つ）。
"""
import sys

sys.dont_write_bytecode = True  # 公式のディレクトリにもラボにも __pycache__ を作らない

# ---------------------------------------------------------------- nn.Buffer の代わり（公式の import より前）
# Buffer(data, persistent=..) は入れ物 _BufferValue を返す。shim した Module.__setattr__ がそれを見たら
# register_buffer(name, data, persistent=persistent) を呼び、名前を self._buffers[name] に結ぶ
# （register_buffer はattribute の代わりに _buffers に置き、dtype の移動・state_dict をふつうに扱う）。ただの代入ではない。
SHIM_DESCRIPTION = (
    "torch.nn.Buffer shim: Buffer(data, persistent=..) returns a _BufferValue holder; patched "
    "nn.Module.__setattr__ sees it, calls nn.Module.register_buffer(name, data, persistent=persistent) "
    "and rebinds the name to self._buffers[name]. Not a plain tensor assignment."
)

BUFFER_SHIM_SRC = r'''
class _BufferValue:
    __slots__ = ("tensor", "persistent")

    def __init__(self, tensor, persistent):
        self.tensor = tensor
        self.persistent = persistent


def Buffer(data, *, persistent=True):  # noqa: N802
    if not isinstance(data, torch.Tensor):
        raise TypeError("Buffer shim: data must be a Tensor")
    return _BufferValue(data, persistent)


_orig_setattr = torch.nn.Module.__setattr__


def _setattr_with_buffer(self, name, value):
    if isinstance(value, _BufferValue):
        torch.nn.Module.register_buffer(self, name, value.tensor, persistent=value.persistent)
        return _orig_setattr(self, name, self._buffers[name])
    return _orig_setattr(self, name, value)


_setattr_with_buffer._oracle_orig_setattr = _orig_setattr
torch.nn.Module.__setattr__ = _setattr_with_buffer
torch.nn.Buffer = Buffer
'''


def install_buffer_shim(torch):
    exec(compile(BUFFER_SHIM_SRC, "<nn.Buffer shim>", "exec"), {"torch": torch})


def uninstall_buffer_shim():
    import torch
    orig = torch.nn.Module.__setattr__._oracle_orig_setattr
    torch.nn.Module.__setattr__ = orig
    if hasattr(torch.nn, "Buffer"):
        del torch.nn.Buffer


def parse_args(argv):
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--upstream", required=True)
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    import torch
    install_buffer_shim(torch)
    import oracle_work as W
    return W.run(args, torch)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
