#!/usr/bin/env python3
"""Build a small DLL with the patched LLVM C/C++ export headers before LLVM."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from validate_windows import MACHINES, inspect_pe


API = r'''
#include "llvm/Support/Compiler.h"
#include "llvm-c/Visibility.h"
extern "C" LLVM_C_ABI int LLVMInitializeProbe();
class LLVM_ABI SharedValue {
  int value;
public:
  SharedValue(int);
  int get() const;
  static int offset;
};
template<class T> class SharedBox {
  T value;
public:
  SharedBox(T);
  T get() const;
};
extern template class LLVM_TEMPLATE_ABI SharedBox<int>;
class LLVM_ABI SharedInterface {
public:
  virtual ~SharedInterface();
  virtual int get() const = 0;
};
LLVM_ABI SharedInterface *createSharedInterface();
'''
LIBRARY = r'''
#include "api.h"
extern "C" LLVM_C_ABI int LLVMInitializeProbe() { return 42; }
int SharedValue::offset = 2;
SharedValue::SharedValue(int v) : value(v + offset) {}
int SharedValue::get() const { return value; }
template<class T> SharedBox<T>::SharedBox(T v) : value(v) {}
template<class T> T SharedBox<T>::get() const { return value; }
template class LLVM_EXPORT_TEMPLATE SharedBox<int>;
SharedInterface::~SharedInterface() {}
class Implementation final : public SharedInterface {
public:
  int get() const override { return 42; }
};
SharedInterface *createSharedInterface() { return new Implementation; }
'''
MAIN = r'''
#include "api.h"
int main() {
  SharedInterface *p = createSharedInterface();
  int v = p->get();
  delete p;
  return LLVMInitializeProbe() == 42 && SharedValue(40).get() == 42 &&
         SharedValue::offset == 2 && SharedBox<int>(42).get() == 42 && v == 42
             ? 0 : 1;
}
'''


def build(source, target, output):
    compiler = shutil.which(target + "-clang++")
    if not compiler:
        raise ValueError(f"pinned MinGW compiler not found for {target}")
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    with tempfile.TemporaryDirectory(prefix="llvm-dll-abi-") as temporary:
        root = Path(temporary)
        config = root / "llvm/Config/llvm-config.h"
        config.parent.mkdir(parents=True)
        config.write_text("#define LLVM_ENABLE_LLVM_EXPORT_ANNOTATIONS 1\n"
                          "#define LLVM_ENABLE_LLVM_C_EXPORT_ANNOTATIONS 1\n"
                          "#define LLVM_BUILD_LLVM_DYLIB 1\n"
                          "#define LLVM_BUILD_LLVM_DYLIB_VIS 1\n")
        (root / "api.h").write_text(API)
        (root / "api.cpp").write_text(LIBRARY)
        (root / "main.cpp").write_text(MAIN)
        common = [compiler, "-Werror", "-fno-exceptions", "-fno-rtti",
                  "-static-libstdc++", "-I" + str(root), "-I" + str(source / "llvm/include")]
        dll = output / "libLLVMABIProbe.dll"
        implib = root / "libLLVMABIProbe.dll.a"
        subprocess.run([*common, "-DLLVM_EXPORTS", "-shared", str(root / "api.cpp"),
                        "-o", str(dll), "-Wl,--out-implib," + str(implib)], check=True)
        executable = output / "probe.exe"
        subprocess.run([*common, str(root / "main.cpp"), str(implib), "-o", str(executable)], check=True)
        machine, imports = inspect_pe(executable)
        if machine != MACHINES[target] or "libllvmabiprobe.dll" not in imports:
            raise ValueError(f"{target}: ABI probe did not import the expected DLL")
    print(f"Built C API, C++ class/static data, template and virtual factory/delete DLL probe for {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", choices=MACHINES)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source.resolve(), args.target, args.output)
