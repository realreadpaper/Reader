# 原生直接解析 MOBI/KF8 设计

## 背景

当前 `Reader` 已有一套轻量 MOBI 原生解析：

- `PalmDBReader` 能读取 PalmDB 容器 records。
- `MOBIHeader` 能识别部分 MOBI header、EXTH、text encoding、cover 记录。
- `MOBIDecompressor` 支持 `none` 和 `PalmDOC`，不支持 `HUFF/CDIC`。
- `MOBIParser.parseClassic` 会解压正文 record、按编码 fallback 得到 HTML，再按简单标签分页。
- `MOBIParser.parseKF8` 当前通过扫描 `PK\x03\x04` 尝试把 KF8 当作 EPUB 解析。
- 原生无法处理 `unsupportedFormat` 时，会通过 calibre `ebook-convert` 转 EPUB 兜底。

用户目标不是转换兜底，而是类似 Kindle for Mac 一样直接解析 `.mobi/.azw/.azw3` 容器。Kindle 不会先生成外部 EPUB 文件；它会直接解析 Kindle/Mobipocket 容器，把 KF7/KF8 内部正文、索引、CSS、图片和目录还原成可排版内容，再交给自身排版引擎。

本设计把项目方向调整为：**原生直接解析优先，不依赖 calibre；解析结果仍输出现有 `ParsedBook`，复用当前 WebKit 阅读渲染。**

## 目标

- 直接解析非 DRM 的 `.mobi`、`.azw`、`.azw3`。
- 支持 classic MOBI/KF7：
  - `none` compression
  - `PalmDOC` compression
  - `HUFF/CDIC` compression
  - record 尾部 extra data flags
  - 多字节字符跨 record overlap
  - 中文编码 UTF-8、GB18030、Big5，以及 CP1252 fallback
  - 图片资源映射和基础目录
- 支持 KF8/AZW3：
  - 识别 hybrid MOBI+KF8 boundary
  - rawML 提取
  - `FDST` flow 分段
  - skeleton index
  - fragment index
  - guide / NCX index
  - XHTML/CSS/图片资源还原
- 保留现有 `ParsedBook` 输出模型，减少 UI 和缓存层改动。
- 原生解析失败时给出明确错误原因；calibre 只作为可选手动兜底，不作为默认路径。

## 非目标

- 不支持 DRM 加密内容。检测到 DRM 时直接返回明确错误。
- 不支持 KFX。
- 不实现 Kindle 私有排版引擎，也不保证分页结果与 Kindle 完全一致。
- 不在解析过程中生成 EPUB 文件作为中间产物。
- 不把主题、字体、分页逻辑下沉进 MOBI parser；这些仍由现有 WebKit 渲染层处理。

## 总体架构

```
PalmDBReader
  -> MOBIContainerInspector
  -> CompressionDecoder
  -> TextRecordAssembler
  -> FormatBranch
       -> KF7Parser
       -> KF8Parser
  -> ResourceMapper
  -> ParsedBook
```

### 1. PalmDBReader

保留现有职责：读取 PalmDB header、record offset、record data、type、creator、name。该模块只负责容器，不理解 MOBI 语义。

### 2. MOBIContainerInspector

新增模块，集中解析 record0 和关键 records：

- PalmDOC header：compression、textLength、textRecordCount、recordSize、encryption。
- MOBI header：identifier、headerLength、mobiType、textEncoding、fileVersion、firstNonBookIndex、fullNameOffset、fullNameLength、locale、inputLanguage、outputLanguage。
- extra data flags。
- DRM 标志。
- EXTH：title、author、publisher、ASIN、cover offset、thumbnail offset、updated title。
- first image record。
- KF8 boundary。
- FDST、FLIS、FCIS、SRCS、RESC、INDX 等结构位置。

输出 `MOBIContainerInfo`，作为后续模块的唯一事实来源，避免多个 parser 重复猜 offset。

