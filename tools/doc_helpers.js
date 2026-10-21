const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, ImageRun, PageBreak, LevelFormat, Footer, PageNumber,
  TableOfContents,
} = require('docx');

const FONT = 'Arial';
const AZUL = '000000';
const W = 9360; // ancho útil (A4 con márgenes de 1")

const p = (text, opts = {}) => new Paragraph({
  spacing: { after: 120, line: 276 }, alignment: opts.align || AlignmentType.JUSTIFIED,
  children: (Array.isArray(text) ? text : [text]).map(t => typeof t === 'string' ? new TextRun({ text: t, font: FONT, size: 21 }) : t),
  ...opts.para,
});
const b = (t) => new TextRun({ text: t, bold: true, font: FONT, size: 21 });
const i = (t) => new TextRun({ text: t, italics: true, font: FONT, size: 21 });
const code = (t) => new TextRun({ text: t, font: 'Consolas', size: 19 });
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 360, after: 160 }, children: [new TextRun({ text: t, font: FONT })] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 240, after: 120 }, children: [new TextRun({ text: t, font: FONT })] });
const bullet = (parts) => new Paragraph({ numbering: { reference: 'vinetas', level: 0 }, spacing: { after: 80 },
  children: (Array.isArray(parts) ? parts : [parts]).map(t => typeof t === 'string' ? new TextRun({ text: t, font: FONT, size: 21 }) : t) });
const codeBlock = (lines) => lines.map((l, k) => new Paragraph({
  shading: { type: ShadingType.CLEAR, fill: 'F2F2F2', color: 'auto' }, spacing: { after: k === lines.length - 1 ? 160 : 0 },
  indent: { left: 200 }, children: [code(l || ' ')] }));

const border = { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF' };
const borders = { top: border, bottom: border, left: border, right: border };
function table(headers, rows, widths) {
  return new Table({ width: { size: W, type: WidthType.DXA }, columnWidths: widths,
    rows: [new TableRow({ tableHeader: true, children: headers.map((h, k) => cell(h, true, widths[k])) }),
           ...rows.map(r => new TableRow({ children: r.map((c, k) => cell(c, false, widths[k])) }))] });
}
function cell(txt, head, w) {
  return new TableCell({
    borders, width: { size: w, type: WidthType.DXA },
    shading: head ? { type: ShadingType.CLEAR, fill: AZUL, color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 90, right: 90 },
    children: String(txt).split('\n').map(line => new Paragraph({ children: [new TextRun({ text: line, font: FONT, size: 18, bold: head, color: head ? 'FFFFFF' : '000000' })] })),
  });
}
const caption = (t) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 80, after: 200 },
  children: [new TextRun({ text: t, italics: true, font: FONT, size: 18, color: '555555' })] });

module.exports = { fs, Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, PageBreak, LevelFormat, Footer, PageNumber, FONT, AZUL, p, b, i, code, h1, h2, bullet, codeBlock, table, caption };
