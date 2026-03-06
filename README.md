# XLiPadBook
A PDF viewer and splitter tool for iPad — display and segment PDF documents with ease.

杂志类 App 有一个常见需求——用户长按某段正文，划出一段话，然后对这段话写评论。这个交互在微信读书、Kindle 里都很成熟，但它们针对的是结构化的电子书格式（ePub、MOBI），正文结构天然清晰。
PDF 没有这种结构。一份杂志 PDF 在底层只有一堆带坐标的"文字片段"（glyph run），没有段落、没有栏、没有语义层次。PDFKit 提供的 PDFSelection 和 selectionsByLine 能给你"行"，但它不知道哪些行属于同一个段落，也不知道这一页有几栏。
因此，段评的核心问题是：给定用户选中的一行文字，如何还原它所在的完整自然段？
这个问题比想象中复杂，主要难点有三个：

几何噪声：PDF 的行坐标存在浮点误差，标题、页码、图注混杂其中，必须过滤。
多栏布局：杂志常见双栏、三栏排版，阅读顺序不是简单地从上到下。
跨栏断段：一个自然段可能从左栏末尾延续到右栏开头，PDFKit 对此一无所知。

XLPDFParagraphEngine 的设计思路，就是用纯几何方法逐层解决这三个问题。

整体架构：四层流水线

PDFSelection
    │
    ▼
① buildLinesFromSelection     — 行提取 + 噪声过滤
    │
    ▼
② buildBlocksFromLinesIteratively  — 几何连通分块
    │
    ▼
③ readingOrderForBlock         — 列识别 + 段落切分
    │
    ▼
④ mergeSemanticContinuousBlocks — 跨栏语义合并
    │
    ▼
paragraphTextFromLines         — 拼接文本输出

