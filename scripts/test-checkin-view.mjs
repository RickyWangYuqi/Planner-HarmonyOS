// 执行真实打卡组件方法和 Builder 文案表达式，验证同一组件实例的数据更新。
// @Watch 使用可控同步观察器；不模拟 ArkUI 节点渲染、动画、触摸或系统键盘，不访问设备和用户数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const location of [process.env.TYPESCRIPT_PATH, 'typescript',
  path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try { ts = require(location); break; } catch { /* 使用本机已有编译器。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
function transpile(source, filename) {
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    reportDiagnostics: true, fileName: filename
  });
  const errors = (output.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(item => item.messageText).join('\n'));
  return output.outputText;
}
const modules = new Map();
function loadModel(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(project, 'entry/src/main/ets/model', name + '.ets');
  const module = { exports: {} };
  modules.set(name, module.exports);
  vm.runInThisContext('(function(require,module,exports){' +
    transpile(readFileSync(filename, 'utf8'), filename) + '\n})', { filename })(
    request => loadModel(path.basename(request)), module, module.exports);
  return module.exports;
}
const model = loadModel('PlanerModel');
const checkInModel = loadModel('CheckInModel');
const engine = loadModel('PlanerEngine');
const checkInEngine = loadModel('CheckInEngine');
const { AppAction, AppData } = model;
const { CheckInItem } = checkInModel;

const viewPath = path.join(project, 'entry/src/main/ets/components/CheckInView.ets');
const editorPath = path.join(project, 'entry/src/main/ets/components/CheckInEditor.ets');
const viewSource = readFileSync(viewPath, 'utf8');
const editorSource = readFileSync(editorPath, 'utf8');
function builderSource(name) {
  const start = viewSource.indexOf('@Builder private ' + name + '(');
  if (start < 0) throw new Error('缺少真实 Builder：' + name);
  const end = viewSource.indexOf('@Builder', start + 1);
  return viewSource.slice(start, end < 0 ? undefined : end);
}
// 文案表达式从当前 Builder 原样提取；业务规则和字符串不在测试中重新实现。
function textExpression(name, index = 0) {
  const expressions = Array.from(builderSource(name).matchAll(/\bText\((.+)\)\.fontSize\(/g), match => match[1]);
  if (!expressions[index]) throw new Error('缺少 Builder Text 表达式：' + name + '/' + index);
  return expressions[index];
}
function requiredMatch(source, expression, label) {
  const match = source.match(expression);
  if (!match) throw new Error('真实视图结构已变化：' + label);
  return match[1];
}
const buttonExpression = requiredMatch(builderSource('smallButton'),
  /Button\((.+), \{ type: ButtonType\.Normal(?:, stateEffect: false)? \}\)/, '动态按钮标题');

function compileComponent(source, name, filename, appended = '', extraContext = {}) {
  const start = source.indexOf('@Component');
  const end = source.indexOf('  @Builder', start);
  if (start < 0 || end < 0) throw new Error(name + ' 方法提取边界已变化');
  const watches = Array.from(source.slice(start, end).matchAll(/@Watch\('([^']+)'\)\s+(?:private\s+)?(\w+)/g),
    match => ({ method: match[1], field: match[2] }));
  const classSource = source.slice(start, end)
    .replace('@Component', '').replace('export struct ' + name, 'class ' + name)
    .replace(/@StorageProp\('[^']+'\)\s*/g, '').replace(/@Watch\('[^']+'\)\s*/g, '')
    .replace(/@(?:Prop|State)\s+/g, '') + appended + '\n}\nglobalThis.ComponentClass = ' + name + ';';
  const context = vm.createContext({
    ...model, ...checkInModel, ...engine, ...checkInEngine, console,
    Palette: class {},
    Scroller: class { scrollBy() {} },
    Motion: { quick: () => ({}), spring: () => ({}) },
    Materials: { confirmation: (_palette, options) => options },
    EditorMaterialRefresh: { request: () => {} },
    curves: { springMotion: () => ({}) },
    setTimeout, clearTimeout, ...extraContext
  });
  vm.runInContext(transpile(classSource, filename), context, { filename });
  return { ComponentClass: context.ComponentClass, watches };
}
const view = compileComponent(viewSource, 'CheckInView', viewPath, '\n' +
  'getUIContext() { return { animateTo: (options, change) => { this.testAnimations = (this.testAnimations || 0) + 1; change(); if (options.onFinish) options.onFinish(); }, getPromptAction: () => ({ showToast: (options) => { (this.testToasts ||= []).push(options.message); }, showDialog: async () => { this.testDialogs = (this.testDialogs || 0) + 1; return { index: this.testDialogIndex ?? 1 }; } }) }; }\n' +
  'metricFromView(scope, field) { return ' + textExpression('metric') + '; }\n' +
  'totalFromView(scope) { return ' + textExpression('statsContent') + '; }\n' +
  'itemNameFromView(id) { return ' + textExpression('itemCard') + '; }\n' +
  'itemStatusFromView(id) { return ' + textExpression('itemCard', 1) + '; }\n' +
  'titleFromView() { return ' + textExpression('modalHeader') + '; }\n' +
  'subtitleFromView() { return ' + textExpression('modalHeader', 1) + '; }\n' +
  'recordStatusFromView(key) { return ' + requiredMatch(builderSource('recordRow'), /Text\((this\.recordLabel\(this\.timelineRecord\(key\)\))\)\.fontSize/, '周期状态文案') + '; }\n' +
  'recordContentFromView(key) { return ' + requiredMatch(builderSource('recordRow'), /Text\((this\.snapshotContentText\(key\))\)\.fontSize/, '周期内容文案') + '; }\n' +
  'recordClickFromView(key) { ' + requiredMatch(builderSource('recordRow'), /\.onClick\(\(\) => \{ (.+) \}\)/, '历史行点击入口') + ' }\n' +
  'futureToggleFromView(key) { ' + requiredMatch(builderSource('recordRow'), /buttonId: 'checkin-advance-' \+ key, onToggle: \(\) => \{ ([^}]+) \}/, '未来时间线按钮点击入口') + ' }\n' +
  'createButtonFromView() { return ' + requiredMatch(builderSource('fixedHeader'), /IconButton\((\{[^\n]+\})\)\.id\('checkin-create'\)/, '新增打卡按钮参数') + '; }\n' +
  'manageIconFromView(icon, id) { return ' + requiredMatch(builderSource('manageButtonContent'), /PlanerIcon\(\{ icon: (.+), iconSize: 18/, '管理按钮最内层图标绑定') + '; }\n' +
  'buttonFromView(title, id) { return ' + buttonExpression + '; }\n');
// 同样执行真实视图回调，确认展开和收起的状态更新经过 animateLayout。
const editorDateBuilder = editorSource.slice(editorSource.indexOf('@Builder private dateSectionBody('),
  editorSource.indexOf('@Builder private frequencyButton('));
const editorFrequencyBuilder = editorSource.slice(editorSource.indexOf('@Builder private frequencyButton('),
  editorSource.indexOf('@Builder private monthDay('));
const calendarExpression = requiredMatch(editorDateBuilder,
  /\.onClick\(\(\) => \{ (.+) \}\)/, '日历动画回调');
const frequencyExpression = requiredMatch(editorFrequencyBuilder,
  /\.onClick\(\(\) => \{ (.+) \}\)/, '频率动画回调');
const editor = compileComponent(editorSource, 'CheckInEditor', editorPath, '\n' +
  'getUIContext() { return { animateTo: (options, change) => { this.testAnimations = (this.testAnimations || 0) + 1; change(); if (options.onFinish) options.onFinish(); }, getPromptAction: () => ({ showToast: (options) => { (this.testToasts ||= []).push(options.message); } }) }; }\n' +
  'calendarFromView() { ' + calendarExpression + '; }\n' +
  'frequencyFromView(value) { ' + frequencyExpression + '; }\n');
function installWatches(instance, watches) {
  for (const binding of watches) {
    let value = instance[binding.field];
    Object.defineProperty(instance, binding.field, {
      configurable: true, enumerable: true,
      get: () => value,
      set(next) {
        if (Object.is(value, next)) return;
        value = next;
        instance[binding.method](binding.field);
      }
    });
  }
}
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++;
  console.log('✓ ' + message);
}
function initialData() {
  const data = new AppData();
  data.currentDate = data.lastRolloverDate = '2026-10-26';
  return data;
}
function action(type, fields = {}) { return Object.assign(new AppAction(type), fields); }
function update(instance, type, fields = {}) {
  instance.data = engine.reduce(instance.data, action(type, fields));
}
function newView() {
  const instance = new view.ComponentClass();
  installWatches(instance, view.watches);
  instance.data = initialData();
  instance.onAction = value => { instance.data = engine.reduce(instance.data, value); };
  instance.aboutToAppear();
  return instance;
}
function newItem(fields = {}) {
  return Object.assign(new CheckInItem(), {
    id: 'reading', name: '背单词289-298', startDate: '2026-10-24', step: 10
  }, fields);
}
const instance = newView();
assert(instance.totalFromView('overall').includes('共 0 期'), '空页面的真实统计文案为零');
assert(instance.metricFromView('overall', 'completed') === '0', '空页面完成次数为零');
update(instance, 'CHECKIN_SAVE', { checkIn: newItem() });
instance.selectedId = 'reading';
assert(instance.totalFromView('overall').includes('共 3 期'), '同一页面创建计划后累计应打周期立即变为三');
assert(instance.totalFromView('selected').includes('共 3 期'), '选中条目观察器刷新详情统计');
assert(instance.sectionCount('waiting') === 1, '创建后待打卡分组立即更新');
assert(instance.itemNameFromView('reading') === '背单词289-298', '稳定条目 ID 从最新数据读取完整名称');
assert(instance.titleFromView() === '背单词289-298', '无参数弹层标题读取当前条目');
assert(instance.selectedTimeline.length === 3, '详情时间线包含未打开应用时错过的周期');
assert(!instance.hasSnapshot('2026-10-24'), '合成遗漏周期不伪装成持久化快照');
assert(instance.recordContentFromView('2026-10-24') === '未记录当期内容', '合成周期不展示推测的数字内容');

