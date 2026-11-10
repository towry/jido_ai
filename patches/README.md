# Jido AI Patch Set

此目录仅存部署所需、相对 `main` 施加之私有补丁。

`deploy` 是孤儿分支：不含 jido_ai 源码。同步上游时只快进 `main` ，再在这份 series 上 rebase 补丁，避免把私有改动和上游提交揉在一起产生大量 conflict。

## Files

* `series` : patch 施行顺序
* `0001-publish-as-jido_ai_twpatch.patch` : 以 `jido_ai_twpatch` 名称发布到 hex（mix.exs package name 改写）
* `0002-ignore-twpatch-build-artifacts.patch` : 忽略 twpatch 构建产物
* `0003-release-version.patch` : `@version` 单一真相源（patch 后 `mix.exs` 的 `@version`，如 `2.4.0-1`）
* `0004-react-after-tool-round-synchronous-join-hook.patch` : 可选的 `after_tool_round` 同步 join hook（ReAct runner）

## Rules

* 勿纳仅供本地 agent 使用之文档、提示或工作流说明
* 每枚 patch 只做一事，便于冲突定位与回滚
* 未写入 `series` 的 `.patch` 文件不会被施加

## Regenerate

在源码树完成改动后，可用 `tools/patches add "describe"` / `tools/patches rebuild <n>` 重生补丁，
并更新 `series` 。CI (`check-patches.yml`) 与发布 (`publish-hex.yml`) 都以 `scripts/apply.sh` 施加。

## 自动构建与发布

推送到 `deploy` 且修改 `patches/`、`scripts/` 或 `publish-hex.yml` 时，`Publish Hex` 会自动校验补丁、
构建并公开发布 hex 包。也可以手动运行同一个 workflow，不需要填写版本号：

```shell
gh workflow run publish-hex.yml --repo towry/jido_ai --ref deploy
```

每次运行固定源码 (`origin/main`) 和补丁 (`deploy`) 两个 commit。Release tag 为 `v<patched @version>`，
对应 `0003-release-version.patch` 的版本（如 `v2.4.0-1`），tag 指向 deploy commit。

发布前验证 tag 等于 patched `@version`。同版本重跑会核对已有产物，完全一致则不做改动；
不一致则失败，绝不覆盖（hex 本身也禁止覆盖已发布版本）。补丁冲突、测试失败或构建失败不会发布新版本。

同步 `main` 本身不会触发这条 `deploy` workflow；同步后可执行上面的手动命令。
此流程只发布 hex 安装包，不会更新 dots 或重启服务器。
