// 执行真实补卡组件方法、Builder 表达式与回调；不模拟 ArkUI 渲染或设备触摸。
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
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    reportDiagnostics: true, fileName: filename
  });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(item => item.messageText).join('\n'));
  return result.outputText;
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
const { CheckInItem, CheckInRecord, CheckInPause } = checkInModel;
const filename = path.join(project, 'entry/src/main/ets/components/CheckInBackfill.ets');
const source = readFileSync(filename, 'utf8');
function builder(name) {
  const start = source.indexOf('@Builder private ' + name + '(');
  if (start < 0) throw new Error('缺少真实 Builder：' + name);
  const end = source.indexOf('@Builder', start + 1);
  return source.slice(start, end < 0 ? undefined : end);
}
function required(text, regex, label) {
  const found = text.match(regex);
  if (!found) throw new Error('真实组件结构变化：' + label);
  return found[1];
}
function textExpression(name, index) {
  const values = Array.from(builder(name).matchAll(/\bText\((.+)\)\.fontSize\(/g), match => match[1]);
  if (!values[index]) throw new Error('缺少真实文案表达式：' + name);
  return values[index];
}
const componentStart = source.indexOf('@Component');
const componentEnd = source.indexOf('  @Builder', componentStart);
const methods = source.slice(componentStart, componentEnd);
const watches = Array.from(methods.matchAll(/@Watch\('([^']+)'\)\s+(?:private\s+)?(\w+)/g),
  match => ({ method: match[1], field: match[2] }));
const touch = required(builder('dateCell'), /\.onTouch\(\(event: TouchEvent\) => \{ ([^}]+) \}\)/, '日历触摸回调');
const click = required(builder('dateCell'), /\.onClick\(\(\) => \{ ([^}]+) \}\)/, '日历点击回调');
const submitClick = required(builder('confirmButton'), /\.onClick\(\(\) => \{ ([^}]+) \}\)/, '提交回调');
const enabled = required(builder('confirmButton'), /\.enabled\((.+)\)/, '提交可用条件');
const scale = required(builder('dateCell'), /\.scale\(\{ x: (.+), y:/, '日期按压缩放');
const feedbackSource = readFileSync(path.join(project, 'entry/src/main/ets/theme/Appearance.ets'), 'utf8');
const feedback = feedbackSource.slice(feedbackSource.indexOf('export class ButtonFeedback'),
  feedbackSource.indexOf('const controlMaterials:')).replace('export class', 'class');
const classSource = feedback + '\n' + methods
  .replace('@Component', '').replace('export struct CheckInBackfill', 'class CheckInBackfill')
  .replace(/@Watch\('[^']+'\)\s*/g, '').replace(/@(?:Prop|State)\s+/g, '') +
  '\ngetUIContext() { return { animateTo: (options, change) => { this.animations = (this.animations || 0) + 1; change(); if(options.onFinish) options.onFinish(); } }; }\n' +
  'dayFromView(index, calendarMonth) { return ' + textExpression('dateCell', 0) + '; }\n' +
  'statusFromView(index, calendarMonth) { return ' + textExpression('dateCell', 1) + '; }\n' +
  'monthFromView() { return ' + textExpression('calendarSection', 0) + '; }\n' +
  'selectedNameFromView() { return ' + textExpression('nameSection', 1) + '; }\n' +
  'editableFromView() { return ' + required(builder('nameSection'), /if \((this\.canEditSelected\(\))\)/, '编辑可用条件') + '; }\n' +
  'enabledFromView() { return ' + enabled + '; }\n' +
  'labelFromView() { return ' + required(builder('confirmButton'), /Button\((this\.submitLabel\(\)),/, '提交按钮标题') + '; }\n' +
  'touchFromView(index, calendarMonth, event) { ' + touch + ' }\n' +
  'clickFromView(index, calendarMonth) { ' + click + ' }\n' +
  'submitFromView() { ' + submitClick + ' }\n' +
  'scaleFromView(index, calendarMonth) { return ' + scale + '; }\n' +
  '}\nglobalThis.ComponentClass = CheckInBackfill;';
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const context = vm.createContext({
  ...model, ...checkInModel, ...engine, ...checkInEngine,
  Palette: class {}, Scroller: class {}, TouchType,
  Motion: { quick: () => ({}) }, EditorMaterialRefresh: { request: () => {} }
});
vm.runInContext(transpile(classSource, filename), context, { filename });
function installWatches(instance) {
  for (const binding of watches) {
    let value = instance[binding.field];
    Object.defineProperty(instance, binding.field, {
      get: () => value, set(next) {
        if (Object.is(value, next)) return;
        value = next; instance[binding.method]();
      }
    });
  }
}
function fixture(fields = {}) {
  const data = new AppData();
  data.currentDate = data.lastRolloverDate = '2026-10-27';
  data.checkIns = [Object.assign(new CheckInItem(), {
    id: 'reading', name: '背单词289-298', startDate: '2026-10-01', step: 10, ...fields
  })];
  return data;
}
function record(key, fields = {}) {
  return Object.assign(new CheckInRecord(), {
    itemId: 'reading', key, name: '背单词269-278', status: 'ready', generatedAt: key + 'T08:00:00', ...fields
  });
}
function create(data = fixture(), initialDate = '') {
  const instance = new context.ComponentClass();
  installWatches(instance);
  instance.data = data; instance.itemId = 'reading'; instance.initialDate = initialDate;
  instance.onComplete = (key, name) => {
    instance.calls = (instance.calls || 0) + 1;
    const action = Object.assign(new AppAction('CHECKIN_BACKFILL'), { id: instance.itemId, key, text: name });
    const error = checkInEngine.validateCheckInAction(instance.data, action);
    if (!error) instance.data = engine.reduce(instance.data, action);
    return error;
  };
  instance.onAdvance = key => {
    instance.advanceCalls = (instance.advanceCalls || 0) + 1;
    const action = Object.assign(new AppAction('CHECKIN_ADVANCE'), { id: instance.itemId, key });
    const error = checkInEngine.validateCheckInAction(instance.data, action);
    if (!error) instance.data = engine.reduce(instance.data, action);
    return error;
  };
  instance.aboutToAppear();
  return instance;
}
function indexOfDay(instance, day) {
  for (let i = 0; i < 42; i++) if (instance.day(i, instance.monthKey()) === day) return i;
  throw new Error('日期不在当前月');
}
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++; console.log('✓ ' + message);
}
const instance = create();
assert(instance.monthFromView() === '2026 年 10 月', '补卡页默认显示真实业务日期所在月份');
assert(instance.dayFromView(indexOfDay(instance, 31), instance.monthKey()) === '31', '真实日期文案完整保留两位数');
assert(instance.day(0, '2026-10') === 0 && instance.day(3, '2026-10') === 1, '日历以周一开头且正确留出首周空格');
assert(instance.visibleRows('2026-08').length === 6 && instance.visibleRows('2027-02').length === 4, '月份自动显示四到六周且不裁掉最后一周');
assert(instance.validDate('2024-02-29') && !instance.validDate('2025-02-29') && !instance.validDate('2026-02-30'), '闰年与无效日期使用真实日期校验');
assert(instance.statusFromView(indexOfDay(instance, 26), instance.monthKey()) === '未完成', '未生成的有效过去周期标为未完成');
assert(instance.statusFromView(indexOfDay(instance, 27), instance.monthKey()) === '待打卡', '今天标为待打卡');
assert(instance.statusFromView(indexOfDay(instance, 28), instance.monthKey()) === '未到期', '未来周期标为未到期');
instance.selectDate('2026-10-27');
assert(!instance.enabledFromView() && instance.error.includes('今天'), '今天不可补卡并给出具体说明');
instance.selectDate('2026-10-28');
assert(instance.enabledFromView() && !instance.editableFromView() && !instance.error, '有效未来日期允许提前打卡但不能编辑内容');
assert(instance.selectedNameFromView() === '背单词289-298', '关闭自动递增的未来周期沿用固定名称');
instance.selectDate('2026-09-30');
assert(!instance.enabledFromView() && instance.error === '' && instance.selectedNameFromView() === '当日无打卡项', '开始日期前只显示当日无打卡项且禁止补卡');
instance.selectDate('2026-10-26');
assert(instance.editableFromView() && !instance.enabledFromView() && instance.draftName === '', '无历史快照的有效过去日期留空内容且禁用直接提交');
assert(instance.editableFromView() && instance.data.checkInRecords.length === 0, '有效未生成周期直接编辑名称且不伪造历史快照');
instance.submitFromView();
assert(instance.error.includes('请输入') && !instance.calls && instance.data.checkInRecords.length === 0 &&
  instance.data.checkIns[0].name === '背单词289-298', '无快照过去日期直接提交不会把当前数字写成历史内容');
instance.draftName = '   ';
instance.submitFromView();
assert(instance.error.includes('请输入') && !instance.calls, '空白名称不会派发补卡');
instance.draftName = ' 背单词279-288 ';
instance.pressedButton = 'submit';
instance.submitFromView();
assert(instance.calls === 1 && !instance.pressedButton && !instance.selectedDate && !instance.draftName, '提交先清按压状态，成功留页并清除本次选择');
assert(instance.statusFromView(indexOfDay(instance, 26), instance.monthKey()) === '已补卡', '同一组件补卡成功后当前月状态立即刷新');
assert(instance.recordFor('2026-10-26').name === '背单词279-288' && instance.data.checkIns[0].name === '背单词289-298', '完整确认内容写入该周期且不推进当前计划');
assert(instance.notice.includes('已补卡') && !instance.submitting, '成功提示支持继续补下一天且释放提交保护');
instance.selectDate('2026-10-26');
instance.submitFromView();
assert(instance.error.includes('已补卡') && instance.calls === 1, '重复补卡在真实提交前拦截');
assert(instance.selectedNameFromView() === '背单词279-288' && !instance.editableFromView(), '已补卡日期以只读形式显示原历史名称');
const changed = instance.data.clone();
changed.checkInRecords.push(record('2026-10-25', { status: 'completed' }));
instance.data = changed;
assert(instance.statusFromView(indexOfDay(instance, 25), instance.monthKey()) === '已完成', '外部完成更新同一组件的真实日期状态');
instance.selectDate('2026-10-25');
assert(instance.error.includes('已完成') && !instance.enabledFromView(), '普通已完成日期也禁止重复补卡');
assert(instance.selectedNameFromView() === '背单词269-278' && !instance.editableFromView(), '已完成日期显示原历史名称，不展示当前计划的新数字');
const snapshotData = fixture();
snapshotData.checkInRecords = [record('2026-10-24')];
const snapshot = create(snapshotData, '2026-10-24');
assert(snapshot.draftName === '背单词269-278' && snapshot.editableFromView(), '带未完成周期进入时直接编辑自己的历史名称');
snapshot.draftName = '背单词268-277（修正）';
const latestData = snapshot.data.clone();
latestData.checkIns[0].name = '背单词299-308';
snapshot.data = latestData;
assert(snapshot.draftName === '背单词268-277（修正）' && snapshot.recordFor('2026-10-24').name === '背单词269-278', '外部数字前进不覆盖正在确认的历史草稿或旧快照');
snapshot.submitFromView();
assert(snapshot.recordFor('2026-10-24').name === '背单词268-277（修正）' && snapshot.data.checkIns[0].name === '背单词299-308', '手改补卡名称只作用于所选历史周期');
snapshot.selectDate('2026-10-23');
snapshot.draftName = '保留待提交草稿';
snapshot.onComplete = () => '存储操作暂未完成';
snapshot.submitFromView();
assert(snapshot.error === '存储操作暂未完成' && snapshot.draftName === '保留待提交草稿' && !snapshot.submitting, '父级返回错误时保留草稿供重试');
snapshot.onComplete = () => { throw new Error('模拟失败'); };
snapshot.submitFromView();
assert(snapshot.error.includes('重试') && snapshot.selectedDate === '2026-10-23' && !snapshot.submitting, '异常不会丢草稿或锁死提交状态');
snapshot.submitting = true; let repeated = false;
snapshot.onComplete = () => { repeated = true; return ''; };
snapshot.submitFromView();
assert(!repeated, '提交保护阻止重入');
snapshot.submitting = false;
const weekly = create(fixture({ frequency: 'weekly', weekdays: [1, 3, 5] }));
assert(!weekly.selectionError('2026-10-26') && !!weekly.selectionError('2026-10-25'), '每周频率仅允许指定周几');
weekly.selectDate('2026-10-25');
assert(weekly.selectedNameFromView() === '当日无打卡项' && !weekly.error && !weekly.editableFromView(), '非周期日期只显示无打卡项而不重复底部长提示');
const monthly = create(fixture({ startDate: '2026-01-01', frequency: 'monthly', monthDays: [15, 31] }));
assert(!monthly.selectionError('2026-10-15') && !!monthly.selectionError('2026-10-14') && !monthly.validDate('2026-09-31'), '每月频率和缺失日期正确限制补卡');
const pausedData = fixture({ paused: true, pauses: [Object.assign(new CheckInPause(), { from: '2026-10-20', to: '2026-10-24' }), Object.assign(new CheckInPause(), { from: '2026-10-27' })] });
const paused = create(pausedData);
assert(!paused.selectionError('2026-10-19') && paused.selectionError('2026-10-20').includes('暂停') && !paused.selectionError('2026-10-24'), '暂停起止边界沿用领域规则且恢复当天有效');
const oldTaskData = fixture({ pauses: [Object.assign(new CheckInPause(), { from: '2026-10-20' })] });
oldTaskData.checkInRecords = [record('2026-10-21')];
const oldTask = create(oldTaskData);
assert(!oldTask.selectionError('2026-10-21') && !!oldTask.selectionError('2026-10-22'), '暂停前已生成任务保留补卡资格，空白暂停日不可补');
const external = create();
external.selectDate('2026-10-22'); external.draftName = '历史内容';
const externallyDone = external.data.clone();
externallyDone.checkInRecords.push(record('2026-10-22', { status: 'completed' }));
external.data = externallyDone; external.submitFromView();
assert(external.error.includes('已完成') && !external.calls, '选中后外部完成同日会在提交时重新拦截');
assert(!external.editableFromView() && external.selectedNameFromView() === '背单词269-278', '外部完成刷新后切换为只读历史快照，不保留过时编辑显示');
external.data = fixture(); external.selectDate('2026-10-21');
const deleted = external.data.clone(); deleted.checkIns = []; external.data = deleted;
external.submitFromView();
assert(external.error.includes('不存在') && !external.calls, '外部删除计划后原页面不会提交失效补卡');
const month = create();
month.moveMonth(-1);
assert(month.monthFromView() === '2026 年 9 月' && month.animations > 0, '切换月份通过实际布局动画更新标题');
const monthData = month.data.clone();
monthData.checkInRecords.push(record('2026-09-30', { status: 'completed', backfilled: true }));
month.data = monthData;
assert(month.statusFromView(indexOfDay(month, 30), month.monthKey()) === '已补卡', '跨月缓存随数据变化刷新已补卡状态');
month.moveMonth(1);
assert(month.recordFor('2026-09-30').backfilled, '退出中的旧月份仍按自己的日期读取记录');
month.year = 9999; month.month = 11; month.moveMonth(1);
assert(month.year === 9999 && month.month === 11, '月份上界不会生成不可解析的五位年');
const press = create();
const index = indexOfDay(press, 26); const calendarMonth = press.monthKey();
press.touchFromView(index, calendarMonth, { type: TouchType.Down });
assert(press.scaleFromView(index, calendarMonth) === 0.97, '真实日期触摸回调按下后只缩放');
press.touchFromView(index, calendarMonth, { type: TouchType.Cancel });
assert(press.scaleFromView(index, calendarMonth) === 1, '触摸取消恢复日期大小');
press.touchFromView(index, calendarMonth, { type: TouchType.Down });
press.clickFromView(index, calendarMonth);
assert(!press.pressedButton && press.selectedDate === '2026-10-26', '真实日期点击先释放按压再选择日期');
press.pressedButton = 'submit'; press.aboutToDisappear();
assert(!press.pressedButton, '离开补卡页清除残留按压反馈');
assert(!source.includes('calendarShown') && builder('calendarSection').includes('this.visibleRows(calendarMonth)'), '补卡专属日历始终展开并渲染完整月份');
assert((source.match(/viewportId: 'checkin-backfill-scroll'/g) || []).length === 2 && source.includes(".id('checkin-backfill-scroll')"), '两个圆角材质区绑定补卡页自己的滚动视口');
assert(source.includes("label: '返回打卡', buttonId: 'checkin-backfill-back'") && source.includes(".id('checkin-backfill-name')"), '补卡返回按钮与输入框具有独立标识');
assert(!source.includes('核对这一天') && !source.includes('已填入本期') && !source.includes('补卡不改变当前进度'), '选日期后不再显示核对、已填入或不改变进度的提示');
assert(builder('bottomFade').includes('.blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)') && !builder('bottomFade').includes('this.palette'), '渐隐只使用透明度混合，不新增主题色背景');
const buildSource = source.slice(source.indexOf('  build() {'));
assert(buildSource.indexOf('this.bottomFade()') < buildSource.indexOf('BlendMode.SRC_OVER') &&
  buildSource.indexOf('BlendMode.SRC_OVER') < buildSource.indexOf("if (this.error)"), '固定错误提示处于滚动渐隐合成作用域之外');
assert((buildSource.match(/Divider\(\)/g) || []).length === 1 && buildSource.includes('bottom: 40'), '底栏移除硬切分割线并为末尾内容保留足够渐隐留白');

const advance = create(fixture({ autoIncrement: true, rangeUpdatedFor: '2026-10-27' }));
const beforePreview = JSON.stringify(advance.data);
advance.selectDate('2026-10-28');
assert(advance.selectedNameFromView() === '背单词299-308', '未来第一周期显示下一段完整名称');
advance.selectDate('2026-10-29');
assert(advance.selectedNameFromView() === '背单词309-318', '未来第二周期名称按有效日期累计递增');
assert(JSON.stringify(advance.data) === beforePreview, '切换未来日期只读预览，不保存快照或生成任务');
assert(!advance.editableFromView() && advance.draftName === '' && advance.enabledFromView() && advance.labelFromView() === '提前打卡', '未来有效日只读且使用独立提前打卡按钮');
advance.draftName = '不能替换的手改名称';
advance.submitFromView();
assert(advance.advanceCalls === 1 && !advance.calls && advance.recordFor('2026-10-29').advanced &&
  advance.recordFor('2026-10-29').name === '背单词309-318', '提前打卡只传日期并保存推荐投影，忽略编辑草稿');
assert(advance.data.checkIns[0].name === '背单词289-298' && advance.data.todayTasks.length === 0 &&
  advance.data.futureTasks.length === 0, '提前完成不推进当前名称也不生成今日或未来任务');
assert(advance.selectedDate === '2026-10-29' && !advance.enabledFromView() &&
  !advance.editableFromView() && advance.labelFromView() === '已提前打卡', '提前成功保留选中日期并禁用重复操作');
assert(advance.statusFromView(indexOfDay(advance, 29), advance.monthKey()) === '已提前打卡', '同一日历日期在提前完成后立即刷新状态');
advance.submitFromView();
assert(advance.advanceCalls === 1 && advance.error.includes('已提前打卡'), '重复提前完成在视图提交前拦截');
const changedAdvance = advance.data.clone(); changedAdvance.checkIns[0].name = '背单词399-408'; advance.data = changedAdvance;
assert(advance.selectedNameFromView() === '背单词309-318', '编辑当前计划不回写已提前完成日期的名称快照');
advance.selectDate('2026-10-28');
assert(advance.selectedNameFromView() === '背单词409-418', '尚未完成的未来日期重新读取最新计划投影');
const singleFuture = create(fixture({ name: '看网课第10节', step: 1, autoIncrement: true, rangeUpdatedFor: '2026-10-27' }));
singleFuture.selectDate('2026-10-29');
assert(singleFuture.selectedNameFromView() === '看网课第12节', '单编号名称随未来有效周期递增');
const weeklyFuture = create(fixture({ frequency: 'weekly', weekdays: [1, 3, 5], autoIncrement: true, rangeUpdatedFor: '2026-10-26' }));
weeklyFuture.selectDate('2026-10-30');
assert(weeklyFuture.selectedNameFromView() === '背单词309-318', '每周未来名称跳过非周期日期');
const monthlyFuture = create(fixture({ frequency: 'monthly', monthDays: [15, 31], autoIncrement: true, rangeUpdatedFor: '2026-10-15' }));
monthlyFuture.selectDate('2026-11-15');
assert(monthlyFuture.selectedNameFromView() === '背单词309-318', '每月未来名称按指定月日接续区间');
const pausedFuture = create(fixture({ pauses: [Object.assign(new CheckInPause(), { from: '2026-10-28' })] }));
pausedFuture.selectDate('2026-10-29');
assert(pausedFuture.selectedNameFromView() === '当日无打卡项' && !pausedFuture.enabledFromView(), '暂停范围中的未来日期不提供提前操作');
const overflowFuture = create(fixture({ name: '看网课第9007199254740991节', step: 1, autoIncrement: true, rangeUpdatedFor: '2026-10-27' }));
overflowFuture.selectDate('2026-10-28'); overflowFuture.submitFromView();
assert(!overflowFuture.enabledFromView() && overflowFuture.error.includes('调整计划') && !overflowFuture.advanceCalls, '未来推算溢出时禁用提前打卡并提示调整计划');
const failedAdvance = create(fixture());
failedAdvance.selectDate('2026-10-28'); failedAdvance.onAdvance = () => '写入暂未完成'; failedAdvance.submitFromView();
assert(failedAdvance.error === '写入暂未完成' && failedAdvance.selectedDate === '2026-10-28' &&
  !failedAdvance.recordFor('2026-10-28') && !failedAdvance.submitting, '提前操作失败保留选中日期且不伪装完成');
failedAdvance.onAdvance = () => { throw new Error('模拟失败'); }; failedAdvance.submitFromView();
assert(failedAdvance.error.includes('提前打卡未完成') && !failedAdvance.submitting, '提前操作异常给出对应错误并释放提交保护');

console.log('\n全部通过：' + passed + ' 个断言。');