instance.openComplete(instance.selected(), '2026-10-26');
assert(instance.metricFromView('overall', 'completed') === '1', '真实完成方法后首页统计同步变为一');
assert(instance.metricFromView('selected', 'rate') === '33%', '详情完成率同步更新');
assert(instance.sectionCount('waiting') === 0 && instance.sectionCount('completed') === 1 && instance.todayItems().map(item => item.id).join(',') === 'reading', '完成更新统计并保留今日清单中的原条目');
assert(instance.recordStatusFromView('2026-10-26') === '已完成', '同一周期行的真实状态文案刷新');
instance.openComplete(instance.selected(), '2026-10-24');
const backfillResult = instance.backfill('2026-10-24', '背单词269-278');
assert(backfillResult === '' && instance.modal === 'backfill' && instance.sheetShown, '新补卡回调成功后留在补卡页，可继续选择其他日期');
const beforeDuplicate = JSON.stringify(instance.data);
const duplicateError = instance.backfill('2026-10-24', '不应覆盖');
assert(!!duplicateError && instance.actionError === duplicateError && instance.modal === 'backfill' && JSON.stringify(instance.data) === beforeDuplicate, '重复补卡返回错误并留页，不重复派发或覆盖快照');
assert(instance.metricFromView('overall', 'completed') === '2', '补卡后同一页面累计次数继续更新');
assert(instance.metricFromView('selected', 'rate') === '67%', '补卡后详情完成率继续更新');
assert(instance.hasSnapshot('2026-10-24'), '补卡将合成周期转换为真实快照');
assert(instance.recordStatusFromView('2026-10-24') === '已补卡', '稳定周期键对应的新状态立即显示');
assert(instance.recordContentFromView('2026-10-24') === '背单词269-278', '历史行显示手动补卡的完整名称快照');
assert(instance.selected().name === '背单词289-298', '补卡不推进或覆盖当前计划名称中的数字');
update(instance, 'CHECKIN_UNDO', { id: 'reading', key: '2026-10-24' });
assert(instance.metricFromView('overall', 'completed') === '1' && instance.metricFromView('selected', 'rate') === '33%', '撤销后首页与详情统计同时回退');
assert(instance.recordStatusFromView('2026-10-24') === '未完成', '撤销后复用的历史行显示未完成');
instance.backToDetail();
const renamed = instance.selected().clone();
renamed.name = '复习单词289-298';
update(instance, 'CHECKIN_SAVE', { checkIn: renamed });
assert(instance.itemNameFromView('reading') === '复习单词289-298' && instance.titleFromView() === '复习单词289-298', '同 ID 改名同时刷新卡片和详情标题');
assert(instance.recordContentFromView('2026-10-26') === '背单词289-298', '改计划名称不回写已经生成的旧周期内容');
assert(instance.manageIconFromView('paused', 'checkin-pause-resume') === 'pause', '运行中按钮忽略旧暂停图标参数，读取实际状态');
update(instance, 'CHECKIN_PAUSE', { id: 'reading' });
assert(instance.itemStatusFromView('reading').includes('已暂停') && instance.subtitleFromView().includes('已暂停'), '暂停后卡片和弹层副标题立即更新');
assert(instance.buttonFromView('旧标题', 'checkin-pause-resume') === '已暂停', '按钮忽略捕获的旧标题并读取最新暂停态');
assert(instance.manageIconFromView('pause', 'checkin-pause-resume') === 'paused', '暂停后最内层 PlanerIcon 绑定立即显示圆形暂停图标');
assert(instance.sectionCount('paused') === 1, '暂停分组计数从最新数据读取');
update(instance, 'CHECKIN_RESUME', { id: 'reading' });
assert(instance.buttonFromView('旧标题', 'checkin-pause-resume') === '暂停' && instance.sectionCount('paused') === 0, '恢复后的按钮和分组计数同步还原');
assert(instance.manageIconFromView('paused', 'checkin-pause-resume') === 'pause', '恢复后最内层图标同步还原，忽略旧的已暂停参数');
assert(instance.manageIconFromView('edit', 'checkin-edit') === 'edit' && instance.manageIconFromView('calendar', 'checkin-backfill') === 'calendar' && instance.manageIconFromView('trash', 'checkin-delete') === 'trash', '其他管理按钮保留各自的语义图标');
instance.modal = 'range'; instance.recordKey = '2026-10-27';
assert(instance.titleFromView() === '确认本期内容' && instance.subtitleFromView().includes('2026-10-27'), '复用弹层切换内容确认时标题动态更新');
instance.modal = 'backfill';
assert(instance.titleFromView() === '补卡' && instance.subtitleFromView() === '复习单词289-298', '复用弹层切换补卡时清除旧确认标题');

