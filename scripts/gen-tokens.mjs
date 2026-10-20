import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const tokens = JSON.parse(await readFile(resolve(root, 'design/tokens.json'), 'utf8'));
const cssPath = resolve(root, 'app/globals.css');
const dartPath = resolve(root, 'mobile/lib/core/theme/tokens.g.dart');

const cssNames = {
  background: 'background',
  surface: 'surface',
  text: 'foreground',
  'text-2': 'text-2',
  hairline: 'hairline',
  work: 'work',
  sidegig: 'sidegig',
  social: 'social',
  shopping: 'shopping',
  danger: 'danger',
};

const cssColor = (value) => value;
const colorChannels = (hex) => [1, 3, 5].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16));
const cssShadowColor = ({ color, opacity }) => {
  const [red, green, blue] = colorChannels(color);
  return `rgba(${red}, ${green}, ${blue}, ${opacity})`;
};
const cssBlock = (mode) => {
  const lines = [
    `  /* Generated from design/tokens.json (${mode}). */`,
  ];
  if (mode === 'light') lines.push(`  --font-sans: ${tokens.type.fontFamily};`);
  for (const [token, cssName] of Object.entries(cssNames)) {
    lines.push(`  --${cssName}: ${cssColor(tokens.colors[mode][token])};`);
  }
  for (const name of ['card', 'sheet', 'float']) {
    const shadow = tokens.shadows[name][mode];
    const spread = shadow.spread ? ` ${shadow.spread}px` : '';
    lines.push(`  --shadow-${name}-value: ${shadow.x || 0} ${shadow.y}px ${shadow.blur}px${spread} ${cssShadowColor(shadow)};`);
  }
  lines.push(`  --scrim: ${tokens.colors.scrim[mode]};`);
  lines.push(`  --row-radius: ${tokens.radii.row}px;`);
  lines.push(`  --sheet-radius: ${tokens.radii.sheet}px;`);
  lines.push(`  --pill-radius: ${tokens.radii.pill}px;`);
  lines.push(`  --spacing-unit: ${tokens.spacing.unit}px;`);
  lines.push(`  --screen-gutter: ${tokens.spacing.screenGutter}px;`);
  lines.push(`  --row-min-height: ${tokens.dimensions.rowMinHeight}px;`);
  lines.push(`  --touch-target-min: ${tokens.dimensions.touchTargetMin}px;`);
  lines.push(`  --motion-sheet: ${tokens.motion.durationsMs.sheet}ms;`);
  lines.push(`  --motion-row-pop: ${tokens.motion.durationsMs.rowPop}ms;`);
  lines.push(`  --motion-row-collapse: ${tokens.motion.durationsMs.rowCollapse}ms;`);
  lines.push(`  --motion-context-crossfade: ${tokens.motion.durationsMs.contextCrossfade}ms;`);
  lines.push(`  --sheet-curve: cubic-bezier(${tokens.motion.sheetCurve.join(', ')});`);
  lines.push(`  --row-pop-scale-start: ${tokens.motion.rowPopScale[0]};`);
  lines.push(`  --row-pop-scale-peak: ${tokens.motion.rowPopScale[1]};`);
  lines.push(`  --row-pop-scale-end: ${tokens.motion.rowPopScale[2]};`);
  lines.push(`  --scrim-opacity: ${tokens.motion.scrimOpacity};`);
  for (const [key, value] of Object.entries(tokens.type.scale)) {
    const name = key.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`);
    lines.push(`  --type-${name}-size: ${value.size}px;`);
    lines.push(`  --type-${name}-weight: ${value.weight};`);
    if (value.letterSpacing !== undefined) lines.push(`  --type-${name}-letter-spacing: ${value.letterSpacing}px;`);
  }
  return lines.join('\n');
};

const replaceBlock = (source, selector, contents) => {
  const expression = new RegExp(`(${selector}\\s*\\{)([\\s\\S]*?)(\\n\\})`);
  const match = source.match(expression);
  if (!match) throw new Error(`Could not find CSS block for ${selector}`);
  const start = '  /* BEGIN GENERATED DESIGN TOKENS — scripts/gen-tokens.mjs */';
  const end = '  /* END GENERATED DESIGN TOKENS */';
  const startIndex = match[2].indexOf(start);
  const endIndex = match[2].indexOf(end, startIndex + start.length);
  if (startIndex < 0 || endIndex < 0) throw new Error(`Generated token markers missing in ${selector}`);
  const block = `${start}\n${contents}\n${end}`;
  const replacedInner = `${match[2].slice(0, startIndex)}${block}${match[2].slice(endIndex + end.length)}`;
  return source.replace(expression, `${match[1]}${replacedInner}${match[3]}`);
};

const hexToDartColor = (hex) => `Color(0xFF${hex.slice(1)})`;
const dartId = (value) => value.replace(/-([a-z0-9])/g, (_, character) => character.toUpperCase());
const dartUpperId = (value) => {
  const identifier = dartId(value);
  return identifier[0].toUpperCase() + identifier.slice(1);
};
const dartShadow = (name, mode) => {
  const shadow = tokens.shadows[name][mode];
  const [red, green, blue] = colorChannels(shadow.color);
  return `BoxShadow(offset: Offset(${shadow.x}, ${shadow.y}), blurRadius: ${shadow.blur}, spreadRadius: ${shadow.spread}, color: Color.fromRGBO(${red}, ${green}, ${blue}, ${shadow.opacity}))`;
};

const dartLines = [
  '// GENERATED CODE - DO NOT MODIFY BY HAND.',
  '// Source: design/tokens.json; generator: scripts/gen-tokens.mjs.',
  "import 'dart:ui' show Color, FontWeight, Offset;",
  "import 'package:flutter/animation.dart' show Cubic;",
  "import 'package:flutter/painting.dart' show BoxShadow;",
  '',
  'abstract final class EzyDesignTokens {',
];
for (const mode of ['light', 'dark']) {
  dartLines.push(`  // ${dartId(mode)} palette`);
  for (const [key, value] of Object.entries(tokens.colors[mode])) {
    dartLines.push(`  static const Color ${mode}${dartUpperId(key)} = ${hexToDartColor(value)};`);
  }
  dartLines.push(`  static const Color ${mode}Scrim = Color.fromRGBO(0, 0, 0, ${tokens.motion.scrimOpacity});`);
  for (const name of ['card', 'sheet', 'float']) dartLines.push(`  static const BoxShadow ${mode}${dartUpperId(name)}Shadow = ${dartShadow(name, mode)};`);
}
dartLines.push(
  '',
  '  // Uses Flutter’s platform system font; no SF Pro font is bundled.',
  '  static const String? systemFontFamily = null;',
  `  static const double spacingUnit = ${tokens.spacing.unit};`,
  `  static const double screenGutter = ${tokens.spacing.screenGutter};`,
  `  static const double rowMinHeight = ${tokens.dimensions.rowMinHeight};`,
  `  static const double touchTargetMin = ${tokens.dimensions.touchTargetMin};`,
  `  static const double rowRadius = ${tokens.radii.row};`,
  `  static const double sheetRadius = ${tokens.radii.sheet};`,
  `  static const double pillRadius = ${tokens.radii.pill};`,
  `  static const Duration sheetDuration = Duration(milliseconds: ${tokens.motion.durationsMs.sheet});`,
  `  static const Duration rowPopDuration = Duration(milliseconds: ${tokens.motion.durationsMs.rowPop});`,
  `  static const Duration rowCollapseDuration = Duration(milliseconds: ${tokens.motion.durationsMs.rowCollapse});`,
  `  static const Duration contextCrossfadeDuration = Duration(milliseconds: ${tokens.motion.durationsMs.contextCrossfade});`,
  `  static const Cubic sheetCurve = Cubic(${tokens.motion.sheetCurve.join(', ')});`,
  `  static const double rowPopScaleStart = ${tokens.motion.rowPopScale[0]};`,
  `  static const double rowPopScalePeak = ${tokens.motion.rowPopScale[1]};`,
  `  static const double rowPopScaleEnd = ${tokens.motion.rowPopScale[2]};`,
  `  static const double scrimOpacity = ${tokens.motion.scrimOpacity};`,
);
for (const [key, value] of Object.entries(tokens.type.scale)) {
  const name = dartId(key);
  dartLines.push(`  static const double ${name}FontSize = ${value.size};`);
  dartLines.push(`  static const FontWeight ${name}FontWeight = FontWeight.w${value.weight};`);
  if (value.letterSpacing !== undefined) dartLines.push(`  static const double ${name}LetterSpacing = ${value.letterSpacing};`);
}
dartLines.push('}', '');

let css = await readFile(cssPath, 'utf8');
css = replaceBlock(css, ':root', cssBlock('light'));
css = replaceBlock(css, '\\.dark', cssBlock('dark'));
await writeFile(cssPath, css);
await mkdir(dirname(dartPath), { recursive: true });
await writeFile(dartPath, dartLines.join('\n'));
console.log('Generated app/globals.css and mobile/lib/core/theme/tokens.g.dart from design/tokens.json');
