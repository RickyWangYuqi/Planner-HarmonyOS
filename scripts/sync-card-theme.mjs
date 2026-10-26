// 将实际色板和渐变规则同步为卡片可直接解析的深浅色资源；不修改其它颜色。
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript',
  path.join(root, '../Planer/node_modules/typescript')].filter(Boolean)) {
  try { ts = require(candidate); break; } catch { /* 复用现有工具链，不下载。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(root, 'entry/src/main/ets/theme', name + '.ets');
  const output = ts.transpileModule(readFileSync(filename, 'utf8'), {
    fileName: filename, compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename })(
    request => load(path.basename(request)), module, module.exports);
  modules.set(name, module.exports); return module.exports;
}
const { paletteFor } = load('Theme');
const { cardGradient, cardSecondaryColor } = load('CardAppearance');
for (const [directory, dark] of [['base', false], ['dark', true]]) {
  const filename = path.join(root, 'entry/src/main/resources', directory, 'element/color.json');
  const source = JSON.parse(readFileSync(filename, 'utf8'));
  const colors = source.color.filter(item => !/^card_.*_gradient_(start|middle|end)$/.test(item.name));
  for (const preset of ['seasalt', 'forest', 'sunset', 'ink']) {
    const palette = paletteFor(preset, dark);
    const gradient = cardGradient(palette, dark);
    const secondary = colors.find(item => item.name === `card_${preset}_soft`);
    if (secondary) secondary.value = cardSecondaryColor(palette, dark);
    for (const stop of ['start', 'middle', 'end']) colors.push({ name: `card_${preset}_gradient_${stop}`, value: gradient[stop] });
  }
  // 沿用当前一行一个颜色的格式，减少无关改动。
  source.color = colors;
  writeFileSync(filename, '{\n  "color": [\n' + colors.map(item => '    ' + JSON.stringify(item).replaceAll(':', ': ').replaceAll(',', ', ')).join(',\n') + '\n  ]\n}\n');
}
console.log('已同步四套主题的深浅色卡片渐变资源。');