const other = newView();
update(other, 'CHECKIN_SAVE', { checkIn: newItem({ startDate: '2026-10-26', autoIncrement: true }) });
other.selectedId = 'reading';
update(other, 'ROLLOVER_TO', { key: '2026-10-27' });
assert(other.buttonFromView('打卡', 'checkin-complete-reading') === '打卡', '跨日自动生成后复用按钮直接显示打卡');
assert(other.selected().name === '背单词299-308', '真实次日自动接续名称中的十个数字');
other.openComplete(other.selected(), '2026-10-27');
assert(!other.sheetShown && other.modal === 'detail' && other.recordContentFromView('2026-10-27') === '背单词299-308', '正常今日打卡直接派发完成，不进入完成弹层');
assert(other.recordStatusFromView('2026-10-27') === '已完成' && other.selectedId === 'reading', '直接完成更新记录并保持当前选择和页面');
update(other, 'CHECKIN_UNDO', { id: 'reading', key: '2026-10-27' });
update(other, 'CHECKIN_SKIP', { id: 'reading', key: '2026-10-27' });
assert(other.sectionCount('waiting') === 1 && other.recordFor('reading', '2026-10-27').status === 'ready', '旧跳过动作被拒绝，周期继续保持未完成');
// 今日切换执行真实入口，断言行为和清单身份，不依赖被移除的完成弹层。
const direct = newView();
for (const id of ['first', 'second', 'third']) update(direct, 'CHECKIN_SAVE', { checkIn: newItem({ id, name: id, startDate: '2026-10-26' }) });
const directOrder = direct.todayItems().map(item => item.id).join(',');
const directSheets = []; direct.onSheetChange = shown => directSheets.push(shown);
direct.selectedId = 'third'; direct.modal = 'editor'; direct.recordKey = '2026-10-25';
const directAnimations = direct.testAnimations || 0;
direct.toggleToday('second');
assert(direct.recordFor('second', direct.today()).status === 'completed' && !direct.sheetShown && directSheets.length === 0, '今日按钮就地完成且不打开或关闭任何弹层');
assert(direct.todayItems().map(item => item.id).join(',') === directOrder && direct.selectedId === 'third' && direct.modal === 'editor' && direct.recordKey === '2026-10-25' && (direct.testAnimations || 0) === directAnimations, '完成保留今日项顺序、现有选择和子页，不触发整页动画');
direct.toggleToday('second');
assert(direct.recordFor('second', direct.today()).status === 'ready' && direct.todayItems().map(item => item.id).join(',') === directOrder && !direct.sheetShown && directSheets.length === 0, '同一按钮就地撤销，条目顺序和弹层状态保持');
direct.openDetail(direct.itemById('third')); const shownEvents = directSheets.length;
direct.toggleToday('first');
assert(direct.sheetShown && direct.selectedId === 'third' && direct.modal === 'detail' && directSheets.length === shownEvents, '详情打开时完成另一个今日项也不替换或重开详情');
const beforeDirectError = JSON.stringify(direct.data); const beforeErrorAnimation = direct.testAnimations || 0;
direct.toggleToday('missing');
assert(!!direct.actionError && JSON.stringify(direct.data) === beforeDirectError && direct.modal === 'detail' && direct.selectedId === 'third' && direct.sheetShown && directSheets.length === shownEvents && (direct.testAnimations || 0) === beforeErrorAnimation, '完成无效条目返回错误，不修改数据或跳转');
direct.openComplete(direct.itemById('third'), '2026-10-27');
assert(direct.actionError.includes('今天或过去') && JSON.stringify(direct.data) === beforeDirectError && direct.modal === 'detail' && direct.selectedId === 'third', '错误未来日期被领域校验拒绝且不进入子页');
update(direct, 'CHECKIN_SKIP', { id: 'second', key: direct.today() });
assert(direct.todayItems().map(item => item.id).join(',') === directOrder && direct.recordFor('second', direct.today()).status === 'ready', '旧跳过动作不再移除今日项，完成与未完成项保持原顺序');
const overflowView = newView();
update(overflowView, 'CHECKIN_SAVE', { checkIn: newItem({ name: '第9007199254740991节', step: 1, autoIncrement: true, startDate: '2026-10-26' }) });
update(overflowView, 'ROLLOVER_TO', { key: '2026-10-27' }); overflowView.toggleToday('reading');
assert(overflowView.sheetShown && overflowView.modal === 'range' && overflowView.recordFor('reading', '2026-10-27').status === 'pending', '非法溢出的pending仍进入手动调整页，不误完成');
overflowView.closeSheet(); overflowView.openComplete(overflowView.itemById('reading'), '2026-10-26');
assert(overflowView.sheetShown && overflowView.modal === 'backfill' && overflowView.recordKey === '2026-10-26', '过去日期仍进入补卡页，保持与今日直接操作区分');

