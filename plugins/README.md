# Only-U Cordis 插件

运维能力先写 `portable\` 脚本和 `.dsh/skills/only-u-ops`。

真正的 DSH **插件**（`dsh.bundle`）放这个目录，不要改 `dsh/` 内核。在开发机装进 profile 再烤盘：

```bat
cd dsh
pnpm dsh plugin --profile dsh-tui add ..\plugins\<包名>
powershell -File ..\scripts\bake-usb.ps1 -Dest F:\Only-U
```

规格见 `docs/adr/0005-usb-baked-dsh-runtime.md` 和 `dsh/docs/user/develop/basic/publish.zh.md`。
