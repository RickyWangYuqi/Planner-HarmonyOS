// 卡片勾选写回回归：在内存文件系统中执行真实 CardSnapshot / CardWriter，
// 验证「卡片点方框 → 写回 data.json」的完整链路与失败保护；不验证卡片渲染与手势。
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

const files = new Map();
const descriptors = new Map();
let nextDescriptor = 1;
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  accessSync: name => files.has(name),
  readTextSync: name => {
    if (!files.has(name)) throw new Error('模拟文件不存在');
    return files.get(name);
  },
  access: async name => files.has(name),
  open: async name => {
    const file = { fd: nextDescriptor++ };
    files.set(name, '');
    descriptors.set(file.fd, name);
    return file;
  },
  write: async (descriptor, text) => {
    files.set(descriptors.get(descriptor), text);
    return Buffer.byteLength(text);
  },
  fsync: async () => {},
  close: async file => { descriptors.delete(typeof file === 'number' ? file : file.fd); },
  readText: async name => {
    if (!files.has(name)) throw new Error('模拟文件不存在');
    return files.get(name);
  },
  copyFile: async (source, target) => { files.set(target, files.get(source)); },
  rename: async (source, target) => { files.set(target, files.get(source)); files.delete(source); }
};

const modules = new Map();
function load(relative) {
  const filename = path.join(project, 'entry/src/main/ets', `${relative}.ets`);
  if (modules.has(filename)) return modules.get(filename);
  const source = readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true
  });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(item => item.messageText).join('\n'));
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${result.outputText}\n})`, { filename })(request => {
    if (request === '@kit.CoreFileKit') return { fileIo };
    return load(path.join(path.dirname(relative), request));
  }, module, module.exports);
  modules.set(filename, module.exports);
  return module.exports;
}

const { CardSnapshot } = load('services/CardSnapshot');
const { CardWriter } = load('services/CardWriter');
const { Task, AppAction } = load('model/PlanerModel');
const { freshData, todayKey, addDays, reduce } = load('model/PlanerEngine');

const context = { filesDir: '/mock-sandbox' };
const dataPath = context.filesDir + '/data.json';
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++;
  console.log(`✓ ${message}`);
}

function task(id, text, completed) {
  const item = new Task();
  item.id = id;
  item.text = text;
  item.completed = completed;
  return item;
}

function seed(tasks, currentDate) {
  const data = freshData();
  if (currentDate) data.currentDate = currentDate;
  data.todayTasks = tasks;
  files.clear();
  files.set(dataPath, JSON.stringify(data));
  return data;
}

function readFileState() {
  return JSON.parse(files.get(dataPath));
}

console.log('卡片勾选写回');

seed([task('a', '写实验报告', false), task('b', '整理周计划', false)], undefined);
assert(await CardWriter.toggleToday(context, 'a') === true, '勾选已存在的当日日程返回 true');
let state = readFileState();
assert(state.todayTasks[0].completed === true, '目标日程被写为已完成');
assert(!!state.todayTasks[0].completedAt, '完成时间一并写入');
assert(state.todayTasks[1].completed === false, '其它日程不受影响');
assert(files.has(dataPath + '.bak'), '写入前保留一份备份');
assert(!files.has(dataPath + '.card.tmp'), '临时文件已清理');

assert(await CardWriter.toggleToday(context, 'a') === true, '再次点击可取消完成');
state = readFileState();
assert(state.todayTasks[0].completed === false, '取消完成后状态回退');
assert(state.todayTasks[0].completedAt === null, '取消完成同时清空完成时间');

seed([task('a', '写实验报告', false)], undefined);
const before = files.get(dataPath);
assert(await CardWriter.toggleToday(context, 'nope') === false, '未知 id 返回 false');
assert(files.get(dataPath) === before, '未知 id 不写入文件');

const yesterday = new Date();
yesterday.setDate(yesterday.getDate() - 1);
const y = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, '0')}-${String(yesterday.getDate()).padStart(2, '0')}`;
seed([task('a', '昨日未完成', false), task('b', '昨日已完成', true)], y);
const snapshot = CardSnapshot.load(context);
assert(snapshot.currentDate > y, '卡片读取时在内存中顺延到真实今天');
assert(snapshot.todayTasks.length === 1, '已完成日程顺延时归档，不留在当日');
assert(await CardWriter.toggleToday(context, 'a') === true, '顺延后的日程仍可勾选');
state = readFileState();
assert(state.currentDate === snapshot.currentDate, '写回时保留顺延后的日期，不回到旧日期');
assert(state.todayTasks[0].completed === true, '顺延后勾选状态落到文件');
assert(state.history.length === 1, '昨日已完成日程留在历史中');