// 执行按钮真实文案与外层尺寸链；节点和动效物理过程仍由真机验证。
const togglePath = path.join(project, 'entry/src/main/ets/components/CheckInToggleButton.ets');
const toggleSource = readFileSync(togglePath, 'utf8');
const toggleBuild = requiredMatch(toggleSource, /  build\(\) \{([\s\S]*?)\n  \}/, '打卡按钮固定外框');
const toggleFrames = [];
const toggle = compileComponent(toggleSource, 'CheckInToggleButton', togglePath,
  '\ngetUIContext() { return { animateTo: (_options, change) => change() }; }\nframeFromView() {' + toggleBuild + '\n}', {
    MaterialButtonScope: () => {
      const frame = {}; toggleFrames.push(frame);
      const attributes = { width(value) { frame.width = value; return attributes; }, height(value) { frame.height = value; return attributes; } };
      return attributes;
    }
  });
const toggleInstance = new toggle.ComponentClass();
assert(toggleInstance.label() === '完成打卡', '独立今日按钮默认文案来自真实label方法');
toggleInstance.frameFromView(); toggleInstance.completed = true;
assert(toggleInstance.label() === '撤销', '完成状态复用同一按钮并显示撤销');
toggleInstance.frameFromView(); toggleInstance.completed = false; toggleInstance.pending = true;
assert(toggleInstance.label() === '调整本期内容', 'pending按钮明确提示手动调整而非完成');
toggleInstance.frameFromView();
assert(toggleFrames.length === 3 && toggleFrames.every(frame => frame.width === 136 && frame.height === 44), '完成、撤销、调整三种文案都保持136×44外框');
assert(toggleSource.includes('ForEach([this.label()]') && toggleSource.includes('.transition(this.contentTransition())') && !toggleBuild.includes('.transition'), '状态转场只替换按钮内部图标文字，外框不参与进退动画');
assert(toggleSource.includes('new PlanerControlModifier(this.palette, !this.completed)') && !toggleSource.includes('.backgroundColor(this.palette.accent)') && !builderSource('itemCard').includes('.backgroundColor(this.palette.accent)'), '未完成按钮允许材质淡主题色，卡片与按钮不添加整块高饱和强调色背景');

toggleInstance.palette = { accent: '#778899', textSoft: '#667788' };
assert(toggleInstance.labelIcon('完成打卡') === '' && toggleInstance.labelIcon('提前打卡') === '', '普通与提前打卡只显示文字，不添加勾选图标');
assert(toggleInstance.labelIcon('撤销') === 'restore' && toggleInstance.labelIcon('调整本期内容') === 'edit', '撤销与调整继续使用对应图标');
assert(toggleInstance.labelColor('完成打卡') === '#778899' && toggleInstance.labelColor('撤销') === '#667788', '按钮文字根据转场条目使用主题色或次要色');
toggleInstance.pending = false; toggleInstance.future = true;
assert(toggleInstance.label() === '提前打卡', '未来未完成按钮显示提前打卡');
toggleInstance.completed = true;
assert(toggleInstance.label() === '撤销' && toggleInstance.labelIcon(toggleInstance.label()) === 'restore' &&
  toggleInstance.labelColor(toggleInstance.label()) === '#667788', '未来已完成按钮复用撤销文案、恢复图标与中性色');
toggleInstance.future = false;
assert(toggleInstance.label() === '撤销', '同一组件回到当期完成状态后保持相同撤销文案');
const createButton = instance.createButtonFromView();
assert(createButton.icon === 'plus' && createButton.tone === 'accent' && createButton.palette === instance.palette,
  '新增打卡按钮真实参数复用加号与随当前色板变化的主题染色材质');

