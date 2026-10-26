// 打卡领域真实引擎回归：日期、递增、历史与日程联动，不写入真实应用数据。
// 运行：node scripts/test-checkin.mjs；TypeScript 可由 TYPESCRIPT_PATH 指定。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
const locations = [process.env.TYPESCRIPT_PATH, 'typescript', path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/tools/node_modules/typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'];
for (const location of locations.filter(Boolean)) {
  try { ts = require(location); break; } catch { /* 尝试下一个已安装工具链 */ }
}
if (!ts) throw new Error('请安装 TypeScript 或设置 TYPESCRIPT_PATH 指向已有 TypeScript 模块。');
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const source = readFileSync(path.join(project, 'entry/src/main/ets/model', `${name}.ets`), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true });
  const errors = (output.diagnostics || []).filter(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, { getCurrentDirectory: () => project, getCanonicalFileName: file => file, getNewLine: () => '\n' }));
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output.outputText}\n})`, { filename: `${name}.ets` })(
    request => load(path.basename(request)), module, module.exports);
  cache.set(name, module.exports);
  return module.exports;
}
const { AppData, AppAction, Task, HistoryEntry } = load('PlanerModel');
const { CheckInItem } = load('CheckInModel');
const { reduce, normalizeData, taskDelayText } = load('PlanerEngine');
const { validateCheckIn, validateCheckInAction, parseCheckInName, formatCheckInName, nextCheckInName, isCheckInDate, checkInStats, checkInTimeline, previewCheckInRecord, checkInFutureTimeline } = load('CheckInEngine');
let passed = 0;
function assert(condition, message) { if (!condition) throw new Error(message); passed++; console.log('  ✓ ' + message); }
function fresh(date = '2026-08-24') { const data = new AppData(); data.currentDate = date; data.lastRolloverDate = date; return data; }
function item(patch = {}) { return Object.assign(new CheckInItem(), { id: 'word', name: '背单词289-298', startDate: '2026-08-24', step: 10 }, patch); }
function action(type, patch = {}) { return Object.assign(new AppAction(type), patch); }
function run(data, type, patch = {}) { return reduce(data, action(type, patch)); }
function save(data, config = item()) { return run(data, 'CHECKIN_SAVE', { checkIn: config }); }
function record(data, key, id = 'word') { return data.checkInRecords.find(value => value.itemId === id && value.key === key); }
function task(data, key, id = 'word') { return data.todayTasks.find(value => value.checkInId === id && value.checkInKey === key); }
function next(data, key) { return run(data, 'ROLLOVER_TO', { key }); }
function error(data, type, patch = {}) { return validateCheckInAction(data, action(type, patch)); }

console.log('1) 名称数字识别及下一期内容');
const words = parseCheckInName('背单词289-298');
assert(words.valid && words.mode === 'range' && words.start === 289 && words.end === 298 && words.step === 10, '单词范围识别289至298，共10个数');
assert(nextCheckInName(item()) === '背单词299-308', '下一期固定10个数为299-308，不多算一个');
assert(nextCheckInName(item({ step: 5 })) === '背单词299-303', '范围允许手改每期数量');
const lesson = parseCheckInName('看网课第10节');
assert(lesson.valid && lesson.mode === 'single' && lesson.start === 10 && lesson.step === 1 && lesson.suffix === '节', '唯一单值识别并默认增加1');
assert(nextCheckInName(item({ name: '看网课第10节', step: 1 })) === '看网课第11节', '单值下一期直接更新名称');
assert(nextCheckInName(item({ name: '看网课第10节', step: 3 })) === '看网课第13节', '单值允许手改增量');
assert(nextCheckInName(item({ name: '课第009节', step: 1 })) === '课第010节', '单值递增保留前导零');
assert(nextCheckInName(item({ name: '词009-018', step: 10 })) === '词019-028', '范围两端分别保留前导零');
assert(formatCheckInName(parseCheckInName('阅读 1 至 10 页'), 11, 20) === '阅读 11 至 20 页', '保留名称前后缀及原分隔符');
assert(!parseCheckInName('2026年背词289-298').valid && !parseCheckInName('课程第2章第10节').valid, '多个数字存在歧义时不擅自选择');
assert(parseCheckInName('2026年背词289-298').error === '名称中有多组数字，若要开启自动递增/接续功能，请只保留一处数字或范围' &&
  parseCheckInName('课程第2章第10节').error === '名称中有多组数字，若要开启自动递增/接续功能，请只保留一处数字或范围', '多组数字的两种歧义路径都说明开启递增或接续的条件');
assert(!parseCheckInName('打卡').valid && !parseCheckInName('练习-10').valid && !parseCheckInName('跑步1.5公里').valid, '无数字、负数和小数不自动推断');
assert(!parseCheckInName('阅读10-1').valid && !parseCheckInName('页9007199254740992').valid, '拒绝倒序范围和非安全整数');
assert(nextCheckInName(item({ name: '第9007199254740991节', step: 1 })) === '', '下一期溢出不生成错误名称');
assert(new CheckInItem().autoIncrement === false && validateCheckIn(item({ name: '今天认真读书' })) === '', '自动递增默认关闭，普通文字名称可保存');
assert(validateCheckIn(item({ name: '今天认真读书', autoIncrement: true })) && validateCheckIn(item({ autoIncrement: true, step: 0 })), '开启自动递增后校验唯一数字和正整数数量');

console.log('2) 周期自动生成及历史快照');
let fixed = save(fresh()); fixed = next(fixed, '2026-08-25');
assert(record(fixed, '2026-08-25').name === '背单词289-298' && record(fixed, '2026-08-25').status === 'ready', '默认关闭递增，次日沿用完整名称');
let state = save(fresh(), item({ autoIncrement: true }));
assert(task(state, '2026-08-24').text === '背单词289-298' && state.futureTasks.length === 0, '首期只生成完整名称，不附独立目标或范围');
const original = state;
state = run(state, 'CHECKIN_SYNC');
assert(state.checkInRecords.length === 1 && state.todayTasks.length === 1, '重复前台同步保持周期唯一');
state = run(state, 'SELECT_DATE', { key: '2026-09-01' });
assert(state.lastRolloverDate === '2026-08-24' && state.checkInRecords.length === 1, '未来预览不会生成未来打卡');
state = run(state, 'SELECT_DATE', { key: '2026-08-24' }); state = next(state, '2026-08-25');
assert(record(state, '2026-08-25').name === '背单词299-308' && record(state, '2026-08-25').status === 'ready', '开启递增即确认规则，次日自动生成完整名称');
assert(state.checkIns[0].name === '背单词299-308' && task(state, '2026-08-25'), '真实次日自动推进名称数值并产生任务');
assert(taskDelayText(task(state, '2026-08-24'), state.currentDate, state.lastRolloverDate) === '延期 1 天', '未完成旧任务按原周期延期');
assert(!error(state, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-25' }), '自动生成后的周期可直接完成，无逐期确认步骤');
state = run(state, 'CHECKIN_SYNC');
assert(task(state, '2026-08-25').text === '背单词299-308' && state.checkIns[0].rangeStart === 299 && state.todayTasks.filter(value => value.checkInKey === '2026-08-25').length === 1, '重复同步不再次递增或生成重复任务');
assert(record(state, '2026-08-24').name === '背单词289-298' && original.checkIns[0].name === '背单词289-298', '下一期生成不重写旧记录和旧状态');
assert(error(state, 'CHECKIN_GENERATE', { id: 'word', key: '2026-08-25' }), '重复确认有明确错误');
state = run(state, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-25' }); state = next(state, '2026-08-26');
assert(state.history.some(entry => entry.tasks.some(value => value.checkInKey === '2026-08-25' && value.text === '背单词299-308')), '完成归档保留当期完整名称');
assert(record(state, '2026-08-26').name === '背单词309-318', '下一建议只基于最后确认名称');
state = run(state, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-24', text: '补记背单词269-278' });
assert(record(state, '2026-08-24').backfilled && task(state, '2026-08-24').text === '补记背单词269-278', '补卡手改当期名称并同步原关联任务');
assert(state.checkIns[0].name === '背单词309-318' && record(state, '2026-08-26').name === '背单词309-318', '补卡不推进或回退当前名称数值');
assert(error(state, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-24' }) && error(state, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-27' }), '禁止重复和未来补卡');
let automatic = save(fresh(), item({ name: '看网课第10节', autoIncrement: true, confirmNext: false, step: 1 })); automatic = next(automatic, '2026-08-25');
assert(record(automatic, '2026-08-25').name === '看网课第11节' && record(automatic, '2026-08-25').status === 'ready', '单值名称随真实周期自动递增，无需逐期确认');
let overflow = save(fresh(), item({ name: '第9007199254740991节', autoIncrement: true, confirmNext: false, step: 1 })); overflow = next(overflow, '2026-08-25');
assert(record(overflow, '2026-08-25').status === 'pending' && !task(overflow, '2026-08-25') && error(overflow, 'CHECKIN_GENERATE', { id: 'word', key: '2026-08-25' }), '溢出停止自动生成且不可直接确认');
overflow = run(overflow, 'CHECKIN_GENERATE', { id: 'word', key: '2026-08-25', text: '第1节' });
assert(record(overflow, '2026-08-25').name === '第1节' && task(overflow, '2026-08-25'), '溢出后可手改合法名称恢复');

console.log('3) 编辑、共享日程入口与节律');
let edit = save(fresh(), item({ autoIncrement: true }));
edit = save(edit, item({ ...edit.checkIns[0], name: '复习单词289-298' })); edit = next(edit, '2026-08-25');
assert(record(edit, '2026-08-24').name === '背单词289-298' && record(edit, '2026-08-25').name === '复习单词299-308', '仅改名称前后缀不会重置递增，也不重写今日快照');
edit = save(edit, item({ ...edit.checkIns[0], name: '自己安排复习', autoIncrement: false }));
assert(record(edit, '2026-08-25').status === 'ready' && task(edit, '2026-08-25').text === '复习单词299-308', '关闭递增并改名仍保留已经生成的今日快照');
edit = next(edit, '2026-08-26');
assert(task(edit, '2026-08-26').text === '自己安排复习', '关闭递增后的后续周期使用手填名称');
let shared = save(fresh()); const id = shared.todayTasks[0].id;
shared = run(shared, 'TOGGLE_TODAY', { id });
assert(record(shared, '2026-08-24').status === 'completed' && record(shared, '2026-08-24').completedAt === shared.todayTasks[0].completedAt, '普通和卡片完成共享记录和时间');
shared = run(shared, 'TOGGLE_TODAY', { id });
assert(record(shared, '2026-08-24').status === 'ready', '普通取消完成同步撤销');
shared = run(shared, 'EDIT_TASK', { id, text: '错误改名', dueDate: '2027-01-01', progress: 100 });
assert(shared.todayTasks[0].text === '背单词289-298' && record(shared, '2026-08-24').status === 'completed', '普通编辑只接受进度，不改打卡快照');
shared = run(shared, 'MOVE_TASK', { id, to: 'future', dueDate: '2027-01-01' });
assert(shared.futureTasks.length === 0 && shared.todayTasks[0].checkInKey === '2026-08-24', '领域层拒绝移入未来破坏周期');
shared = next(shared, '2026-08-25'); shared = run(shared, 'RESTORE', { id, entryDate: '2026-08-24', target: 'future' });
assert(task(shared, '2026-08-24') && record(shared, '2026-08-24').status === 'ready' && shared.futureTasks.length === 0, '历史恢复仍是原周期撤销');
shared = run(shared, 'DELETE_TASK', { id }); shared = run(shared, 'CHECKIN_SYNC');
assert(record(shared, '2026-08-24').status === 'ready' && record(shared, '2026-08-24').taskDetached && !task(shared, '2026-08-24'), '删除关联日程仅解除显示，周期仍未完成且不自动重建');
let pause = save(fresh()); pause = run(pause, 'CHECKIN_PAUSE', { id: 'word' }); pause = next(pause, '2026-08-26');
assert(!record(pause, '2026-08-25') && task(pause, '2026-08-24') && checkInStats(pause).total === 1, '暂停保留已有任务，暂停日期不生成也不计分母');
pause = run(pause, 'CHECKIN_RESUME', { id: 'word' });
assert(record(pause, '2026-08-26').status === 'ready' && checkInStats(pause).total === 2, '恢复后当期继续生成');
assert(isCheckInDate(item({ frequency: 'weekly', weekdays: [1, 3] }), '2026-08-24') && !isCheckInDate(item({ frequency: 'weekly', weekdays: [1, 3] }), '2026-08-25'), '周节律仅指定星期有效');
assert(!isCheckInDate(item({ frequency: 'monthly', monthDays: [31], startDate: '2026-01-01' }), '2026-02-28'), '月31日不会迁移至短月月末');
let schedule = save(fresh('2026-10-26'), item({ startDate: '2026-10-20' })); schedule = save(schedule, item({ ...schedule.checkIns[0], startDate: '2026-10-01' }));
assert(!isCheckInDate(schedule.checkIns[0], '2026-10-10') && checkInStats(schedule).total === 7, '编辑开始日期不重写过去节律');

console.log('4) 永久删除及旧数据迁移');
let deletion = save(save(fresh()), item({ id: 'keep', name: '保留的计划' }));
deletion = run(deletion, 'ADD_TASK', { text: '背单词289-298' });
deletion = run(deletion, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-24' }); deletion = next(deletion, '2026-08-25');
const misplaced = Task.copy(task(deletion, '2026-08-25')); misplaced.id += '-future'; deletion.futureTasks.push(misplaced);
const beforeDeletion = deletion; deletion = run(deletion, 'CHECKIN_DELETE', { id: 'word' });
assert(!deletion.checkIns.some(value => value.id === 'word') && !deletion.checkInRecords.some(value => value.itemId === 'word'), '永久删除条目及全部独立记录，不留tombstone');
assert(!deletion.todayTasks.some(value => value.checkInId === 'word') && !deletion.futureTasks.some(value => value.checkInId === 'word') && !deletion.history.some(entry => entry.tasks.some(value => value.checkInId === 'word')), '永久删除清理当日、未来及历史所有关联任务');
assert(deletion.checkIns.some(value => value.id === 'keep') && deletion.todayTasks.some(value => !value.checkInId && value.text === '背单词289-298'), '永久删除保留其他计划及同名普通任务');
assert(beforeDeletion.checkIns.length === 2 && beforeDeletion.checkInRecords.some(value => value.itemId === 'word'), '删除仍遵循不可变状态，不污染原对象');
assert(error(deletion, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-24' }) && checkInTimeline(deletion, 'word').length === 0, '删除后无历史展示或撤销恢复入口');
const rawDeleted = JSON.parse(JSON.stringify(beforeDeletion)); rawDeleted.checkIns.find(value => value.id === 'word').deleted = true;
const cleanDeleted = normalizeData(rawDeleted);
assert(!cleanDeleted.checkIns.some(value => value.id === 'word') && !cleanDeleted.checkInRecords.some(value => value.itemId === 'word') && !cleanDeleted.todayTasks.some(value => value.checkInId === 'word') && !cleanDeleted.futureTasks.some(value => value.checkInId === 'word') && !cleanDeleted.history.some(entry => entry.tasks.some(value => value.checkInId === 'word')), '旧deleted迁移彻底清理计划、记录和三处分区');
assert(cleanDeleted.checkIns.some(value => value.id === 'keep') && cleanDeleted.todayTasks.some(value => !value.checkInId), '旧deleted清理不影响其他用户数据');
const legacy = JSON.parse(JSON.stringify(save(fresh(), item({ name: '读书' }))));
legacy.checkIns[0].nameVersion = 0; legacy.checkIns[0].useRange = true; legacy.checkIns[0].rangeStart = 11; legacy.checkIns[0].rangeEnd = 20; legacy.checkIns[0].count = 10; legacy.checkIns[0].autoIncrement = true; legacy.checkIns[0].incrementMode = 'shift';
legacy.checkInRecords[0].nameVersion = 0; legacy.checkInRecords[0].useRange = true; legacy.checkInRecords[0].rangeStart = 1; legacy.checkInRecords[0].rangeEnd = 10; legacy.checkInRecords[0].goal = '旧目标';
const migrated = normalizeData(legacy);
assert(migrated.checkIns[0].name === '读书 11-20' && migrated.checkIns[0].step === 10 && migrated.checkIns[0].incrementMode === 'segment', '旧独立范围嵌入名称，旧整体平移统一迁移为下一段数量');
assert(migrated.checkInRecords[0].name === '读书 1-10' && migrated.checkInRecords[0].rangeStart === 1 && migrated.todayTasks[0].text === '读书 1-10', '历史与关联任务使用自己的原范围快照，不受当前计划影响');
assert(JSON.stringify(normalizeData(JSON.parse(JSON.stringify(migrated)))) === JSON.stringify(migrated), '二次加载迁移幂等，不重复附数字');
const embedded = JSON.parse(JSON.stringify(save(fresh()))); delete embedded.checkIns[0].nameVersion; delete embedded.checkInRecords[0].nameVersion;
const same = normalizeData(embedded);
assert(same.checkIns[0].name === '背单词289-298' && same.checkInRecords[0].name === '背单词289-298', '已有唯一数字范围的旧名称不重复追加范围');
const clone = migrated.clone(); clone.checkIns[0].nameVersion = 9; clone.checkInRecords[0].name = '改动';
assert(migrated.checkIns[0].nameVersion === 1 && migrated.checkInRecords[0].name === '读书 1-10', 'clone隔离名称与迁移版本字段');

console.log('5) 时间线、统计和持久化');
let missed = save(fresh(), item({ startDate: '2026-08-20' })); const beforeTimeline = JSON.stringify(missed);
assert(checkInTimeline(missed, 'word', 3).length === 3 && JSON.stringify(missed) === beforeTimeline, '时间线补齐过去未生成周期但不落盘或生成任务');
missed = run(missed, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-22', text: '旅行时复习单词' });
assert(record(missed, '2026-08-22').name === '旅行时复习单词' && record(missed, '2026-08-22').backfilled && missed.todayTasks.length === 1, '过去未生成周期可补实际完整名称且不增加当日任务');
assert(checkInStats(missed).completed === 1 && checkInStats(missed).total === 5 && checkInStats(missed).rate === 20, '补卡计入历史完成率，未完成有效日期计分母');
let streak = save(fresh(), item({ frequency: 'weekly', weekdays: [1, 3] })); streak = run(streak, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-24' }); streak = next(streak, '2026-08-26');
assert(checkInStats(streak).currentStreak === 1, '今天尚未完成与休息日不打断此前连续');
streak = run(streak, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-26' });
assert(checkInStats(streak).currentStreak === 2 && checkInStats(streak).longestStreak === 2, '连续统计按有效周期累计');
streak = next(streak, '2026-09-02');
assert(checkInStats(streak).currentStreak === 0 && checkInStats(streak).longestStreak === 2, '过去漏卡中断当前连续但保留最长');
const loaded = normalizeData(JSON.parse(JSON.stringify(state)));
assert(loaded.checkIns[0] instanceof CheckInItem && loaded.checkIns[0].name === '背单词309-318' && loaded.checkIns[0].rangeUpdatedFor === '2026-08-26' && record(loaded, '2026-08-26').status === 'ready', '跨启动保留已自动生成的名称及周期状态');
const oldData = normalizeData({ currentDate: '2026-08-24', todayTasks: [{ id: 'normal', text: '普通日程' }], history: [], settings: {} });
assert(oldData.checkIns.length === 0 && oldData.todayTasks[0].text === '普通日程', '不含打卡字段的旧数据保持兼容');
assert(!parseCheckInName('跑步.5公里').valid && !parseCheckInName('做题+5').valid && !parseCheckInName('做题－5').valid && !parseCheckInName('做题＋5').valid && !parseCheckInName('做题- 5').valid, '省略整数位的小数、正负号及其全角形式不被识别为无符号整数');
let oldPending = save(fresh(), item({ autoIncrement: true })); oldPending = next(oldPending, '2026-08-25'); oldPending = next(oldPending, '2026-08-26');
// 模拟上版未确认的两条周期，确认历史遗留仍可手动处理且不回退当前配置。
record(oldPending, '2026-08-25').status = 'pending'; record(oldPending, '2026-08-26').status = 'pending';
oldPending.todayTasks = oldPending.todayTasks.filter(value => value.checkInKey === '2026-08-24');
oldPending = save(oldPending, item({ ...oldPending.checkIns[0], name: '新计划999-1008', startDate: '2026-09-01' }));
oldPending = run(oldPending, 'CHECKIN_GENERATE', { id: 'word', key: '2026-08-25', text: '旧计划299-308' });
assert(task(oldPending, '2026-08-25').text === '旧计划299-308' && oldPending.checkIns[0].name === '新计划999-1008' && oldPending.checkIns[0].rangeUpdatedFor === '' && !record(oldPending, '2026-08-26'), '改为未来开始后确认旧pending只生成原周期任务，不回退当前名称或标记');
oldPending = next(oldPending, '2026-09-01');
assert(record(oldPending, '2026-09-01').name === '新计划999-1008' && record(oldPending, '2026-09-01').status === 'ready' && oldPending.checkIns[0].rangeUpdatedFor === '2026-09-01', '新开始日期真正到来后首期生成当前名称并正常推进标记');
console.log('6) 旧逐期确认设置兼容与幂等同步');
let oldConfirm = save(fresh(), item({ autoIncrement: true })); oldConfirm = run(oldConfirm, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-24' }); oldConfirm = next(oldConfirm, '2026-08-25');
const oldConfirmRaw = JSON.parse(JSON.stringify(oldConfirm)); oldConfirmRaw.checkIns[0].confirmNext = true;
oldConfirmRaw.checkIns[0].name = '背单词289-298'; oldConfirmRaw.checkIns[0].rangeStart = 289; oldConfirmRaw.checkIns[0].rangeEnd = 298; oldConfirmRaw.checkIns[0].rangeUpdatedFor = '2026-08-24';
const pendingToday = oldConfirmRaw.checkInRecords.find(value => value.key === '2026-08-25'); pendingToday.status = 'pending'; pendingToday.generatedAt = ''; pendingToday.taskId = '';
oldConfirmRaw.todayTasks = oldConfirmRaw.todayTasks.filter(value => value.checkInKey !== '2026-08-25');
const pendingPast = { ...pendingToday, key: '2026-08-23', name: '背单词279-288' }; oldConfirmRaw.checkInRecords.push(pendingPast);
oldConfirm = normalizeData(oldConfirmRaw);
assert(new CheckInItem().confirmNext === false && oldConfirm.checkIns[0].confirmNext === false, '新旧计划均迁移为开启规则后自动执行，不保留逐期确认开关');
const completedBefore = JSON.stringify(record(oldConfirm, '2026-08-24')); oldConfirm = run(oldConfirm, 'CHECKIN_SYNC');
assert(record(oldConfirm, '2026-08-25').status === 'ready' && task(oldConfirm, '2026-08-25').text === '背单词299-308' && oldConfirm.checkIns[0].name === '背单词299-308', '旧版今日合法pending在启动同步后自动生成');
assert(record(oldConfirm, '2026-08-23').status === 'pending' && JSON.stringify(record(oldConfirm, '2026-08-24')) === completedBefore, '兼容同步不批量生成过去周期，也不修改历史完成快照');
const synchronized = JSON.stringify(oldConfirm); oldConfirm = run(oldConfirm, 'CHECKIN_SYNC');
assert(JSON.stringify(oldConfirm) === synchronized, '兼容自动生成再次同步完全幂等，不多递增或重复任务');
console.log('7) 未来只读预览和按有效周期投影');
let projected = save(fresh(), item({ autoIncrement: true })); const projectionBefore = JSON.stringify(projected);
assert(previewCheckInRecord(projected, 'word', '2026-08-27').name === '背单词319-328', '未来第3个有效周期按日期投影编号，而非始终只显示下一期');
const futureRows = checkInFutureTimeline(projected, 'word', 3);
assert(futureRows.map(value => value.key).join(',') === '2026-08-25,2026-08-26,2026-08-27' && futureRows[1].name === '背单词309-318', '未来时间线升序逐期投影，limit控制可扩展数量');
assert(checkInFutureTimeline(projected, 'word', 5).slice(0, 3).map(value => value.name).join('|') === futureRows.map(value => value.name).join('|') && checkInFutureTimeline(projected, 'word', 0).length === 0, '扩大时间线保留已有前缀且零数量返回空');
futureRows[0].name = '只改展示副本'; const existingPreview = previewCheckInRecord(projected, 'word', '2026-08-24'); existingPreview.name = '不准写入';
assert(JSON.stringify(projected) === projectionBefore, '预测、未来列表和已有快照均返回副本，不修改记录、当前名称或任务');
assert(!previewCheckInRecord(projected, 'missing', '2026-08-27') && !previewCheckInRecord(projected, 'word', '2026-02-30'), '缺失计划与非法日期没有预测');
let singles = save(fresh(), item({ name: '第009节', step: 2, autoIncrement: true }));
assert(previewCheckInRecord(singles, 'word', '2026-08-27').name === '第015节', '单值未来投影按步长与周期数计算并保留前导零');
let rangeStep = save(fresh(), item({ name: '读1-10页', step: 3, autoIncrement: true }));
assert(previewCheckInRecord(rangeStep, 'word', '2026-08-27').name === '读17-19页', '范围未来投影从上一段终点接续，后续每段用配置数量');
let weekly = save(fresh(), item({ frequency: 'weekly', weekdays: [1, 3], autoIncrement: true }));
assert(!previewCheckInRecord(weekly, 'word', '2026-08-25') && previewCheckInRecord(weekly, 'word', '2026-09-02').name === '背单词319-328', '每周预测只计算选中星期，休息日无记录');
assert(checkInFutureTimeline(weekly, 'word', 3).map(value => value.key).join(',') === '2026-08-26,2026-08-31,2026-09-02', '每周未来列表跳过非计划日期');
let monthly = save(fresh('2026-01-31'), item({ startDate: '2026-01-31', frequency: 'monthly', monthDays: [31], autoIncrement: true }));
assert(previewCheckInRecord(monthly, 'word', '2026-05-31').name === '背单词309-318' && checkInFutureTimeline(monthly, 'word', 2).map(value => value.key).join(',') === '2026-03-31,2026-05-31', '月末短月不占周期，也不虚构二月或四月31日');
let leap = save(fresh('2028-02-28'), item({ startDate: '2028-02-28', name: '第1节', step: 1, autoIncrement: true, frequency: 'monthly', monthDays: [29] }));
assert(previewCheckInRecord(leap, 'word', '2028-02-29').name === '第1节' && previewCheckInRecord(leap, 'word', '2028-03-29').name === '第2节', '尚未到首期时闰日为首个编号，下月才递增');
assert(previewCheckInRecord(fixed, 'word', '2026-09-30').name === '背单词289-298', '关闭自动递增的所有未来周期沿用完整名称');
let futureStart = save(fresh(), item({ startDate: '2026-09-01', autoIncrement: true }));
assert(!previewCheckInRecord(futureStart, 'word', '2026-08-31') && previewCheckInRecord(futureStart, 'word', '2026-09-01').name === '背单词289-298' && previewCheckInRecord(futureStart, 'word', '2026-09-03').name === '背单词309-318', '未来开始日用初始名称，其后按实际周期接续');
let pauses = save(fresh(), item({ autoIncrement: true })); pauses = next(pauses, '2026-08-25'); pauses = run(pauses, 'CHECKIN_PAUSE', { id: 'word' });
assert(!previewCheckInRecord(pauses, 'word', '2026-08-26') && checkInFutureTimeline(pauses, 'word').length === 0, '暂停中不生成任意未来建议或死循环扫描');
pauses = next(pauses, '2026-08-28'); pauses = run(pauses, 'CHECKIN_RESUME', { id: 'word' });
assert(record(pauses, '2026-08-28').name === '背单词309-318' && previewCheckInRecord(pauses, 'word', '2026-08-29').name === '背单词319-328', '暂停区间不消耗编号，恢复日继续下一有效周期');
const pastPreview = previewCheckInRecord(missed, 'word', '2026-08-21');
assert(pastPreview.name === '' && pastPreview.status === 'ready' && !pastPreview.generatedAt && checkInTimeline(missed, 'word').filter(value => !value.generatedAt && value.status !== 'completed').every(value => value.name === ''), '过去没有快照的周期只显示空内容，不伪造历史名称');
assert(error(missed, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-21' }), '过去无快照补卡必须填写真实当期内容');
let futureOverflow = save(fresh(), item({ name: '第9007199254740990节', step: 1, autoIncrement: true }));
assert(previewCheckInRecord(futureOverflow, 'word', '2026-08-25').name === '第9007199254740991节' && previewCheckInRecord(futureOverflow, 'word', '2026-08-26').name === '' && previewCheckInRecord(futureOverflow, 'word', '2026-08-26').status === 'pending', '未来安全整数边界精确，溢出返回空待处理预测');
assert(error(futureOverflow, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-26' }) && !record(run(futureOverflow, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-26' }), '2026-08-26'), '溢出提前完成被拒绝且不保存损坏快照');

console.log('8) 提前完成隔离、到期同步及重启');
let early = run(projected, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-27' }); const earlySnapshot = record(early, '2026-08-27');
assert(earlySnapshot.name === '背单词319-328' && earlySnapshot.status === 'completed' && earlySnapshot.advanced && earlySnapshot.completedAt && !earlySnapshot.backfilled, '提前完成保存所选日期的准确名称和真实完成时间');
assert(early.todayTasks.length === 1 && early.futureTasks.length === 0 && early.history.length === 0 && early.checkIns[0].name === '背单词289-298' && early.checkIns[0].rangeUpdatedFor === '2026-08-24', '提前完成不创建任何日程，不推进当前名称或日期标记');
assert(JSON.stringify(checkInStats(early)) === JSON.stringify(checkInStats(projected)) && checkInStats(early, '', '2026-12-31').rate <= 100, '提前完成不进入今天的累计、分母和完成率，未来through仍限制到真实今天');
assert(checkInTimeline(early, 'word').every(value => value.key <= '2026-08-24') && checkInFutureTimeline(early, 'word', 3)[2].advanced, '过去时间线不泄漏未来快照，未来列表显示已提前完成');
assert(error(early, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-27' }) && !error(early, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' }) && error(early, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-27' }), '未来已完成允许撤销但不可重复确认，普通完成入口也不能绕过');
const repeatEarly = run(early, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-27' });
assert(JSON.stringify(repeatEarly) === JSON.stringify(early), '重复提前完成reducer完全幂等，不更新时间或重复记录');
assert(error(projected, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-24' }) && error(weekly, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-25' }) && error(projected, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-25', text: '伪造未来内容' }), '今天、非有效周期和绕过规则手改未来名称均拒绝提前完成');
let browsing = run(early, 'SELECT_DATE', { key: '2026-09-20' }); browsing = run(browsing, 'CHECKIN_SYNC');
assert(browsing.currentDate === '2026-09-20' && browsing.lastRolloverDate === '2026-08-24' && browsing.todayTasks.length === 1 && browsing.futureTasks.length === 0 && browsing.checkIns[0].name === '背单词289-298', '选择远期日历并前台同步不把未来打卡带入today或future');
browsing = run(browsing, 'SELECT_DATE', { key: '2026-08-24' });
assert(JSON.stringify(browsing) === JSON.stringify(early), '从未来浏览返回今天不改变提前快照或真实周期');
let restartedEarly = normalizeData(JSON.parse(JSON.stringify(early))); restartedEarly = run(restartedEarly, 'CHECKIN_SYNC');
assert(record(restartedEarly, '2026-08-27').advanced && record(restartedEarly, '2026-08-27').name === earlySnapshot.name && restartedEarly.checkIns[0].nameAnchorDate === '2026-08-24' && restartedEarly.todayTasks.length === 1, '重启保留提前标记、名称与投影锚点，未来任务仍隔离');
let arriving = next(restartedEarly, '2026-08-25');
assert(record(arriving, '2026-08-25').name === '背单词299-308' && arriving.checkIns[0].name === '背单词299-308', '提前完成远期后次日仍生成自己的编号，不跳过前面周期');
arriving = next(arriving, '2026-08-27');
assert(task(arriving, '2026-08-27').completed && task(arriving, '2026-08-27').completedDate === '2026-08-27' && task(arriving, '2026-08-27').completedAt === earlySnapshot.completedAt && arriving.checkIns[0].name === '背单词319-328', '真实到期日才投放已完成日程，保留提前时间且当前进度对齐');
const arrivalBefore = JSON.stringify(arriving); arriving = run(arriving, 'CHECKIN_SYNC');
assert(JSON.stringify(arriving) === arrivalBefore && arriving.todayTasks.filter(value => value.checkInKey === '2026-08-27').length === 1, '到期重复同步不双重递增或重复任务');
arriving = next(arriving, '2026-08-28');
assert(record(arriving, '2026-08-28').name === '背单词329-338' && arriving.history.some(entry => entry.date === '2026-08-27' && entry.tasks.some(value => value.checkInKey === '2026-08-27')), '提前完成到期后的下一日继续接续，并按原周期归档');
let gap = next(restartedEarly, '2026-08-30');
assert(record(gap, '2026-08-30').name === '背单词349-358' && !record(gap, '2026-08-25') && gap.history.some(entry => entry.date === '2026-08-27' && entry.tasks.some(value => value.checkInKey === '2026-08-27')), '多日未打开仍按日期对齐，当中提前完成归历史，不伪造漏开的记录');
assert(!gap.todayTasks.some(value => value.checkInKey === '2026-08-27') && gap.futureTasks.length === 0 && checkInStats(gap).completed === 1, '跨过到期日不再挂完成任务到今天，统计从真实到期后纳入一次');
let several = run(early, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-25' }); several = run(several, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-29' }); several = next(several, '2026-08-30');
assert(record(several, '2026-08-30').name === '背单词349-358' && several.history.filter(entry => entry.tasks.some(value => value.checkInId === 'word')).length === 3, '无序提前完成多个日期，跨日后各归原周期且不影响编号次数');
let arrivedUndo = next(early, '2026-08-27'); arrivedUndo = run(arrivedUndo, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' });
assert(record(arrivedUndo, '2026-08-27').status === 'ready' && !record(arrivedUndo, '2026-08-27').advanced && task(arrivedUndo, '2026-08-27') && !task(arrivedUndo, '2026-08-27').completed, '到期当天允许普通撤销并清除提前标识，保留原周期名称');

console.log('9) 未来编辑快照、迁移与日程防泄漏');
let changed = save(early, item({ ...early.checkIns[0], name: '新单词100-109' }));
assert(previewCheckInRecord(changed, 'word', '2026-08-25').name === '新单词100-109' && previewCheckInRecord(changed, 'word', '2026-08-26').name === '新单词110-119' && previewCheckInRecord(changed, 'word', '2026-08-27').name === '背单词319-328', '手动重设从下个未生成周期起生效，已提前确认的未来名称保持');
changed = next(changed, '2026-08-27');
assert(task(changed, '2026-08-27').text === '背单词319-328' && changed.checkIns[0].name === '新单词120-129' && previewCheckInRecord(changed, 'word', '2026-08-28').name === '新单词130-139', '旧未来快照到期仍显示旧名，当前规则继续推进且不回退到旧数字');
let renamed = save(early, item({ ...early.checkIns[0], name: '复习单词289-298', step: 5 }));
assert(previewCheckInRecord(renamed, 'word', '2026-08-26').name === '复习单词304-308' && record(renamed, '2026-08-27').name === '背单词319-328', '只改前缀或数量影响未确认预测，不重写任何已确认快照');
renamed = save(renamed, item({ ...renamed.checkIns[0], autoIncrement: false }));
assert(previewCheckInRecord(renamed, 'word', '2026-08-26').name === '复习单词289-298' && previewCheckInRecord(renamed, 'word', '2026-08-27').name === '背单词319-328', '关闭递增后预测固定名称，已有提前快照优先');
let scheduleEdit = save(early, item({ ...early.checkIns[0], frequency: 'weekly', weekdays: [1] }));
assert(!previewCheckInRecord(scheduleEdit, 'word', '2026-08-26') && previewCheckInRecord(scheduleEdit, 'word', '2026-08-27').advanced && checkInFutureTimeline(scheduleEdit, 'word', 2)[0].key === '2026-08-27', '编辑频率后保留已提前确认的非新节律日期，其余只读预测重算');
let pausedEarly = run(early, 'CHECKIN_PAUSE', { id: 'word' });
assert(checkInFutureTimeline(pausedEarly, 'word').length === 1 && previewCheckInRecord(pausedEarly, 'word', '2026-08-27').advanced, '暂停隐藏新预测但保留已确认未来内容供查看');
pausedEarly = next(pausedEarly, '2026-08-27');
assert(task(pausedEarly, '2026-08-27').completed && pausedEarly.checkIns[0].name === '背单词289-298', '暂停期间已确认未来快照仍到期归位，不推进暂停计划当前名称');
let deletedEarly = run(early, 'CHECKIN_DELETE', { id: 'word' });
assert(deletedEarly.checkInRecords.length === 0 && deletedEarly.checkIns.length === 0 && deletedEarly.todayTasks.length === 0, '永久删除同时清理提前完成的独立未来记录');
const oldSkipped = JSON.parse(JSON.stringify(projected)); oldSkipped.checkInRecords[0].status = 'skipped'; oldSkipped.todayTasks = [];
let unskipped = normalizeData(oldSkipped); unskipped = run(unskipped, 'CHECKIN_SYNC');
assert(record(unskipped, '2026-08-24').status === 'ready' && record(unskipped, '2026-08-24').taskDetached && unskipped.todayTasks.length === 0, '旧跳过迁移为未完成，保留已移除日程状态，不重建任务');
assert(error(unskipped, 'CHECKIN_SKIP', { id: 'word', key: '2026-08-24' }) && JSON.stringify(run(unskipped, 'CHECKIN_SKIP', { id: 'word', key: '2026-08-24' })) === JSON.stringify(unskipped), '移除跳过领域动作，直接调用也不改变状态');
unskipped = run(unskipped, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-24' });
assert(record(unskipped, '2026-08-24').status === 'completed' && checkInStats(unskipped).completed === 1, '旧跳过现在可直接完成独立周期，不必恢复或改名');
const contaminated = JSON.parse(JSON.stringify(early)); const leaked = { ...contaminated.todayTasks[0], id: 'leaked', checkInKey: '2026-08-27', dueDate: '2026-08-27' }; contaminated.todayTasks.push(leaked); contaminated.futureTasks.push({ ...leaked, id: 'leaked-future' }); contaminated.history.push({ date: '2026-08-27', tasks: [{ ...leaked, id: 'leaked-history' }] });
const isolated = normalizeData(contaminated);
assert(!isolated.todayTasks.some(value => value.checkInKey > isolated.lastRolloverDate) && isolated.futureTasks.length === 0 && !isolated.history.some(entry => entry.tasks.some(value => value.checkInKey > isolated.lastRolloverDate)) && record(isolated, '2026-08-27').advanced, '加载清理误存的未来打卡任务但保留独立提前快照，三处分区都不泄漏');
assert(JSON.stringify(normalizeData(JSON.parse(JSON.stringify(isolated)))) === JSON.stringify(isolated), '未来隔离与跳过迁移在重复加载时保持幂等');

console.log('10) 分段计数、极远日期与再次完成标识');
let ordinaryUndo = next(early, '2026-08-27'); const arrivedTaskId = task(ordinaryUndo, '2026-08-27').id;
ordinaryUndo = run(ordinaryUndo, 'TOGGLE_TODAY', { id: arrivedTaskId }); ordinaryUndo = run(ordinaryUndo, 'TOGGLE_TODAY', { id: arrivedTaskId });
assert(record(ordinaryUndo, '2026-08-27').status === 'completed' && !record(ordinaryUndo, '2026-08-27').advanced && !record(ordinaryUndo, '2026-08-27').backfilled, '普通日程撤销后当天重完不再标为提前打卡');
let undoBackfill = run(next(early, '2026-08-28'), 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' }); undoBackfill = run(undoBackfill, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-27' });
assert(record(undoBackfill, '2026-08-27').backfilled && !record(undoBackfill, '2026-08-27').advanced && record(undoBackfill, '2026-08-27').name === earlySnapshot.name, '提前完成到期撤销后补卡只保留补卡标记，名称快照不改');
assert(record(next(weekly, '2026-09-02'), '2026-09-02').name === '背单词319-328' && record(next(monthly, '2026-05-31'), '2026-05-31').name === '背单词309-318', '每周与每月多日未开应用的真实生成和只读预测完全一致');
let changedSchedule = save(projected, item({ ...projected.checkIns[0], frequency: 'weekly', weekdays: [1, 3] })); changedSchedule = next(changedSchedule, '2026-09-02');
changedSchedule = save(changedSchedule, item({ ...changedSchedule.checkIns[0], frequency: 'monthly', monthDays: [5, 15] }));
assert(previewCheckInRecord(changedSchedule, 'word', '2026-10-15').name === '背单词359-368' && record(next(changedSchedule, '2026-10-15'), '2026-10-15').name === '背单词359-368', '节律切换按生效边界分段，不重数之前日期');
const hugeStart = save(fresh(), item({ startDate: '9999-01-01', autoIncrement: true }));
const NativeDate = globalThis.Date; let dateCreations = 0;
class CountingDate extends NativeDate { constructor(...args) { super(...args); dateCreations++; } }
let farRows; let farPreview;
try { globalThis.Date = CountingDate; farRows = checkInFutureTimeline(hugeStart, 'word', 3); farPreview = previewCheckInRecord(projected, 'word', '9999-01-01'); } finally { globalThis.Date = NativeDate; }
assert(farRows.map(value => value.key).join(',') === '9999-01-01,9999-01-02,9999-01-03' && farRows[2].name === '背单词309-318' && dateCreations < 100, '远年开始直接跳到开始日期，日频投影常数计数而非扫描数百万天');
assert(farPreview.name && farPreview.name !== projected.checkIns[0].name, '远年日频投影仍返回按周期计算的正确非初始内容');
const inconsistentPause = projected.clone(); inconsistentPause.checkIns[0].paused = false; inconsistentPause.checkIns[0].pauses.push({ from: '2026-08-25', to: '' });
assert(checkInFutureTimeline(inconsistentPause, 'word', 3).length === 0, '兼容暂停布尔值不一致但未闭合暂停区间，及时结束未来查询');
let monthlyRows; dateCreations = 0;
try { globalThis.Date = CountingDate; monthlyRows = checkInFutureTimeline(monthly, 'word', 30); } finally { globalThis.Date = NativeDate; }
assert(monthlyRows.length === 30 && dateCreations < 5000 && monthlyRows[29].name === '背单词589-598', '稀疏月频时间线只算一次起点，后续增量接续而不反复从头计数：' + dateCreations + '/' + monthlyRows[29].name);


console.log('11) 未来提前完成撤销及再次到期');
const earlyBeforeUndo = JSON.stringify(early);
let futureUndone = run(early, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' });
assert(record(futureUndone, '2026-08-27').status === 'ready' && !record(futureUndone, '2026-08-27').advanced && !record(futureUndone, '2026-08-27').completedAt && record(futureUndone, '2026-08-27').name === earlySnapshot.name, '提前撤销清完成状态与时间，保留该日期名称快照');
assert(JSON.stringify(futureUndone.todayTasks) === JSON.stringify(early.todayTasks) && !futureUndone.futureTasks.length && !futureUndone.history.length && futureUndone.checkIns[0].name === early.checkIns[0].name && JSON.stringify(early) === earlyBeforeUndo, '提前撤销不产生日程、不改当前进度且不污染源数据');
assert(error(futureUndone, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' }) && error(projected, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-26' }), '未完成未来周期或重复撤销有错误提示');
let repeatAdvance = run(futureUndone, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-27' });
assert(record(repeatAdvance, '2026-08-27').advanced && record(repeatAdvance, '2026-08-27').status === 'completed' && record(repeatAdvance, '2026-08-27').name === earlySnapshot.name && repeatAdvance.checkInRecords.filter(v => v.key === '2026-08-27').length === 1, '撤销后可再次提前打卡，复用独立周期不重复记录');
futureUndone = normalizeData(JSON.parse(JSON.stringify(futureUndone)));
assert(record(futureUndone, '2026-08-27').status === 'ready' && !record(futureUndone, '2026-08-27').taskId && futureUndone.todayTasks.length === 1, '提前撤销后重启保留待完成快照，仍不泄漏未来日程');
let undoArrival = next(futureUndone, '2026-08-27');
assert(task(undoArrival, '2026-08-27') && !task(undoArrival, '2026-08-27').completed && undoArrival.checkIns[0].name === earlySnapshot.name, '提前撤销的周期真实到期后正常生成未完成日程并推进对应名称');
const undoArrivalBefore = JSON.stringify(undoArrival); undoArrival = run(undoArrival, 'CHECKIN_SYNC');
assert(JSON.stringify(undoArrival) === undoArrivalBefore, '提前撤销周期到期同步幂等，不重复日程');
const undoGap = next(futureUndone, '2026-08-30');
assert(task(undoGap, '2026-08-27') && !task(undoGap, '2026-08-27').completed && taskDelayText(task(undoGap, '2026-08-27'), '2026-08-30', '2026-08-30').includes('3'), '跳过到期日打开时，已确认后撤销的周期保留为延期未完成日程');
let undoPaused = run(early, 'CHECKIN_PAUSE', { id: 'word' }); undoPaused = run(undoPaused, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' }); undoPaused = next(undoPaused, '2026-08-27');
assert(record(undoPaused, '2026-08-27').status === 'ready' && !task(undoPaused, '2026-08-27'), '暂停后仍能撤销提前完成，停用周期不因此生成日程');
const fakeFuture = early.clone(); record(fakeFuture, '2026-08-27').advanced = false;
assert(error(fakeFuture, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27' }) && error(early, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-27', text: '改名' }), '非提前完成的未来脏数据和携带改名的撤销请求均拒绝');

console.log('12) 打卡分组保存、日程衔接和历史保护');
let grouped = save(fresh(), item({ autoIncrement: true, group: '  学习  ' }));
assert(grouped.checkIns[0].group === '学习' && grouped.groups.join(',') === '学习' && task(grouped, '2026-08-24').group === '学习' && record(grouped, '2026-08-24').group === '学习', '创建计划原子保存trim后的分组与目录，今日任务及快照同步归组');
const groupedBeforeInvalid = JSON.stringify(grouped);
assert(JSON.stringify(save(grouped, item({ id: 'bad', name: '', group: '不应创建' }))) === groupedBeforeInvalid, '计划校验失败时不独立创建分组');
grouped = save(grouped, item({ id: 'another', name: '运动', group: '学习' }));
assert(grouped.groups.filter(v => v === '学习').length === 1 && grouped.checkIns.length === 2, '多个打卡计划复用同名目录');
const groupedClone = grouped.clone(); groupedClone.checkIns[0].group = '副本'; record(groupedClone, '2026-08-24').group = '记录副本';
assert(grouped.checkIns[0].group === '学习' && record(grouped, '2026-08-24').group === '学习' && normalizeData(JSON.parse(JSON.stringify(grouped))).checkIns[0].group === '学习', '分组字段参与复制和持久化，副本不回写原数据');
const legacyGroup = JSON.parse(JSON.stringify(grouped)); delete legacyGroup.checkIns[0].group; delete legacyGroup.checkInRecords[0].group;
assert(normalizeData(legacyGroup).checkIns[0].group === '' && record(normalizeData(legacyGroup), '2026-08-24').group === '学习', '旧计划默认未分组，已有日程的历史归属可回填到其独立周期');
grouped = run(grouped, 'CHECKIN_ADVANCE', { id: 'word', key: '2026-08-27' });
grouped = save(grouped, item({ ...grouped.checkIns[0], group: '阅读' }));
assert(task(grouped, '2026-08-24').group === '阅读' && record(grouped, '2026-08-27').group === '阅读' && grouped.groups.includes('阅读'), '编辑计划归属同步当前关联任务和未来周期，但不改未来名称');
grouped = run(grouped, 'CHECKIN_COMPLETE', { id: 'word', key: '2026-08-24' }); grouped = next(grouped, '2026-08-25');
grouped = save(grouped, item({ ...grouped.checkIns[0], group: '复习' }));
assert(task(grouped, '2026-08-25').group === '复习' && grouped.history.find(v => v.date === '2026-08-24').tasks.find(v => v.checkInId === 'word').group === '阅读' && record(grouped, '2026-08-24').group === '阅读', '变更分组保留已归档历史的归属，只改变当前和后续周期');
const groupedArrival = next(grouped, '2026-08-27');
assert(task(groupedArrival, '2026-08-27').group === '复习' && task(groupedArrival, '2026-08-27').completed, '提前完成周期到期日程采用当前计划设置的分组');
let groupedBackfill = save(fresh(), item({ startDate: '2026-08-20', group: '阅读' }));
groupedBackfill = run(groupedBackfill, 'CHECKIN_BACKFILL', { id: 'word', key: '2026-08-21', text: '当时阅读' });
groupedBackfill = run(groupedBackfill, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-21' });
assert(task(groupedBackfill, '2026-08-21').group === '阅读', '历史补卡快照保留组别，撤销回到日程时归入该组');
let groupRemoved = run(grouped, 'DELETE_GROUP', { group: '复习', section: 'today' }); groupRemoved = next(normalizeData(JSON.parse(JSON.stringify(groupRemoved))), '2026-08-27');
assert(!groupRemoved.groups.includes('复习') && groupRemoved.checkIns[0].group === '' && task(groupRemoved, '2026-08-27').group === null && record(groupRemoved, '2026-08-24').group === '阅读', '删除最后分区的目录解除计划及未来快照归属，重启或到期不会复活组，历史不回写');
let futureGroupOnly = save(fresh(), item({ startDate: '2026-09-01', group: '未来组' })); futureGroupOnly = run(futureGroupOnly, 'DELETE_GROUP', { group: '未来组', section: 'today' }); futureGroupOnly = next(futureGroupOnly, '2026-09-01');
assert(!futureGroupOnly.groups.includes('未来组') && task(futureGroupOnly, '2026-09-01').group === null, '没有当前日程的未来计划也能解除已删除目录，首期不会复活组');
let sharedGroup = save(fresh(), item({ group: '共享' })); sharedGroup = run(sharedGroup, 'ADD_TASK', { section: 'future', text: '普通安排', group: '共享', dueDate: '2026-08-30' });
sharedGroup = run(sharedGroup, 'DELETE_GROUP', { group: '共享', section: 'today' });
assert(sharedGroup.groups.includes('共享') && sharedGroup.checkIns[0].group === '共享' && task(sharedGroup, '2026-08-24').group === null && record(sharedGroup, '2026-08-24').group === '', '只删一个分区且另一分区仍使用目录时，当前任务解除分组，计划后续归属保留');
let restoreRemoved = run(grouped, 'DELETE_GROUP', { group: '阅读', section: 'today' }); restoreRemoved = run(restoreRemoved, 'CHECKIN_UNDO', { id: 'word', key: '2026-08-24' });
assert(task(restoreRemoved, '2026-08-24').group === null && !restoreRemoved.groups.includes('阅读'), '撤销历史记录不会使已经删除的组目录复活');
const clearedGroup = save(grouped, item({ ...grouped.checkIns[0], group: '' }));
assert(clearedGroup.checkIns[0].group === '' && task(clearedGroup, '2026-08-25').group === null && record(clearedGroup, '2026-08-27').group === '', '显式取消计划分组同步当前与未来，但保留可复用空目录');

console.log(`打卡逻辑：${passed} 项通过。`);