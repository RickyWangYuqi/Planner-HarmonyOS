// 运行实际响应式策略和列表命中方法，覆盖断点、分屏宽度与双栏拖动几何。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript', path.join(path.dirname(fileURLToPath(import.meta.url)), '../../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try { ts = require(candidate); break; } catch {}
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
const responsive = readFileSync(new URL('../entry/src/main/ets/theme/ResponsiveLayout.ets', import.meta.url), 'utf8');
const module = { exports: {} };
vm.runInNewContext(ts.transpileModule(responsive, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { module, exports: module.exports });
const { ResponsiveLayout: layout } = module.exports;
let count = 0;
const assert = (value, message) => { if (!value) throw new Error(message); count++; };
assert(!layout.wide(390), '手机沿用上下布局');
assert(!layout.wide(599), '小分屏不出现挤压的两列');
assert(!layout.wide(839), '中窗口保留单列');
assert(layout.wide(840), '宽屏断点进入双栏');
assert(layout.wide(1244), '实机平板横屏采用双栏');
assert(layout.sheetWidth(390, true) === '100%', '手机表单维持全宽');
assert(layout.sheetWidth(600, true) === 536, '中窗口表单四周留出边距');
assert(layout.sheetWidth(1244, true) === 920, '平板编辑器有足够两栏空间');
assert(layout.sheetWidth(1244, false) === 600, '日历和教程不过度加宽');
assert(layout.sheetWidth(1920, true) === 920, '更大窗口编辑面板不继续拉长');
assert(layout.contentWidth(1920) === 1280, '大屏主页限制阅读宽度');
assert(layout.contentWidth(800) === 720, '中屏单列有最大宽度');
assert(!layout.editorColumns(600), '窄弹层不分栏');
assert(layout.editorColumns(920), '宽弹层启用内容与日期分栏');
const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const methods = ['futureDragBottom', 'dragBounds', 'insideDragList'].map(name => source.match(new RegExp('^  private ' + name + '\\([^]*?\\n  \\}', 'm'))[0]).join('\n');
const boundsClass = source.match(/^class DragBounds[^]*?\n\}/m)[0];
const sandbox = { module: { exports: {} } };
vm.runInNewContext(ts.transpileModule(`${boundsClass}\nclass Probe { ${methods} }\nmodule.exports=Probe;`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText, sandbox);
const probe = new sandbox.module.exports();
probe.wideLayout = true;
probe.getUIContext = () => ({ px2vp: n => n / 2.25, getFrameNodeById: id => {
 const x = id === 'list-today' ? 24 : 650;
 return { getPositionToWindow: () => ({ x, y: 160 }), getMeasuredSize: () => ({ width: 540 * 2.25, height: 500 * 2.25 }) };
} });
assert(probe.futureDragBottom(660) === 660, '双栏已有底部安全距，不重复扣除浮栏高度');
assert(probe.dragBounds('today').height === 500 && probe.dragBounds('future').height === 500, '同高两栏完整命中区域');
assert(probe.insideDragList('today', 100, 300), '左栏正确命中当日');
assert(!probe.insideDragList('future', 100, 300), '相同纵坐标不误命中未来');
assert(probe.insideDragList('future', 900, 300), '右栏正确命中未来');
assert(!probe.insideDragList('today', 900, 300), '右栏不借用左栏落点');
assert(!probe.insideDragList('future', 900, 700), '列表下方不作为有效落点');
assert(!probe.insideDragList('today', 600, 300) && !probe.insideDragList('future', 600, 300), '栏间留白允许自然取消');
const calendarSource = readFileSync(new URL('../entry/src/main/ets/components/CalendarPicker.ets', import.meta.url), 'utf8');
const engine = readFileSync(new URL('../entry/src/main/ets/model/PlanerEngine.ets', import.meta.url), 'utf8');
const fromKey = engine.match(/^export function fromKey[^]*?\n\}/m)[0].replace('export ', '');
const rowsMethod = calendarSource.match(/^  private visibleRows[^]*?\n  \}/m)[0];
vm.runInNewContext(ts.transpileModule(`${fromKey}\nclass CalendarProbe { rows=[0,1,2,3,4,5]; compact=true; ${rowsMethod} }\nmodule.exports=CalendarProbe;`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText, sandbox);
const calendar = new sandbox.module.exports();
assert(calendar.visibleRows('2021-02').length === 4, '完整四周月份不绘制空周');
assert(calendar.visibleRows('2026-10').length === 5, '实测月份保留五周与截止日');
assert(calendar.visibleRows('2026-08').length === 6, '六周月份末日不可被裁掉');
calendar.compact = false;
assert(calendar.visibleRows('2026-10').length === 6, '手机日历高度保持原规则');
console.log(`Tablet layout regression: ${count} assertions passed.`);