function newEditor(item, data = initialData()) {
  const result = new editor.ComponentClass();
  result.item = item; result.data = data; result.aboutToAppear();
  return result;
}
const blankEditor = newEditor(newItem({ id: '', name: '' }));
assert(blankEditor.recognitionHint() === '编号或区间可以分别按周期自动递增、接续（一次只能开启一项）', '空名称提示准确说明编号递增与区间接续互斥');
const freshEditor = newEditor(newItem({ id: '', autoIncrement: true }));
assert(!freshEditor.autoIncrement && !freshEditor.candidate().autoIncrement, '新建名称即使识别数字也默认关闭自动递增');
assert(freshEditor.step === '10' && freshEditor.recognitionHint() === '区间可以按周期自动接续，点击开启自动递增/接续', '合法范围显示直接启用提示并识别每期数量');
freshEditor.enableAutoIncrement();
assert(freshEditor.autoIncrement && freshEditor.testToasts.at(-1) === '自动递增已打开，下一期将显示背单词299-308', '点击提示执行真实启用方法并Toast下一期完整名称');
assert(freshEditor.preview() === '下一期：背单词299-308' && freshEditor.recognitionHint() === '区间可以按周期自动接续，已开启自动递增/接续', '启用后预览接续分段并更新提示');
assert(freshEditor.candidate().name === '背单词289-298' && freshEditor.candidate().confirmNext === false, '查看预览不改首期，提交规则无需逐期确认');
assert(!editorSource.includes('checkin-confirm-next') && !editorSource.includes('生成下一期前确认'), '编辑器已移除旧确认开关与文案');
freshEditor.step = '20';
freshEditor.changeName('复习单词289-298');
assert(freshEditor.step === '20', '只改名称前后缀保留用户自定每期数量');
freshEditor.changeName('复习单词289-293');
assert(freshEditor.step === '5', '修改数字范围后识别新的默认数量');
freshEditor.changeAutoIncrement(false); freshEditor.changeName('看网课第10节');
assert(freshEditor.step === '1' && freshEditor.recognitionHint() === '编号可以按周期自动递增，点击开启自动递增/接续', '单数字名称默认步长一并可点击启用');
freshEditor.changeAutoIncrement(true);
assert(freshEditor.autoIncrement && freshEditor.testToasts.at(-1) === '自动递增已打开，下一期将显示看网课第11节', '直接打开Switch走同一启用校验和下一期Toast');
assert(freshEditor.preview() === '下一期：看网课第11节', '单数字预览只增加名称中的一个数字');
freshEditor.changeAutoIncrement(false); freshEditor.changeName('保持阅读');
assert(checkInEngine.validateCheckIn(freshEditor.candidate()) === '' && !freshEditor.candidate().autoIncrement, '关闭自动递增后允许无数字的固定名称');
freshEditor.changeAutoIncrement(true);
assert(!freshEditor.autoIncrement && freshEditor.error.includes('没有可递增') && freshEditor.testToasts.at(-1) === freshEditor.error, '未识别名称无法打开Switch并明确反馈原因');
freshEditor.changeName('第1章第2节'); freshEditor.enableAutoIncrement();
assert(!freshEditor.autoIncrement && freshEditor.error.includes('多组数字'), '歧义名称从提示入口启用也被拒绝');
freshEditor.changeName('看网课第10节'); freshEditor.step = '0'; freshEditor.changeAutoIncrement(true);
assert(!freshEditor.autoIncrement && freshEditor.error.includes('大于零') && freshEditor.testToasts.at(-1) === freshEditor.error, '无效步长不能开启并有清晰错误Toast');
freshEditor.step = '1'; freshEditor.changeName('看网课第' + Number.MAX_SAFE_INTEGER + '节'); freshEditor.enableAutoIncrement();
assert(!freshEditor.autoIncrement && freshEditor.error.includes('超出有效范围') && freshEditor.preview().includes('超出有效范围'), '下一期溢出不允许启用且预览给出错误');
const stale = newEditor(newItem({ autoIncrement: true }));
const latest = initialData();
latest.checkIns = [newItem({ name: '背单词299-308', autoIncrement: true, rangeUpdatedFor: '2026-10-27' })];
stale.data = latest;
assert(stale.candidate().name === '背单词299-308', '未改名称的旧草稿保留卡片跨日推进后的数字');
stale.changeName('复习单词289-298');
assert(stale.candidate().name === '复习单词299-308', '只改前后缀的草稿与后台新数字合并');
stale.changeName('复习单词501-510');
assert(stale.candidate().name === '复习单词501-510', '明确手改数字仍按用户草稿提交');
stale.autoIncrement = false;
assert(!stale.candidate().autoIncrement && stale.candidate().name === '复习单词501-510', '关闭自动递增不丢失手改名称');

const animationEditor = newEditor(newItem({ id: '' }));
animationEditor.calendarFromView();
assert(animationEditor.calendarShown && animationEditor.testAnimations === 1, '真实日历展开回调在动画闭包中改变状态');
animationEditor.calendarFromView();
assert(!animationEditor.calendarShown && animationEditor.testAnimations === 2, '真实日历收起回调也经过动画闭包');
animationEditor.frequencyFromView('monthly');
assert(animationEditor.frequency === 'monthly' && animationEditor.testAnimations === 3, '真实频率选择回调通过动画切换月日期区域');

// 同一半模态内的二级页面进退执行真实 showModal，不替换其动画闭包。
const navigation = newView(); update(navigation, 'CHECKIN_SAVE', { checkIn: newItem() });
const sheetEvents = []; navigation.onSheetChange = shown => sheetEvents.push(shown);
navigation.openDetail(navigation.itemById('reading'));
navigation.focusedInput = 'old-input'; navigation.pressedButton = 'old-button'; navigation.actionError = 'old-error';
const beforeEditAnimation = navigation.testAnimations || 0; navigation.editSelected();
assert(navigation.modal === 'editor' && navigation.sheetShown && navigation.editorItem.id === 'reading' && navigation.testAnimations === beforeEditAnimation + 1, '详情进入编辑只推进同一弹层的动画子页');
assert(!navigation.focusedInput && !navigation.pressedButton && !navigation.actionError && sheetEvents.length === 1, '子页进退清除旧焦点与错误，不重复开关原生弹层');
const invalidSave = navigation.saveItem(newItem({ name: '' }));
assert(!!invalidSave && navigation.modal === 'editor' && navigation.sheetShown, '编辑校验失败返回错误并保留当前页面');
const editedItem = navigation.selected().clone(); editedItem.name = '复习单词289-298';
const saved = navigation.saveItem(editedItem);
assert(saved === '' && navigation.modal === 'detail' && navigation.sheetShown && navigation.selected().name === '复习单词289-298', '已有计划保存成功通过动画返回详情且保持弹层');
const stableData = JSON.stringify(navigation.data); const selectedStats = navigation.selectedStats; const overallStats = navigation.overallStats;
const beforeListAnimation = navigation.testAnimations; navigation.switchList(true);
assert(navigation.showAll && navigation.listDirection === 1 && navigation.testAnimations === beforeListAnimation + 1, '列表切换通过真实动画仅更新内容选择状态');
assert(navigation.modal === 'detail' && navigation.selectedId === 'reading' && navigation.sheetShown && sheetEvents.length === 1 && JSON.stringify(navigation.data) === stableData && navigation.selectedStats === selectedStats && navigation.overallStats === overallStats, '列表切换不关闭弹层、不更改业务数据或重新计算统计');
navigation.switchList(true);
assert(navigation.testAnimations === beforeListAnimation + 1, '重复选择相同列表不启动多余动画');
navigation.switchList(false);
assert(!navigation.showAll && navigation.listDirection === -1, '反向列表切换仅改变内容方向和选择');
navigation.openBackfill();
assert(navigation.modal === 'backfill' && navigation.recordKey === '2026-10-25' && navigation.sheetShown, '详情补卡入口选最近漏卡日期并推进同一弹层');
const futureError = navigation.backfill('2026-10-27', '未来');
assert(!!futureError && navigation.modal === 'backfill' && navigation.sheetShown && JSON.stringify(navigation.data) === stableData, '补卡未来日期返回错误且保留补卡页和数据');
const beforeBackAnimation = navigation.testAnimations; navigation.backToDetail();
assert(navigation.modal === 'detail' && navigation.testAnimations === beforeBackAnimation + 1 && navigation.sheetShown, '二级返回执行showModal动画并保留详情弹层');
navigation.closeSheet();
assert(!navigation.sheetShown && sheetEvents.at(-1) === false, '右侧关闭入口真正关闭整张弹层');
const creating = newView(); creating.openNew();
assert(creating.saveItem(newItem({ id: 'new-created' })) === '' && !creating.sheetShown && creating.data.checkIns.length === 1, '新建保存仍关闭编辑弹层，不进入不存在的详情来源');
const ordinary = new model.Task(); ordinary.id = 'ordinary'; ordinary.text = instance.selected().name;
instance.data.todayTasks.push(ordinary);
instance.openDetail(instance.selected());
instance.testDialogIndex = 0;
await instance.confirmAction('CHECKIN_DELETE', '删除', '测试', '完成');
assert(instance.sheetShown && instance.data.checkIns.length === 1, '取消永久删除保留计划与详情页面');
instance.testDialogIndex = 1;
await instance.confirmAction('CHECKIN_DELETE', '删除', '测试', '完成');
assert(instance.data.checkIns.length === 0 && instance.data.checkInRecords.length === 0, '真实删除确认方法永久清除计划和全部周期记录');
assert(!instance.sheetShown && !instance.selectedId && !instance.recordKey, '永久删除成功关闭弹层并清理已失效的选中内容');
assert(instance.data.todayTasks.length === 1 && instance.data.todayTasks[0].id === 'ordinary', '永久删除关联日程保留同名普通日程');
assert(instance.totalFromView('overall').includes('共 0 期'), '永久删除后同一页面统计归零');

