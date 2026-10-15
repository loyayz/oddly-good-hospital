param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$docsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputPath) { $OutputPath = Join-Path $docsRoot 'product-design.html' }
$generatedJson = & python -B -X utf8 (Join-Path $PSScriptRoot 'content-atlas.py')
if ($LASTEXITCODE -ne 0) { throw 'Content atlas generation failed; the existing book was not changed.' }
$generated = ($generatedJson -join [Environment]::NewLine) | ConvertFrom-Json
$catalog = [IO.File]::ReadAllText((Join-Path $docsRoot 'data/content-catalog.json')) | ConvertFrom-Json
$designVersion = [Net.WebUtility]::HtmlEncode($catalog.content_version)
$bookSourcePath = Join-Path $docsRoot 'product-design.html'
$chapters = @(
    @{ File='design/01-simulation.md'; Id='simulation'; Title='模拟与经营规则' },
    @{ File='design/07-clinical-team.md'; Id='clinical-team'; Title='医生、手术与住院' },
    @{ File='design/08-hospital-life.md'; Id='hospital-life'; Title='医院日常与居民回馈' },
    @{ File='design/09-consultation-wellbeing.md'; Id='wellbeing'; Title='诊室互动与员工休闲' },
    @{ File='design/10-community-comedy.md'; Id='comedy'; Title='熟客记忆与社区活动' },
    @{ File='design/11-growth-arrivals-recruitment.md'; Id='growth'; Title='随机来客、多层与招聘' },
    @{ File='design/02-content.md'; Id='content'; Title='内容与后续扩展' },
    @{ File='design/03-experience.md'; Id='experience'; Title='界面与操作' },
    @{ File='design/04-technical.md'; Id='technical'; Title='技术与保存' },
    @{ File='design/16-navigation-space-selection.md'; Id='navigation-selection'; Title='导航与空间选型' },
    @{ File='design/05-production.md'; Id='production'; Title='美术与声音制作' },
    @{ File='design/06-validation.md'; Id='validation'; Title='验收标准' },
    @{ File='design/12-implementation-plan.md'; Id='implementation'; Title='实施路线与阶段交付' },
    @{ File='specs/26-10/2026-10-14-stage01-technical-feasibility.md'; Id='stage01-spec'; Title='第一阶段实施规格' },
    @{ File='design/13-stage01-feasibility.md'; Id='stage01-feasibility'; Title='第一阶段可行性实测' },
    @{ File='specs/26-10/2026-10-14-stage02-stage03-simulation-kernel.md'; Id='stage02-stage03-spec'; Title='第二、第三阶段实施规格' },
    @{ File='design/14-stage02-benchmark.md'; Id='stage02-benchmark'; Title='第二阶段基准工具' },
    @{ File='design/15-stage03-kernel-performance.md'; Id='stage03-performance'; Title='第三阶段内核实测' },
    @{ File='specs/26-10/2026-10-15-stage04-stage24.md'; Id='stage04-stage24-spec'; Title='第04至24阶段实施规格' },
    @{ File='specs/26-10/2026-10-15-stage25-stage28.md'; Id='stage25-stage28-spec'; Title='第25至28阶段实施规格' },
    @{ File='reports/2026-10-15-stage04-stage24.md'; Id='stage04-stage24-delivery'; Title='第04至28阶段交付记录' },
    @{ Generated='atlas'; Id='atlas'; Title='完整内容索引' },
    @{ Generated='report'; Id='report'; Title='设计数据与验收状态' }
)
$chapterByPath = @{}
foreach ($chapter in $chapters) {
    if ($chapter.Generated) { continue }
    $chapter.Path = [IO.Path]::GetFullPath((Join-Path $docsRoot $chapter.File))
    $chapterByPath[$chapter.Path] = $chapter.Id
}
$sections = [Collections.Generic.List[string]]::new()
$sourceDigestText = [Text.StringBuilder]::new()
foreach ($chapter in $chapters) {
    if ($chapter.Generated) {
        $markdown = $generated.($chapter.Generated)
        $sourceDir = $docsRoot
    } else {
        $markdown = [IO.File]::ReadAllText($chapter.Path, [Text.Encoding]::UTF8)
        $sourceDir = [IO.Path]::GetDirectoryName($chapter.Path)
    }
    [void]$sourceDigestText.Append($markdown)
    $body = (ConvertFrom-Markdown -InputObject $markdown).Html
    $body = [regex]::Replace($body, '\bid="([^"]+)"', {
        param($match)
        return 'id="' + $chapter.Id + '--' + $match.Groups[1].Value + '"'
    })
    $body = [regex]::Replace($body, 'href="([^"]+)"', {
        param($match)
        $href = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        if ($href -match '^[a-zA-Z]+:') { return $match.Value }
        if ($href.StartsWith('#')) { return 'href="#' + $chapter.Id + '--' + $href.Substring(1) + '"' }
        $linkPath = $href.Split('#')[0]
        $resolved = [IO.Path]::GetFullPath((Join-Path $sourceDir $linkPath))
        if ($resolved -eq $bookSourcePath) {
            $fragment = if ($href.Contains('#')) { $href.Substring($href.IndexOf('#') + 1) } else { 'simulation' }
            return 'href="#' + $fragment + '"'
        }
        if ($chapterByPath.ContainsKey($resolved)) {
            return 'href="#' + $chapterByPath[$resolved] + '"'
        }
        if ($resolved -eq (Join-Path $docsRoot 'assets/hospital-concept.png')) {
            return 'href="#scene-concept-image"'
        }
        if ([IO.Path]::GetExtension($resolved) -eq '.json' -and [IO.File]::Exists($resolved)) {
            $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolved))
            $filename = [Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($resolved))
            return 'href="data:application/json;base64,' + $encoded + '" download="' + $filename + '"'
        }
        return $match.Value
    })
    $body = [regex]::Replace($body, 'src="([^"]+)"', {
        param($match)
        $src = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        if ($src -match '^[a-zA-Z]+:') { return $match.Value }
        $resolved = [IO.Path]::GetFullPath((Join-Path $sourceDir $src))
        $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolved))
        return 'id="scene-concept-image" src="data:image/png;base64,' + $encoded + '"'
    })
    $body = $body.Replace('<table>', '<div class="table-wrap"><table>').Replace('</table>', '</table></div>')
    $sections.Add('<section class="chapter" id="' + $chapter.Id + '">' + $body + '</section>')
}
$digestBytes = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($sourceDigestText.ToString()))
$digest = [Convert]::ToHexString($digestBytes).ToLowerInvariant()
$toc = ($chapters | ForEach-Object { '<li><a href="#' + $_.Id + '">' + $_.Title + '</a></li>' }) -join [Environment]::NewLine
$sectionHtml = $sections -join [Environment]::NewLine
$document = @"
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="design-source-sha256" content="$digest">
<title>怪好的医院 · Oddly Good Hospital · 产品设计方案</title>
<style>
:root{color-scheme:light;--ink:#293d60;--muted:#53657f;--blue:#3b5f92;--paper:#fffdf7;--line:#d6deeb}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:24px}
body{margin:0;background:#eceff4;color:var(--ink);font:17px/1.85 "Microsoft YaHei","Segoe UI",sans-serif}
a{color:#365988;text-underline-offset:3px}a:hover{color:#985135}
aside{position:fixed;inset:0 auto 0 0;width:224px;padding:30px 20px;background:#e6ebf5;overflow-y:auto;border-right:1px solid #cbd5e5}
.brand{font-size:24px;font-weight:700;letter-spacing:-.5px;margin:0 0 4px}
.edition{font-size:13px;color:var(--muted);margin:0 0 26px}
nav ol{padding-left:20px;margin:0}nav li{margin:10px 0;padding-left:2px}nav a{text-decoration:none;font-size:14px}
.note{font-size:12px;line-height:1.7;margin-top:30px;color:var(--muted)}
main{margin-left:224px;padding:30px clamp(24px,4vw,70px) 80px;max-width:1600px}
.book-title{font-size:16px;color:var(--muted);margin:4px 0 24px}
.chapter{background:var(--paper);padding:clamp(24px,4vw,54px);margin:0 0 32px;border:1px solid var(--line);border-radius:6px;overflow-wrap:anywhere}
h1{font-size:30px;line-height:1.4;margin:0 0 24px;color:#243a5c}
h2{font-size:24px;line-height:1.45;margin:44px 0 18px;border-top:1px solid var(--line);padding-top:26px;color:#325889}
h3{font-size:20px;margin:28px 0 12px}p{margin:12px 0 18px}
ul,ol{padding-left:26px}li{margin:7px 0}
img{display:block;max-width:100%;height:auto;border-radius:4px}
.table-wrap{overflow-x:auto;margin:18px 0 24px}
table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.75}
th{background:#e7edf7;color:#30496f;text-align:left;font-weight:700}
th,td{border:1px solid #ccd6e3;padding:10px 12px;vertical-align:top;min-width:78px}
tr:nth-child(even) td{background:#f5f7fb}
pre{white-space:pre;overflow:auto;background:#edf1f7;border:1px solid var(--line);padding:18px;font-size:13px;line-height:1.6}
code{font-family:Consolas,"Microsoft YaHei",monospace;font-size:.9em}
:not(pre)>code{background:#edf1f7;padding:2px 5px;border-radius:3px}
blockquote{border-left:3px solid #8f9fbc;margin:18px 0;padding:4px 18px;color:#496082}
input[type=checkbox]{accent-color:#3b5f92;pointer-events:none}
@media(max-width:1050px){aside{position:static;width:100%;padding:18px 24px;border-right:0;border-bottom:1px solid #cbd5e5}nav ol{display:flex;flex-wrap:wrap;gap:4px 24px;list-style:none;padding:0}nav li{margin:0}.edition{margin-bottom:12px}.note{margin-top:12px}main{margin-left:0;padding:20px}.chapter{padding:24px}h1{font-size:26px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
@media print{aside,.book-title{display:none}main{margin:0;padding:0;max-width:none}.chapter{border:0;padding:0;margin:0 0 30px;break-before:page}.chapter:first-child{break-before:auto}body{background:white;font-size:11pt}table{font-size:9pt}h1{font-size:22pt}h2{font-size:16pt}pre{white-space:pre-wrap}.table-wrap{overflow:visible}a{color:inherit}}
</style>
</head>
<body>
<aside><p class="brand">怪好的医院</p><p class="edition">Oddly Good Hospital<br>完整产品方案 · $designVersion</p><nav aria-label="文档目录"><ol>$toc</ol></nav><p class="note">全部章节与概念图已包含在本文件中。可离线阅读；源数据链接可另存为JSON。阶段报告保留历史技术与性能记录；阶段1至28的当前功能结论以需求专项及修复后复验为准，未测性能单独列出。</p></aside>
<main><p class="book-title">轻松经营一座属于人类与奇妙居民的医院</p>$sectionHtml</main>
</body></html>
"@
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $document, [Text.UTF8Encoding]::new($false))
Write-Output "BOOK_CHAPTERS=$($chapters.Count)"
Write-Output "BOOK_BYTES=$((Get-Item -LiteralPath $OutputPath).Length)"
Write-Output "SOURCE_SHA256=$digest"
