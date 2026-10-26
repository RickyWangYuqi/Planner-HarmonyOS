// 从真实页面方法和 FormSync 源码执行回归，不读写设备数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript',
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript',
  path.join(root, '../Planer/node_modules/typescript')].filter(Boolean)) {
  try { ts = require(candidate); break; } catch {}
}
if (!ts) throw new Error('缺少现有 TypeScript 工具链');
const base = path.join(root, 'entry/src/main/ets');
const cache = new Map();
const calls = [];
let running = [];
let records = [];
let failId = '';
let release;
const gate = () => new Promise(resolve => { release = resolve; });
let blocked;
const formProvider = {
  getPublishedRunningFormInfos: async () => running,
  getFormRect: async () => ({ width: 320, height: 320 }),
  updateForm: async (id, payload) => {
    if (blocked) { const wait = blocked; blocked = undefined; await wait; }
    if (id === failId) throw new Error('模拟单卡失效');
    calls.push({ id, payload });
  }
};
const formInfo = { FormParam: { IDENTITY_KEY: 'ohos.extra.param.key.form_identity' },
  FormDimension: { Dimension_4_4: 4, Dimension_2_4: 3, Dimension_1_2: 1 } };
const board = { records: async () => records.map(item => ({ ...item })), replace: async (_, value) => { records = value; } };
function compile(source, filename, imports = load) {
  const result = ts.transpileModule(source, { fileName: filename,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(item => item.messageText).join('\n'));
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${result.outputText}\n})`, { filename })(imports, module, module.exports);
  return module.exports;
}
function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const filename = path.join(base, relative + '.ets');
  const exports = compile(readFileSync(filename, 'utf8'), filename, request => {
    if (request === '@kit.AbilityKit') return {};
    if (request === '@kit.FormKit') return { formProvider, formInfo,
      formBindingData: { createFormBindingData: payload => payload } };
    if (relative === 'services/FormSync' && request === './FormBoard') return { FormBoard: board, FormRecord: class {} };
    return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), request)));
  });
  cache.set(relative, exports);
  return exports;
}
const { Task, AppAction } = load('model/PlanerModel');
const { freshData, reduce, todayKey, realDateOf } = load('model/PlanerEngine');
const source = readFileSync(path.join(base, 'pages/Index.ets'), 'utf8');
const names = ['dispatch', 'restoreAnchor', 'applyPendingAnchor', 'nearTodayBottom', 'todayViewportHeight'];
const methods = names.map(name => source.match(new RegExp('^  private ' + name + '\\([^]*?\\n  \\}', 'm'))?.[0] || (() => { throw new Error(name); })()).join('\n');
const timers = [];
// 方法保留真实闭包依赖，用隔离上下文注入框架。
const output = ts.transpileModule(`class Harness { ${methods} }; exports.Harness=Harness;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
const sandbox = { exports: {}, AppAction, Task, reduce, todayKey, realDateOf, Motion: { spring: () => ({}), theme: () => ({}) },
  ScrollAlign: { START: 'start' }, setTimeout: fn => { timers.push(fn); return timers.length; } };