// 旧数字列迁移通过真实 normalizeData 验证，防止新版文本逻辑重写历史数值。
const legacy = initialData();
legacy.checkIns = [newItem({ name: '旧阅读', nameVersion: 0, useRange: true, rangeStart: 289, rangeEnd: 298, count: 10, autoIncrement: true })];
legacy.checkInRecords = [Object.assign(new checkInModel.CheckInRecord(), {
  itemId: 'reading', key: '2026-10-25', name: '旧阅读', nameVersion: 0, useRange: true,
  rangeStart: 279, rangeEnd: 288, status: 'completed'
})];
const history = new model.HistoryEntry(); history.date = '2026-10-25';
history.tasks = [Object.assign(new model.Task(), {
  id: 'linked', checkInId: 'reading', checkInKey: '2026-10-25', text: '旧显示', completed: true
})];
legacy.history = [history]; legacy.todayTasks = [ordinary.clone()];
const migrated = engine.normalizeData(JSON.parse(JSON.stringify(legacy)));
assert(migrated.checkIns[0].name === '旧阅读 289-298' && migrated.checkIns[0].step === 10, '旧独立范围只并入名称一次并保留每期数量');
assert(migrated.checkInRecords[0].rangeStart === 279 && migrated.checkInRecords[0].rangeEnd === 288 &&
  migrated.history[0].tasks[0].text === '旧阅读 279-288', '历史数字列保持原值且关联日程采用自己的周期快照');
assert(JSON.stringify(engine.normalizeData(JSON.parse(JSON.stringify(migrated)))) === JSON.stringify(migrated), 'JSON往返后二次迁移完全幂等不重复追加数字');
legacy.checkIns[0].name = '背单词289-298';
assert(engine.normalizeData(JSON.parse(JSON.stringify(legacy))).checkIns[0].name === '背单词289-298', '旧名称已有明确范围时迁移不追加重复数字');
legacy.checkIns[0].deleted = true;
const purged = engine.normalizeData(JSON.parse(JSON.stringify(legacy)));
assert(purged.checkIns.length === 0 && purged.checkInRecords.length === 0 && purged.history.length === 0 &&
  purged.todayTasks.length === 1 && purged.todayTasks[0].id === 'ordinary', '旧版删除标记迁移清理全部关联数据并保留普通任务');


// 未来预测与历史入口都执行真实组件方法，不创建临时未来日程。
const chronology = newView();
update(chronology, 'CHECKIN_SAVE', { checkIn: newItem({ autoIncrement: true }) });
const chronologyEvents = []; chronology.onSheetChange = shown => chronologyEvents.push(shown);
chronology.openDetail(chronology.itemById('reading'));
const chronologyBefore = JSON.stringify(chronology.data);
const descendingBefore = chronology.selectedTimeline.map(record => record.key).join(',');
assert(chronology.selectedFutureTimeline.length === 30 && chronology.timelineRecord('2026-10-27').name === '背单词299-308', '详情未来区从领域预览读取下一期完整名称');
assert(chronology.recordContentFromView('2026-10-28') === '背单词309-318' &&
  chronology.recordStatusFromView('2026-10-28') === '未来计划', '真实未来行按日期显示推算内容与未来状态');
const orderedKeys = chronology.orderedTimeline().map(record => record.key);
assert(orderedKeys[0] === '2026-10-24' && orderedKeys.every((key, index) => index === 0 || orderedKeys[index - 1] < key), '详情时间线历史在上未来在下并保持日期递增');
assert(chronology.selectedTimeline.map(record => record.key).join(',') === descendingBefore &&
  chronology.timelineAnchorIndex() === 1 + orderedKeys.indexOf(chronology.today()), '展示排序不修改过去降序缓存，初始定位到今天');
chronology.futureLimit = 60;
assert(chronology.selectedFutureTimeline.length === 60 && JSON.stringify(chronology.data) === chronologyBefore, '扩展未来预览只刷新派生状态，不改变日程或持久数据');
const noHistoryAnimation = chronology.testAnimations || 0;
chronology.recordClickFromView('2026-10-27'); chronology.recordClickFromView('2026-10-26');
chronology.openHistory('2026-10-23');
assert(chronology.modal === 'detail' && (chronology.testAnimations || 0) === noHistoryAnimation, '未来、今天和计划开始前日期均不能进入历史页');
chronology.recordClickFromView('2026-10-24');
assert(chronology.modal === 'history' && chronology.recordKey === '2026-10-24' && chronology.sheetShown &&
  chronology.titleFromView() === '历史计划', '过去有效周期通过真实行点击打开同一弹层历史页');
