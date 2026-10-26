// 卡片视图数据回归：在内存中转换并运行真实 CardData.ets，验证三种规格的信息量与配色取值。
// 不访问设备、桌面或用户数据；卡片渲染与材质表现需真机验收，不在本脚本范围。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
const candidates = [process.env.TYPESCRIPT_PATH, 'typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript',
  path.join(project, '../Planer/node_modules/typescript')];
let ts;
for (const candidate of candidates.filter(Boolean)) {
  try { ts = require(candidate); break; } catch { /* 使用已有工具链，不下载依赖。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');

const base = path.join(project, 'entry/src/main/ets');
const modules = new Map();
// 按相对路径解析，卡片数据同时依赖 model 与 theme 两个目录。
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const filename = path.join(base, relative + '.ets');
  const output = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    reportDiagnostics: true, fileName: filename
  });
  const errors = (output.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCurrentDirectory: () => project, getCanonicalFileName: file => file, getNewLine: () => '\n'
  }));
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output.outputText}\n})`, { filename })(
    (request) => load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), request))),
    module, module.exports);
  modules.set(relative, module.exports);
  return module.exports;
}

const { AppData, Task } = load('model/PlanerModel');
const { freshData, reduce, todayKey, addDays } = load('model/PlanerEngine');
const { CardSize, buildCardData, cardSizeForDimension, cardSizeForRect, visibleTaskCount } = load('services/CardData');

let passed = 0;
let failed = 0;
function assert(cond, msg) {
  if (cond) { passed++; console.log(`  ✓ ${msg}`); } else { failed++; console.error(`  ✗ ${msg}`); }
}

function task(text, completed, group, progress, dueDate) {
  const item = new Task();
  item.id = 'id-' + text;
  item.text = text;
  item.completed = completed;
  item.group = group || null;
  item.progress = progress === undefined ? null : progress;
  item.dueDate = dueDate || null;
  return item;
}

// 当日三条：一条已完成、一条带分组与进度、一条普通；另有两条未来日程。
function sampleData() {
  const data = freshData();
  data.currentDate = '2026-10-22';
  data.todayTasks = [
    task('写实验报告', false, '课程', 40),
    task('买牛奶', true, null, 100),
    task('整理周计划', false, null)
  ];
  data.futureTasks = [task('体检', false, null, null, '2026-11-02'), task('交材料', false, null, null, '2026-11-05')];
  data.groups = ['课程'];
  data.settings.showGroups = true;
  return data;
}

console.log('卡片规格映射');
assert(cardSizeForDimension('2*2') === CardSize.SMALL, '2*2 归为小卡');
assert(cardSizeForDimension('2*4') === CardSize.MEDIUM, '2*4 归为中卡');
assert(cardSizeForDimension('4*4') === CardSize.LARGE, '4*4 归为大卡');
assert(cardSizeForDimension('1*2') === CardSize.SMALL, '1*2 归为小卡');
assert(cardSizeForRect(144, 144) === CardSize.SMALL, '144×144 实际几何判为小卡');
assert(cardSizeForRect(320, 144) === CardSize.MEDIUM, '320×144 实际几何判为中卡');
assert(cardSizeForRect(320, 320) === CardSize.LARGE, '320×320 实际几何判为大卡');
assert(visibleTaskCount(CardSize.SMALL) === 3, '小卡三条');
assert(visibleTaskCount(CardSize.MEDIUM) === 4, '中卡四条');
assert(visibleTaskCount(CardSize.LARGE) === 8, '大卡八条');

console.log('三种规格的信息量递减');
const data = sampleData();
const small = buildCardData(data, CardSize.SMALL, false);
const medium = buildCardData(data, CardSize.MEDIUM, false);
const large = buildCardData(data, CardSize.LARGE, false);
assert(small.texts.length === 3, '小卡给三条日程');
assert(medium.texts.length === 3, '中卡在只有三条当日日程时不补空行');
assert(large.texts.length === 3, '大卡在只有三条当日日程时不补空行');
assert(small.doneText === '1 / 3', '完成比按当日任务统计');
assert(small.progress === 33, '进度取整为 33');
assert(small.dateText.indexOf('10月22日') === 0, '日期文案来自 currentDate');
assert(large.futureText === '未来 2 项', '大卡展示未来数量');
assert(small.texts[0] === '写实验报告', '按用户原顺序展示，不重排');
assert(small.marks[0] === '0', '未完成标记为 0');
assert(medium.metas[0] === '课程 · 40%', '中卡元信息含分组与进度');
assert(medium.marks.indexOf('1') === 1, '已完成日程留在原位置并带完成标记');
assert(small.ids.length === small.texts.length, '条目 id 与文案一一对应，供卡片勾选回传');
assert(small.cPanel.length === 9, '背板颜色为带透明度的 ARGB 值');
const many = sampleData();
for (let index = 0; index < 9; index++) many.todayTasks.push(task('补充' + index, false, null));
const manyCard = buildCardData(many, CardSize.LARGE, false);
assert(manyCard.texts.length === 12, '列表可滚动，条目不再按尺寸截断');
assert(manyCard.futureTexts.length === 2, '未来日程条目随卡片数据下发');
assert(manyCard.futureRanges.length === 2 && manyCard.futureRanges[0] === '11月2日',
  '未来日程无起始日时只显示截止日');
assert(manyCard.futureCount === 2, '未来日程条数单独下发，供大卡分区显示');
assert(manyCard.futureIds.length === 2 && manyCard.futureIds[0] === 'id-体检',
  '未来日程带 id，供卡片直接勾选完成');
const ranged = sampleData();
ranged.futureTasks[1].startDate = '2026-11-01';
const rangedCard = buildCardData(ranged, CardSize.LARGE, false);
assert(rangedCard.futureRanges[1] === '11月1日-11月5日', '有起始日时显示起止区间');

console.log('空数据与跨日文案');const empty = freshData();
empty.currentDate = '2026-10-22';
const emptyCard = buildCardData(empty, CardSize.MEDIUM, false);
assert(emptyCard.texts.length === 0, '空数据不产生日程条目');
assert(emptyCard.progress === 0, '空数据进度为 0');
assert(emptyCard.headline.length > 0, '空数据仍有说明文案');

const otherDay = sampleData();
otherDay.currentDate = '2026-10-25';
const otherCard = buildCardData(otherDay, CardSize.SMALL, false);
assert(otherCard.headline.indexOf('今天') < 0, '非今日不写成“今天”');
assert(otherCard.dateText.indexOf('10月25日') === 0, '非今日显示所选日期');

console.log('配色随主题与深浅色切换');
const darkCard = buildCardData(sampleData(), CardSize.SMALL, true);
assert(darkCard.isDark === true, '深色标记透传');
assert(darkCard.cPanel !== small.cPanel, '深色背板与浅色不同');
const forest = sampleData();
forest.settings.colorPreset = 'forest';
const forestCard = buildCardData(forest, CardSize.SMALL, false);
assert(forestCard.cAccent !== small.cAccent, '配色预设影响强调色');

console.log('全部日程完成');
for (const item of data.todayTasks) item.completed = true;
const doneCard = buildCardData(data, CardSize.LARGE, false);
assert(doneCard.progress === 100, '全部完成时进度为 100');
assert(doneCard.headline === '日程已全部完成', '全部完成时使用完成文案');
assert(doneCard.texts.length === 3, '完成态仍展示日程内容');

const retained = sampleData();
retained.settings.retainCompletedFutureUntilDue = true;
retained.futureTasks[0].completed = true;
const retainedCard = buildCardData(retained, CardSize.LARGE, false);
assert(retainedCard.futureMarks.join(',') === '1,0', '卡片未来完成标记与行顺序一致');
assert(retainedCard.retainCompletedFutureUntilDue === true, '保留开关透传卡片，控制完成是否淡出');
assert(retainedCard.futureTexts.length === 2 && retainedCard.futureIds.length === retainedCard.futureMarks.length, '已完成未来日程仍下发且 ID 标记一一对应');
assert(buildCardData(sampleData(), CardSize.LARGE, false).retainCompletedFutureUntilDue === false, '卡片默认仍使用立即消失模式');
const delayedData = sampleData();
delayedData.todayTasks[0].scheduledDate = addDays(todayKey(), -2);
let delayedCard = buildCardData(delayedData, CardSize.SMALL, false);
assert(delayedCard.delays[0] === '延期 2 天' && delayedCard.delays.length === delayedCard.ids.length, '小卡也独立下发与 ID 对齐的延期提示');
assert(delayedCard.metas[0].startsWith('延期 2 天'), '中大卡优先展示延期天数，避免被分组和进度挤掉');
delayedData.todayTasks[0].completed = true;
delayedCard = buildCardData(delayedData, CardSize.LARGE, false);
assert(delayedCard.delays[0] === '', '已完成日程不继续显示卡片延期提示');
console.log('主题渐变资源、三规格一致性和可读性');
function luminance(argb) {
  const rgb = argb.slice(-6).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}
function contrast(first, second) {
  const a = luminance(first), b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
const themeSample = sampleData();
const originalSample = JSON.stringify(themeSample);
const combinations = ['seasalt', 'forest', 'sunset', 'ink'].flatMap(preset => [false, true].map(dark => {
  const input = sampleData(); input.settings.colorPreset = preset;
  const payload = buildCardData(input, CardSize.MEDIUM, dark);
  const resources = JSON.parse(readFileSync(path.join(project, 'entry/src/main/resources',
    dark ? 'dark' : 'base', 'element/color.json'), 'utf8')).color;
  return { preset, dark, payload, resources,
    stops: [payload.cGradientStart, payload.cGradientMiddle, payload.cGradientEnd] };
}));
assert(combinations.every(item => item.stops.every(color => /^#FF[0-9a-f]{6}$/i.test(color)) &&
  item.stops[0] !== item.stops[2]), '八套渐变均为不透明有效颜色，起止有层次，不受壁纸明暗干扰');
const primaryMin = Math.min(...combinations.flatMap(item => item.stops.map(stop => contrast(item.payload.cText, stop))));
const secondaryMin = Math.min(...combinations.flatMap(item => item.stops.map(stop => contrast(item.payload.cSoft, stop))));
assert(primaryMin >= 7, `所有渐变端点及中点正文对比度至少7:1（实测最低 ${primaryMin.toFixed(2)}）`);
assert(secondaryMin >= 4.5, `所有渐变端点及中点辅助文字至少4.5:1（实测最低 ${secondaryMin.toFixed(2)}）`);
assert(combinations.every(item => ['start', 'middle', 'end'].every((name, index) =>
  item.resources.find(resource => resource.name === `card_${item.preset}_gradient_${name}`)?.value.toLowerCase() === item.stops[index].toLowerCase()) &&
  item.resources.find(resource => resource.name === `card_${item.preset}_soft`)?.value.toLowerCase() === item.payload.cSoft.toLowerCase()),
  '跟随系统的渐变和辅助文字资源与手动主题推送完全一致，应用退出后仍可直接换色');
const sizeGradients = [CardSize.SMALL, CardSize.MEDIUM, CardSize.LARGE].map(size => {
  const payload = buildCardData(themeSample, size, false);
  return [payload.cGradientStart, payload.cGradientMiddle, payload.cGradientEnd].join(',');
});
assert(new Set(sizeGradients).size === 1, '三种卡片规格共用相同主题渐变，不按尺寸换色');
assert(JSON.stringify(themeSample) === originalSample, '生成渐变不会修改日程、设置或完成状态');

console.log(`\n结果：${passed} 项通过，${failed} 项失败`);
process.exit(failed === 0 ? 0 : 1);
