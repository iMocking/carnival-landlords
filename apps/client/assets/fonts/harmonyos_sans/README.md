# HarmonyOS Sans

项目主字体：`HarmonyOS_Sans_SC.ttf`（HarmonyOS Sans 简体中文，Regular），由
`res://assets/themes/harmony_os_theme.tres` 设为全局 `default_font`。

- 来源：Huawei Device Co., Ltd. 发布的 HarmonyOS Sans 字体包
- 版权：Copyright 2021 Huawei Device Co., Ltd.
- 许可：HarmonyOS Sans Fonts License Agreement，全文见同目录 `LICENSE.txt`
  - 允许随软件复制、合并、嵌入、捆绑、再分发，不得单独售卖/再分发字体本身，不得修改字体文件；
  - 必须在软件中显著声明使用了 HarmonyOS Sans Fonts（见仓库根目录 README「字体」一节）。

替换字体时：把新字体放到本目录，更新 `harmony_os_theme.tres` 的
`ext_resource` 路径与 `default_font`，然后执行：

```bash
godot --headless --path . --import
```