const weeklyHistory = newView();
update(weeklyHistory, 'CHECKIN_SAVE', { checkIn: newItem({ frequency: 'weekly', weekdays: [1, 3], startDate: '2026-10-01' }) });
weeklyHistory.openDetail(weeklyHistory.itemById('reading')); weeklyHistory.openHistory('2026-10-25');
assert(weeklyHistory.modal === 'detail' && !weeklyHistory.recordKey, '过去非频率周期也不能打开历史项');
chronology.backToDetail();
const advanceAnimations = chronology.testAnimations || 0; const advanceSheetEvents = chronologyEvents.length;
const currentNameBeforeAdvance = chronology.selected().name;
const tasksBeforeAdvance = JSON.stringify([chronology.data.todayTasks, chronology.data.futureTasks, chronology.data.history]);
chronology.futureToggleFromView('2026-10-28');
assert(!chronology.actionError && chronology.timelineRecord('2026-10-28').advanced &&
  chronology.recordContentFromView('2026-10-28') === '背单词309-318', '真实提前动作保存该日期名称快照并刷新未来行');
assert(chronology.modal === 'detail' && chronology.sheetShown && chronologyEvents.length === advanceSheetEvents &&
  (chronology.testAnimations || 0) === advanceAnimations && chronology.selectedId === 'reading', '提前打卡留在详情，不重开弹层或触发子页跳转');
assert(JSON.stringify([chronology.data.todayTasks, chronology.data.futureTasks, chronology.data.history]) === tasksBeforeAdvance &&
  chronology.selected().name === currentNameBeforeAdvance, '提前完成不生成未来日程，也不改变今日任务和当前数字');
const afterAdvance = JSON.stringify(chronology.data);
assert(chronology.recordStatusFromView('2026-10-28') === '已提前打卡' && !!chronology.advance('2026-10-28') &&
  JSON.stringify(chronology.data) === afterAdvance, '未来完成状态立即更新且重复提前操作被拒绝');
assert(!!chronology.advance('2026-10-26') && JSON.stringify(chronology.data) === afterAdvance, '提前动作拒绝今天及过去的入口误用');
chronology.futureToggleFromView('2026-10-28');
const undoneFuture = chronology.timelineRecord('2026-10-28');
assert(!chronology.actionError && undoneFuture.status === 'ready' && !undoneFuture.advanced && !undoneFuture.completedAt &&
  chronology.recordStatusFromView('2026-10-28') === '未来计划', '真实未来按钮第二次点击撤销提前完成并立即刷新状态');
assert(undoneFuture.name === '背单词309-318' && chronology.data.checkInRecords.filter(record =>
  record.itemId === 'reading' && record.key === '2026-10-28').length === 1, '撤销保留同一期名称快照且没有重复周期');
assert(JSON.stringify([chronology.data.todayTasks, chronology.data.futureTasks, chronology.data.history]) === tasksBeforeAdvance &&
  chronology.selected().name === currentNameBeforeAdvance && chronology.metricFromView('selected', 'completed') === '0',
  '未来撤销不生成或移动日程，不改变当前名称和截至今天的统计');
assert(chronology.modal === 'detail' && chronology.sheetShown && chronologyEvents.length === advanceSheetEvents &&
  (chronology.testAnimations || 0) === advanceAnimations, '未来撤销留在原时间线，不触发弹层或页面进退');
chronology.futureToggleFromView('2026-10-28');
assert(chronology.timelineRecord('2026-10-28').status === 'completed' && chronology.timelineRecord('2026-10-28').advanced &&
  chronology.timelineRecord('2026-10-28').name === undoneFuture.name && chronology.data.checkInRecords.filter(record =>
  record.itemId === 'reading' && record.key === '2026-10-28').length === 1, '撤销后第三次点击重新提前完成原周期，不增加记录');
assert(JSON.stringify([chronology.data.todayTasks, chronology.data.futureTasks, chronology.data.history]) === tasksBeforeAdvance &&
  chronology.selected().name === currentNameBeforeAdvance, '未来完成撤销往返始终保持日程隔离和当前进度');
const pausing = newView();
for (const id of ['a', 'b', 'c']) update(pausing, 'CHECKIN_SAVE', { checkIn: newItem({ id, name: id, startDate: '2026-10-26' }) });
pausing.openDetail(pausing.itemById('b'));
const pauseAnimationCount = pausing.testAnimations || 0;
pausing.pauseSelected();
assert(pausing.selected().paused && pausing.buttonFromView('暂停', 'checkin-pause-resume') === '已暂停' &&
  !pausing.testDialogs && pausing.modal === 'detail' && pausing.sheetShown, '暂停直接执行且显示已暂停，不请求确认或离开详情');
pausing.pauseSelected();
assert(!pausing.selected().paused && !pausing.testDialogs && pausing.todayItems().map(item => item.id).join(',') === 'a,b,c' &&
  (pausing.testAnimations || 0) === pauseAnimationCount, '再次点击恢复计划，无确认且恢复今日原有顺序');
assert(!viewSource.includes('CHECKIN_SKIP') && !builderSource('recordRow').includes('跳过'), '打卡视图移除跳过操作，未完成周期保留在时间线');

// 前后台保护执行 Index 的真实读取、派发和持久化方法；只替换磁盘、动画与卡片服务。
const indexPath = path.join(project, 'entry/src/main/ets/pages/Index.ets');
const indexSource = readFileSync(indexPath, 'utf8');
function indexMethod(name) {
  const match = new RegExp('  private (?:async )?' + name + '\\(').exec(indexSource);
  if (!match) throw new Error('缺少 Index 方法：' + name);
  const end = indexSource.indexOf('\n  }', match.index);
  if (end < 0) throw new Error('Index 方法边界已变化：' + name);
  return indexSource.slice(match.index, end + '\n  }'.length);
}
const indexContext = vm.createContext({
  ...model, ...engine, ...checkInEngine,
  todayKey: () => '2026-10-26',
  Motion: { theme: () => ({}), spring: () => ({}) },
  console: { warn() {}, error() {} }
});
const indexClassSource = 'class IndexForegroundHarness {\n' +
  ['foregroundChanged', 'adoptExternalChange', 'checkDate', 'dispatch', 'persist'].map(indexMethod).join('\n') +
  '\n}\nglobalThis.IndexForegroundHarness = IndexForegroundHarness;';
