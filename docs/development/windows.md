# Windows Development Setup

## Goal

Document reproducible local setup and diagnostics for Windows contributors.

先用最短路径跑通：`docs/development/windows-quickstart.md`

## Toolchain (to confirm)

- Flutter: `3.41.0`
- Rust: `1.93.0`
- FRB codegen: `2.11.1`

## Quick Check

- `scripts/doctor.ps1`
- `scripts/format.ps1 -Check`

## 常用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/format.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen_bindings.ps1
scripts\run_windows_smoke.bat
```

## FRB (PR-A) Quick Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen_bindings.ps1

cd crates
cargo test -p lazynote_ffi

cd ..\apps\lazynote_flutter
flutter pub get
flutter analyze
```

## PR-B Quick Commands

```powershell
cd crates
cargo build -p lazynote_ffi --release

cd ..\apps\lazynote_flutter
flutter test
flutter run -d windows
```

Expected output for PR-A:

- Rust tests pass for `lazynote_ffi`.
- Flutter analyze passes.
- FRB generated files are updated in:
  - `crates/lazynote_ffi/src/frb_generated.rs`
  - `apps/lazynote_flutter/lib/core/bindings/`
  - `apps/lazynote_flutter/lib/core/bindings/api.dart`
  - `apps/lazynote_flutter/windows/runner/generated_frb.h`

## Notes

Windows 构建/运行：必须在 Windows 本机执行

Docker：仅用于 Rust 工具链/CI（可选）

- FRB codegen command name may be either:
  - `frb_codegen`
  - `flutter_rust_bridge_codegen`
- `scripts/gen_bindings.ps1` will auto-detect either command.
- 默认配置在仓库根目录 `.flutter_rust_bridge.yaml`，脚本优先使用该配置。
- Flutter 启动时会优先探测 workspace 动态库路径：
  - `../../crates/target/release/`
  - `../../crates/lazynote_ffi/target/release/` (backward compatible)
- 本地运行时文件统一落到 `%APPDATA%\\LazyLife\\`：
  - logs: `%APPDATA%\\LazyLife\\logs\\`
  - settings: `%APPDATA%\\LazyLife\\settings.json`
  - entry db: `%APPDATA%\\LazyLife\\data\\lazynote_entry.sqlite3`

## Troubleshooting (Known)

- `Open Log Folder` on Windows:
  - `explorer.exe` may return non-zero even when folder opens successfully.
  - Current implementation treats `stderr` output or a missing target directory as failure.
  - For compatibility, non-zero without `stderr` is still accepted as success.

- Console warning:
  - `[ERROR:flutter/lib/ui/window/platform_configuration.cc] Reported frame time is older than the last one; clamping`
  - Usually appears during resize/drag/rapid repaint.
  - This is a Flutter Windows engine timing warning and is typically non-fatal.