const futureOnly = freshData();
futureOnly.todayTasks = [];
const futureTask = task('f', '未来任务', false);
futureTask.dueDate = '2026-12-01';
futureOnly.futureTasks = [futureTask];
files.clear();
files.set(dataPath, JSON.stringify(futureOnly));
assert(await CardWriter.toggleToday(context, 'f') === false, '未来日程不在当日勾选范围内');
assert(await CardWriter.completeFuture(context, 'f') === true, '未来日程可在卡片上直接完成');
const futureState = readFileState();
assert(!futureState.futureTasks.some(item => item.id === 'f'), '完成后从未来列表移除');
assert(futureState.history.some(entry => entry.tasks.some(item => item.id === 'f')),
  '完成后归档到当日历史');
assert(await CardWriter.completeFuture(context, 'missing') === false, '未知未来日程返回 false');

files.clear();
assert(CardSnapshot.load(context).todayTasks.length === 0, '数据文件缺失时卡片回落到空数据');
assert(await CardWriter.toggleToday(context, 'a') === false, '无数据文件时勾选不会创建文件');

const retained = freshData();
retained.settings.retainCompletedFutureUntilDue = true;
const keep = task('keep', '完成后保留', false);
keep.dueDate = addDays(todayKey(), 2);
retained.futureTasks = [keep]; files.set(dataPath, JSON.stringify(retained));
assert(await CardWriter.completeFuture(context, 'keep'), '卡片保留模式接受完成操作');
assert(readFileState().futureTasks[0].completed && readFileState().history.length === 0, '卡片写回与应用共用保留规则，不提前归档');
assert(readFileState().settings.retainCompletedFutureUntilDue, '卡片写回不丢失新设置');
assert(await CardWriter.completeFuture(context, 'keep') && !readFileState().futureTasks[0].completed, '卡片再次点击可取消未来完成');
await CardWriter.completeFuture(context, 'keep');
let persisted = readFileState();
persisted.currentDate = addDays(todayKey(), -4);
persisted.lastRolloverDate = persisted.currentDate;
persisted.futureTasks[0].dueDate = addDays(todayKey(), -1);
files.set(dataPath, JSON.stringify(persisted));
const expiredRaw = files.get(dataPath);
const expired = CardSnapshot.load(context);
assert(expired.futureTasks.length === 0 && expired.history.some(entry => entry.date === persisted.futureTasks[0].dueDate), '应用未打开时卡片同样在截止日结束后归档');
assert(files.get(dataPath) === expiredRaw, '卡片仅刷新跨日快照时不额外写文件');
let previewed = freshData();
previewed.todayTasks = [task('real-done', '真实今天完成', true)];
previewed.todayTasks[0].scheduledDate = todayKey();
previewed.todayTasks[0].completedDate = todayKey();
const later = task('later', '未来计划', false); later.dueDate = addDays(todayKey(), 2); later.scheduledDate = later.dueDate;
previewed.futureTasks = [later];
const select = new AppAction('SELECT_DATE'); select.key = addDays(todayKey(), 5);
previewed = reduce(previewed, select); files.set(dataPath, JSON.stringify(previewed));
const rawPreview = files.get(dataPath); let realView = CardSnapshot.load(context);
assert(realView.currentDate === todayKey(), '桌面卡片展示真实今天，不沿用应用保存的未来预览日期');
assert(realView.todayTasks[0].id === 'real-done' && realView.history.length === 0, '从未来预览读取卡片不会提前归档今天完成项');
assert(realView.futureTasks.some(item => item.id === 'later'), '未来预览中拉入当日的未来计划在卡片正确归回未来');
assert(files.get(dataPath) === rawPreview, '切换卡片只读视角不修改应用保存的数据');
previewed.lastRolloverDate = addDays(todayKey(), -1);
previewed.todayTasks.find(item => item.id === 'real-done').completedDate = previewed.lastRolloverDate;
files.set(dataPath, JSON.stringify(previewed)); realView = CardSnapshot.load(context);
assert(realView.history.some(entry => entry.date === previewed.lastRolloverDate && entry.tasks.some(item => item.id === 'real-done')), '应用停在未来日期时卡片仍能处理真实午夜归档');
await CardWriter.completeFuture(context, 'later');
assert(readFileState().history.some(entry => entry.date === todayKey() && entry.tasks.some(item => item.id === 'later')), '卡片从预览存储完成未来计划仍按真实今天写入历史');
console.log(`\n卡片写回：${passed} 项通过`);
