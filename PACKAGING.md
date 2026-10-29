# Windows archive packaging

Windows tool aliases must retain their executable names: LLVM uses the image
name to select modes such as `clang++`, `ld.lld`, and `llvm-ranlib`. Store
byte-identical executable aliases as tar hard links. Do not replace them with
launcher programs or symbolic links. Avoid repacking through formats or tools
that flatten hard links, including ordinary ZIP archives.

`scripts/deduplicate_windows_tools.py` checks contents before linking files.
`release.sh` then creates the final `.tar.xz` with system tar and multi-threaded
xz compression. Extract it with tar or 7-Zip preserving hard links. Native Windows CI
checks that extraction restores hard links before running the complete payload
validation. Every tool, target, runtime, and license remains in the archive.

For packaging-only releases, publish a new payload revision and keep the LLVM
source contract fixed. Existing release assets and their checksums must remain
unchanged. Consumers should update the payload version and SHA-256 together
after the new assets have passed validation and been published.

LLGo's LLVM 22 pins require a new **LLVM 22** payload revision. Backport this
packaging change to the LLVM 22 build contract; the current main-branch LLVM 23
payload is a separate compiler upgrade.