### 3. CompressionDecoder

替换当前 `MOBIDecompressor` 的单文件实现，拆为三个 decoder：

- `NoCompressionDecoder`
- `PalmDOCDecoder`
- `HUFFCDICDecoder`

`HUFF/CDIC` 是直接解析的必需项。遇到 HUFF 时不能再默认 fallback calibre。

### 4. TextRecordAssembler

直接解决乱码的关键模块。

职责：

- 对每个 text record 先解压。
- 根据 MOBI extra data flags 剥离 record 尾部非正文数据。
- 处理多字节字符跨 record 的 overlap。
- 按 `textLength` 截断正文，不把资源或索引 record 混入 raw text。
- 输出 clean rawML bytes。

该模块完成后，`decodeHTML` 的编码 fallback 才有可靠输入。否则即使尝试 GB18030/Big5，也可能因为尾部控制数据污染而局部乱码。

### 5. KF7Parser

classic MOBI/KF7 分支，输入 clean rawML bytes。

职责：

- 根据 header 声明编码和内容探测选择编码。
- 转为 HTML fragment。
- 解析 `<mbp:pagebreak>`、guide、NCX 或 MOBI index 中可用的目录信息。
- 保留原始段落、标题、内链和锚点。
- 把 `recindex:`、`filepos:`、内嵌图片引用映射给 `ResourceMapper`。
- 输出 `ParsedChapter` 和 `ParsedTOCEntry`。

### 6. KF8Parser

KF8/AZW3 分支，不能再扫描 `PK` 当 EPUB。

职责：

- 从容器中定位 KF8 rawML 起点。
- 读取 `FDST`，把 rawML 拆成多个 flow。
- 读取 skeleton index，得到 XHTML 文件框架。
- 读取 fragment index，得到可插入片段。
- 按 skeleton + fragment 关系重建 XHTML。
- 读取 guide / NCX / nav index，建立目录和章节顺序。
- 还原 CSS flow、字体、图片引用。
- 输出章节 HTML、TOC 和资源引用。

该实现路径与 KindleUnpack 的 KF8 处理思路一致，但输出目标是项目的 `ParsedBook`，不是 EPUB 文件。

### 7. ResourceMapper

统一处理 classic MOBI 和 KF8 的资源落盘与引用重写。

职责：

- 识别 image/font/css records。
- 根据 magic number 判断扩展名：jpg、png、gif、webp、svg、css、ttf、otf。
- 写入临时资源目录。
- 建立 MOBI record index / resource id 到文件名的映射。
- 重写 HTML/CSS 中的图片、字体、链接引用。
- 确保 `ParsedBook.resourceDirectory` 可被现有 WebKit renderer 使用。

## 错误处理

新增或细化错误类型：

- `drmProtected`：检测到 DRM，加密内容不支持。
- `unsupportedKFX`：KFX 不属于 MOBI/KF8 解析范围。
- `unsupportedCompression`：遇到未知 compression。
- `corruptedContainer`：PDB record offset、MOBI header、EXTH、FDST 或 index 越界。
- `kf8ReconstructionFailed`：KF8 skeleton/fragment/FDST 结构不完整。
- `resourceMappingFailed`：资源 record 存在但无法安全写入或引用重写。

默认行为：

- 原生失败时展示明确错误。
- 不自动调用 calibre。
- 可以保留一个显式用户选择：“使用 calibre 兜底转换”。该选项是降级策略，不是直接解析路径。

## 实施阶段

### Phase 1：容器诊断工具

新增内部诊断能力，给任意 `.mobi/.azw/.azw3` 输出：

- PalmDB record 数量和 record 大小范围。
- compression。
- MOBI version。
- text encoding。
- text record range。
- extra data flags。
- DRM 状态。
- first image record。
- EXTH metadata。
- 是否 hybrid MOBI+KF8。
- 是否存在 FDST、INDX、FLIS、FCIS、RESC。