vm.runInContext(transpile(indexClassSource, indexPath), indexContext, { filename: indexPath });
function newIndexForeground() {
  const result = new indexContext.IndexForegroundHarness();
  Object.assign(result, {
    context: {}, ready: true, saving: false, saveRevision: 0, saveError: '',
    foregroundSyncPending: false, sheetShown: true, checkInSheetShown: true,
    dragId: '', dragIsGroup: false, splitRatio: 0.45, events: [], deferredSaves: [],
    readError: false, deferSave: false, data: initialData()
  });
  result.adoptedRaw = JSON.stringify(result.data);
  result.diskRaw = result.adoptedRaw;
  result.resetDrag = () => { result.dragId = ''; result.dragIsGroup = false; };
  result.updatePalette = () => { result.events.push({ type: 'palette' }); };
  result.restoreAnchor = () => {};
  result.checkInFeedback = () => {};
  result.syncForm = () => { result.events.push({ type: 'form' }); };
  result.getUIContext = () => ({ animateTo: (_options, callback) => callback() });
  result.storage = {
    readRaw: async () => {
      result.events.push({ type: 'read' });
      if (result.readError) throw new Error('模拟卡片文件读取失败');
      return result.diskRaw;
    },
    save: async (_context, data) => {
      const serialized = JSON.stringify(data);
      result.events.push({ type: 'save', serialized });
      if (result.deferSave) await new Promise(resolve => {
        result.deferredSaves.push(() => { result.diskRaw = serialized; resolve(); });
      });
      else result.diskRaw = serialized;
    }
  };
  // 包装只记录调用顺序，内部仍执行从 Index 提取的原方法。
  const checkDate = result.checkDate.bind(result);
  result.checkDate = () => { result.events.push({ type: 'date' }); return checkDate(); };
  const dispatch = result.dispatch.bind(result);
  result.dispatch = value => {
    result.events.push({ type: 'dispatch', action: value.type, serialized: JSON.stringify(result.data) });
    return dispatch(value);
  };
  return result;
}
const flushMicrotasks = () => new Promise(resolve => setImmediate(resolve));
const foreground = newIndexForeground();
let cardData = engine.reduce(initialData(), action('CHECKIN_SAVE', { checkIn: newItem() }));
cardData = engine.reduce(cardData, action('CHECKIN_COMPLETE', { id: 'reading', key: '2026-10-26' }));
foreground.diskRaw = JSON.stringify(cardData);
await foreground.foregroundChanged();
await flushMicrotasks();
assert(foreground.data.checkInRecords[0].status === 'completed', '两种弹层打开时仍采纳卡片已完成状态');
const firstSync = foreground.events.find(event => event.type === 'dispatch');
assert(firstSync?.action === 'CHECKIN_SYNC' &&
  JSON.parse(firstSync.serialized).checkInRecords[0].status === 'completed' &&
  foreground.events.findIndex(event => event.type === 'read') < foreground.events.findIndex(event => event.type === 'date'),
  '读取并采纳卡片改动发生在日期检查和打卡同步之前');
assert(JSON.parse(foreground.events.find(event => event.type === 'save').serialized).checkInRecords[0].status === 'completed',
  '真实派发和持久化链路不会把卡片完成状态覆盖为旧值');
const sameData = foreground.data;
assert(await foreground.adoptExternalChange() === true && foreground.data === sameData, '相同磁盘快照返回成功且不替换内存数据');

const unavailable = newIndexForeground();
unavailable.context = undefined;
assert(await unavailable.adoptExternalChange() === false && unavailable.events.length === 0, '缺少上下文时明确读取失败且不访问存储');
unavailable.context = {}; unavailable.saving = true;
assert(await unavailable.adoptExternalChange() === false && unavailable.events.length === 0, '保存期间直接采纳请求返回失败且不读旧文件');

const failedRead = newIndexForeground();
failedRead.readError = true;
const beforeReadFailure = failedRead.data;
await failedRead.foregroundChanged();
await flushMicrotasks();
assert(failedRead.data === beforeReadFailure && failedRead.events.every(event => event.type === 'read'),
  '读取抛异常时不检查日期、不派发、不写盘或推送旧卡片数据');
const malformedRead = newIndexForeground();
malformedRead.diskRaw = '{invalid';
await malformedRead.foregroundChanged();
assert(malformedRead.events.every(event => event.type === 'read'), '文件解析失败同样中止后续同步与写入');
const emptyRead = newIndexForeground();
emptyRead.diskRaw = '';
await emptyRead.foregroundChanged();
assert(emptyRead.events.every(event => event.type === 'read'), '空文件读取不会触发旧内存持久化');

const delayed = newIndexForeground();
delayed.saving = true;
await delayed.foregroundChanged();
assert(delayed.foregroundSyncPending && delayed.events.length === 0, '已有保存未完成时记录待同步并跳过读取派发');
await delayed.persist();
await flushMicrotasks();
assert(delayed.events.filter(event => event.type === 'read').length === 1 &&
  delayed.events.filter(event => event.type === 'dispatch').length === 1, '最新保存完成后自动补做一次读取和打卡同步');
assert(!delayed.foregroundSyncPending && !delayed.saving, '补同步完成后清除待同步与保存状态');

const revisions = newIndexForeground();
revisions.deferSave = true;
const firstSave = revisions.persist();
const secondSave = revisions.persist();
await revisions.foregroundChanged();
revisions.deferredSaves[0]();
await firstSave;
assert(revisions.saving && revisions.foregroundSyncPending && !revisions.events.some(event => event.type === 'read'),
  '较早保存版本完成时不能提前恢复前台同步');
revisions.deferSave = false;
revisions.deferredSaves[1]();
await secondSave;
await flushMicrotasks();
assert(!revisions.foregroundSyncPending && revisions.events.filter(event => event.type === 'read').length === 1,
  '只有最新保存版本完成才解除延后状态并重新采纳磁盘数据');

console.log('\n打卡视图回归通过：' + passed + ' 项。');

