# Windows Quickstart (新克隆用户)

目标：在刚克隆仓库后，最少命令跑起 Windows 应用并看到 Rust 链路成功。

## 4 条命令

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1 -SkipFlutterDoctor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen_bindings.ps1
cd apps/lazynote_flutter; flutter pub get
flutter run -d windows
```

## 预期输出

应用窗口启动后，页面应显示：

- `Rust bridge connected`
- `ping: pong`
- `coreVersion: 0.1.0`

如果看到 `Failed to load dynamic library`，先关闭应用后执行：

```powershell
cd crates
cargo build -p lazynote_ffi --release
```

然后回到 `apps/lazynote_flutter` 再次执行 `flutter run -d windows`。