验收：

- 不改变阅读行为。
- 可以用日志判断某本书乱码或格式乱的根因属于编码、尾数据、压缩、KF8 重建还是资源映射。

### Phase 2：可靠 classic MOBI/KF7

实现：

- extra data flags 剥离。
- 多字节 overlap。
- HUFF/CDIC。
- 更稳的编码选择。
- 图片资源映射。
- 基础 TOC/guide。

验收：

- 中文 classic MOBI 不乱码。
- 图片能显示。
- 章节标题不再只显示“第 N 页”。
- HUFF/CDIC 样本不依赖 calibre。

### Phase 3：真实 KF8/AZW3 重建

实现：

- FDST flow reader。
- skeleton index reader。
- fragment index reader。
- guide / NCX reader。
- XHTML/CSS 还原。
- KF8 图片、字体、CSS 资源映射。

验收：

- 非 DRM AZW3 能直接解析。
- 章节顺序正确。
- 目录可跳转。
- CSS 和图片基本保留。
- 不通过 `PK` 扫描假装 EPUB。

### Phase 4：兜底策略收敛

实现：

- 默认原生直接解析。
- 原生失败时提示具体原因。
- calibre fallback 只保留为用户显式选择或调试选项。
- README 和错误文案改为“原生优先，可选转换兜底”。

## 测试策略

### 单元测试

- `MOBIContainerInspectorTests`
  - header offsets
  - EXTH
  - DRM 标志
  - KF8 boundary
  - extra data flags
- `CompressionDecoderTests`
  - none
  - PalmDOC
  - HUFF/CDIC fixture
- `TextRecordAssemblerTests`
  - record 尾数据剥离
  - UTF-8 / GB18030 多字节跨 record overlap
  - textLength 截断
- `KF7ParserTests`
  - 中文解码
  - 图片引用重写
  - guide / pagebreak / basic TOC
- `KF8ParserTests`
  - FDST flow 拆分
  - skeleton + fragment 重建
  - NCX / guide TOC
  - CSS / image resource mapping

### Fixture 策略

每类 fixture 保持小文件，优先使用公开可再分发样本或本地构造样本：

- classic PalmDOC UTF-8。
- classic PalmDOC GB18030。
- classic HUFF/CDIC。
- classic 含图片。
- classic 含 extra data overlap。
- AZW3/KF8 单章节。
- AZW3/KF8 多章节 + CSS + 图片。
- DRM 样本只保存最小 header fixture，不保存受版权内容。

### 手动验收

- 打开中文 `.mobi` 不出现乱码。
- 打开 `.azw3` 不依赖 calibre。
- 图片和目录能显示。
- 原生不支持的文件给出明确原因。
- 旧 EPUB/PDF/TXT/Markdown 行为不变。

## 风险与取舍

- `HUFF/CDIC` 和 KF8 index 是最大技术风险，需要 fixture 驱动实现。
- 不实现 Kindle 排版引擎，所以分页不可能与 Kindle 完全一致。
- 直接解析会增加 parser 复杂度，必须保持模块边界清晰，避免 `MOBIParser.swift` 继续膨胀。
- calibre fallback 仍有价值，但只能作为用户显式兜底，不能掩盖原生解析缺口。

## 审核结论

项目要达到“像 Kindle 一样直接解析 MOBI/KF8”，不能继续依赖 `ebook-convert`，也不能把 KF8 简化为扫描 ZIP。正确路线是补齐 MOBI/KF8 解包链路：

1. 先诊断容器结构。
2. 再修 classic MOBI/KF7 的压缩、尾数据、中文编码和资源映射。
3. 最后实现 KF8 的 FDST、skeleton、fragment、guide/NCX 重建。

完成后，Reader 可以在不转换 EPUB 的前提下，把 MOBI/KF8 还原为 `ParsedBook`，并继续复用现有 WebKit 阅读器。