vm.runInNewContext(output, sandbox);
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++; console.log('✓ ' + message);
}
function fixture() {
  timers.length = 0;
  const page = new sandbox.exports.Harness();
  page.data = freshData();
  page.data.settings.autoScrollNextOnComplete = true;
  page.data.todayTasks = ['a', 'b', 'c', 'd'].map(id => { const task = new Task(); task.id = id; return task; });
  page.ready = true; page.page = 0; page.anchorRevision = 0; page.anchorPending = false; page.todayLastVisible = 3;
  page.todayHeight = 200; page.dragId = ''; page.dragIsGroup = false;
  page.positions = []; page.saved = 0; page.rect = { width: 300, height: 58, y: 180 };
  page.todayScroller = { getItemRect: () => page.rect,
    scrollToIndex: (...args) => page.positions.push(args) };
  page.getUIContext = () => ({ getFrameNodeById: () => ({ getMeasuredSize: () => ({ height: 675 }) }),
    px2vp: value => value / 3.375, animateTo: (_, fn) => fn() });
  page.persist = () => { page.saved++; }; page.updatePalette = () => {};
  return page;
}
function toggle(page, id) { const action = new AppAction('TOGGLE_TODAY'); action.id = id; page.dispatch(action); }
function flush() { while (timers.length) timers.shift()(); }
let page = fixture();
assert(page.todayViewportHeight() === 200, '视口像素转换为 vp，不含标题高度');
assert(!page.nearTodayBottom(), '末项在分区内但被真实列表边缘裁切时仍须定位');
page.rect.y = 142;
assert(page.nearTodayBottom(), '末项完整可见时维持末尾防跳动');
page.rect = { width: 0, height: 0, y: 0 };
assert(!page.nearTodayBottom(), '无效矩形不误判列表已到底');
page = fixture(); page.todayLastVisible = 1; page.rect.y = 0;
assert(!page.nearTodayBottom(), '末项不在可视索引中时不能拦截定位');
page = fixture(); toggle(page, 'a'); flush();
assert(page.positions.length === 1 && page.positions[0][0] === 1, '完成首项后下一项对齐列表顶部');
toggle(page, 'a'); flush(); page.positions.length = 0; toggle(page, 'a'); flush();
assert(page.positions.length === 1, '取消后重新完成，即使锚点相同也再次定位');
page = fixture(); toggle(page, 'c'); flush();
assert(page.positions.length === 0, '勾选非首个未完成项不误滚动');
page = fixture(); toggle(page, 'a'); toggle(page, 'b'); flush();
assert(page.positions.length === 1 && page.positions[0][0] === 2, '快速完成只执行最新一次定位');
page = fixture(); toggle(page, 'a'); page.page = 1; flush();
assert(page.positions.length === 0, '切到设置页后过期回调不再滚动主页');
page = fixture(); toggle(page, 'a'); page.data.settings.autoScrollNextOnComplete = false; flush();
assert(page.positions.length === 0, '关闭自动定位后作废待执行请求');
page = fixture(); toggle(page, 'a'); page.data.todayTasks[0].completed = false; flush();
assert(page.positions[0][0] === 0, '执行时重新查找目标，不沿用取消完成前的索引');
page = fixture(); page.rect.y = 142; toggle(page, 'a'); flush();
assert(page.positions.length === 0, '最后一条完整可见时不为了定位制造底部跳动');
page = fixture(); page.data.todayTasks.forEach(task => { task.completed = true; }); page.restoreAnchor(); flush();
assert(page.positions.length === 0, '全部完成不滚动');
page = fixture(); page.getUIContext = () => ({ getFrameNodeById: () => undefined });
assert(page.todayViewportHeight() === 200, '节点未挂载时回退到 List 实测高度');
page = fixture(); page.todayScroller.getItemRect = () => { throw new Error('未布局'); };
assert(!page.nearTodayBottom(), '布局未就绪不假装已到底');
page = fixture(); const contextReady = page.getUIContext;
page.getUIContext = () => ({ ...contextReady(), getFrameNodeById: () => undefined });
toggle(page, 'a'); flush();
assert(page.anchorPending && page.positions.length === 0, '定时器早于 List 挂载时保留定位请求');
page.getUIContext = contextReady; page.applyPendingAnchor();
assert(!page.anchorPending && page.positions.length === 1, '下一次布局完成后补做定位且只做一次');
const { FormSync } = load('services/FormSync');
const context = {};
const data = freshData(); data.settings.themeMode = 'light';
records = [{ formId: 'B', dimension: '2*2' }]; running = [{ formId: 'B', dimension: 2 }];
FormSync.rememberLaunch({ parameters: { [formInfo.FormParam.IDENTITY_KEY]: 'A' } });
await FormSync.sync(context, data, false);
assert(calls[0].id === 'A', '来源卡片不在枚举结果中仍优先收到刷新');
assert(calls[0].payload.size === 'large', '补齐来源卡片时按真实几何下发规格');
assert(calls[1].id === 'B', '其它卡片继续收到同一配色');
calls.length = 0; records = [{ formId: 'A', dimension: '4*4' }, { formId: 'B', dimension: '2*2' }];
running = [{ formId: 'A', dimension: 4 }, { formId: 'B', dimension: 2 }];
FormSync.rememberLaunch({ parameters: { [formInfo.FormParam.IDENTITY_KEY]: 'B' } });
await FormSync.sync(context, data, false);
assert(calls[0].id === 'B', '热启动改用本次点击的来源卡片');
calls.length = 0; blocked = gate();
data.settings.colorPreset = 'forest'; const first = FormSync.sync(context, data, false);
data.settings.colorPreset = 'sunset'; const second = FormSync.sync(context, data, true);
await new Promise(resolve => setImmediate(resolve));
assert(calls.length === 0, '前一轮推送未结束时后一轮不会抢先覆盖');
release(); await Promise.all([first, second]);
assert(calls[0].payload.preset === 'forest', '推送使用调用时的状态快照');
assert(calls.at(-1).payload.preset === 'sunset' && calls.at(-1).payload.isDark, '快速换色后每张卡片最终保持最新主题');
calls.length = 0; failId = 'B'; await FormSync.sync(context, data, false); failId = '';
assert(calls.some(call => call.id === 'A'), '来源卡片失效不阻断其它实例更新');
FormSync.rememberLaunch({}); calls.length = 0; running = []; records = [];
await FormSync.sync(context, data, false);
assert(calls.length === 0, '普通图标启动清除来源标记，不反复刷新旧卡片');
console.log(`自动定位与卡片同步：${passed} 项通过`);
