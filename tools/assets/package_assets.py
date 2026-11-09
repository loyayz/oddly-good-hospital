"""Publish only final runtime resources, editable art and portable previews."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from catalog import write_json
from deduplicate_delivery import compact_package


def copy_file(source: Path,target: Path):
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)


def main():
    p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True);p.add_argument("--destination",type=Path,required=True)
    a=p.parse_args();root=a.root.resolve();destination=a.destination.resolve()
    audit=json.loads((root/"art-source/production/validation/asset-audit.json").read_text(encoding="utf-8"))
    if audit["status"]!="passed":raise ValueError("Cannot publish an unvalidated asset library")
    if destination.exists() and any(destination.iterdir()):raise ValueError("Delivery directory already contains files")
    destination.mkdir(parents=True,exist_ok=True)
    for folder in ("accessories","animations","appearances","architecture","audio","cases","effects","materials","presentation","props","rigs","runtime","surgery","ui","upgrades"):
        shutil.copytree(root/"assets"/folder,destination/"assets"/folder,
            ignore=shutil.ignore_patterns("__pycache__","*.blend1","*.tmp"))
    for source in (root/"assets/models").iterdir():
        if source.name.startswith("core_") or source.name in ("complete-production.json","equipment-states.json"):
            if source.is_file():copy_file(source,destination/"assets/models"/source.name)
    for name in ("HospitalUI-Regular.otf","HospitalUI-Medium.otf","HospitalUI-Regular.tres",
                 "HospitalUI-Medium.tres","NotoSansCJKsc-Regular.otf","NotoSansCJKsc-Medium.otf","OFL.txt","subset-index.json"):
        copy_file(root/"assets/fonts"/name,destination/"assets/fonts"/name)
        imported=root/"assets/fonts"/(name+".import")
        if imported.exists():copy_file(imported,destination/"assets/fonts"/imported.name)
    copy_file(root/"assets/asset-plan.json",destination/"assets/asset-plan.json")
    shutil.copytree(root/"art-source/production",destination/"art-source/production",
                    ignore=shutil.ignore_patterns("*.blend1","*.pyc","__pycache__","*.tmp"))
    (destination/"art-source/.gdignore").write_text("",encoding="utf-8")
    for source in (root/"content/core").glob("*.json"):
        copy_file(source,destination/"content/core"/source.name)
    copy_file(root/"content/core/locale/zh_CN.csv",destination/"content/core/locale/zh_CN.csv")
    (destination/"content/core/locale/.gdignore").write_text("",encoding="utf-8")
    (destination/".gitignore").write_text("/.godot/\n*.blend1\n",encoding="utf-8")
    for name in ("asset_factory.gd","asset_browser.gd","asset_browser.tscn","sound_bank.gd"):
        copy_file(root/"tools/assets"/name,destination/"tools/assets"/name)
        uid=root/"tools/assets"/(name+".uid")
        if uid.exists():copy_file(uid,destination/"tools/assets"/uid.name)
    copy_file(root/".cache/asset-preview-project/project.godot",destination/"project.godot")
    copy_file(root/"LICENSE",destination/"LICENSE")
    native=json.loads((root/".cache/asset-previews/godot-renderer.json").read_text(encoding="utf-8"))
    native.pop("image",None)
    write_json(destination/"art-source/production/validation/actual-backend.json",native)
    usage=r'''# 怪好的医院：完整目录开发素材

运行资源位于 `assets`，可编辑的 Blender 源工程、PCM 音频和矢量稿位于 `art-source/production`。
`content/core` 保存生成时的内容快照与来源哈希，不替换游戏工程的业务定义。

## 浏览

使用 Godot 4.7.2 打开本目录的 `project.godot`，完成导入后运行。Windows 也可执行：

```powershell
pwsh -File .\Preview.ps1
```

预览器支持按名称或内容 ID 搜索、选择四套外观和七种岗位、检查设备升级、拖动动画进度、切换低动态，以及播放音效和音乐。预览工程使用独立的用户目录，不读取医院存档。

## 接入

补充图形和卡片的位置由 assets/ui/supplement-index.json 提供；居民职业配件、地面叠层与原生生活用品分别位于 accessories/professions、ui/overlays 和 props/library。各组件的事实、范围、资格和照片由调用方绑定。

* 角色、设备、病例、手术承托和建筑使用 GLB；坐标单位为米，Godot Y 向上。身体、固定家具和门的尺寸来源保留在清单中。
* 角色通过语义骨骼挂载配件。四套外观共享主体；微观群落始终是一名演员。椅子主体固定，门和护理床保留分段部件。
* 动画库使用 Godot 原生 AnimationLibrary。阶段与规范化进度由游戏当前事实提供；动画没有医疗结算、资源领取或声音回调。
* `safe_finish` 只收回工具，待结果、失败与暂停保留症状；仅明确的康复阶段显示恢复结构。读档直接定位当前阶段与进度。
* 设备状态以 `assets/models/equipment-states.json` 为准。只有数值表维护集合中的设备提供故障、维修和保养表现。升级调用参数使用实际已完成等级。
* `assets/runtime` 提供顶点色共享材质和仓库既有的 Compatibility 蒙皮适配。GLB 的 `.import` 文件是资源契约的一部分，应一起保留。
* 音频按 `assets/audio/index.json` 的内容 ID 使用；483 项播放定义共享 405 份 Ogg 及对应 WAV 源文件。`sound_bank.gd` 使用设施 6、角色 6、UI 2、音乐 2 个共享播放位；静音停止播放与解码，不补播过时的一次性声音。
* 完全相同的图标、矢量稿与音频只保留一份文件，内容 ID 保持独立。文件位置以各索引为准，`assets/asset-plan.json` 的 `file_aliases` 记录合并路径；资源总清单只保留该文件。

## 预算与验证

角色近景最多 2332、常用最多 1488、远景最多 488 三角面；普通家具最多 784 三角面；角色骨骼最多 33 根。运行 UI 图片最长边不超过 384 像素，529 项图形定义共享 474 张 PNG，最大 40903 字节；两个字重的内容子集共用各自的完整 CJK 回退字库。

验证记录位于 `art-source/production/validation`：1297 个模型、750 个场景、320 套外观装配、560 个岗位装配及 5368 项病例显隐检查通过。实际 Intel Arc/OpenGL Compatibility 画面也已检查。全院 640 人负载、所有门路与真实临床交接仍属于游戏集成验收，不能由素材检查替代。

这些资源面向游戏开发与后续美术精修。GLB 和原生场景可直接导入；整批资源尚未接入实验中的主游戏。

项目原创模型、矢量与合成音频沿用项目 LICENSE。字体使用 `assets/fonts/OFL.txt`；音频没有对白、TTS、拟语或外部录音采样。
'''
    (destination/"使用说明.md").write_text(usage,encoding="utf-8",newline="\n")
    launcher='''#requires -Version 7.0
param([string]$Godot = 'C:\\programs\\godot\\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Godot)) {
    $assetGodotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $assetGodotCommand) { throw '请用 Godot 4.7.2 打开本目录的 project.godot，或通过 -Godot 指定程序路径。' }
    $Godot = $assetGodotCommand.Source
}
& $Godot --headless --editor --import --path $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw '素材导入未完成，请检查 Godot 导入日志。' }
& $Godot --path $PSScriptRoot
'''
    (destination/"Preview.ps1").write_text(launcher,encoding="utf-8",newline="\n")
    compact_package(destination,apply=True)
    manifest=[]
    for path in sorted(destination.rglob("*")):
        if path.is_file():
            raw=path.read_bytes();manifest.append({"path":path.relative_to(destination).as_posix(),"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()})
    write_json(destination/"asset-package.json",{"schema":1,"counts":audit["counts"],"file_count":len(manifest),
        "total_bytes":sum(f["bytes"] for f in manifest),"source_commit":"43be3ca41d950e6fde4597edb3b746cdaa826610",
        "code_branch":"codex/complete-game-assets-20261108","runtime":"Godot 4.7.2 Compatibility",
        "validation":"art-source/production/validation/asset-audit.json","files":manifest})
    print(json.dumps({"destination":str(destination),"files":len(manifest),"bytes":sum(f["bytes"] for f in manifest)},ensure_ascii=False))


if __name__=="__main__":main()
